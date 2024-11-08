#ifndef AUDIOTAPFFT_HPP
#define AUDIOTAPFFT_HPP

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreAudio/AudioHardware.h>
#include <Accelerate/Accelerate.h>
#include <vector>
#include <unordered_map>
#include <iostream>
#include <cmath>
#include <memory>

#include "video.hpp"

#define NUM_FFT_SIZES 5
extern const int fftSizes[NUM_FFT_SIZES]; // Declare fftSizes as extern

// Structure to hold FFT setup and buffers for real and imaginary components
typedef struct {
    FFTSetup fftSetup;
    DSPSplitComplex complexBuffer;
    float *realp;
    float *imagp;
} FFTProcessor;

// Structure to manage multiple FFT setups for different sizes
typedef struct {
    FFTProcessor *processors[NUM_FFT_SIZES];
} FFTManager;

// Functions to initialize and free FFT processor for a specific size
FFTProcessor *initializeFFTProcessor(int fftSize);
void freeFFTProcessor(FFTProcessor *processor);

// Functions to initialize and free FFTManager with setups for multiple sizes
FFTManager *initializeFFTManager();
void freeFFTManager(FFTManager *manager);

// Perform FFT on the provided sample data
void performFFT(const float *samples, int sampleCount, unsigned char *frequencyBins);

// Helper function to get the current time in seconds
double getCurrentTimeInSeconds(void);

// Functions to start and stop audio capture
void StartAudioCapture(AudioObjectID aggregatedDeviceId, AudioDeviceIOProcID *deviceProcID);
void StopAudioDeviceWithIOProc(AudioDeviceID aggregateDeviceID, AudioDeviceIOProcID *deviceProcID);

#endif // AUDIOTAPFFT_HPP
