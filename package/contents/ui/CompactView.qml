import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "../code/presets.js" as Presets

// Panel icon: widget icon when idle, glowing station logo while on air.
// Left click: open  ·  Middle click: play/stop  ·  Wheel: volume
MouseArea {
    id: compact

    property var app

    readonly property bool onAir: app.wantPlaying && app.current !== null && Plasmoid.configuration.compactStyle === 0
    readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    readonly property bool showName: Plasmoid.configuration.compactShowName && horizontal && app.current !== null
    readonly property real iconSize: horizontal ? height : width

    Layout.minimumWidth: showName ? iconSize + nameLabel.implicitWidth + Kirigami.Units.smallSpacing * 3 : -1
    Layout.preferredWidth: Layout.minimumWidth

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true

    onClicked: function (mouse) {
        if (mouse.button === Qt.MiddleButton) app.toggle()
        else app.expanded = !app.expanded
    }
    onWheel: function (wheel) {
        var step = Plasmoid.configuration.wheelStep
        app.setVolume(app.volume + (wheel.angleDelta.y > 0 ? step : -step))
    }

    Item {
        id: iconBox
        width: compact.iconSize
        height: compact.iconSize
        anchors.verticalCenter: parent.verticalCenter
        x: compact.showName ? (compact.LayoutMirroring.enabled ? parent.width - width : 0) : (parent.width - width) / 2

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: compact.containsMouse
            opacity: compact.onAir ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }

        Item {
            id: live
            anchors.centerIn: parent
            width: parent.width * 0.86
            height: width
            opacity: compact.onAir ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 250 } }

            // breathing halo
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 1.12; height: width
                radius: width * logoItem.radiusRatio
                color: "transparent"
                border.width: 2
                border.color: app.accent
                opacity: app.isPaused ? 0.3 : 0.6
                SequentialAnimation on opacity {
                    running: live.visible && !app.isPaused && Plasmoid.configuration.animations
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.25; to: 0.9; duration: app.isBusy ? 400 : 1300; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.9; to: 0.25; duration: app.isBusy ? 400 : 1300; easing.type: Easing.InOutSine }
                }
            }

            StationLogo {
                id: logoItem
                anchors.fill: parent
                logo: app.previewing ? app.previewLogo : (app.current ? (app.current.logo || "") : "")
                tint: app.previewing ? app.previewColor : (app.current ? app.current.color : "gray")
                glyph: app.previewing ? Presets.glyphFor(app.previewName) : (app.current ? (app.current.glyph || "") : "")
            }

            Rectangle {
                width: Math.max(5, parent.width * 0.26); height: width; radius: width / 2
                anchors { right: parent.right; bottom: parent.bottom; margins: -width * 0.2 }
                color: app.isPlaying ? "#ff3b30" : (app.isPaused ? "#9e9e9e" : "#ffb300")
                border.width: 1
                border.color: "white"
            }
        }
    }

    QQC2.Label {
        id: nameLabel
        visible: compact.showName
        anchors.verticalCenter: parent.verticalCenter
        x: compact.LayoutMirroring.enabled ? iconBox.x - width - Kirigami.Units.smallSpacing
                                           : iconBox.x + iconBox.width + Kirigami.Units.smallSpacing
        text: app.previewing ? app.previewName : (app.current ? app.current.name : "")
        font.weight: app.wantPlaying ? Font.DemiBold : Font.Normal
        opacity: app.wantPlaying ? 1 : 0.7
    }
}
