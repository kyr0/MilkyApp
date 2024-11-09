#include "sound.h"

// Global variable to store the average offset introduced by smoothing
float milky_soundAverageOffset = 0.0f;

// Cache for the last rendered waveform
float milky_soundCachedWaveform[2048]; // Assuming a fixed size for simplicity

// static variable to keep track of frame count
int milky_soundFrameCounter = 0;

void smoothBassEmphasizedWaveform(
    const uint8_t *waveform, 
    size_t waveformLength, 
    float *formattedWaveform, 
    size_t canvasWidthPx,
    float volumeScale // added volume scaling factor
) {
    float totalOffset = 0.0f;
    // smoothing shows the bass hits more than treble
    for (size_t i = 0; i < waveformLength - 2; i++) {
        float smoothedValue = volumeScale * (0.6 * waveform[i] + 0.2 * waveform[i + 2]);
        formattedWaveform[i] = smoothedValue;
        totalOffset += smoothedValue - waveform[i];
    }
    // Calculate the average offset
    milky_soundAverageOffset = totalOffset / (waveformLength - 2);
}

/*
void renderWaveformSimple(
    float timeFrame,
    uint8_t *frame,
    size_t canvasWidthPx,
    size_t canvasHeightPx,
    const float *emphasizedWaveform,
    size_t waveformLength,
    float globalAlphaFactor,
    int32_t yOffset,
    int32_t xOffset // New xOffset parameter
) {

    #ifdef __ARM_NEON__
    // NEON-optimized version
    float waveformScaleX = (float)canvasWidthPx / waveformLength;
    int32_t halfCanvasHeight = (int32_t)(canvasHeightPx / 2);
    float inverse255 = 1.0f / 255.0f;

    // Vector constants for NEON computations
    float32x4_t halfCanvasHeightVec = vdupq_n_f32((float)halfCanvasHeight);
    float32x4_t yOffsetVec = vdupq_n_f32((float)yOffset);
    float32x4_t xOffsetVec = vdupq_n_f32((float)xOffset); // Vectorized xOffset
    float32x4_t inverse255Vec = vdupq_n_f32(inverse255);
    float32x4_t globalAlphaFactorVec = vdupq_n_f32(globalAlphaFactor);
    float32x4_t oneVec = vdupq_n_f32(1.0f);
    float32x4_t scaleVec = vdupq_n_f32((float)canvasHeightPx / 512.0f);

    if (milky_soundFrameCounter % 2 == 0) {
        size_t i = 0;
        for (; i + 4 <= waveformLength; i += 4) {
            // Load 4 floats from the emphasizedWaveform
            float32x4_t waveformChunk = vld1q_f32(&emphasizedWaveform[i]);
            // Store the chunk in milky_soundCachedWaveform
            vst1q_f32(&milky_soundCachedWaveform[i], waveformChunk);
        }
        // Handle any remaining elements if waveformLength is not a multiple of 4
        for (; i < waveformLength; i++) {
            milky_soundCachedWaveform[i] = emphasizedWaveform[i];
        }
    }
    milky_soundFrameCounter++;

    for (size_t i = 0; i < waveformLength - 1; i += 4) {
        size_t x1 = (size_t)(i * waveformScaleX) + xOffset; // Apply xOffset
        x1 = (x1 >= canvasWidthPx) ? canvasWidthPx - 1 : x1;

        // Load and adjust sample values
        float32x4_t sampleValues = vld1q_f32(&milky_soundCachedWaveform[i]);
        float32x4_t adjustedSampleValues = vsubq_f32(vsubq_f32(sampleValues, vdupq_n_f32(128.0f)), vdupq_n_f32((float)milky_soundAverageOffset));
        float32x4_t yCoords = vmlaq_f32(halfCanvasHeightVec, adjustedSampleValues, scaleVec);
        yCoords = vaddq_f32(yCoords, yOffsetVec);

        // Alpha calculation - closely matching non-NEON version
        float32x4_t alphaCalculationStep1 = vsubq_f32(oneVec, vmulq_f32(sampleValues, inverse255Vec)); // 1.0f - (sampleValue * inverse255)
        float32x4_t alphaValuesFloat = vmulq_f32(alphaCalculationStep1, globalAlphaFactorVec);         // multiply by globalAlphaFactor
        float32x4_t alphaScaled = vmulq_f32(alphaValuesFloat, vdupq_n_f32(255.0f));                    // multiply by 255

        // Convert alpha values from float to uint8 using integer conversion steps
        uint16x4_t alphaValuesUInt16 = vqmovun_s32(vcvtq_s32_f32(alphaScaled)); // Convert to uint16 and saturate to avoid overflow
        uint8x8_t alpha8 = vqmovn_u16(vcombine_u16(alphaValuesUInt16, alphaValuesUInt16)); // Narrow to uint8

        // Convert yCoords to int32 for pixel plotting
        int32x4_t yCoordsInt32 = vcvtq_s32_f32(yCoords);
        int32_t yCoordsArray[4];
        vst1q_s32(yCoordsArray, yCoordsInt32);

        // Alpha array
        uint8_t alphaArray[4];
        vst1_u8(alphaArray, alpha8);

        // Plot pixels in the frame buffer
        for (int k = 0; k < 4; k++) {
            int x = (int)(x1 + k);
            int y = yCoordsArray[k];
            uint8_t alpha = alphaArray[k];

            if (x < canvasWidthPx && x >= 0 && y >= 0 && y < canvasHeightPx) {
                setPixel(frame, canvasWidthPx, canvasHeightPx, x, y, 255, 255, 255, alpha);
                if (x > 0) setPixel(frame, canvasWidthPx, canvasHeightPx, x - 1, y, 255, 255, 255, alpha);
                if (x < (int)canvasWidthPx - 1) setPixel(frame, canvasWidthPx, canvasHeightPx, x + 1, y, 255, 255, 255, alpha);
            }
        }
    }

    #else
    // Generic (non-NEON) version for comparison
    float waveformScaleX = (float)canvasWidthPx / waveformLength;
    int32_t halfCanvasHeight = (int32_t)(canvasHeightPx / 2);
    float inverse255 = 1.0f / 255.0f;

    if (milky_soundFrameCounter % 2 == 0) {
        memcpy(milky_soundCachedWaveform, emphasizedWaveform, waveformLength * sizeof(float));
    }
    milky_soundFrameCounter++;

    for (size_t i = 0; i < waveformLength - 1; i++) {
        size_t x1 = (size_t)(i * waveformScaleX) + xOffset; // Apply xOffset
        x1 = (x1 >= canvasWidthPx) ? canvasWidthPx - 1 : x1;

        float sampleValue = milky_soundCachedWaveform[i];
        int32_t y = halfCanvasHeight - ((int32_t)((sampleValue - 128 - milky_soundAverageOffset) * canvasHeightPx) / 512) + yOffset;
        y = (y >= (int32_t)canvasHeightPx) ? (int32_t)canvasHeightPx - 1 : ((y < 0) ? 0 : y);

        uint8_t alpha = (uint8_t)(255 * (1.0f - (sampleValue * inverse255)) * globalAlphaFactor);

        setPixel(frame, canvasWidthPx, canvasHeightPx, x1, y, 255, 255, 255, alpha);

        if (x1 > 0) setPixel(frame, canvasWidthPx, canvasHeightPx, x1 - 1, y, 255, 255, 255, alpha);
        if (x1 < canvasWidthPx - 1) setPixel(frame, canvasWidthPx, canvasHeightPx, x1 + 1, y, 255, 255, 255, alpha);
    }
    #endif
}
*/
// Fractional part of x
static inline float fpart(float x) {
    return x - floorf(x);
}

// Reverse fractional part of x
static inline float rfpart(float x) {
    return 1.0f - fpart(x);
}

// Anti-aliased line drawing function (Xiaolin Wu's algorithm)
void drawLineWu(uint8_t *frame, size_t canvasWidthPx, size_t canvasHeightPx,
                float x0, float y0, float x1, float y1, uint8_t r, uint8_t g, uint8_t b, float alpha) {
    bool steep = fabsf(y1 - y0) > fabsf(x1 - x0);

    if (steep) {
        // Swap x and y
        float temp;
        temp = x0; x0 = y0; y0 = temp;
        temp = x1; x1 = y1; y1 = temp;
    }

    if (x0 > x1) {
        // Swap start and end points
        float temp;
        temp = x0; x0 = x1; x1 = temp;
        temp = y0; y0 = y1; y1 = temp;
    }

    float dx = x1 - x0;
    float dy = y1 - y0;
    float gradient = dx == 0.0f ? 1.0f : dy / dx;

    // Handle first endpoint
    float xend = roundf(x0);
    float yend = y0 + gradient * (xend - x0);
    float xgap = rfpart(x0 + 0.5f);
    int xpxl1 = (int)xend;
    int ypxl1 = (int)floorf(yend);

    float alpha1 = rfpart(yend) * xgap * alpha;
    float alpha2 = fpart(yend) * xgap * alpha;

    if (steep) {
        setPixel(frame, canvasWidthPx, canvasHeightPx, ypxl1, xpxl1, r, g, b, (uint8_t)(alpha1 * 255));
        setPixel(frame, canvasWidthPx, canvasHeightPx, ypxl1 + 1, xpxl1, r, g, b, (uint8_t)(alpha2 * 255));
    } else {
        setPixel(frame, canvasWidthPx, canvasHeightPx, xpxl1, ypxl1, r, g, b, (uint8_t)(alpha1 * 255));
        setPixel(frame, canvasWidthPx, canvasHeightPx, xpxl1, ypxl1 + 1, r, g, b, (uint8_t)(alpha2 * 255));
    }

    // First y-intersection for the main loop
    float intery = yend + gradient;

    // Handle second endpoint
    xend = roundf(x1);
    yend = y1 + gradient * (xend - x1);
    xgap = fpart(x1 + 0.5f);
    int xpxl2 = (int)xend;
    int ypxl2 = (int)floorf(yend);

    alpha1 = rfpart(yend) * xgap * alpha;
    alpha2 = fpart(yend) * xgap * alpha;

    if (steep) {
        setPixel(frame, canvasWidthPx, canvasHeightPx, ypxl2, xpxl2, r, g, b, (uint8_t)(alpha1 * 255));
        setPixel(frame, canvasWidthPx, canvasHeightPx, ypxl2 + 1, xpxl2, r, g, b, (uint8_t)(alpha2 * 255));
    } else {
        setPixel(frame, canvasWidthPx, canvasHeightPx, xpxl2, ypxl2, r, g, b, (uint8_t)(alpha1 * 255));
        setPixel(frame, canvasWidthPx, canvasHeightPx, xpxl2, ypxl2 + 1, r, g, b, (uint8_t)(alpha2 * 255));
    }

    // Main loop
    if (steep) {
        for (int x = xpxl1 + 1; x < xpxl2; x++) {
            int y = (int)floorf(intery);
            float alpha1 = rfpart(intery) * alpha;
            float alpha2 = fpart(intery) * alpha;
            setPixel(frame, canvasWidthPx, canvasHeightPx, y, x, r, g, b, (uint8_t)(alpha1 * 255));
            setPixel(frame, canvasWidthPx, canvasHeightPx, y + 1, x, r, g, b, (uint8_t)(alpha2 * 255));
            intery += gradient;
        }
    } else {
        for (int x = xpxl1 + 1; x < xpxl2; x++) {
            int y = (int)floorf(intery);
            float alpha1 = rfpart(intery) * alpha;
            float alpha2 = fpart(intery) * alpha;
            setPixel(frame, canvasWidthPx, canvasHeightPx, x, y, r, g, b, (uint8_t)(alpha1 * 255));
            setPixel(frame, canvasWidthPx, canvasHeightPx, x, y + 1, r, g, b, (uint8_t)(alpha2 * 255));
            intery += gradient;
        }
    }
}

// Anti-aliased line drawing function using Gupta-Sproull algorithm
void drawLineFade(uint8_t *frame, size_t canvasWidthPx, size_t canvasHeightPx,
                  int x0, int y0, int x1, int y1,
                  uint8_t r, uint8_t g, uint8_t b,
                  float startAlpha, float endAlpha) {
    int dx = abs(x1 - x0);
    int dy = -abs(y1 - y0);

    int sx = (x0 < x1) ? 1 : -1;
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;

    int length = (int)sqrtf((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    int currentStep = 0;

    while (true) {
        // Calculate alpha based on the progress along the line
        float t = (length == 0) ? 0.0f : (float)currentStep / length;
        float alpha = startAlpha * (1.0f - t) + endAlpha * t;
        uint8_t alphaByte = (uint8_t)(alpha * 255.0f);

        setPixel(frame, canvasWidthPx, canvasHeightPx, x0, y0, r, g, b, alphaByte);

        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;

        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }

        currentStep++;
    }
}

// Anti-aliased line drawing function using Gupta-Sproull algorithm
void drawLineAntiAliased(uint8_t *frame, size_t canvasWidthPx, size_t canvasHeightPx,
                         int x0, int y0, int x1, int y1,
                         uint8_t r, uint8_t g, uint8_t b, float baseAlpha) {
    int dx = abs(x1 - x0);
    int dy = abs(y1 - y0);

    // Determine the direction of the line
    int sx = (x0 < x1) ? 1 : -1;
    int sy = (y0 < y1) ? 1 : -1;

    bool steep = dy > dx;
    if (steep) {
        // Swap x and y
        int temp;
        temp = x0; x0 = y0; y0 = temp;
        temp = x1; x1 = y1; y1 = temp;
        temp = dx; dx = dy; dy = temp;
        temp = sx; sx = sy; sy = temp;
    }

    // Initialize variables
    int twoDy = 2 * dy;
    int twoDyDx = 2 * (dy - dx);
    int e = twoDy - dx;
    int x = x0;
    int y = y0;

    // Precompute constants for intensity calculation
    float invDenom = 1.0f / (2.0f * sqrtf(dx * dx + dy * dy));

    for (int i = 0; i <= dx; i++) {
        // Calculate pixel intensity
        float distance = fabsf(e) * invDenom;
        float intensityF = (1.0f - distance) * baseAlpha;
        uint8_t intensity = (uint8_t)(intensityF * 255.0f);

        if (steep) {
            // Swap back x and y
            setPixel(frame, canvasWidthPx, canvasHeightPx, y, x, r, g, b, intensity);
        } else {
            setPixel(frame, canvasWidthPx, canvasHeightPx, x, y, r, g, b, intensity);
        }

        // Move to the next pixel
        if (e >= 0) {
            y += sy;
            e += twoDyDx;
        } else {
            e += twoDy;
        }
        x += sx;
    }
}

void drawHorizontalLineWithEdgeSmoothing(uint8_t *frame, size_t canvasWidthPx, size_t canvasHeightPx,
                                         const float *waveform, size_t waveformLength,
                                         uint8_t r, uint8_t g, uint8_t b, float globalAlphaFactor,
                                         int32_t yOffset) {
    int32_t halfCanvasHeight = (int32_t)(canvasHeightPx / 2);

    for (size_t x = 0; x < canvasWidthPx; x++) {
        // Map x to waveform index
        float t = (float)x / (canvasWidthPx - 1);
        size_t i = (size_t)(t * (waveformLength - 1));

        float sampleValue = waveform[i];

        int y = halfCanvasHeight - ((int)((sampleValue - 128.0f - milky_soundAverageOffset) * canvasHeightPx) / 512) + yOffset;
        y = (y >= (int)canvasHeightPx) ? (int)canvasHeightPx - 1 : ((y < 0) ? 0 : y);

        // Compute alpha
        uint8_t alpha = (uint8_t)(255 * globalAlphaFactor);

        // Draw main pixel
        setPixel(frame, canvasWidthPx, canvasHeightPx, x, y, r, g, b, alpha);

        // Overdraw pixel above with 50% alpha of its existing color
        if (y > 0) {
            size_t indexAbove = ((y - 1) * canvasWidthPx + x) * 4;
            uint8_t existingR = frame[indexAbove];
            uint8_t existingG = frame[indexAbove + 1];
            uint8_t existingB = frame[indexAbove + 2];
            uint8_t existingA = frame[indexAbove + 3];

            // Overdraw with 50% alpha of existing color
            setPixel(frame, canvasWidthPx, canvasHeightPx, x, y - 1, existingR, existingG, existingB, 128);
        }

        // Overdraw pixel below with 50% alpha of its existing color
        if (y < (int)canvasHeightPx - 1) {
            size_t indexBelow = ((y + 1) * canvasWidthPx + x) * 4;
            uint8_t existingR = frame[indexBelow];
            uint8_t existingG = frame[indexBelow + 1];
            uint8_t existingB = frame[indexBelow + 2];
            uint8_t existingA = frame[indexBelow + 3];

            // Overdraw with 50% alpha of existing color
            setPixel(frame, canvasWidthPx, canvasHeightPx, x, y + 1, existingR, existingG, existingB, 128);
        }
    }
}

void renderWaveformSimple(
    float timeFrame,
    uint8_t *frame,
    size_t canvasWidthPx,
    size_t canvasHeightPx,
    const float *emphasizedWaveform,
    size_t waveformLength,
    float globalAlphaFactor,
    int32_t yOffset,
    int32_t xOffset
) {
    int32_t halfCanvasHeight = (int32_t)(canvasHeightPx / 2);

    // Optionally cache the waveform if needed
    if (milky_soundFrameCounter % 2 == 0) {
        memcpy(milky_soundCachedWaveform, emphasizedWaveform, waveformLength * sizeof(float));
    }
    milky_soundFrameCounter++;

    // Loop over every x-coordinate on the canvas
    for (int x = 0; x < (int)canvasWidthPx; x++) {
        // Map x coordinate to waveform index
        float t = (float)(x - xOffset) / (canvasWidthPx - 1);
        t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);  // Clamp t to [0, 1]
        size_t i = (size_t)(t * (waveformLength - 1));

        // Get the sample value
        float sampleValue = milky_soundCachedWaveform[i];

        // Compute y coordinate
        int y = halfCanvasHeight - ((int)((sampleValue - 128.0f - milky_soundAverageOffset) * canvasHeightPx) / 512) + yOffset;
        // Adjust y to ensure we have space for 2 pixels height
        y = (y >= (int)canvasHeightPx - 2) ? (int)canvasHeightPx - 3 : ((y < 0) ? 0 : y);

        // Compute alpha
        uint8_t alpha = (uint8_t)(255 * globalAlphaFactor);

        // Draw main line with thickness of 2 pixels
        setPixel(frame, canvasWidthPx, canvasHeightPx, x, y, 255, 255, 255, alpha);
        setPixel(frame, canvasWidthPx, canvasHeightPx, x, y + 1, 255, 255, 255, alpha);

        // Smooth the edges above and below the line
        // Blend pixel above the line
        if (y > 0) {
            // Read the existing color of the pixel above
            size_t indexAbove = ((y - 1) * canvasWidthPx + x) * 4;
            uint8_t existingR = frame[indexAbove];
            uint8_t existingG = frame[indexAbove + 1];
            uint8_t existingB = frame[indexAbove + 2];

            // Blend with the line color at 50% alpha
            uint8_t blendedR = (existingR + 255) / 2;
            uint8_t blendedG = (existingG + 255) / 2;
            uint8_t blendedB = (existingB + 255) / 2;

            // Overwrite the pixel above with the blended color and 50% alpha
            setPixel(frame, canvasWidthPx, canvasHeightPx, x, y - 1, blendedR, blendedG, blendedB, 128);
        }

        // Blend pixel below the line
        if (y < (int)canvasHeightPx - 3) {
            // Read the existing color of the pixel below
            size_t indexBelow = ((y + 2) * canvasWidthPx + x) * 4;
            uint8_t existingR = frame[indexBelow];
            uint8_t existingG = frame[indexBelow + 1];
            uint8_t existingB = frame[indexBelow + 2];

            // Blend with the line color at 50% alpha
            uint8_t blendedR = (existingR + 255) / 2;
            uint8_t blendedG = (existingG + 255) / 2;
            uint8_t blendedB = (existingB + 255) / 2;

            // Overwrite the pixel below with the blended color and 50% alpha
            setPixel(frame, canvasWidthPx, canvasHeightPx, x, y + 2, blendedR, blendedG, blendedB, 128);
        }
    }
}
