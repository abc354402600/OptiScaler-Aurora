#pragma once

#include <utility>

// Keep the caller's output empty until native creation and validation both
// succeed. Error returns must not publish wrappers around absent native handles.
template <typename PublicHandle, typename Registry, typename Value, typename Result, typename Create>
Result CreateProviderHandle(Registry& registry, PublicHandle** output, Value initial, Result success,
                            Result invalidParameter, Result malformedSuccess, Create&& create)
{
    if (!output)
        return invalidParameter;
    *output = nullptr;
    auto pending = registry.Prepare(std::move(initial));
    const auto result = std::forward<Create>(create)(pending->value);
    if (result != success)
        return result;
    if (!pending->value.nativeHandle)
        return malformedSuccess;
    *output = reinterpret_cast<PublicHandle*>(registry.Publish(pending));
    return result;
}
