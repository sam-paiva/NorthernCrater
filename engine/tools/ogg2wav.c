/* ogg2wav: decodes an Ogg Vorbis file to a 16-bit PCM WAV file. NorthernCrater uses it to play the sound
 * previews some mods ship (macOS has no Ogg decoder). Built on demand against the libogg/libvorbis sources the
 * engine build downloads (external/deps/ogg, external/deps/vorbis; BSD licenses).
 * usage: ogg2wav <in.ogg> <out.wav>   (exit 0 = ok) */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <vorbis/vorbisfile.h>

static void put32(unsigned char *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static void put16(unsigned char *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: ogg2wav in.ogg out.wav\n"); return 2; }
    OggVorbis_File vf;
    if (ov_fopen(argv[1], &vf) != 0) { fprintf(stderr, "not an Ogg Vorbis file\n"); return 1; }
    vorbis_info *info = ov_info(&vf, -1);
    int channels = info->channels, rate = (int)info->rate;
    FILE *out = fopen(argv[2], "wb");
    if (!out) { ov_clear(&vf); return 1; }
    unsigned char h[44] = {0};
    fwrite(h, 1, 44, out);                                     /* header patched at the end */
    char buf[8192]; uint32_t bytes = 0; int section = 0; long n;
    while ((n = ov_read(&vf, buf, sizeof buf, 0, 2, 1, &section)) > 0) { fwrite(buf, 1, (size_t)n, out); bytes += (uint32_t)n; }
    memcpy(h, "RIFF", 4); put32(h + 4, 36 + bytes); memcpy(h + 8, "WAVEfmt ", 8); put32(h + 16, 16); put16(h + 20, 1);
    put16(h + 22, (uint16_t)channels); put32(h + 24, (uint32_t)rate); put32(h + 28, (uint32_t)(rate * channels * 2));
    put16(h + 32, (uint16_t)(channels * 2)); put16(h + 34, 16); memcpy(h + 36, "data", 4); put32(h + 40, bytes);
    fseek(out, 0, SEEK_SET); fwrite(h, 1, 44, out); fclose(out); ov_clear(&vf);
    return n < 0 ? 1 : 0;
}
