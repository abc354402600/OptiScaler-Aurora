"""Compile the actual native proxy getters/call admission, including cached pointers."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include "proxies/NativeDeviceLifecycle.h"
#include <iostream>
#include <cstdlib>
#include <cstdint>
#include <string_view>
#define LOG_INFO(...)
#define LOG_WARN(...)
using UINT=unsigned;
using NVSDK_NGX_Result=int;
constexpr int NVSDK_NGX_Result_Success=0, NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_NotInitialized=-7, NVSDK_NGX_Result_FAIL_InvalidParameter=-2;
struct ID3D12Device {};
struct ID3D12GraphicsCommandList {};
namespace NGX_AllocTypes { constexpr uint32_t Unknown=0, NVDynamic=1, InternDynamic=2; constexpr std::string_view AllocKey="alloc"; }
struct NVSDK_NGX_Parameter { uint32_t allocation=NGX_AllocTypes::NVDynamic; int getResult=0;
 int Get(const char*,uint32_t* out) { *out=allocation; return getResult; } };
int internalDestroyed=0;
struct NVNGX_Parameters : NVSDK_NGX_Parameter { ~NVNGX_Parameters() { ++internalDestroyed; } };
struct NVSDK_NGX_Handle {};
using VkDevice=ID3D12Device*;
using VkCommandBuffer=ID3D12GraphicsCommandList*;
using NVSDK_NGX_Feature=int;
using PFN_NVSDK_NGX_ProgressCallback=void(*)();
int checks=0, calls=0, closes=0;
void check(bool ok) { if(!ok) { std::cerr << "native operation check " << checks+1 << " failed\n"; std::exit(2); } ++checks; }
ID3D12Device device, unknown;
ID3D12GraphicsCommandList command;
NVSDK_NGX_Parameter params;
NVSDK_NGX_Handle handle;
void progress() {}
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True)
    parser.add_argument('--driver')
    args=parser.parse_args()
    source=(ROOT/'OptiScaler/proxies/NVNGX_Proxy.h').read_text(encoding='utf-8')
    typedefs=[]; fields=[]; methods=[]; checks=[]
    values={'InDevice':'&device','InCmdList':'&command','InCmdBuffer':'&command',
            'InFeatureID':'27','InParameters':'&params','InHandle':'&handle',
            'InFeatureHandle':'&handle','InCallback':'&progress','OutHandle':'&output'}
    for api,life,close in [('D3D12','_dx12Devices','ShutdownDx12'),('VULKAN','_vulkanDevices','ShutdownVulkan')]:
        methods.append(function(source,f'static NVSDK_NGX_Result {close}('))
        operations=['DestroyParameters','CreateFeature','EvaluateFeature','ReleaseFeature']
        if api=='VULKAN': operations.append('CreateFeature1')
        for op in operations+['Shutdown','Shutdown1']:
            name=api+'_'+op
            declaration=re.search(r'typedef NVSDK_NGX_Result \(\*PFN_'+name+r'\)\((.*?)\);',source,re.S)
            typedefs.append(declaration.group(0))
            fields.append(f'PFN_{name} {name}=nullptr;')
            methods.append(function(source,f'static PFN_{name} {name}('))
            sig=declaration.group(1)
            if op.startswith('Shutdown'): continue
            parameters=[p.strip().split()[-1].lstrip('*') for p in sig.split(',')]
            actual=', '.join(values[p] for p in parameters)
            validate=' '.join(f'check({p}=={values[p]});' for p in parameters if p!='OutHandle')
            is_create=op.startswith('CreateFeature')
            body=validate+f'''
                ++calls;
                check(NVNGXProxy::{close}(nullptr)==-7);
                check(NVNGXProxy::{close}(&device)==-7);
                check(NVNGXProxy::{life}.Initialize(&unknown,0,-2,-7,[] {{ return 0; }})==-7);
            '''+('check(OutHandle && !*OutHandle); *OutHandle=&handle;' if is_create else '')+'return 17;'
            checks.append(f'''
            {{
              check(NVNGXProxy::{name}()==nullptr);
              NVNGXProxy::_module.{name}=+[]({sig}) -> int {{ {body} }};
              auto cached=NVNGXProxy::{name}(); check(cached!=nullptr);
              NVSDK_NGX_Handle* output=&handle;
              int before=calls;
              check(cached({actual})==-7 && calls==before);
              {'check(output==nullptr);' if is_create else ''}
              check(NVNGXProxy::{life}.Initialize(&device,0,-2,-7,[] {{ return 0; }})==0);
              check(cached({actual})==17 && calls==before+1);
              {'check(output==&handle); check(cached('+actual.replace('&output','nullptr')+')==-2);' if is_create else ''}
              {('output=&handle; check(cached('+actual.replace('&device','&unknown')+')==-7 && !output);') if op=='CreateFeature1' else ''}
              check(NVNGXProxy::{life}.Shutdown(nullptr,0,-7,[&] {{
                output=&handle; int count=calls;
                check(cached({actual})==-7 && calls==count);
                {'check(!output);' if is_create else ''}
                return 0;
              }})==0);
              check(cached({actual})==-7 && calls==before+1);
              check(NVNGXProxy::{life}.Initialize(&device,0,-2,-7,[] {{ return 0; }})==0);
              check(cached({actual})==17 && calls==before+2);
              check(NVNGXProxy::{close}(nullptr)==0);
            }}
            ''')
        checks.insert(0,f'''
        NVNGXProxy::_module.{api}_Shutdown=+[] {{ ++closes; return 0; }};
        NVNGXProxy::_module.{api}_Shutdown1=+[]({('ID3D12Device*' if api=='D3D12' else 'VkDevice')} d) {{ check(d==&device); ++closes; return 0; }};
        ''')
        checks.append(f'''
        {{
        check(NVNGXProxy::{life}.Initialize(&device,0,-2,-7,[] {{ return 0; }})==0);
        auto global=NVNGXProxy::{api}_Shutdown();
        auto specific=NVNGXProxy::{api}_Shutdown1();
        int before=closes;
        check(specific(&device)==0 && closes==before+1);
        check(global()==0 && closes==before+1);
        check(!NVNGXProxy::{life}.AnyReady());
        }}
        ''')
    cpp=PRELUDE+'\n'.join(typedefs)+'\nstruct NvngxModule {\n'+'\n'.join(fields)+'\n};\n'
    parameter_source=(ROOT/'OptiScaler/NVNGX_Parameter.h').read_text(encoding='utf-8')
    cpp+=function(parameter_source,'template <typename PFN_DestroyNGXParameters>')+'\n'
    cpp+='struct NVNGXProxy { inline static NativeDeviceLifecycle _dx12Devices,_vulkanDevices; inline static NvngxModule _module; static const NvngxModule& GetModule() { return _module; }\n'
    cpp+='\n'.join(methods)+'\n};\nint main() {\n'+'\n'.join(checks)+r'''
    // Native destroy failures and Busy must not be reported as released.
    using Free=int(*)(NVSDK_NGX_Parameter*);
    check(!TryDestroyNGXParameters(nullptr,Free(nullptr)));
    check(!TryDestroyNGXParameters(&params,Free(nullptr)));
    static int freed=0;
    check(!TryDestroyNGXParameters(&params,+[](NVSDK_NGX_Parameter*) { ++freed; return -7; }));
    check(!TryDestroyNGXParameters(&params,+[](NVSDK_NGX_Parameter*) { ++freed; return -1; }));
    check(TryDestroyNGXParameters(&params,+[](NVSDK_NGX_Parameter* p) { check(p==&params); ++freed; return 0; }));
    check(freed==3);
    params.getResult=-1;
    check(!TryDestroyNGXParameters(&params,+[](NVSDK_NGX_Parameter*) { ++freed; return 0; }) && freed==3);
    params.getResult=0; params.allocation=NGX_AllocTypes::Unknown;
    check(!TryDestroyNGXParameters(&params,+[](NVSDK_NGX_Parameter*) { ++freed; return 0; }) && freed==3);
    auto* local=new NVNGX_Parameters; local->allocation=NGX_AllocTypes::InternDynamic;
    check(TryDestroyNGXParameters(local,Free(nullptr)) && internalDestroyed==1);
    std::cout << "PASS: " << checks << " native operation routing checks\n";
}
'''
    with tempfile.TemporaryDirectory(prefix='aurora-native-operations-') as directory:
        path=Path(directory); test=path/'test.cpp'; exe=path/'test.exe'
        test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':
            command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),'/Fe:'+str(exe)]
        else: command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
