import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ToolButton {
    id: tray
    required property var files
    required property int edge
    required property bool vertical
    required property bool leftEdge
    required property color surface
    required property color ink
    required property color accent
    readonly property bool opened: drawer.visible
    readonly property bool receiving: receiver.containsDrag
    property string lastUri: files.count ? files.get(files.count - 1).uri : ""
    width: edge
    height: edge
    padding: 4
    Accessible.name: "Bandeja de arquivos (" + files.count + ")"
    onClicked: drawer.open()
    function localUris(event) {
        return Array.from(event.urls || [], u => u.toString())
                    .filter(u => /^file:\/\/\/(?!\/)/i.test(u) || /^file:\/\/localhost\//i.test(u));
    }
    function collect(uris) {
        const known = new Set();
        for (let i = 0; i < files.count; ++i) known.add(files.get(i).uri);
        for (const uri of uris) {
            if (known.has(uri)) continue;
            known.add(uri);
            const encoded = uri.replace(/\/$/, "").split("/").pop();
            let name = encoded || "/";
            try { name = decodeURIComponent(name); } catch (_) {}
            files.append({uri: uri, filename: name});
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
                c.moveTo(2, 14); c.lineTo(6, 5); c.lineTo(18, 5); c.lineTo(22, 14);
                c.lineTo(22, 20); c.lineTo(2, 20); c.closePath();
                c.moveTo(2, 14); c.lineTo(8, 14); c.lineTo(10, 17); c.lineTo(14, 17); c.lineTo(16, 14); c.lineTo(22, 14);
                c.stroke();
            }
        }
        Rectangle {
            visible: tray.files.count > 0
            anchors.right: parent.right
            anchors.top: parent.top
            width: Math.max(height, countLabel.implicitWidth + 6)
            height: 16; radius: 8
            color: tray.surface
            border.color: tray.accent
            Text { id: countLabel; anchors.centerIn: parent; text: tray.files.count; font.pixelSize: 10; color: tray.ink }
        }
    }
    component FileHandle: DragHandler {
        required property string uri
        target: null
        enabled: !!uri
        acceptedButtons: Qt.LeftButton

    }
    Drag.mimeData: ({"text/uri-list": lastUri + "\r\n"})
    Drag.supportedActions: Qt.CopyAction
    Drag.dragType: Drag.Automatic
    Drag.active: tileDrag.active
    FileHandle { id: tileDrag; uri: tray.lastUri }
    DropArea {
        id: receiver
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: event => {
            if ((event.supportedActions & Qt.CopyAction) && tray.localUris(event).length)
                event.accept(Qt.CopyAction);
            else event.accepted = false;
        }
        onDropped: event => {
            const uris = tray.localUris(event);
            if ((event.supportedActions & Qt.CopyAction) && uris.length) {
                tray.collect(uris);
                event.accept(Qt.CopyAction);
            } else event.accepted = false;
        }
    }
    Popup {
        id: drawer
        popupType: Popup.Window
        focus: true
        padding: 12
        width: 320
        height: 66 + Math.min(7, Math.max(1, tray.files.count)) * 42
        x: tray.vertical ? (tray.leftEdge ? tray.width : -width) : (tray.width - width) / 2
        y: tray.vertical ? (tray.height - height) / 2 : -height
        background: Rectangle { color: tray.surface; radius: 12; border.color: Qt.alpha(tray.ink, 0.22) }
        contentItem: ColumnLayout {
            Label { text: "Bandeja de arquivos"; color: tray.ink; font.pixelSize: 17; font.bold: true }
            ListView {
                id: list
                Layout.fillWidth: true; Layout.fillHeight: true
                model: tray.files
                clip: true
                ScrollBar.vertical: ScrollBar {}
                delegate: RowLayout {
                    id: row
                    required property int index
                    required property string uri
                    required property string filename
                    width: list.width
                    height: 42
                    Label {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        text: row.filename
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: tray.ink
                        Drag.mimeData: ({"text/uri-list": row.uri + "\r\n"})
                        Drag.supportedActions: Qt.CopyAction
                        HoverHandler { cursorShape: Qt.OpenHandCursor }
                        Drag.dragType: Drag.Automatic
                        Drag.active: rowDrag.active
                        FileHandle { id: rowDrag; uri: row.uri }
                    }
                    ToolButton {
                        text: "×"
                        palette.buttonText: tray.ink
                        Accessible.name: "Retirar " + row.filename + " da bandeja"
                        onClicked: tray.files.remove(row.index)
                    }
                }
                Label { anchors.centerIn: parent; visible: !list.count; text: "Arraste arquivos para o ícone da bandeja."; color: tray.ink }
            }
        }
    }
}
