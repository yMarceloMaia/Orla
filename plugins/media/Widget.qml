import QtQuick
import Quickshell

MediaTile {
    id: widget

    required property var host
    readonly property bool keepOpen: playerPanel.visible

    edge: host.edge
    ink: host.ink
    surface: host.surface
    readonly property bool manualIconOnly: host.preference("iconOnly", false)
    readonly property int dockExtraWidth: manualIconOnly ? 0 : 203
    iconOnly: manualIconOnly || host.compact === true
    compact: iconOnly || host.vertical
    accent: host.accent
    shown: host.shown
    Accessible.name: "Player de mídia"

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: widget.host.savePreference("iconOnly", !widget.manualIconOnly)
    }

    HoverHandler {
        id: iconHover
        enabled: widget.iconOnly
    }

    Timer {
        interval: 250
        running: widget.iconOnly && widget.shown && iconHover.hovered && !playerPanel.visible
        onTriggered: playerPanel.visible = true
    }

    Timer {
        interval: 320
        running: playerPanel.visible && !iconHover.hovered && !panelHover.hovered
        onTriggered: playerPanel.visible = false
    }

    onIconOnlyChanged: if (!iconOnly)
        playerPanel.visible = false
    onShownChanged: if (!shown)
        playerPanel.visible = false

    PopupWindow {
        id: playerPanel

        visible: false
        color: "transparent"
        anchor.item: widget
        anchor.edges: widget.host.vertical ? (widget.host.leftEdge ? Edges.Right : Edges.Left) : Edges.Top
        anchor.gravity: anchor.edges
        implicitWidth: playerCard.width
        implicitHeight: playerCard.height

        MediaTile {
            id: playerCard

            edge: Math.max(50, widget.edge)
            ink: widget.ink
            surface: widget.host.background
            compact: false
            accent: widget.accent
            shown: playerPanel.visible
            enabled: playerPanel.visible

            HoverHandler {
                id: panelHover
            }
        }
    }
}
