import QtQuick
import QtQuick.Controls

Item {
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
        smooth: true
        mipmap: true
        scale: parent.zoomEnabled && parent.button.hovered ? 1.46 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
}
