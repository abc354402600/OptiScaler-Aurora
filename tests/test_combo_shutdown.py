"""Execute Combo's actual Init/Shutdown bodies with independently failing children."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include <unordered_set>
#include <memory>
#include <stdexcept>
#include <cstdlib>
#include <iostream>
using NVSDK_NGX_Result=int; using NVSDK_NGX_Version=int;
constexpr int NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_Fail=-1,NVSDK_NGX_Result_FAIL_InvalidParameter=-2;
struct ID3D12Device {}; struct NVSDK_NGX_FeatureCommonInfo {};
struct Child {
 int inits=0,closes=0,initResult=0,closeResult=0;
 bool initThrows=false,closeThrows=false; ID3D12Device* last=nullptr;
 int D3D12_Init_Ext(unsigned long long,const wchar_t*,ID3D12Device*,int,const NVSDK_NGX_FeatureCommonInfo*) {
   ++inits; if(initThrows) throw std::runtime_error("child init"); return initResult;
 }
 int D3D12_Shutdown1(ID3D12Device* d) {
   ++closes; last=d; if(closeThrows) throw std::runtime_error("child close"); return closeResult;
 }
 int D3D12_Shutdown() { return D3D12_Shutdown1(nullptr); }
};
'''
CHECKS = r'''
int main() {
 int checks=0; auto check=[&](bool ok) { if(!ok) { std::cerr<<"Combo shutdown check "<<checks+1<<" failed\n";std::exit(2); } ++checks; };
 ID3D12Device a,b,unknown;
 for(bool global : {false,true}) for(bool failArt : {false,true}) for(bool failFfx : {false,true}) {
   Nvngx_Combo c;
   auto init=[&](auto* d){ return c.D3D12_Init(0,nullptr,d,nullptr,0); };
   auto close=[&]{ return global?c.D3D12_Shutdown():c.D3D12_Shutdown1(&a); };
   auto& art=*c.artursProvider; auto& ffx=*c.ffxProvider;
   check(close()==0 && art.closes==0 && ffx.closes==0);
   check(init(static_cast<ID3D12Device*>(nullptr))==-2 && art.inits==0 && ffx.inits==0);
   check(init(&a)==0 && init(&b)==0 && art.inits==2 && ffx.inits==2);
   check(c.D3D12_Shutdown1(&unknown)==0 && art.closes==0 && ffx.closes==0);
   art.closeResult=failArt?-8:0; ffx.closeResult=failFfx?-9:0;
   check(close()==(failArt?-8:failFfx?-9:0) && art.closes==1 && ffx.closes==1);
   check(c._artursInitAttempts.contains(&a)==failArt && c._ffxInitAttempts.contains(&a)==failFfx);
   check(c._artursInitAttempts.contains(&b)==(!global||failArt) && c._ffxInitAttempts.contains(&b)==(!global||failFfx));
   art.closeResult=ffx.closeResult=0;
   check(close()==0 && art.closes==1+failArt && ffx.closes==1+failFfx);
   check(close()==0 && art.closes==1+failArt && ffx.closes==1+failFfx);
   check(c.D3D12_Shutdown()==0 && art.closes==1+failArt+!global && ffx.closes==1+failFfx+!global);
   check(c._artursInitAttempts.empty() && c._ffxInitAttempts.empty());
   // A later Init establishes a new cleanup obligation for both children.
   check(init(&a)==0 && close()==0 && art.closes==2+failArt+!global && ffx.closes==2+failFfx+!global);
 }
 // Returned Init errors can still leave child resources needing shutdown.
 for(bool failArt : {false,true}) for(bool failFfx : {false,true}) {
   Nvngx_Combo c;
   c.artursProvider->initResult=failArt?-8:0;c.ffxProvider->initResult=failFfx?-9:0;
   check(c.D3D12_Init_Ext(0,nullptr,&a,0,nullptr)==((failArt||failFfx)?-1:0));
   check(c._artursInitAttempts.contains(&a) && c._ffxInitAttempts.contains(&a));
   check(c.D3D12_Shutdown1(&a)==0 && c.artursProvider->closes==1 && c.ffxProvider->closes==1);
 }
 for(bool first : {false,true}) {
   Nvngx_Combo c;
   (first?c.artursProvider:c.ffxProvider)->initThrows=true;
   bool threw=false;
   try { c.D3D12_Init_Ext(0,nullptr,&a,0,nullptr); } catch(const std::runtime_error&) { threw=true; }
   check(threw && c._artursInitAttempts.contains(&a) && c._ffxInitAttempts.contains(&a)==!first);
   check(c.D3D12_Shutdown()==0 && c.artursProvider->closes==1 && c.ffxProvider->closes==int(!first));
 }
 for(bool global : {false,true}) for(bool first : {false,true}) {
   Nvngx_Combo c;
   check(c.D3D12_Init(0,nullptr,&a,nullptr,0)==0);
   auto close=[&]{ return global?c.D3D12_Shutdown():c.D3D12_Shutdown1(&a); };
   (first?c.artursProvider:c.ffxProvider)->closeThrows=true;
   bool threw=false;
   try { close(); } catch(const std::runtime_error&) { threw=true; }
   check(threw && c._artursInitAttempts.contains(&a)==first && c._ffxInitAttempts.contains(&a));
   (first?c.artursProvider:c.ffxProvider)->closeThrows=false;
   check(close()==0 && c.artursProvider->closes==1+first && c.ffxProvider->closes==2-first);
   check(c._artursInitAttempts.empty() && c._ffxInitAttempts.empty());
 }
 // Global retry after per-device partial close must retain the other device.
 Nvngx_Combo c;
 check(c.D3D12_Init(0,nullptr,&a,nullptr,0)==0 && c.D3D12_Init(0,nullptr,&b,nullptr,0)==0);
 c.ffxProvider->closeResult=-9;
 check(c.D3D12_Shutdown1(&a)==-9 && !c._artursInitAttempts.contains(&a) && c._artursInitAttempts.contains(&b));
 c.ffxProvider->closeResult=0;
 check(c.D3D12_Shutdown()==0 && c.artursProvider->last==nullptr && c.ffxProvider->last==nullptr);
 check(c._artursInitAttempts.empty() && c._ffxInitAttempts.empty());
 std::cout<<"PASS: "<<checks<<" Combo child shutdown checks\n";
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    source = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_Combo.cpp').read_text(encoding='utf-8')
    header = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_Combo.h').read_text(encoding='utf-8')
    names = ('D3D12_Init', 'D3D12_Init_Ext', 'D3D12_Shutdown', 'D3D12_Shutdown1')
    bodies = [function(source, 'NVSDK_NGX_Result Nvngx_Combo::'+n+'(') for n in names]
    signatures = [body[:body.index('{')].strip().replace('Nvngx_Combo::', '')+';' for body in bodies]
    helper = function(header, 'template <typename Provider>')
    cls = '''struct Nvngx_Combo {
 std::unique_ptr<Child> artursProvider=std::make_unique<Child>(),ffxProvider=std::make_unique<Child>();
 std::unordered_set<ID3D12Device*> _artursInitAttempts,_ffxInitAttempts;
 int D3D12_DrainPending(ID3D12Device*) { return 0; } // Real private drain tested by test_combo_create.py.
'''+helper+'\n'+'\n'.join(signatures)+'\n};\n'
    with tempfile.TemporaryDirectory(prefix='aurora-combo-shutdown-') as directory:
        path = Path(directory)
        cpp, exe = path/'test.cpp', path/'test.exe'
        cpp.write_text(PRELUDE+cls+'\n'.join(bodies)+CHECKS, encoding='utf-8')
        command = [args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            command += ['/nologo', '/EHsc', '/std:c++20', str(cpp), '/Fe:'+str(exe)]
        else:
            command += ['-std=c++20', str(cpp), '-o', str(exe)]
        subprocess.run(command, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=25)


if __name__ == '__main__':
    main()
