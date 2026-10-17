#version 440
// Procedural wall: the rock top of a wall run, or (face > 0.5) the face a
// wall shows towards the floor south of it: bricks, or in the camps (issue
// #146) rough rock under moss, rock strata between timber props, or
// basalt columns, or round a vein (issue #169) a miners' rough rock face,
// its ends ragged where bricks go on. Computed in world units so
// neighbouring pieces continue each other's pattern.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 originWu;     // world position of the item's top-left corner
    vec2 sizeWu;
    float pixelsPerWu;
    float face;        // 0 = rock top, 1 = face
    float faceStyle;   // 0 = bricks, 1 = moss, 2 = strata, 3 = basalt, 4 = rock
    vec4 baseColor;
    vec2 ragged;       // wu at the left and the right end that break off
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

vec3 mossFace(vec2 p, vec2 local) {
    // Rough blocks of rock, moss hanging from the top in tongues
    vec2 q = vec2(p.x / 0.45, local.y / 0.22);
    q.x += hash(vec2(floor(q.y), 3.0)) * 0.8;
    vec2 cell = floor(q);
    vec2 f = fract(q);
    float h = hash(cell);
    vec3 col = ubuf.baseColor.rgb * (0.78 + 0.35 * h);
    if (f.x < 0.08 || f.y < 0.1) col = ubuf.baseColor.rgb * 0.5;
    float tongue = 0.12 + 0.3 * hash(vec2(floor(p.x * 5.0), 9.0)) * hash(vec2(floor(p.x * 1.3), 4.0));
    if (local.y < tongue) col = mix(vec3(0.16, 0.3, 0.12), vec3(0.24, 0.42, 0.16), hash(floor(p * ubuf.pixelsPerWu)));
    col *= mix(1.0, 0.7, local.y / ubuf.sizeWu.y);
    return col;
}

vec3 strataFace(vec2 p, vec2 local) {
    // A timber prop every 4 wu and a beam along the top
    float px = 1.0 / ubuf.pixelsPerWu;
    float post = mod(p.x, 4.0);
    if (post < 0.24 || local.y < 0.09) {
        vec3 wood = vec3(0.42, 0.28, 0.15) * (0.85 + 0.2 * hash(vec2(floor(p.x / 4.0), floor(local.y * 12.0))));
        if (post < px || post > 0.24 - px || abs(local.y - 0.09) < px) wood *= 0.6;
        return wood * mix(1.0, 0.75, local.y / ubuf.sizeWu.y);
    }
    // Bands of rock, wavy, each its own shade of the ochre
    float y = local.y + 0.05 * sin(p.x * 1.7) + 0.03 * sin(p.x * 4.3);
    float band = floor(y / 0.11);
    float h = hash(vec2(band, 5.0));
    vec3 col = ubuf.baseColor.rgb * (0.7 + 0.5 * h);
    if (hash(vec2(band, 6.0)) > 0.75) col = mix(col, vec3(0.42, 0.4, 0.38), 0.5);
    if (fract(y / 0.11) < 0.1) col *= 0.75;
    if (hash(floor(p * ubuf.pixelsPerWu)) > 0.97) col *= 1.2;
    col *= mix(1.0, 0.72, local.y / ubuf.sizeWu.y);
    return col;
}

vec3 basaltFace(vec2 p, vec2 local) {
    // Columns of basalt, each its own width, a warm crack here and there
    float x = p.x / 0.32;
    float column = floor(x + 0.3 * sin(floor(x) * 1.7));
    float f = fract(x + 0.3 * sin(floor(x) * 1.7));
    float h = hash(vec2(column, 2.0));
    vec3 col = ubuf.baseColor.rgb * (0.75 + 0.4 * h);
    if (f < 0.12) col = ubuf.baseColor.rgb * 0.4;
    else if (f < 0.24) col *= 1.15;
    float joint = fract(local.y / 0.3 + h);
    if (joint < 0.06) col *= 0.6;
    if (h > 0.88 && f > 0.45 && f < 0.55) col = vec3(0.55, 0.16, 0.05);
    col *= mix(1.0, 0.7, local.y / ubuf.sizeWu.y);
    return col;
}

vec3 rockFace(vec2 p, vec2 local) {
    // A miners' face: rough chunks of rock, each two flat facets, one lit
    // from the upper left, dark seams between them, and pick scars here
    // and there
    vec2 q = vec2(p.x / 0.62, local.y / 0.36);
    vec2 cell = floor(q);
    vec2 f = fract(q);
    float d1 = 9.0, d2 = 9.0;
    vec2 best = cell, bestPt = vec2(0.5);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = cell + vec2(i, j);
            vec2 pt = vec2(i, j) + 0.15 + 0.7 * vec2(hash(c), hash(c + 17.0));
            float d = length(pt - f);
            if (d < d1) { d2 = d1; d1 = d; best = c; bestPt = pt; }
            else if (d < d2) d2 = d;
        }
    }
    vec3 base = ubuf.baseColor.rgb;
    float h = hash(best);
    vec3 col = base * (0.72 + 0.4 * h);
    float ang = 6.2832 * hash(best + 3.1);
    vec2 n = vec2(cos(ang), sin(ang));
    float side = dot(f - bestPt, n);
    float lit = dot(n, vec2(-0.6, -0.8));
    col *= side * lit > 0.0 ? 1.2 : 0.82;
    float seam = d2 - d1;
    if (seam < 0.06) col = base * 0.32;
    else if (seam < 0.1) col *= 0.75;
    if (h > 0.78) {
        vec2 s = f - bestPt;
        float along = dot(s, vec2(0.8, 0.6));
        float across = dot(s, vec2(-0.6, 0.8));
        if (abs(across) < 0.035 && abs(along) < 0.2) col = mix(col, vec3(0.8, 0.76, 0.68), 0.5);
    }
    col *= mix(1.0, 0.7, local.y / ubuf.sizeWu.y);
    return col;
}

void main() {
    vec2 local = qt_TexCoord0 * ubuf.sizeWu;                  // y down
    vec2 p = vec2(ubuf.originWu.x + local.x, ubuf.originWu.y - local.y);
    local = (floor(local * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    p = (floor(p * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    vec3 col = ubuf.face < 0.5 ? rockTop(p, local)
             : ubuf.faceStyle < 0.5 ? brickFace(p, local)
             : ubuf.faceStyle < 1.5 ? mossFace(p, local)
             : ubuf.faceStyle < 2.5 ? strataFace(p, local)
             : ubuf.faceStyle < 3.5 ? basaltFace(p, local)
             : rockFace(p, local);
    // Ragged ends: each course of chunks breaks off at its own place
    float course = floor(local.y / 0.12);
    float a = 1.0;
    if (local.x < ubuf.ragged.x * (0.3 + 0.7 * hash(vec2(course, floor(ubuf.originWu.x) + 3.0))))
        a = 0.0;
    if (ubuf.sizeWu.x - local.x < ubuf.ragged.y * (0.3 + 0.7 * hash(vec2(course, floor(ubuf.originWu.x) + 7.0))))
        a = 0.0;
    fragColor = vec4(col, 1.0) * a * ubuf.qt_Opacity;
}
