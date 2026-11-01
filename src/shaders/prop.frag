#version 440
// The camp's props (issue #146), seen from above: one pass draws a whole
// prop of its kind - a pond, a cluster of stones, a rail track, a heap of
// coals - from hashes of its own cells, as the motes are drawn. Computed in
// world units on the same chunky pixel grid as the floor. Lit kinds give
// premultiplied colour; the glowing kinds (mushrooms, cracks, coals) are
// drawn over the darkness and add light: colour with zero alpha.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sizeWu;
    float pixelsPerWu;
    float kind;   // the index in CampProp.kinds
    float seed;
    float time;
} ubuf;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21) + ubuf.seed);
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Paints col at coverage a over what is painted so far (premultiplied)
void put(inout vec4 acc, vec3 col, float a) {
    acc = vec4(col * a, a) + acc * (1.0 - a);
}

// Distance in the ellipse filling the prop: 1 at its edge
float oval(vec2 p, float wobble) {
    vec2 c = ubuf.sizeWu * 0.5;
    return length((p - c) / c) + wobble * (noise(p * 1.5) - 0.5);
}

vec4 pond(vec2 p) {
    vec4 acc = vec4(0.0);
    float e = oval(p, 0.18);
    if (e > 1.0) return acc;
    if (e > 0.82) {
        // A rim of mossy stones
        float h = hash(floor(p * 3.0));
        put(acc, mix(vec3(0.2, 0.26, 0.2), vec3(0.16, 0.3, 0.12), h) * (0.8 + 0.3 * h), 1.0);
        return acc;
    }
    vec3 col = mix(vec3(0.06, 0.2, 0.22), vec3(0.02, 0.08, 0.1), smoothstep(0.1, 0.8, 1.0 - e));
    // Slow rings from a drip at the middle, and glints
    float r = length(p - ubuf.sizeWu * vec2(0.45, 0.55));
    float ring = sin(r * 7.0 - ubuf.time * 1.4);
    col += vec3(0.06, 0.12, 0.12) * smoothstep(0.92, 1.0, ring) * (1.0 - e);
    if (hash(floor(p * ubuf.pixelsPerWu) + floor(ubuf.time * 0.7)) > 0.995) col += 0.12;
    // Lily pads
    vec2 cell = floor(p / 0.9);
    if (hash(cell + 3.0) > 0.7) {
        vec2 c = (cell + 0.3 + 0.4 * vec2(hash(cell + 1.0), hash(cell + 2.0))) * 0.9;
        float d = length(p - c);
        float notch = abs(atan(p.y - c.y, p.x - c.x) - 0.6 + hash(cell) * 2.0) < 0.3 ? 1.0 : 0.0;
        if (d < 0.2 && notch < 0.5 && e < 0.75) col = vec3(0.16, 0.34, 0.14) * (0.8 + 0.6 * (c.y - p.y + 0.2));
    }
    put(acc, col, 1.0);
    return acc;
}

// Boulders in the prop's ellipse, the southern ones painted over the
// northern ones; mossy on top when moss > 0
vec4 boulders(vec2 p, vec3 base, float moss, float count) {
    vec4 acc = vec4(0.0);
    vec2 s = ubuf.sizeWu;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        if (fi >= count) break;
        vec2 c = s * vec2(0.2 + 0.6 * hash(vec2(fi, 1.0)), 0.25 + 0.5 * fi / max(count - 1.0, 1.0));
        float r = min(s.x, s.y) * (0.22 + 0.14 * hash(vec2(fi, 2.0)));
        vec2 q = (p - c) / vec2(1.0, 0.8);
        float d = length(q) + 0.12 * r * (noise(p * 4.0 + fi) - 0.5);
        if (d > r) {
            // Its contact shadow just south of it
            if (length((p - c - vec2(0.0, r * 0.35)) / vec2(1.0, 0.7)) < r) put(acc, vec3(0.0), 0.35);
            continue;
        }
        // Lit from the top of the screen
        float lit = 0.75 + 0.45 * clamp(-q.y / r, -1.0, 1.0) * 0.5 + 0.1 * hash(floor(p * ubuf.pixelsPerWu));
        vec3 col = base * lit;
        if (moss > 0.0 && q.y < -0.15 * r + 0.25 * r * noise(p * 5.0))
            col = mix(col, vec3(0.18, 0.32, 0.12) * lit, moss);
        put(acc, col, 1.0);
    }
    return acc;
}

vec4 mushrooms(vec2 p) {
    vec4 acc = vec4(0.0);
    vec2 cell = floor(p / 0.45);
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 cc = cell + vec2(float(i), float(j));
            float h = hash(cc);
            vec2 c = (cc + 0.2 + 0.6 * vec2(hash(cc + 1.0), hash(cc + 2.0))) * 0.45;
            if (h > 0.55 || oval(c, 0.0) > 0.9) continue;
            float r = 0.08 + 0.08 * hash(cc + 3.0);
            float d = length(p - c);
            float pulse = 0.7 + 0.3 * sin(ubuf.time * 0.8 + h * 30.0);
            vec3 col = mix(vec3(0.3, 0.9, 0.8), vec3(0.55, 0.8, 1.0), hash(cc + 4.0));
            acc.rgb += col * pulse * ((d < r ? 0.55 : 0.0) + 0.12 * (1.0 - smoothstep(r, r * 3.5, d)));
        }
    return vec4(acc.rgb, 0.0);
}

vec4 ferns(vec2 p) {
    vec4 acc = vec4(0.0);
    vec2 cell = floor(p / 1.2);
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 cc = cell + vec2(float(i), float(j));
            vec2 c = (cc + 0.3 + 0.4 * vec2(hash(cc + 1.0), hash(cc + 2.0))) * 1.2;
            if (hash(cc) > 0.75 || oval(c, 0.0) > 0.85) continue;
            vec2 q = p - c;
            float a = atan(q.y, q.x) + hash(cc + 5.0) * 6.28;
            float R = 0.55 + 0.25 * hash(cc + 3.0);
            float frond = abs(sin(a * 3.5));
            float d = length(q);
            if (d < R * (0.25 + 0.75 * pow(frond, 6.0)) && frond > 0.5) {
                float leaf = step(0.5, fract(d * 7.0 + a));
                put(acc, mix(vec3(0.12, 0.3, 0.1), vec3(0.24, 0.44, 0.16), 1.0 - d / R) * (0.85 + 0.2 * leaf), 1.0);
            }
        }
    return acc;
}

// Along the prop's long side: u along, v across
vec2 track(vec2 p) {
    return ubuf.sizeWu.x >= ubuf.sizeWu.y ? p : p.yx;
}

vec4 rails(vec2 p) {
    vec4 acc = vec4(0.0);
    vec2 t = track(p);
    float across = min(ubuf.sizeWu.x, ubuf.sizeWu.y);
    float px = 1.0 / ubuf.pixelsPerWu;
    float sleeper = mod(t.x + 0.05, 0.55);
    if (sleeper < 0.24 && t.y > across * 0.08 && t.y < across * 0.92)
        put(acc, vec3(0.32, 0.22, 0.13) * (0.85 + 0.3 * hash(vec2(floor((t.x + 0.05) / 0.55), 1.0))), 1.0);
    for (int k = 0; k < 2; k++) {
        float v = across * (k == 0 ? 0.28 : 0.72);
        float d = t.y - v;
        if (abs(d) < 1.5 * px) put(acc, d < 0.0 ? vec3(0.62, 0.6, 0.56) : vec3(0.3, 0.29, 0.28), 1.0);
    }
    return acc;
}

vec4 cart(vec2 p) {
    vec4 acc = vec4(0.0);
    vec2 s = ubuf.sizeWu;
    float px = 1.0 / ubuf.pixelsPerWu;
    vec2 m = min(p, s - p);
    if (m.x < 0.0 || m.y < 0.0) return acc;
    // An iron rim, the ore heaped inside it
    if (min(m.x, m.y) < 2.5 * px) {
        put(acc, vec3(0.27, 0.25, 0.24) * (m.y < px && p.y < s.y * 0.5 ? 1.4 : 1.0), 1.0);
        return acc;
    }
    vec2 cell = floor(p * 4.0);
    float h = hash(cell);
    vec3 col = mix(vec3(0.3, 0.27, 0.24), vec3(0.45, 0.36, 0.25), h);
    if (h > 0.86) col = vec3(0.78, 0.5, 0.2);
    col *= 0.8 + 0.4 * (1.0 - fract(p.y * 4.0));
    put(acc, col, 1.0);
    return acc;
}

vec4 crates(vec2 p) {
    vec4 acc = vec4(0.0);
    float side = 1.25;
    vec2 cell = floor(p / side);
    vec2 f = p - cell * side;
    vec2 n = floor(ubuf.sizeWu / side);
    if (cell.x >= n.x || cell.y >= n.y || hash(cell) < 0.2) return acc;
    float px = 1.0 / ubuf.pixelsPerWu;
    float inset = 0.08;
    vec2 m = min(f - inset, side - inset - f);
    if (m.x < 0.0 || m.y < 0.0) {
        if (f.y > side - inset && f.x > inset) put(acc, vec3(0.0), 0.4);
        return acc;
    }
    vec3 col = vec3(0.52, 0.38, 0.2) * (0.85 + 0.25 * hash(cell + 1.0));
    if (fract(f.y / 0.27) < 0.12) col *= 0.75;
    if (min(m.x, m.y) < 2.0 * px) col = vec3(0.32, 0.22, 0.12);
    else if (abs(f.x - f.y) < 1.5 * px || abs(f.x + f.y - side) < 1.5 * px) col = vec3(0.4, 0.28, 0.15);
    if (m.y < 1.0 * px && f.y < side * 0.5) col *= 1.3;
    put(acc, col, 1.0);
    return acc;
}

vec4 ore(vec2 p) {
    vec4 acc = vec4(0.0);
    float e = oval(p, 0.35);
    if (e > 1.0) {
        if (e < 1.15 && p.y > ubuf.sizeWu.y * 0.5) put(acc, vec3(0.0), 0.3);
        return acc;
    }
    vec2 cell = floor(p * 3.5);
    float h = hash(cell);
    vec3 col = mix(vec3(0.26, 0.23, 0.2), vec3(0.4, 0.33, 0.24), h);
    if (h > 0.9) col = vec3(0.8, 0.52, 0.22);
    float f = fract(p.y * 3.5);
    col *= (0.7 + 0.5 * (1.0 - f)) * (1.05 - 0.4 * e);
    put(acc, col, 1.0);
    return acc;
}

vec4 timber(vec2 p) {
    vec4 acc = vec4(0.0);
    // Logs along the long side, a row each 0.5 wu
    vec2 t = track(p);
    float len = max(ubuf.sizeWu.x, ubuf.sizeWu.y);
    float row = floor(t.y / 0.5);
    float v = fract(t.y / 0.5);
    float shift = 0.3 * hash(vec2(row, 7.0));
    if (t.x < shift || t.x > len - 0.3 * hash(vec2(row, 8.0))) return acc;
    vec3 col = vec3(0.4, 0.27, 0.15) * (0.75 + 0.45 * sin(v * 3.1416));
    if (v < 0.08 || v > 0.92) col *= 0.5;
    // The cut ends show their rings
    float end = min(t.x - shift, 10.0);
    if (end < 0.12) col = mix(vec3(0.62, 0.48, 0.3), vec3(0.45, 0.32, 0.18), step(0.5, fract(length(vec2(end, v - 0.5)) * 12.0)));
    put(acc, col, 1.0);
    return acc;
}

vec4 basalt(vec2 p) {
    vec4 acc = vec4(0.0);
    // Hexagonal column tops
    vec2 s = vec2(0.62, 0.54);
    vec2 q = p / s;
    q.x += mod(floor(q.y), 2.0) * 0.5;
    vec2 cell = floor(q);
    vec2 f = fract(q) - 0.5;
    vec2 c = (cell + 0.5 - vec2(mod(cell.y, 2.0) * 0.5, 0.0)) * s;
    if (oval(c, 0.3) > 0.95 || hash(cell) < 0.15) return acc;
    float edge = max(abs(f.x) * 1.15 + abs(f.y) * 0.6, abs(f.y) * 1.15);
    float h = hash(cell + 2.0);
    vec3 col = vec3(0.34, 0.32, 0.33) * (0.75 + 0.6 * h);
    if (edge > 0.5) col = vec3(0.05, 0.04, 0.04);
    else if (f.y < -0.3) col *= 1.35;
    put(acc, col, 1.0);
    return acc;
}

vec4 cracks(vec2 p) {
    float fade = 1.0 - smoothstep(0.6, 1.0, oval(p, 0.3));
    float n = noise(p * 0.9) * 0.65 + noise(p * 2.3) * 0.35;
    float d = abs(n - 0.5);
    float pulse = 0.75 + 0.25 * sin(ubuf.time * 0.6 + p.x * 0.7);
    float core = 1.0 - smoothstep(0.012, 0.02, d);
    float halo = 1.0 - smoothstep(0.02, 0.08, d);
    vec3 col = vec3(1.0, 0.36, 0.08) * core * 0.9 + vec3(0.6, 0.12, 0.02) * halo * 0.35;
    return vec4(col * fade * pulse, 0.0);
}

vec4 coals(vec2 p) {
    float e = oval(p, 0.3);
    if (e > 1.0) return vec4(0.0);
    vec2 cell = floor(p * 4.0);
    float h = hash(cell);
    float flicker = 0.6 + 0.4 * sin(ubuf.time * (1.0 + 2.0 * h) + h * 40.0);
    float lump = 1.0 - smoothstep(0.25, 0.5, length(fract(p * 4.0) - 0.5));
    vec3 col = mix(vec3(0.9, 0.2, 0.04), vec3(1.0, 0.6, 0.15), h) * lump * flicker * (1.0 - e * 0.7);
    return vec4(col * (h > 0.3 ? 0.8 : 0.2), 0.0);
}

vec4 slag(vec2 p) {
    vec4 acc = vec4(0.0);
    float e = oval(p, 0.5);
    if (e > 1.0) return acc;
    float n = noise(p * 2.5);
    vec3 col = vec3(0.08, 0.07, 0.08) * (0.8 + 0.6 * n);
    if (e > 0.85) col = vec3(0.32, 0.1, 0.05);
    if (n > 0.72) col += vec3(0.12, 0.1, 0.12);
    put(acc, col, 1.0);
    return acc;
}

void main() {
    // Local position in wu, y down
    vec2 p = qt_TexCoord0 * ubuf.sizeWu;
    p = (floor(p * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    int k = int(ubuf.kind + 0.5);
    vec4 col;
    if (k == 0) col = pond(p);
    else if (k == 1) col = boulders(p, vec3(0.3, 0.32, 0.3), 0.75, 4.0);
    else if (k == 2) col = mushrooms(p);
    else if (k == 3) col = ferns(p);
    else if (k == 4) col = rails(p);
    else if (k == 5) col = cart(p);
    else if (k == 6) col = crates(p);
    else if (k == 7) col = ore(p);
    else if (k == 8) col = timber(p);
    else if (k == 9) col = basalt(p);
    else if (k == 10) col = cracks(p);
    else if (k == 11) col = coals(p);
    else col = slag(p);
    fragColor = col * ubuf.qt_Opacity;
}
