; -----------------------------------------------------------------------------
; ZX BIG INTEGER CALCULATOR for ZX Spectrum 128
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

        DEVICE ZXSPECTRUM128
        ORG     #C600

VAR_BASE        EQU     #8600
VAR_COUNT       EQU     64
MAX_BYTES       EQU     255
MAX_LINE        EQU     520
PI_GUARD        EQU     4                 ; extra low bytes carried while computing pi
PI_MAXFRAC      EQU     MAX_BYTES-1-PI_GUARD   ; 250 fractional bytes (~602 decimal digits)

; One shift/subtract step of long division by DE (16 bit): A = dividend byte
; (quotient bits enter at the bottom), HL = running remainder (< DE).
        MACRO DIVSTEP
        ADD     A,A
        ADC     HL,HL
        JR      C,1F                ; remainder overflowed 16 bits: must subtract
        SBC     HL,DE               ; Carry is clear here
        JR      NC,2F
        ADD     HL,DE               ; did not fit: restore, quotient bit = 0
        JR      3F
1:      CCF                         ; Carry was set: clear it, then subtract
        SBC     HL,DE
2:      INC     A                   ; quotient bit = 1
3:
        ENDM

Start:
        DI
        LD      SP,#FF00          ; stack in upper part of the currently paged RAM bank
        EI
        CALL    ClearScreen
        LD      HL,Title
        CALL    PrintString

MainLoop:
        LD      HL,Prompt
        CALL    PrintString
        CALL    ReadLine
        LD      HL,(CmdLen)
        LD      A,H
        OR      L
        JR      Z,MainLoop
        CALL    ParseCommand
        LD      IY,#5C3A         ; Mul/Div use IY; the ROM print routine needs it intact
        JR      C,CommandError
;        LD      HL,OkText
;       CALL    PrintString
        JR      MainLoop

CommandError:
        LD      HL,ErrorText
        CALL    PrintString
        JR      MainLoop

; -----------------------------------------------------------------------------
; Input line. RST 18 reads from current ROM input channel. ENTER = 13.
; Backspace (12 or 8) removes one character. CmdLen is a 16-bit count.
; ----------------------------------------------------------; -----------------------------------------------------------------------------
; Keyboard line editor.
; KEY-SCAN ($028E) returns raw key positions in DE.
; K-TEST ($031E) converts them to main key codes:
;   B=$FF no shift, B=$18 SYMBOL SHIFT, B=$27 CAPS SHIFT.
; Accepted: 0-9, A-F, SYMBOL SHIFT+K (+), SYMBOL SHIFT+L (=),
;           CAPS SHIFT+0 (DELETE/BACKSPACE), ENTER.
; -----------------------------------------------------------------------------
ReadLine:
        LD      HL,0
        LD      (CmdLen),HL
        LD      IX,CmdBuf

ReadKey:
        CALL    #028E
        JR      NZ,ReadKey        ; reject invalid multi-key combinations
        LD      A,E
        CP      #FF
        JR      Z,ReadKey         ; no key

        CALL    #031E             ; K-TEST: A=main key, B=shift, Carry=valid
        JP      NC,WaitKeyRelease
        LD      (KeyChar),A

;        LD      A,B
;        CP      #27
;        JR      Z,DecodeCapsKey
;        CP      #FF
;        JP      NZ,WaitKeyRelease

        ; No shift: ENTER or a hexadecimal digit/letter.
        LD      A,(KeyChar)
        CP      13
        JP      Z,ReadDone
        CALL    IsHexCharacter
        JR      C,DecodeSymbolKey
        JR      StoreCharacter

DecodeSymbolKey:
        LD      A,(KeyChar)
        CP      'K'
        JR      Z,MakePlus
        CP      'J'
        JR      Z,MakeMinus
        CP      'I'
        JR      Z,MakePiChar
        CP      'N'
        JR      Z,MakeDot
        CP      'L'
        JR      Z,MakeEquals
        CP	'G'
        JR	Z,MakeMultiply
        CP	'V'
        JR	Z,MakeDivision
        CP	'M'
        JR	Z,MakeRemainder
        CP	'P'
        JR	Z,DecodeCapsKey
        JR      WaitKeyRelease
MakePlus:
        LD      A,'+'
        JR      StoreCharacter
MakeEquals:
        LD      A,'='
        JR      StoreCharacter
MakeMinus:
        LD      A,'-'
        JR      StoreCharacter
MakePiChar:                         ; the P key is backspace, so key I types 'P'
        LD      A,'P'
        JR      StoreCharacter
MakeDot:
        LD      A,'.'
        JR      StoreCharacter
MakeMultiply:
	LD	A,'*'
	JR	StoreCharacter
MakeDivision:
	LD	A,'/'
	JR	StoreCharacter
MakeRemainder:
	LD	A,'M'
	JR	StoreCharacter
DecodeCapsKey:
        LD      A,(KeyChar)
;        CP      '0'
	CP	'P'
        JR      Z,BackspaceCharacter
        JR      WaitKeyRelease

StoreCharacter:
        LD      C,A
        LD      HL,(CmdLen)
        LD      DE,MAX_LINE
        OR      A
        SBC     HL,DE
        JR      NC,WaitKeyRelease
        LD      A,C
        LD      (IX+0),A
        INC     IX
        LD      HL,(CmdLen)
        INC     HL
        LD      (CmdLen),HL
        LD      A,C
        RST     #10               ; echo typed character
        JR      WaitKeyRelease

BackspaceCharacter:
        LD      HL,(CmdLen)
        LD      A,H
        OR      L
        JR      Z,WaitKeyRelease
        DEC     HL
        LD      (CmdLen),HL
        DEC     IX
        LD      A,8
        RST     #10
        LD      A,' '
        RST     #10
        LD      A,8
        RST     #10
        JR      WaitKeyRelease

ReadDone:
        CALL    WaitAllKeysUp       ; do not treat a held ENTER as another command
        XOR     A
        LD      (IX+0),A
        LD      A,13
        RST     #10
        RET

; Wait for every key, including a shift key, to be released.
WaitKeyRelease:
        CALL    WaitAllKeysUp
        JP      ReadKey

WaitAllKeysUp:
        CALL    #028E
        LD      A,D
        CP      #FF
        JR      NZ,WaitAllKeysUp
        LD      A,E
        CP      #FF
        JR      NZ,WaitAllKeysUp
        RET

; A=character. Carry set unless it is 0-9 or A-F.
IsHexCharacter:
        CP      '0'
        JR      C,NotHexCharacter
        CP      '9'+1
        JR      C,HexCharacterOK
        CP      'A'
        JR      C,NotHexCharacter
        CP      'F'+1
        JR      NC,NotHexCharacter
HexCharacterOK:
        OR      A
        RET
NotHexCharacter:
        SCF
        RET

; -----------------------------------------------------------------------------
; Parse command. Input: CmdBuf/CmdLen. Carry set on any syntax/range error.
; -----------------------------------------------------------------------------
ParseCommand:
        LD      HL,(CmdLen)
        LD      DE,2
        OR      A
        SBC     HL,DE
        JR      NC,CommandHasIndex
        SCF
        RET
CommandHasIndex:
        LD      HL,CmdBuf
        CALL    ParseVarIndex
        RET     C
        LD      (DestIndex),A
        ; A two-character command is a variable display; otherwise '=' is required.
        PUSH    HL                  ; preserve pointer to character after index
        LD      HL,(CmdLen)
        LD      DE,2
        OR      A
        SBC     HL,DE
        POP     HL
        JR      Z,BareVarLengthOK
        LD      A,(HL)
        CP      '='
        JR      Z,ParseAssignment
        CP      '.'
        JP      Z,ParseDecimal
        SCF
        RET
BareVarLengthOK:
        OR      A
        LD      A,(DestIndex)
        CALL    GetVarDataAddress
        LD      A,(HL)             ; length byte
        OR      A
        JR      NZ,PrintVariable
        LD      A,1
        LD      (HL),A             ; uninitialized slots display as zero
        INC     HL
        XOR     A
        LD      (HL),A
        DEC     HL
PrintVariable:
        PUSH    HL
        CALL    PrintSign
        POP     HL
        LD      B,(HL)
        INC     HL
        CALL    PrintBigHex
        LD      A,13
        RST     #10
        OR      A
        RET

ParseAssignment:
        INC     HL                  ; HL -> first RHS character
        LD      A,(HL)
        CP      'P'
        JP      Z,ParsePi
        ; RHS has an expression only in the exact form xx+yy.
        PUSH    HL
        LD      HL,(CmdLen)
        LD      DE,8
        OR      A
        SBC     HL,DE
        POP     HL
        JP      NZ,ParseLiteral
        ; Length is 8: two-char destination, '=', two-char source, '+','*','/' or 'M', two-char source.
        PUSH    HL
        INC     HL
        INC     HL
        LD      A,(HL)
        LD	(FuncSymb),A
        CP	'+'
        JR	Z,.parseAssig1
        CP	'*'
        JR	Z,.parseAssig1
        CP	'/'
        JR	Z,.parseAssig1
        CP      '-'
        JR      Z,.parseAssig1
        CP      'M'
.parseAssig1:
	POP     HL
        JP      NZ,ParseLiteral
        CALL    ParseAddExpression
        RET

; Parse expression at HL: var '+':'*':'/':'M' var. Destination index saved already.
ParseAddExpression:
        CALL    ParseVarIndex
        RET     C
        LD      (Src1Index),A
        LD      A,(HL)
        CP      '+'
        JR	Z,.parseAdd1
        CP	'*'
        JR	Z,.parseAdd1
        CP	'/'
        JR	Z,.parseAdd1
        CP      '-'
        JR      Z,.parseAdd1
        CP      'M'
.parseAdd1:
	SCF
        RET     NZ
        INC     HL
        CALL    ParseVarIndex
        RET     C
        LD      (Src2Index),A
        ; Require the complete command to have been consumed.
        PUSH    HL
        LD      HL,CmdBuf
        LD      DE,(CmdLen)
        ADD     HL,DE
        EX      DE,HL             ; DE = one byte past command
        POP     HL
        OR      A
        SBC     HL,DE
        JR      Z,AddExpressionLengthOK
        SCF
        RET
AddExpressionLengthOK:
        OR      A
        ; Get source 1 data address and length.
        LD      A,(Src1Index)
        CALL    GetVarDataAddress
        LD      A,(HL)
        OR      A
        JR      NZ,AddSrc1Ready
        INC     HL
        XOR     A
        LD      (HL),A
        DEC     HL
        LD      A,1
        LD      (HL),A
AddSrc1Ready:
        LD      A,(HL)
        LD      (Len1),A
        INC     HL
        LD      (Ptr1),HL
        ; Source 2.
        LD      A,(Src2Index)
        CALL    GetVarDataAddress
        LD      A,(HL)
        OR      A
        JR      NZ,AddSrc2Ready
        INC     HL
        XOR     A
        LD      (HL),A
        DEC     HL
        LD      A,1
        LD      (HL),A
AddSrc2Ready:
        LD      A,(HL)
        LD      (Len2),A
        INC     HL
        LD      (Ptr2),HL
        ; Add into a separate work buffer so destination may equal either source.
        ; Operand signs are read now, before the destination can be overwritten.
        LD      A,(Src1Index)
        CALL    GetVarSign
        LD      (Sign1),A
        LD      A,(Src2Index)
        CALL    GetVarSign
        LD      (Sign2),A
        XOR     A
        LD      (WorkSign),A
        LD      A,(FuncSymb)
        CP      '+'
        JR      NZ,.addsrc2_sub
        CALL    SignedAdd
        JR      .addscr2_ret
.addsrc2_sub:
        CP      '-'
        JR      NZ,.addsrc2_mul
        CALL    SignedSub
        JR      .addscr2_ret
.addsrc2_mul:
        CP      '*'
        JR      NZ,.addscr2_div
        CALL    SignedMul
        JR      .addscr2_ret
.addscr2_div:
        CP      '/'
        JR      NZ,.addscr2_mod
        CALL    SignedDiv
        JR      .addscr2_ret
.addscr2_mod:
        CP      'M'
        JR      NZ,.addscr2_ret
        CALL    SignedMod
.addscr2_ret:
        RET     C
        CALL    NormalizeWorkSign   ; a zero result is never negative
        CALL    SetDestSign
        ; Commit result to destination slot only after successful addition.
        LD      A,(DestIndex)
        CALL    GetVarDataAddress
        LD      A,(WorkLen)
        LD      (HL),A
        INC     HL
        LD      DE,WorkBuf
        LD      A,(WorkLen)
        LD      B,A
        LD      A,B
        OR      A
        JR      Z,CommitDone
CommitLoop:
        LD      A,(DE)
        LD      (HL),A
        INC     DE
        INC     HL
        DJNZ    CommitLoop
CommitDone:
        OR      A
        RET

; -----------------------------------------------------------------------------
; Parse a hexadecimal literal after '='. HL points to first digit.
; Digits are read from right to left and packed into little-endian bytes.
; Odd digit count is accepted (e.g. A -> 0A).
; -----------------------------------------------------------------------------
ParseLiteral:
        ; Optional sign before the digits: '-' = negative, '+' = positive.
        XOR     A
        LD      (WorkSign),A
        LD      A,(HL)
        CP      '-'
        JR      NZ,LiteralNotMinus
        LD      A,1
        LD      (WorkSign),A
        INC     HL
        JR      LiteralSignDone
LiteralNotMinus:
        CP      '+'
        JR      NZ,LiteralSignDone
        INC     HL
LiteralSignDone:
        ; Validate RHS length: 1..510 hex digits; calculate ceil(digits/2).
        PUSH    HL
        LD      DE,CmdBuf
        OR      A
        SBC     HL,DE
        ; HL = offset of first RHS character (normally 3).
        LD      (RhsOffset),HL
        LD      DE,(CmdLen)
        EX      DE,HL
        LD      DE,(RhsOffset)
        OR      A
        SBC     HL,DE             ; HL = digit count
        POP     DE                ; DE no longer needed
        LD      A,H
        OR      L
        JR      NZ,LiteralDigitsPresent
        SCF
        RET
LiteralDigitsPresent:
        ; digit count <= 510
        LD      DE,510
        OR      A
        SBC     HL,DE
        JR      C,LiteralCountOK
        JR      Z,LiteralCountOK
        SCF
        RET
LiteralCountOK:
        ; Recompute digits and byte count.
        LD      HL,(CmdLen)
        LD      DE,(RhsOffset)
        OR      A
        SBC     HL,DE
        LD      A,L
        AND     1
        LD      (OddDigits),A
        SRL     H
        RR      L
        LD      A,(OddDigits)
        OR      A
        JR      Z,LiteralBytesReady
        INC     HL
LiteralBytesReady:
        LD      A,H
        OR      A
        JR      Z,LiteralHighOK
        SCF
        RET
LiteralHighOK:
        LD      A,L
        OR      A
        JR      NZ,LiteralNonzero
        SCF
        RET
LiteralNonzero:
        OR      A
        LD      (LiteralByteCount),A
        ; Pointer to final digit: CmdBuf + CmdLen - 1.
        LD      HL,CmdBuf
        LD      DE,(CmdLen)
        ADD     HL,DE
        DEC     HL
        LD      (ScanPtr),HL
        LD      HL,WorkBuf
        LD      (WritePtr),HL
        LD      A,(LiteralByteCount)
        LD      B,A
LiteralByteLoop:
        ; Low nibble comes from rightmost remaining digit.
        LD      HL,(ScanPtr)
        LD      A,(HL)
        CALL    HexToNibble
        RET     C
        LD      C,A
        DEC     HL
        LD      A,(OddDigits)
        OR      A
        JR      Z,HaveHighDigit
        LD      A,B
        CP      1
        JR      NZ,HaveHighDigit
        ; Odd digit count: the final leftmost digit is a low nibble.
        LD      A,C
        JR      StoreLiteralByte
HaveHighDigit:
        LD      A,(HL)
        CALL    HexToNibble
        RET     C
        RLCA
        RLCA
        RLCA
        RLCA
        OR      C
        DEC	HL
StoreLiteralByte:
	LD      (ScanPtr),HL
        LD      HL,(WritePtr)
        LD      (HL),A
        INC     HL
        LD      (WritePtr),HL
        DJNZ    LiteralByteLoop
        ; Trim redundant most-significant zero bytes, retaining one byte.
        LD      A,(LiteralByteCount)
        LD      B,A
        LD      HL,(WritePtr)
        DEC     HL
TrimLiteral:
        LD      A,B
        CP      1
        JR      Z,LiteralTrimDone
        LD      A,(HL)
        OR      A
        JR      NZ,LiteralTrimDone
        DEC     HL
        DEC     B
        JR      TrimLiteral
LiteralTrimDone:
        LD      A,B
        LD      (DestLenTemp),A
        LD      (WorkLen),A
        CALL    NormalizeWorkSign   ; -0 becomes 0
        CALL    SetDestSign
        LD      A,(DestIndex)
        CALL    GetVarDataAddress
        LD      A,(DestLenTemp)
        LD      (HL),A
        INC     HL
        LD      DE,WorkBuf
        LD      A,(DestLenTemp)
        LD      B,A
CommitLiteralLoop:
        LD      A,(DE)
        LD      (HL),A
        INC     DE
        INC     HL
        DJNZ    CommitLiteralLoop
        OR      A
        RET

; -----------------------------------------------------------------------------
; Add Src1 + Src2 into WorkBuf. Returns Carry on 256-byte overflow.
; -----------------------------------------------------------------------------
AddToWork:
        LD      HL,(Ptr1)
        LD      DE,(Ptr2)
        LD      A,(Len1)
        LD      B,A
        LD      A,(Len2)
        LD      C,A
        LD      IX,WorkBuf
        XOR     A
        LD      (WorkLen),A
        OR      A                   ; clear carry
AddBothLoop:
        LD      A,B
        INC     A
        DEC     A
        JR      Z,AddLong2
        LD      A,C
        INC     A
        DEC     A
        JR      Z,AddLong1
        ; Z80 has no ADC A,(DE). Temporarily borrow D as the DE byte,
        ; preserving the pointer on the stack; LD/PUSH/POP keep Carry.
        LD      A,(DE)
        PUSH    DE
        LD      D,A
        LD      A,(HL)
        ADC     A,D
        POP     DE
        LD      (IX+0),A
        INC     HL
        INC     DE
        INC     IX
        LD      A,(WorkLen)
        INC     A
        LD      (WorkLen),A
        DEC     B
        DEC     C
        JR      AddBothLoop
AddLong2:
        LD      A,C
        INC     A
        DEC     A
        JR      Z,AddCarryOut
AddLong2Loop:
        LD      A,(DE)
        ADC     A,0
        LD      (IX+0),A
        INC     DE
        INC     IX
        LD      A,(WorkLen)
        INC     A
        LD      (WorkLen),A
        DEC     C
        JR      NZ,AddLong2Loop
        JR      AddCarryOut
AddLong1:
        LD      A,B
        INC     A
        DEC     A
        JR      Z,AddCarryOut
AddLong1Loop:
        LD      A,(HL)
        ADC     A,0
        LD      (IX+0),A
        INC     HL
        INC     IX
        LD      A,(WorkLen)
        INC     A
        LD      (WorkLen),A
        DEC     B
        JR      NZ,AddLong1Loop
AddCarryOut:
        LD      A,0
        ADC     A,0
        OR      A
        JR      Z,TrimWork
        LD      A,(WorkLen)
        CP      255
        JR      NC,AddOverflow
        LD      (IX+0),1
        INC     A
        LD      (WorkLen),A
TrimWork:
        ; Canonicalize length: remove high zero bytes, but keep at least one.
        LD      A,(WorkLen)
        OR      A
        JR      NZ,TrimWorkStart
        LD      A,1
        LD      (WorkLen),A
        XOR     A
        LD      (WorkBuf),A
        OR      A
        RET
TrimWorkStart:
        LD      B,A
        LD      HL,WorkBuf
        LD      D,0
        LD      E,B
        ADD     HL,DE
        DEC     HL
TrimWorkLoop:
        LD      A,B
        CP      1
        JR      Z,TrimWorkDone
        LD      A,(HL)
        OR      A
        JR      NZ,TrimWorkDone
        DEC     HL
        DEC     B
        JR      TrimWorkLoop
TrimWorkDone:
        LD      A,B
        LD      (WorkLen),A
        OR      A
        RET
AddOverflow:
        SCF
        RET

; ------------------------------------------------------------
; Mul8
;
; Умножение 8 бит × 8 бит.
;
; Вход:
;   A = множитель 1
;   E = множитель 2
;
; Выход:
;   HL = произведение
;
; Изменяет:
;   AF, BC, E, HL
; ------------------------------------------------------------

Mul8:

    ld c,a
    ld b,0

    ld hl,0

    ld a,8

.mul8_loop:

    srl e
    jr nc,.mul8_no_add

    add hl,bc

.mul8_no_add:

    sla c
    rl b

    dec a
    jr nz,.mul8_loop

    ret

; ------------------------------------------------------------
; MulToWork
;
; Умножение двух беззнаковых длинных чисел.
;
; Вход:
;   Ptr1    - адрес первого числа
;   Ptr2    - адрес второго числа
;   Len1    - длина первого числа
;   Len2    - длина второго числа
;
; Выход:
;   WorkBuf - младшие 255 байт результата
;   WorkLen - длина результата (0..255)
;   C       - 1 при переполнении, иначе 0
;
; Использует:
;   MulTmp  - промежуточный буфер 510 байт
;
; Изменяет:
;   AF, BC, DE, HL, IX, IY
; ------------------------------------------------------------

MulToWork:

    ; Обнуление промежуточного буфера

    ld hl,MulTmp
    ld bc,2*MAX_BYTES

.mul_clear:
    ld (hl),0
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,.mul_clear

    ; Проверка нулевых операндов

    ld a,(Len1)
    or a
    jr z,.mul_finish

    ld a,(Len2)
    or a
    jr z,.mul_finish

    ; Инициализация указателей

    ld hl,(Ptr1)
    ld (MulAPtr),hl

    ld hl,MulTmp
    ld (MulRowPtr),hl

    ld a,(Len1)
    ld (MulOuter),a

; ------------------------------------------------------------
; Внешний цикл: байты первого множителя
; ------------------------------------------------------------

.mul_outer:

    ; Читаем очередной байт первого числа

    ld hl,(MulAPtr)
    ld a,(hl)
    ld (MulA),a

    ; IX = начало текущей строки результата

    ld ix,(MulRowPtr)

    ; IY = начало второго множителя

    ld iy,(Ptr2)

    ld a,(Len2)
    ld (MulInner),a

; ------------------------------------------------------------
; Внутренний цикл: байты второго множителя
; ------------------------------------------------------------

.mul_inner:

    ; Умножаем MulA на очередной байт второго числа

    ld e,(iy+0)
    ld a,(MulA)

    call Mul8

    ; HL = 16-битное произведение
    ;
    ; Добавляем его в MulTmp[IX]

    ld a,(ix+0)
    add a,l
    ld (ix+0),a

    ld a,(ix+1)
    adc a,h
    ld (ix+1),a

    ; Распространение переноса

    jr nc,.mul_no_carry

    push ix

    inc ix
    inc ix

.mul_propagate:

    ld a,(ix+0)
    adc a,0
    ld (ix+0),a

    inc ix
    jr c,.mul_propagate

    pop ix

.mul_no_carry:

    ; Следующий байт второго множителя

    inc iy
    inc ix

    ld a,(MulInner)
    dec a
    ld (MulInner),a
    jr nz,.mul_inner

    ; Следующая строка результата

    ld hl,(MulRowPtr)
    inc hl
    ld (MulRowPtr),hl

    ; Следующий байт первого множителя

    ld hl,(MulAPtr)
    inc hl
    ld (MulAPtr),hl

    ld a,(MulOuter)
    dec a
    ld (MulOuter),a
    jr nz,.mul_outer

; ------------------------------------------------------------
; Формирование результата
; ------------------------------------------------------------

.mul_finish:

    ; Копируем младшие 255 байт в WorkBuf

    ld hl,MulTmp
    ld de,WorkBuf
    ld bc,MAX_BYTES

.mul_copy:

    ld a,(hl)
    ld (de),a

    inc hl
    inc de

    dec bc
    ld a,b
    or c
    jr nz,.mul_copy

    ; Проверяем старшие 255 байт.
    ; Если хотя бы один байт ненулевой - переполнение.

    ld hl,MulTmp+MAX_BYTES
    ld b,MAX_BYTES

    xor a

.mul_check_overflow:

    ld a,(hl)
    or a
    jr nz,.mul_overflow

    inc hl
    djnz .mul_check_overflow

    xor a
    ld (MulOverflow),a
    jr .mul_length

.mul_overflow:

    ld a,1
    ld (MulOverflow),a

; ------------------------------------------------------------
; Вычисление фактической длины результата
; ------------------------------------------------------------

.mul_length:

    ld hl,WorkBuf+MAX_BYTES-1
    ld b,MAX_BYTES

.mul_length_loop:

    ld a,(hl)
    or a
    jr nz,.mul_length_found

    dec hl
    djnz .mul_length_loop

    ; Результат равен нулю

    xor a
    ld (WorkLen),a
    jr .mul_return

.mul_length_found:

    ; B содержит длину результата

    ld a,b
    ld (WorkLen),a

; ------------------------------------------------------------
; Возврат флага переполнения
; ------------------------------------------------------------

.mul_return:

    ld a,(MulOverflow)
    or a
    ret z

    scf
    ret

; Частное A / B

DivToWork:
    xor a
    ld (DivMode),a
    jp DivCore


; Остаток A mod B

ModToWork:
    ld a,1
    ld (DivMode),a
    jp DivCore

; ------------------------------------------------------------
; DivCore
;
; Вход:
;   Ptr1  - делимое
;   Len1  - длина делимого
;   Ptr2  - делитель
;   Len2  - длина делителя
;
; DivMode:
;   0 = частное
;   1 = остаток
;
; Выход:
;   WorkBuf
;   WorkLen
;
;   C = 1 - деление на ноль
;   C = 0 - успешно
;
; Изменяет:
;   AF, BC, DE, HL, IX, IY
; ------------------------------------------------------------

DivCore:

    ; Обнуление WorkBuf

    ld hl,WorkBuf
    ld bc,MAX_BYTES

.div_clear_work:
    ld (hl),0
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,.div_clear_work

    xor a
    ld (WorkLen),a

    ; Обнуление DivRem

    ld hl,DivRem
    ld bc,MAX_BYTES+1

.div_clear_rem:
    ld (hl),0
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,.div_clear_rem

    ; Обнуление DivisorBuf

    ld hl,DivisorBuf
    ld bc,MAX_BYTES+1

.div_clear_divisor:
    ld (hl),0
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,.div_clear_divisor

    ; Копирование делителя

    ld a,(Len2)
    or a
    jp z,.div_zero_error

    ld b,a
    ld hl,(Ptr2)
    ld de,DivisorBuf

.div_copy_divisor:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz .div_copy_divisor

    ; Проверка делителя на ноль

    ld hl,DivisorBuf
    ld b,0
    xor a

.div_check_zero:
    or (hl)
    inc hl
    djnz .div_check_zero

    jp z,.div_zero_error

    ; Проверка нулевого делимого

    ld a,(Len1)
    or a
    jp z,.div_success

    ; --------------------------------------------------------
    ; Подготовка указателей
    ; --------------------------------------------------------

    ; DivSrcPtr = Ptr1 + Len1 - 1

    ld hl,(Ptr1)
    ld a,(Len1)
    ld e,a
    ld d,0
    add hl,de
    dec hl
    ld (DivSrcPtr),hl

    ; DivQPtr = WorkBuf + Len1 - 1

    ld hl,WorkBuf
    ld a,(Len1)
    ld e,a
    ld d,0
    add hl,de
    dec hl
    ld (DivQPtr),hl

    ld a,(Len1)
    ld (DivSrcLeft),a

; ------------------------------------------------------------
; Внешний цикл: обработка байтов делимого
; От старшего байта к младшему
; ------------------------------------------------------------

.div_outer:

    ; Читаем очередной байт делимого

    ld hl,(DivSrcPtr)
    ld a,(hl)
    ld (DivCurrent),a

    ; Начинаем со старшего бита

    ld a,#80
    ld (DivMask),a

    ld a,8
    ld (DivBitCount),a

; ------------------------------------------------------------
; Внутренний цикл: обработка битов
; ------------------------------------------------------------

.div_bit:

    ; --------------------------------------------------------
    ; Сдвигаем остаток влево на 1 бит
    ; Добавляем очередной бит делимого
    ; --------------------------------------------------------

    ld a,(DivCurrent)
    ld c,a

    ld a,(DivMask)
    and c

    jr z,.div_bit_zero

    scf
    jr .div_shift

.div_bit_zero:
    or a

.div_shift:

    ld ix,DivRem
    ld b,0

.div_shift_loop:

    rl (ix+0)
    inc ix
    djnz .div_shift_loop

    ; --------------------------------------------------------
    ; Сравнение DivRem с DivisorBuf
    ;
    ; Сравниваем от старшего байта к младшему
    ; --------------------------------------------------------

    ld ix,DivRem+MAX_BYTES
    ld iy,DivisorBuf+MAX_BYTES

    ld b,0

.div_compare:

    ld a,(ix+0)
    ld c,a

    ld a,(iy+0)
    cp c

    jr c,.div_rem_greater
    jr nz,.div_rem_less

    dec ix
    dec iy

    djnz .div_compare

    ; Равны: остаток >= делитель

    jr .div_subtract

.div_rem_less:

    ; Остаток меньше делителя.
    ; Бит частного остаётся равным нулю.

    jr .div_next_bit

.div_rem_greater:

    ; Остаток больше делителя.

; ------------------------------------------------------------
; Вычитание DivRem = DivRem - DivisorBuf
; ------------------------------------------------------------

.div_subtract:

    ld ix,DivRem
    ld iy,DivisorBuf

    ld b,0
    or a

.div_subtract_loop:

    ld c,(iy+0)
    ld a,(ix+0)
    sbc a,c
    ld (ix+0),a

    inc ix
    inc iy

    djnz .div_subtract_loop

    ; Устанавливаем очередной бит частного

    ld hl,(DivQPtr)

    ld a,(hl)
    ld c,a

    ld a,(DivMask)
    or c

    ld (hl),a

; ------------------------------------------------------------
; Следующий бит делимого
; ------------------------------------------------------------

.div_next_bit:

    ; Сдвигаем маску вправо

    ld a,(DivMask)
    srl a
    ld (DivMask),a

    ld a,(DivBitCount)
    dec a
    ld (DivBitCount),a

    jr nz,.div_bit

    ; Следующий байт делимого

    ld hl,(DivSrcPtr)
    dec hl
    ld (DivSrcPtr),hl

    ; Следующий байт частного

    ld hl,(DivQPtr)
    dec hl
    ld (DivQPtr),hl

    ld a,(DivSrcLeft)
    dec a
    ld (DivSrcLeft),a

    jp nz,.div_outer

; ------------------------------------------------------------
; Выбор результата
; ------------------------------------------------------------

.div_success:

    ld a,(DivMode)
    or a
    jr z,.div_trim

    ; Режим остатка:
    ; копируем DivRem в WorkBuf

    ld hl,DivRem
    ld de,WorkBuf
    ld bc,MAX_BYTES
    ldir

; ------------------------------------------------------------
; Удаление ведущих нулей
; ------------------------------------------------------------

.div_trim:

    ld hl,WorkBuf+MAX_BYTES-1
    ld b,MAX_BYTES

.div_trim_loop:

    ld a,(hl)
    or a
    jr nz,.div_trim_found

    dec hl
    djnz .div_trim_loop

    ; Результат равен нулю

    xor a
    ld (WorkLen),a
    ret

.div_trim_found:

    ld a,b
    ld (WorkLen),a

    or a
    ret

; ------------------------------------------------------------
; Деление на ноль
; ------------------------------------------------------------

.div_zero_error:

    xor a
    ld (WorkLen),a

    scf
    ret


; =============================================================================
; Signed arithmetic front-ends.
;
; Sign1/Sign2 hold the signs of Src1/Src2 (0 = positive, 1 = negative); the
; magnitudes are at Ptr1/Len1 and Ptr2/Len2. Each routine returns the result
; magnitude in WorkBuf/WorkLen and its sign in WorkSign. Carry = error.
;
; The remainder is never negative: 0 <= (a M b) < |b|, and the quotient is
; rounded to match, so  a = (a/b)*b + (a M b)  always holds (Euclidean
; division; for b > 0 this is exactly Python's // and %).
; =============================================================================
SignedSub:
        LD      A,(Sign2)
        XOR     1
        LD      (Sign2),A           ; a - b = a + (-b); falls through
SignedAdd:
        LD      A,(Sign1)
        LD      B,A
        LD      A,(Sign2)
        CP      B
        JR      NZ,SignedAddDiff
        LD      A,B                 ; same sign: add magnitudes, keep the sign
        LD      (WorkSign),A
        JP      AddToWork
SignedAddDiff:
        CALL    SubMagToWork        ; WorkBuf = |a|-|b|, Carry = (|a| < |b|)
        JR      C,SignedAddSwap
        LD      A,(Sign1)           ; |a| >= |b|: result takes the sign of a
        LD      (WorkSign),A
        JP      TrimWork
SignedAddSwap:
        CALL    NegateWork          ; WorkBuf = |b|-|a|
        LD      A,(Sign2)           ; |a| < |b|: result takes the sign of b
        LD      (WorkSign),A
        JP      TrimWork

SignedMul:
        LD      A,(Sign1)
        LD      B,A
        LD      A,(Sign2)
        XOR     B
        LD      (WorkSign),A
        JP      MulToWork

SignedDiv:
        LD      A,(Sign1)
        LD      B,A
        LD      A,(Sign2)
        XOR     B
        LD      (WorkSign),A
        CALL    DivToWork           ; truncated: |a| = Q*|b| + R
        RET     C
        LD      A,(Sign1)
        OR      A
        RET     Z                   ; a >= 0: truncated == floored
        LD      HL,DivRem           ; a < 0: if R <> 0 then |q| = Q + 1
        LD      B,MAX_BYTES
DivQFixScan:
        LD      A,(HL)
        OR      A
        JR      NZ,DivQFixInc
        INC     HL
        DJNZ    DivQFixScan
        OR      A
        RET                         ; R = 0: exact, nothing to fix
DivQFixInc:
        LD      HL,WorkBuf          ; WorkBuf is zero beyond the quotient
        LD      B,MAX_BYTES
DivQIncLoop:
        INC     (HL)
        JR      NZ,TrimWorkFull
        INC     HL
        DJNZ    DivQIncLoop
        JR      TrimWorkFull

; Remainder is always >= 0 (0 <= r < |b|), so a = q*b + r holds with the
; quotient from SignedDiv (q is rounded so that this is true).
SignedMod:
        XOR     A
        LD      (WorkSign),A
        CALL    ModToWork           ; truncated remainder R (magnitude)
        RET     C
        LD      A,(Sign1)
        OR      A
        RET     Z                   ; a >= 0: R is already the answer
        LD      HL,WorkBuf          ; a < 0: if R <> 0 then r = |b| - R
        LD      B,MAX_BYTES
ModFixScan:
        LD      A,(HL)
        OR      A
        JR      NZ,ModFixSub
        INC     HL
        DJNZ    ModFixScan
        OR      A
        RET
ModFixSub:
        LD      HL,WorkBuf
        LD      DE,DivisorBuf       ; still holds |b|
        LD      B,MAX_BYTES
        OR      A
ModFixLoop:
        LD      A,(DE)
        SBC     A,(HL)
        LD      (HL),A
        INC     HL
        INC     DE
        DJNZ    ModFixLoop
        ; fall through

; WorkLen = number of significant bytes of WorkBuf (0 if zero). Carry clear.
TrimWorkFull:
        LD      HL,WorkBuf+MAX_BYTES-1
        LD      B,MAX_BYTES
TrimFullLoop:
        LD      A,(HL)
        OR      A
        JR      NZ,TrimFullFound
        DEC     HL
        DJNZ    TrimFullLoop
        XOR     A
        LD      (WorkLen),A
        RET
TrimFullFound:
        LD      A,B
        LD      (WorkLen),A
        OR      A
        RET

; -----------------------------------------------------------------------------
; SubMagToWork: WorkBuf = |Src1| - |Src2| over L = max(Len1,Len2) bytes (the
; shorter operand is zero-extended). WorkLen = L (not trimmed).
; Carry set if |Src1| < |Src2|; WorkBuf then holds 256^L - (|Src2|-|Src1|).
; Carry is the running borrow, so only flag-neutral instructions (INC/DEC r,
; LD, EX DE,HL, 16-bit INC) are used between the SBCs.
; -----------------------------------------------------------------------------
SubMagToWork:
        LD      HL,(Ptr1)
        LD      DE,(Ptr2)
        LD      A,(Len1)
        LD      B,A
        LD      A,(Len2)
        LD      C,A
        LD      IX,WorkBuf
        XOR     A
        LD      (WorkLen),A         ; also clears the borrow
SubLoop:
        INC     B
        DEC     B
        JR      Z,SubNoSrc1
        INC     C
        DEC     C
        JR      Z,SubNoSrc2
        EX      DE,HL               ; HL -> Src2, DE -> Src1
        LD      A,(DE)
        SBC     A,(HL)
        EX      DE,HL
        INC     HL
        INC     DE
        DEC     B
        DEC     C
        JR      SubStore
SubNoSrc2:                          ; only Src1 has data left: a - 0 - borrow
        LD      A,(HL)
        SBC     A,0
        INC     HL
        DEC     B
        JR      SubStore
SubNoSrc1:
        INC     C
        DEC     C
        RET     Z                   ; both exhausted: Carry = final borrow
        LD      A,0                 ; only Src2 has data left: 0 - b - borrow
        EX      DE,HL
        SBC     A,(HL)
        EX      DE,HL
        INC     DE
        DEC     C
SubStore:
        LD      (IX+0),A
        INC     IX
        LD      A,(WorkLen)
        INC     A
        LD      (WorkLen),A
        JR      SubLoop

; -----------------------------------------------------------------------------
; NegateWork: WorkBuf = 0 - WorkBuf (two's complement) over WorkLen bytes.
; -----------------------------------------------------------------------------
NegateWork:
        LD      A,(WorkLen)
        OR      A
        RET     Z
        LD      B,A
        LD      HL,WorkBuf
        XOR     A                   ; clear Carry
NegateLoop:
        LD      A,0
        SBC     A,(HL)
        LD      (HL),A
        INC     HL
        DJNZ    NegateLoop
        RET

; -----------------------------------------------------------------------------
; NormalizeWorkSign: WorkSign = 0 if the WorkBuf magnitude is zero.
; (Does not depend on the result being trimmed.)
; -----------------------------------------------------------------------------
NormalizeWorkSign:
        LD      A,(WorkLen)
        OR      A
        JR      Z,NormalizeZero
        LD      B,A
        LD      HL,WorkBuf
NormalizeLoop:
        LD      A,(HL)
        OR      A
        RET     NZ                  ; non-zero magnitude: keep the sign
        INC     HL
        DJNZ    NormalizeLoop
NormalizeZero:
        XOR     A
        LD      (WorkSign),A
        RET

; A = variable index -> A = its sign. Clobbers DE, HL.
GetVarSign:
        LD      E,A
        LD      D,0
        LD      HL,NumberSigns
        ADD     HL,DE
        LD      A,(HL)
        RET

; NumberSigns[DestIndex] = WorkSign. Clobbers A, DE, HL.
SetDestSign:
        LD      A,(DestIndex)
        LD      E,A
        LD      D,0
        LD      HL,NumberSigns
        ADD     HL,DE
        LD      A,(WorkSign)
        LD      (HL),A
        RET

; Print '-' if variable DestIndex is negative. Clobbers A, DE, HL.
PrintSign:
        LD      A,(DestIndex)
        LD      E,A
        LD      D,0
        LD      HL,NumberSigns
        ADD     HL,DE
        LD      A,(HL)
        OR      A
        RET     Z
        LD      A,'-'
        RST     #10
        RET

; =============================================================================
; PI by Machin's formula   pi = 16*arctan(1/5) - 4*arctan(1/239)
;
; arctan(1/x) = 1/x - 1/(3x^3) + 1/(5x^5) - ...   evaluated in fixed point
; (little-endian, F fractional bytes, one integer byte on top). Every term needs
; only "big number / 16-bit number" and an add or subtract, so each term costs
; O(length) and the series shrink as they go (leading zero bytes are skipped).
;
; Working buffers:  S = WorkBuf (sum), P = MulTmp (x^-(2k+1)), T = MulTmp+255.
; PI_GUARD extra low bytes absorb the truncation errors (a few thousand ulp).
; Result: variable DestIndex = floor(pi * 256^n), n = PiBytes (1..PI_MAXFRAC).
; Only IX is used (IY must stay $5C3A for the ROM interrupt/print routines).
; =============================================================================
ParsePi:                            ; HL -> 'P' ; command is  DD=P  or  DD=Pn  or  DD=Pnn
        INC     HL
        LD      DE,(CmdLen)
        LD      A,D
        OR      A
        JR      NZ,PiBad
        LD      A,E
        SUB     4                   ; characters after "DD=P"
        JR      Z,PiDefault
        CP      1
        JR      Z,PiOneDigit
        CP      2
        JR      NZ,PiBad
        LD      A,(HL)
        CALL    HexToNibble
        RET     C
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      D,A
        INC     HL
        LD      A,(HL)
        CALL    HexToNibble
        RET     C
        OR      D
        JR      PiHaveCount
PiOneDigit:
        LD      A,(HL)
        CALL    HexToNibble
        RET     C
        JR      PiHaveCount
PiDefault:
        LD      A,PI_MAXFRAC
PiHaveCount:
        OR      A
        JR      Z,PiBad
        CP      PI_MAXFRAC+1
        JR      NC,PiBad
        LD      (PiBytes),A
        JP      ComputePi
PiBad:
        SCF
        RET

ComputePi:
        LD      A,(PiBytes)
        ADD     A,PI_GUARD
        LD      (PiF),A             ; F = fractional bytes used internally (<= 254)
        INC     A
        LD      (PiLen),A           ; F+1 bytes including the integer byte
        LD      HL,WorkBuf          ; S = 0
        LD      DE,WorkBuf+1
        LD      BC,MAX_BYTES-1
        LD      (HL),0
        LDIR
        LD      A,1
        LD      (PiAddFlag),A       ; first term of 16*arctan(1/5) is added
        LD      A,16
        LD      BC,5
        LD      DE,25
        CALL    PiArctan
        XOR     A
        LD      (PiAddFlag),A       ; first term of 4*arctan(1/239) is subtracted
        LD      A,4
        LD      BC,239
        LD      DE,57121
        CALL    PiArctan
        ; Result = S without the guard bytes -> variable (length n+1, positive).
        LD      A,(DestIndex)
        CALL    GetVarDataAddress
        LD      A,(PiBytes)
        INC     A
        LD      (HL),A
        INC     HL
        EX      DE,HL               ; DE -> variable data
        LD      C,A
        LD      B,0
        LD      HL,WorkBuf+PI_GUARD
        LDIR
        XOR     A
        LD      (WorkSign),A
        CALL    SetDestSign
        OR      A
        RET

; S +/-= mult * arctan(1/x).  A = mult, BC = x, DE = x*x, PiAddFlag = sign of first term.
PiArctan:
        LD      (PiX2),DE
        PUSH    BC
        PUSH    AF
        LD      HL,MulTmp           ; P = 0
        LD      DE,MulTmp+1
        LD      BC,MAX_BYTES-1
        LD      (HL),0
        LDIR
        LD      A,(PiF)
        LD      E,A
        LD      D,0
        LD      HL,MulTmp
        ADD     HL,DE               ; HL -> integer byte of P
        POP     AF
        LD      (HL),A              ; P = mult
        LD      A,(PiLen)
        LD      (PiCnt),A
        LD      HL,MulTmp
        POP     DE                  ; DE = x
        CALL    PiDivBuf            ; P = mult / x
        LD      HL,1
        LD      (PiOdd),HL
        CALL    PiTrimP
PiTerm:
        LD      A,(PiCnt)
        OR      A
        RET     Z                   ; P has become zero: series finished
        LD      C,A
        LD      B,0
        LD      HL,MulTmp
        LD      DE,MulTmp+MAX_BYTES
        LDIR                        ; T = P
        LD      HL,MulTmp+MAX_BYTES
        LD      DE,(PiOdd)
        CALL    PiDivBuf            ; T = P / (2k+1)
        CALL    PiAddSub            ; S +/-= T
        LD      A,(PiAddFlag)
        XOR     1
        LD      (PiAddFlag),A
        LD      HL,MulTmp
        LD      DE,(PiX2)
        CALL    PiDivBuf            ; P = P / x^2
        CALL    PiTrimP
        LD      HL,(PiOdd)
        INC     HL
        INC     HL
        LD      (PiOdd),HL
        JR      PiTerm

; Divide the PiCnt-byte little-endian number at (HL) by DE (1..65535), in place,
; truncating. Works from the most significant byte down; 8 DIVSTEPs per byte.
PiDivBuf:
        LD      A,(PiCnt)
        LD      C,A
        LD      B,0
        ADD     HL,BC
        DEC     HL
        PUSH    HL
        POP     IX                  ; IX -> most significant byte
        LD      B,C                 ; B = byte count (1..255)
        LD      HL,0                ; running remainder
PiDivLoop:
        LD      A,(IX+0)
        DUP     8
        DIVSTEP
        EDUP
        LD      (IX+0),A
        DEC     IX
        DEC     B
        JP      NZ,PiDivLoop
        RET

; PiCnt = number of significant bytes of P (0 if P = 0).
PiTrimP:
        LD      A,(PiCnt)
        OR      A
        RET     Z
        LD      B,A
        LD      E,A
        LD      D,0
        LD      HL,MulTmp
        ADD     HL,DE
        DEC     HL                  ; HL -> P[PiCnt-1]
PiTrimLoop:
        LD      A,(HL)
        OR      A
        JR      NZ,PiTrimDone
        DEC     HL
        DJNZ    PiTrimLoop
PiTrimDone:
        LD      A,B
        LD      (PiCnt),A
        RET

; S = S + T (PiAddFlag <> 0) or S - T (PiAddFlag = 0) over the PiCnt low bytes of T,
; then the carry/borrow is propagated up through the rest of S.
PiAddSub:
        LD      A,(PiCnt)
        LD      B,A
        LD      C,A
        LD      HL,WorkBuf
        LD      DE,MulTmp+MAX_BYTES
        LD      A,(PiAddFlag)
        OR      A                   ; also clears Carry
        JR      Z,PiSubT
PiAddLoop:
        LD      A,(DE)
        ADC     A,(HL)
        LD      (HL),A
        INC     HL
        INC     DE
        DJNZ    PiAddLoop
        RET     NC
        LD      A,(PiLen)
        SUB     C
        RET     Z
        LD      B,A
PiAddCarry:
        INC     (HL)
        RET     NZ
        INC     HL
        DJNZ    PiAddCarry
        RET
PiSubT:
        EX      DE,HL               ; HL -> T, DE -> S
PiSubLoop:
        LD      A,(DE)
        SBC     A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    PiSubLoop
        RET     NC
        LD      A,(PiLen)
        SUB     C
        RET     Z
        LD      B,A
PiSubBorrow:
        LD      A,(DE)
        SUB     1
        LD      (DE),A
        INC     DE
        RET     NC
        DJNZ    PiSubBorrow
        RET

; =============================================================================
; "DD." - print variable DD in decimal as a fixed-point number: the top byte is
; the integer part, the bytes below it are the fraction (this is how DD=P stores
; pi). The fraction is multiplied by 10 repeatedly; the carry out is the next digit.
; Digits printed = 2.406*F - 4  (the last few digits of the binary value are
; not trustworthy, so they are not shown).
; =============================================================================
ParseDecimal:
        LD      HL,(CmdLen)
        LD      DE,3
        OR      A
        SBC     HL,DE
        JR      Z,PrintDecimalVar
        SCF
        RET

PrintDecimalVar:
        CALL    PrintSign
        LD      A,(DestIndex)
        CALL    GetVarDataAddress
        LD      A,(HL)              ; length
        OR      A
        JR      NZ,DecHaveLen
        LD      A,'0'               ; uninitialised slot = 0
        RST     #10
        JR      DecNewLine
DecHaveLen:
        DEC     A
        LD      (DecF),A            ; F = number of fraction bytes
        INC     HL                  ; HL -> byte 0
        OR      A
        JR      Z,DecCopied
        LD      C,A
        LD      B,0
        LD      DE,WorkBuf
        LDIR                        ; fraction -> WorkBuf; HL ends at the integer byte
DecCopied:
        LD      A,(HL)              ; integer part
        CALL    PrintByteDec
        CALL    DecDigitCount       ; HL = number of fraction digits to print
        LD      A,H
        OR      L
        JR      Z,DecNewLine
        LD      (DecCount),HL
        LD      A,'.'
        RST     #10
DecDigitLoop:
        CALL    DecMul10
        ADD     A,'0'
        RST     #10
        LD      HL,(DecCount)
        DEC     HL
        LD      (DecCount),HL
        LD      A,H
        OR      L
        JR      NZ,DecDigitLoop
DecNewLine:
        LD      A,13
        RST     #10
        OR      A
        RET

; WorkBuf[0..F-1] *= 10 ; returns the carry out (0..9) in A.
DecMul10:
        LD      A,(DecF)
        LD      B,A
        OR      A
        RET     Z
        LD      IX,WorkBuf
        LD      C,0
DecMulLoop:
        LD      L,(IX+0)
        LD      H,0
        ADD     HL,HL               ; 2b
        LD      D,H
        LD      E,L
        ADD     HL,HL               ; 4b
        ADD     HL,HL               ; 8b
        ADD     HL,DE               ; 10b
        LD      E,C
        LD      D,0
        ADD     HL,DE               ; + carry from the byte below
        LD      (IX+0),L
        LD      C,H                 ; carry out (0..9)
        INC     IX
        DJNZ    DecMulLoop
        LD      A,C
        RET

; HL = max(0, 2F + (13F >> 5) - 4)  with F = DecF
DecDigitCount:
        LD      A,(DecF)
        LD      E,A
        LD      D,0
        LD      H,D
        LD      L,E
        ADD     HL,HL
        ADD     HL,HL               ; 4F
        LD      B,H
        LD      C,L
        ADD     HL,HL               ; 8F
        ADD     HL,BC               ; 12F
        ADD     HL,DE               ; 13F
        LD      B,5
DecShr:
        SRL     H
        RR      L
        DJNZ    DecShr
        ADD     HL,DE
        ADD     HL,DE               ; + 2F
        LD      DE,4
        OR      A
        SBC     HL,DE
        RET     NC
        LD      HL,0
        RET

; Print A (0..255) in decimal without leading zeros.
PrintByteDec:
        LD      (DecTmp),A
        XOR     A
        LD      (DecStarted),A
        LD      E,100
        CALL    PbdDigit
        LD      E,10
        CALL    PbdDigit
        LD      A,(DecTmp)
        ADD     A,'0'
        RST     #10
        RET
PbdDigit:
        LD      A,(DecTmp)
        LD      D,0
PbdSub:
        CP      E
        JR      C,PbdGot
        SUB     E
        INC     D
        JR      PbdSub
PbdGot:
        LD      (DecTmp),A          ; remainder
        LD      A,(DecStarted)
        OR      D
        RET     Z                   ; leading zero: not printed
        LD      A,1
        LD      (DecStarted),A
        LD      A,D
        ADD     A,'0'
        RST     #10
        RET

; -----------------------------------------------------------------------------
; Parse exactly two hex digits at HL as a variable index 0..63.
; Returns A=index, HL advanced by 2, Carry on error.
; -----------------------------------------------------------------------------
ParseVarIndex:
        LD      A,(HL)
        CALL    HexToNibble
        RET     C
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      D,A
        INC     HL
        LD      A,(HL)
        CALL    HexToNibble
        RET     C
        OR      D
        CP      64
        JR      C,VarIndexOK
        SCF
        RET
VarIndexOK:
        INC     HL
        OR      A
        RET

; A=ASCII hex digit. Returns nibble in A, Carry if invalid.
HexToNibble:
        CP      '0'
        JR      C,HexBad
        CP      '9'+1
        JR      C,HexNumeric
        CP      'A'
        JR      C,HexTryLower
        CP      'F'+1
        JR      C,HexUpper
HexTryLower:
        CP      'a'
        JR      C,HexBad
        CP      'f'+1
        JR      NC,HexBad
        SUB     'a'-10
        OR      A
        RET
HexUpper:
        SUB     'A'-10
        OR      A
        RET
HexNumeric:
        SUB     '0'
        OR      A
        RET
HexBad:
        SCF
        RET

; A=variable index, returns HL=slot base (length byte).
GetVarDataAddress:
        ADD     A,#86
        LD      H,A
        LD      L,0
        RET

; -----------------------------------------------------------------------------
; PrintBigHex: HL points to little-endian data, B=length (1..255).
; Prints uppercase hexadecimal without spaces.
; -----------------------------------------------------------------------------
PrintBigHex:
        PUSH    HL
        LD      E,B
        LD      D,0
        ADD     HL,DE
        DEC     HL
        EX      (SP),HL
        POP     DE
PrintBigLoop:
        LD      A,(DE)
        PUSH    BC
        PUSH    DE
        CALL    PrintHexByte
        POP     DE
        POP     BC
        DEC     DE
        DJNZ    PrintBigLoop
        RET

PrintHexByte:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PrintNibble
        POP     AF
PrintNibble:
        AND     #0F
        CP      10
        JR      C,PrintDigit
        ADD     A,7
PrintDigit:
        ADD     A,'0'
        RST     #10
        RET

PrintString:
        LD      A,(HL)
        OR      A
        RET     Z
        RST     #10
        INC     HL
        JR      PrintString

ClearScreen:
        CALL	3503
        RET

; -----------------------------------------------------------------------------
; Text and working storage. Keep all program/data above C600; variable slots
; are a separate fixed area at 8600-C5FF.
; -----------------------------------------------------------------------------
Title:          DB "ZX BIG INTEGER CALCULATOR",13,0
Prompt:         DB "> ",0
OkText:         DB "OK - COMMAND ACCEPTED",13,0
ErrorText:      DB "ERROR - INVALID COMMAND",13,0

CmdLen:         DW 0
KeyChar:        DB 0
RhsOffset:      DW 0
ScanPtr:        DW 0
WritePtr:       DW 0
Ptr1:           DW 0	; Addr1
Ptr2:           DW 0	; Addr2
FuncSymb:	DB 0	; function '+','*','/'
DestIndex:      DB 0
Src1Index:      DB 0
Src2Index:      DB 0
Len1:           DB 0
Len2:           DB 0
WorkLen:        DB 0
OddDigits:      DB 0
LiteralByteCount: DB 0
DestLenTemp:    DB 0
Sign1:          DB 0	; sign of Src1 (0 +, 1 -)
Sign2:          DB 0	; sign of Src2
WorkSign:       DB 0	; sign of the result in WorkBuf
NumberSigns:	DS VAR_COUNT,0    ; initially all numbers >0, 1 for <0 numbers
CmdBuf:         DS MAX_LINE+1,0
WorkBuf:        DS MAX_BYTES,0
MulTmp:         DS 2*MAX_BYTES,0
MulAPtr:        DW 0
MulRowPtr:      DW 0
MulA:           DB 0
MulOuter:       DB 0
MulInner:       DB 0
MulOverflow:    DB 0
DivRem:         DS MAX_BYTES+1,0
DivisorBuf:     DS MAX_BYTES+1,0

DivMode:        DB 0
DivSrcPtr:      DW 0
DivQPtr:        DW 0
DivSrcLeft:     DB 0
DivCurrent:     DB 0
DivMask:        DB 0
DivBitCount:    DB 0
PiBytes:        DB 0                ; requested fractional bytes
PiF:            DB 0                ; fractional bytes used internally (PiBytes + PI_GUARD)
PiLen:          DB 0                ; PiF + 1
PiCnt:          DB 0                ; significant bytes of P
PiAddFlag:      DB 0                ; 1 = add the next term, 0 = subtract it
PiOdd:          DW 0                ; 2k+1
PiX2:           DW 0                ; x*x
DecF:           DB 0
DecTmp:         DB 0
DecStarted:     DB 0
DecCount:       DW 0
        SAVESNA "zxcalc.sna",Start
        SAVEBIN "zxcalc.bin",Start,$-Start
