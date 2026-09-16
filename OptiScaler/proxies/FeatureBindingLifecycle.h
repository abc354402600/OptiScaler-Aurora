#pragma once

#include <atomic>

// Called on the serialized device-initialization path, as required by slSetD3DDevice.
// Runtime initialization alone does not make plugin functions safe to call.
class FeatureBindingLifecycle
{
  public:
    bool RuntimeInitialized() const { return _initialized; }
    bool Ready() const { return _ready; }

    void MarkInitialized(bool deferDevice)
    {
        _deferred = deferDevice;
        _initialized = true;
    }

    bool CanAutoBind(void* device) const { return _initialized && device && (!_deferred || device == _selectedDevice); }

    template <typename SetDevice, typename Prepare, typename Publish>
    bool Bind(void* device, SetDevice&& setDevice, Prepare&& prepare, Publish&& publish)
    {
        if (!_initialized || !device)
            return false;
        if (_ready && device == _selectedDevice)
            return true;

        _ready = false;
        if (device != _selectedDevice)
        {
            _selectedDevice = device;
            _deviceBound = false;
        }
        if (!_deviceBound)
        {
            if (!setDevice(device))
                return false;
            _deviceBound = true;
        }

        // Prepare resolves and configures a complete local function table. A
        // missing required function must never publish half of that table.
        auto candidate = prepare();
        if (!candidate)
            return false;
        publish(*candidate);
        _ready = true;
        return true;
    }

  private:
    std::atomic_bool _initialized = false;
    bool _deferred = false;
    bool _deviceBound = false;
    std::atomic_bool _ready = false;
    void* _selectedDevice = nullptr;
};
