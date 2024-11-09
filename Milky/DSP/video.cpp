#include "video.hpp"

// Double-buffering variables
static uint8_t *bufferA = NULL;
static uint8_t *bufferB = NULL;
static int isWritingToBufferA = 1;
static int displayBufferA = 1;
static pthread_mutex_t bufferMutex = PTHREAD_MUTEX_INITIALIZER;
static int renderLoopRunning = 1;

const useconds_t milky_minSleepTime = 1000; // Minimum sleep time (1 ms)
const useconds_t milky_maxSleepTime = 33000; // Maximum sleep time (33 ms)
const double milky_fpsAdjustmentFactor = 0.05; // Adjustment factor for sleep time

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
    size_t lastFrameTime = getCurrentTimeMillis();
    size_t lastFpsLogTime = lastFrameTime;
    useconds_t sleepTime = 33000;
    double currentFPS = 0;
    
    while (renderLoopRunning) {
        size_t currentTime = getCurrentTimeMillis();
        double deltaTime = (currentTime - lastFrameTime) / 1000.0; // Convert to seconds

        if (deltaTime > 0) {
            currentFPS = 1.0 / deltaTime;
        }

        // Log FPS every second
        if (currentTime - lastFpsLogTime >= 1000) {
            fprintf(stdout, "Render FPS: %.2f\n", currentFPS);
            lastFpsLogTime = currentTime;
        }

        lastFrameTime = currentTime;
        
        // Render frame
        uint8_t *frameBuffer = getWriteBuffer();
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
    
        // Adjust sleep time based on FPS
        if (currentFPS < args->desiredFPS && sleepTime > milky_minSleepTime) {
            sleepTime = (useconds_t)(sleepTime * (1.0 - milky_fpsAdjustmentFactor));
            if (sleepTime < milky_minSleepTime) {
                sleepTime = milky_minSleepTime;
            }
        } else if (currentFPS > args->desiredFPS && sleepTime < milky_maxSleepTime) {
            sleepTime = (useconds_t)(sleepTime * (1.0 + milky_fpsAdjustmentFactor));
            if (sleepTime > milky_maxSleepTime) {
                sleepTime = milky_maxSleepTime;
            }
        }
        // sleep to give time, limit rendering count
        
        // Sleep to control frame rate
        usleep(sleepTime);
        toggleBuffer();
    }

    return NULL;
}

size_t getCurrentTimeMillis(void) {
    struct timeval time;
    gettimeofday(&time, NULL);
    return (size_t)(time.tv_sec * 1000 + time.tv_usec / 1000);  // Convert to milliseconds
}

// Start continuous rendering with maximum performance optimizations
void startContinuousRender(
   uint8_t *frameBufferA,
   uint8_t *frameBufferB,
   size_t canvasWidthPx,
   size_t canvasHeightPx,
   uint8_t bitDepth,
   size_t sampleRate,
   size_t delayMs,
   size_t desiredFPS
) {
    pthread_t renderThread;
    pthread_attr_t attr;
    struct sched_param param;

    bufferA = frameBufferA;
    bufferB = frameBufferB;

    // Preallocate render loop arguments to avoid allocation within the loop
    RenderLoopArgs *args = (RenderLoopArgs *)malloc(sizeof(RenderLoopArgs));
    if (args == NULL) {
        fprintf(stderr, "Failed to allocate memory for render loop arguments\n");
        return;
    }

    args->canvasWidthPx = canvasWidthPx;
    args->canvasHeightPx = canvasHeightPx;
    args->bitDepth = bitDepth;
    args->sampleRate = sampleRate;
    args->sleepTime = delayMs;
    args->desiredFPS = desiredFPS;

    pthread_attr_init(&attr);

    // Set real-time priority for minimal latency
    param.sched_priority = sched_get_priority_max(SCHED_RR); // Round-Robin policy with max priority
    if (pthread_attr_setschedpolicy(&attr, SCHED_RR) != 0 || pthread_attr_setschedparam(&attr, &param) != 0) {
        fprintf(stderr, "Failed to set real-time priority; using default.\n");
    }

    // Set QoS class to user-interactive for high responsiveness on macOS
    if (pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0) != 0) {
        fprintf(stderr, "Failed to set QoS class; using default.\n");
    }

    if (pthread_create(&renderThread, &attr, renderLoop, args) != 0) {
        fprintf(stderr, "Failed to create render thread\n");
        free(args);
        pthread_attr_destroy(&attr);
        return;
    }

    // Set affinity to performance cores if on Apple Silicon or other multi-core systems
    thread_affinity_policy_data_t policy = { .affinity_tag = 1 };
    thread_port_t mach_thread = pthread_mach_thread_np(renderThread);
    kern_return_t kr = thread_policy_set(mach_thread, THREAD_AFFINITY_POLICY, (thread_policy_t)&policy, THREAD_AFFINITY_POLICY_COUNT);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Failed to set thread affinity policy: %d\n", kr);
    }

    // Detach the render thread and clean up thread attributes
    pthread_detach(renderThread);
    pthread_attr_destroy(&attr);
}
