import QtQuick
import QtQuick.Controls

Item {
    id: glyph
    required property bool motion
    property string edge: "bottom"
    property real liftDistance: 0
    function bounce() {
        if (motion)
            hop.restart();
    }
    onMotionChanged: if (!motion) {
        hop.stop();
        liftDistance = 0;
    }
    SequentialAnimation {
        id: hop
        NumberAnimation { target: glyph; property: "liftDistance"; from: 0; to: 10; duration: 180; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 65 }
        NumberAnimation { target: glyph; property: "liftDistance"; to: 0; duration: 150; easing.type: Easing.InQuad }
        NumberAnimation { target: glyph; property: "liftDistance"; to: 5; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { target: glyph; property: "liftDistance"; to: 0; duration: 120; easing.type: Easing.InOutQuad }
    }
    required property ToolButton button
    required property url source
    required property bool zoomEnabled
    readonly property real baseSize: Math.round(button.width * 0.82)
    Image {
        anchors.centerIn: parent
        width: parent.baseSize
        height: width
        source: parent.source
        sourceSize.width: Math.ceil(parent.baseSize * 2)
        sourceSize.height: Math.ceil(parent.baseSize * 2)
        fillMode: Image.PreserveAspectFit
        transform: Translate {
            x: glyph.edge === "left" ? glyph.liftDistance : glyph.edge === "right" ? -glyph.liftDistance : 0
            y: glyph.edge === "bottom" ? -glyph.liftDistance : 0
        }
        smooth: true
        mipmap: true
        scale: parent.zoomEnabled && parent.button.hovered ? 1.46 : 1
        Behavior on scale {
            enabled: motion
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    }
}
