# Vista

*Formerly Panorama, renamed because two other Omarchy plugins are already
called Panorama and one of them is a window overview too. The plugin id stays
`ranu.panorama` and the old repository URL still redirects, so existing
installs keep working.*

**Press Win/Super to open the Overview on every monitor.**

![Vista open on two monitors](preview.png)

**Drag windows between workspaces, including onto another monitor.**

![Dragging windows between monitors](docs/media/drag-between-monitors.gif)

**Navigate with the arrow keys and type to search apps, open windows, and Omarchy menu actions.**

![Keyboard navigation and search](docs/media/keyboard-and-search.gif)

Vista is a multi-monitor workspace overview for Omarchy. It provides a full-screen overview on every monitor with live window previews, wallpaper-backed workspace cards, MRU workspace ordering, drag-and-drop between workspaces and monitors, search, and automatic keyboard integration.

See [`CHANGELOG.md`](CHANGELOG.md) for release notes.

## Features

- Press the standalone Win/Super key to open or close Overview.
- Live `ScreencopyView` thumbnails for windows on every workspace.
- Wallpaper-backed workspace cards, including an opaque New workspace card.
- Empty workspaces remain visible when **Occupied workspaces only** is off.
- A New workspace card always stays at the end of each monitor's list.
- Mouse selection, window focusing, drag-and-drop, and multi-monitor layouts.
- Drag a window from one monitor's Overview onto a workspace on another monitor.
- Press `Ctrl+Shift+X` in Overview to arm force-kill mode; the cursor is hidden
  and a close icon (`󰅖`) follows the pointer, and clicking a window kills only
  that client. Press `Escape` or right-click to cancel without killing anything.
- Keyboard navigation with arrows, H/J/K/L, Tab, Enter, Space, and Escape.
- Windows-style MRU ordering for workspaces across Overview, the top bar,
  Win+number, Win+Tab, and Win+Shift+Tab.
- Search for applications, open windows, and Omarchy menu actions from Overview,
  with a built-in calculator.
- Arrange your monitors: the **Displays** mini app draws every screen at its
  logical size and lets you drag them to where they stand on your desk. A layout
  can be saved for that exact set of screens, in Vista's own state file.
- Per-monitor workspace previews, configurable from the gear panel.
- Right-click any part of the top-bar workspace widget to open Overview as a
  mouse fallback when the keyboard shortcut is unavailable.
- Re-registers its runtime bindings after a Hyprland configuration reload.
- Omarchy theme colors and configured icon font.
- No generic fallback icon is drawn over a window thumbnail when an app has no icon.
- Window icons come from the desktop entries, so applications whose window class
  differs from their icon name still show their own icon.

## Requirements

- Omarchy 4 (Hyprland with Lua configuration and the Omarchy Quickshell shell).
- Everything else it calls ships with Omarchy: `hyprctl`, `uwsm-app` and
  `gtk-launch` to launch applications from search, `xdg-terminal-exec` for
  `>command` searches, and `wl-copy` to copy calculator results.

Vista needs no root privileges, installs no services, downloads nothing,
and never edits your Hyprland configuration files. Its bindings exist only at
runtime and are removed when the plugin is disabled.

## Install

```sh
omarchy plugin add https://github.com/elranu/omarchy-vista.git --enable
```

After enabling, the plugin registers its Hyprland bindings automatically. Users do not need to edit `~/.config/hypr/bindings.lua`.

### Switching from Overview Workspaces

Vista has its own plugin id (`ranu.panorama`), so `plugin add` installs it
next to Overview Workspaces instead of replacing it, and both would fight over
the same Win/Super bindings. Remove the original first, then add Vista:

```sh
omarchy plugin remove hancore.overview-workspaces
omarchy plugin add https://github.com/elranu/omarchy-vista.git --enable
omarchy restart shell
```

Settings from the gear panel start from their defaults. To keep the learned
workspace order, move `omarchy-overview-workspaces` to `omarchy-panorama` inside
`${XDG_STATE_HOME:-$HOME/.local/state}` before restarting the shell.

If you run a local copy of this repository under the old id instead, rename its
folder in `~/.config/omarchy/plugins/` to `ranu.panorama`, change the bar entry id
in `~/.config/omarchy/shell.json` from `hancore.overview-workspaces` to
`ranu.panorama`, and restart the shell. That keeps your gear-panel settings.

After updating an existing enabled installation, restart Omarchy Shell once so
the new keybinding service code replaces the preserved `keepLoaded` instance:

```sh
omarchy restart shell
```

A plugin rescan alone does not replace that service instance. Do not use a
Hyprland reload as a substitute.

Enabling automatically replaces the built-in workspace indicator; disabling restores it through Omarchy's native replacement mechanism. Older hosts that injected the full shell configuration also retain the legacy duplicate-layout cleanup.

## Remove

```sh
omarchy plugin remove ranu.panorama
omarchy restart shell
```

Removing the plugin unregisters its runtime bindings and restores Omarchy's
native workspace indicator and workspace shortcuts. Optionally delete its saved
workspace order with `rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-panorama"`
(the state directory keeps its old name so an upgrade does not lose the learned
workspace order).

## Workspace ordering

Open the gear button in the top bar and use the **Occupied workspaces only**
toggle. In both states, occupied workspaces follow Windows-style MRU order and
the New workspace card stays last. The top bar, Overview, and keyboard behavior
change together.

**On (default)**

- Only workspaces with windows are shown.
- Win+1 through Win+0 follow those visual slots.

**Off**

- Native empty slots 1–10 stay visible, along with existing workspaces 11 and higher.
- Native IDs are not renumbered.
- Native Win+number behavior is restored; Overview and Win+Tab remain available.

## Search

**The selected result grows so it is obvious what Enter will do.**

![Search results, with the selected one enlarged](docs/media/search-results.png)

Open Overview with the standalone Win/Super key, then press `/` to enter search.
Type an application name, window title, or Omarchy menu action and press Enter
to launch or focus the selected result. Use the arrow keys or Tab to move the
selection, and Escape to leave search.

H/J/K/L remain workspace navigation keys by default. To restore the older
behavior where any printable character starts search, turn off **Keep h/j/k/l
for navigation** in the gear panel. Prefix a query with `>` to run it as a
terminal command.

### Search shortcuts

| Key | What it does |
|---|---|
| `Enter` | Launch the selected application **on a new workspace**, focus the selected window, or run the selected menu action |
| `Shift+Enter` | Launch the selected application **on the current workspace** (`Shift+click` does the same) |
| `Up` / `Down` / `Tab` | Move the selection |
| `Escape` | Leave search; again to close the Overview |
| `>` prefix | Run the rest of the query as a terminal command |
| `=` prefix | Force a calculation, e.g. `=2048` |

### Calculator

**Type arithmetic and the answer is the first result; Enter opens the calculator
with it loaded.**

![The Calculator mini app, with history and the copy confirmation](docs/media/calculator.png)

Arithmetic in the query shows the answer straight away: `12*3+4`,
`(1500-200)/4`, `2^10`, or `200*15%` (percent divides by 100). `x`, `×` and `÷`
also work, a comma is read as a decimal separator (`3,5*2`), and numbers may
carry an exponent (`1.5e3`). Expressions are parsed by the plugin itself, never
evaluated as code.

| Key | What it does |
|---|---|
| `=` prefix | Force a calculation, so a bare number counts: `=2048` |
| `Enter` (on the answer card) | Open the Calculator mini app with the expression loaded |
| `Shift+Enter` (on the answer card) | Copy the answer and close the Overview |
| `Enter` (inside the Calculator) | Copy the answer, add it to the history, and leave it ready for the next operation |
| `Backspace` / `Delete` / `C` | Delete the last character / clear / clear |
| `Escape` | Close the Calculator and go back to the Overview |

### Mini apps

Mini apps are small interactive panels that open over the workspace grid. Search
for one by name (the Calculator answers to `calc`) and press Enter; Escape
closes it and leaves the Overview open.

Adding one is a QML file based on `MiniApp.qml` plus an entry in `MiniApps.js`.

### Displays

Search for `displays` (also `monitor`, `pantalla`, `screen`) and press Enter.
Every connected monitor is a tile, drawn at its **logical** size, which is the
native resolution divided by the scale: a 2880×1800 panel at scale 1.6 is
1800×1125 here, and that is the number the next monitor's position starts at, so
the picture matches how Hyprland lays the screens out.

Drag a tile to where that screen stands on your desk. Tiles snap to the edges
and the centres of their neighbours, a tile dropped on top of another slides to
the nearest free side, a tile dropped in empty space is pulled back against the
others, and the layout always starts at `0x0`. No overlapping screens, and no
gaps for the pointer to get stuck in.

| Key | Action |
| --- | --- |
| `←` `→` `↑` `↓` or `h` `j` `k` `l` | Move the selected screen to that side; press again to slide it along |
| `1`–`9`, `Tab` | Select a screen |
| `Enter` | Apply to the running session |
| `s` | Save for these screens and apply |
| `u` | Undo changes that were not applied |
| `r` | Reload the Hyprland config, undoing an applied layout |
| `Escape` | Close |

**Apply** only sets positions. The mode and the scale of each monitor are echoed
back exactly as reported, so resolution and refresh rate stay with Omarchy's own
Display panel and your `monitors.lua`. It lasts until the next Hyprland reload.
Hyprland restarts the layer surfaces on every screen that moves, so the Overview
closes when you apply.

**Save** keeps the arrangement in `~/.local/state/omarchy-panorama/display-layouts.json`,
under a signature built from the monitors' descriptions, and applies it. When
those same screens are connected again, the layout is put back. A different set
of screens finds no entry, so a layout saved at the desk is never applied to a
projector somewhere else, and your `monitors.lua` keeps deciding what happens
there. The gear panel's **Restore saved display layouts** turns the restoring
off without throwing the saved layouts away, and **Forget** drops the one for
the screens in front of you.

Resolution, refresh rate, scale and rotation are not changed here; Omarchy's own
Display panel owns those.

The search index reads Omarchy's menu through `$OMARCHY_PATH`, so it does not
assume `/usr/share/omarchy` and can be used on NixOS installations.

## Keyboard integration and cleanup

The enabled plugin service registers standalone Win, Win+Tab, Win+Shift+Tab, optimized Win+number slots, and Super-interrupt guards for normal application shortcuts.

When the plugin is disabled or removed, the service removes the fixed shortcut
chords it manages and restores Omarchy's default workspace navigation and
Super+mouse move/resize. Hyprland's runtime unbind API has no plugin-owner
identity, so a custom user mapping on the same chord cannot be preserved by
this cleanup. The service never runs `hyprctl reload` or writes runtime binds
into the user's Hyprland configuration.

## Manual summon and diagnostics

```sh
omarchy-shell shell summon ranu.panorama '{}'
hyprctl layers | grep -A3 -B2 'quickshell:overview'
omarchy plugin list --json | jq '.[] | select(.id == "ranu.panorama")'
```

## Project files

- `Overview.qml` — Overview layer-shell surface and lifecycle.
- `OverviewWidget.qml` — workspace grid, wallpaper, borders, selection, and drag targets.
- `OverviewWindow.qml` — window geometry, live thumbnails, and app icons.
- `WorkspaceNavigation.qml` — keyboard navigation, focus, and drag commits.
- `OverviewSwitchingController.qml` — Win+Tab switching and commit behavior.
- `WorkspaceOrder.qml` — persistent optimized workspace ordering.
- `HyprlandData.qml` — workspace, monitor, and window state mapping.
- `SettingsPanel.qml` — ordering-mode settings panel.
- `Displays.js` — monitor layout geometry: logical sizes, snapping, overlap and gap repair.
- `DisplaysApp.qml` — the Displays mini app: canvas, drag, apply and save.
- `DisplayLayouts.qml` — saved layouts per set of screens, and restoring them.
- `KeybindingService.qml` — automatic shortcut registration and cleanup.

## Validation

The complete repeatable validation procedure is documented in
[`docs/validation.md`](docs/validation.md). It covers automated tests, plugin
validation, QML checks, Shell IPC, layer checks, mouse fallback behavior,
stability cycles, and recovery isolation.

```sh
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
  Overview.qml OverviewWidget.qml OverviewWindow.qml \
  SettingsPanel.qml KeybindingService.qml bar/widget.qml
node --test
```

## Credits

Vista (formerly Panorama) is a fork of
[iamcheyan/omarchy-overview-workspaces](https://github.com/iamcheyan/omarchy-overview-workspaces)
(Overview Workspaces, by HANCORE), which is published separately in the Omarchy
plugin marketplace. Vista adds multi-monitor support, such as dragging windows
between monitors, and follows its own release line. Both are MIT licensed.

Vista and Overview Workspaces take over the same Win/Super bindings, so enable
only one of them at a time.
