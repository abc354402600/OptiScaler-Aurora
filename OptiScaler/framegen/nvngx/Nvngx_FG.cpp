#include "pch.h"

#include <NVNGX_Parameter.h>
#include "Nvngx_FG.h"
#include <framegen/ProviderHandleCreation.h>

#include "proxies/NVNGX_Proxy.h"
#include "proxies/Ntdll_Proxy.h"

#include "IFGNvngx.h"
#include "Nvngx_Nukems.h"
#include "Nvngx_Arturs.h"
#include "Nvngx_FFX.h"
#include "Nvngx_Combo.h"
#include <imgui/ImGuiNotify.hpp>

std::unique_ptr<IFGNvngx> Nvngx_FG::createProvider()
{
    std::unique_ptr<IFGNvngx> provider;

    const auto selectedProvider = State::Instance().activeFgNvngx.load();

    switch (selectedProvider)
    {
    case FGNvngxReplacement::FFX:
        provider = std::make_unique<Nvngx_FFX>();
        break;

    case FGNvngxReplacement::Nukems:
        provider = std::make_unique<Nvngx_Nukems>();
        break;

    case FGNvngxReplacement::Arturs:
        provider = std::make_unique<Nvngx_Arturs>();
        break;

    case FGNvngxReplacement::Combo:
        provider = std::make_unique<Nvngx_Combo>();
        break;

    case FGNvngxReplacement::None:
    default:
        return nullptr;
    }

    if (!provider->isDx12Available() && !provider->isVulkanAvailable())
    {
        // The selected provider cannot be used, try the remaining providers as fallback, try in order
        // FGNvngxReplacement::Combo doesn't make sense to try as it's Arturs + FFX
        const FGNvngxReplacement fallbacks[] = {
            FGNvngxReplacement::Arturs,
            FGNvngxReplacement::FFX,
            FGNvngxReplacement::Nukems,
        };

        auto formatProvider = [](FGNvngxReplacement provider)
        {
            switch (provider)
            {
            case FGNvngxReplacement::Arturs:
                return "Enabler";
            case FGNvngxReplacement::FFX:
                return "Nvngx FFX";
            case FGNvngxReplacement::Nukems:
                return "Nukems";
            case FGNvngxReplacement::Combo:
                return "Combo";
            case FGNvngxReplacement::None:
            default:
                return "???";
            }
        };

        for (const auto fallback : fallbacks)
        {
            if (fallback == selectedProvider)
                continue;

            std::unique_ptr<IFGNvngx> candidate;

            switch (fallback)
            {
            case FGNvngxReplacement::Arturs:
                candidate = std::make_unique<Nvngx_Arturs>();
                break;

            case FGNvngxReplacement::FFX:
                candidate = std::make_unique<Nvngx_FFX>();
                break;

            case FGNvngxReplacement::Nukems:
                candidate = std::make_unique<Nvngx_Nukems>();
                break;

            case FGNvngxReplacement::None:
            default:
                continue;
            }

            if (!candidate->isDx12Available() && !candidate->isVulkanAvailable())
                continue;

            provider = std::move(candidate);

            Config::Instance()->FGNvngxReplacement.set_volatile_value(fallback);
            State::Instance().activeFgNvngx = fallback;

            LOG_WARN("Nvngx FG provider {} is not available, falling back to {}", formatProvider(selectedProvider),
                     formatProvider(fallback));

            ImGui::InsertNotification({ ImGuiToastType::Warning, 20000,
                                        std::format("{} is not available.\nFalling back to {}.",
                                                    formatProvider(selectedProvider), formatProvider(fallback))
                                            .c_str() });

            return provider;
        }

        LOG_ERROR("Nvngx FG provider {} is not available and can't fallback", formatProvider(selectedProvider));
        ImGui::InsertNotification(
            { ImGuiToastType::Error, 20000,
              std::format("{} is not available and can't fallback", formatProvider(selectedProvider)).c_str() });

        Config::Instance()->FGNvngxReplacement.set_volatile_value(FGNvngxReplacement::None);
        State::Instance().activeFgNvngx = FGNvngxReplacement::None;

        provider.reset();
        return nullptr;
    }

    return provider;
}

ProviderLookup<IFGNvngx> Nvngx_FG::lookupProvider()
{
    return _provider.GetOrCreate([] { return createProvider(); });
}

IFGNvngx* Nvngx_FG::getProvider() { return lookupProvider().provider; }

ProviderStatus Nvngx_FG::D3D12_ProviderStatus()
{
    return lookupProvider().ForApi([](IFGNvngx& provider) { return provider.isDx12Available(); });
}

ProviderStatus Nvngx_FG::VULKAN_ProviderStatus()
{
    return lookupProvider().ForApi([](IFGNvngx& provider) { return provider.isVulkanAvailable(); });
}

int Nvngx_FG::getMaxFakeFramesCount()
{
    auto* provider = getProvider();

    if (!provider)
        return false;

    return provider->getMaxFakeFramesCount();
}

bool Nvngx_FG::isDx12Available()
{
    auto* provider = getProvider();

    if (!provider)
        return false;

    return provider->isDx12Available();
}

bool Nvngx_FG::isVulkanAvailable()
{
    auto* provider = getProvider();

    if (!provider)
        return false;

    return provider->isVulkanAvailable();
}

feature_version Nvngx_FG::version()
{
    auto* provider = getProvider();

    if (!provider)
        return {};

    return provider->version();
}

feature_version Nvngx_FG::extraVersion()
{
    auto* provider = getProvider();

    if (!provider)
        return {};

    return provider->extraVersion();
}

bool Nvngx_FG::setDebugView(bool enabled)
{
    auto lease = _calls.TryTransition();
    if (!lease || (_dx12InitAttempts.empty() && _vulkanInitAttempts.empty()))
        return false;

    // UI callbacks must neither construct a provider nor race Evaluate/Shutdown.
    auto* provider = _provider.Peek();

    if (!provider)
        return false;

    if (provider->getType() == FGNvngxReplacement::Nukems)
    {
        auto* nukemsProvider = static_cast<Nvngx_Nukems*>(provider);
        return nukemsProvider->setDebugView(enabled);
    }
    return false;
}

bool Nvngx_FG::setInterpolatedOnly(bool enabled)
{
    auto lease = _calls.TryTransition();
    if (!lease || (_dx12InitAttempts.empty() && _vulkanInitAttempts.empty()))
        return false;

    auto* provider = _provider.Peek();

    if (!provider)
        return false;

    if (provider->getType() == FGNvngxReplacement::Nukems)
    {
        auto* nukemsProvider = static_cast<Nvngx_Nukems*>(provider);
        return nukemsProvider->setInterpolatedOnly(enabled);
    }
    return false;
}

NVSDK_NGX_Result Nvngx_FG::D3D12_Init(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                      ID3D12Device* InDevice, const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                      NVSDK_NGX_Version InSDKVersion)
{
    auto lease = _calls.TryTransition();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    if (!InDevice)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    const auto lookup = lookupProvider();
    if (lookup.status == ProviderStatus::Pending)
        return NVSDK_NGX_Result_FAIL_NotInitialized;
    auto* provider = lookup.provider;

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    _dx12InitAttempts.insert(InDevice);
    return provider->D3D12_Init(InApplicationId, InApplicationDataPath, InDevice, InFeatureInfo, InSDKVersion);
}

NVSDK_NGX_Result Nvngx_FG::D3D12_Init_Ext(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                          ID3D12Device* InDevice, NVSDK_NGX_Version InSDKVersion,
                                          const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo)
{
    auto lease = _calls.TryTransition();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    if (!InDevice)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    const auto lookup = lookupProvider();
    if (lookup.status == ProviderStatus::Pending)
        return NVSDK_NGX_Result_FAIL_NotInitialized;
    auto* provider = lookup.provider;

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    _dx12InitAttempts.insert(InDevice);
    return provider->D3D12_Init_Ext(InApplicationId, InApplicationDataPath, InDevice, InSDKVersion, InFeatureInfo);
}

NVSDK_NGX_Result Nvngx_FG::DrainHandles(HandleApi api, const void* device)
{
    // The caller holds exclusive transition admission. Snapshot before any
    // teardown, and never infer a legacy Vulkan command buffer's device from
    // mutable process-wide state.
    const auto keys =
        _handles.LiveKeys([&](const Nvngx_FG_Handle& handle)
                          { return handle.api == api && (!device || !handle.device || handle.device == device); });
    if (device)
        for (const auto* key : keys)
            if (_handles.GetIdentity(key, [](const Nvngx_FG_Handle& handle) { return handle.device; }) == nullptr)
                return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = _provider.Peek();
    if (!provider)
        return keys.empty() ? NVSDK_NGX_Result_Success : NVSDK_NGX_Result_FAIL_NotInitialized;
    // DLL_PROCESS_DETACH may hold the loader lock. Do not start GPU/provider
    // destruction there; retain ownership rather than claiming a clean drain.
    if (State::Instance().isShuttingDown)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    // Failed Combo creation can own children without any public token. Drain
    // those before native shutdown even when the registry is empty.
    if (api == HandleApi::D3D12)
    {
        const auto result = provider->D3D12_DrainPending(static_cast<ID3D12Device*>(const_cast<void*>(device)));
        if (result != NVSDK_NGX_Result_Success)
            return result;
    }

    for (const auto* key : keys)
        _handles.SuspendReads(key);

    for (const auto* key : keys)
    {
        const auto result = _handles.Release(
            key, NVSDK_NGX_Result_FAIL_FeatureNotFound, NVSDK_NGX_Result_FAIL_NotInitialized,
            [&](const Nvngx_FG_Handle& handle)
            {
                return api == HandleApi::D3D12 ? provider->D3D12_ReleaseFeature(handle.nativeHandle)
                                               : provider->VULKAN_ReleaseFeature(handle.nativeHandle);
            },
            [](NVSDK_NGX_Result result) { return result == NVSDK_NGX_Result_Success; });
        if (result != NVSDK_NGX_Result_Success)
            return result;
    }
    return NVSDK_NGX_Result_Success;
}

NVSDK_NGX_Result Nvngx_FG::D3D12_Shutdown()
{
    return WithDx12Shutdown([&](auto closeProvider) { return closeProvider(nullptr); });
}

NVSDK_NGX_Result Nvngx_FG::D3D12_Shutdown1(ID3D12Device* InDevice)
{
    return WithDx12Shutdown([&](auto closeProvider) { return closeProvider(InDevice); }, InDevice);
}

NVSDK_NGX_Result Nvngx_FG::D3D12_GetScratchBufferSize(NVSDK_NGX_Feature InFeatureId,
                                                      const NVSDK_NGX_Parameter* InParameters, size_t* OutSizeInBytes)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    return provider->D3D12_GetScratchBufferSize(InFeatureId, InParameters, OutSizeInBytes);
}

NVSDK_NGX_Result Nvngx_FG::D3D12_CreateFeature(ID3D12GraphicsCommandList* InCmdList, NVSDK_NGX_Feature InFeatureID,
                                               NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle)
{
    if (!OutHandle)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;
    *OutHandle = nullptr;

    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    Microsoft::WRL::ComPtr<ID3D12Device> device;
    if (!InCmdList || FAILED(InCmdList->GetDevice(IID_PPV_ARGS(&device))) || !device)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    return CreateProviderHandle(
        _handles, OutHandle,
        Nvngx_FG_Handle { lastIdCreated++ + NVNGX_PROVIDER_ID_OFFSET, nullptr, HandleApi::D3D12, device.Get() },
        NVSDK_NGX_Result_Success, NVSDK_NGX_Result_FAIL_InvalidParameter, NVSDK_NGX_Result_Fail,
        [&](Nvngx_FG_Handle& handle)
        {
            auto* provider = getProvider();
            if (!provider)
                return NVSDK_NGX_Result_Fail;
            return provider->D3D12_CreateFeature(InCmdList, InFeatureID, InParameters, &handle.nativeHandle);
        });
}

NVSDK_NGX_Result Nvngx_FG::D3D12_ReleaseFeature(NVSDK_NGX_Handle* InHandle)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    if (!InHandle)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    return _handles.Release(
        InHandle, NVSDK_NGX_Result_FAIL_FeatureNotFound, NVSDK_NGX_Result_FAIL_NotInitialized,
        [&](const Nvngx_FG_Handle& handle) -> NVSDK_NGX_Result
        {
            if (handle.api != HandleApi::D3D12)
                return NVSDK_NGX_Result_FAIL_FeatureNotFound;
            return provider->D3D12_ReleaseFeature(handle.nativeHandle);
        },
        [](NVSDK_NGX_Result result) { return result == NVSDK_NGX_Result_Success; });
}

NVSDK_NGX_Result Nvngx_FG::D3D12_GetFeatureRequirements(IDXGIAdapter* Adapter,
                                                        const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
                                                        NVSDK_NGX_FeatureRequirement* OutSupported)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    return provider->D3D12_GetFeatureRequirements(Adapter, FeatureDiscoveryInfo, OutSupported);
}

NVSDK_NGX_Result Nvngx_FG::D3D12_EvaluateFeature(ID3D12GraphicsCommandList* InCmdList,
                                                 const NVSDK_NGX_Handle* InFeatureHandle,
                                                 NVSDK_NGX_Parameter* InParameters,
                                                 PFN_NVSDK_NGX_ProgressCallback InCallback)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    if (!InFeatureHandle)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    return _handles.Read(
        InFeatureHandle, NVSDK_NGX_Result_FAIL_FeatureNotFound, NVSDK_NGX_Result_FAIL_NotInitialized,
        [&](const Nvngx_FG_Handle& handle) -> NVSDK_NGX_Result
        {
            if (handle.api != HandleApi::D3D12)
                return NVSDK_NGX_Result_FAIL_FeatureNotFound;

            bool applyHudCutoff = Config::Instance()->FGHudCutoff.value_or_default() > 0.0f ||
                                  State::Instance().gameQuirks & GameQuirk::FSRFGHudlessMismatchFixup;

            uint32_t frameIndex = 1;
            InParameters->Get("DLSSG.MultiFrameIndex", &frameIndex);

            if (applyHudCutoff && frameIndex == 1)
            {
                ID3D12Resource* presentWithHud = nullptr;
                InParameters->Get("DLSSG.Backbuffer", &presentWithHud);
                auto presentWithHudState = D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE;

                ID3D12Resource* hudlessResource = nullptr;
                InParameters->Get("DLSSG.HUDLess", &hudlessResource);
                auto hudlessState = D3D12_RESOURCE_STATE_COPY_DEST;

                auto device = State::Instance().currentD3D12Device;

                if (presentWithHud && hudlessResource && device)
                {
                    if (_hudCopy.get() == nullptr)
                        _hudCopy = std::make_unique<HudCopy_Dx12>("HudCopy", device);

                    if (auto hudCopy = _hudCopy.get(); hudCopy && hudCopy->IsInit())
                    {
                        // In Cyberprank - DLSSG has noise issues, FSR FG has noise + vignetting
                        // In Death Stranding 2 - DLSSG has wrong colormapping it seems, FSR FG is fine
                        const bool isCyberpunk = State::Instance().gameQuirks[GameQuirk::CyberpunkHudlessState];
                        float hudDetectionThreshold = 0.03f;

                        if (isCyberpunk && State::Instance().activeFgInput != FGInput::FSRFG)
                            hudDetectionThreshold = 0.01f;

                        if (Config::Instance()->FGHudCutoff.value_or_default() > 0.0f)
                            hudDetectionThreshold = Config::Instance()->FGHudCutoff.value_or_default() / 10.0f;

                        hudCopy->Dispatch(InCmdList, hudlessResource, presentWithHud, hudlessState, presentWithHudState,
                                          hudDetectionThreshold);
                    }
                }
                else
                {
                    LOG_WARN("Couldn't run hudless fixup");
                }
            }

            if (Config::Instance()->NvngxFGDisableHudless.value_or_default())
                InParameters->Set("DLSSG.HUDLess", (void*) nullptr);

            // LOG_TRACE("Handle received from the game: {:X}", (uint64_t) InFeatureHandle);

            return provider->D3D12_EvaluateFeature(InCmdList, handle.nativeHandle, InParameters, InCallback);
        });
}

NVSDK_NGX_Result Nvngx_FG::D3D12_PopulateParameters_Impl(NVSDK_NGX_Parameter* InParameters)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    return provider->D3D12_PopulateParameters_Impl(InParameters);
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_Init(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                       VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                       PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA,
                                       const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo, NVSDK_NGX_Version InSDKVersion)
{
    auto lease = _calls.TryTransition();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    if (!InDevice)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    const auto lookup = lookupProvider();
    if (lookup.status == ProviderStatus::Pending)
        return NVSDK_NGX_Result_FAIL_NotInitialized;
    auto* provider = lookup.provider;

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    _vulkanInitAttempts.insert(InDevice);
    return provider->VULKAN_Init(InApplicationId, InApplicationDataPath, InInstance, InPD, InDevice, InGIPA, InGDPA,
                                 InFeatureInfo, InSDKVersion);
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_Init_Ext(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                           VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                           NVSDK_NGX_Version InSDKVersion,
                                           const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo)
{
    auto lease = _calls.TryTransition();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    if (!InDevice)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    const auto lookup = lookupProvider();
    if (lookup.status == ProviderStatus::Pending)
        return NVSDK_NGX_Result_FAIL_NotInitialized;
    auto* provider = lookup.provider;

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    _vulkanInitAttempts.insert(InDevice);
    return provider->VULKAN_Init_Ext(InApplicationId, InApplicationDataPath, InInstance, InPD, InDevice, InSDKVersion,
                                     InFeatureInfo);
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_Init_Ext2(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                            VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                            PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA,
                                            NVSDK_NGX_Version InSDKVersion,
                                            const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo)
{
    auto lease = _calls.TryTransition();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    if (!InDevice)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    const auto lookup = lookupProvider();
    if (lookup.status == ProviderStatus::Pending)
        return NVSDK_NGX_Result_FAIL_NotInitialized;
    auto* provider = lookup.provider;

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    _vulkanInitAttempts.insert(InDevice);
    return provider->VULKAN_Init_Ext2(InApplicationId, InApplicationDataPath, InInstance, InPD, InDevice, InGIPA,
                                      InGDPA, InSDKVersion, InFeatureInfo);
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_Shutdown()
{
    return WithVulkanShutdown([&](auto closeProvider) { return closeProvider(nullptr); });
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_Shutdown1(VkDevice InDevice)
{
    return WithVulkanShutdown([&](auto closeProvider) { return closeProvider(InDevice); }, InDevice);
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_GetScratchBufferSize(NVSDK_NGX_Feature InFeatureId,
                                                       const NVSDK_NGX_Parameter* InParameters, size_t* OutSizeInBytes)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    return provider->VULKAN_GetScratchBufferSize(InFeatureId, InParameters, OutSizeInBytes);
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_CreateFeature(VkCommandBuffer InCmdBuffer, NVSDK_NGX_Feature InFeatureID,
                                                NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle)
{
    if (!OutHandle)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;
    *OutHandle = nullptr;

    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    return CreateProviderHandle(
        _handles, OutHandle, Nvngx_FG_Handle { lastIdCreated++ + NVNGX_PROVIDER_ID_OFFSET, nullptr, HandleApi::Vulkan },
        NVSDK_NGX_Result_Success, NVSDK_NGX_Result_FAIL_InvalidParameter, NVSDK_NGX_Result_Fail,
        [&](Nvngx_FG_Handle& handle)
        {
            auto* provider = getProvider();
            if (!provider)
                return NVSDK_NGX_Result_Fail;
            return provider->VULKAN_CreateFeature(InCmdBuffer, InFeatureID, InParameters, &handle.nativeHandle);
        });
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_CreateFeature1(VkDevice InDevice, VkCommandBuffer InCmdList,
                                                 NVSDK_NGX_Feature InFeatureID, NVSDK_NGX_Parameter* InParameters,
                                                 NVSDK_NGX_Handle** OutHandle)
{
    if (!OutHandle)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;
    *OutHandle = nullptr;

    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    if (!InDevice)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    return CreateProviderHandle(
        _handles, OutHandle,
        Nvngx_FG_Handle { lastIdCreated++ + NVNGX_PROVIDER_ID_OFFSET, nullptr, HandleApi::Vulkan, InDevice },
        NVSDK_NGX_Result_Success, NVSDK_NGX_Result_FAIL_InvalidParameter, NVSDK_NGX_Result_Fail,
        [&](Nvngx_FG_Handle& handle)
        {
            auto* provider = getProvider();
            if (!provider)
                return NVSDK_NGX_Result_Fail;
            return provider->VULKAN_CreateFeature1(InDevice, InCmdList, InFeatureID, InParameters,
                                                   &handle.nativeHandle);
        });
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_ReleaseFeature(NVSDK_NGX_Handle* InHandle)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    if (!InHandle)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    return _handles.Release(
        InHandle, NVSDK_NGX_Result_FAIL_FeatureNotFound, NVSDK_NGX_Result_FAIL_NotInitialized,
        [&](const Nvngx_FG_Handle& handle) -> NVSDK_NGX_Result
        {
            if (handle.api != HandleApi::Vulkan)
                return NVSDK_NGX_Result_FAIL_FeatureNotFound;
            return provider->VULKAN_ReleaseFeature(handle.nativeHandle);
        },
        [](NVSDK_NGX_Result result) { return result == NVSDK_NGX_Result_Success; });
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_GetFeatureRequirements(const VkInstance Instance,
                                                         const VkPhysicalDevice PhysicalDevice,
                                                         const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
                                                         NVSDK_NGX_FeatureRequirement* OutSupported)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    return provider->VULKAN_GetFeatureRequirements(Instance, PhysicalDevice, FeatureDiscoveryInfo, OutSupported);
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_EvaluateFeature(VkCommandBuffer InCmdList, const NVSDK_NGX_Handle* InFeatureHandle,
                                                  NVSDK_NGX_Parameter* InParameters,
                                                  PFN_NVSDK_NGX_ProgressCallback InCallback)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    if (!InFeatureHandle)
        return NVSDK_NGX_Result_FAIL_InvalidParameter;

    return _handles.Read(InFeatureHandle, NVSDK_NGX_Result_FAIL_FeatureNotFound, NVSDK_NGX_Result_FAIL_NotInitialized,
                         [&](const Nvngx_FG_Handle& handle) -> NVSDK_NGX_Result
                         {
                             if (handle.api != HandleApi::Vulkan)
                                 return NVSDK_NGX_Result_FAIL_FeatureNotFound;

                             // LOG_TRACE("Handle received from the game: {:X}", (uint64_t) InFeatureHandle);

                             return provider->VULKAN_EvaluateFeature(InCmdList, handle.nativeHandle, InParameters,
                                                                     InCallback);
                         });
}

NVSDK_NGX_Result Nvngx_FG::VULKAN_PopulateParameters_Impl(NVSDK_NGX_Parameter* InParameters)
{
    auto lease = _calls.TryOperation();
    if (!lease)
        return NVSDK_NGX_Result_FAIL_NotInitialized;

    auto* provider = getProvider();

    if (!provider)
        return NVSDK_NGX_Result_Fail;

    return provider->VULKAN_PopulateParameters_Impl(InParameters);
}
