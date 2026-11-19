import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Round (or pill) glass button with an icon and optional text.
QQC2.AbstractButton {
    id: btn

    property string iconName: ""
    property color accent: Kirigami.Theme.highlightColor
    property bool filled: false        // accent-filled "primary" button
    property real iconScale: 0.5

    implicitWidth: text === "" ? implicitHeight : contentRow.implicitWidth + implicitHeight * 0.8
    implicitHeight: Kirigami.Units.gridUnit * 2
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    QQC2.ToolTip.visible: hovered && toolTip !== ""
    QQC2.ToolTip.text: toolTip
    QQC2.ToolTip.delay: 600
    property string toolTip: ""

    scale: pressed ? 0.92 : (hovered ? 1.04 : 1.0)
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    background: Item {
        // soft glow behind primary button
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 1.25; height: parent.height * 1.25
            radius: height / 2
            color: btn.accent
            opacity: btn.filled ? (btn.hovered ? 0.35 : 0.22) : 0
            visible: btn.filled
        }
        GlassPanel {
            anchors.fill: parent
            radius: height / 2
            hovered: btn.hovered
            tint: 0.08
            visible: !btn.filled
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            visible: btn.filled
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.4)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(btn.accent, 1.35) }
                GradientStop { position: 1.0; color: Qt.darker(btn.accent, 1.25) }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 2 }
                height: parent.height * 0.45
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.45) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }
    }

    contentItem: Item {
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: btn.height * btn.iconScale
                height: width
                source: btn.iconName
                visible: btn.iconName !== ""
                color: btn.filled ? "white" : Kirigami.Theme.textColor
                isMask: btn.filled
            }
            QQC2.Label {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.text
                visible: text !== ""
                color: btn.filled ? "white" : Kirigami.Theme.textColor
            }
        }
    }
}
