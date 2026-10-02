const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../AppIcons.js'), 'utf8'), context);
const { buildIndex, resolve, entryKeys, execBinary } = context;

// Shapes taken from the entries Quickshell reports on this machine.
const entries = [
    { id: 'brave-browser', startupClass: 'brave-browser', icon: 'brave-desktop', execString: 'brave %U' },
    { id: 'code', startupClass: 'Code', icon: 'vscode', execString: '/usr/bin/code %F' },
    { id: 'com.mitchellh.ghostty', startupClass: 'com.mitchellh.ghostty', icon: 'com.mitchellh.ghostty', execString: 'ghostty' },
    { id: 'github-desktop', startupClass: 'GitHub Desktop', icon: 'github-desktop', execString: 'github-desktop %U' },
    { id: 'no-icon', startupClass: 'NoIcon', icon: '', execString: 'noicon' }
];
const index = buildIndex(entries);

test('a window class resolves to the icon its desktop entry declares', () => {
    assert.equal(resolve(index, 'brave-browser'), 'brave-desktop');
    assert.equal(resolve(index, 'Code'), 'vscode');
    assert.equal(resolve(index, 'code'), 'vscode');
    assert.equal(resolve(index, 'GitHub Desktop'), 'github-desktop');
});

test('reverse-DNS classes match on their last segment too', () => {
    assert.equal(resolve(index, 'com.mitchellh.ghostty'), 'com.mitchellh.ghostty');
    assert.equal(resolve(index, 'ghostty'), 'com.mitchellh.ghostty');
});

test('the binary in Exec is a key, and entries without an icon are skipped', () => {
    assert.equal(resolve(index, 'brave'), 'brave-desktop');
    assert.equal(resolve(index, 'NoIcon'), '');
    assert.equal(execBinary('/usr/bin/code %F'), 'code');
    assert.equal(execBinary(''), '');
});

test('unknown classes and empty input resolve to nothing', () => {
    for (const name of ['', '   ', 'no-such-app', undefined, null])
        assert.equal(resolve(index, name), '', JSON.stringify(name));
    assert.equal(resolve(null, 'code'), '');
});

test('an earlier entry keeps a key a later one would claim', () => {
    const shadowed = buildIndex([
        { id: 'first', startupClass: 'Shared', icon: 'first-icon' },
        { id: 'second', startupClass: 'Shared', icon: 'second-icon' }
    ]);
    assert.equal(resolve(shadowed, 'Shared'), 'first-icon');
});

test('keys are lower-cased and .desktop suffixes dropped', () => {
    assert.equal(entryKeys({ id: 'Foo.desktop', startupClass: 'FooBar', execString: 'foo' }).join(','), 'foobar,foo,foo');
});

test('wanted icon names come from the entries, plus the generic fallback', () => {
    const { wantedIconNames } = context;
    const names = Array.from(wantedIconNames(entries)).sort().join(',');
    assert.equal(names, 'application-x-executable,brave-desktop,com.mitchellh.ghostty,github-desktop,vscode');
    // Absolute paths resolve on their own, and an entry without an icon adds nothing.
    const other = Array.from(wantedIconNames([{ icon: '/opt/app/icon.png' }, { icon: '' }, {}])).join(',');
    assert.equal(other, 'application-x-executable');
    assert.equal(Array.from(wantedIconNames(null)).join(','), 'application-x-executable');
});

test('the scan command filters to the wanted names and drops unsafe ones', () => {
    const { iconScanCommand, safeIconName } = context;
    const command = iconScanCommand(['brave-desktop', 'com.mitchellh.ghostty', 'bad"name', 'back\\slash', 'semi;colon']);
    assert.match(command, /grep -E "\/\(brave-desktop\|com\.mitchellh\.ghostty\)\\\.\(svg\|png\)\$"/);
    for (const unsafe of ['bad"name', 'back\\slash', 'semi;colon', '$(id)', 'a b'])
        assert.equal(safeIconName(unsafe), false, unsafe);
    for (const safe of ['brave-desktop', 'com.mitchellh.ghostty', 'x+y', 'A_1'])
        assert.equal(safeIconName(safe), true, safe);
    assert.equal(iconScanCommand([]), '');
    assert.equal(iconScanCommand(['bad name']), '');
});
