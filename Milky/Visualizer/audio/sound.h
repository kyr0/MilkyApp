#ifndef SOUND_H
#define SOUND_H

#include <stdint.h>
#include <string.h>
#include <math.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdbool.h>

#include "../video/draw.h"

#ifdef __ARM_NEON__
#include <arm_neon.h>
#endif

// Global variable to store the average offset introduced by smoothing
extern float milky_soundAverageOffset;

// Cache for the last rendered waveform
extern float milky_soundCachedWaveform[2048];

// Static variable to keep track of frame count
extern int milky_soundFrameCounter;

// Function to smooth the bass-emphasized waveform
void smoothBassEmphasizedWaveform(
    const uint8_t *waveform, 
    size_t waveformLength, 
    float *formattedWaveform, 
    size_t canvasWidthPx,
    float volumeScale
);

// Function to render a simple waveform with specified parameters
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
);

#endif // SOUND_H
