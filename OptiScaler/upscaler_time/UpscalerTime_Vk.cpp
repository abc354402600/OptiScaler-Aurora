#include "pch.h"
#include "UpscalerTime_Vk.h"

#include <State.h>
#include <mutex>

void UpscalerTimeVk::Init(VkDevice device, VkPhysicalDevice pd)
{
    _enabled = false;
    _vkUpscaleTrig = false;
    if (device == VK_NULL_HANDLE || pd == VK_NULL_HANDLE)
        return;
    // Keep an existing allocation: its GPU completion is not owned here.
    // Another device skips optional timing instead of replacing an in-flight pool.
    if (_queryPool != VK_NULL_HANDLE)
    {
        _enabled = device == _device && pd == _physicalDevice;
        return;
    }

    VkPhysicalDeviceProperties deviceProperties {};
    vkGetPhysicalDeviceProperties(pd, &deviceProperties);
    VkQueryPoolCreateInfo queryPoolInfo {};
    queryPoolInfo.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
    queryPoolInfo.queryType = VK_QUERY_TYPE_TIMESTAMP;
    queryPoolInfo.queryCount = 2;
    VkQueryPool candidate = VK_NULL_HANDLE;
    if (vkCreateQueryPool(device, &queryPoolInfo, nullptr, &candidate) != VK_SUCCESS || candidate == VK_NULL_HANDLE)
        return;

    _queryPool = candidate;
    _device = device;
    _physicalDevice = pd;
    _timeStampPeriod = deviceProperties.limits.timestampPeriod;
    _enabled = true;
}

void UpscalerTimeVk::UpscaleStart(VkCommandBuffer cmdBuffer)
{
    if (!_enabled || _queryPool == VK_NULL_HANDLE || cmdBuffer == VK_NULL_HANDLE)
        return;

    vkCmdResetQueryPool(cmdBuffer, _queryPool, 0, 2);
    vkCmdWriteTimestamp(cmdBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, _queryPool, 0);
}

void UpscalerTimeVk::UpscaleEnd(VkCommandBuffer cmdBuffer)
{
    if (!_enabled || _queryPool == VK_NULL_HANDLE || cmdBuffer == VK_NULL_HANDLE)
        return;

    vkCmdWriteTimestamp(cmdBuffer, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, _queryPool, 1);
    _vkUpscaleTrig = true;
}

void UpscalerTimeVk::ReadUpscalingTime(VkDevice device)
{
    if (!_vkUpscaleTrig)
        return;
    _vkUpscaleTrig = false;
    if (!_enabled || _queryPool == VK_NULL_HANDLE || device == VK_NULL_HANDLE || device != _device)
        return;

    // Without WAIT_BIT the query may not be ready. Never consume failed/partial
    // output, and do not stall the render thread for optional timing telemetry.
    uint64_t timestamps[2] {};
    if (vkGetQueryPoolResults(device, _queryPool, 0, 2, sizeof(timestamps), timestamps, sizeof(uint64_t),
                              VK_QUERY_RESULT_64_BIT) != VK_SUCCESS)
        return;

    const double elapsedTimeMs = (timestamps[1] - timestamps[0]) * _timeStampPeriod / 1e6;
    if (elapsedTimeMs > 0.0 && elapsedTimeMs < 5000.0)
    {
        std::scoped_lock lock(State::Instance().frameTimeMutex);
        State::Instance().upscaleTimes.push_back(elapsedTimeMs);
        State::Instance().upscaleTimes.pop_front();
    }
}
