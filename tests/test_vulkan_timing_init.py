"""Production timing fields and four method bodies with counted Vulkan stand-ins."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_shutdown_routing import function
from test_vulkan_timing_results import PRELUDE

ROOT=Path(__file__).resolve().parents[1]
STUBS=r'''
using VkPhysicalDevice=void*;using VkCommandBuffer=void*;
constexpr int VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO=5,VK_QUERY_TYPE_TIMESTAMP=2;
constexpr int VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT=1,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT=2;
struct VkQueryPoolCreateInfo {int sType=0,queryType=0,queryCount=0;};
struct VkPhysicalDeviceProperties {struct {double timestampPeriod=0;} limits;};
int creates=0,properties=0,commands=0,createResult=0;void* output=nullptr;bool throwProperties=false;
void vkGetPhysicalDeviceProperties(VkPhysicalDevice pd,VkPhysicalDeviceProperties* p){
 ++properties;check(pd!=nullptr);if(throwProperties)throw 77;p->limits.timestampPeriod=3;
}
int vkCreateQueryPool(VkDevice d,VkQueryPoolCreateInfo* info,void*,VkQueryPool* out){
 ++creates;check(d&&info->sType==5&&info->queryType==2&&info->queryCount==2);
 *out=output;return createResult;
}
void vkCmdResetQueryPool(VkCommandBuffer cmd,VkQueryPool pool,int,int){check(cmd&&pool);++commands;}
void vkCmdWriteTimestamp(VkCommandBuffer cmd,int,VkQueryPool pool,int){check(cmd&&pool);++commands;}
'''
CHECKS=r'''
int main(){int d,pd,pool,other,cmd;
 auto reset=[] {UpscalerTimeVk::_queryPool=nullptr;UpscalerTimeVk::_device=nullptr;
  UpscalerTimeVk::_physicalDevice=nullptr;UpscalerTimeVk::_enabled=false;UpscalerTimeVk::_vkUpscaleTrig=false;};
 for(bool nullDevice:{false,true}){
  reset();int c=creates,p=properties;
  UpscalerTimeVk::Init(nullDevice?nullptr:&d,nullDevice?&pd:nullptr);
  check(creates==c&&properties==p&&!UpscalerTimeVk::_enabled);
 }
 for(int failure:{-1,-2})for(bool invalidOutput:{false,true}){
  reset();createResult=failure;output=invalidOutput?&pool:nullptr;
  UpscalerTimeVk::Init(&d,&pd);
  check(!UpscalerTimeVk::_enabled&&UpscalerTimeVk::_queryPool==nullptr);
  int c=commands;UpscalerTimeVk::UpscaleStart(&cmd);UpscalerTimeVk::UpscaleEnd(&cmd);
  check(commands==c&&!UpscalerTimeVk::_vkUpscaleTrig);
  createResult=0;output=&pool;UpscalerTimeVk::Init(&d,&pd);
  check(UpscalerTimeVk::_enabled&&UpscalerTimeVk::_queryPool==&pool&&UpscalerTimeVk::_device==&d);
 }
 reset();createResult=0;output=nullptr;UpscalerTimeVk::Init(&d,&pd);
 check(!UpscalerTimeVk::_enabled&&UpscalerTimeVk::_queryPool==nullptr);
 throwProperties=true;bool threw=false;int c=creates;
 try{UpscalerTimeVk::Init(&d,&pd);}catch(int){threw=true;}throwProperties=false;
 check(threw&&creates==c&&!UpscalerTimeVk::_enabled);
 output=&pool;UpscalerTimeVk::Init(&d,&pd);
 check(UpscalerTimeVk::_enabled&&UpscalerTimeVk::_timeStampPeriod==3);
 c=creates;int p=properties;
 UpscalerTimeVk::_vkUpscaleTrig=true;UpscalerTimeVk::Init(&d,&pd);
 check(creates==c&&properties==p&&!UpscalerTimeVk::_vkUpscaleTrig&&UpscalerTimeVk::_enabled);
 int before=commands;UpscalerTimeVk::UpscaleStart(nullptr);UpscalerTimeVk::UpscaleEnd(nullptr);
 check(commands==before&&!UpscalerTimeVk::_vkUpscaleTrig);
 UpscalerTimeVk::UpscaleStart(&cmd);UpscalerTimeVk::UpscaleEnd(&cmd);
 check(commands==before+3&&UpscalerTimeVk::_vkUpscaleTrig);
 int q=queries;UpscalerTimeVk::ReadUpscalingTime(&other);
 check(queries==q&&!UpscalerTimeVk::_vkUpscaleTrig);
 for(bool foreignPhysical:{false,true}){
  UpscalerTimeVk::Init(foreignPhysical?&d:&other,foreignPhysical?&other:&pd);
  check(!UpscalerTimeVk::_enabled&&creates==c&&UpscalerTimeVk::_queryPool==&pool&&UpscalerTimeVk::_device==&d);
  before=commands;UpscalerTimeVk::UpscaleStart(&cmd);UpscalerTimeVk::UpscaleEnd(&cmd);
  check(commands==before&&!UpscalerTimeVk::_vkUpscaleTrig);
  UpscalerTimeVk::Init(&d,&pd);check(UpscalerTimeVk::_enabled&&creates==c);
 }
 UpscalerTimeVk::UpscaleEnd(&cmd);UpscalerTimeVk::ReadUpscalingTime(&d);
 check(queries==q+1&&State::Instance().upscaleTimes.values.back()==6.0);
 std::cout<<"PASS: "<<checks<<" Vulkan timing initialization checks\n";
}
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);parser.add_argument('--driver')
    parser.add_argument('--source-ref',help='Historical method bodies for negative control')
    parser.add_argument('--negative-control',choices=['ignore-create-result'])
    args=parser.parse_args()
    name='OptiScaler/upscaler_time/UpscalerTime_Vk.cpp'
    source=(subprocess.check_output(['git','show',args.source_ref+':'+name],cwd=ROOT,text=True,encoding='utf-8')
            if args.source_ref else (ROOT/name).read_text(encoding='utf-8'))
    if args.negative_control:
        old='vkCreateQueryPool(device, &queryPoolInfo, nullptr, &candidate) != VK_SUCCESS'
        assert old in source
        source=source.replace(old,'(vkCreateQueryPool(device, &queryPoolInfo, nullptr, &candidate), false)')
    header=(ROOT/'OptiScaler/upscaler_time/UpscalerTime_Vk.h').read_text(encoding='utf-8')
    header=re.sub(r'^#.*$','',header,flags=re.M).replace('private:','public:')
    prelude=PRELUDE[:PRELUDE.index('// BODY')]
    start=prelude.index('struct UpscalerTimeVk {');end=prelude.index('\n};',start)+3
    prelude=prelude[:start]+STUBS+header+prelude[end:]
    bodies='\n'.join(function(source,'void UpscalerTimeVk::'+name+'(')
                     for name in ('Init','UpscaleStart','UpscaleEnd','ReadUpscalingTime'))
    with tempfile.TemporaryDirectory(prefix='aurora-timing-init-') as folder:
        path=Path(folder);cpp=path/'test.cpp';exe=path/'test.exe'
        cpp.write_text(prelude+bodies+CHECKS,encoding='utf-8')
        command=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':command+=['/nologo','/EHsc','/std:c++20',str(cpp),'/Fe:'+str(exe)]
        else:command+=['-std=c++20',str(cpp),'-o',str(exe)]
        subprocess.run(command,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)

if __name__=='__main__':main()
