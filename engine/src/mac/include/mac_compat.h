/* mac_compat.h - force-included in every FF7Recomp source on macOS.
 *
 * The guest's 32-bit address space [0x10000, 0x80000000) is reserved up front by a zerofill
 * segment in the executable (src/mac/guest_reserve.s, linked non-PIE), so nothing of the host
 * lands there. Guest mappings then replace parts of that reservation: Linux's
 * MAP_FIXED_NOREPLACE (fail if anything is mapped) becomes MAP_FIXED here, as the only thing
 * mapped in that range is the reservation itself. */
#ifndef FF7_MAC_COMPAT_H
#define FF7_MAC_COMPAT_H
#ifdef __APPLE__
#include <sys/mman.h>
#include <pthread.h>
#include <stdint.h>
#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE MAP_FIXED
#endif
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
static inline int ff7_mac_gettid(void) {
    uint64_t t = 0;
    pthread_threadid_np(NULL, &t);
    return (int)t;
}
#define gettid() ff7_mac_gettid()
#ifndef PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP
#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP PTHREAD_RECURSIVE_MUTEX_INITIALIZER
#endif
/* glibc/bionic's pthread_getattr_np: only the stack is asked for (ff7_savestate.c). */
static inline int ff7_mac_getattr_np(pthread_t t, pthread_attr_t *a) {
    pthread_attr_init(a);
    char *top = (char *)pthread_get_stackaddr_np(t);
    size_t size = pthread_get_stacksize_np(t);
    return pthread_attr_setstack(a, top - size, size);
}
#define pthread_getattr_np(t, a) ff7_mac_getattr_np(t, a)
#ifndef _SC_AVPHYS_PAGES
#define _SC_AVPHYS_PAGES _SC_PHYS_PAGES   /* GlobalMemoryStatusEx: memory load reads 0 */
#endif
#endif
#endif
#if defined(__APPLE__) && !defined(POSIX_FADV_DONTNEED)
#define POSIX_FADV_DONTNEED 4
#define posix_fadvise(fd, off, len, adv) ((void)(fd), (void)(off), (void)(len), (void)(adv), 0)   /* a hint only */
#endif
