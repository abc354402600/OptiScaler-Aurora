"""Execute complete exported/private Init chains with counted SDK/state stand-ins."""
from pathlib import Path
import argparse,re,subprocess,tempfile
from test_shutdown_routing import function
ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "proxies/NgxExportLifecycle.h"
#include "proxies/NativeDeviceLifecycle.h"
#include "proxies/NgxInitValidation.h"
#include "proxies/NgxInitMetadata.h"
#include "proxies/NgxPathSnapshot.h"
#include <functional>
#include <source_location>
#include <cstring>
#include <memory>
#include <cstdlib>
#include <iostream>
#include <vector>
#include <unordered_set>
#define NVSDK_NGX_API
#define LOG_FUNC(...)
#define LOG_INFO(...)
#define LOG_WARN(...)
#define LOG_DEBUG(...)
using NVSDK_NGX_Result=int;using NVSDK_NGX_Version=int;using NVSDK_NGX_EngineType=int;
using VkInstance=void*;using VkPhysicalDevice=void*;using VkDevice=void*;
using PFN_vkGetInstanceProcAddr=void*;using PFN_vkGetDeviceProcAddr=void*;
struct ID3D11Device{};struct ID3D12Device{};struct NVSDK_NGX_FeatureCommonInfo{int LoggingInfo=0;struct {const wchar_t* const* Path=nullptr;unsigned Length=0;} PathListInfo;};
constexpr int NVSDK_NGX_Result_FAIL_NotInitialized=-7,NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_FAIL_InvalidParameter=-2;
constexpr int app_id_override=12;const char* project_id_override="override";
void* vkGetInstanceProcAddr=nullptr;void* vkGetDeviceProcAddr=nullptr;
int checks=0,nativeCalls=0,providerCalls=0,pathWrites=0,metadataWrites=0,projectWrites=0,nativeResult=0,providerResult=0;
std::function<void()> onNative,onProvider;int throwStage=0;
void check(bool b,std::source_location loc=std::source_location::current()){if(!b){std::cerr<<"Init chain check "<<checks+1<<" failed at generated line "<<loc.line()<<"\n";std::exit(2);}++checks;}
NgxPathSnapshot::Owner UpdateInitPaths(NVSDK_NGX_FeatureCommonInfo*);
enum class FGNvngxReplacement{None,Yes};enum class FGInput{NvngxFG};
struct Metadata : NgxInitMetadata<int,int,int>{
 Metadata():NgxInitMetadata(0,0){}
 template<class...A>void UpdateApplication(A...a){++metadataWrites;NgxInitMetadata::UpdateApplication(a...);if(throwStage==2)throw 88;}
 template<class...A>void UpdateProject(A...a){++metadataWrites;++projectWrites;NgxInitMetadata::UpdateProject(a...);if(throwStage==4)throw 88;}
 template<class...A>void UpdateLogging(A...a){++metadataWrites;NgxInitMetadata::UpdateLogging(a...);if(throwStage==3)throw 88;}
};
struct State{
 NgxPathCache NVNGX_FeatureInfo_Paths;Metadata NVNGX_Init;bool nvngxDx11Inited=false,nvngxDx12Inited=false,nvngxVkInited=false;
 ID3D11Device* currentD3D11Device=nullptr;ID3D12Device* currentD3D12Device=nullptr;VkDevice currentVkDevice=nullptr;
 FGNvngxReplacement activeFgNvngx=FGNvngxReplacement::Yes;FGInput activeFgInput=FGInput::NvngxFG;
 static State& Instance(){static State s;return s;}
};
NgxPathSnapshot::Owner UpdateInitPaths(NVSDK_NGX_FeatureCommonInfo*){++pathWrites;auto result=State::Instance().NVNGX_FeatureInfo_Paths.Publish({L"new path"});if(throwStage==1)throw 88;return result;}
struct StateView {bool nvngxDx11Inited,nvngxDx12Inited,nvngxVkInited;ID3D11Device* currentD3D11Device;ID3D12Device* currentD3D12Device;VkDevice currentVkDevice;};
StateView ReadState(){auto& s=State::Instance();return {s.nvngxDx11Inited,s.nvngxDx12Inited,s.nvngxVkInited,s.currentD3D11Device,s.currentD3D12Device,s.currentVkDevice};}
struct Option{bool v;bool value_or_default(){return v;}};
struct Config{Option DLSSEnabled{true},UseGenericAppIdWithDlss{false};static Config* Instance(){static Config c;return &c;}};
struct D3D12Hooks{static void HookDevice(ID3D12Device*){}};
struct UpscalerInputsDx12{static void Init(ID3D12Device*){}};
struct UpscalerTimeVk{static void Init(VkDevice,VkPhysicalDevice){}};
struct NativeCall{
 bool operator!=(std::nullptr_t)const{return true;}
 template<class...A>int operator()(A...){++nativeCalls;if(onNative)onNative();return nativeResult;}
};
struct NVNGXProxy{
 inline static NativeDeviceLifecycle _dx12Devices,_vulkanDevices;
 inline static bool useNativeLedger=false;
 static void* NVNGXModule(){return reinterpret_cast<void*>(1);}static void InitNVNGX(){}static void SetDx11Inited(bool){}
 template<class D,class C>static int RunDx12Init(D d,C c){return useNativeLedger?_dx12Devices.Initialize(d,0,-2,-7,c):c();}
 template<class D,class C>static int RunVulkanInit(D d,C c){return useNativeLedger?_vulkanDevices.Initialize(d,0,-2,-7,c):c();}
 // COMPLETION_HELPERS
 // NATIVE_GETTERS
};
struct Nvngx_FG{
 inline static bool useLedger=false;
 inline static int ledgerDevice=0;
 inline static std::unordered_set<int*> attempts,ready;
 // LEDGER_HELPER
 // PROVIDER_METHODS
};
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver');parser.add_argument('--negative-control',choices=['no-path-validation','no-configuration-rollback']);args=parser.parse_args()
    cpp=PRELUDE;routes=[];path_routes=[];invalid_routes=[];failed_project_routes=[];provider_routes=[];other_device_routes=[];allsource=''
    for api in ('Dx11','Dx12','Vk'):
        source=(ROOT/f'OptiScaler/inputs/NVNGX_DLSS_{api}.cpp').read_text(encoding='utf-8');allsource+=source
        cpp+='\nnamespace '+api+'{\n'
        cpp+=('ID3D11Device* D3D11Device=nullptr;\n' if api=='Dx11' else 'ID3D12Device* D3D12Device=nullptr;\n' if api=='Dx12' else 'VkInstance vkInstance=nullptr;VkPhysicalDevice vkPD=nullptr;VkDevice vkDevice=nullptr;PFN_vkGetInstanceProcAddr vkGIPA=nullptr;PFN_vkGetDeviceProcAddr vkGDPA=nullptr;\n')
        for m in re.finditer(r'NVSDK_NGX_API NVSDK_NGX_Result\s+(NVSDK_NGX_\w+_Init\w*)\(',source):
            name=m.group(1);wrapper=function(source,m.group(0));core=function(source,'static NVSDK_NGX_Result NgxCore_'+name.removeprefix('NVSDK_NGX_')+'(')
            if args.negative_control=='no-configuration-rollback':
                wrapper,count=re.subn(r'NgxExportLifecycle::RunInitialization\(\s*NVSDK_NGX_Result_FAIL_NotInitialized,\s*NVSDK_NGX_Result_Success,\s*State::Instance\(\).NVNGX_Init,\s*State::Instance\(\).NVNGX_FeatureInfo_Paths,', 'NgxExportLifecycle::Run(NVSDK_NGX_Result_FAIL_NotInitialized,',wrapper)
                assert count==1, 'negative control must change every Init wrapper'
            if args.negative_control=='no-path-validation':core=core.replace(' || !ValidNgxInitPaths(InFeatureInfo)','')
            cpp+=core+'\n'+wrapper+'\n'
            signature=wrapper[:wrapper.index('{')];params=signature[signature.index('(')+1:signature.rfind(')')].split(',');values=[]
            for param in params:
                if 'InDevice' in param:values.append('&dx11' if api=='Dx11' else '&dx12' if api=='Dx12' else '&vk')
                elif 'wchar_t' in param:values.append('L"data"')
                elif 'char*' in param:values.append('"project"')
                elif '*' in param or re.search(r'\b(Vk\w+|PFN_\w+)\b',param):values.append('nullptr')
                else:values.append('32')
            routes.append('[&]{return '+api+'::'+name+'('+','.join(values)+');}')
            path_values=['&featureInfo' if 'InFeatureInfo' in param else value for param,value in zip(params,values)]
            path_routes.append('[&]{return '+api+'::'+name+'('+','.join(path_values)+');}')
            invalid=[('nullptr' if v in ('&dx11','&dx12','&vk') else v) for v in values]
            invalid_routes.append('[&]{return '+api+'::'+name+'('+','.join(invalid)+');}')
            if api!='Dx11':
                provider_routes.append(len(routes)-1)
                second=[v.replace('&dx12','&otherDx12').replace('&vk','&otherVk') for v in values]
                other_device_routes.append('[&]{return '+api+'::'+name+'('+','.join(second)+');}')
            if api!='Dx11' and 'ProjectID' in name:failed_project_routes.append(len(routes)-1)
        cpp+='}\n'
    native=sorted(set(re.findall(r'NVNGXProxy::((?:D3D11|D3D12|VULKAN)_Init\w*)\(',allsource)))
    provider=sorted(set(re.findall(r'Nvngx_FG::((?:D3D12|VULKAN)_Init\w*)\(',allsource)))
    cpp=cpp.replace('// NATIVE_GETTERS','\n'.join('static NativeCall '+n+'(){return {};}' for n in native))
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    proxy=(ROOT/'OptiScaler/proxies/NVNGX_Proxy.h').read_text(encoding='utf-8')
    cpp=cpp.replace('// COMPLETION_HELPERS','\n'.join(function(proxy,'template <typename Callback> static NVSDK_NGX_Result Complete'+api+'ProviderInit(') for api in ('Dx12','Vulkan')))
    cpp=cpp.replace('// LEDGER_HELPER',function(header,'template <typename Device, typename Callback>'))
    cpp=cpp.replace('// PROVIDER_METHODS','\n'.join('template<class...A>static int '+n+'(A...){auto call=[] {++providerCalls;if(onProvider)onProvider();return providerResult;};if(useLedger)return InitializeProvider(attempts,ready,&ledgerDevice,call);return call();}' for n in provider))
    cpp+='int main(){NVSDK_NGX_FeatureCommonInfo featureInfo;ID3D11Device dx11;ID3D12Device dx12,otherDx12;int vk,otherVk;std::vector<std::function<int()>> routes={'+','.join(routes)+'};\n'
    cpp+='std::vector<std::function<int()>> pathRoutes={'+','.join(path_routes)+'};\n'
    cpp+='std::vector<std::function<int()>> invalidRoutes={'+','.join(invalid_routes)+'};\n'
    cpp+='std::vector<int> failedProjectRoutes={'+','.join(map(str,failed_project_routes))+'};\n'
    cpp+='std::vector<int> providerRoutes={'+','.join(map(str,provider_routes))+'};std::vector<std::function<int()>> otherDeviceRoutes={'+','.join(other_device_routes)+'};\n'
    cpp+=r'''
 auto reset=[] {auto& s=State::Instance();s.nvngxDx11Inited=s.nvngxDx12Inited=s.nvngxVkInited=false;s.currentD3D11Device=nullptr;s.currentD3D12Device=nullptr;s.currentVkDevice=nullptr;s.activeFgNvngx=FGNvngxReplacement::Yes;s.activeFgInput=FGInput::NvngxFG;Dx11::D3D11Device=nullptr;Dx12::D3D12Device=nullptr;Vk::vkInstance=nullptr;Vk::vkPD=nullptr;Vk::vkDevice=nullptr;};
 for(auto& route:routes){
  reset();int before=nativeCalls,paths=pathWrites;
  check(route()==0&&nativeCalls==before+1&&pathWrites==paths+1);
  // Exercise nested exports from both actual native-call and delegated provider phases.
  auto nested=[&]{int native=nativeCalls,provider=providerCalls,path=pathWrites,meta=metadataWrites;
    auto snapshot=State::Instance().NVNGX_Init.Read();auto paths=State::Instance().NVNGX_FeatureInfo_Paths.Read();
    for(auto& other:routes)check(other()==-7);
    check(native==nativeCalls&&provider==providerCalls&&path==pathWrites&&meta==metadataWrites);
    check(State::Instance().NVNGX_Init.Read()==snapshot&&State::Instance().NVNGX_FeatureInfo_Paths.Read()==paths);
  };
  reset();onNative=nested;onProvider=nested;before=nativeCalls;paths=pathWrites;
  check(route()==0&&nativeCalls==before+1&&pathWrites==paths+1);onNative={};onProvider={};
  reset();bool threw=false;onNative=[]{throw 17;};
  try{route();}catch(int){threw=true;}onNative={};check(threw);reset();check(route()==0);
 }


 // Malformed path arrays must reject before all writes, including repeat Init.
 const wchar_t* validPaths[]={L"C:\\游戏 空格",L""};
 const wchar_t* nullFirst[]={nullptr,L"ok"};
 const wchar_t* nullLast[]={L"ok",nullptr};
 for(size_t i=0;i<pathRoutes.size();++i) {
  for(bool alreadyReady:{false,true}) {
   for(int malformed=0;malformed<3;++malformed) {
    reset();if(alreadyReady)check(routes[i]()==0);
    auto previous=ReadState();
    auto d11=Dx11::D3D11Device;auto d12=Dx12::D3D12Device;auto vd=Vk::vkDevice;
    int native=nativeCalls,provider=providerCalls,paths=pathWrites,metadata=metadataWrites;
    featureInfo.PathListInfo={malformed==0?nullptr:malformed==1?nullFirst:nullLast,2};
    check(pathRoutes[i]()==-2);
    check(nativeCalls==native&&providerCalls==provider&&pathWrites==paths&&metadataWrites==metadata);
    check(State::Instance().nvngxDx11Inited==previous.nvngxDx11Inited&&State::Instance().nvngxDx12Inited==previous.nvngxDx12Inited&&State::Instance().nvngxVkInited==previous.nvngxVkInited);
    check(State::Instance().currentD3D11Device==previous.currentD3D11Device&&State::Instance().currentD3D12Device==previous.currentD3D12Device&&State::Instance().currentVkDevice==previous.currentVkDevice);
    check(d11==Dx11::D3D11Device&&d12==Dx12::D3D12Device&&vd==Vk::vkDevice);
    featureInfo.PathListInfo={validPaths,2};check(pathRoutes[i]()==0);
   }
  }
  // Empty arrays may have a null array pointer; empty strings are not rejected.
  for(int empty=0;empty<2;++empty){reset();featureInfo.PathListInfo={empty?nullFirst:nullptr,0};check(pathRoutes[i]()==0);}
 }

 // Reject null devices before path/metadata publication, SDK calls or local state changes.
 for(size_t i=0;i<routes.size();++i) {
  for(bool alreadyReady:{false,true}) {
   reset(); if(alreadyReady)check(routes[i]()==0);
   auto previous=ReadState();
   int native=nativeCalls,provider=providerCalls,paths=pathWrites,metadata=metadataWrites;
   check(invalidRoutes[i]()==-2);
   check(nativeCalls==native&&providerCalls==provider&&pathWrites==paths&&metadataWrites==metadata);
   check(State::Instance().nvngxDx11Inited==previous.nvngxDx11Inited&&State::Instance().nvngxDx12Inited==previous.nvngxDx12Inited&&State::Instance().nvngxVkInited==previous.nvngxVkInited);
   check(State::Instance().currentD3D11Device==previous.currentD3D11Device&&State::Instance().currentD3D12Device==previous.currentD3D12Device&&State::Instance().currentVkDevice==previous.currentVkDevice);
   check(routes[i]()==0);
  }
 }

 // A rejected native/provider phase must not commit the ProjectID afterward.
 for(int index:failedProjectRoutes){
  for(bool failNative:{false,true}){
   reset();int projects=projectWrites;
   nativeResult=failNative?-7:0;providerResult=failNative?0:-7;
   check(routes[index]()==-7);
   check(projectWrites==projects&&!State::Instance().nvngxVkInited&&!State::Instance().nvngxDx12Inited);
   nativeResult=providerResult=0;reset();
   check(routes[index]()==0&&projectWrites==projects+1);
  }
 }

 // Native/provider exceptions must not commit the requested project either.
 for(int index:failedProjectRoutes){
  for(bool throwNative:{false,true}){
   reset();int projects=projectWrites;bool threw=false;
   if(throwNative)onNative=[]{throw 73;};else onProvider=[]{throw 73;};
   try{routes[index]();}catch(int e){threw=e==73;}
   onNative={};onProvider={};
   check(threw&&projectWrites==projects);
   check(routes[index]()==0&&projectWrites==projects+1);
  }
 }

 // Existing global flags do not establish selected provider readiness.
 for(size_t i=0;i<providerRoutes.size();++i){
  auto& route=routes[providerRoutes[i]];reset();providerResult=0;check(route()==0);
  int before=providerCalls;providerResult=-7;
  check(route()==-7&&providerCalls>before);
  // An optional unavailable backend still follows the existing fallback policy.
  providerResult=-1;check(route()==0);
  providerResult=0;check(route()==0);
  check(otherDeviceRoutes[i]()==0);
  if(providerRoutes[i]<8)check(State::Instance().currentD3D12Device==&otherDx12&&Dx12::D3D12Device==&otherDx12);
  else check(State::Instance().currentVkDevice==&otherVk&&Vk::vkDevice==&otherVk);
 }
 // Explicitly disabled D3D12 replacement must not become a required provider.
 reset();State::Instance().activeFgNvngx=FGNvngxReplacement::None;providerResult=-7;
 int before=providerCalls;check(routes[4]()==0&&routes[4]()==0&&providerCalls==before);
 providerResult=0;
 // Actual ledger + actual exported cores: entered provider failure is not
 // optional unavailability. Each route starts with isolated test bookkeeping.
 Nvngx_FG::useLedger=true;
 for(int index:providerRoutes)for(int failure:{-1,-8}) {
  reset();Nvngx_FG::attempts.clear();Nvngx_FG::ready.clear();
  providerResult=failure;int projects=projectWrites,before=providerCalls;
  check(routes[index]()==-7);
  check(providerCalls==before+1&&Nvngx_FG::attempts.size()==1&&Nvngx_FG::ready.empty());
  check(!State::Instance().nvngxDx12Inited&&!State::Instance().nvngxVkInited&&projectWrites==projects);
  providerResult=0;check(routes[index]()==-7&&providerCalls==before+1);
  // Simulate completed provider cleanup; actual cleanup is tested separately.
  Nvngx_FG::attempts.clear();Nvngx_FG::ready.clear();
  check(routes[index]()==0&&Nvngx_FG::ready.size()==1);
 }
 // Complete cores + native lifecycle + provider ledger in one executable.

 Nvngx_FG::useLedger=false;
 // Actual storage + outer transaction: restore owner identity on failure/throw,
 // retain candidate storage on success, and preserve readers of either generation.
 for(size_t i=0;i<routes.size();++i) {
  for(bool hadPaths:{false,true}) {
   reset();auto& state=State::Instance();
   state.NVNGX_Init.UpdateApplication(987,L"previous",123);
   auto beforeMeta=state.NVNGX_Init.Read();
   auto beforePaths=hadPaths?state.NVNGX_FeatureInfo_Paths.Publish({L"previous path"}):NgxPathSnapshot::Owner{};
   state.NVNGX_FeatureInfo_Paths.Restore(beforePaths);
   NgxPathSnapshot::Owner candidate;
   onNative=[&]{candidate=state.NVNGX_FeatureInfo_Paths.Read();check(candidate&&candidate!=beforePaths);throw 88;};
   bool threw=false;try{routes[i]();}catch(int e){threw=e==88;}onNative={};
   check(threw&&state.NVNGX_Init.Read()==beforeMeta&&state.NVNGX_FeatureInfo_Paths.Read()==beforePaths);
   check(candidate->Strings()[0]==L"new path"&&beforeMeta->ApplicationId==987);
   check(routes[i]()==0&&state.NVNGX_Init.Read()!=beforeMeta&&state.NVNGX_FeatureInfo_Paths.Read()!=beforePaths);
  }
  for(int stage:{1,2,3,4}) {
   // Logging requires feature info; not every route publishes a project.
   if(stage==4&&(i<2||i==4||i==5||i==8||i==9||i==11))continue;
   reset();featureInfo.PathListInfo={};
   auto meta=State::Instance().NVNGX_Init.Read();auto paths=State::Instance().NVNGX_FeatureInfo_Paths.Read();
   throwStage=stage;bool threw=false;try{pathRoutes[i]();}catch(int e){threw=e==88;}throwStage=0;
   if(!threw)std::cerr<<"Missing injected failure route "<<i<<" stage "<<stage<<"\n";
   check(threw&&State::Instance().NVNGX_Init.Read()==meta&&State::Instance().NVNGX_FeatureInfo_Paths.Read()==paths);
   check(pathRoutes[i]()==0);
  }
 }
 for(int index:providerRoutes){
  reset();auto meta=State::Instance().NVNGX_Init.Read();auto paths=State::Instance().NVNGX_FeatureInfo_Paths.Read();
  nativeResult=-7;check(routes[index]()==-7);nativeResult=0;
  check(State::Instance().NVNGX_Init.Read()==meta&&State::Instance().NVNGX_FeatureInfo_Paths.Read()==paths);
  providerResult=-7;check(routes[index]()==-7);providerResult=0;
  check(State::Instance().NVNGX_Init.Read()==meta&&State::Instance().NVNGX_FeatureInfo_Paths.Read()==paths);
 }

 // Native SDK/close and provider SDK/close remain deterministic stand-ins.
 Nvngx_FG::useLedger=true;NVNGXProxy::useNativeLedger=true;
 for(int index:providerRoutes)for(bool throws:{false,true}){
  reset();Nvngx_FG::attempts.clear();Nvngx_FG::ready.clear();
  NVNGXProxy::_dx12Devices.Shutdown(nullptr,0,-7,[]{return 0;});
  NVNGXProxy::_vulkanDevices.Shutdown(nullptr,0,-7,[]{return 0;});
  auto& native=index<8?NVNGXProxy::_dx12Devices:NVNGXProxy::_vulkanDevices;
  const void* selected=index<8?static_cast<void*>(&dx12):static_cast<void*>(&vk);
  int unrelated=0;
  check(native.Initialize(&unrelated,0,-2,-7,[]{return 0;})==0);
  nativeResult=0;providerResult=-8;bool caught=false;
  if(throws)onProvider=[]{throw 91;};
  try{check(routes[index]()==-7);}catch(int e){caught=e==91;}
  onProvider={};check(caught==throws);
  check(!native.IsReady(selected)&&native.IsReady(&unrelated));
  check(native.RunOperation(-7,[]{return 0;},selected)==-7);
  check(native.RunOperation(-7,[]{return 0;})==-7);
  check(native.RunOperation(-7,[]{return 11;},&unrelated)==11);
  int before=nativeCalls,providerBefore=providerCalls;providerResult=0;
  check(routes[index]()==-7&&nativeCalls==before&&providerCalls==providerBefore);
  check(native.Shutdown(selected,0,-7,[]{return -8;})==-8&&!native.IsReady(selected));
  int closes=0;check(native.Shutdown(selected,0,-7,[&]{++closes;return 0;})==0&&closes==1);
  Nvngx_FG::attempts.clear();Nvngx_FG::ready.clear();
  check(routes[index]()==0&&native.IsReady(selected));
 }
 NVNGXProxy::useNativeLedger=false;
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
