import QtQuick

Canvas {
    id: grid
    required property var weeks
    required property color ink
    property int limit: 53
    onWeeksChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const visibleWeeks = weeks.slice(-limit);
        const pitch = Math.min(width / limit, height / 7);
        const side = Math.max(1, pitch - 1);
        const shades = [Qt.alpha(ink, 0.14), "#176737", "#239443", "#40bd59", "#78df81"];
        for (let x = 0; x < visibleWeeks.length; x++)
            for (let y = 0; y < 7; y++) {
                const level = visibleWeeks[x][y];
                if (level < 0) continue;
                ctx.fillStyle = shades[level];
                ctx.fillRect(x * pitch, y * pitch, side, side);
            }
    }
}
