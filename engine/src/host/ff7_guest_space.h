/* ff7_guest_space.h - where guest (game) memory lives.
 *
 * Flat (RECOMP_FLAT_MEMORY; the x86_64 Mac build, Android): a guest address is the host
 * address. Offset (Apple arm64: macOS and iOS keep the low 4 GB unmapped): a 4 GB range is
 * reserved anywhere, g_mem_base is its start, and a guest address is an offset into it.
 * ff7_guest_space_init() makes the reservation (once; anything mapping guest memory calls it
 * first, as FFNx's static block does during static initialisation). */
#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#ifdef RECOMP_FLAT_MEMORY
static inline void ff7_guest_space_init(void) {}
#define FF7_HOST(va) ((void *)(uintptr_t)(uint32_t)(va))
#define FF7_VA(p)    ((uint32_t)(uintptr_t)(p))
#else
extern ptrdiff_t g_mem_base;
void ff7_guest_space_init(void);
#define FF7_HOST(va) ((void *)((uintptr_t)(uint32_t)(va) + (uintptr_t)g_mem_base))
#define FF7_VA(p)    ((uint32_t)((uintptr_t)(p) - (uintptr_t)g_mem_base))
#endif
#ifdef __cplusplus
}
#endif
