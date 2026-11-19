import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// Frosted glass surface: translucent fill, hairline rim, top light reflection.
Item {
    id: glass

    property real radius: 18
    property real tint: Plasmoid.configuration.glassOpacity
    property color accent: "transparent"
    property bool highlighted: false
    property bool hovered: false
    default property alias content: inner.data

    readonly property color fg: Kirigami.Theme.textColor

    Rectangle {
        id: body
        anchors.fill: parent
        radius: glass.radius
        color: glass.highlighted
               ? Qt.rgba(glass.accent.r, glass.accent.g, glass.accent.b, 0.22)
               : Qt.rgba(glass.fg.r, glass.fg.g, glass.fg.b, glass.tint + (glass.hovered ? 0.05 : 0))
        border.width: glass.highlighted ? 1.5 : 1
        border.color: glass.highlighted
                      ? Qt.rgba(glass.accent.r, glass.accent.g, glass.accent.b, 0.85)
                      : Qt.rgba(glass.fg.r, glass.fg.g, glass.fg.b, glass.hovered ? 0.28 : 0.14)
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }

    // light reflection on the upper half
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
        height: parent.height * 0.5
        radius: glass.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}
