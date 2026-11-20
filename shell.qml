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
    property var cfg: state.cfg
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
                root.state = JSON.parse(data);
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
            property var wins: root.state.clients.filter(c => monitor && c.origin === monitor.activeWorkspace.id).sort((a, b) => a.address.localeCompare(b.address))
            property bool vertical: root.cfg.position !== "bottom"
            readonly property int displayedWorkspace: monitor?.specialWorkspace?.id || monitor?.activeWorkspace?.id || 0
            readonly property bool fullscreen: !!monitor && root.state.clients.some(c =>
                c.mapped && !c.hidden && c.workspace.id === displayedWorkspace && (c.fullscreen & 2) !== 0)
            visible: !fullscreen
            onFullscreenChanged: if (fullscreen) {
                tipTarget = null;
                endDrag();
                menu.close();
            }
            property bool shown: !fullscreen && (dragging !== "" || !root.cfg.auto || hover.hovered || (tipTarget?.windows?.length > 1 && !tipDelay.running) || menu.opened || linger.running)
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
            property var selectedWins: wins.filter(c => root.key(c) === selected)
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
                    color: "#f02c2e35"
                    border.color: "#70727c"
                    Text {
                        id: label
                        visible: !hint.previews.length
                        anchors.fill: parent
                        anchors.margins: 2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: "white"
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
                                        root.cmd("focus", address);
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
                                    color: "white"
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
            property int extent: root.cfg.size + 22
            implicitWidth: vertical ? (shown ? extent : 3) : Math.min(screen.width, tiles.implicitWidth + 28)
            implicitHeight: vertical ? Math.min(screen.height, tiles.implicitHeight + 28) : (shown ? extent : 3)
            exclusiveZone: root.cfg.auto ? 0 : extent
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            WlrLayershell.namespace: "orla-dock"
            HoverHandler {
                id: hover
                onHoveredChanged: if (!hovered) {
                    linger.restart();
                    tipExit.restart();
                }
            }
            Timer {
                id: linger
                interval: 450
            }
            Rectangle {
                anchors.fill: parent
                visible: panel.shown
                anchors.margins: 3
                radius: 21
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#e04a4c55"
                    }
                    GradientStop {
                        position: 1
                        color: "#e326272d"
                    }
                }
                border.color: "#709c9da5"
                Rectangle {
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
                    spacing: 5
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
                            width: root.cfg.size
                            height: width
                            background: Item {}
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
                                zoomEnabled: root.cfg.zoom
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
                            property var preview: hovered && windows.length === 1 && windows[0].parked ? Hyprland.toplevels.values.find(t => String(t.address).replace(/^0x/, "") === windows[0].address.slice(2))?.wayland : null
                            ScreencopyView {
                                anchors.fill: parent
                                anchors.margins: 5
                                captureSource: tile.preview || null
                                live: false
                                paintCursor: false
                                visible: !!tile.preview
                            }
                            Accessible.name: app?.name || modelData
                            onHoveredChanged: panel.tip(tile, hovered)
                            TapHandler {
                                acceptedButtons: Qt.MiddleButton
                                onTapped: root.newWindow(tile.app)
                            }
                            function activateApp() {
                                if (!windows.length) {
                                    app?.execute();
                                    return;
                                }
                                root.cmd("cycle", ...windows.map(w => w.address));
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
                                    panel.selected = tile.modelData;
                                    menu.popup();
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 4
                                height: 4
                                radius: 2
                                visible: tile.windows.length > 0
                                color: tile.windows.every(w => w.parked) ? "#f9bd68" : "#f5f4fa"
                            }
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
                            zoomEnabled: root.cfg.zoom
                        }
                        onHoveredChanged: panel.tip(optionsButton, hovered)
                        width: root.cfg.size
                        height: width
                        Accessible.name: "Opções da dock"
                        onClicked: {
                            panel.selected = "";
                            menu.popup();
                        }
                    }
                }
            }
            Menu {
                id: menu
                width: panel.selectedWins.length ? Math.min(panel.screen.width - 12, 388) : 248
                padding: 6
                background: Rectangle {
                    radius: 12
                    color: "#fa30323a"
                    border.color: "#696c78"
                }
                popupType: Popup.Window
                DockOption {
                    visible: panel.selected.length > 0 && !!root.appFor(panel.selected)
                    text: "Nova janela"
                    onTriggered: root.newWindow(root.appFor(panel.selected))
                }
                Instantiator {
                    model: panel.selectedWins
                    onObjectAdded: (index, object) => menu.insertItem(index, object)
                    onObjectRemoved: (index, object) => menu.removeItem(object)
                    delegate: DockOption {
                        id: windowRow
                        required property var modelData
                        implicitHeight: 68
                        text: modelData.title
                        Accessible.name: text
                        onTriggered: root.cmd("focus", modelData.address)
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
                                color: "#f4f4fa"
                            }
                            Button {
                                text: windowRow.modelData.parked ? "Restaurar" : "Minimizar"
                                Accessible.name: text + " " + windowRow.text
                                onClicked: {
                                    const w = windowRow.modelData;
                                    menu.close();
                                    root.cmd(w.parked ? "focus" : "minimize", w.address);
                                }
                            }
                        }
                    }
                }
                DockOption {
                    visible: panel.selectedWins.length > 0
                    destructive: true
                    text: "Forçar encerramento do aplicativo…"
                    onTriggered: root.cmd("force", panel.selectedWins[0].address)
                }
                DockOption {
                    visible: !!panel.selected
                    text: root.cfg.pins.includes(panel.selected) ? "Desafixar" : "Fixar"
                    onTriggered: root.set("pins", root.cfg.pins.includes(panel.selected) ? root.cfg.pins.filter(p => p !== panel.selected) : [...root.cfg.pins, panel.selected])
                }
                DockOption {
                    visible: panel.orderedKeys().indexOf(panel.selected) > 0
                    text: "Mover uma posição antes"
                    onTriggered: panel.reorder(panel.selected, panel.orderedKeys().indexOf(panel.selected) - 1)
                }
                Repeater {
                    model: panel.selected ? [] : root.cfg.folders
                    DockOption {
                        required property string modelData
                        text: "📁 " + modelData
                        onTriggered: Quickshell.execDetached(["gio", "open", modelData])
                    }
                }
                DockOption {
                    visible: !panel.selected
                    text: "Abrir lixeira"
                    onTriggered: Quickshell.execDetached(["gio", "open", "trash:///"])
                }
                DockOption {
                    destructive: true
                    visible: !panel.selected
                    text: "Esvaziar lixeira…"
                    onTriggered: root.cmd("empty")
                }
                DockOption {
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
                onEdited: (key, value) => root.set(key, value)
                onRequested: action => root.cmd(action)
            }
        }
    }
}
