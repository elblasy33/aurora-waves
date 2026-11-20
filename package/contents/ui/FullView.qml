import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../code/presets.js" as Presets

Item {
    id: full

    property var app

    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: Kirigami.Units.gridUnit * 34
    Layout.minimumWidth: Kirigami.Units.gridUnit * 13
    Layout.minimumHeight: Kirigami.Units.gridUnit * 11

    // ---- responsive modes ----
    readonly property real gu: Kirigami.Units.gridUnit
    readonly property bool narrow: width < gu * 19
    // wide: card on one side, stations on the other
    readonly property bool wide: width >= gu * 34 && height >= gu * 17
    // short: horizontal (compact) now-playing card
    readonly property bool horizontalCard: !wide && height < gu * 30
    // tiny: only the card
    readonly property bool mini: !wide && height < gu * 19
    readonly property real cardWidth: wide ? Math.max(gu * 16, Math.min(gu * 26, width * 0.42)) : width
    readonly property real logoSize: horizontalCard ? (mini ? gu * 3.6 : gu * 4.4)
                                   : Math.round(Math.max(gu * 5, Math.min(gu * 9, cardWidth * 0.34)))

    LayoutMirroring.enabled: app.rtl
    LayoutMirroring.childrenInherit: true

    focus: true
    Keys.onSpacePressed: app.toggle()
    Keys.onLeftPressed: app.step(app.rtl ? 1 : -1)
    Keys.onRightPressed: app.step(app.rtl ? -1 : 1)
    Keys.onUpPressed: app.setVolume(app.volume + 5)
    Keys.onDownPressed: app.setVolume(app.volume - 5)

    readonly property var cfg: Plasmoid.configuration
    readonly property var cur: app.current
    readonly property color fg: Kirigami.Theme.textColor
    readonly property bool anim: cfg.animations
    readonly property bool curIsLocal: app.kindOf(cur) !== "stream" || yt
    // a YouTube Music song is on: the card shows the song instead of the station
    readonly property bool yt: app.ytMode && app.ytTrack !== null
    readonly property var visibleStations: {
        if (app.groupFilter === "" || !cfg.showGroups) return app.stations
        return app.stations.filter(function (s) { return (s.group || "") === app.groupFilter })
    }

    function editStation(id) {
        app.editing = true
        editorPage.openForm(app.indexOfStation(id))
    }

    Aurora {
        anchors.fill: parent
        anchors.margins: -Kirigami.Units.largeSpacing
        visible: full.cfg.auroraEnabled
        color: app.accent
        image: full.yt ? app.ytTrack.thumb : (full.cur ? app.logoUrl(full.cur.logo) : "")
        running: full.visible && app.expanded && full.anim
        strength: full.cfg.auroraStrength * (app.wantPlaying ? 1.0 : 0.6)
    }

    // =================== PLAYER PAGE ===================
    GridLayout {
        id: playerPage
        anchors.fill: parent
        columns: full.wide ? 2 : 1
        columnSpacing: Kirigami.Units.largeSpacing * 1.5
        rowSpacing: Kirigami.Units.largeSpacing

        opacity: app.editing ? 0 : 1
        visible: opacity > 0
        transform: Translate { x: app.editing ? -40 : 0; Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 220 } }

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            Layout.columnSpan: full.wide ? 2 : 1
            visible: !full.mini
            Kirigami.Icon { source: Plasmoid.icon; Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium; Layout.preferredHeight: width }
            Kirigami.Heading { text: app.t("أمواج أورورا"); level: 3; font.weight: Font.DemiBold }
            QQC2.Label {
                text: app.stations.length + app.t(" محطة")
                visible: !full.narrow
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
            Item { Layout.fillWidth: true }
            GlassButton {
                iconName: "music-note-16th"
                toolTip: app.t("يوتيوب ميوزك")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                filled: full.yt
                accent: app.accent
                onClicked: { editorPage.discovering = false; editorPage.checking = false; app.editing = true; editorPage.ytOpen = true }
            }
            GlassButton {
                iconName: "configure"
                toolTip: app.t("الإعدادات")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: Plasmoid.internalAction("configure").trigger()
            }
            GlassButton {
                iconName: "document-edit"
                toolTip: app.t("إدارة المحطات")
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                onClicked: app.editing = true
            }
        }

        // ---- now playing card ----
        GlassPanel {
            Layout.fillWidth: !full.wide
            Layout.fillHeight: full.wide || full.mini
            Layout.preferredWidth: full.wide ? full.cardWidth : -1
            Layout.alignment: Qt.AlignTop
            Layout.preferredHeight: nowCol.implicitHeight + Kirigami.Units.gridUnit * (full.horizontalCard ? 1.2 : 1.6)
            radius: full.horizontalCard ? 20 : 26
            visible: full.cur !== null || full.yt

            GridLayout {
                id: nowCol
                columns: full.horizontalCard ? 2 : 1
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing * 2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Kirigami.Units.gridUnit * (full.horizontalCard ? 0.6 : 0.8)

                Item {
                    Layout.fillWidth: !full.horizontalCard
                    Layout.preferredWidth: full.horizontalCard ? full.logoSize + 12 : -1
                    Layout.preferredHeight: full.logoSize + (full.horizontalCard ? 12 : 34)
                    Layout.alignment: Qt.AlignVCenter

                    OnAirRing {
                        anchors.centerIn: parent
                        width: full.logoSize; height: full.logoSize
                        color: app.accent
                        cornerRatio: bigLogo.radiusRatio
                        active: app.wantPlaying && !app.isPaused && full.anim
                        busy: app.isBusy
                    }
                    StationLogo {
                        id: bigLogo
                        anchors.centerIn: parent
                        width: full.logoSize; height: full.logoSize
                        logo: full.yt ? (app.ytTrack.thumb || "icon:music-note-16th")
                              : app.previewing ? app.previewLogo : (full.cur ? (full.cur.logo || "") : "")
                        tint: full.yt ? "#e53935" : app.previewing ? app.previewColor : (full.cur ? full.cur.color : "gray")
                        glyph: full.yt ? "♪" : app.previewing ? Presets.glyphFor(app.previewName) : (full.cur ? (full.cur.glyph || "") : "")
                        opacity: app.isPaused ? 0.75 : 1
                        scale: logoMouse.pressed ? 0.95 : (app.isPlaying ? 1.0 : 0.96)
                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                        MouseArea {
                            id: logoMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.toggle()
                        }
                    }
                }

                ColumnLayout {
                    id: info
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * (full.horizontalCard ? 1 : 2)

                    Kirigami.Heading {
                        Layout.fillWidth: true
                        horizontalAlignment: full.horizontalCard ? Text.AlignLeft : Text.AlignHCenter
                        text: full.yt ? app.ytTrack.title
                              : app.previewing ? "🎧 " + app.previewName : (full.cur ? full.cur.name : "")
                        level: full.horizontalCard ? 2 : 1
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: full.horizontalCard ? Text.AlignLeft : Text.AlignHCenter
                        visible: text !== ""
                        text: {
                            if (full.yt)
                                return [app.ytTrack.artist, app.ytTrack.album].filter(function (x) {
                                    return x && x !== app.ytTrack.title }).join("  ·  ")
                            if (app.localPlayback && app.wantPlaying) {
                                var t = app.tracks > 1 ? app.t("مقطع ") + app.track + app.t(" من ") + app.tracks : ""
                                var a = app.trackArtist && full.cur && app.trackArtist !== full.cur.name ? app.trackArtist : ""
                                return [a, t].filter(function (x) { return x !== "" }).join("  ·  ")
                            }
                            return full.cur && full.cur.subtitle ? full.cur.subtitle : ""
                        }
                        opacity: 0.65
                        elide: Text.ElideRight
                    }

                    // status line
                    RowLayout {
                        Layout.alignment: full.horizontalCard ? Qt.AlignLeft : Qt.AlignHCenter
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            visible: app.isPlaying && !full.curIsLocal
                            implicitWidth: liveRow.implicitWidth + 14
                            implicitHeight: liveRow.implicitHeight + 6
                            radius: height / 2
                            color: Qt.rgba(1, 0.23, 0.19, 0.18)
                            border.width: 1
                            border.color: Qt.rgba(1, 0.23, 0.19, 0.6)
                            Row {
                                id: liveRow
                                anchors.centerIn: parent
                                spacing: 5
                                Rectangle {
                                    width: 7; height: 7; radius: 4; color: "#ff3b30"
                                    anchors.verticalCenter: parent.verticalCenter
                                    SequentialAnimation on opacity {
                                        running: app.isPlaying && full.anim; loops: Animation.Infinite
                                        NumberAnimation { to: 0.2; duration: 700 }
                                        NumberAnimation { to: 1.0; duration: 700 }
                                    }
                                }
                                QQC2.Label { text: app.t("مباشر"); font.pixelSize: Kirigami.Theme.smallFont.pixelSize; font.bold: true; color: "#ff6b60" }
                            }
                        }
                        PlasmaComponents.BusyIndicator {
                            visible: app.isBusy
                            running: visible
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        QQC2.Label {
                            text: app.statusText()
                            opacity: 0.85
                            color: app.playState === "error" ? Kirigami.Theme.negativeTextColor : full.fg
                            elide: Text.ElideRight
                            Layout.maximumWidth: info.width * 0.9
                        }
                    }

                    Equalizer {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: info.width * 0.7
                        width: info.width * 0.7
                        height: 26
                        visible: !full.horizontalCard && full.cfg.showEqualizer && !(app.localPlayback && app.duration > 0 && app.wantPlaying)
                        color: app.accent
                        running: app.wantPlaying && !app.isPaused && full.visible && full.anim
                        level: app.isPlaying ? 1.0 : (app.isBusy ? 0.35 : 0.1)
                    }

                    // progress for local files
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: full.horizontalCard ? 0 : Kirigami.Units.gridUnit
                        Layout.rightMargin: full.horizontalCard ? 0 : Kirigami.Units.gridUnit
                        visible: app.localPlayback && app.duration > 0 && app.wantPlaying
                        spacing: 2
                        LayoutMirroring.enabled: false
                        LayoutMirroring.childrenInherit: true
                        Rectangle {
                            id: progressBar
                            Layout.fillWidth: true
                            implicitHeight: seekArea.containsMouse || seekArea.pressed ? 8 : 6; radius: height / 2
                            color: Qt.rgba(full.fg.r, full.fg.g, full.fg.b, 0.12)
                            Behavior on height { NumberAnimation { duration: 120 } }
                            readonly property real shown: seekArea.pressed ? seekArea.frac
                                                          : Math.min(1, app.position / Math.max(1, app.duration))
                            Rectangle {
                                height: parent.height; radius: height / 2
                                width: parent.width * progressBar.shown
                                color: app.accent
                                Behavior on width { enabled: !seekArea.pressed; NumberAnimation { duration: 900 } }
                            }
                            Rectangle {
                                visible: seekArea.containsMouse || seekArea.pressed
                                width: 14; height: 14; radius: 7
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.width * progressBar.shown - width / 2
                                color: "white"
                                border.width: 3; border.color: app.accent
                            }
                            // click / drag to seek
                            MouseArea {
                                id: seekArea
                                anchors.fill: parent
                                anchors.topMargin: -8; anchors.bottomMargin: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                property real frac: 0
                                function at(x) { return Math.max(0, Math.min(1, x / width)) }
                                onPressed: function (m) { frac = at(m.x) }
                                onPositionChanged: function (m) { if (pressed) frac = at(m.x) }
                                onReleased: app.seek(frac * app.duration)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: app.fmtTime(seekArea.pressed ? seekArea.frac * app.duration : app.position)
                                font: Kirigami.Theme.smallFont; opacity: 0.6
                            }
                            Item { Layout.fillWidth: true }
                            QQC2.Label { text: app.fmtTime(app.duration); font: Kirigami.Theme.smallFont; opacity: 0.6 }
                        }
                    }

                    QQC2.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: app.streamInfo
                        visible: !full.horizontalCard && full.cfg.showStreamInfo && app.isPlaying && text !== ""
                        font: Kirigami.Theme.smallFont
                        opacity: 0.45
                    }

                }

                // controls: under the logo+info, spanning the card; transport and volume
                // sit side by side when the card is horizontal and wide enough
                GridLayout {
                    Layout.columnSpan: full.horizontalCard ? 2 : 1
                    Layout.fillWidth: true
                    columns: full.horizontalCard && !full.narrow ? 2 : 1
                    columnSpacing: Kirigami.Units.largeSpacing * 2
                    rowSpacing: Kirigami.Units.smallSpacing

                    // transport
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: full.horizontalCard ? 0 : Kirigami.Units.smallSpacing
                        spacing: full.horizontalCard ? Kirigami.Units.largeSpacing : Kirigami.Units.gridUnit
                        LayoutMirroring.enabled: false     // media controls read left-to-right everywhere
                        LayoutMirroring.childrenInherit: true

                        GlassButton {
                            iconName: "media-skip-backward"
                            toolTip: app.t("المحطة السابقة")
                            enabled: app.stations.length > 1
                            onClicked: app.step(-1)
                        }
                        GlassButton {
                            readonly property bool active: app.isPlaying || app.isBusy
                            iconName: !active ? "media-playback-start"
                                    : (full.curIsLocal ? "media-playback-pause" : "media-playback-stop")
                            filled: true
                            accent: app.accent
                            implicitHeight: Kirigami.Units.gridUnit * (full.horizontalCard ? 2.3 : 3)
                            iconScale: 0.6
                            toolTip: !active ? app.t("تشغيل") : (full.curIsLocal ? app.t("إيقاف مؤقت") : app.t("إيقاف"))
                            onClicked: app.toggle()
                        }
                        GlassButton {
                            iconName: "media-skip-forward"
                            toolTip: app.t("المحطة التالية")
                            enabled: app.stations.length > 1
                            onClicked: app.step(1)
                        }
                    }

                    // volume
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: full.horizontalCard ? 0 : Kirigami.Units.gridUnit
                        Layout.rightMargin: full.horizontalCard ? 0 : Kirigami.Units.gridUnit
                        Kirigami.Icon {
                            source: app.volume === 0 ? "audio-volume-muted"
                                  : app.volume < 35 ? "audio-volume-low"
                                  : app.volume < 70 ? "audio-volume-medium" : "audio-volume-high"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: width
                            MouseArea {
                                anchors.fill: parent
                                property int saved: 70
                                onClicked: {
                                    if (app.volume > 0) { saved = app.volume; app.setVolume(0) }
                                    else app.setVolume(saved)
                                }
                            }
                        }
                        GlassSlider {
                            Layout.fillWidth: true
                            accent: app.accent
                            value: app.volume
                            onMoved: app.setVolume(value)
                        }
                        QQC2.Label {
                            text: app.volume + "%"
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.8
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }

        // ---- stations: below the card, or beside it when wide ----
        ColumnLayout {
            id: stationsCol
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !full.mini || app.stations.length === 0
            spacing: Kirigami.Units.largeSpacing

            // ---- welcome / empty state ----
            ColumnLayout {
                visible: app.stations.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing
                Item { Layout.fillHeight: true }
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                    Layout.preferredHeight: Layout.preferredWidth
                    source: Plasmoid.icon
                }
                Kirigami.Heading {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    level: 2
                    text: app.t("أهلًا بك في أمواج أورورا")
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    Layout.rightMargin: Kirigami.Units.gridUnit
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                    text: app.t("اكتشف إذاعات بلدك والعالم، أو أضف رابطًا أو ملفاتك الموسيقية.")
                }
                Flow {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: parent.width
                    spacing: Kirigami.Units.largeSpacing
                    GlassButton {
                        text: app.t("اكتشف المحطات")
                        iconName: "edit-find"
                        filled: true
                        accent: Kirigami.Theme.highlightColor
                        onClicked: { app.editing = true; editorPage.discovering = true }
                    }
                    GlassButton {
                        text: app.t("إضافة محطة")
                        iconName: "list-add"
                        onClicked: { app.editing = true; editorPage.openForm(-2) }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // ---- group filter chips ----
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.7
                visible: full.cfg.showGroups && app.groups.length > 0
                contentWidth: chipRow.implicitWidth
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: chipRow
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: [""].concat(app.groups)
                        delegate: GlassPanel {
                            id: chip
                            required property string modelData
                            readonly property bool selected: app.groupFilter === modelData
                            width: chipLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                            height: Kirigami.Units.gridUnit * 1.6
                            radius: height / 2
                            highlighted: selected
                            accent: app.accent
                            hovered: chipMouse.containsMouse
                            QQC2.Label {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: chip.modelData === "" ? app.t("الكل") : chip.modelData
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                font.weight: chip.selected ? Font.Bold : Font.Normal
                            }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.groupFilter = chip.modelData
                            }
                        }
                    }
                }
            }

            // ---- station grid / list ----
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: app.stations.length > 0
                clip: true
                model: full.visibleStations
                readonly property bool listMode: full.cfg.viewMode === 1
                readonly property int cols: listMode ? 1
                    : (full.cfg.gridColumns > 0 ? full.cfg.gridColumns
                       : (width > Kirigami.Units.gridUnit * 26 ? 4 : (width > Kirigami.Units.gridUnit * 15 ? 3 : 2)))
                cellWidth: Math.floor(width / cols)
                cellHeight: listMode ? Kirigami.Units.gridUnit * 3.2 : Kirigami.Units.gridUnit * 6
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: full.cur !== null && full.cur.id === modelData.id && !full.yt   // not while a song plays

                    width: grid.cellWidth
                    height: grid.cellHeight
                    scale: tileMouse.pressed ? 0.96 : (tileMouse.containsMouse && !grid.listMode ? 1.03 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    GlassPanel {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing / (grid.listMode ? 2 : 1)
                        radius: grid.listMode ? 14 : 18
                        highlighted: tile.isCurrent && app.wantPlaying && !app.previewing
                        hovered: tileMouse.containsMouse
                        accent: tile.modelData.color

                        // grid layout
                        Column {
                            visible: !grid.listMode
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.smallSpacing * 2
                            spacing: Kirigami.Units.smallSpacing
                            StationLogo {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Kirigami.Units.gridUnit * 2.6
                                height: width
                                logo: tile.modelData.logo || ""
                                tint: tile.modelData.color
                                glyph: tile.modelData.glyph || ""
                            }
                            QQC2.Label {
                                width: parent.width
                                text: tile.modelData.name
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                font.weight: tile.isCurrent ? Font.Bold : Font.Normal
                            }
                        }

                        // list layout
                        RowLayout {
                            visible: grid.listMode
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.largeSpacing
                            anchors.rightMargin: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            StationLogo {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
                                Layout.preferredHeight: Layout.preferredWidth
                                logo: tile.modelData.logo || ""
                                tint: tile.modelData.color
                                glyph: tile.modelData.glyph || ""
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                QQC2.Label { text: tile.modelData.name; font.weight: tile.isCurrent ? Font.Bold : Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                QQC2.Label {
                                    text: tile.modelData.subtitle || tile.modelData.group || ""
                                    visible: text !== ""
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            Kirigami.Icon {
                                source: { var k = app.kindOf(tile.modelData); return k === "folder" ? "folder-music" : k === "playlist" ? "view-media-playlist" : k === "file" ? "audio-x-generic" : "network-wireless" }
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: width
                                opacity: 0.4
                            }
                        }

                        Equalizer {
                            anchors { top: parent.top; left: parent.left; margins: 8 }
                            width: 14; height: 12; bars: 3
                            color: tile.modelData.color
                            visible: tile.isCurrent && app.isPlaying && !app.previewing
                            running: visible && full.anim
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function (mouse) {
                            if (mouse.button === Qt.RightButton) { tileMenu.popup(); return }
                            if (tile.isCurrent && app.wantPlaying) app.toggle()
                            else app.play(tile.modelData.id)
                        }
                        onPressAndHold: tileMenu.popup()
                    }

                    QQC2.Menu {
                        id: tileMenu
                        QQC2.MenuItem { text: app.t("تشغيل"); icon.name: "media-playback-start"; onTriggered: app.play(tile.modelData.id) }
                        QQC2.MenuItem { text: app.t("تعديل…"); icon.name: "document-edit"; onTriggered: full.editStation(tile.modelData.id) }
                        QQC2.MenuItem { text: app.t("نسخ المحطة"); icon.name: "edit-copy"; onTriggered: editorPage.duplicate(app.indexOfStation(tile.modelData.id)) }
                        QQC2.MenuSeparator { }
                        QQC2.MenuItem { text: app.t("حذف"); icon.name: "edit-delete"; onTriggered: editorPage.remove(app.indexOfStation(tile.modelData.id)) }
                    }
                }
            }
        }
    }

    // =================== EDITOR PAGE ===================
    StationEditor {
        id: editorPage
        anchors.fill: parent
        app: full.app
        opacity: app.editing ? 1 : 0
        visible: opacity > 0
        transform: Translate { x: app.editing ? 0 : 40; Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }
}
