// Windows Terminal pixel shader
// Converted from a Shadertoy (GLSL) shader to HLSL.
// Original shader: https://www.shadertoy.com/view/XstXR2
// Author: see the Shadertoy page above (credit them when redistributing).
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported
//          (Shadertoy default unless the author stated another license on-site).
// Changes: GLSL→HLSL; Y-axis flip for Terminal; logo composited under text via shaderTexture.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float  Time;        // replaces iTime
    float  Scale;
    float2 Resolution;  // replaces iResolution
    float4 Background;
};

#define PI 3.1415926535897932384626433832795

static const float wave_amplitude = 0.076;
static const float period = 2.0 * PI;

float wave_phase()
{
    return Time;
}

float square(float2 st)
{
    float2 bl = step(float2(0.0, 0.0), st);        // bottom-left
    float2 tr = step(float2(0.0, 0.0), 1.0 - st);  // top-right
    return bl.x * bl.y * tr.x * tr.y;
}

float4 frame(float2 st)
{
    // Original: st * mat2(1/.48, 0, 0, 1/.69) -> diagonal scale.
    float tushka = square(st * float2(1.0 / 0.48, 1.0 / 0.69));

    // Original sector_mat = mat2(1/.16, 0, 0, 1/.22) -> diagonal scale.
    float2 sector_scale = float2(1.0 / 0.16, 1.0 / 0.22);
    float sectors[4];
    sectors[0] = square(st * sector_scale + (1.0 / 0.16) * float2( 0.000, -0.280));
    sectors[1] = square(st * sector_scale + (1.0 / 0.16) * float2( 0.000, -0.060));
    sectors[2] = square(st * sector_scale + (1.0 / 0.16) * float2(-0.240, -0.280));
    sectors[3] = square(st * sector_scale + (1.0 / 0.16) * float2(-0.240, -0.060));

    float3 c0 = float3(0.941, 0.439, 0.404) * sectors[0];
    float3 c1 = float3(0.435, 0.682, 0.843) * sectors[1];
    float3 c2 = float3(0.659, 0.808, 0.506) * sectors[2];
    float3 c3 = float3(0.996, 0.859, 0.114) * sectors[3];

    return float4(c0 + c1 + c2 + c3, tushka);
}

float4 trail_piece(float2 st, float2 index, float scale)
{
    scale = index.x * 0.082 + 0.452;

    float3 color;
    if (index.y > 0.9 && index.y < 2.1)
    {
        color = float3(0.435, 0.682, 0.843);
        scale *= 0.8;
    }
    else if (index.y > 3.9 && index.y < 5.1)
    {
        color = float3(0.941, 0.439, 0.404);
        scale *= 0.8;
    }
    else
    {
        color = float3(0.0, 0.0, 0.0);
    }

    float scale1 = 1.0 / scale;
    float shift = -(1.0 - scale) / (2.0 * scale);

    // Original: vec3(st, 1.) * mat3(scale1,0,shift, 0,scale1,shift, 0,0,1)
    // -> st * scale1 + shift (both components).
    float2 st2 = st * scale1 + shift;
    float mask = square(st2);

    return float4(color, mask);
}

float4 trail(float2 st)
{
    // actually 1/width, 1/height
    const float piece_height = 7.0 / 0.69;
    const float piece_width = 6.0 / 0.54;

    // make distance between smaller segments slightly lower
    st.x = 1.2760 * pow(st.x, 3.0) - 1.4624 * st.x * st.x + 1.4154 * st.x;

    float x_at_cell = floor(st.x * piece_width) / piece_width;
    float x_at_cell_center = x_at_cell + 0.016;
    float incline = cos(0.5 * period + wave_phase()) * wave_amplitude;

    float offset = sin(x_at_cell_center * period + wave_phase()) * wave_amplitude +
        incline * (st.x - x_at_cell) * 5.452;

    float mask = step(offset, st.y) * (1.0 - step(0.69 + offset, st.y)) * step(0.0, st.x);

    float2 cell_coord = float2((st.x - x_at_cell) * piece_width,
                               frac((st.y - offset) * piece_height));
    float2 cell_index = float2(x_at_cell * piece_width,
                               floor((st.y - offset) * piece_height));

    float4 pieces = trail_piece(cell_coord, cell_index, 0.752);

    return float4(pieces.rgb, pieces.a * mask);
}

float4 logo(float2 st)
{
    if (st.x <= 0.54)
    {
        return trail(st);
    }
    else
    {
        float2 st2 = st + float2(0.0, -sin(st.x * period + wave_phase()) * wave_amplitude);
        return frame(st2 + float2(-0.54, 0.0));
    }
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    // Shadertoy's origin is bottom-left; Terminal's tex origin is top-left.
    float2 st = tex;
    st.y = 1.0 - st.y;
    st.x *= Resolution.x / Resolution.y;

    st *= 1.472;
    st += float2(-0.7, -0.68);

    // Rotation: original st *= mat2(cos,sin,-sin,cos) (GLSL column-major,
    // row-vector multiply) expands to the following.
    float rot = PI * -0.124;
    st = float2( st.x * cos(rot) + st.y * sin(rot),
                -st.x * sin(rot) + st.y * cos(rot));

    float4 logo_ = logo(st);

    // Composite the animated logo *under* the terminal text: sample the live
    // terminal content and suppress the logo where the underlying pixels are
    // bright (i.e. text), so the text stays on top and readable.
    float4 terminal = shaderTexture.Sample(samplerState, tex);
    float luma = dot(terminal.rgb, float3(0.299, 0.587, 0.114));
    float textMask = smoothstep(0.45, 0.85, luma); // bright text -> 1
    float a = logo_.a * (1.0 - textMask);
    return lerp(terminal, float4(logo_.rgb, 1.0), a);
}
