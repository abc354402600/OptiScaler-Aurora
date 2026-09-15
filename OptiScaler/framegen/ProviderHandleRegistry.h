#pragma once

#include <memory>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>
#include <utility>

// Lookup retains ownership before taking the per-handle lock. A Release can
// retire the public pointer while queued callers still safely own the entry.
template <typename Value> class ProviderHandleRegistry
{
  public:
    struct Entry
    {
        Value value;
        std::shared_mutex mutex;
        bool retired = false;
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

    template <typename Result, typename Function> Result Read(const void* key, Result missing, Function&& function)
    {
        auto entry = Find(key);
        if (!entry)
            return missing;
        std::shared_lock lock(entry->mutex);
        return entry->retired ? missing : function(entry->value);
    }

    template <typename Result, typename Function, typename Success>
    Result Release(const void* key, Result missing, Function&& function, Success&& success)
    {
        auto entry = Find(key);
        if (!entry)
            return missing;
        std::scoped_lock lock(entry->mutex);
        if (entry->retired)
            return missing;
        auto result = function(entry->value);
        if (success(result))
        {
            entry->retired = true;
            std::scoped_lock registryLock(_mutex);
            _entries.erase(key);
        }
        // The entry's mutex is unlocked before this local shared_ptr is released.
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
