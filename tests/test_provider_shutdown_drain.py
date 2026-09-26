"""Actual Create/Release/drain/coordinator bodies with fake SDK and COM calls.

Executes the production registry and admission. GPU work is not simulated.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function
from test_provider_handle_api import make_fixture

ROOT = Path(__file__).resolve().parents[1]
CHECKS = r'''
int main() {
 ID3D12Device a,b;ID3D12GraphicsCommandList cmd;cmd.device=&a;
 auto create=[&](ID3D12Device* d){cmd.device=d;NVSDK_NGX_Handle* h=nullptr;
   check(Nvngx_FG::D3D12_CreateFeature(&cmd,0,nullptr,&h)==0&&h&&d->refs==0);return h;};
 auto read=[](auto* h){return Nvngx_FG::D3D12_EvaluateFeature(nullptr,h,nullptr,nullptr);};
 auto vkread=[](auto* h){return Nvngx_FG::VULKAN_EvaluateFeature(nullptr,h,nullptr,nullptr);};
 provider.callback=[] {return 0;};provider.result=0;
 NVSDK_NGX_Handle* bad=&provider.native;
 int before=provider.creates;
 check(Nvngx_FG::D3D12_CreateFeature(nullptr,0,nullptr,&bad)==-2&&!bad&&provider.creates==before);
 cmd.error=-1;bad=&provider.native;
 check(Nvngx_FG::D3D12_CreateFeature(&cmd,0,nullptr,&bad)==-2&&!bad&&a.refs==0);cmd.error=0;
 cmd.device=nullptr;bad=&provider.native;
 check(Nvngx_FG::D3D12_CreateFeature(&cmd,0,nullptr,&bad)==-2&&!bad);
 check(Nvngx_FG::VULKAN_CreateFeature1(nullptr,nullptr,0,nullptr,&bad)==-2&&!bad);
 auto* ha=create(&a);auto* hb=create(&b);
 check(Nvngx_FG::_handles.GetIdentity(ha,[](const auto& h){return h.device;})==&a);
 check(Nvngx_FG::_handles.GetIdentity(hb,[](const auto& h){return h.device;})==&b);
 Nvngx_FG::_dx12InitAttempts={&a,&b};
 int native=0;before=provider.releases;
 auto closeA=[&]{return Nvngx_FG::WithDx12Shutdown([&](auto close){++native;return close(&a);},&a);};
 State::Instance().isShuttingDown=true;
 check(closeA()==-7&&native==0&&provider.releases==before);State::Instance().isShuttingDown=false;
 {auto busy=Nvngx_FG::_calls.TryOperation();check(closeA()==-7&&native==0&&provider.releases==before);}
 provider.releaseCallback=[] {return -8;};
 check(closeA()==-8&&native==0&&Nvngx_FG::_dx12InitAttempts.size()==2&&read(ha)==-7&&read(hb)==0);
 provider.releaseCallback=[&] {
   auto work=std::async(std::launch::async,[&]{
     return Nvngx_FG::D3D12_ReleaseFeature(ha)==-7&&Nvngx_FG::D3D12_Shutdown()==-7;
   });
   check(work.wait_for(std::chrono::seconds(2))==std::future_status::ready&&work.get());return 0;
 };
 check(closeA()==0&&native==1&&!Nvngx_FG::_dx12InitAttempts.contains(&a));
 check(read(ha)==-3&&read(hb)==0);provider.releaseCallback={};
 before=provider.releases;check(closeA()==0&&provider.releases==before);
 // A later initialization cannot resurrect the retired token.
 Nvngx_FG::_dx12InitAttempts.insert(&a);auto* newer=create(&a);
 check(newer!=ha&&read(ha)==-3&&Nvngx_FG::D3D12_ReleaseFeature(ha)==-3);
 provider.releaseCallback=[]()->int{throw std::runtime_error("release");};bool threw=false;
 try{closeA();}catch(const std::runtime_error&){threw=true;}
 check(threw&&bool(Nvngx_FG::_calls.TryOperation())&&read(newer)==-7);provider.releaseCallback={};
 check(closeA()==0&&read(newer)==-3&&read(hb)==0);
 check(Nvngx_FG::D3D12_Shutdown()==0&&read(hb)==-3);
 // Partial drain: one success, then failure; completed work is not repeated.
 auto* one=create(&a);auto* two=create(&a);Nvngx_FG::_dx12InitAttempts.insert(&a);
 int releases=0;provider.releaseCallback=[&]{return ++releases==1?0:-8;};native=0;
 check(closeA()==-8&&releases==2&&native==0);
 check((read(one)==-3)!=(read(two)==-3));
 provider.releaseCallback=[&]{++releases;return 0;};check(closeA()==0&&releases==3&&native==1);
 provider.releaseCallback={};
 // The first failure also suspends selected handles not yet visited. Explicit
 // release remains possible; an unrelated device was already checked above.
 auto* queued1=create(&a);auto* queued2=create(&a);auto* queued3=create(&a);
 Nvngx_FG::_dx12InitAttempts.insert(&a);before=provider.releases;
 provider.releaseCallback=[] {return -8;};
 check(closeA()==-8&&provider.releases==before+1);
 check(read(queued1)==-7&&read(queued2)==-7&&read(queued3)==-7);
 provider.releaseCallback={};
 check(Nvngx_FG::D3D12_ReleaseFeature(queued1)==0&&Nvngx_FG::D3D12_ReleaseFeature(queued2)==0&&Nvngx_FG::D3D12_ReleaseFeature(queued3)==0);
 check(closeA()==0);
 // Native close failure after a completed drain retains the Init footprint.
 auto* last=create(&a);Nvngx_FG::_dx12InitAttempts.insert(&a);before=provider.calls;
 check(Nvngx_FG::WithDx12Shutdown([](auto){return -9;},&a)==-9&&read(last)==-3&&provider.calls==before);
 check(Nvngx_FG::_dx12InitAttempts.contains(&a));before=provider.releases;
 check(closeA()==0&&provider.releases==before);
 // Unknown legacy Vulkan device blocks device-specific drain before ANY release.
 NVSDK_NGX_Handle *known=nullptr,*unknown=nullptr;
 check(Nvngx_FG::VULKAN_CreateFeature1(&a,nullptr,0,nullptr,&known)==0);
 check(Nvngx_FG::VULKAN_CreateFeature(nullptr,0,nullptr,&unknown)==0);
 Nvngx_FG::_vulkanInitAttempts.insert(&a);before=provider.releases;
 check(Nvngx_FG::VULKAN_Shutdown1(&a)==-7&&provider.releases==before&&vkread(known)==0&&vkread(unknown)==0);
 check(Nvngx_FG::VULKAN_Shutdown()==0&&provider.releases==before+2&&vkread(known)==-3&&vkread(unknown)==-3);
 // API and device isolation with only explicit Vulkan handles.
 NVSDK_NGX_Handle* vkB=nullptr;
 check(Nvngx_FG::VULKAN_CreateFeature1(&a,nullptr,0,nullptr,&known)==0);
 check(Nvngx_FG::VULKAN_CreateFeature1(&b,nullptr,0,nullptr,&vkB)==0);
 Nvngx_FG::_vulkanInitAttempts={&a,&b};ha=create(&a);Nvngx_FG::_dx12InitAttempts.insert(&a);
 check(Nvngx_FG::VULKAN_Shutdown1(&a)==0&&vkread(known)==-3&&vkread(vkB)==0&&read(ha)==0);
 check(Nvngx_FG::D3D12_Shutdown()==0&&read(ha)==-3&&vkread(vkB)==0);
 check(Nvngx_FG::VULKAN_Shutdown()==0&&vkread(vkB)==-3);
 // Private failed-Create ownership must block the native callback even when
 // there are zero published handles, and must respect API/device routing.
 native=0;provider.pendingResult=-8;before=provider.calls;
 check(closeA()==-8&&native==0&&provider.calls==before&&provider.pendingDevice==&a);
 int drains=provider.pendingCalls;
 check(Nvngx_FG::VULKAN_Shutdown()==0&&provider.pendingCalls==drains);
 State::Instance().isShuttingDown=true;
 check(closeA()==-7&&native==0&&provider.pendingCalls==drains);
 State::Instance().isShuttingDown=false;provider.pendingResult=0;
 check(closeA()==0&&native==1&&provider.pendingCalls==drains+1);
 std::cout<<"PASS: "<<checks<<" provider shutdown drain checks\n";
}
'''


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver')
    args=parser.parse_args()
    source=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.cpp').read_text(encoding='utf-8')
    header=(ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    extra=[function(source,'NVSDK_NGX_Result Nvngx_FG::'+n+'(')
           for n in ('DrainHandles','D3D12_Shutdown','D3D12_Shutdown1','VULKAN_Shutdown','VULKAN_Shutdown1')]
    declarations='\n'.join('static '+body[:body.index('{')].strip().replace('Nvngx_FG::','')+';' for body in extra)
    coordinators='\n'.join(function(header,'template <typename Callback> static NVSDK_NGX_Result '+n+'(')
                           for n in ('WithDx12Shutdown','WithVulkanShutdown'))
    cpp=make_fixture('\n'.join(extra)+CHECKS)
    cpp='struct State { bool isShuttingDown=false; static State& Instance(){static State s;return s;} };\n'+cpp
    cpp=cpp.replace('struct Nvngx_FG {','''struct Nvngx_FG {
 inline static std::unordered_set<ID3D12Device*> _dx12InitAttempts;
 inline static std::unordered_set<VkDevice> _vulkanInitAttempts;
 struct Publication {Provider* Peek(){return &provider;}};
 inline static Publication _provider;
''')
    cpp=cpp.replace('inline static ProviderHandleRegistry<Nvngx_FG_Handle> _handles;',
                    'inline static ProviderHandleRegistry<Nvngx_FG_Handle> _handles;\n'+declarations+coordinators)
    cpp=cpp.replace('struct Provider {','''struct Provider {
 int pendingResult=0,pendingCalls=0;ID3D12Device* pendingDevice=nullptr;
 int D3D12_DrainPending(ID3D12Device* d){++pendingCalls;pendingDevice=d;return pendingResult;}
 std::function<int()> releaseCallback;''')
    cpp=cpp.replace('++releases; return result;', '++releases; return releaseCallback?releaseCallback():result;')
    with tempfile.TemporaryDirectory(prefix='aurora-provider-drain-') as directory:
        path=Path(directory);test=path/'test.cpp';exe=path/'test.exe';test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':command+=['/nologo','/EHsc','/std:c++20','/I'+str(ROOT/'OptiScaler'),str(test),'/Fe:'+str(exe)]
        else:command+=['-std=c++20','-pthread','-I'+str(ROOT/'OptiScaler'),str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=25)


if __name__=='__main__':main()
