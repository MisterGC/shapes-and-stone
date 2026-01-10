import QtQuick
import Box2D
import Clayground.World
import Clayground.Physics
import Clayground.GameController

ClayWorld2d {
    id: world

    // World configuration (fit world to viewport)
    pixelPerUnit: 20//Math.min(width / xWuMax, height / yWuMax)
    gravity: Qt.point(0, 0)  // Top-down, no gravity
    timeStep: 1/60.0
    anchors.fill: parent
    focus: true

    // World bounds (in world units) - portrait orientation
    xWuMax: 100
    yWuMax: 100

    // Debug visualization
    debugPhysics: false  // Show collision shapes

    canvas.showDebugInfo: false

    // Game state
    property var player: null
    property var enemies: []
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

    // Restore focus when clicked (for WASM)
    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => {
            world.forceActiveFocus()
            mouse.accepted = false
        }
    }


    // Input handling
    Keys.forwardTo: gameCtrl
    GameController {
        id: gameCtrl
        anchors.fill: parent

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
    }

    // Component factories
    Component { id: playerComponent; Player {} }
    Component { id: enemyComponent; Enemy {} }
    Component { id: wallComponent; Wall {} }
    Component { id: floorComponent; Floor {} }

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

    function generateDungeon() {
        console.log("[Game] generateDungeon() called")
        console.log("[Game] Grid size:", gridWidth, "x", gridHeight, "cells")

        // Step 1: Initialize grid with walls
        initializeGrid()

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

        // Step 7: Spawn enemy in last room
        if (rooms.length > 1) {
            let endRoom = rooms[rooms.length - 1]
            let ex = (endRoom.x + endRoom.w / 2) * cellSize
            let ey = (endRoom.y + endRoom.h / 2) * cellSize
            console.log("[Game] Spawning enemy at:", ex, ey)
            spawnEnemy(ex, ey)
        }

        // Bind player controls
        if (player) {
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)
            observedItem = player
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

    function placeRooms(minRooms, maxRooms, minSize, maxSize) {
        rooms = []
        let numRooms = minRooms + Math.floor(Math.random() * (maxRooms - minRooms + 1))
        let attempts = 0
        let maxAttempts = 100

        while (rooms.length < numRooms && attempts < maxAttempts) {
            attempts++

            // Random room size (in cells)
            let rw = minSize + Math.floor(Math.random() * (maxSize - minSize + 1))
            let rh = minSize + Math.floor(Math.random() * (maxSize - minSize + 1))

            // Random position (leave 1 cell border for walls)
            let rx = 1 + Math.floor(Math.random() * (gridWidth - rw - 2))
            let ry = 1 + Math.floor(Math.random() * (gridHeight - rh - 2))

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

        console.log("[Game] Added entrance at x=", entranceX, "exit at x=", exitX)
    }

    function buildDungeonFromGrid() {
        // Create floor for entire dungeon area
        let floorObj = floorComponent.createObject(world.room, {
            xWu: 0, yWu: yWuMax, widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })

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
        return wall
    }

    function spawnPlayer(px, py) {
        console.log("[Game] spawnPlayer at", px, py)
        player = playerComponent.createObject(world.room, {
            xWu: px, yWu: py,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catPlayer,
            collidesWith: catWall
        })
        if (player) {
            console.log("[Game] Player created:", player, "xWu:", player.xWu, "yWu:", player.yWu,
                        "width:", player.width, "height:", player.height,
                        "physics world:", player.world)
        } else {
            console.log("[Game] ERROR: playerComponent.createObject returned null")
        }
    }

    function spawnEnemy(ex, ey) {
        console.log("[Game] spawnEnemy at", ex, ey)
        let enemy = enemyComponent.createObject(world.room, {
            xWu: ex, yWu: ey,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world,  // For MoveTo behavior
            categories: catEnemy,
            collidesWith: catWall
        })
        if (enemy) {
            console.log("[Game] Enemy created:", enemy, "xWu:", enemy.xWu, "yWu:", enemy.yWu)
            enemy.target = player
            enemies.push(enemy)
        } else {
            console.log("[Game] ERROR: enemyComponent.createObject returned null")
        }
    }
}
