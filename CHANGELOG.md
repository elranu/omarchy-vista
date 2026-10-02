# Changelog

## Unreleased

- The icon file index only covers the icons the desktop entries actually
  declare, filtered by `grep` before anything reaches QML: 374 paths here
  instead of 6979, each of which used to run a JavaScript callback at startup
  and stay in memory. A hang captured on 2026-09-24 had the main thread in the
  garbage collector under that per-line callback.
- The window-icon index is rebuilt without per-entry arrays and at most once per
  burst of desktop-entry rescans. A captured hang (2026-09-23) had the shell's
  main thread inside the JavaScript garbage collector under this rebuild,
  although measurement later showed rescans are rare, so this reduces pressure
  rather than proving a cause.

## 0.2.4

- The repository is now `elranu/omarchy-vista`, matching the plugin's name.
  GitHub redirects the old URL, and the plugin id (`ranu.panorama`) and state
  directory are unchanged, so installs and saved workspace order survive.
- Renamed to **Vista**. Two other marketplace plugins are also called Panorama,
  one of them a window overview too. The plugin id (`ranu.panorama`) is
  unchanged, so existing installs keep working.
- Mini apps: interactive panels that open over the workspace grid. `MiniApp.qml`
  is the shared frame (backdrop, title bar, key hints, Escape) and `MiniApps.js`
  the registry, so a new one is a QML file plus an entry. They are searchable
  under **Mini apps**.
- The first mini app is a **Calculator**: a large display, an on-screen keypad,
  history of recent answers, and a copy button. Typing arithmetic in search
  still shows the answer as a card; Enter opens the calculator with it loaded
  and Shift+Enter just copies. Enter inside the calculator copies the answer,
  keeps it in the history and leaves it ready for the next operation, with
  Omarchy's OSD confirming the copy. Numbers may carry an exponent (`1.5e3`),
  so a very large answer can still start the next operation. Expressions go
  through a small parser, never `eval`.
- Shift+Enter (or Shift+click) opens an app on the current workspace; Enter
  still opens it on a new one. The selected result shows both keys.
- The selected search result grows: taller row, larger icon and title, accent
  border, so it is obvious what Enter will act on. The list scrolls by the
  selected row's real geometry, since rows no longer share one height.
- Window icons are resolved through the desktop entries instead of assuming the
  window class is an icon name. Applications whose class differs from their
  icon (Brave is `brave-browser` with icon `brave-desktop`, VS Code is `Code`
  with `vscode`) showed the generic placeholder in the Overview and in search.

## 0.2.3

- The top-bar workspace buttons are no longer destroyed and recreated when
  their order changes. Focusing a workspace reorders the MRU list, and each
  switch rebuilt every button, each one resyncing the bar's click-target
  registry; six switches created 84 buttons. The buttons now follow their slot
  and only the count decides when one is added or removed. A third captured
  hang showed this path after 0.2.2's fix had already removed the redundant
  rebuilds.

## 0.2.2

- Stopped refetching the whole window model on Hyprland events that cannot
  change it: keyboard layout switches, `screencastv2`, and the plugin's own
  Super-key events. Each one used to spawn four `hyprctl` processes, and a
  flapping virtual keyboard could emit dozens per second.
- The top-bar workspace buttons are only rebuilt when the list they show
  actually changes. Every Hyprland event touching their inputs used to destroy
  and recreate all of them, and each button's registration with the bar runs a
  sync across every plugin's click targets. Under a burst of events that churn
  could pin the shell's main thread in the JavaScript garbage collector.

## 0.2.1

- Renamed `AGENTS.md` to `docs/no-hyprctl-reload.md`. The file is installed with
  the plugin, and coding agents read a root `AGENTS.md` as instructions.
- Pinned the GitHub Actions in the test workflow to full commit SHAs and gave
  the workflow an explicit `contents: read` permission.

## 0.2.0

- Forked from Overview Workspaces and renamed to Panorama, with plugin id
  `ranu.panorama`. Quickshell global shortcuts, the Super-key Lua listener, and
  the state directory were renamed to match, so they cannot collide with the
  original plugin.
- Windows can be dragged from one monitor's Overview onto a workspace on another
  monitor.
- Workspace ordering is now a single **Occupied workspaces only** on/off toggle.
  The stored `sortMode` values are unchanged.
- Removed the Chinese and Japanese documentation; the repository is English-only.
- New previews and demo recordings made for Panorama on a two-monitor setup,
  replacing the original plugin's screenshots. The README now documents
  requirements and removal.
- Enter now opens the selected workspace when "Keep h/j/k/l for navigation" is
  off. It used to start a search because Enter reports a carriage return as
  its text, which left the Overview open and made Escape seem to do nothing.

## 0.1.10

- Use one Windows-style MRU order for the Overview grid, top-bar workspace
  buttons, Win+number navigation, and Win+Tab switching. Occupied workspaces
  move to the front when focused; empty/native slots and the New workspace card
  remain outside MRU and stay after occupied workspaces.

## 0.1.9

- Restored automatic Win/Super, Win+Tab, and optimized Win+number bindings on
  Omarchy 4 by using its capability-scoped `barConfig` API.
- Kept compatibility with older Omarchy hosts without requesting access to the
  full shell configuration.
- Removed the raw Super-key listener when the plugin service is disabled or
  destroyed, so no Overview event observer remains behind.
- Restored native Win+number bindings when changing from optimized ordering to
  system ordering, preventing stale Overview slots after a later disable.
- Documented the required Shell restart after updating an existing enabled copy;
  Omarchy intentionally preserves `keepLoaded` services during plugin rescans.

## 0.1.8

- Added a guarded force-kill mode to Overview: press `Ctrl+Shift+X`, then click
  a window to terminate only that client by address.
- The mode hides the themed system cursor and shows the JetBrainsMono Nerd Font
  close glyph `󰅖` next to the pointer. `Escape` or right-click cancels safely.

## 0.1.7

- System-native mode keeps Omarchy's Win+1…0 workspace binds instead of
  leaving those keys unbound.
- While Overview is open, the plugin temporarily guards Super+mouse move/resize
  so the native window operation cannot compete with preview dragging.
- System-native Overview no longer copies another monitor's workspaces into
  the current screen, and each monitor gets its own New workspace id.
- Search, lint, and menu paths follow `$OMARCHY_PATH` on NixOS and Arch.
- Application icons use the same filesystem index as Omarchy's app library.
- Overview and window previews fade in smoothly without changing user mouse bindings.

## 0.1.3

- Added the current plugin version to the workspace-order popup.
- Made the popup options responsive and scrollable when large text or a
  smaller display leaves less vertical space.
- Adapted the settings panel and overview scrim to theme-derived popup and
  background colors; removed the hard-coded dark scrim color.
