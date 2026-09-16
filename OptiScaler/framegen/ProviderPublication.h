#pragma once

#include <atomic>
#include <memory>
#include <utility>

enum class ProviderStatus
{
    Unavailable,
    Pending,
    Available,
};

template <typename T> struct ProviderLookup
{
    T* provider = nullptr;
    ProviderStatus status = ProviderStatus::Unavailable;

    template <typename Supports> ProviderStatus ForApi(Supports&& supports) const
    {
        if (status != ProviderStatus::Available)
            return status;
        return supports(*provider) ? ProviderStatus::Available : ProviderStatus::Unavailable;
    }
};

// A published provider is never replaced. Its owner must outlive all callers.
// Constructors can load DLLs and re-enter Aurora: never wait for the constructor
// and never expose its candidate before validation/fallback has completed.
template <typename T> class ProviderPublication
{
    std::unique_ptr<T> _owner;
    std::atomic<T*> _published { nullptr };
    std::atomic_flag _building = ATOMIC_FLAG_INIT;

  public:
    T* Peek() const { return _published.load(std::memory_order_acquire); }

    template <typename Factory> ProviderLookup<T> GetOrCreate(Factory&& factory)
    {
        if (auto* provider = Peek())
            return { provider, ProviderStatus::Available };
        if (_building.test_and_set(std::memory_order_acquire))
            return { nullptr, ProviderStatus::Pending };

        struct Reset
        {
            std::atomic_flag& building;
            ~Reset() { building.clear(std::memory_order_release); }
        } reset { _building };

        // Another builder may have completed between Peek and acquisition.
        if (auto* provider = Peek())
            return { provider, ProviderStatus::Available };

        auto candidate = std::forward<Factory>(factory)();
        if (!candidate)
            return {}; // Permit a later retry after a configuration change/failure.

        _owner = std::move(candidate);
        auto* provider = _owner.get();
        _published.store(provider, std::memory_order_release);
        return { provider, ProviderStatus::Available };
    }
};
