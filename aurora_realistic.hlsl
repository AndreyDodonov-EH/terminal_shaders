// Windows Terminal pixel shader: "Aurora Realistic"
//
// A volumetric take on the aurora, as opposed to the flat 2D layers of
// aurora_claude.hlsl. The view ray is marched upward through a stack of
// thin horizontal slices of an emissive curtain; sampling the curtain density
// in the ground plane (x,z) and reading colour from the slice height gives real
// perspective (curtains recede toward the horizon) and a physically-flavoured
// colour ramp (teal lower edge -> green body -> crimson/violet tops).
//
// Performance ideas borrowed from nimitz's "Auroras" (2017, CC BY-NC-SA):
//   * triangle-wave noise (no hashing / no bilinear) so it is cheap enough to
//     evaluate many times per pixel;
//   * a per-pixel dither offset + polynomial step spacing, which lets a low step
//     count cover a tall volume without visible banding.
// The noise here is an independent reimplementation; the technique is the credit.
//
// Pair with a solid dark colour scheme and NO backgroundImage.

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
//  TUNABLES
// ============================================================================

// --- Raymarch (cost vs. quality) ---
#define AURORA_STEPS   32     // volume slices; lower = faster, more dithered
#define STEP_STRIDE    1.5    // >1 packs slices near the horizon (polynomial)
#define TRI_OCTAVES    5      // detail of the curtain noise

// --- Animation (higher = faster) ---
#define FOLD_SPEED     0.06   // how fast the curtains fold/drift
#define SHIMMER_SPEED  0.50   // star twinkle

// --- Aurora shape ---
#define FIELD_SCALE    1.30   // horizontal size of curtains (smaller = wider)
#define RIBBON_LO      0.10   // density threshold: raise for sparser ribbons
#define RIBBON_HI      0.62   // upper threshold: gap between for ribbon softness
#define HEIGHT_FALLOFF 2.20   // how quickly curtains fade with altitude
#define AURORA_BRIGHTNESS 1.35

// --- Camera framing ---
#define HORIZON_LIFT   0.16   // push the horizon down the screen (more sky)
#define VIEW_PITCH     0.72   // vertical field of view of the sky

// --- Sky / stars ---
#define STAR_THRESHOLD 0.9970 // higher = fewer stars
#define STAR_BRIGHTNESS 0.55
#define VIGNETTE_SOFTNESS 0.13

// --- Palette (height ramp: bottom -> top) ---
static const float3 COL_LOWEDGE = float3(0.10, 0.55, 0.55); // cool teal base
static const float3 COL_GREEN   = float3(0.14, 1.00, 0.38); // dominant body
static const float3 COL_CRIMSON = float3(0.95, 0.22, 0.42); // upper reds
static const float3 COL_VIOLET  = float3(0.50, 0.20, 0.85); // faint tips
static const float3 SKY_TOP     = float3(0.010, 0.022, 0.040);
static const float3 SKY_HORIZON = float3(0.020, 0.045, 0.055);
static const float3 STAR_WARM   = float3(1.00, 0.85, 0.65);
static const float3 STAR_COOL   = float3(0.70, 0.85, 1.00);

// ============================================================================

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

// Triangle wave in [0, 0.5]: the cheap, hash-free noise primitive.
float tri(float x)
{
    return abs(frac(x) - 0.5);
}

float2 tri2(float2 p)
{
    return float2(tri(p.x + tri(p.y)), tri(p.y + tri(p.x)));
}

// Fixed rotation between octaves (no per-iteration cos/sin in the hot loop).
static const float2x2 M2 = float2x2(0.9553, 0.2955, -0.2955, 0.9553);

// Folded triangle-wave fBm. "animRot" is a rotation matrix precomputed once per
// frame from Time, used to swirl the warp offset so the curtains fold smoothly.
float fbmTri(float2 p, float2x2 animRot)
{
    float rz = 0.0;
    float amp = 0.60;

    [unroll]
    for (int i = 0; i < TRI_OCTAVES; i++)
    {
        float2 dg = tri2(p * 1.85) * 0.75;
        dg = mul(dg, animRot);          // animate by rotating the warp
        p -= dg * 0.5;                  // domain warp -> folding draperies

        rz += amp * tri(p.x + tri(p.y));
        p = mul(p, M2) * 1.85;          // rotate + scale to next octave
        amp *= 0.5;
    }
    return rz;
}

// Curtain density at a point in the ground plane, sharpened into ribbons.
float curtainDensity(float2 q, float2x2 animRot)
{
    float n = fbmTri(q, animRot);
    return smoothstep(RIBBON_LO, RIBBON_HI, n);
}

// Emission colour as a function of normalized slice height (0 bottom, 1 top).
float3 auroraRamp(float h)
{
    float3 c = lerp(COL_LOWEDGE, COL_GREEN, smoothstep(0.00, 0.22, h));
    c = lerp(c, COL_CRIMSON, smoothstep(0.45, 0.82, h));
    c = lerp(c, COL_VIOLET,  smoothstep(0.84, 1.00, h));
    return c;
}

// March upward through the curtain volume and accumulate emission.
float3 aurora(float3 ro, float3 rd, float dither, float2x2 animRot)
{
    float3 col = float3(0.0, 0.0, 0.0);
    float invSteps = 1.0 / float(AURORA_STEPS);

    [loop]
    for (int i = 0; i < AURORA_STEPS; i++)
    {
        // Polynomial spacing: slices bunch up near the horizon where detail
        // matters; the dither hides the seams between slices.
        float fi = (float(i) + dither) * invSteps;
        float h = 0.10 + pow(fi, STEP_STRIDE) * 1.6;

        float t = h / rd.y;             // distance to this height (rd.y > 0)
        float3 pos = ro + rd * t;

        float dens = curtainDensity(pos.xz * FIELD_SCALE, animRot);

        // Curtains thin out with altitude; fade in just above the horizon.
        float vFade = exp(-fi * HEIGHT_FALLOFF);
        float rampIn = smoothstep(0.0, 0.10, fi);

        col += auroraRamp(fi) * dens * vFade * rampIn;
    }

    return col * AURORA_BRIGHTNESS * invSteps;
}

float3 stars(float2 uv, float aspect)
{
    float2 p = float2(uv.x * aspect, uv.y);
    float2 grid = floor(p * 220.0);
    float h = hash21(grid);
    float star = step(STAR_THRESHOLD, h);
    float twinkle = 0.4 + 0.6 * hash21(grid + floor(Time * SHIMMER_SPEED));
    float3 tint = lerp(STAR_WARM, STAR_COOL, hash21(grid + 7.0));

    // Only in the upper sky, brighter higher up.
    float skyMask = 1.0 - smoothstep(0.15, 0.85, uv.y);
    return tint * star * twinkle * skyMask * STAR_BRIGHTNESS * 0.12;
}

float4 main(float4 svpos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float2 uv = tex;
    float4 terminal = shaderTexture.Sample(samplerState, tex);

    float aspect = Resolution.x / max(Resolution.y, 1.0);

    // Screen ray: top of screen looks up into the sky, bottom toward the horizon.
    float2 sp = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float3 ro = float3(0.0, 0.0, 0.0);
    float3 rd = normalize(float3(sp.x, -sp.y * VIEW_PITCH + HORIZON_LIFT, 1.0));

    // Sky gradient (cooler up high, a faint glow toward the horizon).
    float skyT = saturate(rd.y * 1.4);
    float3 sky = lerp(SKY_HORIZON, SKY_TOP, skyT);

    float3 col = sky + stars(uv, aspect);

    // Animation matrices / dither computed once per pixel.
    float ct = Time * FOLD_SPEED;
    float ca = cos(ct), sa = sin(ct);
    float2x2 animRot = float2x2(ca, sa, -sa, ca);
    float dither = hash21(uv * Resolution.xy); // static -> hides banding, no flicker

    // Aurora only above the horizon.
    if (rd.y > 0.001)
    {
        float horizonFade = smoothstep(0.0, 0.18, rd.y); // soften the base line
        col += aurora(ro, rd, dither, animRot) * horizonFade;
    }

    // Organic edge darkening to hide Terminal's un-celled border strips.
    float2 dd = min(uv, 1.0 - uv);
    float edgeDistance = min(dd.x, dd.y);
    edgeDistance += (tri(uv.x * 3.0 + Time * 0.03) - 0.25) * 0.05;
    col *= smoothstep(0.0, VIGNETTE_SOFTNESS, edgeDistance);

    // Composite bright terminal content (text) over the sky.
    float luma = dot(terminal.rgb, float3(0.299, 0.587, 0.114));
    float textMask = smoothstep(0.04, 0.22, luma);
    float3 result = lerp(col, terminal.rgb, textMask);

    return float4(saturate(result), 1.0);
}
