"""Full Combo Create/rollback/private drain/Shutdown bodies, fake child SDKs.

Extracts the actual private ledger and child-close helper. The outer exclusive
shutdown admission is covered by test_provider_shutdown_drain.py.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include <memory>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>
#include <unordered_set>
#include <algorithm>
#include <functional>
#include <future>
#include <stdexcept>
#include <iostream>
#include <cstdlib>
using NVSDK_NGX_Result=int;using NVSDK_NGX_Feature=int;
constexpr int NVSDK_NGX_Result_Success=0,NVSDK_NGX_Result_Fail=-1,
 NVSDK_NGX_Result_FAIL_InvalidParameter=-2,NVSDK_NGX_Result_FAIL_FeatureNotSupported=-3,
 NVSDK_NGX_Result_FAIL_PlatformError=-4,NVSDK_NGX_Result_FAIL_NotInitialized=-7,
 NVSDK_NGX_Feature_FrameGeneration=7;
#define LOG_ERROR(...)
#define IID_PPV_ARGS(x) x
#define FAILED(x) ((x)<0)
struct NVSDK_NGX_Handle{};struct NVSDK_NGX_Parameter{};
struct ID3D12Device{std::atomic_int refs=0;void Release(){--refs;}};
struct ID3D12GraphicsCommandList{
 ID3D12Device* device=nullptr;int error=0;
 int GetDevice(ID3D12Device** out){if(error)return error;*out=device;if(device)++device->refs;return 0;}
};
template<class T>struct ComPtr{
 T* p=nullptr;~ComPtr(){if(p)p->Release();}T** operator&(){return &p;}
 T* Get(){return p;}explicit operator bool(){return p!=nullptr;}
 T* Detach(){auto* r=p;p=nullptr;return r;}void Attach(T* v){p=v;}
};
namespace Microsoft::WRL {template<class T>using ComPtr=::ComPtr<T>;}
struct Child{
 std::atomic_int creates=0,releases=0,closes=0;
 int createResult=0,releaseResult=0;bool outputOnError=false,successNull=false,throwCreate=false,throwRelease=false;
 NVSDK_NGX_Handle native;std::function<void()> callback;
 int D3D12_CreateFeature(ID3D12GraphicsCommandList*,int,NVSDK_NGX_Parameter*,NVSDK_NGX_Handle** out){
  ++creates;*out=nullptr;if(callback)callback();if(throwCreate)throw std::runtime_error("create");
  if((!createResult||outputOnError)&&!successNull)*out=&native;return createResult;
 }
 int D3D12_ReleaseFeature(NVSDK_NGX_Handle* h){
  if(h!=&native)std::abort();++releases;if(callback)callback();
  if(throwRelease)throw std::runtime_error("release");return releaseResult;
 }
 int D3D12_Shutdown1(ID3D12Device*){++closes;return 0;}
 int D3D12_Shutdown(){return D3D12_Shutdown1(nullptr);}
};
using Nvngx_Arturs=Child;using Nvngx_FFX=Child;
'''
CHECKS = r'''
int main(){
 int checks=0;auto check=[&](bool ok){if(!ok){std::cerr<<"Combo create check "<<checks+1<<" failed\n";std::exit(2);}++checks;};
 ID3D12Device a,b;ID3D12GraphicsCommandList cmd;cmd.device=&a;NVSDK_NGX_Parameter params;
 NVSDK_NGX_Handle sentinel,*out=&sentinel;
 auto create=[&](Nvngx_Combo& c){return c.D3D12_CreateFeature(&cmd,7,&params,&out);};
 auto footprint=[&](Nvngx_Combo& c){c._artursInitAttempts.insert(&a);c._ffxInitAttempts.insert(&a);};
 {
  Nvngx_Combo c;footprint(c);
  check(c.D3D12_CreateFeature(&cmd,7,&params,nullptr)==-2);
  check(c.D3D12_CreateFeature(nullptr,7,&params,&out)==-2&&!out);out=&sentinel;
  check(c.D3D12_CreateFeature(&cmd,7,nullptr,&out)==-2&&!out);out=&sentinel;
  check(c.D3D12_CreateFeature(&cmd,0,&params,&out)==-3&&!out);
  cmd.error=-1;check(create(c)==-4&&!out);cmd.error=0;cmd.device=nullptr;
  check(create(c)==-4&&!out);cmd.device=&a;
  check(c._pendingCreates.empty()&&c.artursProvider->creates==0);
  check(create(c)==0&&out&&c._pendingCreates.empty()&&a.refs==0);
  auto* h=reinterpret_cast<Nvngx_Combo_Handle*>(out);
  check(h->artursHandle&&h->ffxHandle&&!h->releaseStarted);
  check(c.D3D12_ReleaseFeature(out)==0&&c.artursProvider->releases==1&&c.ffxProvider->releases==1);
 }
 // Known child retained when second creation fails and rollback fails/throws.
 for(bool throws:{false,true}){
  Nvngx_Combo c;footprint(c);c.ffxProvider->createResult=-1;
  c.artursProvider->releaseResult=-1;c.artursProvider->throwRelease=throws;
  bool caught=false;out=&sentinel;int result=0;
  try{result=create(c);}catch(const std::runtime_error&){caught=true;}
  check((throws?caught:result==-1)&&!out&&a.refs==1&&c._pendingCreates.size()==1);
  auto& p=*c._pendingCreates.front();check(!p.uncertain&&p.handle->artursHandle&&!p.handle->ffxHandle&&p.handle->releaseStarted);
  c.artursProvider->throwRelease=false;
  check(c.D3D12_Shutdown1(&b)==0&&c.artursProvider->releases==1&&c._pendingCreates.size()==1);
  check(c.D3D12_Shutdown1(&a)==-1&&c.artursProvider->closes==0&&c.ffxProvider->closes==0);
  check(c._artursInitAttempts.contains(&a)&&c._ffxInitAttempts.contains(&a));
  c.artursProvider->releaseResult=0;
  check(c.D3D12_Shutdown()==0&&c._pendingCreates.empty()&&a.refs==0&&c.artursProvider->releases==3&&c.ffxProvider->releases==0);
  check(c.artursProvider->closes==1&&c.ffxProvider->closes==1);
  check(c.D3D12_Shutdown()==0&&c.artursProvider->releases==3&&c.artursProvider->closes==1);
 }
 {
  Nvngx_Combo c;c.ffxProvider->createResult=-1;
  check(create(c)==-1&&!out&&c._pendingCreates.empty()&&c.artursProvider->releases==1);
 }
 {
  Nvngx_Combo c;c.artursProvider->createResult=-1;
  check(create(c)==-1&&!out&&c._pendingCreates.empty()&&c.ffxProvider->creates==0&&c.artursProvider->releases==0);
 }
 // Owned FFX Create has strong exception safety: first child's ownership is
 // still provable, unlike an exception inside the third-party Arturs call.
 {
  Nvngx_Combo c;footprint(c);c.ffxProvider->throwCreate=true;bool caught=false;
  try{create(c);}catch(const std::runtime_error&){caught=true;}
  check(caught&&!out&&c._pendingCreates.size()==1&&!c._pendingCreates[0]->uncertain&&a.refs==1);
  check(c.D3D12_Shutdown1(&a)==0&&c._pendingCreates.empty()&&a.refs==0&&c.artursProvider->releases==1&&c.ffxProvider->releases==0);
 }
 // Opaque bad outputs/exceptions must not be guessed valid release targets.
 for(int fault=0;fault<3;++fault){
  Nvngx_Combo c;footprint(c);
  c.artursProvider->throwCreate=fault==0;c.artursProvider->createResult=fault==1?-1:0;
  c.artursProvider->outputOnError=fault==1;c.artursProvider->successNull=fault==2;
  bool caught=false;int result=0;try{result=create(c);}catch(const std::runtime_error&){caught=true;}
  check((fault==0?caught:result==-1)&&!out&&c._pendingCreates.size()==1&&c._pendingCreates[0]->uncertain);
  check(c.D3D12_Shutdown1(&b)==0&&c._pendingCreates.size()==1);
  check(c.D3D12_Shutdown1(&a)==-7&&c.D3D12_Shutdown()==-7);
  check(c.artursProvider->releases==0&&c.artursProvider->closes==0&&c.ffxProvider->creates==0);
  check(a.refs==1); // Unknown ownership retains the device address as well.
 }
 check(a.refs==0);
 // Two private transactions on different devices: selective drain must leave
 // the other retry obligation and device reference intact.
 {
  Nvngx_Combo c;c.ffxProvider->createResult=-1;c.artursProvider->releaseResult=-1;
  check(create(c)==-1&&!out);cmd.device=&b;check(create(c)==-1&&!out);cmd.device=&a;
  check(c._pendingCreates.size()==2&&a.refs==1&&b.refs==1);
  c.artursProvider->releaseResult=0;
  check(c.D3D12_DrainPending(&a)==0&&c._pendingCreates.size()==1&&a.refs==0&&b.refs==1);
  check(c.D3D12_DrainPending(nullptr)==0&&c._pendingCreates.empty()&&b.refs==0);
 }
 // Inspect the complete selection for uncertain ownership before releasing
 // any known child, even if the uncertain entry is later in the ledger.
 {
  Nvngx_Combo c;c.ffxProvider->createResult=-1;c.artursProvider->releaseResult=-1;
  check(create(c)==-1);c.artursProvider->throwCreate=true;
  try{create(c);}catch(const std::runtime_error&){}
  int releases=c.artursProvider->releases;c.artursProvider->releaseResult=0;
  check(c.D3D12_DrainPending(nullptr)==-7&&c.artursProvider->releases==releases&&c._pendingCreates.size()==2);
 }
 // No metadata mutex is held across SDK callbacks. Two real Create calls may
 // complete in parallel; the ledger must lose neither entry nor public handle.
 {
  Nvngx_Combo c;
  c.artursProvider->callback=[&]{auto task=std::async(std::launch::async,[&]{std::lock_guard lock(c._pendingMutex);return true;});
    if(task.wait_for(std::chrono::seconds(2))!=std::future_status::ready||!task.get())std::abort();};
  auto work=[&]{NVSDK_NGX_Handle* h=nullptr;int r=c.D3D12_CreateFeature(&cmd,7,&params,&h);return std::pair(r,h);};
  auto first=std::async(std::launch::async,work),second=std::async(std::launch::async,work);
  auto x=first.get(),y=second.get();check(x.first==0&&y.first==0&&x.second&&y.second&&x.second!=y.second);
  check(c._pendingCreates.empty()&&a.refs==0&&c.artursProvider->creates==2);
  check(c.D3D12_ReleaseFeature(x.second)==0&&c.D3D12_ReleaseFeature(y.second)==0);
 }
 std::cout<<"PASS: "<<checks<<" Combo private rollback checks\n";
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    header = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_Combo.h').read_text(encoding='utf-8')
    source = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_Combo.cpp').read_text(encoding='utf-8')
    types = header[header.index('struct Nvngx_Combo_Handle'):header.index('class Nvngx_Combo')]
    members = header[header.index('    std::atomic_uint32_t'):header.index('    // The outer')]
    # Private helper declarations are already present in members.
    names = ('ForgetPending', 'ReleaseChildren', 'D3D12_CreateFeature', 'D3D12_DrainPending',
             'D3D12_ReleaseFeature', 'D3D12_Shutdown', 'D3D12_Shutdown1')
    bodies = [function(source, ('void ' if n == 'ForgetPending' else 'NVSDK_NGX_Result ')+'Nvngx_Combo::'+n+'(') for n in names]
    declarations = '\n'.join(b[:b.index('{')].replace('Nvngx_Combo::', '').strip()+';' for b in bodies[2:])
    members = members.replace('artursProvider = nullptr', 'artursProvider = std::make_unique<Child>()')
    members = members.replace('ffxProvider = nullptr', 'ffxProvider = std::make_unique<Child>()')
    cls = ('struct Nvngx_Combo {\n'+members+'\nstd::unordered_set<ID3D12Device*> _artursInitAttempts,_ffxInitAttempts;\n'
           +function(header, 'template <typename Provider>')+'\n'+declarations+'\n};\n')
    with tempfile.TemporaryDirectory(prefix='aurora-combo-create-') as directory:
        path = Path(directory)
        test, exe = path/'test.cpp', path/'test.exe'
        test.write_text(PRELUDE+types+cls+'\n'.join(bodies)+CHECKS, encoding='utf-8')
        cmd = [args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            cmd += ['/nologo', '/EHsc', '/std:c++20', str(test), '/Fe:'+str(exe)]
        else:
            cmd += ['-std=c++20', '-pthread', str(test), '-o', str(exe)]
        subprocess.run(cmd, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=30)


if __name__ == '__main__':
    main()
