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
bool fail=false;
std::function<void()> onConstruct;
void check(bool b){if(!b){std::cerr<<"HUD publication check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct ID3D12Device{};
struct HudCopy_Dx12 {
 ID3D12Device* device;bool ready=false;
 HudCopy_Dx12(const char*,ID3D12Device* d):device(d){++constructed;if(onConstruct)onConstruct();if(fail)throw std::runtime_error("construction");ready=true;}
 ~HudCopy_Dx12(){++destroyed;}
};
struct Harness {
 // FIELD
 // HELPER
};
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
 std::cout<<"PASS: "<<checks<<" HUD publication checks\n";
}
'''

def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--driver');args=p.parse_args()
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    field=re.search(r'static inline ProviderPublication<HudCopy_Dx12> _hudCopy;',header).group().replace('static inline ','')
    helper=function(header,'static HudCopy_Dx12* GetHudCopy(').replace('static ','',1)
    with tempfile.TemporaryDirectory(prefix='aurora-hud-publication-') as folder:
        path=Path(folder);cpp=path/'test.cpp';exe=path/'test.exe'
        cpp.write_text(PRELUDE.replace('// FIELD',field).replace('// HELPER',helper),encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else:command+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__':main()
