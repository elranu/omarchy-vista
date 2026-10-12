// Builds the Hyprland Lua that launches a desktop entry from the Overview.
//
// A window lands on whatever workspace is focused when it maps, not when it
// was launched. An app that takes a few seconds to start would open wherever
// the user had moved on to by then, often a workspace on another monitor.
// Hyprland's exec rules pin the window to a workspace chosen at launch time,
// and they follow the process through uwsm-app and gtk-launch.
//
// Everything runs in one eval: focusing the empty workspace is synchronous,
// so the workspace read right after it is the new one, and nothing else can
// change the focus in between.

// uwsm-app keeps the app out of wayland-wm@.service, and gtk-launch resolves
// ids with spaces or ones UWSM rejects. The .desktop suffix is required or
// ids like org.telegram.desktop will not resolve. Same approach as AppLibrary.
function launchCommand(desktopId) {
    const id = String(desktopId ?? "");
    // exec_cmd runs through a shell, and a control character has no business
    // in a desktop id.
    if (id.length === 0 || /[\u0000-\u001f\u007f]/.test(id))
        return "";
    return `uwsm-app -- gtk-launch ${shellQuote(`${id}.desktop`)}`;
}

function shellQuote(text) {
    return `'${String(text).replace(/'/g, "'\\''")}'`;
}

function luaString(text) {
    return `"${String(text).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
}

// With newWorkspace the app gets a fresh, empty workspace, focused right away
// like before. Without it, the app opens on the workspace focused now. Either
// way the window is pinned there, silently, so a slow start never pulls the
// user back to it; when that workspace is still on screen it is focused anyway.
function launchLua(desktopId, newWorkspace) {
    const command = launchCommand(desktopId);
    if (command.length === 0)
        return "";
    const cmd = luaString(command);
    return [
        newWorkspace ? 'hl.dispatch(hl.dsp.focus({ workspace = "empty" }))' : "",
        "local ws = hl.get_active_workspace()",
        `if ws then hl.exec_cmd(${cmd}, { workspace = tostring(ws.id) .. " silent" }) else hl.exec_cmd(${cmd}) end`
    ].filter(line => line.length > 0).join("; ");
}
