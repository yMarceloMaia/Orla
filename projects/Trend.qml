import QtQuick

Canvas {
    id: graph

    required property var points
    required property int column
    required property color ink

    onPointsChanged: requestPaint()
    onInkChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const values = points.map(p => {
            return p[column];
        });
        if (values.length < 2)
            return;

        const max = Math.max(1, values);
        ctx.strokeStyle = ink;
        ctx.lineWidth = 2;
        ctx.beginPath();
        values.forEach((v, i) => {
            const x = i * width / (values.length - 1);
            const y = height - 2 - (height - 4) * v / max;
            if (i === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        });
        ctx.stroke();
    }
}
