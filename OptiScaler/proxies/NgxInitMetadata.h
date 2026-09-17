#pragma once

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <utility>

// Keep strings and related scalar fields from one publication together. Readers
// retain an immutable owner; no metadata lock is held during a native callback.
template <typename Version, typename Engine, typename Logging> class NgxInitMetadata
{
  public:
    struct Values
    {
        uint64_t ApplicationId = 1337;
        std::wstring ApplicationDataPath;
        std::string ProjectId;
        Version SdkVersion {};
        Engine EngineType {};
        std::string EngineVersion;
        Logging Logger {};
    };

    using Owner = std::shared_ptr<const Values>;

  private:
    std::mutex _mutex;
    Owner _snapshot;

    // Only internal value assignments run here, never caller/native code.
    template <typename Edit> Owner Update(Edit edit)
    {
        std::scoped_lock lock(_mutex);
        auto next = std::make_shared<Values>(*_snapshot);
        edit(*next);
        _snapshot = next;
        return next;
    }

  public:
    NgxInitMetadata(Engine engine, Logging logging)
    {
        auto initial = std::make_shared<Values>();
        initial->EngineType = engine;
        initial->Logger = logging;
        _snapshot = std::move(initial);
    }

    Owner Read()
    {
        std::scoped_lock lock(_mutex);
        return _snapshot;
    }

    Owner UpdateApplication(uint64_t applicationId, const wchar_t* dataPath, Version version)
    {
        // Copy borrowed buffers before publishing them to other readers.
        std::wstring ownedPath = dataPath == nullptr ? L"" : dataPath;
        return Update(
            [&](Values& next)
            {
                next.ApplicationId = applicationId;
                next.ApplicationDataPath = std::move(ownedPath);
                next.SdkVersion = version;
            });
    }

    Owner UpdateApplicationId(uint64_t applicationId)
    {
        return Update([&](Values& next) { next.ApplicationId = applicationId; });
    }

    Owner UpdateProject(std::string projectId, Engine engine, std::string engineVersion)
    {
        return Update(
            [&](Values& next)
            {
                next.ProjectId = std::move(projectId);
                next.EngineType = engine;
                next.EngineVersion = std::move(engineVersion);
            });
    }

    Owner UpdateLogging(Logging logging)
    {
        return Update([&](Values& next) { next.Logger = logging; });
    }
};
