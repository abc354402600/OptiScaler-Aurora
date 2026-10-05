"""Execute the experimental COM holder with a counted D3D12 private-data stand-in.

No production integration or real COM/D3D12 runtime is exercised.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver', default='c++')
    args = parser.parse_args()
    cpp = r'''
#include <memory>
#include <iostream>
#include <cstdlib>
#include <cstring>
#include <new>
using ULONG=unsigned long;using UINT=unsigned;using HRESULT=int;
using GUID=int;using REFGUID=const GUID&;using REFIID=const GUID&;
constexpr GUID IID_IUnknown=0,key=91,otherKey=92;
constexpr HRESULT S_OK=0,E_POINTER=-1,E_NOINTERFACE=-2,E_FAIL=-3;
#define STDMETHODCALLTYPE
#define SUCCEEDED(x) ((x)>=0)
#define FAILED(x) ((x)<0)
bool IsEqualGUID(REFGUID a,REFGUID b){return a==b;}
struct IUnknown {virtual HRESULT QueryInterface(REFIID,void**)=0;
 virtual ULONG AddRef()=0;virtual ULONG Release()=0;};
struct ID3D12Object {
 IUnknown* stored=nullptr;GUID storedKey=0;bool failSet=false,failGet=false;
 int reads=0,writes=0;
 HRESULT SetPrivateDataInterface(REFGUID id,const IUnknown* p){
  ++writes;if(failSet)return E_FAIL;
  auto* next=const_cast<IUnknown*>(p);if(next)next->AddRef();
  if(stored)stored->Release();stored=next;storedKey=id;return S_OK;
 }
 HRESULT GetPrivateData(REFGUID id,UINT* size,void* out){
  ++reads;if(failGet||id!=storedKey||!stored)return E_FAIL;
  if(*size<sizeof(stored))return E_FAIL;
  stored->AddRef();std::memcpy(out,&stored,sizeof(stored));*size=sizeof(stored);return S_OK;
 }
 ~ID3D12Object(){if(stored)stored->Release();}
};
#include "patches/experimental/D3D12PrivateState.h"
struct State {static inline int alive=0;int value=7;
 State(){++alive;}~State(){--alive;}};
using Store=AuroraCandidate::PrivateState<State>;
int main(){int checks=0;auto check=[&](bool ok){++checks;if(!ok){std::cerr<<"FAIL "<<checks;std::exit(2);}};
 check(!Store::Read(nullptr,key));check(!Store::Store(nullptr,key,std::make_shared<State>()));
 check(State::alive==0);
 alignas(ID3D12Object) unsigned char memory[sizeof(ID3D12Object)];
 auto* obj=new(memory) ID3D12Object;
 check(!Store::Read(obj,key));check(!Store::Store(obj,key,{}));
 auto value=std::make_shared<State>();std::weak_ptr<State> old=value;
 check(Store::Store(obj,key,value));value.reset();check(!old.expired());
 for(int i=0;i<1000;++i){auto view=Store::Read(obj,key);check(view&&view->value==7);}
 void* unknown=nullptr;check(obj->stored->QueryInterface(IID_IUnknown,&unknown)==S_OK);
 check(unknown!=nullptr);static_cast<IUnknown*>(unknown)->Release();
 check(obj->stored->QueryInterface(key,nullptr)==E_POINTER);
 unknown=reinterpret_cast<void*>(1);check(obj->stored->QueryInterface(otherKey,&unknown)==E_NOINTERFACE);
 check(unknown==nullptr);check(!Store::Read(obj,otherKey));
 obj->failGet=true;check(!Store::Read(obj,key));obj->failGet=false;
 obj->failSet=true;auto failed=std::make_shared<State>();std::weak_ptr<State> failedWeak=failed;
 check(!Store::Store(obj,key,failed));failed.reset();check(failedWeak.expired());
 check(!old.expired());obj->failSet=false;
 auto retained=Store::Read(obj,key);
 auto replacement=std::make_shared<State>();replacement->value=8;
 check(Store::Store(obj,key,replacement));replacement.reset();
 check(!old.expired());retained.reset();check(old.expired());
 auto inFlight=Store::Read(obj,key);std::weak_ptr<State> second=inFlight;
 obj->~ID3D12Object();check(!second.expired());check(inFlight->value==8);
 // Construct a new object at precisely the same address. It must have no old state.
 obj=new(memory) ID3D12Object;check(!Store::Read(obj,key));
 check(Store::Store(obj,key,std::make_shared<State>()));check(Store::Read(obj,key)->value==7);
 inFlight.reset();check(second.expired());
 obj->SetPrivateDataInterface(key,nullptr);check(State::alive==0);check(!Store::Read(obj,key));
 obj->~ID3D12Object();check(State::alive==0);
 std::cout<<checks<<" checks passed: 29 lifetime assertions + 1000 balanced reads (COM stand-in only)\n";
}
'''
    with tempfile.TemporaryDirectory(prefix='aurora-private-state-') as folder:
        folder = Path(folder)
        (folder/'test.cpp').write_text(cpp, encoding='utf-8')
        subprocess.run([args.compiler, args.driver, '-std=c++20', '-I', str(ROOT),
                        str(folder/'test.cpp'), '-o', str(folder/'test.exe')], check=True)
        subprocess.run([str(folder/'test.exe')], check=True)
        header = (ROOT/'patches/experimental/D3D12PrivateState.h').read_text(encoding='utf-8')
        override = folder/'patches/experimental/D3D12PrivateState.h'
        override.parent.mkdir(parents=True)
        for name, statement in [('read-ref-leak', 'value->Release(); // Balance GetPrivateData'),
                                ('store-ref-leak', 'holder->Release(); // SetPrivateDataInterface')]:
            assert header.count(statement) == 1
            override.write_text(header.replace(statement, '// mutation: '+statement), encoding='utf-8')
            subprocess.run([args.compiler, args.driver, '-std=c++20', '-I', str(folder), '-I', str(ROOT),
                            str(folder/'test.cpp'), '-o', str(folder/'test.exe')], check=True)
            result = subprocess.run([str(folder/'test.exe')], capture_output=True, text=True)
            assert result.returncode == 2 and 'FAIL ' in result.stderr, (name, result)
            print('Mutation rejected:', name)


if __name__ == '__main__':
    main()
