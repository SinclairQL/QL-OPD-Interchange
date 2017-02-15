*******************************************************************
**                          OPDCOPY3                             **
**                          ~~~~~~~~                             **
**      These routines handle the translation of differences     **
**      between OPD and QL file contents.                        **
**                                                               **
**                                      LAST AMENDED: 17/09/86   **
*******************************************************************

*       Externals in OPDCOPY3 for use by other modules

        xdef    FILE_CONVERT,FILE_CONVERT_COPY
        xdef    RECONFIGURE
        xdef    ql_to_opd_table

*       Externals from OPDCOPY1

        xref    SET_DESTINATION_TYPE
        xref    targetname,selmsg,selyn,devicetable
        xref    filemsg,fileheader,filestart,fileend

*       Externals from OPDCOPY2

        xref    CONSOLE_GREEN_MESSAGE,CONSOLE_YESNO_MESSAGE
        xref    backflg,charflag

*       Externals from OPDCOPY4

        xref    NOT_COPIED
        
*       Externals from OPDSUBS

        xref    PICK_PARAMETER
        xref    CONSOLE_MESSAGE,CHANNEL_MESSAGE
        xref    SCREEN_NEWLINE,SCREEN_MESSAGE
        xref    CONSOLE_INK,ACTION_INK,SCREEN_INK,CHANNEL_INK
        xref    CLEAR_CONSOLE_LINE
        xref    BEEP1,BEEP2,BEEP3

*       Externals from OPDINIT

        xref    scrid,actid,conid
        xref    desttyp,srctyp

*NOLIST
$INCLUDE        Flp1_asmlib_QL_header
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_errors
*LIST
*PAGE           FILE DATA CONVERSION
*----------------------------------------------------------------------
*       These routines handle the conversion of certain grapics
*       characters that are different on the QL and OPD.  
*----------------------------------------------------------------------

FILE_CONVERT_COPY
        movem.l d1-d2/a0-a3,-(SP)
        move.l  filestart,a0            ; start of file area
        lea     [8](a0),a0              ; convert flag (then header)
        lea     [64+2](a0),a1           ; data area address
*       NOTE. length already in D1
        bra.s   file_convert_join

FILE_CONVERT
        movem.l d1-d2/a0-a3,-(SP)
        move.l  filestart,a0            ; start of file area
        lea     [8](a0),a0              ; convert flag (then header)
        lea     [64+2](a0),a1           ; data area
        move.l  2(a0),d1                ; get length in D1

*               ------------------------------------
*                       D1 = Length
*                       A0 = File Header Address
*                       A1 = Data Area
*               ------------------------------------

file_convert_join
        bsr     RECONFIGURE             ; ... YES, reconfigure routine
        move.w  (a0),d0                 ; see if conversion type known
        lsl.w   #1,d0                   ; convert to displacement
        move.w  convert_table(d0.w),d0  ; get displacement
        jmp     convert_table(d0.w)     ; and make vectored jump

convert_table
        dc.w    CONVERT_FIND_TYPE-convert_table 
        dc.w    CONVERT_EXIT-convert_table 
        dc.w    SIMPLE_CONVERT-convert_table
        dc.w    DOC_CONVERT-convert_table
        dc.w    DBF_CONVERT-convert_table
        dc.w    SCN_CONVERT-convert_table
        dc.w    CONVERT_EXIT-convert_table
        dc.w    ABA_CONVERT-convert_table
        dc.w    GRF_CONVERT-convert_table
        dc.w    CONVERT_EXIT-convert_table
        
*       Check when source is OPD

convert_find_type        
        move.w  srctyp,d0               ; Source OPD ?
        bne.s   @4                      ; ... No, then jump
        move.b  fh_type+2(a0),d0        ; get OPD file type
        beq.s   convert_user            ; Type=0 (data)
        cmpi.b  #2,d0                   ; Type=2 (Basic Application)
        beq.s   SIMPLE_CONVERT
        cmpi.b  #5,d0                   ; Type=5 (Basic Program)
        beq.s   SIMPLE_CONVERT
        bra.s   convert_exit            ; ... Else exit

*       Check when source is QL

@4      move.w  desttyp,d0              ; Destination OPD ?
        bne.s   convert_exit            ; neither drive OPD, so exit
        move.b  fh_type+2(a0),d0
        bne.s   convert_exit            ; Exit if program file

*       Check when depends on parameter prompt

convert_user
        move.w  charflag,d0
        beq.s   SIMPLE_CONVERT

convert_exit
        movem.l (SP)+,d1-d2/a0-a3
        moveq   #0,d0
        rts

convert dc.w    0

*----------------------------------------------------------------------
*       This routine is resposible for the conversion of files that
*       are simple in structure, and consist of graphic data only.
*----------------------------------------------------------------------

SIMPLE_CONVERT
        move.w  #2,(a0)
        bsr     CHAR_CONVERT
        bra.s   convert_exit

*PAGE
*----------------------------------------------------------------------
*       This routine is resposible for the conversion of QUILL files
*               A0      Convert address
*               A1      File Data Address
*----------------------------------------------------------------------

DOC_CONVERT
        eor.b   #1,9(a1)                ; change file type

*       Set logical length for OPD files

        move.w  desttyp,d0              ; see if OPD
        bne.s   @3                      ; ... NO, then jump
        moveq   #0,d0
        add.w   14(a1),d0
        add.w   16(a1),d0
        add.w   18(a1),d0
        add.l   10(a1),d0               ; data part
        move.l  d0,fh_length+2(a0)      ; set as file length
        bra.s   @5
        
*       Check minimum length is 4K

@3      move.l  2(a0),d0                ; get length
        cmpi.l  #$800,d0                ; is it at least 4K
        bgt.s   @5                      ; ... YES, then jump
        move.l  #$800,2(a0)             ; ... NO, adjust length
        
*       Convert only the text part of the file
*       (NOTE. D1.L contains length of file currently in store)

@5      clr.l   d2
        move.w  (a1),d2                 ; set length of header record
        sub.l   d2,d1                   ; and change given length also
        neg.l   d2                      ; ...and set to be ignored
        add.l   10(a1),d2               ; set length of data to convert
        cmp.l   d2,d1                   ; length greater than given
        ble.s   @6                      ; ... YES, take given length
        move.l  d2,d1                   ; ... NO, use calcualted length
@6      add.w   (a1),a1                 ; start address after header
        bsr     CHAR_CONVERT            ; call conversion routine
DOC_RESET
        move.w  #1,(a0)                 ; no more conversion !
        bra     convert_exit
*PAGE
*----------------------------------------------------------------------
*       This routine is responsible for the conversion of ABACUS files
*----------------------------------------------------------------------

ABA_CONVERT

*       Convert the Currency symbol

        movem.l d1/a1,-(SP)
        moveq   #1,d1                   ; set for single character
        add.w   #$158,a1                ; set position in file
        bsr     CHAR_CONVERT
        movem.l (SP)+,d1/a1
        bra     DOC_RESET
*PAGE
*----------------------------------------------------------------------
*       This routine is responsible for the conversion of ARCHIVE
*       Database files
*----------------------------------------------------------------------

DBF_CONVERT
        bra     DOC_RESET
*PAGE
*----------------------------------------------------------------------
*       This routine is responsible for the conversion of ARCHIVE
*       Screen files.  Allowance mus be made for control characters
*       that have binary parameters.
*----------------------------------------------------------------------

SCN_CONVERT
        addq.l  #4,a1                   ; skip header
        moveq   #24,d2                  ; no of lines
@2      bsr.s   scn_line
        add.w   (a1)+,a1              ; skip to next line
        dbra    d2,@2
        bra     DOC_RESET

*       Convert the fields within a line        
        
scn_line        
        movem.l d0-d3/a0-a3,-(SP)       ; save registers
        move.w  (a1)+,d2                ; entry length
        move.w  (a1)+,d2                ; length actually used
@1      moveq   #0,d1
@2      subq.l  #1,d2                   ; end of data ?
        bpl.s   @3                      ; ... NO
        bsr.s   @8                      ; ... YES
        movem.l (SP)+,d0-d3/a0-a3
        rts

@3      cmpi.b  #$01,0(a1,d1.l)         ; set ink ?
        beq.s   @4                      ; ... YES, jump
        cmpi.b  #$02,0(a1,d1.l)         ; set paper ?
        bne.s   @5                      ; ... NO, jump
@4      bsr.s   @8
        addq.l  #2,a1                   ; skip bytes in buffer
        subq.l  #1,d2                   ; ... ignore parameter
        bra.s   @1                      ; ... rejoin loop

@5      cmpi.b  #$04,0(a1,d1.l)         ; Repeat ?
        bne.s   @6                      ; ... NO, jump
        bsr.s   @8
        addq.l  #1,a1                   ; set to data character
        moveq   #1,d1                   ; set length of 1
        bsr.s   @8                      ; convert character
        addq.l  #1,a1                   ; ... adjust buffer pointer
        subq.l  #2,d2                   ; skip parameters
        bra.s   @1                      ; ... rejoin loop

@6      addq.l  #1,d1                   ; update length to convert
        bra.s   @2                      ; loop for more
        
*       Convert data (if any) checked

@8      tst.l   d1                      ; any data left
        beq.s   @9                      ; ... NO, jump
        bsr     CHAR_CONVERT            ; ... YES, convert
        add.l   d1,a1
@9      rts
*PAGE
*----------------------------------------------------------------------
*       This routine is responsible for the conversion of EASEL files
*----------------------------------------------------------------------

GRF_CONVERT
        bra       DOC_RESET
*PAGE
*----------------------------------------------------------------------
*       This routine converts characters
*               A1      Start address
*               D1      Length to convert
*
*       REGISTERS SMASHED:  None
*----------------------------------------------------------------------

CHAR_CONVERT
        movem.l d1/d2/a2/a3,-(SP)       ; save registers used
        moveq   #0,d2                   ; clear register for later use
        lea     opd_to_ql_table,a2      ; assume direction
        move.w  srctyp,d0               ; ...get source type
        beq.s   @6                      ; ...jump if correct
        lea     ql_to_opd_table,a2      ; ...else change direction
        bra.s   @6                      ; ... and join loop
@2      move.l  a1,a3                   ; area start
        add.l   d1,a3                   ; + current character
        move.b  (a3),d2                 ; get byte
        move.b  0(a2,d2.w),(a3)         ; get corresponding table byte
@6      subq.l  #1,d1                   ; reduce remainder count
        bge.s   @2                      ; ...  and loop until finished
        movem.l (SP)+,d1/d2/a2/a3       ; restore original registers
        rts

*       These tables are used for character conversion.  They are
*       simple lookup tables arranged in ascending CODE value giving
*       the corresponding value after conversion.

ql_to_opd_table
        dc.b    0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
        dc.b    20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,202
        dc.b    36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51
        dc.b    52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67
        dc.b    68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83
        dc.b    84,85,86,87,88,89,90,91,92,93,94,95,35,97,98,99
        dc.b    100,101,102,103,104,105,106,107,108,109,110,111
        dc.b    112,113,114,115,116,117,118,119,120,121,122,123
        dc.b    124,125,126,203,128,129,130,131,132,133,134,135
        dc.b    136,137,138,139,140,141,142,143,144,145,146,147
        dc.b    148,149,150,151,152,153,154,155,156,157,158,96
        dc.b    160,161,162,163,164,165,166,167,168,169,179,171
        dc.b    172,173,174,175,176,177,178,179,180,181,182,183
        dc.b    184,185,186,187,188,189,190,191,192,193,194,195
        dc.b    196,197,198,199,200,201,202,203,204,205,206,207
        dc.b    208,209,210,211,212,213,214,215,216,217,218,219
        dc.b    220,221,222,223,224,225,226,227,228,229,230,231
        dc.b    232,233,234,235,236,237,238,239,240,241,242,243
        dc.b    244,245,246,247,248,249,250,251,252,253,254,255
opd_to_ql_table
        dc.b    0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
        dc.b    20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,96
        dc.b    36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51
        dc.b    52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67
        dc.b    68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83
        dc.b    84,85,86,87,88,89,90,91,92,93,94,95,159,97,98,99
        dc.b    100,101,102,103,104,105,106,107,108,109,110,111
        dc.b    112,113,114,115,116,117,118,119,120,121,122,123
        dc.b    124,125,126,127,128,129,130,131,132,133,134,135
        dc.b    136,137,138,139,140,141,142,143,144,145,146,147
        dc.b    148,149,150,151,152,153,154,155,156,157,158,159
        dc.b    160,161,162,163,164,165,166,167,168,169,179,171
        dc.b    172,173,174,175,176,177,178,179,180,181,182,183
        dc.b    184,185,186,187,188,189,190,191,192,193,194,195
        dc.b    196,197,198,199,200,201,35,127,204,205,206,207
        dc.b    208,209,210,211,212,213,214,215,216,217,218,219
        dc.b    220,221,222,223,224,225,226,227,228,229,230,231
        dc.b    232,233,234,235,236,237,238,239,240,241,242,243
        dc.b    244,245,246,247,248,249,250,251,252,253,254,255

*PAGE           PROGRAM RECONFIGURATION
*----------------------------------------------------------------------
*       This routine is used to reconfigure the programs during
*       Copying if necessary.
*
*               A0      Points to File Header
*               A1      Points to File Base
*            targetname is destination filename string
*----------------------------------------------------------------------

RECONFIGURE
        movem.l d0-d5/a0-a3,-(SP)       ; save registers 
        move.b  backflg,d0              ; backup in progress ?
        beq     recon_exit              ; ... NO, then exit
        move.w  desttyp,d0              ; get target type
        cmp.w   srctyp,d0               ; same as Source type ?
        beq     recon_exit              ; ... YES, then can exit
        
        move.l  (a0),-(SP)              ; save file size on stack
        lea     reconfiles,a0           ; get start of table
@2      bsr     SET_DESTINATION_TYPE
        movem.l a0/a1/a6,-(SP)          ; save registers
        sub.l   a6,a6                   ; uses A6 relative addressing
        moveq   #1,d0                   ; Case independent comparison
        lea     targetname,a1           ; Filename being compared
        move.w  UT_CSTR,a2              ; compare string vector
        jsr     (a2)                    ; compare strings in A0 & A1
        movem.l (SP)+,a0/a1/a6           ; restore registers
        beq.s   @3                      ; ... SAME, go to reconfigure
        move.w  (a0),d0                 ; get string length
        addq.w  #3,d0                   ; allow for count + odd length
        bclr.l  #0,d0                   ; ensure answer is even
        add.w   d0,a0                   ; ... and update pointer
        tst.w   (a0)                    ; Finished ?
        beq.s   @9                      ; ... YES, then exit
        bra.s   @2                      ; ... NO, then loop 

*        File needs doing, so re-configure it

@3      move.l  (a1),d3                 ; get first 4 bytes
        moveq   #4,d2                   ; set D2 to this point
        lea     devicetable,a3          ; device type table
        move.w  srctyp,d0               ; source type
        mulu.w  #6,d0                   ; ... convert to displacement
        move.l  2(a3,d0.w),d0           ; ... get text
        addq.b  #1,d0                   ; change to drive 1
@4      cmp.l   d0,d3                   ; matches file data ?
        bne.s   @8                      ; ... NO, then jump
        move.w  desttyp,d1              ; ... YES, set destination type
        mulu.w  #6,d1                   ; ... convert to displacement
        move.l  2(a3,d1.w),d1           ; ... get text
        lea     [-4](a1,d2.w),a2        ; get address reached
        moveq   #2,d3                   ; set loop count-1
@6      lsr.l   #8,d1                   ; lose rightmost byte
        move.b  d1,0(a2,d3.w)           ; change byte in file
        dbra    d3,@6                   ; ...loop until finished
        move.l  d0,d3                   ; restore D3 (file data)
@8      lsl.l   #8,d3                   ; Lose leftmost byte
        move.b  0(a1,d2.w),d3           ; add new byte to right
        addq.l  #1,d2                   ; update point reached
        cmp.l   (SP),d2                 ; see if end of file
        blt.s   @4                      ; ... NO, then loop
@9      addq.l  #4,SP                   ; remove stack save fields

recon_exit
        movem.l (SP)+,d0-d5/a0-a3       ; restore registers corrupted
        rts

reconfiles      dc.w    9
                dc.b    'Flp1_BOOT '
                dc.w    12
                dc.b    'Flp1_OPDLOAD'
                dc.w    12
                dc.b    'Flp1_OPDCOPY'
                dc.w    12
                dc.b    'Flp1_OPDDIAG'
                dc.w    0               ; End of table
        END

