import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Glass segmented control. model: [{key, text, icon}], emits picked(key).
Item {
    id: seg

    property var model: []
    property string current: ""
    property color accent: Kirigami.Theme.highlightColor
    signal picked(string key)

    implicitHeight: Kirigami.Units.gridUnit * 1.9

    readonly property int currentIndex: {
        for (var i = 0; i < model.length; i++) if (model[i].key === current) return i
        return -1
    }
    readonly property real cell: width / Math.max(1, model.length)

    GlassPanel {
        anchors.fill: parent
        radius: height / 2
        tint: 0.06
    }

    // sliding highlight
    Rectangle {
        visible: seg.currentIndex >= 0
        y: 3
        height: parent.height - 6
        width: seg.cell - 6
        radius: height / 2
        x: (seg.LayoutMirroring.enabled ? seg.width - seg.cell * (seg.currentIndex + 1) : seg.cell * seg.currentIndex) + 3
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(seg.accent, 1.3) }
            GradientStop { position: 1.0; color: seg.accent }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.35)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Repeater {
            model: seg.model
            delegate: Item {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property bool sel: index === seg.currentIndex
                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Kirigami.Icon {
                        source: modelData.icon
                        width: Kirigami.Units.iconSizes.small; height: width
                        anchors.verticalCenter: parent.verticalCenter
                        color: parent.parent.sel ? "white" : Kirigami.Theme.textColor
                        isMask: parent.parent.sel
                    }
                    QQC2.Label {
                        text: modelData.text
                        // drop the label (keep the icon) when the segment is too narrow
                        visible: implicitWidth + Kirigami.Units.iconSizes.small + 18 <= seg.cell
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        font.weight: parent.parent.sel ? Font.DemiBold : Font.Normal
                        color: parent.parent.sel ? "white" : Kirigami.Theme.textColor
                    }
                }
                MouseArea {
                    id: segMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(modelData.key)
                    QQC2.ToolTip.text: modelData.text
                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.delay: 500
                }
            }
        }
    }
}
