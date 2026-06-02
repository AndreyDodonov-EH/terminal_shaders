// Aurora Curtains -- Shadertoy port of the Windows Terminal "aurora_claude" shader.
//
// How to use: open https://www.shadertoy.com/new, paste this into the "Image"
// tab, and hit compile/run. No input textures (iChannel0..3) are required.
//
// Differences from the Terminal version are only structural:
//   * GLSL types/intrinsics (vec2, mix, fract, clamp, ...) instead of HLSL.
//   * iTime / iResolution replace Time / Resolution.
//   * There is no terminal text to composite, so the shader just paints the sky.
//   * fragCoord.y is 0 at the bottom on Shadertoy, so uv.y is flipped to keep the
//     aurora hanging from the top exactly like the Terminal version.

// ============================================================================
//  TUNABLES -- everything you'd normally want to tweak lives here. These are
//  compile-time constants (#define / const), so there is no runtime cost.
// ============================================================================

// --- Animation speeds (higher = faster) ---
#define CURTAIN_SPEED   0.05   // folding / drift of the curtains
#define COLOR_SPEED     0.04   // green<->teal shimmer
#define STAR_SPEED      0.40   // twinkle rate
#define EDGE_SPEED      0.035  // wobble of the vignette border

// --- Overall look ---
#define AURORA_BRIGHTNESS 0.50 // master aurora intensity
#define VIGNETTE_SOFTNESS 0.12 // edge fade width; set very large to disable
#define STAR_THRESHOLD    0.9968 // higher = fewer stars (max 1.0)
#define STAR_BRIGHTNESS   0.13

// --- Noise detail vs. performance ---
#define FBM_OCTAVES       5  // full-detail noise (the visible ray texture)
#define FBM_FAST_OCTAVES  3  // cheap noise for low-frequency fields (fringe, reach, border)

// --- Curtains ---
// The single most basic knob: how many curtain layers are summed (1..3).
// Fewer = faster and sparser; each layer below is one curtain.
#define CURTAIN_COUNT 3

// Per-layer params: SEED, FRINGE_Y, SLOPE, REACH, RAY_FREQ, INTENSITY.
// FRINGE_Y is the base height (0 = top, 1 = bottom). REACH is how far rays
// climb. RAY_FREQ controls line spacing (higher = more, thinner lines).
#define C1_SEED -0.05
#define C1_FRINGE 0.48
#define C1_SLOPE -0.06
#define C1_REACH 0.34
#define C1_RAYFREQ 11.0
#define C1_INTENSITY 1.00

#define C2_SEED -0.70
#define C2_FRINGE 0.40
#define C2_SLOPE 0.10
#define C2_REACH 0.28
#define C2_RAYFREQ 9.0
#define C2_INTENSITY 0.55

#define C3_SEED 0.55
#define C3_FRINGE 0.52
#define C3_SLOPE -0.12
#define C3_REACH 0.40
#define C3_RAYFREQ 7.5
#define C3_INTENSITY 0.42

// --- Palette ---
const vec3 COL_TEAL    = vec3(0.02, 0.52, 0.42); // shimmer low
const vec3 COL_GREEN   = vec3(0.16, 1.00, 0.40); // shimmer high (dominant)
const vec3 COL_MINT    = vec3(0.65, 1.00, 0.74); // brightest cores
const vec3 COL_PINK    = vec3(0.85, 0.18, 0.55); // lower-fringe tint
const vec3 COL_VIOLET  = vec3(0.45, 0.16, 0.85); // high faint tips
const vec3 SKY_TOP     = vec3(0.009, 0.022, 0.034);
const vec3 SKY_BOTTOM  = vec3(0.003, 0.006, 0.015);
const vec3 STAR_COLOR  = vec3(0.30, 0.42, 0.55);

// ============================================================================

// ---- Noise helpers ---------------------------------------------------------

float hash21(vec2 p)
{
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i + vec2(0.0, 0.0));
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Same rotation as the HLSL float2x2 used with mul(rot, p): GLSL is
// column-major, so the columns below reproduce that matrix-times-vector.
const mat2 ROT = mat2(0.82, 0.57, -0.57, 0.82);

// Full-detail noise, used where fine structure matters (the rays).
float fbm(vec2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < FBM_OCTAVES; i++)
    {
        sum += amp * valueNoise(p);
        p = ROT * p * 2.03;
        amp *= 0.5;
    }
    return sum;
}

// Fewer-octave (hence faster) noise for low-frequency fields. Fewer passes also
// means smoother output, which is exactly what those smooth fields want.
float fbmFast(vec2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < FBM_FAST_OCTAVES; i++)
    {
        sum += amp * valueNoise(p);
        p = ROT * p * 2.03;
        amp *= 0.5;
    }
    return sum;
}

// ---- One aurora curtain ----------------------------------------------------
//
// "p" is the aspect-corrected coordinate (uv.y == 0 is the top of the screen)
// and "t" the curtain time. Both are computed once per pixel and passed in.
float curtain(vec2 p, float t, float seed, float fringeBase, float slope,
              float reachBase, float rayFreq, float intensity)
{
    float x = p.x + seed;

    // Wavy, folding lower fringe -- the bright bottom edge of the curtain.
    float fold = sin(x * 1.25 + t * 0.9) * 0.045
               + sin(x * 2.70 - t * 0.6) * 0.022
               + (fbmFast(vec2(x * 1.10, seed * 2.0)) - 0.5) * 0.06;
    float fringeY = fringeBase + slope * p.x + fold;

    // Distance above (toward top) the fringe.
    float rise = fringeY - p.y;

    // Per-column reach varies the uneven, non-aligned top edge.
    float reachNoise = fbmFast(vec2(x * 1.7 + t * 0.3, seed * 4.0));
    float reach = reachBase * (0.30 + reachNoise * 1.05);

    // Vertical body that fades upward; columns die out at different heights.
    float body = (rise > 0.0) ? exp(-rise / max(reach, 0.02)) : 0.0;
    body *= smoothstep(-0.015, 0.02, rise);

    // Bright, thin lower fringe line.
    float d = (p.y - fringeY) / 0.014;
    float edge = exp(-d * d);

    // Vertical rays: high frequency in x, low in y -> streaks that run up/down.
    // raysA keeps full detail; raysB only feeds a hard threshold so 3 octaves do.
    float wobble = sin(p.y * 2.2 + t * 1.2 + seed) * 0.25;
    float raysA = fbm(vec2(x * rayFreq + wobble, p.y * 0.9 - t * 0.4 + seed));
    float raysB = fbmFast(vec2(x * rayFreq * 2.15 - t * 0.3, p.y * 1.3 + seed * 3.0));
    raysA = smoothstep(0.42, 0.95, raysA);
    raysB = smoothstep(0.55, 0.97, raysB);
    float rayMix = raysA * 0.75 + raysB * 0.45;

    // Combine: rays dominate the body so the look is lines, not a flat sheet.
    float glow = body * (0.18 + rayMix * 1.05) + edge * 0.9 * clamp(reach, 0.0, 1.0);

    // Limit horizontal extent so the curtain occupies part of the sky.
    float side = smoothstep(-1.25, -0.45, p.x + seed)
               * (1.0 - smoothstep(0.55, 1.40, p.x + seed));

    return glow * side * intensity;
}

vec3 auroraColor(vec2 uv, float aspect)
{
    // Aspect-corrected coord and curtain-time computed once, shared by curtains.
    float ct = iTime * CURTAIN_SPEED;
    vec2 cp = vec2((uv.x - 0.5) * aspect, uv.y);

    float glow = curtain(cp, ct, C1_SEED, C1_FRINGE, C1_SLOPE, C1_REACH, C1_RAYFREQ, C1_INTENSITY);
#if CURTAIN_COUNT >= 2
    glow += curtain(cp, ct, C2_SEED, C2_FRINGE, C2_SLOPE, C2_REACH, C2_RAYFREQ, C2_INTENSITY);
#endif
#if CURTAIN_COUNT >= 3
    glow += curtain(cp, ct, C3_SEED, C3_FRINGE, C3_SLOPE, C3_REACH, C3_RAYFREQ, C3_INTENSITY);
#endif

    float t = iTime * COLOR_SPEED;

    // Green-dominant body with a teal shimmer.
    float shimmer = 0.5 + 0.5 * sin(uv.x * 5.0 + t);
    vec3 color = mix(COL_TEAL, COL_GREEN, shimmer);
    color = mix(color, COL_MINT, clamp(glow * 0.20, 0.0, 1.0));

    // Magenta/pink at the lower fringe, the way real curtains tint at the base.
    float lowTint = smoothstep(0.30, 0.62, uv.y);
    color = mix(color, COL_PINK, lowTint * clamp(glow * 0.30, 0.0, 1.0));

    // Violet on the high, faint tips toward the top of the sky.
    float highTint = 1.0 - smoothstep(0.05, 0.40, uv.y);
    color = mix(color, COL_VIOLET, highTint * clamp(glow * 0.22, 0.0, 1.0));

    return color * glow;
}

vec3 stars(vec2 uv, float aspect)
{
    vec2 p = vec2(uv.x * aspect, uv.y);
    vec2 grid = floor(p * 200.0);
    float star = step(STAR_THRESHOLD, hash21(grid));
    float twinkle = 0.35 + 0.65 * hash21(grid + floor(iTime * STAR_SPEED));

    return STAR_COLOR * star * twinkle
         * (1.0 - smoothstep(0.25, 0.95, uv.y)) * STAR_BRIGHTNESS;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y; // Shadertoy origin is bottom-left; flip so y==0 is the top.

    float aspect = iResolution.x / max(iResolution.y, 1.0);

    // Dark night-sky gradient, slightly cooler near the top.
    vec3 sky = mix(SKY_BOTTOM, SKY_TOP, 1.0 - uv.y);

    vec3 bg = sky + stars(uv, aspect) + auroraColor(uv, aspect) * AURORA_BRIGHTNESS;

    // Organic edge darkening (a soft vignette here; in Terminal it hid the
    // un-celled border). Delete this block for an edge-to-edge image.
    vec2 dd = min(uv, 1.0 - uv);
    float edgeDistance = min(dd.x, dd.y);
    edgeDistance += (fbmFast(uv * 3.2 + iTime * EDGE_SPEED) - 0.5) * 0.045;
    bg *= smoothstep(0.0, VIGNETTE_SOFTNESS, edgeDistance);

    fragColor = vec4(clamp(bg, 0.0, 1.0), 1.0);
}
