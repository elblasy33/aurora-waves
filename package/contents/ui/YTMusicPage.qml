import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../code/presets.js" as Presets

// YouTube Music: search, artists, albums and the play queue, in the widget's glass style.
// Data comes from code/ytmusic.py; playback is the radio daemon's "yt" queue.
Item {
    id: ytp

    property var app
    signal back()

    // search | artist | album | playlist | list | queue | account
    property string view: "search"
    property var stack: []                 // previous views: [{view, detail}]
    property string query: ""
    property string filter: "all"
    property var results: ({ songs: [], artists: [], albums: [] })
    property var detail: null              // artist or album being shown
    property bool loading: false
    property string error: ""
    property int seq: 0
    property bool showAllSongs: false

    readonly property real gu: Kirigami.Units.gridUnit
    readonly property color fg: Kirigami.Theme.textColor
    readonly property bool ready: app.ytStatus.ready
    readonly property string playingId: app.ytMode && app.ytTrack ? app.ytTrack.id : ""
    readonly property bool signedIn: !!app.ytStatus.signedIn
    readonly property var account: app.ytStatus.account || ({})
    property var home: []                  // [{title, items[]}]
    property bool homeLoading: false
    property var lib: null                 // {liked[], playlists[], history[]} when signed in
    property string loginBusy: ""          // browser being read, or "headers"
    property string loginError: ""
    property bool showHeaders: false
    readonly property var browserNames: ({ chrome: "Google Chrome", chromium: "Chromium", brave: "Brave",
                                           edge: "Microsoft Edge", vivaldi: "Vivaldi", opera: "Opera", firefox: "Firefox" })

    onVisibleChanged: {
        if (!visible) return
        if (!app.ytStatus.checked) app.ytCheck(function () { ytp.loadHome() })
        else if (home.length === 0) loadHome()
    }
    onReadyChanged: if (ready && visible && home.length === 0) loadHome()

    function loadHome() {
        if (!ready || homeLoading) return
        homeLoading = true
        app.runYt("home", JSON.stringify({ lang: app.lang, country: app.systemCountry }), function (r) {
            ytp.homeLoading = false
            if (r && r.shelves) ytp.home = r.shelves
        })
        if (signedIn) app.runYt("library", "-", function (r) { if (r && !r.error) ytp.lib = r })
        else lib = null
    }

    function loginWith(params) {
        loginBusy = params.browser || "headers"
        loginError = ""
        app.ytLogin(params, function (r) {
            ytp.loginBusy = ""
            if (!r || r.error) {
                ytp.loginError = r && r.error === "not-signed-in"
                    ? app.t("لم نجد حساب يوتيوب مسجّلًا في هذا المتصفح. افتح music.youtube.com فيه وسجّل الدخول ثم حاول مرة أخرى.")
                    : app.t("تعذّر تسجيل الدخول: ") + (r ? r.error : "")
                return
            }
            ytp.showHeaders = false
            ytp.home = []; ytp.loadHome()
            ytp.goBack()
        })
    }
    function logout() {
        app.ytLogout(function () { ytp.lib = null; ytp.home = []; ytp.loadHome() })
    }

    // a home / library card was picked
    function pick(it) {
        if (it.kind === "song") playSong(it)
        else if (it.kind === "artist") open("artist", it.id, { name: it.title, thumb: it.thumb })
        else open(it.kind, it.id, { title: it.title, thumb: it.thumb, artist: it.subtitle })
    }
    // a list we already have (history)
    function showList(title, list) {
        stack = stack.concat([{ view: view, detail: detail }])
        view = "list"
        detail = { title: title, tracks: list, thumb: list.length ? list[0].thumb : "" }
        detailFlick.contentY = 0
    }
    function showAccount() {
        if (view === "account") { goBack(); return }
        stack = stack.concat([{ view: view, detail: detail }])
        view = "account"
        loginError = ""
    }
    function like(t) {
        app.runYt("like", JSON.stringify({ id: t.id, on: true }), function (r) {
            savedNote.show(r && r.ok ? "♥  " + app.t("أضيفت إلى الأغاني التي أعجبتك") : app.t("تعذّر الإعجاب بالأغنية"), true)
        })
    }

    // ---------------------------------------------------------------- data
    function search() {
        var q = query.trim()
        var mySeq = ++seq
        error = ""
        if (q === "") { results = { songs: [], artists: [], albums: [] }; loading = false; return }
        loading = true
        app.runYt("search", JSON.stringify({ q: q, filter: filter, country: app.systemCountry }), function (r) {
            if (mySeq !== ytp.seq) return
            ytp.loading = false
            if (!r || r.error) { ytp.error = errorText(r); return }
            ytp.results = r
            resultsFlick.contentY = 0
        })
    }

    function errorText(r) {
        if (r && r.error === "not-installed") return app.t("يوتيوب ميوزك غير مفعّل بعد.")
        return app.t("تعذّر الوصول إلى يوتيوب ميوزك. تحقق من الإنترنت.")
    }

    function open(kind, id, seed) {
        stack = stack.concat([{ view: view, detail: detail }])
        view = kind
        detail = seed || null           // show what we know right away
        showAllSongs = false
        var mySeq = ++seq
        loading = true
        error = ""
        app.runYt(kind, id, function (r) {
            if (mySeq !== ytp.seq) return
            ytp.loading = false
            if (!r || r.error) { ytp.error = errorText(r); return }
            ytp.detail = r
        })
        detailFlick.contentY = 0
    }

    function goBack() {
        if (stack.length === 0) { back(); return }
        var prev = stack[stack.length - 1]
        stack = stack.slice(0, -1)
        view = prev.view
        detail = prev.detail
        error = ""
        loading = false
        ++seq
    }

    function showQueue() {
        if (view === "queue") { goBack(); return }
        stack = stack.concat([{ view: view, detail: detail }])
        view = "queue"
    }

    // one song from search: start it now, then fill the queue with similar songs
    function playSong(t) {
        app.playYt([t], 0, t.artist)
        app.runYt("radio", t.id, function (r) {
            if (!r || !r.tracks || !app.ytMode || app.ytQueue.length !== 1 || app.ytQueue[0].id !== t.id) return
            var more = r.tracks.filter(function (x) { return x.id !== t.id })
            if (more.length) app.enqueueYt(more, false)
        })
    }

    function playRadio(t) {
        app.runYt("radio", t.id, function (r) {
            if (r && r.tracks && r.tracks.length) app.playYt(r.tracks, 0, t.title)
        })
    }

    function saveStation(name, thumb, ref, url, subtitle) {
        var st = Presets.make({ name: name, url: url, logo: thumb, glyph: Presets.glyphFor(name), color: "#e53935" })
        st.kind = "yt"
        st.ytRef = ref
        st.subtitle = subtitle
        st.group = app.t("يوتيوب ميوزك")
        var list = app.stations.slice()
        list.push(st)
        app.saveStations(list)
        // keep a local copy of the cover (works offline, shows in media controllers)
        app.runSources("logo", thumb, function (r) {
            var i = app.indexOfStation(st.id)
            if (i < 0 || !r || !r.logo) return
            var l = app.stations.slice()
            var c = JSON.parse(JSON.stringify(l[i]))
            c.logo = r.logo
            l[i] = c
            app.saveStations(l)
        })
        savedNote.show(name)
    }

    function isSaved(ref) {
        for (var i = 0; i < app.stations.length; i++)
            if (app.stations[i].ytRef === ref) return true
        return false
    }

    function fmt(sec) { return sec > 0 ? app.fmtTime(sec) : "" }

    Timer { id: debounce; interval: 600; onTriggered: ytp.search() }

    // ---------------------------------------------------------------- pieces
    component SectionTitle: RowLayout {
        property alias text: lbl.text
        property alias actionText: act.text
        signal action()
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Kirigami.Heading { id: lbl; level: 4; font.weight: Font.DemiBold }
        Item { Layout.fillWidth: true }
        QQC2.Label {
            id: act
            visible: text !== ""
            color: Kirigami.Theme.linkColor
            font: Kirigami.Theme.smallFont
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.action() }
        }
    }

    // a song: cover · title · artist — album · time · play / menu
    component SongRow: GlassPanel {
        id: row
        required property var song
        property var list: []           // the list it belongs to (play continues through it)
        property int pos: 0             // place in `list` (not "index": that clashes with the delegate's)
        property string number: ""      // album track number instead of the cover
        readonly property bool current: ytp.playingId === song.id
        Layout.fillWidth: true
        implicitHeight: ytp.gu * 3
        radius: 14
        hovered: rowHover.hovered
        highlighted: current
        accent: app.accent
        HoverHandler { id: rowHover }
        TapHandler {
            onTapped: row.list.length > 1 ? app.playYt(row.list, row.pos, ytp.detail ? (ytp.detail.name || ytp.detail.title) : "")
                                          : ytp.playSong(row.song)
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing * 2
            anchors.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing * 2
            Item {
                Layout.preferredWidth: ytp.gu * 2.2
                Layout.preferredHeight: ytp.gu * 2.2
                StationLogo {
                    anchors.fill: parent
                    visible: row.number === ""
                    logo: row.song.thumb || ""
                    tint: "#e53935"
                    glyph: "♪"
                    radiusRatio: 0.22
                }
                QQC2.Label {
                    anchors.centerIn: parent
                    visible: row.number !== "" && !row.current
                    text: row.number
                    opacity: 0.55
                }
                // playing marker over the cover
                Rectangle {
                    anchors.fill: parent
                    visible: row.current
                    radius: width * 0.22
                    color: Qt.rgba(0, 0, 0, 0.45)
                    Equalizer {
                        anchors.centerIn: parent
                        width: parent.width * 0.6; height: parent.height * 0.5
                        color: "white"
                        bars: 4
                        running: app.isPlaying && ytp.visible
                        level: app.isPlaying ? 1 : 0.15
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft      // mixed Arabic/Latin names line up
                    text: row.song.title
                    font.weight: Font.DemiBold
                    color: row.current ? app.accent : ytp.fg
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft      // mixed Arabic/Latin names line up
                    text: [row.song.artist, row.number === "" ? row.song.album : ""]
                          .filter(function (x) { return x && x !== row.song.title }).join("  ·  ")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }
            QQC2.Label {
                text: ytp.fmt(row.song.duration)
                font: Kirigami.Theme.smallFont
                opacity: 0.5
                visible: text !== "" && ytp.width > ytp.gu * 17
            }
            QQC2.ToolButton {
                icon.name: "overflow-menu"
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: app.t("المزيد")
                QQC2.ToolTip.visible: hovered
                onClicked: songMenu.popup()
                QQC2.Menu {
                    id: songMenu
                    QQC2.MenuItem {
                        text: app.t("تشغيل التالي"); icon.name: "media-playlist-play"
                        onTriggered: app.enqueueYt([row.song], true)
                    }
                    QQC2.MenuItem {
                        text: app.t("إضافة لقائمة التشغيل"); icon.name: "media-playlist-append"
                        onTriggered: app.enqueueYt([row.song], false)
                    }
                    QQC2.MenuItem {
                        text: app.t("راديو مشابه"); icon.name: "media-playlist-shuffle"
                        onTriggered: ytp.playRadio(row.song)
                    }
                    QQC2.MenuItem {
                        visible: ytp.signedIn
                        height: visible ? implicitHeight : 0
                        text: app.t("أعجبني"); icon.name: "emblem-favorite"
                        onTriggered: ytp.like(row.song)
                    }
                    QQC2.MenuSeparator { }
                    QQC2.MenuItem {
                        text: app.t("حفظ كمحطة (راديو مشابه)"); icon.name: "bookmark-new"
                        enabled: !ytp.isSaved("radio:" + row.song.id)
                        onTriggered: ytp.saveStation(row.song.title, row.song.thumb, "radio:" + row.song.id,
                                                     "https://music.youtube.com/watch?v=" + row.song.id + "&list=RDAMVM" + row.song.id,
                                                     app.t("راديو مشابه") + " · " + row.song.artist)
                    }
                }
            }
        }
    }

    // round artist / square album card for horizontal shelves
    component Card: Item {
        id: card
        required property var item
        property bool round: false
        signal picked()
        width: ytp.gu * 5.6
        height: cover.height + texts.implicitHeight + Kirigami.Units.smallSpacing
        StationLogo {
            id: cover
            width: parent.width; height: width
            logo: card.item.thumb || ""
            tint: "#e53935"
            glyph: Presets.glyphFor(card.item.name || card.item.title || "")
            radiusRatio: card.round ? 0.5 : 0.16
            scale: cardMouse.containsMouse ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 140 } }
        }
        ColumnLayout {
            id: texts
            anchors.top: cover.bottom
            anchors.topMargin: Kirigami.Units.smallSpacing
            width: parent.width
            spacing: 0
            QQC2.Label {
                Layout.fillWidth: true
                text: card.item.name || card.item.title
                horizontalAlignment: card.round ? Text.AlignHCenter : Text.AlignLeft
                font.weight: Font.DemiBold
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 1.1
                elide: Text.ElideRight
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: !card.round && text !== ""
                text: card.item.subtitle !== undefined ? card.item.subtitle
                      : [card.item.year, card.item.type].filter(function (x) { return x }).join(" · ")
                font: Kirigami.Theme.smallFont
                opacity: 0.55
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.picked()
        }
    }

    component Shelf: ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: ytp.gu * 9
        orientation: ListView.Horizontal
        spacing: Kirigami.Units.largeSpacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.horizontal: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
    }

    // ---------------------------------------------------------------- layout
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        // header
        RowLayout {
            Layout.fillWidth: true
            GlassButton {
                iconName: app.rtl ? "go-next" : "go-previous"
                toolTip: app.t("رجوع")
                implicitHeight: ytp.gu * 1.7
                onClicked: ytp.goBack()
            }
            Rectangle {
                implicitWidth: ytp.gu * 1.5; implicitHeight: implicitWidth; radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: "#ff5252" }
                    GradientStop { position: 1; color: "#c62828" }
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: parent.width * 0.6; height: width
                    source: "music-note-16th"
                    color: "white"
                    isMask: true
                }
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Kirigami.Heading {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                    text: app.t("يوتيوب ميوزك")
                    level: 3
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                    text: !ytp.ready ? app.t("ابحث واستمع بنفس جمال الراديو")
                        : ytp.view === "queue" ? app.t("قائمة التشغيل")
                        : ytp.view === "account" ? app.t("الحساب")
                        : ytp.view !== "search" && ytp.detail ? (ytp.detail.name || ytp.detail.title || "")
                        : app.t("ابحث واستمع بنفس جمال الراديو")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.55
                    elide: Text.ElideRight
                }
            }
            // account: avatar when signed in
            Item {
                visible: ytp.ready
                implicitWidth: ytp.gu * 1.7; implicitHeight: implicitWidth
                GlassButton {
                    anchors.fill: parent
                    visible: !ytp.signedIn || !ytp.account.photo
                    iconName: "user"
                    filled: ytp.view === "account"
                    accent: app.accent
                    toolTip: ytp.signedIn ? ytp.account.name : app.t("تسجيل الدخول بحساب جوجل (اختياري)")
                    onClicked: ytp.showAccount()
                }
                StationLogo {
                    anchors.fill: parent
                    visible: ytp.signedIn && !!ytp.account.photo
                    logo: ytp.account.photo || ""
                    radiusRatio: 0.5
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        QQC2.ToolTip.text: ytp.account.name || ""
                        QQC2.ToolTip.visible: containsMouse
                        onClicked: ytp.showAccount()
                    }
                }
            }
            GlassButton {
                visible: ytp.ready && app.ytMode && app.ytQueue.length > 0
                iconName: "view-media-playlist"
                text: ytp.width > ytp.gu * 19 ? String(app.ytQueue.length) : ""
                toolTip: app.t("قائمة التشغيل")
                filled: ytp.view === "queue"
                accent: app.accent
                implicitHeight: ytp.gu * 1.7
                onClicked: ytp.showQueue()
            }
        }

        // ---------------- not set up yet ----------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !ytp.ready

            PlasmaComponents.BusyIndicator {
                anchors.centerIn: parent
                visible: !app.ytStatus.checked
                running: visible
            }
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - ytp.gu * 2, ytp.gu * 18)
                visible: app.ytStatus.checked
                spacing: Kirigami.Units.largeSpacing
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: ytp.gu * 4.5; implicitHeight: implicitWidth; radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#ff5252" }
                        GradientStop { position: 1; color: "#b71c1c" }
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.5; height: width
                        source: "music-note-16th"; color: "white"; isMask: true
                    }
                }
                Kirigami.Heading {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    level: 2
                    text: app.t("موسيقى يوتيوب داخل الراديو")
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    text: app.t("ابحث عن أي أغنية أو فنان أو ألبوم واستمع له من هنا. التفعيل ينزّل مكتبتين صغيرتين (ytmusicapi و yt-dlp) داخل مجلد الويدجت فقط، بدون صلاحيات مدير ولا تغيير في النظام.")
                }
                GlassButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: app.ytSetupBusy ? app.t("جاري التفعيل…") : app.t("تفعيل يوتيوب ميوزك")
                    iconName: app.ytSetupBusy ? "" : "download"
                    filled: true
                    accent: "#e53935"
                    enabled: !app.ytSetupBusy
                    onClicked: app.ytSetup(function (r) { setupError.text = r && r.error ? r.error : "" })
                }
                PlasmaComponents.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    visible: app.ytSetupBusy
                    running: visible
                }
                QQC2.Label {
                    id: setupError
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Kirigami.Theme.negativeTextColor
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        // ---------------- search ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ytp.ready && ytp.view === "search"
            spacing: Kirigami.Units.largeSpacing

            Kirigami.SearchField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: app.t("أغنية، فنان، ألبوم…")
                onTextChanged: { ytp.query = text; debounce.restart() }
                onAccepted: { debounce.stop(); ytp.search() }
            }
            Segmented {
                Layout.fillWidth: true
                visible: ytp.query.trim() !== ""
                accent: app.accent
                current: ytp.filter
                model: [
                    { key: "all",     text: app.t("الكل"),     icon: "" },
                    { key: "songs",   text: app.t("أغاني"),    icon: "" },
                    { key: "artists", text: app.t("فنانون"),   icon: "" },
                    { key: "albums",  text: app.t("ألبومات"),  icon: "" }
                ]
                onPicked: function (key) { ytp.filter = key; ytp.search() }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: resultsFlick
                    anchors.fill: parent
                    clip: true
                    contentHeight: resultsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

                    ColumnLayout {
                        id: resultsCol
                        width: resultsFlick.width - Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        // before typing: your library (signed in) and the home feed
                        SectionTitle {
                            visible: ytp.query.trim() === "" && ytp.signedIn && ytp.lib !== null
                            text: app.t("مكتبتي")
                        }
                        Flow {
                            Layout.fillWidth: true
                            visible: ytp.query.trim() === "" && ytp.signedIn && ytp.lib !== null
                            spacing: Kirigami.Units.smallSpacing
                            GlassButton {
                                text: app.t("أغانٍ أعجبتني")
                                iconName: "emblem-favorite"
                                enabled: ytp.lib && ytp.lib.liked.length > 0
                                onClicked: ytp.open("playlist", "LM", { title: app.t("أغانٍ أعجبتني"), thumb: "" })
                            }
                            GlassButton {
                                text: app.t("السجل")
                                iconName: "view-history"
                                enabled: ytp.lib && ytp.lib.history.length > 0
                                onClicked: ytp.showList(app.t("السجل"), ytp.lib.history)
                            }
                        }
                        Shelf {
                            visible: ytp.query.trim() === "" && ytp.signedIn && ytp.lib !== null && ytp.lib.playlists.length > 0
                            model: ytp.lib ? ytp.lib.playlists : []
                            delegate: Card {
                                required property var modelData
                                item: modelData
                                onPicked: ytp.pick(modelData)
                            }
                        }
                        // sign-in hint (optional)
                        GlassPanel {
                            Layout.fillWidth: true
                            visible: ytp.query.trim() === "" && !ytp.signedIn
                            implicitHeight: hintRow.implicitHeight + ytp.gu
                            radius: 16
                            RowLayout {
                                id: hintRow
                                anchors.fill: parent
                                anchors.margins: ytp.gu * 0.5
                                spacing: Kirigami.Units.largeSpacing
                                Kirigami.Icon { source: "user"; implicitWidth: ytp.gu * 1.6; implicitHeight: implicitWidth; opacity: 0.8 }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: app.t("سجّل الدخول بحساب جوجل لتظهر مفضّلاتك واقتراحات على ذوقك. اختياري.")
                                    wrapMode: Text.WordWrap
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.8
                                }
                                GlassButton {
                                    text: app.t("تسجيل الدخول")
                                    onClicked: ytp.showAccount()
                                }
                            }
                        }
                        PlasmaComponents.BusyIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            visible: ytp.query.trim() === "" && ytp.homeLoading && ytp.home.length === 0
                            running: visible
                        }
                        Repeater {
                            model: ytp.query.trim() === "" ? ytp.home : []
                            delegate: ColumnLayout {
                                id: shelf
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                SectionTitle { text: shelf.modelData.title }
                                Shelf {
                                    model: shelf.modelData.items
                                    delegate: Card {
                                        required property var modelData
                                        item: modelData
                                        round: modelData.kind === "artist"
                                        onPicked: ytp.pick(modelData)
                                    }
                                }
                            }
                        }

                        // artists
                        SectionTitle {
                            visible: ytp.filter === "all" && ytp.results.artists.length > 0
                            text: app.t("فنانون")
                            actionText: app.t("الكل")
                            onAction: { ytp.filter = "artists"; ytp.search() }
                        }
                        Shelf {
                            visible: ytp.filter === "all" && ytp.results.artists.length > 0
                            model: ytp.results.artists
                            delegate: Card {
                                required property var modelData
                                item: modelData
                                round: true
                                onPicked: ytp.open("artist", modelData.id, { name: modelData.name, thumb: modelData.thumb })
                            }
                        }

                        // songs
                        SectionTitle {
                            visible: (ytp.filter === "all" || ytp.filter === "songs") && ytp.results.songs.length > 0
                            text: app.t("أغاني")
                            actionText: ytp.filter === "all" ? app.t("الكل") : ""
                            onAction: { ytp.filter = "songs"; ytp.search() }
                        }
                        Repeater {
                            model: (ytp.filter === "all" || ytp.filter === "songs") ? ytp.results.songs : []
                            delegate: SongRow {
                                required property var modelData
                                song: modelData
                            }
                        }

                        // albums
                        SectionTitle {
                            visible: ytp.filter === "all" && ytp.results.albums.length > 0
                            text: app.t("ألبومات")
                            actionText: app.t("الكل")
                            onAction: { ytp.filter = "albums"; ytp.search() }
                        }
                        Shelf {
                            visible: ytp.filter === "all" && ytp.results.albums.length > 0
                            model: ytp.results.albums
                            delegate: Card {
                                required property var modelData
                                item: modelData
                                onPicked: ytp.open("album", modelData.id, { title: modelData.title, thumb: modelData.thumb, artist: modelData.artist })
                            }
                        }

                        // artists / albums as a grid when filtered
                        Flow {
                            Layout.fillWidth: true
                            visible: ytp.filter === "artists" || ytp.filter === "albums"
                            spacing: Kirigami.Units.largeSpacing
                            Repeater {
                                model: ytp.filter === "artists" ? ytp.results.artists : ytp.filter === "albums" ? ytp.results.albums : []
                                delegate: Card {
                                    required property var modelData
                                    item: modelData
                                    round: ytp.filter === "artists"
                                    onPicked: ytp.filter === "artists"
                                              ? ytp.open("artist", modelData.id, { name: modelData.name, thumb: modelData.thumb })
                                              : ytp.open("album", modelData.id, { title: modelData.title, thumb: modelData.thumb, artist: modelData.artist })
                                }
                            }
                        }
                        Item { implicitHeight: Kirigami.Units.largeSpacing }
                    }
                }

                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    running: ytp.loading && ytp.view === "search"
                    visible: running
                }
                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - ytp.gu * 2
                    visible: !ytp.loading && ytp.query.trim() !== "" && (ytp.error !== ""
                             || (ytp.results.songs.length + ytp.results.artists.length + ytp.results.albums.length) === 0)
                    icon.name: ytp.error !== "" ? "network-disconnect" : "edit-find"
                    text: ytp.error !== "" ? ytp.error : app.t("لا توجد نتائج")
                }
            }
        }

        // ---------------- artist / album ----------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ytp.ready && (ytp.view === "artist" || ytp.view === "album" || ytp.view === "playlist" || ytp.view === "list")

            Flickable {
                id: detailFlick
                anchors.fill: parent
                clip: true
                contentHeight: detailCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

                ColumnLayout {
                    id: detailCol
                    width: detailFlick.width - Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing
                    readonly property var d: ytp.detail || ({})
                    readonly property bool isArtist: ytp.view === "artist"
                    readonly property var songs: (isArtist ? d.songs : d.tracks) || []
                    readonly property string ref: ytp.view === "list" ? ""
                        : (isArtist ? "artist:" : ytp.view === "playlist" ? "playlist:" : "album:") + (d.id || "")

                    // hero
                    GlassPanel {
                        Layout.fillWidth: true
                        implicitHeight: hero.implicitHeight + ytp.gu * 1.4
                        radius: 22
                        RowLayout {
                            id: hero
                            anchors.fill: parent
                            anchors.margins: ytp.gu * 0.7
                            spacing: Kirigami.Units.largeSpacing
                            StationLogo {
                                Layout.preferredWidth: ytp.gu * 5.5
                                Layout.preferredHeight: ytp.gu * 5.5
                                logo: detailCol.d.thumb || (detailCol.songs.length ? detailCol.songs[0].thumb : "")
                                tint: "#e53935"
                                glyph: Presets.glyphFor(detailCol.d.name || detailCol.d.title || "")
                                radiusRatio: detailCol.isArtist ? 0.5 : 0.16
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Heading {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    text: detailCol.d.name || detailCol.d.title || ""
                                    level: 2
                                    font.weight: Font.Bold
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    text: detailCol.isArtist ? (detailCol.d.subs || "")
                                        : [detailCol.d.artist, detailCol.d.year, detailCol.d.type].filter(function (x) { return x }).join("  ·  ")
                                    visible: text !== ""
                                    opacity: 0.65
                                    elide: Text.ElideRight
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    GlassButton {
                                        text: app.t("تشغيل")
                                        iconName: "media-playback-start"
                                        filled: true
                                        accent: "#e53935"
                                        enabled: detailCol.songs.length > 0
                                        onClicked: app.playYt(detailCol.songs, 0, detailCol.d.name || detailCol.d.title)
                                    }
                                    GlassButton {
                                        iconName: "media-playlist-shuffle"
                                        toolTip: app.t("تشغيل عشوائي")
                                        enabled: detailCol.songs.length > 1
                                        onClicked: app.playYt(app.shuffled(detailCol.songs), 0, detailCol.d.name || detailCol.d.title)
                                    }
                                    GlassButton {
                                        iconName: ytp.isSaved(detailCol.ref) ? "checkmark" : "bookmark-new"
                                        toolTip: ytp.isSaved(detailCol.ref) ? app.t("محفوظة في محطاتك") : app.t("حفظ كمحطة")
                                        visible: detailCol.ref !== ""
                                        enabled: !!detailCol.d.id && !ytp.isSaved(detailCol.ref)
                                        onClicked: ytp.saveStation(detailCol.d.name || detailCol.d.title, detailCol.d.thumb,
                                                                   detailCol.ref, detailCol.d.playlistUrl || "",
                                                                   (detailCol.isArtist ? app.t("فنان") : ytp.view === "playlist" ? app.t("قائمة تشغيل") : app.t("ألبوم"))
                                                                   + " · " + app.t("يوتيوب ميوزك"))
                                    }
                                }
                            }
                        }
                    }

                    PlasmaComponents.BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        visible: ytp.loading
                        running: visible
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: ytp.error !== ""
                        text: ytp.error
                        color: Kirigami.Theme.negativeTextColor
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    SectionTitle {
                        visible: detailCol.songs.length > 0
                        text: detailCol.isArtist ? app.t("الأغاني") + "  (" + detailCol.songs.length + ")" : app.t("المقاطع")
                        actionText: detailCol.isArtist && detailCol.songs.length > 10
                                    ? (ytp.showAllSongs ? app.t("أقل") : app.t("عرض الكل")) : ""
                        onAction: ytp.showAllSongs = !ytp.showAllSongs
                    }
                    Repeater {
                        model: detailCol.isArtist && !ytp.showAllSongs ? detailCol.songs.slice(0, 10) : detailCol.songs
                        delegate: SongRow {
                            required property var modelData
                            required property int index
                            song: modelData
                            pos: index
                            list: detailCol.songs
                            number: ytp.view === "album" ? String(index + 1) : ""
                        }
                    }

                    SectionTitle {
                        visible: detailCol.isArtist && (detailCol.d.albums || []).length > 0
                        text: app.t("ألبومات")
                    }
                    Shelf {
                        visible: detailCol.isArtist && (detailCol.d.albums || []).length > 0
                        model: detailCol.isArtist ? (detailCol.d.albums || []) : []
                        delegate: Card {
                            required property var modelData
                            item: modelData
                            onPicked: ytp.open("album", modelData.id, { title: modelData.title, thumb: modelData.thumb })
                        }
                    }
                    SectionTitle {
                        visible: detailCol.isArtist && (detailCol.d.singles || []).length > 0
                        text: app.t("أغانٍ منفردة")
                    }
                    Shelf {
                        visible: detailCol.isArtist && (detailCol.d.singles || []).length > 0
                        model: detailCol.isArtist ? (detailCol.d.singles || []) : []
                        delegate: Card {
                            required property var modelData
                            item: modelData
                            onPicked: ytp.open("album", modelData.id, { title: modelData.title, thumb: modelData.thumb })
                        }
                    }
                    Item { implicitHeight: Kirigami.Units.largeSpacing }
                }
            }
        }

        // ---------------- account (optional Google sign-in) ----------------
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ytp.ready && ytp.view === "account"
            clip: true
            contentHeight: accCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

            ColumnLayout {
                id: accCol
                width: parent.width - Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.largeSpacing

                // signed in
                GlassPanel {
                    Layout.fillWidth: true
                    visible: ytp.signedIn
                    implicitHeight: meRow.implicitHeight + ytp.gu * 1.2
                    radius: 20
                    RowLayout {
                        id: meRow
                        anchors.fill: parent
                        anchors.margins: ytp.gu * 0.6
                        spacing: Kirigami.Units.largeSpacing
                        StationLogo {
                            Layout.preferredWidth: ytp.gu * 3.4; Layout.preferredHeight: ytp.gu * 3.4
                            logo: ytp.account.photo || ""
                            glyph: Presets.glyphFor(ytp.account.name || "?")
                            tint: "#e53935"
                            radiusRatio: 0.5
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Kirigami.Heading { Layout.fillWidth: true; level: 3; text: ytp.account.name || ""; elide: Text.ElideRight }
                            QQC2.Label { Layout.fillWidth: true; text: ytp.account.handle || ""; opacity: 0.6; elide: Text.ElideRight; visible: text !== "" }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: ytp.account.method === "browser"
                                      ? app.t("متصل عبر ") + (ytp.browserNames[ytp.account.browser] || ytp.account.browser)
                                      : app.t("متصل عبر ترويسات الطلب")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.5
                            }
                        }
                    }
                }
                GlassButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: ytp.signedIn
                    text: app.t("تسجيل الخروج")
                    iconName: "system-log-out"
                    onClicked: ytp.logout()
                }

                // signed out
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !ytp.signedIn
                    wrapMode: Text.WordWrap
                    text: app.t("تسجيل الدخول اختياري: يضيف أغانيك المفضلة وقوائمك وسجلك واقتراحات على ذوقك. كل شيء يعمل بدونه.")
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !ytp.signedIn
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.65
                    text: app.t("جوجل لا تسمح بتسجيل الدخول من داخل الويدجت، لذلك نستخدم جلستك المفتوحة في متصفحك: سجّل الدخول في music.youtube.com من المتصفح أولًا، ثم اختره هنا. تُحفظ الجلسة على جهازك فقط، ويمكنك تسجيل الخروج في أي وقت.")
                }
                SectionTitle {
                    visible: !ytp.signedIn
                    text: app.t("من متصفحك")
                }
                Repeater {
                    model: ytp.signedIn ? [] : (app.ytStatus.browsers || [])
                    delegate: GlassPanel {
                        id: brow
                        required property string modelData
                        Layout.fillWidth: true
                        implicitHeight: ytp.gu * 2.6
                        radius: 14
                        hovered: bMouse.containsMouse
                        highlighted: ytp.loginBusy === modelData
                        accent: app.accent
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ytp.gu * 0.6
                            anchors.rightMargin: ytp.gu * 0.6
                            Kirigami.Icon {
                                source: { var m = { chrome: "google-chrome", chromium: "chromium", brave: "brave-browser",
                                                    edge: "microsoft-edge", vivaldi: "vivaldi", opera: "opera", firefox: "firefox" }
                                          return m[brow.modelData] || "internet-web-browser" }
                                fallback: "internet-web-browser"
                                implicitWidth: ytp.gu * 1.5; implicitHeight: implicitWidth
                            }
                            QQC2.Label { Layout.fillWidth: true; text: ytp.browserNames[brow.modelData] || brow.modelData }
                            PlasmaComponents.BusyIndicator {
                                visible: ytp.loginBusy === brow.modelData
                                running: visible
                                implicitWidth: ytp.gu * 1.4; implicitHeight: implicitWidth
                            }
                        }
                        MouseArea {
                            id: bMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: ytp.loginBusy === ""
                            onClicked: ytp.loginWith({ browser: brow.modelData })
                        }
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !ytp.signedIn && (app.ytStatus.browsers || []).length === 0
                    text: app.t("لم نجد متصفحًا مدعومًا. استخدم الطريقة اليدوية بالأسفل.")
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                }

                // manual: paste request headers
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !ytp.signedIn
                    text: (ytp.showHeaders ? "▾ " : "▸ ") + app.t("طريقة يدوية (لصق ترويسات الطلب)")
                    color: Kirigami.Theme.linkColor
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ytp.showHeaders = !ytp.showHeaders }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !ytp.signedIn && ytp.showHeaders
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    text: app.t("في المتصفح: افتح music.youtube.com وأنت مسجّل، اضغط F12 ← Network، اختر أي طلب باسم browse، ثم انسخ Request Headers والصقها هنا.")
                }
                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: ytp.gu * 6
                    visible: !ytp.signedIn && ytp.showHeaders
                    QQC2.TextArea {
                        id: headersBox
                        placeholderText: "cookie: …\nx-goog-authuser: 0\n…"
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
                GlassButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !ytp.signedIn && ytp.showHeaders
                    text: ytp.loginBusy === "headers" ? app.t("جاري التحقق…") : app.t("تسجيل الدخول")
                    filled: true
                    accent: "#e53935"
                    enabled: ytp.loginBusy === "" && headersBox.text.trim() !== ""
                    onClicked: ytp.loginWith({ headers: headersBox.text })
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: ytp.loginError !== ""
                    text: ytp.loginError
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.WordWrap
                }
                Item { implicitHeight: Kirigami.Units.largeSpacing }
            }
        }

        // ---------------- queue ----------------
        ListView {
            id: queueList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ytp.ready && ytp.view === "queue"
            clip: true
            spacing: Kirigami.Units.smallSpacing
            model: ytp.view === "queue" ? app.ytQueue : []
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar { }
            onVisibleChanged: if (visible) positionViewAtIndex(app.ytIndex, ListView.Center)
            header: QQC2.Label {
                width: queueList.width
                bottomPadding: Kirigami.Units.smallSpacing
                text: (app.ytName ? app.ytName + "  ·  " : "") + app.ytQueue.length + app.t(" أغنية")
                opacity: 0.6
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }
            delegate: GlassPanel {
                id: qrow
                required property var modelData
                required property int index
                readonly property bool current: index === app.ytIndex
                width: queueList.width - Kirigami.Units.smallSpacing
                height: ytp.gu * 2.8
                radius: 14
                highlighted: current
                accent: app.accent
                hovered: qHover.hovered
                opacity: index < app.ytIndex ? 0.55 : 1
                HoverHandler { id: qHover }
                TapHandler { onTapped: app.jumpYt(qrow.index) }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                    anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                    spacing: Kirigami.Units.smallSpacing * 2
                    StationLogo {
                        Layout.preferredWidth: ytp.gu * 2
                        Layout.preferredHeight: ytp.gu * 2
                        logo: qrow.modelData.thumb || ""
                        tint: "#e53935"
                        glyph: "♪"
                        radiusRatio: 0.22
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft      // mixed Arabic/Latin names line up
                            text: qrow.modelData.title
                            font.weight: qrow.current ? Font.Bold : Font.Normal
                            color: qrow.current ? app.accent : ytp.fg
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft      // mixed Arabic/Latin names line up
                            text: qrow.modelData.artist || ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                            elide: Text.ElideRight
                        }
                    }
                    QQC2.Label {
                        text: ytp.fmt(qrow.modelData.duration)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.5
                    }
                }
            }
        }
    }

    // "saved" toast
    GlassPanel {
        id: savedNote
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.largeSpacing
        width: Math.min(parent.width - ytp.gu * 2, noteLabel.implicitWidth + ytp.gu * 2)
        height: ytp.gu * 2.2
        radius: height / 2
        highlighted: true
        accent: app.accent
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        function show(name, plain) {
            noteLabel.text = plain ? name : "✓  " + app.t("أضيفت إلى محطاتك: ") + name
            opacity = 1; noteTimer.restart()
        }
        QQC2.Label { id: noteLabel; anchors.centerIn: parent; width: Math.min(implicitWidth, savedNote.width - ytp.gu); elide: Text.ElideRight }
        Timer { id: noteTimer; interval: 2600; onTriggered: savedNote.opacity = 0 }
    }
}
