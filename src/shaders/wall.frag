#version 440
// Procedural wall: the rock top of a wall run, or (face > 0.5) the brick
// face a wall shows towards the floor south of it. Computed in world units
// so neighbouring pieces continue each other's pattern.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 originWu;     // world position of the item's top-left corner
    vec2 sizeWu;
    float pixelsPerWu;
    float face;        // 0 = rock top, 1 = brick face
    vec4 baseColor;
} ubuf;

float hash(vec2 p) {
    p = fract(p * vec2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

vec3 rockTop(vec2 p, vec2 local) {
    // Solid rock seen from above: dark and quiet, so the lit faces and the
    // floor carry the detail. Large soft blotches, rare grit.
    vec2 cell = floor(p * 0.8);
    float h = hash(cell);
    vec3 col = ubuf.baseColor.rgb * 0.62 * (0.92 + 0.12 * h);
    float g = hash(floor(p * ubuf.pixelsPerWu));
    if (g > 0.985) col *= 1.2;
    else if (g < 0.02) col *= 0.8;
    return col;
}

vec3 brickFace(vec2 p, vec2 local) {
    // Courses of bricks, 0.25 wu high, offset every other course.
    float courseH = 0.25;
    float course = floor(local.y / courseH);
    float bw = 0.6;
    float x = p.x + (mod(course, 2.0) == 0.0 ? 0.0 : bw * 0.5);
    vec2 brick = vec2(floor(x / bw), course);
    vec2 f = vec2(fract(x / bw) * bw, local.y - course * courseH);
    float h = hash(brick + floor(p.y));
    vec3 col = ubuf.baseColor.rgb * (0.85 + 0.25 * h);
    float px = 1.0 / ubuf.pixelsPerWu;
    if (f.y < px || f.x < px) return ubuf.baseColor.rgb * 0.45;
    if (f.y < 2.0 * px) col *= 1.15;
    // The face darkens towards its foot, where it meets the floor.
    col *= mix(1.0, 0.72, local.y / ubuf.sizeWu.y);
    return col;
}

void main() {
    vec2 local = qt_TexCoord0 * ubuf.sizeWu;                  // y down
    vec2 p = vec2(ubuf.originWu.x + local.x, ubuf.originWu.y - local.y);
    local = (floor(local * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    p = (floor(p * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    vec3 col = ubuf.face < 0.5 ? rockTop(p, local) : brickFace(p, local);
    fragColor = vec4(col, 1.0) * ubuf.qt_Opacity;
}
