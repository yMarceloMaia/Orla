import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell

Popup {
    id: stack
    property bool lightMode: false
    required property string path
    property bool newest: true
    popupType: Popup.Window
    padding: 12
    width: 344
    height: Math.min(350, 100 + files.count * 36)
    background: Rectangle {
        radius: 12
        color: stack.lightMode ? "#f8f8f9fc" : "#fa30323a"
        border.color: "#696c78"
    }
    FolderListModel {
        id: files
        folder: stack.visible ? "file://" + stack.path.split("/").map(encodeURIComponent).join("/") : ""
        sortField: stack.newest ? FolderListModel.Time : FolderListModel.Name
        sortReversed: stack.newest
        showDotAndDotDot: false
    }
    contentItem: ColumnLayout {
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: stack.path.split("/").pop() || "/"
                textFormat: Text.PlainText
                color: stack.lightMode ? "#24252d" : "white"
                elide: Text.ElideMiddle
            }
            ToolButton {
                text: stack.newest ? "Por data" : "Por nome"
                onClicked: stack.newest = !stack.newest
            }
        }
        ListView {
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            model: files
            ScrollBar.vertical: ScrollBar {}
            delegate: DockOption {
                lightMode: stack.lightMode
                required property string fileName
                required property url fileUrl
                required property bool fileIsDir
                width: ListView.view.width
                text: (fileIsDir ? "▸  " : "") + fileName
                onTriggered: {
                    Quickshell.execDetached(["gio", "open", fileUrl.toString()]);
                    stack.close();
                }
            }
            Label {
                anchors.centerIn: parent
                visible: files.status === FolderListModel.Ready && !files.count
                text: "Pasta vazia"
                color: stack.lightMode ? "#595b66" : "#c2c4cd"
            }
        }
        DockOption {
            lightMode: stack.lightMode
            Layout.fillWidth: true
            text: "Abrir pasta"
            onTriggered: {
                Quickshell.execDetached(["gio", "open", stack.path]);
                stack.close();
            }
        }
    }
}
