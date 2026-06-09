// Windows Terminal pixel shader: "Flow"
//
// Gentle undulating colour gradients — like light refracting through slow water.
// Pure trig math (sin/cos), no noise loops or ray marching, so it's very cheap.
// Pair with a dark terminal profile and no backgroundImage.
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
#define SPEED         0.25       // animation speed (lower = calmer)
#define BRIGHTNESS    0.42       // overall intensity (0 = black, 1 = vivid)
#define WAVE_SCALE    3.0        // spatial frequency of the waves
#define VIGNETTE_STR  0.40       // edge darkening
// ────────────────────────────────────────────────────────────────────────────

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float aspect = Resolution.x / max(Resolution.y, 1.0);
    float2 uv = (tex - 0.5) * float2(aspect, 1.0);

    float t = Time * SPEED;

    // Three overlapping wave fields at different angles and speeds
    float w1 = sin(uv.x * WAVE_SCALE * 1.0 + uv.y * WAVE_SCALE * 0.7 + t * 1.0);
    float w2 = sin(uv.x * WAVE_SCALE * 0.6 - uv.y * WAVE_SCALE * 1.2 + t * 1.3 + 2.0);
    float w3 = sin(uv.x * WAVE_SCALE * 1.3 + uv.y * WAVE_SCALE * 0.4 - t * 0.8 + 4.5);

    // Combine into a smooth 0..1 field
    float f = (w1 + w2 + w3) / 6.0 + 0.5;

    // Subtle second-order shimmer
    float shimmer = sin(uv.x * 7.0 + uv.y * 5.0 + t * 2.5) * 0.05;
    f += shimmer;
    f = saturate(f);

    // Colour palette: dark teal → muted blue → soft purple highlight
    float3 dark   = float3(0.02, 0.05, 0.10);
    float3 mid    = float3(0.06, 0.16, 0.30);
    float3 bright = float3(0.18, 0.30, 0.48);
    float3 accent = float3(0.30, 0.14, 0.42);

    float3 col = dark;
    col = lerp(col, mid,    smoothstep(0.20, 0.45, f));
    col = lerp(col, bright, smoothstep(0.45, 0.70, f));
    col = lerp(col, accent, smoothstep(0.70, 0.90, f) * 0.4);

    col *= BRIGHTNESS;

    // Vignette
    float2 vigUV = tex * 2.0 - 1.0;
    float vign = 1.0 - dot(vigUV, vigUV) * VIGNETTE_STR;
    col *= max(0.0, vign);

    // Composite: shader is the background, terminal text drawn on top.
    float4 terminal = shaderTexture.Sample(samplerState, tex);
    float  luma     = dot(terminal.rgb, float3(0.299, 0.587, 0.114));
    float  textMask = smoothstep(0.04, 0.22, luma);
    float3 result   = lerp(col, terminal.rgb, textMask);

    return float4(saturate(result), 1.0);
}
