"""Exercise the real NGX module builder/accessors with counted loader stand-ins."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "framegen/ProviderPublication.h"
#include <chrono>
#include <future>
#include <functional>
#include <optional>
#include <string>
#include <vector>
#include <stdexcept>
#include <iostream>
#include <cstdlib>
#define LOG_INFO(...)
#define LOG_DEBUG(...)
using HMODULE=void*;
using DWORD=unsigned long;
constexpr DWORD MAX_PATH=260;
struct ScopedSkipDxgiLoadChecks {};
int checks=0,loads=0,resolves=0,hooks=0,pathMode=0;
bool failLoad=false,throwResolve=false;
HMODULE loaded=reinterpret_cast<void*>(0x44);
std::function<void()> loading, resolving, hooking;
std::vector<std::wstring> attempted;
void check(bool ok) { if(!ok) { std::cerr << "module publication check " << checks+1 << " failed\n"; std::exit(2); } ++checks; }
struct Config {
 std::optional<std::wstring> MainDllPath=L"package",NvngxPath=L"override";
 static Config* Instance() { static Config c; return &c; }
};
namespace Util {
 void LoadProxyLibrary(const std::wstring& name,const std::wstring&,const std::wstring& path,HMODULE*,HMODULE* out) {
  ++loads; attempted.push_back(path+L"/"+name); if(loading) loading(); if(!failLoad) *out=loaded;
 }
 std::optional<std::wstring> NvngxPath() { return L"driver"; }
}
DWORD GetModuleFileNameW(HMODULE,wchar_t* out,DWORD count) {
 if(pathMode==1) return 0;
 if(pathMode==2) { std::fill_n(out,count,L'X'); return count; }
 const std::wstring value=L"driver/nvngx.dll"; std::copy(value.begin(),value.end(),out); return DWORD(value.size());
}
void HookNgxApi(HMODULE h) { check(h==loaded); ++hooks; if(hooking) hooking(); }
void exportStub() {}
void* resolve(HMODULE h,const char* name) {
 check(h==loaded); ++resolves;
 if(resolving) resolving();
 if(throwResolve) { throwResolve=false; throw std::runtime_error("resolver"); }
 // Optional absent export must remain null, not block publication of the rest.
 if(std::string(name)=="NVSDK_NGX_VULKAN_Init_Ext2") return nullptr;
 return reinterpret_cast<void*>(&exportStub);
}
struct KernelBaseProxy { static auto GetProcAddress_() { return &resolve; } };
'''

CHECKS=r'''
int main(int argc,char** argv) {
 using namespace std::chrono_literals;
 const std::string mode=argc>1 ? argv[1] : "provided";
 check(!NVNGXProxy::NVNGXModule() && NVNGXProxy::NVNGXModule_Path().empty());
 check(!NVNGXProxy::D3D11_Init() && !NVNGXProxy::D3D12_Init() && !NVNGXProxy::VULKAN_Init());
 hooking=[] { check(!NVNGXProxy::NVNGXModule() && !NVNGXProxy::D3D12_Init()); NVNGXProxy::InitNVNGX(loaded); check(!NVNGXProxy::NVNGXModule()); };
 if(mode=="failed-load") {
   failLoad=true; NVNGXProxy::InitNVNGX();
   check(!NVNGXProxy::NVNGXModule() && resolves==0 && hooks==0 && loads==4);
   check(attempted==std::vector<std::wstring>{L"override/_nvngx.dll",L"override/nvngx.dll",L"driver/_nvngx.dll",L"driver/nvngx.dll"});
   failLoad=false; NVNGXProxy::InitNVNGX(); check(loads==5);
 } else if(mode=="exception") {
   throwResolve=true; bool threw=false;
   try { NVNGXProxy::InitNVNGX(loaded); } catch(const std::runtime_error&) { threw=true; }
   check(threw && !NVNGXProxy::NVNGXModule() && !NVNGXProxy::D3D11_Init());
   NVNGXProxy::InitNVNGX(loaded); check(hooks==2 && loads==0);
 } else if(mode=="loader-pending" || mode=="exports-pending") {
   std::promise<void> entered,release;
   auto released=release.get_future(); bool paused=false;
   auto pause=[&] { if(!paused) { paused=true; entered.set_value(); released.wait(); } };
   if(mode=="loader-pending") loading=pause; else resolving=pause;
   auto builder=std::async(std::launch::async,[] { NVNGXProxy::InitNVNGX(); });
   check(entered.get_future().wait_for(5s)==std::future_status::ready);
   // Contender returns while the loader/export resolver is deliberately blocked.
   auto contender=std::async(std::launch::async,[] {
     NVNGXProxy::InitNVNGX(loaded);
     return !NVNGXProxy::NVNGXModule() && !NVNGXProxy::D3D11_Init() && !NVNGXProxy::VULKAN_Init() && NVNGXProxy::NVNGXModule_Path().empty();
   });
   check(contender.wait_for(5s)==std::future_status::ready && contender.get());
   release.set_value(); check(builder.wait_for(5s)==std::future_status::ready); builder.get();
   loading=nullptr; resolving=nullptr; check(loads==1 && hooks==1);
 } else {
   if(mode=="path-failed") pathMode=1;
   if(mode=="path-truncated") pathMode=2;
   NVNGXProxy::InitNVNGX(loaded); check(loads==0 && hooks==1);
 }
 check(NVNGXProxy::NVNGXModule()==loaded);
 check(NVNGXProxy::D3D11_Init()==&exportStub && NVNGXProxy::D3D12_Init()==&exportStub && NVNGXProxy::VULKAN_Init()==&exportStub);
 check(NVNGXProxy::GetModule().VULKAN_Init_Ext2==nullptr);
 check(pathMode ? NVNGXProxy::NVNGXModule_Path().empty() : NVNGXProxy::NVNGXModule_Path()==L"driver/nvngx.dll");
 const int oldLoads=loads,oldResolves=resolves,oldHooks=hooks;
 NVNGXProxy::InitNVNGX(reinterpret_cast<void*>(0x99));
 check(NVNGXProxy::NVNGXModule()==loaded && loads==oldLoads && resolves==oldResolves && hooks==oldHooks);
 FULL_TABLE_CHECKS
 std::cout << "PASS: " << checks << " module publication checks (" << mode << ")\n";
}
'''

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--compiler',required=True); parser.add_argument('--driver')
    args=parser.parse_args()
    source=(ROOT/'OptiScaler/proxies/NVNGX_Proxy.h').read_text(encoding='utf-8')
    module=function(source,'struct NvngxModule')+';'
    aliases='\n'.join('using '+t+'=void(*)();' for t in sorted(set(re.findall(r'\bPFN_\w+',module))))
    methods=[]
    for declaration in ('static const NvngxModule& GetModule(', 'static std::unique_ptr<NvngxModule> BuildModule(',
                        'static void InitNVNGX(', 'static HMODULE NVNGXModule(', 'static std::wstring NVNGXModule_Path(',
                        'static PFN_D3D11_Init D3D11_Init(', 'static PFN_D3D12_Init D3D12_Init(', 'static PFN_VULKAN_Init VULKAN_Init('):
        methods.append(function(source,declaration))
    resolved=set(re.findall(r'module\.(\w+)\s*=\s*\(PFN_',methods[1]))
    assert len(resolved)>40, 'Export-table extraction unexpectedly incomplete'
    table='\n'.join('check(NVNGXProxy::GetModule().'+field+('==nullptr);' if field=='VULKAN_Init_Ext2' else '==&exportStub);') for field in sorted(resolved))
    cpp=PRELUDE+aliases+'\n'+module+'''
struct NVNGXProxy {
 inline static ProviderPublication<NvngxModule> _modulePublication;
 inline static const NvngxModule _emptyModule {};
'''+ '\n'.join(methods)+'\n};\n'+CHECKS.replace('FULL_TABLE_CHECKS',table)
    with tempfile.TemporaryDirectory(prefix='aurora-module-publication-') as directory:
        path=Path(directory); test=path/'test.cpp'; exe=path/'test.exe'; test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),'/Fe:'+str(exe)]
        else: command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        for mode in ['provided','failed-load','exception','loader-pending','exports-pending','path-failed','path-truncated']:
            subprocess.run([str(exe),mode],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
