import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "."

// The "Opening <app>" card LaunchTracker shows while a launched app starts.
// Omarchy's OSD card only takes a glyph, so this one is drawn by Vista with
// the same shape, place and colours, and the app's own icon. It sits on the
// monitor the app was launched from and never takes input.
Scope {
    id: root

    // { name, icon, monitorName } or null.
    property var notice: null
    property var lastNotice: null
    readonly property bool shown: root.notice !== null

    onNoticeChanged: {
        if (root.notice)
            root.lastNotice = root.notice;
    }

    readonly property int pad: Style.space(16)
    readonly property int gap: Math.round(Style.space(16) * 2 / 3)
    readonly property int iconSize: Style.font.displayLarge
    readonly property int maxMessageWidth: Style.space(190)
    readonly property string message: `Opening ${root.lastNotice?.name ?? ""}`.trim()

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(s => s.name === root.lastNotice?.monitorName) ?? null
        visible: card.opacity > 0
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "vista-launch-notice"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        BorderSurface {
            id: card
            width: card.borderLeft + root.pad + root.iconSize + root.gap + messageText.width + root.pad + card.borderRight
            height: card.borderTop + root.pad + root.iconSize + root.pad + card.borderBottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(67)
            color: Util.alpha(Color.background, 0.97)
            borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
            radius: Style.cornerRadius
            opacity: root.shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Row {
                anchors.fill: parent
                anchors.topMargin: card.borderTop + root.pad
                anchors.rightMargin: card.borderRight + root.pad
                anchors.bottomMargin: card.borderBottom + root.pad
                anchors.leftMargin: card.borderLeft + root.pad
                spacing: root.gap

                Item {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter

                    StyledImage {
                        id: appIcon
                        anchors.fill: parent
                        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                        source: root.lastNotice?.icon ?? ""
                        visible: status === Image.Ready
                        // A slow start is still a start: the icon breathes
                        // while the card waits for the window.
                        SequentialAnimation on opacity {
                            running: root.shown
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }

                    // No icon to show: the rocket from the Nerd Font set.
                    Text {
                        anchors.centerIn: parent
                        visible: !appIcon.visible
                        textFormat: Text.PlainText
                        text: ""
                        font.family: Style.font.family
                        font.pixelSize: root.iconSize
                        color: Color.popups.text
                    }
                }

                Text {
                    id: messageText
                    width: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.message
                    font: messageMetrics.font
                    color: Color.popups.text
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    TextMetrics {
        id: messageMetrics
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Style.font.title
        text: root.message
    }
}
