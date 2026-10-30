# Window controls

An [Omarchy](https://omarchy.org) shell plugin that puts a compact control bar
on every Hyprland window: **minimize**, **maximize**, **float**, and **close**.

The bar sits in the top-right of the window, follows the current theme, and
talks to Hyprland through `hyprctl` Lua dispatchers. Minimize sends the window
to `special:omarchy-minimized`, the same shelf used by
[window-shelf](https://github.com/gardnmi/omarchy-window-shelf). Restore it
from that bar widget, or with the usual special-workspace bindings.

## Install

```sh
omarchy plugin add https://github.com/cytracon/omarchy-cytracon-window-controls --enable
```

Plugin ID: `io.github.cytracon.window-controls`.

If you already use `axel.window-close-buttons`, remove it first so the two
overlays do not stack:

```sh
omarchy plugin remove axel.window-close-buttons --yes
```

## Remove

```sh
omarchy plugin remove io.github.cytracon.window-controls --yes
```

## Behaviour

| Button | Action |
|--------|--------|
| Minimize | Move the window to `special:omarchy-minimized` without following it |
| Maximize | Toggle Hyprland maximized mode (`hl.dsp.window.fullscreen` mode `maximized`). If the window is true-fullscreen, that fullscreen is toggled off first |
| Float | Toggle tiled / floating |
| Close | Close that window, focused or not |

The bar is hidden for unmapped, hidden, minimized, peek, inactive-workspace,
and true-fullscreen windows, for windows that are too narrow to fit the
controls, and when an on-screen window stacked above covers the bar (so a rear
window never paints controls on top of the one in front). Dispatchers target
the window by address, so a click does not steal focus or warp the cursor.

Move a window by dragging the bar: **right-click drag**, or **left-click drag**
on the pill (not a click on a button). Right-drag uses Hyprland's mouse bind
(same idea as Super+Left mouse). A tiled or maximized window is floated first.
A short left-click on a button still runs minimize, maximize, float, or close.

Optional Hyprland layer rule (skips the compositor fade on the overlay):

```lua
hl.layer_rule({
  match = { namespace = "omarchy-window-controls" },
  no_anim = true,
  animation = "none",
  order = -100,
})
```

## External dependencies

- Omarchy Quattro shell (Quickshell). No extra QML modules.
- Hyprland Lua (`hyprctl dispatch`). Tested with Omarchy's Hyprland Lua API.
- Optional: `io.github.gardnmi.window-shelf` to restore minimized windows from the bar.

No extra packages, root access, network access, or helper daemon.

## License

MIT
