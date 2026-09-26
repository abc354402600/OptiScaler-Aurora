"""Production admission and all provider SDK entry prefixes; real shutdown coordinators.

GPU/native bodies after admission are replaced with a sentinel. Shutdown uses a
counted native stand-in; this does not validate driver/device teardown.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "framegen/ProviderCallAdmission.h"
#include <unordered_set>
#include <functional>
#include <future>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <cstdlib>
using NVSDK_NGX_Result=int; using NVSDK_NGX_Version=int; using NVSDK_NGX_Feature=int;
constexpr int NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_FAIL_NotInitialized=-7,NVSDK_NGX_Result_FAIL_InvalidParameter=-2;
struct ID3D12Device {}; struct ID3D12GraphicsCommandList {}; struct IDXGIAdapter {};
struct NVSDK_NGX_Parameter {}; struct NVSDK_NGX_Handle {};
struct NVSDK_NGX_FeatureDiscoveryInfo {}; struct NVSDK_NGX_FeatureRequirement {};
struct NVSDK_NGX_FeatureCommonInfo {};
using VkDevice=void*; using VkInstance=void*; using VkPhysicalDevice=void*; using VkCommandBuffer=void*;
using PFN_vkGetInstanceProcAddr=void*; using PFN_vkGetDeviceProcAddr=void*; using PFN_NVSDK_NGX_ProgressCallback=void*;
int checks=0;
void check(bool ok) { if(!ok) { std::cerr<<"admission check "<<checks+1<<" failed\n";std::exit(2); } ++checks; }
struct Provider {
 bool supportsDx=true,supportsVk=true;
 bool isDx12Available() { return supportsDx; }
 bool isVulkanAvailable() { return supportsVk; }
 int calls=0; std::function<int()> callback;
 int close() { ++calls; return callback?callback():42; }
 int D3D12_Shutdown() { return close(); } int D3D12_Shutdown1(ID3D12Device*) { return close(); }
 int VULKAN_Shutdown() { return close(); } int VULKAN_Shutdown1(VkDevice) { return close(); }
} provider;
'''

EXTRA=r'''
 // Leases may move but may not release admission twice.
 {
   auto first=Nvngx_FG::_calls.TryOperation(); auto second=std::move(first);
   check(!first && bool(second) && !Nvngx_FG::_calls.TryTransition());
   auto nested=Nvngx_FG::_calls.TryOperation(); check(bool(nested));
 }
 check(bool(Nvngx_FG::_calls.TryTransition()));
 // Joining a callback thread does not wait on a lock held by the initiating call.
 Nvngx_FG::_dx12InitAttempts.insert(nullptr);
 provider.callback=[] {
   auto worker=std::async(std::launch::async,[] {
     return !Nvngx_FG::_calls.TryOperation() && !Nvngx_FG::_calls.TryTransition();
   });
   check(worker.wait_for(std::chrono::seconds(2))==std::future_status::ready && worker.get());
   return -8;
 };
 check(Nvngx_FG::D3D12_Shutdown()==-8);
 check(bool(Nvngx_FG::_calls.TryOperation()));
 Nvngx_FG::_vulkanInitAttempts.insert(nullptr);
 provider.callback=[]()->int { throw std::runtime_error("native close"); };
 bool threw=false;
 try { Nvngx_FG::VULKAN_Shutdown(); } catch(const std::runtime_error&) { threw=true; }
 check(threw && bool(Nvngx_FG::_calls.TryTransition()));
 provider.callback={};
 // Retain admission after the native/provider close, through caller cleanup.
 check(Nvngx_FG::WithDx12Shutdown([&](auto close) {
   check(close(nullptr)==42);
   check(!Nvngx_FG::_calls.TryOperation() && !Nvngx_FG::_calls.TryTransition());
   return 57;
 })==57);
 // No provider and unsupported API are no-op shutdowns, with no lazy loading.
 Nvngx_FG::_provider.present=false; int before=provider.calls;
 check(Nvngx_FG::D3D12_Shutdown()==0 && Nvngx_FG::VULKAN_Shutdown()==0 && provider.calls==before);
 Nvngx_FG::_provider.present=true; provider.supportsVk=false; Nvngx_FG::_vulkanInitAttempts.insert(nullptr);
 check(Nvngx_FG::VULKAN_Shutdown()==0 && provider.calls==before);
 provider.supportsVk=true; provider.supportsDx=false; Nvngx_FG::_dx12InitAttempts.insert(nullptr);
 check(Nvngx_FG::D3D12_Shutdown()==0 && provider.calls==before);
 std::cout<<"PASS: "<<checks<<" provider call admission checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver');args=parser.parse_args()
    source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.cpp').read_text(encoding='utf-8')
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    methods=[];bodies=[];checks=[]
    names=re.findall(r'NVSDK_NGX_Result Nvngx_FG::(\w+)\(',source)
    names=[n for n in names if n!='DrainHandles']
    assert len(names)==22, 'Update admission coverage when provider SDK surface changes'
    for name in names:
        body=function(source,'NVSDK_NGX_Result Nvngx_FG::'+name+'(')
        signature=body[:body.index('{')].strip()
        methods.append('static '+signature.replace('Nvngx_FG::','')+';')
        if '_Shutdown' not in name:
            end=re.search(r'if \(!lease\)\s*return NVSDK_NGX_Result_FAIL_NotInitialized;',body).end()
            body=body[:end]+'\nreturn 42;\n}'
        bodies.append(body)
        arguments=[]
        for param in signature[signature.index('(')+1:signature.rindex(')')].split(','):
            param=param.strip()
            if not param: continue
            if 'OutHandle' in param: arguments.append('&out')
            elif any(x in param for x in ('InApplicationId','InSDKVersion','InFeatureID','InFeatureId')): arguments.append('0')
            else: arguments.append('nullptr')
        call=f'Nvngx_FG::{name}('+','.join(arguments)+')'
        if '_Shutdown' in name:
            target='_dx12InitAttempts' if name.startswith('D3D12') else '_vulkanInitAttempts'
            checks.append(f'Nvngx_FG::{target}.insert(nullptr);')
        checks.append(f'out=&sentinel; check({call}==42);')
        if 'CreateFeature' in name: checks.append('check(out==nullptr);')
        checks.append('{ auto transition=Nvngx_FG::_calls.TryTransition(); out=&sentinel; '+f'check({call}==-7);')
        if 'CreateFeature' in name: checks.append('check(out==nullptr);')
        checks.append('}')
        expected=-7 if '_Init' in name or '_Shutdown' in name else 42
        checks.append('{ auto operation=Nvngx_FG::_calls.TryOperation(); '+f'check({call}=={expected});'+' }')
    cls='''struct Nvngx_FG {
 enum class HandleApi { D3D12, Vulkan };
 static int DrainHandles(HandleApi,const void*) { return 0; }
 inline static ProviderCallAdmission _calls;
 inline static std::unordered_set<ID3D12Device*> _dx12InitAttempts;
 inline static std::unordered_set<VkDevice> _vulkanInitAttempts;
 struct Publication { bool present; Provider* Peek() { return present?&provider:nullptr; } };
 inline static Publication _provider{true};
'''+ '\n'.join(methods)+'\n'+'\n'.join(function(header,'template <typename Callback> static NVSDK_NGX_Result '+name+'(') for name in ('WithDx12Shutdown','WithVulkanShutdown'))+'\n};\n'
    cpp=PRELUDE+cls+'\n'.join(bodies)+'\nint main() { NVSDK_NGX_Handle sentinel; NVSDK_NGX_Handle* out=&sentinel;\n'+'\n'.join(checks)+EXTRA
    with tempfile.TemporaryDirectory(prefix='aurora-call-admission-') as directory:
        path=Path(directory);test=path/'test.cpp';exe=path/'test.exe';test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),'/Fe:'+str(exe)]
        else: command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=25)

if __name__=='__main__':main()
