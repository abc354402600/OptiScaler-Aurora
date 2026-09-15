#include "../OptiScaler/menu/input/PrepareBeforeLock.h"
#include <atomic>
#include <chrono>
#include <future>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>

int main()
{
    std::timed_mutex state;
    int checks = 0;
    auto check = [&](bool ok)
    {
        if (!ok)
            throw std::runtime_error("input lock regression");
        ++checks;
    };
    auto otherThreadCanEnter = [&]
    {
        return std::async(std::launch::async,
                          [&]
                          {
                              if (!state.try_lock_for(std::chrono::milliseconds(100)))
                                  return false;
                              state.unlock();
                              return true;
                          })
            .get();
    };

    // Simulate GetProcAddress waiting for a DllMain which calls an input hook.
    bool loaderCallbackEntered = false, applyWasLocked = false;
    int result = OptiInput::PrepareBeforeLock(
        state,
        [&]
        {
            loaderCallbackEntered = otherThreadCanEnter();
            return 42;
        },
        [&](int value)
        {
            applyWasLocked = !otherThreadCanEnter();
            return value + 1;
        });
    check(loaderCallbackEntered);
    check(applyWasLocked);
    check(result == 43);
    check(otherThreadCanEnter());

    bool published = false;
    try
    {
        OptiInput::PrepareBeforeLock(
            state, []() -> int { throw std::runtime_error("resolve"); }, [&](int) { published = true; });
    }
    catch (const std::runtime_error&)
    {
    }
    check(!published && otherThreadCanEnter());
    try
    {
        OptiInput::PrepareBeforeLock(state, [] { return 0; }, [](int) { throw std::runtime_error("apply"); });
    }
    catch (const std::runtime_error&)
    {
    }
    check(otherThreadCanEnter());

    // Releasing the prepared module reference can itself run DllMain.
    bool releasedOutsideLock = false;
    OptiInput::PrepareBeforeLock(
        state,
        [&]
        {
            return std::shared_ptr<int>(new int(1),
                                        [&](int* p)
                                        {
                                            releasedOutsideLock = otherThreadCanEnter();
                                            delete p;
                                        });
        },
        [](const auto&) {});
    check(releasedOutsideLock);

    std::atomic<int> active = 0, overlap = 0;
    int total = 0;
    std::vector<std::future<void>> workers;
    for (int i = 0; i < 16; ++i)
        workers.push_back(std::async(std::launch::async,
                                     [&]
                                     {
                                         OptiInput::PrepareBeforeLock(
                                             state, [] { return 1; },
                                             [&](int n)
                                             {
                                                 if (active.fetch_add(1) != 0)
                                                     ++overlap;
                                                 total += n;
                                                 --active;
                                             });
                                     }));
    for (auto& worker : workers)
        worker.get();
    check(total == 16 && overlap == 0);
    std::cout << "PASS: " << checks << " input lock ordering checks\n";
}
