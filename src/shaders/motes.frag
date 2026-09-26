#version 440
// Floating motes in world space: dust in the dungeon air, fireflies over the
// village. Every mote is a hash of its grid cell, drifting on its own slow
// orbit - hundreds of them for one full-screen pass and no per-mote cost.
// Output is additive: premultiplied colour with zero alpha adds light.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sizeWu;
    float time;
    float pixelsPerWu;
    float density;     // 0..1 share of cells holding a mote
    float moteSize;    // radius in world units
    float blink;       // 0 = steady dust, 1 = fireflies pulsing on and off
    float drift;       // orbit radius in world units
    vec4 color;
} ubuf;

float hash(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

float layer(vec2 p, float cellWu, float speed, float seed) {
    vec2 cell = floor(p / cellWu);
    float glow = 0.0;
    // A mote can orbit into a neighbouring cell, so look one cell around.
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = cell + vec2(float(i), float(j));
            float h = hash(c + seed);
            if (h > ubuf.density) continue;
            float ph = hash(c + seed + 7.3) * 6.2831;
            float t = ubuf.time * speed + ph;
            vec2 home = (c + vec2(hash(c + 1.1), hash(c + 2.7))) * cellWu;
            vec2 pos = home + ubuf.drift * vec2(sin(t * 0.7), cos(t * 0.53 + ph));
            float d = length(p - pos);
            float r = ubuf.moteSize * (0.6 + 0.8 * hash(c + 4.4));
            float on = 1.0;
            if (ubuf.blink > 0.5) on = smoothstep(0.55, 0.95, sin(t * 1.3 + ph * 3.0));
            else on = 0.55 + 0.45 * sin(t * 2.1 + ph);
            glow += on * (1.0 - smoothstep(r * 0.4, r, d));
            // Fireflies carry a soft halo around the bright core
            if (ubuf.blink > 0.5) glow += on * 0.25 * (1.0 - smoothstep(r, r * 4.0, d));
        }
    }
    return glow;
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y) * ubuf.sizeWu;
    // Snap to the same chunky pixel grid as the floor
    p = (floor(p * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    float g = layer(p, 1.7, 0.35, 0.0) + 0.6 * layer(p, 1.1, 0.5, 13.0);
    g = clamp(g, 0.0, 1.0);
    fragColor = vec4(ubuf.color.rgb * g * ubuf.color.a, 0.0) * ubuf.qt_Opacity;
}
