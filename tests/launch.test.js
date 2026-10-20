const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../Launch.js'), 'utf8'), context);
const { launchCommand, launchLua, shellQuote, luaString, launchHints, matchesLaunch, parseOpenWindow, moveLua, activeWindowClass } = context;

test('the command goes through uwsm-app and gtk-launch with the .desktop suffix', () => {
    assert.equal(launchCommand('org.telegram.desktop'),
        "uwsm-app -- gtk-launch 'org.telegram.desktop.desktop'");
});

test('an id with spaces or quotes stays one shell word', () => {
    assert.equal(launchCommand("My App"), "uwsm-app -- gtk-launch 'My App.desktop'");
    assert.equal(shellQuote("it's"), "'it'\\''s'");
    assert.equal(launchCommand("a'b; rm -rf ~"), "uwsm-app -- gtk-launch 'a'\\''b; rm -rf ~.desktop'");
});

test('an empty id or one with a control character launches nothing', () => {
    assert.equal(launchCommand(''), '');
    assert.equal(launchCommand(undefined), '');
    assert.equal(launchCommand('evil\nhyprctl dispatch exit'), '');
    assert.equal(launchLua('', true), '');
});

test('a Lua string escapes backslashes and double quotes', () => {
    assert.equal(luaString('a"b\\c'), '"a\\"b\\\\c"');
});

test('a new workspace is focused first, then the app is pinned to it silently', () => {
    const lua = launchLua('foot', true);
    const focus = lua.indexOf('hl.dsp.focus({ workspace = "empty" })');
    const read = lua.indexOf('hl.get_active_workspace()');
    assert.ok(focus >= 0 && read > focus);
    assert.match(lua, /hl\.exec_cmd\("uwsm-app -- gtk-launch 'foot\.desktop'", \{ workspace = tostring\(ws\.id\) \.\. " silent" \}\)/);
});

test('in place, the app is pinned to the workspace focused now', () => {
    const lua = launchLua('foot', false);
    assert.doesNotMatch(lua, /"empty"/);
    assert.match(lua, /^local ws = hl\.get_active_workspace\(\)/);
});

test('hints come from the id, the startup class, the name, the binary and a web app host', () => {
    const obsidian = launchHints({ id: 'obsidian', name: 'Obsidian', startupClass: 'md.obsidian.Obsidian', command: ['/usr/bin/obsidian', '%U'] });
    assert.equal(obsidian.join(','), 'obsidian,md.obsidian.obsidian');
    const webapp = launchHints({ id: 'HEY', name: 'HEY', command: ['omarchy-launch-webapp', 'https://app.hey.com'] });
    assert.ok(webapp.includes('app.hey.com'));
    assert.ok(!webapp.includes('omarchy-launch-webapp'));
    const flatpak = launchHints({ id: 'org.telegram.desktop', name: 'Telegram Desktop', execString: 'flatpak run org.telegram.desktop' });
    assert.ok(!flatpak.includes('flatpak'));
    assert.ok(flatpak.includes('telegramdesktop'));
});

test('a window matches by equal class or by a long hint inside it', () => {
    assert.ok(matchesLaunch(['obsidian'], 'obsidian'));
    assert.ok(matchesLaunch(['obsidian'], 'Obsidian'));
    assert.ok(matchesLaunch(['app.hey.com'], 'chrome-app.hey.com__-Default'));
    assert.ok(!matchesLaunch(['foo'], 'foobar'));
    assert.ok(!matchesLaunch(['obsidian'], 'com.mitchellh.ghostty'));
    assert.ok(!matchesLaunch(['obsidian'], ''));
});

test('an openwindow event is read up to the class, whatever the title holds', () => {
    const event = parseOpenWindow('634a6a9a7e30,4,obsidian,Notes, drafts, and more');
    assert.equal(event.address, '0x634a6a9a7e30');
    assert.equal(event.workspace, '4');
    assert.equal(event.windowClass, 'obsidian');
    assert.equal(parseOpenWindow('nothex,4,obsidian,x'), null);
    assert.equal(parseOpenWindow('abc'), null);
});

test('the move sends the window back silently and keeps its workspace on its monitor', () => {
    const lua = moveLua('0x634a6a9a7e30', 7, 'eDP-1');
    assert.match(lua, /window\.move\(\{ workspace = 7, follow = false, window = "address:0x634a6a9a7e30" \}\)/);
    assert.match(lua, /workspace\.move\(\{ workspace = "7", monitor = "eDP-1" \}\)/);
    assert.doesNotMatch(lua, /hl\.dsp\.focus/);
    assert.match(lua, /set_prop\(\{ prop = "focus_on_activate", value = "0"/);
    assert.match(lua, /ws\.monitor\.name ~= "eDP-1"/);
    assert.equal(moveLua('0x1"; os.exit()', 7, 'eDP-1'), '');
    assert.equal(moveLua('0x1', 0, 'eDP-1'), '');
    assert.doesNotMatch(moveLua('0x1', 3, 'eDP-1" })'), /monitor/);
});

test('an activewindow event is read up to the class', () => {
    assert.equal(activeWindowClass('obsidian,Notes, drafts'), 'obsidian');
    assert.equal(activeWindowClass(undefined), '');
});
