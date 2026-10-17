import QtQuick

// The cave cat (issue #150): a few soft shapes curled by the campfire,
// breathing slowly. A knight near, it lifts its head and its eyes follow
// the knight; the knight gone, it tucks its head back in; now and then it
// stretches. A Creature: the watch, the breath and the act are the
// template's, the shapes are the cat's. Numbers and colours in
// Balance.camp.cat.
Creature {
    id: cat
    creature: "cat"
    numbers: Balance.camp.cat

    // Given a fish (Game.feedCat): it eats it, head down over it, the fish
    // shrinking bite by bite, then lies content a while, eyes half shut
    property real eat: 0
    property real content: 0
    property color _fishColor: "#C8C2A0"
    function feed(color) {
        _fishColor = color
        eatAnim.restart()
    }
    SequentialAnimation {
        id: eatAnim
        NumberAnimation { target: cat; property: "eat"; from: 0; to: 1; duration: 2600 }
        ScriptAction { script: cat.content = 1 }
        PropertyAction { target: cat; property: "eat"; value: 0 }
        NumberAnimation { target: cat; property: "content"; to: 0; duration: 25000 }
    }
    readonly property real _munch: eat > 0 ? Math.abs(Math.sin(eat * Math.PI * 7)) : 0

    // Which way it lies, its head east (1) or west (-1)
    readonly property real side: seed < 0.5 ? 1 : -1
    readonly property real _s: width
    readonly property real _lx: lookX * side
    readonly property real _ly: lookY

    // Contact shadow, under the curled body
    Rectangle {
        x: cat._s * 0.06; y: cat._s * 0.4
        width: cat._s * 0.9; height: cat._s * 0.45
        radius: height / 2
        color: "black"
        opacity: 0.35
    }

    Item {
        id: pose
        anchors.fill: parent
        transform: Scale { origin.x: cat._s / 2; xScale: cat.side }

        // The tail, wrapped round the front of the body; awake its tip
        // flicks now and then
        Rectangle {
            x: cat._s * 0.14; y: cat._s * 0.7
            width: cat._s * 0.58; height: cat._s * 0.11
            radius: height / 2
            color: cat.numbers.fur
            transformOrigin: Item.Right
            rotation: -8 + cat.lift * 10 * Math.sin(cat._t * 2.3)
        }

        // The body, breathing; stretching it grows long and low
        Rectangle {
            id: body
            x: cat._s * 0.06; y: cat._s * 0.3
            width: cat._s * 0.76; height: cat._s * 0.5
            radius: height / 2
            color: cat.numbers.fur
            transform: Scale {
                origin.x: body.width * 0.3; origin.y: body.height
                xScale: 1 + 0.22 * cat.act
                yScale: 1 + (0.05 - 0.02 * cat.lift) * cat.breathing - 0.15 * cat.act
            }
            // The paler flank the light catches
            Rectangle {
                x: parent.width * 0.18; y: parent.height * 0.12
                width: parent.width * 0.5; height: parent.height * 0.32
                radius: height / 2
                color: cat.numbers.light
                opacity: 0.45
            }
        }

        // The front paws, out in front while it stretches
        Repeater {
            model: 2
            Rectangle {
                x: cat._s * (0.74 + 0.16 * cat.act); y: cat._s * (0.66 + index * 0.08)
                width: cat._s * 0.14; height: cat._s * 0.07
                radius: height / 2
                color: cat.numbers.light
                opacity: cat.act
            }
        }

        // The fish it was given, at its paws, smaller with each bite
        Item {
            visible: cat.eat > 0
            readonly property real k: 1 - cat.eat
            x: cat._s * 0.86; y: cat._s * 0.74
            Rectangle {
                width: cat._s * 0.3 * parent.k; height: cat._s * 0.12 * Math.max(0.3, parent.k)
                x: -width / 2; y: -height / 2
                radius: height / 2
                color: cat._fishColor
            }
        }

        // The head: tucked low on the body asleep, lifted and turned to
        // the knight awake
        Item {
            id: head
            readonly property real d: cat._s * 0.36
            width: d; height: d
            x: cat._s * (0.74 + 0.06 * cat.lift * cat._lx + 0.1 * cat.act) - d / 2
            y: cat._s * (0.58 - 0.18 * cat.lift - 0.05 * cat.lift * cat._ly + (cat.eat > 0 ? 0.12 + 0.05 * cat._munch : 0)) - d / 2
            scale: 0.9 + 0.1 * cat.lift

            // The ears: flat asleep, up awake
            Repeater {
                model: [-1, 1]
                Rectangle {
                    width: head.d * 0.36; height: width
                    x: head.d / 2 + modelData * head.d * 0.24 - width / 2
                    y: -head.d * 0.02
                    rotation: 45
                    color: cat.numbers.fur
                    transform: Scale { origin.x: head.d * 0.18; origin.y: head.d * 0.36; yScale: 0.75 + 0.25 * cat.lift }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: cat.numbers.fur
            }
            // The muzzle, toward the knight it watches
            Rectangle {
                width: head.d * 0.4; height: head.d * 0.3
                radius: height / 2
                x: head.d * (0.3 + 0.12 * cat.lift * cat._lx)
                y: head.d * (0.58 - 0.1 * cat.lift * cat._ly)
                color: cat.numbers.light
                opacity: 0.7
            }
            // The eyes: shut lines asleep, round and catching the fire
            // awake, both on the knight
            Repeater {
                model: [-1, 1]
                Rectangle {
                    readonly property real h: head.d * (0.04 + 0.12 * cat.lift * (1 - 0.7 * Math.max(cat.content, cat.eat > 0 ? 1 : 0)))
                    width: head.d * (0.2 - 0.06 * cat.lift); height: h
                    radius: Math.min(width, h) / 2
                    x: head.d * (0.5 + modelData * 0.2 + 0.12 * cat.lift * cat._lx) - width / 2
                    y: head.d * (0.42 - 0.12 * cat.lift * cat._ly) - h / 2
                    color: cat.lift > 0.3 ? cat.numbers.eyes : "#201812"
                }
            }
        }
    }
}
