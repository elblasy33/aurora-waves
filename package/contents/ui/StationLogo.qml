import QtQuick
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// A glass logo. "logo" may be:
//   ""              -> gradient orb with the glyph (letter / emoji)
//   "pkg:<file>"    -> bundled image in contents/images/logos
//   "icon:<name>"   -> system icon theme icon on the gradient orb
//   "file:///..."   -> any image
Item {
    id: sl

    property string logo: ""
    property color tint: "#1e88e5"
    property string glyph: ""
    property real radiusRatio: [0.3, 0.5, 0.18][Plasmoid.configuration.logoShape] ?? 0.3

    implicitWidth: 64
    implicitHeight: 64

    readonly property string iconName: logo.indexOf("icon:") === 0 ? logo.slice(5) : ""
    readonly property string imageUrl: {
        if (logo === "" || iconName !== "") return ""
        if (logo.indexOf("pkg:") === 0) return Qt.resolvedUrl("../images/logos/" + logo.slice(4))
        return logo
    }
    readonly property real r: Math.min(width, height) * radiusRatio
    readonly property bool hasImage: imageUrl !== "" && img.status === Image.Ready

    // ---- generated orb ----
    Rectangle {
        anchors.fill: parent
        radius: sl.r
        visible: !sl.hasImage
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.lighter(sl.tint, 1.45) }
            GradientStop { position: 0.55; color: sl.tint }
            GradientStop { position: 1.0; color: Qt.darker(sl.tint, 1.7) }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: parent.width * 0.56
            height: width
            source: sl.iconName
            visible: sl.iconName !== ""
            isMask: true
            color: "white"
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height * 0.02
            visible: sl.iconName === ""
            text: sl.glyph
            color: "white"
            font.pixelSize: parent.height * (sl.glyph.length > 1 ? 0.36 : 0.5)
            font.bold: true
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.25)
        }
    }

    // ---- image (masked to the shape) ----
    Image {
        id: img
        anchors.fill: parent
        source: sl.imageUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
        visible: false
        sourceSize: Qt.size(Math.max(64, width * 2), Math.max(64, height * 2))
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: sl.r; color: "black" }
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        visible: sl.hasImage
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    // ---- glass sheen + rim ----
    Rectangle {
        anchors.fill: parent
        radius: sl.r
        color: "transparent"
        border.width: Math.max(1, sl.width / 64)
        border.color: Qt.rgba(1, 1, 1, 0.35)
    }

    Rectangle {
        x: parent.width * 0.08
        y: parent.height * 0.05
        width: parent.width * 0.84
        height: parent.height * 0.45
        radius: sl.r * 0.85
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.38) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }
}
