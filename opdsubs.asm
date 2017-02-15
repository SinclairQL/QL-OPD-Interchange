***********************************************************************
**                                                                   **
**                OPD SUPPORT PROGRAM SUBROUTINES                    **
**                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~                    **
**      This module contains subroutines used within the OPDDIAG     **
**      and OPDCOPY programs.                                        **
**                                       LAST AMENDED:  22/07/86     **
***********************************************************************

        xdef    MDV_START, MDV_STOP, OPD_SPIN, QL_SPIN
        xdef    OPD_READ_HEADER,QL_READ_HEADER
        xdef    PICK_PARAMETER, SHOW_PARAMETER, DRIVE_LIST
        xdef    CONSOLE_MESSAGE,ACTION_MESSAGE,ERROR_MESSAGE
        xdef    BEEP1,BEEP2,BEEP3
        xdef    CLEAR_CONSOLE_LINE
        xdef    SCREEN_CLEAR_LINE,CHANNEL_CLEAR_LINE
        xdef    SCREEN_NEWLINE,CHANNEL_NEWLINE
        xdef    SCREEN_MESSAGE,CHANNEL_MESSAGE
        xdef    CONSOLE_LARGE_WIDE,ACTION_LARGE_WIDE
        xdef    CHANNEL_LARGE_WIDE
        xdef    CONSOLE_LARGE,ACTION_LARGE,CHANNEL_LARGE
        xdef    CONSOLE_NORMAL,ACTION_NORMAL,CHANNEL_NORMAL
        xdef    CONSOLE_STRIP,CHANNEL_STRIP
        xdef    CONSOLE_INK,ACTION_INK,SCREEN_INK,CHANNEL_INK
        xdef    CONSOLE_POSITION,CHANNEL_POSITION        

        xref    conid,scrid,actid,errid
        xref    maxdrv,opddriver

*       STANDARD DEFINITIONS
*NOLIST
$INCLUDE        Flp1_asmlib_trap1
$INCLUDE        Flp1_asmlib_trap2
$INCLUDE        Flp1_asmlib_trap3
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_errors
$INCLUDE        Flp1_asmlib_Channels
*LIST
*PAGE          M I C R O D R I V E    P H Y S I C A L   R O U T I N E S
MDV_START
        move.l  opddriver,a2
        jmp     ch_start(a2)
        
MDV_STOP
        move.l  opddriver,a2
        jmp     ch_stop(a2)
        
OPD_SPIN
        pea     OPD_READ_HEADER
        bra.s   spin
        
QL_SPIN
        pea     QL_READ_HEADER

spin    move.l  (SP)+,d5
        bsr     MDV_START
        tst.b   d0
        bne.s   @9
        move.l  d5,a2                   ; sector read routine address
        jsr     (a2)
        bra.s   @8                      ; ... ERROR
        bsr     MDV_STOP
        addq.l  #2,(SP)                 ; OK, update return address
        rts
@8      bsr     MDV_STOP
@9      rts

OPD_READ_HEADER
        move.l  opddriver,a2
        jmp     ch_read_header(a2)
QL_READ_HEADER
        move.l  opddriver,a2
        jmp     ch_ql_read_header(a2)

*PAGE           PARAMETER SELECTION
*--------------------------------------------------------------------
*       Pick a parameter value
*
*       A5 contains parameter control block address 
*              1 Word - Current Value              
*              2*word - Minimum/Maximum value      
*              1 word - xorigin for minimum        
*              4*word - block wifth/height/x & y origins  
*                                                                 
*       conid   contains console channel identity          
*       actid   contains action channel identity           
*--------------------------------------------------------------------

PICK_PARAMETER
        moveq   #SD_CLEAR,d0
        move.l  actid,a0
        TRAP    #3
        bsr     CHANNEL_NORMAL
        moveq   #7,d1
        bsr     CHANNEL_INK
        lea     curmsg1,a1
        bsr     CHANNEL_MESSAGE
        bsr     CHANNEL_NEWLINE
        moveq   #4,d1
        bsr     CHANNEL_INK       
        lea     curmsg2,a1
        bsr     CHANNEL_MESSAGE
        bra.s   picknxt
curmsg1 dc.w    34
        dc.b    '   QUIT       SELECT        ACCEPT'
curmsg2 dc.w    36
        dc.b    ' ESC or ¾   ¼½ or SPACE   ENTER or ¿'

picknxt bsr     SHOW_PARAMETER
        moveq   #SD_SETMD,d0            ; set write mode trap
        moveq   #-1,d1                  ; reset to XOR mode
        TRAP    #3
@1      moveq   #sd_pixp,d0
        move.w  12(a5),d1               ; x-position
        move.w  14(a5),d2               ; y-position
        trap    #3
        moveq   #SD_CURE,d0
        trap    #3
        moveq   #IO_FBYTE,d0            ; fetch a byte
        trap    #3
        exg     d2,d1
        moveq   #SD_CURS,d0
        trap    #3
        cmpi.b  #208,d2                 ; Up arrow
        beq.s   @6                      ; ... Yes, error exit
        cmpi.b  #27,d2                  ; ESC
        beq.s   @6                      ; ... Yes, error exit
        cmpi.b  #200,d2                 ; Right Arrow
        beq.s   @7                      ; ... Yes, toggle value
        cmpi.b  #' ',d2                 ; SPACE
        beq.s   @7                      ; ... Yes, toggle value
        cmpi.b  #192,d2                 ; Left Arrow
        beq.s   @8                      ; ... Toggle backward
        cmpi.b  #216,d2                 ; Down arrow
        beq.s   @4                      ; ... Yes, then normal exit
        cmpi.b  #10,d2                  ; ENTER
        beq.s   @4                      ; ... YES, then normal exit
        subi.b  #'0',d2
        cmp.b   5(a5),d2                ; greater than maximum ?
        bhi.s   @1                      ; ... YES, ignore
        cmp.b   3(a5),d2                ; less than minimum
        bmi.s   @1                      ; ... YES, ignore
        bsr.s   block                   ; undo current highlight
        move.b  d2,1(a5)                ; store new value
        bsr     SHOW_PARAMETER          ; highlight value
@4      moveq   #0,d0                   ; ... Yes, then valid exit
@5      move.l  d0,-(a7)                ; save return code
        moveq   #SD_SETMD,d0
        moveq   #0,d1                   ; set for normal mode
        trap    #3
        bsr     error_clear
        moveq   #SD_CLEAR,d0
        move.l  actid,a0
        trap    #3
        move.l  (a7)+,d0                ; set return code
        rts    

*       Error exit

@6      bsr.s   block                   ; clear current block
        moveq   #err_bp,d0              ; set error return
        bra.s   @5

*       Toggle forward

@7      bsr     error_clear
        bsr.s   block                   ; clear current block
        addq.w  #1,(a5)                 ; next parameter value
        move.w  4(a5),d0 
        cmp.w   (a5),d0                 ; is it in range
        bge     picknxt                 ; ... yes, then output
        move.w  2(a5),(a5)              ; reset to minimum
        bra     picknxt                 ; then output

*       Toggle backward

@8      bsr     error_clear
        bsr.s   block                   ; clear current block
        subq.w  #1,(a5)                 ; next value
        move.w  2(a5),d0                ; ...and store
        cmp.w   (a5),d0                 ; is it in range?
        ble     picknxt                 ; ..yes, then continue
        move.w  4(a5),(a5)              ; reset to maximum
        bra     picknxt

*       Output block

block   move.l  conid,a0
        addq.w  #8,8(a5)
        subq.w  #4,12(a5)
        lea     8(a5),a1
        moveq   #2,d1                   ; colour red
        moveq   #sd_fill,d0
        trap    #3
        subq.w  #8,8(a5)
        addq.w  #4,12(a5)
        rts

error_clear
        move.l  a0,-(SP)
        moveq   #SD_CLEAR,d0
        move.l  errid,a0
        trap    #3
        move.l  (SP)+,a0
        rts
        
*-----------------------------------------------------------------
*       Highlight the parameter currently selected
*       Parameters as for PICK_PARAMETER
*-----------------------------------------------------------------

SHOW_PARAMETER
        moveq   #SD_SETMD,d0            ; set write mode trap
        moveq   #-1,d1                  ; reset to XOR mode
        move.l  conid,a0                ; console window
        TRAP    #3
        move.w  (a5),d0                 ; get current parameter value
        sub.w   2(a5),d0                ; subtract minimum
        move.w  8(a5),d1                ; entry size
        add.w   #12,d1                  ; ...plus gap size
        mulu.w  d1,d0                   ; ... times relative par value
        add.w   6(a5),d0                ; plus start
        move.w  d0,12(a5)               ; into block control
        bsr.s   block                   ; ... and output block
        moveq   #SD_SETMD,d0
        moveq   #0,d1
        TRAP    #3
        rts

*PAGE
*------------------------------------------------------------------
*       Output a list of drive numbers up to value of 'maxdrv'
*               A0 contains channel id
*               A5 contains parameter block address
*------------------------------------------------------------------
DRIVE_LIST
        moveq   #0,d5
        move.w  maxdrv,4(a5)            ; set maximum drive number
@2      cmp.w   maxdrv,d5               ; finished ?
        blt     @4                      ; ... NO, jump
        rts                             ; ...YES, exit
@4      addq.l  #1,d5                   ; update drive number
        moveq   #'0',d0                 ; set base character value
        add.l   d5,d0                   ; ... plus drive
        lea     drvmsg,a1
        move.b  d0,3(a1)                ; store in message
        bsr     CHANNEL_MESSAGE
        bra.s   @2
drvmsg  dc.w    2
        dc.b    ' n'

BEEP1
        lea     beep1d,a3
beep    movem.l d0-d3/a0-a2,-(SP)
        moveq   #MT_IPCOM,d0
        TRAP    #1
        movem.l (SP)+,d0-d3/a0-a2
        rts
        
BEEP2   lea     beep2d,a3
        bra.s   beep
        
BEEP3   lea     beep3d,a3
        bra.s   beep

beep1d  dc.b    $A,8
        dc.l    $0000AAAA
        dc.b    150,150                 ; pitch 1, pitch 2
        dc.w    250,10000               ; interval, duration
        dc.b    $00+$00,$00+$00         ; step/wrap, random/fuzzy
        dc.b    $01                     ; no reply
        ALIGN
beep2d  dc.b    $A,8
        dc.l    $0000AAAA
        dc.b    30,30                   ; pitch 1,pitch 2
        dc.w    1000,10000              ; interval, duration
        dc.b    $00+$00,$00+$00         ; step/wrap, random/fuzzy
        dc.b    $01                     ; no reply
        ALIGN
beep3d  dc.b    $A,8
        dc.l    $0000AAAA
        dc.b    70,50                   ; pitch 1, pitch 2
        dc.w    2500,15000              ; interval, duration
        dc.b    $10+$00,$00+$00         ; step/wrap, random/fuzzy
        dc.b    $01                     ; no reply
        ALIGN
*PAGE        S C R E E N   R O U T I N E S
*       This routine clears the line for the message in A1

CLEAR_CONSOLE_LINE
        moveq   #0,d1
        move.w  (a1),d2                 ; get line number
        bsr.s   CONSOLE_POSITION
CHANNEL_CLEAR_LINE
        moveq   #SD_CLRLN,d0
        bsr.s   trap3
        moveq   #SD_PROW,d0
        TRAP    #3
        bsr.s   CHANNEL_NEWLINE
        rts
SCREEN_CLEAR_LINE
        move.l  scrid,a0
        bra.s   CHANNEL_CLEAR_LINE

*       A1 points to co-ordinates wanted (as for CONSOLE_MESSAGE)

CONSOLE_POSITION                        ; A1 = Position word
        move.w  (a1)+,d2                ; Y Co-ordinate
        move.w  (a1)+,d1                ; X Co-ordinate
        move.l  conid,a0

*       D1 = X Co-ordinate,  D2 = Y Co-ordinate

CHANNEL_POSITION                        ; A0 = Channel Id
        moveq   #sd_pos,d0
        bra.s   trap3

SCREEN_NEWLINE
        move.l  scrid,a0
CHANNEL_NEWLINE
        lea     nlbuf,a1
        bra.s   CHANNEL_MESSAGE
nlbuf   dc.w    1
        dc.b    10,10
*PAGE
*       Send the message indicated by A1 to the console window at
*       the indicated position.

CONSOLE_MESSAGE
        move.l  a1,-(SP)                ; save message string address
        bsr.s   CONSOLE_POSITION
        moveq   #SD_CLRLN,d0
        TRAP    #3
        moveq   #SD_CLRBT,d0
        TRAP    #3
        move.l  (SP)+,a1                ; restore message address
        addq.l  #4,a1                   ; skip positioning word
        bra.s   channel_message
        
*       Send the message given by A1 to the error window

ERROR_MESSAGE
        move.l  errid,a0
        bra.s   clear_message

*       Send the message given by A1 to Action window

ACTION_MESSAGE
        move.l  actid,a0
CLEAR_MESSAGE
        move.l  a1,-(SP)                ; save message address
        moveq   #SD_CLEAR,d0
        TRAP    #3
        move.l  (SP)+,a1                ; restore messagee address
        bra.s   CHANNEL_MESSAGE

*       This routine sends the message indicated by A1 to the
*       screen/channel window.

SCREEN_MESSAGE
        move.l  a1,-(SP)
        bsr.s   SCREEN_NEWLINE
        move.l  (SP)+,a1
CHANNEL_MESSAGE
        moveq   #IO_SSTRG,d0
        move.w  (a1)+,d2                ; set length
trap3   moveq   #-1,d3         
        TRAP    #3
        rts
*PAGE
CONSOLE_LARGE_WIDE
        move.l  conid,a0
        bra.s   CHANNEL_LARGE_WIDE
ACTION_LARGE_WIDE
        move.l   actid,a0
CHANNEL_LARGE_WIDE                      ; A0 = Channel Id
        moveq   #3,d1                   ; 16 pixels wide
        bra.s   set_large        

CONSOLE_LARGE
        move.l  conid,a0
        bra.s   CHANNEL_LARGE
ACTION_LARGE
        move.l  actid,a0
CHANNEL_LARGE
        moveq   #2,d1                   ; 12 pixels wide
set_large
        moveq   #1,d2                   ; 20 pixels high
        bra.s   set_size

CONSOLE_NORMAL
        move.l  conid,a0
        bra.s   CHANNEL_NORMAL
ACTION_NORMAL
        move.l  actid,a0
CHANNEL_NORMAL                          ; A0 = Channel Id
        moveq   #2,d1                   ; 12 pixels wide
set_normal
        moveq   #0,d2                   ; 10 pixels high
set_size
        moveq   #SD_SETSZ,d0
trap3B  bra.s   trap3


*       D1 = Strip Colour

CONSOLE_STRIP
        move.l  conid,a0
CHANNEL_STRIP                           ; A0 = Channel Id
        moveq   #SD_SETST,d0
        bra.s   trap3B

*       D1 = Ink Colour

CONSOLE_INK
        move.l  conid,a0
        bra.s   CHANNEL_INK
ACTION_INK
        move.l  actid,a0
        bra.s   CHANNEL_INK
SCREEN_INK
        move.l  scrid,a0
CHANNEL_INK                             ; A0 = Channel Id
        moveq   #SD_SETIN,d0
        bra.s   trap3B
        END
