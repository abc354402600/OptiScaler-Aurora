"""Actual exported Init/Shutdown wrappers: rejection before core side effects.

Core SDK work is a counted stand-in. Path ownership and shutdown bodies have
separate extracted-body suites. This does not simulate GPU work.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "proxies/NgxExportLifecycle.h"
#include "proxies/NgxInitMetadata.h"
#include "proxies/NgxPathSnapshot.h"
#include <functional>
#include <future>
#include <chrono>
#include <stdexcept>
#include <cstdlib>
#include <iostream>
#include <vector>
#define NVSDK_NGX_API
using NVSDK_NGX_Result=int;using NVSDK_NGX_Version=int;using NVSDK_NGX_EngineType=int;
using VkInstance=void*;using VkPhysicalDevice=void*;using VkDevice=void*;
using PFN_vkGetInstanceProcAddr=void*;using PFN_vkGetDeviceProcAddr=void*;
struct ID3D11Device{};struct ID3D12Device{};struct NVSDK_NGX_FeatureCommonInfo{};
constexpr int NVSDK_NGX_Result_FAIL_NotInitialized=-7,NVSDK_NGX_Result_Success=0;
struct State {NgxInitMetadata<int,int,int> NVNGX_Init{0,0};NgxPathCache NVNGX_FeatureInfo_Paths;static State& Instance(){static State s;return s;}};
int checks=0,calls=0,last=-1;std::function<int()> callback;
void check(bool ok){if(!ok){std::cerr<<"Export admission check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
int CoreCalled(int id,bool delegated=false){check(!delegated);++calls;last=id;return callback?callback():31;}
int OtherTranslationUnit();
'''
CHECKS=r'''
 for(int i=0;i<(int)routes.size();++i){
  int before=calls;
  check(routes[i]()==31&&calls==before+1&&last==i);
  // Every exported API/variant must reject every reentrant Init/Shutdown.
  callback=[&]{int current=calls;
    for(auto& nested:routes)check(nested()==-7&&calls==current);
    check(OtherTranslationUnit()==-7);
    auto worker=std::async(std::launch::async,[&]{for(auto& nested:routes)if(nested()!=-7)return false;return true;});
    check(worker.wait_for(std::chrono::seconds(5))==std::future_status::ready&&worker.get());
    check(calls==current);return -9;};
  check(routes[i]()==-9&&calls==before+2);callback={};
  check(routes[i]()==31); // Failed callback releases outer admission.
  callback=[]()->int{throw std::runtime_error("SDK callback");};bool threw=false;
  try{routes[i]();}catch(const std::runtime_error&){threw=true;}
  callback={};check(threw&&routes[i]()==31); // Exception releases admission too.
 }
 check(OtherTranslationUnit()==73);
 std::cout<<"PASS: "<<checks<<" exported Init/Shutdown admission checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver')
    args=parser.parse_args();cpp=PRELUDE;routes=[];index=0
    for api in ('Dx11','Dx12','Vk'):
        source=(ROOT/f'OptiScaler/inputs/NVNGX_DLSS_{api}.cpp').read_text(encoding='utf-8')
        assert '_skipInit' not in source and 'ScopedInit' not in source
        pattern=r'NVSDK_NGX_API NVSDK_NGX_Result\s+(NVSDK_NGX_(?:D3D11|D3D12|VULKAN)_(?:Init\w*|Shutdown1?))\('
        entries=list(re.finditer(pattern,source))
        assert len(entries)==(7 if api=='Vk' else 6)
        for m in entries:
            name=m.group(1);body=function(source,m.group(0))
            core=function(source,'static NVSDK_NGX_Result NgxCore_'+name.removeprefix('NVSDK_NGX_')+'(')
            # Private delegation must never call the public gate recursively.
            assert not re.search(r'\bNVSDK_NGX_(D3D11|D3D12|VULKAN)_(Init\w*|Shutdown1?)\(',core)
            signature=core[:core.index('{')]
            cpp+=signature+'{return CoreCalled('+str(index)+(',delegated' if '_Init' in name else '')+');}\n'+body+'\n'
            signature=body[:body.index('{')];params=signature[signature.index('(')+1:signature.rfind(')')].strip()
            arguments=[]
            for param in ([] if params in ('','void') else params.split(',')):
                if '*' in param or re.search(r'\b(Vk\w+|PFN_\w+)\b',param):arguments.append('nullptr')
                else:arguments.append('0')
            routes.append('[]{return '+name+'('+','.join(arguments)+');}')
            index+=1
    cpp+='int main(){std::vector<std::function<int()>> routes={'+','.join(routes)+'};\n'+CHECKS
    with tempfile.TemporaryDirectory(prefix='aurora-export-init-') as directory:
        path=Path(directory);test=path/'test.cpp';other=path/'other.cpp';exe=path/'test.exe'
        test.write_text(cpp,encoding='utf-8')
        other.write_text('#include "proxies/NgxExportLifecycle.h"\nint OtherTranslationUnit(){return NgxExportLifecycle::Run(-7,[]{return 73;});}\n',encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),str(other),'/Fe:'+str(exe)]
        else:command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(test),str(other),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__':main()
