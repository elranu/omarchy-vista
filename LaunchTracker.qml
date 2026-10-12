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
//
// Between the launch and the window there is nothing to see, sometimes for
// seconds, so an "Opening" notice on Omarchy's OSD card covers that gap. It
// goes when the window appears, when an already running app focuses its own
// window instead, or after noticeLimit, for a window no hint recognises.
Singleton {
    id: root

    property var pending: []
    // Long enough for a cold Electron start.
    readonly property int patience: 45000
    property var notices: []
    property bool noticeShown: false
    readonly property int noticeLimit: 15000

    function launch(entry, newWorkspace) {
        const script = Launch.launchLua(entry?.id, newWorkspace);
        if (script.length === 0)
            return false;
        const hints = Launch.launchHints(entry);
        launcher.createObject(root, { script: script, hints: hints });
        if (GlobalStates.launchNotice)
            root.notice(String(entry?.name ?? ""), hints);
        return true;
    }

    function notice(name, hints) {
        const now = Date.now();
        root.notices = root.notices.filter(item => item.expires > now)
            .concat([{ name: name, hints: hints, since: now, expires: now + root.noticeLimit }]);
        root.refreshNotice();
    }

    // Focus moves around right after a launch, often onto a window of the
    // same app, so a focus counts only once the notice has been up a while.
    function dismissNotice(windowClass, minAge) {
        const now = Date.now();
        const index = root.notices.findIndex(item => now - item.since >= minAge
            && Launch.matchesLaunch(item.hints, windowClass));
        if (index < 0)
            return;
        const rest = root.notices.slice();
        rest.splice(index, 1);
        root.notices = rest;
        root.refreshNotice();
    }

    // The newest launch still waiting is on the card. The card is only closed
    // when Vista put something on it, so a volume OSD is left alone.
    function refreshNotice() {
        const now = Date.now();
        root.notices = root.notices.filter(item => item.expires > now);
        if (root.notices.length === 0) {
            noticeTimer.stop();
            if (root.noticeShown)
                Quickshell.execDetached(["omarchy-shell", "-q", "osd", "close"]);
            root.noticeShown = false;
            return;
        }
        const latest = root.notices[root.notices.length - 1];
        Quickshell.execDetached(["omarchy-shell", "-q", "osd", "show", Launch.noticePayload(latest.name)]);
        root.noticeShown = true;
        noticeTimer.interval = Math.max(50, Math.min(...root.notices.map(item => item.expires)) - now);
        noticeTimer.restart();
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

    Timer {
        id: noticeTimer
        onTriggered: root.refreshNotice()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event?.name === "activewindow" && root.notices.length > 0) {
                root.dismissNotice(Launch.activeWindowClass(event.data), 1000);
                return;
            }
            if (event?.name !== "openwindow")
                return;
            const opened = Launch.parseOpenWindow(event.data);
            if (!opened)
                return;
            if (root.notices.length > 0)
                root.dismissNotice(opened.windowClass, 0);
            if (root.pending.length === 0)
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
