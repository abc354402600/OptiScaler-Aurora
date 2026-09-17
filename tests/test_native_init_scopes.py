"""Validate actual delegated-Init skip scopes across threads and exception unwind."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include <future>
#include <chrono>
#include <stdexcept>
#include <cstdlib>
#include <iostream>
int checks=0;
void check(bool ok) { if(!ok) { std::cerr << "Init scope check " << checks+1 << " failed\n"; std::exit(2); } ++checks; }
'''

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--compiler',required=True); parser.add_argument('--driver')
    args=parser.parse_args(); cpp=PRELUDE; checks=[]
    for api in ('Dx11','Dx12','Vk'):
        source=(ROOT/f'OptiScaler/inputs/NVNGX_DLSS_{api}.cpp').read_text(encoding='utf-8')
        flag=re.search(r'static (?:thread_local )?bool _skipInit = false;',source).group(0)
        scope=function(source,'class ScopedInit'+api)+';'
        cpp+='\nnamespace '+api+' {\n'+flag+'\n'+scope+'\n}\n'
        checks.append(f'''
        {{
          using namespace {api};
          check(!_skipInit);
          {{
            ScopedInit{api} outer;
            check(_skipInit);
            {{ ScopedInit{api} inner; check(_skipInit); }}
            check(_skipInit);
            auto other=std::async(std::launch::async, [] {{
              if(_skipInit) return false;
              {{ ScopedInit{api} worker; if(!_skipInit) return false;
                 {{ ScopedInit{api} nested; if(!_skipInit) return false; }}
                 if(!_skipInit) return false;
              }}
              return !_skipInit;
            }});
            check(other.wait_for(std::chrono::seconds(5))==std::future_status::ready && other.get());
            check(_skipInit);
          }}
          check(!_skipInit);
          try {{ ScopedInit{api} guard; throw std::runtime_error("init"); }} catch(const std::runtime_error&) {{}}
          check(!_skipInit);
        }}
        ''')
    cpp+='int main() {\n'+ '\n'.join(checks)+'\nstd::cout << "PASS: " << checks << " native Init scope checks\\n";\n}\n'
    with tempfile.TemporaryDirectory(prefix='aurora-init-scopes-') as directory:
        path=Path(directory); test=path/'test.cpp'; exe=path/'test.exe'; test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': command+=['/nologo','/EHsc','/std:c++20',str(test),'/Fe:'+str(exe)]
        else: command+=['-std=c++20',str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
