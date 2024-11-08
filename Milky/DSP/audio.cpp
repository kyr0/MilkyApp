#include "audio.hpp"

// Global variable for FFTManager, initialized in StartAudioCapture and freed in StopAudioDeviceWithIOProc
static FFTManager *fftManager = NULL;
const int fftSizes[NUM_FFT_SIZES] = {128, 256, 512, 1024, 2048};

// FPS counting
double lastTime = 0;
int frameCounter = 0;

// Initialize an FFT processor for a specific size
FFTProcessor *initializeFFTProcessor(int fftSize) {
    FFTProcessor *processor = (FFTProcessor *)malloc(sizeof(FFTProcessor));
    int log2n = log2f(fftSize);
    processor->fftSetup = vDSP_create_fftsetup(log2n, kFFTRadix2);
    processor->realp = (float *)calloc(fftSize / 2, sizeof(float));
    processor->imagp = (float *)calloc(fftSize / 2, sizeof(float));
    processor->complexBuffer.realp = processor->realp;
    processor->complexBuffer.imagp = processor->imagp;
    return processor;
}

// Initialize FFTManager with pre-created FFT setups for different sizes
FFTManager *initializeFFTManager() {
    FFTManager *manager = (FFTManager *)malloc(sizeof(FFTManager));
    for (int i = 0; i < NUM_FFT_SIZES; i++) {
        manager->processors[i] = initializeFFTProcessor(fftSizes[i]);
        if (!manager->processors[i]->fftSetup) {
            fprintf(stderr, "Failed to create FFT setup for size %d\n", fftSizes[i]);
        }
    }
    return manager;
}

// Free resources in FFTProcessor
void freeFFTProcessor(FFTProcessor *processor) {
    vDSP_destroy_fftsetup(processor->fftSetup);
    free(processor->realp);
    free(processor->imagp);
    free(processor);
}

// Free all FFT setups in the manager
void freeFFTManager(FFTManager *manager) {
    for (int i = 0; i < NUM_FFT_SIZES; i++) {
        freeFFTProcessor(manager->processors[i]);
    }
    free(manager);
}

void performFFT(const float *samples, int sampleCount, unsigned char *frequencyBins) {
    // Find the appropriate FFT setup based on the sample count
    int fftSize = 0;
    FFTProcessor *processor = NULL;
    for (int i = 0; i < NUM_FFT_SIZES; i++) {
        if (fftSizes[i] >= sampleCount) {
            fftSize = fftSizes[i];
            processor = fftManager->processors[i];
            break;
        }
    }

    // Fall back to the largest size if no suitable size found
    if (!processor) {
        fftSize = fftSizes[NUM_FFT_SIZES - 1];
        processor = fftManager->processors[NUM_FFT_SIZES - 1];
    }

    // Prepare the complex buffer with the samples
    vDSP_ctoz((DSPComplex *)samples, 2, &processor->complexBuffer, 1, sampleCount / 2);

    // Perform the FFT
    vDSP_fft_zrip(processor->fftSetup, &processor->complexBuffer, 1, log2f(fftSize), FFT_FORWARD);

    // Calculate magnitudes
    float magnitudes[fftSize / 2];
    vDSP_zvmags(&processor->complexBuffer, 1, magnitudes, 1, sampleCount / 2);

    // Take the square root to get amplitude spectrum
    float sqrtMagnitudes[fftSize / 2];
    vvsqrtf(sqrtMagnitudes, magnitudes, (int *)&sampleCount);

    // Normalize and scale to 8-bit values (0–255)
    float scale = 2.0f / fftSize;
    for (int i = 0; i < sampleCount / 2; i++) {
        float scaledValue = sqrtMagnitudes[i] * scale * 127.5f + 128;
        int clampedValue = scaledValue < 0 ? 0 : (scaledValue > 255 ? 255 : (int)scaledValue);
        frequencyBins[i] = (unsigned char)clampedValue;
    }
}


// Helper function to get the current time in seconds
double getCurrentTimeInSeconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + (now.tv_nsec / 1e9);
}

OSStatus AudioDeviceIOProcCallback(
    AudioDeviceID inDevice,
    const AudioTimeStamp *inNow,
    const AudioBufferList *inInputData,
    const AudioTimeStamp *inInputTime,
    AudioBufferList *outOutputData,
    const AudioTimeStamp *inOutputTime,
    void *inClientData
) {
    // Get the current time in seconds
    double currentTime = getCurrentTimeInSeconds();
    double deltaTime = currentTime - lastTime;
    
    // Calculate FPS every second
    if (deltaTime >= 1.0) {
        double fps = frameCounter / deltaTime;
        printf("Audio FPS: %.2f\n", fps);
        
        // Reset counters
        lastTime = currentTime;
        frameCounter = 0;
    }
    
    // Process audio data if available
    if (inInputData && inInputData->mNumberBuffers > 0) {
        // Access the audio data buffer
        float *inputBuffer = (float *)inInputData->mBuffers[0].mData;
        UInt32 sampleCount = inInputData->mBuffers[0].mDataByteSize / sizeof(float);
        
        // Temporary arrays to hold the waveform and frequency bins
        uint8_t waveform[sampleCount];
        unsigned char frequencyBins[sampleCount / 2];
        
        // Convert `inputBuffer` to `waveform` (scaling as needed)
        for (UInt32 i = 0; i < sampleCount; i++) {
            waveform[i] = (uint8_t)((inputBuffer[i] + 1.0f) * 127.5f);  // Scale to 0–255
        }

        // Perform FFT and fill `frequencyBins`
        performFFT(inputBuffer, sampleCount, frequencyBins);
        
        // Update the global audio data (copy data into global buffers)
        updateAudioData(waveform, frequencyBins, sampleCount, sampleCount / 2);
    }
    
    // Increment the frame counter
    frameCounter++;

    return noErr;
}


void StartAudioCapture(AudioObjectID aggregatedDeviceId, AudioDeviceIOProcID *deviceProcID) {
    OSStatus status;
    // Initialize FFTManager with multiple FFT setups
    fftManager = initializeFFTManager();

    // Register the callback
    status = AudioDeviceCreateIOProcID(aggregatedDeviceId, AudioDeviceIOProcCallback, NULL, deviceProcID);
    if (status != noErr) {
        fprintf(stderr, "Failed to create IOProc ID: %d\n", (int)status);
        return;
    }

    // Start the device with the registered I/O procedure
    status = AudioDeviceStart(aggregatedDeviceId, *deviceProcID);
    if (status != noErr) {
        fprintf(stderr, "Failed to start device: %d\n", (int)status);
        AudioDeviceDestroyIOProcID(aggregatedDeviceId, *deviceProcID);
        return;
    }

    printf("Audio streaming started.\n");
}

void StopAudioDeviceWithIOProc(AudioDeviceID aggregateDeviceID, AudioDeviceIOProcID *deviceProcID) {
    AudioDeviceStop(aggregateDeviceID, *deviceProcID);
    AudioDeviceDestroyIOProcID(aggregateDeviceID, *deviceProcID);
    freeFFTManager(fftManager);
    printf("Audio streaming stopped.\n");
}
