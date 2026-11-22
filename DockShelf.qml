import QtQuick

Canvas {
    id: shelf

    required property bool vertical
    required property bool leftEdge
    required property color rearColor
    required property color frontColor
    required property color edgeColor
    required property color faceColor
    required property bool neon
    required property real depth
    renderStrategy: Canvas.Cooperative

    onRearColorChanged: requestPaint()
    onFrontColorChanged: requestPaint()
    onEdgeColorChanged: requestPaint()
    onFaceColorChanged: requestPaint()
    onNeonChanged: requestPaint()
    onDepthChanged: requestPaint()
    onVerticalChanged: requestPaint()
    onLeftEdgeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible)
        requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        const length = vertical ? height : width;
        const thickness = vertical ? width : height;
        if (length < 48 || thickness < depth + 5)
            return;
        if (vertical) {
            if (leftEdge)
                ctx.transform(0, 1, -1, 0, width, 0);
            else
                ctx.transform(0, -1, 1, 0, 0, height);
        }

        const inset = Math.min(25, length * 0.09);
        const rear = thickness - depth - 4;
        const front = thickness - 6;
        function plane(offset) {
            ctx.beginPath();
            ctx.moveTo(inset + 3, rear + offset);
            ctx.lineTo(length - inset - 3, rear + offset);
            ctx.lineTo(length - 4, front + offset);
            ctx.lineTo(4, front + offset);
            ctx.closePath();
        }

        plane(5);
        ctx.fillStyle = "#28000000";
        ctx.fill();
        plane(3);
        ctx.fillStyle = faceColor;
        ctx.fill();

        const finishGradient = ctx.createLinearGradient(0, rear, 0, front);
        finishGradient.addColorStop(0, rearColor);
        finishGradient.addColorStop(1, frontColor);
        plane(0);
        ctx.fillStyle = finishGradient;
        ctx.fill();
        if (neon) {
            ctx.lineJoin = "round";
            for (const [width, opacity] of [[12, 0.065], [8, 0.12], [4, 0.24]]) {
                ctx.lineWidth = width;
                ctx.strokeStyle = Qt.alpha(edgeColor, opacity);
                ctx.stroke();
            }
        }
        ctx.lineWidth = 1;
        ctx.strokeStyle = neon ? Qt.tint(edgeColor, Qt.alpha("white", 0.34)) : edgeColor;
        ctx.stroke();

        ctx.beginPath();
        ctx.moveTo(7, front - 1);
        ctx.lineTo(length - 7, front - 1);
        ctx.strokeStyle = Qt.alpha(edgeColor, 0.6);
        ctx.stroke();
    }
}
