import "."

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "WorkspaceBarConfig.js" as WorkspaceBarConfig

Item {
    id: root

    // Injected by Omarchy's service loader.
    property var shell: null
    // A QML singleton is only created once something refers to it, and the
    // Displays mini app is loaded on demand. Referring to it from this
    // always-loaded service is what keeps the saved-layout watcher alive, so a
    // layout saved for these screens is put back when they reappear even if the
    // panel is never opened.
    readonly property var displayLayouts: DisplayLayouts
    // Same reason: a mini app popped out into a window must survive the Overview
    // closing, and the singleton that owns those windows is created on demand.
    readonly property var miniAppWindows: MiniAppWindows
    property string appliedMode: ""
    property bool restoring: false

    // Hyprland removes runtime bindings while processing `configreloaded`.
    // Reinstall after the reload has settled, otherwise the service can keep
    // its old appliedMode while all plugin-owned bindings are gone.
    Timer {
        id: reapplyAfterReload
        interval: 250
        repeat: false
        onTriggered: root.applyBindings()
    }

    // A runtime binding transaction can produce a configreloaded event on some
    // Hyprland versions. Ignore that event while our own binding transaction
    // is settling; otherwise the service can repeatedly apply the same script
    // and starve the Quickshell event loop. Events arriving after the guard
    // expires are genuine external reloads and still trigger reinstallation.
    Timer {
        id: bindingApplyGuard
        interval: 750
        repeat: false
    }

    // The only key expressions installed below belong to this plugin. Never
    // add a generic SUPER+key observer: it cannot distinguish a standalone
    // Super release from a user shortcut such as Ctrl+Super+V.
    function configuredMode() {
        return WorkspaceBarConfig.configuredOverviewMode(root.shell);
    }

    function migrateLegacyDuplicateWidget() {
        const legacyConfig = WorkspaceBarConfig.legacyShellConfig(root.shell);
        if (!legacyConfig || typeof root.shell.mutateShellConfig !== "function")
            return;
        const configCopy = JSON.parse(JSON.stringify(legacyConfig));
        if (WorkspaceBarConfig.removeDuplicateNativeWidget(configCopy)) {
            root.shell.mutateShellConfig(function(config) {
                WorkspaceBarConfig.removeDuplicateNativeWidget(config);
            });
        }
    }

    // Workspace numbers and the overview navigation chords are the only normal
    // bindings this plugin owns. Do not install generic SUPER+key observers:
    // Hyprland cannot associate an unbind with its original owner, so those
    // observers can interfere with user-defined shortcuts.
    function workspaceNumberCommands(optimized) {
        const commands = [];
        for (let slot = 1; slot <= 10; ++slot) {
            const keycode = slot + 9;
            commands.push(`hl.unbind("SUPER + code:${keycode}")`);
            if (optimized) {
                commands.push(`hl.bind("SUPER + code:${keycode}", hl.dsp.global("quickshell:panoramaSlot${slot}"), { description = "Overview workspace slot ${slot}" })`);
            } else {
                commands.push(`hl.bind("SUPER + code:${keycode}", hl.dsp.focus({ workspace = "${slot}" }), { description = "Switch to workspace ${slot}" })`);
            }
        }
        return commands;
    }

    function nativeWorkspaceNumberCommands() {
        return root.workspaceNumberCommands(false);
    }

    function bindingScript(optimized) {
        const commands = [
            'hl.layer_rule({ name = "overview-instant", match = { namespace = "^quickshell:overview$" }, no_anim = true, animation = "none" })',
            // These are the plugin's own expressions. Do not add unrelated
            // user shortcuts here; unbind has no owner information.
            'hl.unbind("SUPER_L")',
            'hl.unbind("SUPER_R")',
            'hl.unbind("SUPER + SUPER_L")',
            'hl.unbind("SUPER + SUPER_R")',
            'hl.unbind("SUPER + TAB")',
            'hl.unbind("SUPER + SHIFT + TAB")'
        ];
        commands.push('if _G.panoramaSuperListener then _G.panoramaSuperListener:remove() end');
        commands.push('_G.panoramaSuperDown = _G.panoramaSuperDown or {}');
        commands.push('_G.panoramaSuperListener = hl.on("input.keyboard.key", function(code, time, state) local isSuper = code == 133 or code == 134; if state == 1 then if isSuper then _G.panoramaSuperDown[code] = true; local other = false; for k,v in pairs(_G.panoramaSuperDown) do if k ~= code and v then other = true end end; hl.dispatch(hl.dsp.event("panorama-super," .. (other and "interrupt" or "down"))) else local any = false; for k,v in pairs(_G.panoramaSuperDown) do if v then any = true end end; if any then hl.dispatch(hl.dsp.event("panorama-super,interrupt")) end end else if isSuper and _G.panoramaSuperDown[code] then _G.panoramaSuperDown[code] = nil; local any = false; for k,v in pairs(_G.panoramaSuperDown) do if v then any = true end end; hl.dispatch(hl.dsp.event("panorama-super," .. (any and "up" or "tap"))) end end end)');
        commands.push('hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"), { non_consuming = true, transparent = true, description = "Overview Super state" })');
        commands.push('hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"), { non_consuming = true, transparent = true, description = "Overview Super state" })');
        commands.push('hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"), { non_consuming = true, transparent = true, release = true, description = "Overview Super state" })');
        commands.push('hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"), { non_consuming = true, transparent = true, release = true, description = "Overview Super state" })');
        commands.push('hl.bind("SUPER + TAB", hl.dsp.global("quickshell:panoramaNext"), { description = "Overview workspace next" })');
        commands.push('hl.bind("SUPER + SHIFT + TAB", hl.dsp.global("quickshell:panoramaPrev"), { description = "Overview workspace previous" })');
        commands.push('hl.bind("SUPER + SUPER_L", hl.dsp.global("quickshell:panoramaCommit"), { release = true, description = "Overview workspace commit" })');
        commands.push('hl.bind("SUPER + SUPER_R", hl.dsp.global("quickshell:panoramaCommit"), { release = true, description = "Overview workspace commit" })');
        // Native mode does not own Win+number. Never unbind or recreate those
        // keys there; they may be user-defined rather than Omarchy defaults.
        return optimized
            ? commands.concat(root.workspaceNumberCommands(true)).join("; ")
            : commands.join("; ");
    }

    function transitionScript(previousMode, nextMode) {
        const commands = [root.bindingScript(nextMode === "legacy")];
        // Only a live legacy -> system transition proves that these number
        // bindings belong to this service. Restore the native mappings during
        // that handoff; a fresh system-mode start must leave user mappings alone.
        if (WorkspaceBarConfig.requiresNativeWorkspaceNumberRestore(previousMode, nextMode))
            for (const command of root.nativeWorkspaceNumberCommands())
                commands.push(command);
        return commands.join("; ");
    }

    function applyBindings() {
        if (!root.shell)
            return;
        root.migrateLegacyDuplicateWidget();
        const mode = root.configuredMode();
        if (mode === "") {
            if (root.appliedMode !== "") {
                root.restoreBindings();
                root.appliedMode = "";
            }
            return;
        }
        if (root.appliedMode === mode)
            return;
        root.restoring = false;
        bindingApplyGuard.restart();
        Quickshell.execDetached(["hyprctl", "eval", root.transitionScript(root.appliedMode, mode)]);
        root.appliedMode = mode;
    }

    function restoreBindings() {
        if (root.restoring)
            return;
        root.restoring = true;
        const commands = [
            'if _G.panoramaSuperListener then _G.panoramaSuperListener:remove(); _G.panoramaSuperListener = nil end',
            '_G.panoramaSuperDown = nil',
            'hl.unbind("SUPER_L")',
            'hl.unbind("SUPER_R")',
            'hl.unbind("SUPER + SUPER_L")',
            'hl.unbind("SUPER + SUPER_R")',
            'hl.unbind("SUPER + TAB")',
            'hl.unbind("SUPER + SHIFT + TAB")'
        ];
        if (root.appliedMode === "legacy")
            for (const command of root.nativeWorkspaceNumberCommands())
                commands.push(command);
        commands.push('hl.bind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })');
        commands.push('hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })');
        Quickshell.execDetached(["hyprctl", "eval", commands.join("; ")]);
    }

    Component.onCompleted: Qt.callLater(root.applyBindings)
    onShellChanged: Qt.callLater(root.applyBindings)

    Connections {
        target: root.shell
        ignoreUnknownSignals: true
        function onBarConfigChanged() {
            Qt.callLater(root.applyBindings);
        }
        function onShellConfigChanged() {
            Qt.callLater(root.applyBindings);
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event?.name !== "configreloaded")
                return;
            if (bindingApplyGuard.running)
                return;
            root.appliedMode = "";
            root.restoring = false;
            reapplyAfterReload.restart();
        }
    }

    Component.onDestruction: root.restoreBindings()
}
