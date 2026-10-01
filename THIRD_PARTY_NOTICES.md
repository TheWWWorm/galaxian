# Attribution

`game/src/input/touch_scroll.gd` is reused from the Apache-2.0 licensed
Abyssal compatibility engine (the maintained DEEP remake). The save isolation,
local import and device-neutral controls follow the same architecture.
`worker.js` and `tools/prepare_web_host.py` adapt its numbered-asset streaming
approach for Cloudflare hosting, also under Apache-2.0.

AEM/AEI file-layout research was consulted at https://github.com/BaalNetbek/AEMesh.
No implementation from that repository is bundled.

Godot is distributed under the MIT license: https://godotengine.org/license/.
Its runtime license notices are available in the exported runtime.
The custom web shell in `game/web/shell.html` is based on Godot's MIT-licensed
HTML template; its license is in `game/web/GODOT_LICENSE.txt`. The home-screen
viewport styling follows the Apache-2.0 licensed maintained DEEP remake.

`game/src/locale/noto_sans_sc.otf`, `noto_sans_jp.otf` and `noto_sans_kr.otf` are
subsets of **Noto Sans CJK** (Regular, version 2.004, SC, JP and KR faces), copyright
2014-2021 Adobe, with Reserved Font Name 'Source', licensed under the
[SIL Open Font License 1.1](licenses/OFL-1.1.txt). Each subset holds only the
characters the matching interface text catalog uses, written from the unmodified
upstream collection. Source: https://github.com/notofonts/noto-cjk . Keep the
license with every distribution that includes these files. `tools/engine_text.py`
and `tools/subset_font.js` are adapted from the Apache-2.0 licensed maintained
DEEP remake.

Original Galaxy on Fire content belongs to its respective rights holders. The
engine license covers this engine's code only. No original content is bundled.
