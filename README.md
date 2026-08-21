# qwitch

qwitch is a minimal keyboard-layout switcher for the Omarchy 4.0 bar. It uses
Omarchy's native Quickshell controls, follows the active theme, and keeps all
layout and shortcut changes in the running Hyprland session.

## Features

- Add, edit, remove, and order XKB layouts from the bar panel; valid changes
  save automatically through Omarchy's shell configuration API.
- Switch every safely managed typing keyboard from the panel or an optional
  recorded shortcut.
- Show a label, Unicode flag, or both in the bar.
- Optionally show the same representation through Omarchy's OSD.
- See actual typing keyboards by default, with rejected keyboard-like devices
  available in a compact advanced section for diagnosis and overrides.
- Keep security tokens, OTP/FIDO devices, virtual keyboards, consumer-control
  nodes, pointers, and ambiguous devices unmanaged by default.

On first enable, qwitch adopts a coherent layout list already active in
Hyprland and records any native `grp:*_toggle` XKB shortcut it finds. It does
not edit `~/.config/hypr` or install a persistent Hyprland keybinding. While it
is running, it also removes Omarchy's simpler `omarchy.keyboard-layout` widget
from the bar through the shell's native configuration API.

## Install

After the repository is published, add it disabled, review the checkout, then
enable it:

```sh
omarchy plugin add https://github.com/aloglu/qwitch.git
omarchy plugin enable io.github.aloglu.qwitch
```

For local development from this checkout:

```sh
omarchy plugin add "file://$HOME/workspaces/qwitch"
omarchy plugin enable io.github.aloglu.qwitch
```

The local URL is still installed with `git clone`, so it contains committed
`HEAD`, not uncommitted working-tree changes. Commit before adding it. If you
amend or otherwise rewrite a revision that is already installed, remove and
re-add the plugin; Omarchy plugin updates are fast-forward-only.

## Update

Pull the latest committed version into Omarchy's managed plugin checkout, then
restart the shell so every loaded QML component is rebuilt from that revision:

```sh
omarchy plugin update io.github.aloglu.qwitch
omarchy restart shell
```

The shell normally detects plugin files automatically, but a restart is the
reliable way to clear a stale panel or widget after an update. If the installed
revision was amended or rebased, remove and add the plugin again because the
updater intentionally accepts only fast-forward changes.

qwitch does not force a bar position. Place or move it with Omarchy's normal bar
customization tools. Left-click the widget to switch to the next layout;
right-click it to open the layout menu, whose gear opens settings.

Remove it with:

```sh
omarchy plugin remove io.github.aloglu.qwitch
```

After an abnormal shell crash, `hyprctl reload` reapplies the persistent
Hyprland configuration and clears any remaining runtime-only device state.

## Runtime access and dependencies

qwitch uses tools already present in Omarchy 4.0:

- `xkbcli` to enumerate XKB layouts and variants;
- `flock`, `jq`, and standard util-linux tools to maintain one validated,
  session-only cleanup lease and serialize qwitch-owned runtime changes;
- `/proc/bus/input/devices` and `hyprctl devices` to distinguish typing
  keyboards from keyboard-like HID interfaces;
- the Hyprland Lua runtime to apply per-device layout lists and own one optional
  shortcut handle;
- `omarchy-shell` IPC for shortcut dispatch and Omarchy's OSD.

qwitch needs no root privileges and makes no network requests. Its temporary
runtime state lives under `$XDG_RUNTIME_DIR/qwitch/`, alongside the lock at
`$XDG_RUNTIME_DIR/qwitch-runtime.lock`. A small resident helper and one sleeping
watchdog survive normal plugin unload long enough to restore only qwitch-owned
device layouts and its exact shortcut handle; all of this state disappears with
the user session. Once a cleanup lease settles, its watchdog exits; the private
resident helper and lock may remain available until that user session ends.

Changing settings writes only the qwitch fields in Omarchy's normal
`~/.config/omarchy/shell.json` bar entry. Runtime device layouts are restored on
normal plugin shutdown using compare-and-restore semantics, so a device changed
by another tool after qwitch's last write is left alone.

Automatic device detection is intentionally conservative. The regular settings
view contains only high-confidence typing keyboards. Security tokens, virtual
inputs, controls, pointers, and ambiguous interfaces stay in Advanced devices;
a security token can be forced into the managed set only after an explicit
warning.

## Development

Validate the manifest and run the terminal-only test suite with:

```sh
omarchy plugin validate .
node --test --test-isolation=none tests/model.test.js tests/service.test.js tests/runtime.test.js
```

The implementation follows the [Omarchy plugin development guide](https://omarchyplugins.com/develop.html)
and targets Omarchy 4.0's Quattro shell contract.

## License

Released under the [MIT License](LICENSE).
