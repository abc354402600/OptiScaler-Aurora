#pragma once

#include "SysUtils.h"

#include <vulkan/vulkan.hpp>

class UpscalerTimeVk
{
  public:
    static void Init(VkDevice device, VkPhysicalDevice pd);
    static void UpscaleStart(VkCommandBuffer cmdBuffer);
    static void UpscaleEnd(VkCommandBuffer cmdBuffer);
    static void ReadUpscalingTime(VkDevice device);

  private:
    static inline VkDevice _device = VK_NULL_HANDLE;
    static inline VkPhysicalDevice _physicalDevice = VK_NULL_HANDLE;
    static inline bool _enabled = false;
    static inline VkQueryPool _queryPool = VK_NULL_HANDLE;
    static inline double _timeStampPeriod = 1.0;
    static inline bool _vkUpscaleTrig = false;
};
