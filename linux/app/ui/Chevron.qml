import QtQuick

// The Mac month mark is a wide flat chevron. A rotated "›" stays the size of the glyph.
Canvas {
    id: canvas
    property color ink: "#a88a33"
    width: 40
    height: 8
    onPaint: {
        const ctx = getContext("2d")
        if (ctx.reset)
            ctx.reset()
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = canvas.ink
        ctx.lineWidth = 1.35
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(1.2, 1.5)
        ctx.lineTo(width / 2, height - 1.3)
        ctx.lineTo(width - 1.2, 1.5)
        ctx.stroke()
    }
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
