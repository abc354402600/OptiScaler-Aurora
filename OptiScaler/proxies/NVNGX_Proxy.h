#pragma once

#include "SysUtils.h"
#include "Util.h"
#include "Config.h"
#include "Logger.h"

#include <proxies/Ntdll_Proxy.h>
#include <proxies/KernelBase_Proxy.h>

#include "nvapi/NvApiHooks.h"

#include "detours/detours.h"

#include <filesystem>
#include <proxies/NativeDeviceLifecycle.h>
#include <proxies/NgxPathSnapshot.h>
#include <framegen/ProviderPublication.h>
#include <vulkan/vulkan.hpp>

inline const char* project_id_override = "24480451-f00d-face-1304-0308dabad187";
constexpr unsigned long long app_id_override = 0x24480451;

#pragma region spoofing hooks for 16xx

typedef NVSDK_NGX_Result (*PFN_NVSDK_NGX_D3D1X_GetFeatureRequirements)(
    IDXGIAdapter* Adapter, const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
    NVSDK_NGX_FeatureRequirement* OutSupported);
typedef NVSDK_NGX_Result (*PFN_NVSDK_NGX_VULKAN_GetFeatureRequirements)(
    const VkInstance Instance, const VkPhysicalDevice PhysicalDevice,
    const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo, NVSDK_NGX_FeatureRequirement* OutSupported);

inline static PFN_NVSDK_NGX_D3D1X_GetFeatureRequirements Original_D3D11_GetFeatureRequirements = nullptr;
inline static PFN_NVSDK_NGX_D3D1X_GetFeatureRequirements Original_D3D12_GetFeatureRequirements = nullptr;
inline static PFN_NVSDK_NGX_VULKAN_GetFeatureRequirements Original_Vulkan_GetFeatureRequirements = nullptr;

inline static NVSDK_NGX_Result __stdcall Hooked_Dx12_GetFeatureRequirements(
    IDXGIAdapter* Adapter, const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
    NVSDK_NGX_FeatureRequirement* OutSupported)
{
    LOG_FUNC();

    auto result = Original_D3D12_GetFeatureRequirements(Adapter, FeatureDiscoveryInfo, OutSupported);

    if (result == NVSDK_NGX_Result_Success && FeatureDiscoveryInfo->FeatureID == NVSDK_NGX_Feature_SuperSampling)
    {
        LOG_INFO("Spoofing support!");
        OutSupported->FeatureSupported = NVSDK_NGX_FeatureSupportResult_Supported;
        OutSupported->MinHWArchitecture = 0;
        strcpy_s(OutSupported->MinOSVersion, "10.0.10240.16384");
    }

    return result;
}

inline static NVSDK_NGX_Result __stdcall Hooked_Dx11_GetFeatureRequirements(
    IDXGIAdapter* Adapter, const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
    NVSDK_NGX_FeatureRequirement* OutSupported)
{
    LOG_FUNC();

    auto result = Original_D3D11_GetFeatureRequirements(Adapter, FeatureDiscoveryInfo, OutSupported);

    if (result == NVSDK_NGX_Result_Success && FeatureDiscoveryInfo->FeatureID == NVSDK_NGX_Feature_SuperSampling)
    {
        LOG_INFO("Spoofing support!");
        OutSupported->FeatureSupported = NVSDK_NGX_FeatureSupportResult_Supported;
        OutSupported->MinHWArchitecture = 0;
        strcpy_s(OutSupported->MinOSVersion, "10.0.10240.16384");
    }

    return result;
}

inline static NVSDK_NGX_Result __stdcall Hooked_Vulkan_GetFeatureRequirements(
    const VkInstance Instance, const VkPhysicalDevice PhysicalDevice,
    const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo, NVSDK_NGX_FeatureRequirement* OutSupported)
{
    LOG_FUNC();

    auto result = Original_Vulkan_GetFeatureRequirements(Instance, PhysicalDevice, FeatureDiscoveryInfo, OutSupported);

    if (result == NVSDK_NGX_Result_Success && FeatureDiscoveryInfo->FeatureID == NVSDK_NGX_Feature_SuperSampling)
    {
        LOG_INFO("Spoofing support!");
        OutSupported->FeatureSupported = NVSDK_NGX_FeatureSupportResult_Supported;
        OutSupported->MinHWArchitecture = 0;
        strcpy_s(OutSupported->MinOSVersion, "10.0.10240.16384");
    }

    return result;
}

inline static void HookNgxApi(HMODULE nvngx)
{
    if (Original_D3D11_GetFeatureRequirements != nullptr || Original_D3D12_GetFeatureRequirements != nullptr)
        return;

    LOG_DEBUG("Trying to hook NgxApi");

    Original_D3D11_GetFeatureRequirements =
        (PFN_NVSDK_NGX_D3D1X_GetFeatureRequirements) KernelBaseProxy::GetProcAddress_()(
            nvngx, "NVSDK_NGX_D3D11_GetFeatureRequirements");
    Original_D3D12_GetFeatureRequirements =
        (PFN_NVSDK_NGX_D3D1X_GetFeatureRequirements) KernelBaseProxy::GetProcAddress_()(
            nvngx, "NVSDK_NGX_D3D12_GetFeatureRequirements");
    Original_Vulkan_GetFeatureRequirements =
        (PFN_NVSDK_NGX_VULKAN_GetFeatureRequirements) KernelBaseProxy::GetProcAddress_()(
            nvngx, "NVSDK_NGX_VULKAN_GetFeatureRequirements");

    if (Original_D3D11_GetFeatureRequirements != nullptr || Original_D3D12_GetFeatureRequirements != nullptr ||
        Original_Vulkan_GetFeatureRequirements != nullptr)
    {
        LOG_INFO("NVSDK_NGX_XXXXXX_GetFeatureRequirements found, hooking!");

        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());

        if (Original_D3D11_GetFeatureRequirements != nullptr)
            DetourAttach(&(PVOID&) Original_D3D11_GetFeatureRequirements, Hooked_Dx11_GetFeatureRequirements);

        if (Original_D3D12_GetFeatureRequirements != nullptr)
            DetourAttach(&(PVOID&) Original_D3D12_GetFeatureRequirements, Hooked_Dx12_GetFeatureRequirements);

        if (Original_Vulkan_GetFeatureRequirements != nullptr)
            DetourAttach(&(PVOID&) Original_Vulkan_GetFeatureRequirements, Hooked_Vulkan_GetFeatureRequirements);

        auto detourResult = DetourTransactionCommit();
        if (detourResult != NO_ERROR)
        {
            LOG_ERROR("Failed to hook NVSDK_NGX_XXXXXX_GetFeatureRequirements: {:X}", detourResult);
            Original_D3D11_GetFeatureRequirements = nullptr;
            Original_D3D12_GetFeatureRequirements = nullptr;
            Original_Vulkan_GetFeatureRequirements = nullptr;
        }
    }
}

inline static void UnhookApis()
{
    NvApiHooks::Unhook();

    if (Original_D3D11_GetFeatureRequirements != nullptr || Original_D3D12_GetFeatureRequirements != nullptr)
    {
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());

        if (Original_D3D11_GetFeatureRequirements != nullptr)
            DetourDetach(&(PVOID&) Original_D3D11_GetFeatureRequirements, Hooked_Dx11_GetFeatureRequirements);

        if (Original_D3D12_GetFeatureRequirements != nullptr)
            DetourDetach(&(PVOID&) Original_D3D12_GetFeatureRequirements, Hooked_Dx12_GetFeatureRequirements);

        if (Original_Vulkan_GetFeatureRequirements != nullptr)
            DetourDetach(&(PVOID&) Original_Vulkan_GetFeatureRequirements, Hooked_Vulkan_GetFeatureRequirements);

        auto detourResult = DetourTransactionCommit();
        if (detourResult != NO_ERROR)
        {
            LOG_ERROR("Failed to unhook NVSDK_NGX_XXXXXX_GetFeatureRequirements: {:X}", detourResult);
        }
        else
        {
            Original_D3D11_GetFeatureRequirements = nullptr;
            Original_D3D12_GetFeatureRequirements = nullptr;
            Original_Vulkan_GetFeatureRequirements = nullptr;
        }
    }
}

#pragma endregion

typedef uint32_t (*PFN_NVSDK_NGX_GetSnippetVersion)(void);
static feature_version GetVersionUsingNGXSnippet(const std::vector<std::string>& dlls)
{
    uint32_t highestVersion = 0;
    for (const auto& dll : dlls)
    {
        PFN_NVSDK_NGX_GetSnippetVersion _GetSnippetVersion =
            (PFN_NVSDK_NGX_GetSnippetVersion) DetourFindFunction(dll.c_str(), "NVSDK_NGX_GetSnippetVersion");
        if (_GetSnippetVersion)
        {
            LOG_TRACE("_GetSnippetVersion ptr from {}: {:X}", dll, (ULONG64) _GetSnippetVersion);
            uint32_t version = _GetSnippetVersion();
            highestVersion = std::max(version, highestVersion);
        }
    }

    feature_version version;

    version.major = (highestVersion & 0xFFFF0000) / 0x00010000;
    version.minor = (highestVersion & 0x0000FF00) / 0x00000100;
    version.patch = (highestVersion & 0x000000FF) / 0x00000001;

    return version;
}

typedef NVSDK_NGX_Result (*PFN_CUDA_Init)(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                          const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                          NVSDK_NGX_Version InSDKVersion);
typedef NVSDK_NGX_Result (*PFN_CUDA_Init_ProjectID)(const char* InProjectId, NVSDK_NGX_EngineType InEngineType,
                                                    const char* InEngineVersion, const wchar_t* InApplicationDataPath,
                                                    NVSDK_NGX_Version InSDKVersion,
                                                    const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_CUDA_Shutdown)(void);
typedef NVSDK_NGX_Result (*PFN_CUDA_GetParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_CUDA_AllocateParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_CUDA_GetCapabilityParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_CUDA_DestroyParameters)(NVSDK_NGX_Parameter* InParameters);
typedef NVSDK_NGX_Result (*PFN_CUDA_GetScratchBufferSize)(NVSDK_NGX_Feature InFeatureId,
                                                          const NVSDK_NGX_Parameter* InParameters,
                                                          size_t* OutSizeInBytes);
typedef NVSDK_NGX_Result (*PFN_CUDA_CreateFeature)(NVSDK_NGX_Feature InFeatureID,
                                                   const NVSDK_NGX_Parameter* InParameters,
                                                   NVSDK_NGX_Handle** OutHandle);
typedef NVSDK_NGX_Result (*PFN_CUDA_EvaluateFeature)(const NVSDK_NGX_Handle* InFeatureHandle,
                                                     const NVSDK_NGX_Parameter* InParameters,
                                                     PFN_NVSDK_NGX_ProgressCallback InCallback);
typedef NVSDK_NGX_Result (*PFN_CUDA_ReleaseFeature)(NVSDK_NGX_Handle* InHandle);

typedef NVSDK_NGX_Result (*PFN_D3D11_Init)(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                           ID3D11Device* InDevice, const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                           NVSDK_NGX_Version InSDKVersion);
typedef NVSDK_NGX_Result (*PFN_D3D11_Init_ProjectID)(const char* InProjectId, NVSDK_NGX_EngineType InEngineType,
                                                     const char* InEngineVersion, const wchar_t* InApplicationDataPath,
                                                     ID3D11Device* InDevice, NVSDK_NGX_Version InSDKVersion,
                                                     const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_D3D11_Init_Ext)(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                               ID3D11Device* InDevice, NVSDK_NGX_Version InSDKVersion,
                                               const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_D3D11_Shutdown)(void);
typedef NVSDK_NGX_Result (*PFN_D3D11_Shutdown1)(ID3D11Device* InDevice);
typedef NVSDK_NGX_Result (*PFN_D3D11_GetParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_D3D11_AllocateParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_D3D11_GetCapabilityParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_D3D11_DestroyParameters)(NVSDK_NGX_Parameter* InParameters);
typedef NVSDK_NGX_Result (*PFN_D3D11_GetScratchBufferSize)(NVSDK_NGX_Feature InFeatureId,
                                                           const NVSDK_NGX_Parameter* InParameters,
                                                           size_t* OutSizeInBytes);
typedef NVSDK_NGX_Result (*PFN_D3D11_CreateFeature)(ID3D11DeviceContext* InDevCtx, NVSDK_NGX_Feature InFeatureID,
                                                    NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle);
typedef NVSDK_NGX_Result (*PFN_D3D11_ReleaseFeature)(NVSDK_NGX_Handle* InHandle);
typedef NVSDK_NGX_Result (*PFN_D3D11_GetFeatureRequirements)(IDXGIAdapter* Adapter,
                                                             const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
                                                             NVSDK_NGX_FeatureRequirement* OutSupported);
typedef NVSDK_NGX_Result (*PFN_D3D11_EvaluateFeature)(ID3D11DeviceContext* InDevCtx,
                                                      const NVSDK_NGX_Handle* InFeatureHandle,
                                                      const NVSDK_NGX_Parameter* InParameters,
                                                      PFN_NVSDK_NGX_ProgressCallback InCallback);

typedef NVSDK_NGX_Result (*PFN_D3D12_Init)(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                           ID3D12Device* InDevice, const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                           NVSDK_NGX_Version InSDKVersion);
typedef NVSDK_NGX_Result (*PFN_D3D12_Init_ProjectID)(const char* InProjectId, NVSDK_NGX_EngineType InEngineType,
                                                     const char* InEngineVersion, const wchar_t* InApplicationDataPath,
                                                     ID3D12Device* InDevice, NVSDK_NGX_Version InSDKVersion,
                                                     const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_D3D12_Init_Ext)(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                               ID3D12Device* InDevice, NVSDK_NGX_Version InSDKVersion,
                                               const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_D3D12_Shutdown)(void);
typedef NVSDK_NGX_Result (*PFN_D3D12_Shutdown1)(ID3D12Device* InDevice);
typedef NVSDK_NGX_Result (*PFN_D3D12_GetParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_D3D12_AllocateParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_D3D12_GetCapabilityParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_D3D12_DestroyParameters)(NVSDK_NGX_Parameter* InParameters);
typedef NVSDK_NGX_Result (*PFN_D3D12_GetScratchBufferSize)(NVSDK_NGX_Feature InFeatureId,
                                                           const NVSDK_NGX_Parameter* InParameters,
                                                           size_t* OutSizeInBytes);
typedef NVSDK_NGX_Result (*PFN_D3D12_CreateFeature)(ID3D12GraphicsCommandList* InCmdList, NVSDK_NGX_Feature InFeatureID,
                                                    NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle);
typedef NVSDK_NGX_Result (*PFN_D3D12_ReleaseFeature)(NVSDK_NGX_Handle* InHandle);
typedef NVSDK_NGX_Result (*PFN_D3D12_GetFeatureRequirements)(IDXGIAdapter* Adapter,
                                                             const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
                                                             NVSDK_NGX_FeatureRequirement* OutSupported);
typedef NVSDK_NGX_Result (*PFN_D3D12_EvaluateFeature)(ID3D12GraphicsCommandList* InCmdList,
                                                      const NVSDK_NGX_Handle* InFeatureHandle,
                                                      const NVSDK_NGX_Parameter* InParameters,
                                                      PFN_NVSDK_NGX_ProgressCallback InCallback);
typedef NVSDK_NGX_Result (*PFN_D3D12_PopulateParameters_Impl)(NVSDK_NGX_Parameter* InParameters);

typedef NVSDK_NGX_Result (*PFN_UpdateFeature)(const NVSDK_NGX_Application_Identifier* ApplicationId,
                                              const NVSDK_NGX_Feature FeatureID);

typedef NVSDK_NGX_Result (*PFN_VULKAN_RequiredExtensions)(unsigned int* OutInstanceExtCount,
                                                          const char*** OutInstanceExts,
                                                          unsigned int* OutDeviceExtCount, const char*** OutDeviceExts);
typedef NVSDK_NGX_Result (*PFN_VULKAN_Init)(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                            VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                            PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA,
                                            const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                            NVSDK_NGX_Version InSDKVersion);
typedef NVSDK_NGX_Result (*PFN_VULKAN_Init_Ext)(unsigned long long InApplicationId,
                                                const wchar_t* InApplicationDataPath, VkInstance InInstance,
                                                VkPhysicalDevice InPD, VkDevice InDevice,
                                                NVSDK_NGX_Version InSDKVersion,
                                                const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_VULKAN_Init_Ext2)(unsigned long long InApplicationId,
                                                 const wchar_t* InApplicationDataPath, VkInstance InInstance,
                                                 VkPhysicalDevice InPD, VkDevice InDevice,
                                                 PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA,
                                                 NVSDK_NGX_Version InSDKVersion,
                                                 const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_VULKAN_Init_ProjectID_Ext)(
    const char* InProjectId, NVSDK_NGX_EngineType InEngineType, const char* InEngineVersion,
    const wchar_t* InApplicationDataPath, VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
    PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA, NVSDK_NGX_Version InSDKVersion,
    const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_VULKAN_Init_ProjectID)(const char* InProjectId, NVSDK_NGX_EngineType InEngineType,
                                                      const char* InEngineVersion, const wchar_t* InApplicationDataPath,
                                                      VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                                                      PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA,
                                                      NVSDK_NGX_Version InSDKVersion,
                                                      const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo);
typedef NVSDK_NGX_Result (*PFN_VULKAN_Shutdown)(void);
typedef NVSDK_NGX_Result (*PFN_VULKAN_Shutdown1)(VkDevice InDevice);
typedef NVSDK_NGX_Result (*PFN_VULKAN_GetParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_VULKAN_AllocateParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_VULKAN_GetCapabilityParameters)(NVSDK_NGX_Parameter** OutParameters);
typedef NVSDK_NGX_Result (*PFN_VULKAN_DestroyParameters)(NVSDK_NGX_Parameter* InParameters);
typedef NVSDK_NGX_Result (*PFN_VULKAN_GetScratchBufferSize)(NVSDK_NGX_Feature InFeatureId,
                                                            const NVSDK_NGX_Parameter* InParameters,
                                                            size_t* OutSizeInBytes);
typedef NVSDK_NGX_Result (*PFN_VULKAN_CreateFeature)(VkCommandBuffer InCmdBuffer, NVSDK_NGX_Feature InFeatureID,
                                                     NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle);
typedef NVSDK_NGX_Result (*PFN_VULKAN_CreateFeature1)(VkDevice InDevice, VkCommandBuffer InCmdList,
                                                      NVSDK_NGX_Feature InFeatureID, NVSDK_NGX_Parameter* InParameters,
                                                      NVSDK_NGX_Handle** OutHandle);
typedef NVSDK_NGX_Result (*PFN_VULKAN_ReleaseFeature)(NVSDK_NGX_Handle* InHandle);
typedef NVSDK_NGX_Result (*PFN_VULKAN_GetFeatureRequirements)(
    const VkInstance Instance, const VkPhysicalDevice PhysicalDevice,
    const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo, NVSDK_NGX_FeatureRequirement* OutSupported);
typedef NVSDK_NGX_Result (*PFN_VULKAN_GetFeatureInstanceExtensionRequirements)(
    const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo, uint32_t* OutExtensionCount,
    VkExtensionProperties** OutExtensionProperties);
typedef NVSDK_NGX_Result (*PFN_VULKAN_GetFeatureDeviceExtensionRequirements)(
    VkInstance Instance, VkPhysicalDevice PhysicalDevice, const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
    uint32_t* OutExtensionCount, VkExtensionProperties** OutExtensionProperties);
typedef NVSDK_NGX_Result (*PFN_VULKAN_EvaluateFeature)(VkCommandBuffer InCmdList,
                                                       const NVSDK_NGX_Handle* InFeatureHandle,
                                                       const NVSDK_NGX_Parameter* InParameters,
                                                       PFN_NVSDK_NGX_ProgressCallback InCallback);
typedef NVSDK_NGX_Result (*PFN_VULKAN_PopulateParameters_Impl)(NVSDK_NGX_Parameter* InParameters);

struct NvngxModule
{
    HMODULE dll = nullptr;
    std::wstring filePath;

    PFN_CUDA_Init CUDA_Init = nullptr;
    PFN_CUDA_Init_ProjectID CUDA_Init_ProjectID = nullptr;
    PFN_CUDA_Shutdown CUDA_Shutdown = nullptr;
    PFN_CUDA_GetParameters CUDA_GetParameters = nullptr;
    PFN_CUDA_AllocateParameters CUDA_AllocateParameters = nullptr;
    PFN_CUDA_GetCapabilityParameters CUDA_GetCapabilityParameters = nullptr;
    PFN_CUDA_DestroyParameters CUDA_DestroyParameters = nullptr;
    PFN_CUDA_GetScratchBufferSize CUDA_GetScratchBufferSize = nullptr;
    PFN_CUDA_CreateFeature CUDA_CreateFeature = nullptr;
    PFN_CUDA_EvaluateFeature CUDA_EvaluateFeature = nullptr;
    PFN_CUDA_ReleaseFeature CUDA_ReleaseFeature = nullptr;

    PFN_D3D11_Init D3D11_Init = nullptr;
    PFN_D3D11_Init_ProjectID D3D11_Init_ProjectID = nullptr;
    PFN_D3D11_Init_Ext D3D11_Init_Ext = nullptr;
    PFN_D3D11_Shutdown D3D11_Shutdown = nullptr;
    PFN_D3D11_Shutdown1 D3D11_Shutdown1 = nullptr;
    PFN_D3D11_GetParameters D3D11_GetParameters = nullptr;
    PFN_D3D11_AllocateParameters D3D11_AllocateParameters = nullptr;
    PFN_D3D11_GetCapabilityParameters D3D11_GetCapabilityParameters = nullptr;
    PFN_D3D11_DestroyParameters D3D11_DestroyParameters = nullptr;
    PFN_D3D11_GetScratchBufferSize D3D11_GetScratchBufferSize = nullptr;
    PFN_D3D11_CreateFeature D3D11_CreateFeature = nullptr;
    PFN_D3D11_ReleaseFeature D3D11_ReleaseFeature = nullptr;
    PFN_D3D11_GetFeatureRequirements D3D11_GetFeatureRequirements = nullptr;
    PFN_D3D11_EvaluateFeature D3D11_EvaluateFeature = nullptr;

    PFN_D3D12_Init D3D12_Init = nullptr;
    PFN_D3D12_Init_ProjectID D3D12_Init_ProjectID = nullptr;
    PFN_D3D12_Init_Ext D3D12_Init_Ext = nullptr;
    PFN_D3D12_Shutdown D3D12_Shutdown = nullptr;
    PFN_D3D12_Shutdown1 D3D12_Shutdown1 = nullptr;
    PFN_D3D12_GetParameters D3D12_GetParameters = nullptr;
    PFN_D3D12_AllocateParameters D3D12_AllocateParameters = nullptr;
    PFN_D3D12_GetCapabilityParameters D3D12_GetCapabilityParameters = nullptr;
    PFN_D3D12_DestroyParameters D3D12_DestroyParameters = nullptr;
    PFN_D3D12_GetScratchBufferSize D3D12_GetScratchBufferSize = nullptr;
    PFN_D3D12_CreateFeature D3D12_CreateFeature = nullptr;
    PFN_D3D12_ReleaseFeature D3D12_ReleaseFeature = nullptr;
    PFN_D3D12_GetFeatureRequirements D3D12_GetFeatureRequirements = nullptr;
    PFN_D3D12_EvaluateFeature D3D12_EvaluateFeature = nullptr;

    PFN_VULKAN_RequiredExtensions VULKAN_RequiredExtensions = nullptr;
    PFN_VULKAN_Init VULKAN_Init = nullptr;
    PFN_VULKAN_Init_ProjectID VULKAN_Init_ProjectID = nullptr;
    PFN_VULKAN_Init_Ext VULKAN_Init_Ext = nullptr;
    PFN_VULKAN_Init_Ext2 VULKAN_Init_Ext2 = nullptr;
    PFN_VULKAN_Init_ProjectID_Ext VULKAN_Init_ProjectID_Ext = nullptr;
    PFN_VULKAN_Shutdown VULKAN_Shutdown = nullptr;
    PFN_VULKAN_Shutdown1 VULKAN_Shutdown1 = nullptr;
    PFN_VULKAN_GetParameters VULKAN_GetParameters = nullptr;
    PFN_VULKAN_AllocateParameters VULKAN_AllocateParameters = nullptr;
    PFN_VULKAN_GetCapabilityParameters VULKAN_GetCapabilityParameters = nullptr;
    PFN_VULKAN_DestroyParameters VULKAN_DestroyParameters = nullptr;
    PFN_VULKAN_GetScratchBufferSize VULKAN_GetScratchBufferSize = nullptr;
    PFN_VULKAN_CreateFeature VULKAN_CreateFeature = nullptr;
    PFN_VULKAN_CreateFeature1 VULKAN_CreateFeature1 = nullptr;
    PFN_VULKAN_ReleaseFeature VULKAN_ReleaseFeature = nullptr;
    PFN_VULKAN_GetFeatureRequirements VULKAN_GetFeatureRequirements = nullptr;
    PFN_VULKAN_GetFeatureInstanceExtensionRequirements VULKAN_GetFeatureInstanceExtensionRequirements = nullptr;
    PFN_VULKAN_GetFeatureDeviceExtensionRequirements VULKAN_GetFeatureDeviceExtensionRequirements = nullptr;
    PFN_VULKAN_EvaluateFeature VULKAN_EvaluateFeature = nullptr;

    PFN_UpdateFeature UpdateFeature = nullptr;
};

class NVNGXProxy
{
  private:
    inline static ProviderPublication<NvngxModule> _modulePublication;
    inline static const NvngxModule _emptyModule {};

    static const NvngxModule& GetModule()
    {
        auto* module = _modulePublication.Peek();
        return module ? *module : _emptyModule;
    }

    inline static bool _cudaInited = false;
    inline static bool _dx11Inited = false;
    inline static NativeDeviceLifecycle _dx12Devices;
    inline static NativeDeviceLifecycle _vulkanDevices;

    inline static void LogCallback(const char* message, NVSDK_NGX_Logging_Level loggingLevel,
                                   NVSDK_NGX_Feature sourceComponent)
    {
        std::string logMessage(message);
        LOG_DEBUG("NVSDK Feature {}: {}", (UINT) sourceComponent, logMessage);
    }

    static std::unique_ptr<NvngxModule> BuildModule(HMODULE nvngxModule)
    {
        auto candidate = std::make_unique<NvngxModule>();
        auto& module = *candidate;

        LOG_INFO("");

        ScopedSkipDxgiLoadChecks scopedSkipDxgiLoadChecks {};

        if (nvngxModule != nullptr && module.dll == nullptr)
        {
            module.dll = nvngxModule;
        }

        std::vector<std::wstring> dllNames = { L"_nvngx.dll", L"nvngx.dll" };

        auto optiPath = Config::Instance()->MainDllPath.value();
        auto overridePath = Config::Instance()->NvngxPath.value_or(L"");

        if (module.dll == nullptr)
        {
            for (size_t i = 0; i < dllNames.size(); i++)
            {
                LOG_DEBUG("Trying to load {}", wstring_to_string(dllNames[i]));

                HMODULE memModule = nullptr;
                Util::LoadProxyLibrary(dllNames[i], optiPath, overridePath, &memModule, &module.dll);

                if (module.dll != nullptr)
                {
                    break;
                }
            }
        }

        if (module.dll == nullptr)
        {
            auto regNGXCorePath = Util::NvngxPath();
            if (regNGXCorePath.has_value())
            {
                overridePath = regNGXCorePath.value();

                for (size_t i = 0; i < dllNames.size(); i++)
                {
                    LOG_DEBUG("Trying to load {}", wstring_to_string(dllNames[i]));

                    HMODULE memModule = nullptr;
                    Util::LoadProxyLibrary(dllNames[i], optiPath, overridePath, &memModule, &module.dll);

                    if (module.dll != nullptr)
                    {
                        break;
                    }
                }
            }
        }

        if (module.dll != nullptr)
        {
            wchar_t modulePath[MAX_PATH] {};
            DWORD len = GetModuleFileNameW(module.dll, modulePath, MAX_PATH);
            if (len > 0 && len < MAX_PATH)
                module.filePath.assign(modulePath, len);

            LOG_INFO("Loaded from {}", wstring_to_string(module.filePath));
        }

        if (module.dll != nullptr && module.D3D12_Init_ProjectID == nullptr)
        {
            LOG_INFO("Getting nvngx method addresses");

            HookNgxApi(module.dll);

            module.D3D11_Init = (PFN_D3D11_Init) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D11_Init");
            module.D3D11_Init_ProjectID = (PFN_D3D11_Init_ProjectID) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_Init_ProjectID");
            module.D3D11_Init_Ext =
                (PFN_D3D11_Init_Ext) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D11_Init_Ext");
            module.D3D11_Shutdown =
                (PFN_D3D11_Shutdown) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D11_Shutdown");
            module.D3D11_Shutdown1 =
                (PFN_D3D11_Shutdown1) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D11_Shutdown1");
            module.D3D11_GetParameters = (PFN_D3D11_GetParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_GetParameters");
            module.D3D11_AllocateParameters = (PFN_D3D11_AllocateParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_AllocateParameters");
            module.D3D11_GetCapabilityParameters =
                (PFN_D3D11_GetCapabilityParameters) KernelBaseProxy::GetProcAddress_()(
                    module.dll, "NVSDK_NGX_D3D11_GetCapabilityParameters");
            module.D3D11_DestroyParameters = (PFN_D3D11_DestroyParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_DestroyParameters");
            module.D3D11_GetScratchBufferSize = (PFN_D3D11_GetScratchBufferSize) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_GetScratchBufferSize");
            module.D3D11_CreateFeature = (PFN_D3D11_CreateFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_CreateFeature");
            module.D3D11_ReleaseFeature = (PFN_D3D11_ReleaseFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_ReleaseFeature");
            module.D3D11_GetFeatureRequirements = (PFN_D3D11_GetFeatureRequirements) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_GetFeatureRequirements");
            module.D3D11_EvaluateFeature = (PFN_D3D11_EvaluateFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D11_EvaluateFeature");

            module.D3D12_Init = (PFN_D3D12_Init) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D12_Init");
            module.D3D12_Init_ProjectID = (PFN_D3D12_Init_ProjectID) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_Init_ProjectID");
            module.D3D12_Init_Ext =
                (PFN_D3D12_Init_Ext) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D12_Init_Ext");
            module.D3D12_Shutdown =
                (PFN_D3D12_Shutdown) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D12_Shutdown");
            module.D3D12_Shutdown1 =
                (PFN_D3D12_Shutdown1) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_D3D12_Shutdown1");
            module.D3D12_GetParameters = (PFN_D3D12_GetParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_GetParameters");
            module.D3D12_AllocateParameters = (PFN_D3D12_AllocateParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_AllocateParameters");
            module.D3D12_GetCapabilityParameters =
                (PFN_D3D12_GetCapabilityParameters) KernelBaseProxy::GetProcAddress_()(
                    module.dll, "NVSDK_NGX_D3D12_GetCapabilityParameters");
            module.D3D12_DestroyParameters = (PFN_D3D12_DestroyParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_DestroyParameters");
            module.D3D12_GetScratchBufferSize = (PFN_D3D12_GetScratchBufferSize) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_GetScratchBufferSize");
            module.D3D12_CreateFeature = (PFN_D3D12_CreateFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_CreateFeature");
            module.D3D12_ReleaseFeature = (PFN_D3D12_ReleaseFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_ReleaseFeature");
            module.D3D12_GetFeatureRequirements = (PFN_D3D12_GetFeatureRequirements) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_GetFeatureRequirements");
            module.D3D12_EvaluateFeature = (PFN_D3D12_EvaluateFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_D3D12_EvaluateFeature");

            module.VULKAN_RequiredExtensions = (PFN_VULKAN_RequiredExtensions) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_RequiredExtensions");
            module.VULKAN_Init =
                (PFN_VULKAN_Init) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_VULKAN_Init");
            module.VULKAN_Init_Ext =
                (PFN_VULKAN_Init_Ext) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_VULKAN_Init_Ext");
            module.VULKAN_Init_Ext2 =
                (PFN_VULKAN_Init_Ext2) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_VULKAN_Init_Ext2");
            module.VULKAN_Init_ProjectID_Ext = (PFN_VULKAN_Init_ProjectID_Ext) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_Init_ProjectID_Ext");
            module.VULKAN_Init_ProjectID = (PFN_VULKAN_Init_ProjectID) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_Init_ProjectID");
            module.VULKAN_Shutdown =
                (PFN_VULKAN_Shutdown) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_VULKAN_Shutdown");
            module.VULKAN_Shutdown1 =
                (PFN_VULKAN_Shutdown1) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_VULKAN_Shutdown1");
            module.VULKAN_GetParameters = (PFN_VULKAN_GetParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_GetParameters");
            module.VULKAN_AllocateParameters = (PFN_VULKAN_AllocateParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_AllocateParameters");
            module.VULKAN_GetCapabilityParameters =
                (PFN_VULKAN_GetCapabilityParameters) KernelBaseProxy::GetProcAddress_()(
                    module.dll, "NVSDK_NGX_VULKAN_GetCapabilityParameters");
            module.VULKAN_DestroyParameters = (PFN_VULKAN_DestroyParameters) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_DestroyParameters");
            module.VULKAN_GetScratchBufferSize = (PFN_VULKAN_GetScratchBufferSize) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_GetScratchBufferSize");
            module.VULKAN_CreateFeature = (PFN_VULKAN_CreateFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_CreateFeature");
            module.VULKAN_CreateFeature1 = (PFN_VULKAN_CreateFeature1) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_CreateFeature1");
            module.VULKAN_ReleaseFeature = (PFN_VULKAN_ReleaseFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_ReleaseFeature");
            module.VULKAN_GetFeatureRequirements =
                (PFN_VULKAN_GetFeatureRequirements) KernelBaseProxy::GetProcAddress_()(
                    module.dll, "NVSDK_NGX_VULKAN_GetFeatureRequirements");
            module.VULKAN_GetFeatureInstanceExtensionRequirements =
                (PFN_VULKAN_GetFeatureInstanceExtensionRequirements) KernelBaseProxy::GetProcAddress_()(
                    module.dll, "NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements");
            module.VULKAN_GetFeatureDeviceExtensionRequirements =
                (PFN_VULKAN_GetFeatureDeviceExtensionRequirements) KernelBaseProxy::GetProcAddress_()(
                    module.dll, "NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements");
            module.VULKAN_EvaluateFeature = (PFN_VULKAN_EvaluateFeature) KernelBaseProxy::GetProcAddress_()(
                module.dll, "NVSDK_NGX_VULKAN_EvaluateFeature");

            module.UpdateFeature =
                (PFN_UpdateFeature) KernelBaseProxy::GetProcAddress_()(module.dll, "NVSDK_NGX_UpdateFeature");
        }

        return module.dll ? std::move(candidate) : nullptr;
    }

  public:
    static void InitNVNGX(HMODULE nvngxModule = nullptr)
    {
        // Native loader callbacks may re-enter. Pending returns immediately;
        // no caller observes this candidate's partially resolved export table.
        _modulePublication.GetOrCreate([&] { return BuildModule(nvngxModule); });
    }

    [[nodiscard]] static NgxPathSnapshot::Owner GetFeatureCommonInfo(NVSDK_NGX_FeatureCommonInfo* fcInfo)
    {
        if (!fcInfo)
            return {};
        const auto cached = State::Instance().NVNGX_FeatureInfo_Paths.Read();
        auto paths = cached ? cached->Strings() : std::vector<std::wstring> {};
        if (State::Instance().NVNGX_DLSS_Path.has_value())
        {
            std::filesystem::path dlssPath(State::Instance().NVNGX_DLSS_Path.value());
            paths.push_back(dlssPath.remove_filename().wstring());
        }
        auto owner = std::make_shared<const NgxPathSnapshot>(std::move(paths));
        owner->Bind(fcInfo->PathListInfo);

        // Config logging
        fcInfo->LoggingInfo.MinimumLoggingLevel =
            Config::Instance()->LogLevel < 2 ? NVSDK_NGX_LOGGING_LEVEL_VERBOSE : NVSDK_NGX_LOGGING_LEVEL_ON;
        fcInfo->LoggingInfo.LoggingCallback = LogCallback;
        fcInfo->LoggingInfo.DisableOtherLoggingSinks = true;
        return owner;
    }

    static HMODULE NVNGXModule() { return GetModule().dll; }
    static std::wstring NVNGXModule_Path() { return GetModule().filePath; }

    static bool IsNVNGXInited()
    {
        return GetModule().dll != nullptr && (_dx11Inited || IsDx12Inited() || IsVulkanInited()) &&
               Config::Instance()->DLSSEnabled.value_or_default();
    }

    // DirectX11
    static bool InitDx11(ID3D11Device* InDevice)
    {
        if (_dx11Inited)
            return true;

        InitNVNGX();

        if (GetModule().dll == nullptr)
            return false;

        NVSDK_NGX_FeatureCommonInfo fcInfo {};
        const auto initPaths = GetFeatureCommonInfo(&fcInfo);
        const auto metadata = State::Instance().NVNGX_Init.Read();
        NVSDK_NGX_Result nvResult = NVSDK_NGX_Result_Fail;

        if (metadata->ProjectId != "" && GetModule().D3D11_Init_ProjectID != nullptr)
        {
            LOG_DEBUG("GetModule().D3D11_Init_ProjectID!");

            nvResult = GetModule().D3D11_Init_ProjectID(
                metadata->ProjectId.c_str(), metadata->EngineType, metadata->EngineVersion.c_str(),
                metadata->ApplicationDataPath.c_str(), InDevice, metadata->SdkVersion, &fcInfo);
        }
        else if (GetModule().D3D11_Init_Ext != nullptr)
        {
            LOG_DEBUG("GetModule().D3D11_Init_Ext!");
            nvResult = GetModule().D3D11_Init_Ext(metadata->ApplicationId, metadata->ApplicationDataPath.c_str(),
                                                  InDevice, metadata->SdkVersion, &fcInfo);
        }

        LOG_DEBUG("result: {0:X}", (UINT) nvResult);

        _dx11Inited = (nvResult == NVSDK_NGX_Result_Success);
        return _dx11Inited;
    }

    static void SetDx11Inited(bool value) { _dx11Inited = value; }

    static bool IsDx11Inited() { return _dx11Inited; }

    static PFN_D3D11_Init_ProjectID D3D11_Init_ProjectID() { return GetModule().D3D11_Init_ProjectID; }

    static PFN_D3D11_Init D3D11_Init() { return GetModule().D3D11_Init; }

    static PFN_D3D11_Init_Ext D3D11_Init_Ext() { return GetModule().D3D11_Init_Ext; }

    static PFN_D3D11_GetFeatureRequirements D3D11_GetFeatureRequirements()
    {
        return GetModule().D3D11_GetFeatureRequirements;
    }

    static PFN_D3D11_GetCapabilityParameters D3D11_GetCapabilityParameters()
    {
        return GetModule().D3D11_GetCapabilityParameters;
    }

    static PFN_D3D11_AllocateParameters D3D11_AllocateParameters() { return GetModule().D3D11_AllocateParameters; }

    static PFN_D3D11_GetParameters D3D11_GetParameters() { return GetModule().D3D11_GetParameters; }

    static PFN_D3D11_DestroyParameters D3D11_DestroyParameters()
    {
        if (!_dx11Inited)
            return nullptr;

        return GetModule().D3D11_DestroyParameters;
    }

    static PFN_D3D11_CreateFeature D3D11_CreateFeature()
    {
        if (!_dx11Inited)
            return nullptr;

        return GetModule().D3D11_CreateFeature;
    }

    static PFN_D3D11_EvaluateFeature D3D11_EvaluateFeature()
    {
        if (!_dx11Inited)
            return nullptr;

        return GetModule().D3D11_EvaluateFeature;
    }

    static PFN_D3D11_ReleaseFeature D3D11_ReleaseFeature()
    {
        if (!_dx11Inited)
            return nullptr;

        return GetModule().D3D11_ReleaseFeature;
    }

    static PFN_D3D11_Shutdown D3D11_Shutdown()
    {
        if (!_dx11Inited)
            return nullptr;

        return GetModule().D3D11_Shutdown;
    }

    static PFN_D3D11_Shutdown1 D3D11_Shutdown1()
    {
        if (!_dx11Inited)
            return nullptr;

        return GetModule().D3D11_Shutdown1;
    }

    // DirectX12
    static bool InitDx12(ID3D12Device* InDevice)
    {
        return RunDx12Init(InDevice,
                           [&]() -> NVSDK_NGX_Result
                           {
                               InitNVNGX();

                               if (GetModule().dll == nullptr)
                                   return NVSDK_NGX_Result_Fail;

                               NVSDK_NGX_FeatureCommonInfo fcInfo {};
                               const auto initPaths = GetFeatureCommonInfo(&fcInfo);
                               const auto metadata = State::Instance().NVNGX_Init.Read();
                               NVSDK_NGX_Result nvResult = NVSDK_NGX_Result_Fail;

                               if (metadata->ProjectId != "" && GetModule().D3D12_Init_ProjectID != nullptr)
                               {
                                   LOG_INFO("GetModule().D3D12_Init_ProjectID!");

                                   nvResult = GetModule().D3D12_Init_ProjectID(
                                       metadata->ProjectId.c_str(), metadata->EngineType,
                                       metadata->EngineVersion.c_str(), metadata->ApplicationDataPath.c_str(), InDevice,
                                       metadata->SdkVersion, &fcInfo);
                               }
                               else if (GetModule().D3D12_Init_Ext != nullptr)
                               {
                                   LOG_INFO("GetModule().D3D12_Init_Ext!");
                                   nvResult = GetModule().D3D12_Init_Ext(metadata->ApplicationId,
                                                                         metadata->ApplicationDataPath.c_str(),
                                                                         InDevice, metadata->SdkVersion, &fcInfo);
                               }

                               LOG_INFO("result: {0:X}", (UINT) nvResult);

                               return nvResult;
                           }) == NVSDK_NGX_Result_Success;
    }

    template <typename Callback> static NVSDK_NGX_Result RunDx12Init(ID3D12Device* InDevice, Callback&& callback)
    {
        return _dx12Devices.Initialize(InDevice, NVSDK_NGX_Result_Success, NVSDK_NGX_Result_FAIL_InvalidParameter,
                                       NVSDK_NGX_Result_FAIL_NotInitialized, std::forward<Callback>(callback));
    }

    static bool IsDx12DeviceInited(ID3D12Device* device) { return _dx12Devices.IsReady(device); }
    static bool IsDx12Inited() { return _dx12Devices.AnyReady(); }

    static NVSDK_NGX_Result ShutdownDx12(ID3D12Device* device)
    {
        return _dx12Devices.Shutdown(
            device, NVSDK_NGX_Result_Success, NVSDK_NGX_Result_FAIL_NotInitialized,
            [&]() -> NVSDK_NGX_Result
            {
                // A device-specific shutdown must never fall back to a global one.
                if (device)
                    return GetModule().D3D12_Shutdown1 ? GetModule().D3D12_Shutdown1(device) : NVSDK_NGX_Result_Fail;
                if (GetModule().D3D12_Shutdown)
                    return GetModule().D3D12_Shutdown();
                return GetModule().D3D12_Shutdown1 ? GetModule().D3D12_Shutdown1(nullptr) : NVSDK_NGX_Result_Fail;
            });
    }

    static PFN_D3D12_Init_ProjectID D3D12_Init_ProjectID() { return GetModule().D3D12_Init_ProjectID; }

    static PFN_D3D12_Init D3D12_Init() { return GetModule().D3D12_Init; }

    static PFN_D3D12_Init_Ext D3D12_Init_Ext() { return GetModule().D3D12_Init_Ext; }

    static PFN_D3D12_GetFeatureRequirements D3D12_GetFeatureRequirements()
    {
        return GetModule().D3D12_GetFeatureRequirements;
    }

    static PFN_D3D12_GetCapabilityParameters D3D12_GetCapabilityParameters()
    {
        return GetModule().D3D12_GetCapabilityParameters;
    }

    static PFN_D3D12_AllocateParameters D3D12_AllocateParameters() { return GetModule().D3D12_AllocateParameters; }

    static PFN_D3D12_GetParameters D3D12_GetParameters() { return GetModule().D3D12_GetParameters; }

    static PFN_D3D12_DestroyParameters D3D12_DestroyParameters()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().D3D12_DestroyParameters ? +[](NVSDK_NGX_Parameter* InParameters) -> NVSDK_NGX_Result
        {
            return _dx12Devices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().D3D12_DestroyParameters(InParameters); });
        } : nullptr;
    }

    static PFN_D3D12_CreateFeature D3D12_CreateFeature()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().D3D12_CreateFeature ? +[](ID3D12GraphicsCommandList* InCmdList, NVSDK_NGX_Feature InFeatureID,
                                                    NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle) -> NVSDK_NGX_Result
        {
            if (!OutHandle)
                return NVSDK_NGX_Result_FAIL_InvalidParameter;
            *OutHandle = nullptr;
            return _dx12Devices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().D3D12_CreateFeature(InCmdList, InFeatureID, InParameters, OutHandle); });
        } : nullptr;
    }

    static PFN_D3D12_EvaluateFeature D3D12_EvaluateFeature()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().D3D12_EvaluateFeature ? +[](ID3D12GraphicsCommandList* InCmdList,
                                                      const NVSDK_NGX_Handle* InFeatureHandle,
                                                      const NVSDK_NGX_Parameter* InParameters,
                                                      PFN_NVSDK_NGX_ProgressCallback InCallback) -> NVSDK_NGX_Result
        {
            return _dx12Devices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().D3D12_EvaluateFeature(InCmdList, InFeatureHandle, InParameters, InCallback); });
        } : nullptr;
    }

    static PFN_D3D12_ReleaseFeature D3D12_ReleaseFeature()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().D3D12_ReleaseFeature ? +[](NVSDK_NGX_Handle* InHandle) -> NVSDK_NGX_Result
        {
            return _dx12Devices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().D3D12_ReleaseFeature(InHandle); });
        } : nullptr;
    }

    static PFN_D3D12_Shutdown D3D12_Shutdown()
    {
        return GetModule().D3D12_Shutdown ? +[]() { return ShutdownDx12(nullptr); } : nullptr;
    }

    static PFN_D3D12_Shutdown1 D3D12_Shutdown1() { return GetModule().D3D12_Shutdown1 ? &ShutdownDx12 : nullptr; }

    // Vulkan
    static bool InitVulkan(VkInstance InInstance, VkPhysicalDevice InPD, VkDevice InDevice,
                           PFN_vkGetInstanceProcAddr InGIPA, PFN_vkGetDeviceProcAddr InGDPA)
    {
        return RunVulkanInit(InDevice,
                             [&]() -> NVSDK_NGX_Result
                             {
                                 InitNVNGX();

                                 if (GetModule().dll == nullptr)
                                     return NVSDK_NGX_Result_Fail;

                                 NVSDK_NGX_FeatureCommonInfo fcInfo {};
                                 const auto initPaths = GetFeatureCommonInfo(&fcInfo);
                                 const auto metadata = State::Instance().NVNGX_Init.Read();
                                 NVSDK_NGX_Result nvResult = NVSDK_NGX_Result_Fail;

                                 if (metadata->ProjectId != "" && GetModule().VULKAN_Init_ProjectID != nullptr)
                                 {
                                     LOG_DEBUG("GetModule().VULKAN_Init_ProjectID!");
                                     nvResult = GetModule().VULKAN_Init_ProjectID(
                                         metadata->ProjectId.c_str(), metadata->EngineType,
                                         metadata->EngineVersion.c_str(), metadata->ApplicationDataPath.c_str(),
                                         InInstance, InPD, InDevice, InGIPA, InGDPA, metadata->SdkVersion, &fcInfo);
                                 }
                                 else if (GetModule().VULKAN_Init_Ext != nullptr)
                                 {
                                     LOG_DEBUG("GetModule().VULKAN_Init_Ext!");
                                     nvResult = GetModule().VULKAN_Init_Ext(
                                         metadata->ApplicationId, metadata->ApplicationDataPath.c_str(), InInstance,
                                         InPD, InDevice, metadata->SdkVersion, &fcInfo);
                                 }

                                 LOG_DEBUG("result: {0:X}", (UINT) nvResult);

                                 return nvResult;
                             }) == NVSDK_NGX_Result_Success;
    }

    template <typename Callback> static NVSDK_NGX_Result RunVulkanInit(VkDevice InDevice, Callback&& callback)
    {
        return _vulkanDevices.Initialize(InDevice, NVSDK_NGX_Result_Success, NVSDK_NGX_Result_FAIL_InvalidParameter,
                                         NVSDK_NGX_Result_FAIL_NotInitialized, std::forward<Callback>(callback));
    }

    static bool IsVulkanDeviceInited(VkDevice device) { return _vulkanDevices.IsReady(device); }
    static bool IsVulkanInited() { return _vulkanDevices.AnyReady(); }

    static NVSDK_NGX_Result ShutdownVulkan(VkDevice device)
    {
        return _vulkanDevices.Shutdown(
            device, NVSDK_NGX_Result_Success, NVSDK_NGX_Result_FAIL_NotInitialized,
            [&]() -> NVSDK_NGX_Result
            {
                // A device-specific shutdown must never fall back to a global one.
                if (device)
                    return GetModule().VULKAN_Shutdown1 ? GetModule().VULKAN_Shutdown1(device) : NVSDK_NGX_Result_Fail;
                if (GetModule().VULKAN_Shutdown)
                    return GetModule().VULKAN_Shutdown();
                return GetModule().VULKAN_Shutdown1 ? GetModule().VULKAN_Shutdown1(nullptr) : NVSDK_NGX_Result_Fail;
            });
    }

    static PFN_VULKAN_Init_ProjectID VULKAN_Init_ProjectID() { return GetModule().VULKAN_Init_ProjectID; }

    static PFN_VULKAN_Init_ProjectID_Ext VULKAN_Init_ProjectID_Ext() { return GetModule().VULKAN_Init_ProjectID_Ext; }

    static PFN_VULKAN_Init_Ext VULKAN_Init_Ext() { return GetModule().VULKAN_Init_Ext; }

    static PFN_VULKAN_Init_Ext2 VULKAN_Init_Ext2() { return GetModule().VULKAN_Init_Ext2; }

    static PFN_VULKAN_Init VULKAN_Init() { return GetModule().VULKAN_Init; }

    static PFN_VULKAN_GetFeatureDeviceExtensionRequirements VULKAN_GetFeatureDeviceExtensionRequirements()
    {
        return GetModule().VULKAN_GetFeatureDeviceExtensionRequirements;
    }

    static PFN_VULKAN_GetFeatureInstanceExtensionRequirements VULKAN_GetFeatureInstanceExtensionRequirements()
    {
        return GetModule().VULKAN_GetFeatureInstanceExtensionRequirements;
    }

    static PFN_VULKAN_GetFeatureRequirements VULKAN_GetFeatureRequirements()
    {
        return GetModule().VULKAN_GetFeatureRequirements;
    }

    static PFN_VULKAN_GetCapabilityParameters VULKAN_GetCapabilityParameters()
    {
        return GetModule().VULKAN_GetCapabilityParameters;
    }

    static PFN_VULKAN_AllocateParameters VULKAN_AllocateParameters() { return GetModule().VULKAN_AllocateParameters; }

    static PFN_VULKAN_GetParameters VULKAN_GetParameters() { return GetModule().VULKAN_GetParameters; }

    static PFN_VULKAN_DestroyParameters VULKAN_DestroyParameters()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().VULKAN_DestroyParameters ? +[](NVSDK_NGX_Parameter* InParameters) -> NVSDK_NGX_Result
        {
            return _vulkanDevices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().VULKAN_DestroyParameters(InParameters); });
        } : nullptr;
    }

    static PFN_VULKAN_CreateFeature VULKAN_CreateFeature()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().VULKAN_CreateFeature ? +[](VkCommandBuffer InCmdBuffer, NVSDK_NGX_Feature InFeatureID,
                                                     NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle) -> NVSDK_NGX_Result
        {
            if (!OutHandle)
                return NVSDK_NGX_Result_FAIL_InvalidParameter;
            *OutHandle = nullptr;
            return _vulkanDevices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().VULKAN_CreateFeature(InCmdBuffer, InFeatureID, InParameters, OutHandle); });
        } : nullptr;
    }

    static PFN_VULKAN_CreateFeature1 VULKAN_CreateFeature1()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().VULKAN_CreateFeature1 ? +[](VkDevice InDevice, VkCommandBuffer InCmdList,
                                                      NVSDK_NGX_Feature InFeatureID, NVSDK_NGX_Parameter* InParameters,
                                                      NVSDK_NGX_Handle** OutHandle) -> NVSDK_NGX_Result
        {
            if (!OutHandle)
                return NVSDK_NGX_Result_FAIL_InvalidParameter;
            *OutHandle = nullptr;
            return _vulkanDevices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().VULKAN_CreateFeature1(InDevice, InCmdList, InFeatureID, InParameters, OutHandle); }, InDevice);
        } : nullptr;
    }

    static PFN_VULKAN_EvaluateFeature VULKAN_EvaluateFeature()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().VULKAN_EvaluateFeature ? +[](VkCommandBuffer InCmdList,
                                                       const NVSDK_NGX_Handle* InFeatureHandle,
                                                       const NVSDK_NGX_Parameter* InParameters,
                                                       PFN_NVSDK_NGX_ProgressCallback InCallback) -> NVSDK_NGX_Result
        {
            return _vulkanDevices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().VULKAN_EvaluateFeature(InCmdList, InFeatureHandle, InParameters, InCallback); });
        } : nullptr;
    }

    static PFN_VULKAN_ReleaseFeature VULKAN_ReleaseFeature()
    {
        // Availability is stable; admission is checked when the pointer is called.
        // This also protects pointers cached before a concurrent shutdown.
        return GetModule().VULKAN_ReleaseFeature ? +[](NVSDK_NGX_Handle* InHandle) -> NVSDK_NGX_Result
        {
            return _vulkanDevices.RunOperation(NVSDK_NGX_Result_FAIL_NotInitialized,
                [&] { return GetModule().VULKAN_ReleaseFeature(InHandle); });
        } : nullptr;
    }

    static PFN_VULKAN_Shutdown VULKAN_Shutdown()
    {
        return GetModule().VULKAN_Shutdown ? +[]() { return ShutdownVulkan(nullptr); } : nullptr;
    }

    static PFN_VULKAN_Shutdown1 VULKAN_Shutdown1() { return GetModule().VULKAN_Shutdown1 ? &ShutdownVulkan : nullptr; }

    static PFN_UpdateFeature UpdateFeature()
    {
        if (GetModule().dll == nullptr)
            InitNVNGX();

        return GetModule().UpdateFeature;
    }
};
