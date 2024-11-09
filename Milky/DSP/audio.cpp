#include "audio.hpp"

// Global variable for FFTManager, initialized in StartAudioCapture and freed in StopAudioDeviceWithIOProc
static FFTManager *fftManager = NULL;
const int fftSizes[NUM_FFT_SIZES] = {128, 256, 512, 1024, 2048};

// Global audio data variables
uint8_t globalWaveform[MAX_WAVEFORM_SAMPLES];   // Adjust size as needed
uint8_t globalSpectrum[2048];   // Adjust size as needed
size_t globalWaveformLength = 0;
size_t globalSpectrumLength = 0;

static pthread_mutex_t audioDataMutex = PTHREAD_MUTEX_INITIALIZER;

// FPS counting
double lastTime = 0;
int frameCounter = 0;

static double lastFpsLogTime = 0;
static int audioFrameCounter = 0;
static double lastAudioUpdateTime = 0;
static double lastFFTUpdateTime = 0;
const double audioUpdateInterval = 1.0 / 60.0; // 30 updates per second
const double fftUpdateInterval = 1.0 / 15.0;   // 15 updates per second
const double fpsLogInterval = 1.0;             // Log FPS every second

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
    double currentTime = getCurrentTimeInSeconds();
    
    float *inputBuffer = (float *)inInputData->mBuffers[0].mData;
    UInt32 sampleCount = inInputData->mBuffers[0].mDataByteSize / sizeof(float);

    // Process audio data at 30 Hz
    if (currentTime - lastAudioUpdateTime >= audioUpdateInterval) {
        lastAudioUpdateTime = currentTime;

        if (inInputData && inInputData->mNumberBuffers > 0) {

            // Convert inputBuffer to waveform
            uint8_t waveform[MAX_WAVEFORM_SAMPLES];
            for (UInt32 i = 0; i < MAX_WAVEFORM_SAMPLES && i < sampleCount; i++) {
                waveform[i] = (uint8_t)((inputBuffer[i] + 1.0f) * 127.5f);
            }
            
            // Update global waveform data
            pthread_mutex_lock(&audioDataMutex);
            memcpy(globalWaveform, waveform, MAX_WAVEFORM_SAMPLES);
            globalWaveformLength = MAX_WAVEFORM_SAMPLES;
            pthread_mutex_unlock(&audioDataMutex);
        }
        audioFrameCounter++;
    }

    // Perform FFT at 15 Hz
    if (currentTime - lastFFTUpdateTime >= fftUpdateInterval) {
        lastFFTUpdateTime = currentTime;

        if (inInputData && inInputData->mNumberBuffers > 0) {

            // Perform FFT
            uint8_t spectrum[2048];
            performFFT(inputBuffer, sampleCount, spectrum);

            // Update global spectrum data
            pthread_mutex_lock(&audioDataMutex);
            memcpy(globalSpectrum, spectrum, 2048);
            globalSpectrumLength = 2048;
            pthread_mutex_unlock(&audioDataMutex);
        }
    }
    
    // Log audio FPS every second
    if (currentTime - lastFpsLogTime >= fpsLogInterval) {
        double fps = audioFrameCounter / (currentTime - lastFpsLogTime);
        printf("Audio FPS: %.2f\n", fps);
        lastFpsLogTime = currentTime;
        audioFrameCounter = 0;
    }
    return noErr;
}


// Update audio data
void updateAudioData(const uint8_t *waveform, const uint8_t *spectrum, size_t waveformLength, size_t spectrumLength) {
    pthread_mutex_lock(&audioDataMutex);
    
    // Ensure we don't overflow the global buffers
    globalWaveformLength = (waveformLength <= sizeof(globalWaveform)) ? waveformLength : sizeof(globalWaveform);
    globalSpectrumLength = (spectrumLength <= sizeof(globalSpectrum)) ? spectrumLength : sizeof(globalSpectrum);
    
    // Copy data into the global buffers
    memcpy(globalWaveform, waveform, globalWaveformLength);
    memcpy(globalSpectrum, spectrum, globalSpectrumLength);
    
    pthread_mutex_unlock(&audioDataMutex);
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
