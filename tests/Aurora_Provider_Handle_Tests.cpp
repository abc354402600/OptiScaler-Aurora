#include "../OptiScaler/framegen/ProviderHandleRegistry.h"
#include <atomic>
#include <chrono>
#include <future>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

struct Handle
{
    unsigned id;
    std::shared_ptr<int> lifetime;
};
int main()
{
    int passed = 0;
    auto check = [&](bool ok, const char* text)
    {
        if (!ok)
            throw std::runtime_error(text);
        ++passed;
    };
    ProviderHandleRegistry<Handle> registry;
    auto pending = registry.Prepare({ 42, std::make_shared<int>(7) });
    std::weak_ptr<int> lifetime = pending->value.lifetime;
    auto* handle = registry.Publish(pending);
    pending.reset();
    check(registry.Read(handle, -1, [](auto& h) { return static_cast<int>(h.id); }) == 42, "published lookup");
    check(registry.Read(reinterpret_cast<void*>(1), -1, [](auto&) { return 0; }) == -1,
          "unknown pointer is not dereferenced");
    check(registry.Read(nullptr, -1, [](auto&) { return 0; }) == -1, "null lookup");
    check(registry.Release(
              handle, -1, [](auto&) { return -2; }, [](int r) { return r == 0; }) == -2,
          "failed native release propagated");
    check(!lifetime.expired(), "failed release retains object");
    check(registry.Read(handle, -1, [](auto&) { return 1; }) == 1, "failed release remains usable");

    std::promise<void> entered, resume;
    auto resumeFuture = resume.get_future();
    auto reader = std::async(std::launch::async,
                             [&]
                             {
                                 return registry.Read(handle, -1,
                                                      [&](auto& h)
                                                      {
                                                          entered.set_value();
                                                          resumeFuture.wait();
                                                          return *h.lifetime;
                                                      });
                             });
    entered.get_future().wait();
    std::atomic<int> nativeReleases = 0;
    auto releaser = std::async(std::launch::async,
                               [&]
                               {
                                   return registry.Release(
                                       handle, -1, -3,
                                       [&](auto&)
                                       {
                                           ++nativeReleases;
                                           return 0;
                                       },
                                       [](int r) { return r == 0; });
                               });
    const bool releaseReturned = releaser.wait_for(std::chrono::seconds(2)) == std::future_status::ready;
    const bool retained = !lifetime.expired() && nativeReleases == 0;
    resume.set_value();
    check(releaseReturned && retained, "busy release returns without waiting or touching native handle");
    check(reader.get() == 7 && releaser.get() == -3, "evaluate completes and busy release can be retried");
    check(registry.Release(
              handle, -1, -3,
              [&](const auto&)
              {
                  ++nativeReleases;
                  return 0;
              },
              [](int r) { return r == 0; }) == 0,
          "explicit release retry succeeds after evaluate");
    check(!lifetime.expired() && nativeReleases == 1, "retired public token remains owned after native release");
    check(registry.GetIdentity(handle, [](const auto& h) { return h.id; }) == 42,
          "router can identify a retired handle without reading its address");
    check(!registry.GetIdentity(reinterpret_cast<void*>(1), [](const auto& h) { return h.id; }).has_value(),
          "foreign identity is not dereferenced");
    check(registry.Read(handle, -1, [](auto&) { return 0; }) == -1, "retired handle rejected without dereference");
    check(registry.Release(
              handle, -1, [](auto&) { return 0; }, [](int r) { return r == 0; }) == -1,
          "repeat release rejected");

    auto abandoned = registry.Prepare({ 43, std::make_shared<int>(8) });
    std::weak_ptr<int> failedCreateLifetime = abandoned->value.lifetime;
    auto* unpublished = &abandoned->value;
    check(registry.Read(unpublished, -1, [](auto&) { return 0; }) == -1, "failed Create never publishes a handle");
    abandoned.reset();
    check(failedCreateLifetime.expired(), "failed Create wrapper is reclaimed");

    auto next = registry.Prepare({ 44, std::make_shared<int>(9) });
    auto* nextHandle = registry.Publish(next);
    check(nextHandle != handle, "new handle cannot reuse a retired public token address");
    next.reset();
    std::vector<std::future<int>> releases;
    nativeReleases = 0;
    for (int i = 0; i < 16; ++i)
        releases.push_back(std::async(std::launch::async,
                                      [&]
                                      {
                                          return registry.Release(
                                              nextHandle, -1,
                                              [&](auto&)
                                              {
                                                  ++nativeReleases;
                                                  return 0;
                                              },
                                              [](int r) { return r == 0; });
                                      }));
    int successes = 0;
    for (auto& result : releases)
        successes += result.get() == 0;
    check(successes == 1 && nativeReleases == 1, "concurrent releases invoke provider exactly once");

    auto third = registry.Prepare({ 45, std::make_shared<int>(10) });
    auto* thirdHandle = registry.Publish(third);
    third.reset();
    const auto isSuccess = [](int result) { return result == 0; };
    check(registry.Read(thirdHandle, -1, -3,
                        [&](const auto&)
                        {
                            check(registry.GetIdentity(thirdHandle, [](const auto& h) { return h.id; }) == 45,
                                  "identity lookup can reenter Evaluate");
                            check(registry.Release(
                                      thirdHandle, -1, -3, [](const auto&) { return 0; }, isSuccess) == -3,
                                  "Evaluate callback release fails busy without deadlock");
                            return 4;
                        }) == 4,
          "Evaluate survives callback reentry");

    check(registry.Release(
              thirdHandle, -1, -3,
              [&](const auto&)
              {
                  check(registry.GetIdentity(thirdHandle, [](const auto& h) { return h.id; }) == 45,
                        "identity lookup remains routable during Release");
                  check(registry.Read(thirdHandle, -1, -3, [](const auto&) { return 0; }) == -3,
                        "Evaluate callback during Release fails busy");
                  check(registry.Release(
                            thirdHandle, -1, -3, [](const auto&) { return 0; }, isSuccess) == -3,
                        "nested Release fails busy");
                  auto worker =
                      std::async(std::launch::async,
                                 [&] { return registry.Read(thirdHandle, -1, -3, [](const auto&) { return 0; }); });
                  check(worker.wait_for(std::chrono::seconds(2)) == std::future_status::ready && worker.get() == -3,
                        "callback may join another thread without a registry lock cycle");
                  return -2;
              },
              isSuccess) == -2,
          "failed reentrant Release keeps ownership");
    check(registry.Read(thirdHandle, -1, -3, [](const auto&) { return 9; }) == 9,
          "failed reentrant Release permits Evaluate again");

    bool threw = false;
    try
    {
        registry.Read(thirdHandle, -1, -3, [](const auto&) -> int { throw std::runtime_error("evaluate"); });
    }
    catch (const std::runtime_error&)
    {
        threw = true;
    }
    check(threw, "Evaluate exception propagated");
    threw = false;
    try
    {
        registry.Release(
            thirdHandle, -1, -3, [](const auto&) -> int { throw std::runtime_error("release"); }, isSuccess);
    }
    catch (const std::runtime_error&)
    {
        threw = true;
    }
    check(threw, "Release exception propagated and read admission was unwound");
    check(registry.Read(thirdHandle, -1, -3, [](const auto&) { return 5; }) == 5,
          "Release exception restores read admission");
    check(registry.Release(
              thirdHandle, -1, -3, [](const auto&) { return 0; }, isSuccess) == 0,
          "Release after exceptions succeeds");
    check(registry.Read(thirdHandle, -1, -3, [](const auto&) { return 0; }) == -1,
          "retired handle is missing rather than busy");
    std::cout << "PASS: " << passed << " provider handle lifetime checks\n";
}
