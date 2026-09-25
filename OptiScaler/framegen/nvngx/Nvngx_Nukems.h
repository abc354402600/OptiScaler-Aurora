#pragma once
#include "Nvngx_DllProxy.h"

typedef void (*PFN_RefreshGlobalConfiguration)();

class Nvngx_Nukems : public Nvngx_DllProxy
{
    PFN_RefreshGlobalConfiguration _refreshGlobalConfiguration = nullptr;

    bool setSetting(const wchar_t* setting, const wchar_t* value);
    bool is120orNewer() const { return _refreshGlobalConfiguration != nullptr; }

  protected:
    void LoadLibraries() override final;

  public:
    Nvngx_Nukems() { LoadLibraries(); }

    bool setDebugView(bool enabled);
    bool setInterpolatedOnly(bool enabled);
    int getMaxFakeFramesCount() override { return 1; }
    FGNvngxReplacement getType() override { return FGNvngxReplacement::Nukems; }
};
