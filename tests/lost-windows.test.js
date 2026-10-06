const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../LostWindows.js'), 'utf8'), context);
const { monitorBox, isLost, lostWindows, safeAddress, rescueCommands } = context;

const fixture = JSON.parse(fs.readFileSync(
    path.join(__dirname, 'fixtures', 'lost-window-meet.json'), 'utf8'));
const [LAPTOP, EXTERNAL] = fixture.monitors;
const [MEET, GMAIL, TERMINAL] = fixture.clients;
const box = monitor => {
    const b = monitorBox(monitor);
    return `${b.x0},${b.y0} → ${b.x1},${b.y1}`;
};

test('a monitor covers its logical area, the native size divided by the scale', () => {
    assert.equal(box(LAPTOP), '2400,225 → 4200,1350');
    assert.equal(box(EXTERNAL), '0,0 → 2400,1350');
    // A panel turned on its side swaps width and height.
    assert.equal(box({ x: 0, y: 0, width: 2560, height: 1440, scale: 1, transform: 1 }),
                 '0,0 → 1440,2560');
    assert.equal(monitorBox(null), null);
    assert.equal(monitorBox({ x: 0, y: 0, width: 0, height: 0, scale: 1 }), null);
});

test('the reported Meet window is lost and its neighbours are not', () => {
    // On eDP-1 according to Hyprland, with the geometry of DP-5.
    assert.equal(isLost(MEET, LAPTOP), true);
    // The other window on the same workspace was where it belonged.
    assert.equal(isLost(GMAIL, LAPTOP), false);
    assert.equal(isLost(TERMINAL, EXTERNAL), false);
    const lost = lostWindows(fixture.clients, fixture.monitors);
    assert.equal(lost.map(client => client.address).join(','), '0x64458dcb8700');
});

test('a window hanging over an edge is not lost, only one whose centre left', () => {
    const over = { workspace: { id: 3 }, at: [3800, 300], size: [600, 400], mapped: true };
    // Centre at 4100: still inside a monitor that ends at 4200.
    assert.equal(isLost(over, LAPTOP), false);
    const gone = { workspace: { id: 3 }, at: [4000, 300], size: [600, 400], mapped: true };
    // Centre at 4300: past the right edge.
    assert.equal(isLost(gone, LAPTOP), true);
});

test('hidden, unmapped and special-workspace windows are never reported', () => {
    const base = { workspace: { id: 3 }, at: [10, 45], size: [1185, 1295] };
    assert.equal(isLost(Object.assign({}, base, { hidden: true }), LAPTOP), false);
    assert.equal(isLost(Object.assign({}, base, { mapped: false }), LAPTOP), false);
    // Scratchpad windows are positioned against whichever monitor shows them.
    assert.equal(isLost(Object.assign({}, base, { workspace: { id: -98 } }), LAPTOP), false);
    assert.equal(isLost(base, null), false);
    assert.equal(isLost(null, LAPTOP), false);
    assert.equal(isLost({ workspace: { id: 3 } }, LAPTOP), false);
});

test('a window without a monitor of its own is skipped, not guessed at', () => {
    const orphan = Object.assign({}, MEET, { monitor: 7 });
    assert.equal(lostWindows([orphan], fixture.monitors).length, 0);
    assert.equal(lostWindows(null, fixture.monitors).length, 0);
});

test('rescuing moves the window to the workspace being looked at, then focuses it', () => {
    const commands = rescueCommands('0x64458dcb8700', 3, 9);
    assert.equal(commands.length, 2);
    assert.equal(commands[0],
        'hl.dsp.window.move({ workspace = 9, follow = false, window = "address:0x64458dcb8700" })');
    assert.equal(commands[1], 'hl.dsp.focus({ window = "address:0x64458dcb8700" })');
});

test('a window already on that workspace takes a hop so it is laid out again', () => {
    const commands = rescueCommands('0x64458dcb8700', 3, 3);
    assert.equal(commands.length, 3);
    assert.match(commands[0], /workspace = "special:vista-rescue", follow = false/);
    assert.match(commands[1], /workspace = 3, follow = false/);
    assert.match(commands[2], /hl\.dsp\.focus/);
});

test('only a hex address ever reaches a dispatch', () => {
    assert.equal(safeAddress('0x64458dcb8700'), '0x64458dcb8700');
    assert.equal(safeAddress('  0xABCdef  '), '0xABCdef');
    assert.equal(safeAddress('64458dcb8700'), '');
    assert.equal(safeAddress('0x1" }) hl.exec("rm -rf ~'), '');
    assert.equal(rescueCommands('0x1" })', 3, 9).length, 0);
    assert.equal(rescueCommands('0x64458dcb8700', 3, 0).length, 0);
});
