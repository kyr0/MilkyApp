#ifndef VIDEO_H
#define VIDEO_H

#include <sys/time.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#include <sched.h>

#ifdef __ARM_NEON__
#include <arm_neon.h>
#endif


#ifdef __cplusplus
extern "C" {
#endif


void render(
    uint8_t *frame,                 // Canvas frame buffer (RGBA format)
    size_t canvasWidthPx,           // Canvas width in pixels
    size_t canvasHeightPx,          // Canvas height in pixels
    const uint8_t *waveform,        // Waveform data array, 8-bit unsigned integers, 576 samples
    const uint8_t *spectrum,        // Spectrum data array
    size_t waveformLength,          // Length of the waveform data array
    size_t spectrumLength,          // Length of the spectrum data array
    uint8_t bitDepth,               // Bit depth of the rendering
    float *presetsBuffer,           // Preset data
    float speed,                    // Speed factor for the rendering
    size_t currentTime,             // Current time in milliseconds,
    size_t sampleRate               // Waveform sample rate (samples per second)
);

#ifdef __cplusplus
}
#endif

void reserveAndUpdateMemory(size_t canvasWidthPx, size_t canvasHeightPx,  uint8_t *frame, size_t frameSize);
void updateAudioData(const uint8_t *waveform, const uint8_t *spectrum, size_t waveformLength, size_t spectrumLength);

#endif // VIDEO_H
