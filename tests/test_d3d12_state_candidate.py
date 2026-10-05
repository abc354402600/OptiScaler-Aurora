"""Exercise pinned upstream plus the experimental state patch, without a GPU.

This is an adoption test, not a test of the shipped Aurora implementation.
The input functions and state structure are extracted from the patched source.
"""
import argparse
import re
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function
from audit_upstream_d3d12_state import REV, ROOT


def candidate(folder):
    relative = 'OptiScaler/hooks/D3D12_Hooks.cpp'
    target = folder/relative
    target.parent.mkdir(parents=True)
    target.write_bytes(subprocess.check_output(['git', 'show', REV+':'+relative], cwd=ROOT))
    subprocess.run(['git', 'apply', '--check', str(ROOT/'patches/experimental/d3d12-state-semantics.patch')],
                   cwd=folder, check=True)
    subprocess.run(['git', 'apply', str(ROOT/'patches/experimental/d3d12-state-semantics.patch')],
                   cwd=folder, check=True)
    return target.read_text(encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver', default='c++')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='aurora-state-candidate-') as folder:
        folder = Path(folder)
        source = candidate(folder)
        cpp = r'''
#include <algorithm>
#include <iterator>
#include <memory>
#include <unordered_map>
#include <iostream>
#include <cstdlib>
#include <thread>
using UINT=unsigned;using HRESULT=int;
#define SUCCEEDED(x) ((x)>=0)
#define LOG_ERROR(...) ((void)0)
struct ID3D12GraphicsCommandList {};
struct ID3D12PipelineState {};
struct ID3D12DescriptorHeap {};
struct ID3D12CommandAllocator {};
constexpr UINT kMaxDescriptorHeaps=2;
struct RootBindings {int sentinel=0;void Clear(){sentinel=0;}};
struct Option {bool enabled=true;bool value_or_default(){return enabled;}};
struct Config {Option ExtendedStateRestore,FGHudfixPersistentBindings;
 static Config* Instance(){static Config c;return &c;}};
struct ResTrack_Dx12 {static inline int calls=0;
 static void OnSetDescriptorHeaps(ID3D12GraphicsCommandList*,UINT,ID3D12DescriptorHeap* const*){++calls;}};
'''
        for name in ['t_suppressRecording', 't_upscalerActive']:
            declaration = re.search(r'^static thread_local [^;]*\b'+name+r'\b[^;]*;', source, re.M)
            assert declaration, name
            cpp += declaration[0]+'\n'
        cpp += function(source, 'struct CommandListState')+';\n'
        cpp += function(source, 'struct SuppressRecordingScope')+';\n'
        cpp += function(source, 'static inline bool ShouldRecord(')+'\n'
        cpp += r'''
std::unordered_map<ID3D12GraphicsCommandList*,std::unique_ptr<CommandListState>> states;
CommandListState* GetCmdListState(ID3D12GraphicsCommandList* p,bool create){
 auto it=states.find(p);if(it!=states.end())return it->second.get();
 if(!create)return nullptr;return (states[p]=std::make_unique<CommandListState>()).get();
}
UINT liveCount=0;ID3D12DescriptorHeap* liveHeap=nullptr;int heapCalls=0;
void setHeaps(ID3D12GraphicsCommandList*,UINT n,ID3D12DescriptorHeap* const* p){
 ++heapCalls;liveCount=n;liveHeap=n?p[0]:nullptr;
}
struct HeapHook {bool available=true;auto GetHook()const{return available?&setHeaps:nullptr;}}s_SetDescriptorHeaps;
HRESULT resetResult=0;int resetCalls=0;
HRESULT resetOriginal(ID3D12GraphicsCommandList*,ID3D12CommandAllocator*,ID3D12PipelineState*){
 ++resetCalls;return resetResult;
}
struct ResetHook {decltype(&resetOriginal) o_earlyHook=resetOriginal,o_lateHook=resetOriginal;}s_Reset;
int clearCalls=0;
void clearOriginal(ID3D12GraphicsCommandList*,ID3D12PipelineState*){++clearCalls;}
struct ClearHook {decltype(&clearOriginal) o_earlyHook=clearOriginal,o_lateHook=clearOriginal;}s_ClearState;
'''
        for decl in ['static void RecordReset(', 'static void RecordDescriptorHeaps(',
                     'static bool RestoreDescriptorHeaps(', 'static HRESULT hkReset(',
                     'static HRESULT hkResetLate(', 'static void hkClearState(',
                     'static void hkClearStateLate(']:
            cpp += function(source, decl)+'\n'
        cpp += r'''
int main(){int checks=0;auto check=[&](bool ok){++checks;if(!ok){std::cerr<<"FAIL "<<checks;std::exit(2);}};
 ID3D12GraphicsCommandList cmd;ID3D12PipelineState pso,second;
 ID3D12DescriptorHeap game,opti;ID3D12DescriptorHeap* gameArray[]={&game};
 ID3D12DescriptorHeap* two[]={&game,&opti};
 CommandListState unknown;
 check(!RestoreDescriptorHeaps(&cmd,unknown));check(heapCalls==0);
 for(bool late:{false,true}){
 states.clear();resetResult=-1;resetCalls=0;
 // Exercise late -> early chaining, not only independent fake originals.
 s_Reset.o_lateHook=&hkReset;
 auto reset=late?&hkResetLate:&hkReset;
 check(reset(&cmd,nullptr,&pso)==-1);check(states.empty());check(resetCalls==1);
 resetResult=0;check(reset(&cmd,nullptr,&pso)==0);
 auto* s=GetCmdListState(&cmd,false);check(s&&s->pipelineState==&pso);
 check(s->descriptorHeapsKnown&&s->numDescriptorHeaps==0);
 RecordDescriptorHeaps(&cmd,2,two);s->compute.sentinel=7;s->graphics.sentinel=9;
 resetResult=-1;check(reset(&cmd,nullptr,&second)==-1);
 check(s->pipelineState==&pso&&s->numDescriptorHeaps==2&&s->compute.sentinel==7);
 resetResult=0;check(reset(&cmd,nullptr,&second)==0);
 check(s->pipelineState==&second&&s->compute.sentinel==0&&s->graphics.sentinel==0);
 check(s->numDescriptorHeaps==0&&s->descriptorHeaps[0]==nullptr&&s->descriptorHeaps[1]==nullptr);
 for(bool nullArray:{false,true}){
 RecordDescriptorHeaps(&cmd,1,gameArray);
 RecordDescriptorHeaps(&cmd,0,nullArray?nullptr:gameArray);
 check(s->descriptorHeapsKnown&&s->numDescriptorHeaps==0);
 setHeaps(&cmd,1,two+1);check(RestoreDescriptorHeaps(&cmd,*s));
 check(liveCount==0&&liveHeap==nullptr);
 }
 RecordDescriptorHeaps(&cmd,2,two);check(RestoreDescriptorHeaps(&cmd,*s));check(liveCount==2);
 // Invalid input must not read a nonexistent array or truncate the state.
 RecordDescriptorHeaps(&cmd,3,gameArray);check(s->numDescriptorHeaps==2);
 RecordDescriptorHeaps(&cmd,1,nullptr);check(s->numDescriptorHeaps==2);
 t_upscalerActive=true;RecordDescriptorHeaps(&cmd,0,nullptr);check(s->numDescriptorHeaps==2);
 bool otherThreadRecords=false;
 std::thread worker([&]{otherThreadRecords=ShouldRecord(&cmd);});worker.join();
 check(otherThreadRecords);check(!ShouldRecord(&cmd));
 // Reset invalidates even during upscaler work, unlike ordinary recording.
 check(reset(&cmd,nullptr,nullptr)==0);check(s->pipelineState==nullptr&&s->numDescriptorHeaps==0);
 t_upscalerActive=false;
 {SuppressRecordingScope outer;check(t_suppressRecording==1);
  {SuppressRecordingScope inner;check(t_suppressRecording==2);}
  check(t_suppressRecording==1);RecordDescriptorHeaps(&cmd,1,gameArray);check(s->numDescriptorHeaps==0);}
 check(t_suppressRecording==0);
 s_SetDescriptorHeaps.available=false;check(!RestoreDescriptorHeaps(&cmd,*s));
 s_SetDescriptorHeaps.available=true;
 Config::Instance()->ExtendedStateRestore.enabled=false;
 RecordDescriptorHeaps(&cmd,1,gameArray);check(s->numDescriptorHeaps==0);
 Config::Instance()->ExtendedStateRestore.enabled=true;
 s_ClearState.o_lateHook=&hkClearState;
 auto clear=late?&hkClearStateLate:&hkClearState;
 RecordDescriptorHeaps(&cmd,2,two);s->compute.sentinel=7;s->graphics.sentinel=9;
 clearCalls=0;clear(&cmd,&pso);check(clearCalls==1);
 check(s->pipelineState==&pso&&s->descriptorHeapsKnown&&s->numDescriptorHeaps==0);
 check(s->compute.sentinel==0&&s->graphics.sentinel==0);
 clear(&cmd,nullptr);check(s->pipelineState==nullptr);
 states.clear();clear(&cmd,&second);s=GetCmdListState(&cmd,false);
 check(s&&s->pipelineState==&second&&s->descriptorHeapsKnown);
 }
 std::cout<<checks<<" candidate state checks passed (CPU stand-ins only)\n";
}
'''
        (folder/'test.cpp').write_text(cpp, encoding='utf-8')
        subprocess.run([args.compiler, args.driver, '-std=c++20', str(folder/'test.cpp'),
                        '-o', str(folder/'test.exe')], check=True)
        subprocess.run([str(folder/'test.exe')], check=True)
        # Prove that passing results depend on all three semantic fixes.
        mutations = {
            'lost-initial-pso': (
                'auto* state = GetCmdListState(commandList, true);\n    state->Clear();',
                'auto* state = GetCmdListState(commandList, false);\n'
                '    if (!state) return;\n    state->Clear();'),
            'ignored-empty-array': (
                'if (!config->ExtendedStateRestore.value_or_default())',
                'if (!config->ExtendedStateRestore.value_or_default() || !ppDescriptorHeaps)'),
            'skipped-empty-restore': (
                'if (!state.descriptorHeapsKnown || state.numDescriptorHeaps > kMaxDescriptorHeaps ||',
                'if (state.numDescriptorHeaps == 0 || !state.descriptorHeapsKnown || '
                'state.numDescriptorHeaps > kMaxDescriptorHeaps ||'),
        }
        for name, (old, new) in mutations.items():
            assert cpp.count(old) == 1, name
            (folder/'test.cpp').write_text(cpp.replace(old, new), encoding='utf-8')
            subprocess.run([args.compiler, args.driver, '-std=c++20', str(folder/'test.cpp'),
                            '-o', str(folder/'test.exe')], check=True)
            result = subprocess.run([str(folder/'test.exe')], capture_output=True, text=True)
            assert result.returncode == 2 and 'FAIL ' in result.stderr, (name, result)
            print('Mutation rejected:', name)


if __name__ == '__main__':
    main()
