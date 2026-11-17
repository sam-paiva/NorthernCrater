/* ff7_guest_space.c - the offset build's guest address space (see ff7_guest_space.h). */
#include "ff7_guest_space.h"
#ifndef RECOMP_FLAT_MEMORY
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>

ptrdiff_t g_mem_base;

static void reserve(void) {
    /* 4 GB of address space, nothing committed: the pieces (the exe image, the heap arena,
     * the VirtualAlloc region, FFNx's block) are mapped into it later at their guest addresses. */
    void *p = mmap(NULL, (size_t)1 << 32, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (p == MAP_FAILED) { fprintf(stderr, "[ff7] FATAL: cannot reserve 4 GB of address space for the game\n"); abort(); }
    g_mem_base = (ptrdiff_t)p;
    fprintf(stderr, "[ff7] guest memory at %p (offset build)\n", p);
}

void ff7_guest_space_init(void) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, reserve);
}
#endif
