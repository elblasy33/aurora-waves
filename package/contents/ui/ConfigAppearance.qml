import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.iconthemes as KIconThemes
import org.kde.plasma.plasmoid
import "../code/i18n.js" as I18n

KCM.SimpleKCM {
    id: page

    property alias cfg_glassOpacity: glassSlider.value
    property alias cfg_auroraEnabled: auroraCheck.checked
    property alias cfg_auroraStrength: auroraSlider.value
    property alias cfg_animations: animCheck.checked
    property alias cfg_logoShape: shapeCombo.currentIndex
    property alias cfg_useStationAccent: accentCheck.checked
    property alias cfg_viewMode: viewCombo.currentIndex
    property int cfg_gridColumns
    property alias cfg_showEqualizer: eqCheck.checked
    property alias cfg_showStreamInfo: infoCheck.checked
    property alias cfg_showGroups: groupsCheck.checked
    property alias cfg_compactStyle: compactCombo.currentIndex
    property alias cfg_compactShowName: nameCheck.checked
    property string cfg_customIcon

    readonly property string lang: I18n.resolve(Plasmoid.configuration.language, Qt.locale().name)
    function t(s) { return I18n.tr(lang, s) }

    LayoutMirroring.enabled: lang === "ar"
    LayoutMirroring.childrenInherit: true

    Kirigami.FormLayout {
        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: page.t("الزجاج والخلفية") }

        RowLayout {
            Kirigami.FormData.label: page.t("شفافية الزجاج:")
            QQC2.Slider { id: glassSlider; from: 0.0; to: 0.3; stepSize: 0.01; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(glassSlider.value / 0.3 * 100) + "%" }
        }
        QQC2.CheckBox { id: auroraCheck; Kirigami.FormData.label: page.t("الخلفية المتحركة:"); text: page.t("ألوان المحطة المتحركة خلف الزجاج") }
        RowLayout {
            Kirigami.FormData.label: page.t("شدة الخلفية:")
            enabled: auroraCheck.checked
            QQC2.Slider { id: auroraSlider; from: 0.1; to: 1.0; stepSize: 0.05; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(auroraSlider.value * 100) + "%" }
        }
        QQC2.CheckBox { id: accentCheck; Kirigami.FormData.label: page.t("الألوان:"); text: page.t("لون الواجهة يتبع لون المحطة (وإلا لون النظام)") }
        QQC2.CheckBox { id: animCheck; Kirigami.FormData.label: page.t("الحركة:"); text: page.t("تفعيل الحركات (الهالة، الموجات، المعادل)") }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: page.t("المحطات") }

        QQC2.ComboBox {
            id: shapeCombo
            Kirigami.FormData.label: page.t("شكل اللوجو:")
            model: [page.t("مربع ناعم (Squircle)"), page.t("دائرة"), page.t("مربع بزوايا خفيفة")]
        }
        QQC2.ComboBox {
            id: viewCombo
            Kirigami.FormData.label: page.t("طريقة العرض:")
            model: [page.t("شبكة"), page.t("قائمة")]
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: page.t("عدد الأعمدة:")
            enabled: viewCombo.currentIndex === 0
            model: [page.t("تلقائي"), "2", "3", "4", "5"]
            currentIndex: page.cfg_gridColumns === 0 ? 0 : page.cfg_gridColumns - 1
            onActivated: page.cfg_gridColumns = currentIndex === 0 ? 0 : currentIndex + 1
        }
        QQC2.CheckBox { id: groupsCheck; Kirigami.FormData.label: page.t("التصنيفات:"); text: page.t("عرض شرائط التصنيفات للتصفية") }
        QQC2.CheckBox { id: eqCheck; Kirigami.FormData.label: page.t("المعادل:"); text: page.t("عرض أعمدة المعادل") }
        QQC2.CheckBox { id: infoCheck; Kirigami.FormData.label: page.t("معلومات البث:"); text: page.t("عرض الصيغة ومعدل البت") }

        Kirigami.Separator { Kirigami.FormData.isSection: true; Kirigami.FormData.label: page.t("أيقونة اللوحة") }

        QQC2.ComboBox {
            id: compactCombo
            Kirigami.FormData.label: page.t("الأيقونة:")
            model: [page.t("لوجو المحطة أثناء التشغيل"), page.t("الأيقونة دائمًا")]
        }
        QQC2.Button {
            Kirigami.FormData.label: page.t("أيقونة الودجت:")
            icon.name: page.cfg_customIcon !== "" ? page.cfg_customIcon : ""
            icon.source: page.cfg_customIcon !== "" ? "" : Qt.resolvedUrl("../images/aurora-waves.svg")
            text: page.cfg_customIcon !== "" ? page.cfg_customIcon : "Aurora"
            onClicked: iconDialog.open()
            KIconThemes.IconDialog {
                id: iconDialog
                onIconNameChanged: if (iconName) page.cfg_customIcon = iconName
            }
        }
        QQC2.CheckBox { id: nameCheck; Kirigami.FormData.label: page.t("الاسم:"); text: page.t("عرض اسم المحطة بجانب الأيقونة في اللوحة الأفقية") }
    }
}
