/* Plays one PCM WAV on the PulseAudio or PipeWire socket.
   The rope writes 16-bit little-endian files. The KDE runtime has no
   pw-play, so the Flatpak ships this instead. */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <pulse/error.h>
#include <pulse/simple.h>

static uint16_t read16(const unsigned char *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read32(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: chotki-play file.wav\n");
        return 2;
    }
    FILE *file = fopen(argv[1], "rb");
    if (!file) {
        fprintf(stderr, "chotki-play: %s: %s\n", argv[1], strerror(errno));
        return 1;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return 1;
    }
    long length = ftell(file);
    if (length < 44 || length > 8L * 1024L * 1024L) {
        fprintf(stderr, "chotki-play: unexpected wav length\n");
        fclose(file);
        return 1;
    }
    if (fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return 1;
    }
    unsigned char *bytes = malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) {
        free(bytes);
        fclose(file);
        return 1;
    }
    fclose(file);
    if (memcmp(bytes, "RIFF", 4) != 0 || memcmp(bytes + 8, "WAVE", 4) != 0) {
        fprintf(stderr, "chotki-play: not a wav file\n");
        free(bytes);
        return 1;
    }

    int rate = 0;
    int channels = 0;
    int bits = 0;
    const unsigned char *pcm = NULL;
    uint32_t pcm_bytes = 0;
    for (long offset = 12; offset + 8 <= length;) {
        const unsigned char *chunk = bytes + offset;
        uint32_t size = read32(chunk + 4);
        const unsigned char *body = chunk + 8;
        if (offset + 8L + (long)size > length) break;
        if (memcmp(chunk, "fmt ", 4) == 0 && size >= 16) {
            if (read16(body) != 1) {
                fprintf(stderr, "chotki-play: only PCM wav files play\n");
                free(bytes);
                return 1;
            }
            channels = read16(body + 2);
            rate = (int)read32(body + 4);
            bits = read16(body + 14);
        } else if (memcmp(chunk, "data", 4) == 0) {
            pcm = body;
            pcm_bytes = size;
        }
        offset += 8L + (long)size + (size & 1U);
    }
    if (!pcm || rate < 8000 || rate > 192000 || channels < 1 || channels > 2 || bits != 16) {
        fprintf(stderr, "chotki-play: need 16-bit PCM, one or two channels\n");
        free(bytes);
        return 1;
    }

    pa_sample_spec spec;
    spec.format = PA_SAMPLE_S16LE;
    spec.rate = (uint32_t)rate;
    spec.channels = (uint8_t)channels;
    int error = 0;
    pa_simple *pulse = pa_simple_new(NULL, "Chotki", PA_STREAM_PLAYBACK, NULL,
                                      "rope", &spec, NULL, NULL, &error);
    if (!pulse) {
        fprintf(stderr, "chotki-play: %s\n", pa_strerror(error));
        free(bytes);
        return 1;
    }
    if (pa_simple_write(pulse, pcm, pcm_bytes, &error) < 0 ||
        pa_simple_drain(pulse, &error) < 0) {
        fprintf(stderr, "chotki-play: %s\n", pa_strerror(error));
        pa_simple_free(pulse);
        free(bytes);
        return 1;
    }
    pa_simple_free(pulse);
    free(bytes);
    return 0;
}
