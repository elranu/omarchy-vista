import QtQuick
import qs.Commons

Text {
    id: root

    property string symbol: "apps"
    property real iconSize: 18

    function glyphFor(name) {
        switch (String(name || "apps")) {
        case "add": return "\uF067";                // fa-plus
        case "apps": return "\uF00A";                // fa-th-large
        case "select_window": return "\uF24D";       // fa-object-group
        case "terminal": return "\uF120";            // fa-terminal
        case "search": return "\uF002";              // fa-search
        case "menu": return "\uF0C9";                // fa-bars
        case "calculator": return "\uF1EC";          // fa-calculator
        case "monitor": return "\uF108";            // fa-desktop
        case "note": return "\uF0F6";               // fa-file-text-o
        case "save": return "\uF0C7";               // fa-floppy-o
        case "capture": return "\uF1D8";            // fa-paper-plane
        case "refresh": return "\uF021";            // fa-refresh
        case "undo": return "\uF0E2";               // fa-undo
        case "apply": return "\uF00C";              // fa-check
        case "forget": return "\uF014";             // fa-trash-o
        case "rename": return "\uF040";             // fa-pencil
        case "open": return "\uF07C";               // fa-folder-open
        case "copy": return "\uF0C5";               // fa-files-o
        case "window": return "\uF2D0";             // fa-window-maximize
        default: return "\uF00A";                     // fa-th-large
        }
    }

    text: root.glyphFor(root.symbol)
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font {
        // Style.fontFamily is not guaranteed to contain private-use Nerd Font
        // glyphs. Keep the icon font explicit; changing this to the text theme
        // font makes every fallback icon render as an empty box.
        family: "JetBrainsMono Nerd Font"
        pixelSize: root.iconSize
    }
}
