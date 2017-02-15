******************************************************************
**                       OPDCOPY:  Module 2                     **
**                                                              **
**      This module is responsible for the following tasks:     **
**              - Parameter Input                               **
**                                      LAST UPDATED: 23/07/86  **
******************************************************************

        xdef    CONSOLE_GREEN_MESSAGE, CONSOLE_YESNO_MESSAGE
        xdef    GET_PARAMETERS,GET_TARGET_DETAILS,DISPLAY_SOURCE
        xdef    GET_SELECTIVE
        xdef    srcdrv,srctyp,destdrv,desttyp,destfmt,medium
        xdef    conid,scrid,actid,errid,select,charflag

*       Externals in OPDCOPY1

        xref    QUIT, COPY_TAPE,destchan,srcchan
        xref    devicetable,devicecount,fileheader,filestart,fileend
        xref    OPEN_FILE,CLOSE_FILE,OPEN_DIR
        xref    SET_DESTINATION_TYPE,SET_TARGET_HEADER
        xref    OPEN_CLOSE_TARGET_DIR
        xref    ALLOCATE_MEMORY,RELEASE_MEMORY_FIRST
        xref    OPEN_SOURCE_DIR,dirchan,sourcename,targetname
        xref    SCREEN_ERROR_TEXT,SCREEN_QDOS_ERROR
        xref    errorcount,notcount,okcount,maxdrv

*       Externalsin OPDCOPY2

        xref    tapeid, srcmed, header, backflg

*       Externals in OPDSUBS

        xref    PICK_PARAMETER,SHOW_PARAMETER,DRIVE_LIST
        xref    CONSOLE_MESSAGE,CLEAR_CONSOLE_LINE
        xref    SCREEN_MESSAGE,SCREEN_NEWLINE
        xref    ACTION_MESSAGE,ERROR_MESSAGE,CHANNEL_MESSAGE
        xref    BEEP1,BEEP2,BEEP3,QL_SPIN,OPD_SPIN
        xref    CHANNEL_NORMAL,CONSOLE_NORMAL,ACTION_NORMAL
        xref    CHANNEL_LARGE,CONSOLE_LARGE,ACTION_LARGE
        xref    CONSOLE_LARGE_WIDE,ACTION_LARGE_WIDE
        xref    CHANNEL_LARGE_WIDE
        xref    CONSOLE_INK,ACTION_INK,SCREEN_INK,CHANNEL_INK
        xref    CONSOLE_STRIP,CONSOLE_POSITION
        xref    OPDEND,opddriver

*       Externals in OPDFIND

        xref    FIND_DRIVER,FIND_CODE,FIND_PHYSICAL
        xref    mdvname,opdname,flpname,devname

*NOLIST
$INCLUDE        flp1_asmlib_files
$INCLUDE        Flp1_asmlib_QL_header
$INCLUDE        flp1_asmlib_trap3
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_system
$INCLUDE        Flp1_asmlib_errors
*LIST
*PAGE           PARAMETER INPUT - STANDARD OPTIONS
********************************************************************
**
**       This routine gets the required parameters for this run
**
********************************************************************

GET_PARAMETERS

*       Set defaults

        lea     wcopy,a1
        move.w  #1,(a1)                 ; NO for Wild Card Copy
        lea     select,a1
        move.w  #1,(a1)                 ; NO for Selective Copy
        lea     charflag,a1
        move.w  #1,(a1)                 ; NO for Data Translate

*       Get source drive number

getsdrv moveq   #SD_CLEAR,d0
        move.l  conid,a0
        TRAP    #3
        lea     srcmsg,a1               ; Source drive message
        bsr     CONSOLE_GREEN_MESSAGE
        lea     srcdrv,a5       
        bsr     DRIVE_LIST
        bsr     PICK_PARAMETER
        beq.s   getstyp
quitget addq    #4,a7                   ; remove return address
        bra     QUIT

srcdrv  dc.w    1                       ; Current value
        dc.w    1,8                     ; Minimum/Maximum values
        dc.w    240                     ; x origin for minimum
        dc.w    12,9,0,10
srcmsg  dc.w    1,1,18
        dc.b    'SOURCE:      Drive'
msg3a   dc.w    0,3,14
        dc.b    'SOURCE:       '

*       Get Source Drive type

getstyp lea     stypmsg,a1              ; source drive type
        bsr     CONSOLE_GREEN_MESSAGE
        lea     srctyp,a5
        bsr     DEVICE_TYPES
        bsr     PICK_PARAMETER
        bne     getsdrv
        tst.b   sv_mdrun(a6)
        beq.s   srcshow
        lea     usedmsg,a1
        bsr     ERROR_MESSAGE
        bra.s   getstyp

srctyp  dc.w    1
        dc.w    0,2          
        dc.w    240          
        dc.w    36,9,0,20
stypmsg dc.w    2,14,6
        dc.b    'Type: '

*       Display results for Source Drive

srcshow move.w  srcdrv,d3
        move.w  srctyp,d0
        bsr     drvfmt
        bne.s   @5
        bsr     DISPLAY_SOURCE
        move.w  srcdrv,d0
        eor.b   #3,d0
        lea     destdrv,a1
        move.w  d0,(a1)
        bra.s   getddrv
@5      lea     xfmtmsg,a1
        bsr     ERROR_MESSAGE
        bra.s   getstyp
xfmtmsg dc.w    28
        dc.b    'Drive @:  Not Correct Format' 

usedmsg dc.w    20
        dc.b    '  Microdrives in Use'

*       Get Destination Drive details

getddrv lea     desttyp,a1
        clr.w   (a1)                    ; set to OPD type
        move.w  srctyp,d0               ; source OPD ?
        bne.s   @2                      ; ... NO, leave alone
        addq.w  #1,(a1)                 ; ... YES, change to MDV
@2      bsr     GET_TARGET_DETAILS
        bne     getsdrv
        moveq   #SD_CURS,d0             ; suppress cursor
        moveq   #-1,d3
        move.l  conid,a0
        TRAP    #3
        bsr     SPECIAL_OPTIONS
        bne     getddrv
        moveq   #0,d0
        rts
                
*--------------------------------------------------
*       check if drive in D3 is format in D0
*--------------------------------------------------

DRVFMT  lea     xfmtmsg,a5
        move.b  d3,8(a5)
        addi.b  #'0',8(a5)              ; convert to numeric char.
        lea     header,a5
        cmpi.w  #1,d0
        bhi.s   @4                      ; No check if FLP
        beq.s   @3
        bsr     OPD_SPIN
        bra.s   @8
        bra.s   @4
@3      bsr     QL_SPIN
        bra.s   @8
@4      moveq   #0,d0                   ; set valid exit
        bra.s   @9
@8      moveq   #err_fe,d0              ; set failed condition
@9      tst.l   d0
        rts
*-----------------------------------------------------------------
*       This routine adds the list of device types to the
*       Source and destination prompts
*               A5 points to parameter block
*------------------------------------------------------------------

DEVICE_TYPES
        moveq   #0,d4
        move.w  devicecount,d5
        lea     devicetable,a4
        move.w  2(a5),d0                ; see if OPD in use
        beq.s   @5                      ; ... YES, then jump
        lea     dvmsg,a1                ; ... NO, output spaces
        move.w  #4,(a1)
        bsr     CHANNEL_MESSAGE
        bra.s   @7
@5      lea     0(a4,d4),a2
        lea     devname,a1
        move.l  2(a2),2(a1)
        andi.l  #$5F5F5F00,2(a1)        ; convert to upper case 
        bsr     CHANNEL_MESSAGE
        lea     dvmsg,a1
        move.w  #1,(a1)                 ; set for one space
        bsr     CHANNEL_MESSAGE
@7      addq.w  #6,d4
        subq.w  #1,d5
        bpl.s   @5
        rts
dvmsg   dc.w    1
        dc.b    '    '

DISPLAY_SOURCE
        bsr     OPEN_SOURCE_DIR
        lea     dirchan,a1
        bsr     CLOSE_FILE
DISPLAY_SOURCE_AGAIN
        move.w  srctyp,d0
        move.w  srcdrv,d1
        bsr     FIND_PHYSICAL
        lea     srcmed,a0
        move.l  fs_mname(a2),2(a0)      ; move across medium name
        move.l  fs_mname+4(a2),6(a0)
        move.l  fs_mname+8(a2),10(a0)
        move.l  a0,-(SP)                ; address of name
        move.w  srcdrv,-(SP)            ; drive number
        move.w  srctyp,-(SP)            ; drive type
        pea     msg3A                   ; 'source' message
        bra.s   DISPLAY_DRIVE

msg5a   dc.w    1,3,14
        dc.b    'DESTINATION:  '

DISPLAY_TARGET
        pea     medium                  ; address of name
        move.w  destdrv,-(SP)           ; drive number
        move.w  desttyp,-(SP)           ; drive type
        pea     msg5A                   ; 'destination' message
DISPLAY_DRIVE        
        bsr     CONSOLE_LARGE
        move.l  (SP)+,a1                ; get source/target
        bsr     CONSOLE_GREEN_MESSAGE
        move.l  4(SP),a1                ; address of medium name string
        move.w  #10,(a1)                ; set QL medium length
        move.w  (SP)+,d0                ; get type code
        bne.s   @2                      ; ... QL, so jump
        subq.w  #2,(a1)                 ; change to OPD medium length
@2      mulu.w  #6,d0
        lea     nullmsg,a1
        lea     devicetable,a2
        move.l  2(a2,d0.w),2(a1)        ; set device type
        move.w  (SP)+,d0                ; drive
        add.b   #'0',d0                 ; convert to ASCII
        move.b  d0,5(a1)
        bsr     CHANNEL_MESSAGE
        lea     undmsg,a1
        bsr     CHANNEL_MESSAGE
        move.l  (SP)+,a1                ; medium name
        bsr     CHANNEL_MESSAGE
        bsr     CONSOLE_NORMAL
        rts
undmsg  dc.w    1
        dc.b    "_ "
nullmsg dc.w    4
        dc.b    '    '
        
*-------------------------------------------------------------------
*       This routine gets the details of the output tape for the
*       Copy process.
*-------------------------------------------------------------------

GET_TARGET_DETAILS        
        lea     ddrvmsg,a1              ; destination drive message
        bsr     CONSOLE_GREEN_MESSAGE
        lea     destdrv,a5
        bsr     DRIVE_LIST
        bsr     PICK_PARAMETER
        beq.s   getdtyp
        rts

destdrv dc.w    2      
        dc.w    1,8
        dc.w    240    
        dc.w    12,9,0,20
ddrvmsg dc.w    2,1,18
        dc.b    'DESTINATION: Drive'

getdtyp lea     dtypmsg,a1              ; destination type message
        bsr     CONSOLE_GREEN_MESSAGE
        lea     desttyp,a5
        bsr     DEVICE_TYPES
        bsr     PICK_PARAMETER
        bne     get_target_details
        move.w  srcdrv,d0               ; check if same drive number
        cmp.w   destdrv,d0
        bne.s   destuse
        move.w  srctyp,d0               ; ... AND same drive type
        cmp.w   desttyp,d0
        bne.s   destuse
        lea     msg11,a1                ; ERROR: Drives same
        bsr     ERROR_MESSAGE
        bra     get_target_details      
          
desttyp dc.w    1          
        dc.w    0,2        
        dc.w    240        
        dc.w    36,9,0,30
dtypmsg dc.w    3,14,6
        dc.b    'Type: '
msg11   dc.w    33
        dc.b    'Source and Destination same Drive '

destuse tst.b   sv_mdrun(a6)
        beq.s   @2
        lea     usedmsg,a1
        bsr     ERROR_MESSAGE
        bra     getdtyp
@2      lea     destfmt,a5
        move.w  #1,(a5)                  ; set for reformat
        move.w  destdrv,d3
        move.w  desttyp,d0
        bsr     DRVFMT
        bne.s   @5
        bra.s   getfmt
@5      lea     destfmt,a5              ; clear as already correct fmt
        clr.w   (a5)       
getfmt  lea     dfmtmsg,a1              ; reformat tape message
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        lea     destfmt,a5
        move.w  (a5),-(a7)              ; save original value
        bsr     PICK_PARAMETER
        move.w  (a7)+,d7                ; restore original value to d7
        tst.b   d0                      ; check return code
        bne     getdtyp                 ; ... branch back if not OK    
        move.w  destfmt,d0
        beq.s   getmed                  ; if new value yes then medium
        tst.w   d7
        bne     mdetail
        lea     xfmtmsg,a1
        bsr     ERROR_MESSAGE
        bra     get_target_details

destfmt dc.w    0          
        dc.w    0,1        
        dc.w    264    
        dc.w    36,9,0,50  
dfmtmsg dc.w    5,6,16
        dc.b    'Reformat:       '

*       If not reformatting, get current details

mdetail bsr     OPEN_CLOSE_TARGET_DIR
        move.w  desttyp,d0
        move.w  destdrv,d1
        bsr     FIND_PHYSICAL           ; get physical def block
        lea     medium,a0
        move.l  fs_mname(a2),2(a0)      ; move across medium name
        move.l  fs_mname+4(a2),6(a0)
        move.l  fs_mname+8(a2),10(a0)
        bra     get_target_ok

*       Get medium name when re-formatting

getmed  lea     mcpymsg,a1
        bsr     ACTION_MESSAGE
        lea     medmsg,a1               ; Medium message
        bsr     CONSOLE_GREEN_MESSAGE
        moveq   #IO_FLINE,d0            ; get console data
        moveq   #-1,d3                  ; wait for completion
        moveq   #10,d2                  ; max of ten characters
        lea     medium+2,a1             ; start of text area
        moveq   #9,d1
@3      move.b  #' ',0(a1,d1.w)         ; spacefill medium name first
        dbra    d1,@3
        TRAP    #3                      ; get name wanted
        cmpi.b  #10,[-1](a1)
        bne.s   @5
        move.b  #' ',[-1](a1)
        subq.w  #1,d1
@5      lea     medium,a2
        move.w  d1,(a2)                 ; store length
        bra.s   medium_copy

medmsg  dc.w    5,6,13
        dc.b    'Medium Name: '
msg8A   dc.w    3,20
medium  dc.w    10
        ds.b    14
mcpymsg dc.w    36
        dc.b    ' (ENTER to copy Source medium name) ' 

*       Allow tape name to be copied if ENTER key used.

medium_copy
        lea     tapeid,a0
        lea     srcmed,a1
        lea     medium,a2
        clr.w   (a0)                    ; clear tape id required
@2      move.w  medium,d0               ; get medium length
        beq.s   @5                      ; go to default name
        subq.w  #1,d0                   ; only one character ?
        bne.s   get_target_ok           ; ... NO
        cmpi.b  #$7F,2(a2)              ; copyright entry ?
        bne.s   get_target_ok           ; ... NO
        move.w  12(a1),(a0)             ; set target id
@5      move.l  (a1)+,(a2)+             ; set defaulted medium name
        move.l  (a1)+,(a2)+
        move.l  (a1)+,(a2)+
get_target_ok
        lea     medmsg,a1
        bsr     CLEAR_CONSOLE_LINE
        bsr     DISPLAY_TARGET
        moveq   #0,d0
        rts

*PAGE   PARAMETER INPUT - SPECIAL OPTIONS
SPECIAL_OPTIONS
        lea     specialmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        lea     specialyesno,a5
        move.w  #1,(a5)                 ; preset to NO
        bsr     PICK_PARAMETER
        bne.s   @9
        move.w  specialyesno,d0
        beq.s   special_yes
        moveq   #0,d0
@9      rts
special_exit
        moveq   #SD_CLEAR,d0
        move.l  conid,a0
        TRAP    #3
        bsr     DISPLAY_SOURCE_AGAIN
        bsr     DISPLAY_TARGET
        bra.s   special_options
specialyesno    dc.w    1
                dc.w    0,1
                dc.w    228
                dc.w    36,9,0,50
specialmsg      dc.w    5,3,16
                dc.b    'Change Options: '
special_yes
        bsr     CONSOLE_LARGE
        moveq   #4,d1
        bsr     CONSOLE_INK
        moveq   #SD_SETUL,d0            ; set underline mode
        moveq   #1,d1
        TRAP    #3
        lea     specmsg,a1
        bsr     CONSOLE_MESSAGE
        moveq   #SD_SETUL,d0
        moveq   #0,d1
        TRAP    #3
        bsr     CONSOLE_NORMAL

        bsr     check_translate
        bne.s   @6
        lea     tranmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        lea     charflag,a5
        bsr     SHOW_PARAMETER

@6
*        lea     wcopymsg,a1
*        bsr     CONSOLE_GREEN_MESSAGE
*        bsr     CONSOLE_YESNO_MESSAGE
*        lea     wcopy,a5
*        bsr     SHOW_PARAMETER
        
        lea     selmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        lea     select,a5
        bsr     SHOW_PARAMETER
        bra.s   get_translate

specmsg dc.w    0,9,15
        dc.b    'SPECIAL OPTIONS '

*       See if data translation wanted/needed

get_translate
        bsr.s   check_translate
        bne.s   @9        
@5      lea     charflag,a5
        bsr     SHOW_PARAMETER
        bsr     PICK_PARAMETER
        bne     special_exit
@9      bra     get_select
*@9      bra     get_wcopy

*       Check if translate prompt relevant

check_translate
        move.w  srctyp,d0
        move.w  desttyp,d1
        cmp.b   d0,d1                   ; same type ?
        beq     @8
        tst.b   d0
        beq.s   @5
        tst.b   d1
        bne     @8                      ; neither type is OPD
@5      moveq   #0,d0
        rts
@8      moveq   #ERR_NC,d0
        rts

charflag dc.w   0          
        dc.w    0,1        
        dc.w    264        
        dc.w    36,9,0,30  
tranmsg dc.w    3,6,16
        dc.b    'Data translate: '

*---------------------------------------------------------------
*       See if Wild Card Copy wanted
*---------------------------------------------------------------

get_wcopy
        lea     wcopy,a5
        bsr     SHOW_PARAMETER
        bsr     PICK_PARAMETER
        beq.s   get_select
        bne     special_exit
wcopy   dc.w    0          
        dc.w    0,1        
        dc.w    264        
        dc.w    36,9,0,40  
wcopymsg dc.w    4,6,16
        dc.b    'Wild Card Copy: '

*--------------------------------------------------------
*       See if Interactive File Selection wanted
*--------------------------------------------------------
get_select
        bsr.s   GET_SELECTIVE
*        bne     get_wcopy
        bra     special_exit
GET_SELECTIVE
        lea     selmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        lea     select,a5
        bsr     PICK_PARAMETER
        rts

select  dc.w    0          
        dc.w    0,1        
        dc.w    264        
        dc.w    36,9,0,50  
selmsg  dc.w    5,6,16
        dc.b    'Selective Copy: '

CONSOLE_GREEN_MESSAGE
        move.l  a1,-(SP)
        moveq   #4,d1
        bsr     CONSOLE_INK
        move.l  (SP)+,a1
        bsr     CONSOLE_MESSAGE
        moveq   #7,d1
        bsr     CONSOLE_INK
        rts

CONSOLE_YESNO_MESSAGE
        moveq   #7,d1
        bsr     CONSOLE_INK
        lea     yesnomsg,a1
        bsr     CHANNEL_MESSAGE
        rts
yesnomsg        dc.w    6
                dc.b    'YES NO'

*PAGE           WINDOW DESCRIPTIONS
conid   dc.l    0                       ; CONSOLE id & description
condesc dc.b    2,1                     ; ... border colour/width
        dc.b    0,6                     ; ... paper/ink colours
        dc.w    436,72                  ; ... width,height
        dc.w    38,40                   ; ... x/y origins
actid   dc.l    0                       ; ACTION id & description
actdesc dc.b    2,1             
        dc.b    0,4             
        dc.w    436,22          
        dc.w    38,114          
scrid   dc.l    0                       ; SCREEN id & description
scrdesc dc.b    0,2             
        dc.b    0,4             
        dc.w    440,84          
        dc.w    40,138          
errid   dc.l    0                       ; ERROR id & description
errdesc dc.b    0,1             
        dc.b    0,4             
        dc.w    436,22          
        dc.w    38,224          
        END
