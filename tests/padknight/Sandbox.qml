// Pad knight bench - the knight plays with a gamepad (issue #200).
//
// Driven by run_padknight.py (clayliveloader --sbx Sandbox.qml): the game
// enters the dojo's "dungeon" scenario and the driver plays it through the
// inspector's gamepad input alone, the dojo's synthetic pad, reading the
// knight back through state(). plugPad() and padInput() stand in for a
// physical pad: a virtual SDL pad on clayground's GamepadHub.

import QtQuick
import Clayground.GameController
import "../../src"

Item {
    id: bench
    anchors.fill: parent

    Game {
        id: game
        anchors.fill: parent
        muted: true
    }

    // The dojo's scenario menu reaches the game through the bench
    function scenarios() { return game.scenarios() }
    function applyScenario(name, danger) { game.applyScenario(name, danger) }

    // ---- driver API ----

    function begin() {
        game.applyScenario("dungeon", 0)
        return game.player !== null
    }

    function _find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = _find(kids[i], name)
            if (f) return f
        }
        return null
    }

    // The knight, the controller and what the screen tells the player, as
    // JSON
    function state() {
        let dialogue = _find(game, "knightPad").dialogue
        let p = game.player, c = _find(game, "knightPad").controller, hint = _find(game, "controlsHint")
        return JSON.stringify({
            x: p.xWu, y: p.yWu, facing: p.facingAngle, padAim: p.padAim,
            attacking: p.isAttacking, charging: p.isCharging, chargeFull: p.chargeFull,
            blocking: p.isBlocking, dashing: p.isDashing, hp: p.hp, maxHp: p.maxHp,
            potions: p.potions, draughts: p.draughts, mana: p.mana, momentum: p.momentum,
            gold: p.gold, lockedOn: p.lockedOn,
            panel: game.knightPanelOpen, talking: game.talking,
            ware: dialogue ? dialogue.selected : -1, wares: dialogue ? dialogue.wares.length : 0,
            dialogueHint: dialogue && dialogue.visible ? dialogue.children.filter(c => c.text !== undefined)
                                                          .map(c => c.text).join(" | ") : "",
            padInUse: game.padInUse,
            hint: hint && hint.visible ? hint.text : "",
            keyboard: c.keyboardSelected, gamepad: c.gamepadSelected,
            gamepadName: c.gamepad ? c.gamepad.name : "",
            screenX: game.playerScreenX, screenY: game.playerScreenY,
            chargeTime: Balance.knight.chargeTime
        })
    }

    // A knight hurt by half, with a potion to drink
    function hurtWithPotion() {
        let p = game.player
        p.hp = Math.ceil(p.maxHp / 2)
        p.potions = 1
        return p.potions
    }

    // A grunt 4 wu right of the knight, to lock on to
    function gruntNear() {
        let p = game.player
        game.spawnEnemy(p.xWu + 4, p.yWu, 0, "grunt", 1)
        return true
    }

    // Momentum and mana for a whirlwind, a draught and little mana
    function readyToWhirl() {
        let p = game.player
        p.momentum = Balance.momentum.max
        p.mana = p.maxMana
        return true
    }
    function lowWithDraught() {
        let p = game.player
        p.mana = 1
        p.draughts = 1
        return p.draughts
    }

    function toVillage() {
        game.applyScenario("village", 0)
        return game.player !== null
    }
    // The knight beside the first NPC who sells more than one thing, with
    // gold to pay; its name
    function besideSeller() {
        let p = game.player
        for (let n of game.room.children) {
            if (n.objectName !== "npc" || !n.wares || n.wares.length < 2) continue
            p.xWu = n.xWu + n.widthWu + 0.2
            p.yWu = n.yWu
            p.gold = 999
            return n.npcName
        }
        return ""
    }

    // ---- a physical pad ----

    function backend() { return GamepadHub.backend }
    function plugPad(name) { return GamepadHub.attachVirtualGamepad(name) }
    function padInput(id, input, value) { return GamepadHub.setVirtualGamepadInput(id, input, value) }
    function unplugPad(id) { return GamepadHub.detachVirtualGamepad(id) }
}
