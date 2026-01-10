import QtQuick
import Box2D
import Clayground.Physics

RectBoxBody {
    id: wall

    // Physics config - static, immovable
    bodyType: Body.Static

    // Visual: Dark stone color
    color: "#2C3E50"

    // Subtle border for definition
    border.color: "#1A252F"
    border.width: 1
}
