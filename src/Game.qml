import QtQuick
import Box2D
import Clayground.World
import Clayground.Physics
import Clayground.GameController

ClayWorld2d {
    id: world

    // World configuration (fit world to viewport)
    pixelPerUnit: 20//Math.min(width / xWuMax, height / yWuMax)
    gravity: Qt.poiant(0, 0)  // Top-down, no gravity
    timeStep: 1/60.0
    anchors.fill: parent
    focus: true

    // World bounds (in world units) - portrait orientation
    xWuMax: 100
    yWuMax: 100

    // Debug visualization
    debugPhysics: false  // Show collision shapes

    canvas.showDebugInfo: true

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

    // Simple dungeon generation (placeholder for full algorithm)
    function generateDungeon() {
        console.log("[Game] generateDungeon() called")
        const tileSize = 1.0  // 1 world unit per tile

        // Create room at world boundaries
        const roomX = 0
        const roomY = 0
        const roomW = xWuMax
        const roomH = yWuMax

        console.log("[Game] Creating room...")
        createRoom(roomX, roomY, roomW, roomH, tileSize)

        // Spawn player in room center
        const centerX = roomX + roomW / 2
        const centerY = roomY + roomH / 2
        console.log("[Game] Spawning player at center:", centerX, centerY)
        spawnPlayer(centerX, centerY)

        // Spawn test enemy above player
        console.log("[Game] Spawning enemy...")
        spawnEnemy(centerX, centerY + 3)

        // Bind player movement to controller
        if (player) {
            console.log("[Game] Player spawned successfully, binding controls")
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)  // Invert Y for top-down
            observedItem = player
            console.log("[Game] observedItem set to player:", observedItem)
        } else {
            console.log("[Game] ERROR: Player is null!")
        }
        console.log("[Game] generateDungeon() complete")
    }

    function createBoundary(tileSize) {
        const wallThickness = 1
        const margin = 5  // Inset from world edges so walls are visible

        const left = margin
        const right = xWuMax - margin
        const bottom = margin
        const top = yWuMax - margin
        const boundaryWidth = right - left
        const boundaryHeight = top - bottom

        // Bottom wall
        createWall(left, bottom, boundaryWidth, wallThickness)
        // Top wall
        createWall(left, top - wallThickness, boundaryWidth, wallThickness)
        // Left wall
        createWall(left, bottom, wallThickness, boundaryHeight)
        // Right wall
        createWall(right - wallThickness, bottom, wallThickness, boundaryHeight)
    }

    function createRoom(rx, ry, rw, rh, tileSize) {
        // Floor (visual only)
        let floor = floorComponent.createObject(world.room, {
            xWu: rx, yWu: ry + rh, widthWu: rw, heightWu: rh,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })

        // Solid walls enclosing the room
        // Note: yWu is the TOP of the wall, height extends downward
        const wallThickness = 1

        // Bottom wall (south) - top of wall at ry + wallThickness
        createWall(rx, ry + wallThickness, rw, wallThickness)
        // Top wall (north) - top of wall at ry + rh
        createWall(rx, ry + rh, rw, wallThickness)
        // Left wall (west) - top of wall at ry + rh
        createWall(rx, ry + rh, wallThickness, rh)
        // Right wall (east) - top of wall at ry + rh
        createWall(rx + rw - wallThickness, ry + rh, wallThickness, rh)
    }

    function createWall(wx, wy, ww, wh) {
        console.log("[Game] createWall - room.height:", world.room.height, "room.width:", world.room.width)
        // Create in room and bind physics world
        let wall = wallComponent.createObject(world.room, {
            xWu: wx, yWu: wy, widthWu: ww, heightWu: wh,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer | catEnemy
        })
        if (!wall) {
            console.log("[Game] ERROR: Failed to create wall at", wx, wy)
        } else {
            console.log("[Game] Wall created - xWu:", wx, "yWu:", wy, "-> screen x:", wall.x, "y:", wall.y,
                        "size:", wall.width, "x", wall.height)
        }
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
