"""Compile the actual shutdown bodies with counted provider/NGX stand-ins.

This checks routing, not GPU shutdown or concurrency. No production function body
is duplicated here: changes to the exported routes are taken from the source tree.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def function(source, declaration):
    start = source.index(declaration)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


PRELUDE = r'''
#include "proxies/NativeDeviceLifecycle.h"
#include "proxies/NgxInitMetadata.h"
#include <cstdlib>
#include <iostream>
#include <string>
#define NVSDK_NGX_API
#define LOG_FUNC(...)
#define LOG_INFO(...)
#define LOG_DEBUG(...)
using NVSDK_NGX_Result=int; using UINT=unsigned;
constexpr int NVSDK_NGX_Result_Success=0, NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2, NVSDK_NGX_Result_FAIL_NotInitialized=-7;
struct ID3D12Device {};
using VkDevice=void*; using VkInstance=void*; using VkPhysicalDevice=void*;
using PFN_vkGetInstanceProcAddr=void*; using PFN_vkGetDeviceProcAddr=void*;
struct NVSDK_NGX_FeatureCommonInfo {};
enum class FGNvngxReplacement { None, Nukems };
enum class FGInput { Upscaler };
enum class API { DX12, Vulkan };
bool shutdown=false;
ID3D12Device* D3D12Device=nullptr;
void* vkInstance=nullptr; void* vkPD=nullptr; VkDevice vkDevice=nullptr;
struct FG { int cleanups=0; void Shutdown() { ++cleanups; } void DestroyFGContext() { ++cleanups; } } fg;
struct State {
 bool nvngxDx12Inited=true,nvngxVkInited=true,isShuttingDown=false,clearCapturedHudlesses=false;
 void* currentFeature=nullptr; FG* currentFG=&fg; API api=API::DX12;
 FGInput activeFgInput=FGInput::Upscaler;
 FGNvngxReplacement activeFgNvngx=FGNvngxReplacement::Nukems;
 NgxInitMetadata<int,int,int> NVNGX_Init{0,0};
 static State& Instance() { static State s; return s; }
};
int initCalls=0,initResult=0,globalDx=0,deviceDx=0,globalVk=0,deviceVk=0,nativeResult=0;
void* lastDevice=nullptr;
struct InitExport {
 bool operator!=(std::nullptr_t) const { return true; }
 template<class... Args> int operator()(Args...) const { ++initCalls; return initResult; }
};
int closeDx() { ++globalDx; lastDevice=nullptr; return nativeResult; }
int closeDx1(ID3D12Device* d) { ++deviceDx; lastDevice=d; return nativeResult; }
int closeVk() { ++globalVk; lastDevice=nullptr; return nativeResult; }
int closeVk1(VkDevice d) { ++deviceVk; lastDevice=d; return nativeResult; }
struct Module {
 void* dll=reinterpret_cast<void*>(1);
 InitExport D3D12_Init_ProjectID,D3D12_Init_Ext,VULKAN_Init_ProjectID,VULKAN_Init_Ext;
 int (*D3D12_Shutdown)()=&closeDx; int (*D3D12_Shutdown1)(ID3D12Device*)=&closeDx1;
 int (*VULKAN_Shutdown)()=&closeVk; int (*VULKAN_Shutdown1)(VkDevice)=&closeVk1;
};
struct Nvngx_FG {
 inline static int globalDx=0,deviceDx=0,globalVk=0,deviceVk=0;
 static int D3D12_Shutdown() { ++globalDx; return 0; }
 static int D3D12_Shutdown1(ID3D12Device*) { ++deviceDx; return 0; }
 static int VULKAN_Shutdown() { ++globalVk; return 0; }
 static int VULKAN_Shutdown1(VkDevice) { ++deviceVk; return 0; }
};
struct DLSSFeatureDx12 {
 inline static bool _dlssInitedDx12=true;
 static void ResetAfterNativeShutdown();
};
'''

CHECKS = r'''
int main() {
 int checks=0; auto check=[&](bool ok) { if(!ok) { std::cerr << "native route regression at " << checks+1 << '\n'; std::exit(2); } ++checks; };
 ID3D12Device a,b; int feature=1;
 auto& state=State::Instance();
 check(NVSDK_NGX_D3D12_Shutdown()==0 && globalDx==0 && deviceDx==0);
 initResult=-4;
 check(!NVNGXProxy::InitVulkan(nullptr,nullptr,&a,nullptr,nullptr));
 check(!NVNGXProxy::IsVulkanInited());
 check(!NVNGXProxy::InitDx12(&a) && !NVNGXProxy::IsDx12Inited());
 initResult=0;
 check(NVNGXProxy::InitDx12(&a) && NVNGXProxy::InitDx12(&b));
 check(NVNGXProxy::InitVulkan(nullptr,nullptr,&a,nullptr,nullptr));
 int before=initCalls;
 check(NVNGXProxy::InitDx12(&a) && NVNGXProxy::InitVulkan(nullptr,nullptr,&a,nullptr,nullptr) && initCalls==before);
 D3D12Device=&a; state.nvngxDx12Inited=true; state.currentFeature=&feature; state.api=API::DX12; fg.cleanups=0;
 before=Nvngx_FG::deviceDx;
 check(NVSDK_NGX_D3D12_Shutdown1(&b)==0 && deviceDx==1 && globalDx==0 && lastDevice==&b);
 check(Nvngx_FG::deviceDx==before+1 && Nvngx_FG::globalDx==1);
 check(D3D12Device==&a && state.nvngxDx12Inited && state.currentFeature==&feature && fg.cleanups==0);
 check(NVNGXProxy::IsDx12DeviceInited(&a) && !NVNGXProxy::IsDx12DeviceInited(&b));
 check(NVNGXProxy::IsVulkanDeviceInited(&a));
 nativeResult=-4; before=Nvngx_FG::deviceDx;
 check(NVSDK_NGX_D3D12_Shutdown1(&a)==-4);
 check(NVNGXProxy::IsDx12DeviceInited(&a) && D3D12Device==&a && state.nvngxDx12Inited);
 check(state.currentFeature==&feature && fg.cleanups==0 && Nvngx_FG::deviceDx==before && !shutdown);
 nativeResult=0; NVNGXProxy::_module.D3D12_Shutdown1=nullptr;
 check(NVSDK_NGX_D3D12_Shutdown1(&a)==-1 && globalDx==0);
 check(NVNGXProxy::IsDx12DeviceInited(&a) && state.currentFeature==&feature);
 NVNGXProxy::_module.D3D12_Shutdown1=&closeDx1;
 check(NVSDK_NGX_D3D12_Shutdown1(&a)==0 && lastDevice==&a && globalDx==0);
 check(!NVNGXProxy::IsDx12Inited() && !D3D12Device && !state.nvngxDx12Inited && !state.currentFeature);
 check(fg.cleanups==1 && !DLSSFeatureDx12::_dlssInitedDx12 && !shutdown);
 before=deviceDx;
 check(NVSDK_NGX_D3D12_Shutdown1(&a)==0 && deviceDx==before);
 check(NVNGXProxy::InitDx12(&a) && NVNGXProxy::InitDx12(&b));
 NVNGXProxy::_module.D3D12_Shutdown=nullptr;
 check(NVSDK_NGX_D3D12_Shutdown()==0 && deviceDx==before+1 && !lastDevice);
 check(!NVNGXProxy::IsDx12DeviceInited(&a) && !NVNGXProxy::IsDx12DeviceInited(&b));
 check(NVNGXProxy::IsVulkanDeviceInited(&a));
 NVNGXProxy::_module.D3D12_Shutdown=&closeDx;
 check(NVNGXProxy::InitDx12(&a));
 check(NVSDK_NGX_D3D12_Shutdown1(nullptr)==0 && globalDx==1 && !NVNGXProxy::IsDx12Inited());

 check(NVNGXProxy::InitVulkan(nullptr,nullptr,&b,nullptr,nullptr));
 vkDevice=&a; vkInstance=&a; vkPD=&a; state.nvngxVkInited=true; state.currentFeature=&feature; state.api=API::Vulkan;
 check(NVSDK_NGX_VULKAN_Shutdown1(&b)==0 && deviceVk==1 && globalVk==0 && lastDevice==&b);
 check(vkDevice==&a && vkInstance==&a && vkPD==&a && state.nvngxVkInited && state.currentFeature==&feature);
 nativeResult=-4; before=Nvngx_FG::deviceVk;
 check(NVSDK_NGX_VULKAN_Shutdown1(&a)==-4);
 check(NVNGXProxy::IsVulkanDeviceInited(&a) && Nvngx_FG::deviceVk==before && vkDevice==&a);
 nativeResult=0; NVNGXProxy::_module.VULKAN_Shutdown1=nullptr;
 check(NVSDK_NGX_VULKAN_Shutdown1(&a)==-1 && globalVk==0 && NVNGXProxy::IsVulkanDeviceInited(&a));
 NVNGXProxy::_module.VULKAN_Shutdown1=&closeVk1;
 state.api=API::DX12;
 check(NVSDK_NGX_VULKAN_Shutdown1(&a)==0 && lastDevice==&a && globalVk==0);
 check(!vkDevice && !vkInstance && !vkPD && !state.nvngxVkInited);
 check(state.currentFeature==&feature); // Do not clear a feature owned by the other API.
 check(NVNGXProxy::InitVulkan(nullptr,nullptr,&a,nullptr,nullptr));
 NVNGXProxy::_module.VULKAN_Shutdown=nullptr; before=deviceVk;
 check(NVSDK_NGX_VULKAN_Shutdown()==0 && deviceVk==before+1 && !lastDevice);
 check(!NVNGXProxy::IsVulkanInited());
 NVNGXProxy::_module.VULKAN_Shutdown=&closeVk;
 check(NVNGXProxy::InitVulkan(nullptr,nullptr,&a,nullptr,nullptr));
 check(NVSDK_NGX_VULKAN_Shutdown1(nullptr)==0 && globalVk==1);
 // Existing process-exit workaround still skips native D3D12 calls.
 check(NVNGXProxy::InitDx12(&a)); D3D12Device=&a; state.isShuttingDown=true; before=globalDx;
 check(NVSDK_NGX_D3D12_Shutdown()==0 && globalDx==before && NVNGXProxy::IsDx12DeviceInited(&a));
 std::cout << "PASS: " << checks << " native shutdown routing checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--compiler',required=True); parser.add_argument('--driver'); args=parser.parse_args()
    proxy=(ROOT/'OptiScaler/proxies/NVNGX_Proxy.h').read_text(encoding='utf-8')
    methods=[]
    for api in ('Dx12','Vulkan'):
        for declaration in (f'static bool Init{api}(',
                            f'template <typename Callback> static NVSDK_NGX_Result Run{api}Init(',
                            f'static bool Is{api}DeviceInited(',f'static bool Is{api}Inited(',
                            f'static NVSDK_NGX_Result Shutdown{api}('):
            methods.append(function(proxy,declaration))
    cls='''struct NVNGXProxy {
 inline static NativeDeviceLifecycle _dx12Devices,_vulkanDevices;
 inline static Module _module;
 static const Module& GetModule() { return _module; }
 static void InitNVNGX() {}
 static std::nullptr_t GetFeatureCommonInfo(NVSDK_NGX_FeatureCommonInfo*) { return nullptr; }
'''+ '\n'.join(methods)+'\n};\n'
    source=(ROOT/'OptiScaler/upscalers/dlss/DLSSFeature_Dx12.cpp').read_text(encoding='utf-8')
    bodies=[function(source,'void DLSSFeatureDx12::ResetAfterNativeShutdown(')]
    for api,filename,cleanup in (('D3D12','Dx12','ShutdownD3D12'),('VULKAN','Vk','ShutdownVulkan')):
        source=(ROOT/f'OptiScaler/inputs/NVNGX_DLSS_{filename}.cpp').read_text(encoding='utf-8')
        for declaration in (f'static NVSDK_NGX_Result {cleanup}(',
                            f'NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_{api}_Shutdown(',
                            f'NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_{api}_Shutdown1('):
            bodies.append(function(source,declaration))
    with tempfile.TemporaryDirectory(prefix='aurora-native-shutdown-') as folder:
        path=Path(folder); cpp=path/'test.cpp'; exe=path/'test.exe'
        cpp.write_text(PRELUDE+cls+'\n'.join(bodies)+CHECKS,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else: command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
