// Reserve the guest's 32-bit address space [0x10000, 0x80000000) in the executable itself
// (see src/mac/include/mac_compat.h). Placed with -segaddr FF7GUEST 0x10000; the link is
// non-PIE so it stays there. Zerofill: no file bytes, and no memory until the guest maps it.
.zerofill FF7GUEST,__guest,_ff7_guest_reserve,0x7FFF0000
.no_dead_strip _ff7_guest_reserve
