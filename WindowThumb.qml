import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Rectangle {
    id: thumb
    required property var client
    property bool capturing: true
    radius: 6
    color: "#23252c"
    clip: true
    Image {
        anchors.centerIn: parent
        width: 26
        height: 26
        visible: !view.hasContent
        source: Quickshell.iconPath(DesktopEntries.heuristicLookup(thumb.client.class)?.icon || "application-x-executable", true)
    }
    ScreencopyView {
        id: view
        readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 1
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * ratio)
        height: Math.min(parent.height, parent.width / Math.max(0.01, ratio))
        captureSource: thumb.capturing ? (Hyprland.toplevels.values.find(t => String(t.address).replace(/^0x/, "") === thumb.client.address.slice(2))?.wayland || null) : null
        paintCursor: false
        live: false
    }
}
