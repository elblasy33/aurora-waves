import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// "Check & repair": finds moved files/folders, missing logos and dead links, and offers fixes.
Item {
    id: health

    property var app
    property var editor
    signal back()

    property var results: []          // [{id, name, issues:[{type, note, fix, fixNote}]}]
    property bool running: false
    property bool ran: false
    property string error: ""

    readonly property var problems: {
        var out = []
        for (var i = 0; i < results.length; i++)
            for (var j = 0; j < results[i].issues.length; j++)
                out.push({ id: results[i].id, name: results[i].name, issue: results[i].issues[j], key: i + ":" + j })
        return out
    }
    readonly property int fixable: problems.filter(function (p) { return !!p.issue.fix }).length

    function run() {
        running = true
        error = ""
        var list = app.stations.map(function (s) {
            return { id: s.id, name: s.name, url: s.url, kind: app.kindOf(s), logo: s.logo || "" }
        })
        app.runSources("check", JSON.stringify(list), function (r) {
            health.running = false
            health.ran = true
            if (!Array.isArray(r)) { health.error = app.t("تعذّر إتمام الفحص"); health.results = []; return }
            health.results = r
        })
    }

    // readable text for the codes returned by sources.py check
    function describe(issue) {
        var d = issue.detail || ""
        switch (issue.type + ":" + issue.code) {
        case "path:missing":       return app.t("المسار غير موجود: ") + d
        case "path:empty_folder":  return app.t("المجلد لا يحتوي على ملفات صوتية: ") + d
        case "audio:auth":         return app.t("المصدر يرفض الاتصال (401/403) — الرابط مغلق أو يحتاج تصريحًا")
        case "audio:notfound":     return app.t("الرابط غير موجود (404)")
        case "audio:unreachable":  return app.t("تعذّر الوصول إلى المصدر")
        case "audio:noaudio":      return app.t("لا يوجد صوت في هذا المصدر")
        case "audio:silent":       return app.t("المصدر يعمل لكنه صامت")
        case "audio:timeout":      return app.t("انتهت المهلة دون استقبال صوت")
        case "audio:resolve":      return app.t("تعذّر استخراج البث من الصفحة")
        case "audio:empty_playlist": return app.t("قائمة التشغيل فارغة")
        case "logo:missing":       return app.t("صورة اللوجو مفقودة")
        case "logo:remote":        return app.t("اللوجو محفوظ على الإنترنت فقط")
        case "logo:broken":        return app.t("رابط اللوجو لا يعمل")
        }
        return issue.code
    }
    function fixText(issue) {
        var d = issue.fixDetail || ""
        switch (issue.fixCode) {
        case "found_at":      return app.t("وُجد في: ") + d
        case "pick_manually": return app.t("اختر المسار أو المصدر يدويًا")
        case "alt_url":       return app.t("رابط بديل مُجرَّب وفيه صوت: ") + d
        case "no_alt":        return app.t("لا يوجد بديل يعمل في الدليل")
        case "logo_found":    return app.t("تم العثور على لوجو بديل")
        case "logo_glyph":    return app.t("سيُستبدل بلوجو زجاجي بالحرف")
        case "logo_local":    return app.t("سيُحفظ نسخة محلية منه")
        }
        return ""
    }

    function applyFix(p) {
        var i = app.indexOfStation(p.id)
        if (i < 0 || !p.issue.fix) return
        var list = app.stations.slice()
        var st = JSON.parse(JSON.stringify(list[i]))
        if (p.issue.fix.url !== undefined) st.url = p.issue.fix.url
        if (p.issue.fix.logo !== undefined) st.logo = p.issue.fix.logo
        list[i] = st
        app.saveStations(list)
        dropIssue(p)
    }

    function dropIssue(p) {
        var r = JSON.parse(JSON.stringify(results))
        for (var k = 0; k < r.length; k++) {
            if (r[k].id !== p.id) continue
            r[k].issues = r[k].issues.filter(function (x) {
                return !(x.type === p.issue.type && x.code === p.issue.code && x.detail === p.issue.detail)
            })
        }
        results = r
    }

    function fixAll() {
        var ps = problems.filter(function (p) { return !!p.issue.fix })
        for (var i = 0; i < ps.length; i++) applyFix(ps[i])
    }

    onVisibleChanged: if (visible && !running) run()

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            GlassButton {
                iconName: app.rtl ? "go-next" : "go-previous"
                toolTip: app.t("رجوع")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: health.back()
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Kirigami.Heading { text: app.t("فحص وإصلاح"); level: 3; font.weight: Font.DemiBold }
                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: app.t("المسارات، اللوجوهات، وروابط البث")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.55
                }
            }
            GlassButton {
                iconName: "view-refresh"
                toolTip: app.t("إعادة الفحص")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                enabled: !health.running
                onClicked: health.run()
            }
        }

        // summary
        GlassPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: sumRow.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: 16
            visible: health.ran || health.running
            highlighted: health.ran && !health.running && health.problems.length === 0
            accent: Kirigami.Theme.positiveTextColor

            RowLayout {
                id: sumRow
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                PlasmaComponents.BusyIndicator {
                    visible: health.running
                    running: visible
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: width
                }
                Kirigami.Icon {
                    visible: !health.running
                    source: health.error !== "" ? "dialog-error"
                          : health.problems.length === 0 ? "data-success" : "data-warning"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: width
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: health.running ? app.t("جاري فحص ") + app.stations.length + app.t(" محطة… (نستمع لكل رابط بضع ثوانٍ)")
                        : health.error !== "" ? health.error
                        : health.problems.length === 0 ? app.t("كل المحطات سليمة ✓")
                        : health.problems.length + app.t(" مشكلة — ") + health.fixable + app.t(" يمكن إصلاحها تلقائيًا")
                }
                GlassButton {
                    visible: !health.running && health.fixable > 0
                    text: app.t("إصلاح الكل")
                    iconName: "tools-wizard"
                    filled: true
                    accent: app.accent
                    implicitHeight: Kirigami.Units.gridUnit * 1.7
                    onClicked: health.fixAll()
                }
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Kirigami.Units.smallSpacing
            model: health.problems
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

            delegate: GlassPanel {
                id: card
                required property var modelData
                readonly property var st: { app.stations; var i = app.indexOfStation(modelData.id); return i >= 0 ? app.stations[i] : null }
                width: ListView.view.width - Kirigami.Units.smallSpacing
                height: cardCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: 16

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        StationLogo {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                            Layout.preferredHeight: Layout.preferredWidth
                            logo: card.st ? (card.st.logo || "") : ""
                            tint: card.st ? card.st.color : "gray"
                            glyph: card.st ? (card.st.glyph || "") : "?"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            QQC2.Label { text: card.modelData.name; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                            RowLayout {
                                Kirigami.Icon {
                                    source: card.modelData.issue.type === "path" ? "folder-important"
                                          : card.modelData.issue.type === "logo" ? "image-missing" : "audio-volume-muted"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: width
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: health.describe(card.modelData.issue)
                                    color: Kirigami.Theme.negativeTextColor
                                    font: Kirigami.Theme.smallFont
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: health.fixText(card.modelData.issue)
                        visible: text !== ""
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        GlassButton {
                            visible: !!card.modelData.issue.fix
                            text: app.t("إصلاح")
                            iconName: "tools-wizard"
                            filled: true
                            accent: app.accent
                            implicitHeight: Kirigami.Units.gridUnit * 1.6
                            onClicked: health.applyFix(card.modelData)
                        }
                        GlassButton {
                            text: app.t("تعديل يدوي")
                            iconName: "document-edit"
                            implicitHeight: Kirigami.Units.gridUnit * 1.6
                            onClicked: health.editor.openForm(app.indexOfStation(card.modelData.id))
                        }
                        GlassButton {
                            text: app.t("تجاهل")
                            iconName: "dialog-cancel"
                            implicitHeight: Kirigami.Units.gridUnit * 1.6
                            onClicked: health.dropIssue(card.modelData)
                        }
                    }
                }
            }
        }
    }
}
