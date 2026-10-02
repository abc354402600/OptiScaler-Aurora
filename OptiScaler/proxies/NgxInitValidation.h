#pragma once

#include <cstddef>

// Validate the structure before any configuration writes or SDK entry.
// The caller still owns the lifetime and readability of non-null pointers.
template <typename FeatureInfo> bool ValidNgxInitPaths(const FeatureInfo* info)
{
    if (info == nullptr || info->PathListInfo.Length == 0)
        return true;
    if (info->PathListInfo.Path == nullptr)
        return false;
    for (std::size_t i = 0; i < info->PathListInfo.Length; ++i)
        if (info->PathListInfo.Path[i] == nullptr)
            return false;
    return true;
}
