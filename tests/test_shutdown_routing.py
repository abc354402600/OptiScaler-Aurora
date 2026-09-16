"""Compile the actual shutdown bodies with counted provider/NGX stand-ins.

This checks routing, not GPU shutdown or concurrency. No production function body
is duplicated here: changes to the exported routes are taken from the source tree.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def function(source, declaration):
    start = source.index(declaration)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


PRELUDE = r'''
#include <stdexcept>
#include <iostream>
#define NVSDK_NGX_API
using NVSDK_NGX_Result = int;
constexpr int NVSDK_NGX_Result_Success = 0, NVSDK_NGX_Result_Fail = -1;
struct ID3D12Device {};
using VkDevice = void*;
enum class FGNvngxReplacement { None, Nukems };
enum class FGInput { Upscaler };
bool shutdown = false;
ID3D12Device* D3D12Device = nullptr;
void* vkInstance = nullptr; void* vkPD = nullptr; VkDevice vkDevice = nullptr;
struct FG { int cleanups = 0; void Shutdown() { ++cleanups; } void DestroyFGContext() { ++cleanups; } } fg;
struct State {
    bool nvngxDx12Inited = true, nvngxVkInited = true, isShuttingDown = false, clearCapturedHudlesses = false;
    void* currentFeature = nullptr; FG* currentFG = &fg;
    FGInput activeFgInput = FGInput::Upscaler;
    FGNvngxReplacement activeFgNvngx = FGNvngxReplacement::Nukems;
    static State& Instance() { static State s; return s; }
};
struct Config {
    struct Setting { bool value_or_default() { return true; } } DLSSEnabled;
    static Config* Instance() { static Config c; return &c; }
};
struct DLSSFeatureDx12 { static void Shutdown(ID3D12Device*) {} };
struct NVNGXProxy {
    inline static bool dx = true, vk = true;
    inline static int globalDx = 0, deviceDx = 0, globalVk = 0, deviceVk = 0;
    static bool IsDx12Inited() { return dx; } static void SetDx12Inited(bool v) { dx = v; }
    static bool IsVulkanInited() { return vk; } static void SetVulkanInited(bool v) { vk = v; }
    static auto D3D12_Shutdown() { return +[]() { ++globalDx; return 0; }; }
    static auto D3D12_Shutdown1() { return +[](ID3D12Device*) { ++deviceDx; return 0; }; }
    static auto VULKAN_Shutdown() { return +[]() { ++globalVk; return 0; }; }
    static auto VULKAN_Shutdown1() { return +[](VkDevice) { ++deviceVk; return 0; }; }
};
struct Nvngx_FG {
    inline static int globalDx = 0, deviceDx = 0, globalVk = 0, deviceVk = 0;
    inline static void* lastDevice = nullptr;
    static int D3D12_Shutdown() { ++globalDx; return 0; }
    static int D3D12_Shutdown1(ID3D12Device* d) { ++deviceDx; lastDevice = d; return 0; }
    static int VULKAN_Shutdown() { ++globalVk; return 0; }
    static int VULKAN_Shutdown1(VkDevice d) { ++deviceVk; lastDevice = d; return 0; }
};
struct Nvngx_DllProxy {
    bool available = true;
    bool isDx12Available() { return available; } bool isVulkanAvailable() { return available; }
    int (*_DLSSG_D3D12_Shutdown)() = nullptr;
    int (*_DLSSG_D3D12_Shutdown1)(ID3D12Device*) = nullptr;
    int (*_DLSSG_VULKAN_Shutdown)() = nullptr;
    int (*_DLSSG_VULKAN_Shutdown1)(VkDevice) = nullptr;
    int D3D12_Shutdown(); int D3D12_Shutdown1(ID3D12Device* InDevice);
    int VULKAN_Shutdown(); int VULKAN_Shutdown1(VkDevice InDevice);
};
'''

CHECKS = r'''
int main() {
    int checks = 0; auto check = [&](bool ok) { if (!ok) throw std::runtime_error("shutdown route regression"); ++checks; };
    ID3D12Device device;
    check(NVSDK_NGX_D3D12_Shutdown1(&device) == 0);
    check(Nvngx_FG::deviceDx == 1 && Nvngx_FG::globalDx == 0 && Nvngx_FG::lastDevice == &device);
    check(NVNGXProxy::deviceDx == 1 && NVNGXProxy::globalDx == 0);
    check(fg.cleanups == 1 && !shutdown && !State::Instance().nvngxDx12Inited);
    NVNGXProxy::dx = true;
    check(NVSDK_NGX_D3D12_Shutdown() == 0 && Nvngx_FG::globalDx == 1 && NVNGXProxy::globalDx == 1);
    check(NVSDK_NGX_VULKAN_Shutdown1(&device) == 0);
    check(Nvngx_FG::deviceVk == 1 && Nvngx_FG::globalVk == 0 && Nvngx_FG::lastDevice == &device);
    check(NVNGXProxy::deviceVk == 1 && NVNGXProxy::globalVk == 0 && !shutdown);
    NVNGXProxy::vk = true;
    check(NVSDK_NGX_VULKAN_Shutdown() == 0 && Nvngx_FG::globalVk == 1 && NVNGXProxy::globalVk == 1);
    Nvngx_DllProxy proxy;
    check(proxy.D3D12_Shutdown() == -1 && proxy.D3D12_Shutdown1(&device) == -1);
    check(proxy.VULKAN_Shutdown() == -1 && proxy.VULKAN_Shutdown1(&device) == -1);
    proxy._DLSSG_D3D12_Shutdown = &Nvngx_FG::D3D12_Shutdown;
    proxy._DLSSG_D3D12_Shutdown1 = &Nvngx_FG::D3D12_Shutdown1;
    proxy._DLSSG_VULKAN_Shutdown = &Nvngx_FG::VULKAN_Shutdown;
    proxy._DLSSG_VULKAN_Shutdown1 = &Nvngx_FG::VULKAN_Shutdown1;
    check(proxy.D3D12_Shutdown() == 0 && proxy.D3D12_Shutdown1(&device) == 0);
    check(proxy.VULKAN_Shutdown() == 0 && proxy.VULKAN_Shutdown1(&device) == 0);
    proxy.available = false;
    check(proxy.D3D12_Shutdown() == -1 && proxy.VULKAN_Shutdown() == -1);
    std::cout << "PASS: " << checks << " extracted shutdown routing checks\n";
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--driver")
    args = parser.parse_args()
    bodies = []
    for api, filename, cleanup in (("D3D12", "Dx12", "ShutdownD3D12"), ("VULKAN", "Vk", "ShutdownVulkan")):
        source = (ROOT / f"OptiScaler/inputs/NVNGX_DLSS_{filename}.cpp").read_text(encoding="utf-8")
        for declaration in (f"static NVSDK_NGX_Result {cleanup}(",
                            f"NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_{api}_Shutdown(",
                            f"NVSDK_NGX_API NVSDK_NGX_Result NVSDK_NGX_{api}_Shutdown1("):
            bodies.append(function(source, declaration))
    source = (ROOT / "OptiScaler/framegen/nvngx/Nvngx_DllProxy.cpp").read_text(encoding="utf-8")
    for api in ("D3D12", "VULKAN"):
        for suffix in ("", "1"):
            bodies.append(function(source, f"NVSDK_NGX_Result Nvngx_DllProxy::{api}_Shutdown{suffix}("))
    with tempfile.TemporaryDirectory(prefix="aurora-shutdown-test-") as folder:
        path = Path(folder)
        cpp, exe = path / "test.cpp", path / "test.exe"
        cpp.write_text(PRELUDE + "\n".join(bodies) + CHECKS, encoding="utf-8")
        command = [args.compiler] + ([args.driver] if args.driver else [])
        if Path(args.compiler).stem.lower() == "cl":
            command += ["/nologo", "/EHsc", "/std:c++20", str(cpp), f"/Fe:{exe}"]
        else:
            command += ["-std=c++20", str(cpp), "-o", str(exe)]
        subprocess.run(command, cwd=path, check=True)
        subprocess.run([str(exe)], cwd=path, check=True)


if __name__ == "__main__":
    main()
