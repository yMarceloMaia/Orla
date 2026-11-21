import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/bin/orla"
    property var state: ({
            cfg: {
                pins: [],
                size: 46,
                auto: true,
                zoom: true,
                position: "bottom",
                folders: []
            },
            clients: [],
            monitors: []
        })
    ListModel { id: trayFiles }
    property var planUsage: []
    Process {
        id: usageFetch
        command: [root.helper, "usage"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim()) root.planUsage = JSON.parse(text)
        }
    }
    Timer {
        interval: 600000
        running: root.cfg.usageWidget === true
        triggeredOnStart: true
        repeat: true
        onTriggered: usageFetch.running = true
    }
    property var githubData: ({})
    property var githubBaseline: null
    property double githubSince: 0
    function updateGithub(result) {
        const previous = githubBaseline;
        const watching = cfg.githubWidget && cfg.githubAlerts !== false;
        const current = result.alerts;
        if (watching && previous && previous.login === result.login) {
            for (const [url, pr] of Object.entries(current)) {
                const old = previous.alerts[url];
                if (!old && Date.parse(pr.created) < githubSince) continue;
                const added = pr.count - (old?.count || 0);
                const messages = [];
                if (added > 0) messages.push(added === 1 ? "Novo comentário" : added + " novos comentários");
                if (pr.merge === "CONFLICTING" && old?.merge !== "CONFLICTING")
                    messages.push("Conflito de merge");
                if (pr.merge === "UNKNOWN" && old) pr.merge = old.merge;
                if (messages.length)
                    Quickshell.execDetached(["notify-send", "--app-name=Orla", "--", pr.repo + " #" + pr.number, messages.join(" · ")]);
            }
        }
        githubBaseline = watching ? result : null;
        githubSince = Date.now();
        githubData = result;
    }
    readonly property bool githubWatching: !!cfg.githubWidget && cfg.githubAlerts !== false
    onGithubWatchingChanged: githubBaseline = null
    property string githubError: ""
    Process {
        id: githubFetch
        command: [root.helper, "github"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                const result = JSON.parse(text);
                root.githubError = result.error || "";
                if (!result.error) root.updateGithub(result);
            }
        }
    }
    Timer {
        interval: root.githubWatching ? 300000 : 900000
        running: root.cfg.githubWidget === true
        triggeredOnStart: true
        repeat: true
        onTriggered: githubFetch.running = true
    }
    property var lastPlacement: ({})
    signal windowMinimized(var client)
    property var cfg: state.cfg
    readonly property bool light: cfg.appearance === "light" || (cfg.appearance !== "dark" && (state.visuals?.mode ? state.visuals.mode === "light" : Qt.styleHints.colorScheme === Qt.Light))
    readonly property bool motion: !cfg.reduceMotion && state.visuals?.animations !== false
    readonly property bool useThemePalette: cfg.appearance === "system" || cfg.appearance === state.visuals?.mode
    readonly property color background: (useThemePalette && state.visuals?.background) || (light ? "#fafafe" : "#262830")
    readonly property color ink: (useThemePalette && state.visuals?.foreground) || (light ? "#24252d" : "#f3f3f8")
    readonly property color surface: Qt.alpha(background, cfg.glass ? 0.96 : 1)
    readonly property color focusAccent: root.state.visuals?.accent || (light ? "#35589d" : "#96baff")
    readonly property color outline: light ? "#809598a3" : "#70778090"
    function cmd(...args) {
        Quickshell.execDetached([helper, ...args]);
    }
    function set(key, v) {
        cmd("set", key, JSON.stringify(v));
    }
    function appFor(id) {
        return DesktopEntries.applications.values.find(e => e.id === id) || DesktopEntries.heuristicLookup(id);
    }
    function newWindow(app) {
        if (!app)
            return;
        const action = app.actions.find(a => /^(new[-_ ]?window|open[-_ ]?new[-_ ]?window)$/i.test(a.id));
        if (action)
            action.execute();
        else
            app.execute();
    }
    function entry(c) {
        return DesktopEntries.heuristicLookup(c.initialClass || c.class);
    }
    function key(c) {
        let e = entry(c);
        return e ? e.id : c.class;
    }
    Process {
        id: watcher
        command: [root.helper, "watch"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const previous = root.state.clients;
                const next = JSON.parse(data);
                root.state = next;
                for (const address of Object.keys(root.lastPlacement))
                    if (!next.clients.some(w => w.address === address && w.parked)) delete root.lastPlacement[address];
                if (!previous.length) return;
                for (const window of next.clients) {
                    const old = previous.find(w => w.address === window.address);
                    if (old && !old.parked && window.parked) {
                        root.lastPlacement[window.address] = old;
                        if (root.motion) root.windowMinimized(old);
                    }
                }
            }
        }
        onExited: retry.restart()
    }
    Timer {
        id: retry
        interval: 1500
        onTriggered: watcher.running = true
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            property var monitor: root.state.monitors.find(m => m.name === modelData.name)
            WindowTransition {
                id: transition
                screen: panel.screen
                accent: root.focusAccent
                onRestoreReady: address => root.cmd("focus", address)
            }
            Connections {
                target: root
                function onWindowMinimized(client) { panel.animateWindow(client, false); }
            }
            function requestWindow(action, ...addresses) {
                if (root.motion && (action === "cycle" || action === "focus")) {
                    for (const address of addresses) {
                        const parked = root.state.clients.find(w => w.address === address && w.parked);
                        if (!parked) continue;
                        if (transition.pendingAddress === address) return;
                        const saved = root.lastPlacement[address];
                        const geometry = saved || Object.assign({}, parked, { workspace: {id: parked.origin}, monitor: panel.monitor?.id });
                        if (animateWindow(geometry, true)) return;
                        break;
                    }
                }
                root.cmd(action, ...addresses);
            }
            function animateWindow(client, restored) {
                const mon = panel.monitor;
                if (!mon || panel.fullscreen || client.monitor !== mon.id ||
                    client.workspace.id !== mon.activeWorkspace.id || !client.size || !client.at) return;
                const key = root.key(client);
                const tile = tiles.children.find(item => item.modelData === key && item.app !== undefined);
                if (!tile || client.size[0] <= 0 || client.size[1] <= 0) return;
                const center = tile.mapToItem(panel.contentItem, tile.width / 2, tile.height / 2);
                const cx = panel.vertical ? (root.cfg.position === "left" ? panel.extent / 2 : panel.screen.width - panel.extent / 2)
                                          : (panel.screen.width - panel.width) / 2 + center.x;
                const cy = panel.vertical ? (panel.screen.height - panel.height) / 2 + center.y : panel.screen.height - panel.extent / 2;
                const edge = panel.iconSize;
                transition.play(Qt.rect(client.at[0] - mon.x, client.at[1] - mon.y, client.size[0], client.size[1]),
                                Qt.rect(cx - edge / 2, cy - edge / 2, edge, edge),
                                Quickshell.iconPath(tile.app?.icon || "application-x-executable", true), restored, client.address);
                return true;
            }
            property var wins: root.state.clients.filter(c => monitor && c.origin === monitor.activeWorkspace.id).sort((a, b) => a.address.localeCompare(b.address))
            property bool vertical: root.cfg.position !== "bottom"
            readonly property int displayedWorkspace: monitor?.specialWorkspace?.id || monitor?.activeWorkspace?.id || 0
            readonly property bool fullscreen: !!monitor && root.state.clients.some(c => c.mapped && !c.hidden && c.workspace.id === displayedWorkspace && (c.fullscreen & 2) !== 0)
            visible: !fullscreen
            onFullscreenChanged: if (fullscreen) {
                tipTarget = null;
                endDrag();
                menu.close();
            }
            property bool shown: !fullscreen && (dragging !== "" || !root.cfg.auto || hover.hovered || (tipTarget?.windows?.length > 1 && !tipDelay.running) || fileDragGrace.running || fileHoverCount > 0 || menu.opened || fileTray.receiving || fileTray.opened || usageTile.opened || githubTile.opened || stack.opened || resizeSize > 0 || linger.running)
            property int fileHoverCount: 0
            property int resizeSize: 0
            readonly property int iconSize: resizeSize || root.cfg.size
            property var documents: []
            Process {
                id: docReader
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (menu.visible && docReader.command[2] === panel.selected)
                            panel.documents = text.trim() ? JSON.parse(text) : [];
                    }
                }
            }
            property string stackPath: ""
            readonly property var recentEntries: {
                const running = root.state.clients.map(c => root.key(c));
                const entries = (root.state.recent || []).map(k => root.appFor(k)).filter(Boolean);
                return root.cfg.recentApps ? entries.filter((e, i) => !running.includes(e.id) && !root.cfg.pins.includes(e.id) && entries.findIndex(o => o.id === e.id) === i).slice(0, 3) : [];
            }
            property string dragging: ""
            property int dropIndex: -1
            property real dragOffset: 0
            function orderedKeys() {
                const visibleKeys = [...new Set([...root.cfg.pins, ...wins.map(c => root.key(c))])];
                const saved = root.cfg.order || [];
                return [...saved.filter(k => visibleKeys.includes(k)), ...visibleKeys.filter(k => !saved.includes(k))];
            }
            function reorder(key, destination) {
                const keys = orderedKeys();
                const from = keys.indexOf(key);
                if (from < 0 || destination === from || destination < 0 || destination >= keys.length)
                    return;
                keys.splice(from, 1);
                keys.splice(destination, 0, key);
                // Keep the slots of apps that are currently on other workspaces.
                let next = 0;
                const merged = (root.cfg.order || []).map(k => keys.includes(k) ? keys[next++] : k);
                root.set("order", merged.concat(keys.slice(next)));
            }
            function endDrag() {
                dragging = "";
                dragOffset = 0;
                dropIndex = -1;
            }
            property string selected: ""
            readonly property bool windowMenuVisible: menu.visible
            property var selectedWins: []
            function openMenu(key, button) {
                selected = key;
                selectedWins = key ? wins.filter(c => root.key(c) === key) : [];
                tipTarget = null;
                const center = button.mapToItem(panel.contentItem, button.width / 2, button.height / 2);
                menuHost.anchorPoint = center;
                menuHost.visible = true;
                menu.open();
            }
            function toggleMenuWindow(window) {
                panel.requestWindow(window.parked ? "focus" : "minimize", window.address);
                menu.close();
            }
            property Item tipTarget: null
            function tip(item, show) {
                if (show) {
                    tipExit.stop();
                    tipTarget = item;
                    tipDelay.restart();
                } else if (tipTarget === item) {
                    tipExit.restart();
                }
            }
            Timer {
                id: tipExit
                interval: 320
                onTriggered: {
                    if (!previewHover.hovered && !panel.tipTarget?.hovered && !hover.hovered)
                        panel.tipTarget = null;
                }
            }
            Timer {
                id: tipDelay
                interval: 450
            }
            PanelWindow {
                id: hint
                visible: !panel.dragging && !!panel.tipTarget && (panel.tipTarget.hovered || panel.tipTarget.windows?.length > 1) && !tipDelay.running && !menu.opened && panel.shown
                color: "transparent"
                mask: Region {
                    item: hint.previews.length ? hintBody : null
                }
                property var previews: (panel.tipTarget?.windows?.length > 1 && visible) ? panel.tipTarget.windows.slice(0, Math.max(1, Math.min(5, Math.floor(panel.screen.width / 145)))) : []
                implicitWidth: previews.length ? previews.length * 138 + 12 : Math.min(280, label.implicitWidth + 20)
                implicitHeight: previews.length ? 116 : 28
                screen: panel.screen
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "orla-preview"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                readonly property point center: panel.tipTarget ? panel.tipTarget.mapToItem(panel.contentItem, panel.tipTarget.width / 2, panel.tipTarget.height / 2) : Qt.point(0, 0)
                anchors.left: !panel.vertical || root.cfg.position === "left"
                anchors.right: panel.vertical && root.cfg.position === "right"
                anchors.bottom: !panel.vertical
                anchors.top: panel.vertical
                margins.bottom: panel.vertical ? 0 : panel.extent - 4
                margins.left: panel.vertical ? panel.extent - 4 : Math.max(0, Math.min(screen.width - width, (screen.width - panel.width) / 2 + center.x - width / 2))
                margins.right: panel.vertical ? panel.extent - 4 : 0
                margins.top: panel.vertical ? Math.max(0, Math.min(screen.height - height, (screen.height - panel.height) / 2 + center.y - height / 2)) : 0
                Rectangle {
                    id: hintBody
                    HoverHandler {
                        id: previewHover
                        enabled: hint.previews.length > 0
                        onHoveredChanged: {
                            if (hovered)
                                tipExit.stop();
                            else
                                tipExit.restart();
                        }
                    }
                    anchors.fill: parent
                    radius: 9
                    color: root.surface
                    border.color: root.outline
                    Text {
                        id: label
                        visible: !hint.previews.length
                        anchors.fill: parent
                        anchors.margins: 2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: root.ink
                        text: panel.tipTarget?.Accessible.name || ""
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Repeater {
                            model: hint.previews
                            Column {
                                required property var modelData
                                TapHandler {
                                    onTapped: {
                                        const address = parent.modelData.address;
                                        panel.requestWindow("focus", address);
                                        panel.tipTarget = null;
                                    }
                                }
                                width: 132
                                spacing: 4
                                WindowThumb {
                                    width: 132
                                    height: 84
                                    client: parent.modelData
                                }
                                Text {
                                    width: parent.width
                                    color: root.ink
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    text: parent.modelData.title
                                }
                            }
                        }
                    }
                }
            }
            anchors.bottom: !vertical
            anchors.left: root.cfg.position === "left"
            anchors.right: root.cfg.position === "right"
            property int extent: panel.iconSize + 22
            property real reveal: shown ? 1 : 0
            Behavior on reveal {
                enabled: root.motion && root.cfg.auto && !panel.fullscreen
                NumberAnimation {
                    duration: 170
                    easing.type: Easing.OutCubic
                }
            }
            readonly property bool expanded: shown || reveal > 0
            implicitWidth: vertical ? (expanded ? extent : 3) : Math.min(screen.width, tiles.implicitWidth + 28)
            implicitHeight: vertical ? Math.min(screen.height, tiles.implicitHeight + 28) : (expanded ? extent : 3)
            exclusiveZone: root.cfg.auto ? 0 : extent
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            WlrLayershell.namespace: "orla-dock"
            BackgroundEffect.blurRegion: panel.reveal > 0 && !root.cfg.islands && root.cfg.glass && root.state.visuals?.blur ? shelfRegion : null
            Region {
                id: shelfRegion
                item: shelf
                radius: shelf.radius
            }
            HoverHandler {
                id: hover
                onHoveredChanged: if (!hovered) {
                    linger.restart();
                    tipExit.restart();
                }
            }
            Timer { id: fileDragGrace; interval: 800 }
            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: event => { fileDragGrace.restart(); event.accept(Qt.CopyAction) }
                onPositionChanged: fileDragGrace.restart()
                onDropped: event => { event.accepted = false }
            }
            Timer {
                id: linger
                interval: 450
            }
            Rectangle {
                id: shelf
                anchors.fill: parent
                visible: panel.reveal > 0
                opacity: panel.reveal
                transform: Translate {
                    x: panel.vertical ? (root.cfg.position === "left" ? -1 : 1) * panel.extent * (1 - panel.reveal) : 0
                    y: panel.vertical ? 0 : panel.extent * (1 - panel.reveal)
                }
                anchors.margins: 3
                radius: 21
                color: "transparent"
                gradient: root.cfg.islands ? null : shelfGradient
                Gradient {
                    id: shelfGradient
                    GradientStop {
                        position: 0
                        color: Qt.alpha(Qt.tint(root.background, Qt.alpha(root.ink, 0.09)), root.cfg.glass ? 0.84 : 1)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(root.background, root.cfg.glass ? 0.78 : 1)
                    }
                }
                border.color: root.cfg.islands ? "transparent" : root.outline
                Rectangle {
                    visible: !root.cfg.islands
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 20
                    color: "transparent"
                    border.color: "#25ffffff"
                }
                Grid {
                    id: tiles
                    anchors.centerIn: parent
                    columns: panel.vertical ? 1 : children.length
                    spacing: root.cfg.islands ? 8 : 5
                    Repeater {
                        property string keyList: JSON.stringify(panel.orderedKeys())
                        model: JSON.parse(keyList)
                        ToolButton {
                            id: tile
                            required property string modelData
                            required property int index
                            readonly property int sourceIndex: panel.dragging ? panel.orderedKeys().indexOf(panel.dragging) : -1
                            readonly property real shift: !panel.dragging ? 0 : panel.dragging === modelData ? panel.dragOffset : index > sourceIndex && index <= panel.dropIndex ? -(width + tiles.spacing) : index < sourceIndex && index >= panel.dropIndex ? width + tiles.spacing : 0
                            property var app: root.appFor(tile.modelData)
                            property var windows: panel.wins.filter(c => root.key(c) === modelData)
                            width: panel.iconSize
                            height: width
                            readonly property bool hasFocusedWindow: windows.some(w => !w.parked && w.address === root.state.active)
                            background: Rectangle {
                                radius: Math.round(tile.width * 0.25)
                                color: Qt.alpha(root.focusAccent, root.light ? 0.20 : 0.32)
                                border.color: Qt.alpha(root.light ? Qt.darker(root.focusAccent, 1.25) : Qt.lighter(root.focusAccent, 1.4), 0.9)
                                border.width: 1
                                opacity: tile.hasFocusedWindow ? 1 : 0
                                Behavior on opacity {
                                    enabled: root.motion
                                    NumberAnimation { duration: 110 }
                                }
                                transform: Translate {
                                    x: panel.vertical ? 0 : tile.shift
                                    y: panel.vertical ? tile.shift : 0
                                }
                            }
                            hoverEnabled: true
                            z: panel.dragging === modelData ? 2 : hovered ? 1 : 0
                            padding: 0
                            contentItem: DockGlyph {
                                transform: Translate {
                                    x: panel.vertical ? 0 : tile.shift
                                    y: panel.vertical ? tile.shift : 0
                                }
                                button: tile
                                source: Quickshell.iconPath(tile.app?.icon || tile.modelData, true)
                                edge: root.cfg.position
                                zoomEnabled: root.cfg.zoom
                                motion: root.motion
                            }
                            Rectangle {
                                visible: tile.windows.length > 1
                                z: 5
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -2
                                anchors.rightMargin: -1
                                transform: Translate {
                                    x: panel.vertical ? 0 : tile.shift
                                    y: panel.vertical ? tile.shift : 0
                                }
                                height: 18
                                width: Math.max(height, countLabel.implicitWidth + 8)
                                radius: height / 2
                                color: "#364760"
                                border.color: "#b6c5da"
                                Text {
                                    id: countLabel
                                    anchors.centerIn: parent
                                    color: "white"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    text: tile.windows.length
                                }
                            }
                            FileDrop {
                                anchors.fill: parent; z: 4
                                helper: root.helper; light: root.light; appId: tile.app?.id || ""
                                onContainsDragChanged: { panel.fileHoverCount += containsDrag ? 1 : -1; fileDragGrace.restart() }
                                onLaunchRequested: if (root.cfg.launchAnimation) tile.contentItem.bounce()
                                onCompatibleChanged: if (compatible) panel.tipTarget = null
                            }
                            property var preview: hovered && windows.length === 1 && windows[0].parked ? Hyprland.toplevels.values.find(t => String(t.address).replace(/^0x/, "") === windows[0].address.slice(2))?.wayland : null
                            Loader {
                                anchors.fill: parent
                                anchors.margins: 5
                                active: !!tile.preview
                                sourceComponent: ScreencopyView {
                                    captureSource: tile.preview || null
                                    live: false
                                    paintCursor: false
                                }
                            }
                            Accessible.name: app?.name || modelData
                            onHoveredChanged: panel.tip(tile, hovered)
                            TapHandler {
                                acceptedButtons: Qt.MiddleButton
                                onTapped: { if (root.cfg.launchAnimation && tile.app) tile.contentItem.bounce(); root.newWindow(tile.app) }
                            }
                            function activateApp() {
                                if (!windows.length) {
                                    if (app && root.cfg.launchAnimation)
                                        contentItem.bounce();
                                    app?.execute();
                                    return;
                                }
                                panel.requestWindow("cycle", ...windows.map(w => w.address));
                            }
                            onClicked: activateApp()
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                preventStealing: true
                                property real start: 0
                                property bool moved: false
                                cursorShape: panel.dragging === tile.modelData ? Qt.ClosedHandCursor : Qt.ArrowCursor
                                onPressed: mouse => {
                                    start = panel.vertical ? mouse.y : mouse.x;
                                    moved = false;
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed)
                                        return;
                                    const delta = (panel.vertical ? mouse.y : mouse.x) - start;
                                    if (!moved && Math.abs(delta) < Qt.styleHints.startDragDistance)
                                        return;
                                    moved = true;
                                    panel.tipTarget = null;
                                    panel.dragging = tile.modelData;
                                    const step = tile.width + tiles.spacing;
                                    const last = panel.orderedKeys().length - 1;
                                    panel.dragOffset = Math.max(-tile.index * step, Math.min((last - tile.index) * step, delta));
                                    panel.dropIndex = tile.index + Math.round(panel.dragOffset / step);
                                }
                                onReleased: mouse => {
                                    if (!moved) {
                                        if (contains(Qt.point(mouse.x, mouse.y)))
                                            tile.activateApp();
                                        return;
                                    }
                                    const pt = mapToItem(panel.contentItem, mouse.x, mouse.y);
                                    if (panel.contentItem.contains(pt))
                                        panel.reorder(tile.modelData, panel.dropIndex);
                                    panel.endDrag();
                                }
                                onCanceled: if (moved)
                                    panel.endDrag()
                                Component.onDestruction: if (moved && panel && panel.dragging === tile.modelData)
                                    panel.endDrag()
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: {
                                    panel.openMenu(tile.modelData, tile);
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.cfg.islands ? Math.round(tile.width * 0.27) : 4
                                height: 4
                                radius: 2
                                visible: root.cfg.indicators !== false && tile.windows.length > 0
                                color: tile.windows.every(w => w.parked) ? (root.light ? "#955300" : "#f9bd68") : root.ink
                            }
                        }
                    }
                    Item {
                        width: panel.vertical ? panel.iconSize : 12
                        height: panel.vertical ? 12 : panel.iconSize
                        Rectangle {
                            anchors.centerIn: parent
                            width: panel.vertical ? parent.width * 0.66 : 2
                            height: panel.vertical ? 2 : parent.height * 0.66
                            radius: 1
                            visible: !root.cfg.islands || grip.containsMouse || grip.pressed
                            color: grip.containsMouse ? "#e1e3ef" : "#80838f"
                        }
                        MouseArea {
                            id: grip
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: panel.vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor
                            property real start: 0
                            property int initial: 0
                            function coordinate(m) {
                                const pt = mapToGlobal(m.x, m.y);
                                return panel.vertical ? (root.cfg.position === "left" ? pt.x : -pt.x) : -pt.y;
                            }
                            onPressed: m => {
                                start = coordinate(m);
                                initial = root.cfg.size;
                                panel.resizeSize = initial;
                            }
                            onPositionChanged: m => {
                                if (pressed)
                                    panel.resizeSize = Math.max(30, Math.min(68, initial + Math.round(coordinate(m) - start)));
                            }
                            onReleased: {
                                const value = panel.resizeSize;
                                panel.resizeSize = 0;
                                if (value !== initial)
                                    root.set("size", value);
                            }
                            onCanceled: panel.resizeSize = 0
                        }
                    }
                    Repeater {
                        model: panel.recentEntries
                        ToolButton {
                            required property var modelData
                            width: panel.iconSize
                            height: width
                            background: Item {}
                            Accessible.name: modelData.name + " · recente"
                            contentItem: DockGlyph {
                                button: parent
                                source: Quickshell.iconPath(parent.modelData.icon, true)
                                edge: root.cfg.position
                                zoomEnabled: root.cfg.zoom
                                motion: root.motion
                            }
                            onHoveredChanged: panel.tip(this, hovered)
                            FileDrop {
                                anchors.fill: parent
                                helper: root.helper; light: root.light; appId: parent.modelData.id
                                onContainsDragChanged: { panel.fileHoverCount += containsDrag ? 1 : -1; fileDragGrace.restart() }
                                onLaunchRequested: if (root.cfg.launchAnimation) parent.contentItem.bounce()
                            }
                            onClicked: {
                                if (root.cfg.launchAnimation)
                                    contentItem.bounce();
                                modelData.execute();
                            }
                        }
                    }
                    Repeater {
                        model: root.cfg.stacks ? root.cfg.folders : []
                        ToolButton {
                            required property string modelData
                            width: panel.iconSize
                            height: width
                            background: Item {}
                            Accessible.name: modelData
                            contentItem: DockGlyph {
                                button: parent
                                source: Quickshell.iconPath("folder", true)
                                edge: root.cfg.position
                                zoomEnabled: root.cfg.zoom
                                motion: root.motion
                            }
                            onHoveredChanged: panel.tip(this, hovered)
                            onClicked: {
                                panel.stackPath = modelData;
                                stack.parent = this;
                                stack.open();
                            }
                        }
                    }
                    Repeater {
                        model: root.cfg.separateMinimized ? panel.wins.filter(w => w.parked) : []
                        ToolButton {
                            required property var modelData
                            width: panel.iconSize
                            height: width
                            Accessible.name: modelData.title + " · minimizada"
                            contentItem: WindowThumb {
                                client: parent.modelData
                                capturing: panel.shown
                            }
                            onHoveredChanged: panel.tip(this, hovered)
                            onClicked: panel.requestWindow("focus", modelData.address)
                        }
                    }
                    FileTray {
                        id: fileTray
                        visible: root.cfg.fileTray !== false
                        files: trayFiles
                        edge: panel.iconSize
                        vertical: panel.vertical
                        leftEdge: root.cfg.position === "left"
                        surface: root.background
                        ink: root.ink
                        accent: root.focusAccent
                        onHoveredChanged: panel.tip(fileTray, hovered && !opened)
                        onOpenedChanged: if (opened && panel.tipTarget === fileTray) panel.tipTarget = null
                    }
                    UsageTile {
                        id: usageTile
                        onShowAccountHintChanged: {
                            if (showAccountHint) panel.tip(usageTile, true);
                            else if (panel.tipTarget === usageTile) panel.tipTarget = null;
                        }
                        profile: root.cfg.usageCompact === true ? "Claude" : (root.cfg.usageCompact || "all")
                        onSelectProfile: name => root.set("usageCompact", name)
                        visible: root.cfg.usageWidget === true
                        edge: panel.iconSize
                        vertical: panel.vertical
                        leftEdge: root.cfg.position === "left"
                        accounts: root.planUsage
                        busy: usageFetch.running
                        ink: root.ink
                        surface: root.background
                        onRefresh: usageFetch.running = true
                    }
                    GithubTile {
                        id: githubTile
                        compact: root.cfg.githubCompact === true
                        onToggleCompact: root.set("githubCompact", !compact)
                        visible: root.cfg.githubWidget === true
                        edge: panel.iconSize
                        vertical: panel.vertical
                        leftEdge: root.cfg.position === "left"
                        maxPanelWidth: panel.screen.width - 16
                        maxPanelHeight: panel.screen.height - panel.extent - 16
                        data: root.githubData
                        errorText: root.githubError
                        busy: githubFetch.running
                        surface: root.background
                        ink: root.ink
                        onRefresh: githubFetch.running = true
                    }
                    MediaTile {
                        id: mediaTile
                        enabled: root.cfg.mediaPlayer !== false
                        edge: panel.iconSize
                        compact: panel.vertical || panel.screen.width < 28 + 203 + edge + tiles.spacing
                            + tiles.children.reduce((sum, item) => sum + (item !== mediaTile && item.visible && item.width > 0 ? item.width + tiles.spacing : 0), 0)
                        surface: root.surface
                        ink: root.ink
                        accent: root.focusAccent
                        shown: panel.shown
                    }
                    ToolButton {
                        id: optionsButton
                        background: Item {}
                        hoverEnabled: true
                        z: hovered ? 1 : 0
                        padding: 0
                        contentItem: DockGlyph {
                            button: optionsButton
                            source: Quickshell.iconPath("preferences-system", true)
                            edge: root.cfg.position
                                zoomEnabled: root.cfg.zoom
                            motion: root.motion
                        }
                        onHoveredChanged: panel.tip(optionsButton, hovered)
                        width: panel.iconSize
                        height: width
                        Accessible.name: "Opções da dock"
                        onClicked: {
                            panel.openMenu("", optionsButton);
                        }
                    }
                }
            }
            FolderStack {
                id: stack
                lightMode: root.light
                parent: panel.contentItem
                path: panel.stackPath
                x: panel.vertical ? (root.cfg.position === "left" ? parent.width : -width) : (parent.width - width) / 2
                y: panel.vertical ? (parent.height - height) / 2 : -height
            }
            PanelWindow {
                id: menuHost
                screen: panel.screen
                visible: false
                color: "transparent"
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "orla-menu"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                property point anchorPoint
            }
            Menu {
                id: menu
                parent: menuHost.contentItem
                x: panel.vertical ? (root.cfg.position === "left" ? panel.width : menuHost.width - panel.width - width)
                                  : Math.max(0, Math.min(menuHost.width - width, (menuHost.width - panel.width) / 2 + menuHost.anchorPoint.x - width / 2))
                y: panel.vertical ? Math.max(0, Math.min(menuHost.height - height, (menuHost.height - panel.height) / 2 + menuHost.anchorPoint.y - height / 2))
                                  : menuHost.height - panel.height - height
                modal: true
                dim: false
                onClosed: { menuHost.visible = false; panel.selectedWins = []; }
                onAboutToShow: {
                    panel.documents = [];
                    if (panel.selected) {
                        docReader.running = false;
                        docReader.command = [root.helper, "documents", panel.selected];
                        docReader.running = true;
                    }
                }
                width: panel.selectedWins.length ? Math.min(panel.screen.width - 12, 388) : 248
                padding: 6
                background: Rectangle {
                    radius: 12
                    color: root.surface
                    border.color: root.outline
                }
                popupType: Popup.Item
                DockOption {
                    lightMode: root.light
                    visible: panel.selected.length > 0 && !!root.appFor(panel.selected)
                    text: "Nova janela"
                    onTriggered: {
                        const tile = tiles.children.find(child => child.modelData === panel.selected);
                        if (root.cfg.launchAnimation && tile?.contentItem?.bounce) tile.contentItem.bounce();
                        root.newWindow(root.appFor(panel.selected));
                    }
                }
                Menu {
                    id: recentMenu
                    title: "Documentos recentes"
                    enabled: panel.documents.length > 0
                    Instantiator {
                        model: panel.documents
                        onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => recentMenu.removeItem(object)
                        delegate: DockOption {
                            lightMode: root.light
                            required property var modelData
                            text: modelData.name
                            onTriggered: root.cmd("open-document", panel.selected, modelData.uri)
                        }
                    }
                }
                Instantiator {
                    model: panel.selectedWins
                    onObjectAdded: (index, object) => menu.insertItem(index, object)
                    onObjectRemoved: (index, object) => menu.removeItem(object)
                    delegate: DockOption {
                        id: windowRow
                        lightMode: root.light
                        required property var modelData
                        implicitHeight: 68
                        text: modelData.title
                        Accessible.name: text
                        onTriggered: panel.requestWindow("focus", modelData.address)
                        contentItem: RowLayout {
                            spacing: 8
                            WindowThumb {
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 50
                                client: windowRow.modelData
                                capturing: panel.windowMenuVisible
                            }
                            Label {
                                Layout.fillWidth: true
                                text: windowRow.text
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.ink
                            }
                            Button {
                                text: windowRow.modelData.parked ? "Restaurar" : "Minimizar"
                                Accessible.name: text + " " + windowRow.text
                                onPressed: panel.toggleMenuWindow(windowRow.modelData)
                            }
                        }
                    }
                }
                DockOption {
                    lightMode: root.light
                    visible: panel.selectedWins.length > 0
                    destructive: true
                    text: "Forçar encerramento do aplicativo…"
                    onTriggered: root.cmd("force", panel.selectedWins[0].address)
                }
                DockOption {
                    lightMode: root.light
                    visible: !!panel.selected
                    text: root.cfg.pins.includes(panel.selected) ? "Desafixar" : "Fixar"
                    onTriggered: root.set("pins", root.cfg.pins.includes(panel.selected) ? root.cfg.pins.filter(p => p !== panel.selected) : [...root.cfg.pins, panel.selected])
                }
                DockOption {
                    lightMode: root.light
                    visible: panel.orderedKeys().indexOf(panel.selected) > 0
                    text: "Mover uma posição antes"
                    onTriggered: panel.reorder(panel.selected, panel.orderedKeys().indexOf(panel.selected) - 1)
                }
                Repeater {
                    model: panel.selected ? [] : root.cfg.folders
                    DockOption {
                        lightMode: root.light
                        required property string modelData
                        text: "📁 " + modelData
                        onTriggered: Quickshell.execDetached(["gio", "open", modelData])
                    }
                }
                DockOption {
                    lightMode: root.light
                    visible: !panel.selected
                    text: "Abrir lixeira"
                    onTriggered: Quickshell.execDetached(["gio", "open", "trash:///"])
                }
                DockOption {
                    lightMode: root.light
                    destructive: true
                    visible: !panel.selected
                    text: "Esvaziar lixeira…"
                    onTriggered: root.cmd("empty")
                }
                DockOption {
                    lightMode: root.light
                    text: "Configurar dock…"
                    onTriggered: root.cmd("settings")
                }
            }
        }
    }
    IpcHandler {
        target: "settings"
        function open(): void {
            root.cmd("settings");
        }
        function createWindow(): void {
            settingsLoader.active = false;
            settingsLoader.active = true;
        }
    }
    Loader {
        id: settingsLoader
        active: false
        sourceComponent: Component {
            DockSettings {
                visible: true
                cfg: root.cfg
                lightMode: root.light
                motion: root.motion
                systemAccent: root.focusAccent
                color: root.background
                onEdited: (key, value) => root.set(key, value)
                onRequested: action => root.cmd(action)
            }
        }
    }
}
