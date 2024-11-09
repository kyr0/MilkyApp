// video.hpp
#ifndef VIDEO_HPP
#define VIDEO_HPP

#include <stdint.h>
#include <stddef.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <sched.h>
#include "../Visualizer/video.h"
#include "audio.hpp"
#include <mach/mach.h>
#include <mach/thread_policy.h>

// Structure to hold arguments for the render loop
struct RenderLoopArgs {
    size_t canvasWidthPx;
    size_t canvasHeightPx;
    uint8_t bitDepth;
    size_t sampleRate;
    size_t sleepTime;
    size_t desiredFPS;
};

size_t getCurrentTimeMillis(void);
uint8_t *getDisplayBuffer(void);
void toggleBuffer(void);
uint8_t *getWriteBuffer(void);
void *renderLoop(void *arg);
void startContinuousRender(
    uint8_t *frameBufferA,
    uint8_t *frameBufferB,
   int32_t *sharedBufferIndex, 
    size_t canvasWidthPx,
    size_t canvasHeightPx,
    uint8_t bitDepth,
    size_t sampleRate,
    size_t delayMs,
    size_t desiredFPS
);

#endif // VIDEO_HPP
