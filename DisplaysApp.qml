pragma ComponentBehavior: Bound
import "."

import QtQuick
import QtQuick.Layouts
import Quickshell
import "Displays.js" as Displays

// Displays mini app: every connected monitor as a tile, drawn at the size and
// position Hyprland gives it, and draggable to where the screens stand on the
// desk. Geometry lives in Displays.js; this file is the view and the commands.
//
// Nothing reaches Hyprland until Apply. Apply only sets positions: the mode and
// the scale of each monitor are echoed back exactly as reported, so resolution
// and refresh rate stay with Omarchy's own Display panel and monitors.lua.
MiniApp {
    id: root

    // Tiles as last read from Hyprland, and the edited copy shown on the canvas.
    property var liveTiles: []
    property var tiles: []
    property string selectedKey: ""
    readonly property bool dirty: !Displays.samePositions(root.liveTiles, root.tiles)
    readonly property int tileCount: root.tiles.length

    title: "Displays"
    subtitle: "Drag a screen to where it stands on your desk"
    icon: "monitor"
    contentWidth: 900
    contentHeight: 640
    widthShare: 0.72
    heightShare: 0.78
    hints: [
        { key: "←→↑↓", label: "Move" },
        { key: "1-9", label: "Select" },
        { key: "⏎", label: "Apply" },
        { key: "s", label: "Save" },
        { key: "u", label: "Undo" }
    ]

    function reload() {
        const fresh = Displays.fromMonitors(HyprlandData.monitors);
        root.liveTiles = fresh;
        root.tiles = fresh;
        if (Displays.indexOfKey(fresh, root.selectedKey) < 0)
            root.selectedKey = fresh.length > 0
                ? (fresh.find(tile => tile.focused)?.key ?? fresh[0].key)
                : "";
    }

    function selectIndex(index) {
        if (index >= 0 && index < root.tiles.length)
            root.selectedKey = root.tiles[index].key;
    }

    function drop(key, x, y) {
        root.tiles = Displays.place(root.tiles, key, x, y);
        root.selectedKey = key;
    }

    function nudge(side) {
        if (root.selectedKey.length === 0)
            return;
        root.tiles = Displays.moveToSide(root.tiles, root.selectedKey, side);
    }

    function undo() {
        root.tiles = root.liveTiles;
    }

    // One hyprctl call for the whole layout: applying monitor by monitor would
    // leave Hyprland in an overlapping intermediate state between calls. It goes
    // through `eval`, because Omarchy 4 drives Hyprland with the Lua parser and
    // `hyprctl keyword` refuses to run against it.
    function apply() {
        if (!root.dirty)
            return;
        const rules = root.tiles.map(tile => Displays.monitorRule(tile));
        Quickshell.execDetached(["hyprctl", "eval", rules.join("; ")]);
        root.applied();
    }

    // Keeps this arrangement for exactly these screens and applies it. Saving
    // without applying would leave the saved layout and the session disagreeing.
    function save() {
        DisplayLayouts.save(root.tiles);
        // The confirmation goes out before applying, because applying closes
        // the overview and takes this panel with it.
        root.saved();
        root.apply();
    }

    function forget() {
        DisplayLayouts.forget(Displays.layoutSignature(root.tiles));
    }

    // Puts the monitors back the way the config has them.
    function revert() {
        Quickshell.execDetached(["hyprctl", "reload"]);
        root.applied();
    }

    signal applied()
    signal saved()

    readonly property string signature: Displays.layoutSignature(root.tiles)
    readonly property bool hasSavedLayout: !!DisplayLayouts.layoutFor(root.signature)

    function handleKey(event) {
        const text = String(event.text ?? "");
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.apply();
            return true;
        }
        if (event.key === Qt.Key_Left || text === "h") {
            root.nudge("left");
            return true;
        }
        if (event.key === Qt.Key_Right || text === "l") {
            root.nudge("right");
            return true;
        }
        if (event.key === Qt.Key_Up || text === "k") {
            root.nudge("up");
            return true;
        }
        if (event.key === Qt.Key_Down || text === "j") {
            root.nudge("down");
            return true;
        }
        if (text === "u") {
            root.undo();
            return true;
        }
        if (text === "r") {
            root.revert();
            return true;
        }
        if (text === "s") {
            root.save();
            return true;
        }
        if (text.length === 1 && text >= "1" && text <= "9") {
            root.selectIndex(parseInt(text, 10) - 1);
            return true;
        }
        if (text === "\t" || event.key === Qt.Key_Tab) {
            const at = Displays.indexOfKey(root.tiles, root.selectedKey);
            root.selectIndex((at + 1) % Math.max(1, root.tiles.length));
            return true;
        }
        return false;
    }

    Component.onCompleted: root.reload()

    // Hyprland reports monitors again for focus and metadata changes too, so an
    // edit in progress is only thrown away when the set of screens itself
    // changed: tiles naming a connector that is gone would otherwise be applied
    // or saved for the wrong monitors.
    Connections {
        target: HyprlandData
        function onMonitorsChanged() {
            const live = Displays.fromMonitors(HyprlandData.monitors);
            if (!root.dirty || Displays.layoutSignature(live) !== root.signature) {
                root.reload();
                return;
            }
            // Same screens with an edit in progress: keep where the tiles were
            // dragged to, but take the fresh mode, scale and transform, so Apply
            // cannot send stale values back with the new position.
            root.liveTiles = live;
            root.tiles = Displays.mergeMetadata(root.tiles, live);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // The canvas. Tiles are drawn in logical pixels scaled down to fit, so
        // the picture matches how Hyprland lays the screens out: a 2880x1800
        // panel at scale 1.6 is 1800x1125 wide here, the same number the next
        // monitor's position starts at.
        Rectangle {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: TuiStyle.surfaceSubtle
            border.width: 1
            border.color: TuiStyle.inactiveBorder

            readonly property real padding: 24
            readonly property var box: Displays.boundingBox(root.tiles)
            readonly property real viewScale: box.w > 0 && box.h > 0
                ? Math.min((width - 2 * padding) / box.w, (height - 2 * padding) / box.h)
                : 1
            readonly property real offsetX: (width - box.w * viewScale) / 2
            readonly property real offsetY: (height - box.h * viewScale) / 2

            function toScreenX(logical) { return offsetX + (logical - box.x) * viewScale; }
            function toScreenY(logical) { return offsetY + (logical - box.y) * viewScale; }
            function toLogicalX(screen) { return box.x + (screen - offsetX) / viewScale; }
            function toLogicalY(screen) { return box.y + (screen - offsetY) / viewScale; }

            Repeater {
                model: root.tiles

                Rectangle {
                    id: tile
                    required property var modelData
                    required property int index

                    readonly property bool selected: tile.modelData.key === root.selectedKey
                    readonly property bool dragging: dragArea.drag.active

                    x: canvas.toScreenX(tile.modelData.x)
                    y: canvas.toScreenY(tile.modelData.y)
                    width: tile.modelData.w * canvas.viewScale
                    height: tile.modelData.h * canvas.viewScale
                    radius: 6
                    color: tile.selected ? TuiStyle.selection : TuiStyle.surfaceRaised
                    border.width: tile.selected ? 2 : 1
                    border.color: tile.selected ? TuiStyle.accent
                        : (tile.modelData.focused ? TuiStyle.fg : TuiStyle.inactiveBorder)
                    opacity: tile.dragging ? 0.85 : 1
                    z: tile.selected ? 2 : 1

                    // Snapping decides the final position, so the tile only
                    // animates when it is not under the pointer.
                    Behavior on x {
                        enabled: !tile.dragging
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: !tile.dragging
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        width: parent.width - 16

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${tile.index + 1}`
                            color: TuiStyle.accent
                            font.pixelSize: Math.max(14, Math.min(34, tile.height * 0.22))
                            font.bold: true
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.name
                            color: TuiStyle.fg
                            font.pixelSize: 13
                            font.bold: true
                            visible: tile.height > 70
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${tile.modelData.w} × ${tile.modelData.h}`
                            color: TuiStyle.fg
                            font.pixelSize: 11
                            visible: tile.height > 96
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${tile.modelData.width}×${tile.modelData.height} @ ${tile.modelData.refreshRate.toFixed(0)} Hz · ×${tile.modelData.scale}`
                            color: TuiStyle.dim
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.maximumWidth: tile.width - 16
                            visible: tile.height > 120
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        cursorShape: Qt.OpenHandCursor
                        drag.target: tile
                        drag.threshold: 4
                        onPressed: root.selectedKey = tile.modelData.key
                        onReleased: root.drop(tile.modelData.key,
                                              canvas.toLogicalX(tile.x),
                                              canvas.toLogicalY(tile.y))
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.tileCount === 0
                text: "No monitors reported"
                color: TuiStyle.dim
                font.pixelSize: 14
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.dirty
                        ? "Applying restarts the bar on every screen that moves, so the overview closes."
                        : "Positions match the running session."
                    color: root.dirty ? TuiStyle.fg : TuiStyle.dim
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.hasSavedLayout
                        ? "Saved for these screens; it comes back when they are connected again."
                        : "Save keeps this arrangement for these screens only."
                    color: TuiStyle.dim
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }

            MiniApp.IconButton {
                icon: "undo"
                tooltip: "Undo unapplied changes (u)"
                enabled: root.dirty
                onActivated: root.undo()
            }
            MiniApp.IconButton {
                icon: "refresh"
                tooltip: "Reload the Hyprland config (r)"
                onActivated: root.revert()
            }
            MiniApp.IconButton {
                icon: "forget"
                tooltip: "Forget the layout saved for these screens"
                visible: root.hasSavedLayout
                onActivated: root.forget()
            }
            MiniApp.IconButton {
                icon: "apply"
                tooltip: "Apply to this session (Enter)"
                enabled: root.dirty
                onActivated: root.apply()
            }
            MiniApp.IconButton {
                icon: "save"
                tooltip: "Save for these screens and apply (s)"
                primary: true
                enabled: root.tileCount > 1
                onActivated: root.save()
            }
        }
    }

}
