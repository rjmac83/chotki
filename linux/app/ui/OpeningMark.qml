import QtQuick

Item {
    id: curtain
    objectName: "opening-mark"
    signal finished()
    property bool ending: false
    property real elapsed: 0
    property real grown: 0
    property real frameOpacity: 1

    function leadMilliseconds() { return bridge.openingStaggerLead * 1000 }
    function fadeMilliseconds() { return bridge.openingKnotFade * 1000 }
    function total() { return bridge.openingBuild + bridge.openingHold + bridge.openingFade }

    function knotAlpha(ms, index) {
        const slots = bridge.openingKnotSlots
        if (slots < 2) return 0
        const buildMs = bridge.openingBuild * 1000
        const start = (index - 1) / (slots - 1) * (buildMs - leadMilliseconds())
        return Math.min(1, Math.max(0, (ms - start) / fadeMilliseconds()))
    }

    function crossAlpha(ms) {
        const buildMs = bridge.openingBuild * 1000
        return Math.min(1, Math.max(0, (ms - (buildMs - fadeMilliseconds())) / fadeMilliseconds()))
    }

    function finish() {
        if (ending) return
        ending = true
        clock.stop()
        finished()
    }

    function step() {
        const seconds = (Date.now() - startedAt) / 1000
        elapsed = seconds
        const ms = Math.max(0, seconds) * 1000
        const buildMs = bridge.openingBuild * 1000
        const holdEnd = (bridge.openingBuild + bridge.openingHold) * 1000
        grown = buildMs > 0 ? Math.min(1, Math.max(0, ms / buildMs)) : 1
        frameOpacity = ms < holdEnd ? 1 : Math.max(0, 1 - (ms - holdEnd) / (bridge.openingFade * 1000))
        glyph.requestPaint()
        if (seconds >= total()) finish()
    }

    property real startedAt: 0
    Component.onCompleted: {
        startedAt = Date.now()
        step()
    }

    Rectangle {
        anchors.fill: parent
        color: "#15161c"
    }

    Canvas {
        id: glyph
        width: 220
        height: 220
        anchors.centerIn: parent
        antialiasing: true
        scale: 0.85 + 0.15 * curtain.grown
        opacity: curtain.frameOpacity
        onPaint: {
            const context = getContext("2d")
            context.reset()
            const side = Math.min(width, height)
            const ms = curtain.elapsed * 1000
            const knots = bridge.openingKnots
            const radius = bridge.openingKnotRadius * side
            // Qt's ellipse() is the bounding box, not the HTML canvas call.
            // Passing the centre and the radius drew each knot at half size,
            // shifted down and right, so the cross looked large and too close.
            // arc() is the same circle OpeningMarkDrawing fills.
            for (let index = 0; index < knots.length; index++) {
                const alpha = curtain.knotAlpha(ms, index + 1) * curtain.frameOpacity
                if (alpha <= 0) continue
                const centre = knots[index]
                context.beginPath()
                context.fillStyle = "rgba(201, 162, 39, " + alpha + ")"
                context.arc(centre.x * side, centre.y * side, radius, 0, Math.PI * 2)
                context.fill()
            }
            const cross = curtain.crossAlpha(ms) * curtain.frameOpacity
            if (cross <= 0) return
            const box = bridge.openingBox
            const originX = box.x * side
            const originY = box.y * side
            const boxWidth = box.width * side
            const boxHeight = box.height * side
            context.fillStyle = "rgba(201, 162, 39, " + cross + ")"
            const bars = bridge.openingBars
            for (let index = 0; index < bars.length; index++) {
                const bar = bars[index]
                context.fillRect(originX + bar.x * boxWidth, originY + bar.y * boxHeight,
                                 bar.width * boxWidth, bar.height * boxHeight)
            }
            const foot = bridge.openingFootrest
            if (!foot) return
            function across(unit) { return originX + unit * boxWidth }
            function down(unit) { return originY + unit * boxHeight }
            context.beginPath()
            context.moveTo(across(foot.leadingX), down(foot.leadingY))
            context.lineTo(across(foot.trailingX), down(foot.trailingY))
            context.lineTo(across(foot.trailingX), down(foot.trailingY + foot.thickness))
            context.lineTo(across(foot.leadingX), down(foot.leadingY + foot.thickness))
            context.closePath()
            context.fill()
        }
    }

    MouseArea { anchors.fill: parent }

    Timer {
        id: clock
        interval: 33
        repeat: true
        running: true
        onTriggered: curtain.step()
    }
}
