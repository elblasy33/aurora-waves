import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "../code/i18n.js" as I18n

KCM.SimpleKCM {
    id: page

    property string cfg_language
    property alias cfg_mprisEnabled: mprisCheck.checked
    property alias cfg_resumeOnStart: resumeCheck.checked
    property alias cfg_wheelStep: wheelSpin.value

    // preview the chosen language immediately on this page
    readonly property string lang: I18n.resolve(cfg_language, Qt.locale().name)
    function t(s) { return I18n.tr(lang, s) }

    LayoutMirroring.enabled: lang === "ar"
    LayoutMirroring.childrenInherit: true

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: page.t("اللغة:")
            model: [page.t("تلقائي (لغة النظام)"), "العربية", "English"]
            readonly property var codes: ["auto", "ar", "en"]
            currentIndex: Math.max(0, codes.indexOf(page.cfg_language))
            onActivated: page.cfg_language = codes[currentIndex]
        }
        QQC2.CheckBox {
            id: mprisCheck
            Kirigami.FormData.label: page.t("مشغلات الوسائط:")
            text: page.t("الظهور في متحكم الوسائط والـ Visualizer وأزرار الوسائط (MPRIS)")
        }
        QQC2.CheckBox {
            id: resumeCheck
            Kirigami.FormData.label: page.t("عند بدء الجلسة:")
            text: page.t("تشغيل آخر محطة تلقائيًا")
        }
        QQC2.SpinBox {
            id: wheelSpin
            Kirigami.FormData.label: page.t("خطوة الصوت بالعجلة:")
            from: 1; to: 20
        }
    }
}
