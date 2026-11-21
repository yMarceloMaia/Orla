import QtQuick

MediaTile {
    required property var host
    edge: host.edge
    ink: host.ink
    surface: host.surface
    compact: host.vertical || host.availableWidth < edge + 203
    accent: host.accent
    shown: host.shown
}
