# Galaxy on Fire native remake

An independent Godot engine for **Galaxy on Fire 1, iPhone edition**. Supply your
own compatible IPA; the engine imports its ships, environments, artwork, music,
text, missions and catalogues locally. No original game content is included.

## Screenshots

Captured in the remake using locally imported game assets.

![Galaxy on Fire remake — cinematic screenshot 1](https://i.imgur.com/sA5bYTF.jpeg)
![Galaxy on Fire remake — cinematic screenshot 2](https://i.imgur.com/ZGKAZZU.jpeg)
![Galaxy on Fire remake — cinematic screenshot 3](https://i.imgur.com/qJOEQEk.jpeg)

## Version 1.0

Play the thirteen-mission linear campaign, then explore freely. **Skip campaign ·
Explore** enters exploration directly without completion rewards. Trade, outfit
ships, accept contracts or play Survival with a separate score archive.

The remake adds keyboard/mouse and controller controls, variable throttle, time
acceleration, persistent checkpoints and a compact desktop interface with scalable
text. Touch controls are available on mobile and can be switched in Options.
Original icons, portraits and interface artwork come from your game file.
Map travel uses a short departure/arrival fade.

This is an independently designed reimplementation, not emulation or a line-by-line
port. Original program code is never executed or cached. Exact legacy animation,
AI choreography and driver quirks are not claimed to be identical.

## Install and play

- **Windows x86-64:** extract the package and run `gof1.exe`.
- **Linux x86-64:** extract and run `gof1.x86_64` (allow execution if your file
  manager removed its executable permission).
- **macOS Apple silicon / Intel:** extract the universal `.app` package. It is
  unsigned and not notarized; macOS may require approval in Privacy & Security.
- **Android ARM64 / x86-64:** install the signed APK, then choose your IPA using
  the system file picker. Android 7 or newer is required.
- **Web:** open [galaxian.wwworm.com](https://galaxian.wwworm.com/) and choose your
  IPA. Import runs entirely inside your browser; the archive is not uploaded. Keep
  the tab open during import.

Select **Choose game IPA…**, wait for import to finish, then start or load a pilot.
Native desktop builds also accept dragging an IPA onto the window. No converter,
Python, Java, Node.js or iPhone runtime is needed by players. First import can take
several minutes, especially on mobile or in a browser. Cancel stops at an import
checkpoint and preserves previously installed content and saves.

### Compatible game files

The validated archive identifies itself as iPhone **1.1.5**. Acceptance is based on
resource structure and supported data layout, not a fixed filename or checksum.
The current reader needs an unencrypted ARM32 application with its content symbols;
unsupported variants report an error. Other editions have not been validated.
J2ME JARs are not accepted. Keep your IPA so you can recreate the local cache.

### Browser requirements

Use a browser supporting WebGL 2, WebAssembly threads and persistent site storage.
Browser saves and imported content belong to that browser profile and site origin;
clearing site data removes them, and private browsing may not preserve them.
Mobile browsers can use touch controls, but physical mobile-browser performance
has not been verified. Native desktop builds are preferable on low-memory devices.

## Controls

| Action | Keyboard / mouse | Controller |
| --- | --- | --- |
| Steer | Mouse or arrow keys | Right stick |
| Strafe | A / D | Left stick |
| Throttle | W / S | D-pad up / down |
| Fire | Left click or Space | RT or A |
| Next primary weapon | Q | X |
| Missiles | F | LT |
| Boost | Shift | Left stick click |
| Autopilot to objective / station | R | LB |
| Time acceleration | T | RB |
| Dock near the station hull | E | Y |
| Chase / first-person camera | C | — |
| Release / capture mouse | Tab | — |
| Dismiss radio | Enter / tap the panel | — |
| Pause | Escape | Start |
| Save / fullscreen | F5 / F11 | — |

Time acceleration runs repeated simulation steps: up to 2× manually and 16× on
autopilot. Hostiles, damage or approaching a destination return it to 1×. Focus
loss and active-controller disconnect pause the game.

Options includes sensitivity, inversion, aim assistance, touch controls, linked
primary firing and separate music/effects volume. On touchscreens, use the joystick
or drag empty flight space to steer. Android Back pauses/resumes flight or returns
from a menu. Full key remapping is not implemented.

## Saves and updates

Each IPA has a separate content identity, cache and saves. Campaign, exploration
and Survival use separate slots. Checkpoint writes preserve a `.bak` recovery copy;
failed writes are reported without replacing the last valid save. Previous preview
pilots remain compatible. Old imported caches may require choosing the IPA again.

Native desktop data lives in the Godot user-data directory named `gof1-remake`
(`~/.local/share/gof1-remake/` on Linux). Android uses private application storage;
uninstalling the app removes that storage. The first release uses a release signing
key, so old debug-signed development APKs cannot be updated in place.

The imported cache contains original resources and normalized data. It is private
player content and must not be included when sharing engine source or builds.

Engine code is Apache-2.0: [License](LICENSE.md), [Attribution](THIRD_PARTY_NOTICES.md).
Original content and trademarks belong to their rights holders. This is not an
official Fishlabs release, and the engine license grants no rights to game assets.
File formats and behavior were investigated using supplied games; this is not a
clean-room claim.
