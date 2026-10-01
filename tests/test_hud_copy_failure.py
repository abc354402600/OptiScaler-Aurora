"""Execute production HUD Dispatch with CPU command/resource stand-ins."""
import argparse
import re
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <functional>
#include <vector>
#include <future>
#include "framegen/ProviderCallAdmission.h"
using UINT=unsigned;
using D3D12_RESOURCE_STATES=int;
constexpr int D3D12_RESOURCE_STATE_COPY_DEST=1, D3D12_RESOURCE_STATE_COPY_SOURCE=2,
 D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE=3, D3D12_RESOURCE_STATE_UNORDERED_ACCESS=4;
constexpr int D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET=1,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS=2,
 D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS=4,HudCopy_NUM_OF_HEAPS=2;
#define LOG_DEBUG(...)
#define LOG_ERROR(...)
#ifndef _countof
#define _countof(x) (sizeof(x)/sizeof(x[0]))
#endif
int checks=0,barriers=0,copies=0,dispatches=0;
bool constantsReady=true,testingReentry=false;
std::function<void()> onConstants;
void check(bool ok){if(!ok){std::cerr<<"HUD failure check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct Desc {uint64_t Width=128; unsigned Height=64,Dimension=3,DepthOrArraySize=1,MipLevels=1,Format=28;
 struct Sample {unsigned Count=1,Quality=0;} SampleDesc;};
struct ID3D12Device {int refs=0; void Release(){--refs;}} primaryDevice,otherDevice;
struct DeviceChild {
 ID3D12Device* owner=&primaryDevice; int queryResult=0;
 int GetDevice(ID3D12Device** out){*out=queryResult<0?nullptr:owner;if(*out)++(*out)->refs;return queryResult;}
};
namespace Microsoft::WRL {template<class T>struct ComPtr {
 T* value=nullptr;~ComPtr(){if(value)value->Release();}
 T** operator&(){return &value;}T* Get()const{return value;}
};}
#define IID_PPV_ARGS(p) p
#define SUCCEEDED(hr) ((hr)>=0)
struct ID3D12Resource : DeviceChild {int state=1; Desc desc; Desc GetDesc(){return desc;} void SetName(const wchar_t*){}};
struct ID3D12DescriptorHeap {};
struct ID3D12GraphicsCommandList : DeviceChild {
 void CopyResource(ID3D12Resource* target,ID3D12Resource* source){check(target->state==1&&source->state==2);++copies;}
 void SetDescriptorHeaps(unsigned,ID3D12DescriptorHeap**){}
 void SetComputeRootSignature(void*){} void SetPipelineState(void*){}
 void SetComputeRootDescriptorTable(int,int){}
 void Dispatch(UINT,UINT,int){++dispatches;}
};
struct FrameDescriptorHeap {
 int GetSrvCPU(int){return 0;} int GetUavCPU(int){return 0;} int GetCbvCPU(int){return 0;}
 ID3D12DescriptorHeap* GetHeapCSU(){return nullptr;} int GetTableGPUStart(){return 0;}
};
struct ScopedGpuTime_Dx12 {ScopedGpuTime_Dx12(int*,ID3D12GraphicsCommandList*){}};
struct Shader_Dx12 {
 static bool CreateBufferResource(void*,ID3D12Resource*,int,ID3D12Resource**,int){return false;}
};
struct HudCopy_Dx12 {
 // DISPATCH_ADMISSION
 bool _init=true; ID3D12Device* _device=&primaryDevice; std::unique_ptr<int> GpuTime;
 int _counter=0; FrameDescriptorHeap _frameHeaps[2]; ID3D12Resource* _buffer=nullptr;
 ID3D12Resource* _constantBuffer=nullptr; void* _rootSignature=nullptr; void* _pipelineState=nullptr;
 std::string _name; unsigned InNumThreadsX=16,InNumThreadsY=16;
 struct InternalCompareParams {float DiffThreshold=0;};
 static void ResourceBarrier(ID3D12GraphicsCommandList*,ID3D12Resource* r,int before,int after){check(r->state==before);r->state=after;++barriers;}
 static void CreateShaderResourceView(void*,ID3D12Resource*,int){}
 static void CreateUnorderedAccessView(void*,ID3D12Resource*,int,int){}
 static bool CreateConstantsBuffer(void*,ID3D12Resource*,InternalCompareParams,int){
  if(onConstants&&!testingReentry){testingReentry=true;onConstants();testingReentry=false;}
  return constantsReady;
 }
 // DISPATCH
};
int main(){
 HudCopy_Dx12 copy;ID3D12Resource buffer,hudless,present;ID3D12GraphicsCommandList commands;
 copy._buffer=&buffer;
 for(int presentState:{1,3,4})for(int hudlessState:{1,3,4}){
  buffer.state=1;present.state=presentState;hudless.state=hudlessState;
  constantsReady=false;barriers=copies=dispatches=0;
  check(!copy.Dispatch(&commands,&hudless,&present,hudlessState,presentState,0.03f));
  check(present.state==presentState&&hudless.state==hudlessState&&buffer.state==1);
  check(dispatches==0);
  // Failure must not poison a later call on the same resources.
  constantsReady=true;
  check(copy.Dispatch(&commands,&hudless,&present,hudlessState,presentState,0.03f));
  check(present.state==presentState&&hudless.state==hudlessState&&buffer.state==1);
  check(dispatches==1);
 }
 std::vector<std::function<void(Desc&)>> changes={
  [](Desc& d){++d.Width;},[](Desc& d){++d.Height;},[](Desc& d){++d.Dimension;},
  [](Desc& d){++d.DepthOrArraySize;},[](Desc& d){++d.MipLevels;},[](Desc& d){++d.Format;},
  [](Desc& d){++d.SampleDesc.Count;},[](Desc& d){++d.SampleDesc.Quality;}
 };
 for(auto& change:changes){
  present.desc={};change(present.desc);
  buffer.state=1;present.state=3;hudless.state=1;
  barriers=copies=dispatches=0;
  auto* retained=copy._buffer;
  check(!copy.Dispatch(&commands,&hudless,&present,1,3,0.03f));
  check(barriers==0&&copies==0&&dispatches==0&&copy._buffer==retained);
  check(buffer.state==1&&present.state==3&&hudless.state==1);
  present.desc={};
  check(copy.Dispatch(&commands,&hudless,&present,1,3,0.03f));
 }
 for(DeviceChild* child:{static_cast<DeviceChild*>(&commands),static_cast<DeviceChild*>(&present),
                        static_cast<DeviceChild*>(&hudless),static_cast<DeviceChild*>(&buffer)}){
  for(int mode:{0,1,2}){
   child->owner=mode==0?&otherDevice:mode==1?&primaryDevice:nullptr;
   child->queryResult=mode==1?-1:0;
   barriers=copies=dispatches=0;
   check(!copy.Dispatch(&commands,&hudless,&present,1,3,0.03f));
   check(barriers==0&&copies==0&&dispatches==0);
   check(primaryDevice.refs==0&&otherDevice.refs==0);
   child->owner=&primaryDevice;child->queryResult=0;
   check(copy.Dispatch(&commands,&hudless,&present,1,3,0.03f));
   check(primaryDevice.refs==0&&otherDevice.refs==0);
  }
 }
 onConstants=[&]{
  int oldBarriers=barriers,oldCopies=copies,oldDispatches=dispatches;
  check(!copy.Dispatch(&commands,&hudless,&present,1,3,0.03f));
  auto worker=std::async(std::launch::async,[&]{return copy.Dispatch(&commands,&hudless,&present,1,3,0.03f);});
  check(!worker.get());
  check(barriers==oldBarriers&&copies==oldCopies&&dispatches==oldDispatches);
 };
 check(copy.Dispatch(&commands,&hudless,&present,1,3,0.03f));
 onConstants={};
 check(copy.Dispatch(&commands,&hudless,&present,1,3,0.03f));
 std::cout<<"PASS: "<<checks<<" HUD Dispatch failure-state checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True)
    parser.add_argument('--driver')
    args=parser.parse_args()
    source=(ROOT/'OptiScaler/shaders/hud_copy/HudCopy_Dx12.cpp').read_text(encoding='utf-8')
    dispatch=function(source,'bool HudCopy_Dx12::Dispatch(').replace('HudCopy_Dx12::Dispatch','Dispatch',1)
    with tempfile.TemporaryDirectory(prefix='aurora-hud-failure-') as folder:
        path=Path(folder); cpp=path/'test.cpp'; exe=path/'test.exe'
        header=(ROOT/'OptiScaler/shaders/hud_copy/HudCopy_Dx12.h').read_text(encoding='utf-8')
        admission=re.search(r'ProviderCallAdmission _dispatchCalls;',header).group()
        cpp.write_text(PRELUDE.replace('// DISPATCH_ADMISSION',admission).replace('// DISPATCH',dispatch),encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':
            command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else:command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__':main()
