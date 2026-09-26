"""Complete production FFX Create and Release with counted COM and throwing parameters.

No FFX context exists during Create. Tests do not simulate shaders/GPU execution.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include <memory>
#include <atomic>
#include <cstdint>
#include <stdexcept>
#include <iostream>
#include <cstdlib>
#include <new>
bool failHandleAllocation=false;
using NVSDK_NGX_Result=int;using NVSDK_NGX_Feature=int;using ffxContext=void*;
constexpr int NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2,NVSDK_NGX_Result_FAIL_FeatureNotSupported=-3,
 NVSDK_NGX_Result_FAIL_PlatformError=-4,NVSDK_NGX_Feature_FrameGeneration=7,FFX_API_RETURN_OK=0;
#define LOG_WARN(...)
#define IID_PPV_ARGS(x) x
#define FAILED(x) ((x)<0)
struct NVSDK_NGX_Handle {};
struct ID3D12Device {int refs=0;void Release(){--refs;}};
struct ID3D12GraphicsCommandList {
 ID3D12Device* device=nullptr;int error=0;bool outputOnError=false;
 int GetDevice(ID3D12Device** out){if(!error||outputOnError){*out=device;if(device)++device->refs;}return error;}
};
template<class T> struct ComPtr {
 T* p=nullptr;~ComPtr(){if(p)p->Release();}T** operator&(){return &p;}
 T* Detach(){auto* out=p;p=nullptr;return out;}explicit operator bool(){return p!=nullptr;}
};
struct NVSDK_NGX_Parameter {
 int calls=0,throwAt=0;
 int Get(const char*,uint32_t* out){if(++calls==throwAt)throw std::runtime_error("param");*out=128;return 0;}
};
struct FfxApiProxy {static int D3D12_DestroyContext(ffxContext*,void*){std::abort();}};
struct Nvngx_FFX {
 inline static std::atomic_uint32_t lastIdCreated=0;inline static bool ready=true,initThrows=false;
 static bool Init(){if(initThrows)throw std::runtime_error("init");return ready;}
 static int D3D12_CreateFeature(ID3D12GraphicsCommandList*,int,NVSDK_NGX_Parameter*,NVSDK_NGX_Handle**);
 static int D3D12_ReleaseFeature(NVSDK_NGX_Handle*);
};
'''
CHECKS = r'''
int main(){
 int checks=0;auto check=[&](bool ok){if(!ok){std::cerr<<"FFX create check "<<checks+1<<" failed\n";std::exit(2);}++checks;};
 ID3D12Device device;ID3D12GraphicsCommandList cmd;cmd.device=&device;NVSDK_NGX_Parameter params;
 NVSDK_NGX_Handle sentinel,*out=&sentinel;
 auto create=[&]{return Nvngx_FFX::D3D12_CreateFeature(&cmd,7,&params,&out);};
 check(Nvngx_FFX::D3D12_CreateFeature(&cmd,7,&params,nullptr)==-2);
 check(Nvngx_FFX::D3D12_CreateFeature(nullptr,7,&params,&out)==-2&&!out);out=&sentinel;
 check(Nvngx_FFX::D3D12_CreateFeature(&cmd,7,nullptr,&out)==-2&&!out);out=&sentinel;
 check(Nvngx_FFX::D3D12_CreateFeature(&cmd,0,&params,&out)==-3&&!out);
 Nvngx_FFX::ready=false;out=&sentinel;check(create()==-1&&!out&&device.refs==0);Nvngx_FFX::ready=true;
 Nvngx_FFX::initThrows=true;out=&sentinel;bool threw=false;
 try{create();}catch(const std::runtime_error&){threw=true;}
 check(threw&&!out&&device.refs==0);Nvngx_FFX::initThrows=false;
 for(bool writes:{false,true}){cmd.error=-1;cmd.outputOnError=writes;out=&sentinel;
   check(create()==-4&&!out&&device.refs==0);}
 cmd.error=0;cmd.device=nullptr;out=&sentinel;check(create()==-4&&!out);cmd.device=&device;
 for(int i=1;i<=2;++i){params.calls=0;params.throwAt=i;out=&sentinel;threw=false;
   try{create();}catch(const std::runtime_error&){threw=true;}
   check(threw&&!out&&device.refs==0);}
 params.throwAt=0;params.calls=0;
 failHandleAllocation=true;out=&sentinel;threw=false;
 try{create();}catch(const std::bad_alloc&){threw=true;}
 check(threw&&!out&&device.refs==0);failHandleAllocation=false;
 check(create()==0&&out&&device.refs==1);
 auto* h=reinterpret_cast<Nvngx_FFX_Handle*>(out);
 check(h->device==&device&&h->swapchainWidth==128&&h->swapchainHeight==128&&!h->fgContext);
 check(Nvngx_FFX::D3D12_ReleaseFeature(out)==0&&device.refs==0);
 std::cout<<"PASS: "<<checks<<" FFX private creation checks\n";
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    header = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FFX.h').read_text(encoding='utf-8')
    source = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FFX.cpp').read_text(encoding='utf-8')
    types = header[header.index('struct ffxContext_wrap'):header.index('class Nvngx_FFX')]
    # Inject only allocation behavior into the actual handle type, so failure
    # happens at the production make_unique call after GetDevice acquired a ref.
    types = types.replace('struct Nvngx_FFX_Handle\n{', '''struct Nvngx_FFX_Handle
{
 static void* operator new(size_t size){if(failHandleAllocation)throw std::bad_alloc();return ::operator new(size);}
 static void operator delete(void* p){::operator delete(p);}
''')
    bodies = ''.join(function(source, 'NVSDK_NGX_Result Nvngx_FFX::'+n+'(')
                     for n in ('D3D12_CreateFeature', 'D3D12_ReleaseFeature'))
    with tempfile.TemporaryDirectory(prefix='aurora-ffx-create-') as directory:
        path = Path(directory)
        test, exe = path/'test.cpp', path/'test.exe'
        test.write_text(PRELUDE+types+bodies+CHECKS, encoding='utf-8')
        cmd = [args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            cmd += ['/nologo', '/EHsc', '/std:c++20', str(test), '/Fe:'+str(exe)]
        else:
            cmd += ['-std=c++20', str(test), '-o', str(exe)]
        subprocess.run(cmd, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=25)


if __name__ == '__main__':
    main()
