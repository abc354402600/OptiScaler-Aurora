#include "../OptiScaler/proxies/NativeDeviceLifecycle.h"
#include <chrono>
#include <cstdlib>
#include <future>
#include <iostream>
#include <stdexcept>

int main()
{
    using namespace std::chrono_literals;
    int checks = 0, first = 1, second = 2, absent = 3, calls = 0;
    auto check = [&](bool ok)
    {
        if (!ok)
        {
            std::cerr << "native device regression at " << checks + 1 << '\n';
            std::exit(2);
        }
        ++checks;
    };
    NativeDeviceLifecycle dx, vk;
    auto success = [&]
    {
        ++calls;
        return 0;
    };
    auto initialize = [&](auto& api, void* device) { return api.Initialize(device, 0, -2, -7, success); };
    check(!dx.AnyReady());
    check(initialize(dx, nullptr) == -2 && calls == 0);
    check(dx.Shutdown(nullptr, 0, -7, success) == 0 && calls == 0);
    check(initialize(dx, &first) == 0 && calls == 1 && dx.IsReady(&first));
    check(initialize(dx, &first) == 0 && calls == 1);
    check(initialize(dx, &second) == 0 && calls == 2 && dx.IsReady(&second));
    check(initialize(vk, &first) == 0 && calls == 3);
    check(dx.Shutdown(&absent, 0, -7, success) == 0 && calls == 3);
    check(dx.Shutdown(&first, 0, -7, [] { return -4; }) == -4);
    check(dx.IsReady(&first) && dx.IsReady(&second) && vk.IsReady(&first));
    check(dx.Shutdown(&first, 0, -7, success) == 0 && calls == 4);
    check(!dx.IsReady(&first) && dx.IsReady(&second) && dx.AnyReady() && vk.IsReady(&first));
    check(dx.Shutdown(&first, 0, -7, success) == 0 && calls == 4);
    check(initialize(dx, &first) == 0 && calls == 5);
    check(dx.Shutdown(nullptr, 0, -7, [] { return -4; }) == -4 && dx.IsReady(&first) && dx.IsReady(&second));
    check(dx.Shutdown(nullptr, 0, -7, success) == 0 && calls == 6 && !dx.AnyReady());
    check(!dx.IsReady(&first) && !dx.IsReady(&second) && vk.IsReady(&first));
    check(dx.Initialize(&first, 0, -2, -7, [] { return -4; }) == -4 && !dx.AnyReady());
    bool threw = false;
    try
    {
        dx.Initialize(&first, 0, -2, -7, []() -> int { throw std::runtime_error("init"); });
    }
    catch (const std::runtime_error&)
    {
        threw = true;
    }
    check(threw && !dx.AnyReady());
    check(initialize(dx, &first) == 0);
    threw = false;
    try
    {
        dx.Shutdown(&first, 0, -7, []() -> int { throw std::runtime_error("shutdown"); });
    }
    catch (const std::runtime_error&)
    {
        threw = true;
    }
    check(threw && dx.IsReady(&first));

    // Same-thread native callbacks cannot wait on their own transition.
    check(dx.Shutdown(&first, 0, -7,
                      [&]
                      {
                          check(!dx.IsReady(&first) && !dx.AnyReady());
                          check(initialize(dx, &first) == -7);
                          check(dx.Shutdown(nullptr, 0, -7, success) == -7);
                          check(vk.IsReady(&first));
                          return -4;
                      }) == -4);
    check(dx.IsReady(&first));

    // Another thread can query unaffected devices while one shutdown is inside
    // foreign code. Conflicting transitions return promptly, not after a wait.
    check(initialize(dx, &second) == 0);
    std::promise<void> entered, release;
    auto released = release.get_future();
    auto closer = std::async(std::launch::async,
                             [&]
                             {
                                 return dx.Shutdown(&first, 0, -7,
                                                    [&]
                                                    {
                                                        entered.set_value();
                                                        released.wait();
                                                        return 0;
                                                    });
                             });
    check(entered.get_future().wait_for(5s) == std::future_status::ready);
    auto contender = std::async(std::launch::async,
                                [&]
                                {
                                    return !dx.IsReady(&first) && dx.IsReady(&second) && dx.AnyReady() &&
                                           dx.Shutdown(nullptr, 0, -7, success) == -7 && initialize(dx, &absent) == -7;
                                });
    check(contender.wait_for(5s) == std::future_status::ready && contender.get());
    release.set_value();
    check(closer.wait_for(5s) == std::future_status::ready && closer.get() == 0);
    check(!dx.IsReady(&first) && dx.IsReady(&second));

    check(dx.Initialize(&first, 0, -2, -7,
                        [&]
                        {
                            check(!dx.IsReady(&first) && dx.IsReady(&second));
                            check(dx.Shutdown(&first, 0, -7, success) == -7);
                            check(initialize(dx, &first) == -7);
                            return 0;
                        }) == 0);
    check(dx.IsReady(&first));
    // In-flight operations block both global and device teardown, without
    // holding the metadata lock across their callbacks. A second API is free.
    check(dx.RunOperation(-7,
                          [&]
                          {
                              check(dx.Shutdown(&first, 0, -7, success) == -7);
                              check(dx.Shutdown(&second, 0, -7, success) == -7);
                              check(dx.Shutdown(nullptr, 0, -7, success) == -7);
                              check(initialize(dx, &absent) == -7);
                              check(initialize(dx, &first) == 0);
                              check(vk.RunOperation(-7, [] { return 19; }) == 19);
                              check(dx.RunOperation(-7, [] { return 21; }) == 21);
                              return -4;
                          }) == -4);
    check(dx.RunOperation(-7, success, &absent) == -7);
    threw = false;
    try
    {
        dx.RunOperation(-7, []() -> int { throw std::runtime_error("evaluate"); });
    }
    catch (const std::runtime_error&)
    {
        threw = true;
    }
    check(threw);
    std::promise<void> operating, finishOperation;
    auto finish = finishOperation.get_future();
    auto operation = std::async(std::launch::async,
                                [&]
                                {
                                    return dx.RunOperation(-7,
                                                           [&]
                                                           {
                                                               operating.set_value();
                                                               finish.wait();
                                                               return 29;
                                                           });
                                });
    check(operating.get_future().wait_for(5s) == std::future_status::ready);
    auto closeDuringOperation = std::async(std::launch::async, [&] { return dx.Shutdown(nullptr, 0, -7, success); });
    check(closeDuringOperation.wait_for(5s) == std::future_status::ready && closeDuringOperation.get() == -7);
    finishOperation.set_value();
    check(operation.wait_for(5s) == std::future_status::ready && operation.get() == 29);
    check(dx.Shutdown(nullptr, 0, -7,
                      [&]
                      {
                          check(dx.RunOperation(-7, success) == -7);
                          return 0;
                      }) == 0);
    check(dx.RunOperation(-7, success) == -7);
    check(initialize(dx, &first) == 0);
    check(dx.RunOperation(-7, [] { return 31; }, &first) == 31);
    std::cout << "PASS: " << checks << " native device lifecycle checks\n";
}
