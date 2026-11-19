import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "المظهر / Appearance"
        icon: "preferences-desktop-color"
        source: "ConfigAppearance.qml"
    }
    ConfigCategory {
        name: "عام / General"
        icon: "preferences-system"
        source: "ConfigBehavior.qml"
    }
}
