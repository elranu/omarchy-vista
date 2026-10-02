pragma ComponentBehavior: Bound
import "."

import QtQuick
import QtQuick.Layouts

// A toolbar button for the mini apps: the glyph carries the action and the
// tooltip spells it out, since an icon alone is a guess the first time someone
// sees it.
//
// Its own file rather than an inline component of MiniApp.qml, because that file
// declares `pragma ComponentBehavior: Bound`, and Qt refuses to instantiate a
// bound inline component from another file -- which is exactly what every mini
// app would be doing.
Rectangle {
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
