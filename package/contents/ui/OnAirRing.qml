import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// Rotating conic halo + expanding "radio waves" around a logo.
Item {
    id: ring

    property color color: "#1e88e5"
    property bool active: false
    property bool busy: false        // connecting: faster spin, no waves
    property real cornerRatio: 0.3

    // radio waves
    Repeater {
        model: 3
        Rectangle {
            id: wave
            anchors.centerIn: parent
            width: ring.width
            height: ring.height
            radius: width * ring.cornerRatio
            color: "transparent"
            border.width: 2
            border.color: ring.color
            opacity: 0
            visible: ring.active && !ring.busy

            SequentialAnimation {
                running: wave.visible
                loops: Animation.Infinite
                PauseAnimation { duration: index * 900 }
                ParallelAnimation {
                    NumberAnimation { target: wave; property: "scale"; from: 1.0; to: 1.55; duration: 2700; easing.type: Easing.OutCubic }
                    NumberAnimation { target: wave; property: "opacity"; from: 0.55; to: 0; duration: 2700; easing.type: Easing.OutCubic }
                }
                PauseAnimation { duration: (2 - index) * 900 }
            }
        }
    }

    // conic halo
    Item {
        id: halo
        anchors.centerIn: parent
        width: ring.width + 14
        height: ring.height + 14
        visible: false

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillGradient: ConicalGradient {
                    id: sweep
                    centerX: halo.width / 2
                    centerY: halo.height / 2
                    angle: 0
                    NumberAnimation on angle {
                        from: 0; to: 360
                        duration: ring.busy ? 1400 : 7000
                        loops: Animation.Infinite
                        running: ring.active && ring.visible
                    }
                    GradientStop { position: 0.0; color: ring.color }
                    GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.9) }
                    GradientStop { position: 0.5; color: Qt.rgba(ring.color.r, ring.color.g, ring.color.b, 0.0) }
                    GradientStop { position: 0.75; color: Qt.rgba(ring.color.r, ring.color.g, ring.color.b, 0.6) }
                    GradientStop { position: 1.0; color: ring.color }
                }
                PathRectangle {
                    x: 0; y: 0
                    width: halo.width; height: halo.height
                    radius: halo.width * ring.cornerRatio * 1.05
                }
            }
        }
    }

    MultiEffect {
        id: haloFx
        anchors.fill: halo
        source: halo
        blurEnabled: true
        blur: 0.5
        blurMax: 24
        autoPaddingEnabled: true
        opacity: ring.active ? 0.95 : 0.0
        Behavior on opacity { NumberAnimation { duration: 500 } }
    }
}
