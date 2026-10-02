"""Compile production metadata storage, actual proxy Init bodies and log callback."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include "proxies/NgxInitMetadata.h"
#include "proxies/NativeDeviceLifecycle.h"
#include "proxies/NgxExportLifecycle.h"
#include <atomic>
#include <future>
#include <functional>
#include <iostream>
#include <cstdlib>
#include <string_view>
#include <tuple>
#include <type_traits>
#include <vector>
#define LOG_DEBUG(...)
#define LOG_INFO(...)
#define LOG_ERROR(...)
#define NVSDK_NGX_API
using NVSDK_NGX_Result=int; using UINT=unsigned;
constexpr int NVSDK_NGX_Result_Success=0, NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2, NVSDK_NGX_Result_FAIL_NotInitialized=-7;
constexpr int NVSDK_NGX_LOGGING_LEVEL_OFF=0,NVSDK_NGX_LOGGING_LEVEL_ON=1,
 NVSDK_NGX_LOGGING_LEVEL_VERBOSE=2,NVSDK_NGX_Feature_SuperSampling=1;
struct Logging { void(*LoggingCallback)(const char*,int,int)=nullptr; int MinimumLoggingLevel=0; bool DisableOtherLoggingSinks=false; };
using Metadata=NgxInitMetadata<int,int,Logging>;
struct State {
 Metadata NVNGX_Init{0,{}};
 static State& Instance() { static State value; return value; }
};
struct Option { bool value=true; bool value_or_default() const { return value; } };
struct Config { Option LogToNGX; Option UseGenericAppIdWithDlss{false}; static Config* Instance() { static Config c; return &c; } };
namespace spdlog { namespace level { constexpr int info=2; }
 namespace details { struct log_msg { std::string_view payload; int level=2; }; } }
struct ID3D11Device {}; struct ID3D12Device {};
using VkDevice=void*; using VkInstance=void*; using VkPhysicalDevice=void*;
using PFN_vkGetInstanceProcAddr=void*; using PFN_vkGetDeviceProcAddr=void*;
struct NVSDK_NGX_FeatureCommonInfo {};
int checks=0;
void check(bool ok) { if(!ok) { std::cerr << "metadata check " << checks+1 << " failed\n"; std::exit(2); } ++checks; }
using NVSDK_NGX_Feature=int;
constexpr int NVSDK_NGX_Application_Identifier_Type_Application_Id=1, NVSDK_NGX_Application_Identifier_Type_Project_Id=2;
constexpr uint64_t app_id_override=1337; const char* project_id_override="generic";
struct NVSDK_NGX_Application_Identifier {
 int IdentifierType=1;
 struct { uint64_t ApplicationId=456; struct { const char* ProjectId="updated"; int EngineType=3; const char* EngineVersion="engine"; } ProjectDesc; } v;
};
std::function<void()> duringNative, duringPaths;
std::string seenProject,seenEngine;
std::wstring seenPath;
uint64_t seenId=0; int seenVersion=0,seenEngineType=0;
bool nativePointersStable=true;
int nativeReturn=0,sdkCalls=0;
struct InitExport {
 bool enabled=true;
 bool operator!=(std::nullptr_t) const { return enabled; }
 template<class... Args> int operator()(Args... args) const {
   ++sdkCalls;
   auto values=std::tuple{args...};
   constexpr auto count=sizeof...(Args);
   constexpr bool project=std::is_convertible_v<decltype(std::get<0>(values)),const char*>;
   if constexpr(project) {
     const char* p=std::get<0>(values); const char* e=std::get<2>(values); const wchar_t* d=std::get<3>(values);
     seenProject=p; seenEngine=e; seenPath=d; seenEngineType=std::get<1>(values); seenVersion=std::get<count-2>(values);
     if(duringNative) duringNative();
     nativePointersStable &= seenProject==p && seenEngine==e && seenPath==d;
   } else {
     const wchar_t* d=std::get<1>(values); seenId=std::get<0>(values); seenPath=d; seenVersion=std::get<count-2>(values);
     if(duringNative) duringNative();
     nativePointersStable &= seenPath==d;
   }
   return nativeReturn;
 }
};
struct Module {
 void* dll=reinterpret_cast<void*>(1);
 InitExport D3D11_Init_ProjectID,D3D11_Init_Ext,D3D12_Init_ProjectID,D3D12_Init_Ext,VULKAN_Init_ProjectID,VULKAN_Init_Ext;
};
std::string logged; int loggedLevel=0,loggedFeature=0;
void receive(const char* message,int level,int feature) {
 logged=message; loggedLevel=level; loggedFeature=feature;
 // A metadata update inside a callback must not deadlock or change this call.
 State::Instance().NVNGX_Init.UpdateLogging({});
}
void otherLog(const char*,int,int) {}
'''

CHECKS = r'''
int main() {
 auto& cache=State::Instance().NVNGX_Init;
 auto initial=cache.Read();
 check(initial->ApplicationId==1337 && initial->SdkVersion==0 && initial->ProjectId.empty() && initial->EngineType==0 && !initial->Logger.LoggingCallback);
 std::wstring path=L"C:/\u6e38\u620f space/"+std::wstring(300,L'a');
 auto app=cache.UpdateApplication(81,path.c_str(),71);
 auto saved=path; path.assign(2000,L'b');
 check(app->ApplicationId==81 && app->ApplicationDataPath==saved && app->SdkVersion==71);
 std::string project(500,'p'),engine(600,'e');
 auto both=cache.UpdateProject(project,22,engine);
 check(both->ApplicationId==81 && both->SdkVersion==71 && both->ProjectId==project && both->EngineVersion==engine && both->EngineType==22);
 check(app->ProjectId.empty() && initial->ApplicationDataPath.empty());
 auto logger=cache.UpdateLogging({receive,1,true});
 check(logger->ProjectId==project && logger->Logger.LoggingCallback==receive && logger->Logger.DisableOtherLoggingSinks);
 auto updatedId=cache.UpdateApplicationId(91);
 check(updatedId->ApplicationId==91 && updatedId->ApplicationDataPath==saved && updatedId->ProjectId==project && updatedId->Logger.LoggingCallback==receive);
 std::weak_ptr<const Metadata::Values> retired=cache.UpdateApplication(5,nullptr,9);
 check(cache.Read()->ApplicationDataPath.empty()); cache.UpdateApplicationId(6); check(retired.expired());
 // Compile and execute the actual grouped writer statements from every adapter.
 for(auto write:{&publishDx11,&publishDx12,&publishVk}) {
   write(77,L"caller data",17,"caller project",23,"caller engine");
   auto value=cache.Read();
   check(value->ApplicationId==77 && value->ApplicationDataPath==L"caller data" && value->SdkVersion==17);
   check(value->ProjectId=="caller project" && value->EngineType==23 && value->EngineVersion=="caller engine");
 }
 // Native callbacks publish a different set while the current Init still uses
 // every pointer/scalar from its original snapshot.
 ID3D11Device d11; ID3D12Device d12; int vkDevice;
 for(bool projectMode:{false,true}) {
   for(int api=0;api<3;++api) {
     const std::string expectedProject=projectMode?std::string(500,'P'):"";
     const std::string expectedEngine(600,'E'); const std::wstring expectedPath(700,L'D');
     cache.UpdateApplication(123,expectedPath.c_str(),29); cache.UpdateProject(expectedProject,42,expectedEngine);
     duringNative=[&] { cache.UpdateApplication(999,L"REPLACED",99); cache.UpdateProject("new",99,"new"); };
     NVNGXProxy::_dx11Inited=false;
     NVNGXProxy::_dx12Devices.Shutdown(nullptr,0,-1,[] { return 0; });
     NVNGXProxy::_vulkanDevices.Shutdown(nullptr,0,-1,[] { return 0; });
     bool result=api==0?NVNGXProxy::InitDx11(&d11):api==1?NVNGXProxy::InitDx12(&d12):NVNGXProxy::InitVulkan(nullptr,nullptr,&vkDevice,nullptr,nullptr);
     check(result && nativePointersStable && seenPath==expectedPath && seenVersion==29);
     check(projectMode?(seenProject==expectedProject && seenEngine==expectedEngine && seenEngineType==42):seenId==123);
     check(cache.Read()->ApplicationId==999 && cache.Read()->ProjectId=="new");
   }
 }
 duringNative={};
 // Actual public writer is excluded during path capture and SDK callbacks.
 NVSDK_NGX_Application_Identifier identifier;
 for(int api=0;api<3;++api) {
   auto reset=[&] { NVNGXProxy::_dx11Inited=false; NVNGXProxy::_dx12Devices.Shutdown(nullptr,0,-1,[]{return 0;}); NVNGXProxy::_vulkanDevices.Shutdown(nullptr,0,-1,[]{return 0;}); };
   auto init=[&] { return api==0?NVNGXProxy::InitDx11(&d11):api==1?NVNGXProxy::InitDx12(&d12):NVNGXProxy::InitVulkan(nullptr,nullptr,&vkDevice,nullptr,nullptr); };
   reset(); cache.UpdateApplication(123,L"original",29); cache.UpdateProject("",0,"");
   auto rejected=[&] {
     auto before=cache.Read();
     for(int type:{1,2}) { identifier.IdentifierType=type; check(NVSDK_NGX_UpdateFeature(&identifier,1)==-7); check(cache.Read()==before); }
     check(NgxExportLifecycle::Run(-7,[]{return 0;})==-7);
   };
   duringPaths=rejected; duringNative=[&] { rejected(); auto worker=std::async(std::launch::async,rejected); worker.get(); };
   check(init() && seenId==123 && seenPath==L"original");
   duringPaths={}; duringNative={};
   identifier.IdentifierType=1; check(NVSDK_NGX_UpdateFeature(&identifier,1)==0 && cache.Read()->ApplicationId==456);
   identifier.IdentifierType=2; check(NVSDK_NGX_UpdateFeature(&identifier,1)==0 && cache.Read()->ProjectId=="updated");
   // A writer rejects direct Init before path/SDK callbacks, including cached Init.
   int entered=0; duringPaths=[&]{++entered;}; duringNative=duringPaths;
   check(NgxExportLifecycle::Run(-7,[&]{ check(!init()); auto worker=std::async(std::launch::async,init); check(!worker.get()); return 0; })==0);
   check(entered==0);
   reset(); duringPaths=[] { throw 42; }; duringNative={};
   try { init(); check(false); } catch(int e) { check(e==42); }
   duringPaths={}; check(NVSDK_NGX_UpdateFeature(&identifier,1)==0); check(init());
   reset(); duringNative=[] { throw 43; };
   try { init(); check(false); } catch(int e) { check(e==43); }
   duringNative={}; check(NVSDK_NGX_UpdateFeature(&identifier,1)==0);
   if(api!=0) { check(!init()); reset(); }
   check(init());
 }
 // Actual D3D12/Vulkan direct helpers distinguish missing backends from SDK failures.
 for(int api=1;api<3;++api)for(bool projectMode:{false,true})for(int failure=0;failure<3;++failure){
  auto& lifecycle=api==1?NVNGXProxy::_dx12Devices:NVNGXProxy::_vulkanDevices;
  lifecycle.Shutdown(nullptr,0,-7,[]{return 0;});
  cache.UpdateProject(projectMode?"project":"",1,"engine");
  NVNGXProxy::module=Module{};
  auto init=[&]{return api==1?NVNGXProxy::InitDx12(&d12):NVNGXProxy::InitVulkan(nullptr,nullptr,&vkDevice,nullptr,nullptr);};
  if(failure==0)NVNGXProxy::module.dll=nullptr;
  if(failure==1){
   NVNGXProxy::module.D3D12_Init_ProjectID.enabled=false;NVNGXProxy::module.D3D12_Init_Ext.enabled=false;
   NVNGXProxy::module.VULKAN_Init_ProjectID.enabled=false;NVNGXProxy::module.VULKAN_Init_Ext.enabled=false;
  }
  nativeReturn=failure==2?-4:0;int before=sdkCalls;
  check(!init()&&sdkCalls==before+(failure==2?1:0)&&!lifecycle.AnyReady());
  NVNGXProxy::module=Module{};nativeReturn=0;
  if(failure==2)check(!init()&&sdkCalls==before+1);
  int closes=0;
  check(lifecycle.Shutdown(nullptr,0,-7,[&]{++closes;return 0;})==0&&closes==(failure==2?1:0));
  check(init()&&lifecycle.AnyReady());
 }
 // The log payload is a view, not a C string. Never send its trailing bytes.
 const char raw[]={'o','k','X','Y',0};
 cache.UpdateLogging({receive,1,false}); logCallback({std::string_view(raw,2),2});
 check(logged=="ok" && loggedLevel==1 && loggedFeature==1 && !cache.Read()->Logger.LoggingCallback);
 logged.clear(); cache.UpdateLogging({receive,0,false}); logCallback({"hidden",2}); check(logged.empty());
 cache.UpdateLogging({receive,1,false}); logCallback({"trace",0}); check(logged.empty());
 cache.UpdateLogging({receive,2,false}); logCallback({"trace",0}); check(logged=="trace");
 logged.clear(); Config::Instance()->LogToNGX.value=false; logCallback({"hidden",2}); check(logged.empty());
 Config::Instance()->LogToNGX.value=true;
 // Independent writers must preserve each other's fields, and every grouped
 // publication must be internally coherent (not a torn mix of two updates).
 std::atomic_bool bad=false;
 cache.UpdateApplication(1,L"1",1); cache.UpdateProject("1",1,"1"); cache.UpdateLogging({receive,1,true});
 auto a=std::async(std::launch::async,[&] { for(int i=1;i<=2000;++i) {
   auto own=cache.UpdateApplication(i,std::to_wstring(i).c_str(),i); std::this_thread::yield();
   if(own->ApplicationId!=i || own->SdkVersion!=i || own->ApplicationDataPath!=std::to_wstring(i)) bad=true;
 }});
 auto b=std::async(std::launch::async,[&] { for(int i=1;i<=2000;++i) cache.UpdateProject(std::to_string(i),i,std::to_string(i)); });
 auto c=std::async(std::launch::async,[&] { for(int i=1;i<=2000;++i) cache.UpdateLogging(i%2?Logging{receive,1,true}:Logging{otherLog,2,false}); });
 auto reader=std::async(std::launch::async,[&] { for(int i=0;i<6000;++i) {
   auto value=cache.Read();
   if(value->ApplicationId!=value->SdkVersion || value->ApplicationDataPath!=std::to_wstring(value->ApplicationId) || value->ProjectId!=std::to_string(value->EngineType) || value->EngineVersion!=value->ProjectId) bad=true;
   if(value->Logger.LoggingCallback==receive ? (value->Logger.MinimumLoggingLevel!=1 || !value->Logger.DisableOtherLoggingSinks) : (value->Logger.LoggingCallback!=otherLog || value->Logger.MinimumLoggingLevel!=2 || value->Logger.DisableOtherLoggingSinks)) bad=true;
 }});
 a.get(); b.get(); c.get(); reader.get(); check(!bad);
 auto final=cache.Read(); check(final->ApplicationId==2000 && final->EngineType==2000 && final->Logger.LoggingCallback==otherLog);
 std::cout << "PASS: " << checks << " NGX metadata checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--compiler',required=True); parser.add_argument('--driver')
    args=parser.parse_args(); cpp=PRELUDE
    for api in ('Dx11','Dx12','Vk'):
        source=(ROOT/f'OptiScaler/inputs/NVNGX_DLSS_{api}.cpp').read_text(encoding='utf-8')
        statements=[]
        for name in ('UpdateApplication','UpdateProject'):
            statements.append(re.search(r'State::Instance\(\)\.NVNGX_Init\.'+name+r'\([^;]+;',source).group(0))
        cpp+=f'\nvoid publish{api}(uint64_t InApplicationId,const wchar_t* InApplicationDataPath,int InSDKVersion,const char* InProjectId,int InEngineType,const char* InEngineVersion) {{'+ '\n'.join(statements)+'}\n'
    source=(ROOT/'OptiScaler/proxies/NVNGX_Proxy.h').read_text(encoding='utf-8')
    methods=[function(source,'static bool InitDx11(')]
    for api in ('Dx12','Vulkan'):
        for declaration in (f'static bool Init{api}(',f'template <typename Callback> static NVSDK_NGX_Result Run{api}Init('):
            methods.append(function(source,declaration))
    cpp+='''struct NVNGXProxy {
 inline static bool _dx11Inited=false;
 inline static NativeDeviceLifecycle _dx12Devices,_vulkanDevices;
 inline static Module module;
 static const Module& GetModule() { return module; }
 static void InitNVNGX() {}
 static std::nullptr_t GetFeatureCommonInfo(NVSDK_NGX_FeatureCommonInfo*) { if(duringPaths) duringPaths(); return nullptr; }
'''+ '\n'.join(methods)+'\n};\n'
    cpp+=function((ROOT/'OptiScaler/inputs/NVNGX.cpp').read_text(encoding='utf-8'),'NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_UpdateFeature(')+'\n'
    source=(ROOT/'OptiScaler/Logger.cpp').read_text(encoding='utf-8')
    cpp+='auto logCallback='+function(source,'[](const spdlog::details::log_msg& msg)')+';\n'+CHECKS
    with tempfile.TemporaryDirectory(prefix='aurora-ngx-metadata-') as directory:
        path=Path(directory); test=path/'test.cpp'; exe=path/'test.exe'; test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),'/Fe:'+str(exe)]
        else: command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=45)

if __name__=='__main__': main()
