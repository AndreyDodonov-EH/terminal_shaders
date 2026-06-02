// Matrix Rain -- Shadertoy port of matrix_rain.hlsl (Windows Terminal).
//
// How to use: open https://www.shadertoy.com/new, paste this into the "Image"
// tab, and hit compile/run. No iChannel textures are required.
//
// Structural differences from the Terminal version:
//   * iTime / iResolution replace Time / Resolution.
//   * fragCoord.y is 0 at the bottom on Shadertoy; uv.y is flipped so rain falls
//     downward like the Terminal shader (y == 0 at the top).
//   * No shaderTexture / terminal text compositing.
//
// MIT License — original work, no third-party code.

// ── Tunables ─────────────────────────────────────────────────────────────────
#define CELL_H        28.0   // glyph cell height in pixels (smaller = more glyphs)
#define BASE_SPEED    0.085  // base fall speed, screens/sec
#define TRAIL_LEN     0.42   // trail length in UV space (0..1)
#define MASTER_BRIGHT 0.85   // overall intensity (lower = subtler background)
#define VIGNETTE_STR  0.55   // how strongly to darken the edges
#define HEAD_FLARE    1.30   // brightness of the leading glyph (1 = no flare)
#define GLYPH_FPS     3.0    // how often body glyphs re-roll (per second)
#define HEAD_FPS      8.0    // how often the bright leading glyph re-rolls
#define GLYPH_COUNT   12
// ─────────────────────────────────────────────────────────────────────────────

// 7-wide x 9-tall bitmap font. Each entry is one row, leftmost pixel = bit 6.
const int FONT[GLYPH_COUNT * 9] = int[](
     62, 34, 34, 34, 34, 34, 34, 34, 62,  // 0  oval
      8, 24,  8,  8,  8,  8,  8,  8, 28,  // 1
      2,  6, 10, 18, 34,  2,  2,  2,  2,  // 2  ｲ-ish
    127,  1,  1,  1,  1,  1,  1,  1,127,  // 3  ｺ
      8,  8,127,  8, 24, 40, 72,  8, 12,  // 4  ﾅ
     30, 34, 66, 66,126,  2,  4,  8,120,  // 5  ﾑ-ish
      0,126,  0,  0,  0,  0,127,  0,  0,  // 6  ﾆ
      0,  8,  8,  8,127,  8,  8,  8,  0,  // 7  +
     34, 34, 34, 34, 34, 34, 38,  4,  8,  // 8  ﾘ
    127,  2,  4,  8, 16, 32, 64,127,  0,  // 9  Z-ish
     34, 34,  2,  4,  8, 16, 32,  0,  8,  // 10 ﾂ
    127, 65, 93, 85, 93, 65, 65, 65,127   // 11 boxed
);

float hash1(float n)
{
    return fract(sin(n) * 43758.5453);
}

float hash2(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Brightness [0..HEAD_FLARE] for a column at vertical position y (UV space).
float streamLayer(float colIdx, float y, float seed)
{
    float hSpeed  = hash1(colIdx * 1.3174 + seed);
    float hOffset = hash1(colIdx * 7.5431 + seed + 3.0);
    float hTrail  = hash1(colIdx * 3.8917 + seed + 7.0);

    float speed = BASE_SPEED * (0.30 + hSpeed * 1.60);
    float trail = TRAIL_LEN  * (0.45 + hTrail * 0.75);

    float headY = fract(iTime * speed + hOffset);

    float dy         = fract(headY - y + 1.0);
    float inTrail    = step(dy, trail);
    float t          = clamp(dy / trail, 0.0, 1.0);
    float brightness = (1.0 - t) * (1.0 - t);

    brightness = mix(brightness, HEAD_FLARE, smoothstep(0.04, 0.0, dy));

    return brightness * inTrail;
}

float glyphBit(vec2 p, int id)
{
    p = (p - 0.5) / 0.82 + 0.5;
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0)
        return 0.0;

    int cx = clamp(int(p.x * 7.0), 0, 6);
    int cy = clamp(int(p.y * 9.0), 0, 8);

    int row = FONT[id * 9 + cy];
    return float((row >> (6 - cx)) & 1);
}

float glyphAA(vec2 p, int id, vec2 invCell)
{
    vec2 e = invCell * 0.5;
    float s = glyphBit(p + vec2(-e.x, -e.y), id)
            + glyphBit(p + vec2( e.x, -e.y), id)
            + glyphBit(p + vec2(-e.x,  e.y), id)
            + glyphBit(p + vec2( e.x,  e.y), id);
    return s * 0.25;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y; // match Terminal: y == 0 at the top, rain falls down

    vec2 cellPx  = vec2(CELL_H * 7.0 / 9.0, CELL_H);
    vec2 grid    = iResolution.xy / cellPx;
    vec2 cellF   = uv * grid;
    vec2 cellId  = floor(cellF);
    vec2 cellUV  = fract(cellF);
    vec2 invCell = 1.0 / cellPx;

    float colIdx      = cellId.x;
    float cellCenterY = (cellId.y + 0.5) / grid.y;

    float g  = streamLayer(colIdx,          cellCenterY, 0.0);
    float g2 = streamLayer(colIdx + 9000.0, cellCenterY, 17.3) * 0.5;
    float intensity = max(g, g2) * MASTER_BRIGHT;

    float isHead   = smoothstep(0.85 * MASTER_BRIGHT, HEAD_FLARE * MASTER_BRIGHT, intensity);
    float fps      = mix(GLYPH_FPS, HEAD_FPS, isHead);
    float timeStep = floor(iTime * fps + hash2(cellId) * 10.0);
    int id = int(hash1(hash2(cellId) * 53.0 + timeStep * 1.7) * float(GLYPH_COUNT));
    id = clamp(id, 0, GLYPH_COUNT - 1);

    float ch  = glyphAA(cellUV, id, invCell);
    float lit = intensity * ch;

    vec3 tailColor = vec3(0.00, 0.06, 0.02);
    vec3 midColor  = vec3(0.03, 0.45, 0.13);
    vec3 headColor = vec3(0.55, 0.95, 0.62);

    vec3 col = mix(tailColor, midColor, smoothstep(0.0,  0.45, lit));
    col      = mix(col,       headColor, smoothstep(0.70, 1.05, lit));
    col     *= smoothstep(0.0, 0.05, lit);

    vec2 vigUV = uv * 2.0 - 1.0;
    float vign = 1.0 - dot(vigUV * vec2(0.85, 1.0), vigUV * vec2(0.85, 1.0)) * VIGNETTE_STR;
    col *= max(0.0, vign);

    fragColor = vec4(col, 1.0);
}
