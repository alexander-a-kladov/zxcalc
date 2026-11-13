# zxcalc

; -----------------------------------------------------------------------------

; ZX BIG INTEGER CALCULATOR for ZX Spectrum 48

; SjASMPlus source. Variables: $8600-$C5FF (64 slots x 256 bytes)

;

; Slot layout: +0 = byte length (1..255), +1..+255 = unsigned magnitude,

; little-endian. Input/output notation is most-significant byte first.

; The sign of each variable is kept separately in NumberSigns[index]

; (0 = positive, 1 = negative). Zero is always positive.

;

; Commands:

;   2B=23049209348BCD32423    assign hexadecimal constant

;   2B=-23049209348BCD32423   assign negative constant (key J = '-')

;   00=01+2B                  add two variables      (signed)

;   00=01-2B                  subtract               (signed)

;   00=01*2B                  multiply               (signed)

;   00=01/2B                  divide  (remainder is never negative)

;   00=01M2B                  remainder, 0 <= r < |b|  (a = (a/b)*b + a M b)

;   00                        print a variable (with leading '-' if negative)

;   00=P                      pi into variable 00, 250 fractional bytes (key I types 'P')

;   00=P20                    pi with 20h fractional bytes (1..FA): the variable holds

;                             floor(pi * 256^n): top byte = 3, then n fraction bytes

;   00.                       print a variable in decimal as fixed point, e.g.

;                             3.14159265... (top byte . fraction; key N types '.')

;

; Input uses ROM KEY-SCAN + K-TEST, with one-key-per-press debouncing.

; Commands are parsed and range-checked before execution; accepted commands

; print an explicit success message, rejected commands print an error.

;

; NOTE: This source is a first complete implementation; assemble and test in

; an emulator before relying on it. It deliberately keeps the original

; AddVariable/PrintBigHex algorithms out of the old fixed test-data layout.

; -----------------------------------------------------------------------------

Компиляция:

sjasmplus zxcalc.asm
