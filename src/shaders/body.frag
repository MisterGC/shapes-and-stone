#version 440
// Cel shading for a round body, lit from the top-left like the floor and the
// walls: a hard light crescent, a hard shadow crescent and a dark outline,
// drawn over the body's own flat colour. Output is a premultiplied overlay.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 outlineColor;
    float outline;     // outline width as a fraction of the radius
} ubuf;

void main() {
    vec2 p = qt_TexCoord0 * 2.0 - 1.0;          // -1..1, y down
    float d = length(p);
    if (d > 1.0) { fragColor = vec4(0.0); return; }
    vec4 c = vec4(0.0);
    // Points far from a circle shifted towards the light are on the shadow
    // side, and the other way round for the light crescent.
    if (length(p - vec2(-0.16, -0.16)) > 0.9)
        c = vec4(0.0, 0.0, 0.0, 0.3);
    else if (length(p - vec2(0.2, 0.2)) > 0.94)
        c = vec4(vec3(0.28), 0.28);
    if (d > 1.0 - ubuf.outline)
        c = vec4(ubuf.outlineColor.rgb, 1.0);
    fragColor = c * ubuf.qt_Opacity;
}
