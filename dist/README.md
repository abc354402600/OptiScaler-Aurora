> **Aurora v1.1**：DLSS SR/RR/FG 310.9.1、Streamline 2.14.1、运行库防降级，以及初始化、释放和资源访问保护。保留 SL1 与默认 DualFeature=false。详见 [版本说明](https://github.com/abc354402600/OptiScaler-Aurora/releases/tag/aurora-v1.1)；未承诺所有游戏闪退均已解决。

# OptiScaler, y4my4my4m fork

## Step 1:

Modify these to your OptiScaler.ini (read the comments, might not apply to you):

```ini
[NvApi]
; x2~x6 MFG spacing is uneven without this (basically frame generation will feel laggy) for 40XX cards only! (?) older cards should keep it auto?
DisableFlipMetering = true

; only if youre on linux and noticing some weird motion pacing bug
DisableReflexSync = true

[DLSSG]
; only needed if you have a 40XX card
AdaMfgUnlock = true
```

These values should be tried and played with if things don't behave as you expect.

## Step 2:

Put all these files in your game folder (next to the actual .exe, not the launcher)

## Step 3:

Rename `OptiScaler.dll` to `dxgi.dll`

For a Vulkan only game there is no DXGI to take over, so `dxgi.dll` never loads. Rename it to a
DLL that game does import instead. `winmm.dll` and `version.dll` are the usual ones. Whatever name
you pick is the one you override in Step 5.

## Step 4:

You need to put the `nvngx_dlssnr.dll` file (about 158mb) in the game's folder. Make sure to use
the patched version if you have a card other than a 50XX. It is not in either package.

There are two downloads. The plain one is the loader by itself. The `_with_DLSS` one also carries,
already in place and needing no action:

- `OptiScaler\nvngx_dlss.dll`, `nvngx_dlssd.dll`, `nvngx_dlssg.dll` are DLSS 310.9. OptiScaler
  searches its own folder ahead of the exe folder, so these are used without touching what the
  game ships.
- `OptiScaler\dlssg_to_fsr3_amd_is_better.dll` is Nukem's dlssg-to-fsr3 (GPLv3,
  https://github.com/Nukem9/dlssg-to-fsr3 — source and license terms there), the FSR3 backend
  behind the "Nukem's" FG replacement on cards without native DLSSG. Sourced from the RHI
  app's local cache; checksum recorded at packaging time.
- `OptiScaler\streamline\sl.*.dll` are Streamline 2.14.

Take the plain one if the game already has newer, or you keep your own set.

## Step 5 (proton only)

You need to pass dxgi to the WINEDLLOVERRIDES

```
WINEDLLOVERRIDES="dxgi=n,b" %command%
```

Use whatever name you renamed the DLL to in Step 3.

---

For support, contact y4my4m in Harmony's town hall (https://har.mony.lol)

---

In case of emergency, with the files from the `_with_DLSS` package:
- Copy `OptiScaler\streamline\sl.*.dll` over the set the game ships
- Copy `OptiScaler\nvngx_dlss.dll`, `nvngx_dlssd.dll`, `nvngx_dlssg.dll` next to the exe

You shouldn't have to do this, but worth the shot if nothing else works. Keep a copy of whatever
you overwrite.

The first one is the fix for a game stuck at 2X. A game that ships its own Streamline loads it
from where it put it, and OptiScaler's copy does not override that. Unreal titles keep theirs
under `Engine\Plugins\Runtime\Nvidia\Streamline\Binaries\ThirdParty\Win64`, which is where the
files have to go, not next to the exe.

The overlay reports the Streamline version it found. Below 2.7.1 there is no multi frame
generation to unlock and the ratio stops at 2X, whatever the ini asks for.

---

## Changelog

The DLL reports its own version in the overlay title bar, as `10.0.0-dev-fork-y4my4my4m-v4`.
Versions before 4 are not recorded here.

### Version 4

- DLSS Neural Rendering can run inside the upscaler instead of after it, at render resolution
  rather than display resolution. `[DlssNr] DualFeature = true`, with `DualEnlarger` choosing
  which upscaler enlarges the frame afterwards. Measured 219.6 ms to 5.7 ms per frame at 1440p.
  Does nothing at DLAA, where render resolution already equals display resolution.
- The same arrangement on native Vulkan. Untested, no Vulkan title has run it.
- Vulkan device creation no longer identifies the GPU through DXGI. Under Proton DXGI is dxvk,
  whose adapter enumeration re-enters the same hook and hangs or crashes the game.
- MFG unlock reports the detected DLSS-G version and which patches matched, so a bug report
  carries a version number.
- The generated frame ceiling is published where the count crosses `slDLSSGGetState`, rather
  than by scanning `sl.dlss_g.dll` for the clamp. The scan matched nothing on any shipped
  Streamline and could not tell one candidate from another.
- `OverrideInterpolationCount` needs Streamline 2.7.1. Below that it says so in the log
  instead of being read and ignored.
- A reported maximum below the configured interpolation count no longer rewrites that count
  in the ini.
- A generated frame ceiling read before nvngx_dlssg.dll loads is no longer cached. It held
  Ada's 1 for the session and clamped the ratio with it.
- Neural Rendering on a native D3D11 upscaler names what it needs instead of waiting forever.
- Per-pass Neural Rendering settings, and a pass ceiling that can be lifted.

---

Version 4
