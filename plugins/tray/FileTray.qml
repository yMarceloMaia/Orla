import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell

ToolButton {
    id: tray
    required property var files
    required property int edge
    required property int maxWidth
    required property int maxHeight
    required property bool vertical
    required property bool leftEdge
    required property color surface
    required property color ink
    required property color accent
    readonly property bool opened: drawer.visible
    readonly property bool receiving: receiver.containsDrag || drawerReceiver.containsDrag
    property string lastUri: files.count ? files.get(files.count - 1).uri : ""
    width: edge
    height: edge
    padding: 4
    Accessible.name: "Bandeja de arquivos (" + files.count + ")"
    onClicked: drawer.open()
    function localUris(event) {
        return Array.from(event.urls || [], u => u.toString()).filter(u => /^file:\/\/\/(?!\/)/i.test(u) || /^file:\/\/localhost\//i.test(u));
    }
    function collect(uris) {
        const known = new Set();
        for (let i = 0; i < files.count; ++i)
            known.add(files.get(i).uri);
        for (const uri of uris) {
            if (known.has(uri))
                continue;
            known.add(uri);
            const encoded = uri.replace(/\/$/, "").split("/").pop();
            let name = encoded || "/";
            try {
                name = decodeURIComponent(name);
            } catch (_) {}
            files.append({
                uri: uri,
                filename: name
            });
        }
    }
    background: Rectangle {
        radius: 10
        color: Qt.tint(tray.surface, Qt.alpha(tray.accent, tray.receiving ? 0.30 : tray.hovered ? 0.14 : 0.06))
        border.color: tray.receiving || tray.visualFocus ? tray.accent : Qt.alpha(tray.ink, 0.18)
    }
    contentItem: Item {
        Canvas {
            anchors.centerIn: parent
            width: Math.round(tray.edge * 0.57)
            height: width
            property color stroke: tray.receiving ? tray.accent : tray.ink
            onStrokeChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.scale(width / 24, height / 24);
                c.lineWidth = 1.7;
                c.lineJoin = "round";
                c.strokeStyle = stroke;
                c.beginPath();
                c.moveTo(2, 14);
                c.lineTo(6, 5);
                c.lineTo(18, 5);
                c.lineTo(22, 14);
                c.lineTo(22, 20);
                c.lineTo(2, 20);
                c.closePath();
                c.moveTo(2, 14);
                c.lineTo(8, 14);
                c.lineTo(10, 17);
                c.lineTo(14, 17);
                c.lineTo(16, 14);
                c.lineTo(22, 14);
                c.stroke();
            }
        }
        Rectangle {
            visible: tray.files.count > 0
            anchors.right: parent.right
            anchors.top: parent.top
            width: Math.max(height, countLabel.implicitWidth + 6)
            height: 16
            radius: 8
            color: tray.surface
            border.color: tray.accent
            Text {
                id: countLabel
                anchors.centerIn: parent
                text: tray.files.count
                font.pixelSize: 10
                color: tray.ink
            }
        }
    }
    component FileHandle: DragHandler {
        required property string uri
        target: null
        enabled: !!uri
        acceptedButtons: Qt.LeftButton
    }
    Drag.mimeData: ({
            "text/uri-list": lastUri + "\r\n"
        })
    Drag.supportedActions: Qt.CopyAction
    Drag.dragType: Drag.Automatic
    Drag.active: tileDrag.active
    FileHandle {
        id: tileDrag
        uri: tray.lastUri
    }
    component FileReceiver: DropArea {
        keys: ["text/uri-list"]
        onEntered: event => {
            if ((event.supportedActions & Qt.CopyAction) && tray.localUris(event).length)
                event.accept(Qt.CopyAction);
            else
                event.accepted = false;
        }
        onDropped: event => {
            const uris = tray.localUris(event);
            if ((event.supportedActions & Qt.CopyAction) && uris.length) {
                tray.collect(uris);
                event.accept(Qt.CopyAction);
            } else
                event.accepted = false;
        }
    }
    FileReceiver {
        id: receiver
        anchors.fill: parent
    }

    Popup {
        id: drawer
        popupType: Popup.Window
        focus: true
        padding: 11
        width: Math.min(368, tray.maxWidth)
        height: Math.min(tray.maxHeight, 106 + (tray.files.count ? Math.min(7, tray.files.count) * 53 : 72))
        x: tray.vertical ? (tray.leftEdge ? tray.width : -width) : (tray.width - width) / 2
        y: tray.vertical ? (tray.height - height) / 2 : -height
        background: Rectangle {
            color: tray.surface
            radius: 15
            border.color: drawerReceiver.containsDrag ? tray.accent : Qt.alpha(tray.ink, 0.17)
        }
        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                spacing: 8
                RowLayout {
                    spacing: 9
                    Image {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        source: Quickshell.iconPath("folder-download", true)
                        sourceSize: Qt.size(48, 48)
                        fillMode: Image.PreserveAspectFit
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label {
                            Layout.fillWidth: true
                            text: "Bandeja de arquivos"
                            color: tray.ink
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            text: tray.files.count === 1 ? "1 item" : tray.files.count + " itens"
                            color: Qt.alpha(tray.ink, 0.70)
                            font.pixelSize: 11
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 31
                    radius: 7
                    color: Qt.alpha(tray.accent, drawerReceiver.containsDrag ? 0.20 : 0.07)
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        verticalAlignment: Text.AlignVCenter
                        color: drawerReceiver.containsDrag ? tray.accent : Qt.alpha(tray.ink, 0.76)
                        text: drawerReceiver.containsDrag ? "Solte para adicionar à bandeja" : "Solte arquivos aqui ou arraste um item para fora"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ListView {
                        id: list
                        anchors.fill: parent
                        model: tray.files
                        clip: true
                        spacing: 4
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            id: row
                            required property int index
                            required property string uri
                            required property string filename
                            readonly property string location: {
                                const location = uri.replace(/^file:\/\/(localhost)?/i, "").replace(/\/$/, "").replace(/[^/]*$/, "");
                                try {
                                    return decodeURIComponent(location) || "/";
                                } catch (_) {
                                    return location;
                                }
                            }
                            width: list.width
                            height: 49
                            radius: 7
                            color: rowDrag.active ? Qt.alpha(tray.accent, 0.21) : Qt.alpha(tray.ink, itemHover.hovered ? 0.09 : 0.046)
                            border.color: rowDrag.active ? tray.accent : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 7
                                spacing: 7
                                Rectangle {
                                    id: dragSource
                                    property var dragPreview: null
                                    property bool previewReady: false
                                    radius: 7
                                    color: rowDrag.active ? Qt.tint(tray.surface, Qt.alpha(tray.accent, 0.10)) : "transparent"
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Drag.mimeData: ({
                                            "text/uri-list": row.uri + "\r\n"
                                        })
                                    Drag.supportedActions: Qt.CopyAction
                                    Drag.dragType: Drag.Automatic
                                    Drag.imageSource: dragPreview ? dragPreview.url : ""
                                    Drag.hotSpot: Qt.point(10, height / 2)
                                    Drag.active: rowDrag.active && previewReady
                                    FileHandle {
                                        id: rowDrag
                                        uri: row.uri
                                        onActiveChanged: {
                                            dragSource.previewReady = false;
                                            dragSource.dragPreview = null;
                                            if (!active)
                                                return;
                                            if (!dragSource.grabToImage(result => {
                                                if (rowDrag.active) {
                                                    dragSource.dragPreview = result;
                                                    dragSource.previewReady = true;
                                                }
                                            }))
                                                dragSource.previewReady = true;
                                        }
                                    }
                                    HoverHandler {
                                        id: itemHover
                                        cursorShape: rowDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 8
                                        Image {
                                            Layout.preferredWidth: 22
                                            Layout.preferredHeight: 22
                                            source: Quickshell.iconPath(row.uri.endsWith("/") ? "folder" : "text-x-generic", true)
                                            sourceSize: Qt.size(36, 36)
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Label {
                                                Layout.fillWidth: true
                                                text: row.filename
                                                textFormat: Text.PlainText
                                                elide: Text.ElideMiddle
                                                color: tray.ink
                                                font.weight: Font.Medium
                                                font.pixelSize: 13
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: row.location
                                                textFormat: Text.PlainText
                                                elide: Text.ElideLeft
                                                color: Qt.alpha(tray.ink, 0.69)
                                                font.pixelSize: 11
                                            }
                                        }
                                    }
                                }
                                ToolButton {
                                    id: removeButton
                                    text: "×"
                                    hoverEnabled: true
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    palette.buttonText: tray.ink
                                    Accessible.name: "Retirar " + row.filename + " da bandeja"
                                    background: Rectangle {
                                        radius: 5
                                        color: Qt.alpha(tray.ink, removeButton.hovered ? 0.12 : 0)
                                        border.color: removeButton.visualFocus ? tray.accent : "transparent"
                                    }
                                    onClicked: tray.files.remove(row.index)
                                }
                            }
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: !list.count
                        text: "A bandeja está vazia"
                        color: Qt.alpha(tray.ink, 0.70)
                    }
                }
            }
            FileReceiver {
                id: drawerReceiver
                anchors.fill: parent
            }
        }
    }
}
