#pragma once

#include <NVNGX_Parameter.h>

#include "proxies/NVNGX_Proxy.h"
#include "proxies/Ntdll_Proxy.h"
#include <shaders/hud_copy/HudCopy_Dx12.h>
#include "IFGNvngx.h"
#include <framegen/ProviderHandleRegistry.h>
#include <framegen/ProviderPublication.h>
#include <framegen/ProviderCallAdmission.h>
#include <unordered_set>

class Nvngx_FG
{
  private:
    // The public handle remains the address returned by CreateFeature. Registry
    // ownership protects Evaluate/Release callers without dereferencing stale IDs.
    struct Nvngx_FG_Handle
    {
        unsigned int id;
        NVSDK_NGX_Handle* nativeHandle = nullptr;
    };

    static inline std::atomic_uint32_t lastIdCreated = 0;
    static inline ProviderHandleRegistry<Nvngx_FG_Handle> _handles;
    static inline ProviderPublication<IFGNvngx> _provider;
    static inline ProviderCallAdmission _calls;
    // Accessed only with transition admission. An attempted Init may have
    // partially initialized a provider even when it reports failure.
    static inline std::unordered_set<ID3D12Device*> _dx12InitAttempts;
    static inline std::unordered_set<VkDevice> _vulkanInitAttempts;
    static inline std::unique_ptr<HudCopy_Dx12> _hudCopy;

    static std::unique_ptr<IFGNvngx> createProvider();
    static ProviderLookup<IFGNvngx> lookupProvider();
    static IFGNvngx* getProvider();

  public:
    // The exported API holds this admission through native shutdown, provider
    // shutdown and local cleanup. A rejected transition changes none of them.
    template <typename Callback> static NVSDK_NGX_Result WithDx12Shutdown(Callback&& callback)
    {
        auto lease = _calls.TryTransition();
        if (!lease)
            return NVSDK_NGX_Result_FAIL_NotInitialized;
        return std::forward<Callback>(callback)(
            [](ID3D12Device* device)
            {
                if (device ? !_dx12InitAttempts.contains(device) : _dx12InitAttempts.empty())
                    return NVSDK_NGX_Result_Success;
                auto* provider = _provider.Peek();
                const auto result = !provider || !provider->isDx12Available() ? NVSDK_NGX_Result_Success
                                    : device                                  ? provider->D3D12_Shutdown1(device)
                                                                              : provider->D3D12_Shutdown();
                if (result == NVSDK_NGX_Result_Success)
                {
                    if (device)
                        _dx12InitAttempts.erase(device);
                    else
                        _dx12InitAttempts.clear();
                }
                return result;
            });
    }

    template <typename Callback> static NVSDK_NGX_Result WithVulkanShutdown(Callback&& callback)
    {
        auto lease = _calls.TryTransition();
        if (!lease)
            return NVSDK_NGX_Result_FAIL_NotInitialized;
        return std::forward<Callback>(callback)(
            [](VkDevice device)
            {
                if (device ? !_vulkanInitAttempts.contains(device) : _vulkanInitAttempts.empty())
                    return NVSDK_NGX_Result_Success;
                auto* provider = _provider.Peek();
                const auto result = !provider || !provider->isVulkanAvailable() ? NVSDK_NGX_Result_Success
                                    : device                                    ? provider->VULKAN_Shutdown1(device)
                                                                                : provider->VULKAN_Shutdown();
                if (result == NVSDK_NGX_Result_Success)
                {
                    if (device)
                        _vulkanInitAttempts.erase(device);
                    else
                        _vulkanInitAttempts.clear();
                }
                return result;
            });
    }

    static std::optional<unsigned int> GetHandleId(const NVSDK_NGX_Handle* handle)
    {
        return _handles.GetIdentity(handle, [](const Nvngx_FG_Handle& value) { return value.id; });
    }

    static int getMaxFakeFramesCount();
    static ProviderStatus D3D12_ProviderStatus();
    static ProviderStatus VULKAN_ProviderStatus();
    static bool isDx12Available();
    static bool isVulkanAvailable();
    static feature_version version();
    static feature_version extraVersion();

    // TODO: nukem-specific, unify
    static void setDebugView(bool enabled);
    static void setInterpolatedOnly(bool enabled);

    static NVSDK_NGX_Result D3D12_Init(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                       ID3D12Device* InDevice, const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                       NVSDK_NGX_Version InSDKVersion);

    static NVSDK_NGX_Result D3D12_Init_Ext(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                           ID3D12Device* InDevice, NVSDK_NGX_Version InSDKVersion,
                                           const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);

    static NVSDK_NGX_Result D3D12_Shutdown();

    static NVSDK_NGX_Result D3D12_Shutdown1(ID3D12Device* InDevice);

    static NVSDK_NGX_Result D3D12_GetScratchBufferSize(NVSDK_NGX_Feature InFeatureId,
                                                       const NVSDK_NGX_Parameter* InParameters, size_t* OutSizeInBytes);

    static NVSDK_NGX_Result D3D12_CreateFeature(ID3D12GraphicsCommandList* InCmdList, NVSDK_NGX_Feature InFeatureID,
                                                NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle);

    static NVSDK_NGX_Result D3D12_ReleaseFeature(NVSDK_NGX_Handle* InHandle);

    static NVSDK_NGX_Result D3D12_GetFeatureRequirements(IDXGIAdapter* Adapter,
                                                         const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
                                                         NVSDK_NGX_FeatureRequirement* OutSupported);

    static NVSDK_NGX_Result D3D12_EvaluateFeature(ID3D12GraphicsCommandList* InCmdList,
                                                  const NVSDK_NGX_Handle* InFeatureHandle,
                                                  NVSDK_NGX_Parameter* InParameters,
                                                  PFN_NVSDK_NGX_ProgressCallback InCallback);

    static NVSDK_NGX_Result D3D12_PopulateParameters_Impl(NVSDK_NGX_Parameter* InParameters);

    // Vulkan
    static NVSDK_NGX_Result VULKAN_Init(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                        VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                        PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA,
                                        const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                        NVSDK_NGX_Version InSDKVersion);

    static NVSDK_NGX_Result VULKAN_Init_Ext(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                            VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                            NVSDK_NGX_Version InSDKVersion,
                                            const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);

    static NVSDK_NGX_Result VULKAN_Init_Ext2(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                             VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                             PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA,
                                             NVSDK_NGX_Version InSDKVersion,
                                             const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);

    static NVSDK_NGX_Result VULKAN_Shutdown();

    static NVSDK_NGX_Result VULKAN_Shutdown1(VkDevice InDevice);

    static NVSDK_NGX_Result VULKAN_GetScratchBufferSize(NVSDK_NGX_Feature InFeatureId,
                                                        const NVSDK_NGX_Parameter* InParameters,
                                                        size_t* OutSizeInBytes);

    static NVSDK_NGX_Result VULKAN_CreateFeature(VkCommandBuffer InCmdBuffer, NVSDK_NGX_Feature InFeatureID,
                                                 NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle);

    static NVSDK_NGX_Result VULKAN_CreateFeature1(VkDevice InDevice, VkCommandBuffer InCmdList,
                                                  NVSDK_NGX_Feature InFeatureID, NVSDK_NGX_Parameter* InParameters,
                                                  NVSDK_NGX_Handle** OutHandle);

    static NVSDK_NGX_Result VULKAN_ReleaseFeature(NVSDK_NGX_Handle* InHandle);

    static NVSDK_NGX_Result VULKAN_GetFeatureRequirements(const VkInstance Instance,
                                                          const VkPhysicalDevice PhysicalDevice,
                                                          const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
                                                          NVSDK_NGX_FeatureRequirement* OutSupported);

    static NVSDK_NGX_Result VULKAN_EvaluateFeature(VkCommandBuffer InCmdList, const NVSDK_NGX_Handle* InFeatureHandle,
                                                   NVSDK_NGX_Parameter* InParameters,
                                                   PFN_NVSDK_NGX_ProgressCallback InCallback);

    static NVSDK_NGX_Result VULKAN_PopulateParameters_Impl(NVSDK_NGX_Parameter* InParameters);
};
