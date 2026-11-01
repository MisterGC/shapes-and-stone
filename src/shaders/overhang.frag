#version 440
// The rock overhanging a cave edge, over its wall face and the floor below:
// a ragged lip of rock hangs over the top of the face, stalactites hang
// from it, and each stalactite drops a shadow onto the floor. Every
// stalactite is a hash of its stretch of the edge, so one pass draws them
// all. Computed in world units on the same chunky pixel grid as the walls.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 originWu;      // world position of the item's top-left corner
    vec2 sizeWu;
    float pixelsPerWu;
    float faceWu;       // height of the wall face below the item's top
    float lipWu;        // how far the lip hangs over the face, at most
    float stalactiteWu; // longest stalactite below the lip
    float toothWu;      // about one stalactite per this much edge
    float shadowWu;     // longest shadow on the floor below the face
    float seed;
    vec4 baseColor;
} ubuf;

float hash(vec2 p) {
    p = fract(p * vec2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

// Smooth noise along the edge, 0..1
float edgeNoise(float x) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash(vec2(i, ubuf.seed)), hash(vec2(i + 1.0, ubuf.seed)), f);
}

void main() {
    vec2 local = qt_TexCoord0 * ubuf.sizeWu;                  // y down
    local = (floor(local * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    float x = ubuf.originWu.x + local.x;
    float y = local.y;
    float px = 1.0 / ubuf.pixelsPerWu;

    // The lip: rock down to a ragged line over the face
    float lip = ubuf.lipWu * (0.35 + 0.65 * edgeNoise(x * 1.3));
    float rock = y < lip ? 1.0 : 0.0;
    float underside = (y < lip && y > lip - px) ? 1.0 : 0.0;
    float shade = 0.0;

    // Stalactites, one chance per stretch of toothWu; a neighbour's can
    // reach over, so look one stretch to either side
    float cell = floor(x / ubuf.toothWu);
    for (int k = -1; k <= 1; k++) {
        float c = cell + float(k);
        float h = hash(vec2(c, ubuf.seed + 3.1));
        if (h < 0.3) continue;
        float xc = (c + 0.2 + 0.6 * hash(vec2(c, ubuf.seed + 5.7))) * ubuf.toothWu;
        float halfW = ubuf.toothWu * (0.1 + 0.12 * hash(vec2(c, ubuf.seed + 8.3)));
        float len = ubuf.stalactiteWu * (0.35 + 0.65 * hash(vec2(c, ubuf.seed + 9.9)));
        float top = ubuf.lipWu * (0.35 + 0.65 * edgeNoise(xc * 1.3)) - px;
        float t = (y - top) / len;
        float dx = abs(x - xc);
        if (t >= 0.0 && t <= 1.0 && dx < halfW * (1.0 - t)) {
            rock = 1.0;
            if (dx > halfW * (1.0 - t) - px) underside = 1.0;
        }
        // Its shadow on the floor below the face, longer for a longer one
        float fy = y - ubuf.faceWu;
        float fl = ubuf.shadowWu * len / ubuf.stalactiteWu;
        if (fy > 0.0 && fy < fl) {
            float s = fy / fl;
            float w = halfW * 1.8 * (1.0 - 0.7 * s);
            shade = max(shade, 0.45 * (1.0 - s) * (1.0 - smoothstep(w * 0.5, w, dx)));
        }
    }

    if (rock > 0.5) {
        vec3 col = ubuf.baseColor.rgb * 0.62 * (0.92 + 0.12 * hash(floor(vec2(x, y) * 0.8)));
        if (underside > 0.5) col *= 0.6;
        fragColor = vec4(col, 1.0) * ubuf.qt_Opacity;
        return;
    }
    fragColor = vec4(0.0, 0.0, 0.0, shade) * ubuf.qt_Opacity;
}
