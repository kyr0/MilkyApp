#include "video.hpp"

// Double-buffering variables
static uint8_t *bufferA = NULL;
static uint8_t *bufferB = NULL;
static int isWritingToBufferA = 1;
static int displayBufferA = 1;
static pthread_mutex_t bufferMutex = PTHREAD_MUTEX_INITIALIZER;
static int renderLoopRunning = 1;

static double milky_lastFrameTime = 0;
static double milky_fps = 0;
static double milky_lastFpsLogTime = 0;

extern "C" void render(
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

// Function to get the display buffer (read-only)
uint8_t *getDisplayBuffer(void) {
    pthread_mutex_lock(&bufferMutex);
    uint8_t *displayBuffer = displayBufferA ? bufferA : bufferB;
    pthread_mutex_unlock(&bufferMutex);
    return displayBuffer;
}

// Toggle the writing buffer after a frame render is complete
void toggleBuffer(void) {
    pthread_mutex_lock(&bufferMutex);
    displayBufferA = isWritingToBufferA;
    isWritingToBufferA = !isWritingToBufferA;
    pthread_mutex_unlock(&bufferMutex);
}

// Function to get the active buffer for writing
uint8_t *getWriteBuffer(void) {
    return isWritingToBufferA ? bufferA : bufferB;
}

// Render loop function
void *renderLoop(void *arg) {
    RenderLoopArgs *args = (RenderLoopArgs *)arg;

    while (renderLoopRunning) {
        size_t currentTime = getCurrentTimeMillis();

        uint8_t *frameBuffer = getWriteBuffer();
        
        // Calculate FPS
        if (currentTime - milky_lastFpsLogTime >= 1000) {
            double deltaTime = (currentTime - milky_lastFrameTime) / 1000.0;  // Convert to seconds
            if (deltaTime > 0) {
                milky_fps = 1.0 / deltaTime;
                milky_lastFpsLogTime = currentTime;
                fprintf(stdout, "Render FPS: %.2f\n", milky_fps);
            }
        }
        milky_lastFrameTime = currentTime;
        
        render(
            frameBuffer,
            args->canvasWidthPx,
            args->canvasHeightPx,
            globalWaveform,
            globalSpectrum,
            globalWaveformLength,
            globalSpectrumLength,
            args->bitDepth,
            NULL,
            0.03f,
            currentTime,
            args->sampleRate
        );

        usleep(16000);
        toggleBuffer();
    }

    return NULL;
}

// Start continuous rendering
void startContinuousRender(uint8_t *frameBufferA, uint8_t *frameBufferB, size_t canvasWidthPx, size_t canvasHeightPx, uint8_t bitDepth, size_t sampleRate) {
    pthread_t renderThread;
    pthread_attr_t attr;
    struct sched_param param;

    bufferA = frameBufferA;
    bufferB = frameBufferB;

    RenderLoopArgs *args = (RenderLoopArgs *)malloc(sizeof(RenderLoopArgs));
    if (args == NULL) {
        fprintf(stderr, "Failed to allocate memory for render loop arguments\n");
        return;
    }

    args->canvasWidthPx = canvasWidthPx;
    args->canvasHeightPx = canvasHeightPx;
    args->bitDepth = bitDepth;
    args->sampleRate = sampleRate;

    pthread_attr_init(&attr);

    if (pthread_attr_setschedpolicy(&attr, SCHED_FIFO) == 0) {
        param.sched_priority = sched_get_priority_max(SCHED_FIFO);
        pthread_attr_setschedparam(&attr, &param);
    } else {
        fprintf(stderr, "Failed to set SCHED_FIFO; using default priority.\n");
    }

    pthread_create(&renderThread, &attr, renderLoop, args);
    pthread_detach(renderThread);

    pthread_attr_destroy(&attr);
}
