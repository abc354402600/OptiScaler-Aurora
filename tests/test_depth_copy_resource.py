"""Actual depth allocation helper; counted COM/descriptor stand-ins, no GPU claims."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include <cstdlib>
#include <iostream>
#include <cstdint>
using HRESULT=int;using UINT64=uint64_t;using D3D12_RESOURCE_STATES=int;
using D3D12_HEAP_FLAGS=int;
constexpr int S_OK=0,D3D12_HEAP_FLAG_NONE=0;
struct D3D12_HEAP_PROPERTIES {};
struct Desc {
 int Dimension=2;uint64_t Width=1920;int Height=1080,DepthOrArraySize=1,MipLevels=1,Format=42,Flags=0;
 struct {int Count=1,Quality=0;} SampleDesc;
};
int checks=0;
void check(bool b){if(!b){std::cerr<<"depth resource check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct ID3D12Resource;
struct ID3D12Device {
 int refs=1,creates=0,result=0;ID3D12Resource* output=nullptr;
 void AddRef(){++refs;}void Release(){--refs;}
 int CreateCommittedResource(D3D12_HEAP_PROPERTIES*,int,Desc*,int,void*,ID3D12Resource** out){++creates;*out=output;return result;}
};
struct ID3D12Resource {
 ID3D12Device* owner=nullptr;int query=0,heapResult=0,releases=0,heapCalls=0;Desc desc;
 int GetDevice(ID3D12Device** out){*out=owner;if(owner)owner->AddRef();return query;}
 Desc GetDesc(){return desc;}
 int GetHeapProperties(D3D12_HEAP_PROPERTIES*,D3D12_HEAP_FLAGS*){++heapCalls;return heapResult;}
 void Release(){++releases;}
};
namespace Microsoft::WRL {template<class T>struct ComPtr {
 T* p=nullptr;T** operator&(){return &p;}T* Get(){return p;}
 ~ComPtr(){if(p)p->Release();}
};}
#define IID_PPV_ARGS(p) (p)
#define SUCCEEDED(r) ((r)>=0)
#define LOG_ERROR(...) ((void)0)
#define LOG_DEBUG(...) ((void)0)
// HELPER
int main(){
 ID3D12Device device,other;ID3D12Resource source,target;source.owner=target.owner=&device;
 ID3D12Resource* slot=&target;
 check(!CreateBufferResource(nullptr,&source,0,&slot));
 check(!CreateBufferResource(&device,nullptr,0,&slot));
 check(CreateBufferResource(&device,&source,0,&slot)&&slot==&target&&device.creates==0);
 for(int field=0;field<9;++field){
  target.desc=source.desc;
  switch(field){
   case 0:++target.desc.Dimension;break;case 1:++target.desc.Width;break;case 2:++target.desc.Height;break;
   case 3:++target.desc.DepthOrArraySize;break;case 4:++target.desc.MipLevels;break;case 5:++target.desc.Format;break;
   case 6:++target.desc.SampleDesc.Count;break;case 7:++target.desc.SampleDesc.Quality;break;case 8:++target.desc.Flags;break;
  }
  check(!CreateBufferResource(&device,&source,0,&slot));
  check(slot==&target&&target.releases==0&&device.creates==0);
 }
 target.desc=source.desc;
 check(!CreateBufferResource(&device,&source,0,nullptr));
 check(!CreateBufferResource(&device,&target,0,&slot)&&slot==&target&&target.releases==0);
 for(auto* child:{&source,&target})for(int mode=0;mode<3;++mode){
  child->owner=mode==0?&other:mode==1?nullptr:&device;child->query=mode==2?-1:0;
  check(!CreateBufferResource(&device,&source,0,&slot));
  check(device.refs==1&&other.refs==1&&slot==&target&&target.releases==0);
  child->owner=&device;child->query=0;
 }
 check(CreateBufferResource(&device,&source,0,&slot));
 slot=nullptr;source.heapResult=-1;
 check(!CreateBufferResource(&device,&source,0,&slot)&&device.creates==0&&slot==nullptr);
 source.heapResult=0;device.result=-1;
 check(!CreateBufferResource(&device,&source,0,&slot)&&device.creates==1&&slot==nullptr);
 device.result=0;device.output=&target;
 check(CreateBufferResource(&device,&source,0,&slot)&&device.creates==2&&slot==&target);
 check(CreateBufferResource(&device,&source,0,&slot)&&device.creates==2);
 check(device.refs==1&&other.refs==1&&target.releases==0);
 std::cout<<"PASS: "<<checks<<" depth resource ownership checks\n";
}
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True)
    parser.add_argument('--driver')
    parser.add_argument('--source-ref',help='Optional historical source for a negative control')
    args=parser.parse_args()
    name='OptiScaler/framegen/nvngx/Nvngx_DllProxy.cpp'
    source=(subprocess.check_output(['git','show',args.source_ref+':'+name],cwd=ROOT,text=True,encoding='utf-8')
            if args.source_ref else (ROOT/name).read_text(encoding='utf-8'))
    body=function(source,'static bool CreateBufferResource(')
    with tempfile.TemporaryDirectory(prefix='aurora-depth-resource-') as folder:
        path=Path(folder);cpp=path/'test.cpp';exe=path/'test.exe'
        cpp.write_text(PRELUDE.replace('// HELPER',body),encoding='utf-8')
        cmd=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':cmd+=['/nologo','/EHsc','/std:c++20',str(cpp),'/Fe:'+str(exe)]
        else:cmd+=['-std=c++20',str(cpp),'-o',str(exe)]
        subprocess.run(cmd,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)


if __name__=='__main__':main()
