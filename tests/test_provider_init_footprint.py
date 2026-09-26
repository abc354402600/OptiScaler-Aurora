"""Run complete provider Init/Shutdown bodies with a deterministic fake SDK.

The SDK can fail or throw after entering Init/Shutdown. This tests cleanup
ownership, not readiness, native resource allocation or GPU behavior.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

from test_shutdown_routing import function
from test_provider_call_admission import PRELUDE

ROOT = Path(__file__).resolve().parents[1]

SCENARIO = r'''
 {
   auto init=[&](auto* device) { return INIT_CALL; };
   auto close=[&](auto* device) { return Nvngx_FG::API_Shutdown1(device); };
   auto all=[] { return Nvngx_FG::API_Shutdown(); };
   auto& attempts=Nvngx_FG::ATTEMPTS;
   check(attempts.empty());
   int before=provider.calls;
   check(all()==0 && close(&a)==0 && provider.calls==before);
   before=provider.inits;
   check(init(static_cast<ID3D12Device*>(nullptr))==-2 && provider.inits==before && attempts.empty());
   Nvngx_FG::status=ProviderStatus::Pending;
   check(init(&a)==-7 && attempts.empty() && provider.inits==before);
   Nvngx_FG::status=ProviderStatus::Unavailable;
   check(init(&a)==-1 && attempts.empty() && provider.inits==before);
   Nvngx_FG::status=ProviderStatus::Available;
   {
     auto busy=Nvngx_FG::_calls.TryOperation();
     check(init(&a)==-7 && attempts.empty() && provider.inits==before);
   }
   provider.initCallback=[&] {
     check(attempts.contains(&a) && !Nvngx_FG::_calls.TryOperation());
     return 0;
   };
   check(init(&a)==0 && attempts.contains(&a) && provider.inits==before+1);
   provider.initCallback={};
   before=provider.calls;
   check(close(&b)==0 && provider.calls==before && attempts.contains(&a));
   provider.callback=[] { return -8; };
   check(close(&a)==-8 && attempts.contains(&a));
   provider.callback=[] { return 0; };
   check(close(&a)==0 && attempts.empty());
   before=provider.calls;
   check(close(&a)==0 && all()==0 && provider.calls==before);
   // Failed Init is still a cleanup obligation, not proof of readiness.
   provider.initCallback=[] { return -8; };
   check(init(&a)==-8 && attempts.contains(&a));
   check(close(&a)==0 && attempts.empty());
   provider.initCallback=[]()->int { throw std::runtime_error("partial init"); };
   bool threw=false;
   try { init(&a); } catch(const std::runtime_error&) { threw=true; }
   check(threw && attempts.contains(&a) && bool(Nvngx_FG::_calls.TryTransition()));
   check(close(&a)==0 && attempts.empty());
   provider.initCallback={};
   check(init(&a)==0 && init(&b)==0 && attempts.size()==2);
   provider.callback=[]()->int { throw std::runtime_error("partial close"); };
   threw=false;
   try { all(); } catch(const std::runtime_error&) { threw=true; }
   check(threw && attempts.size()==2 && bool(Nvngx_FG::_calls.TryTransition()));
   provider.callback=[] { return -8; };
   check(all()==-8 && attempts.size()==2);
   provider.callback=[] { return 0; };
   check(all()==0 && attempts.empty());
 }
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    source = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.cpp').read_text(encoding='utf-8')
    header = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    names = ['D3D12_Init', 'D3D12_Init_Ext', 'VULKAN_Init', 'VULKAN_Init_Ext', 'VULKAN_Init_Ext2']
    init_bodies = [function(source, 'NVSDK_NGX_Result Nvngx_FG::'+n+'(') for n in names]
    shutdown_bodies = [function(source, 'NVSDK_NGX_Result Nvngx_FG::'+api+'_Shutdown'+suffix+'(')
                       for api in ('D3D12', 'VULKAN') for suffix in ('', '1')]
    signatures = [body[:body.index('{')].strip().replace('Nvngx_FG::', '')
                  for body in init_bodies+shutdown_bodies]
    stubs = '\n'.join(s+' { ++inits; return initCallback?initCallback():0; }' for s in signatures[:5])
    prelude = PRELUDE.replace('#include <unordered_set>', '#include <unordered_set>\n#include "framegen/ProviderPublication.h"')
    prelude = prelude.replace('constexpr int NVSDK_NGX_Result_Success=0,', 'constexpr int NVSDK_NGX_Result_Fail=-1,NVSDK_NGX_Result_Success=0,')
    prelude = prelude.replace('struct Provider {', 'struct Provider {\n int inits=0; std::function<int()> initCallback;\n'+stubs)
    coordinators = '\n'.join(function(header, 'template <typename Callback> static NVSDK_NGX_Result '+n+'(')
                             for n in ('WithDx12Shutdown', 'WithVulkanShutdown'))
    cls = r'''
struct Nvngx_FG {
 enum class HandleApi { D3D12, Vulkan };
 static int DrainHandles(HandleApi,const void*) { return 0; }
 inline static ProviderCallAdmission _calls;
 inline static std::unordered_set<ID3D12Device*> _dx12InitAttempts;
 inline static std::unordered_set<VkDevice> _vulkanInitAttempts;
 inline static ProviderStatus status=ProviderStatus::Available;
 struct Publication { Provider* Peek() { return &provider; } };
 inline static Publication _provider;
 static ProviderLookup<Provider> lookupProvider() { return {status==ProviderStatus::Available?&provider:nullptr,status}; }
'''+ '\n'.join('static '+s+';' for s in signatures)+'\n'+coordinators+'\n};\n'
    scenarios = []
    for name, sig in zip(names, signatures):
        arguments = []
        for param in sig[sig.index('(')+1:sig.rindex(')')].split(','):
            if 'InDevice' in param:
                arguments.append('device')
            elif 'InApplicationId' in param or 'InSDKVersion' in param:
                arguments.append('0')
            else:
                arguments.append('nullptr')
        call = 'Nvngx_FG::'+name+'('+','.join(arguments)+')'
        api = 'D3D12' if name.startswith('D3D12') else 'VULKAN'
        attempts = '_dx12InitAttempts' if api == 'D3D12' else '_vulkanInitAttempts'
        scenarios.append(SCENARIO.replace('INIT_CALL', call).replace('API', api).replace('ATTEMPTS', attempts))
    tail = r'''
 // The same pointer value in the two APIs does not share a cleanup footprint.
 check(Nvngx_FG::D3D12_Init(0,nullptr,&a,nullptr,0)==0);
 check(Nvngx_FG::VULKAN_Init_Ext(0,nullptr,nullptr,nullptr,&a,0,nullptr)==0);
 check(Nvngx_FG::D3D12_Shutdown()==0 && Nvngx_FG::_dx12InitAttempts.empty() && Nvngx_FG::_vulkanInitAttempts.contains(&a));
 check(Nvngx_FG::VULKAN_Shutdown()==0 && Nvngx_FG::_vulkanInitAttempts.empty());
 std::cout<<"PASS: "<<checks<<" complete provider Init footprint checks\n";
}
'''
    cpp = prelude+cls+'\n'.join(init_bodies+shutdown_bodies)+'\nint main() { ID3D12Device a,b;\n'+''.join(scenarios)+tail
    with tempfile.TemporaryDirectory(prefix='aurora-init-footprint-') as directory:
        path = Path(directory)
        test, exe = path/'test.cpp', path/'test.exe'
        test.write_text(cpp, encoding='utf-8')
        command = [args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            command += ['/nologo', '/EHsc', '/std:c++20', '/I'+str(ROOT/'OptiScaler'), str(test), '/Fe:'+str(exe)]
        else:
            command += ['-std=c++20', '-I'+str(ROOT/'OptiScaler'), str(test), '-o', str(exe)]
        subprocess.run(command, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=25)


if __name__ == '__main__':
    main()
