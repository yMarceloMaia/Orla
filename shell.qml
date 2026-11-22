import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "DockFit.js" as DockFit

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
    ListModel { id: plugins; dynamicRoles: true }
    property string catalogSignature: ""
    property var services: ({})
    function syncPlugins(catalog) {
        const signature = JSON.stringify(catalog);
        if (signature === catalogSignature) return;
        catalogSignature = signature;
        for (let i = 0; i < catalog.length; ++i) {
            const plugin = catalog[i];
            let j = i;
            while (j < plugins.count && plugins.get(j).pluginId !== plugin.pluginId) ++j;
            if (j === plugins.count) plugins.insert(i, plugin);
            else {
                if (j !== i) plugins.move(j, i, 1);
                plugins.set(i, plugin);
            }
        }
        if (plugins.count > catalog.length) plugins.remove(catalog.length, plugins.count - catalog.length);
    }
    function pluginEnabled(setting, fallback) { return cfg[setting] ?? fallback; }
    Instantiator {
        model: plugins
        delegate: Loader {
            id: serviceLoader
            required property string pluginId
            required property string serviceUrl
            required property string setting
            required property bool defaultOn
            property var memory: ({})
            readonly property var cfg: root.cfg
            readonly property var services: root.services
            readonly property string helper: root.helper
            active: !!serviceUrl && root.pluginEnabled(setting, defaultOn)
            onServiceUrlChanged: setSource(serviceUrl, {host: serviceLoader})
            onItemChanged: {
                const next = Object.assign({}, root.services);
                if (item) next[pluginId] = item;
                else delete next[pluginId];
                root.services = next;
            }
        }
    }
    property var lastPlacement: ({})
    signal windowMinimized(var client)
    property var cfg: state.cfg
    readonly property string dockLayout: cfg.dockLayout || (cfg.islands ? "islands" : "bar")
    readonly property bool islands: dockLayout === "islands"
    readonly property bool shelfLayout: dockLayout === "shelf"
    readonly property bool neon: !islands && cfg.dockFinish === "neon"
    readonly property bool paper: !islands && cfg.dockFinish === "paper"
    readonly property color dockBase: neon ? "#181b27" : paper ? (light ? "#f1efe9" : "#34343a") : background
    readonly property color dockInk: neon ? "#eef0f7" : ink
    readonly property color dockAccent: neon && focusAccent.hslLightness < 0.55 ? Qt.lighter(focusAccent, 1.65) : focusAccent
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
                root.syncPlugins(next.plugins || []);
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
                overflowMenu.close();
            }
            property bool shown: !fullscreen && (dragging !== "" || !root.cfg.auto || hover.hovered || (tipTarget?.windows?.length > 1 && !tipDelay.running) || fileDragGrace.running || fileHoverCount > 0 || menu.opened || overflowMenu.opened || tiles.children.some(child => child.keepOpen === true) || stack.opened || resizeSize > 0 || linger.running)
            property int fileHoverCount: 0
            property int resizeSize: 0
            readonly property int preferredIconSize: resizeSize || root.cfg.size
            readonly property int iconSize: fit.edge
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
            readonly property var dockKeys: orderedKeys()
            readonly property var folderItems: root.cfg.stacks ? root.cfg.folders : []
            readonly property var minimizedItems: root.cfg.separateMinimized ? wins.filter(w => w.parked) : []
            property var widgetBudget: ({count: 0, extra: 0})
            function refreshWidgetBudget() {
                let count = 0;
                let extra = 0;
                for (let i = 0; i < dockWidgets.count; ++i) {
                    const widget = dockWidgets.itemAt(i);
                    if (widget?.dockWidgetReady) {
                        ++count;
                        extra += widget.dockExtraWidth;
                    }
                }
                if (widgetBudget.count !== count || widgetBudget.extra !== extra)
                    widgetBudget = {count, extra};
            }
            readonly property var fit: DockFit.fit((vertical ? screen.height : screen.width) - lengthPadding,
                preferredIconSize, 30, root.islands ? 8 : 5, widgetBudget.count, vertical ? 0 : widgetBudget.extra,
                dockKeys.length + recentEntries.length + folderItems.length + minimizedItems.length)
            readonly property var displayedItems: {
                const focused = wins.find(w => !w.parked && w.address === root.state.active);
                const focusedKey = focused ? root.key(focused) : "";
                const priority = [...new Set([...(focusedKey ? [focusedKey] : []), ...root.cfg.pins, ...dockKeys])];
                const allowed = new Set(priority.slice(0, fit.slots));
                const apps = dockKeys.filter(key => allowed.has(key));
                const folderSlots = Math.max(0, fit.slots - apps.length);
                const folders = folderItems.slice(0, folderSlots);
                const minimizedSlots = Math.max(0, folderSlots - folders.length);
                const minimized = minimizedItems.slice(0, minimizedSlots);
                const recent = recentEntries.slice(0, Math.max(0, minimizedSlots - minimized.length));
                return {apps, folders, minimized, recent};
            }
            readonly property var overflowItems: [
                ...dockKeys.filter(key => !displayedItems.apps.includes(key)).map(key => ({kind: "app", key})),
                ...folderItems.slice(displayedItems.folders.length).map(path => ({kind: "folder", path})),
                ...minimizedItems.slice(displayedItems.minimized.length).map(window => ({kind: "window", window})),
                ...recentEntries.slice(displayedItems.recent.length).map(app => ({kind: "recent", app}))
            ]
            function openOverflowItem(entry) {
                switch (entry.kind) {
                case "app": {
                    const windows = wins.filter(w => root.key(w) === entry.key);
                    if (windows.length)
                        requestWindow("cycle", ...windows.map(w => w.address));
                    else
                        root.appFor(entry.key)?.execute();
                    break;
                }
                case "recent":
                    entry.app.execute();
                    break;
                case "window":
                    requestWindow("focus", entry.window.address);
                    break;
                case "folder":
                    stackPath = entry.path;
                    stack.parent = overflowButton;
                    Qt.callLater(() => stack.open());
                    break;
                }
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
                visible: !panel.dragging && !!panel.tipTarget && (panel.tipTarget.hovered || panel.tipTarget.windows?.length > 1) && !tipDelay.running && !menu.opened && !overflowMenu.opened && panel.shown
                color: "transparent"
                mask: Region {
                    item: hint.previews.length ? hintBody : null
                }
                readonly property var previews: visible && panel.tipTarget?.windows?.length > 1 ? panel.tipTarget.windows : []
                readonly property int availableWidth: Math.max(150, panel.screen.width - (panel.vertical ? panel.extent : 0) - 16)
                readonly property int columns: Math.max(1, Math.min(4, previews.length, Math.floor((availableWidth - 18) / 208)))
                readonly property int cardWidth: Math.min(286, Math.floor((availableWidth - 18 - (columns - 1) * 8) / columns))
                readonly property int thumbnailHeight: Math.max(90, Math.min(166, Math.round(cardWidth * 0.60), panel.screen.height - 124))
                readonly property bool scrollable: previews.length > columns
                readonly property color muted: Qt.alpha(root.ink, 0.7)
                readonly property color shelf: Qt.tint(root.background, Qt.alpha(root.ink, 0.045))
                implicitWidth: previews.length ? columns * cardWidth + (columns - 1) * 8 + 18 : Math.min(280, label.implicitWidth + 20)
                implicitHeight: previews.length ? thumbnailHeight + 82 + (scrollable ? 10 : 0) : 28
                Connections {
                    target: panel
                    function onTipTargetChanged() { previewList.positionViewAtBeginning(); }
                }
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
                    radius: hint.previews.length ? 14 : 9
                    color: hint.previews.length ? hint.shelf : root.surface
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
                    ColumnLayout {
                        visible: hint.previews.length > 0
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7
                        RowLayout {
                            spacing: 7
                            Image {
                                Layout.preferredWidth: 19
                                Layout.preferredHeight: 19
                                sourceSize: Qt.size(38, 38)
                                source: hint.previews.length ? Quickshell.iconPath(root.entry(hint.previews[0])?.icon || "application-x-executable", true) : ""
                            }
                            Text {
                                Layout.fillWidth: true
                                text: label.text
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.ink
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: hint.previews.length + " janelas"
                                color: hint.muted
                                font.pixelSize: 11
                            }
                        }
                        ListView {
                            id: previewList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            orientation: ListView.Horizontal
                            clip: true
                            spacing: 8
                            cacheBuffer: 0
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: hint.scrollable
                            model: hint.previews
                            ScrollBar.horizontal: ScrollBar {
                                policy: hint.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                            }
                            WheelHandler {
                                enabled: hint.scrollable
                                rotationScale: 1
                                target: null
                                onWheel: event => {
                                    const delta = event.pixelDelta.x || event.pixelDelta.y ||
                                        (event.angleDelta.x || event.angleDelta.y) / 120 * (hint.cardWidth + previewList.spacing);
                                    previewList.contentX = Math.max(0, Math.min(previewList.contentWidth - previewList.width, previewList.contentX - delta));
                                    event.accepted = true;
                                }
                            }
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                readonly property bool focused: !modelData.parked && modelData.address === root.state.active
                                width: hint.cardWidth
                                height: hint.thumbnailHeight + 36
                                radius: 10
                                color: Qt.tint(hint.shelf, Qt.alpha(focused ? root.focusAccent : root.ink, cardHover.hovered ? 0.13 : 0.07))
                                border.color: focused || cardHover.hovered ? root.focusAccent : Qt.alpha(root.ink, 0.13)
                                border.width: focused ? 2 : 1
                                HoverHandler { id: cardHover }
                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 6
                                    height: 30
                                    spacing: 4
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: card.modelData.title || label.text
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: root.ink
                                        font.pixelSize: 12
                                        font.weight: card.focused ? Font.DemiBold : Font.Medium
                                        verticalAlignment: Text.AlignVCenter
                                        TapHandler {
                                            onTapped: {
                                                panel.requestWindow("focus", card.modelData.address);
                                                panel.tipTarget = null;
                                            }
                                        }
                                    }
                                    ToolButton {
                                        id: windowAction
                                        text: card.modelData.parked ? "Restaurar" : "Minimizar"
                                        Accessible.name: text + " " + (card.modelData.title || label.text)
                                        padding: 4
                                        contentItem: Text {
                                            text: windowAction.text
                                            color: root.ink
                                            font.pixelSize: 10
                                        }
                                        background: Rectangle {
                                            radius: 5
                                            color: Qt.alpha(root.ink, windowAction.hovered ? 0.16 : 0.07)
                                        }
                                        onClicked: {
                                            panel.requestWindow(card.modelData.parked ? "focus" : "minimize", card.modelData.address);
                                            panel.tipTarget = null;
                                        }
                                    }
                                }
                                WindowThumb {
                                    x: 6
                                    y: 30
                                    width: card.width - 12
                                    height: hint.thumbnailHeight
                                    radius: 6
                                    client: card.modelData
                                    TapHandler {
                                        onTapped: {
                                            panel.requestWindow("focus", card.modelData.address);
                                            panel.tipTarget = null;
                                        }
                                    }
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
            readonly property int lengthPadding: root.shelfLayout ? 44 : 28
            property real reveal: shown ? 1 : 0
            Behavior on reveal {
                enabled: root.motion && root.cfg.auto && !panel.fullscreen
                NumberAnimation {
                    duration: 170
                    easing.type: Easing.OutCubic
                }
            }
            readonly property bool expanded: shown || reveal > 0
            implicitWidth: vertical ? (expanded ? extent : 3) : Math.min(screen.width, tiles.implicitWidth + lengthPadding)
            implicitHeight: vertical ? Math.min(screen.height, tiles.implicitHeight + lengthPadding) : (expanded ? extent : 3)
            exclusiveZone: root.cfg.auto ? 0 : extent
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            WlrLayershell.namespace: "orla-dock"
            BackgroundEffect.blurRegion: panel.reveal > 0 && !root.islands && !root.shelfLayout && !root.paper && !root.neon && root.cfg.glass && root.state.visuals?.blur ? shelfRegion : null
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
            Item {
                id: shelf
                anchors.fill: parent
                anchors.margins: 3
                readonly property real radius: root.paper ? 10 : 21
                visible: panel.reveal > 0
                opacity: panel.reveal
                transform: Translate {
                    x: panel.vertical ? (root.cfg.position === "left" ? -1 : 1) * panel.extent * (1 - panel.reveal) : 0
                    y: panel.vertical ? 0 : panel.extent * (1 - panel.reveal)
                }
                Repeater {
                    model: root.neon && !root.shelfLayout ? [0.07, 0.12, 0.23] : []
                    delegate: Rectangle {
                        required property int index
                        required property real modelData
                        anchors.fill: shelf
                        anchors.margins: index * 2 - 2
                        radius: shelf.radius - anchors.margins
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.alpha(root.dockAccent, modelData)
                    }
                }
                Rectangle {
                    visible: !root.islands && !root.shelfLayout
                    anchors.fill: parent
                    anchors.margins: root.neon ? 3 : 0
                    radius: shelf.radius - anchors.margins
                    color: root.dockBase
                    gradient: root.paper ? null : root.neon ? neonGradient : shelfGradient
                    border.color: root.neon ? Qt.tint(root.dockAccent, Qt.alpha("white", 0.36)) : root.paper ? Qt.alpha(root.ink, 0.20) : root.outline
                    Gradient {
                        id: neonGradient
                        orientation: panel.vertical ? Gradient.Horizontal : Gradient.Vertical
                        GradientStop { position: 0; color: Qt.tint(root.dockBase, Qt.alpha(root.dockAccent, panel.vertical && root.cfg.position === "left" ? 0.16 : 0.08)) }
                        GradientStop { position: 0.5; color: root.dockBase }
                        GradientStop { position: 1; color: Qt.tint(root.dockBase, Qt.alpha(root.dockAccent, panel.vertical && root.cfg.position === "left" ? 0.08 : 0.16)) }
                    }
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
                    Rectangle {
                        visible: !root.paper && !root.neon
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.color: "#25ffffff"
                    }
                }
                Loader {
                    active: root.shelfLayout
                    anchors.fill: parent
                    sourceComponent: DockShelf {
                        vertical: panel.vertical
                        leftEdge: root.cfg.position === "left"
                        depth: 21
                        neon: root.neon
                        rearColor: Qt.tint(root.dockBase, Qt.alpha(root.neon ? root.dockAccent : root.dockInk, root.paper ? 0.015 : root.neon ? 0.22 : 0.13))
                        frontColor: root.dockBase
                        faceColor: Qt.darker(root.dockBase, 1.22)
                        edgeColor: root.neon ? root.dockAccent : Qt.alpha(root.dockInk, root.paper ? 0.22 : 0.44)
                    }
                }
                Grid {
                    id: tiles
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.shelfLayout && !panel.vertical ? -3 : 0
                    anchors.horizontalCenterOffset: root.shelfLayout && panel.vertical ? (root.cfg.position === "left" ? 3 : -3) : 0
                    columns: panel.vertical ? 1 : children.length
                    spacing: panel.fit.spacing
                    ToolButton {
                        id: appsButton
                        width: panel.iconSize
                        height: width
                        padding: 0
                        hoverEnabled: true
                        Accessible.name: "Aplicativos"
                        onHoveredChanged: panel.tip(this, hovered)
                        onClicked: {
                            panel.tipTarget = null;
                            Quickshell.execDetached(["omarchy", "menu", "summon", "apps"]);
                        }
                        background: Rectangle {
                            radius: Math.round(appsButton.width * 0.23)
                            color: Qt.alpha(root.dockInk, appsButton.down ? 0.18 : appsButton.hovered ? 0.12 : 0.06)
                            border.color: appsButton.visualFocus ? root.dockAccent : Qt.alpha(root.dockInk, 0.14)
                        }
                        contentItem: Item {
                            Grid {
                                anchors.centerIn: parent
                                columns: 3
                                spacing: Math.max(2, Math.round(appsButton.width * 0.065))
                                Repeater {
                                    model: 9
                                    Rectangle {
                                        width: Math.max(3, Math.round(appsButton.width * 0.11))
                                        height: width
                                        radius: width / 3
                                        color: root.dockInk
                                    }
                                }
                            }
                        }
                    }
                    Repeater {
                        property string keyList: JSON.stringify(panel.displayedItems.apps)
                        model: JSON.parse(keyList)
                        ToolButton {
                            id: tile
                            required property string modelData
                            required property int index
                            readonly property int sourceIndex: panel.dragging ? panel.displayedItems.apps.indexOf(panel.dragging) : -1
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
                                    const last = panel.displayedItems.apps.length - 1;
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
                                        panel.reorder(tile.modelData, panel.dockKeys.indexOf(panel.displayedItems.apps[panel.dropIndex]));
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
                                width: root.islands ? Math.round(tile.width * 0.27) : 4
                                height: 4
                                radius: 2
                                visible: root.cfg.indicators !== false && tile.windows.length > 0
                                color: tile.windows.every(w => w.parked) ? (root.light && !root.neon ? "#955300" : "#f9bd68") : root.dockInk
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
                            visible: !root.islands || grip.containsMouse || grip.pressed
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
                        model: panel.displayedItems.recent
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
                        model: panel.displayedItems.folders
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
                        model: panel.displayedItems.minimized
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
                    Repeater {
                        id: dockWidgets
                        model: plugins
                        onItemAdded: Qt.callLater(panel.refreshWidgetBudget)
                        onItemRemoved: Qt.callLater(panel.refreshWidgetBudget)
                        delegate: Loader {
                            id: widgetHost
                            required property string pluginId
                            required property string widgetUrl
                            required property string serviceUrl
                            required property string setting
                            required property bool defaultOn
                            readonly property var service: root.services[pluginId] || null
                            active: root.pluginEnabled(setting, defaultOn) && (!serviceUrl || !!service)
                            visible: dockWidgetReady
                            readonly property bool dockWidgetReady: status === Loader.Ready
                            readonly property real dockExtraWidth: item?.dockExtraWidth ?? 0
                            readonly property bool compact: panel.fit.compact
                            onDockWidgetReadyChanged: Qt.callLater(panel.refreshWidgetBudget)
                            onDockExtraWidthChanged: Qt.callLater(panel.refreshWidgetBudget)
                            readonly property bool keepOpen: !!item?.keepOpen
                            readonly property var cfg: root.cfg
                            readonly property color background: root.background
                            readonly property color surface: root.surface
                            readonly property color accent: root.focusAccent
                            readonly property color ink: root.ink
                            readonly property int edge: panel.iconSize
                            readonly property int preferredEdge: panel.preferredIconSize
                            readonly property int extent: panel.extent
                            readonly property bool vertical: panel.vertical
                            readonly property bool leftEdge: cfg.position === "left"
                            readonly property bool shown: panel.shown
                            readonly property int screenWidth: panel.screen.width
                            readonly property int screenHeight: panel.screen.height
                            readonly property int availableWidth: screenWidth - panel.lengthPadding - tiles.children.reduce(
                                (sum, c) => sum + (c !== widgetHost && c.visible && c.width > 0 ? c.width + tiles.spacing : 0), 0)
                            function preference(key, fallback) {
                                return cfg["plugin." + pluginId + ".config." + key] ?? fallback;
                            }
                            function savePreference(key, value) {
                                if (/^[a-zA-Z0-9_-]+$/.test(key))
                                    root.set("plugin." + pluginId + ".config." + key, value);
                            }
                            function set(key, value) { root.set(key, value); }
                            function tip(target, show) {
                                if (show) panel.tip(target, true);
                                else if (panel.tipTarget === target) panel.tipTarget = null;
                            }
                            onWidgetUrlChanged: setSource(widgetUrl, {host: widgetHost})
                        }
                    }
                    ToolButton {
                        id: overflowButton
                        visible: panel.overflowItems.length > 0
                        width: panel.iconSize
                        height: width
                        padding: 0
                        hoverEnabled: true
                        text: "+" + panel.overflowItems.length
                        Accessible.name: panel.overflowItems.length + " itens adicionais da dock"
                        onHoveredChanged: panel.tip(this, hovered)
                        onClicked: {
                            panel.tipTarget = null;
                            menuHost.anchorPoint = mapToItem(panel.contentItem, width / 2, height / 2);
                            menuHost.visible = true;
                            overflowMenu.open();
                        }
                        background: Rectangle {
                            radius: 8
                            color: Qt.alpha(root.dockInk, overflowButton.hovered ? 0.13 : 0.07)
                            border.color: Qt.alpha(root.dockInk, 0.20)
                        }
                        contentItem: Text {
                            text: overflowButton.text
                            color: root.dockInk
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
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
                surface: root.background
                ink: root.ink
                accent: root.focusAccent
                maxWidth: panel.screen.width - (panel.vertical ? panel.extent : 0) - 14
                maxHeight: panel.screen.height - (panel.vertical ? 0 : panel.extent) - 14
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
                id: overflowMenu
                parent: menuHost.contentItem
                popupType: Popup.Item
                modal: true
                dim: false
                width: Math.min(310, panel.screen.width - (panel.vertical ? panel.extent : 0) - 12)
                height: Math.min(implicitHeight, panel.screen.height - (panel.vertical ? 0 : panel.extent) - 8)
                x: panel.vertical ? (root.cfg.position === "left" ? panel.width : menuHost.width - panel.width - width)
                                  : Math.max(0, Math.min(menuHost.width - width, (menuHost.width - panel.width) / 2 + menuHost.anchorPoint.x - width / 2))
                y: panel.vertical ? Math.max(0, Math.min(menuHost.height - height, (menuHost.height - panel.height) / 2 + menuHost.anchorPoint.y - height / 2))
                                  : menuHost.height - panel.height - height
                padding: 8
                onClosed: menuHost.visible = false
                background: Rectangle {
                    radius: 14
                    color: root.background
                    border.color: root.outline
                }
                Instantiator {
                    model: panel.overflowItems
                    onObjectAdded: (index, object) => overflowMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => overflowMenu.removeItem(object)
                    delegate: DockOption {
                        required property var modelData
                        ink: root.ink
                        accent: root.focusAccent
                        text: {
                            switch (modelData.kind) {
                            case "app": return root.appFor(modelData.key)?.name || modelData.key;
                            case "recent": return modelData.app.name + " · recente";
                            case "window": return modelData.window.title + " · minimizada";
                            case "folder": return (modelData.path.split("/").filter(Boolean).pop() || "/") + " · pasta";
                            }
                            return "";
                        }
                        onTriggered: panel.openOverflowItem(modelData)
                    }
                }
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
                readonly property var selectedApp: panel.selected ? root.appFor(panel.selected) : null
                width: Math.min(panel.screen.width - (panel.vertical ? panel.extent : 0) - 12, panel.selectedWins.length ? 412 : 282)
                height: Math.min(implicitHeight, panel.screen.height - (panel.vertical ? 0 : panel.extent) - 8)
                padding: 8
                delegate: DockOption {
                    ink: root.ink
                    accent: root.focusAccent
                    visible: !subMenu || !!panel.selected
                    hoverEnabled: !subMenu
                }
                component MenuRule: MenuSeparator {
                    implicitHeight: visible ? 9 : 0
                    contentItem: Item {
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 5
                            height: 1
                            color: Qt.alpha(root.ink, 0.14)
                        }
                    }
                }
                background: Rectangle {
                    radius: 14
                    color: root.background
                    border.color: root.outline
                }
                popupType: Popup.Item
                Item {
                    width: menu.availableWidth
                    implicitHeight: 48
                    height: implicitHeight
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        spacing: 9
                        Image {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            sourceSize: Qt.size(48, 48)
                            source: Quickshell.iconPath(panel.selected ? menu.selectedApp?.icon || "application-x-executable" : "preferences-system", true)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: panel.selected ? menu.selectedApp?.name || panel.selected : "Orla"
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.ink
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                            Text {
                                visible: panel.selectedWins.length > 0
                                text: panel.selectedWins.length === 1 ? "1 janela" : panel.selectedWins.length + " janelas"
                                color: Qt.alpha(root.ink, 0.68)
                                font.pixelSize: 11
                            }
                        }
                    }
                }
                MenuRule {}
                DockOption {
                    ink: root.ink; accent: root.focusAccent
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
                    padding: 7
                    width: Math.min(292, panel.screen.width - 12)
                    background: Rectangle { radius: 12; color: root.background; border.color: root.outline }
                    enabled: panel.documents.length > 0
                    Instantiator {
                        model: panel.documents
                        onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => recentMenu.removeItem(object)
                        delegate: DockOption {
                            ink: root.ink; accent: root.focusAccent
                            required property var modelData
                            text: modelData.name
                            onTriggered: root.cmd("open-document", panel.selected, modelData.uri)
                        }
                    }
                }
                MenuRule { visible: panel.selectedWins.length > 0 }
                Instantiator {
                    model: panel.selectedWins
                    onObjectAdded: (index, object) => {
                        for (let i = 0; i < menu.count; ++i) {
                            if (menu.itemAt(i) === windowSectionEnd) {
                                menu.insertItem(i, object);
                                return;
                            }
                        }
                        menu.addItem(object);
                    }
                    onObjectRemoved: (index, object) => menu.removeItem(object)
                    delegate: DockOption {
                        id: windowRow
                        ink: root.ink; accent: root.focusAccent
                        required property var modelData
                        readonly property bool focused: !modelData.parked && modelData.address === root.state.active
                        implicitHeight: 67
                        background: Rectangle {
                            radius: 8
                            color: Qt.alpha(windowRow.focused ? root.focusAccent : root.ink,
                                windowRow.highlighted || windowRow.hovered ? 0.11 : 0.045)
                            border.color: Qt.alpha(windowRow.focused ? root.focusAccent : root.ink, windowRow.focused ? 0.70 : 0.12)
                        }
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
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    Layout.fillWidth: true
                                    text: windowRow.text || "Janela"
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: root.ink
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    visible: windowRow.modelData.parked || windowRow.focused
                                    text: windowRow.modelData.parked ? "Minimizada" : "Em foco"
                                    color: Qt.alpha(root.ink, 0.70)
                                    font.pixelSize: 11
                                }
                            }
                            Button {
                                id: windowAction
                                text: windowRow.modelData.parked ? "Restaurar" : "Minimizar"
                                Accessible.name: text + " " + windowRow.text
                                padding: 6
                                contentItem: Text {
                                    text: windowAction.text
                                    color: root.ink
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                background: Rectangle {
                                    radius: 6
                                    color: Qt.alpha(root.ink, windowAction.hovered ? 0.15 : 0.07)
                                    border.color: windowAction.visualFocus ? root.focusAccent : "transparent"
                                }
                                onClicked: panel.toggleMenuWindow(windowRow.modelData)
                            }
                        }
                    }
                }
                MenuRule { id: windowSectionEnd; visible: panel.selectedWins.length > 0 }
                DockOption {
                    ink: root.ink; accent: root.focusAccent
                    visible: !!panel.selected
                    text: root.cfg.pins.includes(panel.selected) ? "Desafixar" : "Fixar"
                    onTriggered: root.set("pins", root.cfg.pins.includes(panel.selected) ? root.cfg.pins.filter(p => p !== panel.selected) : [...root.cfg.pins, panel.selected])
                }
                DockOption {
                    ink: root.ink; accent: root.focusAccent
                    visible: panel.orderedKeys().indexOf(panel.selected) > 0
                    text: "Mover uma posição antes"
                    onTriggered: panel.reorder(panel.selected, panel.orderedKeys().indexOf(panel.selected) - 1)
                }
                Repeater {
                    model: panel.selected ? [] : root.cfg.folders
                    DockOption {
                        ink: root.ink; accent: root.focusAccent
                        required property string modelData
                        text: "📁 " + modelData
                        onTriggered: Quickshell.execDetached(["gio", "open", modelData])
                    }
                }
                DockOption {
                    ink: root.ink; accent: root.focusAccent
                    visible: !panel.selected
                    text: "Abrir lixeira"
                    onTriggered: Quickshell.execDetached(["gio", "open", "trash:///"])
                }
                DockOption {
                    ink: root.ink; accent: root.focusAccent
                    destructive: true
                    visible: !panel.selected
                    text: "Esvaziar lixeira…"
                    onTriggered: root.cmd("empty")
                }
                MenuRule {}
                DockOption {
                    ink: root.ink; accent: root.focusAccent
                    visible: panel.selectedWins.length > 0
                    destructive: true
                    text: "Forçar encerramento do aplicativo…"
                    onTriggered: root.cmd("force", panel.selectedWins[0].address)
                }
                DockOption {
                    ink: root.ink; accent: root.focusAccent
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
                catalog: plugins
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
