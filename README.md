# qwitch

qwitch is a minimal keyboard-layout switcher for the Omarchy 4.0 bar. It uses
Omarchy's native Quickshell controls, follows the active theme, and keeps all
layout and shortcut changes in the running Hyprland session.

## Features

- Add, edit, remove, and order XKB layouts from the bar panel; valid changes
  save automatically through Omarchy's shell configuration API.
- Switch every safely managed typing keyboard from the panel or an optional
  recorded shortcut.
- Optionally remember layouts per application or per live window, while
  keeping one global layout as the default behavior.
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

The settings panel reports Hyprland's detected XKB group-toggle shortcut and
qwitch's optional recorded shortcut separately because they have different
owners. If both are configured, both sources can switch the active layout.

Layout scope is global by default. **Remember by app** uses Quickshell's native
active-toplevel information to associate an application ID with a persisted
layout, shared by every window belonging to that application. **Remember by
window** instead uses Hyprland's native live-window identity, allowing two
windows from the same application to keep different layouts. Window memories
are intentionally session-only and are removed when their windows close; they
are not reconstructed from titles, process IDs, or other unreliable guesses.
Switching back to **Global** stops focus-driven restores without discarding
application memories. Every bar instance reads the active layout from qwitch's
singleton service, so a focus-driven restore updates the displayed bar layout
on every monitor at the same time.

On multi-monitor systems, scope follows Hyprland's single keyboard-focused
window regardless of which monitor contains it. Moving focus to a remembered
window on another monitor restores that window's app or window layout, and all
qwitch bar instances display the resulting active keyboard layout.

Automatic app- and window-scope restores are silent. The OSD preference applies
only to layout changes initiated by the user, including qwitch controls and a
native XKB group-toggle shortcut. qwitch correlates compositor layout events
with the XKB keymap targeted by its own switch operations. This also covers
duplicate events mirrored through an input-method virtual keyboard, so a
self-generated event cannot produce a second OSD notification.

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

Validate the manifest and run the model/runtime tests with:

```sh
omarchy plugin validate .
node --test --test-isolation=none tests/model.test.js tests/service.test.js tests/runtime.test.js
```

In a running Omarchy graphical session, exercise the real settings panel and
its native controls with:

```sh
tests/run-qml-tests.sh
```

The QML harness checks field sizing and focus behavior, native button-group
signals, automatic saving, shortcut-source labeling, and viewport reset. It
copies the panel and Omarchy UI modules into a temporary test configuration; it
does not install or alter the plugin.

The implementation follows the [Omarchy plugin development guide](https://omarchyplugins.com/develop.html)
and targets Omarchy 4.0's Quattro shell contract.

## License

Released under the [MIT License](LICENSE).
