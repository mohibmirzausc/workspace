// Simple "dithering" effect
// (c) moni-dz (https://github.com/moni-dz)
// CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

// Packed bayer pattern using bit manipulation
const float bayerPattern[4] = float[4](
    0x0514, // Encoding 0,8,2,10
    0xC4E6, // Encoding 12,4,14,6
    0x3B19, // Encoding 3,11,1,9
    0xF7D5  // Encoding 15,7,13,5
);

float getBayerFromPacked(int x, int y) {
    int idx = (x & 3) + ((y & 3) << 2);
    return float((int(bayerPattern[y & 3]) >> ((x & 3) << 2)) & 0xF) * (1.0 / 16.0);
}

// LOCAL MODIFICATIONS to the upstream shader (see header for origin):
//
// THE PROBLEM THIS SOLVES. Upstream dithers every pixel. That works on a
// near-black theme, where the background lands exactly on a quantisation
// step and produces no pattern. Catppuccin Mocha's background is #1e1e2e --
// RGB (0.118, 0.118, 0.18), a MID-dark colour that sits far from any step at
// low LEVELS, so the shader dithered the entire background into a dense grid
// that washed the whole terminal out.
//
// Measured distance-from-nearest-step for #1e1e2e:
//   LEVELS 2  -> 0.24/0.24/0.36   heavy dither
//   LEVELS 4  -> 0.47/0.47/0.28   heavy dither
//   LEVELS 8  -> 0.06/0.06/0.44   heavy dither (blue channel)
//   LEVELS 16 -> 0.12/0.12/0.11   light
//
// So instead of fighting it with LEVELS, background-coloured pixels are
// skipped outright: dithering applies to text and bright content, the
// background stays flat. That is what the reference screenshots actually
// look like -- texture on the glyphs, clean background.
//
// BG_COLOR must match `theme` in ghostty.nix. If the theme changes, change
// this too, or the background starts dithering again.
#define BG_COLOR vec3(0.118, 0.118, 0.180)
#define BG_TOLERANCE 0.06

// PIXEL_SIZE -- physical pixels per Bayer cell. Upstream is effectively 1,
// which on a 2x Retina panel is ~2pt across: too fine to read as dithering.
// LEVELS -- colour steps per channel; lower = stronger effect.
#define PIXEL_SIZE 2.0
#define LEVELS 3.0
#define INV_LEVELS (1.0 / LEVELS)

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord * (1.0 / iResolution.xy);
    vec3 color = texture(iChannel0, uv).rgb;

    // Leave the background alone. Without this the flat background is the
    // single largest dithered area on screen and drowns out the text.
    if (all(lessThan(abs(color - BG_COLOR), vec3(BG_TOLERANCE)))) {
        fragColor = vec4(color, 1.0);
        return;
    }

    // Quantise the coordinate before the lookup so one Bayer cell spans
    // PIXEL_SIZE physical pixels instead of one.
    vec2 cell = floor(fragCoord / PIXEL_SIZE);
    float threshold = getBayerFromPacked(int(cell.x), int(cell.y));
    vec3 dithered = floor(color * LEVELS + threshold) * INV_LEVELS;

    fragColor = vec4(dithered, 1.0);
}
