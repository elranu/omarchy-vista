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
    // Set while the editor's file view is moved to a renamed note: that load
    // is the same text under a new name, not a change made somewhere else.
    property bool repointing: false
    // The note the context menu was opened on, and where to draw it.
    property string menuName: ""
    property real menuX: 0
    property real menuY: 0
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
        { key: "F2", label: "Rename" },
        { key: "↑↓", label: "Pick" }
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

    // Moves the selection through the filtered list, so the list is reachable
    // without the mouse: the rows themselves cannot take focus while the search
    // box has it, which is where typing leaves you.
    function step(delta) {
        const notes = root.visibleNotes;
        if (notes.length === 0)
            return;
        var index = notes.findIndex(note => note.name === root.selectedName);
        index = index < 0 ? (delta > 0 ? 0 : notes.length - 1)
                          : Math.max(0, Math.min(notes.length - 1, index + delta));
        root.select(notes[index].name);
        list.currentIndex = index;
    }

    function select(name) {
        if (root.dirty && name !== root.selectedName) {
            root.save();
            // The save was refused and the edit is still unsaved: leaving the
            // note open is better than navigating away from text that only
            // exists in this editor.
            if (root.dirty)
                return;
        }
        root.selectedName = name;
        root.loadedText = "";
        root.editorText = "";
        root.externalChange = false;
        root.renaming = false;
        root.menuName = "";
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

    // Right-click menu. MiniApp routes a subclass's children into its content
    // area, so the menu is positioned in that area's coordinates and clamped to
    // it: this is a plain item, not a popup surface, so a menu past the edge
    // would be clipped rather than flipped by the compositor.
    function openMenu(name, position) {
        root.menuName = name;
        root.menuX = position.x;
        root.menuY = position.y;
    }

    function closeMenu() {
        root.menuName = "";
    }

    // What closing does with unsaved text. Normally it saves. If the note
    // changed on disk while it was open, saving would overwrite that newer
    // version without the user having chosen to, so the edit goes to a conflict
    // copy beside the note instead, and both survive.
    function saveOnLeave() {
        if (!root.dirty)
            return;
        if (root.externalChange) {
            NotesStore.saveConflictCopy(root.selectedName, root.editorText);
            return;
        }
        root.save();
    }

    // Changing folders with an unsaved edit: the edit is saved where it
    // belongs first, and the change is abandoned if that fails, because once
    // the folder moves the same file name would point into the new one.
    function changeFolder(path) {
        if (root.dirty) {
            root.save();
            if (root.dirty)
                return false;
        }
        root.select("");
        NotesStore.setDirectory(path);
        return true;
    }

    function startRename() {
        if (root.selectedName.length === 0)
            return;
        renameField.text = root.selectedName;
        // The field focuses itself once it is visible; see onVisibleChanged.
        root.renaming = true;
        renameField.forceActiveFocus();
    }

    function commitRename() {
        if (!root.renaming)
            return;
        root.renaming = false;
        // The store copies the note and confirms it before returning, then
        // onRenamed below repoints the editor; nothing is left in flight for a
        // quick save or a note switch to race.
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
        if (root.menuName.length > 0 && event.key === Qt.Key_Escape) {
            root.closeMenu();
            return true;
        }
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
        if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown) {
            root.step(1);
            return true;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) {
            root.step(-1);
            return true;
        }
        return false;
    }

    Component.onCompleted: {
        // Makes the notes folder if it is not there yet, then lists it.
        NotesStore.prepare();
    }

    // Called by whoever hosts the app once it is on screen -- the Overview or a
    // window -- so the cursor is in the capture box, ready to type, the moment
    // Notes opens. Asking from Component.onCompleted lost the race: the
    // Overview took the keyboard back right after.
    function focusInitial() {
        captureField.forceActiveFocus();
    }

    // Saving on the way out: closing the panel with unsaved text in the editor
    // would otherwise throw it away without asking.
    Component.onDestruction: root.saveOnLeave()

    // Escape or the Close keycap: the editor's text is written before the panel
    // goes away, so closing never silently drops an edit.
    onCloseRequested: root.saveOnLeave()


    Connections {
        target: NotesStore

        function onRenamed(from, to) {
            if (from !== root.selectedName)
                return;
            root.repointing = true;
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
            if (root.repointing) {
                root.repointing = false;
                if (!keepEdit)
                    root.editorText = text;
                return;
            }
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

                MiniAppIconButton {
                    icon: "capture"
                    tooltip: "File under today (Ctrl+Enter)"
                    primary: true
                    enabled: captureField.text.trim().length > 0
                    onActivated: root.capture()
                }
            }
        }

        // Failures and refusals from the store. Without this they only reached
        // a property nothing displayed, which is the same as failing silently.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            visible: NotesStore.error.length > 0
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
                    text: NotesStore.error
                    color: TuiStyle.fg
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                MiniAppIconButton {
                    icon: "apply"
                    tooltip: "Dismiss"
                    onActivated: NotesStore.clearError()
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

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) {
                                root.step(1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                root.step(-1);
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                       && root.visibleNotes.length > 0) {
                                root.select(root.visibleNotes[0].name);
                                event.accepted = true;
                            }
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
                    currentIndex: root.visibleNotes.findIndex(note => note.name === root.selectedName)
                    highlightMoveDuration: 90
                    // Keeps the keyboard selection on screen.
                    onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)

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
                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    root.openMenu(row.modelData.name,
                                                  rowMouse.mapToItem(contextMenu.parent, mouse.x, mouse.y));
                                else
                                    root.select(row.modelData.name);
                            }
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

                    MiniAppIconButton {
                        icon: "add"
                        tooltip: "New note (Ctrl+N)"
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

                        // forceActiveFocus on an item that is still hidden does
                        // nothing, so the field claims the keyboard the moment it
                        // appears rather than a frame too early. The retry is for
                        // the other half of the problem: the Overview's layer
                        // takes keyboard focus on demand, so the surface may only
                        // get it a frame after the click that opened the menu.
                        onVisibleChanged: {
                            if (visible)
                                renameFocus.restart();
                        }

                        Timer {
                            id: renameFocus
                            interval: 80
                            onTriggered: {
                                renameField.forceActiveFocus();
                                renameField.selectAll();
                            }
                        }

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

                    MiniAppIconButton {
                        icon: "apply"
                        visible: root.renaming
                        tooltip: "Apply the new name (Enter)"
                        onActivated: root.commitRename()
                    }

                    MiniAppIconButton {
                        icon: "save"
                        tooltip: "Save the note (Ctrl+S)"
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

                        MiniAppIconButton {
                            icon: "refresh"
                            tooltip: "Take the version from disk"
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

                // The folder, and the only way to change it: typing a path here
                // is what points Notes at a vault instead of its own directory.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: "Folder"
                        color: TuiStyle.dim
                        font.pixelSize: 10
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        radius: 4
                        color: folderField.activeFocus ? TuiStyle.surfaceSubtle : "transparent"
                        border.width: folderField.activeFocus ? 1 : 0
                        border.color: TuiStyle.accent

                        TextInput {
                            id: folderField
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            verticalAlignment: TextInput.AlignVCenter
                            text: NotesStore.directory
                            color: TuiStyle.dim
                            font.pixelSize: 10
                            selectByMouse: true
                            onAccepted: {
                                if (!root.changeFolder(folderField.text))
                                    folderField.text = NotesStore.directory;
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    folderField.text = NotesStore.directory;
                                    editor.forceActiveFocus();
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    StyledText {
                        // Not a silent truncation: say when older notes are not
                        // in the list.
                        visible: NotesStore.noteTotal > NotesStore.notes.length
                        text: `newest ${NotesStore.notes.length} of ${NotesStore.noteTotal}`
                        color: TuiStyle.dim
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // Dismissed by a click anywhere else, the way a menu is expected to behave.
    MouseArea {
        anchors.fill: parent
        visible: root.menuName.length > 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 50
        onClicked: root.closeMenu()
    }

    Rectangle {
        id: contextMenu
        visible: root.menuName.length > 0
        x: Math.max(0, Math.min(root.menuX, (contextMenu.parent?.width ?? 0) - contextMenu.width))
        y: Math.max(0, Math.min(root.menuY, (contextMenu.parent?.height ?? 0) - contextMenu.height))
        z: 51
        width: 180
        height: menuColumn.implicitHeight + 10
        radius: 8
        color: TuiStyle.bg
        border.width: 1
        border.color: TuiStyle.accent

        ColumnLayout {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 5
            spacing: 2

            MenuRow {
                icon: "open"
                label: "Open"
                onActivated: {
                    root.select(root.menuName);
                    root.closeMenu();
                }
            }

            MenuRow {
                icon: "rename"
                label: "Rename"
                keyHint: "F2"
                onActivated: {
                    const name = root.menuName;
                    root.closeMenu();
                    root.select(name);
                    root.startRename();
                }
            }
        }
    }

    component MenuRow: Rectangle {
        id: menuRow

        property string icon: "apps"
        property string label: ""
        property string keyHint: ""

        signal activated()

        Layout.fillWidth: true
        implicitHeight: 28
        radius: 5
        color: menuRowMouse.containsMouse ? TuiStyle.surfaceHover : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 8

            NerdIcon {
                symbol: menuRow.icon
                iconSize: 12
                color: TuiStyle.dim
            }

            StyledText {
                Layout.fillWidth: true
                text: menuRow.label
                color: TuiStyle.fg
                font.pixelSize: 12
            }

            StyledText {
                text: menuRow.keyHint
                visible: menuRow.keyHint.length > 0
                color: TuiStyle.dim
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: menuRowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menuRow.activated()
        }
    }

}
