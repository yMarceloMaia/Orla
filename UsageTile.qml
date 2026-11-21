import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ToolButton {
    id: tile
    required property string profile
    readonly property int accountIndex: names.indexOf(profile)
    readonly property bool compact: accountIndex >= 0
    signal selectProfile(string name)
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: tile.selectProfile(tile.names[tile.accountIndex + 1] || "all")
    }
    required property int edge
    required property bool vertical
    required property bool leftEdge
    required property bool busy
    required property var accounts
    required property color ink
    required property color surface
    signal refresh()
    readonly property bool opened: details.opened
    readonly property var names: ["Claude", "claude-trabalho", "Codex"]
    function tint(index) {
        return ["#e49a76", "#deb66d", "#79aea7"][index];
    }
    function weekly(index) {
        return accounts[index]?.windows.find(w => w.label === "Semanal");
    }
    width: vertical || compact ? edge : 196
    height: edge
    padding: 5
    readonly property bool showAccountHint: visible && compact && hovered && !details.visible
    Accessible.name: compact ? names[accountIndex] + " · uso semanal" : "Uso dos planos Claude, claude-trabalho e Codex"
    onClicked: details.open()
    background: Rectangle {
        radius: 10
        color: Qt.tint(tile.surface, Qt.alpha(tile.ink, tile.hovered ? 0.10 : 0.04))
        gradient: tile.compact ? accountFill : null
        Gradient {
            id: accountFill
            GradientStop { position: 0; color: ["#875036", "#806027", "#386963"][Math.max(0, tile.accountIndex)] }
            GradientStop { position: 1; color: ["#492b21", "#44351d", "#203e3c"][Math.max(0, tile.accountIndex)] }
        }
        border.color: tile.compact ? Qt.alpha(tile.tint(tile.accountIndex), tile.hovered ? 0.85 : 0.55) : Qt.alpha(tile.ink, 0.16)
    }
    contentItem: Item {
        Item {
            id: dial
            visible: tile.compact
            anchors.fill: parent
            readonly property var quota: tile.weekly(tile.accountIndex)
            property double now: Date.now()
            readonly property int hours: quota?.reset ? Math.max(0, Math.ceil((quota.reset * 1000 - now) / 3600000)) : 0
            Timer { running: dial.visible; repeat: true; triggeredOnStart: true; interval: 60000; onTriggered: dial.now = Date.now() }
            Canvas {
                id: ring
                anchors.fill: parent
                readonly property real used: dial.quota?.used || 0
                readonly property color tint: tile.tint(Math.max(0, tile.accountIndex))
                readonly property color track: Qt.alpha(tint, 0.23)
                onUsedChanged: requestPaint()
                onTintChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const radius = Math.min(width, height) * 0.44;
                    ctx.lineWidth = Math.max(2, radius * 0.22);
                    ctx.lineCap = "round";
                    for (const [fraction, color] of [[1, track], [used / 100, tint]]) {
                        if (fraction <= 0) continue;
                        ctx.beginPath();
                        ctx.strokeStyle = color;
                        ctx.arc(width / 2, height / 2, radius, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * fraction);
                        ctx.stroke();
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: dial.quota ? Math.round(dial.quota.used) + "%" : "—"
                    font.bold: true; font.pixelSize: Math.max(8, Math.round(dial.width * 0.24)); color: "#fff9f1"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: dial.width >= 32 && !!dial.quota?.reset
                    text: (dial.hours >= 24 ? Math.floor(dial.hours / 24) + "d " : "") + dial.hours % 24 + "h"
                    font.pixelSize: Math.max(7, Math.round(dial.width * 0.16)); color: "#fff0da"
                }
            }
        }
        Row {
            visible: !tile.vertical && !tile.compact
            anchors.centerIn: parent
            spacing: 6
            Repeater {
                model: tile.names
                Column {
                    id: summary
                    required property int index
                    required property string modelData
                    width: 56
                    spacing: 1
                    Text { text: parent.modelData; color: tile.ink; font.pixelSize: 10 }
                    Text { text: tile.weekly(parent.index) ? Math.round(tile.weekly(parent.index).used) + "%" : "—"; color: tile.ink; font.pixelSize: tile.edge < 40 ? 11 : 14; font.bold: true }
                    Rectangle {
                        width: parent.width; height: 3; radius: 1.5
                        color: Qt.alpha(tile.ink, 0.16)
                        Rectangle { width: parent.width * (tile.weekly(summary.index)?.used || 0) / 100; height: parent.height; radius: parent.radius; color: tile.tint(summary.index) }
                    }
                }
            }
        }
        Column {
            visible: tile.vertical && !tile.compact
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: tile.edge * 0.64; height: 4; radius: 2
                    color: Qt.alpha(tile.ink, 0.18)
                    Rectangle { width: parent.width * (tile.weekly(parent.index)?.used || 0) / 100; height: parent.height; color: tile.tint(parent.index); radius: 2 }
                }
            }
        }
    }
    Popup {
        id: details
        popupType: Popup.Window
        focus: true
        padding: 16
        width: 342
        height: body.implicitHeight + 2 * padding
        x: tile.vertical ? (tile.leftEdge ? tile.width : -width) : (tile.width - width) / 2
        y: tile.vertical ? (tile.height - height) / 2 : -height
        palette.buttonText: tile.ink
        background: Rectangle { radius: 14; color: tile.surface; border.color: Qt.alpha(tile.ink, 0.2) }
        contentItem: ColumnLayout {
            id: body
            spacing: 9
            RowLayout {
                Label { Layout.fillWidth: true; text: "Uso dos planos"; font.bold: true; font.pixelSize: 18; color: tile.ink }
                RefreshButton { busy: tile.busy; ink: tile.ink; onClicked: tile.refresh() }
            }
            Repeater {
                model: tile.names
                ColumnLayout {
                    id: profile
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: profile.modelData; font.bold: true; color: tile.ink }
                    Label {
                        visible: !!text
                        text: tile.accounts[profile.index]?.error || (!tile.accounts.length ? "Consultando…" : "")
                        color: Qt.alpha(tile.ink, 0.75)
                    }
                    Repeater {
                        model: tile.accounts[profile.index]?.windows || []
                        RowLayout {
                            id: period
                            required property var modelData
                            Layout.fillWidth: true
                            Label { Layout.preferredWidth: 54; text: period.modelData.label; font.pixelSize: 11; color: tile.ink }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Qt.alpha(tile.ink, 0.15)
                                Rectangle { width: parent.width * period.modelData.used / 100; height: parent.height; radius: 2; color: tile.tint(profile.index) }
                            }
                            Label { Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight; text: Math.round(period.modelData.used) + "%"; font.pixelSize: 11; color: tile.ink }
                            Label {
                                Layout.preferredWidth: 99; horizontalAlignment: Text.AlignRight
                                text: period.modelData.reset ? "↻ " + Qt.formatDateTime(new Date(period.modelData.reset * 1000), "dd/MM HH:mm") : "—"
                                font.pixelSize: 11; color: Qt.alpha(tile.ink, 0.76)
                                Accessible.name: "Renovação: " + text
                            }
                        }
                    }
                }
            }
        }
    }
}
