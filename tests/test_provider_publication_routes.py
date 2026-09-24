"""Execute actual FG routing prefixes and provider shutdown wrappers with stand-ins.

Stops each exported route at the pre-existing native/internal fallback boundary;
a sentinel models that boundary. This verifies Pending never reaches it, not GPU
initialization or the implementation of the native fallback itself.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include "framegen/ProviderPublication.h"
#include "framegen/ProviderCallAdmission.h"
#include <unordered_set>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <unordered_map>
#define NVSDK_NGX_API
#define LOG_FUNC(...)
#define LOG_INFO(...)
#define LOG_WARN(...)
#define LOG_DEBUG(...)
#define LOG_ERROR(...)
using UINT = unsigned;
using NVSDK_NGX_Result = int;
constexpr int NVSDK_NGX_Result_Success=0, NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2, NVSDK_NGX_Result_FAIL_NotInitialized=-7;
constexpr int nativeFallback=77, replacement=88;
enum NVSDK_NGX_Feature { NVSDK_NGX_Feature_SuperSampling, NVSDK_NGX_Feature_RayReconstruction, NVSDK_NGX_Feature_FrameGeneration };
enum class FGInput { NvngxFG, Other };
enum class FGNvngxReplacement { None, Nukems };
struct State {
 std::atomic<FGNvngxReplacement> activeFgNvngx { FGNvngxReplacement::Nukems };
 FGInput activeFgInput = FGInput::NvngxFG;
 static State& Instance() { static State s; return s; }
};
struct Config { static Config* Instance() { static Config c; return &c; } };
struct ID3D12Device {};
struct ID3D12GraphicsCommandList {};
using VkDevice=void*; using VkCommandBuffer=void*; using VkInstance=void*; using VkPhysicalDevice=void*;
struct VkExtensionProperties {};
struct NVSDK_NGX_Parameter {};
struct NVSDK_NGX_Handle { unsigned Id; } handle { 12 };
struct NVSDK_NGX_FeatureDiscoveryInfo { NVSDK_NGX_Feature FeatureID; };
constexpr int NVSDK_NGX_FeatureSupportResult_Supported=1;
struct NVSDK_NGX_FeatureRequirement { int FeatureSupported=0; int MinHWArchitecture=0; char MinOSVersion[64] {}; };

std::unordered_map<unsigned, NVSDK_NGX_Feature> HandleToFeature;
struct Provider {
 bool isDx12Available() { return true; }
 bool isVulkanAvailable() { return true; }
 inline static int shutdowns=0;
 inline static void* lastDevice=nullptr;
 int D3D12_Shutdown() { ++shutdowns; return 0; }
 int VULKAN_Shutdown() { ++shutdowns; return 0; }
 int D3D12_Shutdown1(ID3D12Device* d) { ++shutdowns; lastDevice=d; return 0; }
 int VULKAN_Shutdown1(VkDevice d) { ++shutdowns; lastDevice=d; return 0; }
};
struct Nvngx_FG {
 inline static ProviderPublication<Provider> _provider;
 inline static ProviderCallAdmission _calls;
 inline static std::unordered_set<ID3D12Device*> _dx12InitAttempts;
 inline static std::unordered_set<VkDevice> _vulkanInitAttempts;
 // ACTUAL_SHUTDOWN_COORDINATORS
 inline static ProviderStatus status=ProviderStatus::Pending;
 inline static int queries=0, creates=0, lazyLoads=0;
 static ProviderStatus D3D12_ProviderStatus() { ++queries; return status; }
 static ProviderStatus VULKAN_ProviderStatus() { ++queries; return status; }
 static Provider* getProvider() { ++lazyLoads; return _provider.GetOrCreate([] { return std::make_unique<Provider>(); }).provider; }
 static int D3D12_CreateFeature(ID3D12GraphicsCommandList*, NVSDK_NGX_Feature, NVSDK_NGX_Parameter*, NVSDK_NGX_Handle** out) { ++creates; *out=&handle; return 0; }
 static int VULKAN_CreateFeature1(VkDevice, VkCommandBuffer, NVSDK_NGX_Feature, NVSDK_NGX_Parameter*, NVSDK_NGX_Handle** out) { ++creates; *out=&handle; return 0; }
 static int VULKAN_CreateFeature(VkCommandBuffer, NVSDK_NGX_Feature, NVSDK_NGX_Parameter*, NVSDK_NGX_Handle** out) { ++creates; *out=&handle; return 0; }
 static int VULKAN_GetScratchBufferSize(NVSDK_NGX_Feature, const NVSDK_NGX_Parameter*, size_t* out) { *out=123; return replacement; }
 static int D3D12_Shutdown(); static int D3D12_Shutdown1(ID3D12Device*);
 static int VULKAN_Shutdown(); static int VULKAN_Shutdown1(VkDevice);
};
'''
CHECKS = r'''
int main() {
 int checks=0;
 auto check=[&](bool ok) { if(!ok) { std::cerr << "route regression at " << checks+1 << '\n'; std::exit(2); } ++checks; };
 ID3D12Device device; ID3D12GraphicsCommandList cmd;
 // No lookup on shutdown: zero DLL construction even before the first Init.
 check(Nvngx_FG::D3D12_Shutdown()==0 && Nvngx_FG::D3D12_Shutdown1(&device)==0);
 check(Nvngx_FG::VULKAN_Shutdown()==0 && Nvngx_FG::VULKAN_Shutdown1(&device)==0);
 check(Nvngx_FG::lazyLoads==0 && Provider::shutdowns==0);
 Nvngx_FG::_provider.GetOrCreate([&] {
   check(Nvngx_FG::D3D12_Shutdown()==0 && Nvngx_FG::VULKAN_Shutdown()==0);
   check(Nvngx_FG::lazyLoads==0 && Provider::shutdowns==0);
   return std::make_unique<Provider>();
 });
 Nvngx_FG::_dx12InitAttempts.insert(&device); Nvngx_FG::_vulkanInitAttempts.insert(&device);
 check(Nvngx_FG::D3D12_Shutdown()==0 && Nvngx_FG::VULKAN_Shutdown()==0);
 Nvngx_FG::_dx12InitAttempts.insert(&device); Nvngx_FG::_vulkanInitAttempts.insert(&device);
 check(Nvngx_FG::D3D12_Shutdown1(&device)==0 && Nvngx_FG::VULKAN_Shutdown1(&device)==0);
 check(Provider::shutdowns==4 && Provider::lastDevice==&device && Nvngx_FG::lazyLoads==0);
 auto exerciseCreate=[&](auto call) {
   NVSDK_NGX_Handle* out=&handle;
   Nvngx_FG::status=ProviderStatus::Pending;
   int before=Nvngx_FG::creates;
   check(call(NVSDK_NGX_Feature_FrameGeneration,&out)==-7 && out==nullptr && Nvngx_FG::creates==before);
   check(call(NVSDK_NGX_Feature_FrameGeneration,nullptr)==-2);
   Nvngx_FG::status=ProviderStatus::Unavailable;
   check(call(NVSDK_NGX_Feature_FrameGeneration,&out)==nativeFallback && out==nullptr);
   Nvngx_FG::status=ProviderStatus::Available;
   check(call(NVSDK_NGX_Feature_FrameGeneration,&out)==0 && out==&handle && Nvngx_FG::creates==before+1);
   Nvngx_FG::status=ProviderStatus::Pending;
   before=Nvngx_FG::queries;
   check(call(NVSDK_NGX_Feature_SuperSampling,&out)==nativeFallback && out==nullptr && Nvngx_FG::queries==before);
 };
 exerciseCreate([&](auto f,auto out){ return NVSDK_NGX_D3D12_CreateFeature(&cmd,f,nullptr,out); });
 exerciseCreate([&](auto f,auto out){ return NVSDK_NGX_VULKAN_CreateFeature(&cmd,f,nullptr,out); });
 exerciseCreate([&](auto f,auto out){ return NVSDK_NGX_VULKAN_CreateFeature1(&device,&cmd,f,nullptr,out); });
 State::Instance().activeFgNvngx=FGNvngxReplacement::None;
 NVSDK_NGX_Handle* out=&handle;
 check(NVSDK_NGX_D3D12_CreateFeature(&cmd,NVSDK_NGX_Feature_FrameGeneration,nullptr,&out)==nativeFallback && !out);
 State::Instance().activeFgNvngx=FGNvngxReplacement::Nukems;
 NVSDK_NGX_FeatureDiscoveryInfo info { NVSDK_NGX_Feature_FrameGeneration };
 NVSDK_NGX_FeatureRequirement supported;
 unsigned extensionCount=37; VkExtensionProperties* properties=nullptr; size_t scratch=41;
 Nvngx_FG::status=ProviderStatus::Pending;
 check(NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements(&info,&extensionCount,&properties)==-7);
 check(NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements(nullptr,nullptr,&info,&extensionCount,&properties)==-7);
 check(NVSDK_NGX_VULKAN_GetFeatureRequirements(nullptr,nullptr,&info,&supported)==-7);
 check(NVSDK_NGX_VULKAN_GetScratchBufferSize(info.FeatureID,nullptr,&scratch)==-7 && scratch==41);
 check(extensionCount==37 && properties==nullptr && supported.FeatureSupported==0);
 Nvngx_FG::status=ProviderStatus::Available;
 check(NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements(&info,&extensionCount,&properties)==0);
 check(NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements(nullptr,nullptr,&info,&extensionCount,&properties)==0);
 check(NVSDK_NGX_VULKAN_GetFeatureRequirements(nullptr,nullptr,&info,&supported)==0 && supported.FeatureSupported==1);
 check(NVSDK_NGX_VULKAN_GetScratchBufferSize(info.FeatureID,nullptr,&scratch)==replacement && scratch==123);
 Nvngx_FG::status=ProviderStatus::Unavailable;
 check(NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements(&info,&extensionCount,&properties)==nativeFallback);
 check(NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements(nullptr,nullptr,&info,&extensionCount,&properties)==nativeFallback);
 check(NVSDK_NGX_VULKAN_GetFeatureRequirements(nullptr,nullptr,&info,&supported)==nativeFallback);
 std::cout << "PASS: " << checks << " extracted provider publication routing checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True)
    parser.add_argument('--driver')
    args=parser.parse_args()
    bodies=[]
    dx=(ROOT/'OptiScaler/inputs/NVNGX_DLSS_Dx12.cpp').read_text(encoding='utf-8')
    vk=(ROOT/'OptiScaler/inputs/NVNGX_DLSS_Vk.cpp').read_text(encoding='utf-8')
    body=function(dx,'NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_D3D12_CreateFeature(')
    bodies.append(body[:body.index('    // Native DLSS passthrough')]+f'    return nativeFallback;\n}}')
    for name in ('CreateFeature','CreateFeature1','GetFeatureInstanceExtensionRequirements','GetFeatureDeviceExtensionRequirements','GetFeatureRequirements','GetScratchBufferSize'):
        body=function(vk,'NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_VULKAN_'+name+'(')
        if name.startswith('Create'):
            body=body[:body.index('    else if (')]+'    return nativeFallback;\n}'
        elif name!='GetScratchBufferSize':
            body=body[:body.index('    if (Config::Instance()->DLSSEnabled')]+'    return nativeFallback;\n}'
        bodies.append(body)
    source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.cpp').read_text(encoding='utf-8')
    for api in ('D3D12','VULKAN'):
        for suffix in ('','1'):
            bodies.append(function(source,f'NVSDK_NGX_Result Nvngx_FG::{api}_Shutdown{suffix}('))
    with tempfile.TemporaryDirectory(prefix='aurora-publication-route-') as folder:
        path=Path(folder); cpp=path/'test.cpp'; exe=path/'test.exe'
        header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
        coordinators='\n'.join(function(header,'template <typename Callback> static NVSDK_NGX_Result '+name+'(') for name in ('WithDx12Shutdown','WithVulkanShutdown'))
        prelude=PRELUDE.replace('// ACTUAL_SHUTDOWN_COORDINATORS',coordinators)
        cpp.write_text(prelude+'\n'.join(bodies)+CHECKS,encoding='utf-8')
        cmd=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':
            cmd+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else:
            cmd+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(cmd,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__':
    main()
