    .syntax unified
    .thumb

    .global bench_art_mix1x3_128_asm
    .thumb_func
    .type bench_art_mix1x3_128_asm, %function
bench_art_mix1x3_128_asm:
    .balign 16
    mov r0, #100
1:
    .rept 128
    nop
    add.w r1, r1, #0
    add.w r2, r2, #0
    add.w r3, r3, #0
    .endr
    subs r0, r0, #1
    bne 1b
    bx lr
