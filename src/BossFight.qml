import QtQuick

// The Hollow Warden's fight (Balance.boss, issue #274): its room's gates,
// its waking, its phase 2's adds and floor zones, its fall, and what
// every screen shows of it - the name banner, the HP bar and the victory
// banner. Game builds the room and the Warden (setUp, or beginArena for
// the dojo's boss room) and steps it on the physics steps (step).
//
// stage is "" where there is no boss, "waiting" until every knight still
// standing is in the room, "fight" from the moment its gates shut, and
// "beaten" once the Warden fell. Alone the game owns the fight; in a
// session the host does - it wakes the Warden, brings the adds, opens the
// zones and owns the gates - and keeps it as the session property "boss"
// ({seed, level, stage, zones}), so every screen, one joining later too,
// shuts and opens its gates, shows the banners and draws the zones. A
// zone hurts the knight of the screen that sees it hurt, as a trap does,
// and the victory heals each screen's own knight.
Item {
    id: fight

    property var game: null
    property var session: null

    // The boss room, {x, y, w, h} in cells, null where there is none, and
    // whether it is the dojo's fight room, which has no gates
    property var room: null
    property bool arena: false
    // The Warden's appearance, 0 at the first boss depth
    property int appearance: 0
    property string stage: ""
    // The Warden on this screen, and its phase as last seen
    property var warden: null
    property int phase: 1
    property int wardenHp: 0
    property int wardenMaxHp: 1
    // The gates (BossGate), and the zones under way, {id, x, y, at}: x, y
    // their centre in wu, at the moment on the fight's clock they hurt
    property var gates: []
    property var zones: []
    property var _zoneItems: ({})
    property var _judged: ({})
    property real _clock: 0
    property real _nextZone: -1
    property int _zoneCount: 0
    // Seconds into the fight, on the physics clock, and since the Warden
    // fell: the banners show on it, so a pause holds them
    property real fightSeconds: 0
    property real wonSeconds: -1
    // Adds called so far, and the zones opened, for a bench
    property int addsCalled: 0
    property int zonesOpened: 0
    // The zones that hurt this node's knight, and how much
    property int zoneHits: 0

    signal began()
    signal won()

    readonly property bool fighting: stage === "fight"

    function _alive(e) { return !!e && e.destroyed === false }
    function _owns() { return !session || !session.connected || session.isHost }
    // The fight's clock: the session's, in seconds, so every screen's
    // zones hurt at the same moment; alone the physics clock
    function now() { return session && session.connected ? session.now() / 1000 : _clock }

    Component { id: gateComponent; BossGate {} }
    Component { id: zoneComponent; BossZone {} }

    // A boss room of the dungeon at appearance: its gates on edges,
    // [{gx, gy, nx, ny, exit}] - the corridor's cell, the step from it
    // into the room, and whether it is the exit stairs' shaft
    function setUp(r, edges, n) {
        clear()
        room = r
        arena = false
        appearance = n
        let cs = game.cellSize, thick = 0.35
        let list = []
        for (let e of edges) {
            let cx = (e.gx + 0.5) * cs + e.nx * (cs / 2 - thick / 2)
            let cy = (e.gy + 0.5) * cs + e.ny * (cs / 2 - thick / 2)
            let g = gateComponent.createObject(game.room, {
                cell: e.gx + "," + e.gy, cxWu: cx, cyWu: cy, across: e.nx !== 0,
                lengthWu: cs, thickWu: thick, exit: e.exit === true, shut: e.exit === true,
                pixelPerUnit: Qt.binding(() => game.pixelPerUnit),
                world: game.physics,
                categories: game.catWall,
                collidesWith: game.catPlayer | game.catEnemy | game.catProjectile
            })
            if (g) list.push(g)
        }
        gates = list
        stage = "waiting"
        _applySession()
    }
    // The dojo's boss room: the fight room, no gates; the fight begins
    // on the next step
    function beginArena(r, n) {
        clear()
        room = r
        arena = true
        appearance = n
        stage = "waiting"
    }
    function clear() {
        for (let g of gates) if (g) g.destroy()
        gates = []
        for (let id in _zoneItems) if (_zoneItems[id]) _zoneItems[id].destroy()
        _zoneItems = ({})
        _judged = ({})
        zones = []
        room = null
        arena = false
        stage = ""
        warden = null
        phase = 1
        _clock = 0
        _nextZone = -1
        fightSeconds = 0
        addsCalled = 0
        zonesOpened = 0
        zoneHits = 0
        wonSeconds = -1
    }

    // Whether (x, y), wu, lies in the room, margin wu inside its walls
    function inside(x, y, margin) {
        if (!room) return false
        let cs = game.cellSize, m = margin === undefined ? 0.5 : margin
        return x >= room.x * cs + m && x <= (room.x + room.w) * cs - m
            && y >= room.y * cs + m && y <= (room.y + room.h) * cs - m
    }
    function _allInside() {
        let here = game.knightsHere()
        return here.length > 0 && here.every(k => inside(k.x, k.y))
    }

    // Each physics step
    function step(dt) {
        if (stage === "") return
        _clock += dt
        if (!_alive(warden)) warden = game.enemies.find(e => _alive(e) && e.boss) || null
        if (_alive(warden)) {
            phase = warden.phase
            wardenHp = warden.hp
            wardenMaxHp = Math.max(1, warden.maxHp)
        }
        if (stage === "fight") fightSeconds += dt
        if (stage === "beaten") wonSeconds += dt
        if (_owns()) {
            if (stage === "waiting" && _alive(warden) && _allInside()) _setStage("fight")
            if (stage === "fight" && phase === 2) _openZones()
        }
        _stepZones()
    }

    // The stage moves on, here and, from the host, on every screen
    function _setStage(s) {
        if (stage === s) return
        _show(s)
        _publish()
    }
    // What a stage does on this screen
    function _show(s) {
        stage = s
        let ways = s === "fight", exitShut = s !== "beaten"
        for (let g of gates) g.shut = g.exit ? exitShut : ways
        if (s === "fight") {
            if (_alive(warden) && !warden.remote) warden.dormant = false
            fightSeconds = 0
            console.log("[BossFight] The Warden's room shuts:", Balance.boss.name)
            began()
        } else if (s === "beaten") {
            for (let id in _zoneItems) if (_zoneItems[id]) _zoneItems[id].destroy()
            _zoneItems = ({})
            zones = []
            wonSeconds = 0
            _heal()
            console.log("[BossFight] The Warden falls")
            won()
        }
    }
    // Every knight healed to full HP and mana, a fallen one risen: each
    // screen its own
    function _heal() {
        let p = game.player
        if (!p) return
        if (p.fallen && game._rise) game._rise("boss")
        p.hp = p.maxHp
        p.mana = p.maxMana
    }

    // Host: the Warden's HP passed a mark (Enemy._bossMarks): its phase 2
    // with the first adds, or the second wave
    function mark(enemy, what) {
        if (!_owns() || stage === "") return
        if (what === "phase") {
            _nextZone = now() + Balance.boss.zone.every / 2
            _callAdds(enemy)
        } else if (what === "wave") {
            _callAdds(enemy)
        }
    }
    // Balance.boss.adds weak grunts out of the floor round the Warden,
    // inside the room
    function _callAdds(enemy) {
        let n = Balance.boss.adds, cs = game.cellSize
        let cx = enemy.centreXWu, cy = enemy.centreYWu
        for (let i = 0; i < n; i++) {
            let a = Math.PI / 2 + i * 2 * Math.PI / n
            let x = cx + Math.cos(a) * 2.6, y = cy + Math.sin(a) * 2.6
            if (room) {
                x = Math.max(room.x * cs + 1, Math.min((room.x + room.w) * cs - 1, x))
                y = Math.max(room.y * cs + 1, Math.min((room.y + room.h) * cs - 1, y))
            }
            game.spawnRing(x, y, Balance.boss.coreColor)
            game.spawnEnemy(x - 0.4, y + 0.4, 0, "grunt", game.partyKnights)
            addsCalled++
        }
    }
    // Host: the Warden fell: its gold, the gates open, the victory
    function fell(enemy) {
        if (!_owns() || stage === "") return
        let b = Balance.boss, total = b.gold + b.goldGrow * appearance
        if (!arena) {
            let each = Math.max(1, Math.round(total / b.drops))
            for (let i = 0; i < b.drops; i++) {
                let a = i * 2 * Math.PI / b.drops, r = 0.5 + 0.35 * (i % 3)
                game._spawnGold(enemy.centreXWu + Math.cos(a) * r, enemy.centreYWu + Math.sin(a) * r, each)
            }
        }
        _setStage("beaten")
    }

    // Host: every zone.every seconds a zone under each knight standing in
    // the room
    function _openZones() {
        let z = Balance.boss.zone, t = now()
        if (_nextZone < 0) _nextZone = t + z.every / 2
        if (t < _nextZone) return
        _nextZone = t + z.every
        let list = zones.filter(q => q.at + z.linger > t)
        for (let k of game.knightsHere()) {
            if (!inside(k.x, k.y, 0)) continue
            list.push({ id: "z" + (++_zoneCount), x: Math.round(k.x * 100) / 100,
                        y: Math.round(k.y * 100) / 100, at: Math.round((t + z.warn) * 1000) / 1000 })
            zonesOpened++
        }
        zones = list
        _publish()
    }
    function zoneDamage() {
        return Balance.boss.zone.damage + Balance.boss.zone.grow * appearance
    }
    // Every screen: each zone's ring closes on the fight's clock; as it
    // closes the floor hurts this node's knight where it stands in it,
    // then it fades
    function _stepZones() {
        let z = Balance.boss.zone, t = now(), keep = []
        for (let q of zones) {
            let item = _zoneItems[q.id]
            if (t > q.at + z.linger) {
                if (item) item.destroy()
                delete _zoneItems[q.id]
                continue
            }
            keep.push(q)
            if (!item) {
                item = zoneComponent.createObject(game.room, {
                    zoneId: q.id, xWu: q.x, yWu: q.y, radiusWu: z.radius,
                    pixelPerUnit: Qt.binding(() => game.pixelPerUnit),
                    ringParent: game.fx && game.glowParent ? game.glowParent() : null
                })
                _zoneItems[q.id] = item
            }
            if (!item) continue
            item.warn = Math.max(0, Math.min(1, 1 - (q.at - t) / z.warn))
            item.burst = t >= q.at ? Math.max(0, 1 - (t - q.at) / z.linger) : 0
            if (t >= q.at && !_judged[q.id]) {
                _judged[q.id] = true
                _judge(q)
            }
        }
        if (keep.length !== zones.length) zones = keep
    }
    function _judge(q) {
        let p = game.player
        if (!p || p.fallen) return
        let dx = p.xWu + p.widthWu / 2 - q.x, dy = p.yWu - p.heightWu / 2 - q.y
        if (Math.sqrt(dx * dx + dy * dy) > Balance.boss.zone.radius) return
        let result = p.takeTrapDamage(zoneDamage())
        if (result === "hit") zoneHits++
        console.log("[BossFight] A zone under the knight:", result)
    }

    // ---- in a session ----
    function _publish() {
        if (!session || !session.connected || !session.isHost) return
        session.publishBoss({ seed: session.runSeed, level: game.levelIndex, stage: stage,
                              zones: zones })
    }
    // A joiner: the host's fight as it says
    function _applySession() {
        let v = session ? session.boss : null
        if (!v || !session.connected || session.isHost || stage === "" || arena) return
        if (v.seed !== session.runSeed || v.level !== game.levelIndex) return
        if (v.stage !== stage && v.stage !== "") _show(v.stage)
        zones = v.zones || []
    }
    readonly property var _sessionBoss: session ? session.boss : null
    on_SessionBossChanged: _applySession()

    // ---- what it shows ----
    // A banner t seconds into its show of length seconds: in over fade,
    // out over fade at its end
    function _bannerAt(t, length) {
        let fade = 0.3
        if (t < 0 || t > length) return 0
        return Math.min(1, t / fade, (length - t) / fade)
    }
    // The name banner as the room shuts
    Text {
        id: nameBanner
        objectName: "bossBanner"
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.2
        visible: opacity > 0
        opacity: fight.stage === "fight" ? fight._bannerAt(fight.fightSeconds, Balance.boss.banner) : 0
        text: Balance.boss.name.toUpperCase()
        color: "#E8C35A"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 42
        font.bold: true
        font.letterSpacing: 4
        Text {
            anchors.top: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Depth " + (fight.game ? fight.game.depth : 0)
            color: "#DDDDDD"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 18
            font.bold: true
        }
    }
    // Its HP while it stands, a notch where its phase 2 begins
    Item {
        id: bar
        objectName: "bossBar"
        visible: fight.stage === "fight" && fight._alive(fight.warden)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 54
        width: Math.min(560, parent.width * 0.6)
        height: 34
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: Balance.boss.name
            color: "#E8D9B0"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 15
            font.bold: true
            font.letterSpacing: 2
        }
        Rectangle {
            id: barBack
            anchors.bottom: parent.bottom
            width: parent.width
            height: 12
            color: "#1A1416"
            border.color: "#000000"
            border.width: 2
            Rectangle {
                x: 2
                y: 2
                height: parent.height - 4
                width: (parent.width - 4) * Math.max(0, fight.wardenHp / fight.wardenMaxHp)
                color: fight.phase === 2 ? Balance.boss.coreColor : "#B8402E"
                Behavior on width { NumberAnimation { duration: 120 } }
            }
            Rectangle {
                x: (parent.width - 4) * Balance.boss.phaseAt + 1
                y: 0
                width: 2
                height: parent.height
                color: "#E8D9B0"
                opacity: 0.8
            }
        }
    }
    // The victory banner
    Text {
        id: victoryBanner
        objectName: "victoryBanner"
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.2
        visible: opacity > 0
        opacity: fight.stage === "beaten" ? fight._bannerAt(fight.wonSeconds, Balance.boss.victory) : 0
        text: "VICTORY"
        color: "#F2D68A"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 48
        font.bold: true
        font.letterSpacing: 6
        Text {
            anchors.top: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: Balance.boss.name + " falls"
            color: "#DDDDDD"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 18
            font.bold: true
        }
    }
}
