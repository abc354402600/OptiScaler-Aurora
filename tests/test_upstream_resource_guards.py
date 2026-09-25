"""Execute selected production HUD/copy guards without a graphics driver.

The format helper is complete. Resource classification and output
lookup are the real prefixes; later rendering is a counted sentinel. Copy-region
and barrier statements are extracted verbatim from the actual capture path.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]

PRELUDE = r'''
#include <cstdlib>
#include <iostream>
#include <vector>
#include <utility>
#include <cstdint>
using UINT=unsigned; using DXGI_FORMAT=int;
#define FAILED(x) ((x)<0)
constexpr int D3D12_RESOURCE_DIMENSION_TEXTURE2D=2;
constexpr UINT D3D12_RESOURCE_FLAG_RAYTRACING_ACCELERATION_STRUCTURE=1,D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL=2,
 D3D12_RESOURCE_FLAG_VIDEO_DECODE_REFERENCE_ONLY=4,D3D12_RESOURCE_FLAG_DENY_SHADER_RESOURCE=8,
 D3D12_RESOURCE_FLAG_VIDEO_ENCODE_REFERENCE_ONLY=16;
struct Desc { int Dimension=2; UINT DepthOrArraySize=1; struct { UINT Count=1; } SampleDesc; UINT Flags=0; };
struct ID3D12Resource { Desc desc; int reads=0; Desc GetDesc(){++reads;return desc;} };
struct State { bool isShuttingDown=false; static State& Instance(){static State s;return s;} };
struct ResTrack_Dx12 { static bool CheckResource(ID3D12Resource*); };
struct ResourceInfo { uint64_t width=0;UINT height=0;ID3D12Resource* buffer=nullptr;int state=9; };
struct D3D12_BOX { UINT left=0,top=0,front=0,right=0,bottom=0,back=1; };
struct Command {
 UINT x=0,y=0,copies=0; D3D12_BOX box;
 void CopyTextureRegion(void*,UINT a,UINT b,UINT,void*,D3D12_BOX* p){x=a;y=b;box=*p;++copies;}
 void CopyResource(ID3D12Resource*,ID3D12Resource*){++copies;}
};
constexpr int D3D12_RESOURCE_STATE_VIDEO_ENCODE_WRITE=99,D3D12_RESOURCE_STATE_COPY_SOURCE=4;
std::vector<std::pair<int,int>> barriers;
void ResourceBarrier(Command*,ID3D12Resource*,int from,int to){barriers.emplace_back(from,to);}
constexpr int NVSDK_NGX_Parameter_Output=0,NVSDK_NGX_Result_Success=0;
struct Parameters {
 ID3D12Resource* first=nullptr;ID3D12Resource* fallback=nullptr;int status=0,calls=0;
 int Get(int,ID3D12Resource** p){++calls;*p=first;return status;}
 int Get(int,void** p){++calls;*p=fallback;return fallback?0:-1;}
};
int outputReached=0;
'''
CHECKS = r'''
int main(){
 int checks=0;auto check=[&](bool ok){if(!ok){std::cerr<<"resource check "<<checks+1<<" failed\n";std::exit(2);}++checks;};
 check(!CompareResourceFormats(DXGI_FORMAT_UNKNOWN,DXGI_FORMAT_UNKNOWN));
 check(!CompareResourceFormats(DXGI_FORMAT_UNKNOWN,DXGI_FORMAT_R8G8B8A8_UNORM));
 check(CompareResourceFormats(DXGI_FORMAT_R8G8B8A8_UNORM,DXGI_FORMAT_R8G8B8A8_UNORM_SRGB));
 check(!CompareResourceFormats(DXGI_FORMAT_R8G8B8A8_UNORM,DXGI_FORMAT_R16G16B16A16_FLOAT));
 check(!CompareResourceFormats(10001,10002));
 check(!CompareResourceFormats(10001,DXGI_FORMAT_R8G8B8A8_UNORM));
 ID3D12Resource texture;
 check(ResTrack_Dx12::CheckResource(&texture));check(!ResTrack_Dx12::CheckResource(nullptr));
 State::Instance().isShuttingDown=true;int reads=texture.reads;
 check(!ResTrack_Dx12::CheckResource(&texture)&&texture.reads==reads);State::Instance().isShuttingDown=false;
 texture.desc.Dimension=1;check(!ResTrack_Dx12::CheckResource(&texture));texture.desc.Dimension=2;
 for(UINT count:{0u,2u,4u}){texture.desc.SampleDesc.Count=count;check(!ResTrack_Dx12::CheckResource(&texture));}
 texture.desc.SampleDesc.Count=1;
 for(UINT count:{0u,2u,6u}){texture.desc.DepthOrArraySize=count;check(!ResTrack_Dx12::CheckResource(&texture));}
 texture.desc.DepthOrArraySize=1;
 for(UINT flag:{1u,2u,4u,8u,16u,31u}){texture.desc.Flags=flag;check(!ResTrack_Dx12::CheckResource(&texture));}
 texture.desc.Flags=32;check(ResTrack_Dx12::CheckResource(&texture));
 // Mixed larger/smaller axes used to underflow unsigned offsets or overrun the target.
 for(UINT sw:{1u,1920u,3840u})for(UINT sh:{1u,1080u,2160u})
 for(UINT w:{1u,1280u,4000u})for(UINT h:{1u,720u,2400u}){
   ResourceInfo info{w,h};Command cmd;CopyRegion(&cmd,&info,sw,sh);
   check(cmd.copies==1 && cmd.box.right<=w && cmd.box.bottom<=h &&
         uint64_t(cmd.x)+cmd.box.right<=sw && uint64_t(cmd.y)+cmd.box.bottom<=sh);
 }
 ResourceInfo info{1920,1080,&texture,9};Command cmd;
 barriers.clear();CopyWithBarriers(&cmd,&info,3);
 check(cmd.copies==1 && barriers==std::vector<std::pair<int,int>>{{3,4},{4,3}});
 barriers.clear();CopyWithBarriers(&cmd,&info,99);check(cmd.copies==2&&barriers.empty());
 Parameters params;
 OutputLookup(&params);check(outputReached==0&&params.calls==1);
 params.status=-1;OutputLookup(&params);check(outputReached==0&&params.calls==3);
 params.fallback=&texture;OutputLookup(&params);check(outputReached==1&&params.calls==5);
 params.status=0;params.first=&texture;OutputLookup(&params);check(outputReached==2&&params.calls==6);
 std::cout<<"PASS: "<<checks<<" upstream resource checks\n";
}
'''


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver');args=parser.parse_args()
    hud=(ROOT/'OptiScaler/hudfix/Hudfix_Dx12.cpp').read_text(encoding='utf-8')
    track=(ROOT/'OptiScaler/resource_tracking/ResTrack_dx12.cpp').read_text(encoding='utf-8')
    upscale=(ROOT/'OptiScaler/inputs/FG/Upscaler_Inputs_Dx12.cpp').read_text(encoding='utf-8')
    formats=function(hud,'inline static int GetFormatGroup(')+function(hud,'inline static bool CompareResourceFormats(')
    names=['DXGI_FORMAT_UNKNOWN']+sorted(set(re.findall(r'DXGI_FORMAT_\w+',formats))-{'DXGI_FORMAT_UNKNOWN'})
    enums='\n'.join(f'constexpr int {name}={i};' for i,name in enumerate(names))
    classify=function(track,'bool ResTrack_Dx12::CheckResource(')
    classify=classify[:classify.index('    auto& s = State::Instance();')]+'return true;\n}\n'
    region=hud[hud.index('                const UINT copyWidth'):]
    region=region[:region.index('cmdList->CopyTextureRegion')]+region[region.index('cmdList->CopyTextureRegion'):].split(';',1)[0]+';'
    region='void CopyRegion(Command* cmdList,ResourceInfo* resource,UINT scWidth,UINT scHeight){D3D12_BOX srcBox;int dstLocation,srcLocation;'+region+'}\n'
    copy=hud[hud.index('                // Using state D3D12_RESOURCE_STATE_VIDEO_ENCODE_WRITE as skip flag'):]
    copy=copy[:copy.index('                LOG_DEBUG("Copy created");')]
    copy='void CopyWithBarriers(Command* cmdList,ResourceInfo* resource,int state){ID3D12Resource* _captureBuffer[1]={};int fIndex=0;'+copy+'}\n'
    output=function(upscale,'void UpscalerInputsDx12::UpscaleEnd(')
    output=output[output.index('            ID3D12Resource* output = nullptr;'):output.index('            ResourceInfo info')]
    output='void OutputLookup(Parameters* InParameters){'+output+'++outputReached;}\n'
    cpp=PRELUDE+enums+formats+classify+region+copy+output+CHECKS
    with tempfile.TemporaryDirectory(prefix='aurora-upstream-guards-') as directory:
        path=Path(directory);test=path/'test.cpp';exe=path/'test.exe';test.write_text(cpp,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':command+=['/nologo','/EHsc','/std:c++20',str(test),'/Fe:'+str(exe)]
        else:command+=['-std=c++20',str(test),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=25)


if __name__=='__main__':main()
