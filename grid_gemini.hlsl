// Windows Terminal Pixel Shader
// Effect: Slowly moving, subtle cyber-grid that preserves text readability

Texture2D shaderTexture;
SamplerState samplerState;

// Variables passed in directly by Windows Terminal
cbuffer PixelShaderSettings {
    float  Time;
    float  Scale;
    float2 Resolution;
    float4 Background;
};

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    // Sample the original terminal window (text + background)
    float4 terminalColor = shaderTexture.Sample(samplerState, tex);
    
    // Calculate brightness (luminance) of the current pixel
    float luma = dot(terminalColor.rgb, float3(0.299, 0.587, 0.114));
    
    // If the pixel is bright (likely text), skip the background effect 
    // to keep your shell text perfectly readable.
    if (luma > 0.2) {
        return terminalColor;
    }

    // Generate the moving grid coordinates
    // The divisors (40.0) control the grid size. 
    // The Time multipliers (0.1) control the scroll speed.
    float gridX = abs(frac(tex.x * Resolution.x / 40.0 + Time * 0.1) - 0.5);
    float gridY = abs(frac(tex.y * Resolution.y / 40.0 - Time * 0.1) - 0.5);
    
    // Smooth out the edges to create sharp lines
    float lineX = smoothstep(0.45, 0.5, gridX);
    float lineY = smoothstep(0.45, 0.5, gridY);
    
    // Combine the X and Y lines and apply a subtle dark cyan color
    float gridIntensity = max(lineX, lineY) * 0.15; // 0.15 keeps it dim and unobtrusive
    float4 gridColor = float4(0.0, 0.4, 0.8, 1.0) * gridIntensity;
    
    // Add the glowing grid to the dark background
    return terminalColor + gridColor;
}