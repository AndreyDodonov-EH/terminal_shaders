// Windows Terminal pixel shader: "Nebula"
//
// Slow-drifting deep-space nebula made of layered 2D value noise (fbm).
// No ray marching — just five noise octaves composited with a colour ramp.
// Pair with a solid-black terminal profile and no backgroundImage.
//
// MIT License — original work for this repository.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float  Time;
    float  Scale;
    float2 Resolution;
    float4 Background;
};

// ── Tunables ────────────────────────────────────────────────────────────────
#define DRIFT_SPEED   0.028      // how fast the nebula drifts
#define BRIGHTNESS    0.52       // overall glow intensity (0 = invisible, 1 = vivid)
#define OCTAVES       5          // fbm layers (3 = fast, 5 = rich detail)
#define WARP_STRENGTH 0.35       // domain-warp distortion (0 = clean bands)
#define VIGNETTE_STR  0.50       // edge darkening
// ────────────────────────────────────────────────────────────────────────────

float hash(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float valueNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));

    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float fbm(float2 p)
{
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0, 100.0);
    float2x2 rot = float2x2(0.866, 0.5, -0.5, 0.866);   // 30-degree rotation

    [unroll]
    for (int i = 0; i < OCTAVES; i++)
    {
        v += a * valueNoise(p);
        p  = mul(p, rot) * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float aspect = Resolution.x / max(Resolution.y, 1.0);
    float2 uv = (tex - 0.5) * float2(aspect, 1.0);

    float t = Time * DRIFT_SPEED;

    // Two fbm passes with domain warping for organic swirl
    float2 q = float2(fbm(uv * 3.0 + float2(0.0,  t)),
                       fbm(uv * 3.0 + float2(5.2, -t * 0.7)));

    float2 r = float2(fbm(uv * 3.0 + q * WARP_STRENGTH * 4.0 + float2(1.7, 9.2) + t * 0.35),
                       fbm(uv * 3.0 + q * WARP_STRENGTH * 4.0 + float2(8.3, 2.8) - t * 0.22));

    float f = fbm(uv * 3.0 + r * WARP_STRENGTH * 4.0);

    // Colour ramp: deep indigo → teal → warm accent at the brightest wisps
    float3 deep   = float3(0.02, 0.01, 0.06);
    float3 mid    = float3(0.04, 0.12, 0.28);
    float3 bright = float3(0.10, 0.40, 0.52);
    float3 accent = float3(0.45, 0.22, 0.50);

    float3 col = deep;
    col = lerp(col, mid,    smoothstep(0.0,  0.4,  f));
    col = lerp(col, bright, smoothstep(0.35, 0.65, f));
    col = lerp(col, accent, smoothstep(0.6,  0.85, f) * 0.5);

    // A second, offset cloud layer adds depth without extra octaves
    float f2 = fbm(uv * 2.2 + float2(t * 0.5, -t * 0.3) + 50.0);
    float3 warm = float3(0.32, 0.08, 0.18);
    col += warm * smoothstep(0.45, 0.72, f2) * 0.22;

    col *= BRIGHTNESS;

    // Vignette
    float2 vigUV = tex * 2.0 - 1.0;
    float vign = 1.0 - dot(vigUV, vigUV) * VIGNETTE_STR;
    col *= max(0.0, vign);

    // Composite under terminal text
    float4 terminal = shaderTexture.Sample(samplerState, tex);
    float  luma     = dot(terminal.rgb, float3(0.299, 0.587, 0.114));
    float  textMask = smoothstep(0.20, 0.60, luma);

    return lerp(float4(col, 1.0), terminal, textMask);
}
