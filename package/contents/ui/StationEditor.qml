import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.iconthemes as KIconThemes
import "../code/presets.js" as Presets

Item {
    id: editor

    property var app

    // form state: formIndex -1 = closed, -2 = new station, >=0 = editing that index
    property int formIndex: -1
    property string dName: ""
    property string dSubtitle: ""
    property string dGroup: ""
    property string dKind: "stream"        // stream | file | folder | playlist
    property string dUrl: ""
    property bool dShuffle: false
    property string dLogo: ""              // "" | pkg:… | icon:… | file:///…
    property string dGlyph: ""
    property string dColor: Presets.palette[0]

    property bool discovering: false
    property bool checking: false
    readonly property bool narrow: width < Kirigami.Units.gridUnit * 21
    property string fetchState: ""          // "" | busy | done | none
    property string fetchedName: ""
    property bool logoBusy: false
    property bool showLogoUrl: false

    readonly property color fg: Kirigami.Theme.textColor
    readonly property string logoMode: dLogo.indexOf("icon:") === 0 ? "icon" : (dLogo === "" ? "glyph" : "image")
    readonly property string autoGlyph: Presets.glyphFor(dName)
    readonly property bool formValid: dName.trim() !== "" && dUrl.trim() !== ""
                                      && (dKind !== "stream" || /^(https?|rtmp|rtsp|mms):\/\//.test(dUrl.trim()))

    function openForm(i) {
        if (i >= 0) {
            var s = app.stations[i]
            dName = s.name; dSubtitle = s.subtitle || ""; dGroup = s.group || ""
            dKind = app.kindOf(s); dUrl = s.url; dShuffle = !!s.shuffle
            dLogo = s.logo || ""; dGlyph = s.glyph || ""; dColor = s.color
        } else {
            dName = ""; dSubtitle = ""; dGroup = app.groupFilter; dKind = "stream"; dUrl = ""; dShuffle = false
            dLogo = ""; dGlyph = ""
            dColor = Presets.palette[Math.floor(Math.random() * Presets.palette.length)]
        }
        fetchState = ""
        fetchedName = ""
        logoBusy = false
        showLogoUrl = false
        formIndex = i
        formScroll.QQC2.ScrollBar.vertical.position = 0
    }

    // name / description / logo from the source itself (directory, ICY headers, site icon, yt-dlp)
    function fetchFromSource(logoOnly) {
        var url = dUrl.trim()
        if (dKind !== "stream" || url === "") return
        fetchState = "busy"
        var forIndex = formIndex
        app.runSources("probe", url, function (r) {
            if (editor.formIndex !== forIndex) return
            if (!r || r.error) { editor.fetchState = "none"; return }
            var got = false
            if (r.logo) { editor.dLogo = r.logo; got = true }
            if (!logoOnly) {
                if (r.name) {
                    editor.fetchedName = r.name
                    if (editor.dName.trim() === "") editor.dName = r.name
                    got = true
                }
                if (r.subtitle && editor.dSubtitle.trim() === "") { editor.dSubtitle = r.subtitle; got = true }
            }
            editor.fetchState = got ? "done" : "none"
        })
    }

    // copy / download an image into the widget's own logo folder
    function storeLogo(url) {
        if (!url) return
        logoBusy = true
        var forIndex = formIndex
        app.runSources("logo", url, function (r) {
            editor.logoBusy = false
            if (editor.formIndex !== forIndex) return
            if (r && r.logo) editor.dLogo = r.logo
            else if (String(url).indexOf("file://") === 0) editor.dLogo = url
            else editor.fetchState = "badlogo"
        })
    }

    function draft() {
        return {
            name: dName.trim(), subtitle: dSubtitle.trim(), group: dGroup.trim(),
            kind: dKind, url: dUrl.trim(), shuffle: dShuffle,
            logo: dLogo, glyph: dGlyph.trim() !== "" ? dGlyph.trim() : autoGlyph, color: dColor
        }
    }

    function saveForm() {
        var list = app.stations.slice()
        var st = draft()
        if (formIndex >= 0) {
            st.id = list[formIndex].id
            list[formIndex] = st
        } else {
            st.id = Presets.newId()
            list.push(st)
        }
        app.saveStations(list)
        formIndex = -1
    }

    function testDraft() {
        var st = draft()
        app.preview(st.name, st.url, st.kind, st.shuffle, st.logo)
    }

    function move(i, d) {
        var j = i + d
        if (j < 0 || j >= app.stations.length) return
        var list = app.stations.slice()
        var t = list[i]; list[i] = list[j]; list[j] = t
        app.saveStations(list)
    }

    function remove(i) {
        if (i < 0) return
        var list = app.stations.slice()
        var removed = list.splice(i, 1)[0]
        if (app.current && removed.id === app.current.id && app.wantPlaying) app.stop()
        app.saveStations(list)
    }

    function duplicate(i) {
        if (i < 0) return
        var list = app.stations.slice()
        var copy = JSON.parse(JSON.stringify(list[i]))
        copy.id = Presets.newId()
        copy.name = copy.name + app.t(" (نسخة)")
        list.splice(i + 1, 0, copy)
        app.saveStations(list)
    }

    function hasUrl(url) {
        for (var i = 0; i < app.stations.length; i++)
            if (app.stations[i].url === url) return true
        return false
    }

    function baseName(url) {
        var s = decodeURIComponent(String(url)).replace(/\/+$/, "")
        s = s.slice(s.lastIndexOf("/") + 1)
        return s.replace(/\.[^.]+$/, "")
    }

    // import every entry of an .m3u/.pls as its own station
    function importPlaylist(url) {
        app.run("--playlist " + app.shq(url), function (out) {
            var entries = []
            try { entries = JSON.parse(out) } catch (e) { }
            if (!Array.isArray(entries) || entries.length === 0) return
            var list = app.stations.slice()
            var group = baseName(url)
            for (var i = 0; i < entries.length; i++) {
                if (editor.hasUrl(entries[i].url)) continue
                list.push(Presets.make({
                    name: entries[i].name, url: entries[i].url, logo: "",
                    glyph: Presets.glyphFor(entries[i].name),
                    color: Presets.palette[(list.length * 5) % Presets.palette.length]
                }))
                list[list.length - 1].group = group
            }
            app.saveStations(list)
        })
    }

    // ================= discover page =================
    DiscoverPage {
        anchors.fill: parent
        app: editor.app
        visible: editor.discovering
        enabled: editor.formIndex === -1
        onBack: editor.discovering = false
    }

    // ================= check & repair page =================
    HealthPage {
        anchors.fill: parent
        app: editor.app
        editor: editor
        visible: editor.checking
        enabled: editor.formIndex === -1
        onBack: editor.checking = false
    }

    // ================= list page =================
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing
        enabled: editor.formIndex === -1
        visible: !editor.discovering && !editor.checking

        RowLayout {
            Layout.fillWidth: true
            GlassButton {
                iconName: app.rtl ? "go-next" : "go-previous"
                toolTip: app.t("رجوع")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: { editor.formIndex = -1; app.editing = false }
            }
            Kirigami.Heading { text: app.t("المحطات"); level: 3; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            GlassButton {
                text: editor.narrow ? "" : app.t("اكتشف")
                iconName: "edit-find"
                toolTip: app.t("ابحث في آلاف الإذاعات حول العالم")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: editor.discovering = true
            }
            GlassButton {
                text: editor.narrow ? "" : app.t("فحص")
                iconName: "tools-wizard"
                toolTip: app.t("فحص وإصلاح المسارات واللوجوهات والروابط")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: editor.checking = true
            }
            GlassButton {
                iconName: "document-import"
                toolTip: app.t("استيراد قائمة تشغيل (M3U / PLS) كمحطات")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: importDialog.open()
            }
            GlassButton {
                text: editor.narrow ? "" : app.t("جديدة")
                iconName: "list-add"
                filled: true
                accent: app.accent
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: editor.openForm(-2)
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: app.stations
                    delegate: GlassPanel {
                        id: row
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                        radius: 16
                        hovered: rowHover.hovered

                        HoverHandler { id: rowHover }
                        TapHandler { onDoubleTapped: editor.openForm(row.index) }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                            anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                            spacing: Kirigami.Units.smallSpacing * 2

                            StationLogo {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
                                Layout.preferredHeight: Layout.preferredWidth
                                logo: row.modelData.logo || ""
                                tint: row.modelData.color
                                glyph: row.modelData.glyph || ""
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    QQC2.Label { text: row.modelData.name; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Rectangle {
                                        visible: (row.modelData.group || "") !== ""
                                        implicitWidth: groupLbl.implicitWidth + 10
                                        implicitHeight: groupLbl.implicitHeight + 2
                                        radius: height / 2
                                        color: Qt.rgba(editor.fg.r, editor.fg.g, editor.fg.b, 0.1)
                                        QQC2.Label { id: groupLbl; anchors.centerIn: parent; text: row.modelData.group || ""; font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.9; opacity: 0.8 }
                                    }
                                }
                                QQC2.Label {
                                    text: row.modelData.subtitle ? row.modelData.subtitle : decodeURIComponent(row.modelData.url)
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.5
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }
                            Row {
                                spacing: 0
                                opacity: rowHover.hovered ? 1 : 0.5
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                // wide: every action visible; narrow: edit + "more" menu
                                QQC2.ToolButton { visible: !editor.narrow; icon.name: "arrow-up"; enabled: row.index > 0; onClicked: editor.move(row.index, -1); QQC2.ToolTip.text: app.t("لأعلى"); QQC2.ToolTip.visible: hovered }
                                QQC2.ToolButton { visible: !editor.narrow; icon.name: "arrow-down"; enabled: row.index < app.stations.length - 1; onClicked: editor.move(row.index, 1); QQC2.ToolTip.text: app.t("لأسفل"); QQC2.ToolTip.visible: hovered }
                                QQC2.ToolButton { icon.name: "document-edit"; onClicked: editor.openForm(row.index); QQC2.ToolTip.text: app.t("تعديل"); QQC2.ToolTip.visible: hovered }
                                QQC2.ToolButton { visible: !editor.narrow; icon.name: "edit-copy"; onClicked: editor.duplicate(row.index); QQC2.ToolTip.text: app.t("نسخ"); QQC2.ToolTip.visible: hovered }
                                QQC2.ToolButton { visible: !editor.narrow; icon.name: "edit-delete"; onClicked: editor.remove(row.index); QQC2.ToolTip.text: app.t("حذف"); QQC2.ToolTip.visible: hovered }
                                QQC2.ToolButton {
                                    visible: editor.narrow
                                    icon.name: "overflow-menu"
                                    onClicked: moreMenu.popup()
                                    QQC2.Menu {
                                        id: moreMenu
                                        QQC2.MenuItem { text: app.t("لأعلى"); icon.name: "arrow-up"; enabled: row.index > 0; onTriggered: editor.move(row.index, -1) }
                                        QQC2.MenuItem { text: app.t("لأسفل"); icon.name: "arrow-down"; enabled: row.index < app.stations.length - 1; onTriggered: editor.move(row.index, 1) }
                                        QQC2.MenuItem { text: app.t("نسخ"); icon.name: "edit-copy"; onTriggered: editor.duplicate(row.index) }
                                        QQC2.MenuSeparator { }
                                        QQC2.MenuItem { text: app.t("حذف"); icon.name: "edit-delete"; onTriggered: editor.remove(row.index) }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Maspero library ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    Kirigami.Icon { source: "folder-music"; Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: width; opacity: 0.7 }
                    QQC2.Label { text: app.t("مكتبة ماسبيرو — اضغط للإضافة"); font.weight: Font.DemiBold; opacity: 0.7 }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: Presets.catalog
                        delegate: GlassPanel {
                            id: chip
                            required property var modelData
                            readonly property bool added: { app.stations; return editor.hasUrl(modelData.url) }
                            width: chipRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                            height: Kirigami.Units.gridUnit * 1.9
                            radius: height / 2
                            opacity: added ? 0.4 : 1
                            hovered: chipMouse.containsMouse && !added

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing
                                StationLogo {
                                    width: Kirigami.Units.gridUnit * 1.2; height: width
                                    anchors.verticalCenter: parent.verticalCenter
                                    logo: chip.modelData.logo
                                    tint: chip.modelData.color
                                    glyph: chip.modelData.glyph
                                    radiusRatio: 0.5
                                }
                                QQC2.Label { text: Presets.nameFor(chip.modelData, app.lang); anchors.verticalCenter: parent.verticalCenter; font: Kirigami.Theme.smallFont }
                                Kirigami.Icon {
                                    source: chip.added ? "checkmark" : "list-add"
                                    width: Kirigami.Units.iconSizes.small; height: width
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !chip.added
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var list = app.stations.slice()
                                    var st = Presets.make(chip.modelData, app.lang)
                                    st.group = app.t("ماسبيرو")
                                    list.push(st)
                                    app.saveStations(list)
                                }
                            }
                        }
                    }
                }

                QQC2.Button {
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    Layout.alignment: Qt.AlignHCenter
                    flat: true
                    text: app.t("استعادة المحطات الافتراضية")
                    icon.name: "edit-reset"
                    onClicked: resetConfirm.open()
                }
            }
        }
    }

    QQC2.Dialog {
        id: resetConfirm
        anchors.centerIn: parent
        modal: true
        title: app.t("استعادة الافتراضي؟")
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        QQC2.Label { text: app.t("سيتم استبدال قائمتك الحالية بالمحطتين الافتراضيتين.") }
        onAccepted: { if (app.wantPlaying) app.stop(); app.saveStations(Presets.defaults(app.lang)) }
    }

    // ================= edit / add form =================
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Kirigami.Units.largeSpacing
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: editor.formIndex !== -1 ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: editor.formIndex = -1 }
    }

    Rectangle {
        anchors.fill: form
        radius: form.radius
        scale: form.scale
        visible: form.visible
        color: Kirigami.Theme.backgroundColor
        opacity: 0.9
    }

    GlassPanel {
        id: form
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.largeSpacing
        height: Math.min(parent.height - Kirigami.Units.largeSpacing,
                         formCol.implicitHeight + actionBar.implicitHeight + Kirigami.Units.gridUnit * 2.4)
        radius: 24
        tint: 0.12
        accent: editor.dColor
        visible: editor.formIndex !== -1
        scale: visible ? 1 : 0.9
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

        QQC2.ScrollView {
            id: formScroll
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: actionBar.top
                      margins: Kirigami.Units.gridUnit * 0.6; bottomMargin: Kirigami.Units.largeSpacing }
            contentWidth: availableWidth

            ColumnLayout {
                id: formCol
                width: formScroll.availableWidth
                spacing: Kirigami.Units.largeSpacing

                // ---- header with live preview ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    StationLogo {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        Layout.preferredHeight: Layout.preferredWidth
                        logo: editor.dLogo
                        tint: editor.dColor
                        glyph: editor.dGlyph !== "" ? editor.dGlyph : editor.autoGlyph
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Kirigami.Heading { text: editor.formIndex === -2 ? app.t("محطة جديدة") : app.t("تعديل المحطة"); level: 3 }
                        QQC2.Label { text: editor.dName !== "" ? editor.dName : app.t("بدون اسم"); opacity: 0.7; elide: Text.ElideRight; Layout.fillWidth: true }
                        QQC2.Label { text: editor.dSubtitle; visible: text !== ""; opacity: 0.5; font: Kirigami.Theme.smallFont; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }

                // ---- source ----
                SectionLabel { text: app.t("المصدر") }
                Segmented {
                    Layout.fillWidth: true
                    model: [
                        { key: "stream",   text: app.t("رابط بث"),     icon: "network-wireless" },
                        { key: "file",     text: app.t("ملف"),          icon: "audio-x-generic" },
                        { key: "folder",   text: app.t("مجلد"),         icon: "folder-music" },
                        { key: "playlist", text: app.t("قائمة تشغيل"),  icon: "view-media-playlist" }
                    ]
                    current: editor.dKind
                    accent: editor.dColor
                    onPicked: function (key) {
                        if (key !== editor.dKind) { editor.dKind = key; editor.dUrl = "" }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: editor.dKind === "stream" ? editor.dUrl : decodeURIComponent(editor.dUrl.replace(/^file:\/\//, ""))
                        readOnly: editor.dKind !== "stream"
                        onTextEdited: editor.dUrl = text
                        placeholderText: editor.dKind === "stream" ? "https://… (mp3 / aac / m3u8 / Dailymotion / YouTube)"
                                       : editor.dKind === "folder" ? app.t("اختر مجلد موسيقى…") : app.t("اختر ملفًا…")
                        LayoutMirroring.enabled: false
                        horizontalAlignment: Text.AlignLeft
                    }
                    QQC2.Button {
                        visible: editor.dKind === "stream"
                        enabled: /^https?:\/\//.test(editor.dUrl.trim()) && editor.fetchState !== "busy"
                        icon.name: "download"
                        text: app.t("جلب")
                        display: editor.narrow ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon
                        QQC2.ToolTip.text: app.t("جلب الاسم والوصف واللوجو من المصدر")
                        QQC2.ToolTip.visible: hovered
                        onClicked: editor.fetchFromSource(false)
                    }
                    QQC2.Button {
                        visible: editor.dKind !== "stream"
                        icon.name: editor.dKind === "folder" ? "folder-open" : "document-open"
                        text: app.t("تصفح…")
                        display: editor.narrow ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon
                        onClicked: {
                            if (editor.dKind === "folder") folderDialog.open()
                            else if (editor.dKind === "playlist") playlistDialog.open()
                            else audioDialog.open()
                        }
                    }
                }
                // fetch feedback
                RowLayout {
                    Layout.fillWidth: true
                    visible: editor.fetchState !== ""
                    PlasmaComponents.BusyIndicator {
                        visible: editor.fetchState === "busy"
                        running: visible
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: width
                    }
                    Kirigami.Icon {
                        visible: editor.fetchState !== "busy"
                        source: editor.fetchState === "done" ? "dialog-ok-apply" : "dialog-information"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: width
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.75
                        text: editor.fetchState === "busy" ? app.t("جاري البحث عن معلومات المحطة…")
                            : editor.fetchState === "done" ? app.t("تم جلب المعلومات من المصدر ✓")
                            : editor.fetchState === "badlogo" ? app.t("تعذّر تحميل الصورة من هذا الرابط")
                            : app.t("لم يُعثر على معلومات — أدخلها يدويًا")
                    }
                    QQC2.Button {
                        visible: editor.fetchState === "done" && editor.fetchedName !== "" && editor.fetchedName !== editor.dName
                        flat: true
                        text: app.t("استخدم الاسم: ") + editor.fetchedName
                        Layout.maximumWidth: editor.width * 0.45
                        onClicked: editor.dName = editor.fetchedName
                    }
                }

                QQC2.Switch {
                    visible: editor.dKind === "folder" || editor.dKind === "playlist"
                    text: app.t("تشغيل عشوائي")
                    checked: editor.dShuffle
                    onToggled: editor.dShuffle = checked
                }

                // ---- details ----
                SectionLabel { text: app.t("التفاصيل") }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Kirigami.Units.largeSpacing
                    QQC2.Label { text: app.t("الاسم") }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: editor.dName
                        onTextEdited: editor.dName = text
                        placeholderText: app.t("مثال: صوت العرب")
                    }
                    QQC2.Label { text: app.t("وصف") }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: editor.dSubtitle
                        onTextEdited: editor.dSubtitle = text
                        placeholderText: app.t("اختياري — مثل: FM 89.5")
                    }
                    QQC2.Label { text: app.t("التصنيف") }
                    QQC2.ComboBox {
                        id: groupBox
                        Layout.fillWidth: true
                        editable: true
                        model: app.groups
                        editText: editor.dGroup
                        onEditTextChanged: editor.dGroup = editText
                        onActivated: editor.dGroup = currentText
                        Component.onCompleted: editText = editor.dGroup
                        Connections {
                            target: editor
                            function onFormIndexChanged() { groupBox.editText = editor.dGroup }
                        }
                    }
                }

                // ---- logo ----
                SectionLabel { text: app.t("اللوجو") }
                Segmented {
                    Layout.fillWidth: true
                    model: [
                        { key: "glyph",  text: app.t("حرف"),        icon: "draw-text" },
                        { key: "icon",   text: app.t("أيقونة"),      icon: "preferences-desktop-icons" },
                        { key: "image",  text: app.t("صورة"),        icon: "insert-image" },
                        { key: "source", text: app.t("من المصدر"),   icon: "download" }
                    ]
                    current: editor.logoMode
                    accent: editor.dColor
                    onPicked: function (key) {
                        if (key === "glyph") editor.dLogo = ""
                        else if (key === "icon") iconDialog.open()
                        else if (key === "image") imageDialog.open()
                        else if (editor.dKind === "stream" && /^https?:\/\//.test(editor.dUrl.trim())) editor.fetchFromSource(true)
                        else editor.fetchState = "none"
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    visible: editor.logoMode === "glyph"
                    spacing: 2
                    QQC2.TextField {
                        width: Kirigami.Units.gridUnit * 5
                        text: editor.dGlyph
                        onTextEdited: editor.dGlyph = text
                        maximumLength: 4
                        placeholderText: editor.autoGlyph !== "" ? editor.autoGlyph : app.t("تلقائي")
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Repeater {
                        model: ["📻", "🎵", "🎙️", "📖", "⚽", "🎶", "🌙", "☕"]
                        QQC2.ToolButton {
                            required property string modelData
                            text: modelData
                            onClicked: editor.dGlyph = modelData
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: editor.logoMode === "icon"
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: editor.dLogo.slice(5)
                        elide: Text.ElideMiddle
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.Button { text: app.t("تغيير…"); icon.name: "preferences-desktop-icons"; onClicked: iconDialog.open() }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: editor.logoMode === "image" || editor.showLogoUrl
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.BusyIndicator {
                            visible: editor.logoBusy
                            running: visible
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: width
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: editor.logoMode === "image"
                                  ? decodeURIComponent(editor.app.logoUrl(editor.dLogo).toString().replace(/^file:\/\//, ""))
                                  : ""
                            elide: Text.ElideMiddle
                            opacity: 0.6
                            font: Kirigami.Theme.smallFont
                        }
                        QQC2.Button { text: app.t("من الجهاز…"); icon.name: "document-open"; display: editor.narrow ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon; QQC2.ToolTip.text: text; QQC2.ToolTip.visible: hovered && editor.narrow; onClicked: imageDialog.open() }
                        QQC2.Button {
                            text: app.t("من رابط…")
                            display: editor.narrow ? QQC2.AbstractButton.IconOnly : QQC2.AbstractButton.TextBesideIcon
                            icon.name: "insert-link"
                            checkable: true
                            checked: editor.showLogoUrl
                            onToggled: editor.showLogoUrl = checked
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: editor.showLogoUrl
                        QQC2.TextField {
                            id: logoUrlField
                            Layout.fillWidth: true
                            placeholderText: "https://…/logo.png"
                            LayoutMirroring.enabled: false
                            horizontalAlignment: Text.AlignLeft
                            onAccepted: editor.storeLogo(text.trim())
                        }
                        QQC2.Button {
                            text: app.t("تحميل")
                            icon.name: "download"
                            enabled: /^https?:\/\//.test(logoUrlField.text.trim()) && !editor.logoBusy
                            onClicked: editor.storeLogo(logoUrlField.text.trim())
                        }
                    }
                }

                // colors
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: Presets.palette
                        Rectangle {
                            required property string modelData
                            width: 24; height: 24; radius: 12
                            color: modelData
                            border.width: editor.dColor === modelData ? 3 : 1
                            border.color: editor.dColor === modelData ? editor.fg : Qt.rgba(1, 1, 1, 0.4)
                            scale: editor.dColor === modelData ? 1.15 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: editor.dColor = parent.modelData }
                        }
                    }
                    // custom color
                    Rectangle {
                        readonly property bool custom: Presets.palette.indexOf(editor.dColor) < 0
                        width: 24; height: 24; radius: 12
                        color: custom ? editor.dColor : "transparent"
                        border.width: custom ? 3 : 1
                        border.color: custom ? editor.fg : Qt.rgba(editor.fg.r, editor.fg.g, editor.fg.b, 0.5)
                        Kirigami.Icon { anchors.centerIn: parent; width: 14; height: 14; source: "color-picker"; visible: !parent.custom }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: colorDialog.open() }
                        QQC2.ToolTip.text: app.t("لون مخصص")
                        QQC2.ToolTip.visible: hov.hovered
                        HoverHandler { id: hov }
                    }
                }

            }
        }

        // ---- actions: pinned to the bottom so they stay reachable at any widget height ----
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: actionBar.top; margins: Kirigami.Units.gridUnit * 0.6; bottomMargin: Kirigami.Units.smallSpacing }
            height: 1
            color: editor.fg
            opacity: 0.12
        }
        RowLayout {
            id: actionBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Kirigami.Units.gridUnit * 0.6 }
            GlassButton {
                text: editor.narrow ? "" : app.t("تجربة")
                iconName: "media-playback-start"
                enabled: editor.formValid
                opacity: enabled ? 1 : 0.5
                toolTip: app.t("استمع للمصدر قبل الحفظ")
                onClicked: editor.testDraft()
            }
            Item { Layout.fillWidth: true }
            GlassButton {
                text: app.t("إلغاء")
                onClicked: editor.formIndex = -1
            }
            GlassButton {
                text: app.t("حفظ")
                iconName: "dialog-ok"
                filled: true
                accent: editor.dColor
                enabled: editor.formValid
                opacity: enabled ? 1 : 0.5
                onClicked: editor.saveForm()
            }
        }
    }

    // ================= dialogs =================
    FileDialog {
        id: audioDialog
        title: app.t("اختر ملفًا صوتيًا")
        nameFilters: [app.t("ملفات صوتية (*.mp3 *.m4a *.aac *.ogg *.opus *.flac *.wav *.wma *.mka *.mp4)"), app.t("كل الملفات (*)")]
        onAccepted: {
            editor.dUrl = selectedFile.toString()
            if (editor.dName === "") editor.dName = editor.baseName(editor.dUrl)
        }
    }
    FolderDialog {
        id: folderDialog
        title: app.t("اختر مجلد الموسيقى")
        onAccepted: {
            editor.dUrl = selectedFolder.toString()
            if (editor.dName === "") editor.dName = editor.baseName(editor.dUrl)
            if (editor.dGlyph === "" && editor.dLogo === "") editor.dLogo = "icon:folder-music"
        }
    }
    FileDialog {
        id: playlistDialog
        title: app.t("اختر قائمة تشغيل")
        nameFilters: [app.t("قوائم تشغيل (*.m3u *.m3u8 *.pls)")]
        onAccepted: {
            editor.dUrl = selectedFile.toString()
            if (editor.dName === "") editor.dName = editor.baseName(editor.dUrl)
        }
    }
    FileDialog {
        id: importDialog
        title: app.t("استيراد قائمة تشغيل كمحطات")
        nameFilters: [app.t("قوائم تشغيل (*.m3u *.m3u8 *.pls)")]
        onAccepted: editor.importPlaylist(selectedFile.toString())
    }
    FileDialog {
        id: imageDialog
        title: app.t("اختر صورة اللوجو")
        nameFilters: [app.t("صور (*.png *.jpg *.jpeg *.svg *.webp *.gif *.ico)")]
        onAccepted: editor.storeLogo(selectedFile.toString())   // keeps a copy so moving the file is safe
    }
    ColorDialog {
        id: colorDialog
        title: app.t("لون المحطة")
        selectedColor: editor.dColor
        onAccepted: editor.dColor = selectedColor.toString()
    }
    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: if (iconName) editor.dLogo = "icon:" + iconName
    }
}
