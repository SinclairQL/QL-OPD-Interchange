******************************************************************
**                       OPDCOPY:  Module 2                     **
**                                                              **
**      This module is responsible for the following tasks:     **
**              - Formatting                                    **
**              - Backing up software                           **
**                                      LAST UPDATED: 08/10/86  **
******************************************************************

        xdef    COPY_MASTER,FORMAT_TARGET,OPEN_CLOSE_TARGET_DIR
        xdef    tapeid,srcmed,header,backflg

*       Externals in OPDCOPY1

        xref    QUIT, COPY_TAPE,destchan,srcchan
        xref    devicetable,devicecount,fileheader,filestart,fileend
        xref    OPEN_FILE,CLOSE_FILE,OPEN_DIR
        xref    SET_DESTINATION_TYPE,SET_TARGET_HEADER
        xref    ALLOCATE_MEMORY,RELEASE_MEMORY_FIRST
        xref    OPEN_SOURCE_DIR,dirchan,sourcename,targetname
        xref    SCREEN_ERROR_TEXT,SCREEN_QDOS_ERROR
        xref    errorcount,notcount,okcount,maxdrv

*       Externals in OPDCOPY5

        xref    CONSOLE_GREEN_MESSAGE, CONSOLE_YESNO_MESSAGE
        xref    GET_SELECTIVE, GET_TARGET_DETAILS, DISPLAY_SOURCE
        xref    scrid,conid,select,medium
        xref    srcdrv,srctyp,destfmt,destdrv,desttyp
        
*       Externals in OPDSUBS

        xref    PICK_PARAMETER,SHOW_PARAMETER,DRIVE_LIST
        xref    CONSOLE_MESSAGE,CLEAR_CONSOLE_LINE
        xref    SCREEN_MESSAGE,SCREEN_NEWLINE
        xref    ACTION_MESSAGE,ERROR_MESSAGE,CHANNEL_MESSAGE
        xref    BEEP1, BEEP2, BEEP3, OPD_SPIN, QL_SPIN
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
$INCLUDE        flp1_asmlib_channels
$INCLUDE        flp1_asmlib_files
$INCLUDE        Flp1_asmlib_QL_header
$INCLUDE        Flp1_asmlib_trap1
$INCLUDE        Flp1_asmlib_trap2
$INCLUDE        flp1_asmlib_trap3
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_system
$INCLUDE        Flp1_asmlib_errors
*LIST
*PAGE           PHYSICAL LEVEL ROUTINES
********************************************************************
**                                                
**              P H Y S I C A L     L E V E L     
**                                                
**      (Some shared routines also in OPDSUBS)
********************************************************************

OPEN_CLOSE_TARGET_DIR
        move.w  desttyp,d0
        move.w  destdrv,d1
        lea     targetname,a0
        lea     dirchan,a1
        bsr     OPEN_DIR
        lea     dirchan,a1
        bsr     CLOSE_FILE
        rts

*PAGE           FORMATTING ROUTINES
********************************************************************
*       
*       This routine is used to format the target drive (if this
*       has been requested in 'destfmt'.
*
********************************************************************

FORMAT_TARGET
        move.w  destfmt,d0              ; see if format required
        beq.s   check_format
        moveq   #0,d0
        rts
        
check_format
        bsr     SCREEN_NEWLINE
        move.w  desttyp,d1              ; check for floppy disc type
        cmpi.w  #1,d1
        bgt     @4
        moveq   #2,d1
        bsr     CONSOLE_INK
        move.w  destdrv,d3
        lea     header,a5               ; set sector hdr buffer address
        bsr     opd_spin
        bra.s   @1
        lea     fmtopdmsg,a1
        bra.s   @2
@1      move.w  destdrv,d3
        lea     header,a5               ; set sec. hdr buffer address
        bsr     ql_spin
        bra.s   @4
        lea     fmtqlmsg,a1
@2      bsr     CONSOLE_MESSAGE
        lea     fmtmsg2,a1
        bsr     CHANNEL_MESSAGE
        moveq   #7,d1
        bsr     CONSOLE_INK
        lea     header,a1
        move.w  #10,(a1)
        bsr     CHANNEL_MESSAGE
@3      bsr     BEEP2
        lea     fmtmsg3,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        lea     fmtyesno,a5
        clr.w   (a5)                    ; preset answer to YES
        bsr     PICK_PARAMETER
        move.l  d0,-(SP)                ; save reply condition
        lea     fmtopdmsg,a1
        bsr     CLEAR_CONSOLE_LINE
        lea     fmtmsg3,a1
        bsr     CLEAR_CONSOLE_LINE
        move.l  (SP)+,d0                ; restore reply condition
        bne.s   try_again               ; ...ESC
        move.w  fmtyesno,d0
        bne.s   try_again
@4      bra     format_go

fmtopdmsg dc.w    5,2,3
          dc.b    'OPD '
fmtqlmsg  dc.w    5,2,2
          dc.b    'QL'
fmtmsg2   dc.w    17
          dc.b    ' Tape in Target:  '
fmtyesno  dc.w    1
          dc.w    0,1
          dc.w    234
          dc.w    30,9,0,60
fmtmsg3   dc.w    6,1,18
          dc.b    ' Confirm Format:  '

try_again
        bsr     BEEP2
        lea     fmtmsg4,a1
        bsr     CONSOLE_GREEN_MESSAGE
        lea     fmtmsg4A,a1
        bsr     CHANNEL_MESSAGE
        lea     fmtretry,a5
        move.w  #0,(a5)                 ; preset answer to YES
        bsr     PICK_PARAMETER
        move.l  d0,-(SP)                ; save reply
        lea     fmtmsg4,a1
        bsr     CLEAR_CONSOLE_LINE
        move.l  (SP)+,d0                ; restore reply
        bne.s   @1                      ; ... ESC, treat as NO
        move.w  fmtretry,d0
        cmpi.w  #1,d0                   ; NO answer ?
        beq.s   @1
        blt     format_target           ; YES answer ?
        moveq   #0,d0                   ; USE answer ?
        rts      
@1      moveq   #err_ff,d0
        rts

fmtretry dc.w   1
        dc.w    0,2
        dc.w    210
        dc.w    36,9,0,60
fmtmsg4 dc.w    6,2,14
        dc.b    'Retry Format: '
fmtmsg4A dc.w   12
        dc.b    ' YES  NO USE'
        
format_go
        lea     mediumname,a2
        moveq   #5,d0                   ; set device name length
        add.w   medium,d0
        move.w  d0,(a2)+
        lea     devicetable,a0
        move.w  desttyp,d0
        mulu    #6,d0                   ; convert to displacement
        move.l  2(a0,d0),(a2)           ; get text part
        addq.l  #3,a2                   ; skip over fixed part
        moveq   #'0',d0
        add.w   destdrv,d0
        move.b  d0,(a2)+                ; set drive
        move.b  #'_',(a2)+              ; ... and underscore

        move.w  medium,d0
        subq    #1,d0
        lea     medium,a1
        addq.l  #2,a1
@2      move.b  (a1)+,(a2)+
        dbra    d0,@2

@6      bsr     ACTION_LARGE_WIDE
        lea     fmtmsg11,a1
        bsr     ACTION_MESSAGE
        bra.s   do_format
        
fmtmsg11 dc.w   18
         dc.b    '    ... formatting'

do_format
        move.w  tapeid,d0               ; specific tape id required ?
        beq.s   @2                      ; ... NO, jump
        move.w  d0,sv_rand(a6)          ; set required tape id
@2      moveq   #IO_FORMT,d0            ; FORMAT medium trap
        lea     mediumname,a0           ; set name pointer
        TRAP    #2
        tst.l   d0
        beq.s   format_worked

*       format failed

format_failed
        bsr     SCREEN_QDOS_ERROR
        bra     try_again
        
*       format worked - check tape id if necessary

format_worked
        move.w  d1,-(SP)                ; save Total Sectors
        move.w  d2,-(SP)                ; save Good sectors
        bsr     OPEN_CLOSE_TARGET_DIR
        move.b  tapeid,d0               ; is security check required ?
        beq.s   format_results          ; ... NO, then jump
        move.w  destfmt,d0              ; OPD tape ?
        beq.s   format_results          ; ... can't do
        move.w  srctyp,d0
        move.w  srcdrv,d1
        bsr     FIND_PHYSICAL
        move.l  fs_mname+10(a2),d1      ; get actual id
        cmp.w   tapeid,d1               ; is it desired id ?
        beq.s   format_results          ; ... YES, continue
        addq.l  #4,SP                   ; remove total/good from stack
        moveq   #2,d1
        bsr     SCREEN_INK
        lea     fmtxidmsg,a1
        bsr     SCREEN_MESSAGE
        bsr     BEEP1
        bra.s   do_format               ; ... and repeat format

fmtxidmsg       dc.w    34
                dc.b    'REFORMATTING: Tape Id check failed'

*       Output the details of the successful format
        
format_results
        moveq   #4,d1                   ; green ink
        bsr     SCREEN_INK
        lea     fmtmsg14,a1
        bsr     SCREEN_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK
        lea     mediumname,a1
        bsr     CHANNEL_MESSAGE
        move.w  tapeid,d0               ; is tape id check required
        beq.s   @6                      ; ... NO, then jump
        moveq   #2,d1                   ; change to red ink
        bsr     SCREEN_INK
        lea     fmtidmsg,a1
        bsr     SCREEN_MESSAGE
        move.w  tapeid,d1
        move.w  UT_MINT,a2
        jsr     (a2)
@6      moveq   #4,d1
        bsr     SCREEN_INK             ; green ink
        lea     fmttotalmsg,a1
        bsr     SCREEN_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK
        move.w  UT_MINT,a2
        move.w  (a7)+,d1
        jsr     (a2)

        moveq   #4,d1
        bsr     SCREEN_INK
        lea     fmtgoodmsg,a1
        bsr     SCREEN_message
        moveq   #7,d1
        bsr     SCREEN_INK
        move.w  UT_MINT,a2
        move.w  (a7)+,d1
        jsr     (a2)
        moveq   #0,d0
        rts

fmtmsg14 dc.w   12
         dc.b    'FORMATTED:  '
fmtidmsg        dc.w    14
                dc.b    '     Tape Id: '
fmttotalmsg     dc.w   18
                dc.b   '  Total Sectors = '
fmtgoodmsg      dc.w   18
                dc.b   '  Good  Sectors = '
*PAGE           BACKUP ROUTINES
********************************************************************
*
*       This routine is used to create valid Copies of the Master
*       (AND to make the Original Masters)
*
*******************************************************************

COPY_MASTER
        lea     opdfile,a0
        lea     filechan,a1
        moveq   #0,d3                   ; set to read (exclusive)
        bsr     OPEN_FILE
        beq.s   opd_file_found
not_master
        lea     backflg,a1
        sf      (a1)
        moveq   #0,d0
        rts
opdfile dc.w    14
        dc.b    'Flp1_OPDdriver'

*       Find out the device type that is being used

opd_file_found
        lea     opdfile,a1 
        lea     devname,a0
        move.l  opdfile+2,2(a0)         ; set required string
        move.w  devicecount,d1          ; get highes device type
        mulu.w  #6,d1                   ; convert to displacement
        lea     devicetable,a1
@1      movem.l d1/a0-a1/a6,-(SP)       ; save registers
        lea     0(a1,d1.w),a1           ; set comparison string
        suba.l  a6,a6                   ; A6 relative
        moveq   #1,d0                   ; case independent
        move.w  UT_CSTR,a2
        jsr     (a2)
        movem.l (SP)+,d1/a0-a1/a6
        beq.s   @2                      ; ... YES, exit loop
        subq.w  #6,d1
        bpl.s   @1
@2      divu    #6,d1                   ; convert back to value
        lea     srctyp,a0
        move.w  d1,(a0)                 ; set default device type
        
*       Get the medium details

        moveq   #FS_MDINF,d0
        moveq   #-1,d3
        move.l  filechan,a0
        lea     opdheader,a1
        TRAP    #3
        lea     oldkeys,a1              ; set up expected key
        move.b  #'M',(a1)
        eor.b   d1,(a1)+
        move.b  d1,(a1)+

        move.b  sv_mddid(a6),d2         ; get drive id
        lea     sv_fsdef(a6),a2
        move.l  0(a2,d2.w),a2           ; get physical def
        move.w  fs_mname+10(a2),(a1)    ; save tape code number
        moveq   #FS_HEADR,d0            ; get header
        moveq   #64,d2
        moveq   #-1,d3
        lea     opdheader,a1
        TRAP    #3
        lea     filechan,a1
        bsr     CLOSE_FILE

*       Check the header against the keys.
*       NOTE.   A value of all zeroes in the header is treated
*               as valid at this stage, and it is assumed that a master
*               tape is to be made.

master_check
        lea     opdheader,a1
        lea     newkeys,a3
        move.b  #'C',(a3)               ; preset to copy
        move.b  10(a1),d1
        bne.s   @3
        move.b  #'M',(a3)               ; change to master
        lea     masterflg,a1
        st      (a1)                    ; set flag to say making master
        lea     oldkeys,a1
        clr.l   (a1)
        bra.s   master_found
@3      cmp.b   oldkeys,d1
        bne     not_master

master_found
        lea     backflg,a0
        sf      (a0)
        lea     desttyp,a0
        clr.w   2(a0)                   ; allow OPD type
        move.w  #240,6(a0)              ; reset toggle address
        bsr     CONSOLE_LARGE
        moveq   #2,d1
        bsr     CONSOLE_INK
        lea     cmsg3,a1
        bsr     CONSOLE_MESSAGE
        bsr     CONSOLE_NORMAL
        lea     cmsg4,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
@4      bsr     BEEP2
        lea     copyyn,a5
        bsr     PICK_PARAMETER
        bne.s   @8                      ; ... ESC, treat as NO
        move.w  copyyn,d0
        beq.s   get_backup_details
@8      moveq   #0,d0
        bra     master_abandon

cmsg3   dc.w    0,2,30
        dc.b    'Master copy of OPD/QL Software'
copyyn  dc.w    0
        dc.w    0,1
        dc.w    204
        dc.w    36,9,0,40
cmsg4   dc.w    4,1,16
        dc.b    ' Make a Backup: '

get_backup_details
        lea     backflg,a0              ; set backup mode flag
        st      (a0)
        bsr     DISPLAY_SOURCE
        lea     desttyp,a0
        move.w  #1,2(a0)                ; prohibit OPD type
        move.w  #288,6(a0)              ; ...and adjust toggle address
@2      bsr     GET_TARGET_DETAILS
        bne     master_found
        lea     desttyp,a0
        clr.w   2(a0)                   ; allow OPD type
        move.w  #240,6(a0)              ; reset toggle address
        lea     select,a1
        move.w  #1,(a1)                 ; set default to NO
        bsr     GET_SELECTIVE
        bne.s   @2        
        
*       If a master copy, then get the issue code number

master_code
        lea     codebuf,a1
        lea     opdheader,a2
        move.l  6(a2),(a1)              ; save current value
        move.b  masterflg,d1            ; making MASTER ?
        beq     master_format           ; ... NO, then start backup
        lea     codemsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     BEEP2
        moveq   #IO_FLINE,d0
        moveq   #8,d2
        moveq   #-1,d3
        move.l  conid,a0
        lea     codebuf,a1              ; get new value
        TRAP    #3
        
        move.w  cn_dtoi,a2              ; ASCII to long integer vector
        move.l  a1,d7                   ; set buffer end
        subq.l  #1,d7                   ; ... but ignore LF
        lea     codebuf,a0              ; buffer address
        move.l  a6,-(a7)                ; save system variables pointer
        sub.l   a6,a6                   ; relativise addresses to a6
        link    a1,#-30                 ; reserve stack space
        jsr     (a2)                    ; ... got to convert
        lea     codebuf,a2
        clr.l   (a2)                    ; clear code buffer
        tst.b   d0
        bne.s   @2
        move.w  (a1)+,(a2)              ; save answer
@2      unlk    a1
        move.l  (a7)+,a6                ; restore A6
        
        lea     codemsg,a1
        bsr     CLEAR_CONSOLE_LINE
        moveq   #4,d1
        bsr     SCREEN_INK
        lea     codemsg+4,a1
        bsr     SCREEN_MESSAGE
        moveq   #7,d1                   ; white ink
        bsr     SCREEN_INK
        move.w  codebuf,d1
        move.w  UT_MINT,a2
        jsr     (a2)
        bra.s   master_format

codemsg dc.w    6,9,15
        dc.b    'Serial Number:  '

*       Format & copy tape

master_format
        bsr     COPY_TAPE
        beq.s   master_copy_ok
master_abandon
        move.b  masterflg,d1            ; master flag set?
        bne.s   @2                      ; ... YES, continue
        move.b  backflg,d1              ; backup flag set
        bne.s   @2                      ; ... yes, then continue
        moveq   #0,d0                   ; ... NO, clear error condition
        bra.s   @9                      ; ... and exit
@2      move.l  d0,-(a7)                ; save error code
        tst.l   d0
        beq.s   @3
        bsr     SCREEN_NEWLINE
        move.l  (a7),d0                 ; restore error code
        move.w  UT_ERR,a2               ; output reason
        move.l  scrid,a0
        jsr     (a2)
        bsr     SCREEN_NEWLINE
@3      lea     cmsg2,a1
        bsr     ERROR_MESSAGE
        bsr     RELEASE_MEMORY_FIRST
        move.l  (a7)+,d0                ; restore error code
@9      rts

cmsg2   dc.w    32
        dc.b    10,'**** Backup Mode abandoned ****'

*       Open up copy of OPD Driver file

master_copy_ok
        lea     opdfile,a0
        bsr     SET_DESTINATION_TYPE
        lea     destchan,a1             ; store for channel id
        moveq   #0,d3                   ; old (exclusive) mode
        bsr     OPEN_FILE
        bne.s   master_abandon

*       Get new encryption keys

        moveq   #FS_MDINF,d0
        moveq   #-1,d3
        lea     fileheader,a1
        TRAP    #3
        lea     newkeys,a1              ; set up expected key 
        eor.b   d1,(a1)+
        move.b  d1,(a1)+

        move.w  desttyp,d0
        move.w  destdrv,d1
        bsr     FIND_PHYSICAL
        lea     newkeys+2,a1
        move.w  d1,(a1)                 ; save tape code number

*       Get file header

copy_get_header
        moveq   #FS_HEADR,d0
        moveq   #64,d2
        moveq   #-1,d3
        move.l  destchan,a0             ; channel id
        lea     fileheader,a1           ; buffer for file header
        TRAP    #3
        
*       Read in encrypted part of file

        moveq   #FS_POSAB,d0
        move.l  #ch_ql_read_header+10,d1 ; after table
        move.l  destchan,a0
        TRAP    #3
        
        move.w  #512,d1
        bsr     ALLOCATE_MEMORY
        moveq   #IO_FSTRG,d0
        move.w  #512,d2
        move.l  destchan,a0
        move.l  fileend,a1
        addq.l  #4,a1
        TRAP    #3
        tst.b   d0
        bne     master_abandon

*       De-encrypt & re-encrypt file

encryption
        move.l  oldkeys,d1
        move.l  newkeys,d3
        move.l  fileend,a2
        addq.l  #4,a2
        moveq   #127,d2
@4      eor.l   d1,(a2)                 ; decrypt
        eor.l   d3,(a2)+                ; re-encrypt
        dbra    d2,@4
              
*       Save encrypted file

        moveq   #FS_POSAB,d0
        move.l  #ch_ql_read_header+10,d1 ; after table
        move.l  destchan,a0
        TRAP    #3
        
        moveq   #IO_SSTRG,d0
        move.w  #512,d2
        move.l  destchan,a0
        move.l  fileend,a1
        addq.l  #4,a1
        TRAP    #3
        tst.b   d0
        bne     master_abandon
        bsr     RELEASE_MEMORY_FIRST
        
*       Store Tape type and issue code in file header & close file

        lea     fileheader,a1           ; buffer address
        move.l  codebuf,fh_user(a1)     ; serial number
        move.b  newkeys,fh_user+4(a1)   ; tape type
        bsr     SET_TARGET_HEADER

copy_wait_end
        move.b  sv_mdrun(a6),d0
        bne.s   copy_wait_end
        lea     cokmsg,a1
        bsr     ERROR_MESSAGE
        lea     copyyn,a1               ; get backup prompt
        move.w  #1,(a1)                 ; change default to NO
        bra     COPY_MASTER

cokmsg  dc.w    32
        dc.b    '   Copy of Master Tape completed'
*PAGE           D A T A     A R E A S
backflg         dc.b    0
masterflg       dc.b    0
filechan        ds.l    1
fileaddr        ds.l    1
codebuf         ds.l    2
oldkeys         dc.l    0
newkeys         dc.l    0
header          ds.b    16
opdheader       ds.b    64
srcmed          dc.w    10
                ds.b    14
tapeid          dc.w    0
mediumname      dc.w    0
                ds.b    16
        END
