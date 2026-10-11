import QtQuick

// A vertical page dissolves at its top and bottom instead of ending on a cut.
// The length matches the Mac mask: min(20, 15% of the viewport). This item
// does not take presses, so a control under the fade still receives the click.
Item {
    id: fade
    objectName: "edge-fade"
    property color ground: "#15161c"
    readonly property real edge: Math.min(20, Math.max(1, height) * 0.15)

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: fade.edge
        gradient: Gradient {
            GradientStop { position: 0; color: fade.ground }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: fade.edge
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: fade.ground }
        }
    }
}
