#pragma once

#include <framegen/ProviderCallAdmission.h>
#include <utility>

// Shared by exported D3D11/D3D12/Vulkan Init and Shutdown. Internal delegation
// calls private cores explicitly; SDK callbacks must enter the public gate again.
// This gate protects exported transitions, not ordinary Evaluate or direct native
// proxy calls. It does not replace their separate ownership/admission checks.
class NgxExportLifecycle
{
    static inline ProviderCallAdmission _transitions;

  public:
    template <typename Result, typename Callback> static Result Run(Result busy, Callback&& callback)
    {
        auto lease = _transitions.TryTransition();
        if (!lease)
            return busy;
        return std::forward<Callback>(callback)();
    }
};
