pragma ComponentBehavior: Bound
import "."

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "Calculator.js" as Calculator
import "MiniApps.js" as MiniApps
import "Launch.js" as Launch

Item {
    id: root

    property string query: ""
    property bool searchMode: false
    property int selectedIndex: 0
    property int maxAppResults: 5
    property int maxWindowResults: 7
    property int maxMenuResults: 6

    readonly property string normalizedQuery: query.trim()
    readonly property bool commandMode: normalizedQuery.startsWith(">")
    readonly property string commandText: commandMode ? normalizedQuery.slice(1).trim() : ""
    readonly property bool hasQuery: normalizedQuery.length > 0
    readonly property var appResults: hasQuery && !commandMode
        ? AppSearch.fuzzyQuery(normalizedQuery).slice(0, maxAppResults)
        : []
    readonly property var windowResults: hasQuery && !commandMode
        ? root.filterWindows(normalizedQuery).slice(0, maxWindowResults)
        : []
    readonly property var menuResults: hasQuery && !commandMode
        ? MenuSearch.query(normalizedQuery, maxMenuResults)
        : []
    readonly property int commandResultCount: commandMode && commandText.length > 0 ? 1 : 0
    // Arithmetic in the query, such as 12*3+4, becomes the first result;
    // "=" forces it. Mutually exclusive with command mode, so both use index 0.
    readonly property var calcResult: hasQuery && !commandMode ? Calculator.evaluate(normalizedQuery) : null
    readonly property int calcResultCount: calcResult ? 1 : 0
    readonly property var miniAppResults: hasQuery && !commandMode
        ? MiniApps.search(normalizedQuery, 3)
        : []
    readonly property int leadingResultCount: commandResultCount + calcResultCount
        + miniAppResults.length
    readonly property int totalResults: leadingResultCount + appResults.length
        + windowResults.length + menuResults.length
    readonly property int popupWidth: Math.min(760, Math.max(520, width - 80))

    signal searchRequested()
    signal closeRequested()

    // The rendered row for the current selection. Rows differ in height (the
    // calculator card is 92, a selected result 76, the rest 54) and section
    // headers sit between them, so scrolling asks the delegate where it is
    // instead of multiplying an assumed row height.
    property Item selectedRowItem: null

    function windowHaystack(win) {
        const workspace = win?.workspace || {};
        return [
            win?.title || "",
            win?.initialTitle || "",
            win?.class || "",
            win?.initialClass || "",
            workspace.name || "",
            workspace.id || "",
            win?.monitor || ""
        ].join(" ").toLowerCase();
    }

    function filterWindows(text) {
        const needle = String(text || "").toLowerCase().trim();
        if (needle.length === 0)
            return [];
        return (ServiceManager.workspace.windowList || []).filter(win =>
            win && win.mapped && !win.hidden && win.address
                && root.windowHaystack(win).indexOf(needle) >= 0);
    }

    function clampSelection() {
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, totalResults - 1)));
    }

    function moveSelection(delta) {
        if (totalResults <= 0)
            return;
        selectedIndex = (selectedIndex + delta + totalResults) % totalResults;
        // After layout: the newly selected row grows, and its neighbour shrinks.
        Qt.callLater(resultsFlickable.ensureVisible);
    }

    // By default an app opens on a new, empty workspace. With inPlace (Shift+Enter
    // or Shift+click) it opens on the workspace that was current when the
    // Overview opened: arrow navigation only moves the selection, it never
    // switches workspace, so Hyprland's focused workspace is still that one.
    // Either way the window is pinned to that workspace, so an app that is
    // slow to start still opens there after the user has moved on.
    function launchApp(app, inPlace) {
        const script = Launch.launchLua(app?.id, !inPlace);
        if (script.length === 0)
            return;
        Quickshell.execDetached(["hyprctl", "eval", script]);
        GlobalStates.overviewOpen = false;
    }

    function openMiniApp(app, input) {
        if (!app)
            return;
        GlobalStates.overviewMiniAppInput = String(input ?? "");
        GlobalStates.overviewMiniApp = app.id;
        GlobalStates.overviewSearchMode = false;
        root.closeRequested();
    }

    function openCalculator() {
        root.openMiniApp(MiniApps.byId("calculator"), calcResult ? calcResult.expression : normalizedQuery);
    }

    // "--" keeps a negative result such as -6 from being read as an option.
    // The Overview closes on copy, so Omarchy's OSD card confirms it; -q keeps
    // that best-effort if the shell's IPC is unavailable.
    function copyCalcResult() {
        if (!calcResult)
            return;
        Quickshell.execDetached(["wl-copy", "--", calcResult.display]);
        Quickshell.execDetached(["omarchy-shell", "-q", "osd", "show",
            JSON.stringify({ icon: "\uF1EC", message: `Copied ${calcResult.grouped}`, duration: 1400 })]);
        GlobalStates.overviewOpen = false;
    }

    function focusWindow(win) {
        if (!win)
            return;
        WorkspaceNavigation.focusWindow(win);
        GlobalStates.overviewOpen = false;
    }

    function executeCommand() {
        if (commandText.length === 0)
            return;
        // xdg-terminal-exec is the freedesktop terminal dispatcher present on
        // Omarchy; execDetached keeps the terminal alive after the overview
        // closes without a vendor-specific wrapper binary.
        Quickshell.execDetached([
            "xdg-terminal-exec",
            "--app-id=ranu.panorama.command",
            "--title=Overview Command",
            "--hold",
            "-e",
            "bash",
            "-lc",
            commandText
        ]);
        GlobalStates.overviewOpen = false;
    }

    function runMenuAction(row) {
        if (!row)
            return;
        MenuSearch.runAction(row.action);
        GlobalStates.overviewOpen = false;
    }

    function activateSelection(inPlace) {
        if (commandResultCount > 0) {
            executeCommand();
            return;
        }
        if (calcResultCount > 0 && selectedIndex === 0) {
            // Enter opens the calculator so the sum can be carried on;
            // Shift+Enter is the shortcut that just copies and leaves.
            if (inPlace === true)
                copyCalcResult();
            else
                openCalculator();
            return;
        }
        const miniAppIndex = selectedIndex - commandResultCount - calcResultCount;
        if (miniAppIndex >= 0 && miniAppIndex < miniAppResults.length) {
            openMiniApp(miniAppResults[miniAppIndex], "");
            return;
        }
        const appIndex = selectedIndex - leadingResultCount;
        if (appIndex >= 0 && appIndex < appResults.length) {
            launchApp(appResults[appIndex], inPlace === true);
            return;
        }
        const windowIndex = appIndex - appResults.length;
        if (windowIndex >= 0 && windowIndex < windowResults.length) {
            focusWindow(windowResults[windowIndex]);
            return;
        }
        const menuIndex = windowIndex - windowResults.length;
        if (menuIndex >= 0 && menuIndex < menuResults.length)
            runMenuAction(menuResults[menuIndex]);
    }

    function windowTitle(win) {
        return win?.title || win?.initialTitle || "Untitled window";
    }

    function windowProgram(win) {
        return win?.class || win?.initialClass || "Window";
    }

    function workspaceLabel(win) {
        const workspace = win?.workspace || {};
        const wsId = workspace.id > 0 ? workspace.id : -1;
        const entries = ServiceManager.workspace.overviewWorkspaceEntries ?? [];
        let slot = 0;
        for (let i = 0; i < entries.length; ++i) {
            if (entries[i].id === wsId) {
                slot = i + 1;
                break;
            }
        }
        const monitor = win?.monitor ? `  ${win.monitor}` : "";
        return slot > 0 ? `Slot ${slot}${monitor}` : `Workspace${monitor}`;
    }

    onTotalResultsChanged: clampSelection()
    onQueryChanged: selectedIndex = 0


    // Query bar: shows what is being typed, above the workspace cards. It appears
    // as soon as search mode starts, even before any text, so it is clear the
    // keyboard no longer navigates workspaces.
    // Where the query bar will appear. With vim keys on, search is otherwise
    // invisible: nothing on screen says the key exists.
    Rectangle {
        id: searchHint
        anchors {
            top: parent.top
            topMargin: 24
            horizontalCenter: parent.horizontalCenter
        }
        width: hintRow.implicitWidth + 24
        height: 30
        visible: root.searchMode === false
            && GlobalStates.overviewVimKeys
        radius: 6
        color: TuiStyle.surfaceSubtle
        border.width: 1
        border.color: TuiStyle.inactiveBorder
        opacity: 0.75

        RowLayout {
            id: hintRow
            anchors.centerIn: parent
            spacing: 7

            NerdIcon {
                symbol: "search"
                iconSize: 13
                color: TuiStyle.dim
            }

            StyledText {
                text: "Press  /  to search"
                color: TuiStyle.dim
                font.pixelSize: 12
            }
        }
    }

    Rectangle {
        id: queryBar
        property bool cursorOn: true

        anchors {
            top: parent.top
            topMargin: 24
            horizontalCenter: parent.horizontalCenter
        }
        width: root.popupWidth
        height: 46
        visible: root.searchMode
        radius: 8
        color: TuiStyle.bg
        border.width: 1
        border.color: root.commandMode ? TuiStyle.accent : TuiStyle.menuBorder

        Timer {
            running: queryBar.visible
            interval: 530
            repeat: true
            onTriggered: queryBar.cursorOn = !queryBar.cursorOn
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            NerdIcon {
                symbol: root.commandMode ? "terminal" : (root.calcResultCount > 0 ? "calculator" : "search")
                iconSize: 18
                color: root.commandMode || root.calcResultCount > 0 ? TuiStyle.accent : TuiStyle.dim
            }

            StyledText {
                Layout.fillWidth: true
                text: root.hasQuery
                    ? root.query
                    : "Search apps, windows and the menu    =  calculate    >  shell command"
                color: root.hasQuery ? TuiStyle.fg : TuiStyle.dim
                font.pixelSize: 15
                elide: Text.ElideLeft
            }

            Rectangle {
                Layout.preferredWidth: 2
                Layout.preferredHeight: 19
                color: TuiStyle.accent
                opacity: queryBar.cursorOn ? 1 : 0
                visible: root.hasQuery
            }

            StyledText {
                visible: root.totalResults > 0
                text: `${root.selectedIndex + 1}/${root.totalResults}`
                color: TuiStyle.dim
                font.pixelSize: 11
            }
        }
    }

    Rectangle {
        id: resultsPopup
        anchors {
            top: queryBar.bottom
            topMargin: 8
            horizontalCenter: parent.horizontalCenter
        }
        width: root.popupWidth
        height: Math.min(resultsColumn.implicitHeight + 20, Math.max(180, root.height - y - 32))
        visible: root.searchMode && root.hasQuery
        radius: 8
        color: TuiStyle.bg
        border.width: 1
        border.color: TuiStyle.menuBorder
        clip: true

        Flickable {
            id: resultsFlickable
            anchors.fill: parent
            anchors.margins: 10
            contentWidth: width
            contentHeight: resultsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            function ensureVisible() {
                const item = root.selectedRowItem;
                if (!item || item.height <= 0)
                    return;
                const margin = 8;
                const top = item.y - margin;
                const bottom = item.y + item.height + margin;
                const maxContentY = Math.max(0, contentHeight - height);
                if (top < contentY)
                    contentY = Math.max(0, top);
                else if (bottom > contentY + height)
                    contentY = Math.min(maxContentY, bottom - height);
            }

            ColumnLayout {
                id: resultsColumn
                width: resultsFlickable.width
                spacing: 6

                SearchResultRow {
                    Layout.fillWidth: true
                    visible: root.commandResultCount > 0
                    resultIndex: 0
                    title: root.commandText
                    subtitle: "Open an independent terminal and run this command"
                    meta: "Terminal command"
                    symbol: "terminal"
                    selected: root.selectedIndex === resultIndex
                    onActivated: root.executeCommand()
                }

                CalcCard {
                    Layout.fillWidth: true
                    visible: root.calcResultCount > 0
                    selected: root.selectedIndex === 0
                    result: root.calcResult
                    onActivated: inPlace => inPlace ? root.copyCalcResult() : root.openCalculator()
                }

                SearchSectionHeader {
                    Layout.fillWidth: true
                    visible: root.miniAppResults.length > 0
                    label: "Mini apps"
                    count: root.miniAppResults.length
                }

                Repeater {
                    model: root.miniAppResults

                    SearchResultRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        resultIndex: root.commandResultCount + root.calcResultCount + index
                        title: modelData?.title || ""
                        subtitle: modelData?.subtitle || ""
                        meta: "Opens in Overview"
                        symbol: modelData?.icon || "apps"
                        selected: root.selectedIndex === resultIndex
                        onActivated: root.openMiniApp(modelData, "")
                    }
                }

                SearchSectionHeader {
                    Layout.fillWidth: true
                    visible: root.appResults.length > 0
                    label: "Applications"
                    count: root.appResults.length
                }

                Repeater {
                    model: root.appResults

                    SearchResultRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        resultIndex: root.leadingResultCount + index
                        title: modelData?.name || ""
                        subtitle: modelData?.comment || modelData?.genericName || modelData?.id || ""
                        // The selected row spells out both keys; the others stay short.
                        meta: selected ? "Enter new · Shift+Enter here" : "New workspace"
                        iconSource: AppSearch.iconSource(modelData?.icon || "")
                        selected: root.selectedIndex === resultIndex
                        onActivated: inPlace => root.launchApp(modelData, inPlace)
                    }
                }

                SearchSectionHeader {
                    Layout.fillWidth: true
                    visible: root.windowResults.length > 0
                    label: "Open Windows"
                    count: root.windowResults.length
                }

                Repeater {
                    model: root.windowResults

                    SearchResultRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        resultIndex: root.leadingResultCount + root.appResults.length + index
                        title: root.windowTitle(modelData)
                        subtitle: root.windowProgram(modelData)
                        meta: root.workspaceLabel(modelData)
                        iconSource: AppSearch.iconSource(AppSearch.guessIcon(root.windowProgram(modelData)))
                        selected: root.selectedIndex === resultIndex
                        onActivated: root.focusWindow(modelData)
                    }
                }

                SearchSectionHeader {
                    Layout.fillWidth: true
                    visible: root.menuResults.length > 0
                    label: "Command Menu"
                    count: root.menuResults.length
                }

                Repeater {
                    model: root.menuResults

                    SearchResultRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        resultIndex: root.leadingResultCount + root.appResults.length + root.windowResults.length + index
                        title: modelData?.label || ""
                        subtitle: modelData?.description || modelData?.action || ""
                        meta: modelData?.path || "Omarchy menu"
                        symbol: "menu"
                        selected: root.selectedIndex === resultIndex
                        onActivated: root.runMenuAction(modelData)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    visible: root.totalResults === 0
                    text: root.commandMode
                        ? "Type a command after >"
                        : "No matching applications, windows or menu actions"
                    color: TuiStyle.dim
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 13
                }
            }
        }
    }

    component SearchSectionHeader: Item {
        required property string label
        property int count: 0
        implicitHeight: 26

        StyledText {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 8
                rightMargin: 8
            }
            height: 20
            text: `${parent.label}  ${parent.count}`
            color: TuiStyle.dim
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }


    // The calculator answer, set apart from the result list: the expression as
    // it reads best, the result large in the accent colour, and a keycap hint.
    component CalcCard: Rectangle {
        id: card
        property var result: null
        property bool selected: false
        // inPlace is Shift: copy without opening the calculator.
        signal activated(bool inPlace)

        implicitHeight: 92
        radius: 8
        color: selected ? TuiStyle.accentWash(TuiStyle.accent) : TuiStyle.surfaceSubtle

        onSelectedChanged: if (card.selected) root.selectedRowItem = card
        border.width: 1
        border.color: selected ? TuiStyle.accent : TuiStyle.surfaceRaised

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 10
                color: TuiStyle.accentWash(TuiStyle.accent)

                NerdIcon {
                    anchors.centerIn: parent
                    symbol: "calculator"
                    iconSize: 22
                    color: TuiStyle.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: card.result?.pretty ?? ""
                    color: TuiStyle.dim
                    font.pixelSize: 13
                    elide: Text.ElideLeft
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.result ? `= ${card.result.grouped}` : ""
                    color: TuiStyle.accent
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    elide: Text.ElideLeft
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: keyRow.implicitWidth + 16
                implicitHeight: 26
                radius: 6
                color: "transparent"
                border.width: 1
                border.color: card.selected ? TuiStyle.accent : TuiStyle.inactiveBorder

                RowLayout {
                    id: keyRow
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        text: "\u23CE"
                        color: card.selected ? TuiStyle.accent : TuiStyle.dim
                        font.pixelSize: 13
                    }

                    StyledText {
                        text: "Open"
                        color: card.selected ? TuiStyle.fg : TuiStyle.dim
                        font.pixelSize: 12
                    }

                    StyledText {
                        text: "\u21E7\u23CE"
                        color: card.selected ? TuiStyle.accent : TuiStyle.dim
                        font.pixelSize: 13
                    }

                    StyledText {
                        text: "Copy"
                        color: card.selected ? TuiStyle.fg : TuiStyle.dim
                        font.pixelSize: 12
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = 0
            onClicked: mouse => card.activated((mouse.modifiers & Qt.ShiftModifier) !== 0)
        }
    }

    component SearchResultRow: Rectangle {
        id: row
        required property int resultIndex
        required property string title
        property string subtitle: ""
        property string meta: ""
        property string iconSource: ""
        property string symbol: "apps"
        property bool selected: false
        // inPlace is true for Shift+click; only app rows use it.
        signal activated(bool inPlace)

        // The selected row grows: taller, larger icon and title, accent border.
        // Sizes are animated rather than scaled so the text keeps its hinting
        // instead of being resampled.
        readonly property real grow: selected ? 1 : 0

        implicitHeight: 54 + 22 * grow
        radius: 6
        color: selected ? TuiStyle.selection : "transparent"
        border.width: selected ? 1 : 0
        border.color: TuiStyle.accent

        onSelectedChanged: if (row.selected) root.selectedRowItem = row

        Behavior on implicitHeight {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10 + 2 * row.grow
            anchors.rightMargin: 12
            spacing: 11

            Rectangle {
                Layout.preferredWidth: 34 + 14 * row.grow
                Layout.preferredHeight: 34 + 14 * row.grow
                radius: 6

                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
                color: row.selected ? TuiStyle.accentWash(TuiStyle.accent) : TuiStyle.surfaceSubtle

                Image {
                    anchors.centerIn: parent
                    width: 24 + 10 * row.grow
                    height: 24 + 10 * row.grow
                    source: row.iconSource
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready
                }

                NerdIcon {
                    anchors.centerIn: parent
                    symbol: row.symbol
                    iconSize: 21 + 9 * row.grow
                    color: row.selected ? TuiStyle.accent : TuiStyle.dim
                    visible: row.iconSource.length === 0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: row.title
                    color: TuiStyle.fg
                    font.pixelSize: 14 + 5 * row.grow
                    font.weight: row.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: row.subtitle
                    color: TuiStyle.dim
                    font.pixelSize: 12 + 2 * row.grow
                    elide: Text.ElideRight
                }
            }

            StyledText {
                Layout.maximumWidth: 210
                text: row.meta
                color: row.selected ? TuiStyle.fg : TuiStyle.dim
                font.pixelSize: 11
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = row.resultIndex
            onClicked: mouse => row.activated((mouse.modifiers & Qt.ShiftModifier) !== 0)
        }
    }
}
