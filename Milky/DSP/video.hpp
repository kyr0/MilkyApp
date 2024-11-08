// video.hpp
#ifndef VIDEO_HPP
#define VIDEO_HPP

#include <stdint.h>
#include <stddef.h>
#include <pthread.h>

// Structure to hold arguments for the render loop
struct RenderLoopArgs {
    size_t canvasWidthPx;
    size_t canvasHeightPx;
    uint8_t bitDepth;
    size_t sampleRate;
};

// Function declarations
uint8_t *getDisplayBuffer(void);
void toggleBuffer(void);
uint8_t *getWriteBuffer(void);
void updateAudioData(const uint8_t *waveform, const uint8_t *spectrum, size_t waveformLength, size_t spectrumLength);
void *renderLoop(void *arg);
void startContinuousRender(uint8_t *frameBufferA, uint8_t *frameBufferB, size_t canvasWidthPx, size_t canvasHeightPx, uint8_t bitDepth, size_t sampleRate);

#endif // VIDEO_HPP
