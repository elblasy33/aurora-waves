import QtQuick

// Decorative spectrum bars. "level": 0 = flat, 0.35 = idle shimmer, 1 = live.
Row {
    id: eq

    property int bars: 18
    property color color: "white"
    property real level: 1.0
    property bool running: true

    spacing: Math.max(2, width / bars * 0.35)
    height: 28

    Repeater {
        model: eq.bars
        Rectangle {
            id: bar
            property real target: 0.15
            width: (eq.width - eq.spacing * (eq.bars - 1)) / eq.bars
            height: Math.max(3, eq.height * target * eq.level)
            anchors.bottom: parent ? parent.bottom : undefined
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(eq.color, 1.5) }
                GradientStop { position: 1.0; color: Qt.rgba(eq.color.r, eq.color.g, eq.color.b, 0.55) }
            }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

            Timer {
                interval: 140 + (index * 37) % 120
                running: eq.running && eq.visible
                repeat: true
                onTriggered: {
                    // bell-ish envelope so the middle bars are livelier
                    var center = 1 - Math.abs(index - eq.bars / 2) / (eq.bars / 2)
                    bar.target = 0.15 + Math.random() * (0.45 + 0.4 * center)
                }
            }
        }
    }
}
