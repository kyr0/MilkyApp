#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Simple random noise function for grain effect
float random(float2 uv) {
    return fract(sin(dot(uv ,float2(12.9898,78.233))) * 43758.5453);
}

// Vertex shader
vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = in.position;
    out.texCoord = in.texCoord;
    return out;
}


// Cubic Hermite interpolation function
float cubicHermite(float A, float B, float C, float D, float t) {
    float a = -A / 2.0 + (3.0 * B) / 2.0 - (3.0 * C) / 2.0 + D / 2.0;
    float b = A - (5.0 * B) / 2.0 + 2.0 * C - D / 2.0;
    float c = -A / 2.0 + C / 2.0;
    float d = B;
    return a * t * t * t + b * t * t + c * t + d;
}

// Bicubic weight function
float bicubicWeight(float x) {
    x = abs(x);
    if (x <= 1.0) {
        return (1.5 * x - 2.5) * x * x + 1.0;
    } else if (x < 2.0) {
        return ((-0.5 * x + 2.5) * x - 4.0) * x + 2.0;
    } else {
        return 0.0;
    }
}

#define MAX_RADIUS 5 // Define the maximum blur radius

// Corrected gaussianBlur function with dynamic radius
float4 gaussianBlur(texture2d<float, access::sample> texture, sampler s, float2 uv, float2 textureSize, int radius) {
    float4 result = float4(0.0);
    float totalWeight = 0.0;

    // Clamp radius to MAX_RADIUS to prevent exceeding array bounds
    radius = min(radius, MAX_RADIUS);

    // Calculate sigma based on the radius
    float sigma = float(radius) / 2.0; // Adjust sigma as needed
    float twoSigmaSq = 2.0 * sigma * sigma;

    // Precompute Gaussian weights
    int kernelSize = radius * 2 + 1;
    float weights[2 * MAX_RADIUS + 1]; // Fixed-size array
    float weightSum = 0.0;

    for (int i = 0; i < kernelSize; ++i) {
        float x = float(i - radius);
        float weight = exp(-x * x / twoSigmaSq);
        weights[i] = weight;
        weightSum += weight;
    }

    // Normalize weights
    for (int i = 0; i < kernelSize; ++i) {
        weights[i] /= weightSum;
    }

    // Apply Gaussian blur
    for (int x = -radius; x <= radius; ++x) {
        for (int y = -radius; y <= radius; ++y) {
            float2 offset = float2(float(x), float(y)) / textureSize;
            float weight = weights[x + radius] * weights[y + radius];
            result += texture.sample(s, uv + offset) * weight;
            totalWeight += weight;
        }
    }

    // Normalize the result
    return result / totalWeight;
}


// Bicubic interpolation function
float4 bicubicSample(texture2d<float, access::sample> texture, sampler s, float2 uv, float2 textureSize) {
    uv = uv * textureSize - 0.5;

    float2 pixel = floor(uv);
    float2 f = uv - pixel;

    float4 result = float4(0.0);

    for (int m = -1; m <= 2; m++) {
        float4 c0 = texture.sample(s, (pixel + float2(-1.0, m)) / textureSize);
        float4 c1 = texture.sample(s, (pixel + float2( 0.0, m)) / textureSize);
        float4 c2 = texture.sample(s, (pixel + float2( 1.0, m)) / textureSize);
        float4 c3 = texture.sample(s, (pixel + float2( 2.0, m)) / textureSize);

        float4 row = float4(
            cubicHermite(c0.x, c1.x, c2.x, c3.x, f.x),
            cubicHermite(c0.y, c1.y, c2.y, c3.y, f.x),
            cubicHermite(c0.z, c1.z, c2.z, c3.z, f.x),
            cubicHermite(c0.w, c1.w, c2.w, c3.w, f.x)
        );

        float weight = cubicHermite(0.0, 1.0, 0.0, 0.0, f.y + m);
        result += row * weight;
    }

    return result;
}


// Fragment shader with pixelated upscaling and corrected corner vignette effect
fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> inputTexture [[texture(0)]]) {
    
    // Sampler with linear filtering and clamped addressing
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 textureSize = float2(inputTexture.get_width(), inputTexture.get_height());
    float2 uv = in.texCoord;
    
    float2 center = float2(0.5, 0.5);
    
    /*
    // Apply zoom-in effect
    float zoomFactor = 1.2; // Adjust zoom factor (>1.0 zooms in)
    
    // Adjust UV coordinates for zoom
    uv = (uv - center) / zoomFactor + center;
*/
   // Clamp UV coordinates to avoid sampling outside texture bounds
   uv = clamp(uv, 0.0, 1.0);

   // First: upscale with bicubic interpolation
   float4 color = bicubicSample(inputTexture, texSampler, uv, textureSize);

   // Then: apply slight blur with specified radius
   int blurRadius = 1; // Adjust the blur radius as needed (max is MAX_RADIUS)
   color = gaussianBlur(inputTexture, texSampler, uv, textureSize, blurRadius);


    // Calculate distances from the four corners
    float distTL = distance(uv, float2(0.0, 1.0)); // Top-left corner
    float distTR = distance(uv, float2(1.0, 1.0)); // Top-right corner
    float distBL = distance(uv, float2(0.0, 0.0)); // Bottom-left corner
    float distBR = distance(uv, float2(1.0, 0.0)); // Bottom-right corner

    // Find the minimum distance to any corner
    float cornerDist = min(min(distTL, distTR), min(distBL, distBR));

    // Apply smoothstep to create a smooth vignette effect in the corners
    float vignetteStart = 0.0;  // Distance where vignette effect is strongest (at the corner)
    float vignetteEnd = 0.5;    // Distance where vignette effect fades out
    float vignette = 1.0 - smoothstep(vignetteStart, vignetteEnd, cornerDist);

    // Adjust the vignette intensity
    float vignetteIntensity = 0.4; // Adjust intensity between 0.0 and 1.0
    color.rgb *= (1.0 - vignetteIntensity * vignette);
    
    // Diminish the center
    float distCenter = distance(uv, center);
    float centerDiminishStart = 0.0; // Start diminishing at the center
    float centerDiminishEnd = 0.03;   // End of diminishing effect
    float centerDiminish = smoothstep(centerDiminishStart, centerDiminishEnd, distCenter);

    // Adjust the center diminishing intensity
    float centerDiminishIntensity = 0.2; // Adjust intensity between 0.0 and 1.0
    color.rgb *= (1.0 - centerDiminishIntensity * (1.0 - centerDiminish));

    // Apply gamma correction to adjust brightness
    float gamma = 1.15;
    color.rgb = pow(color.rgb, float3(1.0 / gamma));

    // Add grain effect for texture
    float grainAmount = 0.05;
    //float2 textureSize = float2(inputTexture.get_width(), inputTexture.get_height());
    float grain = random(in.texCoord * textureSize) * grainAmount;
    color.rgb += float3(grain);
    
    // Clamp the final color values to valid range
    color.rgb = clamp(color.rgb, 0.0, 1.0);

    return color;
}
