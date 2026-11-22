import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Qt.labs.folderlistmodel
import Quickshell

Popup {
    id: stack

    required property string path
    required property color surface
    required property color ink
    required property color accent
    required property int maxWidth
    required property int maxHeight
    property bool newest: true
    property bool reversed: true
    property bool showHidden: false
    readonly property color muted: Qt.alpha(ink, 0.70)
    readonly property color outline: Qt.alpha(ink, 0.17)

    function openEntry(entry) {
        Quickshell.execDetached(["gio", "open", entry]);
        close();
    }

    popupType: Popup.Window
    padding: 11
    width: Math.min(368, maxWidth)
    height: Math.min(maxHeight, 112 + (files.count ? Math.min(7, files.count) * 52 : 52))
    background: Rectangle {
        radius: 15
        color: stack.surface
        border.color: stack.outline
    }

    FolderListModel {
        id: files
        folder: stack.visible ? "file://" + stack.path.split("/").map(encodeURIComponent).join("/") : ""
        sortField: stack.newest ? FolderListModel.Time : FolderListModel.Name
        sortReversed: stack.reversed
        showHidden: stack.showHidden
        showDotAndDotDot: false
    }

    component StackLabel: Text {
        color: stack.ink
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.pixelSize: 13
    }

    component StackButton: ToolButton {
        id: button
        hoverEnabled: true
        leftPadding: 8
        rightPadding: 8
        implicitHeight: 30
        contentItem: StackLabel {
            text: button.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.weight: Font.Medium
            color: button.checked ? stack.accent : stack.ink
        }
        background: Rectangle {
            radius: 6
            color: Qt.alpha(button.checked ? stack.accent : stack.ink, button.down ? 0.18 : button.hovered ? 0.12 : button.checked ? 0.09 : 0)
            border.color: button.visualFocus ? stack.accent : "transparent"
        }
    }

    contentItem: ColumnLayout {
        spacing: 8
        RowLayout {
            spacing: 9
            Image {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                source: Quickshell.iconPath("folder", true)
                sourceSize: Qt.size(48, 48)
                fillMode: Image.PreserveAspectFit
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StackLabel {
                    Layout.fillWidth: true
                    text: stack.path.split("/").filter(Boolean).pop() || "/"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                StackLabel {
                    Layout.fillWidth: true
                    text: files.count === 1 ? "1 item" : files.count + " items"
                    color: stack.muted
                    font.pixelSize: 11
                }
            }
            StackButton {
                text: "Open folder ↗"
                onClicked: stack.openEntry(stack.path)
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: toolbar.implicitHeight + 6
            radius: 8
            color: Qt.alpha(stack.ink, 0.055)
            RowLayout {
                id: toolbar
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4
                StackButton {
                    text: stack.newest ? "Date modified" : "Name"
                    Accessible.name: "Sort by " + (stack.newest ? "nome" : "date modified")
                    onClicked: {
                        stack.newest = !stack.newest;
                        stack.reversed = stack.newest;
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                StackButton {
                    text: stack.reversed ? "↓" : "↑"
                    Accessible.name: stack.reversed ? "Switch to ascending order" : "Switch to descending order"
                    onClicked: stack.reversed = !stack.reversed
                }
                StackButton {
                    text: "Hidden files"
                    checkable: true
                    checked: stack.showHidden
                    Accessible.name: "Show hidden files"
                    onClicked: stack.showHidden = checked
                }
            }
        }
        ListView {
            id: list
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            spacing: 4
            model: files
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                id: entry
                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                required property date fileModified
                required property string fileSuffix
                width: ListView.view.width
                height: 48
                leftPadding: 9
                rightPadding: 12
                hoverEnabled: true
                Accessible.name: fileName
                onClicked: stack.openEntry(fileUrl.toString())
                background: Rectangle {
                    radius: 7
                    color: Qt.alpha(stack.ink, entry.down ? 0.15 : entry.hovered ? 0.11 : 0.046)
                    border.color: entry.visualFocus ? stack.accent : "transparent"
                }
                contentItem: RowLayout {
                    spacing: 9
                    Image {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        sourceSize: Qt.size(36, 36)
                        source: Quickshell.iconPath(entry.fileIsDir ? "folder" : "text-x-generic", true)
                        fillMode: Image.PreserveAspectFit
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StackLabel {
                            Layout.fillWidth: true
                            text: entry.fileName
                            font.weight: Font.Medium
                        }
                        StackLabel {
                            Layout.fillWidth: true
                            text: (entry.fileIsDir ? "Folder" : entry.fileSuffix ? entry.fileSuffix.toUpperCase() : "File") + " · " + Qt.formatDateTime(entry.fileModified, "dd/MM/yyyy · HH:mm")
                            color: stack.muted
                            font.pixelSize: 11
                        }
                    }
                }
            }
            StackLabel {
                anchors.centerIn: parent
                visible: files.status === FolderListModel.Ready && !files.count
                text: "Empty folder"
                color: stack.muted
            }
        }
    }
}
