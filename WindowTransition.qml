import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: effect
    required property color accent
    property rect fromBox
    property rect toBox
    property url icon
    property string pendingAddress: ""
    signal restoreReady(string address)
    property bool restoring
    property real progress: 0
    visible: tween.running
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "orla-window-transition"

    function play(windowBox, iconBox, source, restore, address) {
        tween.stop();
        fromBox = restore ? iconBox : windowBox;
        toBox = restore ? windowBox : iconBox;
        icon = source;
        restoring = restore;
        pendingAddress = restore ? address : "";
        tween.start();
    }
    NumberAnimation {
        id: tween
        target: effect
        property: "progress"
        from: 0; to: 1
        duration: 200
        onRunningChanged: if (!running && effect.pendingAddress) {
            const address = effect.pendingAddress;
            effect.pendingAddress = "";
            effect.restoreReady(address);
        }
        easing.type: Easing.InOutSine
    }
    Rectangle {
        // Scale proportionally so large windows spend more of the trip as a
        // recognizable tile, while their center keeps moving toward the dock.
        function scaled(start, end) {
            return start > 0 && end > 0 ? start * Math.pow(end / start, effect.progress) : 0;
        }
        readonly property real t: effect.progress
        width: scaled(effect.fromBox.width, effect.toBox.width)
        height: scaled(effect.fromBox.height, effect.toBox.height)
        x: (effect.fromBox.x + effect.fromBox.width / 2) * (1 - t)
           + (effect.toBox.x + effect.toBox.width / 2) * t - width / 2
        y: (effect.fromBox.y + effect.fromBox.height / 2) * (1 - t)
           + (effect.toBox.y + effect.toBox.height / 2) * t - height / 2
        radius: Math.min(16, Math.min(width, height) / 4)
        color: Qt.alpha(Qt.tint("#252932", Qt.alpha(effect.accent, 0.38)), 0.46)
        border.color: "#a6282a32"
        border.width: 1
        opacity: effect.restoring ? 1 - 0.5 * Math.max(0, (t - 0.85) / 0.15) : 1
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.color: Qt.tint(effect.accent, "#55ffffff")
            border.width: 2
        }
        Image {
            anchors.centerIn: parent
            width: Math.min(88, parent.width * 0.82, parent.height * 0.82)
            height: width
            source: effect.icon
            sourceSize: Qt.size(176, 176)
            fillMode: Image.PreserveAspectFit
        }
    }
}
