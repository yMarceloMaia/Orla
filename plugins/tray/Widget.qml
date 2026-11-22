import QtQuick

FileTray {
    required property var host
    edge: host.edge
    maxWidth: host.screenWidth - (host.vertical ? host.extent : 0) - 14
    maxHeight: host.screenHeight - (host.vertical ? 0 : host.extent) - 14
    ink: host.ink
    vertical: host.vertical
    leftEdge: host.leftEdge
    surface: host.background
    accent: host.accent
    files: host.service.files
    readonly property bool keepOpen: receiving || opened
    onHoveredChanged: host.tip(this, hovered && !opened)
    onOpenedChanged: if (opened)
        host.tip(this, false)
}
