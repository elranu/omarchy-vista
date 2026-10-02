pragma ComponentBehavior: Bound
import "."

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "Notes.js" as Notes

// Notes mini app: a capture box that always writes to today's note, the list of
// notes next to it, and an editor for the one that is selected.
//
// Capturing never touches what is already in the file -- the bullet is appended
// -- while the editor does rewrite the note it has open, which is why it only
// saves on Ctrl+S or the Save button and tells you when the file changed
// underneath.
MiniApp {
    id: root

    property string selectedName: ""
    property string editorText: ""
    property string loadedText: ""
    property string query: ""
    // The note was rewritten on disk while it was being edited here.
    property bool externalChange: false
    property bool renaming: false
    readonly property bool dirty: root.selectedName.length > 0 && root.editorText !== root.loadedText
    readonly property var visibleNotes:
        Notes.filterNotes(NotesStore.notes, root.query, NotesStore.contentMatches)

    title: "Notes"
    subtitle: `Quick capture goes to ${Notes.dailyName(new Date())}`
    icon: "note"
    contentWidth: 980
    contentHeight: 680
    widthShare: 0.74
    heightShare: 0.82
    hints: [
        { key: "Ctrl ⏎", label: "Capture" },
        { key: "Ctrl S", label: "Save" },
        { key: "Ctrl N", label: "New" },
        { key: "Ctrl F", label: "Search" },
        { key: "F2", label: "Rename" }
    ]

    signal captured(string message)

    function capture() {
        const text = captureField.text;
        if (text.trim().length === 0)
            return;
        if (NotesStore.capture(text)) {
            captureField.text = "";
            root.captured(`Captured to ${Notes.dailyName(new Date())}`);
        }
    }

    function select(name) {
        if (root.dirty && name !== root.selectedName)
            root.save();
        root.selectedName = name;
        root.loadedText = "";
        root.editorText = "";
        root.externalChange = false;
        root.renaming = false;
        noteFile.path = name.length > 0 ? NotesStore.pathFor(name) : "";
        noteFile.reload();
        if (name.length > 0)
            Qt.callLater(() => editor.forceActiveFocus());
    }

    function save() {
        if (!root.dirty)
            return;
        if (NotesStore.save(root.selectedName, root.editorText)) {
            root.loadedText = root.editorText;
            root.externalChange = false;
        }
    }

    function startRename() {
        if (root.selectedName.length === 0)
            return;
        root.renaming = true;
        renameField.text = root.selectedName;
        Qt.callLater(() => {
            renameField.forceActiveFocus();
            renameField.selectAll();
        });
    }

    function commitRename() {
        if (!root.renaming)
            return;
        root.renaming = false;
        // The editor keeps the text it has; the file view is only repointed once
        // the move has actually happened, in onRenamed below. Pointing it at the
        // new name straight away raced the mv and emptied the editor.
        NotesStore.rename(root.selectedName, renameField.text);
        editor.forceActiveFocus();
    }

    function createNote() {
        const name = NotesStore.create(newNoteField.text);
        if (name.length === 0)
            return;
        newNoteField.text = "";
        root.select(name);
        editor.forceActiveFocus();
    }

    // Keys that reach the frame rather than a focused text field: the Overview
    // forwards them here while this app is open.
    function handleKey(event) {
        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            filterField.forceActiveFocus();
            return true;
        }
        if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
            newNoteField.forceActiveFocus();
            return true;
        }
        if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            root.save();
            return true;
        }
        if (event.key === Qt.Key_F2
            || (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier))) {
            root.startRename();
            return true;
        }
        if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            return true;
        }
        return false;
    }

    Component.onCompleted: {
        // Makes the notes folder if it is not there yet, then lists it.
        NotesStore.prepare();
        Qt.callLater(() => captureField.forceActiveFocus());
    }

    // Saving on the way out: closing the panel with unsaved text in the editor
    // would otherwise throw it away without asking.
    Component.onDestruction: root.save()

    // Escape or the Close keycap: the editor's text is written before the panel
    // goes away, so closing never silently drops an edit.
    onCloseRequested: root.save()


    Connections {
        target: NotesStore

        function onRenamed(from, to) {
            if (from !== root.selectedName)
                return;
            root.selectedName = to;
            noteFile.path = NotesStore.pathFor(to);
        }
    }

    FileView {
        id: noteFile
        printErrors: false
        watchChanges: true
        onLoaded: {
            // Whether an edit is in progress has to be read *before* loadedText
            // is replaced: dirty compares the editor against the text last
            // loaded, so updating it first made a freshly selected note look
            // like an unsaved edit and the editor stayed empty.
            const keepEdit = root.dirty;
            const text = noteFile.text();
            root.loadedText = text;
            if (keepEdit)
                root.externalChange = true;
            else
                root.editorText = text;
        }
        onFileChanged: noteFile.reload()
        // A read that fails leaves the editor alone: the note may simply have
        // been moved a moment ago, and clearing would throw away text the user
        // can still save. select() is what empties the editor.
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[NotesApp] Could not read the note:", error);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Quick capture. Always writes to today's note, whatever is selected in
        // the list, so writing something down is never a navigation task.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 86
            radius: 8
            color: TuiStyle.surfaceSubtle
            border.width: 1
            border.color: captureField.activeFocus ? TuiStyle.accent : TuiStyle.inactiveBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextArea {
                        id: captureField
                        placeholderText: "Write it down; Ctrl+Enter files it under today"
                        color: TuiStyle.fg
                        placeholderTextColor: TuiStyle.dim
                        font.pixelSize: 14
                        wrapMode: TextEdit.Wrap
                        background: null
                        selectByMouse: true

                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && (event.modifiers & Qt.ControlModifier)) {
                                root.capture();
                                event.accepted = true;
                            }
                        }
                    }
                }

                NotesButton {
                    label: "Capture"
                    primary: true
                    enabled: captureField.text.trim().length > 0
                    onActivated: root.capture()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // The list: newest first, filtered by name as you type and by
            // contents once the query is worth reading every file for.
            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 6
                    color: TuiStyle.surfaceSubtle
                    border.width: 1
                    border.color: filterField.activeFocus ? TuiStyle.accent : TuiStyle.inactiveBorder

                    TextInput {
                        id: filterField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: TuiStyle.fg
                        font.pixelSize: 13
                        selectByMouse: true
                        onTextChanged: {
                            root.query = text;
                            NotesStore.searchContents(text);
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: filterField.text.length === 0
                            text: "Search notes"
                            color: TuiStyle.dim
                            font.pixelSize: 13
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.visibleNotes

                    delegate: Rectangle {
                        id: row
                        required property var modelData

                        readonly property bool selected: row.modelData.name === root.selectedName

                        width: list.width
                        height: 48
                        radius: 6
                        color: row.selected ? TuiStyle.selection
                            : (rowMouse.containsMouse ? TuiStyle.surfaceHover : "transparent")

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                color: TuiStyle.fg
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                color: TuiStyle.dim
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.select(row.modelData.name)
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.visibleNotes.length === 0
                        text: NotesStore.listing ? "Reading…"
                            : (root.query.length > 0 ? "Nothing matches" : "No notes yet")
                        color: TuiStyle.dim
                        font.pixelSize: 13
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 6
                        color: TuiStyle.surfaceSubtle
                        border.width: 1
                        border.color: newNoteField.activeFocus ? TuiStyle.accent : TuiStyle.inactiveBorder

                        TextInput {
                            id: newNoteField
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: TuiStyle.fg
                            font.pixelSize: 12
                            selectByMouse: true
                            onAccepted: root.createNote()

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: newNoteField.text.length === 0
                                text: "New note title"
                                color: TuiStyle.dim
                                font.pixelSize: 12
                            }
                        }
                    }

                    NotesButton {
                        label: "New"
                        onActivated: root.createNote()
                    }
                }
            }

            // The editor for the selected note.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.renaming
                        text: root.selectedName.length > 0
                            ? `${root.selectedName}${root.dirty ? " ·  unsaved" : ""}`
                            : "Pick a note, or write one above"
                        color: root.dirty ? TuiStyle.accent : TuiStyle.dim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    // The name turns into a field in place, so renaming is the
                    // same gesture as reading the name.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        visible: root.renaming
                        radius: 6
                        color: TuiStyle.surfaceSubtle
                        border.width: 1
                        border.color: TuiStyle.accent

                        TextInput {
                            id: renameField
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: TuiStyle.fg
                            font.pixelSize: 12
                            selectByMouse: true
                            onAccepted: root.commitRename()

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root.renaming = false;
                                    editor.forceActiveFocus();
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    NotesButton {
                        label: root.renaming ? "Apply" : "Rename"
                        enabled: root.selectedName.length > 0
                        onActivated: root.renaming ? root.commitRename() : root.startRename()
                    }

                    NotesButton {
                        label: "Save"
                        primary: true
                        enabled: root.dirty
                        onActivated: root.save()
                    }
                }

                // The note changed on disk while it was open here. Saving would
                // overwrite that version, so the choice is spelled out instead
                // of being made silently.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    visible: root.externalChange
                    radius: 6
                    color: TuiStyle.surfaceRaised
                    border.width: 1
                    border.color: TuiStyle.accent

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: "This note changed on disk while you were editing it."
                            color: TuiStyle.fg
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        NotesButton {
                            label: "Reload"
                            onActivated: {
                                root.editorText = root.loadedText;
                                root.externalChange = false;
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: TuiStyle.surfaceSubtle
                    border.width: 1
                    border.color: editor.activeFocus ? TuiStyle.accent : TuiStyle.inactiveBorder

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 10

                        TextArea {
                            id: editor
                            enabled: root.selectedName.length > 0
                            text: root.editorText
                            onTextChanged: root.editorText = text
                            color: TuiStyle.fg
                            font.pixelSize: 13
                            font.family: "monospace"
                            wrapMode: TextEdit.Wrap
                            background: null
                            selectByMouse: true

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                                    root.save();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `Folder: ${NotesStore.directory}`
                    color: TuiStyle.dim
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }
            }
        }
    }

    component NotesButton: Rectangle {
        id: button

        property string label: ""
        property bool primary: false

        signal activated()

        implicitWidth: buttonLabel.implicitWidth + 22
        implicitHeight: 30
        radius: 6
        color: !button.enabled ? "transparent"
            : (buttonMouse.containsMouse ? TuiStyle.surfaceHover : TuiStyle.surfaceRaised)
        border.width: 1
        border.color: button.primary && button.enabled ? TuiStyle.accent : TuiStyle.inactiveBorder
        opacity: button.enabled ? 1 : 0.45

        StyledText {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            color: button.primary && button.enabled ? TuiStyle.accent : TuiStyle.fg
            font.pixelSize: 12
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }
}
