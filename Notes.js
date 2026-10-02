// Notes mini app: file naming, listing, searching and the shape of a quick
// capture. Everything here is pure, so the rules that decide what is written to
// disk are unit tested without a running shell.
//
// Notes are plain Markdown files in one directory, which defaults to
// ~/.Vista/Notes and is configurable. A quick capture is appended as one
// timestamped bullet to the note for today, named after the date, so writing
// something down never overwrites what is already there.

var DEFAULT_DIRECTORY = "~/.Vista/Notes";
// A listing of a notes folder is read once per open; this is the ceiling on how
// many notes are kept in memory and drawn in the list.
var LISTING_LIMIT = 500;

function expandPath(path, home) {
    var value = String(path ?? "").trim();
    const base = String(home ?? "");
    if (value === "~")
        value = base;
    else if (value.startsWith("~/"))
        value = `${base}/${value.slice(2)}`;
    while (value.length > 1 && value.endsWith("/"))
        value = value.slice(0, -1);
    return value;
}

// Duck-typed rather than `instanceof Date`: a date handed over from QML, or
// from a test harness running this file in its own context, is a different Date
// constructor and would fail the instance check, silently falling back to now.
function asDate(value) {
    return value && typeof value.getFullYear === "function" ? value : new Date();
}

function two(value) {
    return value < 10 ? `0${value}` : String(value);
}

function dateStamp(date) {
    const when = asDate(date);
    return `${when.getFullYear()}-${two(when.getMonth() + 1)}-${two(when.getDate())}`;
}

function clockStamp(date) {
    const when = asDate(date);
    return `${two(when.getHours())}:${two(when.getMinutes())}`;
}

function dailyName(date) {
    return `${dateStamp(date)}.md`;
}

// A file name of our own making, from a title the user typed. Anything that is
// not a plain character becomes a dash, so a title can never climb out of the
// notes directory or collide with a dotfile.
function slugify(title) {
    const slug = String(title ?? "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 60);
    return slug;
}

function fileNameFor(title, date) {
    const slug = slugify(title);
    if (slug.length > 0)
        return `${slug}.md`;
    // An untitled note still needs a name that sorts and never collides.
    const when = asDate(date);
    return `${dateStamp(when)}-${two(when.getHours())}${two(when.getMinutes())}${two(when.getSeconds())}.md`;
}

// Guards every path that reaches a write: the app only ever writes a bare file
// name inside the notes directory.
function isSafeFileName(name) {
    const value = String(name ?? "");
    if (value.length === 0 || value.length > 120)
        return false;
    if (value.startsWith("."))
        return false;
    if (value.indexOf("/") >= 0 || value.indexOf("\\") >= 0)
        return false;
    if (value.indexOf("..") >= 0)
        return false;
    return /^[A-Za-z0-9 ._-]+\.md$/.test(value);
}

// `find -printf '%T@\t%p\n'`, newest first. A listing is the only way the app
// learns what notes exist, so a malformed line is dropped rather than guessed at.
function parseListing(text, directory) {
    const prefix = `${String(directory ?? "")}/`;
    const out = [];
    const lines = String(text ?? "").split("\n");
    for (var i = 0; i < lines.length; ++i) {
        const line = lines[i];
        if (line.length === 0)
            continue;
        const tab = line.indexOf("\t");
        if (tab <= 0)
            continue;
        const mtime = parseFloat(line.slice(0, tab));
        const path = line.slice(tab + 1);
        if (!isFinite(mtime) || path.length === 0)
            continue;
        const name = path.startsWith(prefix) ? path.slice(prefix.length) : path;
        out.push({
            path: path,
            name: name,
            title: titleFromName(name),
            mtime: mtime
        });
    }
    out.sort((a, b) => (b.mtime - a.mtime) || a.name.localeCompare(b.name));
    return out.slice(0, LISTING_LIMIT);
}

function titleFromName(name) {
    return String(name ?? "").replace(/\.md$/i, "");
}

// The first Markdown heading is a better title than the file name, which for a
// daily note is just a date.
function titleFromContent(text, fallback) {
    const lines = String(text ?? "").split("\n");
    for (var i = 0; i < lines.length; ++i) {
        const match = /^#{1,6}\s+(.+?)\s*$/.exec(lines[i]);
        if (match)
            return match[1];
    }
    return String(fallback ?? "");
}

function snippet(text, limit) {
    const max = typeof limit === "number" ? limit : 90;
    const flat = String(text ?? "")
        .replace(/^#{1,6}\s+.*$/gm, "")
        .replace(/[\s\n]+/g, " ")
        .trim();
    return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
}

// Name matches rank above notes that only matched on their contents, so typing
// the start of a note's name always brings it to the top.
function filterNotes(notes, query, contentMatches) {
    const list = Array.isArray(notes) ? notes : [];
    const needle = String(query ?? "").toLowerCase().trim();
    const matched = {};
    const paths = Array.isArray(contentMatches) ? contentMatches : [];
    for (var i = 0; i < paths.length; ++i)
        matched[paths[i]] = true;
    if (needle.length === 0)
        return list.slice();
    const scored = [];
    for (var j = 0; j < list.length; ++j) {
        const note = list[j];
        const title = String(note.title ?? "").toLowerCase();
        const name = String(note.name ?? "").toLowerCase();
        var rank = -1;
        if (title.startsWith(needle) || name.startsWith(needle))
            rank = 0;
        else if (title.indexOf(needle) >= 0 || name.indexOf(needle) >= 0)
            rank = 1;
        else if (matched[note.path])
            rank = 2;
        if (rank >= 0)
            scored.push({ note: note, rank: rank });
    }
    scored.sort((a, b) => (a.rank - b.rank) || (b.note.mtime - a.note.mtime));
    return scored.map(entry => entry.note);
}

// A capture is appended, never merged into what is there: the existing text is
// returned untouched with one bullet added, and a note created for today gets a
// heading first. Extra lines of a multi-line capture are indented so the whole
// thing stays one bullet.
function appendCapture(content, text, date) {
    const body = String(text ?? "").replace(/\s+$/, "");
    if (body.trim().length === 0)
        return String(content ?? "");
    const lines = body.split("\n");
    var bullet = `- ${clockStamp(date)} ${lines[0].trim()}`;
    for (var i = 1; i < lines.length; ++i)
        bullet += `\n  ${lines[i].trim()}`;
    var existing = String(content ?? "");
    if (existing.trim().length === 0)
        return `# ${dateStamp(date)}\n\n${bullet}\n`;
    if (!existing.endsWith("\n"))
        existing += "\n";
    return `${existing}${bullet}\n`;
}

// A new note starts with its title as a heading, so the list shows the title
// the user typed rather than the slug in the file name.
function newNoteContent(title, date) {
    const heading = String(title ?? "").trim();
    if (heading.length === 0)
        return `# ${dateStamp(date)} ${clockStamp(date)}\n\n`;
    return `# ${heading}\n\n`;
}
