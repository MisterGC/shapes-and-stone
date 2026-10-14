import QtQuick

// The travellers the knights freed from the stone, at the camps (issue
// #159). A traveller freed in a run that left toward the exit sits by the
// fire of every later camp of that run; a special one (Balance.deep
// .specials) joins the camps for good: kept with this machine's record,
// it sits by every camp's fire after that, across runs, with its comfort
// at the fire. Alone this node decides; in a session the host's run and
// specials are the party's (the session properties "freed" and
// "specials"), and a joiner keeps a special freed in the party with its
// own record too, as it keeps the party's descent. Tonight's freed are
// those this screen saw go on since the game started, in a session since
// it was hosted or joined: the title and the fallen screen show them and
// the specials with the camps. The figures are made of figure in room
// (extra adds props to those they are made with)
QtObject {
    id: freed

    property Component figure: null
    property Item room: null
    property var extra: props => ({})
    // The game's Session and the store the record is kept in
    property var link: null
    property var store: null
    // This node's knight, for a special's line at the camp
    property var knight: null

    // This node's: the run's freed and tonight's ([{key, kind, outcome,
    // special}], key the level and the cell, "level:gx,gy") and the
    // specials with the camps (their ids)
    property var run: []
    property var tonight: []
    property var joined: []
    readonly property bool _joiner: link !== null && link.connected && !link.isHost
    // The run's freed and the specials every screen shows: in a session
    // the host's
    readonly property var runShown: _joiner
        ? (link.freedRun && link.freedRun.seed === link.runSeed ? link.freedRun.run : []) : run
    readonly property var joinedShown: _joiner ? (link.hostSpecials || []) : joined
    readonly property var specials: joinedShown.map(id => specialOf(id)).filter(sp => sp !== null)
    // The freed of the run sitting at the camps: those that left toward
    // the exit, not a special (it sits as one of the specials)
    readonly property var campRun: runShown.filter(f => (f.outcome === "leaving" || f.outcome === "fleeing")
                                                        && !f.special)
    // "Freed tonight: 2 lost travellers, a miner" ("" none), and "With the
    // camps: Maren the healer" ("" none)
    readonly property string tonightLine: {
        if (tonight.length === 0) return ""
        let lost = tonight.filter(f => f.kind === "lost" && !f.special).length
        let miners = tonight.filter(f => f.kind === "miner" && !f.special).length
        let parts = []
        if (lost > 0) parts.push(lost === 1 ? "a lost traveller" : lost + " lost travellers")
        if (miners > 0) parts.push(miners === 1 ? "a miner" : miners + " miners")
        for (let f of tonight.filter(f => f.special)) {
            let sp = specialOf(f.special)
            if (sp) parts.push(sp.name)
        }
        return "Freed tonight: " + parts.join(", ")
    }
    readonly property string joinedLine: specials.length === 0 ? ""
        : "With the camps: " + specials.map(sp => sp.name + " " + sp.title).join(", ")

    // The figures by the fire of this camp, and the specials among them
    property var figures: []

    function specialOf(id) {
        return Balance.deep.specials.find(sp => sp.id === id) || null
    }
    // The specials a petrified traveller may still be: none with the
    // camps nor freed this run
    function candidates() {
        let taken = joinedShown.concat(runShown.filter(f => f.special).map(f => f.special))
        return Balance.deep.specials.filter(sp => taken.indexOf(sp.id) < 0)
    }
    // The product of what the specials with the camps give to what
    // ("heal", "mana" or "light"), 1 for none
    function comfort(what) {
        let k = 1
        for (let sp of specials) if (typeof sp[what] === "number") k *= sp[what]
        return k
    }

    function load() {
        let ids = []
        try { ids = JSON.parse(store.get("specials", "[]")) } catch (err) { ids = [] }
        joined = Array.isArray(ids) ? ids.filter(id => specialOf(id) !== null) : []
    }
    // A run starts: none freed in it yet
    function startRun() {
        run = []
        _publishRun()
    }
    // A session hosted, joined or left starts its own evening
    function startEvening() {
        tonight = []
    }
    // Host: the run's freed and the specials, for every node
    function publish() {
        _publishRun()
        _publishSpecials()
    }
    // The traveller key of kind went on as outcome; special its id or "".
    // decides: this node decides how the freed go on (alone or the host).
    // A special joins the camps for good on every node
    function goneOn(key, kind, outcome, special, decides) {
        let entry = { key: key, kind: kind, outcome: outcome, special: special || "" }
        let put = (list) => list.filter(f => f.key !== key).concat([entry])
        tonight = put(tonight)
        if (decides) {
            run = put(run)
            _publishRun()
        }
        if (special && joined.indexOf(special) < 0) {
            joined = joined.concat([special])
            store.set("specials", JSON.stringify(joined))
            console.log("[CampFreed]", specialOf(special).name, "joins the camps for good")
            _publishSpecials()
        }
    }
    function _publishRun() {
        if (link && link.connected && link.isHost) link.publishFreed({ seed: link.runSeed, run: run })
    }
    function _publishSpecials() {
        if (link && link.connected && link.isHost) link.publishSpecials(joined)
    }

    // The camp is built: the specials and the run's freed sit round fire
    // (a Campfire), on spots where onFloor(x, y) is true, clear of the
    // points avoid ([{x, y}]); the spots start at an angle drawn from
    // rand, the level's stream for them. The fire gives the specials'
    // comfort. The figures made
    function seat(fire, rand, onFloor, avoid) {
        let cfg = Balance.deep.camp, made = []
        figures = []
        fire.healRate = Balance.campfire.healPerSecond * comfort("heal")
        fire.manaRate = Balance.campfire.manaPerSecond * comfort("mana")
        fire.lightRadius = Balance.camp.fireLight * comfort("light")
        let sitters = specials.map(sp => ({ kind: sp.kind, special: sp.id }))
            .concat(campRun.map(f => ({ kind: f.kind, special: "" })))
            .slice(0, cfg.most)
        if (sitters.length === 0) return made
        let fx = fire.xWu + fire.widthWu / 2, fy = fire.yWu - fire.heightWu / 2
        let start = rand() * 2 * Math.PI
        let taken = avoid.slice()
        for (let i = 0; i < cfg.angles && made.length < sitters.length; i++) {
            let a = start + i * 2 * Math.PI / cfg.angles
            let x = fx + cfg.ring * Math.cos(a), y = fy + cfg.ring * Math.sin(a)
            if (!onFloor(x, y) || taken.some(p => Math.hypot(p.x - x, p.y - y) < cfg.clear)) continue
            taken.push({ x: x, y: y })
            let who = sitters[made.length]
            let size = 2, foot = y - 0.35
            let f = figure.createObject(room, Object.assign({
                cxWu: x, cyWu: foot + size / 2 - 0.05, sizeWu: size, footXWu: x, footYWu: foot,
                cell: "camp" + made.length, kind: who.kind, special: who.special,
                seated: true, freed: true, colour: 1, seed: (i + 1) / (cfg.angles + 1),
                facing: x < fx ? 1 : -1
            }, extra({})))
            if (f) made.push(f)
        }
        figures = made
        console.log("[CampFreed]", made.length, "freed by the fire:", specials.length, "specials,",
                    campRun.length, "of the run")
        return made
    }
    // The camp goes; its figures go with the level's objects
    function clear() {
        figures = []
    }

    // A special by the fire says its line while a knight stands near it
    property Timer _talk: Timer {
        interval: 200
        repeat: true
        running: freed.figures.length > 0
        onTriggered: {
            let k = freed.knight
            for (let f of freed.figures) {
                if (!f || f.special === "") continue
                let near = k && !k.fallen
                           && Math.hypot(k.xWu + 0.5 - f.footXWu, k.yWu - 0.5 - f.footYWu) <= Balance.deep.camp.sayReach
                f.saying = near ? freed.specialOf(f.special).campLine : ""
            }
        }
    }
}
