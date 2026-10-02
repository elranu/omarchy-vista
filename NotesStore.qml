pragma Singleton
pragma ComponentBehavior: Bound
import "."

import QtQuick
import Quickshell
import Quickshell.Io
import "Notes.js" as Notes

// The notes on disk: one directory of Markdown files, listed newest first, with
// the directory remembered in Vista's own state file. Quick captures are
// appended to the note for today; editing writes a single file at a time.
//
// Only a bare file name inside the directory is ever written, checked with
// Notes.isSafeFileName, so a note's title can never point the write somewhere
// else on the disk.
Singleton {
    id: root

    readonly property string statePath: `${Directories.stateHome}/notes.json`
    property string directory: Notes.DEFAULT_DIRECTORY
    readonly property string resolvedDirectory: Notes.expandPath(root.directory, Directories.home)
    property var notes: []
    property bool listing: false
    property string error: ""
    // Paths whose contents matched the last content search.
    property var contentMatches: []
    property string contentQuery: ""

    signal captured(string fileName)
    signal saved(string fileName)
    signal created(string path)

    function setDirectory(path) {
        const value = String(path ?? "").trim();
        if (value.length === 0 || value === root.directory)
            return;
        root.directory = value;
        root.notes = [];
        root.persist();
        root.refresh();
    }

    // Listing never creates anything: someone who never opens Notes should not
    // find a new folder in their home directory. The folder is made when a note
    // is actually written, or when the app opens.
    function refresh() {
        if (root.resolvedDirectory.length === 0)
            return;
        root.listing = true;
        listProcess.command = ["bash", "-c",
            `[ -d ${root.quoted(root.resolvedDirectory)} ] || exit 0; `
            + `find ${root.quoted(root.resolvedDirectory)} -maxdepth 2 -type f -name '*.md' -printf '%T@\\t%p\\n'`];
        listProcess.running = true;
    }

    // Called when the app opens: makes the folder and lists it in one shell
    // call, so by the time the panel is on screen a write has somewhere to go.
    function prepare() {
        if (root.resolvedDirectory.length === 0)
            return;
        root.listing = true;
        listProcess.command = ["bash", "-c",
            `mkdir -p ${root.quoted(root.resolvedDirectory)}; `
            + `find ${root.quoted(root.resolvedDirectory)} -maxdepth 2 -type f -name '*.md' -printf '%T@\\t%p\\n'`];
        listProcess.running = true;
    }

    // Single quotes around a path, with any embedded quote closed and reopened:
    // the directory comes from the user's own setting and can hold spaces.
    function quoted(path) {
        return `'${String(path ?? "").replace(/'/g, "'\\''")}'`;
    }

    function pathFor(fileName) {
        return `${root.resolvedDirectory}/${fileName}`;
    }

    function noteFor(fileName) {
        return root.notes.find(note => note.name === fileName) ?? null;
    }

    // Quick capture: read today's note, append one bullet, write it back. The
    // read is synchronous on purpose -- appending to a stale copy would drop
    // whatever was captured in between.
    function capture(text) {
        const body = String(text ?? "");
        if (body.trim().length === 0)
            return false;
        const name = Notes.dailyName(new Date());
        if (!Notes.isSafeFileName(name))
            return false;
        writeFile.path = root.pathFor(name);
        writeFile.reload();
        writeFile.waitForJob();
        const existing = writeFile.loaded ? writeFile.text() : "";
        writeFile.setText(Notes.appendCapture(existing, body, new Date()));
        writeFile.waitForJob();
        root.captured(name);
        root.refresh();
        return true;
    }

    function save(fileName, content) {
        if (!Notes.isSafeFileName(fileName)) {
            root.error = `Refused to write ${fileName}`;
            return false;
        }
        writeFile.path = root.pathFor(fileName);
        writeFile.setText(String(content ?? ""));
        writeFile.waitForJob();
        root.saved(fileName);
        root.refresh();
        return true;
    }

    function create(title) {
        const name = Notes.fileNameFor(title, new Date());
        if (!Notes.isSafeFileName(name)) {
            root.error = `Refused to create ${name}`;
            return "";
        }
        writeFile.path = root.pathFor(name);
        writeFile.setText(Notes.newNoteContent(title, new Date()));
        writeFile.waitForJob();
        root.created(name);
        root.refresh();
        return name;
    }

    // Content search, only for queries long enough to be worth reading every
    // file for. Names are filtered in Notes.filterNotes without touching disk.
    function searchContents(query) {
        const needle = String(query ?? "").trim();
        root.contentQuery = needle;
        if (needle.length < 3) {
            root.contentMatches = [];
            return;
        }
        grepProcess.running = false;
        grepProcess.command = ["grep", "-ril", "--include=*.md", "--", needle, root.resolvedDirectory];
        grepProcess.running = true;
    }

    function persist() {
        stateFile.setText(JSON.stringify({ version: 1, directory: root.directory }, null, 2) + "\n");
    }

    function parseState(text) {
        const raw = String(text ?? "").trim();
        if (raw.length === 0)
            return;
        try {
            const parsed = JSON.parse(raw);
            const directory = String(parsed?.directory ?? "").trim();
            if (directory.length > 0)
                root.directory = directory;
        } catch (e) {
            console.warn("[NotesStore] Failed to parse saved settings:", e);
        }
    }

    property Process listProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.notes = Notes.parseListing(this.text, root.resolvedDirectory);
                root.listing = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    root.error = this.text.trim();
            }
        }
    }

    property Process grepProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.contentMatches = this.text.split("\n").filter(line => line.length > 0);
            }
        }
    }

    // One view, repointed per operation: notes are read and written one at a
    // time, and keeping a view per file would mean a watcher per note.
    property FileView writeFile: FileView {
        atomicWrites: true
        printErrors: false
    }

    property FileView stateFile: FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: root.parseState(stateFile.text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[NotesStore] Failed to load settings:", error);
        }
    }

    Component.onCompleted: root.refresh()
}
