*******************************************************************
**                      OPDCOPY1:  Main Copy Module              **
**                                                               **
**      This program is used to copy microdrive tapes from the   **
**      ICL OPD format to the Sinclair QL format, and vice versa **
**                                                               **
**                                      LAST AMENDED: 08/09/86   **
*******************************************************************

slavemem        equ     $5000   ; memory reserved for slaving use

*       Externals in OPDCOPY1  (used by other modules)

        xdef    QUIT, SUICIDE, COPY_TAPE, title
        xdef    OPEN_FILE, CLOSE_FILE
        xdef    OPEN_SOURCE_DIR, OPEN_DIR
        xdef    SET_DESTINATION_TYPE, SET_TARGET_HEADER
        xdef    ALLOCATE_MEMORY, RELEASE_MEMORY_FIRST
        xdef    filestart,fileend,dirchan,destchan,srcchan
        xdef    fileheader,sourcename,targetname
        xdef    errorcount,notcount,okcount
        
*       Externals in OPDCOPY2

        xref    GET_PARAMETERS,COPY_MASTER
        xref    CONSOLE_GREEN_MESSAGE, CONSOLE_YESNO_MESSAGE
        xref    FORMAT_TARGET
        xref    srcdrv,srctyp
        xref    destdrv,desttyp,destfmt
        xref    select,charflag,backflg

*       Externals in OPDCOPY3

        xref    FILE_CONVERT,FILE_CONVERT_COPY
        xref    ql_to_opd_table

*       Externals in OPDCOPY4

        xref    SELECT_FILE, CHECK_SPACE, EXPRESS_COPY, NOT_COPIED
        xref    SCREEN_ERROR_TEXT, SCREEN_QDOS_ERROR, NAME_CHECK
        xref    filemsg,selmsg,selyn, convert

*       Externals in OPDINIT

        xref    INITIALISATION
        xref    conid,scrid,actid,errid,error,opdflag,mode
        
*       Externals in OPDSUBS

        xref    SHOW_PARAMETER,PICK_PARAMETER
        xref    CONSOLE_MESSAGE,CLEAR_CONSOLE_LINE
        xref    CONSOLE_INK, ACTION_INK, SCREEN_INK, CHANNEL_INK
        xref    CHANNEL_NORMAL, ACTION_LARGE
        xref    ACTION_LARGE_WIDE, CHANNEL_LARGE_WIDE
        xref    CONSOLE_STRIP
        xref    CHANNEL_MESSAGE, CHANNEL_CLEAR_LINE
        xref    SCREEN_MESSAGE, SCREEN_NEWLINE
        xref    ACTION_MESSAGE, ERROR_MESSAGE
        xref    BEEP1,BEEP2,BEEP3

*       Externals in OPDEND

        xref    OPDEND

*NOLIST
$INCLUDE        Flp1_asmlib_QL_header
$INCLUDE        Flp1_asmlib_trap1
$INCLUDE        Flp1_asmlib_trap2
$INCLUDE        Flp1_asmlib_trap3
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_system
$INCLUDE        Flp1_asmlib_errors
*LIST
*PAGE           I N I T I A L I S A T I O N
*==================== C O D E     ST A R T ===========================

        bra.s   START
        ds.b    4
        dc.w    $4AFB
title   dc.w    7
        dc.b    'OPDCOPY '

$INCLUDE        Flp2_device_table_asm

        BRA     ql_to_opd_table
        

*       Set up the device count

START
        lea     devicecount,a0
        lea     srctyp,a1
        move.w  (a0),4(a1)
        lea     desttyp,a1
        move.w  (a0),4(a1)

        bsr     INITIALISATION          ; now standard initialisation
        bsr     COPY_MASTER             ; allow for backup
        bsr     TIDY_UP
        moveq   #SD_CLEAR,d0
        move.l  scrid,a0
        TRAP    #3
*PAGE        MAIN CONTROL LOOP
*---------------------------------------------------------------------
*       Main control loop
*---------------------------------------------------------------------

RESTART
@3      bsr     GET_PARAMETERS          ; prompt for parameters
        bne     QUIT                    ; ... if not, then quit
        moveq   #SD_CLEAR,d0
        move.l  scrid,a0
        TRAP    #3
        bsr     COPY_TAPE               ; copy tape
        bne     copy_abandoned

        lea     compmsg,a1              ; completed message
        bsr     ERROR_MESSAGE
        bsr     BEEP3
        moveq   #4,d1
        bsr     SCREEN_INK
        moveq   #SD_CLEAR,d0
        TRAP    #3
        bsr     SCREEN_NEWLINE
        bsr     CHANNEL_LARGE_WIDE
        pea     okmsg
        move.w  okcount,-(SP)
        bsr.s   @8
        pea     errmsg
        move.w  errorcount,-(SP)
        bsr.s   @8
        pea     ncpymsg
        move.w  notcount,-(SP)
        bsr.s   @8
        bsr     CHANNEL_NORMAL
        lea     contmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        lea     continue,a5
        move.w  #1,(a5)                 ; preset to NO
        bsr     PICK_PARAMETER
        bne     SUICIDE
        move.w  continue,d0
        bne     SUICIDE

        moveq   #SD_CLEAR,d0
        move.l  scrid,a0
        TRAP    #3
        bsr     TIDY_UP
        bra     RESTART

*       Output one line of copy report - parameters on stack
*                                       Word - count
*                                       Long - message address

@8      moveq   #4,d1
        bsr     SCREEN_INK
        lea     fillmsg,a1
        bsr     SCREEN_MESSAGE
        move.l  6(SP),a1
        bsr     CHANNEL_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK
        move.w  4(SP),d1
        move.w  UT_MINT,a2
        jsr     (a2)
        move.l  (SP)+,a2                ; get return address
        addq.l  #6,SP                   ; remove parameter fields
        jmp     (a2)
        
compmsg dc.w    22
        dc.b    '        COPY COMPLETED'
fillmsg dc.w    4
        dc.b    '    '
okmsg   dc.w    12
        dc.b    'Copied OK   '
errmsg  dc.w    12
        dc.b    'Copy failed '
ncpymsg dc.w    12
        dc.b    'Not copied  '
copy_abandoned
        lea     abanmsg,a1              ; abandoned message
        bsr     ERROR_MESSAGE
        bsr     BEEP3
        bra     RESTART
abanmsg dc.w    22
        dc.b    '        COPY ABANDONED'

continue dc.w    1
        dc.w    0,1             
        dc.w    324
        dc.w    36,9,0,50
contmsg dc.w    5,1,26
        dc.b    'ANOTHER CARTRIDGE TO COPY '
*PAGE
*----------------------------------------------------------
*       Tidy Up all files open and memory allocated
*----------------------------------------------------------

TIDY_UP
@1      move.l  filestart,d1             ; see if any file areas allocated
        beq.s   @2                      ; jump if not
        bsr     RELEASE_MEMORY_FIRST
        bra.s   @1

@2      lea     dirchan,a1
        bsr     CLOSE_FILE
        lea     srcchan,a1
        bsr     CLOSE_FILE
        lea     destchan,a1
        bsr     CLOSE_FILE

        lea     errorcount,a1           ; clear count fields
        clr.w   (a1)
        lea     notcount,a1
        clr.w   (a1)
        lea     okcount,a1
        clr.w   (a1)
        rts              
*PAGE           CLOSEDOWN ROUTINES
*----------------------------------------------------------------------
*       Closedown routines
*----------------------------------------------------------------------

*       Check whether closedown really meant

QUIT
        moveq   #SD_CLEAR,d0
        move.l  conid,a0
        trap    #3
        lea     quitmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        bsr     BEEP1
        lea     quityn,a5
        move.w  #0,(a5)                 ; preset answer to YES
        bsr     PICK_PARAMETER
        beq.s   @2
        bsr.s   TIDY_UP
        bra     RESTART                 ; ESC ... treat as NO
@2      move.w  quityn,d1
        bne     restart
        moveq   #0,d0
        bra.s   SUICIDE

quityn  dc.w    1
        dc.w    0,1             
        dc.w    264
        dc.w    36,9,0,30
quitmsg dc.w    3,1,21
        dc.b    'Confirm quit please:  ' 

*PAGE
*       This routine outputs any error message in d0 to screen channel
*       and then terminates the program.
*       NOTE. Common Heap Areas and channels open will be released
*       ~~~~  automatically when job is removed.

SUICIDE
        move.l  d0,-(a7)                ; save error code (if any)
        bsr     SCREEN_QDOS_ERROR
        bsr     TIDY_UP
        moveq   #SD_CLEAR,d0
        move.l  scrid,a0
        TRAP    #3
        moveq   #SD_CLEAR,d0
        move.l  conid,a0
        TRAP    #3
        move.b  opdflag,d1              ; see if loaded OPD Driver
        beq.s   @2                      ; ... no, then jump
        lea     opdend,a2
        clr.l   6(a2)                   ; set to run as subroutine
        bsr     OPDEND                  ; ... then call close routine
        lea     endmsg,a1
        bsr     CONSOLE_MESSAGE
@2      bsr     ACTION_LARGE
        lea     byemsg,a1
        bsr     ACTION_MESSAGE
        moveq   #MT_FRJOB,d0            ; force remove trap
        move.l  (a7)+,d3                ; set error condition
        moveq   #-1,d1                  ; ... this job
        TRAP    #1

endmsg  dc.w    3,4,24
        dc.b    'OPD Driver Code unloaded'
byemsg  dc.w    20
        dc.b    '         Closed Down'
*PAGE           MAIN FILE COPY ROUTINES
*---------------------------------------------------------------------
*       This routine controls the copying of a whole tape
*
*       If possible, complete files are loaded into store, and then
*       complete files writen.  Files will be loaded into memory
*       until either all files are loaded, OR the free store drops
*       below the minimum allowed for.
*
*       The alternative (but slower) copying method will be used
*       for files that will not fit into store.
*---------------------------------------------------------------------
COPY_TAPE        
        bsr     FORMAT_TARGET
        bne.s   @8                      ; ...format failed!!
        moveq   #SD_CLEAR,d0
        move.l  actid,a0
        trap    #3
        bsr     OPEN_SOURCE_DIR         ; open source directory
@8      bne     copy_tape_exit          ; ... no, then fatal error
        bsr     SCREEN_NEWLINE
copy_file
        bsr     GET_FILE                ; attempt to load files
@0      cmpi.b  #ERR_EF,d0              ; End of directory ?
        beq.s   @1                      ; ... YES, go to write files
        cmpi.b  #ERR_OM,d0              ; out of memory
        bne.s   copy_tape_error         ; ... NO, error exit
@1      move.l  filestart,d1            ; see if any files stored
        beq.s   @4                      ; ... if not, then jump
        move.l  d0,-(a7)                ; save error code
        bsr     SAVE_FILES              ; write away saved files
        beq.s   @2                      ; OK, then jump
        addq.l  #4,SP                   ; remove stored error code
        rts                             ; ... and exit immediately
@2      move.l  (SP)+,d0                ; restore original error code
        cmpi.b  #ERR_OM,d0
        bne.s   @7
        bsr     SCREEN_NEWLINE
        bsr     GET_FILE_RETRY
        bra.s   @0        
@4      cmp.b   #ERR_OM,d0              ; not enough memory ?
        beq.s   @8                      ; ... YES, jump
        cmpi.b  #ERR_EF,d0
        bne.s   copy_tape_complete
@7      moveq   #0,d0                   ; ... NO, must be directory end
        bra.s   copy_tape_complete
@8      bsr     SLOW_COPY
        bne.s   copy_tape_exit          ; ERROR, then exit
        bra.s   copy_file

copy_tape_error
        bsr     SCREEN_QDOS_ERROR
copy_tape_complete
        move.l  d0,-(SP)
        lea     dirchan,a1
        bsr     CLOSE_FILE
        move.l  (SP)+,d0
copy_tape_exit
        tst.l   d0                     ; set reply condition
        rts
*PAGE
*---------------------------------------------------------------------
*       These routines are concerned with getting the next file into
*       store if at all possible.
*---------------------------------------------------------------------

GET_FILE
        lea     largestsze,a1           ; largest file to date
        clr.l   (a1)                    ; ... = none !

next_file
        bsr     READ_FILE_HEADER
        bne     get_file_exit

GET_FILE_RETRY
        move.l  fileheader,d1           ; get wanted store area
        lea     largestsze,a1
        cmp.l   (a1),d1                 ; largest file  so far ?
        ble.s   @1                      ; ... NO, then jump
        move.l  d1,(a1)                 ; ... YES, reset largest
@1      move.l  sv_basic(a6),d0         ; end of free store area
        sub.l   sv_free(a6),d0          ; ... - start=total free store
        sub.l   #slavemem,d0            ; ... - slave memory work area
        cmp.l   d0,d1                   ; enough store for next file?
        ble.s   @4                      ; ... yes then jump
        moveq   #ERR_OM,d0              ; ... no set out of memory exit
        rts
      
@4      add.l   #64+2,d1                ; add header to file size
        bsr     ALLOCATE_MEMORY         ; get memory OK ?
        bne     get_file_exit           ; ... NO, then exit

        move.l  fileend,a0              ; get save area
        addq.l  #4,a0                   ; get conversion flag address
        move.w  convert,(a0)            ; ...store it
        addq.l  #2,a0                   ; start of file header area
        moveq   #15,d0                  ; 64 bytes
        lea     fileheader,a2
@5      move.l  (a2)+,(a0)+             ; move header to save area
        dbra    d0,@5

*       Load complete file

        bsr     READING
        bsr     OPEN_SOURCE_FILE
        moveq   #4,d1
        bsr     SCREEN_INK
        lea     loadmsg,a1
        bsr     SCREEN_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK
        lea     sourcename,a1
        bsr     CHANNEL_MESSAGE
        moveq   #FS_LOAD,d0             ; load file trap
        move.l  fileheader,d2           ; length
        moveq   #-1,d3                  ; timeout
        move.l  fileend,a1              ; buffer address
        add.w   #[64+4+2],a1            ; ... after header/link data
        move.l  srcchan,a0              ; channel id
        trap    #3
        tst.l   d0
        beq.s   @8

*       If load failed, try ordinary read mode

        moveq   #FS_POSAB,d0
        moveq   #0,d0                   ; start of file
        moveq   #-1,d3
        TRAP    #3
        move.l  fileheader,d5           ; length required
        move.l  fileend,a1              ; file area address
        add.w   #[64+4+2],a1            ; ... after file header space

@6      tst.l   d5                      ; check length left
        beq.s   @8                      ; zero
        moveq   #IO_FSTRG,d0            ; set for string read
        moveq   #64,d2                  ; length of 64 bytes
        lsl.l   #4,d2                   ; ...... * 16 = 1024
        cmp.l   d2,d5                   ; more than left ?
        bge.s   @7                      ; ... NO, jump
        move.l  d5,d2                   ; ... YES, set to length left
@7      sub.l   d2,d5                   ; reduce length left
        TRAP    #3
        tst.l   d0
        beq.s   @6                      ; loop for more
        
*       Close file

@8      move.l  d0,-(SP)                ; save error code
        lea     srcchan,a1
        bsr     CLOSE_FILE
        move.l  (SP)+,d0                ; restore error code
        beq     next_file               ; ... NONE, go for next file

*       If both load attempts failed, then output error message
*       and remove file from loaded list

        lea     lerrmsg,a1
        bsr     SCREEN_ERROR_TEXT
        bsr     SCREEN_QDOS_ERROR
        bsr     BEEP1
        bsr     RELEASE_MEMORY_LAST
        lea     fileheader+14,a1
        bsr     NOT_COPIED
        lea     errorcount,a1
        addq.w  #1,(a1)
        bra     next_file
        
*       Exit setting condition codes

get_file_exit
        move.b  d0,d0                   ; set reply condition
        rts

largestsze      dc.l    0
loadmsg dc.w    12
        dc.b    'LOADING.....'
lerrmsg dc.w    20
        dc.b    '    File Load Failed'
*PAGE
*---------------------------------------------------------------------
*       This routine takes each of the saved files,  writes them to
*       the target drive, then release the allocated space
*----------------------------------------------------------------------

SAVE_FILES
        bsr     SCREEN_NEWLINE
@1      move.l  filestart,d1            ; any files saved ?
        bne.s   @2                      ; ... No, then continue
        moveq   #0,d0                   ; ... YES, set OK exit
        rts

@2      move.l  filestart,a5            ; start of next file area
        add.w   #8+2,a5                 ; update to file header
        bsr     SET_TARGET_FILENAME
        lea     targetname,a5
        bsr     NAME_CHECK
        moveq   #4,d1
        bsr     SCREEN_INK
        lea     savemsg,a1              ; 'SAVING' message
        bsr     SCREEN_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK
        lea     targetname,a1
        bsr     CHANNEL_MESSAGE
        bsr     WRITING

        bsr     FILE_CONVERT            ; File conversion
        bsr     OPEN_TARGET
        beq.s   @4                      ; ... OK, so continue
        cmpi.b  #ERR_NC,d0              ; Not Complete error ?
        beq.s   @6                      ; ... YES, go to release store
        rts                             ; ... NO, exit

@4      moveq   #FS_SAVE,d0             ; save file trap
        move.l  filestart,a1
        add.w   #8+2,a1                 ; set to fileheader start
        move.l  (a1),d2                 ; length of file
        moveq   #-1,d3                  ; timeout
        move.l  destchan,a0
        lea     64(a1),a1               ; start of data part of file
        TRAP    #3
        tst.b   d0
        beq.s   @5
        lea     errorcount,a1
        addq.w  #1,(a1)
        bra     SCREEN_QDOS_ERROR

@5      move.l  filestart,a1
        add.w   #8+2,a1
        bsr     SET_TARGET_HEADER
        lea     okcount,a1
        addq.w  #1,(a1)
        
@6      bsr     RELEASE_MEMORY_FIRST
        bne.s   @9                      ; ... EXIT if error
        move.l  filestart,d1            ; any more ?
        bne     @2                      ; ... YES, go for next
        bsr     VERIFYING               ; ... NO, wait until drive stop
        moveq   #0,d0                   ; set OK return
@9      move.b  d0,d0                   ; set return code
        rts
savemsg dc.w    12
        dc.b    'SAVING......'
*PAGE
*---------------------------------------------------------------------
*       This routine copies files that are too big to fit into memory
*       all at once.  It reads in part of a file, and then writes out
*       that part. This is repeated until the file is completely
*       written.
*---------------------------------------------------------------------

SLOW_COPY
        
*       Output message for file to be processed

        bsr     OPEN_SOURCE_FILE
        bne     slow_error
        lea     fileheader,a5
        bsr     SET_TARGET_FILENAME
        lea     targetname,a5
        bsr     NAME_CHECK
        moveq   #4,d1
        bsr     SCREEN_INK
        bsr     SCREEN_NEWLINE
        lea     slowmsg,a1
        bsr     SCREEN_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK
        lea     fileheader+14,a1
        bsr     CHANNEL_MESSAGE

*       Allocate work area

slowmem move.l  sv_basic(a6),d1         ; top of free store
        sub.l   sv_free(a6),d1          ; - start = size
        sub.l   #slavemem,d1            ; - area for slaving
        cmp.l   maxsize,d1              ; see if > Word length (32Kb)
        ble.s   @2                      ; ... NO, then OK
        move.l  maxsize,d1              ; ... YES, then reset
@2      lea     slowsze,a1
        move.l  d1,(a1)                 ; store size        
        add.l   #64+8+2,d1              ; allow for header fields
        bsr     ALLOCATE_MEMORY         ; allocate memory required
        beq.s   @4
        bsr     SCREEN_QDOS_ERROR
        bra     slow_error

*       Open Target File

@4      bsr     OPEN_TARGET
        beq.s   @7                      ; ... OK
        cmpi.b  #ERR_NC,d0              ; error = file not copied ?
        bne.s   @6                      ; ... NO, then leave alone
        moveq   #0,d0                   ; ... YES, change to OK exit
@6      rts

*       Move across Convert flag and File Header

@7      lea     fileheader,a1
        move.l  fileend,a2
        addq.l  #4,a2
        move.w  convert,(a2)+
        moveq   #[64/4-1],d0
@8      move.l  (a1)+,(a2)+
        dbra    d0,@8
        
*       Read in as much as possible, and then write it out

slowread
        bsr     READING
        moveq   #IO_FSTRG,d0
        move.l  slowsze,d2
        moveq   #-1,d3
        move.l  fileend,a1
        add.w   #4+64+2,a1              ; set buffer address
        move.l  srcchan,a0
        TRAP    #3
        tst.b   d0                      ; check it worked
        beq.s   slowwrite               ; ... YES, go to write it
        cmpi.b  #ERR_EF,d0              ; EOF condition ?
        bne.s   slow_end                ; ... NO, exit
        moveq   #0,d0                   ; EOF set as if no error
        tst.w   d1                      ; check something read in
        bne.s   @6
        lea     okcount,a1
        addq.w  #1,(a1)
        bra.s   slow_end_ok             ; ... NO, then exit
@6      bsr     FILE_CONVERT_COPY
slowwrite
        bsr     WRITING
        moveq   #IO_SSTRG,d0
        move.w  d1,d2 
        moveq   #-1,d3
        move.l  destchan,a0
        move.l  fileend,a1
        add.w   #4+64+2,a1              ; set buffer address
        TRAP    #3
        tst.b   d0                      ; Worked ?
        bne.s   @5                      ; ... NO
        move.w  desttyp,d0
        cmp.w   #1,d0
        bgt.s   @3
        move.w  srctyp,d0
        cmp.w   #1,d0
        bgt.s   @3
        move.w  desttyp,d0              ; get device type
        subq.w  #2,d0                   ; see if OPD/MDV
        bmi.s   @3                      ; ... NO
        bsr.s   VERIFYING               ; ... YES
@3      bra.s   slowread                ; go for more
@5      move.l  d0,-(SP)
        bsr     SCREEN_QDOS_ERROR
        bsr     RELEASE_MEMORY_FIRST
        move.l  (a7)+,d0                ; set return condition code
slow_error
        lea     errorcount,a1
        addq.w  #1,(a1)
        tst.l   d0
        rts

slow_end_ok
        lea     okcount,a1
        addq.w  #1,(a1)

*       De-allocate work area & Close target file

slow_end
        move.l  d0,-(a7)                ; save any error code
        move.l  fileend,a1
        addq.l  #4+2,a1                 ; set buffer address
        bsr     SET_TARGET_HEADER
        bsr     VERIFYING
        bsr     RELEASE_MEMORY_FIRST    ; release any memory allocated
        move.l  (SP)+,d0                ; restore error code
        rts
slowsze dc.l    $2000                   ; size of store area
maxsize dc.l    $7FFE                   ; max size allowed
slowmsg dc.w    12
        dc.b    'COPYING TO..'
*PAGE 
*--------------------------------------------------------------------
*       This routine waits till the target drive has stopped
*--------------------------------------------------------------------

VERIFYING
        tst.b   sv_mdrun(a6)            ; are drives running ?
        beq.s   @9                      ; ... NO, then exit
        bsr     ACTION_LARGE_WIDE
        lea     vermsg,a1               ; ... YES, then message
        bsr     ACTION_MESSAGE
@3      moveq   #MT_SUSJB,d0            ; suspend job trap
        moveq   #-1,d1                  ; this job
        moveq   #10,d3                  ; fifth of a second
        moveq   #0,d2                   ; no flag byte
        move.l  d2,a1
        TRAP    #1
        tst.b   sv_mdrun(a6)            ; have drives stopped
        bne.s   @3                      ; ... NO, then loop
@9      rts

vermsg  dc.w    20
        dc.b    '       ... verifying'

READING
        movem.l d0-d3/a0-a3,-(SP)
        bsr     ACTION_LARGE_WIDE
        lea     readmsg,a1
        bsr     ACTION_MESSAGE
        movem.l (SP)+,d0-d3/a0-a3
        rts
readmsg dc.w    18
        dc.b    '       ... reading'

WRITING
        movem.l d0-d3/a0-a3,-(SP)
        bsr     ACTION_LARGE_WIDE
        lea     writmsg,a1
        bsr     ACTION_MESSAGE
        movem.l (SP)+,d0-d3/a0-a3
        rts
writmsg dc.w    18
        dc.b    '       ... writing'
        
*PAGE
*----------------------------------------------------------------------
*       This routine reads a file entry from the directory, and than
*       opens the corresponding file and reads its header into store.
*----------------------------------------------------------------------

READ_FILE_HEADER
        moveq   #IO_FSTRG,d0            ; get byte trap
        moveq   #-1,d3                  ; timeout
        moveq   #64,d2                  ; set buffer length
        move.l  dirchan,a0              ; directory channel
        lea     fileheader,a1           ; buffer to use
        TRAP    #3
        tst.b   d0                      ; error ?
        beq.s   read_header_ok          ; ... NO, continue
        cmpi.b  #err_ef,d0              ; end of directory ?
        beq     read_header_exit        ; ... YES, exit
        lea     xdirmsg,a1              ; ... NO, error message
        bsr     SCREEN_ERROR_TEXT
        bra     SCREEN_QDOS_ERROR
xdirmsg dc.w    30
        dc.b    'ERROR READING SOURCE DIRECTORY'

read_header_ok
        lea     fileheader,a2
        tst.l   (a2)                    ; see if null entry
        beq.s   read_file_header        ; ... if so, go for next
        bsr     OPEN_SOURCE_FILE
        bne.s   read_header_exit

        moveq   #FS_HEADR,d0            ; read header trap
        moveq   #64,d2                  ; buffer lengh
        moveq   #-1,d3                  ; timeout
        lea     fileheader,a1           ; buffer
        TRAP    #3

        bsr     SELECT_FILE             ; file wanted ?
        move.l  d0,-(SP)
        lea     srcchan,a1              ; ... NO, then file closed
        bsr     CLOSE_FILE
        move.l  (SP)+,d0                ; file wanted ?
        bne     read_file_header        ; ... NO, go for next
read_header_exit
        tst.l   d0                      ; set reply condition code
        rts
*PAGE
*--------------------------------------------------------------------
*       Move filename from stored file header into 'sourcename'
*--------------------------------------------------------------------

OPEN_SOURCE_FILE
        lea     sourcename,a3
        lea     fileheader+14,a2
        move.w  (a2)+,d2                ; get file name length
        move.w  d2,(a3)                 ; ... and set it
        addq.w  #5,(a3)+                ; ... + Device name length
        addq.l  #5,a3                   ; skip over device name
        bra.s   @3
@2      move.b  (a2)+,(a3)+             ; move file name across
@3      dbra    d2,@2
        moveq   #0,d3                   ; Exclusive (old) file
        lea     sourcename,a0           ; file name
        lea     srcchan,a1              ; store for channel id
        bsr     OPEN_FILE
        rts
        
*--------------------------------------------------------------------
*       This routine sets the file header for the current target file
*       (pointed to by A1).  It then closes the target file
*--------------------------------------------------------------------

SET_TARGET_HEADER
        moveq   #FS_HEADS,d0            ; set header
        moveq   #-1,d3
        move.l  destchan,a0
        TRAP    #3
        lea     destchan,a1
        bsr     CLOSE_FILE
        rts
*PAGE           MEMORY CONTROL ROUTINES
*       Memory is allocated as required for each file.
*       A linked list of the memory areas is maintained.
*               'filestart'     = forward pointer
*               'fileend'       = backward pointer
*
*       Each file area is formatted as follows:
*               Bytes 0-3       Forward pointer (0=end of list)
*                     4-7       Backward pointer (0=end of list)
*                     8-9       Conversion Type required
*                    10-73      File Header
*                     74+       File data
*               
*--------------------------------------------------------------------
*       This routine allocates memory, and adds it to the end of the
*       list of alllocated areas.
*
*               ENTRY: 
*                     D1 = Size required in bytes
*--------------------------------------------------------------------

ALLOCATE_MEMORY
        moveq   #MT_ALCHP,d0            ; reserve common heap
        moveq   #-1,d2                  ; This job
        addq.l  #8,d1                   ; allow for link fields
        TRAP    #1                      ; go to get memory
        tst.b   d0                      ; Error ?
        bne.s   @9                      ; ... YES, then exit

*       Set forward pointer

        lea     filestart,a1            ; start list pointer
        move.l  fileend,d0              ; list empty ?
        beq.s   @2                      ; ... YES, then jump
        move.l  fileend,a1              ; get current last pointer
        subq.l  #4,a1                   ; adjust for forward pointer
@2      move.l  (a1),(a0)               ; set pointer to next
        move.l  a0,(a1)                 ; set pointer to this
        
*       Set backward pointer

        lea     fileend,a1              ; previous item (list start)
        addq.l  #4,a0                   ; this item (backward link)
        move.l  (a1),(a0)               ; set pointer to next
        move.l  a0,(a1)                 ; set pointer to this
        moveq   #0,d0                   ; set OK return
@9      rts
*PAGE        
*-------------------------------------------------------------------
*       These routines release memory from the doubly linked list
*       pointed to by:-
*               'filestart'     beginning of list
*               'fileend'       end of list
*-------------------------------------------------------------------

RELEASE_MEMORY_FIRST
        lea     filestart,a0
        tst.l   (a0)                    ; list empty ?
        bne.s   @2                      ; ... NO, continue
        rts
        
*       Remove backward pointer

@2      move.l  (a0),a0                 ; get item address into A0
        lea     fileend,a1              ; assume only item in list
        tst.l   (a0)                    ; is it ?
        beq.s   @4                      ; ... YES, jump
        move.l  (a0),a1                 ; ... NO, follow forward
        addq.l  #4,a1                   ; ... and get backward
@4      addq.l  #4,a0                   ; Set unlink item address
        move.l  (a0),(a1)               ; UNLINK from list
        
*       Remove forward pointer

        subq.l  #4,a0                   ; Restore forward pointer
        lea     filestart,a1            ; previous item
        move.l  (a0),(a1)               ; UNLINK
        bra.s   release_memory
        

RELEASE_MEMORY_LAST
        lea     fileend,a0
        tst.l   (a0)                    ; list empty ?
        bne.s   @2                      ; ... NO, continue
        rts
        
*       Remove forward pointer

@2      move.l  (a0),a0                 ; get item address into A0
        lea     filestart,a1            ; assume only item in list
        tst.l   (a0)                    ; is it ?
        beq.s   @4                      ; ... YES, jump
        move.l  (a0),a1                 ; ... NO, follow backward
        subq.l  #4,a1                   ; ... and get forward
@4      subq.l  #4,a0                   ; Set unlink item address
        move.l  (a0),(a1)               ; UNLINK from list
        
*       Remove backward pointer

        addq.l  #4,a0                   ; restore backward pointer
        lea     fileend,a1              ; previous item
        move.l  (a0),(a1)               ; UNLINK

Release_Memory
        moveq   #MT_RECHP,d0            ; release memory given by A0
        TRAP    #1
        tst.l   d0                      ; set return condition
        bne.s   @6
        rts
@6      lea     memrmsg,a1
        bsr     SCREEN_ERROR_TEXT
        bra     SCREEN_QDOS_ERROR

memrmsg dc.w    24
        dc.b    'FAILURE RELEASING MEMORY'
*PAGE           FILE OPEN/CLOSE ROUTINES
*--------------------------------------------------------------------
*       This routine adds the correct device type and number for the
*       destination file.
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       A0      Filename                Updated Filename
*--------------------------------------------------------------------

SET_DESTINATION_TYPE
        movem.l d0/a1,-(SP)
        move.w  desttyp,d0              ; get destination type
        mulu.w  #6,d0                   ; convert to displacement
        lea     devicetable,a1
        move.l  2(a1,d0.w),2(a0)        ; move to output name
        move.w  destdrv,d0              ; get drive
        add.w   #'0',d0                 ; convert to ASCII
        move.b  d0,5(a0)                ; store in output name
        movem.l (SP)+,d0/a1
        rts

*--------------------------------------------------------------------
*       This routine constructs the target filename .
*               ENTRY           EXIT
*               ~~~~~           ~~~~
*       A5      File Header
*       filename                output filename text
*--------------------------------------------------------------------

SET_TARGET_FILENAME
        movem.l d0/a0/a1/a2,-(SP)       ; save registers used
        lea     14(a5),a1               ; set pointer to name
        move.w  (a1)+,d0                ; get name length
        lea     targetname,a2
        move.w  d0,(a2)                 ; set name length
        addq.w  #5,(a2)+                ; plus Device name length
        addq.l  #4,a2                   ; skip over device part
        move.b  #'_',(a2)+              ; set underscore
        bra.s   @2     
@1      move.b  (a1)+,(A2)+             ; move file name
@2      dbra    d0,@1                   ; ... until finished
        lea     targetname,a0           ; name
        bsr     SET_DESTINATION_TYPE
        movem.l (SP)+,d0/a0/a1/a2       ; restore registers used
        rts
*PAGE        
*---------------------------------------------------------------------
*       This routine opens the target file given by 'filename'.
*
*       If any existing copy exists, then the user is asked whether
*       it should be overwritten.
*       
*       ERROR RETURNS:  ERR_NC          File not to be copied
*                       Others          QDOS Error
*
*---------------------------------------------------------------------

OPEN_TARGET
        lea     targetname,a0           ; file name
        lea     destchan,a1             ; address to store channel ID
        moveq   #2,d3                   ; new file
        bsr     OPEN_FILE               ; Open file
        beq.s   @9                      ; ...OK, so exit
        cmpi.b  #ERR_EX,d0              ; Exists error ?
        bne.s   @9                      ; ...NO, so exit
        lea     filemsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        lea     targetname,a1
        bsr     CHANNEL_MESSAGE
        lea     overmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        bsr     BEEP2
        lea     overyn,a5
        clr.w   (a5)                    ; preset answer to YES
        bsr     PICK_PARAMETER
        bne.s   open_target_fail
@7      lea     filemsg,a1
        bsr     CLEAR_CONSOLE_LINE
        lea     overmsg,a1
        bsr     CLEAR_CONSOLE_LINE
        move.w  overyn,d0               ; reply is yes
        bne.s   Open_Target_Fail        ; ... NO, then not copied
       
@8      moveq   #IO_DELET,d0            ; set for file delete
        lea     targetname,a0           ; of target file
        TRAP    #2
        tst.b   d0                      ; did it fail
        beq     open_target             ; ... NO, retry open
@9      rts
*PAGE
Open_Target_Fail
        lea     targetname,a1           ; filename
        bsr     NOT_COPIED
        bsr     BEEP1
        lea     errorcount,a1
        addq.w  #1,(a1)
        moveq   #ERR_NC,d0              ; set not completed
        rts

overyn  dc.w    0
        dc.w    0,1
        dc.w    180
        dc.w    36,9,0,60
overmsg dc.w    6,3,12
        dc.b    'Overwrite:  '
*PAGE
*---------------------------------------------------------------------
*       Open Source directory
*----------------------------------------------------------------------

OPEN_SOURCE_DIR
        move.w  srctyp,d0
        move.w  srcdrv,d1
        lea     sourcename,a0
        lea     dirchan,a1
        bsr.s   OPEN_DIR
        beq.s   @9
        move.l  d0,-(SP)
        lea     sdirmsg,a1
        bsr     SCREEN_ERROR_TEXT
        move.l  (SP)+,d0
@9      rts

sdirmsg dc.w    29
        dc.b    'FAIL OPENING SOURCE DIRECTORY '
        
*----------------------------------------------------------------------
*       Open a directory
*               ENTRY   D0      Drive Type
*                       D1      Drive Number
*                       A0      Address to store channel name
*                       A1      Address to store channel id
*----------------------------------------------------------------------

OPEN_DIR
        move.l  a0,a2                   ; copy name address
        lea     devicetable,a3          ; device name table
        mulu.w  #6,d0                   ; convert type to displacement
        move.w  #5,(a2)+                ; set length
        move.l  2(a3,d0),(a2)           ; set device name
@1      addq.l  #3,a2                   ; skip over fixed part
        add.b   d1,(a2)+                ; ... add drive number
        move.b  #'_',(a2)               ; ... add underscore
        moveq   #4,d3                   ; directory open mode
        bsr     OPEN_FILE
        rts
*PAGE
*---------------------------------------------------------------------
*       This routine opens a file.  A check is made to see if there
*       is already a file open , and if so it is closed
*               A0 = File Name
*               A1 = Location to store channel if successful
*               D3 = Mode
*---------------------------------------------------------------------
OPEN_FILE
        movem.l d3/a0/a1,-(SP)          ; save Open parameters
        bsr     CLOSE_FILE
        movem.l (SP)+,d3/a0/a1          ; restore Open parameters
        moveq   #IO_OPEN,d0
        moveq   #-1,d1                  ; this job
        move.l  a0,-(SP)                ; save name pointer
        move.l  a1,-(SP)                ; ... and channel store pointer
        TRAP    #2                      ; Open file
        move.l  (SP)+,a1                ; restore channel store
        cmpi.b  #ERR_EX,d0              ; already exists ?
        beq.s   @9                      ; ... YES, exit immediately
        tst.b   d0                      ; Did open work ?
        bne.s   @7                      ; ... NO, go for error message
        move.l  a0,(a1)                 ; ... YES, store channel
        bra.s   @9
@7      move.l  d0,-(a7)                ; save error code
        moveq   #2,d1
        bsr     SCREEN_INK
        lea     openmsg,a1
        bsr     SCREEN_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK
        move.l  4(SP),a1                ; get filename
        bsr     CHANNEL_MESSAGE
        move.l  (SP),d0
        bsr     SCREEN_QDOS_ERROR
        move.l  (SP)+,d0
@9      addq.l  #4,SP                   ; remove file name pointer
        tst.b   d0                      ; set return condition
        rts
openmsg dc.w    22
        dc.b    10,' Failed to open file '
*---------------------------------------------------------------------
*       This routine closes a file
*               A1 = Address containing channel (zero if no file open)
*---------------------------------------------------------------------
CLOSE_FILE
        move.l  d0,-(SP)                ; save any error code
        tst.l   (a1)                    ; see if channel open
        beq.s   @9                      ; ... NO, then jump
        moveq   #IO_CLOSE,d0
        move.l  (a1),a0                 ; set channel for close
        clr.l   (a1)                    ; clear stored channel
        moveq   #-1,d3                  ; timeout=forever
        TRAP    #2                      
@9      move.l  (SP)+,d0                ; restore error code/condition
        rts
*PAGE           D A T A    A R E A S
errorcount      dc.w    0               ; Error count
notcount        dc.w    0               ; Not copied count
okcount         dc.w    0               ; Copied OK count
dirchan         dc.l    0               ; Directory channel id
destchan        dc.l    0               ; Source    channel id
srcchan         dc.l    0               ; Target    channel id
filestart       dc.l    0               ; File list forward pointer
fileend         dc.l    0               ; File list backward pointer

sourcename      dc.w    0               ; area to construct target name
                ds.b    40
targetname      dc.w    0               ; area to construct source name
                ds.b    40
fileheader      ds.b    64
        END

