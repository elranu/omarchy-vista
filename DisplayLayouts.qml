pragma Singleton
pragma ComponentBehavior: Bound
import "."

import QtQuick
import Quickshell
import Quickshell.Io
import "Displays.js" as Displays

// Saved monitor layouts, kept in Vista's own state directory and never in the
// Hyprland config. A layout is stored under the signature of the screens it was
// saved with, so the arrangement from the desk is only ever put back on those
// same screens: plugging a projector somewhere else finds no entry and leaves
// Hyprland's own rules alone.
//
// Nothing is written until the Displays mini app saves, and nothing is restored
// unless a saved layout matches the monitors that are connected right now.
Singleton {
    id: root

    readonly property string statePath: `${Directories.stateHome}/display-layouts.json`

    // Signature -> { positions: [{ key, name, x, y }], savedAt }
    property var layouts: ({})
    property bool ready: false
    // Mirrors the bar widget's `restoreDisplayLayouts` setting.
    readonly property bool restoreEnabled: GlobalStates.restoreDisplayLayouts

    signal restored(string signature)

    function layoutFor(signature) {
        const key = String(signature ?? "");
        return key.length > 0 && root.layouts[key] ? root.layouts[key] : null;
    }

    function hasLayoutFor(tiles) {
        return !!root.layoutFor(Displays.layoutSignature(tiles));
    }

    function save(tiles) {
        const entry = Displays.savedLayout(tiles);
        if (entry.signature.length === 0 || entry.positions.length === 0)
            return;
        var next = {};
        for (var key in root.layouts)
            next[key] = root.layouts[key];
        entry.savedAt = new Date().toISOString();
        next[entry.signature] = entry;
        root.layouts = next;
        root.persist();
    }

    function forget(signature) {
        const key = String(signature ?? "");
        if (!root.layouts[key])
            return;
        var next = {};
        for (var existing in root.layouts) {
            if (existing !== key)
                next[existing] = root.layouts[existing];
        }
        root.layouts = next;
        root.persist();
    }

    function serialized() {
        var entries = [];
        for (var key in root.layouts)
            entries.push(root.layouts[key]);
        return JSON.stringify({ version: 1, layouts: entries }, null, 2) + "\n";
    }

    function parseState(text) {
        root.ready = true;
        const raw = String(text ?? "").trim();
        if (raw.length === 0)
            return;
        try {
            const parsed = JSON.parse(raw);
            const entries = Array.isArray(parsed?.layouts) ? parsed.layouts : [];
            var next = {};
            for (var i = 0; i < entries.length; ++i) {
                const entry = entries[i];
                const signature = String(entry?.signature ?? "");
                if (signature.length > 0 && Array.isArray(entry?.positions))
                    next[signature] = entry;
            }
            root.layouts = next;
        } catch (e) {
            console.warn("[DisplayLayouts] Failed to parse saved layouts:", e);
        }
        // Monitors are usually known before this file finishes loading, so the
        // monitorsChanged that would have triggered a restore has already been
        // and gone. Ask for one now that the saved layouts are in hand.
        root.restoreDebounce.restart();
    }

    function persist() {
        if (!root.ready)
            return;
        stateFile.setText(root.serialized());
    }

    // Puts the saved layout back when the connected screens match it and they
    // are not already arranged that way. Restoring is one hyprctl call, so
    // Hyprland never sees an intermediate layout with two monitors on top of
    // each other.
    function restoreIfSaved() {
        if (!root.restoreEnabled || !root.ready)
            return false;
        const live = Displays.fromMonitors(HyprlandData.monitors);
        if (live.length < 2)
            return false;
        const signature = Displays.layoutSignature(live);
        const saved = root.layoutFor(signature);
        if (!saved)
            return false;
        const target = Displays.restoreLayout(live, saved);
        if (!target || Displays.samePositions(live, target))
            return false;
        const commands = target.map(tile => `keyword monitor ${Displays.monitorKeyword(tile)}`);
        Quickshell.execDetached(["hyprctl", "--batch", commands.join("; ")]);
        root.restored(signature);
        return true;
    }

    property Process ensureStateDirectory: Process {
        command: ["mkdir", "-p", Directories.stateHome]
        onExited: stateFile.reload()
    }

    property FileView stateFile: FileView {
        id: stateFile
        path: root.statePath
        // No file until a layout is saved, which is the normal case: the
        // handler below treats that as empty instead of logging on every start.
        printErrors: false
        onLoaded: root.parseState(stateFile.text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[DisplayLayouts] Failed to load saved layouts:", error);
            root.ready = true;
        }
    }

    // Hyprland reports the new set of screens a moment after a monitor is
    // plugged in, and the bar is restarted around the same time. A short delay
    // keeps the restore from racing that.
    property Timer restoreDebounce: Timer {
        interval: 600
        onTriggered: root.restoreIfSaved()
    }

    property Connections monitorWatch: Connections {
        target: HyprlandData
        function onMonitorsChanged() {
            if (root.ready)
                root.restoreDebounce.restart();
        }
    }

    Component.onCompleted: root.ensureStateDirectory.running = true
}
