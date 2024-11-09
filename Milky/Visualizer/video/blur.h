#ifndef BLUR_H
#define BLUR_H

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>

#ifdef __ARM_NEON__
#include <arm_neon.h>
#endif

void blurFrame(uint8_t *prevFrame, size_t frameSize, size_t step, float factor);
void preserveMassFade(uint8_t *prevFrame, uint8_t *frame, size_t frameSize);

#endif // BLUR_H
