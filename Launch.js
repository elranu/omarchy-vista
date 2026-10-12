// Builds the Hyprland Lua that launches a desktop entry from the Overview,
// and recognises the window it opens.
//
// A window lands on whatever workspace is focused when it maps, not when it
// was launched. An app that takes a few seconds to start would open wherever
// the user had moved on to by then, often a workspace on another monitor.
// Hyprland's exec rules pin the window to a workspace chosen at launch time,
// but only when Hyprland can tie the window to the process it started, which
// for most apps it cannot (see launchHints). LaunchTracker covers the rest.
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

// Hyprland only applies an exec rule to the process it started, and the app
// rarely is that process: uwsm-app hands the launch to its daemon, and
// gtk-launch or a single-instance app reparent it, so the window that finally
// maps has no link back. Vista watches for it instead, by the names a window
// of this app is likely to carry as its class.
const WRAPPERS = ["env", "sh", "bash", "setsid", "flatpak", "uwsm-app", "gtk-launch",
    "omarchy-launch-webapp", "omarchy-launch-or-focus-webapp"];

function launchHints(entry) {
    const hints = [];
    const add = value => {
        const hint = String(value ?? "").trim().toLowerCase();
        if (hint.length >= 3 && !hints.includes(hint))
            hints.push(hint);
    };
    const id = String(entry?.id ?? "");
    add(id);
    add(id.split(".").pop());
    const startupClass = String(entry?.startupClass ?? "");
    add(startupClass);
    add(startupClass.split(".").pop());
    add(String(entry?.name ?? "").replace(/\s+/g, ""));
    const command = Array.isArray(entry?.command) && entry.command.length > 0
        ? entry.command.map(String)
        : String(entry?.execString ?? "").split(/\s+/);
    const binary = String(command[0] ?? "").split("/").pop();
    if (!WRAPPERS.includes(binary))
        add(binary);
    // A web app's window class carries its host, e.g. chrome-chatgpt.com__-Default.
    for (const arg of command) {
        const url = /^(?:--app=)?["']?https?:\/\/([^/\s"']+)/i.exec(arg);
        if (url)
            add(url[1].replace(/^www\./i, ""));
    }
    return hints;
}

// Equal to a hint, or containing one long enough not to match by accident.
function matchesLaunch(hints, windowClass) {
    const cls = String(windowClass ?? "").toLowerCase();
    if (cls.length === 0)
        return false;
    return (hints ?? []).some(hint => cls === hint || (hint.length >= 4 && cls.includes(hint)));
}

// openwindow>>ADDRESS,WORKSPACENAME,CLASS,TITLE. The title may hold commas,
// the first three fields cannot.
function parseOpenWindow(data) {
    const parts = String(data ?? "").split(",");
    if (parts.length < 3 || !/^(0x)?[0-9a-f]+$/i.test(parts[0]))
        return null;
    return {
        address: parts[0].startsWith("0x") ? parts[0] : `0x${parts[0]}`,
        workspace: parts[1],
        windowClass: parts[2]
    };
}

// Moves the window to the workspace it was launched for, and that workspace
// to the monitor it was on: one that emptied and closed in the meantime is
// created again on the focused monitor. Nothing is focused, so the user stays
// where they went.
function moveLua(address, workspaceId, monitorName) {
    const id = Number(workspaceId);
    if (!/^0x[0-9a-f]+$/i.test(String(address)) || !Number.isInteger(id) || id < 1)
        return "";
    // Omarchy sets focus_on_activate, and apps such as Electron ones ask for
    // activation once they are up: the window would pull the user over to it
    // right after being sent back. Off for this window only.
    const steps = [
        `hl.dispatch(hl.dsp.window.set_prop({ prop = "focus_on_activate", value = "0", window = "address:${address}" }))`,
        `hl.dispatch(hl.dsp.window.move({ workspace = ${id}, follow = false, window = "address:${address}" }))`
    ];
    // Moving a workspace to the monitor it is already on shows it there and
    // focuses that monitor, so the move only happens when it is elsewhere.
    // get_workspace wants the id as a string: a number is not a selector.
    if (/^[A-Za-z0-9_.:-]+$/.test(String(monitorName ?? "")))
        steps.push(`local ws = hl.get_workspace("${id}")`,
            `if ws and ws.monitor and ws.monitor.name ~= "${monitorName}" then hl.dispatch(hl.dsp.workspace.move({ workspace = "${id}", monitor = "${monitorName}" })) end`);
    return steps.join("; ");
}

// activewindow>>CLASS,TITLE. A single-instance app that is already running
// focuses its window instead of opening one.
function activeWindowClass(data) {
    return String(data ?? "").split(",")[0];
}

// The notice shown on Omarchy's OSD card until the app's window appears.
// Duration 0 keeps it up until LaunchTracker closes it. The icon is the Nerd
// Font rocket.
function noticePayload(appName) {
    const name = String(appName ?? "").trim();
    return JSON.stringify({ icon: "", message: name.length > 0 ? `Opening ${name}` : "Opening", duration: 0 });
}
