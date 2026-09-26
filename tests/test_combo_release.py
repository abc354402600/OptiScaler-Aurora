"""Exercise actual Combo release body and evaluation admission with the real registry.

The shader/resource portion of Evaluate is replaced by a sentinel after its actual
admission checks. Native child release outcomes are injected; no GPU is involved.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
#include "framegen/ProviderHandleRegistry.h"
#include <cstdlib>
#include <iostream>
#include <memory>
#include <stdexcept>
using NVSDK_NGX_Result=int;
constexpr int NVSDK_NGX_Result_Success=0, NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2, NVSDK_NGX_Result_FAIL_FeatureNotFound=-3;
using PFN_NVSDK_NGX_ProgressCallback=void*;
struct NVSDK_NGX_Handle {};
struct ID3D12GraphicsCommandList {};
struct NVSDK_NGX_Parameter {};
int destroyed=0;
'''
SUPPORT=r'''
struct Child {
 int result=0, calls=0; bool throws=false;
 int D3D12_ReleaseFeature(NVSDK_NGX_Handle* handle) {
   if(!handle) std::exit(3);
   ++calls;
   if(throws) throw std::runtime_error("injected release");
   return result;
 }
};
struct Nvngx_Combo {
 std::unique_ptr<Child> artursProvider=std::make_unique<Child>(), ffxProvider=std::make_unique<Child>();
 int ReleaseChildren(Nvngx_Combo_Handle*);
 int D3D12_ReleaseFeature(NVSDK_NGX_Handle*);
 int D3D12_EvaluateFeature(ID3D12GraphicsCommandList*,const NVSDK_NGX_Handle*,NVSDK_NGX_Parameter*,PFN_NVSDK_NGX_ProgressCallback);
};
struct PrivateHandle { unsigned id; NVSDK_NGX_Handle* nativeHandle; };
'''
CHECKS=r'''
int main() {
 int checks=0; auto check=[&](bool ok) { if(!ok) { std::cerr << "Combo release regression at " << checks+1 << '\n'; std::exit(2); } ++checks; };
 NVSDK_NGX_Handle arturs,ffx; NVSDK_NGX_Parameter params;
 for(int artFail=0;artFail<2;++artFail) for(int ffxFail=0;ffxFail<2;++ffxFail) {
   Nvngx_Combo combo; ProviderHandleRegistry<PrivateHandle> registry;
   auto* combined=new Nvngx_Combo_Handle { 42,&ffx,&arturs };
   auto* token=registry.Publish(registry.Prepare({42,reinterpret_cast<NVSDK_NGX_Handle*>(combined)}));
   auto evaluate=[&]{ return registry.Read(token,-3,[&](auto& value) { return combo.D3D12_EvaluateFeature(nullptr,value.nativeHandle,&params,nullptr); }); };
   auto release=[&]{ return registry.Release(token,-3,[&](auto& value) { return combo.D3D12_ReleaseFeature(value.nativeHandle); },[](int r){return r==0;}); };
   check(evaluate()==99);
   int previousDestroyed=destroyed;
   combo.artursProvider->result=artFail?-1:0; combo.ffxProvider->result=ffxFail?-1:0;
   check(release()==((artFail||ffxFail)?-1:0));
   check(combo.artursProvider->calls==1 && combo.ffxProvider->calls==1);
   check(destroyed==previousDestroyed+((artFail||ffxFail)?0:1));
   check(evaluate()==-3);
   if(artFail||ffxFail) {
      check(combined->releaseStarted && (combined->artursHandle!=nullptr)==bool(artFail) && (combined->ffxHandle!=nullptr)==bool(ffxFail));
      combo.artursProvider->result=combo.ffxProvider->result=0;
      check(release()==0 && destroyed==previousDestroyed+1);
   }
   check(release()==-3 && evaluate()==-3);
   check(combo.artursProvider->calls==1+artFail && combo.ffxProvider->calls==1+ffxFail);
   check(registry.GetIdentity(token,[](const auto& v){return v.id;}).value()==42);
 }
 // Failure via a C++ exception also retains the wrapper and completed child release.
 Nvngx_Combo combo; ProviderHandleRegistry<PrivateHandle> registry;
 auto* combined=new Nvngx_Combo_Handle { 51,&ffx,&arturs };
 auto* token=registry.Publish(registry.Prepare({51,reinterpret_cast<NVSDK_NGX_Handle*>(combined)}));
 auto release=[&]{ return registry.Release(token,-3,[&](auto& value){return combo.D3D12_ReleaseFeature(value.nativeHandle);},[](int r){return r==0;}); };
 int previousDestroyed=destroyed;
 combo.ffxProvider->throws=true;
 bool threw=false;
 try { release(); } catch(const std::runtime_error&) { threw=true; }
 check(threw && destroyed==previousDestroyed && combined->artursHandle==nullptr && combined->ffxHandle==&ffx);
 check(combo.D3D12_EvaluateFeature(nullptr,reinterpret_cast<NVSDK_NGX_Handle*>(combined),&params,nullptr)==-3);
 combo.ffxProvider->throws=false;
 check(release()==0 && destroyed==previousDestroyed+1 && combo.artursProvider->calls==1 && combo.ffxProvider->calls==2);
 check(release()==-3);
 check(combo.D3D12_ReleaseFeature(nullptr)==-2);
 check(combo.D3D12_EvaluateFeature(nullptr,nullptr,&params,nullptr)==-2);
 std::cout << "PASS: " << checks << " Combo release ownership checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--compiler',required=True); parser.add_argument('--driver'); args=parser.parse_args()
    cpp_source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_Combo.cpp').read_text(encoding='utf-8')
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_Combo.h').read_text(encoding='utf-8')
    struct=header[header.index('struct Nvngx_Combo_Handle'):header.index('\nclass Nvngx_Combo')]
    # Count destruction without changing the production ownership fields.
    struct=struct.replace('\n};','\n    ~Nvngx_Combo_Handle() { ++destroyed; }\n};',1)
    release=function(cpp_source,'NVSDK_NGX_Result Nvngx_Combo::ReleaseChildren(')+function(cpp_source,'NVSDK_NGX_Result Nvngx_Combo::D3D12_ReleaseFeature(')
    evaluate=function(cpp_source,'NVSDK_NGX_Result Nvngx_Combo::D3D12_EvaluateFeature(')
    evaluate=evaluate[:evaluate.index('    // Assuming ffx')]+'    return 99;\n}'
    with tempfile.TemporaryDirectory(prefix='aurora-combo-release-') as folder:
        path=Path(folder); cpp=path/'test.cpp'; exe=path/'test.exe'
        cpp.write_text(PRELUDE+struct+SUPPORT+release+evaluate+CHECKS,encoding='utf-8')
        cmd=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl': cmd+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(cpp),'/Fe:'+str(exe)]
        else: cmd+=['-std=c++20','-I'+str(ROOT/'OptiScaler'),str(cpp),'-o',str(exe)]
        subprocess.run(cmd,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__': main()
