#include "draw.h"

/**
 * Clears the entire frame buffer by setting all pixels to black and fully transparent.
 * This function uses memset to efficiently set all bytes in the frame buffer to 0.
 *
 * @param frame     The frame buffer to be cleared (RGBA format).
 * @param frameSize The size of the frame buffer in bytes.
 */
void clearFrame(uint8_t *frame, size_t frameSize) {
    memset(frame, 0, frameSize);
}

/**
 * Sets the RGBA values for a specific pixel in the frame buffer.
 * To do so, it modifies the color and transparency of a pixel located at
 * the specified (x, y) coordinates within the frame buffer. It ensures that
 * the pixel is within the bounds of the frame before setting the values.
 *
 * @param frame  The frame buffer where the pixel is to be set (RGBA format).
 * @param width  The width of the frame in pixels.
 * @param x      The x-coordinate of the pixel to set.
 * @param y      The y-coordinate of the pixel to set.
 * @param r      The red component value of the pixel.
 * @param g      The green component value of the pixel.
 * @param b      The blue component value of the pixel.
 * @param a      The alpha (transparency) component value of the pixel.
 */
void setPixel(uint8_t *frame, size_t canvasWidthPx, size_t canvasHeightPx,
              int x, int y, uint8_t srcR, uint8_t srcG, uint8_t srcB, uint8_t srcA) {
    if (x < 0 || x >= (int)canvasWidthPx || y < 0 || y >= (int)canvasHeightPx) return;

    size_t index = (y * canvasWidthPx + x) * 4; // Assuming RGBA format

    // Existing pixel values
    uint8_t dstR = frame[index];
    uint8_t dstG = frame[index + 1];
    uint8_t dstB = frame[index + 2];
    uint8_t dstA = frame[index + 3];

    // Convert alpha values to floats in range [0,1]
    float srcAlpha = srcA / 255.0f;
    float dstAlpha = dstA / 255.0f;

    // Compute the output alpha
    float outAlpha = srcAlpha + dstAlpha * (1.0f - srcAlpha);

    // Avoid division by zero
    if (outAlpha == 0.0f) {
        frame[index]     = 0;
        frame[index + 1] = 0;
        frame[index + 2] = 0;
        frame[index + 3] = 0;
        return;
    }

    // Blend the colors
    frame[index]     = (uint8_t)(((srcR * srcAlpha) + (dstR * dstAlpha * (1.0f - srcAlpha))) / outAlpha);
    frame[index + 1] = (uint8_t)(((srcG * srcAlpha) + (dstG * dstAlpha * (1.0f - srcAlpha))) / outAlpha);
    frame[index + 2] = (uint8_t)(((srcB * srcAlpha) + (dstB * dstAlpha * (1.0f - srcAlpha))) / outAlpha);
    frame[index + 3] = (uint8_t)(outAlpha * 255.0f);
}

/**
 Optimized Bresenham's line algorithm.
 
 Credits go to Jack Elton Bresenham who developed it in 1962 at IBM.
 https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm

 Draws a line on a screen buffer using the Bresenham's line algorithm.
 It calculates the line's path from (x0, y0) to (x1, y1) and sets the pixel intensity
 directly on the screen buffer. The algorithm is optimized for performance by avoiding
 function calls and using direct memory access. It also ensures that the line stays
 within the bounds of the screen canvas by clamping the coordinates.

 @param screen The screen buffer to draw the line on.
 @param width  The width of the screen buffer in pixels.
 @param height The height of the screen buffer in pixels.
 @param x0     The x-coordinate of the starting point of the line.
 @param y0     The y-coordinate of the starting point of the line.
 @param x1     The x-coordinate of the ending point of the line.
 @param y1     The y-coordinate of the ending point of the line.
*/
void drawLine(uint8_t *screen, size_t width, size_t height, int x0, int y0, int x1, int y1, uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    // Precompute pitch and initial position
    size_t pitch = width * 4; // assuming 4 bytes per pixel (RGBA)

    // Precompute RGBA pixel value in a buffer
    uint32_t pixel = (a << 24) | (b << 16) | (g << 8) | r;

    // Calculate deltas and step directions
    int dx = abs(x1 - x0);
    int dy = -abs(y1 - y0);
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;

    int x = x0;
    int y = y0;

    // Pre-check bounds to avoid repeatedly checking inside the loop
    if (x < 0 || x >= (int)width || y < 0 || y >= (int)height) return;

    while (1) {
        // Directly write the precomputed RGBA value to the screen buffer
        size_t index = (size_t)y * pitch + (size_t)x * 4;
        *((uint32_t*)&screen[index]) = pixel;

        // Break if end point is reached
        if (x == x1 && y == y1) break;

        // Adjust error and x/y positions based on Bresenham's algorithm
        int e2 = err << 1;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }

        // If the line moves out of bounds, break out
        if (x < 0 || x >= (int)width || y < 0 || y >= (int)height) break;
    }
}

