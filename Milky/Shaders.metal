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
    float a = (-A + 3.0 * B - 3.0 * C + D) * 0.5;
    float b = (2.0 * A - 5.0 * B + 4.0 * C - D) * 0.5;
    float c = (-A + C) * 0.5;
    float d = B;
    return ((a * t + b) * t + c) * t + d;
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

    float4 sampleValues[4][4];

    // Sample the 4x4 neighborhood
    for (int m = -1; m <= 2; m++) {
        for (int n = -1; n <= 2; n++) {
            float2 coord = (pixel + float2(n, m)) / textureSize;
            coord = clamp(coord, 0.0, 1.0); // Clamp to texture bounds
            sampleValues[m + 1][n + 1] = texture.sample(s, coord);
        }
    }

    // Interpolate along x for each row
    float4 colValues[4];
    for (int m = 0; m < 4; m++) {
        colValues[m] = float4(
            cubicHermite(sampleValues[m][0].x, sampleValues[m][1].x, sampleValues[m][2].x, sampleValues[m][3].x, f.x),
            cubicHermite(sampleValues[m][0].y, sampleValues[m][1].y, sampleValues[m][2].y, sampleValues[m][3].y, f.x),
            cubicHermite(sampleValues[m][0].z, sampleValues[m][1].z, sampleValues[m][2].z, sampleValues[m][3].z, f.x),
            cubicHermite(sampleValues[m][0].w, sampleValues[m][1].w, sampleValues[m][2].w, sampleValues[m][3].w, f.x)
        );
    }

    // Interpolate along y using the results from x interpolation
    float4 result = float4(
        cubicHermite(colValues[0].x, colValues[1].x, colValues[2].x, colValues[3].x, f.y),
        cubicHermite(colValues[0].y, colValues[1].y, colValues[2].y, colValues[3].y, f.y),
        cubicHermite(colValues[0].z, colValues[1].z, colValues[2].z, colValues[3].z, f.y),
        cubicHermite(colValues[0].w, colValues[1].w, colValues[2].w, colValues[3].w, f.y)
    );

    return result;
}

// Function to convert RGB to HSV
float3 rgbToHsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Function to convert HSV back to RGB
float3 hsvToRgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float4 extractBrightAreas(float4 color, float threshold) {
    float luminance = dot(color.rgb, float3(0.299, 0.587, 0.114));
    float mask = step(threshold, luminance);
    return color * mask;
}

// 1D Gaussian blur function
float4 gaussianBlur1D(texture2d<float, access::sample> texture, sampler s, float2 uv, float2 textureSize, float2 direction, float sigma) {
    const int kernelSize = 9; // Adjust for desired blur size (must be odd)
    const int radius = (kernelSize - 1) / 2;
    float weights[kernelSize];
    float totalWeight = 0.0;

    // Precompute Gaussian weights
    for (int i = 0; i < kernelSize; ++i) {
        int x = i - radius;
        float weight = exp(-float(x * x) / (2.0 * sigma * sigma));
        weights[i] = weight;
        totalWeight += weight;
    }

    // Normalize weights
    for (int i = 0; i < kernelSize; ++i) {
        weights[i] /= totalWeight;
    }

    // Apply blur
    float4 result = float4(0.0);
    for (int i = -radius; i <= radius; ++i) {
        float2 offset = float2(i) * direction / textureSize;
        result += texture.sample(s, uv + offset) * weights[i + radius];
    }

    return result;
}

// Fragment shader with pixelated upscaling and corrected corner vignette effect
fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> inputTexture [[texture(0)]]) {
    
    // Sampler with linear filtering and clamped addressing
    constexpr sampler texSampler(mag_filter::nearest, min_filter::nearest, address::repeat);

    float2 textureSize = float2(inputTexture.get_width(), inputTexture.get_height());
    float2 uv = in.texCoord;
    
    float2 center = float2(0.5, 0.5);
    
    /*
    // Apply zoom-in effect
    float zoomFactor = 1.2; // Adjust zoom factor (>1.0 zooms in)
    
    // Adjust UV coordinates for zoom
    uv = (uv - center) / zoomFactor + center;
*/

   // First: upscale with bicubic interpolation
   float4 color = bicubicSample(inputTexture, texSampler, uv, textureSize);
    
    // Clamp UV coordinates to avoid sampling outside texture bounds
    uv = clamp(uv, 0.0, 1.0);

   // Then: apply slight blur with specified radius
   //int blurRadius = 2; // Adjust the blur radius as needed (max is MAX_RADIUS)
   //color = gaussianBlur(inputTexture, texSampler, uv, textureSize, blurRadius);

    // Vignette effect
    float dist = distance(uv, center);
    float vignette = smoothstep(0.5, 0.8, dist);
    float vignetteIntensity = 0.5;
    color.rgb *= mix(1.0, 1.0 - vignetteIntensity, vignette);
    
    // Diminish the center
    float distCenter = distance(uv, center);
    float centerDiminishStart = 0.0; // Start diminishing at the center
    float centerDiminishEnd = 0.03;   // End of diminishing effect
    float centerDiminish = smoothstep(centerDiminishStart, centerDiminishEnd, distCenter);

    // Adjust the center diminishing intensity
    float centerDiminishIntensity = 0.3; // Adjust intensity between 0.0 and 1.0
    color.rgb *= (1.0 - centerDiminishIntensity * (1.0 - centerDiminish));

    // Add grain effect for texture
    float grainAmount = 0.05;
    //float2 textureSize = float2(inputTexture.get_width(), inputTexture.get_height());
    float grain = random(in.texCoord * textureSize) * grainAmount;
    color.rgb += float3(grain);
    
    
    // **Bloom Effect Approximation**

    // Extract bright areas
    float bloomThreshold = 0.7; // Adjust threshold as needed
    float3 brightColor = max(color.rgb - bloomThreshold, 0.0) / (1.0 - bloomThreshold);

    // Approximate bloom by sampling neighboring pixels
    float bloomIntensity = 1.5; // Adjust bloom intensity
    float3 bloom = float3(0.0);
    int sampleCount = 8; // Number of samples
    float radius = 5.0 / min(textureSize.x, textureSize.y); // Adjust radius

    for (int i = 0; i < sampleCount; ++i) {
        float angle = float(i) / float(sampleCount) * 6.28318; // 2 * PI
        float2 offset = float2(cos(angle), sin(angle)) * radius;
        float2 sampleUV = uv + offset;
        sampleUV = clamp(sampleUV, 0.0, 1.0);
        float4 sampleColor = bicubicSample(inputTexture, texSampler, sampleUV, textureSize);
        float3 sampleBright = max(sampleColor.rgb - bloomThreshold, 0.0) / (1.0 - bloomThreshold);
        bloom += sampleBright;
    }

    bloom /= float(sampleCount);

    // Combine bloom with original color
    color.rgb += bloom * bloomIntensity;

    
    // **Boost saturation**
    float3 hsv = rgbToHsv(color.rgb);
    hsv.y = clamp(hsv.y * 1.2, 0.0, 1.0); // Increase saturation by 20%
    color.rgb = hsvToRgb(hsv);
    
    // Apply gamma correction to adjust brightness
    float gamma = 1.2; // Use a standard gamma value
    color.rgb = pow(color.rgb, float3(1.0 / gamma));

    // Clamp the final color values to valid range
    color.rgb = clamp(color.rgb, 0.0, 1.0);

    return color;
}
