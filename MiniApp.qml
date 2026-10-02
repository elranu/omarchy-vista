pragma ComponentBehavior: Bound
import "."

import QtQuick
import QtQuick.Layouts

// Shared frame for Overview mini apps: a centred panel over the workspace grid
// with a title bar, a content area and a footer of key hints. A mini app only
// declares its own content and hints; the frame owns the dimmed backdrop, the
// sizing and Escape.
//
// The frame does not take keyboard focus itself. Overview.qml routes keys to
// the open mini app, so each app handles its own keys and this one stays a
// plain visual container.
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property string icon: "apps"
    // A mini app is a window, not a tooltip: it takes a share of the Overview
    // and only falls back to its own preferred size on a screen too small for
    // that share. contentWidth/contentHeight are the floor, the shares are what
    // the panel grows to, and the margins keep the workspace grid visible
    // around it.
    property real contentWidth: 620
    property real contentHeight: 460
    property real widthShare: 0.62
    property real heightShare: 0.74
    readonly property real sideMargin: 48
    readonly property real verticalMargin: 72
    readonly property real panelWidth:
        Math.min(Math.max(root.contentWidth, root.width * root.widthShare),
                 root.width - 2 * root.sideMargin)
    readonly property real panelHeight:
        Math.min(Math.max(root.contentHeight, root.height * root.heightShare),
                 root.height - 2 * root.verticalMargin)
    // Pairs of { key, label } drawn as keycaps along the bottom.
    property var hints: []
    // Set when the same app is hosted in a real window instead of over the
    // workspace grid: the frame then fills the window, with no backdrop to dim
    // and no panel border, because Hyprland draws the window's own.
    property bool windowed: false

    default property alias content: contentArea.data

    signal closeRequested()
    // Asked for from the title bar or with Ctrl+Enter: the same app, in a window
    // Hyprland puts on a workspace.
    signal popOutRequested()

    anchors.fill: parent

    // Darkens the grid behind the panel and swallows clicks that miss it. In a
    // window there is nothing behind to dim.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        visible: !root.windowed
        enabled: !root.windowed
        onClicked: root.closeRequested()

        Rectangle {
            anchors.fill: parent
            color: TuiStyle.bg
            opacity: 0.55
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: root.windowed ? root.width : root.panelWidth
        height: root.windowed ? root.height : root.panelHeight
        radius: root.windowed ? 0 : 10
        color: TuiStyle.bg
        border.width: root.windowed ? 0 : 1
        border.color: TuiStyle.accent

        // Clicks inside the panel must not reach the backdrop above.
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 9
                    color: TuiStyle.accentWash(TuiStyle.accent)

                    NerdIcon {
                        anchors.centerIn: parent
                        symbol: root.icon
                        iconSize: 20
                        color: TuiStyle.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.title
                        color: TuiStyle.fg
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.subtitle.length > 0
                        text: root.subtitle
                        color: TuiStyle.dim
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                MiniAppKeycap {
                    visible: !root.windowed
                    keyLabel: "Ctrl ⏎"
                    label: "Window"
                    onActivated: root.popOutRequested()
                }

                MiniAppKeycap {
                    keyLabel: "Esc"
                    label: "Close"
                    onActivated: root.closeRequested()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: TuiStyle.inactiveBorder
                opacity: TuiStyle.dividerOpacity
            }

            Item {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.hints.length > 0
                spacing: 8

                Item { Layout.fillWidth: true }

                Repeater {
                    model: root.hints

                    MiniAppKeycap {
                        required property var modelData
                        keyLabel: modelData?.key ?? ""
                        label: modelData?.label ?? ""
                    }
                }
            }
        }
    }

    // Icon buttons for the mini apps' own toolbars. The glyph carries the
    // action and the tooltip spells it out, since an icon alone is a guess the
    // first time someone sees it.
    component IconButton: Rectangle {
        id: iconButton

        property string icon: "apps"
        property string label: ""
        property string tooltip: ""
        property bool primary: false

        signal activated()

        implicitWidth: buttonRow.implicitWidth + 20
        implicitHeight: 30
        radius: 6
        color: !iconButton.enabled ? "transparent"
            : (iconButtonMouse.containsMouse ? TuiStyle.surfaceHover : TuiStyle.surfaceRaised)
        border.width: 1
        border.color: iconButton.primary && iconButton.enabled
            ? TuiStyle.accent : TuiStyle.inactiveBorder
        opacity: iconButton.enabled ? 1 : 0.45

        RowLayout {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 6

            NerdIcon {
                symbol: iconButton.icon
                iconSize: 14
                color: iconButton.primary && iconButton.enabled ? TuiStyle.accent : TuiStyle.fg
            }

            StyledText {
                visible: iconButton.label.length > 0
                text: iconButton.label
                color: iconButton.primary && iconButton.enabled ? TuiStyle.accent : TuiStyle.fg
                font.pixelSize: 12
            }
        }

        MouseArea {
            id: iconButtonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.activated()
        }

        // Drawn above the button and clamped to the panel, so a tooltip on the
        // rightmost button is not cut off by the frame.
        Rectangle {
            id: tip
            visible: iconButtonMouse.containsMouse && iconButton.tooltip.length > 0
            z: 60
            width: tipLabel.implicitWidth + 14
            height: 24
            radius: 5
            color: TuiStyle.bg
            border.width: 1
            border.color: TuiStyle.inactiveBorder
            y: -height - 6
            x: Math.max(-iconButton.x,
                        Math.min((iconButton.width - width) / 2,
                                 (iconButton.parent?.width ?? 0) - iconButton.x - width))

            StyledText {
                id: tipLabel
                anchors.centerIn: parent
                text: iconButton.tooltip
                color: TuiStyle.fg
                font.pixelSize: 11
            }
        }
    }

    component MiniAppKeycap: Rectangle {
        id: cap
        property string keyLabel: ""
        property string label: ""
        signal activated()

        implicitWidth: capRow.implicitWidth + 16
        implicitHeight: 26
        radius: 6
        color: capArea.containsMouse && cap.activated ? TuiStyle.surfaceHover : "transparent"
        border.width: 1
        border.color: TuiStyle.inactiveBorder

        RowLayout {
            id: capRow
            anchors.centerIn: parent
            spacing: 6

            StyledText {
                text: cap.keyLabel
                color: TuiStyle.accent
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            StyledText {
                visible: cap.label.length > 0
                text: cap.label
                color: TuiStyle.dim
                font.pixelSize: 12
            }
        }

        MouseArea {
            id: capArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cap.activated()
        }
    }
}
