import QtQuick
import Box2D
import Clayground.Physics

RectBoxBody {
    id: wall

    Component.onCompleted: {
        console.log("[Wall] Created at xWu:", xWu, "yWu:", yWu, "wWu:", widthWu, "hWu:", heightWu,
                    "-> pixels x:", x, "y:", y, "w:", width, "h:", height)
    }

    // Physics config - static, immovable
    bodyType: Body.Static
    friction: 0.0      // No friction so players slide along walls
    restitution: 0.0   // No bounce

    // Visual: Dark stone color
    color: "#2C3E50"

    // Subtle border for definition
    border.color: "#1A252F"
    border.width: 1
}
