import QtQuick
import QtQuick.Controls.Basic
import Quickshell.Widgets
import QtQuick.Shapes
import Quickshell.Services.Mpris

Rectangle {
    id: tile
    required property int edge
    required property bool compact
    property bool iconOnly: false
    required property color ink
    required property color surface
    required property color accent
    required property bool shown
    readonly property var player: {
        if (!enabled || iconOnly) return null;
        const players = Mpris.players.values;
        return players.find(p => p.isPlaying)
            || players.find(p => p.playbackState === MprisPlaybackState.Paused)
            || null;
    }
    visible: enabled
    width: compact ? edge : edge + 203
    height: edge
    radius: Math.min(12, edge / 4)
    color: surface
    border.color: Qt.alpha(ink, 0.17)

    ClippingRectangle {
        id: cover
        readonly property int inset: Math.round(tile.edge * 0.15)
        radius: Math.min(7, width / 4)
        color: Qt.alpha(tile.ink, 0.07)
        anchors.left: parent.left
        anchors.leftMargin: inset
        anchors.verticalCenter: parent.verticalCenter
        width: tile.edge - 2 * inset
        height: width
        Image {
            id: art
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            source: tile.player?.trackArtUrl || ""
            sourceSize: Qt.size(120, 120)
        }
        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "♫"
            color: tile.accent
            font.pixelSize: cover.height * 0.65
        }
    }

    Column {
        visible: !tile.compact
        anchors.left: cover.right
        anchors.leftMargin: 8
        anchors.right: controls.left
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: tile.player?.trackTitle || tile.player?.identity || "Nothing playing"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: tile.ink
            font.bold: true
            font.pixelSize: 12
        }
        Text {
            width: parent.width
            visible: tile.edge >= 38 && !!text
            text: tile.player?.trackArtist || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Qt.alpha(tile.ink, 0.75)
            font.pixelSize: 10
        }
        Rectangle {
            width: parent.width
            height: 2
            visible: tile.player?.length > 0 && tile.player.positionSupported
            color: Qt.alpha(tile.ink, 0.24)
            Rectangle {
                height: parent.height
                width: parent.width * Math.min(1, Math.max(0, (tile.player?.position || 0) / (tile.player?.length || 1)))
                color: tile.accent
            }
            Timer {
                interval: 1000
                repeat: true
                running: tile.shown && !tile.compact && parent.visible && !!tile.player?.isPlaying
                onTriggered: tile.player?.positionChanged()
            }
        }
    }

    Row {
        id: controls
        visible: !tile.iconOnly && (!tile.compact || !!tile.player)
        anchors.right: parent.right
        anchors.rightMargin: tile.compact ? 0 : 6
        anchors.verticalCenter: parent.verticalCenter
        component ControlButton: ToolButton {
            id: button
            required property string description
            required property string glyph
            property bool primary: false
            width: tile.compact ? tile.edge : primary ? 30 : 24
            height: tile.edge
            padding: 0
            hoverEnabled: true
            Accessible.name: description
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) - 2
                    height: width
                    radius: width / 2
                    color: tile.compact ? Qt.alpha(tile.surface, 0.83)
                         : Qt.alpha(tile.ink, button.down ? 0.24 : button.hovered ? 0.16 : button.primary ? 0.08 : 0)
                    border.color: button.visualFocus ? tile.accent : "transparent"
                }
            }
            contentItem: Item {
                Shape {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    opacity: button.enabled ? 1 : 0.35
                    ShapePath {
                        strokeWidth: -1
                        fillColor: tile.ink
                        PathSvg { path: button.glyph }
                    }
                }
            }
        }
        ControlButton {
            visible: !tile.compact
            glyph: "M3 3h2v10H3z M13 3v10L6 8z"
            description: "Previous track"
            enabled: !!tile.player?.canGoPrevious
            onClicked: tile.player.previous()
        }
        ControlButton {
            primary: true
            glyph: tile.player?.isPlaying ? "M4 3h3v10H4z M9 3h3v10H9z" : "M5 2.5l8.5 5.5L5 13.5z"
            description: tile.player?.isPlaying ? "Pause" : "Play"
            enabled: !!tile.player?.canTogglePlaying
            onClicked: tile.player.togglePlaying()
        }
        ControlButton {
            visible: !tile.compact
            glyph: "M11 3h2v10h-2z M3 3l7 5-7 5z"
            description: "Next track"
            enabled: !!tile.player?.canGoNext
            onClicked: tile.player.next()
        }
    }
}
