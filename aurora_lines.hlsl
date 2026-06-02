// Windows Terminal pixel shader: ribbon aurora background
// A darker, more natural aurora built from uneven arcs, broad glowing sheets,
// and narrow streaks inside the ribbons. The aurora does not share one flat top
// edge, so it reads less like vapor and more like aurora borealis.

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

// ---- Aurora ---------------------------------------------------------------

float ribbonStreaks(float2 p, float spine, float t, float seed)
{
    // Fine structure inside the broad sheet. The streaks are present, but they
    // are not the whole aurora.
    float bend = sin((p.y - spine) * 7.0 + seed) * 0.045;
    float x = p.x + bend + sin(p.y * 2.1 + t + seed) * 0.025;
    float cell = frac(x * 34.0 + seed * 5.0);
    float thin = pow(1.0 - abs(cell - 0.5) * 2.0, 4.5);
    float broken = smoothstep(0.22, 0.78, fbm(float2(x * 3.0 + t * 0.25, p.y * 4.0 + seed)));

    return thin * broken;
}

float auroraRibbon(float2 uv, float seed, float yBase, float slope, float width, float height, float strength)
{
    float t = Time * 0.045;
    float aspect = Resolution.x / max(Resolution.y, 1.0);
    float2 p = float2((uv.x - 0.5) * aspect, uv.y);
    float x = p.x + seed;

    // A lower glowing arc with an uneven shape, similar to aurora rising from a
    // horizon instead of hanging from a straight top border.
    float rough = (fbm(float2(x * 1.5 - t, seed * 2.0)) - 0.5) * 0.10;
    float spine = yBase + slope * p.x
        + sin(x * 1.65 + t * 1.7) * 0.11
        + sin(x * 4.15 - t * 2.0) * 0.035
        + rough;

    float dist = abs(p.y - spine);
    float brightArc = exp(-dist * dist / (width * width));

    // Broad luminous sheet above the arc, with soft edges and holes.
    float rise = max(spine - p.y, 0.0);
    float aboveArc = 1.0 - smoothstep(spine - 0.03, spine + 0.05, p.y);
    float verticalFade = exp(-rise * height);
    float lowerFade = 1.0 - smoothstep(spine + 0.03, spine + 0.30, p.y);
    float sheetNoise = smoothstep(0.18, 0.88, fbm(float2(x * 1.15 + t, p.y * 2.25 - t * 0.6)));
    float sheet = aboveArc * lowerFade * verticalFade * (0.55 + sheetNoise * 0.85);

    float streaks = ribbonStreaks(p, spine, t, seed) * sheet;
    float sideMask = smoothstep(-1.15, -0.35, p.x + seed) * (1.0 - smoothstep(0.65, 1.35, p.x + seed));

    return (brightArc * 0.75 + sheet * 0.62 + streaks * 0.55) * sideMask * strength;
}

float3 auroraColor(float2 uv)
{
    float mainRibbon = auroraRibbon(uv, -0.10, 0.56, -0.10, 0.030, 2.8, 1.00);
    float highRibbon = auroraRibbon(uv, 0.42, 0.43, 0.08, 0.045, 2.35, 0.58);
    float softBack = auroraRibbon(uv, -0.66, 0.50, 0.16, 0.070, 3.15, 0.34);
    float glow = mainRibbon + highRibbon + softBack;

    float t = Time * 0.04;
    float warmGreen = 0.5 + 0.5 * sin(uv.x * 4.5 + t);
    float3 teal = float3(0.03, 0.56, 0.42);
    float3 green = float3(0.18, 1.00, 0.38);
    float3 mint = float3(0.70, 1.00, 0.72);
    float3 violet = float3(0.50, 0.14, 0.82);

    float3 color = lerp(teal, green, warmGreen);
    color = lerp(color, mint, saturate(glow * 0.34));

    // Violet sits on one side like the reference photos, not over the full sky.
    float violetArea = smoothstep(-0.95, -0.20, (uv.x - 0.5) * (Resolution.x / max(Resolution.y, 1.0)))
        * (1.0 - smoothstep(0.06, 0.48, uv.y));
    color = lerp(color, violet, violetArea * saturate(glow * 0.50));

    return color * glow;
}

float3 stars(float2 uv)
{
    float aspect = Resolution.x / max(Resolution.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float2 grid = floor(p * 190.0);
    float star = step(0.9965, hash21(grid));
    float twinkle = 0.35 + 0.65 * hash21(grid + floor(Time * 0.35));

    return float3(0.30, 0.42, 0.55) * star * twinkle * (1.0 - smoothstep(0.2, 0.95, uv.y)) * 0.23;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float2 uv = tex;
    float4 terminal = shaderTexture.Sample(samplerState, tex);

    float3 sky = lerp(float3(0.003, 0.006, 0.015),
                      float3(0.010, 0.024, 0.036),
                      1.0 - uv.y);

    float3 bg = sky + stars(uv) + auroraColor(uv) * 0.62;

    // Organic edge darkening helps cover Terminal's un-celled border strips.
    float2 dd = min(uv, 1.0 - uv);
    float edgeDistance = min(dd.x, dd.y);
    edgeDistance += (fbm(uv * 3.2 + Time * 0.035) - 0.5) * 0.045;
    bg *= smoothstep(0.0, 0.12, edgeDistance);

    // Keep terminal text readable by compositing bright terminal content above
    // the generated background.
    float luma = dot(terminal.rgb, float3(0.299, 0.587, 0.114));
    float textMask = smoothstep(0.04, 0.22, luma);
    float3 result = lerp(bg, terminal.rgb, textMask);

    return float4(saturate(result), 1.0);
}
