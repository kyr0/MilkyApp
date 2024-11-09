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
        float smoothedValue = volumeScale * (0.8 * waveform[i] + 0.2 * waveform[i + 2]);
        formattedWaveform[i] = smoothedValue;
        totalOffset += smoothedValue - waveform[i];
    }
    // Calculate the average offset
    milky_soundAverageOffset = totalOffset / (waveformLength - 2);
}

void renderWaveformSimple(
    float timeFrame,
    uint8_t *frame,
    size_t canvasWidthPx,
    size_t canvasHeightPx,
    const float *emphasizedWaveform,
    size_t waveformLength,
    float globalAlphaFactor,
    int32_t yOffset
) {

    #ifdef __ARM_NEON__
    // NEON-optimized version
    float waveformScaleX = (float)canvasWidthPx / waveformLength;
    int32_t halfCanvasHeight = (int32_t)(canvasHeightPx / 2);
    float inverse255 = 1.0f / 255.0f;

    // Vector constants for NEON computations
    float32x4_t halfCanvasHeightVec = vdupq_n_f32((float)halfCanvasHeight);
    float32x4_t yOffsetVec = vdupq_n_f32((float)yOffset);
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
        size_t x1 = (size_t)(i * waveformScaleX);
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
        size_t x1 = (size_t)(i * waveformScaleX);
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
