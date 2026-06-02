// Windows Terminal pixel shader: "Aurora Curtains" background
// A more photographic aurora borealis: the glow is built from vertical curtain
// rays (the characteristic "lines"), with a bright lower fringe and a ragged,
// uneven top edge -- each vertical ray fades out at a different height, so the
// aurora never reaches the top line as one flat band. Far less of the soft
// "vapor" sheet than the earlier versions; the structure reads as rays.
//
// NOTE: For the intended look this profile should NOT set a `backgroundImage`
// (the shader paints the whole sky). Pair it with a solid dark color scheme.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float  Time;
    float  Scale;
    float2 Resolution;
    float4 Background;
};

// ---- Noise helpers ---------------------------------------------------------

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

float valueNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

// Full-detail noise, used where fine structure matters (the rays).
float fbm(float2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    float2x2 rot = float2x2(0.82, -0.57, 0.57, 0.82);

    for (int i = 0; i < 5; i++)
    {
        sum += amp * valueNoise(p);
        p = mul(rot, p) * 2.03;
        amp *= 0.5;
    }

    return sum;
}

// Cheap 3-octave noise for smooth, low-frequency fields (fringe fold, per-column
// reach, border wave). Visually indistinguishable there but ~40% less work than
// the 5-octave version, which is the bulk of the per-pixel cost.
float fbm3(float2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    float2x2 rot = float2x2(0.82, -0.57, 0.57, 0.82);

    for (int i = 0; i < 3; i++)
    {
        sum += amp * valueNoise(p);
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
float curtain(float2 uv, float seed, float fringeBase, float slope,
              float reachBase, float rayFreq, float intensity)
{
    float t = Time * 0.05;
    float aspect = Resolution.x / max(Resolution.y, 1.0);
    float2 p = float2((uv.x - 0.5) * aspect, uv.y);
    float x = p.x + seed;

    // Wavy, folding lower fringe -- the bright bottom edge of the curtain.
    float fold = sin(x * 1.25 + t * 0.9) * 0.045
               + sin(x * 2.70 - t * 0.6) * 0.022
               + (fbm3(float2(x * 1.10, seed * 2.0)) - 0.5) * 0.06;
    float fringeY = fringeBase + slope * p.x + fold;

    // Distance above (toward top) the fringe.
    float rise = fringeY - p.y;

    // Per-column reach: how high this vertical slice climbs. Varying it across
    // x is what gives the aurora its uneven, non-aligned top edge.
    float reachNoise = fbm3(float2(x * 1.7 + t * 0.3, seed * 4.0));
    float reach = reachBase * (0.30 + reachNoise * 1.05);

    // Vertical body that fades upward; columns die out at different heights.
    float body = (rise > 0.0) ? exp(-rise / max(reach, 0.02)) : 0.0;
    body *= smoothstep(-0.015, 0.02, rise); // clip just below the fringe

    // Bright, thin lower fringe line (d*d is cheaper than pow()).
    float d = (p.y - fringeY) / 0.014;
    float edge = exp(-d * d);

    // Vertical rays: high frequency in x, low in y -> streaks that run up/down.
    float wobble = sin(p.y * 2.2 + t * 1.2 + seed) * 0.25;
    float raysA = fbm(float2(x * rayFreq + wobble, p.y * 0.9 - t * 0.4 + seed));
    float raysB = fbm(float2(x * rayFreq * 2.15 - t * 0.3, p.y * 1.3 + seed * 3.0));
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

float3 auroraColor(float2 uv)
{
    // A few curtains at different depths, positions and ray scales.
    float main = curtain(uv, -0.05, 0.48, -0.06, 0.34, 11.0, 1.00);
    float left = curtain(uv, -0.70, 0.40,  0.10, 0.28,  9.0, 0.55);
    float far  = curtain(uv,  0.55, 0.52, -0.12, 0.40,  7.5, 0.42);
    float glow = main + left + far;

    float t = Time * 0.04;

    // Green-dominant body with a teal shimmer.
    float shimmer = 0.5 + 0.5 * sin(uv.x * 5.0 + t);
    float3 teal  = float3(0.02, 0.52, 0.42);
    float3 green = float3(0.16, 1.00, 0.40);
    float3 mint  = float3(0.65, 1.00, 0.74);
    float3 color = lerp(teal, green, shimmer);
    color = lerp(color, mint, saturate(glow * 0.20));

    // Magenta/pink at the lower fringe, the way real curtains tint at the base.
    float3 pink = float3(0.85, 0.18, 0.55);
    float lowTint = smoothstep(0.30, 0.62, uv.y);
    color = lerp(color, pink, lowTint * saturate(glow * 0.30));

    // Violet on the high, faint tips toward the top of the sky.
    float3 violet = float3(0.45, 0.16, 0.85);
    float highTint = (1.0 - smoothstep(0.05, 0.40, uv.y));
    color = lerp(color, violet, highTint * saturate(glow * 0.22));

    return color * glow;
}

float3 stars(float2 uv)
{
    float aspect = Resolution.x / max(Resolution.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float2 grid = floor(p * 200.0);
    float star = step(0.9968, hash21(grid));
    float twinkle = 0.35 + 0.65 * hash21(grid + floor(Time * 0.4));

    return float3(0.30, 0.42, 0.55) * star * twinkle
         * (1.0 - smoothstep(0.25, 0.95, uv.y)) * 0.13;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float2 uv = tex;
    float4 terminal = shaderTexture.Sample(samplerState, tex);

    // Dark night-sky gradient, slightly cooler near the top.
    float3 sky = lerp(float3(0.003, 0.006, 0.015),
                      float3(0.009, 0.022, 0.034),
                      1.0 - uv.y);

    float3 bg = sky + stars(uv) + auroraColor(uv) * 0.50;

    // Organic edge darkening to hide Terminal's un-celled border strips.
    float2 dd = min(uv, 1.0 - uv);
    float edgeDistance = min(dd.x, dd.y);
    edgeDistance += (fbm3(uv * 3.2 + Time * 0.035) - 0.5) * 0.045;
    bg *= smoothstep(0.0, 0.12, edgeDistance);

    // Keep terminal text readable by compositing bright content on top.
    float luma = dot(terminal.rgb, float3(0.299, 0.587, 0.114));
    float textMask = smoothstep(0.04, 0.22, luma);
    float3 result = lerp(bg, terminal.rgb, textMask);

    return float4(saturate(result), 1.0);
}
