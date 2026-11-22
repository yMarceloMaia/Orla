import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.MenuItem {
    id: option
    required property color ink
    required property color accent
    property bool destructive: false
    readonly property color textColor: destructive ? (ink.hslLightness < 0.5 ? "#a43d32" : "#f2a196") : ink
    implicitHeight: visible ? 35 : 0
    leftPadding: 10
    rightPadding: subMenu ? 24 : 10
    hoverEnabled: true
    contentItem: Text {
        text: option.text
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.pixelSize: 13
        font.weight: Font.Medium
        color: Qt.alpha(option.textColor, option.enabled ? 1 : 0.55)
    }
    background: Rectangle {
        radius: 7
        color: Qt.alpha(option.destructive ? option.textColor : option.accent, option.down ? 0.19 : option.highlighted || option.hovered ? 0.11 : 0)
        border.color: option.visualFocus ? option.accent : "transparent"
    }
}
