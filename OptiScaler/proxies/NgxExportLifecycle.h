#pragma once

#include <framegen/ProviderCallAdmission.h>
#include <utility>

// Shared by exported D3D11/D3D12/Vulkan Init and Shutdown. Internal delegation
// calls private cores explicitly; SDK callbacks must enter the public gate again.
// Direct native Init holds a read lease across configuration capture and SDK entry.
// UpdateFeature is a writer too. Native operation wrappers also hold readers;
// device/resource ownership still requires its separate admission checks.
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

    // Roll back global configuration only. SDK attempt/cleanup ownership is separate.
    // Delegated private Init calls remain inside this single outer transaction.
    template <typename Result, typename Metadata, typename Paths, typename Callback>
    static Result RunInitialization(Result busy, Result success, Metadata& metadata, Paths& paths, Callback&& callback)
    {
        return Run(busy,
                   [&]
                   {
                       auto oldMetadata = metadata.Read();
                       auto oldPaths = paths.Read();
                       struct Rollback
                       {
                           Metadata& metadata;
                           Paths& paths;
                           decltype(oldMetadata) previousMetadata;
                           decltype(oldPaths) previousPaths;
                           bool committed = false;
                           ~Rollback()
                           {
                               if (!committed)
                               {
                                   metadata.Restore(std::move(previousMetadata));
                                   paths.Restore(std::move(previousPaths));
                               }
                           }
                       } rollback { metadata, paths, std::move(oldMetadata), std::move(oldPaths) };
                       auto result = std::forward<Callback>(callback)();
                       rollback.committed = result == success;
                       return result;
                   });
    }
};
