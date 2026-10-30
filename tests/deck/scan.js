// The Steam Deck bench's look at the texts on screen (issue #202): one
// expression, traced by clayrender on every frame in Game.qml's context.
// Every visible text on screen counts - the HUD's, a menu's, and a world
// text inside the window - except the DEV menu, which only the sandbox
// shows. It answers with every text on screen, the texts smaller than
// minPx, those elided or cut by a line limit, and the HUD's and the
// menus' texts that reach past the window's edge.
(function () {
    const minPx = 12
    const W = world.width, H = world.height
    const out = { texts: [], small: [], cut: [], outside: [] }

    function isText(it) {
        return it.text !== undefined && it.font !== undefined && it.color !== undefined
            && it.horizontalAlignment !== undefined
    }
    function name(it) { return String(it.text).replace(/\s+/g, " ").slice(0, 60) }

    function check(it, inWorld) {
        // The text's painted box in window coordinates
        const pw = it.paintedWidth !== undefined ? it.paintedWidth : it.contentWidth
        const ph = it.paintedHeight !== undefined ? it.paintedHeight : it.contentHeight
        let x0 = 0, y0 = 0
        if (it.horizontalAlignment === Text.AlignRight) x0 = it.width - pw
        else if (it.horizontalAlignment === Text.AlignHCenter) x0 = (it.width - pw) / 2
        if (it.verticalAlignment === Text.AlignBottom) y0 = it.height - ph
        else if (it.verticalAlignment === Text.AlignVCenter) y0 = (it.height - ph) / 2
        const a = it.mapToItem(null, x0, y0), b = it.mapToItem(null, x0 + pw, y0 + ph)
        const left = Math.min(a.x, b.x), right = Math.max(a.x, b.x)
        const top = Math.min(a.y, b.y), bottom = Math.max(a.y, b.y)
        // A world text off the camera is not on screen
        if (right <= 0 || left >= W || bottom <= 0 || top >= H) {
            if (!inWorld) out.outside.push(name(it))
            return
        }
        out.texts.push(name(it))
        const scale = ph > 0 ? (bottom - top) / ph : 1
        const px = (it.fontInfo ? it.fontInfo.pixelSize : it.font.pixelSize) * scale
        if (px < minPx - 0.01) out.small.push(name(it) + " (" + px.toFixed(1) + " px)")
        if (it.truncated) out.cut.push(name(it))
        if (!inWorld && (left < -1 || top < -1 || right > W + 1 || bottom > H + 1))
            out.outside.push(name(it))
    }

    function walk(it, opacity, inWorld) {
        if (!it || !it.visible || it.objectName === "devMenu") return
        const op = opacity * it.opacity
        if (op < 0.05) return
        const deep = inWorld || it === world.room
        if (isText(it) && String(it.text).trim() !== "") check(it, deep)
        const kids = it.children
        for (let i = 0; i < kids.length; i++) walk(kids[i], op, deep)
    }
    walk(world, 1, false)
    return out
})()
