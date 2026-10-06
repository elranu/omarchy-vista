pragma ComponentBehavior: Bound
import "."

import QtQuick
import Quickshell
import "MiniApps.js" as MiniApps

// A mini app in a real window. FloatingWindow is an xdg toplevel, so Hyprland
// puts it on a workspace, tiles it, and reaches it with Super+number like any
// other window, instead of the layer surface the Overview draws on.
//
// The window is owned by MiniAppWindows, not by the Overview, so closing the
// Overview leaves it alone. Its class is the shell's own, because Quickshell's
// app id belongs to the process and cannot be set per window; the title is what
// a Hyprland window rule can match on.
FloatingWindow {
    id: window

    property string appId: ""
    property string input: ""
    readonly property var app: MiniApps.byId(window.appId)

    signal dismissed()

    title: window.app ? `${window.app.title} — Vista` : "Vista"
    implicitWidth: 820
    implicitHeight: 620
    minimumSize: Qt.size(420, 380)
    color: TuiStyle.bg

    FocusScope {
        anchors.fill: parent
        focus: true

        Loader {
            id: appLoader
            anchors.fill: parent
            source: window.app ? Qt.resolvedUrl(window.app.source) : ""

            onLoaded: {
                const item = appLoader.item;
                if (!item)
                    return;
                item.windowed = true;
                if ("expression" in item)
                    item.expression = window.input;
                item.closeRequested.connect(() => window.dismissed());
                if (typeof item.focusInitial === "function")
                    Qt.callLater(() => item.focusInitial());
            }
        }

        // The window has the keyboard itself, so the app's own handler is wired
        // straight to it rather than being forwarded by the Overview.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                window.dismissed();
                event.accepted = true;
                return;
            }
            if (appLoader.item?.handleKey && appLoader.item.handleKey(event))
                event.accepted = true;
        }
    }
}
