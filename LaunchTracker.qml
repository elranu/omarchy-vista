pragma Singleton
pragma ComponentBehavior: Bound
import "."

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Launch.js" as Launch

// Launches an app from the Overview and makes sure its window ends up on the
// workspace it was launched for. Hyprland puts a window on the workspace
// focused when it maps; an app that takes a few seconds to start would open
// wherever the user moved to in the meantime, often another monitor.
//
// The launch carries an exec rule, which settles it when Hyprland can tie the
// window to the process it started. Usually it cannot (see Launch.js), so the
// next window whose class matches the app, within the patience below, is moved
// back to that workspace without taking the focus.
Singleton {
    id: root

    property var pending: []
    // Long enough for a cold Electron start.
    readonly property int patience: 45000

    function launch(entry, newWorkspace) {
        const script = Launch.launchLua(entry?.id, newWorkspace);
        if (script.length === 0)
            return false;
        launcher.createObject(root, { script: script, hints: Launch.launchHints(entry) });
        return true;
    }

    function track(hints, workspace) {
        const id = Number(workspace?.id);
        if (!Number.isInteger(id) || id < 1 || hints.length === 0)
            return;
        const now = Date.now();
        const live = root.pending.filter(item => item.expires > now);
        live.push({ hints: hints, workspaceId: id, monitorName: String(workspace?.monitor ?? ""), expires: now + root.patience });
        root.pending = live;
    }

    function claim(windowClass) {
        const now = Date.now();
        const live = root.pending.filter(item => item.expires > now);
        const index = live.findIndex(item => Launch.matchesLaunch(item.hints, windowClass));
        const match = index >= 0 ? live.splice(index, 1)[0] : null;
        root.pending = live;
        return match;
    }

    // The eval launches; reading the focused workspace right after it names
    // the one the app was launched for, new or current.
    Component {
        id: launcher
        Process {
            id: launchProcess
            required property string script
            required property var hints
            running: true
            command: ["bash", "-c", 'hyprctl eval "$1" >/dev/null && hyprctl -j activeworkspace', "vista-launch", launchProcess.script]
            // Finishes whether or not the eval succeeded: a failed eval
            // skips the query and leaves nothing to parse.
            stdout: StdioCollector {
                id: launchOutput
                onStreamFinished: {
                    try {
                        root.track(launchProcess.hints, JSON.parse(launchOutput.text));
                    } catch (error) {
                        console.warn("ranu.panorama: could not read the launch workspace:", error);
                    }
                    launchProcess.destroy();
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event?.name !== "openwindow" || root.pending.length === 0)
                return;
            const opened = Launch.parseOpenWindow(event.data);
            if (!opened)
                return;
            const match = root.claim(opened.windowClass);
            if (!match)
                return;
            const script = Launch.moveLua(opened.address, match.workspaceId, match.monitorName);
            if (script.length > 0)
                Quickshell.execDetached(["hyprctl", "eval", script]);
        }
    }
}
