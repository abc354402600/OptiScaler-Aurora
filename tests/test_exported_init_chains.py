"""Execute complete exported/private Init chains with counted SDK/state stand-ins."""
from pathlib import Path
import argparse,re,subprocess,tempfile
from test_shutdown_routing import function
ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "proxies/NgxExportLifecycle.h"
#include <functional>
#include <cstring>
#include <memory>
#include <cstdlib>
#include <iostream>
#include <vector>
#define NVSDK_NGX_API
#define LOG_FUNC(...)
#define LOG_INFO(...)
#define LOG_WARN(...)
#define LOG_DEBUG(...)
using NVSDK_NGX_Result=int;using NVSDK_NGX_Version=int;using NVSDK_NGX_EngineType=int;
using VkInstance=void*;using VkPhysicalDevice=void*;using VkDevice=void*;
using PFN_vkGetInstanceProcAddr=void*;using PFN_vkGetDeviceProcAddr=void*;
struct ID3D11Device{};struct ID3D12Device{};struct NVSDK_NGX_FeatureCommonInfo{int LoggingInfo=0;};
constexpr int NVSDK_NGX_Result_FAIL_NotInitialized=-7,NVSDK_NGX_Result_Success=0;
constexpr int app_id_override=12;const char* project_id_override="override";
void* vkGetInstanceProcAddr=nullptr;void* vkGetDeviceProcAddr=nullptr;
int checks=0,nativeCalls=0,providerCalls=0,pathWrites=0,metadataWrites=0;
std::function<void()> onNative,onProvider;
void check(bool b){if(!b){std::cerr<<"Init chain check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct NgxPathSnapshot{using Owner=std::shared_ptr<int>;};
NgxPathSnapshot::Owner UpdateInitPaths(NVSDK_NGX_FeatureCommonInfo*){++pathWrites;return std::make_shared<int>(1);}
enum class FGNvngxReplacement{None,Yes};enum class FGInput{NvngxFG};
struct Metadata{
 template<class...A>void UpdateApplication(A...){++metadataWrites;}
 template<class...A>void UpdateProject(A...){++metadataWrites;}
 template<class...A>void UpdateLogging(A...){++metadataWrites;}
};
struct State{
 Metadata NVNGX_Init;bool nvngxDx11Inited=false,nvngxDx12Inited=false,nvngxVkInited=false;
 ID3D11Device* currentD3D11Device=nullptr;ID3D12Device* currentD3D12Device=nullptr;VkDevice currentVkDevice=nullptr;
 FGNvngxReplacement activeFgNvngx=FGNvngxReplacement::Yes;FGInput activeFgInput=FGInput::NvngxFG;
 static State& Instance(){static State s;return s;}
};
struct Option{bool v;bool value_or_default(){return v;}};
struct Config{Option DLSSEnabled{true},UseGenericAppIdWithDlss{false};static Config* Instance(){static Config c;return &c;}};
struct D3D12Hooks{static void HookDevice(ID3D12Device*){}};
struct UpscalerInputsDx12{static void Init(ID3D12Device*){}};
struct UpscalerTimeVk{static void Init(VkDevice,VkPhysicalDevice){}};
struct NativeCall{
 bool operator!=(std::nullptr_t)const{return true;}
 template<class...A>int operator()(A...){++nativeCalls;if(onNative)onNative();return 0;}
};
struct NVNGXProxy{
 static void* NVNGXModule(){return reinterpret_cast<void*>(1);}static void InitNVNGX(){}static void SetDx11Inited(bool){}
 template<class D,class C>static int RunDx12Init(D,C c){return c();}
 template<class D,class C>static int RunVulkanInit(D,C c){return c();}
 // NATIVE_GETTERS
};
struct Nvngx_FG{
 // PROVIDER_METHODS
};
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver');args=parser.parse_args()
    cpp=PRELUDE;routes=[];allsource=''
    for api in ('Dx11','Dx12','Vk'):
        source=(ROOT/f'OptiScaler/inputs/NVNGX_DLSS_{api}.cpp').read_text(encoding='utf-8');allsource+=source
        cpp+='\nnamespace '+api+'{\n'
        cpp+=('ID3D11Device* D3D11Device=nullptr;\n' if api=='Dx11' else 'ID3D12Device* D3D12Device=nullptr;\n' if api=='Dx12' else 'VkInstance vkInstance=nullptr;VkPhysicalDevice vkPD=nullptr;VkDevice vkDevice=nullptr;PFN_vkGetInstanceProcAddr vkGIPA=nullptr;PFN_vkGetDeviceProcAddr vkGDPA=nullptr;\n')
        for m in re.finditer(r'NVSDK_NGX_API NVSDK_NGX_Result\s+(NVSDK_NGX_\w+_Init\w*)\(',source):
            name=m.group(1);wrapper=function(source,m.group(0));core=function(source,'static NVSDK_NGX_Result NgxCore_'+name.removeprefix('NVSDK_NGX_')+'(')
            cpp+=core+'\n'+wrapper+'\n'
            signature=wrapper[:wrapper.index('{')];params=signature[signature.index('(')+1:signature.rfind(')')].split(',');values=[]
            for param in params:
                if 'InDevice' in param:values.append('&dx11' if api=='Dx11' else '&dx12' if api=='Dx12' else '&vk')
                elif 'wchar_t' in param:values.append('L"data"')
                elif 'char*' in param:values.append('"project"')
                elif '*' in param or re.search(r'\b(Vk\w+|PFN_\w+)\b',param):values.append('nullptr')
                else:values.append('32')
            routes.append('[&]{return '+api+'::'+name+'('+','.join(values)+');}')
        cpp+='}\n'
    native=sorted(set(re.findall(r'NVNGXProxy::((?:D3D11|D3D12|VULKAN)_Init\w*)\(',allsource)))
    provider=sorted(set(re.findall(r'Nvngx_FG::((?:D3D12|VULKAN)_Init\w*)\(',allsource)))
    cpp=cpp.replace('// NATIVE_GETTERS','\n'.join('static NativeCall '+n+'(){return {};}' for n in native))
    cpp=cpp.replace('// PROVIDER_METHODS','\n'.join('template<class...A>static int '+n+'(A...){++providerCalls;if(onProvider)onProvider();return 0;}' for n in provider))
    cpp+='int main(){ID3D11Device dx11;ID3D12Device dx12;int vk;std::vector<std::function<int()>> routes={'+','.join(routes)+'};\n'
    cpp+=r'''
 auto reset=[] {State::Instance()=State{};Dx11::D3D11Device=nullptr;Dx12::D3D12Device=nullptr;Vk::vkInstance=nullptr;Vk::vkPD=nullptr;Vk::vkDevice=nullptr;};
 for(auto& route:routes){
  reset();int before=nativeCalls,paths=pathWrites;
  check(route()==0&&nativeCalls==before+1&&pathWrites==paths+1);
  // Exercise nested exports from both actual native-call and delegated provider phases.
  auto nested=[&]{int native=nativeCalls,provider=providerCalls,path=pathWrites,meta=metadataWrites;
    for(auto& other:routes)check(other()==-7);
    check(native==nativeCalls&&provider==providerCalls&&path==pathWrites&&meta==metadataWrites);
  };
  reset();onNative=nested;onProvider=nested;before=nativeCalls;paths=pathWrites;
  check(route()==0&&nativeCalls==before+1&&pathWrites==paths+1);onNative={};onProvider={};
  reset();bool threw=false;onNative=[]{throw 17;};
  try{route();}catch(int){threw=true;}onNative={};check(threw);reset();check(route()==0);
 }
 std::cout<<"PASS: "<<checks<<" complete exported Init chain checks\n";
}
'''
    with tempfile.TemporaryDirectory(prefix='aurora-init-chain-') as directory:
        path=Path(directory);test=path/'test.cpp';exe=path/'test.exe';test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),'/Fe:'+str(exe)]
        else:command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True);subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__':main()
