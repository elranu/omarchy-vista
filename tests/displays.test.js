const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../Displays.js'), 'utf8'), context);
const {
    logicalSize, describeMonitor, fromMonitors, place, moveToSide, normalize,
    monitorKeyword, layoutSignature, savedLayout, restoreLayout, samePositions
} = context;

const LAPTOP = {
    name: 'eDP-1', description: 'Samsung Display Corp. 0x4193',
    width: 2880, height: 1800, scale: 1.6, x: 0, y: 0, refreshRate: 90.001,
    transform: 0, focused: true
};
const EXTERNAL = {
    name: 'DP-3', description: 'HAK TYPEC 0x01010101',
    width: 2560, height: 1600, scale: 1.6, x: 1800, y: 0, refreshRate: 59.998,
    transform: 0, focused: false
};
const dim = monitor => {
    const size = logicalSize(monitor);
    return `${size.w}x${size.h}`;
};
const at = tiles => tiles.map(tile => `${tile.name}@${tile.x}x${tile.y}`).sort().join(' ');
const sizes = tiles => tiles.map(tile => `${tile.name}:${tile.w}x${tile.h}`).sort().join(' ');
const noOverlap = tiles => {
    for (let i = 0; i < tiles.length; ++i) {
        for (let j = i + 1; j < tiles.length; ++j) {
            const a = tiles[i], b = tiles[j];
            const hit = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
            assert.equal(hit, false, `${a.name} overlaps ${b.name}`);
        }
    }
};

test('logical size is the native resolution divided by the scale', () => {
    assert.equal(dim(LAPTOP), '1800x1125');
    assert.equal(dim(EXTERNAL), '1600x1000');
    assert.equal(dim({ width: 1920, height: 1080, scale: 1 }), '1920x1080');
});

test('a rotated monitor swaps its logical width and height', () => {
    assert.equal(dim({ width: 2560, height: 1440, scale: 1, transform: 1 }), '1440x2560');
    assert.equal(dim({ width: 2560, height: 1440, scale: 1, transform: 3 }), '1440x2560');
    assert.equal(dim({ width: 2560, height: 1440, scale: 1, transform: 7 }), '1440x2560');
    assert.equal(dim({ width: 2560, height: 1440, scale: 1, transform: 2 }), '2560x1440');
});

test('the saved identity prefers the description, because connector names move between plugs', () => {
    assert.equal(describeMonitor(EXTERNAL), 'desc:HAK TYPEC 0x01010101');
    assert.equal(describeMonitor({ name: 'DP-5', description: '' }), 'DP-5');
    assert.equal(describeMonitor({ name: 'DP-5' }), 'DP-5');
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    assert.equal(tiles.find(tile => tile.name === 'DP-3').match, 'desc:HAK TYPEC 0x01010101');
    // The runtime key is the connector, which is what selecting one tile needs.
    assert.equal(tiles.map(tile => tile.key).sort().join(','), 'DP-3,eDP-1');
});

test('twin monitors reporting the same description still get one identity each', () => {
    const twin = (connector, x) => ({
        name: connector, description: 'Dell U2720Q', width: 2560, height: 1440,
        scale: 1, x: x, y: 0, refreshRate: 60, transform: 0
    });
    const tiles = fromMonitors([twin('DP-3', 0), twin('DP-5', 2560)]);
    assert.equal(tiles.map(tile => tile.key).sort().join(','), 'DP-3,DP-5');
    assert.equal(tiles.map(tile => tile.match).sort().join(','),
                 'desc:Dell U2720Q#1,desc:Dell U2720Q#2');
    // Moving one twin leaves the other where it was.
    const moved = place(tiles, 'DP-5', -2400, 0);
    assert.equal(at(moved), 'DP-3@2560x0 DP-5@0x0');
    // And each twin gets its own saved position back, not the first one twice.
    const restored = restoreLayout(tiles, savedLayout(moved));
    assert.equal(at(restored), 'DP-3@2560x0 DP-5@0x0');
});

test('a saved layout survives the external moving to another connector', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const saved = savedLayout(moveToSide(tiles, 'DP-3', 'left'));
    const replugged = fromMonitors([LAPTOP, Object.assign({}, EXTERNAL, { name: 'DP-5' })]);
    const restored = restoreLayout(replugged, saved);
    assert.equal(at(restored), 'DP-5@0x0 eDP-1@1600x0');
});

test('disabled monitors are left out and the rest come back left to right', () => {
    const tiles = fromMonitors([EXTERNAL, LAPTOP, { name: 'HDMI-A-1', disabled: true, width: 1920, height: 1080, scale: 1 }]);
    assert.equal(tiles.length, 2);
    assert.equal(tiles[0].name, 'eDP-1');
    assert.equal(tiles[1].name, 'DP-3');
    assert.equal(sizes(tiles), 'DP-3:1600x1000 eDP-1:1800x1125');
});

test('a drag near a neighbour edge clicks onto it', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const moved = place(tiles, 'DP-3', 1760, 30);
    assert.equal(at(moved), 'DP-3@1800x0 eDP-1@0x0');
});

test('a monitor dropped on top of another slides to its nearest free side', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const moved = place(tiles, 'DP-3', 200, 100);
    noOverlap(moved);
    const external = moved.find(tile => tile.name === 'DP-3');
    assert.equal(external.y, 1125);
});

test('a monitor dropped in empty space is pulled back against the others', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const moved = place(tiles, 'DP-3', 6000, 4000);
    noOverlap(moved);
    const external = moved.find(tile => tile.name === 'DP-3');
    const laptop = moved.find(tile => tile.name === 'eDP-1');
    assert.equal(external.x, laptop.x + laptop.w);
});

test('the layout always starts at 0x0', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const moved = place(tiles, 'DP-3', -1700, -900);
    assert.equal(at(moved), 'DP-3@0x0 eDP-1@1600x0');
    const single = normalize([{ key: 'a', name: 'DP-1', x: 500, y: 400, w: 100, h: 100 }]);
    assert.equal(at(single), 'DP-1@0x0');
});

test('an arrow parks the monitor on that side and pressing it again slides along', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const once = moveToSide(tiles, 'DP-3', 'up');
    noOverlap(once);
    const first = once.find(tile => tile.name === 'DP-3');
    const laptopFirst = once.find(tile => tile.name === 'eDP-1');
    assert.equal(first.y + first.h, laptopFirst.y);
    const twice = moveToSide(once, 'DP-3', 'up');
    noOverlap(twice);
    const second = twice.find(tile => tile.name === 'DP-3');
    assert.notEqual(`${second.x}x${second.y}`, `${first.x}x${first.y}`);
    assert.equal(second.y + second.h, twice.find(tile => tile.name === 'eDP-1').y);
});

test('a single monitor has no side to move to', () => {
    const tiles = fromMonitors([LAPTOP]);
    assert.equal(at(moveToSide(tiles, 'eDP-1', 'left')), 'eDP-1@0x0');
});

test('the keyword echoes the mode and scale back and only changes the position', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    assert.equal(monitorKeyword(tiles[1]), 'DP-3,2560x1600@60.00,1800x0,1.6');
    assert.equal(monitorKeyword(tiles[0]), 'eDP-1,2880x1800@90.00,0x0,1.6');
});

test('the signature identifies the set of screens, whatever their order', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const reversed = fromMonitors([EXTERNAL, LAPTOP]);
    assert.equal(layoutSignature(tiles), layoutSignature(reversed));
    assert.notEqual(layoutSignature(tiles), layoutSignature(fromMonitors([LAPTOP])));
});

test('a saved layout comes back on the same screens and is refused on any other set', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const saved = savedLayout(moveToSide(tiles, 'DP-3', 'left'));
    const restored = restoreLayout(tiles, saved);
    assert.equal(at(restored), 'DP-3@0x0 eDP-1@1600x0');
    assert.equal(restoreLayout(fromMonitors([LAPTOP]), saved), null);
    assert.equal(restoreLayout(tiles, null), null);
    assert.equal(restoreLayout(tiles, { signature: layoutSignature(tiles), positions: [] }), null);
});

test('a saved layout whose monitors would overlap is refused', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    const overlapping = {
        signature: layoutSignature(tiles),
        positions: [
            { key: describeMonitor(LAPTOP), x: 0, y: 0 },
            { key: describeMonitor(EXTERNAL), x: 100, y: 100 }
        ]
    };
    assert.equal(restoreLayout(tiles, overlapping), null);
});

test('a changed position is detected, so applying can be skipped when nothing moved', () => {
    const tiles = fromMonitors([LAPTOP, EXTERNAL]);
    assert.equal(samePositions(tiles, fromMonitors([EXTERNAL, LAPTOP])), true);
    assert.equal(samePositions(tiles, moveToSide(tiles, 'DP-3', 'left')), false);
    assert.equal(samePositions(tiles, fromMonitors([LAPTOP])), false);
});
