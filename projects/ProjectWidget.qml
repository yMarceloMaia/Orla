import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../components"

ToolButton {
    id: tile
    required property var host
    required property bool monitor
    readonly property bool keepOpen: panel.visible
    implicitHeight: host.edge
    readonly property int dockExtraWidth: host.screenWidth < 1000 ? 0 : 55
    readonly property bool compact: host.vertical || host.compact === true || !dockExtraWidth
    readonly property bool light: host.background.hslLightness > 0.5
    readonly property color tone: monitor ? (light ? "#096958" : "#80d9c3") : (light ? "#5d4ba8" : "#c2afff")
    readonly property var activeRuns: ProjectHub.runs.filter(r => !r.ended)
    readonly property var environmentProjects: (panel.visible && !tile.monitor ? ProjectHub.projects : []).filter(
        project => project.commands.some(command => command.environment))
    readonly property var runsById: {
        const index = {};
        for (const run of ProjectHub.runs)
            index[run.id] = run;
        return index;
    }
    readonly property var recentFailures: {
        const seen = new Set();
        const failures = [];
        const since = Date.now() / 1000 - 300;
        for (const run of ProjectHub.runs) {
            const key = run.project + ":" + run.cmd;
            if (seen.has(key))
                continue;
            seen.add(key);
            if (run.state === "Failed" && run.ended >= since)
                failures.push(run);
            if (failures.length === 5)
                break;
        }
        return failures;
    }
    readonly property real memoryTotal: ProjectHub.projects.reduce((sum, p) => sum + (p.metric?.total || 0), 0)
    readonly property bool partial: ProjectHub.projects.some(p => p.metric?.partial || p.metric?.approxMemory)
    implicitWidth: compact ? host.edge : host.edge + dockExtraWidth
    padding: 5
    readonly property color muted: Qt.alpha(host.ink, 0.69)
    Accessible.name: monitor ? "Project Resources" : "Project Commands"
    contentItem: RowLayout {
        spacing: 5
        ProjectMark {
            monitor: tile.monitor
            tone: tile.tone
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: Math.min(29, tile.host.edge - 10)
            Layout.preferredHeight: Layout.preferredWidth
        }
        ColumnLayout {
            visible: !tile.compact
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: tile.monitor ? "Memory" : "Commands"
                font.pixelSize: 10
                color: tile.muted
            }
            Text {
                text: tile.monitor ? (tile.partial ? "≈" : "") + tile.mem(tile.memoryTotal) : tile.activeRuns.length + " active"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: tile.host.ink
            }
        }
    }
    background: Rectangle {
        radius: 10
        color: Qt.tint(tile.host.background, Qt.alpha(tile.host.ink, tile.hovered ? 0.10 : 0.04))
        border.color: tile.visualFocus ? tile.tone : Qt.alpha(tile.host.ink, 0.18)
    }
    onClicked: panel.visible = !panel.visible
    TapHandler {
        enabled: !tile.monitor
        acceptedButtons: Qt.RightButton
        onTapped: tile.showActiveRuns()
    }
    function showActiveRuns() {
        confirmation.close();
        panel.logRun = null;
        panel.mode = "";
        panel.key = "";
        panel.query = "";
        panel.tab = "active";
        panel.visible = true;
        ProjectHub.tick();
    }
    function mem(n) {
        return n >= 1073741824 ? (n / 1073741824).toFixed(1) + " GiB" : Math.round((n || 0) / 1048576) + " MiB";
    }
    function send(data) {
        ProjectHub.error = "";
        ProjectHub.send(Object.assign({
            project: panel.key
        }, data));
    }
    function edit(mode, value) {
        ProjectHub.error = "";
        panel.mode = mode;
        if (mode === "command") {
            const c = JSON.parse(value);
            panel.original = c;
            commandName.text = c.name || "";
            commandArgs.text = JSON.stringify(c.argv || []);
            commandCategory.text = c.category || "";
            commandDescription.text = c.description || "";
            inEnvironment.checked = !!c.environment;
            needsConfirm.checked = c.confirm !== false;
            httpReadiness.text = c.ready?.type === "http" ? c.ready.url : "";
            selectedDependencies = c.depends || [];
            dependencyPicker.visible = false;
            editor.text = JSON.stringify({
                cwd: c.cwd || ".",
                env: c.env || {},
                ready: c.ready?.type !== "http" ? c.ready || null : null,
                shell: c.shell || false,
                capture: c.capture !== false,
                policy: c.policy || (c.category === "compose" ? "shared" : "managed"),
                timeout: c.timeout || 120,
                icon: c.icon || "›"
            }, null, 2);
            advanced.checked = false;
            commandName.forceActiveFocus();
        } else if (mode === "configure") {
            const p = JSON.parse(value);
            projectName.text = p.name;
            composeNames.text = p.compose.join(", ");
            projectName.forceActiveFocus();
        } else {
            if (mode === "add" || mode === "discover") {
                pathField.text = value;
                pathField.forceActiveFocus();
            } else {
                editor.text = value;
                editor.forceActiveFocus();
            }
        }
    }
    function confirm(label, request) {
        confirmation.question = label;
        confirmation.request = Object.assign({project: panel.key}, request);
        confirmation.open();
    }
    property var selectedDependencies: []
    function commandNameFor(project, id) {
        return project?.commands.find(command => command.id === id)?.name || id;
    }
    function startEnvironment(project) {
        const commands = project.commands.filter(command => command.environment);
        if (!commands.length)
            return;
        const sequence = commandSequence(project.commands, commands);
        confirm("Start " + project.name + "?\n" + sequence.map(command => command.argv.join(" ")).join("\n"), {
            op: "all",
            project: project.id,
            confirmed: true
        });
    }
    function commandSequence(catalog, targets) {
        const visited = new Set();
        const sequence = [];
        function collect(item) {
            if (!item || visited.has(item.id))
                return;
            visited.add(item.id);
            for (const id of item.depends || [])
                collect(catalog.find(c => c.id === id));
            sequence.push(item);
        }
        targets.forEach(collect);
        return sequence;
    }
    function start(project, command) {
        const sequence = commandSequence(project.commands, [command]);
        const data = {
            op: "start",
            project: project.id,
            id: command.id
        };
        if (sequence.some(c => c.confirm !== false)) {
            data.confirmed = true;
            confirm("Run in " + project.name + "?\n" + sequence.map(c => c.argv.join(" ")).join("\n"), data);
        } else
            send(data);
    }
    function save() {
        try {
            if (panel.mode === "add" || panel.mode === "discover")
                send({
                    op: panel.mode,
                    path: pathField.text.trim()
                });
            else if (panel.mode === "configure")
                send({
                    op: "configure",
                    name: projectName.text,
                    compose: composeNames.text.split(",").map(n => n.trim()).filter(Boolean)
                });
            else if (panel.mode === "interval") {
                const data = JSON.parse(editor.text);
                if (!Number.isInteger(data.open) || !Number.isInteger(data.closed) || data.open < 2 || data.closed < data.open || data.closed > 600)
                    throw Error("Use 2 to 600 seconds. The closed-panel interval must be at least as long as the open-panel interval.");
                host.savePreference("intervals", {
                    open: data.open,
                    closed: data.closed
                });
                ProjectHub.intervalSeconds = data.open;
                ProjectHub.idleSeconds = data.closed;
            } else {
                const spec = Object.assign({}, panel.original, JSON.parse(editor.text), {
                    name: commandName.text,
                    description: commandDescription.text,
                    category: commandCategory.text,
                    argv: JSON.parse(commandArgs.text),
                    environment: inEnvironment.checked,
                    confirm: needsConfirm.checked,
                    depends: selectedDependencies
                });
                if (httpReadiness.text.trim())
                    spec.ready = {type: "http", url: httpReadiness.text.trim()};
                else if (spec.ready?.type === "http")
                    delete spec.ready;
                if (!spec.ready)
                    delete spec.ready;
                send({
                    op: "save",
                    command: spec
                });
            }
            panel.mode = "";
        } catch (e) {
            ProjectHub.error = e.message;
        }
    }
    function intervals() {
        if (monitor && host) {
            const value = host.preference("intervals", {
                open: 4,
                closed: 30
            });
            if (Number.isInteger(value?.open) && Number.isInteger(value?.closed) && value.open >= 2 && value.closed >= value.open && value.closed <= 600) {
                ProjectHub.intervalSeconds = value.open;
                ProjectHub.idleSeconds = value.closed;
            }
        }
    }
    Component.onCompleted: intervals()
    component T: Label {
        color: tile.host.ink
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        Layout.fillWidth: true
    }
    component Field: TextField {
        Layout.fillWidth: true
        color: tile.host.ink
        placeholderTextColor: tile.muted
        background: Rectangle {
            radius: 6
            color: Qt.alpha(tile.host.ink, 0.045)
            border.color: parent.activeFocus ? tile.host.accent : Qt.alpha(tile.host.ink, 0.2)
        }
    }
    component B: Button {
        id: b
        property bool primary: false
        padding: 8
        contentItem: Text {
            text: b.text
            textFormat: Text.PlainText
            font.weight: Font.Medium
            color: b.primary ? tile.tone : tile.host.ink
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 6
            color: Qt.alpha(b.primary ? tile.tone : tile.host.ink, b.hovered ? 0.13 : b.primary ? 0.095 : 0.04)
            border.color: b.visualFocus ? tile.tone : Qt.alpha(b.primary ? tile.tone : tile.host.ink, 0.15)
        }
    }
    PanelWindow {
        id: panel
        visible: false
        readonly property var dock: tile.QsWindow.window
        screen: dock?.screen ?? null
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "orla-project-panel"
        // Mapping a keyboard-interactive layer can pull pointer focus off the dock.
        WlrLayershell.keyboardFocus: acceptsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        property bool acceptsKeyboard: false
        HoverHandler {
            onHoveredChanged: if (hovered && panel.visible)
                panel.acceptsKeyboard = true
        }
        anchors.left: !tile.host.vertical || tile.host.leftEdge
        anchors.right: tile.host.vertical && !tile.host.leftEdge
        anchors.bottom: !tile.host.vertical
        anchors.top: tile.host.vertical
        readonly property point tileCenter: visible && dock ? tile.mapToItem(dock.contentItem, tile.width / 2, tile.height / 2) : Qt.point(0, 0)
        margins.left: tile.host.vertical ? tile.host.extent : Math.max(0, Math.min(tile.host.screenWidth - width, (tile.host.screenWidth - (dock?.width ?? 0)) / 2 + tileCenter.x - width / 2))
        margins.right: tile.host.vertical ? tile.host.extent : 0
        margins.bottom: tile.host.vertical ? 0 : tile.host.extent
        margins.top: tile.host.vertical ? Math.max(0, Math.min(tile.host.screenHeight - height, (tile.host.screenHeight - (dock?.height ?? 0)) / 2 + tileCenter.y - height / 2)) : 0
        implicitWidth: Math.min(724, tile.host.screenWidth - 16)
        implicitHeight: Math.min(!mode && !project && tab === "main" && !logRun ? Math.min(620, header.implicitHeight + overview.implicitHeight + (tile.monitor ? 64 : 110) + (ProjectHub.error ? errorLabel.implicitHeight + 10 : 0)) : 620, tile.host.screenHeight - tile.host.extent - 16)
        color: "transparent"
        property string key: ""
        property string mode: ""
        property string tab: "main"
        readonly property bool portsTab: tab === "ports"
        readonly property bool activeTab: tab === "active"
        readonly property bool showingSystemPorts: visible && !tile.monitor && portsTab && !project && !mode && !logRun
        readonly property var ports: (project ? metric.ports : ProjectHub.systemPorts) || []
        property string portQuery: ""
        readonly property var filteredPorts: {
            const query = portQuery.trim().toLowerCase();
            if (!query)
                return ports;
            const terms = query.split(/\s+/);
            return ports.filter(port => {
                const searchable = typeof port === "string" ? port : [port.protocol, port.address, port.port, ...port.owners.map(owner => owner.name + " " + owner.pid)].join(" ");
                const text = searchable.toLowerCase();
                return terms.every(term => text.includes(term));
            });
        }
        onShowingSystemPortsChanged: if (showingSystemPorts)
            ProjectHub.send({
                op: "systemPorts"
            })
        onKeyChanged: {
            tab = "main";
            portQuery = "";
        }
        onTabChanged: if (scroll.contentItem)
            scroll.contentItem.contentY = scroll.contentItem.originY
        property string sortBy: "total"
        property string query: ""
        property var logRun: null
        property string logQuery: ""
        property real returnScrollY: 0
        property var lines: []
        property bool logLoading: false
        property bool followLogTail: false
        property var original: ({})
        property bool counted: false
        readonly property var project: ProjectHub.projects.find(p => p.id === key)
        readonly property var metric: project?.metric || {}
        readonly property var runs: ProjectHub.runs.filter(r => r.project === key)
        readonly property var quickGroups: visible && activeTab ? ProjectHub.projects.map(project => ({
            project,
            favorites: project.commands.filter(command => command.favorite),
            runs: tile.activeRuns.filter(run => run.project === project.id),
            failures: tile.recentFailures.filter(run => run.project === project.id)
        })).filter(group => group.favorites.length || group.runs.length || group.failures.length) : []
        function logPage(run) {
            scroll.contentItem.cancelFlick();
            returnScrollY = scroll.contentItem.contentY;
            logRun = run;
            logQuery = "";
            lines = [];
            logLoading = true;
            ProjectHub.error = "";
            requestLogs();
        }
        function openLogsInTerminal(runId) {
            const viewer = decodeURIComponent(Qt.resolvedUrl("log_terminal.py").toString().slice(7));
            Quickshell.execDetached(["xdg-terminal-exec", "--", "python3", viewer, runId]);
        }
        function requestLogs() {
            ProjectHub.send({
                op: "logs",
                project: logRun.project,
                run: logRun.id
            });
        }
        function closeLogs() {
            logRun = null;
            lines = [];
            Qt.callLater(() => {
                if (panel.visible && !panel.logRun) {
                    const view = scroll.contentItem;
                    view.contentY = Math.max(view.originY, Math.min(returnScrollY, view.originY + view.contentHeight - view.height));
                }
            });
        }
        function scrollLogsToEnd() {
            if (logRun && !logQuery.trim())
                logScroll.contentY = Math.max(0, logScroll.contentHeight - logScroll.height);
        }
        onVisibleChanged: {
            if (visible)
                ProjectHub.panelOpened(panel);
            if (counted !== visible) {
                counted = visible;
                ProjectHub.panels += visible ? 1 : -1;
            }
            if (!visible) {
                acceptsKeyboard = false;
                confirmation.close();
                mode = "";
                tab = "main";
                portQuery = "";
                query = "";
                logRun = null;
                lines = [];
            }
        }
        Component.onDestruction: if (counted)
            ProjectHub.panels--
        Connections {
            target: ProjectHub
            function onPanelOpened(window) {
                if (panel.visible && window !== panel && window.screen === panel.screen)
                    panel.visible = false;
            }
            function onLogResult(run, lines) {
                if (panel.logRun?.id !== run)
                    return;
                panel.followLogTail = panel.logLoading || logScroll.atYEnd;
                panel.lines = lines;
                panel.logLoading = false;
                if (panel.followLogTail)
                    logTail.restart();
            }
        }
        Timer {
            running: panel.showingSystemPorts
            repeat: true
            interval: ProjectHub.intervalSeconds * 1000
            onTriggered: ProjectHub.send({
                op: "systemPorts"
            })
        }
        Timer {
            running: panel.visible && !!panel.logRun
            repeat: true
            interval: 1500
            onTriggered: panel.requestLogs()
        }
        Timer {
            id: logTail
            // Wait for the log viewport to be laid out before jumping to its end.
            interval: 0
            onTriggered: panel.scrollLogsToEnd()
        }
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: tile.host.background
            border.color: Qt.alpha(tile.host.ink, 0.2)
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            RowLayout {
                id: header
                B {
                    visible: !!panel.project || !!panel.mode || !!panel.logRun
                    text: "‹"
                    Accessible.name: "Back"
                    onClicked: {
                        if (panel.logRun) {
                            panel.closeLogs();
                            return;
                        }
                        if (panel.mode)
                            panel.mode = "";
                        else
                            panel.key = "";
                        panel.query = "";
                    }
                }
                ProjectMark {
                    monitor: tile.monitor
                    tone: tile.tone
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                }
                T {
                    text: panel.logRun ? "Logs" : panel.project?.name || (tile.monitor ? "Project Resources" : "Project Commands")
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                RefreshButton {
                    ink: tile.host.ink
                    busy: ProjectHub.ticking
                    onClicked: {
                        if (panel.logRun)
                            panel.requestLogs();
                        else
                            tile.send(panel.showingSystemPorts ? {
                                op: "systemPorts"
                            } : {
                                op: "refresh",
                                monitor: true,
                                detail: true
                            });
                    }
                }
                B {
                    text: "×"
                    Accessible.name: "Close"
                    onClicked: panel.visible = false
                }
            }
            T {
                id: errorLabel
                visible: !!ProjectHub.error
                text: ProjectHub.error
                color: tile.host.accent
            }
            RowLayout {
                visible: !tile.monitor && !panel.mode && !panel.logRun
                B {
                    text: panel.project ? "Commands" : "Projects"
                    primary: panel.tab === "main"
                    onClicked: panel.tab = "main"
                }
                B {
                    visible: !panel.project
                    text: "Active (" + tile.activeRuns.length + ")"
                    primary: panel.activeTab
                    onClicked: panel.tab = "active"
                }
                B {
                    text: panel.project ? "Ports" : "System ports"
                    primary: panel.portsTab
                    onClicked: {
                        panel.tab = "ports";
                        if (panel.project)
                            ProjectHub.tick();
                    }
                }
            }
            TextField {
                Layout.fillWidth: true
                visible: !!panel.project && !panel.mode && !tile.monitor && !panel.portsTab && !panel.logRun
                placeholderText: "Search commands"
                text: panel.query
                onTextEdited: panel.query = text
            }
            RowLayout {
                visible: !tile.monitor && panel.portsTab && !panel.mode && !panel.logRun
                Layout.fillWidth: true
                Field {
                    id: portFilter
                    placeholderText: panel.project ? "Filter by port or protocol" : "Filter by port, address, protocol, process, or PID"
                    Accessible.name: "Filter ports"
                    text: panel.portQuery
                    onTextEdited: {
                        panel.portQuery = text;
                        scroll.contentItem.contentY = 0;
                    }
                }
                B {
                    visible: !!panel.portQuery
                    text: "×"
                    Accessible.name: "Clear port filter"
                    onClicked: {
                        panel.portQuery = "";
                        portFilter.forceActiveFocus();
                    }
                }
            }
            ScrollView {
                id: scroll
                visible: !panel.logRun
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: 8
                    ColumnLayout {
                        id: overview
                        spacing: 10
                        visible: !panel.mode && !panel.project && panel.tab === "main"
                        Layout.fillWidth: true
                        RowLayout {
                            id: summary
                            visible: ProjectHub.projects.length > 0
                            Layout.fillWidth: true
                            readonly property var metrics: ProjectHub.projects.map(p => p.metric || {})
                            Repeater {
                                model: tile.monitor ? [[(tile.partial ? "≈" : "") + tile.mem(tile.memoryTotal), "Attributed RAM"], [(summary.metrics.some(m => m.cpuPartial) ? "≈" : "") + summary.metrics.reduce((v, m) => v + (m.totalCpu || 0), 0).toFixed(1) + "%", "CPU"], [summary.metrics.reduce((v, m) => v + (m.processes?.length || 0), 0), "Processes"], [summary.metrics.filter(m => m.processes?.length || m.containers?.some(c => c.state === "running")).length, "Active projects"]] : [[ProjectHub.projects.length, "Projects"], [tile.activeRuns.length, "Running"], [ProjectHub.projects.reduce((v, p) => v + p.commands.length, 0), "Commands"]]
                                delegate: ColumnLayout {
                                    required property var modelData
                                    spacing: 1
                                    Layout.fillWidth: true
                                    T {
                                        text: modelData[0]
                                        font.pixelSize: 18
                                        font.weight: Font.DemiBold
                                    }
                                    T {
                                        text: modelData[1]
                                        font.pixelSize: 11
                                        color: tile.muted
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: ProjectHub.projects.length > 0
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Qt.alpha(tile.host.ink, 0.12)
                        }
                        ColumnLayout {
                            visible: !ProjectHub.projects.length
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            Layout.bottomMargin: 8
                            spacing: 4
                            T {
                                text: tile.monitor ? "Choose a project to monitor" : "Choose a project folder"
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            T {
                                text: tile.monitor ? "Add a folder to monitor CPU, memory, and processes." : "Orla finds scripts and tasks you can run from here."
                                color: tile.muted
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.preferredHeight: childrenRect.height
                            spacing: 6
                            B {
                                primary: true
                                text: "Add folder"
                                onClicked: tile.edit("add", "")
                            }
                            B {
                                text: "Discover projects"
                                onClicked: tile.edit("discover", "")
                            }
                            B {
                                visible: tile.monitor
                                text: panel.sortBy === "total" ? "Sort by CPU" : "Sort by RAM"
                                onClicked: panel.sortBy = panel.sortBy === "total" ? "totalCpu" : "total"
                            }
                            B {
                                visible: tile.monitor
                                text: "Intervals"
                                onClicked: tile.edit("interval", JSON.stringify({
                                    open: ProjectHub.intervalSeconds,
                                    closed: ProjectHub.idleSeconds
                                }, null, 2))
                            }
                        }
                        Repeater {
                            model: panel.visible && !panel.project && !panel.mode ? [...new Set((ProjectHub.docker?.rows || []).filter(r => r.workingDir).map(r => r.project))].filter(n => !ProjectHub.projects.some(p => p.compose.includes(n))) : []
                            delegate: B {
                                required property string modelData
                                text: "Importar Compose · " + modelData
                                onClicked: tile.send({
                                    op: "importDocker",
                                    name: modelData
                                })
                            }
                        }
                        Repeater {
                            model: (panel.visible && !panel.project && !panel.mode ? ProjectHub.projects : []).slice().sort((a, b) => (b.metric?.[panel.sortBy] || 0) - (a.metric?.[panel.sortBy] || 0))
                            delegate: B {
                                required property var modelData
                                Layout.fillWidth: true
                                readonly property var m: modelData.metric || {}
                                readonly property int running: ProjectHub.runs.filter(r => r.project === modelData.id && !r.ended).length
                                text: (m.processes?.length || m.containers?.some(c => c.state === "running") || running ? "●  " : "○  ") + modelData.name + "    " + (m.total !== undefined ? (m.partial || m.approxMemory ? "≈" : "") + tile.mem(m.total) + "   " + (m.cpuPartial ? "≈" : "") + m.totalCpu.toFixed(1) + "%   " + m.processes.length + " processes" : "") + (running ? "   ▶ " + running : "")
                                contentItem: RowLayout {
                                    spacing: 10
                                    Rectangle {
                                        implicitWidth: 8
                                        implicitHeight: 8
                                        radius: 4
                                        color: running || m.processes?.length || m.containers?.some(c => c.state === "running") ? tile.tone : Qt.alpha(tile.host.ink, 0.22)
                                    }
                                    T {
                                        text: modelData.name
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideMiddle
                                        wrapMode: Text.NoWrap
                                    }
                                    Text {
                                        color: tile.muted
                                        font.pixelSize: 12
                                        text: tile.monitor ? (m.partial || m.approxMemory ? "≈" : "") + tile.mem(m.total) + "    " + (m.cpuPartial ? "≈" : "") + (m.totalCpu || 0).toFixed(1) + "%" : running + " running"
                                    }
                                    Text {
                                        color: tile.muted
                                        text: "›"
                                        font.pixelSize: 18
                                    }
                                }
                                onClicked: {
                                    panel.key = modelData.id;
                                    panel.query = "";
                                }
                                Rectangle {
                                    visible: tile.monitor
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    width: parent.width * Math.min(1, (m.totalCpu || 0) / 100)
                                    height: 2
                                    color: tile.host.accent
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: !panel.mode && !tile.monitor && panel.portsTab
                        Layout.fillWidth: true
                        spacing: 8
                        T {
                            text: panel.project ? "Open ports for this project" : "Ports in use on the system"
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        T {
                            visible: !panel.ports.length
                            text: panel.project ? (ProjectHub.ticking ? "Checking ports…" : "No open ports found for this project.") : (ProjectHub.systemPorts === null ? "Checking ports…" : "No TCP or UDP ports found.")
                            color: tile.muted
                        }
                        T {
                            visible: panel.ports.length > 0 && !panel.filteredPorts.length
                            text: "No ports match the filter."
                            color: tile.muted
                        }
                        Repeater {
                            model: panel.visible && parent.visible ? panel.filteredPorts : []
                            delegate: Rectangle {
                                id: port
                                required property var modelData
                                readonly property bool system: typeof modelData !== "string"
                                readonly property bool local: !system && /^(tcp|udp)\//.test(modelData)
                                Layout.fillWidth: true
                                implicitHeight: portRow.implicitHeight + 20
                                radius: 6
                                color: Qt.alpha(tile.host.ink, 0.045)
                                ColumnLayout {
                                    id: portRow
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 3
                                    RowLayout {
                                        Layout.fillWidth: true
                                        T {
                                            text: {
                                                if (!port.system)
                                                    return port.local ? port.modelData.slice(4) : port.modelData;
                                                const address = port.modelData.address;
                                                return (address.includes(":") ? "[" + address + "]" : address) + ":" + port.modelData.port;
                                            }
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            text: port.system ? (port.modelData.protocol === "tcp" ? "TCP · Listening" : "UDP · Bound") : port.local ? port.modelData.slice(0, 3).toUpperCase() + " local" : "Docker"
                                            color: tile.muted
                                        }
                                    }
                                    T {
                                        visible: port.system
                                        text: {
                                            if (!port.system)
                                                return "";
                                            const owners = port.modelData.owners;
                                            return owners.length ? owners.map(owner => owner.name + " (PID " + owner.pid + ")").join(" · ") : "Process owner unavailable";
                                        }
                                        color: tile.muted
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: !!panel.project && !panel.mode && !panel.portsTab
                        Layout.fillWidth: true
                        T {
                            text: panel.project?.path || ""
                            color: tile.muted
                        }
                        T {
                            visible: !!panel.project?.error
                            text: panel.project?.error || ""
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.preferredHeight: childrenRect.height
                            spacing: 6
                            B {
                                text: "Open folder"
                                onClicked: Qt.openUrlExternally("file://" + panel.project.path.split("/").map(encodeURIComponent).join("/"))
                            }
                            B {
                                id: editorButton
                                visible: tile.monitor
                                text: "Open in editor ▾"
                                onClicked: editorMenu.open()
                                Menu {
                                    id: editorMenu
                                    popupType: Popup.Item
                                    y: editorButton.height + 4
                                    width: Math.max(editorButton.width, implicitWidth)
                                    palette.windowText: tile.host.ink
                                    palette.text: tile.host.ink
                                    palette.highlightedText: tile.host.ink
                                    palette.highlight: Qt.tint(tile.host.background, Qt.alpha(tile.tone, 0.14))
                                    background: Rectangle {
                                        radius: 8
                                        color: tile.host.background
                                        border.color: Qt.alpha(tile.host.ink, 0.22)
                                    }
                                    Repeater {
                                        model: [
                                            {
                                                name: "Neovim",
                                                id: "nvim"
                                            },
                                            {
                                                name: "VS Code",
                                                id: "code"
                                            },
                                            {
                                                name: "Zed",
                                                id: "zed"
                                            }
                                        ]
                                        delegate: MenuItem {
                                            required property var modelData
                                            text: modelData.name
                                            onTriggered: tile.send({
                                                op: "openEditor",
                                                editor: modelData.id
                                            })
                                        }
                                    }
                                }
                            }
                            B {
                                text: "Configure"
                                onClicked: tile.edit("configure", JSON.stringify({
                                    name: panel.project.name,
                                    compose: panel.project.compose
                                }, null, 2))
                            }
                            B {
                                text: "Remove"
                                onClicked: tile.confirm("Remove this project from the registry?", {
                                    op: "remove"
                                })
                            }
                        }
                        T {
                            visible: tile.monitor
                            text: "Local memory   " + tile.mem(panel.metric.local) + (panel.metric.approxMemory ? " (includes estimated RSS)" : "") + "     Containers   " + tile.mem(panel.metric.containerRam) + (panel.metric.partial ? " (partial)" : "")
                        }
                        Repeater {
                            model: panel.visible && tile.monitor ? ["CPU", "RAM"] : []
                            delegate: RowLayout {
                                required property int index
                                required property string modelData
                                Layout.fillWidth: true
                                T {
                                    Layout.fillWidth: false
                                    Layout.preferredWidth: 100
                                    text: modelData + "   " + (index ? tile.mem(panel.metric.total) : (panel.metric.totalCpu || 0).toFixed(1) + "%")
                                }
                                Trend {
                                    Layout.fillWidth: true
                                    implicitHeight: 35
                                    points: panel.metric.history || []
                                    column: index
                                    ink: tile.tone
                                }
                            }
                        }
                        T {
                            visible: tile.monitor && !!panel.metric.cpuPartial
                            color: tile.muted
                            text: "CPU totals are partial until there are two local samples and Docker metrics."
                        }
                        ProcessTable {
                            Layout.fillWidth: true
                            visible: tile.monitor
                            projectId: panel.key
                            ink: tile.host.ink
                            tone: tile.tone
                            processes: panel.visible && tile.monitor ? panel.metric.processes || [] : []
                        }
                        T {
                            visible: tile.monitor
                            text: "Docker"
                            font.bold: true
                        }
                        T {
                            visible: tile.monitor && !panel.metric.containers?.length
                            text: ProjectHub.docker?.online ? "No containers associated." : "Docker is unavailable or locked."
                            color: tile.muted
                        }
                        Repeater {
                            model: panel.visible && tile.monitor ? panel.metric.containers || [] : []
                            delegate: T {
                                required property var modelData
                                text: modelData.name + "   " + (modelData.service || "") + "   " + modelData.state + "   " + (modelData.health || "") + "   " + (modelData.ram == null ? "RAM unavailable" : tile.mem(modelData.ram))
                            }
                        }
                        T {
                            visible: !!panel.metric.ports?.length && tile.monitor
                            text: "Ports   " + (panel.metric.ports || []).join(", ")
                        }
                        Repeater {
                            model: (panel.visible && !panel.mode ? panel.project?.commands || [] : []).filter(c => (c.name + " " + c.category).toLowerCase().includes(panel.query.toLowerCase())).sort((a, b) => Number(!!b.favorite) - Number(!!a.favorite) || String(a.category).localeCompare(String(b.category)))
                            delegate: ColumnLayout {
                                required property var modelData
                                readonly property var cmd: modelData
                                readonly property var latest: panel.runs.find(r => r.cmd === cmd.id)
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 7
                                    Layout.bottomMargin: 5
                                    implicitHeight: 1
                                    color: Qt.alpha(tile.host.ink, 0.16)
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    T {
                                        text: (cmd.favorite ? "★  " : "") + cmd.name
                                        font.pixelSize: 16
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: cmd.category || "Local"
                                        color: tile.muted
                                        textFormat: Text.PlainText
                                    }
                                    Text {
                                        visible: !!latest
                                        text: latest?.state || ""
                                        color: tile.tone
                                        font.weight: Font.Medium
                                        textFormat: Text.PlainText
                                    }
                                }
                                T {
                                    visible: !!cmd.description
                                    text: cmd.description || ""
                                }
                                T {
                                    text: cmd.argv.join(" ")
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    color: tile.muted
                                }
                                T {
                                    font.pixelSize: 11
                                    text: (cmd.source ? cmd.source + "  ·  " : "") + cmd.id
                                    color: tile.muted
                                }
                                Flow {
                                    visible: !tile.monitor
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: childrenRect.height
                                    spacing: 5
                                    B {
                                        primary: true
                                        text: "Run"
                                        onClicked: tile.start(panel.project, cmd)
                                    }
                                    B {
                                        visible: !!latest
                                        text: "Logs"
                                        onClicked: panel.logPage(latest)
                                    }
                                    B {
                                        visible: !!latest && !latest.ended
                                        text: "Stop"
                                        onClicked: tile.confirm("Stop " + cmd.name + "?", {
                                            op: "stop",
                                            run: latest.id,
                                            confirmed: true
                                        })
                                    }
                                    B {
                                        text: "Edit"
                                        onClicked: tile.edit("command", JSON.stringify(cmd, null, 2))
                                    }
                                    B {
                                        text: cmd.favorite ? "Unpin" : "Favorite"
                                        onClicked: tile.send({
                                            op: "save",
                                            command: Object.assign({}, cmd, {
                                                favorite: !cmd.favorite
                                            })
                                        })
                                    }
                                    B {
                                        visible: cmd.id.startsWith("custom:")
                                        text: "Delete"
                                        onClicked: tile.confirm("Delete this command?", {
                                            op: "delete",
                                            id: cmd.id
                                        })
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        id: runList
                        visible: !tile.monitor && !panel.mode && (panel.activeTab || (!!panel.project && !panel.portsTab))
                        Layout.fillWidth: true
                        spacing: 8
                        T {
                            visible: !panel.activeTab
                            text: "Runs and history"
                            font.bold: true
                        }
                        RowLayout {
                            visible: panel.activeTab
                            Layout.fillWidth: true
                            T {
                                text: "Commands by project"
                                font.bold: true
                            }
                            B {
                                id: environmentButton
                                primary: true
                                enabled: tile.environmentProjects.length > 0
                                text: "Start environment ▾"
                                onClicked: environmentMenu.open()
                                Menu {
                                    id: environmentMenu
                                    popupType: Popup.Item
                                    y: environmentButton.height + 4
                                    palette.windowText: tile.host.ink
                                    palette.highlight: Qt.tint(tile.host.background, Qt.alpha(tile.tone, 0.14))
                                    background: Rectangle {
                                        radius: 8
                                        color: tile.host.background
                                        border.color: Qt.alpha(tile.host.ink, 0.22)
                                    }
                                    Instantiator {
                                        model: tile.environmentProjects
                                        onObjectAdded: (index, object) => environmentMenu.insertItem(index, object)
                                        onObjectRemoved: (index, object) => environmentMenu.removeItem(object)
                                        delegate: MenuItem {
                                            required property var modelData
                                            text: modelData.name
                                            onTriggered: Qt.callLater(tile.startEnvironment, modelData)
                                        }
                                    }
                                }
                            }
                        }
                        T {
                            visible: panel.activeTab && !tile.environmentProjects.length
                            text: "To enable Start environment, mark a command to include when starting the environment."
                            color: tile.muted
                            font.pixelSize: 12
                        }
                        T {
                            visible: panel.activeTab && !tile.activeRuns.length
                            text: "No commands running."
                            color: tile.muted
                        }
                        Repeater {
                            model: !runList.visible || !panel.visible ? [] : panel.activeTab ? panel.quickGroups : [{
                                project: panel.project,
                                favorites: [],
                                runs: panel.runs,
                                failures: []
                            }]
                            delegate: ColumnLayout {
                                id: runGroup
                                required property var modelData
                                readonly property var group: modelData
                                Layout.fillWidth: true
                                spacing: 8
                                T {
                                    visible: panel.activeTab
                                    text: runGroup.group.project?.name || ""
                                    Layout.topMargin: 8
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                }
                                T {
                                    visible: runGroup.group.favorites.length > 0
                                    text: "Favorites"
                                    color: tile.muted
                                    font.pixelSize: 12
                                }
                                Repeater {
                                    model: runGroup.group.favorites
                                    delegate: RowLayout {
                                        id: favoriteRow
                                        required property var modelData
                                        readonly property var activeRun: runGroup.group.runs.find(run => run.cmd === modelData.id)
                                        Layout.fillWidth: true
                                        T {
                                            text: "★  " + favoriteRow.modelData.name
                                            font.weight: Font.Medium
                                        }
                                        B {
                                            text: favoriteRow.activeRun ? "Logs" : "Run"
                                            primary: !favoriteRow.activeRun
                                            onClicked: {
                                                if (favoriteRow.activeRun)
                                                    panel.logPage(favoriteRow.activeRun);
                                                else
                                                    tile.start(runGroup.group.project, favoriteRow.modelData);
                                            }
                                        }
                                    }
                                }
                                T {
                                    visible: runGroup.group.favorites.length > 0 && runGroup.group.runs.length > 0
                                    text: "Active runs"
                                    Layout.topMargin: 4
                                    color: tile.muted
                                    font.pixelSize: 12
                                }
                                Repeater {
                                    model: runGroup.group.runs.concat(runGroup.group.failures)
                                    delegate: ColumnLayout {
                                        id: runRow
                                        required property int index
                                        required property var modelData
                                        readonly property var r: modelData
                                        readonly property var project: runGroup.group.project
                                        readonly property var waiting: r.state === "Queued" ? (r.deps || []).map(id => tile.runsById[id]).filter(dep =>
                                            dep && !["Ready", "Completed"].includes(dep.state) && (dep.state !== "Running" || dep.readiness)) : []
                                        readonly property string status: r.state === "Running" && r.readiness ? "Checking readiness" : waiting.length ? "Waiting for dependency" : r.state
                                        readonly property color statusColor: r.state === "Failed" ? (tile.light ? "#a43939" : "#ff9e9e") :
                                            r.state === "Ready" ? (tile.light ? "#166449" : "#8de5b1") :
                                            r.state === "Queued" || r.state === "Starting" || status === "Checking readiness" ? (tile.light ? "#865208" : "#f2c379") : tile.tone
                                        Layout.fillWidth: true
                                        T {
                                            visible: panel.activeTab && runRow.index === runGroup.group.runs.length
                                            text: "Recent failures"
                                            Layout.topMargin: 6
                                            font.weight: Font.DemiBold
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.topMargin: 5
                                            implicitHeight: 1
                                            color: Qt.alpha(tile.host.ink, 0.15)
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            T {
                                                text: tile.commandNameFor(project, r.cmd)
                                                font.weight: Font.DemiBold
                                            }
                                            Rectangle {
                                                radius: 6
                                                implicitWidth: runStatus.implicitWidth + 14
                                                implicitHeight: runStatus.implicitHeight + 6
                                                color: Qt.alpha(runRow.statusColor, 0.12)
                                                Label {
                                                    id: runStatus
                                                    anchors.centerIn: parent
                                                    text: runRow.status
                                                    textFormat: Text.PlainText
                                                    color: runRow.statusColor
                                                    font.weight: Font.Medium
                                                }
                                            }
                                        }
                                        T {
                                            visible: waiting.length > 0
                                            text: "Waiting for " + waiting.map(dep => tile.commandNameFor(project, dep.cmd)).join(", ")
                                            color: tile.muted
                                        }
                                        T {
                                            text: [Math.max(0, Math.round((r.ended || Date.now() / 1000) - r.started)) + " s", r.pid ? "PID " + r.pid : "#" + r.id.slice(0, 8), r.code == null ? "" : "exit " + r.code].filter(Boolean).join("  ·  ")
                                            color: tile.muted
                                            font.pixelSize: 12
                                        }
                                        RowLayout {
                                            B {
                                                text: "Logs"
                                                onClicked: panel.logPage(r)
                                            }
                                            B {
                                                visible: panel.activeTab
                                                text: "Open in terminal"
                                                onClicked: panel.openLogsInTerminal(r.id)
                                            }
                                            B {
                                                visible: !r.ended
                                                text: "Stop"
                                                onClicked: tile.confirm("Stop this run? Associated services may be shared.", {
                                                    op: "stop",
                                                    project: r.project,
                                                    run: r.id,
                                                    confirmed: true
                                                })
                                            }
                                            B {
                                                visible: !r.ended
                                                text: "Restart"
                                                onClicked: tile.confirm("Stop and restart " + r.cmd + "?", {
                                                    op: "restart",
                                                    project: r.project,
                                                    id: r.cmd,
                                                    confirmed: true
                                                })
                                            }
                                            B {
                                                visible: !!r.ended
                                                text: "Run again"
                                                onClicked: tile.confirm("Run again " + r.cmd + "?", {
                                                    op: "start",
                                                    project: r.project,
                                                    id: r.cmd,
                                                    confirmed: true
                                                })
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: !!panel.mode
                        Layout.fillWidth: true
                        T {
                            text: ({
                                    add: "Project path",
                                    discover: "Folder containing the projects",
                                    configure: "Name and Compose associations",
                                    interval: "Intervals in seconds",
                                    command: "Command definition"
                                })[panel.mode] || ""
                            font.bold: true
                        }
                        Field {
                            id: projectName
                            visible: panel.mode === "configure"
                            placeholderText: "Project name"
                        }
                        Field {
                            id: composeNames
                            visible: panel.mode === "configure"
                            placeholderText: "Comma-separated Compose projects"
                        }
                        ColumnLayout {
                            visible: panel.mode === "command"
                            Layout.fillWidth: true
                            Field {
                                id: commandName
                                placeholderText: "Command name"
                            }
                            Field {
                                id: commandDescription
                                placeholderText: "Description (optional)"
                            }
                            Field {
                                id: commandCategory
                                placeholderText: "Category"
                            }
                            T {
                                text: "Executable and arguments"
                                font.weight: Font.DemiBold
                            }
                            Field {
                                id: commandArgs
                                readOnly: !!panel.original.source
                                placeholderText: '["python", "-m", "http.server"]'
                            }
                            CheckBox {
                                id: inEnvironment
                                text: "Include when starting the environment"
                                palette.windowText: tile.host.ink
                            }
                            CheckBox {
                                id: needsConfirm
                                text: "Require confirmation"
                                palette.windowText: tile.host.ink
                            }
                            T {
                                text: "Startup order"
                                font.weight: Font.DemiBold
                            }
                            Field {
                                id: httpReadiness
                                placeholderText: "HTTP readiness URL (optional)"
                                Accessible.name: "HTTP readiness URL"
                            }
                            T {
                                text: "Use an endpoint that responds successfully when this command is ready, such as a health check."
                                color: tile.muted
                                font.pixelSize: 12
                            }
                            B {
                                text: "Run after" + (tile.selectedDependencies.length ? " (" + tile.selectedDependencies.length + ")" : "")
                                onClicked: dependencyPicker.visible = !dependencyPicker.visible
                            }
                            T {
                                visible: tile.selectedDependencies.length > 0
                                text: tile.selectedDependencies.map(id => tile.commandNameFor(panel.project, id)).join(", ")
                                color: tile.muted
                                font.pixelSize: 12
                            }
                            ColumnLayout {
                                id: dependencyPicker
                                visible: false
                                Layout.fillWidth: true
                                Repeater {
                                    model: dependencyPicker.visible && panel.mode === "command" ? (panel.project?.commands || []).filter(command => command.id !== panel.original.id) : []
                                    delegate: CheckBox {
                                        required property var modelData
                                        text: modelData.name
                                        palette.windowText: tile.host.ink
                                        checked: tile.selectedDependencies.includes(modelData.id)
                                        onToggled: {
                                            const id = modelData.id;
                                            tile.selectedDependencies = checked ? [...tile.selectedDependencies, id] : tile.selectedDependencies.filter(value => value !== id);
                                        }
                                    }
                                }
                            }
                            CheckBox {
                                id: advanced
                                text: "Advanced settings"
                                palette.windowText: tile.host.ink
                            }
                        }
                        Field {
                            id: pathField
                            visible: panel.mode === "add" || panel.mode === "discover"
                            placeholderText: "/path/to/projects"
                            selectByMouse: true
                            onAccepted: if (text.trim())
                                tile.save()
                        }
                        TextArea {
                            id: editor
                            Layout.fillWidth: true
                            wrapMode: TextEdit.WrapAnywhere
                            selectByMouse: true
                            visible: panel.mode === "interval" || (panel.mode === "command" && advanced.checked)
                            color: tile.host.ink
                            placeholderText: panel.mode === "add" || panel.mode === "discover" ? "/path/to/projects" : ""
                            background: Rectangle {
                                radius: 6
                                color: Qt.alpha(tile.host.ink, 0.06)
                            }
                        }
                        B {
                            text: "Save"
                            onClicked: tile.save()
                        }
                    }
                }
            }
            ColumnLayout {
                visible: !!panel.logRun
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Field {
                        text: panel.logQuery
                        placeholderText: "Search logs"
                        onTextEdited: {
                            panel.logQuery = text;
                            if (text.trim())
                                logScroll.contentY = 0;
                            else {
                                panel.followLogTail = true;
                                logTail.restart();
                            }
                        }
                    }
                    B {
                        text: "Open in terminal"
                        enabled: !!panel.logRun
                        onClicked: panel.openLogsInTerminal(panel.logRun.id)
                    }
                }
                ScrollView {
                    id: logView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    background: Rectangle {
                        radius: 8
                        color: Qt.alpha(tile.host.ink, 0.045)
                    }
                    Flickable {
                        id: logScroll
                        contentWidth: logView.availableWidth
                        contentHeight: logText.height
                        boundsBehavior: Flickable.StopAtBounds
                        onHeightChanged: if (panel.logRun && panel.followLogTail)
                            logTail.restart()
                        onMovementStarted: panel.followLogTail = false
                        TextEdit {
                            id: logText
                            width: logScroll.contentWidth
                            height: implicitHeight
                            padding: 10
                            readOnly: true
                            selectByMouse: true
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: "monospace"
                            color: tile.host.ink
                            text: {
                                const search = panel.logQuery.trim().toLowerCase();
                                const output = (search ? panel.lines.filter(line => line.toLowerCase().includes(search)) : panel.lines).join("\n");
                                return output || (panel.logLoading ? "Loading logs…" : search ? "No matching log lines." : "No log lines available.");
                            }
                        }
                    }
                }
            }
        }
        Popup {
            id: confirmation
            parent: panel.contentItem
            popupType: Popup.Item
            anchors.centerIn: parent
            width: Math.min(420, parent.width - 24)
            padding: 16
            modal: true
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            property string question: ""
            property var request: null
            onClosed: {
                question = "";
                request = null;
            }
            Overlay.modal: Rectangle {
                color: "#55000000"
            }
            background: Rectangle {
                radius: 12
                color: tile.host.background
                border.color: Qt.alpha(tile.host.ink, 0.22)
            }
            contentItem: ColumnLayout {
                spacing: 10
                T {
                    text: "Confirm action"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                ScrollView {
                    id: questionView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(questionText.implicitHeight, 168, Math.max(48, panel.height - 112))
                    contentWidth: availableWidth
                    clip: true
                    T {
                        id: questionText
                        width: questionView.availableWidth
                        text: confirmation.question
                        wrapMode: Text.WrapAnywhere
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    B {
                        text: "Cancel"
                        onClicked: confirmation.close()
                    }
                    B {
                        text: confirmation.request?.op === "all" ? "Start environment" : confirmation.request?.op === "start" ? "Run" : "Confirm"
                        primary: true
                        onClicked: {
                            const request = confirmation.request;
                            confirmation.close();
                            if (request)
                                tile.send(request);
                        }
                    }
                }
            }
        }
    }
}
