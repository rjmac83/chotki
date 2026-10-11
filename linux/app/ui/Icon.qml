import QtQuick

Canvas {
    id: icon
    width: 18
    height: 18
    property string kind: ""
    property color tint: "#a39e8f"
    // Logical coordinates stay the same. The bitmap follows the screen so a
    // 2× display does not scale a 1× drawing.
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    canvasSize: Qt.size(width * dpr, height * dpr)
    onKindChanged: requestPaint()
    onTintChanged: requestPaint()
    onDprChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const p = getContext("2d")
        if (p.reset) p.reset()
        p.setTransform(dpr, 0, 0, dpr, 0, 0)
        p.strokeStyle = tint
        p.fillStyle = tint
        p.lineWidth = 1.15
        p.lineCap = "round"
        p.lineJoin = "round"

        function line(points) {
            p.beginPath()
            p.moveTo(points[0], points[1])
            for (let i = 2; i < points.length; i += 2) p.lineTo(points[i], points[i + 1])
            p.stroke()
        }
        function box(x, y, w, h) { p.strokeRect(x, y, w, h) }
        function circle(x, y, r) {
            p.beginPath(); p.arc(x, y, r, 0, Math.PI * 2); p.stroke()
        }

        switch (kind) {
        case "Home":
            box(2.2, 3.3, 13.6, 12)
            line([2.2, 6.7, 15.8, 6.7])
            line([5.5, 2.2, 5.5, 4.8]); line([12.5, 2.2, 12.5, 4.8])
            for (let x of [5.5, 9, 12.5]) for (let y of [9.2, 12.4]) {
                p.beginPath(); p.arc(x, y, 0.6, 0, Math.PI * 2); p.fill()
            }
            break
        case "Prayers":
        case "Prayer":
            for (let i = 0; i < 6; ++i) {
                const a = i * Math.PI / 3
                circle(9 + Math.cos(a) * 5.1, 9 + Math.sin(a) * 5.1, 1.85)
            }
            circle(9, 9, 1.15)
            break
        case "Fasting":
            p.beginPath()
            p.arc(9, 8.2, 5.4, 0.15 * Math.PI, 0.85 * Math.PI)
            p.stroke()
            line([4.2, 8.6, 13.8, 8.6])
            break
        case "Services":
            line([4.2, 15, 4.2, 8.4, 9, 4.4, 13.8, 8.4, 13.8, 15])
            line([9, 2.2, 9, 5.4])
            line([7.5, 3.5, 10.5, 3.5])
            break
        case "Life":
            circle(9, 4.4, 1.7)
            line([9, 6.3, 9, 11])
            line([5.4, 8.2, 12.6, 8.2])
            line([9, 11, 6.3, 15.2])
            line([9, 11, 11.7, 15.2])
            break
        case "Reading":
            line([9, 4.3, 9, 15.1])
            line([9, 5.3, 6.5, 3.7, 2.3, 3.5, 2.3, 13.5, 6.4, 13.7, 9, 15.1])
            line([9, 5.3, 11.5, 3.7, 15.7, 3.5, 15.7, 13.5, 11.6, 13.7, 9, 15.1])
            break
        case "Progress":
            line([2.5, 3, 2.5, 15, 16, 15])
            line([4, 11.8, 7.3, 8.8, 9.8, 10, 14.3, 4.8])
            break
        case "Library":
            for (let x of [2.5, 9.8]) for (let y of [2.5, 9.8]) box(x, y, 5.7, 5.7)
            break
        case "Glossary":
            box(3.5, 2.7, 11, 12.6)
            line([6, 6, 12, 6]); line([6, 8.7, 12, 8.7]); line([6, 11.4, 10.5, 11.4])
            break
        case "Settings":
            circle(9, 9, 3.5); circle(9, 9, 1.15)
            for (let i = 0; i < 8; ++i) {
                const a = i * Math.PI / 4
                line([9 + Math.cos(a) * 4.4, 9 + Math.sin(a) * 4.4,
                      9 + Math.cos(a) * 6.5, 9 + Math.sin(a) * 6.5])
            }
            break
        }
    }
}
