import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import "../../components"

ToolButton {
    id: tile
    required property var host
    readonly property var svc: host.service
    readonly property var rows: svc?.rows || []
    readonly property int activeCount: rows.filter(r => r.state === "running").length
    readonly property bool keepOpen: panel.visible
    readonly property color muted: Qt.alpha(host.ink, 0.68)
    readonly property bool light: host.background.hslLightness > 0.5
    readonly property color green: light ? "#17663e" : "#86dbaa"
    readonly property color blue: light ? "#12669a" : "#85cefa"
    readonly property color danger: light ? "#a43d32" : "#f2a196"
    function stateName(value) {
        const names = {running: "Running", exited: "Stopped", created: "Created", paused: "Paused", restarting: "Restarting", dead: "Inactive", removing: "Removing"}
        return names[value] || value || ""
    }
    readonly property int dockExtraWidth: 40
    readonly property bool compact: host.vertical || host.compact === true
    implicitWidth: compact ? host.edge : host.edge + dockExtraWidth
    padding: compact ? 3 : 6
    implicitHeight: host.edge
    Accessible.name: "Docker Manager"
    onClicked: panel.visible = !panel.visible
    background: Rectangle {
        radius: 10
        color: Qt.tint(tile.host.background, Qt.alpha(tile.host.ink, tile.hovered ? 0.1 : 0.045))
        border.color: Qt.alpha(tile.host.ink, 0.16)
    }
    contentItem: RowLayout {
        spacing: 4
        Image {
            source: "docker.svg"
            fillMode: Image.PreserveAspectFit
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
        }
        Text {
            visible: !tile.compact
            color: tile.host.ink
            text: tile.svc?.online ? tile.activeCount : "–"
            font.bold: true
        }
    }
    component Caption: Label {
        textFormat: Text.PlainText
        color: tile.host.ink
    }
    component Command: Button {
        id: button
        property color tone: tile.host.ink
        implicitHeight: 34
        leftPadding: 12
        rightPadding: 12
        opacity: enabled ? 1 : 0.46
        contentItem: Caption {
            text: button.text
            font.weight: Font.Medium
            color: button.tone
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
        }
        background: Rectangle {
            radius: 7
            color: Qt.alpha(button.tone, button.down ? 0.18 : button.hovered ? 0.12 : 0.055)
            border.color: button.visualFocus ? tile.blue : Qt.alpha(button.tone, 0.16)
        }
    }
    function ram(bytes) {
        return bytes >= 1073741824 ? (bytes / 1073741824).toFixed(1) + " GiB" : Math.round(bytes / 1048576) + " MiB"
    }
    PopupWindow {
        id: panel
        visible: false
        color: "transparent"
        anchor.item: tile
        anchor.edges: tile.host.vertical ? (tile.host.leftEdge ? Edges.Right : Edges.Left) : Edges.Top
        anchor.gravity: anchor.edges
        readonly property bool needsUnlock: !!tile.svc?.locked && !tile.svc?.online
        implicitWidth: Math.min(needsUnlock ? 408 : 520, tile.host.screenWidth - 16)
        implicitHeight: Math.min(needsUnlock ? unlockView.implicitHeight + 40 : tile.svc?.online ? 488 : 224, tile.host.screenHeight - tile.host.extent - 16)
        property string selected: ""
        property bool watching: false
        function watch(value) {
            if (watching === value) return
            watching = value
            if (tile.svc) tile.svc.panels += value ? 1 : -1
        }
        onVisibleChanged: {
            if (visible) selected = ""
            watch(visible)
        }
        Component.onDestruction: watch(false)
        readonly property var container: tile.rows.find(r => r.id === selected)
        function select(row) {
            selected = row.id
            tile.svc.message = ""
        }
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: tile.host.background
            border.color: Qt.alpha(tile.host.ink, 0.22)
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            palette.buttonText: tile.host.ink
            palette.button: tile.host.surface
            focus: true
            Keys.onEscapePressed: panel.visible = false
            spacing: 10
            ColumnLayout {
                id: unlockView
                visible: panel.needsUnlock
                Layout.fillWidth: true
                spacing: 14
                RowLayout {
                    spacing: 12
                    Rectangle {
                        implicitWidth: 52; implicitHeight: 52; radius: 14
                        color: Qt.alpha(tile.blue, 0.12)
                        Image { anchors.centerIn: parent; width: 34; height: 34; source: "docker.svg" }
                        Rectangle {
                            anchors.right: parent.right; anchors.bottom: parent.bottom
                            width: 20; height: 20; radius: 8; color: tile.blue
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter; y: 4
                                width: 8; height: 8; radius: 4; color: "transparent"
                                border.width: 1.5; border.color: tile.host.background
                            }
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 9; width: 10; height: 7; radius: 2; color: tile.host.background }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Caption { text: "Docker"; color: tile.muted; font.pixelSize: 13 }
                        Caption { text: tile.svc?.authorizing ? "Authenticating" : "Access locked"; font.pixelSize: 20; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                    Command { text: "×"; implicitWidth: 32; Accessible.name: "Close panel"; onClicked: panel.visible = false }
                }
                Caption {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: tile.svc?.authorizing ? "Confirm the request in the system dialog." : tile.svc?.installed ? "Allow read access to local containers and metrics for up to 10 minutes." : "Install the helper to unlock Docker using your system password."
                }
                Caption {
                    Layout.fillWidth: true; visible: !!tile.svc?.message
                    color: tile.muted; text: tile.svc?.message || ""; wrapMode: Text.WordWrap
                }
                Button {
                    id: unlockButton
                    Layout.fillWidth: true; implicitHeight: 39
                    enabled: !tile.svc?.authorizing
                    text: tile.svc?.authorizing ? "Waiting for confirmation…" : tile.svc?.installed ? "Unlock Docker" : "Install authentication helper"
                    onClicked: tile.svc.unlock()
                    contentItem: Caption {
                        text: unlockButton.text; font.weight: Font.DemiBold
                        color: tile.light ? "white" : "#112431"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 8; color: unlockButton.hovered ? Qt.tint(tile.blue, Qt.alpha(tile.host.ink, 0.09)) : tile.blue
                        border.color: unlockButton.visualFocus ? tile.host.ink : "transparent"
                    }
                }
            }
            RowLayout {
                visible: !panel.needsUnlock
                Image { source: "docker.svg"; Layout.preferredWidth: 26; Layout.preferredHeight: 26 }
                Caption { text: "Docker"; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                Caption { text: tile.svc?.online ? "●  Online" : tile.svc?.locked ? "○  Locked" : "○  Unavailable"; color: tile.svc?.online ? tile.green : tile.muted }
                ToolButton { text: "×"; Accessible.name: "Close panel"; onClicked: panel.visible = false }
                RefreshButton { busy: !!tile.svc?.busy; ink: tile.host.ink; onClicked: tile.svc.refresh() }
            }
            RowLayout {
                visible: tile.svc?.online && !panel.container
                Repeater {
                    model: [
                        [tile.activeCount, "Running"],
                        [tile.rows.length - tile.activeCount, "Other states"],
                        [tile.rows.some(r => r.ram !== null) ? tile.ram(tile.rows.reduce((sum,r) => sum + (r.ram || 0), 0)) : (tile.activeCount ? "—" : "0 MiB"), "RAM in use"]
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        radius: 0
                        color: "transparent"
                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            Caption { text: modelData[0]; font.bold: true; font.pixelSize: 17 }
                            Caption { text: modelData[1]; color: tile.muted; font.pixelSize: 11 }
                        }
                    }
                }
            }
            Caption { visible: !panel.needsUnlock && !!tile.svc?.error; text: tile.svc?.error || ""; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
            Caption { visible: !panel.needsUnlock && !panel.container && !!tile.svc?.message; text: tile.svc?.message || ""; Layout.fillWidth: true; wrapMode: Text.Wrap }
            Caption { visible: tile.svc?.online && !tile.rows.length; text: "No containers in this Docker context."; color: tile.muted }
            ListView {
                id: list
                visible: !panel.needsUnlock && !panel.container
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: tile.rows
                delegate: Column {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    Caption {
                        visible: row.index === 0 || tile.rows[row.index - 1]?.project !== row.modelData.project
                        width: parent.width
                        height: visible ? 32 : 0
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.project
                        elide: Text.ElideRight
                        color: tile.blue
                        font.bold: true
                    }
                    ToolButton {
                        width: parent.width
                        height: 60
                        padding: 8
                        onClicked: panel.select(row.modelData)
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: panel.select(row.modelData) }
                        background: Rectangle { radius: 7; color: Qt.alpha(tile.host.ink, parent.hovered ? 0.10 : 0.035); border.color: parent.visualFocus ? tile.blue : "transparent" }
                        contentItem: ColumnLayout {
                            spacing: 2
                            RowLayout {
                                Caption { Layout.fillWidth: true; text: row.modelData.name; elide: Text.ElideRight; font.weight: Font.DemiBold }
                                Caption { text: tile.stateName(row.modelData.state); color: row.modelData.state === "running" ? tile.green : tile.muted }
                                Caption { text: "›"; color: tile.muted }
                            }
                            Caption { text: row.modelData.cpu === null ? "Metrics unavailable" : "CPU " + row.modelData.cpu.toFixed(1) + "%   ·   RAM " + tile.ram(row.modelData.ram); color: tile.muted; font.pixelSize: 11 }
                            Rectangle {
                                Layout.fillWidth: true; height: 3; radius: 2; color: Qt.alpha(tile.host.ink, 0.08)
                                Rectangle { height: parent.height; width: parent.width * Math.min(1, (row.modelData.cpu || 0) / 100); radius: 2; color: tile.host.accent }
                            }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
            ScrollView {
                id: actions
                visible: !!panel.container
                Layout.fillHeight: true
                Layout.fillWidth: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: actions.availableWidth
                    spacing: 8
                    Command {
                        text: "‹  Projects"
                        onClicked: panel.selected = ""
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Caption {
                            Layout.fillWidth: true
                            text: panel.container?.name || ""
                            font.pixelSize: 23
                            font.weight: Font.DemiBold
                            wrapMode: Text.WrapAnywhere
                        }
                        Caption {
                            text: tile.stateName(panel.container?.state)
                            color: panel.container?.state === "running" ? tile.green : tile.muted
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { Layout.fillWidth: true; text: panel.container?.project || ""; color: tile.muted; elide: Text.ElideRight }
                        Command {
                            text: (panel.container?.id || "").slice(0,12) + "  ⧉"
                            Accessible.name: "Copy container ID"
                            onClicked: {
                                clipboard.text = panel.selected
                                clipboard.selectAll()
                                clipboard.copy()
                                tile.svc.message = "ID copied."
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 8
                        color: Qt.alpha(tile.blue, 0.065)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            Repeater {
                                model: [["CPU", panel.container?.cpu == null ? "—" : panel.container.cpu.toFixed(1) + "%"],
                                        ["Memory", panel.container?.ram == null ? "—" : tile.ram(panel.container.ram)]]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Caption { text: modelData[0]; color: tile.muted }
                                    Caption { text: modelData[1]; font.pixelSize: 17; font.weight: Font.DemiBold }
                                }
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.preferredHeight: childrenRect.height
                        spacing: 6
                        Repeater {
                            model: [["Live logs","logs"],["Open shell","shell"],["Health checks","health"]]
                            delegate: Command {
                                required property var modelData
                                text: modelData[0]
                                tone: tile.blue
                                enabled: !tile.svc?.busyAction && (modelData[1] !== "shell" || panel.container?.state === "running")
                                onClicked: {
                                    const op = modelData[1]
                                    if (op === "health") { tile.svc.run(op, panel.selected); return }
                                    const args = op === "shell" ? ["exec","-it",panel.selected,"sh"] : ["logs","--tail","200","--follow",panel.selected]
                                    Quickshell.execDetached(["xdg-terminal-exec","--"].concat(tile.svc.unlocked ? ["/usr/bin/pkexec","--disable-internal-agent",tile.svc.helper,op,panel.selected] : ["docker"].concat(args)))
                                }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(tile.host.ink, 0.13) }
                    RowLayout {
                        spacing: 8
                        Command {
                            visible: ["exited","created"].includes(panel.container?.state)
                            text: "Start"
                            tone: tile.green
                            enabled: !tile.svc?.busyAction
                            onClicked: tile.svc.run("start", panel.selected)
                        }
                        Command {
                            visible: panel.container?.state === "running"
                            text: "Restart"
                            enabled: !tile.svc?.busyAction
                            onClicked: tile.svc.run("restart", panel.selected)
                        }
                        Command {
                            visible: panel.container?.state === "running"
                            text: "Stop container"
                            tone: tile.danger
                            enabled: !tile.svc?.busyAction
                            onClicked: tile.svc.run("stop", panel.selected)
                        }
                    }
                    TextEdit { id: clipboard; visible: false }
                    Caption { visible: !!panel.container?.urls?.length; text: "Published ports"; font.weight: Font.DemiBold }
                    Repeater {
                        model: panel.container?.urls || []
                        delegate: Command {
                            Layout.maximumWidth: actions.availableWidth
                            required property string modelData
                            text: "Open " + modelData
                            onClicked: Qt.openUrlExternally(modelData)
                        }
                    }
                    Caption { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; text: tile.svc?.message || ""; visible: !!text }
                }
            }
        }
    }
}
