import QtQuick
import Box2D
import Clayground.Common
import Clayground.World
import Clayground.Physics
import Clayground.GameController
import Clayground.Sound

ClayWorld2d {
    id: world

    // World configuration (fit world to viewport)
    pixelPerUnit: 55
    gravity: Qt.point(0, 0)  // Top-down, no gravity
    timeStep: 1/60.0
    anchors.fill: parent
    focus: true

    // Dark background behind the world
    Rectangle { parent: world; anchors.fill: parent; color: "#1a1a2e"; z: -1 }

    // Dungeon audio
    Music {
        id: dungeonAmbience
        source: "assets/dungeon_ambience.mp3"
        volume: 0.4
        loop: true
        Component.onCompleted: play()
    }

    Music {
        id: dungeonMusic
        source: "assets/dungeon_music.mp3"
        volume: 0.3
        loop: true
        Component.onCompleted: play()
    }

    Sound {
        id: impactSound
        source: "assets/punch_hitting.wav"
        volume: 0.7
    }

    Sound {
        id: dashSound
        source: "assets/dash.wav"
        volume: 0.6
    }

    function playImpact() {
        impactSound.play()
    }

    Sound {
        id: deathBurstSound
        source: "assets/burst.wav"
        volume: 0.7
    }

    Sound {
        id: swordSwingSound
        source: "assets/sword_swing.wav"
        volume: 0.5
    }

    function playDash() {
        dashSound.play()
    }

    function playSwordSwing() {
        swordSwingSound.play()
    }

    function playDeathBurst() {
        deathBurstSound.play()
    }

    // Apply screen shake via transform on room
    transform: Translate { x: _shakeOffsetX; y: _shakeOffsetY }

    // World bounds (in world units) - portrait orientation
    xWuMax: 100
    yWuMax: 100

    // Debug visualization
    debugPhysics: false
    property bool debugBehavior: false
    property bool debugMechanics: false
    property bool fightRoomActive: false
    property real _fightRoomCx: 0
    property real _fightRoomCy: 0

    canvas.showDebugInfo: false

    // Screen shake
    property real _shakeIntensity: 0
    property real _shakeOffsetX: 0
    property real _shakeOffsetY: 0

    Timer {
        id: shakeTimer
        interval: 30
        repeat: true
        running: _shakeIntensity > 0.5
        onTriggered: {
            _shakeOffsetX = (Math.random() * 2 - 1) * _shakeIntensity
            _shakeOffsetY = (Math.random() * 2 - 1) * _shakeIntensity
            _shakeIntensity *= 0.7
            if (_shakeIntensity <= 0.5) {
                _shakeOffsetX = 0
                _shakeOffsetY = 0
                _shakeIntensity = 0
            }
        }
    }

    function shake(intensity) {
        _shakeIntensity = Math.max(_shakeIntensity, intensity)
    }

    // Game state
    property var player: null
    property var enemies: []
    property var dungeonObjects: []
    property int entranceGridX: 0
    property int exitGridX: 0
    property int masterSeed: -1   // -1 = random on first run
    property int levelIndex: 0
    property var rng: null
    components: []

    // Collision categories
    readonly property int catWall: Box.Category1
    readonly property int catPlayer: Box.Category2
    readonly property int catEnemy: Box.Category3

    Component.onCompleted: {
        console.log("[Game] Component.onCompleted - width:", width, "height:", height)
        forceActiveFocus()
    }

    // Wait for valid size before generating dungeon
    onWidthChanged: {
        if (width > 0 && height > 0 && !player) {
            console.log("[Game] Size ready - width:", width, "height:", height)
            console.log("[Game] pixelPerUnit:", pixelPerUnit)
            generateDungeon()
        }
    }

    // Mouse input: aiming + attack + shield (also handles WASM focus)
    MouseArea {
        id: mouseInput
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: (mouse) => {
            world.forceActiveFocus()
            if (!player) return
            if (mouse.button === Qt.LeftButton) player.attack()
            if (mouse.button === Qt.RightButton) player.isBlocking = true
        }

        onReleased: (mouse) => {
            if (mouse.button === Qt.RightButton && player)
                player.isBlocking = false
        }
    }

    // Player center in screen coords (for aiming) - map from player's parent to mouseInput coords
    property var playerScreenPos: player ? player.parent.mapToItem(mouseInput, player.x + player.width * 0.5, player.y + player.height * 0.5) : Qt.point(width/2, height/2)
    property real playerScreenX: playerScreenPos.x
    property real playerScreenY: playerScreenPos.y


    // Input handling
    Keys.forwardTo: gameCtrl
    GameController {
        id: gameCtrl
        anchors.fill: parent
        showDebugOverlay: false

        Component.onCompleted: {
            console.log("[Game] GameController.onCompleted - os:", Qt.platform.os)
            const os = Qt.platform.os
            if (os === "ios" || os === "android") {
                console.log("[Game] Selecting touchscreen gamepad")
                selectTouchscreenGamepad()
            } else {
                console.log("[Game] Selecting keyboard (WASD + Space/Shift)")
                selectKeyboard(Qt.Key_W, Qt.Key_S, Qt.Key_A, Qt.Key_D,
                               Qt.Key_Space, Qt.Key_Shift)
            }
        }

        onAxisXChanged: console.log("[Input] axisX:", axisX)
        onAxisYChanged: console.log("[Input] axisY:", axisY)
        onButtonBPressedChanged: if (buttonBPressed && player) player.dash()
    }

    // Player Health HUD (fixed position, not following camera)
    Rectangle {
        id: healthHud
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 10
        width: 200
        height: 24
        color: "#333333"
        radius: 4
        z: 1000  // Above everything

        Rectangle {
            id: healthFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: player ? (parent.width - 4) * (player.hp / player.maxHp) : parent.width - 4
            radius: 2
            color: {
                if (!player) return "#22CC22"
                let ratio = player.hp / player.maxHp
                if (ratio > 0.5) return "#22CC22"
                if (ratio > 0.25) return "#CCCC22"
                return "#CC2222"
            }

            Behavior on width { NumberAnimation { duration: 100 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            anchors.centerIn: parent
            text: player ? player.hp + " / " + player.maxHp : ""
            color: "white"
            font.pixelSize: 12
            font.bold: true
        }
    }

    // Player Mana HUD
    Rectangle {
        id: manaHud
        anchors.top: healthHud.bottom
        anchors.left: parent.left
        anchors.margins: 10
        anchors.topMargin: 4
        width: 200
        height: 16
        color: "#333333"
        radius: 4
        z: 1000

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: player ? (parent.width - 4) * (player.mana / player.maxMana) : parent.width - 4
            radius: 2
            color: "#8844AA"
            Behavior on width { NumberAnimation { duration: 100 } }
        }

        Text {
            anchors.centerIn: parent
            text: player ? player.mana + " / " + player.maxMana : ""
            color: "white"
            font.pixelSize: 10
            font.bold: true
        }
    }

    // Crosshair at mouse position
    Item {
        id: crosshair
        x: mouseInput.mouseX - 6
        y: mouseInput.mouseY - 6
        width: 12
        height: 12
        z: 1000

        // Horizontal line
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 2
            color: "#7AB8D4"
        }
        // Vertical line
        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: parent.height
            color: "#7AB8D4"
        }
    }

    // DEV menu (sandbox only)
    Column {
        id: devMenu
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 10
        z: 1000
        visible: Clayground.runsInSandbox
        spacing: 4

        property bool expanded: false

        Rectangle {
            width: devMenu.expanded ? 160 : 36
            height: 24; radius: 4
            color: "#333333CC"

            Text {
                anchors.centerIn: parent
                text: devMenu.expanded ? "DEV [v]" : "DEV"
                color: "#AAAAAA"
                font.pixelSize: 12; font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: devMenu.expanded = !devMenu.expanded
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Seed: " + masterSeed
                color: "#AAAAAA"; font.pixelSize: 11
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: world.debugPhysics ? "#4A90A480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Physics: " + (world.debugPhysics ? "ON" : "OFF")
                color: "white"; font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: world.debugPhysics = !world.debugPhysics
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: world.debugBehavior ? "#4A90A480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Behavior: " + (world.debugBehavior ? "ON" : "OFF")
                color: "white"; font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: world.debugBehavior = !world.debugBehavior
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: world.debugMechanics ? "#4A90A480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Mechanics: " + (world.debugMechanics ? "ON" : "OFF")
                color: "white"; font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: world.debugMechanics = !world.debugMechanics
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: fightRoomActive ? "#AA444480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: fightRoomActive ? "Fight Room: ON" : "Fight Room"
                color: fightRoomActive ? "#FF8888" : "white"
                font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: fightRoomActive ? exitFightRoom() : enterFightRoom()
            }
        }
    }

    // Track player movement for minimap exploration
    Connections {
        target: player
        function onXWuChanged() { revealAroundPlayer() }
        function onYWuChanged() { revealAroundPlayer() }
    }

    // Minimap with fog of war
    Canvas {
        id: minimap
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: 150
        height: 150
        z: 1000

        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "#111"
            ctx.fillRect(0, 0, width, height)

            var scale = width / gridWidth

            // Draw explored cells
            for (var gy = 0; gy < gridHeight; gy++) {
                for (var gx = 0; gx < gridWidth; gx++) {
                    if (exploredCells[gy] && exploredCells[gy][gx]) {
                        var cellType = grid[gy][gx]
                        ctx.fillStyle = (cellType === cellWall) ? "#333" : "#666"
                        ctx.fillRect(gx * scale, (gridHeight - 1 - gy) * scale, scale, scale)
                    }
                }
            }

            // Draw player
            if (player) {
                var px = player.xWu / cellSize * scale
                var py = (gridHeight - player.yWu / cellSize) * scale
                ctx.fillStyle = "#4A90A4"
                ctx.beginPath()
                ctx.arc(px, py, 3, 0, Math.PI * 2)
                ctx.fill()
            }

            // Draw enemies (if in explored area)
            for (var e of enemies) {
                if (!e || e.destroyed) continue
                var ex = Math.floor(e.xWu / cellSize)
                var ey = Math.floor(e.yWu / cellSize)
                if (exploredCells[ey] && exploredCells[ey][ex]) {
                    ctx.fillStyle = "#CC4444"
                    ctx.beginPath()
                    ctx.arc(e.xWu / cellSize * scale, (gridHeight - e.yWu / cellSize) * scale, 2, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }
    }

    // Exit trigger sensor
    property var exitSensor: null
    property bool resetting: false

    CollisionTracker {
        fixture: exitSensor ? exitSensor.fixture : null
        onBeginContact: (entity) => {
            if (entity === player && !resetting) {
                console.log("[Game] Player reached the exit!")
                resetting = true
                Qt.callLater(resetDungeon)
            }
        }
    }

    // Component factories
    Component { id: playerComponent; Player {} }
    Component { id: enemyComponent; Enemy {} }
    Component { id: wallComponent; Wall {} }
    Component { id: floorComponent; Floor {} }

    // Death particle
    Component {
        id: deathParticleComp
        Rectangle {
            id: _dp
            property real pixelPerUnit: 1
            property real xWu: 0
            property real yWu: 0
            property real widthWu: 0.2
            property real heightWu: 0.2
            property real velX: 0
            property real velY: 0
            x: xWu * pixelPerUnit
            y: parent ? parent.height - yWu * pixelPerUnit : 0
            width: widthWu * pixelPerUnit
            height: heightWu * pixelPerUnit
            radius: width * 0.3
            rotation: Math.random() * 360
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: _dp; property: "xWu"; to: _dp.xWu + _dp.velX; duration: 500; easing.type: Easing.OutQuad }
                    NumberAnimation { target: _dp; property: "yWu"; to: _dp.yWu + _dp.velY; duration: 500; easing.type: Easing.OutQuad }
                    NumberAnimation { target: _dp; property: "opacity"; from: 1.0; to: 0; duration: 500 }
                    NumberAnimation { target: _dp; property: "widthWu"; to: 0.05; duration: 500 }
                    NumberAnimation { target: _dp; property: "heightWu"; to: 0.05; duration: 500 }
                }
                ScriptAction { script: _dp.destroy() }
            }
        }
    }

    // Dungeon generation constants
    readonly property int cellSize: 2      // Each grid cell = 2x2 world units (for 2-wide hallways)
    readonly property int wallThickness: 1

    // Cell types for the grid
    readonly property int cellWall: 0
    readonly property int cellFloor: 1
    readonly property int cellRoom: 2
    readonly property int cellHallway: 3

    // Grid dimensions (in cells, not world units)
    readonly property int gridWidth: Math.floor(xWuMax / cellSize)
    readonly property int gridHeight: Math.floor(yWuMax / cellSize)

    // Dungeon data
    property var grid: []
    property var rooms: []

    // Minimap exploration
    property var exploredCells: []
    property int revealRadius: 6

    function generateDungeon() {
        if (masterSeed < 0)
            masterSeed = Math.floor(Math.random() * 2147483647)
        let levelSeed = deriveSeed(masterSeed, levelIndex)
        rng = createRng(levelSeed)
        console.log("[Game] Seed:", masterSeed, "Level:", levelIndex, "LevelSeed:", levelSeed)
        console.log("[Game] Grid size:", gridWidth, "x", gridHeight, "cells")

        // Step 1: Initialize grid with walls
        initializeGrid()
        initExploredCells()

        // Step 2: Place rooms
        placeRooms(6, 8, 5, 8)  // minRooms, maxRooms, minSize, maxSize (in cells)

        // Step 3: Connect rooms with spanning tree
        connectRooms()

        // Step 4: Add entrance (south) and exit (north)
        addEntranceAndExit()

        // Step 5: Convert grid to actual game objects
        buildDungeonFromGrid()

        // Step 6: Spawn player in first room
        if (rooms.length > 0) {
            let startRoom = rooms[0]
            let px = (startRoom.x + startRoom.w / 2) * cellSize
            let py = (startRoom.y + startRoom.h / 2) * cellSize
            console.log("[Game] Spawning player at:", px, py)
            spawnPlayer(px, py)
        }

        // Step 7: Block the entrance so player can't backtrack
        blockEntrance()

        // Step 8: Place exit trigger sensor at the north edge
        placeExitSensor()

        // Step 9: Spawn 10-20 enemies across non-start rooms with tier variation
        if (rooms.length > 1) {
            let spawnRooms = rooms.slice(1)
            let numEnemies = 5 + Math.floor(rng() * 4)
            for (let i = 0; i < numEnemies; i++) {
                let room = spawnRooms[i % spawnRooms.length]
                let ex = (room.x + 1 + rng() * (room.w - 2)) * cellSize
                let ey = (room.y + 1 + rng() * (room.h - 2)) * cellSize
                // Tier: 0=weak(20%), 1=normal(60%), 2=tough(20%)
                let roll = rng()
                let tier = roll < 0.2 ? 0 : (roll < 0.8 ? 1 : 2)
                // ~20% chance of guardian (tougher tiers more likely)
                let type = rng() < (tier === 2 ? 0.4 : 0.15) ? "guardian" : "grunt"
                spawnEnemy(ex, ey, tier, type)
            }
        }

        // Bind player controls
        if (player) {
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)
            // Mouse aiming: bind screen coords for facing calculation
            player.mouseScreenX = Qt.binding(() => mouseInput.mouseX)
            player.mouseScreenY = Qt.binding(() => mouseInput.mouseY)
            player.playerScreenX = Qt.binding(() => playerScreenX)
            player.playerScreenY = Qt.binding(() => playerScreenY)
            observedItem = player
            revealAroundPlayer()  // Initial reveal
        }

        console.log("[Game] generateDungeon() complete")
    }

    function initializeGrid() {
        grid = []
        for (let y = 0; y < gridHeight; y++) {
            let row = []
            for (let x = 0; x < gridWidth; x++) {
                row.push(cellWall)
            }
            grid.push(row)
        }
        console.log("[Game] Grid initialized:", grid.length, "rows")
    }

    function initExploredCells() {
        exploredCells = []
        for (let y = 0; y < gridHeight; y++) {
            let row = []
            for (let x = 0; x < gridWidth; x++) {
                row.push(false)
            }
            exploredCells.push(row)
        }
    }

    function revealAroundPlayer() {
        if (!player) return
        let px = Math.floor(player.xWu / cellSize)
        let py = Math.floor(player.yWu / cellSize)

        for (let dy = -revealRadius; dy <= revealRadius; dy++) {
            for (let dx = -revealRadius; dx <= revealRadius; dx++) {
                let gx = px + dx
                let gy = py + dy
                if (gx >= 0 && gx < gridWidth && gy >= 0 && gy < gridHeight) {
                    if (dx*dx + dy*dy <= revealRadius*revealRadius) {
                        exploredCells[gy][gx] = true
                    }
                }
            }
        }
        minimap.requestPaint()
    }

    function placeRooms(minRooms, maxRooms, minSize, maxSize) {
        rooms = []
        let numRooms = minRooms + Math.floor(rng() * (maxRooms - minRooms + 1))
        let attempts = 0
        let maxAttempts = 100

        while (rooms.length < numRooms && attempts < maxAttempts) {
            attempts++

            // Random room size (in cells)
            let rw = minSize + Math.floor(rng() * (maxSize - minSize + 1))
            let rh = minSize + Math.floor(rng() * (maxSize - minSize + 1))

            // Random position (leave 1 cell border for walls)
            let rx = 1 + Math.floor(rng() * (gridWidth - rw - 2))
            let ry = 1 + Math.floor(rng() * (gridHeight - rh - 2))

            // Check if room overlaps with existing rooms (with 1 cell padding)
            let overlaps = false
            for (let room of rooms) {
                if (rx < room.x + room.w + 1 &&
                    rx + rw + 1 > room.x &&
                    ry < room.y + room.h + 1 &&
                    ry + rh + 1 > room.y) {
                    overlaps = true
                    break
                }
            }

            if (!overlaps) {
                rooms.push({x: rx, y: ry, w: rw, h: rh})
                // Carve room into grid
                for (let y = ry; y < ry + rh; y++) {
                    for (let x = rx; x < rx + rw; x++) {
                        grid[y][x] = cellRoom
                    }
                }
                console.log("[Game] Placed room", rooms.length, "at", rx, ry, "size", rw, "x", rh)
            }
        }

        // Sort rooms by Y position (bottom to top) for spanning tree
        rooms.sort((a, b) => a.y - b.y)
        console.log("[Game] Placed", rooms.length, "rooms")
    }

    function connectRooms() {
        if (rooms.length < 2) return

        // Simple spanning tree: connect each room to the next
        for (let i = 0; i < rooms.length - 1; i++) {
            let roomA = rooms[i]
            let roomB = rooms[i + 1]

            // Get center of each room
            let ax = Math.floor(roomA.x + roomA.w / 2)
            let ay = Math.floor(roomA.y + roomA.h / 2)
            let bx = Math.floor(roomB.x + roomB.w / 2)
            let by = Math.floor(roomB.y + roomB.h / 2)

            // Carve L-shaped hallway
            carveHallway(ax, ay, bx, by)
        }
    }

    function carveHallway(x1, y1, x2, y2) {
        // Carve horizontal first, then vertical (L-shape)
        let x = x1
        let y = y1

        // Horizontal segment
        let dx = x2 > x1 ? 1 : -1
        while (x !== x2) {
            if (grid[y][x] === cellWall) {
                grid[y][x] = cellHallway
            }
            x += dx
        }

        // Vertical segment
        let dy = y2 > y1 ? 1 : -1
        while (y !== y2) {
            if (grid[y][x] === cellWall) {
                grid[y][x] = cellHallway
            }
            y += dy
        }
    }

    function addEntranceAndExit() {
        if (rooms.length === 0) return

        // Entrance: carve path from bottom room to south edge
        let startRoom = rooms[0]
        let entranceX = Math.floor(startRoom.x + startRoom.w / 2)
        for (let y = 0; y < startRoom.y; y++) {
            grid[y][entranceX] = cellHallway
        }

        // Exit: carve path from top room to north edge
        let endRoom = rooms[rooms.length - 1]
        let exitX = Math.floor(endRoom.x + endRoom.w / 2)
        for (let y = endRoom.y + endRoom.h; y < gridHeight; y++) {
            grid[y][exitX] = cellHallway
        }

        entranceGridX = entranceX
        exitGridX = exitX
        console.log("[Game] Added entrance at x=", entranceX, "exit at x=", exitX)
    }

    function buildDungeonFromGrid() {
        // Create floor for entire dungeon area
        let floorObj = floorComponent.createObject(world.room, {
            xWu: 0, yWu: yWuMax, widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
        dungeonObjects.push(floorObj)

        // Create merged walls using run-length encoding
        let wallCount = createMergedWalls()

        // Create boundary walls
        createBoundaryWalls()

        console.log("[Game] Built dungeon with", wallCount, "merged walls")
    }

    function createMergedWalls() {
        // Run-length encoding: merge consecutive wall cells horizontally
        let wallCount = 0

        for (let gy = 0; gy < gridHeight; gy++) {
            let gx = 0
            while (gx < gridWidth) {
                if (grid[gy][gx] === cellWall) {
                    // Found start of wall run, find its length
                    let startX = gx
                    while (gx < gridWidth && grid[gy][gx] === cellWall) {
                        gx++
                    }
                    let runLength = gx - startX

                    // Create single wall for entire run
                    let wx = startX * cellSize
                    let wy = gy * cellSize
                    let ww = runLength * cellSize
                    createWallAt(wx, wy + cellSize, ww, cellSize)
                    wallCount++
                } else {
                    gx++
                }
            }
        }

        return wallCount
    }

    function createBoundaryWalls() {
        // South wall (with entrance gap handled by grid)
        // North wall (with exit gap handled by grid)
        // West wall
        createWallAt(0, yWuMax, wallThickness, yWuMax)
        // East wall
        createWallAt(xWuMax - wallThickness, yWuMax, wallThickness, yWuMax)
    }

    function createWallAt(wx, wy, ww, wh) {
        let wall = wallComponent.createObject(world.room, {
            xWu: wx, yWu: wy, widthWu: ww, heightWu: wh,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer | catEnemy
        })
        dungeonObjects.push(wall)
        return wall
    }

    function spawnPlayer(px, py) {
        console.log("[Game] spawnPlayer at", px, py)
        player = playerComponent.createObject(world.room, {
            xWu: px, yWu: py,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world,
            categories: catPlayer,
            collidesWith: catWall,
            // Attack sensor detects enemies
            attackSensorCategories: catPlayer,
            attackSensorCollidesWith: catEnemy
        })
        if (player) {
            console.log("[Game] Player created:", player, "xWu:", player.xWu, "yWu:", player.yWu,
                        "width:", player.width, "height:", player.height,
                        "physics world:", player.world)
        } else {
            console.log("[Game] ERROR: playerComponent.createObject returned null")
        }
    }

    function spawnEnemy(ex, ey, tier, type) {
        tier = tier || 1
        type = type || "grunt"
        let tierData = [
            { hp: 18, tint: "#6B2A2A" },  // weak: darker, desaturated
            { hp: 30, tint: "" },           // normal: default colors
            { hp: 42, tint: "#CC6644" }     // tough: brighter, warm glow
        ]
        let td = tierData[tier]
        let ehp = td.hp + (type === "guardian" ? 10 : 0)
        let enemy = enemyComponent.createObject(world.room, {
            xWu: ex, yWu: ey,
            hp: ehp, maxHp: ehp,
            tier: tier,
            enemyType: type,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world,
            categories: catEnemy,
            collidesWith: catWall | catPlayer
        })
        if (enemy) {
            console.log("[Game] Enemy created -", type, "tier:", tier, "hp:", ehp)
            enemy.target = player
            enemies.push(enemy)
        } else {
            console.log("[Game] ERROR: enemyComponent.createObject returned null")
        }
    }

    function spawnDeathParticles(wx, wy) {
        let colors = ["#CC4444", "#8B3A3A", "#FF6644", "#AA2222", "#FF8866"]
        for (let i = 0; i < 8; i++) {
            let angle = (i / 8) * Math.PI * 2 + (Math.random() - 0.5)
            let speed = 1.5 + Math.random() * 2.0
            deathParticleComp.createObject(world.room, {
                xWu: wx, yWu: wy,
                velX: Math.cos(angle) * speed,
                velY: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
            })
        }
    }

    // Floating damage number component
    Component {
        id: damageNumberComp
        Text {
            id: _dmgText
            property real pixelPerUnit: 1
            property real xWu: 0
            property real yWu: 0
            property real startYWu: 0
            x: xWu * pixelPerUnit - width / 2
            y: parent ? parent.height - yWu * pixelPerUnit - height : 0
            font.pixelSize: 14
            font.bold: true
            style: Text.Outline
            styleColor: "#000000"
            z: 999
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: _dmgText; property: "yWu"; to: _dmgText.startYWu + 1.5; duration: 600; easing.type: Easing.OutQuad }
                    NumberAnimation { target: _dmgText; property: "opacity"; from: 1.0; to: 0; duration: 600 }
                }
                ScriptAction { script: _dmgText.destroy() }
            }
        }
    }

    function spawnDamageNumber(wx, wy, amount, color) {
        if (!debugMechanics) return
        damageNumberComp.createObject(world.room, {
            xWu: wx, yWu: wy + 0.5,
            startYWu: wy + 0.5,
            text: "" + amount,
            color: color,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
    }

    function spawnParryEffect(wx, wy) {
        let colors = ["#FFD700", "#FFFFFF", "#FFE866", "#FFFFAA"]
        for (let i = 0; i < 5; i++) {
            let angle = (i / 5) * Math.PI * 2 + (Math.random() - 0.5)
            let speed = 2.0 + Math.random() * 1.5
            deathParticleComp.createObject(world.room, {
                xWu: wx, yWu: wy,
                velX: Math.cos(angle) * speed,
                velY: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
            })
        }
    }

    function blockEntrance() {
        let wx = entranceGridX * cellSize
        let wy = cellSize  // Bottom edge of map
        let wall = createWallAt(wx, wy, cellSize, cellSize)
        wall.opacity = 0  // Invisible blocker
        console.log("[Game] Entrance blocked at grid x=", entranceGridX)
    }

    function placeExitSensor() {
        let wx = exitGridX * cellSize
        let wy = yWuMax  // Top edge of map
        exitSensor = wallComponent.createObject(world.room, {
            xWu: wx, yWu: wy, widthWu: cellSize, heightWu: cellSize,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer,
            sensor: true
        })
        exitSensor.opacity = 0
        dungeonObjects.push(exitSensor)
        console.log("[Game] Exit sensor placed at grid x=", exitGridX)
    }

    function clearDungeon() {
        exitSensor = null

        // Destroy enemies
        for (let e of enemies) {
            try { if (e && !e.destroyed) e.destroy() } catch(err) {}
        }
        enemies = []

        // Destroy player
        if (player) {
            try { player.destroy() } catch(err) {}
            player = null
        }

        // Destroy all tracked dungeon objects (walls, floors)
        for (let obj of dungeonObjects) {
            try { if (obj) obj.destroy() } catch(err) {}
        }
        dungeonObjects = []

        grid = []
        rooms = []
    }

    function resetDungeon() {
        let savedHp = player ? player.hp : 120
        console.log("[Game] Resetting dungeon, preserving HP:", savedHp)
        clearDungeon()
        levelIndex++
        generateDungeon()
        if (player) player.hp = savedHp
        resetting = false
    }

    // --- Fight Room ---
    function enterFightRoom() {
        console.log("[Game] Entering fight room")
        clearDungeon()
        fightRoomActive = true

        // Simple walled room: 15x15 cells centered
        let roomSize = 15
        let ox = Math.floor((gridWidth - roomSize) / 2)
        let oy = Math.floor((gridHeight - roomSize) / 2)

        // Initialize grid and carve room
        initializeGrid()
        initExploredCells()
        for (let y = oy; y < oy + roomSize; y++)
            for (let x = ox; x < ox + roomSize; x++) {
                grid[y][x] = cellRoom
                exploredCells[y][x] = true
            }

        // Build walls and floor
        let floorObj = floorComponent.createObject(world.room, {
            xWu: 0, yWu: yWuMax, widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
        dungeonObjects.push(floorObj)
        createMergedWalls()
        createBoundaryWalls()

        // Spawn player at center
        let cx = (ox + roomSize / 2) * cellSize
        let cy = (oy + roomSize / 2) * cellSize
        _fightRoomCx = cx
        _fightRoomCy = cy
        spawnPlayer(cx, cy)

        // Bind controls
        if (player) {
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)
            player.mouseScreenX = Qt.binding(() => mouseInput.mouseX)
            player.mouseScreenY = Qt.binding(() => mouseInput.mouseY)
            player.playerScreenX = Qt.binding(() => playerScreenX)
            player.playerScreenY = Qt.binding(() => playerScreenY)
            observedItem = player
        }

        // Spawn test enemies: 2 grunts + 1 guardian
        _spawnFightRoomEnemies()
    }

    // Auto-respawn enemies in fight room when all dead
    Timer {
        id: fightRoomRespawn
        interval: 2000
        repeat: true
        running: fightRoomActive
        onTriggered: {
            if (!player) return
            let alive = 0
            for (let e of enemies)
                if (e && e.destroyed === false) alive++
            if (alive > 0) return
            enemies = []
            _spawnFightRoomEnemies()
            console.log("[Game] Fight room: respawned enemies")
        }
    }

    function _spawnFightRoomEnemies() {
        let cx = _fightRoomCx
        let cy = _fightRoomCy
        spawnEnemy(cx + 4, cy + 2, 1, "grunt")
        spawnEnemy(cx - 4, cy + 2, 1, "grunt")
        spawnEnemy(cx, cy + 4, 2, "guardian")
    }

    function exitFightRoom() {
        console.log("[Game] Exiting fight room")
        fightRoomActive = false
        clearDungeon()
        generateDungeon()
    }

    // --- Seeded PRNG (mulberry32) ---
    function createRng(seed) {
        let s = seed | 0
        return function() {
            s = (s + 0x6D2B79F5) | 0
            var t = Math.imul(s ^ (s >>> 15), 1 | s)
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }

    function deriveSeed(master, index) {
        return (master * 2654435761 + index * 2246822519) | 0
    }

    // --- Line-of-sight (Bresenham on grid) ---
    function hasLineOfSight(x1Wu, y1Wu, x2Wu, y2Wu) {
        let gx0 = Math.floor(x1Wu / cellSize)
        let gy0 = Math.floor(y1Wu / cellSize)
        let gx1 = Math.floor(x2Wu / cellSize)
        let gy1 = Math.floor(y2Wu / cellSize)

        let dx = Math.abs(gx1 - gx0)
        let dy = Math.abs(gy1 - gy0)
        let sx = gx0 < gx1 ? 1 : -1
        let sy = gy0 < gy1 ? 1 : -1
        let err = dx - dy

        while (true) {
            if (gx0 < 0 || gx0 >= gridWidth || gy0 < 0 || gy0 >= gridHeight)
                return false
            if (grid[gy0][gx0] === cellWall)
                return false
            if (gx0 === gx1 && gy0 === gy1)
                return true
            let e2 = 2 * err
            if (e2 > -dy) { err -= dy; gx0 += sx }
            if (e2 < dx)  { err += dx; gy0 += sy }
        }
    }

    // --- A* pathfinder on grid ---
    function findPath(x1Wu, y1Wu, x2Wu, y2Wu) {
        let sx = Math.floor(x1Wu / cellSize)
        let sy = Math.floor(y1Wu / cellSize)
        let ex = Math.floor(x2Wu / cellSize)
        let ey = Math.floor(y2Wu / cellSize)

        // Clamp to grid
        sx = Math.max(0, Math.min(gridWidth - 1, sx))
        sy = Math.max(0, Math.min(gridHeight - 1, sy))
        ex = Math.max(0, Math.min(gridWidth - 1, ex))
        ey = Math.max(0, Math.min(gridHeight - 1, ey))

        // Snap start/end to nearest walkable cell if on a wall
        function snapToWalkable(cx, cy) {
            if (grid[cy][cx] !== cellWall) return {x: cx, y: cy}
            let dirs = [[0,1],[0,-1],[1,0],[-1,0],[1,1],[1,-1],[-1,1],[-1,-1]]
            for (let d of dirs) {
                let nx = cx + d[0], ny = cy + d[1]
                if (nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridHeight
                    && grid[ny][nx] !== cellWall)
                    return {x: nx, y: ny}
            }
            return null
        }
        let s = snapToWalkable(sx, sy)
        let e = snapToWalkable(ex, ey)
        if (!s || !e) return []
        sx = s.x; sy = s.y; ex = e.x; ey = e.y

        // Binary heap (min-heap by f score)
        let open = []
        let closed = new Set()
        let cameFrom = {}
        let gScore = {}

        function key(x, y) { return y * gridWidth + x }
        function heuristic(x, y) { return Math.abs(x - ex) + Math.abs(y - ey) }

        function heapPush(node) {
            open.push(node)
            let i = open.length - 1
            while (i > 0) {
                let p = (i - 1) >> 1
                if (open[p].f <= open[i].f) break
                let tmp = open[p]; open[p] = open[i]; open[i] = tmp
                i = p
            }
        }

        function heapPop() {
            let top = open[0]
            let last = open.pop()
            if (open.length > 0) {
                open[0] = last
                let i = 0
                while (true) {
                    let best = i
                    let l = 2 * i + 1, r = 2 * i + 2
                    if (l < open.length && open[l].f < open[best].f) best = l
                    if (r < open.length && open[r].f < open[best].f) best = r
                    if (best === i) break
                    let tmp = open[best]; open[best] = open[i]; open[i] = tmp
                    i = best
                }
            }
            return top
        }

        let startKey = key(sx, sy)
        gScore[startKey] = 0
        heapPush({x: sx, y: sy, f: heuristic(sx, sy)})

        let dirs = [[1,0],[-1,0],[0,1],[0,-1]]

        while (open.length > 0) {
            let cur = heapPop()
            let ck = key(cur.x, cur.y)

            if (cur.x === ex && cur.y === ey) {
                // Reconstruct path as world-unit waypoints
                let path = []
                let k = ck
                while (k !== undefined) {
                    let py = Math.floor(k / gridWidth)
                    let px = k % gridWidth
                    path.unshift(Qt.point(px * cellSize + cellSize / 2,
                                          py * cellSize + cellSize / 2))
                    k = cameFrom[k]
                }
                return path
            }

            if (closed.has(ck)) continue
            closed.add(ck)

            for (let d of dirs) {
                let nx = cur.x + d[0]
                let ny = cur.y + d[1]
                if (nx < 0 || nx >= gridWidth || ny < 0 || ny >= gridHeight) continue
                if (grid[ny][nx] === cellWall) continue
                let nk = key(nx, ny)
                if (closed.has(nk)) continue
                let ng = gScore[ck] + 1
                if (gScore[nk] === undefined || ng < gScore[nk]) {
                    gScore[nk] = ng
                    cameFrom[nk] = ck
                    heapPush({x: nx, y: ny, f: ng + heuristic(nx, ny)})
                }
            }
        }

        return [] // No path found
    }
}
