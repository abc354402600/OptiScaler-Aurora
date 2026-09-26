"""Production FFX wrapper/destructor, full Release and Evaluate guard prefix.

FfxApiProxy and COM stand-ins expose failure, exception and destruction order.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include <memory>
#include <functional>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <cstdlib>
using ffxContext=void*;using NVSDK_NGX_Result=int;
constexpr int FFX_API_RETURN_OK=0,NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2,NVSDK_NGX_Result_FAIL_FeatureNotFound=-3;
#define LOG_WARN(...)
struct NVSDK_NGX_Handle{};struct ID3D12GraphicsCommandList{};struct NVSDK_NGX_Parameter{};
using PFN_NVSDK_NGX_ProgressCallback=void*;
int checks=0,destroys=0,releases=0;bool alive=true;
void check(bool ok){if(!ok){std::cerr<<"FFX release check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct ID3D12Device{void Release(){check(alive);alive=false;++releases;}};
struct FfxApiProxy{
 inline static std::function<int(ffxContext*)> callback;
 static int D3D12_DestroyContext(ffxContext* ctx,void*){check(alive);++destroys;return callback?callback(ctx):0;}
};
struct Nvngx_FFX{
 static NVSDK_NGX_Result D3D12_ReleaseFeature(NVSDK_NGX_Handle*);
 static NVSDK_NGX_Result D3D12_EvaluateFeature(ID3D12GraphicsCommandList*,const NVSDK_NGX_Handle*,NVSDK_NGX_Parameter*,PFN_NVSDK_NGX_ProgressCallback);
};
'''
CHECKS=r'''
int main(){
 ID3D12Device device;NVSDK_NGX_Parameter params;
 auto make=[&](bool context){alive=true;auto* h=new Nvngx_FFX_Handle{};h->device=&device;
   if(context){h->fgContext=std::make_unique<ffxContext_wrap>();h->fgContext->ctx=&device;}return h;};
 auto release=[](auto* h){return Nvngx_FFX::D3D12_ReleaseFeature(reinterpret_cast<NVSDK_NGX_Handle*>(h));};
 auto evaluate=[&](auto* h){return Nvngx_FFX::D3D12_EvaluateFeature(nullptr,reinterpret_cast<NVSDK_NGX_Handle*>(h),&params,nullptr);};
 check(Nvngx_FFX::D3D12_ReleaseFeature(nullptr)==-2);
 auto* h=make(false);check(evaluate(h)==42);int before=destroys;check(release(h)==0&&destroys==before&&!alive);
 h=make(true);before=destroys;check(release(h)==0&&destroys==before+1&&!alive); // No destructor double-destroy.
 h=make(true);int refs=releases;before=destroys;FfxApiProxy::callback=[](auto*){return -1;};
 check(release(h)==-1&&alive&&releases==refs&&destroys==before+1&&h->releaseStarted);
 check(evaluate(h)==-3);FfxApiProxy::callback={};check(release(h)==0&&!alive&&destroys==before+2);
 h=make(true);refs=releases;before=destroys;
 FfxApiProxy::callback=[](auto*)->int{throw std::runtime_error("destroy");};bool threw=false;
 try{release(h);}catch(const std::runtime_error&){threw=true;}
 check(threw&&alive&&releases==refs&&h->releaseStarted&&evaluate(h)==-3);
 FfxApiProxy::callback={};check(release(h)==0&&destroys==before+2&&!alive);
 // SDK may clear the context even on error. Retry still owns the wrapper/device,
 // but must not call destruction on a null context.
 h=make(true);before=destroys;FfxApiProxy::callback=[](auto* p){*p=nullptr;return -1;};
 check(release(h)==-1&&alive&&!h->fgContext->ctx&&evaluate(h)==-3);
 FfxApiProxy::callback={};check(release(h)==0&&destroys==before+1&&!alive);
 std::cout<<"PASS: "<<checks<<" FFX release ordering checks\n";
}
'''


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver');args=parser.parse_args()
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_Ffx.h').read_text(encoding='utf-8')
    source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_Ffx.cpp').read_text(encoding='utf-8')
    types=header[header.index('struct ffxContext_wrap'):header.index('class Nvngx_FFX')]
    release=function(source,'NVSDK_NGX_Result Nvngx_FFX::D3D12_ReleaseFeature(')
    evaluate=function(source,'NVSDK_NGX_Result Nvngx_FFX::D3D12_EvaluateFeature(')
    evaluate=evaluate[:evaluate.index('    if (!Init())')]+'return 42;\n}\n'
    with tempfile.TemporaryDirectory(prefix='aurora-ffx-release-') as d:
        path=Path(d);test=path/'test.cpp';exe=path/'test.exe';test.write_text(PRELUDE+types+release+evaluate+CHECKS,encoding='utf-8')
        cmd=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':cmd+=['/nologo','/EHsc','/std:c++20',str(test),'/Fe:'+str(exe)]
        else:cmd+=['-std=c++20',str(test),'-o',str(exe)]
        subprocess.run(cmd,cwd=path,check=True);subprocess.run([str(exe)],cwd=path,check=True,timeout=25)


if __name__=='__main__':main()
