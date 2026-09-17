#pragma once

#include <atomic>
#include <mutex>
#include <unordered_map>
#include <utility>

// Tracks native Init/Shutdown ownership per API. Callbacks run without the
// metadata lock. Overlapping/reentrant transitions fail rather than waiting on
// a native DLL or loader callback. Operation admission covers the API as a whole
// because legacy native handles do not all expose a reliable device association.
class NativeDeviceLifecycle
{
    std::mutex _mutex;
    std::unordered_map<const void*, bool> _devices;
    bool _transition = false;
    size_t _operations = 0;
    const void* _target = nullptr;
    std::atomic_size_t _usable { 0 };

    void UpdateUsable()
    {
        size_t count = 0;
        for (const auto& [device, ready] : _devices)
            if (ready && (!_transition || (_target && device != _target)))
                ++count;
        _usable.store(count, std::memory_order_release);
    }

    void Finish(const void* device, bool initializing, bool succeeded)
    {
        std::scoped_lock lock(_mutex);
        if (initializing)
        {
            if (succeeded)
                _devices.at(device) = true;
            else
                _devices.erase(device);
        }
        else if (succeeded)
        {
            if (device)
                _devices.erase(device);
            else
                _devices.clear();
        }
        _transition = false;
        _target = nullptr;
        UpdateUsable();
    }

  public:
    bool AnyReady() const { return _usable.load(std::memory_order_acquire) != 0; }

    bool IsReady(const void* device)
    {
        std::scoped_lock lock(_mutex);
        const auto entry = _devices.find(device);
        return entry != _devices.end() && entry->second && (!_transition || (_target && device != _target));
    }

    template <typename Result, typename Callback>
    Result RunOperation(Result unavailable, Callback&& callback, const void* device = nullptr)
    {
        {
            std::scoped_lock lock(_mutex);
            if (_transition || _devices.empty() || (device && !_devices.contains(device)))
                return unavailable;
            ++_operations;
        }
        // Native code runs without the metadata mutex, including callbacks.
        struct Completion
        {
            NativeDeviceLifecycle& owner;
            ~Completion()
            {
                std::scoped_lock lock(owner._mutex);
                --owner._operations;
            }
        } completion { *this };
        return std::forward<Callback>(callback)();
    }

    template <typename Result, typename Callback>
    Result Initialize(const void* device, Result success, Result invalid, Result busy, Callback&& callback)
    {
        if (!device)
            return invalid;
        {
            std::scoped_lock lock(_mutex);
            if (_transition)
                return busy;
            if (_devices.contains(device))
                return success;
            if (_operations)
                return busy;
            // Allocate bookkeeping before the native callback succeeds.
            _devices.emplace(device, false);
            _transition = true;
            _target = device;
            UpdateUsable();
        }
        try
        {
            const auto result = callback();
            Finish(device, true, result == success);
            return result;
        }
        catch (...)
        {
            Finish(device, true, false);
            throw;
        }
    }

    template <typename Result, typename Callback>
    Result Shutdown(const void* device, Result success, Result busy, Callback&& callback)
    {
        {
            std::scoped_lock lock(_mutex);
            if (_transition)
                return busy;
            if (device ? !_devices.contains(device) : _devices.empty())
                return success; // Nothing owned; do not call a native shutdown.
            if (_operations)
                return busy; // No waiting or deferred native teardown.
            _transition = true;
            _target = device; // nullptr means all devices in this API.
            UpdateUsable();
        }
        try
        {
            const auto result = callback();
            Finish(device, false, result == success);
            return result;
        }
        catch (...)
        {
            Finish(device, false, false);
            throw;
        }
    }
};
