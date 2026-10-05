"""Reproduce adoption blockers in pinned upstream 500ed335, not Aurora tests.

Extracts unchanged upstream function bodies from Git. CPU stand-ins only; no
Direct3D device, DLL loading, performance measurement or game verification.
Exit zero means the documented blockers were reproduced, NOT that code is safe.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
REV = '500ed3354f61c7463e086243f6968645c2a90148'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver', default='c++')
    args = parser.parse_args()
    source = subprocess.check_output(
        ['git', 'show', REV+':OptiScaler/hooks/D3D12_Hooks.cpp'],
        cwd=ROOT, encoding='utf-8')
    cpp = r'''
#include <algorithm>
#include <memory>
#include <unordered_map>
#include <iostream>
#include <cstdlib>
using UINT=unsigned;
struct ID3D12GraphicsCommandList {};
struct ID3D12PipelineState {};
struct ID3D12DescriptorHeap {};
constexpr UINT kMaxDescriptorHeaps=2;
int t_suppressRecording=0;
bool ShouldRecord(ID3D12GraphicsCommandList* p){return p&&t_suppressRecording==0;}
struct Option{bool value_or_default(){return true;}};
struct Config{Option ExtendedStateRestore,FGHudfixPersistentBindings;
 static Config* Instance(){static Config c;return &c;}};
struct ResTrack_Dx12{static void OnSetDescriptorHeaps(ID3D12GraphicsCommandList*,UINT,
 ID3D12DescriptorHeap* const*){}};
struct CommandListState{
 UINT numDescriptorHeaps=0; ID3D12DescriptorHeap* descriptorHeaps[2]{};
 ID3D12PipelineState* pipelineState=nullptr;
 void Clear(){numDescriptorHeaps=0;descriptorHeaps[0]=descriptorHeaps[1]=nullptr;pipelineState=nullptr;}
};
std::unordered_map<ID3D12GraphicsCommandList*,std::unique_ptr<CommandListState>> states;
CommandListState* GetCmdListState(ID3D12GraphicsCommandList* p,bool create){
 auto it=states.find(p);if(it!=states.end())return it->second.get();
 if(!create)return nullptr;return (states[p]=std::make_unique<CommandListState>()).get();
}
UINT liveCount=0;ID3D12DescriptorHeap* liveHeap=nullptr;
void setHeaps(ID3D12GraphicsCommandList*,UINT n,ID3D12DescriptorHeap* const* p){
 liveCount=n;liveHeap=n?p[0]:nullptr;
}
struct Hook{auto GetHook()const{return &setHeaps;}}s_SetDescriptorHeaps;
#define LOG_ERROR(...) ((void)0)
'''
    for decl in ['static void RecordReset(', 'static void RecordDescriptorHeaps(',
                 'static bool RestoreDescriptorHeaps(']:
        cpp += function(source, decl)+'\n'
    cpp += r'''
int main(){int reproduced=0;ID3D12GraphicsCommandList cmd;ID3D12PipelineState pso;
 ID3D12DescriptorHeap game,opti;ID3D12DescriptorHeap* gameArray[]={&game};
 ID3D12DescriptorHeap* optiArray[]={&opti};
 RecordReset(&cmd,&pso);
 // First root/heaps recording later creates the state, with the PSO already lost.
 auto* s=GetCmdListState(&cmd,true);
 if(s->pipelineState==nullptr){++reproduced;std::cout<<"BLOCKER 1: first Reset loses initial PSO\n";}
 RecordReset(&cmd,&pso);
 if(s->pipelineState!=&pso)return 3; // existing-entry control
 RecordDescriptorHeaps(&cmd,1,gameArray);
 RecordDescriptorHeaps(&cmd,0,nullptr);
 if(s->numDescriptorHeaps==1){++reproduced;std::cout<<"BLOCKER 2: zero/null heap unbind retains old heap\n";}
 // Non-null pointer for zero count avoids relying on null-array acceptance.
 RecordDescriptorHeaps(&cmd,0,gameArray);
 if(s->numDescriptorHeaps!=0)return 4;
 setHeaps(&cmd,1,optiArray);
 bool restored=RestoreDescriptorHeaps(&cmd,*s);
 if(!restored&&liveCount==1&&liveHeap==&opti){++reproduced;
  std::cout<<"BLOCKER 3: recorded empty heap state is not restored\n";}
 RecordDescriptorHeaps(&cmd,1,gameArray);
 if(!RestoreDescriptorHeaps(&cmd,*s)||liveHeap!=&game)return 5;
 std::cout<<reproduced<<"/3 adoption blockers reproduced; 3 controls passed\n";
 return reproduced==3?0:2;
}
'''
    with tempfile.TemporaryDirectory(prefix='aurora-upstream-state-audit-') as folder:
        path = Path(folder)
        (path/'audit.cpp').write_text(cpp, encoding='utf-8')
        subprocess.run([args.compiler, args.driver, '-std=c++20', str(path/'audit.cpp'),
                        '-o', str(path/'audit.exe')], check=True)
        subprocess.run([str(path/'audit.exe')], check=True)


if __name__ == '__main__':
    main()
