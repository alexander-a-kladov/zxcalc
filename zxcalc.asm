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
; Input is read through the Spectrum ROM input stream (RST 18), so the ROM
; keyboard/editor handles the physical keyboard and ENTER. The program does
; not scan the keyboard matrix itself.
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
        ; Keep interrupts enabled during normal ROM keyboard input.
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
; -----------------------------------------------------------------------------
ReadLine:
        LD      HL,0
        LD      (CmdLen),HL
        LD      IX,CmdBuf
ReadLoop:
        RST     #18
        CP      13
        JR      Z,ReadDone
        CP      12
        JR      Z,ReadBackspace
        CP      8
        JR      Z,ReadBackspace
        LD      HL,(CmdLen)
        LD      DE,MAX_LINE
        OR      A
        SBC     HL,DE
        JR      NC,ReadLoop
        LD      (IX+0),A
        INC     IX
        LD      HL,(CmdLen)
        INC     HL
        LD      (CmdLen),HL
        JR      ReadLoop
ReadBackspace:
        LD      HL,(CmdLen)
        LD      A,H
        OR      L
        JR      Z,ReadLoop
        DEC     HL
        LD      (CmdLen),HL
        DEC     IX
        JR      ReadLoop
ReadDone:
        XOR     A
        LD      (IX+0),A
        LD      A,13
        RST     #10
        LD      A,10
        RST     #10
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
        LD      A,10
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
        ; Length is 8: two-char destination, '=', two-char source, '+', two-char source.
        PUSH    HL
        INC     HL
        INC     HL
        LD      A,(HL)
        CP      '+'
        POP     HL
        JR      NZ,ParseLiteral
        CALL    ParseAddExpression
        RET

; Parse expression at HL: var '+' var. Destination index saved already.
ParseAddExpression:
        CALL    ParseVarIndex
        RET     C
        LD      (Src1Index),A
        LD      A,(HL)
        CP      '+'
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
        CALL    AddToWork
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
StoreLiteralByte:
        LD      HL,(WritePtr)
        LD      (HL),A
        INC     HL
        LD      (WritePtr),HL
        LD      HL,(ScanPtr)
        DEC     HL
        LD      (ScanPtr),HL
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
        LD      A,12
        RST     #10
        RET

; -----------------------------------------------------------------------------
; Text and working storage. Keep all program/data above C600; variable slots
; are a separate fixed area at 8600-C5FF.
; -----------------------------------------------------------------------------
Title:          DB "ZX BIG INTEGER CALCULATOR",13,10,0
Prompt:         DB "> ",0
OkText:         DB "OK",13,10,0
ErrorText:      DB "ERROR",13,10,0

CmdLen:         DW 0
RhsOffset:      DW 0
ScanPtr:        DW 0
WritePtr:       DW 0
Ptr1:           DW 0
Ptr2:           DW 0
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

        SAVESNA "zxcalc.sna",Start
