#include "pch.h"
#include "HudCopy_Dx12.h"
#include "HudCopy_Common.h"
#include <wrl/client.h>

#include <Config.h>
#include <State.h>
#include "precompile/HudCopy_Shader.h"

void HudCopy_Dx12::ResourceBarrier(ID3D12GraphicsCommandList* cmdList, ID3D12Resource* resource,
                                   D3D12_RESOURCE_STATES beforeState, D3D12_RESOURCE_STATES afterState)
{
    if (beforeState == afterState)
        return;

    D3D12_RESOURCE_BARRIER barrier = {};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = resource;
    barrier.Transition.StateBefore = beforeState;
    barrier.Transition.StateAfter = afterState;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    cmdList->ResourceBarrier(1, &barrier);
}

bool HudCopy_Dx12::Dispatch(ID3D12GraphicsCommandList* cmdList, ID3D12Resource* hudless, ID3D12Resource* present,
                            D3D12_RESOURCE_STATES hudlessState, D3D12_RESOURCE_STATES presentState,
                            float hudDetectionThreshold)
{
    // Protect mutable CPU heap/buffer bookkeeping without waiting inside a
    // callback. This is not a fence for previously submitted GPU commands.
    auto dispatchLease = _dispatchCalls.TryTransition();
    if (!dispatchLease)
        return false;

    if (!_init || _device == nullptr || hudless == nullptr || present == nullptr || cmdList == nullptr)
        return false;

    // A cached shader/context must not submit resources from another device.
    // Unknown ownership skips this optional pass before recording commands.
    const auto belongsToDevice = [&](auto* child)
    {
        Microsoft::WRL::ComPtr<ID3D12Device> owner;
        return SUCCEEDED(child->GetDevice(IID_PPV_ARGS(&owner))) && owner.Get() == _device;
    };
    if (!belongsToDevice(cmdList) || !belongsToDevice(present) || !belongsToDevice(hudless) ||
        (_buffer && !belongsToDevice(_buffer)))
        return false;

    ScopedGpuTime_Dx12 scopedGpuTime(GpuTime.get(), cmdList);

    _counter++;
    _counter = _counter % HudCopy_NUM_OF_HEAPS;
    FrameDescriptorHeap& currentHeap = _frameHeaps[_counter];

    if (_buffer == nullptr)
    {
        LOG_DEBUG("[{0}] Start!", _name);

        auto resourceFlags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET | D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS |
                             D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS;

        auto result = Shader_Dx12::CreateBufferResource(_device, present, D3D12_RESOURCE_STATE_COPY_DEST, &_buffer,
                                                        resourceFlags);

        if (result)
            _buffer->SetName(L"HudCopy_Buffer");

        return result;
    }

    // CopyResource requires matching geometry/subresources. Keep the old buffer
    // alive on resize: earlier command lists may still reference it. Rebuilding
    // it here without queue-completion ownership would create a use-after-free.
    const auto sourceDesc = present->GetDesc();
    const auto bufferDesc = _buffer->GetDesc();
    if (sourceDesc.Dimension != bufferDesc.Dimension || sourceDesc.Width != bufferDesc.Width ||
        sourceDesc.Height != bufferDesc.Height || sourceDesc.DepthOrArraySize != bufferDesc.DepthOrArraySize ||
        sourceDesc.MipLevels != bufferDesc.MipLevels || sourceDesc.Format != bufferDesc.Format ||
        sourceDesc.SampleDesc.Count != bufferDesc.SampleDesc.Count ||
        sourceDesc.SampleDesc.Quality != bufferDesc.SampleDesc.Quality)
        return false;

    ResourceBarrier(cmdList, present, presentState, D3D12_RESOURCE_STATE_COPY_SOURCE);

    cmdList->CopyResource(_buffer, present);

    // Make sure present is in D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE
    ResourceBarrier(cmdList, present, D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    ResourceBarrier(cmdList, _buffer, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

    ResourceBarrier(cmdList, hudless, hudlessState, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

    // Create views
    CreateShaderResourceView(_device, hudless, currentHeap.GetSrvCPU(0));
    CreateShaderResourceView(_device, present, currentHeap.GetSrvCPU(1));
    CreateUnorderedAccessView(_device, _buffer, currentHeap.GetUavCPU(0), 0);

    InternalCompareParams constants {};
    constants.DiffThreshold = hudDetectionThreshold;

    if (!CreateConstantsBuffer(_device, _constantBuffer, constants, currentHeap.GetCbvCPU(0)))
    {
        LOG_ERROR("[{0}] Failed to create a constants buffer", _name);
        // No compute dispatch has run, but the copy and transitions above are
        // already recorded. Restore the caller's states on this failure path.
        ResourceBarrier(cmdList, present, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, presentState);
        ResourceBarrier(cmdList, hudless, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, hudlessState);
        ResourceBarrier(cmdList, _buffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_DEST);
        return false;
    }

    ID3D12DescriptorHeap* heaps[] = { currentHeap.GetHeapCSU() };
    cmdList->SetDescriptorHeaps(_countof(heaps), heaps);

    cmdList->SetComputeRootSignature(_rootSignature);
    cmdList->SetPipelineState(_pipelineState);

    cmdList->SetComputeRootDescriptorTable(0, currentHeap.GetTableGPUStart());

    auto presentDesc = present->GetDesc();
    UINT dispatchWidth = static_cast<UINT>((presentDesc.Width + InNumThreadsX - 1) / InNumThreadsX);
    UINT dispatchHeight = (presentDesc.Height + InNumThreadsY - 1) / InNumThreadsY;

    cmdList->Dispatch(dispatchWidth, dispatchHeight, 1);

    ResourceBarrier(cmdList, _buffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
    ResourceBarrier(cmdList, present, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);

    cmdList->CopyResource(present, _buffer);

    // Restore resource states
    ResourceBarrier(cmdList, present, D3D12_RESOURCE_STATE_COPY_DEST, presentState);
    ResourceBarrier(cmdList, hudless, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, hudlessState);
    ResourceBarrier(cmdList, _buffer, D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_COPY_DEST);

    return true;
}

HudCopy_Dx12::HudCopy_Dx12(std::string InName, ID3D12Device* InDevice) : Shader_Dx12(InName, InDevice)
{
    if (InDevice == nullptr)
    {
        LOG_ERROR("InDevice is nullptr!");
        return;
    }

    LOG_DEBUG("{0} start!", _name);

    if (!SetupRootSignature(InDevice, 2, 1, 1))
    {
        LOG_ERROR("Failed to setup root signature");
        return;
    }

    D3D12_RESOURCE_DESC desc = CD3DX12_RESOURCE_DESC::Buffer(sizeof(InternalCompareParams));
    auto heapProps = CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_UPLOAD);

    auto result =
        InDevice->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &desc, D3D12_RESOURCE_STATE_GENERIC_READ,
                                          nullptr, IID_PPV_ARGS(&_constantBuffer));

    if (result != S_OK)
    {
        LOG_ERROR("[{0}] CreateCommittedResource error {1:x}", _name, (unsigned int) result);
        return;
    }

    if (!CreateComputePipeline(InDevice, &_pipelineState, HudCopy_cso, sizeof(HudCopy_cso), shaderCode.c_str()))
    {
        LOG_ERROR("[{0}] Failed to create compute pipeline", _name);
        return;
    }

    _init = InitHeaps(InDevice, _frameHeaps, HudCopy_NUM_OF_HEAPS);
}

HudCopy_Dx12::~HudCopy_Dx12()
{
    if (State::Instance().isShuttingDown)
        return;

    if (!_init)
    {
        // Construction can return after allocating only part of the shader.
        // No Dispatch was possible; the base destructor skips these resources
        // when initialization failed, so retire them here before a later retry.
        SAFE_RELEASE(_pipelineState);
        SAFE_RELEASE(_rootSignature);
        SAFE_RELEASE(_constantBuffer);
    }

    for (int i = 0; i < HudCopy_NUM_OF_HEAPS; i++)
    {
        _frameHeaps[i].ReleaseHeaps();
    }

    SAFE_RELEASE(_buffer);
}
