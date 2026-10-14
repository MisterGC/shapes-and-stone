#version 440
// Moths circling the camp's lights (issue #149): the campfire and the
// lanterns are up to six homes l0..l5 (x, y in wu from the rectangle's
// south-west corner, the loop's radius, how many moths), and every moth
// is a hash of its light and its number, going round on its own slow,
// uneven loop - all of them in one pass and no item per moth. A pixel far
// from every light leaves after six box tests. Output is additive like
// the motes': premultiplied colour with zero alpha adds light.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sizeWu;
    float time;
    float pixelsPerWu;
    float seed;
    float squash;      // the loop's north-south share of its east-west
    float swell;       // share of its radius the loop swells and shrinks by
    vec2 speed;        // radians a second, slowest and fastest
    float waver;       // how unevenly a moth goes round
    float dart;        // wu a moth darts aside
    float mothSize;    // wingspan in wu
    float flutter;     // wingbeats a second
    vec4 l0;
    vec4 l1;
    vec4 l2;
    vec4 l3;
    vec4 l4;
    vec4 l5;
    vec4 color;
} ubuf;

float hash(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

// How much of moth id, circling home at orbit, covers p
float moth(vec2 p, vec2 home, float orbit, float id) {
    float h0 = hash(vec2(id, ubuf.seed));
    float h1 = hash(vec2(id + 3.1, ubuf.seed));
    float h2 = hash(vec2(id + 5.7, ubuf.seed));
    float h3 = hash(vec2(id + 8.3, ubuf.seed));
    float t = ubuf.time;
    float ph = h2 * 6.2831;
    float way = h0 < 0.5 ? -1.0 : 1.0;
    // Round its light, now faster, now slower, the loop swelling and
    // shrinking, and a dart aside now and then
    float a = way * mix(ubuf.speed.x, ubuf.speed.y, h1) * t + ph
              + ubuf.waver * sin(t * (0.7 + 0.6 * h3) + ph * 2.0);
    float r = orbit * (1.0 + 0.5 * ubuf.swell * sin(t * (0.3 + 0.4 * h1) + ph * 3.0));
    vec2 pos = home + r * vec2(cos(a), ubuf.squash * sin(a));
    pos += ubuf.dart * vec2(sin(t * (2.3 + 1.7 * h0) + ph * 7.0) * sin(t * 0.9 + ph),
                            cos(t * (1.9 + 1.5 * h2) + ph * 5.0) * sin(t * 0.7 + ph * 3.0));
    // Wings beating: as wide as the wingspan, folded to a third of it
    float beat = abs(sin(t * ubuf.flutter * 3.1416 + ph * 11.0));
    vec2 q = p - pos;
    vec2 wing = vec2(0.5 * ubuf.mothSize * (0.35 + 0.65 * beat), 0.22 * ubuf.mothSize);
    float d = length(q / wing);
    return (1.0 - smoothstep(0.7, 1.0, d)) * (0.55 + 0.45 * beat);
}

float light(vec2 p, vec4 l, float k) {
    if (l.w < 0.5) return 0.0;
    vec2 d = abs(p - l.xy);
    float reach = l.z * (1.0 + 0.5 * ubuf.swell) + ubuf.dart + ubuf.mothSize;
    if (d.x > reach || d.y > reach) return 0.0;
    float g = 0.0;
    for (int m = 0; m < 8; m++) {
        if (float(m) >= l.w) break;
        g = max(g, moth(p, l.xy, l.z, k * 8.0 + float(m)));
    }
    return g;
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y) * ubuf.sizeWu;
    // Snap to the same chunky pixel grid as the floor
    p = (floor(p * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    float g = max(max(light(p, ubuf.l0, 0.0), light(p, ubuf.l1, 1.0)),
                  max(light(p, ubuf.l2, 2.0), light(p, ubuf.l3, 3.0)));
    g = max(g, max(light(p, ubuf.l4, 4.0), light(p, ubuf.l5, 5.0)));
    fragColor = vec4(ubuf.color.rgb * g * ubuf.color.a, 0.0) * ubuf.qt_Opacity;
}
