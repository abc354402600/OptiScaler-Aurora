#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

// A ring index alone does not establish which frame owns its resources.
template <std::size_t SlotCount> class FrameCaptureHistory
{
    struct Stamp
    {
        std::uint64_t frame = 0;
        bool valid = false;
    };
    std::array<Stamp, SlotCount> _slots {};

  public:
    constexpr void Capture(std::size_t slot, std::uint64_t frame)
    {
        if (slot < SlotCount)
            _slots[slot] = { frame, true };
    }

    constexpr void Clear() { _slots = {}; }

    constexpr bool CanPresent(std::size_t slot, std::uint64_t dispatchFrame, std::uint64_t presentFrame) const
    {
        return slot < SlotCount && dispatchFrame == presentFrame && _slots[slot].valid &&
               _slots[slot].frame == dispatchFrame;
    }
};
