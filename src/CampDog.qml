import QtQuick

// A traveller's dog (issue #151): it trots after its traveller and stays
// beside it, wags, looks up at a knight that comes near and now and then
// scratches itself. A Creature like the cave cat: the watch, the breath
// and the act are the template's, the following and the shapes the
// dog's. It is drawn only. Numbers and colours in
// Balance.camp.travellers.dog.
Creature {
    id: dog
    creature: "dog"
    numbers: Balance.camp.travellers.dog

    // The traveller it follows, an Npc
    property var leader: null
    // Which side of it the dog keeps, east (1) or west (-1)
    readonly property real keep: seed < 0.5 ? 1 : -1
    // Where it faces, east (1) or west (-1), and whether it is on its way
    property real facing: keep
    property bool moving: false

    // Where it wants to be: beside the leader's centre, a little lower
    function spot() {
        let lx = leader.xWu + leader.widthWu / 2, ly = leader.yWu - leader.heightWu / 2
        return Qt.point(lx + keep * numbers.follow, ly - 0.25)
    }
    // It closes on its spot at gain times the way left a second, at most
    // speed: no step overshoots it, so it never steps back and forth
    // (issue #178). It sets out once the spot is start wu away and rests
    // within rest wu of it; on its way it faces where it goes, at rest
    // its traveller
    property real velocityX: 0
    property real velocityY: 0
    function follow(dt) {
        if (!leader) return
        let to = spot()
        let dx = to.x - xWu, dy = to.y - yWu, d = Math.hypot(dx, dy)
        if (moving ? d < numbers.rest : d < numbers.start) {
            moving = false
            velocityX = 0
            velocityY = 0
            // At rest it faces its traveller
            let lx = leader.xWu + leader.widthWu / 2
            if (Math.abs(lx - xWu) > 0.05) facing = lx > xWu ? 1 : -1
            return
        }
        moving = true
        let v = Math.min(numbers.speed, numbers.gain * d)
        velocityX = dx / d * v
        velocityY = dy / d * v
        xWu += velocityX * dt
        yWu += velocityY * dt
        if (Math.abs(velocityX) > 0.05) facing = velocityX > 0 ? 1 : -1
    }
    Timer {
        interval: dog.numbers.step * 1000
        running: !!dog.leader
        repeat: true
        onTriggered: dog.follow(interval / 1000)
    }

    readonly property real _s: width
    // Its head turns to the knight it watches
    readonly property real _lx: lookX * facing
    readonly property real _ly: lookY
    readonly property real _trot: moving ? Math.sin(_t * 18) : 0

    // Contact shadow
    Rectangle {
        x: dog._s * 0.08; y: dog._s * 0.55
        width: dog._s * 0.84; height: dog._s * 0.3
        radius: height / 2
        color: "black"
        opacity: 0.35
    }

    Item {
        id: pose
        anchors.fill: parent
        transform: Scale { origin.x: dog._s / 2; xScale: dog.facing }

        // The tail: wags slow asleep, fast awake or on its way
        Rectangle {
            x: dog._s * 0.02; y: dog._s * 0.4
            width: dog._s * 0.22; height: dog._s * 0.08
            radius: height / 2
            color: dog.numbers.fur
            transformOrigin: Item.Right
            rotation: -25 + (10 + 20 * Math.max(dog.lift, dog.moving ? 1 : 0))
                      * Math.sin(dog._t * (dog.lift > 0.5 || dog.moving ? 16 : 3))
        }
        // The legs, trotting while it moves
        Repeater {
            model: [0.24, 0.36, 0.58, 0.7]
            Rectangle {
                x: dog._s * modelData
                y: dog._s * (0.62 + 0.04 * dog._trot * (index % 2 === 0 ? 1 : -1))
                width: dog._s * 0.08; height: dog._s * 0.16
                radius: width / 2
                color: Qt.darker(dog.numbers.fur, 1.25)
            }
        }
        // The body, breathing; scratching it hunches
        Rectangle {
            id: body
            x: dog._s * 0.18; y: dog._s * 0.36
            width: dog._s * 0.62; height: dog._s * 0.34
            radius: height / 2
            color: dog.numbers.fur
            transform: Scale {
                origin.x: body.width / 2; origin.y: body.height
                yScale: 1 + 0.05 * dog.breathing + 0.08 * dog.act + 0.04 * dog._trot
            }
            Rectangle {
                x: parent.width * 0.15; y: parent.height * 0.12
                width: parent.width * 0.5; height: parent.height * 0.3
                radius: height / 2
                color: dog.numbers.light
                opacity: 0.4
            }
        }
        // A hind leg up, scratching
        Rectangle {
            x: dog._s * 0.3; y: dog._s * (0.5 - 0.06 * Math.sin(dog._t * 30))
            width: dog._s * 0.08; height: dog._s * 0.16
            radius: width / 2
            rotation: -50
            color: Qt.darker(dog.numbers.fur, 1.25)
            opacity: dog.act
        }

        // The head: up and turned to the knight awake, tilted scratching
        Item {
            id: head
            readonly property real d: dog._s * 0.34
            width: d; height: d
            x: dog._s * (0.8 + 0.05 * dog.lift * dog._lx) - d / 2
            y: dog._s * (0.38 - 0.1 * dog.lift - 0.04 * dog.lift * dog._ly) - d / 2
            rotation: 18 * dog.act

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: dog.numbers.fur
            }
            // The snout, ahead of the head
            Rectangle {
                width: head.d * 0.5; height: head.d * 0.36
                radius: height / 2
                x: head.d * (0.62 + 0.08 * dog.lift * dog._lx)
                y: head.d * (0.46 - 0.08 * dog.lift * dog._ly)
                color: dog.numbers.light
                Rectangle {
                    width: parent.height * 0.4; height: width
                    radius: width / 2
                    x: parent.width - width * 0.8; y: 0
                    color: dog.numbers.eyes
                }
            }
            // The ears: floppy, pricked a little awake
            Repeater {
                model: [0.12, 0.42]
                Rectangle {
                    width: head.d * 0.26; height: head.d * (0.5 - 0.12 * dog.lift)
                    radius: width / 2
                    x: head.d * modelData
                    y: head.d * (0.05 - 0.12 * dog.lift)
                    rotation: index === 0 ? 20 : -10
                    color: Qt.darker(dog.numbers.fur, 1.35)
                }
            }
            // The eye
            Rectangle {
                width: head.d * 0.14; height: width
                radius: width / 2
                x: head.d * (0.58 + 0.06 * dog.lift * dog._lx)
                y: head.d * (0.3 - 0.06 * dog.lift * dog._ly)
                color: dog.numbers.eyes
            }
        }
    }
}
