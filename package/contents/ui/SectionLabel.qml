import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

RowLayout {
    property alias text: label.text
    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing
    QQC2.Label { id: label; font.weight: Font.DemiBold; opacity: 0.75 }
    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Kirigami.Theme.textColor
        opacity: 0.12
    }
}
