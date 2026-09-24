#pragma once

#include <cstddef>
#include <mutex>
#include <utility>

// One provider is shared by D3D12 and Vulkan. Transitions exclude all admitted
// operations, but no metadata lock is held while running provider/native code.
class ProviderCallAdmission
{
    std::mutex _mutex;
    std::size_t _operations = 0;
    bool _transition = false;

  public:
    class Lease
    {
        friend class ProviderCallAdmission;
        ProviderCallAdmission* _owner = nullptr;
        bool _transition = false;
        Lease(ProviderCallAdmission* owner, bool transition) : _owner(owner), _transition(transition) {}

      public:
        Lease() = default;
        Lease(const Lease&) = delete;
        Lease& operator=(const Lease&) = delete;
        Lease(Lease&& other) noexcept : _owner(std::exchange(other._owner, nullptr)), _transition(other._transition) {}
        explicit operator bool() const { return _owner != nullptr; }
        ~Lease()
        {
            if (!_owner)
                return;
            std::scoped_lock lock(_owner->_mutex);
            if (_transition)
                _owner->_transition = false;
            else
                --_owner->_operations;
        }
    };

    Lease TryOperation()
    {
        std::scoped_lock lock(_mutex);
        if (_transition)
            return {};
        ++_operations;
        return { this, false };
    }

    Lease TryTransition()
    {
        std::scoped_lock lock(_mutex);
        if (_transition || _operations != 0)
            return {};
        _transition = true;
        return { this, true };
    }
};
