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
#include <functional>
#include <future>
#include <stdexcept>
#include "framegen/ProviderCallAdmission.h"
using NVSDK_NGX_Result=int;
constexpr int NVSDK_NGX_Result_Success=0, NVSDK_NGX_Result_Fail=-1;
constexpr int NVSDK_NGX_Result_FAIL_NotInitialized=-2;
using NVSDK_NGX_Feature=int; using NVSDK_NGX_Version=int;
using VkInstance=void*; using VkPhysicalDevice=void*; using VkDevice=void*; using VkCommandBuffer=void*;
using PFN_vkGetInstanceProcAddr=void*; using PFN_vkGetDeviceProcAddr=void*;
using PFN_NVSDK_NGX_ProgressCallback=void*;
struct NVSDK_NGX_FeatureCommonInfo {};
struct NVSDK_NGX_FeatureDiscoveryInfo {};
struct NVSDK_NGX_FeatureRequirement {};
struct NVSDK_NGX_Handle {};
struct IDXGIAdapter {}; struct ID3D12Device {}; struct ID3D12Resource {};
ID3D12Device commandDevice,globalDevice;
namespace Microsoft::WRL {template<class T>struct ComPtr {
 T* p=nullptr;T** operator&(){return &p;}T* Get(){return p;}explicit operator bool(){return p!=nullptr;}
};}
#define IID_PPV_ARGS(p) (p)
#define SUCCEEDED(r) ((r)>=0)
int copies=0, barriers=0, depthWrites=0;
bool supplyDepth=false, bufferSuccess=false;
struct ID3D12GraphicsCommandList {
 int queryResult=0;ID3D12Device* owner=&commandDevice;
 int GetDevice(ID3D12Device** out){*out=owner;return queryResult;}
 void CopyResource(ID3D12Resource*,ID3D12Resource*) { ++copies; }
};
std::function<void()> onEvaluate;
int nativeCalls=0, parameterWrites=0, releases=0, invalidReleases=0;
ID3D12Resource resource;
struct NVSDK_NGX_Parameter {
 void Get(const char*,ID3D12Resource** out) { *out=supplyDepth?&resource:nullptr; }
 template<class T> int Get(const char*,T*) { return 0; }
 template<class T> int Set(const char* name,T) { if(std::strcmp(name,"DLSSG.Depth")==0)++depthWrites; ++parameterWrites; return 0; }
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
int bufferCalls=0;ID3D12Device* lastDevice=nullptr;ID3D12Resource** lastTarget=nullptr;
bool CreateBufferResource(ID3D12Device* device,ID3D12Resource*,int,ID3D12Resource** target) { ++bufferCalls;lastDevice=device;lastTarget=target;return bufferSuccess; }
void ResourceBarrier(ID3D12GraphicsCommandList*,ID3D12Resource*,int,int) { ++barriers; }
'''

def generate(negative_control=None):
    source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_DllProxy.cpp').read_text(encoding='utf-8')
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_DllProxy.h').read_text(encoding='utf-8')
    field=re.search(r'ID3D12Resource\* depthCopy\[2\][^;]*;',header).group()
    field+='\n'+re.search(r'size_t _depthCopyIndex[^;]*;',header).group()
    field+='\n'+re.search(r'ProviderCallAdmission _depthCopyCalls;',header).group()
    destructor=function(header,'~Nvngx_DllProxy()')
    declarations=[]; callbacks=[]; bodies=[]; checks=[]
    for match in re.finditer(r'NVSDK_NGX_Result\s+Nvngx_DllProxy::(\w+)\(([^{}]*?)\)\s*\{',source):
        name,params=match.group(1,2)
        body=function(source,match.group(0)[:-1].rstrip())
        if name=='D3D12_EvaluateFeature' and negative_control=='no-admission':
            body=body.replace('if (dlssgDepth && !copyLease)','if (false)')
        declarations.append(f'NVSDK_NGX_Result {name}({params});\nNVSDK_NGX_Result (*_DLSSG_{name})({params})=nullptr;')
        hook='if(onEvaluate)onEvaluate();' if name=='D3D12_EvaluateFeature' else ''
        callbacks.append(f'NVSDK_NGX_Result native_{name}({params}) {{ ++nativeCalls; {hook} return 123; }}')
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
 proxy.available=true;
 Config::Instance()->NvngxFGMakeDepthCopy.value=1;
 supplyDepth=true;
 ID3D12GraphicsCommandList command;
 for(bool success:{false,true}) {
  for(bool stale:{false,true}) {
   bufferSuccess=success;
   proxy.depthCopy[0]=proxy.depthCopy[1]=stale?&resource:nullptr;
   copies=barriers=depthWrites=0;
   int native=nativeCalls;
   check(proxy.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr)==123 && nativeCalls==native+1);
   bool shouldCopy=success && stale;
   check(copies==(shouldCopy?1:0) && barriers==(shouldCopy?2:0) && depthWrites==(shouldCopy?1:0));
  }
 }
 State::Instance().currentD3D12Device=&globalDevice;
 bufferSuccess=true;proxy.depthCopy[0]=proxy.depthCopy[1]=&resource;
 check(proxy.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr)==123&&lastDevice==&commandDevice);
 for(int mode=0;mode<3;++mode){
  command.queryResult=mode==0?-1:0;command.owner=mode==1?nullptr:&commandDevice;
  copies=barriers=depthWrites=bufferCalls=0;
  check(proxy.D3D12_EvaluateFeature(mode==2?nullptr:&command,nullptr,&parameters,nullptr)==123);
  check(copies==0&&barriers==0&&depthWrites==0&&bufferCalls==0);
 }
 command.queryResult=0;command.owner=&commandDevice;
 before=nativeCalls;
 check(proxy.D3D12_EvaluateFeature(&command,nullptr,nullptr,nullptr)==-1&&nativeCalls==before);
 bool inside=false;
 onEvaluate=[&]{
  if(inside)return;inside=true;
  int copyBefore=copies, nativeBefore=nativeCalls;
  check(proxy.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr)==-2);
  auto worker=std::async(std::launch::async,[&]{return proxy.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr);});
  check(worker.get()==-2&&copies==copyBefore&&nativeCalls==nativeBefore);
  inside=false;
 };
 check(proxy.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr)==123);
 onEvaluate=[] {throw std::runtime_error("SDK exception");};
 bool threw=false;try{proxy.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr);}catch(const std::runtime_error&){threw=true;}
 check(threw);
 onEvaluate={};check(proxy.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr)==123);
 Derived independent;
 check(independent._depthCopyIndex==0&&independent._depthCopyCalls.TryTransition());
 independent._DLSSG_D3D12_EvaluateFeature=&native_D3D12_EvaluateFeature;
 check(independent.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr)==123&&lastTarget==&independent.depthCopy[0]);
 check(independent.D3D12_EvaluateFeature(&command,nullptr,&parameters,nullptr)==123&&lastTarget==&independent.depthCopy[1]);
 std::cout << "PASS: " << checks << " DLL provider boundary checks\\n";
}
'''
    return PRELUDE+cls+'\n'.join(callbacks+bodies)+main

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True); parser.add_argument('--driver')
    parser.add_argument('--negative-control',choices=['no-admission'])
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='aurora-dll-boundary-') as folder:
        path=Path(folder); cpp=path/'test.cpp'; exe=path/'test.exe'
        cpp.write_text(generate(args.negative_control),encoding='utf-8')
        cmd=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':
            cmd+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else: cmd+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(cmd,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
