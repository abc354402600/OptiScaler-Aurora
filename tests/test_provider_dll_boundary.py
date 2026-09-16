"""Execute all DLL-provider forwarders with absent/present exports.

Uses actual method bodies, depth pointer declaration, and destructor from source.
SDK/resource stand-ins only exercise dispatch and CPU cleanup, never GPU behavior.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
using NVSDK_NGX_Result=int;
constexpr int NVSDK_NGX_Result_Success=0, NVSDK_NGX_Result_Fail=-1;
using NVSDK_NGX_Feature=int; using NVSDK_NGX_Version=int;
using VkInstance=void*; using VkPhysicalDevice=void*; using VkDevice=void*; using VkCommandBuffer=void*;
using PFN_vkGetInstanceProcAddr=void*; using PFN_vkGetDeviceProcAddr=void*;
using PFN_NVSDK_NGX_ProgressCallback=void*;
struct NVSDK_NGX_FeatureCommonInfo {};
struct NVSDK_NGX_FeatureDiscoveryInfo {};
struct NVSDK_NGX_FeatureRequirement {};
struct NVSDK_NGX_Handle {};
struct IDXGIAdapter {}; struct ID3D12Device {}; struct ID3D12Resource {};
struct ID3D12GraphicsCommandList { void CopyResource(ID3D12Resource*,ID3D12Resource*) {} };
int nativeCalls=0, parameterWrites=0, releases=0, invalidReleases=0;
ID3D12Resource resource;
struct NVSDK_NGX_Parameter {
 template<class T> int Get(const char*,T*) { return 0; }
 template<class T> int Set(const char*,T) { ++parameterWrites; return 0; }
};
using HMODULE=void*;
void FreeLibrary(HMODULE) {}
void releaseResource(ID3D12Resource*& p) {
 if(p) { if(p==&resource) ++releases; else ++invalidReleases; p=nullptr; }
}
#define SAFE_RELEASE(x) releaseResource(x)
struct Config {
 struct Option { int value=0; int value_or_default() { return value; } };
 Option NvngxFGMakeDepthCopy, NvngxFGShowDebug, NvngxFGDispatchFlags;
 static Config* Instance() { static Config c; return &c; }
};
struct State { ID3D12Device* currentD3D12Device=nullptr; static State& Instance() { static State s; return s; } };
constexpr int D3D12_RESOURCE_STATE_COPY_DEST=1, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE=2, D3D12_RESOURCE_STATE_COPY_SOURCE=3;
bool CreateBufferResource(ID3D12Device*,ID3D12Resource*,int,ID3D12Resource**) { return false; }
void ResourceBarrier(ID3D12GraphicsCommandList*,ID3D12Resource*,int,int) {}
'''

def generate():
    source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_DllProxy.cpp').read_text(encoding='utf-8')
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_DllProxy.h').read_text(encoding='utf-8')
    field=re.search(r'ID3D12Resource\* depthCopy\[2\][^;]*;',header).group()
    destructor=function(header,'~Nvngx_DllProxy()')
    declarations=[]; callbacks=[]; bodies=[]; checks=[]
    for match in re.finditer(r'NVSDK_NGX_Result\s+Nvngx_DllProxy::(\w+)\(([^{}]*?)\)\s*\{',source):
        name,params=match.group(1,2)
        body=function(source,match.group(0)[:-1].rstrip())
        declarations.append(f'NVSDK_NGX_Result {name}({params});\nNVSDK_NGX_Result (*_DLSSG_{name})({params})=nullptr;')
        callbacks.append(f'NVSDK_NGX_Result native_{name}({params}) {{ ++nativeCalls; return 123; }}')
        bodies.append(body)
        args=[]
        for parameter in params.split(',') if params.strip() else []:
            variable=parameter.split()[-1].lstrip('*')
            args.append('&parameters' if variable=='InParameters' else '&handle' if variable=='OutHandle' else '{}')
        args=','.join(args)
        checks.append(f'''
 proxy.available=true;
 before=nativeCalls; parameterWrites=0;
 check(proxy.{name}({args})==-1 && nativeCalls==before && parameterWrites==0);
 proxy._DLSSG_{name}=&native_{name};
 check(proxy.{name}({args})==123 && nativeCalls==before+1);
 proxy.available=false; parameterWrites=0;
 check(proxy.{name}({args})==-1 && nativeCalls==before+1 && parameterWrites==0);
''')
    assert len(bodies)==22
    cls='struct Nvngx_DllProxy {\n'+field+'''
 HMODULE dll=nullptr;
 bool available=true;
 bool isDx12Available() { return available; }
 bool isVulkanAvailable() { return available; }
 Nvngx_DllProxy()=default;
'''+destructor+'\n'+'\n'.join(declarations)+'\n};\n'
    # The real derived classes have user-provided constructors; default-initialize
    # their base in nonzero storage to catch indeterminate depth pointers.
    main=r'''
struct Derived : Nvngx_DllProxy { Derived() {} };
int main() {
 int checks=0; auto check=[&](bool ok) { if(!ok) { std::cerr << "DLL boundary regression at " << checks+1 << '\n'; std::exit(2); } ++checks; };
 alignas(Derived) unsigned char storage[sizeof(Derived)];
 std::memset(storage,0xA5,sizeof(storage));
 auto* fresh=new(storage) Derived;
 check(fresh->depthCopy[0]==nullptr && fresh->depthCopy[1]==nullptr);
 fresh->~Derived();
 check(invalidReleases==0 && releases==0);
 fresh=new(storage) Derived;
 fresh->depthCopy[0]=&resource;
 fresh->~Derived();
 check(invalidReleases==0 && releases==1);
 Nvngx_DllProxy proxy;
 NVSDK_NGX_Parameter parameters; NVSDK_NGX_Handle* handle=nullptr;
 int before=0;
'''+''.join(checks)+'''
 std::cout << "PASS: " << checks << " DLL provider boundary checks\\n";
}
'''
    return PRELUDE+cls+'\n'.join(callbacks+bodies)+main

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True); parser.add_argument('--driver')
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='aurora-dll-boundary-') as folder:
        path=Path(folder); cpp=path/'test.cpp'; exe=path/'test.exe'
        cpp.write_text(generate(),encoding='utf-8')
        cmd=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':
            cmd+=['/nologo','/EHsc','/std:c++20',str(cpp),'/Fe:'+str(exe)]
        else: cmd+=['-std=c++20',str(cpp),'-o',str(exe)]
        subprocess.run(cmd,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
