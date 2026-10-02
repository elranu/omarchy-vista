pragma Singleton
pragma ComponentBehavior: Bound
import "."

import QtQml
import QtQuick
import Quickshell

// Owns the mini apps that were popped out into windows. A singleton, so the
// windows outlive the Overview that opened them; KeybindingService refers to it
// for the same reason it refers to DisplayLayouts, since a QML singleton is only
// created once something asks for it.
Singleton {
    id: root

    // One entry per open window: { serial, appId, input }.
    property var windows: []
    property int nextSerial: 1

    function open(appId, input) {
        const id = String(appId ?? "");
        if (id.length === 0)
            return;
        root.windows = root.windows.concat([{
            serial: root.nextSerial,
            appId: id,
            input: String(input ?? "")
        }]);
        root.nextSerial += 1;
    }

    function close(serial) {
        root.windows = root.windows.filter(entry => entry.serial !== serial);
    }

    Instantiator {
        model: root.windows

        delegate: MiniAppWindow {
            required property var modelData

            appId: modelData.appId
            input: modelData.input
            visible: true

            onDismissed: root.close(modelData.serial)
        }
    }
}
