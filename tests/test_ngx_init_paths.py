"""Owned NGX paths: compile actual builders, helper and adapter admission prefixes."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "proxies/NgxPathSnapshot.h"
#include <filesystem>
#include <optional>
#include <functional>
#include <cstring>
#include <atomic>
#include <future>
#include <thread>
#include <stdexcept>
#include <iostream>
#include <cstdlib>
#define LOG_DEBUG(...)
#define LOG_FUNC(...)
constexpr int NVSDK_NGX_LOGGING_LEVEL_VERBOSE=1,NVSDK_NGX_LOGGING_LEVEL_ON=2;
struct PathList { const wchar_t* const* Path=nullptr; unsigned Length=0; };
struct Logging { int MinimumLoggingLevel=0; void(*LoggingCallback)()=nullptr; bool DisableOtherLoggingSinks=false; };
struct NVSDK_NGX_FeatureCommonInfo { PathList PathListInfo; void* InternalData=nullptr; Logging LoggingInfo; };
struct State {
 NgxPathCache NVNGX_FeatureInfo_Paths;
 std::optional<std::wstring> NVNGX_DLSS_Path=L"C:/SR/nvngx_dlss.dll",NVNGX_DLSSD_Path=L"C:/RR/nvngx_dlssd.dll",NVNGX_DLSSG_Path=L"C:/FG/nvngx_dlssg.dll";
 static State& Instance() { static State state; return state; }
};
struct Config {
 std::optional<std::wstring> DLSSFeaturePath=L"C:/override",NVNGX_DLSS_Library=L"custom",MainDllPath=L"C:/Aurora";
 int LogLevel=1;
 static Config* Instance() { static Config config; return &config; }
};
namespace Util {
 std::filesystem::path ExePath() { return L"C:/Game/Game.exe"; }
 std::optional<std::filesystem::path> FindFilePath(const std::filesystem::path&,const char*) { return {}; }
}
int checks=0;
void check(bool ok) { if(!ok) { std::cerr << "NGX path check " << checks+1 << " failed\n"; std::exit(2); } ++checks; }
std::vector<std::wstring> strings(const PathList& list) {
 std::vector<std::wstring> result;
 for(unsigned i=0;i<list.Length;++i) result.emplace_back(list.Path[i]);
 return result;
}
'''

CHECKS=r'''
int main() {
 auto& cache=State::Instance().NVNGX_FeatureInfo_Paths;
 std::wstring a=L"C:/\u6e38\u620f space/A",b=L"C:/B";
 const wchar_t* original[]={a.c_str(),b.c_str()};
 NVSDK_NGX_FeatureCommonInfo input; input.PathListInfo={original,2};
 auto* marker=reinterpret_cast<void*>(0x1234); input.InternalData=marker;
 std::vector<std::wstring> expected={L"C:/override",L"C:/SR",L"C:/Aurora",a,b,L"C:/Game/",L"C:/RR",L"C:/FG"};
 auto info11=input,info12=input,infoVk=input;
 auto owner11=Dx11::UpdateInitPaths(&info11);
 auto owner12=Dx12::UpdateInitPaths(&info12);
 auto ownerVk=Vk::UpdateInitPaths(&infoVk);
 check(strings(info11.PathListInfo)==expected);
 check(strings(info12.PathListInfo)==expected);
 check(strings(infoVk.PathListInfo)==expected);
 check(info11.InternalData==marker && info12.InternalData==marker && infoVk.InternalData==marker);
 check(info11.PathListInfo.Path!=info12.PathListInfo.Path && info12.PathListInfo.Path!=infoVk.PathListInfo.Path);
 a.assign(3000,L'x'); b.clear(); // Input strings are independent after copying.
 check(strings(info11.PathListInfo)==expected && strings(info12.PathListInfo)==expected);
 auto newer=cache.Publish({L"new"});
 check(strings(infoVk.PathListInfo)==expected && newer->Strings()==std::vector<std::wstring>{L"new"});
 std::weak_ptr<const NgxPathSnapshot> retired=owner11;
 owner11.reset(); check(retired.expired());
 check(!Dx11::UpdateInitPaths(nullptr) && !Dx12::UpdateInitPaths(nullptr) && !Vk::UpdateInitPaths(nullptr));
 check(cache.Read()==newer);
 NVSDK_NGX_FeatureCommonInfo common1,common2;
 auto commonOwner1=NVNGXProxy::GetFeatureCommonInfo(&common1);
 auto commonOwner2=NVNGXProxy::GetFeatureCommonInfo(&common2);
 check(strings(common1.PathListInfo)==std::vector<std::wstring>{L"new",L"C:/SR/"});
 check(strings(common2.PathListInfo)==strings(common1.PathListInfo));
 check(cache.Read()==newer && newer->Strings().size()==1); // No accumulated append/leak.
 check(common1.LoggingInfo.MinimumLoggingLevel==NVSDK_NGX_LOGGING_LEVEL_VERBOSE && common1.LoggingInfo.LoggingCallback==&NVNGXProxy::LogCallback && common1.LoggingInfo.DisableOtherLoggingSinks);
 check(!NVNGXProxy::GetFeatureCommonInfo(nullptr));
 auto empty=cache.Publish({}); State::Instance().NVNGX_DLSS_Path.reset();
 auto emptyOwner=NVNGXProxy::GetFeatureCommonInfo(&common2);
 check(common2.PathListInfo.Length==0 && !common2.PathListInfo.Path && emptyOwner);
 check(strings(common1.PathListInfo)==std::vector<std::wstring>{L"new",L"C:/SR/"});
 State::Instance().NVNGX_DLSS_Path=L"C:/SR/nvngx_dlss.dll";
 Config::Instance()->NVNGX_DLSS_Library.reset();
 NVSDK_NGX_FeatureCommonInfo noOriginal;
 auto defaultOwner=Dx12::UpdateInitPaths(&noOriginal);
 check(strings(noOriginal.PathListInfo)==std::vector<std::wstring>{L"C:/override",L"C:/Aurora",L"C:/Game/",L"C:/SR",L"C:/RR",L"C:/FG"});
 // Preserve Vulkan's existing bad-length workaround without dereferencing junk.
 NVSDK_NGX_FeatureCommonInfo junk;
 junk.PathListInfo={reinterpret_cast<const wchar_t* const*>(1),10};
 auto junkOwner=Vk::UpdateInitPaths(&junk);
 check(strings(junk.PathListInfo)==strings(noOriginal.PathListInfo));
 // Actual adapter prefixes retain ownership through nested delegated calls.
 for(auto invoke:{&Dx11::Invoke,&Dx12::Invoke,&Vk::Invoke}) {
   std::weak_ptr<const NgxPathSnapshot> active;
   bool threw=false;
   try { invoke(nullptr,[&](const NVSDK_NGX_FeatureCommonInfo& fc) {
     active=cache.Read(); const auto retained=strings(fc.PathListInfo);
     auto replacement=cache.Publish({L"different thread / nested call"});
     check(!active.expired() && strings(fc.PathListInfo)==retained);
     {
       Dx12::ScopedInitDx12 delegated;
       Dx12::Invoke(&fc,[&](const NVSDK_NGX_FeatureCommonInfo& child) {
         check(child.PathListInfo.Path==fc.PathListInfo.Path && strings(child.PathListInfo)==retained);
         check(cache.Read()==replacement);
       });
     }
     throw std::runtime_error("native Init failure");
   }); } catch(const std::runtime_error&) { threw=true; }
   check(threw && active.expired()); // No raw leaked pointer array keeps it alive.
 }
 // Repeat writers/readers on the production cache while keeping each call's view.
 std::atomic_bool bad=false; std::vector<std::future<void>> workers;
 for(int worker=0;worker<4;++worker) workers.push_back(std::async(std::launch::async,[&,worker] {
   for(int i=0;i<1000;++i) {
     const auto value=std::to_wstring(worker)+L" / "+std::to_wstring(i);
     auto own=cache.Publish({value,value}); PathList view; own->Bind(view);
     std::this_thread::yield(); auto read=cache.Read();
     if(view.Length!=2 || strings(view)!=std::vector<std::wstring>{value,value} || read->Strings().size()!=2 || read->Strings()[0]!=read->Strings()[1]) bad=true;
   }
 }));
 for(auto& worker:workers) worker.get();
 check(!bad);
 std::cout << "PASS: " << checks << " NGX path ownership checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--compiler',required=True); parser.add_argument('--driver')
    args=parser.parse_args(); cpp=PRELUDE
    for api,entry in [('Dx11','D3D11_Init_Ext'),('Dx12','D3D12_Init_Ext'),('Vk','VULKAN_Init_Ext2')]:
        source=(ROOT/f'OptiScaler/inputs/NVNGX_DLSS_{api}.cpp').read_text(encoding='utf-8')
        flag=re.search(r'static thread_local bool _skipInit = false;',source).group(0)
        body=function(source,'NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_'+entry+'(')
        prefix=body[body.index('{')+1:body.index('const auto initPaths =')]
        end=body.index(';',body.index('const auto initPaths ='))+1
        prefix+=body[body.index('const auto initPaths ='):end]
        cpp+='\nnamespace '+api+' {\n'+flag+'\n'+function(source,'class ScopedInit'+api)+';\n'
        cpp+=function(source,'[[nodiscard]] static NgxPathSnapshot::Owner UpdateInitPaths(')
        cpp+='\nvoid Invoke(const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo,std::function<void(const NVSDK_NGX_FeatureCommonInfo&)> callback) {\n'+prefix+'\ncallback(localFeatureInfo);\n}\n}\n'
    source=(ROOT/'OptiScaler/proxies/NVNGX_Proxy.h').read_text(encoding='utf-8')
    cpp+='struct NVNGXProxy { static void LogCallback() {}\n'+function(source,'[[nodiscard]] static NgxPathSnapshot::Owner GetFeatureCommonInfo(')+'\n};\n'+CHECKS
    with tempfile.TemporaryDirectory(prefix='aurora-ngx-paths-') as directory:
        path=Path(directory); test=path/'test.cpp'; exe=path/'test.exe'; test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),'/Fe:'+str(exe)]
        else: command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
