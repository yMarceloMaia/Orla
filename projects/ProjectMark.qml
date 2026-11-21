import QtQuick

Rectangle {
    id: mark
    required property bool monitor
    required property color tone
    implicitWidth: 32
    implicitHeight: 32
    radius: width * 0.27
    color: Qt.alpha(tone, 0.12)
    Canvas {
        id: drawing
        anchors.fill: parent
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.scale(width / 32, height / 32);
            c.strokeStyle = mark.tone;
            c.lineWidth = 2.4;
            c.lineCap = "round";
            c.lineJoin = "round";
            c.beginPath();
            if (mark.monitor) {
                c.moveTo(5, 18);
                c.lineTo(10, 18);
                c.lineTo(13, 9);
                c.lineTo(17, 24);
                c.lineTo(21, 14);
                c.lineTo(23, 16);
                c.lineTo(27, 16);
            } else {
                c.moveTo(8, 10);
                c.lineTo(14, 16);
                c.lineTo(8, 22);
                c.moveTo(18, 22);
                c.lineTo(24, 22);
            }
            c.stroke();
        }
    }
    onToneChanged: drawing.requestPaint()
}
