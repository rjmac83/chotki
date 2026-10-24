import QtQuick

// The scroll viewport dissolves into the backdrop, the way the Mac mask does.
// layer.effect is a component. A live ShaderEffect cannot be assigned to it,
// and rebuilding the layer on every size change faults mapToScene.
Item {
    id: fade
    objectName: "edge-fade"
    readonly property real fraction: Math.min(0.15, 20 / Math.max(1, height))

    Component {
        id: mask
        ShaderEffect {
            property real edge: fade.fraction
            fragmentShader: Qt.resolvedUrl("shaders/edge.frag.qsb")
        }
    }

    function apply() {
        var host = parent
        if (!host || host.layer.effect === mask)
            return
        host.layer.smooth = true
        host.layer.effect = mask
        host.layer.enabled = true
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
