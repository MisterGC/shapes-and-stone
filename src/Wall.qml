import QtQuick
import Box2D
import Clayground.Physics

RectBoxBody {
    id: wall

    // Physics config - static, immovable
    bodyType: Body.Static
    friction: 0.0      // No friction so players slide along walls
    restitution: 0.0   // No bounce

    // Visual: Dark stone color (no border)
    color: "#2C3E50"
}
