; -----------------------------------------------------------------------------
; ZX BIG INTEGER CALCULATOR for ZX Spectrum 128
; SjASMPlus source. Variables: $8600-$C5FF (64 slots x 256 bytes)
;
; Slot layout: +0 = byte length (1..255), +1..+255 = unsigned value,
; little-endian. Input/output notation is most-significant byte first.
;
; Commands:
;   2B=23049209348BCD32423    assign hexadecimal constant
;   00=01+2B                 add two variables
;   00                       print a variable
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
        JR      C,CommandError
        LD      HL,OkText
        CALL    PrintString
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

        LD      A,B
        CP      #27
        JR      Z,DecodeCapsKey
        CP      #FF
        JP      NZ,WaitKeyRelease

        ; No shift: ENTER or a hexadecimal digit/letter.
        LD      A,(KeyChar)
        CP      13
        JR      Z,ReadDone
        CALL    IsHexCharacter
        JR      C,DecodeSymbolKey
        JR      StoreCharacter

DecodeSymbolKey:
        LD      A,(KeyChar)
        CP      'K'
        JR      Z,MakePlus
        CP      'L'
        JR      Z,MakeEquals
        CP	'G'
        JR	Z,MakeMultiply
        CP	'V'
        JR	Z,MakeDivision
        CP	'M'
        JR	Z,MakeRemainder
        JR      WaitKeyRelease
MakePlus:
        LD      A,'+'
        JR      StoreCharacter
MakeEquals:
        LD      A,'='
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
        CP      '0'
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
        LD      B,(HL)
        INC     HL
        CALL    PrintBigHex
        LD      A,13
        RST     #10
        OR      A
        RET

ParseAssignment:
        INC     HL                  ; HL -> first RHS character
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
        CP	'M'
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
        CP	'M'
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
        LD	A,(FuncSymb)
	CP	'+'
	JR	NZ,.addsrc2_mul
	CALL	AddToWork
	JR	.addscr2_ret
.addsrc2_mul:
	CP	'*'
	JR	NZ,.addscr2_div
	CALL	MulToWork
	JR	.addscr2_ret
.addscr2_div:
	CP	'/'
	JR	NZ,.addscr2_mod
	CALL	DivToWork
	JR	.addscr2_ret
.addscr2_mod:
	CP	'M'
	JR	NZ,.addscr2_ret
	CALL	ModToWork
.addscr2_ret:
        RET     C
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
        SAVESNA "zxcalc.sna",Start
