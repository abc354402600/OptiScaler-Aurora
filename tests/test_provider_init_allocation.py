"""Actual initialization ledger helper under STL allocation and SDK failures."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include <unordered_set>
#include <utility>
#include <new>
#include <cstdlib>
#include <iostream>
using NVSDK_NGX_Result=int;
constexpr int NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_FAIL_NotInitialized=-7;
static thread_local int budget=-1;
void* operator new(size_t n){
 if(budget==0)throw std::bad_alloc();if(budget>0)--budget;
 if(auto* p=std::malloc(n?n:1))return p;throw std::bad_alloc();
}
void operator delete(void* p)noexcept{std::free(p);}
void operator delete(void* p,size_t)noexcept{std::free(p);}
'''
CHECKS = r'''
int main(){
 int checks=0,a=0;auto check=[&](bool ok){if(!ok){std::cerr<<"Init allocation check "<<checks+1<<" failed\n";std::exit(2);}++checks;};
 bool sawFailure=false,sawSuccess=false;
 for(int allowed=0;allowed<10;++allowed){
  std::unordered_set<int*> attempts,ready;int calls=0,result=-1;bool threw=false;
  budget=allowed;
  try{result=Test::InitializeProvider(attempts,ready,&a,[&]{++calls;budget=0;return 0;});}
  catch(const std::bad_alloc&){threw=true;}
  budget=-1;
  if(threw){sawFailure=true;check(calls==0&&attempts.empty()&&ready.empty());}
  else{sawSuccess=true;check(result==0&&calls==1&&attempts.contains(&a)&&ready.contains(&a));}
 }
 check(sawFailure&&sawSuccess);
 for(bool sdkThrows:{false,true}){
  std::unordered_set<int*> attempts,ready;bool threw=false;int result=0,calls=0;
  try{result=Test::InitializeProvider(attempts,ready,&a,[&]{++calls;budget=0;if(sdkThrows)throw 17;return -8;});}
  catch(int){threw=true;}
  budget=-1;
  check((sdkThrows?threw:result==-7)&&attempts.contains(&a)&&ready.empty());
  budget=0;result=Test::InitializeProvider(attempts,ready,&a,[&]{++calls;return 0;});budget=-1;
  check(result==-7&&calls==1); // No retry or allocation against unresolved state.
 }
 std::unordered_set<int*> attempts,ready;int calls=0;
 check(Test::InitializeProvider(attempts,ready,&a,[&]{++calls;return 0;})==0);
 budget=0;int result=Test::InitializeProvider(attempts,ready,&a,[&]{++calls;return 0;});budget=-1;
 check(result==0&&calls==1); // Idempotent repeat requires no allocation/SDK call.
 std::cout<<"PASS: "<<checks<<" provider Init allocation checks\n";
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    header = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    helper = function(header, 'template <typename Device, typename Callback>')
    with tempfile.TemporaryDirectory(prefix='aurora-init-alloc-') as directory:
        path = Path(directory)
        cpp, exe = path/'test.cpp', path/'test.exe'
        cpp.write_text(PRELUDE+'\nstruct Test {\n'+helper+'\n};\n'+CHECKS, encoding='utf-8')
        command = [args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            command += ['/nologo', '/EHsc', '/std:c++20', str(cpp), '/Fe:'+str(exe)]
        else:
            command += ['-std=c++20', str(cpp), '-o', str(exe)]
        subprocess.run(command, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=25)


if __name__ == '__main__':
    main()
