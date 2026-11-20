import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.MenuItem {
    id: option
    property bool destructive: false
    implicitHeight: visible ? 34 : 0
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    contentItem: Text {
        text: option.text
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.pixelSize: 14
        color: option.destructive ? "#ffb7ae" : "#f3f3f8"
    }
    background: Rectangle {
        radius: 7
        color: option.highlighted || option.hovered ? "#51586c" : "transparent"
    }
}
