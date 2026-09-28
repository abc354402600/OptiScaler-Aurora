#pragma once

#include <framegen/ProviderCallAdmission.h>
#include <utility>

// Shared by exported D3D11/D3D12/Vulkan Init and Shutdown. Internal delegation
// calls private cores explicitly; SDK callbacks must enter the public gate again.
// Direct native Init holds a read lease across configuration capture and SDK entry.
// UpdateFeature is a writer too. Ordinary Evaluate and device/resource ownership
// still require their separate admission checks.
class NgxExportLifecycle
{
    static inline ProviderCallAdmission _transitions;

  public:
    static auto TryRead() { return _transitions.TryOperation(); }
    static auto TryWrite() { return _transitions.TryTransition(); }

    template <typename Result, typename Callback> static Result Run(Result busy, Callback&& callback)
    {
        auto lease = _transitions.TryTransition();
        if (!lease)
            return busy;
        return std::forward<Callback>(callback)();
    }
};
