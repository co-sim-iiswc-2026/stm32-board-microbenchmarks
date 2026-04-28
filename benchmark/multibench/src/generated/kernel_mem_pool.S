@ HAND-WRITTEN — defines the two shared SRAM pools used by every memory-
@ partition kernel that needs working-set buffer space. Centralized here
@ so the partition's RAM footprint is bounded by 2 * 32 KB = 64 KB instead
@ of growing linearly with the number of kernels (each kernel previously
@ owned a private buffer and the partition overran 128 KB SRAM).
@
@ Pools:
@   mem_pool_a -- 32 KB, .bss zero-init. Used by load_seq, ldm_burst,
@                 load_streaming, load_random_huge (all read-only or
@                 read-then-overwrite).
@   mem_pool_b -- 32 KB, .bss zero-init. Used by store_seq, store_streaming,
@                 memcpy (as dst).
@
@ Two pools (vs one) so memcpy_8k can read from `_a` and write to `_b`
@ without aliasing.
@
@ Both pools live in main SRAM (default linker placement). If we later need
@ a CCM-RAM bench, point its kernel at a third symbol in .ccm.

.syntax unified
.cpu cortex-m4

.section .bss.mem_pool_a, "aw", %nobits
.balign 4
.global mem_pool_a
.type   mem_pool_a, %object
.size   mem_pool_a, 32768
mem_pool_a:
    .space 32768

.section .bss.mem_pool_b, "aw", %nobits
.balign 4
.global mem_pool_b
.type   mem_pool_b, %object
.size   mem_pool_b, 32768
mem_pool_b:
    .space 32768
