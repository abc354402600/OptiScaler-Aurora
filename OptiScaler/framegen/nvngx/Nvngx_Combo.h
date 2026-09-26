#pragma once
#include "IFGNvngx.h"
#include "Nvngx_FFX.h"
#include "Nvngx_Arturs.h"
#include <d3d12.h>
#include <unordered_set>
#include <mutex>
#include <vector>
#include <wrl/client.h>

struct Nvngx_Combo_Handle
{
    unsigned int Id;

    NVSDK_NGX_Handle* ffxHandle = nullptr;
    NVSDK_NGX_Handle* artursHandle = nullptr;
    bool releaseStarted = false;
};

class Nvngx_Combo : public IFGNvngx
{
  private:
    std::atomic_uint32_t lastIdCreated = 0;

    std::unique_ptr<Nvngx_Arturs> artursProvider = nullptr;
    std::unique_ptr<Nvngx_FFX> ffxProvider = nullptr;

    struct PendingCreate
    {
        std::unique_ptr<Nvngx_Combo_Handle> handle;
        Microsoft::WRL::ComPtr<ID3D12Device> device;
        NVSDK_NGX_Handle* uncertainHandle = nullptr;
        bool uncertain = false;
    };
    // Create calls may run concurrently. Hold this mutex only for bookkeeping,
    // never across child callbacks; Shutdown is excluded by outer admission.
    std::mutex _pendingMutex;
    std::vector<std::shared_ptr<PendingCreate>> _pendingCreates;
    void ForgetPending(const std::shared_ptr<PendingCreate>& pending);
    NVSDK_NGX_Result ReleaseChildren(Nvngx_Combo_Handle* handle);

    // The outer Nvngx_FG transition admission serializes Init/Shutdown.
    // Record each child separately so retry never closes a completed child twice.
    std::unordered_set<ID3D12Device*> _artursInitAttempts;
    std::unordered_set<ID3D12Device*> _ffxInitAttempts;

    template <typename Provider>
    static NVSDK_NGX_Result ShutdownChild(std::unordered_set<ID3D12Device*>& attempts, Provider& child,
                                          ID3D12Device* device)
    {
        if (device ? !attempts.contains(device) : attempts.empty())
            return NVSDK_NGX_Result_Success;
        const auto result = device ? child.D3D12_Shutdown1(device) : child.D3D12_Shutdown();
        if (result == NVSDK_NGX_Result_Success)
        {
            if (device)
                attempts.erase(device);
            else
                attempts.clear();
        }
        return result;
    }

  public:
    Nvngx_Combo()
    {
        artursProvider = std::make_unique<Nvngx_Arturs>();
        ffxProvider = std::make_unique<Nvngx_FFX>();
    }

    bool isDx12Available() override final
    {
        return artursProvider->isDx12Available() && ffxProvider->isDx12Available();
    };
    bool isVulkanAvailable() override final { return false; };

    // DX12
    NVSDK_NGX_Result D3D12_Init(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                ID3D12Device* InDevice, const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,
                                NVSDK_NGX_Version InSDKVersion) override;

    NVSDK_NGX_Result D3D12_Init_Ext(unsigned long long InApplicationId, const wchar_t* InApplicationDataPath,
                                    ID3D12Device* InDevice, NVSDK_NGX_Version InSDKVersion,
                                    const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo) override;

    NVSDK_NGX_Result D3D12_Shutdown() override;

    NVSDK_NGX_Result D3D12_Shutdown1(ID3D12Device* InDevice) override;
    NVSDK_NGX_Result D3D12_DrainPending(ID3D12Device* InDevice) override;

    NVSDK_NGX_Result D3D12_GetScratchBufferSize(NVSDK_NGX_Feature InFeatureId, const NVSDK_NGX_Parameter* InParameters,
                                                size_t* OutSizeInBytes) override;

    NVSDK_NGX_Result D3D12_CreateFeature(ID3D12GraphicsCommandList* InCmdList, NVSDK_NGX_Feature InFeatureID,
                                         NVSDK_NGX_Parameter* InParameters, NVSDK_NGX_Handle** OutHandle) override;

    NVSDK_NGX_Result D3D12_ReleaseFeature(NVSDK_NGX_Handle* InHandle) override;

    NVSDK_NGX_Result D3D12_GetFeatureRequirements(IDXGIAdapter* Adapter,
                                                  const NVSDK_NGX_FeatureDiscoveryInfo* FeatureDiscoveryInfo,
                                                  NVSDK_NGX_FeatureRequirement* OutSupported) override;

    NVSDK_NGX_Result D3D12_EvaluateFeature(ID3D12GraphicsCommandList* InCmdList,
                                           const NVSDK_NGX_Handle* InFeatureHandle, NVSDK_NGX_Parameter* InParameters,
                                           PFN_NVSDK_NGX_ProgressCallback InCallback) override;

    NVSDK_NGX_Result D3D12_PopulateParameters_Impl(NVSDK_NGX_Parameter* InParameters) override;

    int getMaxFakeFramesCount() override { return 5; }
    FGNvngxReplacement getType() override { return FGNvngxReplacement::Combo; }
    feature_version version() override;
    feature_version extraVersion() override;
};
