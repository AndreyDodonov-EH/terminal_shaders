// Windows Terminal pixel shader: "Aurora Curtains" -- tri-noise variant.
//
// Identical in structure to aurora_claude.hlsl; the ONLY change is the noise
// basis. Instead of value noise (4 hash lookups + a bilinear blend per sample),
// it uses hash-free triangle-wave noise (tri/triValue) -- the cheap primitive
// from nimitz's "Auroras" (2017). The aurora's fbm is the per-pixel hotspot, so
// this is meant for a cost/look comparison against aurora_claude.hlsl.
//
// Expect a slightly different texture: triangle noise is sharper / more ridged
// and streaky (less soft and blobby), which can read as more filament-like but
// may want the ray smoothstep thresholds retuned. hash21 is kept ONLY for the
// stars, which need point-random placement.
//
// Pair with a solid dark color scheme and NO backgroundImage.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float  Time;
    float  Scale;
    float2 Resolution;
    float4 Background;
};

// ============================================================================
//  TUNABLES -- everything you'd normally want to tweak lives here. These are
//  compile-time constants (#define / static const), so there is no runtime cost.
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
#define FBM_FAST_OCTAVES  3 // cheap noise for low-frequency fields (fringe, reach, border)

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
static const float3 COL_TEAL    = float3(0.02, 0.52, 0.42); // shimmer low
static const float3 COL_GREEN   = float3(0.16, 1.00, 0.40); // shimmer high (dominant)
static const float3 COL_MINT    = float3(0.65, 1.00, 0.74); // brightest cores
static const float3 COL_PINK    = float3(0.85, 0.18, 0.55); // lower-fringe tint
static const float3 COL_VIOLET  = float3(0.45, 0.16, 0.85); // high faint tips
static const float3 SKY_TOP     = float3(0.009, 0.022, 0.034);
static const float3 SKY_BOTTOM  = float3(0.003, 0.006, 0.015);
static const float3 STAR_COLOR  = float3(0.30, 0.42, 0.55);

// ============================================================================

// ---- Noise helpers ---------------------------------------------------------

// Kept ONLY for the stars (point-random placement).
float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

// Triangle wave in [0, 0.5] -- the cheap, hash-free noise primitive.
float tri(float x)
{
    return abs(frac(x) - 0.5);
}

// Triangle-lattice value in ~[0, 1]: a drop-in stand-in for value noise, but
// with no hashing and no bilinear blend, so far less ALU per sample.
float triValue(float2 p)
{
    return tri(p.x + tri(p.y)) + tri(p.y + tri(p.x));
}

// Full-detail noise, used where fine structure matters (the rays).
float fbm(float2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    float2x2 rot = float2x2(0.82, -0.57, 0.57, 0.82);

    for (int i = 0; i < FBM_OCTAVES; i++)
    {
        sum += amp * triValue(p);
        p = mul(rot, p) * 2.03;
        amp *= 0.5;
    }

    return sum;
}

// Fewer-octave (hence faster) noise for low-frequency fields (fringe fold,
// per-column reach, border wave). Fewer passes also means smoother output,
// which is exactly what those smooth fields want.
float fbmFast(float2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    float2x2 rot = float2x2(0.82, -0.57, 0.57, 0.82);

    for (int i = 0; i < FBM_FAST_OCTAVES; i++)
    {
        sum += amp * triValue(p);
        p = mul(rot, p) * 2.03;
        amp *= 0.5;
    }

    return sum;
}

// ---- One aurora curtain ----------------------------------------------------
//
// uv.y == 0 is the top of the screen. A curtain has a bright lower fringe at
// "fringeY" and vertical rays that rise toward the top (smaller y). The height
// each ray reaches is modulated by noise across x, which is what makes the top
// edge ragged instead of one flat line.
// "p" is the aspect-corrected coordinate and "t" the curtain time, both passed
// in so they are computed once per pixel instead of once per curtain.
float curtain(float2 p, float t, float seed, float fringeBase, float slope,
              float reachBase, float rayFreq, float intensity)
{
    float x = p.x + seed;

    // Wavy, folding lower fringe -- the bright bottom edge of the curtain.
    float fold = sin(x * 1.25 + t * 0.9) * 0.045
               + sin(x * 2.70 - t * 0.6) * 0.022
               + (fbmFast(float2(x * 1.10, seed * 2.0)) - 0.5) * 0.06;
    float fringeY = fringeBase + slope * p.x + fold;

    // Distance above (toward top) the fringe.
    float rise = fringeY - p.y;

    // Per-column reach: how high this vertical slice climbs. Varying it across
    // x is what gives the aurora its uneven, non-aligned top edge.
    float reachNoise = fbmFast(float2(x * 1.7 + t * 0.3, seed * 4.0));
    float reach = reachBase * (0.30 + reachNoise * 1.05);

    // Vertical body that fades upward; columns die out at different heights.
    float body = (rise > 0.0) ? exp(-rise / max(reach, 0.02)) : 0.0;
    body *= smoothstep(-0.015, 0.02, rise); // clip just below the fringe

    // Bright, thin lower fringe line (d*d is cheaper than pow()).
    float d = (p.y - fringeY) / 0.014;
    float edge = exp(-d * d);

    // Vertical rays: high frequency in x, low in y -> streaks that run up/down.
    // raysA keeps full detail (the visible ray texture); raysB only feeds a hard
    // threshold and its top octaves are sub-pixel shimmer, so 3 octaves suffice.
    float wobble = sin(p.y * 2.2 + t * 1.2 + seed) * 0.25;
    float raysA = fbm(float2(x * rayFreq + wobble, p.y * 0.9 - t * 0.4 + seed));
    float raysB = fbmFast(float2(x * rayFreq * 2.15 - t * 0.3, p.y * 1.3 + seed * 3.0));
    raysA = smoothstep(0.42, 0.95, raysA);
    raysB = smoothstep(0.55, 0.97, raysB);
    float rayMix = raysA * 0.75 + raysB * 0.45;

    // Combine: rays dominate the body so the look is lines, not a flat sheet.
    float glow = body * (0.18 + rayMix * 1.05) + edge * 0.9 * saturate(reach);

    // Limit horizontal extent so the curtain occupies part of the sky.
    float side = smoothstep(-1.25, -0.45, p.x + seed)
               * (1.0 - smoothstep(0.55, 1.40, p.x + seed));

    return glow * side * intensity;
}

float3 auroraColor(float2 uv, float aspect)
{
    // Compute the aspect-corrected coord and curtain-time once, share across all
    // curtains instead of recomputing inside each.
    float ct = Time * CURTAIN_SPEED;
    float2 cp = float2((uv.x - 0.5) * aspect, uv.y);

    float glow = curtain(cp, ct, C1_SEED, C1_FRINGE, C1_SLOPE, C1_REACH, C1_RAYFREQ, C1_INTENSITY);
#if CURTAIN_COUNT >= 2
    glow += curtain(cp, ct, C2_SEED, C2_FRINGE, C2_SLOPE, C2_REACH, C2_RAYFREQ, C2_INTENSITY);
#endif
#if CURTAIN_COUNT >= 3
    glow += curtain(cp, ct, C3_SEED, C3_FRINGE, C3_SLOPE, C3_REACH, C3_RAYFREQ, C3_INTENSITY);
#endif

    float t = Time * COLOR_SPEED;

    // Green-dominant body with a teal shimmer.
    float shimmer = 0.5 + 0.5 * sin(uv.x * 5.0 + t);
    float3 color = lerp(COL_TEAL, COL_GREEN, shimmer);
    color = lerp(color, COL_MINT, saturate(glow * 0.20));

    // Magenta/pink at the lower fringe, the way real curtains tint at the base.
    float lowTint = smoothstep(0.30, 0.62, uv.y);
    color = lerp(color, COL_PINK, lowTint * saturate(glow * 0.30));

    // Violet on the high, faint tips toward the top of the sky.
    float highTint = (1.0 - smoothstep(0.05, 0.40, uv.y));
    color = lerp(color, COL_VIOLET, highTint * saturate(glow * 0.22));

    return color * glow;
}

float3 stars(float2 uv, float aspect)
{
    float2 p = float2(uv.x * aspect, uv.y);
    float2 grid = floor(p * 200.0);
    float star = step(STAR_THRESHOLD, hash21(grid));
    float twinkle = 0.35 + 0.65 * hash21(grid + floor(Time * STAR_SPEED));

    return STAR_COLOR * star * twinkle
         * (1.0 - smoothstep(0.25, 0.95, uv.y)) * STAR_BRIGHTNESS;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float2 uv = tex;
    float4 terminal = shaderTexture.Sample(samplerState, tex);

    // Aspect computed once and shared by the aurora and the stars.
    float aspect = Resolution.x / max(Resolution.y, 1.0);

    // Dark night-sky gradient, slightly cooler near the top.
    float3 sky = lerp(SKY_BOTTOM, SKY_TOP, 1.0 - uv.y);

    float3 bg = sky + stars(uv, aspect) + auroraColor(uv, aspect) * AURORA_BRIGHTNESS;

    // Organic edge darkening to hide Terminal's un-celled border strips.
    float2 dd = min(uv, 1.0 - uv);
    float edgeDistance = min(dd.x, dd.y);
    edgeDistance += (fbmFast(uv * 3.2 + Time * EDGE_SPEED) - 0.5) * 0.045;
    bg *= smoothstep(0.0, VIGNETTE_SOFTNESS, edgeDistance);

    // Keep terminal text readable by compositing bright content on top.
    float luma = dot(terminal.rgb, float3(0.299, 0.587, 0.114));
    float textMask = smoothstep(0.04, 0.22, luma);
    float3 result = lerp(bg, terminal.rgb, textMask);

    return float4(saturate(result), 1.0);
}
