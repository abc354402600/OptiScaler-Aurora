"""Execute actual Vulkan timing read body with deterministic result/failure stand-ins."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = r'''
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <mutex>
#include <deque>
#include <stdexcept>
using VkDevice=void*;using VkQueryPool=void*;
constexpr auto VK_NULL_HANDLE=nullptr;
constexpr int VK_SUCCESS=0,VK_QUERY_RESULT_64_BIT=1;
int checks=0,queries=0,result=0;bool writeOutput=true,throwQuery=false;
uint64_t start=100,end=2000100;
void check(bool ok){if(!ok){std::cerr<<"timing check "<<checks+1<<" failed\n";std::exit(2);}++checks;}
struct Mutex {bool locked=false;void lock(){check(!locked);locked=true;}void unlock(){check(locked);locked=false;}};
struct Samples {
 std::deque<double> values{10,20,30};bool throwPush=false;
 void push_back(double v){if(throwPush)throw std::bad_alloc();values.push_back(v);}
 void pop_front(){check(!values.empty());values.pop_front();}
};
struct State {Mutex frameTimeMutex;Samples upscaleTimes;static State& Instance(){static State s;return s;}};
struct UpscalerTimeVk {
 static inline VkDevice _device=nullptr;
 static inline bool _enabled=true;
 static inline VkQueryPool _queryPool=nullptr;
 static inline double _timeStampPeriod=1;
 static inline bool _vkUpscaleTrig=false;
 static void ReadUpscalingTime(VkDevice device);
};
int vkGetQueryPoolResults(VkDevice device,VkQueryPool pool,int first,int count,size_t bytes,
                         uint64_t* data,size_t stride,int flags){
 ++queries;check(device&&pool&&first==0&&count==2&&bytes==16&&stride==8);
 check(flags==VK_QUERY_RESULT_64_BIT); // No blocking wait or partial result request.
 if(throwQuery)throw std::runtime_error("query");
 if(writeOutput){data[0]=start;data[1]=end;}
 return result;
}
// BODY
int main(){
 int device,pool;
 UpscalerTimeVk::_queryPool=&pool;UpscalerTimeVk::_device=&device;
 auto& state=State::Instance();
 auto read=[&]{UpscalerTimeVk::_vkUpscaleTrig=true;UpscalerTimeVk::ReadUpscalingTime(&device);};
 auto original=state.upscaleTimes.values;
 // Drivers may leave output untouched or return plausible but invalid partial data.
 for(int error:{1,-1,-2,-4})for(bool writes:{true,false}){
  result=error;writeOutput=writes;int before=queries;read();
  check(queries==before+1&&state.upscaleTimes.values==original);
  check(!UpscalerTimeVk::_vkUpscaleTrig&&!state.frameTimeMutex.locked);
  UpscalerTimeVk::ReadUpscalingTime(&device);check(queries==before+1);
 }
 result=0;writeOutput=true;read();
 check(state.upscaleTimes.values.size()==3&&state.upscaleTimes.values.back()==2.0);
 check(state.upscaleTimes.values.front()==20&&!state.frameTimeMutex.locked);
 original=state.upscaleTimes.values;
 int before=queries;
 UpscalerTimeVk::_vkUpscaleTrig=true;UpscalerTimeVk::ReadUpscalingTime(nullptr);
 check(queries==before&&!UpscalerTimeVk::_vkUpscaleTrig);
 UpscalerTimeVk::_queryPool=nullptr;read();check(queries==before&&!UpscalerTimeVk::_vkUpscaleTrig);
 UpscalerTimeVk::_queryPool=&pool;
 for(uint64_t delta:{uint64_t(0),uint64_t(5000000000),uint64_t(6000000000)}){
  end=start+delta;read();check(state.upscaleTimes.values==original);
 }
 end=start+2000000;
 state.upscaleTimes.throwPush=true;bool threw=false;
 try{read();}catch(const std::bad_alloc&){threw=true;}
 check(threw&&!state.frameTimeMutex.locked&&!UpscalerTimeVk::_vkUpscaleTrig);
 check(state.upscaleTimes.values==original);
 state.upscaleTimes.throwPush=false;read();check(state.upscaleTimes.values.back()==2.0);
 throwQuery=true;threw=false;try{read();}catch(const std::runtime_error&){threw=true;}
 check(threw&&!UpscalerTimeVk::_vkUpscaleTrig&&!state.frameTimeMutex.locked);
 throwQuery=false;read();check(state.upscaleTimes.values.back()==2.0);
 std::cout<<"PASS: "<<checks<<" Vulkan timing result checks\n";
}
'''


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiler',required=True)
    parser.add_argument('--driver')
    parser.add_argument('--source-ref',help='Historical source for a negative control')
    args=parser.parse_args()
    name='OptiScaler/upscaler_time/UpscalerTime_Vk.cpp'
    source=(subprocess.check_output(['git','show',args.source_ref+':'+name],cwd=ROOT,text=True,encoding='utf-8')
            if args.source_ref else (ROOT/name).read_text(encoding='utf-8'))
    body=function(source,'void UpscalerTimeVk::ReadUpscalingTime(')
    with tempfile.TemporaryDirectory(prefix='aurora-vulkan-timing-') as folder:
        path=Path(folder);cpp=path/'test.cpp';exe=path/'test.exe'
        cpp.write_text(PRELUDE.replace('// BODY',body),encoding='utf-8')
        cmd=[args.compiler]+([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower()=='cl':cmd+=['/nologo','/EHsc','/std:c++20',str(cpp),'/Fe:'+str(exe)]
        else:cmd+=['-std=c++20',str(cpp),'-o',str(exe)]
        subprocess.run(cmd,cwd=path,check=True)
        subprocess.run([str(exe)],cwd=path,check=True,timeout=30)


if __name__=='__main__':main()
