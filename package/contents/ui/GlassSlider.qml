import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.Slider {
    id: slider

    property color accent: Kirigami.Theme.highlightColor
    readonly property color fg: Kirigami.Theme.textColor

    from: 0
    to: 100
    stepSize: 1
    hoverEnabled: true
    // Plasma's style sizes a Slider from its background/handle; ours declare none, which
    // left it 0px tall there: drawn, but with no area to click or drag
    implicitWidth: Kirigami.Units.gridUnit * 6
    implicitHeight: 26
    padding: 4
    wheelEnabled: true

    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: slider.availableWidth
        height: 8
        radius: 4
        color: Qt.rgba(slider.fg.r, slider.fg.g, slider.fg.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(slider.fg.r, slider.fg.g, slider.fg.b, 0.12)

        Rectangle {
            // fill grows from the start edge (mirrors in RTL)
            x: slider.mirrored ? parent.width - width : 0
            width: (slider.mirrored ? 1 - slider.visualPosition : slider.visualPosition) * parent.width
            height: parent.height
            radius: 4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.darker(slider.accent, 1.15) }
                GradientStop { position: 1.0; color: Qt.lighter(slider.accent, 1.4) }
            }
        }
    }

    handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: 18
        height: 18
        radius: 9
        color: "white"
        border.width: 3
        border.color: slider.accent
        scale: slider.pressed ? 1.2 : (slider.hovered ? 1.1 : 1.0)
        Behavior on scale { NumberAnimation { duration: 120 } }
    }
}
