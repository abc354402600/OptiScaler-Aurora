#include "../OptiScaler/framegen/ProviderHandleRegistry.h"
#include "../OptiScaler/framegen/ProviderHandleCreation.h"
#include <atomic>
#include <cstdlib>
#include <iostream>
#include <new>
#include <stdexcept>

// Fail individual ordinary allocations, or every allocation after the native
// callback succeeds. No production allocation hooks or test toggles are added.
static thread_local int allocationBudget = -1;
void* operator new(std::size_t size)
{
    if (allocationBudget == 0)
        throw std::bad_alloc();
    if (allocationBudget > 0)
        --allocationBudget;
    if (auto* p = std::malloc(size ? size : 1))
        return p;
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }

struct Handle
{
    unsigned id;
    int* nativeHandle = nullptr;
};

int main()
{
    int checks = 0;
    auto check = [&](bool ok)
    {
        if (!ok)
        {
            std::cerr << "publication allocation check " << checks + 1 << " failed\n";
            std::exit(2);
        }
        ++checks;
    };
    int native = 9;
    bool observedPreflightFailure = false;
    bool observedSuccess = false;
    // Covers the entry, hash node and possible bucket allocations across STL
    // implementations. Every throw must occur before the native callback.
    for (int budget = 0; budget != 8; ++budget)
    {
        ProviderHandleRegistry<Handle> registry;
        Handle* out = reinterpret_cast<Handle*>(1);
        int calls = 0;
        allocationBudget = budget;
        bool threw = false;
        try
        {
            CreateProviderHandle(registry, &out, Handle { 1 }, 0, -2, -1,
                                 [&](Handle& h)
                                 {
                                     ++calls;
                                     h.nativeHandle = &native;
                                     return 0;
                                 });
        }
        catch (const std::bad_alloc&)
        {
            threw = true;
        }
        allocationBudget = -1;
        if (threw)
        {
            observedPreflightFailure = true;
            check(calls == 0 && !out);
            check(registry.LiveKeys([](auto&) { return true; }).empty());
        }
        else
        {
            observedSuccess = true;
            check(calls == 1 && out);
        }
    }
    check(observedPreflightFailure && observedSuccess);

    ProviderHandleRegistry<Handle> registry;
    Handle* out = nullptr;
    const void* privateAddress = nullptr;
    auto create = [&](bool fail, bool throws)
    {
        return CreateProviderHandle(
            registry, &out, Handle { 2 }, 0, -2, -1,
            [&](Handle& h)
            {
                privateAddress = &h;
                check(!out);
                check(!registry.GetIdentity(&h, [](auto& v) { return v.id; }));
                check(registry.Read(&h, -3, [](auto&) { return 0; }) == -3);
                check(registry.Release(&h, -3, [](auto&) { return 0; }, [](int r) { return r == 0; }) == -3);
                check(registry.LiveKeys([](auto&) { return true; }).empty());
                if (throws)
                    throw std::runtime_error("native create");
                if (fail)
                    return -1;
                h.nativeHandle = &native;
                allocationBudget = 0; // No allocation may follow native success.
                return 0;
            });
    };
    check(create(true, false) == -1 && !out);
    check(!registry.GetIdentity(privateAddress, [](auto& v) { return v.id; }));
    bool threw = false;
    try
    {
        create(false, true);
    }
    catch (const std::runtime_error&)
    {
        threw = true;
    }
    check(threw && !out && registry.LiveKeys([](auto&) { return true; }).empty());
    int result = -1;
    threw = false;
    try
    {
        result = create(false, false);
    }
    catch (const std::bad_alloc&)
    {
        threw = true;
    }
    allocationBudget = -1;
    check(!threw && result == 0 && out);
    check(registry.Read(out, -3, [](auto& h) { return *h.nativeHandle; }) == native);
    check(registry.LiveKeys([](auto&) { return true; }).size() == 1);
    check(registry.Release(out, -3, [](auto&) { return 0; }, [](int r) { return r == 0; }) == 0);
    std::cout << "PASS: " << checks << " publication allocation checks\n";
}
