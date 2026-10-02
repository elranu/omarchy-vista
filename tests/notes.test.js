const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../Notes.js'), 'utf8'), context);
const {
    DEFAULT_DIRECTORY, expandPath, dateStamp, clockStamp, dailyName, slugify,
    fileNameFor, isSafeFileName, parseListing, titleFromName, titleFromContent,
    snippet, filterNotes, appendCapture, newNoteContent
} = context;

const AT = new Date(2026, 9, 2, 14, 32, 5);
const names = notes => notes.map(note => note.name).join(',');

test('the default directory is under the home directory and ~ expands', () => {
    assert.equal(DEFAULT_DIRECTORY, '~/.Vista/Notes');
    assert.equal(expandPath('~/.Vista/Notes', '/home/ranu'), '/home/ranu/.Vista/Notes');
    assert.equal(expandPath('~', '/home/ranu'), '/home/ranu');
    assert.equal(expandPath('/srv/notes/', '/home/ranu'), '/srv/notes');
    assert.equal(expandPath('  ~/Notes  ', '/home/ranu'), '/home/ranu/Notes');
});

test('a date and a time are stamped with two digits', () => {
    assert.equal(dateStamp(AT), '2026-10-02');
    assert.equal(clockStamp(AT), '14:32');
    assert.equal(dailyName(AT), '2026-10-02.md');
    assert.equal(clockStamp(new Date(2026, 0, 5, 9, 7)), '09:07');
});

test('a title becomes a plain file name that cannot leave the folder', () => {
    assert.equal(slugify('Reunión con Daniele'), 'reuni-n-con-daniele');
    assert.equal(fileNameFor('Ideas / proyecto', AT), 'ideas-proyecto.md');
    assert.equal(fileNameFor('../../etc/passwd', AT), 'etc-passwd.md');
    assert.equal(fileNameFor('', AT), '2026-10-02-143205.md');
    assert.equal(fileNameFor('   ', AT), '2026-10-02-143205.md');
});

test('only a plain file name inside the folder is accepted for writing', () => {
    assert.equal(isSafeFileName('nota.md'), true);
    assert.equal(isSafeFileName('2026-10-02.md'), true);
    assert.equal(isSafeFileName('con espacio.md'), true);
    assert.equal(isSafeFileName('../fuera.md'), false);
    assert.equal(isSafeFileName('sub/nota.md'), false);
    assert.equal(isSafeFileName('.oculta.md'), false);
    assert.equal(isSafeFileName('nota.txt'), false);
    assert.equal(isSafeFileName(''), false);
});

test('a listing comes back newest first, and junk lines are dropped', () => {
    const listing = [
        '1759300000.0\t/home/ranu/.Vista/Notes/ideas.md',
        '1759400000.5\t/home/ranu/.Vista/Notes/2026-10-02.md',
        'not a listing line',
        '\t/home/ranu/.Vista/Notes/empty-mtime.md',
        ''
    ].join('\n');
    const notes = parseListing(listing, '/home/ranu/.Vista/Notes');
    assert.equal(names(notes), '2026-10-02.md,ideas.md');
    assert.equal(notes[0].path, '/home/ranu/.Vista/Notes/2026-10-02.md');
    assert.equal(notes[0].title, '2026-10-02');
});

test('the first heading is the title, the file name is the fallback', () => {
    assert.equal(titleFromName('ideas-proyecto.md'), 'ideas-proyecto');
    assert.equal(titleFromContent('## Reunión con Daniele\n\ntexto', 'x'), 'Reunión con Daniele');
    assert.equal(titleFromContent('\n\n# Primero\n# Segundo', 'x'), 'Primero');
    assert.equal(titleFromContent('sin heading', 'ideas'), 'ideas');
    assert.equal(titleFromContent('', 'ideas'), 'ideas');
});

test('a snippet is one line of the body, without the heading', () => {
    assert.equal(snippet('# Título\n\nprimera línea\nsegunda'), 'primera línea segunda');
    assert.equal(snippet('x'.repeat(200), 20).length, 20);
    assert.match(snippet('x'.repeat(200), 20), /…$/);
});

test('typing filters by name first and by contents second', () => {
    const notes = parseListing([
        '300\t/n/ideas.md',
        '200\t/n/reunion.md',
        '100\t/n/2026-10-02.md'
    ].join('\n'), '/n');
    assert.equal(names(filterNotes(notes, '')), 'ideas.md,reunion.md,2026-10-02.md');
    assert.equal(names(filterNotes(notes, 'ide')), 'ideas.md');
    assert.equal(names(filterNotes(notes, 'union')), 'reunion.md');
    // A note whose contents matched ranks below any name match.
    assert.equal(names(filterNotes(notes, 'ide', ['/n/reunion.md'])), 'ideas.md,reunion.md');
    assert.equal(names(filterNotes(notes, 'nada')), '');
});

test('a capture is appended as one bullet and never rewrites what is there', () => {
    assert.equal(appendCapture('', 'comprar pan', AT), '# 2026-10-02\n\n- 14:32 comprar pan\n');
    assert.equal(appendCapture('# 2026-10-02\n\n- 09:10 algo', 'otra', AT),
                 '# 2026-10-02\n\n- 09:10 algo\n- 14:32 otra\n');
    // The existing text is returned byte for byte, with the bullet after it.
    const existing = '# 2026-10-02\n\n- 09:10 algo\n\nun párrafo suelto\n';
    assert.equal(appendCapture(existing, 'otra', AT).startsWith(existing), true);
});

test('a multi-line capture stays a single bullet', () => {
    assert.equal(appendCapture('', 'primera\nsegunda\ntercera', AT),
                 '# 2026-10-02\n\n- 14:32 primera\n  segunda\n  tercera\n');
});

test('an empty capture changes nothing', () => {
    assert.equal(appendCapture('# 2026-10-02\n', '   \n  ', AT), '# 2026-10-02\n');
    assert.equal(appendCapture('', '', AT), '');
});

test('a new note starts with its title as a heading', () => {
    assert.equal(newNoteContent('Ideas de producto', AT), '# Ideas de producto\n\n');
    assert.equal(newNoteContent('', AT), '# 2026-10-02 14:32\n\n');
});
