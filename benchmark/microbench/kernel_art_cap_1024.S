    .syntax unified
    .thumb

    .global bench_art_cap_1024_asm
    .thumb_func
    .type bench_art_cap_1024_asm, %function
bench_art_cap_1024_asm:
    mov r0, #100
1:
    .rept 1024
    nop
    .endr
    subs r0, r0, #1
    bne 1b
    bx lr
