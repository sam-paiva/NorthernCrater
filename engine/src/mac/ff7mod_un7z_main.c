/* ff7mod-un7z: unpack a .7z mod download (src/android/un7z.c, the launcher's own extractor). */
#include <stdio.h>
int ff7_un7z(const char *archive, const char *outdir, char *err, unsigned long errlen);
int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: %s <archive.7z> <outdir>\n", argv[0]); return 64; }
    char err[512] = "";
    int rc = ff7_un7z(argv[1], argv[2], err, sizeof err);
    if (rc != 0) { fprintf(stderr, "un7z: %s\n", err); return 1; }
    return 0;
}
