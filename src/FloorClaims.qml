import QtQuick

// Things on the floor that the host owns and gives to the first knight
// that claims them: gold where an enemy died, a fallen knight's pouch.
// Alone this node's knight takes one at once. In a session the host
// spawns each as a replicated object, every node claims those its own
// knight reaches, and the host gives one to the first claim it gets and
// despawns it, so it is taken once, by one knight. One for each kind of
// drop: its component and the room it lies in (extra adds props of the
// kind to those it is made with), the grant made of a drop (grantOf, its
// id added) and taken by this node's knight (take), and the session's
// calls for the kind (claimOf, despawnOf, grantTo) on link
QtObject {
    id: claims

    property Component component: null
    property Item room: null
    // The game's Session
    property var link: null
    property var extra: props => ({})
    property var grantOf: drop => ({})
    property var take: grant => {}
    property var claimOf: objectId => {}
    property var despawnOf: objectId => {}
    property var grantTo: (nodeId, grant) => {}

    // The drops on the floor, and those of the session by their id
    property var drops: []
    property var _byId: ({})

    // A drop with props, the replicated object objectId ("" alone); one
    // made already for objectId is that one
    function make(props, objectId) {
        objectId = objectId || ""
        if (objectId !== "" && _byId[objectId]) return _byId[objectId]
        let drop = component.createObject(room, Object.assign({}, props, extra(props), { objectId: objectId }))
        if (!drop) return null
        drops.push(drop)
        if (objectId !== "") _byId[objectId] = drop
        return drop
    }
    // The replicated object went on every node
    function remove(objectId) {
        let drop = _byId[objectId]
        if (!drop) return
        delete _byId[objectId]
        forget(drop)
    }
    function forget(drop) {
        drops = drops.filter(d => d !== drop)
        try { drop.destroy() } catch (err) {}
    }
    // This node's knight reached drop: its own alone, claimed from the
    // host in a session
    function claim(drop) {
        if (!drop || drop.claimed) return
        if (drop.objectId === "") {
            take(grantOf(drop))
            forget(drop)
        } else if (link.connected) {
            drop.claimed = true
            claimOf(drop.objectId)
        }
    }
    // Every drop within reach wu of (x, y)
    function claimNear(x, y, reach) {
        for (let drop of drops.slice())
            if (drop && Math.hypot(drop.xWu - x, drop.yWu - y) <= reach) claim(drop)
    }
    // Host: a node's knight reached a drop; the first claim takes it, a
    // later one finds it gone
    function give(nodeId, objectId) {
        let drop = _byId[objectId]
        if (!drop || !link.isHost) return
        let grant = Object.assign({ id: objectId }, grantOf(drop))
        despawnOf(objectId)
        if (nodeId === link.nodeId) take(grant)
        else grantTo(nodeId, grant)
    }
    // The level goes: the host's drops go on every node with their
    // despawn, a joiner's when that arrives, the others at once
    function clear() {
        for (let drop of drops.slice()) {
            if (!drop) continue
            if (drop.objectId !== "" && link.connected) {
                if (link.isHost) despawnOf(drop.objectId)
                continue
            }
            try { drop.destroy() } catch (err) {}
        }
        drops = drops.filter(d => d && d.objectId !== "" && link.connected && _byId[d.objectId] === d)
    }
}
