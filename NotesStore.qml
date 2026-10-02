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
    property int noteTotal: 0
    property bool listing: false
    // The saved folder is read asynchronously. Until it is in hand, listing the
    // default folder would show the wrong notes and create a folder the user
    // never asked for, so work waits here.
    property bool settingsReady: false
    property bool preparePending: false
    property string error: ""
    // Paths whose contents matched the last content search.
    property var contentMatches: []
    property string contentQuery: ""

    // Set by the file view when a write fails, read right after waitForJob.
    property bool writeFailed: false

    // Every refusal and failure goes through here, so the panel can show it:
    // a failed write that only sets a property nobody reads is the same as a
    // silent one.
    function fail(message) {
        root.error = String(message ?? "");
        console.warn("[NotesStore]", root.error);
    }

    function clearError() {
        root.error = "";
    }

    // Writes a note and confirms it. The read-back is the only honest check
    // that the bytes reached the disk before this view is repointed, and the
    // retry covers a write that the view dropped because the previous one was
    // still settling -- which happens when several notes are written in one go.
    function writeNow(path, content) {
        const name = String(path).split("/").pop();
        for (var attempt = 0; attempt < 2; ++attempt) {
            root.writeFailed = false;
            writeFile.path = "";
            writeFile.path = path;
            writeFile.setText(String(content ?? ""));
            writeFile.waitForJob();
            if (!root.writeFailed && root.exists(name)) {
                root.clearError();
                return true;
            }
        }
        return false;
    }

    signal captured(string fileName)
    signal saved(string fileName)
    signal created(string path)
    signal renamed(string from, string to)

    function setDirectory(path) {
        const value = String(path ?? "").trim();
        if (value.length === 0 || value === root.directory)
            return;
        root.directory = value;
        root.notes = [];
        root.noteTotal = 0;
        // Matches from the old folder are paths that no longer exist here.
        root.contentMatches = [];
        root.persist();
        // prepare(), not refresh(): the app is open, and a folder that does
        // not exist yet has to be made before the first capture lands in it.
        root.prepare();
        if (root.contentQuery.length > 0)
            root.searchContents(root.contentQuery);
    }

    // Listing never creates anything: someone who never opens Notes should not
    // find a new folder in their home directory. The folder is made when a note
    // is actually written, or when the app opens.
    function refresh() {
        if (root.resolvedDirectory.length === 0)
            return;
        if (!root.settingsReady)
            return;
        root.listing = true;
        listProcess.command = ["bash", "-c",
            `[ -d ${root.quoted(root.resolvedDirectory)} ] || exit 0; `
            + `find ${root.quoted(root.resolvedDirectory)} -maxdepth 1 -type f -name '*.md' -printf '%T@\\t%p\\n'`];
        listProcess.running = true;
    }

    // Called when the app opens: makes the folder and lists it in one shell
    // call, so by the time the panel is on screen a write has somewhere to go.
    function prepare() {
        if (root.resolvedDirectory.length === 0)
            return;
        if (!root.settingsReady) {
            root.preparePending = true;
            return;
        }
        root.listing = true;
        listProcess.command = ["bash", "-c",
            `mkdir -p ${root.quoted(root.resolvedDirectory)}; `
            + `find ${root.quoted(root.resolvedDirectory)} -maxdepth 1 -type f -name '*.md' -printf '%T@\\t%p\\n'`];
        listProcess.running = true;
    }

    // Single quotes around a path, with any embedded quote closed and reopened:
    // the directory comes from the user's own setting and can hold spaces.
    function quoted(path) {
        return `'${String(path ?? "").replace(/'/g, "'\\''")}'`;
    }

    // One pass over the folder for each note's first heading, stopping at the
    // first match in each file rather than reading it whole.
    function readHeadings() {
        if (root.resolvedDirectory.length === 0)
            return;
        headingProcess.running = false;
        headingProcess.command = ["bash", "-c",
            `find ${root.quoted(root.resolvedDirectory)} -maxdepth 1 -type f -name '*.md' -print0 `
            + `| xargs -0 -r awk '/^#+[ \\t]/ { print FILENAME "\\t" $0; nextfile }'`];
        headingProcess.running = true;
    }

    // Does this note already exist? Asked of the disk, not of the cached
    // listing: the listing arrives asynchronously, so two notes created one
    // after another both looked free and the second overwrote the first.
    function exists(fileName) {
        // Cleared first: a view asked for the path it already holds keeps the
        // answer it cached, so two notes created in a row both looked free and
        // the second wrote over the first.
        readFile.path = "";
        readFile.path = root.pathFor(fileName);
        readFile.waitForJob();
        return readFile.loaded;
    }

    // The given name, or the same with a number appended until it is free.
    function freeName(fileName) {
        if (fileName.length === 0)
            return "";
        if (!root.exists(fileName))
            return fileName;
        const bare = String(fileName).replace(/\.md$/i, "");
        for (var n = 2; n < 100; ++n) {
            const candidate = `${bare}-${n}.md`;
            if (!root.exists(candidate))
                return candidate;
        }
        return "";
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
        // One timestamp for both: taking it twice could name the file after
        // yesterday and stamp the line with today across midnight.
        const now = new Date();
        const name = Notes.dailyName(now);
        if (!Notes.isSafeFileName(name))
            return false;
        writeFile.path = root.pathFor(name);
        writeFile.reload();
        writeFile.waitForJob();
        const existing = writeFile.loaded ? writeFile.text() : "";
        if (!root.writeNow(root.pathFor(name), Notes.appendCapture(existing, body, now))) {
            root.fail(`Could not write ${name}`);
            return false;
        }
        root.captured(name);
        root.refresh();
        return true;
    }

    function save(fileName, content) {
        if (!Notes.isSafeFileName(fileName)) {
            root.fail(`Refused to write ${fileName}`);
            return false;
        }
        if (!root.writeNow(root.pathFor(fileName), content)) {
            root.fail(`Could not write ${fileName}`);
            return false;
        }
        root.saved(fileName);
        root.refresh();
        return true;
    }

    // Keeps an edit whose note changed on disk while it was open, without
    // touching the note itself.
    function saveConflictCopy(fileName, content) {
        const name = root.freeName(Notes.conflictName(fileName, new Date()));
        if (name.length === 0 || !Notes.isSafeFileName(name)) {
            root.fail(`Could not keep a copy of ${fileName}`);
            return "";
        }
        if (!root.writeNow(root.pathFor(name), content)) {
            root.fail(`Could not keep a copy of ${fileName}`);
            return "";
        }
        root.refresh();
        return name;
    }

    function create(title) {
        const now = new Date();
        // The same title twice, or two untitled notes inside one second, would
        // otherwise write straight over the first one.
        const name = root.freeName(Notes.fileNameFor(title, now));
        if (name.length === 0 || !Notes.isSafeFileName(name)) {
            root.fail(`Refused to create ${name}`);
            return "";
        }
        if (!root.writeNow(root.pathFor(name), Notes.newNoteContent(title, now))) {
            root.fail(`Could not create ${name}`);
            return "";
        }
        root.created(name);
        root.refresh();
        return name;
    }

    // Content search, only for queries long enough to be worth reading every
    // file for. Names are filtered in Notes.filterNotes without touching disk.
    // Renaming copies the note to its new name and only then removes the old
    // file. The copy is a synchronous, read-back-confirmed write, so by the time
    // this returns the note exists under its new name and nothing can still
    // point at the old one: an asynchronous `mv` left a window in which a quick
    // Ctrl+S, a note switch or closing the panel wrote the old name again,
    // leaving both files behind. Only the removal is asynchronous, and it runs
    // after the copy is known to be on disk.
    //
    // The new name is slugified like a new note's title and moved off any name
    // that is taken, so a rename can never overwrite another note.
    function rename(fileName, input) {
        const wanted = Notes.renameTarget(input);
        if (wanted === fileName)
            return fileName;
        const target = root.freeName(wanted);
        if (target.length === 0 || !Notes.isSafeFileName(fileName) || !Notes.isSafeFileName(target)) {
            root.fail(`Refused to rename ${fileName}`);
            return "";
        }
        if (!root.exists(fileName)) {
            root.fail(`${fileName} is no longer on disk`);
            return "";
        }
        const content = readFile.text();
        if (!root.writeNow(root.pathFor(target), content)) {
            root.fail(`Could not rename ${fileName}`);
            return "";
        }
        removeProcess.command = ["rm", "-f", "--", root.pathFor(fileName)];
        removeProcess.running = true;
        root.renamed(fileName, target);
        return target;
    }

    function searchContents(query) {
        const needle = String(query ?? "").trim();
        root.contentQuery = needle;
        if (needle.length < 3) {
            // Stop first: a grep still running would finish later and put
            // content-only matches back under a one or two letter query.
            grepProcess.running = false;
            root.contentMatches = [];
            return;
        }
        grepProcess.running = false;
        grepProcess.command = ["bash", "-c",
            `find ${root.quoted(root.resolvedDirectory)} -maxdepth 1 -type f -name '*.md' -print0 `
            + `| xargs -0 -r grep -ril -- ${root.quoted(needle)}`];
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
                root.noteTotal = Notes.listingTotal(this.text);
                root.listing = false;
                root.readHeadings();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    root.fail(this.text.trim());
            }
        }
    }

    property Process headingProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.notes = Notes.applyHeadings(root.notes, this.text, root.resolvedDirectory);
            }
        }
    }

    property Process removeProcess: Process {
        onExited: root.refresh()
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
    // Read-only, kept apart from writeFile so an existence check never disturbs
    // a write in progress.
    property FileView readFile: FileView {
        // Synchronous, so an existence check answers before the next line runs.
        blockLoading: true
        printErrors: false
    }

    property FileView writeFile: FileView {
        // Synchronous: several notes written in one go -- a capture, a create,
        // a save -- each have to be on disk before the next one repoints this
        // view, otherwise the earlier write is dropped.
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => {
            root.writeFailed = true;
            console.warn("[NotesStore] Write failed:", error);
        }
    }

    property FileView stateFile: FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: {
            root.parseState(stateFile.text());
            root.settingsLoaded();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[NotesStore] Failed to load settings:", error);
            root.settingsLoaded();
        }
    }

    // If the settings file never reports either way, the app would wait forever
    // with an empty list; after a moment the default folder is good enough.
    property Timer settingsFallback: Timer {
        running: true
        interval: 1500
        onTriggered: {
            if (!root.settingsReady)
                root.settingsLoaded();
        }
    }

    function settingsLoaded() {
        if (root.settingsReady)
            return;
        root.settingsReady = true;
        if (root.preparePending) {
            root.preparePending = false;
            root.prepare();
        } else {
            root.refresh();
        }
    }
}
