# qwitch

qwitch is a keyboard-layout switcher for the Omarchy 4 bar, built with native
Quickshell and Hyprland APIs.

## Features

- Add, edit, remove, and reorder XKB layouts with automatic saving.
- Switch layouts globally or remember them per application or live window.
- Display text, a flag, or both, with optional Omarchy OSD notifications.
- Detect real typing keyboards conservatively, with advanced device overrides.
- Show the native XKB switching shortcut configured in Hyprland.

Left-click the widget to switch layouts. Right-click to open the layout menu;
use its gear button for settings. qwitch also replaces Omarchy's built-in
keyboard-layout indicator while running.

## Switching shortcut

qwitch does not edit `~/.config/hypr`, install a Hyprland keybinding, or change
`kb_options`. Configure a native XKB group toggle in
`~/.config/hypr/input.lua`. For example, Alt+Shift is:

```lua
hl.config({
  input = {
    kb_options = "grp:alt_shift_toggle",
  },
})
```

Leave `kb_layout` unset or commented out so qwitch remains the source of truth
for the active layout list. Because `kb_options` is one comma-separated list,
keep any unrelated XKB options you already use alongside the `grp:*` option.

Then reload and validate Hyprland:

```sh
hyprctl reload
hyprctl configerrors
```

qwitch displays the detected shortcut but does not manage it.

## Install

```sh
omarchy plugin add https://github.com/aloglu/qwitch.git
omarchy plugin enable io.github.aloglu.qwitch
```

## Update

```sh
omarchy plugin update io.github.aloglu.qwitch
omarchy restart shell
```

Restarting the shell clears stale loaded QML. Updates are fast-forward-only;
remove and re-add the plugin after rebasing or amending an installed revision.

## Remove

```sh
omarchy plugin remove io.github.aloglu.qwitch
```

## Development

Install the current committed checkout locally with:

```sh
omarchy plugin add "file://$HOME/workspaces/qwitch"
omarchy plugin enable io.github.aloglu.qwitch
```

Local installs clone committed `HEAD`; commit changes before installing. Run
the checks with:

```sh
omarchy plugin validate .
node --test --test-isolation=none tests/model.test.js tests/service.test.js tests/runtime.test.js
tests/run-qml-tests.sh
```

## License

Released under the [MIT License](LICENSE).
