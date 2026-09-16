#include "../OptiScaler/framegen/ProviderHandleCreation.h"
#include "../OptiScaler/framegen/ProviderHandleRegistry.h"
#include <iostream>
#include <stdexcept>

struct PublicHandle
{
    unsigned id;
};
struct PrivateHandle
{
    unsigned id;
    int* nativeHandle = nullptr;
    std::shared_ptr<int> lifetime;
};

int main()
{
    constexpr int success = 0, invalid = -2, failure = -1;
    int checks = 0, native = 17, calls = 0;
    auto check = [&](bool condition)
    {
        if (!condition)
            throw std::runtime_error("provider creation regression");
        ++checks;
    };
    ProviderHandleRegistry<PrivateHandle> registry;
    PublicHandle* output = reinterpret_cast<PublicHandle*>(1);
    const void* pendingAddress = nullptr;
    std::weak_ptr<int> pendingLifetime;
    auto initial = [&]
    {
        auto lifetime = std::make_shared<int>(1);
        pendingLifetime = lifetime;
        return PrivateHandle { 42, nullptr, lifetime };
    };
    auto failCreate = [&](PrivateHandle& h)
    {
        ++calls;
        pendingAddress = &h;
        check(output == nullptr);
        return failure;
    };
    check(CreateProviderHandle(registry, static_cast<PublicHandle**>(nullptr), initial(), success, invalid, failure,
                               failCreate) == invalid);
    check(calls == 0 && pendingLifetime.expired());
    check(CreateProviderHandle(registry, &output, initial(), success, invalid, failure, failCreate) == failure);
    check(output == nullptr && pendingLifetime.expired());
    check(!registry.GetIdentity(pendingAddress, [](const auto& h) { return h.id; }));

    output = reinterpret_cast<PublicHandle*>(1);
    check(CreateProviderHandle(registry, &output, initial(), success, invalid, failure,
                               [](PrivateHandle&) { return success; }) == failure);
    check(output == nullptr && pendingLifetime.expired());

    // A provider can write a pointer and still fail. Do not publish it or guess ownership.
    output = reinterpret_cast<PublicHandle*>(1);
    check(CreateProviderHandle(registry, &output, initial(), success, invalid, failure,
                               [&](PrivateHandle& h)
                               {
                                   h.nativeHandle = &native;
                                   return failure;
                               }) == failure);
    check(output == nullptr && pendingLifetime.expired() && native == 17);

    output = reinterpret_cast<PublicHandle*>(1);
    try
    {
        CreateProviderHandle(registry, &output, initial(), success, invalid, failure,
                             [](PrivateHandle&) -> int { throw std::runtime_error("native failure"); });
    }
    catch (const std::runtime_error&)
    {
    }
    check(output == nullptr && pendingLifetime.expired());

    check(CreateProviderHandle(registry, &output, initial(), success, invalid, failure,
                               [&](PrivateHandle& h)
                               {
                                   h.nativeHandle = &native;
                                   return success;
                               }) == success);
    check(output != nullptr && !pendingLifetime.expired());
    check(registry.Read(output, -1, [](auto& h) { return *h.nativeHandle; }) == 17);
    int releases = 0;
    check(registry.Release(
              output, failure,
              [&](auto&)
              {
                  ++releases;
                  return success;
              },
              [](int r) { return r == success; }) == success);
    check(registry.Release(
              output, failure,
              [&](auto&)
              {
                  ++releases;
                  return success;
              },
              [](int r) { return r == success; }) == failure &&
          releases == 1);
    std::cout << "PASS: " << checks << " provider creation failure checks\n";
}
