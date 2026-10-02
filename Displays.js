// Geometry for the Displays mini app: turns `hyprctl monitors -j` into tiles
// laid out in Hyprland's logical coordinate space, moves one of them, and keeps
// the result a layout Hyprland can use.
//
// Hyprland positions monitors in logical pixels, which is the native resolution
// divided by the scale, so a 2880x1800 panel at scale 1.6 occupies 1800x1125 and
// the monitor to its right starts at x=1800. Every function here works in that
// space; the view scales it down to fit the canvas.
//
// Two rules make a layout usable, and both are enforced on every move:
//   - no overlap, because two monitors sharing logical pixels draw the cursor
//     on both screens
//   - no gaps between a monitor and the rest, because the pointer gets stuck in
//     the hole instead of crossing to the next screen
// The layout is also normalised so its top-left corner sits at 0x0, which is
// where Hyprland expects a layout to start.

// Hyprland transforms: 0 normal, 1 is 90 degrees, 2 is 180, 3 is 270, and 4..7
// are the same angles flipped. The odd ones turn the panel on its side, so the
// logical width and height swap.
function isRotated(transform) {
    return Math.abs(Number(transform) || 0) % 2 === 1;
}

function logicalSize(monitor) {
    const scale = Number(monitor?.scale) || 1;
    const width = Math.round((Number(monitor?.width) || 0) / scale);
    const height = Math.round((Number(monitor?.height) || 0) / scale);
    return isRotated(monitor?.transform) ? { w: height, h: width } : { w: width, h: height };
}

// External connector names move between plugs on a dock, so a description is
// the stabler key for saved layouts. Built-in panels and anything without a
// description fall back to the connector name.
function monitorKey(monitor) {
    const description = String(monitor?.description ?? "").trim();
    if (description.length > 0)
        return `desc:${description}`;
    return String(monitor?.name ?? "");
}

function fromMonitors(monitors) {
    const list = Array.isArray(monitors) ? monitors : [];
    const tiles = [];
    for (var i = 0; i < list.length; ++i) {
        const monitor = list[i];
        if (!monitor || monitor.disabled === true)
            continue;
        const size = logicalSize(monitor);
        if (size.w <= 0 || size.h <= 0)
            continue;
        tiles.push({
            key: monitorKey(monitor),
            name: String(monitor.name ?? ""),
            description: String(monitor.description ?? ""),
            x: Math.round(Number(monitor.x) || 0),
            y: Math.round(Number(monitor.y) || 0),
            w: size.w,
            h: size.h,
            width: Math.round(Number(monitor.width) || 0),
            height: Math.round(Number(monitor.height) || 0),
            refreshRate: Number(monitor.refreshRate) || 0,
            scale: Number(monitor.scale) || 1,
            transform: Number(monitor.transform) || 0,
            focused: monitor.focused === true
        });
    }
    tiles.sort((a, b) => (a.x - b.x) || (a.y - b.y) || a.name.localeCompare(b.name));
    return tiles;
}

function clone(tiles) {
    return (Array.isArray(tiles) ? tiles : []).map(tile => Object.assign({}, tile));
}

function indexOfKey(tiles, key) {
    const needle = String(key ?? "");
    for (var i = 0; i < tiles.length; ++i) {
        if (tiles[i].key === needle)
            return i;
    }
    return -1;
}

function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

// Touching means sharing a border with some length, not just a corner: two
// monitors that meet at one point still trap the pointer.
function touches(a, b) {
    const sharesX = a.x < b.x + b.w && b.x < a.x + a.w;
    const sharesY = a.y < b.y + b.h && b.y < a.y + a.h;
    if (sharesX && (a.y === b.y + b.h || b.y === a.y + a.h))
        return true;
    return sharesY && (a.x === b.x + b.w || b.x === a.x + a.w);
}

function normalize(tiles) {
    const out = clone(tiles);
    if (out.length === 0)
        return out;
    var minX = out[0].x;
    var minY = out[0].y;
    for (var i = 1; i < out.length; ++i) {
        minX = Math.min(minX, out[i].x);
        minY = Math.min(minY, out[i].y);
    }
    for (var j = 0; j < out.length; ++j) {
        out[j].x -= minX;
        out[j].y -= minY;
    }
    return out;
}

// How far a dragged edge may be from a neighbour's edge and still click onto it,
// in logical pixels. Generous on purpose: dragging a 1800-wide tile inside a
// canvas a few hundred pixels across means every screen pixel is several
// logical ones.
var SNAP_THRESHOLD = 80;

function snapAxis(value, length, candidates, threshold) {
    var best = value;
    var bestDelta = threshold + 1;
    for (var i = 0; i < candidates.length; ++i) {
        const delta = Math.abs(candidates[i] - value);
        if (delta <= threshold && delta < bestDelta) {
            best = candidates[i];
            bestDelta = delta;
        }
    }
    return best;
}

// Edge to edge, aligned starts, aligned ends and centre to centre, which is what
// makes two screens of different heights line up the way they stand on a desk.
function snapCandidatesX(moved, others) {
    const out = [];
    for (var i = 0; i < others.length; ++i) {
        const other = others[i];
        out.push(other.x - moved.w, other.x + other.w, other.x,
                 other.x + other.w - moved.w,
                 other.x + Math.round((other.w - moved.w) / 2));
    }
    return out;
}

function snapCandidatesY(moved, others) {
    const out = [];
    for (var i = 0; i < others.length; ++i) {
        const other = others[i];
        out.push(other.y - moved.h, other.y + other.h, other.y,
                 other.y + other.h - moved.h,
                 other.y + Math.round((other.h - moved.h) / 2));
    }
    return out;
}

function boundingBox(tiles) {
    if (tiles.length === 0)
        return { x: 0, y: 0, w: 0, h: 0 };
    var minX = tiles[0].x, minY = tiles[0].y;
    var maxX = tiles[0].x + tiles[0].w, maxY = tiles[0].y + tiles[0].h;
    for (var i = 1; i < tiles.length; ++i) {
        minX = Math.min(minX, tiles[i].x);
        minY = Math.min(minY, tiles[i].y);
        maxX = Math.max(maxX, tiles[i].x + tiles[i].w);
        maxY = Math.max(maxY, tiles[i].y + tiles[i].h);
    }
    return { x: minX, y: minY, w: maxX - minX, h: maxY - minY };
}

function distance(ax, ay, bx, by) {
    return Math.abs(ax - bx) + Math.abs(ay - by);
}

// The four ways to park `moved` against `other` without overlapping it, keeping
// whatever the other axis already is.
function sidePlacements(moved, other) {
    return [
        { x: other.x - moved.w, y: moved.y },
        { x: other.x + other.w, y: moved.y },
        { x: moved.x, y: other.y - moved.h },
        { x: moved.x, y: other.y + other.h }
    ];
}

function firstOverlap(moved, others) {
    for (var i = 0; i < others.length; ++i) {
        if (overlaps(moved, others[i]))
            return others[i];
    }
    return null;
}

// A tile dropped on top of another slides to that neighbour's nearest free side.
// Each pass fixes one overlap and may create another, so this repeats; the cap
// is a guard against a pathological set, and the fallback parks the tile to the
// right of everything, which always fits.
function resolveOverlaps(moved, others) {
    var current = Object.assign({}, moved);
    for (var pass = 0; pass < 8; ++pass) {
        const hit = firstOverlap(current, others);
        if (!hit)
            return current;
        const options = sidePlacements(current, hit);
        var best = null;
        var bestDistance = Infinity;
        for (var i = 0; i < options.length; ++i) {
            const option = options[i];
            const candidate = Object.assign({}, current, option);
            if (firstOverlap(candidate, others))
                continue;
            const cost = distance(option.x, option.y, current.x, current.y);
            if (cost < bestDistance) {
                best = option;
                bestDistance = cost;
            }
        }
        if (!best) {
            // No free side of this neighbour: step over it and try again.
            current.x = hit.x + hit.w;
            continue;
        }
        current.x = best.x;
        current.y = best.y;
    }
    const box = boundingBox(others);
    current.x = box.x + box.w;
    current.y = box.y;
    return current;
}

// Every position where `moved` sits flush against `other`, sharing a border and
// not just a corner: the four sides, each aligned to the neighbour's start, its
// end, and centred.
function attachPlacements(moved, other) {
    const alignY = [other.y, other.y + other.h - moved.h,
                    other.y + Math.round((other.h - moved.h) / 2)];
    const alignX = [other.x, other.x + other.w - moved.w,
                    other.x + Math.round((other.w - moved.w) / 2)];
    const out = [];
    for (var i = 0; i < alignY.length; ++i) {
        out.push({ x: other.x - moved.w, y: alignY[i] });
        out.push({ x: other.x + other.w, y: alignY[i] });
    }
    for (var j = 0; j < alignX.length; ++j) {
        out.push({ x: alignX[j], y: other.y - moved.h });
        out.push({ x: alignX[j], y: other.y + other.h });
    }
    return out;
}

function touchesAny(moved, others) {
    for (var i = 0; i < others.length; ++i) {
        if (touches(moved, others[i]))
            return true;
    }
    return false;
}

// A tile dropped away from the others is pulled back to the nearest position
// where it shares a border with one of them, so the pointer can always cross.
function attach(moved, others) {
    if (others.length === 0 || touchesAny(moved, others))
        return Object.assign({}, moved);
    var best = null;
    var bestDistance = Infinity;
    for (var i = 0; i < others.length; ++i) {
        const options = attachPlacements(moved, others[i]);
        for (var j = 0; j < options.length; ++j) {
            const option = options[j];
            const candidate = Object.assign({}, moved, option);
            if (firstOverlap(candidate, others))
                continue;
            const cost = distance(option.x, option.y, moved.x, moved.y);
            if (cost < bestDistance) {
                best = option;
                bestDistance = cost;
            }
        }
    }
    if (!best)
        return Object.assign({}, moved);
    return Object.assign({}, moved, best);
}

// Drop `key` at a logical position: snap to the neighbours, push off anything it
// landed on, pull it back if it landed in empty space, and normalise the result
// to 0x0.
function place(tiles, key, x, y, threshold) {
    const out = clone(tiles);
    const index = indexOfKey(out, key);
    if (index < 0)
        return normalize(out);
    const others = out.filter((tile, i) => i !== index);
    var moved = Object.assign({}, out[index], { x: Math.round(x), y: Math.round(y) });
    const limit = typeof threshold === "number" ? threshold : SNAP_THRESHOLD;
    moved.x = snapAxis(moved.x, moved.w, snapCandidatesX(moved, others), limit);
    moved.y = snapAxis(moved.y, moved.h, snapCandidatesY(moved, others), limit);
    for (var pass = 0; pass < 3; ++pass) {
        const before = `${moved.x}x${moved.y}`;
        moved = resolveOverlaps(moved, others);
        moved = attach(moved, others);
        if (`${moved.x}x${moved.y}` === before)
            break;
    }
    out[index] = moved;
    return normalize(out);
}

// Keyboard moves. An arrow key parks the tile on that side of everything else,
// aligned to whichever neighbour edge it is already closest to. Pressing the
// same arrow again slides it along that side to the next alignment, so two
// presses of Down walk a tile across the row below instead of fighting over one
// spot.
var SIDES = { left: true, right: true, up: true, down: true };

function alignmentsFor(moved, others, side) {
    const box = boundingBox(others);
    const out = [];
    if (side === "left" || side === "right") {
        const x = side === "left" ? box.x - moved.w : box.x + box.w;
        const ys = [box.y, box.y + box.h - moved.h,
                    box.y + Math.round((box.h - moved.h) / 2)];
        for (var i = 0; i < others.length; ++i)
            ys.push(others[i].y, others[i].y + others[i].h - moved.h);
        for (var j = 0; j < ys.length; ++j)
            out.push({ x: x, y: ys[j] });
    } else {
        const y = side === "up" ? box.y - moved.h : box.y + box.h;
        const xs = [box.x, box.x + box.w - moved.w,
                    box.x + Math.round((box.w - moved.w) / 2)];
        for (var k = 0; k < others.length; ++k)
            xs.push(others[k].x, others[k].x + others[k].w - moved.w);
        for (var l = 0; l < xs.length; ++l)
            out.push({ x: xs[l], y: y });
    }
    const seen = {};
    const unique = [];
    for (var m = 0; m < out.length; ++m) {
        const id = `${out[m].x}x${out[m].y}`;
        if (seen[id])
            continue;
        seen[id] = true;
        unique.push(out[m]);
    }
    unique.sort((a, b) => (a.y - b.y) || (a.x - b.x));
    return unique;
}

function moveToSide(tiles, key, side) {
    const out = clone(tiles);
    const index = indexOfKey(out, key);
    if (index < 0 || !SIDES[String(side)])
        return normalize(out);
    const others = out.filter((tile, i) => i !== index);
    if (others.length === 0)
        return normalize(out);
    const moved = out[index];
    const options = alignmentsFor(moved, others, side);
    if (options.length === 0)
        return normalize(out);
    var currentIndex = -1;
    for (var i = 0; i < options.length; ++i) {
        if (options[i].x === moved.x && options[i].y === moved.y) {
            currentIndex = i;
            break;
        }
    }
    var target;
    if (currentIndex >= 0) {
        target = options[(currentIndex + 1) % options.length];
    } else {
        target = options[0];
        var bestDistance = distance(target.x, target.y, moved.x, moved.y);
        for (var j = 1; j < options.length; ++j) {
            const cost = distance(options[j].x, options[j].y, moved.x, moved.y);
            if (cost < bestDistance) {
                target = options[j];
                bestDistance = cost;
            }
        }
    }
    return place(out, key, target.x, target.y, 0);
}

// The `monitor` keyword Hyprland takes at runtime: connector, mode, position,
// scale. The mode is echoed back exactly as reported so applying a move never
// changes resolution or refresh rate; only the position differs.
function monitorKeyword(tile) {
    const refresh = Number(tile?.refreshRate) || 0;
    const mode = `${Math.round(Number(tile?.width) || 0)}x${Math.round(Number(tile?.height) || 0)}@${refresh.toFixed(2)}`;
    const scale = Number(tile?.scale) || 1;
    return `${tile?.name ?? ""},${mode},${Math.round(Number(tile?.x) || 0)}x${Math.round(Number(tile?.y) || 0)},${scale}`;
}

function samePositions(a, b) {
    const left = Array.isArray(a) ? a : [];
    const right = Array.isArray(b) ? b : [];
    if (left.length !== right.length)
        return false;
    for (var i = 0; i < left.length; ++i) {
        const match = right.find(tile => tile.key === left[i].key);
        if (!match || match.x !== left[i].x || match.y !== left[i].y)
            return false;
    }
    return true;
}

// Identifies the set of connected monitors, so a layout saved at the desk is
// only ever reapplied to that same set of screens and never to the ones at the
// next place.
function layoutSignature(tiles) {
    return (Array.isArray(tiles) ? tiles : [])
        .map(tile => tile.key)
        .filter(key => String(key ?? "").length > 0)
        .sort()
        .join("|");
}

function savedLayout(tiles) {
    return {
        signature: layoutSignature(tiles),
        positions: (Array.isArray(tiles) ? tiles : []).map(tile => ({
            key: tile.key,
            name: tile.name,
            x: Math.round(Number(tile.x) || 0),
            y: Math.round(Number(tile.y) || 0)
        }))
    };
}

// Puts a saved layout back onto the monitors as they are now. Every key has to
// match, otherwise the saved positions belong to a different set of screens and
// the live layout is kept untouched.
function restoreLayout(tiles, saved) {
    const out = clone(tiles);
    if (!saved || layoutSignature(out) !== String(saved.signature ?? ""))
        return null;
    const positions = Array.isArray(saved.positions) ? saved.positions : [];
    for (var i = 0; i < out.length; ++i) {
        const match = positions.find(entry => entry.key === out[i].key);
        if (!match)
            return null;
        out[i].x = Math.round(Number(match.x) || 0);
        out[i].y = Math.round(Number(match.y) || 0);
    }
    const fixed = normalize(out);
    for (var j = 0; j < fixed.length; ++j) {
        const others = fixed.filter((tile, k) => k !== j);
        if (firstOverlap(fixed[j], others))
            return null;
    }
    return fixed;
}
