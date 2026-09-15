#include "../OptiScaler/framegen/FrameCaptureHistory.h"

#include <limits>

// Compile-time tests execute the production policy, without a GPU or Windows SDK.
constexpr int CheckFrameHistory()
{
    FrameCaptureHistory<4> history;
    int checks = 0;
    const auto check = [&checks](bool condition)
    {
        if (!condition)
            throw "frame capture regression";
        ++checks;
    };

    check(!history.CanPresent(0, 0, 0));
    history.Capture(0, 0);
    check(history.CanPresent(0, 0, 0));
    check(!history.CanPresent(4, 0, 0));
    history.Capture(4, 0); // Invalid slot must not corrupt an existing one.
    check(history.CanPresent(0, 0, 0));

    // Incident: captured 210, game PresentStart rebases the frame counter to 2323.
    history.Capture(2, 210);
    check(!history.CanPresent(2, 210, 2323));
    check(!history.CanPresent(3, 2323, 2323));
    check(!history.CanPresent(2, 2322, 2322)); // Same modulo slot is not ownership.
    check(history.CanPresent(2, 210, 210));

    // The next genuine capture allows recovery; no old data is relabeled.
    history.Capture(0, 2324);
    check(history.CanPresent(0, 2324, 2324));
    check(!history.CanPresent(0, 0, 0));
    check(!history.CanPresent(0, 2324, 2325));
    history.Clear(); // Disable / re-enable must wait for a fresh capture.
    check(!history.CanPresent(0, 2324, 2324));
    check(!history.CanPresent(2, 210, 210));
    history.Capture(3, 1911);
    check(history.CanPresent(3, 1911, 1911));

    // Frame IDs are 64-bit, not just modulo-buffer or truncated token IDs.
    constexpr auto large = (std::uint64_t { 1 } << 32) + 1911;
    history.Capture(3, large);
    check(!history.CanPresent(3, 1911, 1911));
    check(history.CanPresent(3, large, large));
    constexpr auto maximum = std::numeric_limits<std::uint64_t>::max();
    history.Capture(3, maximum);
    check(history.CanPresent(3, maximum, maximum));
    check(!history.CanPresent(3, maximum, 0));
    history.Capture(0, 0);
    check(history.CanPresent(0, 0, 0));

    // Backward counter reset cannot adopt a stale slot, even when indices coincide.
    history.Capture(1, 5);
    check(history.CanPresent(1, 5, 5));
    check(!history.CanPresent(1, 1, 1));
    history.Clear();
    check(!history.CanPresent(3, maximum, maximum));
    return checks;
}

static_assert(CheckFrameHistory() == 22);
int main() { return CheckFrameHistory() == 22 ? 0 : 1; }
