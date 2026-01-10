import QtQuick
import Box2D
import Clayground.World
import Clayground.Physics
import Clayground.GameController

ClayWorld2d {
    id: world

    // World configuration
    pixelPerUnit: width / xWuMax
    gravity: Qt.point(0, 0)  // Top-down, no gravity
    timeStep: 1/60.0
    anchors.fill: parent
    focus: true

    // World bounds (in world units)
    xWuMax: 80
    yWuMax: 60

    // Game state
    property var player: null
    property var enemies: []

    // Collision categories
    readonly property int catWall: Box.Category1
    readonly property int catPlayer: Box.Category2
    readonly property int catEnemy: Box.Category3

    Component.onCompleted: {
        forceActiveFocus()
        generateDungeon()
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
            const os = Qt.platform.os
            if (os === "ios" || os === "android")
                selectTouchscreenGamepad()
            else
                selectKeyboard(Qt.Key_W, Qt.Key_S, Qt.Key_A, Qt.Key_D,
                               Qt.Key_Space, Qt.Key_Shift)
        }
    }

    // Component factories
    Component { id: playerComponent; Player {} }
    Component { id: enemyComponent; Enemy {} }
    Component { id: wallComponent; Wall {} }
    Component { id: floorComponent; Floor {} }

    // Simple dungeon generation (placeholder for full algorithm)
    function generateDungeon() {
        const tileSize = 1.0  // 1 world unit per tile

        // Create boundary walls
        createBoundary(tileSize)

        // Create a simple test room
        createRoom(10, 10, 20, 15, tileSize)

        // Spawn player at bottom center
        spawnPlayer(20, 5)

        // Spawn test enemy
        spawnEnemy(20, 20)

        // Bind player movement to controller
        if (player) {
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)  // Invert Y for top-down
            observedItem = player
        }
    }

    function createBoundary(tileSize) {
        const wallThickness = 1

        // Bottom wall
        createWall(0, 0, xWuMax, wallThickness)
        // Top wall
        createWall(0, yWuMax - wallThickness, xWuMax, wallThickness)
        // Left wall
        createWall(0, 0, wallThickness, yWuMax)
        // Right wall
        createWall(xWuMax - wallThickness, 0, wallThickness, yWuMax)
    }

    function createRoom(rx, ry, rw, rh, tileSize) {
        // Floor
        let floor = floorComponent.createObject(world, {
            x: rx, y: ry, width: rw, height: rh
        })

        // Room walls (leaving gaps for doors)
        const wallThickness = 1

        // Top wall with door gap
        createWall(rx, ry + rh - wallThickness, rw * 0.4, wallThickness)
        createWall(rx + rw * 0.6, ry + rh - wallThickness, rw * 0.4, wallThickness)

        // Bottom wall with door gap
        createWall(rx, ry, rw * 0.4, wallThickness)
        createWall(rx + rw * 0.6, ry, rw * 0.4, wallThickness)

        // Side walls
        createWall(rx, ry, wallThickness, rh)
        createWall(rx + rw - wallThickness, ry, wallThickness, rh)
    }

    function createWall(wx, wy, ww, wh) {
        return wallComponent.createObject(world, {
            x: wx, y: wy, width: ww, height: wh,
            categories: catWall,
            collidesWith: catPlayer | catEnemy
        })
    }

    function spawnPlayer(px, py) {
        player = playerComponent.createObject(world, {
            x: px, y: py,
            categories: catPlayer,
            collidesWith: catWall
        })
    }

    function spawnEnemy(ex, ey) {
        let enemy = enemyComponent.createObject(world, {
            x: ex, y: ey,
            categories: catEnemy,
            collidesWith: catWall
        })
        enemy.target = player
        enemies.push(enemy)
    }
}
