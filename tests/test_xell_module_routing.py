"""Execute the production module hook in both build modes, and Vulkan menu gates.

Win32 calls and UI state are stand-ins: this does not establish loader/GPU safety.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    hook = function((ROOT/'OptiScaler/hooks/Kernel_Hooks.cpp').read_text(encoding='utf-8'),
                    'BOOL WINAPI KernelHooks::hk_K32_GetModuleHandleExA(')
    menu = (ROOT/'OptiScaler/menu/menu_common.cpp').read_text(encoding='utf-8')
    gates = []
    for key in ['Ffx', 'Combo']:
        gate = re.search(r'nvngxOptions\[fgNvngx'+key+r'Index\]\.set_disabled\((state.swapchainApi[^,]+),', menu)
        assert gate, key
        gates.append(gate[1])
    render = function(menu, 'void MenuCommon::RenderFakenvapiSettings(')
    start = render.index('    const bool showLatencyFlex')
    end = render.index('    ImGui::SeparatorText(', start)
    prefix = render[start:end]
    assert 'if (showForceXell)' in render and render.index('if (showForceXell)') < render.index('bool forceXell')
    # No arbitrary export patching in the non-input initialization path.
    xell = (ROOT/'OptiScaler/proxies/XeLL_Proxy.h').read_text(encoding='utf-8')
    assert 'RedirectAllExports' not in function(xell, 'static bool InitXeLLProper(')
    cpp = r'''
#include <cstring>
#include <cstdlib>
#include <iostream>
using BOOL=int;using DWORD=unsigned;using HMODULE=void*;using LPCSTR=const char*;
#define WINAPI
constexpr unsigned GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS=4;
int dllStorage,selectedStorage,otherStorage;
HMODULE dllModule=&dllStorage;
struct XeLLProxy {static inline HMODULE selected=nullptr;static HMODULE Module(){return selected;}};
int calls=0,refs=0;DWORD lastFlags;LPCSTR lastName;HMODULE* lastOut;bool succeed=true;
BOOL original(DWORD flags,LPCSTR name,HMODULE* out){
 ++calls;lastFlags=flags;lastName=name;lastOut=out;
 if(!out||!succeed)return 0;
 *out=flags==4?const_cast<char*>(name):static_cast<void*>(&otherStorage);++refs;return 1;
}
struct KernelHooks {static inline auto o_K32_GetModuleHandleExA=&original;
 static BOOL hk_K32_GetModuleHandleExA(DWORD,LPCSTR,HMODULE*);};
enum class API {DX11,DX12,Vulkan};enum class FGOutput {NoFG,XeFG};
struct State {API swapchainApi;FGOutput activeFgOutput;bool reflexLimitsFps;};
namespace fakenvapi {bool main=false;bool isUsingAsMainNvapi(){return main;}}
int section=0;bool visibleForce=false;
void visibility(State state){
''' + prefix + '++section;visibleForce=showForceXell;}\n' + hook
    for i, gate in enumerate(gates):
        cpp += f'bool gate{i}(State state){{return {gate};}}\n'
    cpp += r'''
int main(){int checks=0;auto check=[&](bool v){++checks;if(!v){std::cerr<<"FAIL "<<checks;std::exit(2);}};
const char* name="libxell.dll";HMODULE out=nullptr;
for(bool selected:{false,true}){
 XeLLProxy::selected=selected?&selectedStorage:nullptr;
 calls=refs=0;succeed=true;out=nullptr;
 check(KernelHooks::hk_K32_GetModuleHandleExA(0,name,&out)==1);
#ifdef LOW_LATENCY_INPUTS
 check(out==dllModule&&calls==0);
#else
 check(calls==1&&refs==1);check(out==(selected?&selectedStorage:&otherStorage));
 check(lastFlags==(selected?4u:0u));check(lastName==(selected?reinterpret_cast<LPCSTR>(&selectedStorage):name));
 succeed=false;out=nullptr;calls=refs=0;
 check(!KernelHooks::hk_K32_GetModuleHandleExA(0,name,&out));check(calls==1&&refs==0&&out==nullptr);
#endif
}
// Unrelated names, invalid output/name, and flagged/address requests forward untouched.
succeed=true;
for(DWORD flags:{1u,2u,4u,6u}){calls=0;KernelHooks::hk_K32_GetModuleHandleExA(flags,name,&out);
 check(calls==1&&lastFlags==flags&&lastName==name&&lastOut==&out);}
for(auto other:{"other.dll","C:\\game\\libxell.dll"}){calls=0;
 KernelHooks::hk_K32_GetModuleHandleExA(0,other,&out);check(calls==1&&lastName==other);}
calls=0;KernelHooks::hk_K32_GetModuleHandleExA(0,nullptr,&out);check(calls==1&&lastName==nullptr);
calls=0;KernelHooks::hk_K32_GetModuleHandleExA(0,name,nullptr);check(calls==1&&lastOut==nullptr);
for(API api:{API::DX11,API::DX12,API::Vulkan})for(bool main:{false,true})
for(FGOutput fg:{FGOutput::NoFG,FGOutput::XeFG})for(bool reflex:{false,true}){
 State state{api,fg,reflex};fakenvapi::main=main;section=0;visibleForce=false;visibility(state);
 check(section==(api!=API::Vulkan||main||(fg==FGOutput::XeFG&&reflex)));
 check(visibleForce==(api!=API::Vulkan));
 check(gate0(state)==(api==API::Vulkan));check(gate1(state)==(api==API::Vulkan));
}
std::cout<<"PASS: "<<checks<<" XeLL/menu checks\n";}
'''
    with tempfile.TemporaryDirectory(prefix='aurora-xell-routing-') as directory:
        path = Path(directory)
        test = path/'test.cpp'
        test.write_text(cpp, encoding='utf-8')
        for low_latency in [False, True]:
            exe = path/('input.exe' if low_latency else 'normal.exe')
            command = [args.compiler] + ([args.driver] if args.driver else [])
            if Path(args.compiler).stem.lower() == 'cl':
                command += ['/nologo','/EHsc','/std:c++20',str(test),'/Fe:'+str(exe)]
                if low_latency: command += ['/DLOW_LATENCY_INPUTS']
            else:
                command += ['-std=c++20',str(test),'-o',str(exe)]
                if low_latency: command += ['-DLOW_LATENCY_INPUTS']
            subprocess.run(command,cwd=path,check=True)
            subprocess.run([str(exe)],cwd=path,check=True,timeout=25)


if __name__ == '__main__':
    main()
