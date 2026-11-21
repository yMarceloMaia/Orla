import QtQuick
import QtQuick.Controls.Basic

ToolButton {
    id: button
    required property bool busy
    required property color ink
    enabled: !busy
    text: busy ? "Atualizando…" : "Atualizar"
    Accessible.name: text
    horizontalPadding: 10
    verticalPadding: 5
    background: Rectangle {
        radius: 8
        color: Qt.alpha(button.ink, button.down ? 0.19 : button.hovered ? 0.12 : 0.06)
        border.color: Qt.alpha(button.ink, button.visualFocus ? 0.8 : 0.18)
    }
    contentItem: Row {
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.busy ? "…" : "↻"
            font.pixelSize: 16
            color: button.ink
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.ink
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
