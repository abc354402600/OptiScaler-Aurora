"""Execute production overlay predicates and SL2 preference prefix, without a GPU.

Also check bounded integration contracts (early return ordering, SL1 separation,
game scope and configuration persistence). This is not a complete DXGI/SL test.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_shutdown_routing import function

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--driver')
    args = parser.parse_args()
    predicates = []
    for file, count in [('DxgiFactory_Hooks.cpp', 6), ('DxgiFactory_WrappedCalls.cpp', 3)]:
        source = (ROOT / 'OptiScaler/hooks' / file).read_text(encoding='utf-8')
        matches = re.findall(r'if\s*\(([^{};]*?Height[^{};]*?< 100[^{};]*?)\)\s*\{\s*LOG_WARN\("Overlay call!"\)', source)
        assert len(matches) == count, (file, len(matches))
        predicates += [m.replace('pDesc->BufferDesc.', '').replace('pDesc->', '') for m in matches]

    source = (ROOT / 'OptiScaler/hooks/Streamline_Hooks.cpp').read_text(encoding='utf-8')
    init = function(source, 'sl::Result StreamlineHooks::hkslInit(')
    prefix = init[init.index('    sl::Preferences localPref = pref;'):init.index('    if (localPref.logMessageCallback')]
    assert init.index('DisableOTA') < init.index('return o_slInit(')
    assert 'DisableOTA' not in function(source, 'bool StreamlineHooks::hkslInit_sl1(')
    quirks = (ROOT / 'OptiScaler/misc/Quirks.h').read_text(encoding='utf-8')
    entries = re.findall(r'QUIRK_ENTRY\([^;]*?\),', quirks)
    ota_entries = [entry for entry in entries if 'GameQuirk::DisableOTA' in entry]
    assert len(ota_entries) == 1 and '"controlresonant.exe"' in ota_entries[0]
    assert 'DoNotPreserveFGSwapChain' in ota_entries[0]
    config = (ROOT / 'OptiScaler/Config.cpp').read_text(encoding='utf-8')
    assert 'DisableOTA.set_from_config(readBool("NvApi", "DisableOTA"))' in config
    assert 'GetBoolValue(Instance()->DisableOTA.value_for_config())' in config
    assert 'CustomOptional<bool> DisableOTA { false };' in (ROOT / 'OptiScaler/Config.h').read_text(encoding='utf-8')
    dll = (ROOT / 'OptiScaler/dllmain.cpp').read_text(encoding='utf-8')
    policy = re.search(r'    if \(quirks & GameQuirk::DisableOTA.*?quirks.reset\(GameQuirk::DisableOTA\);', function(dll, 'static void CheckQuirks('), re.S).group()
    # Extract actual policy and execute explicit true/false versus auto below.
    cpp = r'''
#include <iostream>
#include <cstdlib>
#include <optional>
struct Option {
 std::optional<bool> value;
 bool has_value(){return value.has_value();}
 bool value_or_default(){return value.value_or(false);}
 void set_volatile_value(bool v){value=v;}
};
struct Config {Option DisableOTA; static Config* Instance(){static Config c;return &c;}};
namespace sl {struct Preferences {unsigned flags;}; struct PreferenceFlags {
 static constexpr unsigned eAllowOTA=1,eLoadDownloadedPlugins=2;
};}
enum class GameQuirk {DisableOTA};
struct Quirks {bool enabled; bool operator&(GameQuirk){return enabled;} void reset(GameQuirk){enabled=false;}};
unsigned Apply(const sl::Preferences& pref){
''' + prefix + 'return localPref.flags;}\nvoid Policy(Quirks& quirks){\n' + policy + '\n}\n'
    for i, predicate in enumerate(predicates):
        cpp += f'bool overlay{i}(unsigned Width,unsigned Height){{return {predicate};}}\n'
    cpp += r'''
int main(){int checks=0;auto check=[&](bool ok){++checks;if(!ok){std::cerr<<"Failed "<<checks;std::exit(2);}};
'''
    for i in range(len(predicates)):
        cpp += f'''
 check(!overlay{i}(0,0)); check(!overlay{i}(0,1080)); check(!overlay{i}(1920,0));
 check(!overlay{i}(100,100)); check(!overlay{i}(1920,1080));
 for(unsigned tiny:{{1u,99u}}){{check(overlay{i}(tiny,1080));check(overlay{i}(1920,tiny));
 check(overlay{i}(0,tiny));check(overlay{i}(tiny,0));}}
'''
    cpp += r'''
for(bool game:{false,true})for(int setting:{-1,0,1}){
 Config::Instance()->DisableOTA.value=setting<0?std::nullopt:std::optional<bool>(setting==1);
 Quirks quirks{game};Policy(quirks);
 bool disabled=setting<0?game:setting==1;
 check(Config::Instance()->DisableOTA.value_or_default()==disabled);
 for(unsigned flags=0;flags<16;++flags){sl::Preferences pref{flags};
 check(Apply(pref)==(disabled?(flags&~3u):flags));check(pref.flags==flags);}
}
std::cout<<"PASS: "<<checks<<" October compatibility checks (production predicates/prefix/policy)\n";}
'''
    with tempfile.TemporaryDirectory(prefix='aurora-october-') as directory:
        path = Path(directory)
        test, exe = path / 'test.cpp', path / 'test.exe'
        test.write_text(cpp, encoding='utf-8')
        command = [args.compiler] + ([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == 'cl':
            command += ['/nologo', '/EHsc', '/std:c++20', str(test), '/Fe:' + str(exe)]
        else:
            command += ['-std=c++20', str(test), '-o', str(exe)]
        subprocess.run(command, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True, timeout=25)


if __name__ == '__main__':
    main()
