pragma ComponentBehavior: Bound
import "."

import QtQuick
import QtQuick.Layouts
import Quickshell
import "Calculator.js" as Calculator

// Calculator mini app: a display, a keypad for the mouse, and a history of
// what was already worked out. Typing works too -- Overview.qml forwards keys
// here while a mini app is open.
MiniApp {
    id: root

    // Seeded from the search query when opened from an expression.
    property string expression: ""
    property var history: []

    // Inside the calculator every input is a calculation, so evaluation is
    // forced with "=": a bare number like 81, left over from the previous
    // answer, still shows as a result instead of an unfinished expression.
    readonly property var result: expression.length > 0
        ? Calculator.evaluate(`=${expression}`)
        : null
    readonly property bool hasResult: !!result
    readonly property bool resultIsBareNumber: !!result && result.pretty === result.display

    title: "Calculator"
    subtitle: "Type or click; Enter copies the result"
    icon: "calculator"
    contentWidth: 640
    contentHeight: 600
    widthShare: 0.42
    heightShare: 0.66
    hints: [
        { key: "⏎", label: "Copy" },
        { key: "⌫", label: "Delete" },
        { key: "C", label: "Clear" }
    ]

    signal copied(string value)

    function append(text) {
        root.expression += text;
    }

    function backspace() {
        root.expression = root.expression.slice(0, -1);
    }

    function clear() {
        root.expression = "";
    }

    // Enter keeps the answer: it goes to the clipboard and to the history, and
    // the expression is replaced by the result so it can be built on.
    function commit() {
        if (!root.hasResult)
            return;
        const entry = { pretty: root.result.pretty, display: root.result.display, grouped: root.result.grouped };
        const next = root.history.filter(item => item.pretty !== entry.pretty);
        next.unshift(entry);
        root.history = next.slice(0, 6);
        Quickshell.execDetached(["wl-copy", "--", entry.display]);
        root.copied(entry.display);
        root.expression = entry.display;
    }

    // Returns whether the key was consumed, so Overview.qml knows to stop.
    function handleKey(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commit();
            return true;
        }
        if (event.key === Qt.Key_Backspace) {
            root.backspace();
            return true;
        }
        if (event.key === Qt.Key_Delete) {
            root.clear();
            return true;
        }
        const text = String(event.text ?? "");
        // Same grammar the parser accepts, exponents included, so 1.5e3 can be
        // typed here and not only seeded from search. Incomplete forms such as
        // "1e" simply do not evaluate until they are finished.
        if (text.length === 1 && "0123456789+-*/^%().,x×÷=eE".indexOf(text) >= 0) {
            root.append(text === "=" ? "" : text);
            return true;
        }
        // C clears, but not the "c" of a number being typed... there is none:
        // the branch above already consumed every character the parser knows.
        if (text === "c" || text === "C") {
            root.clear();
            return true;
        }
        return false;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Display
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 104
            radius: 8
            color: TuiStyle.surfaceSubtle
            border.width: 1
            border.color: TuiStyle.inactiveBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    // A bare number needs no echo above itself.
                    text: root.hasResult
                        ? (root.resultIsBareNumber ? " " : root.result.pretty)
                        : (root.expression.length > 0 ? root.expression : " ")
                    color: TuiStyle.dim
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.hasResult
                        ? root.result.grouped
                        : (root.expression.length > 0 ? "…" : "0")
                    color: root.hasResult ? TuiStyle.accent : TuiStyle.dim
                    font.pixelSize: 38
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideLeft
                }
            }
        }

        // Keypad
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 4
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: [
                    { label: "C", action: "clear", tint: true },
                    { label: "(", action: "(" },
                    { label: ")", action: ")" },
                    { label: "⌫", action: "back", tint: true },
                    { label: "7", action: "7" },
                    { label: "8", action: "8" },
                    { label: "9", action: "9" },
                    { label: "÷", action: "/", tint: true },
                    { label: "4", action: "4" },
                    { label: "5", action: "5" },
                    { label: "6", action: "6" },
                    { label: "×", action: "*", tint: true },
                    { label: "1", action: "1" },
                    { label: "2", action: "2" },
                    { label: "3", action: "3" },
                    { label: "−", action: "-", tint: true },
                    { label: "0", action: "0" },
                    { label: ".", action: "." },
                    { label: "%", action: "%", tint: true },
                    { label: "+", action: "+", tint: true }
                ]

                KeypadButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: modelData.label
                    tinted: modelData.tint === true
                    onActivated: {
                        if (modelData.action === "clear")
                            root.clear();
                        else if (modelData.action === "back")
                            root.backspace();
                        else
                            root.append(modelData.action);
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                visible: root.history.length === 0
                text: "History appears here once you press Enter"
                color: TuiStyle.dim
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Repeater {
                model: root.history.slice(0, 3)

                Rectangle {
                    id: entry
                    required property var modelData
                    Layout.preferredHeight: 30
                    implicitWidth: entryRow.implicitWidth + 18
                    radius: 6
                    color: entryArea.containsMouse ? TuiStyle.surfaceHover : TuiStyle.surfaceSubtle

                    RowLayout {
                        id: entryRow
                        anchors.centerIn: parent
                        spacing: 6

                        StyledText {
                            Layout.maximumWidth: 110
                            text: entry.modelData.pretty
                            color: TuiStyle.dim
                            font.pixelSize: 11
                            elide: Text.ElideLeft
                        }

                        StyledText {
                            text: `= ${entry.modelData.grouped}`
                            color: TuiStyle.fg
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: entryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Reuse an earlier answer as the start of a new sum.
                        onClicked: root.expression = entry.modelData.display
                    }
                }
            }

            Rectangle {
                Layout.preferredHeight: 34
                implicitWidth: copyRow.implicitWidth + 24
                radius: 7
                color: copyArea.containsMouse ? TuiStyle.accent : TuiStyle.accentWash(TuiStyle.accent)
                opacity: root.hasResult ? 1 : 0.45

                RowLayout {
                    id: copyRow
                    anchors.centerIn: parent
                    spacing: 7

                    StyledText {
                        text: "⏎"
                        color: copyArea.containsMouse ? TuiStyle.bg : TuiStyle.accent
                        font.pixelSize: 13
                    }

                    StyledText {
                        text: "Copy"
                        color: copyArea.containsMouse ? TuiStyle.bg : TuiStyle.accent
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: copyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.hasResult
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.commit()
                }
            }
        }
    }

    component KeypadButton: Rectangle {
        id: button
        property string label: ""
        property bool tinted: false
        signal activated()

        radius: 8
        color: buttonArea.pressed
            ? TuiStyle.surfacePressed
            : buttonArea.containsMouse
                ? TuiStyle.surfaceHover
                : (button.tinted ? TuiStyle.accentWash(TuiStyle.accent) : TuiStyle.surfaceSubtle)

        StyledText {
            anchors.centerIn: parent
            text: button.label
            color: button.tinted ? TuiStyle.accent : TuiStyle.fg
            font.pixelSize: 18
            font.weight: button.tinted ? Font.DemiBold : Font.Normal
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }
}
