"""Actual replacement-provider Release routes with counted/reentrant callbacks."""
from pathlib import Path
import argparse
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "framegen/ProviderHandleRegistry.h"
#include <functional>
#include <iostream>
#include <cstdlib>
using NVSDK_NGX_Result=int;
constexpr int NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2,NVSDK_NGX_Result_FAIL_FeatureNotFound=-3,
 NVSDK_NGX_Result_FAIL_NotInitialized=-7;
struct NVSDK_NGX_Handle { unsigned id; };
struct Provider {
 int calls=0; std::function<int()> callback;
 int D3D12_ReleaseFeature(NVSDK_NGX_Handle*) { ++calls; return callback?callback():0; }
 int VULKAN_ReleaseFeature(NVSDK_NGX_Handle*) { ++calls; return callback?callback():0; }
} provider;
struct Nvngx_FG {
 struct Nvngx_FG_Handle { unsigned id; NVSDK_NGX_Handle* nativeHandle; };
 inline static ProviderHandleRegistry<Nvngx_FG_Handle> _handles;
 inline static bool available=true;
 static Provider* getProvider() { return available?&provider:nullptr; }
 static int D3D12_ReleaseFeature(NVSDK_NGX_Handle*);
 static int VULKAN_ReleaseFeature(NVSDK_NGX_Handle*);
};
int checks=0;
void check(bool ok) { if(!ok) { std::cerr<<"Release route check "<<checks+1<<" failed\n";std::exit(2); } ++checks; }
'''
CHECKS=r'''
int main() {
 NVSDK_NGX_Handle native{1};
 for(auto release:{&Nvngx_FG::D3D12_ReleaseFeature,&Nvngx_FG::VULKAN_ReleaseFeature}) {
   auto* token=reinterpret_cast<NVSDK_NGX_Handle*>(Nvngx_FG::_handles.Publish(Nvngx_FG::_handles.Prepare({42,&native})));
   provider.calls=0; provider.callback={};
   check(release(nullptr)==-2);
   check(release(reinterpret_cast<NVSDK_NGX_Handle*>(1))==-3 && provider.calls==0);
   check(Nvngx_FG::_handles.Read(token,-3,[&](const auto&) { return release(token); })==-7 && provider.calls==0);
   provider.callback=[&] {
     check(release(token)==-7 && provider.calls==1);
     check(Nvngx_FG::_handles.GetIdentity(token,[](const auto& h){return h.id;})==42);
     return -8;
   };
   check(release(token)==-8 && provider.calls==1);
   provider.callback={};
   check(release(token)==0 && provider.calls==2);
   check(release(token)==-3 && provider.calls==2);
   Nvngx_FG::available=false;
   check(release(token)==-1 && provider.calls==2);
   Nvngx_FG::available=true;
 }
 std::cout<<"PASS: "<<checks<<" provider release admission checks\n";
}
'''
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver');args=parser.parse_args()
    source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.cpp').read_text(encoding='utf-8')
    bodies='\n'.join(function(source,f'NVSDK_NGX_Result Nvngx_FG::{api}_ReleaseFeature(') for api in ('D3D12','VULKAN'))
    with tempfile.TemporaryDirectory(prefix='aurora-provider-release-') as folder:
        path=Path(folder);cpp=path/'test.cpp';exe=path/'test.exe';cpp.write_text(PRELUDE+bodies+CHECKS,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else: command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=20)

if __name__=='__main__':main()
