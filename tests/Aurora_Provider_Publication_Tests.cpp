#include "../OptiScaler/framegen/ProviderPublication.h"
#include <chrono>
#include <cstdlib>
#include <future>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

struct Provider
{
    int value = 0;
    bool validated = false;
};

int main()
{
    using namespace std::chrono_literals;
    int checks = 0;
    auto check = [&](bool ok)
    {
        if (!ok)
        {
            std::cerr << "publication regression at check " << checks + 1 << '\n';
            std::exit(2);
        }
        ++checks;
    };
    ProviderPublication<Provider> slot;
    check(slot.Peek() == nullptr);
    int unexpectedFactories = 0;
    auto unexpected = [&]() -> std::unique_ptr<Provider>
    {
        ++unexpectedFactories;
        return nullptr;
    };

    // Hold a partially constructed candidate on another thread. No sleeps are
    // used to guess when construction is in flight.
    std::promise<void> entered, release;
    auto releaseFuture = release.get_future();
    auto builder = std::async(std::launch::async,
                              [&]
                              {
                                  return slot.GetOrCreate(
                                      [&]
                                      {
                                          auto candidate = std::make_unique<Provider>();
                                          candidate->value = 42;
                                          entered.set_value();
                                          releaseFuture.wait();
                                          candidate->validated = true;
                                          return candidate;
                                      });
                              });
    check(entered.get_future().wait_for(5s) == std::future_status::ready);
    check(slot.Peek() == nullptr);
    auto contender = std::async(std::launch::async, [&] { return slot.GetOrCreate(unexpected); });
    check(contender.wait_for(5s) == std::future_status::ready); // Must not wait for the DLL constructor.
    const auto pending = contender.get();
    check(pending.status == ProviderStatus::Pending && pending.provider == nullptr);
    bool apiChecked = false;
    check(pending.ForApi(
              [&](auto&)
              {
                  apiChecked = true;
                  return true;
              }) == ProviderStatus::Pending);
    check(!apiChecked && unexpectedFactories == 0);
    release.set_value();
    check(builder.wait_for(5s) == std::future_status::ready);
    const auto published = builder.get();
    check(published.status == ProviderStatus::Available && published.provider == slot.Peek());
    check(published.provider->validated && published.provider->value == 42);
    check(published.ForApi([](auto&) { return true; }) == ProviderStatus::Available);
    check(published.ForApi([](auto&) { return false; }) == ProviderStatus::Unavailable);
    check(slot.GetOrCreate(unexpected).provider == published.provider && unexpectedFactories == 0);

    // Reentrant loader callbacks see Pending, not a deadlock or a second factory.
    ProviderPublication<Provider> reentrant;
    auto recursive = reentrant.GetOrCreate(
        [&]
        {
            auto inner = reentrant.GetOrCreate(unexpected);
            check(inner.status == ProviderStatus::Pending && !inner.provider);
            check(reentrant.Peek() == nullptr);
            return std::make_unique<Provider>(Provider { 7, true });
        });
    check(recursive.provider && recursive.provider->value == 7 && unexpectedFactories == 0);

    // Failure and exceptions do not permanently latch the construction gate.
    ProviderPublication<Provider> retry;
    check(retry.GetOrCreate([] { return std::unique_ptr<Provider>(); }).status == ProviderStatus::Unavailable);
    check(retry.Peek() == nullptr);
    bool threw = false;
    try
    {
        retry.GetOrCreate([]() -> std::unique_ptr<Provider> { throw std::runtime_error("injected"); });
    }
    catch (const std::runtime_error&)
    {
        threw = true;
    }
    check(threw && retry.Peek() == nullptr);
    check(retry.GetOrCreate([] { return std::make_unique<Provider>(Provider { 9, true }); }).provider->value == 9);

    // Contending initial calls may return Pending; every successful observation
    // must share one fully validated object. Subsequent reads never rebuild it.
    ProviderPublication<Provider> contested;
    std::atomic<int> factories { 0 }, badReads { 0 };
    std::promise<void> start;
    auto startFuture = start.get_future().share();
    std::vector<std::thread> threads;
    for (int i = 0; i < 12; ++i)
        threads.emplace_back(
            [&]
            {
                startFuture.wait();
                for (int j = 0; j < 1000; ++j)
                {
                    auto lookup = contested.GetOrCreate(
                        [&]
                        {
                            ++factories;
                            return std::make_unique<Provider>(Provider { 99, true });
                        });
                    if (lookup.status == ProviderStatus::Pending)
                        continue;
                    if (!lookup.provider || lookup.provider != contested.Peek() || !lookup.provider->validated ||
                        lookup.provider->value != 99)
                        ++badReads;
                }
            });
    start.set_value();
    for (auto& thread : threads)
        thread.join();
    check(factories == 1 && badReads == 0);
    check(contested.GetOrCreate(unexpected).provider == contested.Peek() && unexpectedFactories == 0);
    std::cout << "PASS: " << checks << " provider publication checks\n";
}
