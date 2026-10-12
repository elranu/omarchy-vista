const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../Launch.js'), 'utf8'), context);
const { launchCommand, launchLua, shellQuote, luaString } = context;

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
