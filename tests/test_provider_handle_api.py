"""Actual provider Create/Release and Evaluate admission reject cross-API tokens.

Only the D3D12 HUD/shader body is omitted after handle/API admission; the native
SDK is a counted stand-in. The registry, creation helper and token types are real.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function
from test_provider_call_admission import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
CHECKS = r'''
int main() {
 ID3D12Device device; ID3D12GraphicsCommandList command;command.device=&device;
 for(int variant=0;variant<3;++variant) {
   bool dx=variant==0;
   NVSDK_NGX_Handle* token=nullptr;
   auto create=[&] {
     if(dx) return Nvngx_FG::D3D12_CreateFeature(&command,0,nullptr,&token);
     if(variant==1) return Nvngx_FG::VULKAN_CreateFeature(nullptr,0,nullptr,&token);
     return Nvngx_FG::VULKAN_CreateFeature1(&device,nullptr,0,nullptr,&token);
   };
   auto evaluate=[&](bool correct) {
     return dx==correct?Nvngx_FG::D3D12_EvaluateFeature(nullptr,token,nullptr,nullptr)
                       :Nvngx_FG::VULKAN_EvaluateFeature(nullptr,token,nullptr,nullptr);
   };
   auto release=[&](bool correct) {
     return dx==correct?Nvngx_FG::D3D12_ReleaseFeature(token):Nvngx_FG::VULKAN_ReleaseFeature(token);
   };
   provider.result=0;
   check(create()==0 && token);
   const auto id=Nvngx_FG::_handles.GetIdentity(token,[](const auto& h){return h.id;});
   check(id.has_value());
   check(Nvngx_FG::_handles.GetIdentity(token,[&](const auto& h){return h.api;})==
         (dx?Nvngx_FG::HandleApi::D3D12:Nvngx_FG::HandleApi::Vulkan));
   int before=provider.evaluates;
   check(evaluate(false)==-3 && provider.evaluates==before);
   check(evaluate(true)==0 && provider.evaluates==before+1);
   before=provider.releases;
   check(release(false)==-3 && provider.releases==before);
   check(evaluate(true)==0); // A rejected cross-API Release did not retire the token.
   provider.result=-8;
   check(release(true)==-8 && provider.releases==before+1);
   check(release(false)==-3 && provider.releases==before+1);
   provider.result=0;
   check(release(true)==0 && provider.releases==before+2);
   before=provider.evaluates;
   check(evaluate(true)==-3 && evaluate(false)==-3 && provider.evaluates==before);
   check(release(true)==-3 && release(false)==-3);
   check(Nvngx_FG::_handles.GetIdentity(token,[](const auto& h){return h.id;})==id);
   provider.result=-8;
   check(create()==-8 && !token);
 }

 // Actual Init ledger plus actual operation bodies; close bookkeeping simulated.
 for(int variant=0;variant<3;++variant){
  bool dx=variant==0;ID3D12Device other;
  // Exercise both typed-device and erased-device ledger instantiations.
  auto run=[&](auto& attempts,auto& ready){
  attempts.clear();ready.clear();provider.result=0;
  NVSDK_NGX_Handle* token=nullptr;
  auto create=[&]{return dx?Nvngx_FG::D3D12_CreateFeature(&command,0,nullptr,&token):
    variant==1?Nvngx_FG::VULKAN_CreateFeature(nullptr,0,nullptr,&token):Nvngx_FG::VULKAN_CreateFeature1(&device,nullptr,0,nullptr,&token);};
  auto evaluate=[&]{return dx?Nvngx_FG::D3D12_EvaluateFeature(nullptr,token,nullptr,nullptr):Nvngx_FG::VULKAN_EvaluateFeature(nullptr,token,nullptr,nullptr);};
  auto release=[&]{return dx?Nvngx_FG::D3D12_ReleaseFeature(token):Nvngx_FG::VULKAN_ReleaseFeature(token);};
  using Device=typename std::decay_t<decltype(attempts)>::value_type;
  auto selected=static_cast<Device>(&device);auto unrelated=static_cast<Device>(&other);
  check(Nvngx_FG::InitializeProvider(attempts,ready,selected,[]{return -8;})==-7);
  int before=provider.creates;check(create()==-7&&!token&&provider.creates==before);
  attempts.clear();ready.clear();check(Nvngx_FG::InitializeProvider(attempts,ready,selected,[]{return 0;})==0);
  check(create()==0&&token);check(evaluate()==0);
  check(Nvngx_FG::InitializeProvider(attempts,ready,unrelated,[]{return -8;})==-7);
  before=provider.evaluates;check(evaluate()==(variant==1?-7:0));
  check(provider.evaluates==before+(variant==1?0:1));
  ready.erase(selected);before=provider.evaluates;
  check(evaluate()==-7&&provider.evaluates==before);
  before=provider.releases;check(release()==0&&provider.releases==before+1);
  attempts.clear();ready.clear();check(create()==0&&token);check(evaluate()==0);check(release()==0);
  };
  if(dx)run(Nvngx_FG::_dx12InitAttempts,Nvngx_FG::_dx12InitReady);
  else run(Nvngx_FG::_vulkanInitAttempts,Nvngx_FG::_vulkanInitReady);
 }
 std::cout<<"PASS: "<<checks<<" provider API handle routing checks\n";
}
'''


def make_fixture(checks=CHECKS):
    source = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.cpp').read_text(encoding='utf-8')
    header = (ROOT/'OptiScaler/framegen/nvngx/Nvngx_FG.h').read_text(encoding='utf-8')
    names = ['D3D12_CreateFeature', 'VULKAN_CreateFeature', 'VULKAN_CreateFeature1',
             'D3D12_EvaluateFeature', 'VULKAN_EvaluateFeature', 'D3D12_ReleaseFeature', 'VULKAN_ReleaseFeature']
    bodies = [function(source, 'NVSDK_NGX_Result Nvngx_FG::'+n+'(') for n in names]
    signatures = [body[:body.index('{')].strip().replace('Nvngx_FG::', '') for body in bodies]
    stubs = []
    for name, sig in zip(names, signatures):
        if 'Create' in name:
            stubs.append(sig+' { ++creates; *OutHandle=result?nullptr:&native; return result; }')
        else:
            counter = 'evaluates' if 'Evaluate' in name else 'releases'
            stubs.append(sig+' { ++'+counter+'; return result; }')
    prelude = PRELUDE.replace('#include <unordered_set>', '''#include <unordered_set>
#include <atomic>
#include "framegen/ProviderHandleRegistry.h"
#include "framegen/ProviderHandleCreation.h"
#define LOG_TRACE(...)
constexpr unsigned NVNGX_PROVIDER_ID_OFFSET=1000;
''')
    prelude = prelude.replace('constexpr int NVSDK_NGX_Result_Success=0,', 'constexpr int NVSDK_NGX_Result_Fail=-1,NVSDK_NGX_Result_FAIL_FeatureNotFound=-3,NVSDK_NGX_Result_Success=0,')
    prelude = prelude.replace('struct Provider {', 'struct Provider {\n NVSDK_NGX_Handle native; int creates=0,evaluates=0,releases=0,result=0;\n'+'\n'.join(stubs))
    prelude = prelude.replace('struct ID3D12Device {}; struct ID3D12GraphicsCommandList {};', r"""
struct ID3D12Device { int refs=0; void Release(){--refs;} };
struct ID3D12GraphicsCommandList {
 ID3D12Device* device=nullptr; int error=0;
 int GetDevice(ID3D12Device** out) { if(error)return error;*out=device;if(device)++device->refs;return 0; }
};
#define FAILED(x) ((x)<0)
#define IID_PPV_ARGS(x) x
namespace Microsoft::WRL { template<class T> struct ComPtr {
 T* ptr=nullptr; ~ComPtr(){if(ptr)ptr->Release();} T** operator&(){return &ptr;}
 T* Get(){return ptr;} explicit operator bool()const{return ptr!=nullptr;}
}; }
""")
    types = header[header.index('    enum class HandleApi'):header.index('    static inline std::atomic_uint32_t')]
    cls = '''struct Nvngx_FG {
 inline static ProviderCallAdmission _calls;
 inline static std::atomic_uint32_t lastIdCreated=0;
 static Provider* getProvider() { return &provider; }
'''+types+'\ninline static ProviderHandleRegistry<Nvngx_FG_Handle> _handles;\n'+'\n'.join('static '+s+';' for s in signatures)+'\n};\n'
    cls = cls.replace('struct Nvngx_FG {', 'struct Nvngx_FG {\n'+
        function(header,'template <typename Device, typename Callback>')+'\n'+
        function(header,'template <typename Device>\n    static bool CanUseProvider(')+'''
 inline static std::unordered_set<ID3D12Device*> _dx12InitAttempts,_dx12InitReady;
 inline static std::unordered_set<VkDevice> _vulkanInitAttempts,_vulkanInitReady;
''')
    dx = bodies[3]
    bodies[3] = dx[:dx.index('            bool applyHudCutoff')] + '''
            return provider->D3D12_EvaluateFeature(InCmdList,handle.nativeHandle,InParameters,InCallback);
        });
}
'''
    return prelude+cls+'\n'.join(bodies)+checks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    parser.add_argument('--negative-control',action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='aurora-handle-api-') as directory:
        path = Path(directory)
        cpp, exe = path/'test.cpp', path/'test.exe'
        fixture=make_fixture()
        if args.negative_control:
            old=function(fixture,'template <typename Device>\n    static bool CanUseProvider(')
            fixture=fixture.replace(old,old[:old.index('{')]+'{return true;}')
        cpp.write_text(fixture, encoding='utf-8')
        command = [args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            command += ['/nologo', '/EHsc', '/std:c++20', '/I'+str(ROOT/'OptiScaler'), str(cpp), '/Fe:'+str(exe)]
        else:
            command += ['-std=c++20', '-I'+str(ROOT/'OptiScaler'), str(cpp), '-o', str(exe)]
        subprocess.run(command, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=25)


if __name__ == '__main__':
    main()
