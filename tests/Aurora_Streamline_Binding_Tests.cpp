#include "../OptiScaler/proxies/FeatureBindingLifecycle.h"
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>

int main()
{
    int checks = 0;
    auto check = [&](bool condition)
    {
        if (!condition)
            throw std::runtime_error("Streamline binding lifecycle regression");
        ++checks;
    };
    struct Functions
    {
        int generation;
        bool optionalCamera;
    };
    FeatureBindingLifecycle state;
    int first = 1, second = 2, third = 3;
    int setCalls = 0, resolveCalls = 0, publishCalls = 0;
    bool deviceSucceeds = true, requiredFunctions = true, reflexSucceeds = true;
    bool cameraAvailable = false;
    Functions published { 0, false };
    std::string order;
    auto setDevice = [&](void*)
    {
        ++setCalls;
        order += "device ";
        return deviceSucceeds;
    };
    auto prepare = [&]() -> std::optional<Functions>
    {
        ++resolveCalls;
        order += "resolve ";
        if (!requiredFunctions)
            return std::nullopt;
        order += "reflex ";
        if (!reflexSucceeds)
            return std::nullopt;
        return Functions { resolveCalls, cameraAvailable };
    };
    bool publishedBeforeReady = false;
    auto publish = [&](const Functions& functions)
    {
        ++publishCalls;
        publishedBeforeReady = !state.Ready();
        published = functions;
        order += "publish ";
    };

    check(!state.RuntimeInitialized() && !state.Ready());
    check(!state.Bind(&first, setDevice, prepare, publish) && setCalls == 0);
    state.MarkInitialized(true);
    check(state.RuntimeInitialized() && !state.Ready());
    check(!state.CanAutoBind(&first) && !state.CanAutoBind(&second));
    check(!state.Bind(nullptr, setDevice, prepare, publish) && setCalls == 0);

    // The explicit second-device hook selects a device; failure must not resolve or publish.
    deviceSucceeds = false;
    check(!state.Bind(&second, setDevice, prepare, publish));
    check(!state.Ready() && resolveCalls == 0 && publishCalls == 0);
    check(state.CanAutoBind(&second) && !state.CanAutoBind(&first));
    deviceSucceeds = true;
    requiredFunctions = false;
    check(!state.Bind(&second, setDevice, prepare, publish));
    check(setCalls == 2 && resolveCalls == 1 && publishCalls == 0 && !state.Ready());

    // Retry function discovery without repeating successful slInit/slSetD3DDevice.
    requiredFunctions = true;
    reflexSucceeds = false;
    check(!state.Bind(&second, setDevice, prepare, publish));
    check(setCalls == 2 && publishCalls == 0 && !state.Ready());
    reflexSucceeds = true;
    order.clear();
    check(state.Bind(&second, setDevice, prepare, publish));
    check(state.Ready() && publishedBeforeReady && !published.optionalCamera);
    check(order == "resolve reflex publish " && setCalls == 2);
    order.clear();
    check(state.Bind(&second, setDevice, prepare, publish) && order.empty() && publishCalls == 1);

    // A failed new-device binding invalidates readiness but cannot publish a mixed table.
    int oldGeneration = published.generation;
    requiredFunctions = false;
    check(!state.Bind(&third, setDevice, prepare, publish));
    check(!state.Ready() && published.generation == oldGeneration && publishCalls == 1);
    requiredFunctions = true;
    cameraAvailable = true;
    check(state.Bind(&third, setDevice, prepare, publish));
    check(state.Ready() && published.generation != oldGeneration && published.optionalCamera && setCalls == 3);

    FeatureBindingLifecycle normal;
    normal.MarkInitialized(false);
    check(normal.CanAutoBind(&first) && !normal.CanAutoBind(nullptr) && !normal.Ready());
    order.clear();
    check(normal.Bind(&first, setDevice, prepare, [](const Functions&) {}));
    check(order == "device resolve reflex " && normal.Ready());
    std::cout << "PASS: " << checks << " Streamline binding lifecycle checks\n";
}
