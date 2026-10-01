"""Actual HUD publication helper, with constructor reentry/failure stand-ins."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "framegen/ProviderPublication.h"
#include <functional>
#include <future>
#include <iostream>
#include <stdexcept>
#include <cstdlib>
int checks=0,constructed=0,destroyed=0;
bool fail=false,unready=false;
std::function<void()> onConstruct;
void check(bool b){if(!b){std::cerr<<"HUD publication check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct ID3D12Device{};
struct HudCopy_Dx12 {
 ID3D12Device* device;bool ready=false;
 HudCopy_Dx12(const char*,ID3D12Device* d):device(d){++constructed;if(onConstruct)onConstruct();if(fail)throw std::runtime_error("construction");ready=!unready;}
 bool IsInit()const{return ready;}
 ~HudCopy_Dx12(){++destroyed;}
};
struct Harness {
 // FIELD
 // HELPER
};
// Exercise the actual HUD and base destructors with counted COM stand-ins.
struct State {bool isShuttingDown=false;static State& Instance(){static State s;return s;}};
struct Resource {int releases=0;void Release(){check(++releases==1);}};
#define SAFE_RELEASE(p) do {if(p){(p)->Release();(p)=nullptr;}}while(false)
constexpr int HudCopy_NUM_OF_HEAPS=2;
struct Heap {Resource* resource=nullptr;void ReleaseHeaps(){SAFE_RELEASE(resource);}~Heap(){ReleaseHeaps();}};
struct Shader_Dx12 {
 bool _init=false;
 Resource *_pipelineState=nullptr,*_rootSignature=nullptr,*_constantBuffer=nullptr;
 ~Shader_Dx12();
};
struct CleanupHud:Shader_Dx12 {
 Heap _frameHeaps[HudCopy_NUM_OF_HEAPS];Resource* _buffer=nullptr;
 ~CleanupHud();
};
// BASE_DESTRUCTOR
// HUD_DESTRUCTOR
int main(){
 ID3D12Device first,second;
 {
  Harness h;
  check(h.GetHudCopy(nullptr)==nullptr&&constructed==0);
  fail=true;bool threw=false;
  try{h.GetHudCopy(&first);}catch(const std::runtime_error&){threw=true;}
  check(threw&&constructed==1);
  fail=false;
  onConstruct=[&]{
   check(h.GetHudCopy(&first)==nullptr);
   auto worker=std::async(std::launch::async,[&]{return h.GetHudCopy(&second);});
   check(worker.get()==nullptr);
  };
  auto* published=h.GetHudCopy(&first);
  onConstruct={};
  check(published&&published->ready&&published->device==&first&&constructed==2);
  check(h.GetHudCopy(&second)==published&&constructed==2&&destroyed==0);
  auto worker=std::async(std::launch::async,[&]{return h.GetHudCopy(&first);});
  check(worker.get()==published&&constructed==2);
 }
 check(destroyed==1);
 {
  Harness h;unready=true;int start=constructed,retired=destroyed;
  for(int i=1;i<=3;++i){check(h.GetHudCopy(&first)==nullptr);check(constructed==start+i&&destroyed==retired+i);}
  unready=false;auto* retry=h.GetHudCopy(&second);
  check(retry&&retry->IsInit()&&retry->device==&second);
  check(h.GetHudCopy(&first)==retry&&constructed==start+4);
 }
 // All partial allocation combinations, then the normal initialized path.
 for(bool ready:{false,true})for(int mask=0;mask<64;++mask){
  Resource r[6];
  {
   CleanupHud h;h._init=ready;
   if(mask&1)h._rootSignature=&r[0];if(mask&2)h._constantBuffer=&r[1];
   if(mask&4)h._pipelineState=&r[2];if(mask&8)h._frameHeaps[0].resource=&r[3];
   if(mask&16)h._frameHeaps[1].resource=&r[4];if(mask&32)h._buffer=&r[5];
  }
  for(int i=0;i<6;++i)check(r[i].releases==((mask>>i)&1));
 }
 std::cout<<"PASS: "<<checks<<" HUD publication checks\n";
}
'''

def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--driver');args=p.parse_args()
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    field=re.search(r'static inline ProviderPublication<HudCopy_Dx12> _hudCopy;',header).group().replace('static inline ','')
    helper=function(header,'static HudCopy_Dx12* GetHudCopy(').replace('static ','',1)
    hud=(ROOT/'OptiScaler/shaders/hud_copy/HudCopy_Dx12.cpp').read_text(encoding='utf-8')
    base=(ROOT/'OptiScaler/shaders/Shader_Dx12.cpp').read_text(encoding='utf-8')
    hud_destructor=function(hud,'HudCopy_Dx12::~HudCopy_Dx12()').replace('HudCopy_Dx12','CleanupHud')
    base_destructor=function(base,'Shader_Dx12::~Shader_Dx12()')
    with tempfile.TemporaryDirectory(prefix='aurora-hud-publication-') as folder:
        path=Path(folder);cpp=path/'test.cpp';exe=path/'test.exe'
        cpp.write_text(PRELUDE.replace('// FIELD',field).replace('// HELPER',helper).replace('// BASE_DESTRUCTOR',base_destructor).replace('// HUD_DESTRUCTOR',hud_destructor),encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else:command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__':main()
