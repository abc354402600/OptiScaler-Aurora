#pragma once

#include <memory>
#include <mutex>
#include <optional>
#include <unordered_map>
#include <utility>
#include <vector>

// Lookup retains the token. Admission is checked under a short per-handle lock;
// provider callbacks never run under that lock and busy releases never wait.
template <typename Value> class ProviderHandleRegistry
{
  public:
    struct Entry
    {
        Value value;
        std::mutex mutex;
        size_t readers = 0;
        bool releasing = false;
        bool retired = false;
        bool readsSuspended = false;
        explicit Entry(Value v) : value(std::move(v)) {}
    };
    using Pending = std::shared_ptr<Entry>;

    static Pending Prepare(Value value) { return std::make_shared<Entry>(std::move(value)); }

    Value* Publish(const Pending& entry)
    {
        std::scoped_lock lock(_mutex);
        auto* key = &entry->value;
        _entries.emplace(key, entry);
        return key;
    }

    // Only immutable identity fields may be inspected by the predicate. The
    // caller must exclude new publication/operations for a lifecycle snapshot.
    template <typename Predicate> std::vector<const void*> LiveKeys(Predicate&& predicate)
    {
        std::vector<const void*> keys;
        std::scoped_lock lock(_mutex);
        for (const auto& [key, entry] : _entries)
        {
            std::scoped_lock entryLock(entry->mutex);
            if (!entry->retired && predicate(static_cast<const Value&>(entry->value)))
                keys.push_back(key);
        }
        return keys;
    }

    // Caller holds lifecycle admission. A partial drain must not resume Evaluate
    // on resources whose teardown has begun; explicit Release retry is allowed.
    void SuspendReads(const void* key)
    {
        if (auto entry = Find(key))
        {
            std::scoped_lock lock(entry->mutex);
            entry->readsSuspended = true;
        }
    }

    // Identity remains available after retirement. Retained tokens prevent their
    // addresses being recycled into unrelated handles while the DLL is loaded.
    template <typename Identity>
    auto GetIdentity(const void* key, Identity&& identity)
        -> std::optional<decltype(identity(std::declval<const Value&>()))>
    {
        auto entry = Find(key);
        if (!entry)
            return std::nullopt;
        // Published wrapper fields are immutable; native resources they point
        // to are only accessed through Read/Release admission below.
        return identity(static_cast<const Value&>(entry->value));
    }

    template <typename Result, typename Function> Result Read(const void* key, Result missing, Function&& function)
    {
        return Read(key, missing, missing, std::forward<Function>(function));
    }

    template <typename Result, typename Function>
    Result Read(const void* key, Result missing, Result busy, Function&& function)
    {
        auto entry = Find(key);
        if (!entry)
            return missing;
        {
            std::scoped_lock lock(entry->mutex);
            if (entry->retired)
                return missing;
            if (entry->releasing || entry->readsSuspended)
                return busy;
            ++entry->readers;
        }
        struct ReadScope
        {
            Entry& entry;
            ~ReadScope()
            {
                std::scoped_lock lock(entry.mutex);
                --entry.readers;
            }
        } scope { *entry };
        return function(static_cast<const Value&>(entry->value));
    }

    template <typename Result, typename Function, typename Success>
    Result Release(const void* key, Result missing, Function&& function, Success&& success)
    {
        return Release(key, missing, missing, std::forward<Function>(function), std::forward<Success>(success));
    }

    template <typename Result, typename Function, typename Success>
    Result Release(const void* key, Result missing, Result busy, Function&& function, Success&& success)
    {
        auto entry = Find(key);
        if (!entry)
            return missing;
        {
            std::scoped_lock lock(entry->mutex);
            if (entry->retired)
                return missing;
            if (entry->releasing || entry->readers != 0)
                return busy;
            entry->releasing = true;
        }
        struct ReleaseScope
        {
            Entry& entry;
            bool succeeded = false;
            ~ReleaseScope()
            {
                std::scoped_lock lock(entry.mutex);
                entry.retired = succeeded;
                entry.releasing = false;
            }
        } scope { *entry };
        auto result = function(static_cast<const Value&>(entry->value));
        scope.succeeded = success(result);
        // Retain public tokens until registry destruction to avoid address reuse.
        // Failed/busy releases retain native ownership for an explicit retry.
        return result;
    }

  private:
    Pending Find(const void* key)
    {
        std::scoped_lock lock(_mutex);
        const auto it = _entries.find(key);
        return it == _entries.end() ? nullptr : it->second;
    }
    std::mutex _mutex;
    std::unordered_map<const void*, Pending> _entries;
};
