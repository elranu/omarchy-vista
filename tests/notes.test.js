const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../Notes.js'), 'utf8'), context);
const {
    DEFAULT_DIRECTORY, expandPath, dateStamp, clockStamp, dailyName, slugify,
    fileNameFor, isSafeFileName, parseListing, titleFromName, titleFromContent,
    snippet, filterNotes, appendCapture, newNoteContent, renameTarget, uniqueFileName,
    listingTotal, applyHeadings, LISTING_LIMIT
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

test('the write guard checks containment, not spelling', () => {
    assert.equal(isSafeFileName('nota.md'), true);
    assert.equal(isSafeFileName('2026-10-02.md'), true);
    assert.equal(isSafeFileName('con espacio.md'), true);
    // Notes written by hand or by Obsidian have names like these, and the app
    // lists and edits them, so Save has to accept them too.
    assert.equal(isSafeFileName('Reunión.md'), true);
    assert.equal(isSafeFileName('Project (draft).md'), true);
    assert.equal(isSafeFileName('日本語.md'), true);
    assert.equal(isSafeFileName('Notas.MD'), true);
    // What could leave the folder, hide the file or carry a control character.
    assert.equal(isSafeFileName('../fuera.md'), false);
    assert.equal(isSafeFileName('sub/nota.md'), false);
    assert.equal(isSafeFileName('.oculta.md'), false);
    assert.equal(isSafeFileName('mala\nlinea.md'), false);
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

test('a note holding only whitespace keeps its bytes', () => {
    // The append contract is that what is there comes back untouched; only a
    // genuinely empty file gets a heading.
    assert.equal(appendCapture('   \n', 'algo', AT), '   \n- 14:32 algo\n');
    assert.equal(appendCapture('', 'algo', AT), '# 2026-10-02\n\n- 14:32 algo\n');
});

test('titles come from each note\'s first heading, with the file name as fallback', () => {
    const notes = parseListing(['300\t/n/ideas.md', '200\t/n/2026-10-02.md'].join('\n'), '/n');
    const titled = applyHeadings(notes, '/n/ideas.md\t# Ideas de producto', '/n');
    assert.equal(titled.map(note => note.title).join(','), 'Ideas de producto,2026-10-02');
    // A heading of a different level, and a file with none at all.
    assert.equal(applyHeadings(notes, '/n/ideas.md\t### Sub', '/n')[0].title, 'Sub');
    assert.equal(applyHeadings(notes, '', '/n')[0].title, 'ideas');
    // Positions are untouched by the titles pass.
    assert.equal(titled.map(note => note.name).join(','), 'ideas.md,2026-10-02.md');
});

test('the listing reports how many notes there really were', () => {
    const lines = [];
    for (let i = 0; i < LISTING_LIMIT + 5; ++i)
        lines.push(`${1000 + i}\t/n/nota-${i}.md`);
    const text = lines.join('\n');
    assert.equal(listingTotal(text), LISTING_LIMIT + 5);
    assert.equal(parseListing(text, '/n').length, LISTING_LIMIT);
    assert.equal(listingTotal('300\t/n/a.md\nbasura\n'), 1);
});

test('an empty capture changes nothing', () => {
    assert.equal(appendCapture('# 2026-10-02\n', '   \n  ', AT), '# 2026-10-02\n');
    assert.equal(appendCapture('', '', AT), '');
});

test('a new note starts with its title as a heading', () => {
    assert.equal(newNoteContent('Ideas de producto', AT), '# Ideas de producto\n\n');
    assert.equal(newNoteContent('', AT), '# 2026-10-02 14:32\n\n');
});

test('a rename slugifies the new name and keeps a given .md', () => {
    assert.equal(renameTarget('Ideas de Producto'), 'ideas-de-producto.md');
    assert.equal(renameTarget('mis-notas.md'), 'mis-notas.md');
    assert.equal(renameTarget('MIS NOTAS.MD'), 'mis-notas.md');
    // A name that looks like a path becomes a file name in the folder.
    assert.equal(renameTarget('../../etc/passwd'), 'etc-passwd.md');
    assert.equal(renameTarget('   '), '');
    assert.equal(renameTarget('.oculta'), 'oculta.md');
});

test('renaming onto a taken name gets a suffix instead of losing a note', () => {
    const taken = ['ideas.md', 'ideas-2.md', 'otra.md'];
    assert.equal(uniqueFileName('ideas.md', taken, 'otra.md'), 'ideas-3.md');
    assert.equal(uniqueFileName('libre.md', taken, 'otra.md'), 'libre.md');
    // Renaming a note to the name it already has is not a collision.
    assert.equal(uniqueFileName('ideas.md', taken, 'ideas.md'), 'ideas.md');
    assert.equal(uniqueFileName('', taken, 'otra.md'), '');
});

test('every name a rename can produce is safe to write', () => {
    for (const input of ['../../etc/passwd', '.bashrc', 'a/b/c', 'nota con espacios',
                         'Ünïcödé', 'mis-notas.md', 'x'.repeat(200)]) {
        const target = renameTarget(input);
        if (target.length > 0)
            assert.equal(isSafeFileName(target), true, `${input} -> ${target}`);
    }
});
