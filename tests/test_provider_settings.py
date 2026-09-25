"""Execute complete production Nukem setters and provider UI routes.

The real transition admission is used; the OS environment and DLL callback are
stand-ins. This tests CPU call ordering, not the DLL's configuration internals.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include "framegen/ProviderCallAdmission.h"
#include <unordered_set>
#include <functional>
#include <future>
#include <chrono>
#include <string>
#include <stdexcept>
#include <iostream>
#include <cstdlib>
enum class FGNvngxReplacement { Nukems, Other };
int writes=0,refreshes=0,checks=0;
bool environmentOK=true;
std::wstring key,value;
std::function<void()> callback;
bool SetEnvironmentVariableW(const wchar_t* k,const wchar_t* v) {
 ++writes;key=k;value=v;return environmentOK;
}
void refresh(){++refreshes;if(callback)callback();}
void check(bool ok){if(!ok){std::cerr<<"settings check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct Base { FGNvngxReplacement type=FGNvngxReplacement::Nukems; FGNvngxReplacement getType(){return type;} };
struct Nvngx_Nukems:Base {
 void (*_refreshGlobalConfiguration)()=refresh;
 bool is120orNewer() const {return _refreshGlobalConfiguration!=nullptr;}
 bool setSetting(const wchar_t*,const wchar_t*);
 bool setDebugView(bool);bool setInterpolatedOnly(bool);
} provider;
struct Nvngx_FG {
 inline static ProviderCallAdmission _calls;
 inline static std::unordered_set<void*> _dx12InitAttempts,_vulkanInitAttempts;
 struct Publication {bool ready;int peeks;Base* Peek(){++peeks;return ready?&provider:nullptr;}};
 inline static Publication _provider{true,0};
 static bool setDebugView(bool);static bool setInterpolatedOnly(bool);
};
'''
CHECKS = r'''
int main(){
 for(auto setter:{Nvngx_FG::setDebugView,Nvngx_FG::setInterpolatedOnly}) {
  int before=writes;
  check(!setter(true)&&writes==before); // No Init footprint: no lazy load or environment write.
  Nvngx_FG::_dx12InitAttempts.insert(&provider);
  int peeks=Nvngx_FG::_provider.peeks;
  {auto busy=Nvngx_FG::_calls.TryOperation();check(!setter(true)&&writes==before&&Nvngx_FG::_provider.peeks==peeks);}
  {auto busy=Nvngx_FG::_calls.TryTransition();check(!setter(true)&&writes==before&&Nvngx_FG::_provider.peeks==peeks);}
  Nvngx_FG::_provider.ready=false;check(!setter(true)&&writes==before);Nvngx_FG::_provider.ready=true;
  provider.type=FGNvngxReplacement::Other;check(!setter(true)&&writes==before);provider.type=FGNvngxReplacement::Nukems;
  provider._refreshGlobalConfiguration=nullptr;check(!setter(true)&&writes==before);provider._refreshGlobalConfiguration=refresh;
  environmentOK=false;int calls=refreshes;
  check(!setter(true)&&writes==before+1&&refreshes==calls);environmentOK=true;
  callback=[setter]{
   auto work=std::async(std::launch::async,[setter]{
    return !setter(false)&&!Nvngx_FG::_calls.TryOperation()&&!Nvngx_FG::_calls.TryTransition();
   });
   check(work.wait_for(std::chrono::seconds(2))==std::future_status::ready&&work.get());
  };
  check(setter(true)&&value==L"1"&&refreshes==calls+1);
  check(key==(setter==Nvngx_FG::setDebugView?L"DLSSGTOFSR3_EnableDebugOverlay":L"DLSSGTOFSR3_EnableInterpolatedFramesOnly"));
  callback={};check(setter(false)&&value.empty()&&refreshes==calls+2);
  check(bool(Nvngx_FG::_calls.TryOperation())&&bool(Nvngx_FG::_calls.TryOperation()));
  callback=[]{throw std::runtime_error("DLL callback");};bool threw=false;
  try{setter(true);}catch(const std::runtime_error&){threw=true;}
  check(threw&&bool(Nvngx_FG::_calls.TryTransition()));callback={};
  Nvngx_FG::_dx12InitAttempts.clear();Nvngx_FG::_vulkanInitAttempts.insert(&provider);
  check(setter(true));Nvngx_FG::_vulkanInitAttempts.clear();
  before=writes;check(!setter(false)&&writes==before);
 }
 std::cout<<"PASS: "<<checks<<" provider settings checks\n";
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    proxy = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.cpp').read_text(encoding='utf-8')
    nukem = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_Nukems.cpp').read_text(encoding='utf-8')
    cpp = PRELUDE
    for name in ('setDebugView', 'setInterpolatedOnly'):
        cpp += function(proxy, 'bool Nvngx_FG::'+name+'(')
        cpp += function(nukem, 'bool Nvngx_Nukems::'+name+'(')
    cpp += function(nukem, 'bool Nvngx_Nukems::setSetting(') + CHECKS
    with tempfile.TemporaryDirectory(prefix='aurora-provider-settings-') as directory:
        path = Path(directory)
        test, exe = path/'test.cpp', path/'test.exe'
        test.write_text(cpp, encoding='utf-8')
        command = [args.compiler] + ([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            command += ['/nologo', '/EHsc', '/std:c++20', '/I'+str(ROOT/'OptiScaler'), str(test), '/Fe:'+str(exe)]
        else:
            command += ['-std=c++20', '-pthread', '-I'+str(ROOT/'OptiScaler'), str(test), '-o', str(exe)]
        subprocess.run(command, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=25)


if __name__ == '__main__':
    main()
