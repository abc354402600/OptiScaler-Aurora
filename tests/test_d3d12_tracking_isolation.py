"""Run shipped UAV hook bodies and the tracking switch with CPU stand-ins.

Checks recording/forwarding and ordered thread isolation, not GPU restoration.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    source = (ROOT/'OptiScaler/hooks/D3D12_Hooks.cpp').read_text(encoding='utf-8')
    cpp = r'''
#include <vector>
#include <unordered_map>
#include <mutex>
#include <thread>
#include <iostream>
#include <cstdlib>
using UINT=unsigned;using D3D12_GPU_VIRTUAL_ADDRESS=unsigned long long;
struct ID3D12GraphicsCommandList {};
enum class RootEntryType {Invalid,UAV};
struct RootState {RootEntryType type=RootEntryType::Invalid;D3D12_GPU_VIRTUAL_ADDRESS bufferLocation=0;};
// Count actual record attempts, including duplicate late -> early writes.
struct CountingLock {int acquisitions=0;void lock(){++acquisitions;}void unlock(){}};
CountingLock rootStatesMutex;
std::unordered_map<ID3D12GraphicsCommandList*,std::vector<RootState>> rootStates;
struct D3D12Hooks {static void SetRootSignatureTracking(bool);};
int calls=0;ID3D12GraphicsCommandList* lastCmd=nullptr;UINT lastIndex=0;
D3D12_GPU_VIRTUAL_ADDRESS lastAddress=0;
void original(ID3D12GraphicsCommandList* cmd,UINT i,D3D12_GPU_VIRTUAL_ADDRESS address){
 ++calls;lastCmd=cmd;lastIndex=i;lastAddress=address;
}
using HookFn=decltype(&original);
struct Hook {HookFn o_earlyHook=original,o_lateHook=original;};
Hook s_SetComputeRootUnorderedAccessView,s_SetGraphicsRootUnorderedAccessView;
'''
    names = ['isUpscalerActive', 'lateInProgressSetComputeRootUnorderedAccessView',
             'lateInProgressSetGraphicsRootUnorderedAccessView']
    for name in names:
        match = re.search(r'^static (?:thread_local )?bool '+name+r' = false;', source, re.M)
        assert match, name
        cpp += match[0]+'\n'
    cpp += function(source, 'void D3D12Hooks::SetRootSignatureTracking(')+'\n'
    for pipeline in ['Compute', 'Graphics']:
        for suffix in ['', 'Late']:
            body = function(source, 'static void hkSet'+pipeline+'RootUnorderedAccessView'+suffix+'(')
            # Substitute only the lock type to count duplicate recording; retain the hook body.
            cpp += body.replace('std::shared_mutex', 'CountingLock')+'\n'
    cpp += r'''
int main(){int checks=0;auto check=[&](bool ok){++checks;if(!ok){std::cerr<<"FAIL "<<checks;std::exit(2);}};
 ID3D12GraphicsCommandList a,b;
 for(bool graphics:{false,true}){
 auto early=graphics?hkSetGraphicsRootUnorderedAccessView:hkSetComputeRootUnorderedAccessView;
 auto late=graphics?hkSetGraphicsRootUnorderedAccessViewLate:hkSetComputeRootUnorderedAccessViewLate;
 auto& hook=graphics?s_SetGraphicsRootUnorderedAccessView:s_SetComputeRootUnorderedAccessView;
 auto& nesting=graphics?lateInProgressSetGraphicsRootUnorderedAccessView:lateInProgressSetComputeRootUnorderedAccessView;
 hook.o_lateHook=early;
 for(bool latePath:{false,true}){
 auto call=latePath?late:early;
 rootStates.clear();rootStates[&a].resize(2);calls=0;rootStatesMutex.acquisitions=0;
 D3D12Hooks::SetRootSignatureTracking(true);
 call(&a,1,123);check(rootStates[&a][1].type==RootEntryType::UAV);
 check(rootStates[&a][1].bufferLocation==123);check(calls==1);
 check(lastCmd==&a&&lastIndex==1&&lastAddress==123);check(rootStatesMutex.acquisitions==1);
 call(&a,1,0);check(rootStates[&a][1].bufferLocation==0);check(calls==2);
 call(&a,9,77);check(rootStates[&a].size()==2&&rootStates[&a][1].bufferLocation==0);
 check(calls==3&&lastIndex==9);
 call(nullptr,0,88);check(calls==4&&lastCmd==nullptr);check(!rootStates.contains(nullptr));
 D3D12Hooks::SetRootSignatureTracking(false);int writes=rootStatesMutex.acquisitions;
 call(&a,1,99);check(calls==5);check(rootStatesMutex.acquisitions==writes);
 check(rootStates[&a][1].bufferLocation==0);check(!nesting);
 // Join orders access to all stand-ins, so the test itself has no data race.
 rootStates[&b].resize(1);bool workerEnabled=false;
 std::thread worker([&]{workerEnabled=!isUpscalerActive;call(&b,0,321);});worker.join();
 check(workerEnabled);check(rootStates[&b][0].bufferLocation==321);check(isUpscalerActive);
 check(calls==6);D3D12Hooks::SetRootSignatureTracking(true);check(!isUpscalerActive);
 }
 nesting=true;rootStates[&a][0]={};calls=0;int writes=rootStatesMutex.acquisitions;
 early(&a,0,999);check(calls==1);check(rootStatesMutex.acquisitions==writes);
 check(rootStates[&a][0].type==RootEntryType::Invalid);nesting=false;
 }
 std::cout<<checks<<" D3D12 tracking checks passed (CPU stand-ins)\n";
}
'''
    mutations = {
        'global-tracking-switch': ('static thread_local bool isUpscalerActive', 'static bool isUpscalerActive'),
        'compute-uav-inversion': ('if (!lateInProgressSetComputeRootUnorderedAccessView &&',
                                  'if (lateInProgressSetComputeRootUnorderedAccessView &&'),
        'graphics-uav-inversion': ('if (!lateInProgressSetGraphicsRootUnorderedAccessView &&',
                                   'if (lateInProgressSetGraphicsRootUnorderedAccessView &&'),
    }
    with tempfile.TemporaryDirectory(prefix='aurora-d3d12-tracking-') as directory:
        path = Path(directory)
        cases = {'fixed': cpp}
        for name, (old, new) in mutations.items():
            assert cpp.count(old) == 1, name
            cases[name] = cpp.replace(old, new)
        for name, text in cases.items():
            test, exe = path/'test.cpp', path/'test.exe'
            test.write_text(text, encoding='utf-8')
            command = [args.compiler]+([args.driver] if args.driver else [])
            if Path(args.compiler).stem.lower() == 'cl':
                command += ['/nologo', '/EHsc', '/std:c++20', str(test), '/Fe:'+str(exe)]
            else:
                command += ['-std=c++20', str(test), '-o', str(exe)]
            subprocess.run(command, cwd=path, check=True)
            result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=25)
            if name == 'fixed':
                assert result.returncode == 0, result
                print(result.stdout.strip())
            else:
                assert result.returncode == 2 and 'FAIL ' in result.stderr, (name, result)
                print('Mutation rejected:', name)


if __name__ == '__main__':
    main()
