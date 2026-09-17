#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

// The pointer array and its strings share one immutable owner. Native Init
// callers retain that owner until the call (including delegated Init) returns.
class NgxPathSnapshot
{
    std::vector<std::wstring> _strings;
    std::vector<const wchar_t*> _pointers;

  public:
    using Owner = std::shared_ptr<const NgxPathSnapshot>;

    explicit NgxPathSnapshot(std::vector<std::wstring> paths) : _strings(std::move(paths))
    {
        _pointers.reserve(_strings.size());
        for (const auto& path : _strings)
            _pointers.push_back(path.c_str());
    }

    NgxPathSnapshot(const NgxPathSnapshot&) = delete;
    NgxPathSnapshot& operator=(const NgxPathSnapshot&) = delete;
    const std::vector<std::wstring>& Strings() const { return _strings; }

    template <typename PathList> void Bind(PathList& list) const
    {
        list.Path = _pointers.empty() ? nullptr : _pointers.data();
        list.Length = static_cast<unsigned int>(_pointers.size());
    }
};

class NgxPathCache
{
    std::mutex _mutex;
    NgxPathSnapshot::Owner _snapshot;

  public:
    NgxPathSnapshot::Owner Read()
    {
        std::scoped_lock lock(_mutex);
        return _snapshot;
    }

    [[nodiscard]] NgxPathSnapshot::Owner Publish(std::vector<std::wstring> paths)
    {
        auto snapshot = std::make_shared<const NgxPathSnapshot>(std::move(paths));
        {
            std::scoped_lock lock(_mutex);
            _snapshot = snapshot;
        }
        return snapshot;
    }
};
