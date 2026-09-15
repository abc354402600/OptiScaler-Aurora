#pragma once

#include <mutex>
#include <utility>

namespace OptiInput
{
// Discovery can wait for a DLL whose initialization calls an input detour.
// Do not hold the detour's state mutex until discovery has finished.
template <typename Mutex, typename Prepare, typename Apply>
decltype(auto) PrepareBeforeLock(Mutex& mutex, Prepare&& prepare, Apply&& apply)
{
    auto prepared = std::forward<Prepare>(prepare)();
    std::unique_lock lock(mutex);
    return std::forward<Apply>(apply)(prepared);
}
} // namespace OptiInput
