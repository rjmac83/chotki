import QtQuick

// The scroll viewport dissolves into the backdrop, the way the Mac mask does.
// layer.effect is a component. A live ShaderEffect cannot be assigned to it,
// and rebuilding the layer on every size change faults mapToScene.
// The software renderer drops that layer, and an offscreen grab then loses the
// page, so there the dissolve is painted over the viewport instead.
Item {
    id: fade
    objectName: "edge-fade"
    readonly property color ground: "#15161c"
    readonly property real fraction: Math.min(0.15, 20 / Math.max(1, height))
    readonly property real band: Math.max(12, height * fraction)
    readonly property bool useMask: gpu(GraphicsInfo.api)
    property bool masked: false

    function gpu(api) {
        return api === GraphicsInfo.OpenGL
            || api === GraphicsInfo.Vulkan
            || api === GraphicsInfo.Metal
            || api === GraphicsInfo.Direct3D11
    }

    function apply() {
        var host = parent
        if (!host)
            return
        if (!useMask) {
            if (host.layer.effect === mask) {
                host.layer.enabled = false
                host.layer.effect = null
            }
            masked = false
            return
        }
        if (host.layer.effect === mask) {
            masked = true
            return
        }
        host.layer.smooth = true
        host.layer.effect = mask
        host.layer.enabled = true
        masked = true
    }

    onUseMaskChanged: apply()

    Component {
        id: mask
        ShaderEffect {
            property real edge: fade.fraction
            fragmentShader: Qt.resolvedUrl("shaders/edge.frag.qsb")
        }
    }

    Rectangle {
        visible: !fade.masked
        width: parent.width
        height: fade.band
        gradient: Gradient {
            GradientStop { position: 0.0; color: fade.ground }
            GradientStop { position: 1.0; color: Qt.rgba(fade.ground.r, fade.ground.g, fade.ground.b, 0) }
        }
    }
    Rectangle {
        visible: !fade.masked
        y: parent.height - height
        width: parent.width
        height: fade.band
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(fade.ground.r, fade.ground.g, fade.ground.b, 0) }
            GradientStop { position: 1.0; color: fade.ground }
        }
    }

    Component.onCompleted: apply()
    onParentChanged: apply()
    Component.onDestruction: {
        var host = parent
        if (host && host.layer.effect === mask) {
            host.layer.enabled = false
            host.layer.effect = null
        }
    }
}
