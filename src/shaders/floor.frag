#version 440
// Procedural floor: flagstones (dungeon) or trodden earth (village), computed
// in world units so the pattern stays fixed to the ground while the camera
// moves. No texture is sampled - every tile, seam and pebble is arithmetic.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sizeWu;       // floor size in world units
    float pixelsPerWu; // chunky pixel grid: detail snaps to 1/pixelsPerWu
    float stoneWu;     // flagstone size (a wide stone is twice as long)
    float seamPx;      // gap between stones, in chunky pixels (may be < 1)
    float style;       // 0 = flagstones, 1 = earth
    float seed;
    vec4 baseColor;
    vec4 seamColor;
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
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 flagstones(vec2 p, vec2 rawP) {
    // Rows of stones stoneWu wide, every other row shifted by half a stone,
    // with occasional double-length stones so the grid does not read as a
    // grid. The layout is worked out in stone units (s), so the stone size
    // is one uniform.
    vec2 s = p / ubuf.stoneWu;
    float row = floor(s.y);
    vec2 q = vec2(s.x + (mod(row, 2.0) == 0.0 ? 0.0 : 0.5), s.y);
    float wide = step(0.78, hash(vec2(floor(q.x * 0.5), row)));
    vec2 cellSize = vec2(1.0 + wide, 1.0);
    vec2 cell = floor(q / cellSize);
    vec2 f = fract(q / cellSize) * cellSize;

    float h = hash(cell + row * 7.0);
    vec3 col = ubuf.baseColor.rgb * (0.92 + 0.12 * h);
    // A faint hue drift per stone: cold stone next to warmer stone.
    col *= mix(vec3(0.98, 0.99, 1.02), vec3(1.02, 1.0, 0.97), hash(cell + 3.1));

    // Large, soft damp patches across many stones.
    col *= 0.88 + 0.22 * noise(p * 0.18);

    // Seams, with a one-pixel bevel: lit on the upper-left edge of a stone,
    // shaded on the lower-right, as if lit from the top of the screen.
    // One chunky pixel, in stone units. The seam alone is finer than the
    // grid: it is measured on the unsnapped position, seamPx pixels wide, so
    // the gaps stay thin while stones, bevels and cracks keep the chunky
    // look. The bevel is the first chunky pixel inside the stone.
    float px = 1.0 / (ubuf.pixelsPerWu * ubuf.stoneWu);
    vec2 rs = rawP / ubuf.stoneWu;
    float rrow = floor(rs.y);
    vec2 rq = vec2(rs.x + (mod(rrow, 2.0) == 0.0 ? 0.0 : 0.5), rs.y);
    float rwide = step(0.78, hash(vec2(floor(rq.x * 0.5), rrow)));
    vec2 rcell = vec2(1.0 + rwide, 1.0);
    vec2 rf = fract(rq / rcell) * rcell;
    float rEdge = min(min(rf.x, rcell.x - rf.x), min(rf.y, rcell.y - rf.y));
    if (rEdge < px * ubuf.seamPx * 0.5)
        return ubuf.seamColor.rgb;
    float edgeL = f.x;
    float edgeR = cellSize.x - f.x;
    float edgeT = cellSize.y - f.y;
    float edgeB = f.y;
    if (edgeT < px || edgeL < px)
        col *= 1.08;
    else if (edgeB < px || edgeR < px)
        col *= 0.88;

    // A jagged crack across the odd stone: straight segments that change
    // direction at a few hashed points, never a smooth wave.
    if (h > 0.965) {
        float seg = floor(f.x * 4.0);
        float y0 = 0.3 + 0.4 * hash(cell + seg);
        float y1 = 0.3 + 0.4 * hash(cell + seg + 1.0);
        float yc = mix(y0, y1, fract(f.x * 4.0));
        if (abs(f.y - yc) < px * 0.6) col *= 0.7;
    }
    // Pits and grit.
    if (hash(floor(p * ubuf.pixelsPerWu)) > 0.99) col *= 0.82;
    return col;
}

vec3 earth(vec2 p) {
    // Trodden ground: two scales of soft patches, sparse pebbles and tufts.
    float n = noise(p * 0.35) * 0.6 + noise(p * 1.3) * 0.4;
    vec3 col = ubuf.baseColor.rgb * (0.82 + 0.3 * n);
    // Tufts of grass take over where the ground is least trodden.
    float grass = smoothstep(0.62, 0.7, noise(p * 0.22 + 9.0));
    col = mix(col, vec3(0.15, 0.22, 0.17), grass * 0.45);

    vec2 cell = floor(p * 2.0);
    float h = hash(cell);
    if (h > 0.975) {
        vec2 c = (cell + 0.5 + (vec2(hash(cell + 1.7), hash(cell + 2.3)) - 0.5) * 0.5) / 2.0;
        float r = 0.04 + 0.04 * hash(cell + 5.0);
        float d = length(p - c);
        if (d < r) col = mix(col, ubuf.seamColor.rgb * 1.6, 0.6);
        else if (d < r + 1.0 / ubuf.pixelsPerWu && p.y < c.y) col *= 0.75;
    }
    if (hash(floor(p * ubuf.pixelsPerWu)) > 0.97) col *= 0.85;
    return col;
}

void main() {
    // World position, y up like the world; snapped to the chunky pixel grid.
    vec2 rawP = vec2(qt_TexCoord0.x, 1.0 - qt_TexCoord0.y) * ubuf.sizeWu;
    vec2 p = (floor(rawP * ubuf.pixelsPerWu) + 0.5) / ubuf.pixelsPerWu;
    vec3 col = ubuf.style < 0.5 ? flagstones(p, rawP) : earth(p);
    fragColor = vec4(col, 1.0) * ubuf.qt_Opacity;
}
