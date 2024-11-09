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
        float smoothedValue = volumeScale * (0.1 * waveform[i] + 0.2 * waveform[i + 2]);
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
    float waveformScaleX = (float)canvasWidthPx / waveformLength;
    float halfCanvasHeight = (float)(canvasHeightPx / 2);
    float inverse255 = 1.0f / 255.0f;

    if (milky_soundFrameCounter % 2 == 0) {
        memcpy(milky_soundCachedWaveform, emphasizedWaveform, waveformLength * sizeof(float));
    }
    milky_soundFrameCounter++;

    for (size_t i = 0; i < waveformLength - 1; i++) {
        // Compute coordinates for the first point
        float x1 = (i * waveformScaleX) + xOffset;
        x1 = (x1 >= canvasWidthPx) ? (float)(canvasWidthPx - 1) : x1;

        float sampleValue1 = milky_soundCachedWaveform[i];
        float y1 = halfCanvasHeight - ((sampleValue1 - 128.0f - milky_soundAverageOffset) * canvasHeightPx) / 512.0f + yOffset;
        y1 = (y1 >= canvasHeightPx) ? (float)(canvasHeightPx - 1) : ((y1 < 0.0f) ? 0.0f : y1);

        // Compute coordinates for the second point
        float x2 = ((i + 1) * waveformScaleX) + xOffset;
        x2 = (x2 >= canvasWidthPx) ? (float)(canvasWidthPx - 1) : x2;

        float sampleValue2 = milky_soundCachedWaveform[i + 1];
        float y2 = halfCanvasHeight - ((sampleValue2 - 128.0f - milky_soundAverageOffset) * canvasHeightPx) / 512.0f + yOffset;
        y2 = (y2 >= canvasHeightPx) ? (float)(canvasHeightPx - 1) : ((y2 < 0.0f) ? 0.0f : y2);

        // Compute alpha
        float alpha = (1.0f - (sampleValue1 * inverse255)) * globalAlphaFactor;

        // Draw anti-aliased line
        drawLineWu(frame, canvasWidthPx, canvasHeightPx, x1, y1, x2, y2, 255, 255, 255, alpha);
    }
}
