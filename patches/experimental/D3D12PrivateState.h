#pragma once

// Experimental only. Include after the D3D12/COM definitions.
// The key must be unique to T and owned exclusively by this implementation.
// The caller must hold a live D3D12 object and serialize initialization/writes.
// Shared ownership protects the state allocation, not its mutable fields.
#include <atomic>
#include <memory>
#include <new>
#include <utility>

namespace AuroraCandidate
{
template <class T> class PrivateState final : public IUnknown
{
    std::atomic<ULONG> refs {1};
    GUID key;
    std::shared_ptr<T> state;

    PrivateState(REFGUID id, std::shared_ptr<T> value) : key(id), state(std::move(value)) {}
    ~PrivateState() = default;

  public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** out) override
    {
        if (!out)
            return E_POINTER;
        *out = nullptr;
        if (!IsEqualGUID(id, IID_IUnknown) && !IsEqualGUID(id, key))
            return E_NOINTERFACE;
        *out = static_cast<IUnknown*>(this);
        AddRef();
        return S_OK;
    }

    ULONG STDMETHODCALLTYPE AddRef() override { return refs.fetch_add(1, std::memory_order_relaxed) + 1; }
    ULONG STDMETHODCALLTYPE Release() override
    {
        const auto left = refs.fetch_sub(1, std::memory_order_acq_rel) - 1;
        if (!left)
            delete this;
        return left;
    }

    static bool Store(ID3D12Object* object, REFGUID id, std::shared_ptr<T> value)
    {
        if (!object || !value)
            return false;
        auto* holder = new (std::nothrow) PrivateState(id, std::move(value));
        if (!holder)
            return false;
        const auto result = object->SetPrivateDataInterface(id, holder);
        holder->Release(); // SetPrivateDataInterface owns its own reference on success.
        return SUCCEEDED(result);
    }

    static std::shared_ptr<T> Read(ID3D12Object* object, REFGUID id)
    {
        if (!object)
            return {};
        IUnknown* value = nullptr;
        UINT size = sizeof(value);
        if (FAILED(object->GetPrivateData(id, &size, &value)))
            return {};
        if (!value)
            return {};
        if (size != sizeof(value))
        {
            value->Release();
            return {};
        }
        // Only our private type exposes this per-state key as an interface ID.
        void* typed = nullptr;
        const auto result = value->QueryInterface(id, &typed);
        value->Release(); // Balance GetPrivateData's documented AddRef.
        if (FAILED(result) || !typed)
            return {};
        auto* base = static_cast<IUnknown*>(typed);
        auto copy = static_cast<PrivateState*>(base)->state;
        base->Release(); // Balance QueryInterface.
        return copy;
    }
};
} // namespace AuroraCandidate
