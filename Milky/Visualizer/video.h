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

typedef struct {
    uint8_t *frameBufferA;
    uint8_t *frameBufferB;
    size_t canvasWidthPx;
    size_t canvasHeightPx;
    uint8_t bitDepth;
    size_t sampleRate;
} RenderLoopArgs;

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

void reserveAndUpdateMemory(size_t canvasWidthPx, size_t canvasHeightPx,  uint8_t *frame, size_t frameSize);

size_t getCurrentTimeMillis(void) {
    struct timeval time;
    gettimeofday(&time, NULL);
    return (size_t)(time.tv_sec * 1000 + time.tv_usec / 1000);  // Convert to milliseconds
}

void startContinuousRender(uint8_t *frameBufferA, uint8_t *frameBufferB, size_t canvasWidthPx, size_t canvasHeightPx, uint8_t bitDepth, size_t sampleRate);

extern uint8_t *getDisplayBuffer(void);

void initializeBuffers(size_t bufferSize);
void toggleBuffer(void);

void updateAudioData(const uint8_t *waveform, const uint8_t *spectrum, size_t waveformLength, size_t spectrumLength);

#endif // VIDEO_H
