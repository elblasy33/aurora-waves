import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "../code/presets.js" as Presets
import "../code/i18n.js" as I18n

PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration

    // ---------- language ----------
    readonly property string lang: I18n.resolve(cfg.language, Qt.locale().name)
    readonly property bool rtl: lang === "ar"
    function t(s) { return I18n.tr(lang, s) }

    // ---------- data ----------
    property var stations: []
    property string currentId: cfg.lastStation
    readonly property var current: findStation(currentId, stations)
    readonly property color accent: (cfg.useStationAccent && current) ? current.color : Kirigami.Theme.highlightColor
    readonly property var groups: {
        var g = []
        for (var i = 0; i < stations.length; i++) {
            var name = stations[i].group || ""
            if (name !== "" && g.indexOf(name) < 0) g.push(name)
        }
        return g
    }
    property string groupFilter: ""

    // ---------- playback state (mirrors radiod) ----------
    property string playState: "stopped"   // stopped | connecting | playing | paused | error
    property bool daemonAlive: false
    property string trackTitle: ""
    property string trackArtist: ""
    property string streamInfo: ""
    property real position: 0
    property real duration: 0
    property bool localPlayback: false
    property int track: 0
    property int tracks: 0
    property int volume: cfg.volume
    property double volumeTouched: 0
    property bool editing: false

    readonly property bool wantPlaying: playState === "connecting" || playState === "playing" || playState === "paused"
    readonly property bool isPlaying: playState === "playing"
    readonly property bool isBusy: playState === "connecting"
    readonly property bool isPaused: playState === "paused"

    readonly property string scriptPath: decodeURIComponent(
        Qt.resolvedUrl("../code/radioctl.py").toString().replace(/^file:\/\//, ""))

    // ---------- plasmoid ----------
    Plasmoid.icon: cfg.customIcon || "radio"
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.status: wantPlaying ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: previewing ? previewName : (current ? current.name : t("إذاعات مصر"))
    toolTipSubText: statusText() + "  ·  🔊 " + volume + "%"
    hideOnWindowDeactivate: !editing   // keep popup open while a file dialog is up
    switchWidth: Kirigami.Units.gridUnit * 13
    switchHeight: Kirigami.Units.gridUnit * 18

    compactRepresentation: CompactView { app: root }
    fullRepresentation: FullView { app: root }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.wantPlaying ? t("إيقاف") : t("تشغيل")
            icon.name: root.wantPlaying ? "media-playback-stop" : "media-playback-start"
            onTriggered: root.wantPlaying ? root.stop() : root.play(null)
        },
        PlasmaCore.Action {
            text: t("المحطة التالية")
            icon.name: "media-skip-forward"
            onTriggered: root.step(1)
        },
        PlasmaCore.Action {
            text: t("إدارة المحطات…")
            icon.name: "document-edit"
            onTriggered: { root.editing = true; root.expanded = true }
        }
    ]

    // ---------- helpers ----------
    function findStation(id, list) {
        if (!list || list.length === 0) return null
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i]
        return list[0]
    }

    function indexOfStation(id) {
        for (var i = 0; i < stations.length; i++)
            if (stations[i].id === id) return i
        return -1
    }

    // image url for a logo string (no icon/glyph); used by the ambient backdrop
    function logoUrl(logo) {
        if (!logo || logo.indexOf("icon:") === 0) return ""
        if (logo.indexOf("pkg:") === 0) return Qt.resolvedUrl("../images/logos/" + logo.slice(4))
        return logo
    }

    function kindOf(st) {
        if (!st) return "stream"
        if (st.kind) return st.kind
        var u = (st.url || "").toLowerCase()
        if (u.indexOf("file://") !== 0 && u.indexOf("/") !== 0) return "stream"
        if (/\.(m3u8?|pls)$/.test(u)) return "playlist"
        return "file"
    }

    function fmtTime(s) {
        s = Math.max(0, Math.floor(s))
        var m = Math.floor(s / 60), h = Math.floor(m / 60)
        var ss = (s % 60 < 10 ? "0" : "") + (s % 60)
        return h > 0 ? h + ":" + ((m % 60) < 10 ? "0" : "") + (m % 60) + ":" + ss : m + ":" + ss
    }

    function statusText() {
        switch (playState) {
        case "connecting": return t("جاري الاتصال…")
        case "playing":
            if (trackTitle !== "") return trackTitle
            return localPlayback ? t("تشغيل من ملفاتك") : t("على الهواء مباشرة")
        case "paused":     return t("متوقف مؤقتًا")
        case "error":      return t("تعذّر التشغيل — اضغط للمحاولة مرة أخرى")
        default:           return t("متوقف")
        }
    }

    function loadStations() {
        var raw = cfg.stations
        var list = null
        if (raw && raw.length > 0) {
            try { list = JSON.parse(raw) } catch (e) { list = null }
        }
        if (!Array.isArray(list)) {
            list = Presets.defaults(lang)
            cfg.stations = JSON.stringify(list)
        }
        stations = list
    }

    function saveStations(list) {
        stations = list.slice()
        cfg.stations = JSON.stringify(stations)
        if (indexOfStation(currentId) < 0 && stations.length > 0)
            currentId = stations[0].id
        if (groupFilter !== "" && groups.indexOf(groupFilter) < 0) groupFilter = ""
        artStage.renderAll()
    }

    // what the daemon needs to know about each station
    function daemonStations() {
        var out = []
        for (var i = 0; i < stations.length; i++) {
            var s = stations[i]
            out.push({ id: s.id, name: s.name, subtitle: s.subtitle || "", url: s.url,
                       kind: kindOf(s), shuffle: !!s.shuffle, art: artStage.artFor(s) })
        }
        return out
    }

    // ---------- process bridge ----------
    property var callbacks: ({})

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    readonly property string sourcesPath: scriptPath.replace(/radioctl\.py$/, "sources.py")

    function exec(script, args, cb) {
        var cmd = "python3 -I " + shq(script) + " " + args
        if (cb) callbacks[cmd] = cb
        executable.connectSource(cmd)
    }
    function run(args, cb) { exec(scriptPath, args, cb) }

    // discovery / logo helpers; cb receives parsed JSON (or {error})
    function runSources(cmd, arg, cb) {
        exec(sourcesPath, cmd + " " + shq(arg), function (out) {
            var r
            try { r = JSON.parse(out) } catch (e) { r = { error: "bad reply" } }
            if (cb) cb(r)
        })
    }

    // listen to something that is not (yet) a saved station
    property string previewName: ""
    property string previewLogo: ""
    property string daemonCurrentId: ""
    readonly property bool previewing: daemonCurrentId === "preview" && wantPlaying

    property string previewColor: Presets.palette[0]

    function colorForName(name) {
        var h = 0
        for (var i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
        return Presets.palette[h % Presets.palette.length]
    }

    function preview(name, url, kind, shuffle, logo) {
        name = name || t("تجربة")
        logo = logo || ""
        var list = daemonStations()
        // a plain image logo can be used as cover right away; the glass render replaces it
        var quickArt = /^(https?|file):\/\//.test(logo) ? logo : ""
        list.push({ id: "preview", name: name, url: url, kind: kind || "stream",
                    shuffle: !!shuffle, art: quickArt })
        previewName = name
        previewLogo = logo
        previewColor = colorForName(name)
        daemonCurrentId = "preview"
        playState = "connecting"
        send({ cmd: "play", id: "preview", stations: list, volume: volume })
        artStage.renderOne({ id: "preview", logo: logo, color: previewColor, glyph: Presets.glyphFor(name) },
                           function (art) { root.send({ cmd: "art", id: "preview", art: art }) })
    }

    function send(req) {
        req.mpris = cfg.mprisEnabled
        req.appName = t("إذاعات مصر")
        req.liveText = t("بث مباشر")
        run(shq(JSON.stringify(req)), function (out) {
            try { root.handleStatus(JSON.parse(out)) } catch (e) { }
        })
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            var out = (data["stdout"] || "").trim()
            disconnectSource(source)
            var cb = root.callbacks[source]
            if (cb) {
                delete root.callbacks[source]
                cb(out)
            }
        }
    }

    // ---------- actions ----------
    function play(id) {
        if (id !== undefined && id !== null) {
            currentId = id
            cfg.lastStation = id
        }
        if (!current) return
        playState = "connecting"
        daemonCurrentId = current.id
        trackTitle = ""
        streamInfo = ""
        send({ cmd: "play", id: current.id, stations: daemonStations(), volume: volume })
    }

    function stop() {
        playState = "stopped"
        trackTitle = ""
        streamInfo = ""
        send({ cmd: "stop" })
    }

    function toggle() {
        if (!daemonAlive || playState === "stopped" || playState === "error") { play(null); return }
        send({ cmd: "toggle", stations: daemonStations(), volume: volume })
    }

    function step(delta) {
        if (stations.length === 0) return
        var i = indexOfStation(current ? current.id : "")
        play(stations[(i + delta + stations.length) % stations.length].id)
    }

    function setVolume(v) {
        v = Math.max(0, Math.min(100, Math.round(v)))
        if (v === volume) return
        volume = v
        volumeTouched = Date.now()
        volumeCommit.restart()
    }

    Timer {
        id: volumeCommit
        interval: 150
        onTriggered: {
            root.cfg.volume = root.volume
            if (root.daemonAlive) root.send({ cmd: "volume", v: root.volume })
        }
    }

    function handleStatus(s) {
        daemonAlive = !!s.daemon
        if (!s.daemon) {
            if (playState !== "error") playState = "stopped"
            return
        }
        if (s.error) return
        playState = s.state
        daemonCurrentId = s.currentId || ""
        if (s.currentId && s.currentId !== currentId && indexOfStation(s.currentId) >= 0) {
            currentId = s.currentId          // e.g. changed by media keys / visualizer
            cfg.lastStation = s.currentId
        }
        trackTitle = s.title || ""
        trackArtist = s.artist || ""
        localPlayback = !!s.local
        position = s.pos || 0
        duration = s.duration || 0
        track = s.track || 0
        tracks = s.tracks || 0
        streamInfo = (s.codec ? s.codec.toUpperCase() : "")
                   + (s.bitrate ? " · " + Math.round(s.bitrate / 1000) + " kbps" : "")
        if (Date.now() - volumeTouched > 2000 && s.volume !== undefined && s.volume !== volume) {
            volume = s.volume
            cfg.volume = s.volume
        }
    }

    Timer {
        id: poll
        interval: (root.expanded || root.wantPlaying) ? 1000 : 4000
        repeat: true
        running: root.daemonAlive || root.expanded
        triggeredOnStart: true
        onTriggered: root.send({ cmd: "status" })
    }

    // ---------- MPRIS cover art: render each logo to a PNG ----------
    Item {
        id: artStage
        x: -4000
        width: 256
        height: 256

        property string artDir: ""
        property var done: ({})      // id -> key of the rendered file
        property var queue: []
        property var job: null

        function keyFor(s) {
            var str = (s.logo || "") + "|" + s.color + "|" + (s.glyph || "") + "|" + root.cfg.logoShape
            var h = 5381
            for (var i = 0; i < str.length; i++) h = ((h * 33) ^ str.charCodeAt(i)) >>> 0
            return h.toString(36)
        }
        function pathFor(s) { return artDir + "/" + s.id + "-" + keyFor(s) + ".png" }
        function artFor(s) {
            if (artDir !== "" && done[s.id] === keyFor(s)) return "file://" + pathFor(s)
            var u = root.logoUrl(s.logo)
            return u.toString().indexOf("file://") === 0 ? u.toString() : ""
        }
        function renderAll() {
            if (artDir === "") return
            var q = []
            for (var i = 0; i < root.stations.length; i++)
                if (done[root.stations[i].id] !== keyFor(root.stations[i])) q.push(root.stations[i])
            // keep one-off jobs (previews) that are still waiting
            queue = q.concat(queue.filter(function (j) { return !!j.cb }))
            if (!job) next()
        }
        // render a single cover now and hand its file url to cb
        function renderOne(st, cb) {
            if (artDir === "") return
            var j = JSON.parse(JSON.stringify(st))
            j.cb = cb
            queue = queue.filter(function (q) { return q.id !== j.id }).concat([j])
            if (!job) next()
        }
        property bool stationJobs: false
        function next() {
            if (queue.length === 0) {
                job = null
                if (stationJobs && root.daemonAlive) root.send({ cmd: "sync", stations: root.daemonStations() })
                stationJobs = false
                return
            }
            job = queue[0]
            queue = queue.slice(1)
            if (!job.cb) stationJobs = true
            artLogo.logo = job.logo || ""
            artLogo.tint = job.color
            artLogo.glyph = job.glyph || ""
            grabDelay.waited = 0
            grabDelay.restart()
        }

        StationLogo { id: artLogo; anchors.fill: parent }

        Timer {
            id: grabDelay
            interval: 250
            property int waited: 0
            onTriggered: {
                // give remote logos (favicons) up to ~4s to arrive before capturing
                if (artLogo.imageUrl !== "" && !artLogo.hasImage && waited < 4000) {
                    waited += interval
                    restart()
                    return
                }
                var s = artStage.job
                var ok = artLogo.grabToImage(function (result) {
                    var path = artStage.pathFor(s)
                    if (result.saveToFile(path)) {
                        if (s.cb) s.cb("file://" + path)
                        else {
                            var d = artStage.done
                            d[s.id] = artStage.keyFor(s)
                            artStage.done = d
                        }
                    }
                    artStage.next()
                }, Qt.size(256, 256))
                if (!ok) artStage.next()
            }
        }
    }

    Connections {
        target: root.cfg
        function onLogoShapeChanged() { artStage.renderAll() }
        function onMprisEnabledChanged() { if (root.daemonAlive) root.send({ cmd: "sync" }) }
    }

    Component.onCompleted: {
        loadStations()
        if (indexOfStation(currentId) < 0 && stations.length > 0)
            currentId = stations[0].id
        run("--init", function (out) {
            try { artStage.artDir = JSON.parse(out).artDir } catch (e) { }
            artStage.renderAll()
        })
        // adopt a daemon that is already running (e.g. after plasmashell restart)
        run(shq(JSON.stringify({ cmd: "status" })), function (out) {
            var s = {}
            try { s = JSON.parse(out) } catch (e) { }
            root.handleStatus(s)
            if (!s.daemon && root.cfg.resumeOnStart) root.play(null)
        })
    }
}
