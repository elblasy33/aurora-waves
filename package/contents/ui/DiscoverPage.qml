import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../code/presets.js" as Presets

// Search the open Radio Browser directory (radio-browser.info) and add stations.
Item {
    id: disc

    property var app
    signal back()

    property var results: []
    property bool loading: false
    property bool exhausted: false
    property string error: ""
    property string query: ""
    property string country: app.systemCountry
    property string tag: ""
    property int seq: 0
    property bool started: false
    property var busyAdds: ({})          // url -> true while fetching its logo

    readonly property color fg: Kirigami.Theme.textColor
    readonly property int pageSize: 50

    // Arab countries keep localized names; the rest of the world comes from the directory
    readonly property var arabCountries: [
        { code: "EG", name: app.t("🇪🇬  مصر") },        { code: "SA", name: app.t("🇸🇦  السعودية") },
        { code: "AE", name: app.t("🇦🇪  الإمارات") },    { code: "KW", name: app.t("🇰🇼  الكويت") },
        { code: "QA", name: app.t("🇶🇦  قطر") },         { code: "BH", name: app.t("🇧🇭  البحرين") },
        { code: "OM", name: app.t("🇴🇲  عُمان") },        { code: "JO", name: app.t("🇯🇴  الأردن") },
        { code: "LB", name: app.t("🇱🇧  لبنان") },       { code: "SY", name: app.t("🇸🇾  سوريا") },
        { code: "PS", name: app.t("🇵🇸  فلسطين") },      { code: "IQ", name: app.t("🇮🇶  العراق") },
        { code: "YE", name: app.t("🇾🇪  اليمن") },       { code: "SD", name: app.t("🇸🇩  السودان") },
        { code: "LY", name: app.t("🇱🇾  ليبيا") },       { code: "TN", name: app.t("🇹🇳  تونس") },
        { code: "DZ", name: app.t("🇩🇿  الجزائر") },     { code: "MA", name: app.t("🇲🇦  المغرب") }
    ]
    readonly property var fallbackWorld: [
        { code: "US", name: app.t("🇺🇸  أمريكا") },      { code: "GB", name: app.t("🇬🇧  بريطانيا") },
        { code: "FR", name: app.t("🇫🇷  فرنسا") },       { code: "DE", name: app.t("🇩🇪  ألمانيا") },
        { code: "TR", name: app.t("🇹🇷  تركيا") }
    ]
    property var worldCountries: []          // [{code, name, count}] from sources.py countries
    readonly property string homeCountry: app.systemCountry

    // All · your country · Arab countries (Arabic UI) · the rest of the world by station count
    readonly property var countries: {
        var out = [{ code: "", name: app.t("🌍  كل الدول") }]
        var used = {}
        function push(c) { if (c.code && !used[c.code]) { used[c.code] = true; out.push(c) } }
        function named(code) {
            for (var i = 0; i < arabCountries.length; i++) if (arabCountries[i].code === code) return arabCountries[i]
            for (var j = 0; j < fallbackWorld.length; j++) if (fallbackWorld[j].code === code) return fallbackWorld[j]
            for (var k = 0; k < worldCountries.length; k++)
                if (worldCountries[k].code === code) return { code: code, name: flag(code) + "  " + worldCountries[k].name }
            return { code: code, name: flag(code) + "  " + code }
        }
        if (homeCountry !== "") push(named(homeCountry))
        if (app.lang === "ar") arabCountries.forEach(push)
        if (worldCountries.length > 0) {
            worldCountries.forEach(function (c) { push(named(c.code)) })
        } else {
            arabCountries.forEach(push)
            fallbackWorld.forEach(push)
        }
        return out
    }
    readonly property var tags: [
        { t: "",           n: app.t("الكل") },      { t: "news",       n: app.t("أخبار") },
        { t: "pop",        n: app.t("بوب") },       { t: "hits",       n: app.t("الأكثر شهرة") },
        { t: "rock",       n: app.t("روك") },       { t: "jazz",       n: app.t("جاز") },
        { t: "classical",  n: app.t("كلاسيك") },    { t: "chillout",   n: app.t("استرخاء") },
        { t: "electronic", n: app.t("إلكتروني") },  { t: "talk",       n: app.t("حوارات") },
        { t: "sport",      n: app.t("رياضة") },     { t: "arabic",     n: app.t("عربي") },
        { t: "tarab",      n: app.t("طرب") },       { t: "quran",      n: app.t("قرآن") },
        { t: "islamic",    n: app.t("إسلامي") }
    ]

    function flag(cc) {
        if (!cc || cc.length !== 2) return "🌐"
        cc = cc.toUpperCase()
        return String.fromCodePoint(0x1F1E6 + cc.charCodeAt(0) - 65, 0x1F1E6 + cc.charCodeAt(1) - 65)
    }

    function search(more) {
        var mySeq = ++seq
        loading = true
        error = ""
        var offset = more ? results.length : 0
        if (!more) exhausted = false
        app.runSources("search", JSON.stringify({ q: query.trim(), country: country, tag: tag,
                                                  limit: pageSize, offset: offset }), function (r) {
            if (mySeq !== disc.seq) return
            disc.loading = false
            if (!Array.isArray(r)) {
                disc.error = app.t("تعذّر الاتصال بدليل الإذاعات. تحقق من الإنترنت.")
                if (!more) disc.results = []
                return
            }
            disc.exhausted = r.length < disc.pageSize
            disc.results = more ? disc.results.concat(r) : r
            if (!more) list.positionViewAtBeginning()
        })
    }

    function isAdded(url) {
        for (var i = 0; i < app.stations.length; i++)
            if (app.stations[i].url === url) return true
        return false
    }

    function colorFor(name) {
        var h = 0
        for (var i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
        return Presets.palette[h % Presets.palette.length]
    }

    function add(s) {
        var st = Presets.make({
            name: s.name,
            url: s.url,
            logo: s.favicon,                 // shown right away; replaced by a local copy below
            glyph: Presets.glyphFor(s.name),
            color: colorFor(s.name)
        })
        var bits = []
        if (s.codec) bits.push(s.codec + (s.bitrate ? " " + s.bitrate + "k" : ""))
        if (s.tags.length) bits.push(s.tags.slice(0, 2).join(app.t("، ")))
        st.subtitle = bits.join(" · ")
        st.group = s.country || ""
        var list = app.stations.slice()
        list.push(st)
        app.saveStations(list)

        // keep a local copy of the logo (works offline, survives dead favicon links)
        var b = busyAdds; b[s.url] = true; busyAdds = b
        var done = function (r) {
            var bb = disc.busyAdds; delete bb[s.url]; disc.busyAdds = bb
            var logo = (r && r.logo) ? r.logo : ""
            var i = app.indexOfStation(st.id)
            if (i < 0) return
            var l = app.stations.slice()
            var copy = JSON.parse(JSON.stringify(l[i]))
            copy.logo = logo !== "" ? logo : (s.favicon || "")
            if (copy.logo === l[i].logo) return
            l[i] = copy
            app.saveStations(l)
        }
        if (s.favicon) app.runSources("logo", s.favicon, function (r) {
            if (r && r.logo) done(r)
            else if (s.homepage) app.runSources("sitelogo", s.homepage, done)
            else done(r)
        })
        else if (s.homepage) app.runSources("sitelogo", s.homepage, done)
        else done({})
    }

    onVisibleChanged: {
        if (!visible || started) return
        started = true
        search(false)
        app.runSources("countries", "-", function (r) { if (Array.isArray(r)) disc.worldCountries = r })
    }

    Timer { id: debounce; interval: 650; onTriggered: disc.search(false) }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        // header
        RowLayout {
            Layout.fillWidth: true
            GlassButton {
                iconName: app.rtl ? "go-next" : "go-previous"
                toolTip: app.t("رجوع")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: disc.back()
            }
            ColumnLayout {
                spacing: 0
                Kirigami.Heading { text: app.t("اكتشف إذاعات العالم"); level: 3; font.weight: Font.DemiBold }
                QQC2.Label { text: app.t("من دليل Radio Browser المفتوح"); font: Kirigami.Theme.smallFont; opacity: 0.55 }
            }
            Item { Layout.fillWidth: true }
        }

        // search + country (stacked when narrow)
        GridLayout {
            Layout.fillWidth: true
            columns: disc.width < Kirigami.Units.gridUnit * 19 ? 1 : 2
            Kirigami.SearchField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: app.t("ابحث باسم الإذاعة…")
                onTextChanged: { disc.query = text; debounce.restart() }
                onAccepted: { debounce.stop(); disc.search(false) }
            }
            QQC2.ComboBox {
                id: countryBox
                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                Layout.fillWidth: parent.columns === 1
                model: disc.countries
                textRole: "name"
                valueRole: "code"
                Component.onCompleted: currentIndex = indexOfValue(disc.country)
                onModelChanged: currentIndex = indexOfValue(disc.country)
                onActivated: { disc.country = currentValue; disc.search(false) }
            }
        }

        // tag chips
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.7
            contentWidth: tagRow.implicitWidth
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: tagRow
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: disc.tags
                    delegate: GlassPanel {
                        id: tchip
                        required property var modelData
                        readonly property bool selected: disc.tag === modelData.t
                        width: tlabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: Kirigami.Units.gridUnit * 1.6
                        radius: height / 2
                        highlighted: selected
                        accent: app.accent
                        hovered: tmouse.containsMouse
                        QQC2.Label {
                            id: tlabel
                            anchors.centerIn: parent
                            text: tchip.modelData.n
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            font.weight: tchip.selected ? Font.Bold : Font.Normal
                        }
                        MouseArea {
                            id: tmouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { disc.tag = tchip.modelData.t; disc.search(false) }
                        }
                    }
                }
            }
        }

        // results
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: Kirigami.Units.smallSpacing
                model: disc.results
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

                delegate: GlassPanel {
                    id: rowItem
                    required property var modelData
                    required property int index
                    readonly property bool added: { app.stations; return disc.isAdded(modelData.url) }
                    readonly property bool previewingThis: app.previewing && app.previewName === modelData.name
                    width: ListView.view.width - Kirigami.Units.smallSpacing
                    height: Kirigami.Units.gridUnit * 3.2
                    radius: 16
                    hovered: rh.hovered
                    highlighted: previewingThis
                    accent: app.accent

                    HoverHandler { id: rh }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                        anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                        spacing: Kirigami.Units.smallSpacing * 2

                        StationLogo {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.3
                            Layout.preferredHeight: Layout.preferredWidth
                            logo: rowItem.modelData.favicon
                            tint: disc.colorFor(rowItem.modelData.name)
                            glyph: Presets.glyphFor(rowItem.modelData.name)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            QQC2.Label {
                                text: rowItem.modelData.name
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                                text: {
                                    var s = rowItem.modelData
                                    var p = [disc.flag(s.countrycode) + " " + s.country]
                                    if (s.codec) p.push(s.codec + (s.bitrate ? " " + s.bitrate + "k" : ""))
                                    if (s.tags.length) p.push(s.tags.slice(0, 3).join(app.t("، ")))
                                    return p.join("  ·  ")
                                }
                            }
                        }
                        QQC2.ToolButton {
                            icon.name: rowItem.previewingThis ? "media-playback-stop" : "media-playback-start"
                            QQC2.ToolTip.text: rowItem.previewingThis ? app.t("إيقاف") : app.t("استماع سريع")
                            QQC2.ToolTip.visible: hovered
                            onClicked: rowItem.previewingThis ? app.stop()
                                     : app.preview(rowItem.modelData.name, rowItem.modelData.url, "stream", false, rowItem.modelData.favicon)
                        }
                        GlassButton {
                            iconName: rowItem.added ? "checkmark" : "list-add"
                            filled: !rowItem.added
                            accent: app.accent
                            implicitHeight: Kirigami.Units.gridUnit * 1.6
                            enabled: !rowItem.added
                            toolTip: rowItem.added ? app.t("مضافة") : app.t("إضافة لمحطاتي")
                            onClicked: disc.add(rowItem.modelData)
                        }
                    }
                }

                footer: Item {
                    width: list.width
                    height: (disc.results.length > 0 && !disc.exhausted) ? Kirigami.Units.gridUnit * 3 : 0
                    visible: height > 0
                    QQC2.Button {
                        anchors.centerIn: parent
                        text: app.t("تحميل المزيد")
                        icon.name: "go-down"
                        enabled: !disc.loading
                        onClicked: disc.search(true)
                    }
                }
            }

            // states
            PlasmaComponents.BusyIndicator {
                anchors.centerIn: parent
                running: disc.loading && disc.results.length === 0
                visible: running
            }
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: !disc.loading && disc.results.length === 0
                icon.name: disc.error !== "" ? "network-disconnect" : "edit-find"
                text: disc.error !== "" ? disc.error : app.t("لا توجد نتائج")
                explanation: disc.error !== "" ? "" : app.t("جرّب اسمًا آخر أو دولة أخرى")
            }
        }
    }
}
