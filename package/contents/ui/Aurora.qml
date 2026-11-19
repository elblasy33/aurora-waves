import QtQuick
import QtQuick.Effects

// Slow drifting color blobs tinted by the current station, heavily blurred.
// Sits behind the glass panels so they have something to "frost".
Item {
    id: aurora

    property color color: "#1e88e5"
    property string image: ""
    property bool running: true
    property real strength: 0.55

    clip: true

    readonly property color c2: Qt.hsla((color.hslHue + 0.12) % 1, Math.min(1, color.hslSaturation + 0.1), 0.55, 1)
    readonly property color c3: Qt.hsla((color.hslHue + 0.85) % 1, color.hslSaturation, 0.45, 1)

    Item {
        id: blobs
        anchors.fill: parent
        visible: false

        Image {
            anchors.centerIn: parent
            width: parent.width * 0.9
            height: width
            source: aurora.image
            fillMode: Image.PreserveAspectCrop
            opacity: 0.6
            visible: aurora.image !== ""
            sourceSize: Qt.size(128, 128)
        }

        Rectangle {
            id: b1
            width: aurora.width * 0.85; height: width; radius: width / 2
            color: aurora.color
            x: -width * 0.2; y: -height * 0.25
            Behavior on color { ColorAnimation { duration: 900 } }
        }
        Rectangle {
            id: b2
            width: aurora.width * 0.7; height: width; radius: width / 2
            color: aurora.c2
            x: aurora.width - width * 0.7; y: aurora.height * 0.35
            Behavior on color { ColorAnimation { duration: 900 } }
        }
        Rectangle {
            id: b3
            width: aurora.width * 0.6; height: width; radius: width / 2
            color: aurora.c3
            x: aurora.width * 0.05; y: aurora.height - height * 0.55
            Behavior on color { ColorAnimation { duration: 900 } }
        }

        SequentialAnimation {
            running: aurora.running
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: b1; property: "x"; to: aurora.width * 0.25; duration: 9000; easing.type: Easing.InOutSine }
                NumberAnimation { target: b2; property: "y"; to: aurora.height * 0.05; duration: 9000; easing.type: Easing.InOutSine }
                NumberAnimation { target: b3; property: "x"; to: aurora.width * 0.45; duration: 9000; easing.type: Easing.InOutSine }
            }
            ParallelAnimation {
                NumberAnimation { target: b1; property: "x"; to: -b1.width * 0.2; duration: 11000; easing.type: Easing.InOutSine }
                NumberAnimation { target: b2; property: "y"; to: aurora.height * 0.35; duration: 11000; easing.type: Easing.InOutSine }
                NumberAnimation { target: b3; property: "x"; to: aurora.width * 0.05; duration: 11000; easing.type: Easing.InOutSine }
            }
        }
    }

    MultiEffect {
        anchors.fill: blobs
        source: blobs
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 0.2
        opacity: aurora.strength
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }
}
