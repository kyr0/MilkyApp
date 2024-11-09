#ifndef DRAW_H
#define DRAW_H

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

void clearFrame(uint8_t *frame, size_t frameSize);
void setPixel(uint8_t *frame, size_t canvasWidthPx, size_t canvasHeightPx,
              int x, int y, uint8_t srcR, uint8_t srcG, uint8_t srcB, uint8_t srcA);
void drawLine(uint8_t *frame, size_t width, size_t height, int x0, int y0, int x1, int y1, uint8_t r, uint8_t g, uint8_t b, uint8_t a);

#endif // DRAW_H
