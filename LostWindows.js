// Windows Hyprland reports on one monitor while their geometry sits somewhere
// else -- usually on another monitor, after a hotplug or a popup opened from a
// window on the other screen. Such a window is "lost": switching to its
// workspace does not show it, because it is drawn off that monitor.
//
// The Overview still draws it, clamped into its workspace card, so that is where
// it can be found and brought back. This file only decides which windows are
// lost and what to send Hyprland to rescue one; it never moves anything itself.

// The monitor's area in Hyprland's logical coordinates: native size divided by
// the scale, turned on its side for a rotated panel.
function monitorBox(monitor) {
    if (!monitor)
        return null;
    const scale = Number(monitor.scale) || 1;
    const rotated = Math.abs(Number(monitor.transform) || 0) % 2 === 1;
    const width = (rotated ? Number(monitor.height) : Number(monitor.width)) / scale;
    const height = (rotated ? Number(monitor.width) : Number(monitor.height)) / scale;
    if (!(width > 0) || !(height > 0))
        return null;
    const x = Number(monitor.x) || 0;
    const y = Number(monitor.y) || 0;
    return { x0: x, y0: y, x1: x + width, y1: y + height };
}

// A window is lost when the centre of its geometry is outside the monitor
// Hyprland says it is on. The centre rather than any corner: a window that only
// hangs over an edge is still visible and is not what this is for.
//
// Left out: hidden and unmapped windows, which are not drawn anywhere anyway,
// and special workspaces (negative ids), whose windows are positioned against
// whichever monitor shows the special workspace when it is toggled.
function isLost(client, monitor) {
    if (!client || !monitor)
        return false;
    if (client.hidden === true || client.mapped === false)
        return false;
    const workspaceId = Number(client.workspace?.id);
    if (!(workspaceId > 0))
        return false;
    const at = client.at;
    const size = client.size;
    if (!Array.isArray(at) || !Array.isArray(size) || at.length < 2 || size.length < 2)
        return false;
    const box = monitorBox(monitor);
    if (!box)
        return false;
    const cx = Number(at[0]) + Number(size[0]) / 2;
    const cy = Number(at[1]) + Number(size[1]) / 2;
    if (!isFinite(cx) || !isFinite(cy))
        return false;
    return cx < box.x0 || cx >= box.x1 || cy < box.y0 || cy >= box.y1;
}

function lostWindows(clients, monitors) {
    const byId = {};
    const list = Array.isArray(monitors) ? monitors : [];
    for (var i = 0; i < list.length; ++i)
        byId[list[i].id] = list[i];
    const out = [];
    const all = Array.isArray(clients) ? clients : [];
    for (var j = 0; j < all.length; ++j) {
        const client = all[j];
        if (isLost(client, byId[client?.monitor]))
            out.push(client);
    }
    return out;
}

// A Hyprland window address as it may appear in a dispatch: hex only, so a
// value from anywhere can never end the Lua string it is placed in.
function safeAddress(address) {
    const value = String(address ?? "").trim();
    return /^0x[0-9a-fA-F]+$/.test(value) ? value : "";
}

// What to send Hyprland to bring a lost window to the workspace being looked
// at. Moving a window to another workspace makes Hyprland lay it out again on
// that workspace's monitor, which is what fixes the stale geometry; it is the
// same move the rest of Vista already uses.
//
// A window that is already on that workspace cannot be moved onto it, which
// would be a no-op and leave it where it is, so it takes a hop through a
// special workspace and back. The special workspace exists only for that
// moment: Hyprland drops it again when it is empty.
function rescueCommands(address, windowWorkspaceId, targetWorkspaceId) {
    const target = Number(targetWorkspaceId);
    const safe = safeAddress(address);
    if (safe.length === 0 || !(target > 0))
        return [];
    const window = `window = "address:${safe}"`;
    const commands = [];
    if (Number(windowWorkspaceId) === target)
        commands.push(`hl.dsp.window.move({ workspace = "special:vista-rescue", follow = false, ${window} })`);
    commands.push(`hl.dsp.window.move({ workspace = ${target}, follow = false, ${window} })`);
    commands.push(`hl.dsp.focus({ ${window} })`);
    return commands;
}
