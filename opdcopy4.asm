*******************************************************************
**                      OPDCOPY4:  File Selection                **
**                                                               **
**      This module is responsible for the following tasks       **
**              - File Selection                                 **
**              - ERROR messages                                 **
**              - Express Copy                                   **
**                                      LAST AMENDED: 25/07/86   **
*******************************************************************

*       Externals in this module used by other modules

        xdef    EXPRESS_COPY, SELECT_FILE, NOT_COPIED, NAME_CHECK
        xdef    SCREEN_ERROR_TEXT, SCREEN_QDOS_ERROR
        xdef    selyn, filemsg, selmsg, copymsg, convert

*       Externals in OPDCOPY1

        xref    ALLOCATE_MEMORY,RELEASE_MEMORY_FIRST
        xref    errorcount,notcount,okcount
        xref    sourcename,srcchan,fileheader,targetname
        
*       Externals in OPDCOPY2

        xref    CONSOLE_GREEN_MESSAGE, CONSOLE_YESNO_MESSAGE
        xref    srcdrv,srctyp
        xref    destdrv,desttyp,destfmt
        xref    select, wcopy

*       Externals in OPDINIT

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

*NOLIST
$INCLUDE        Flp1_asmlib_QL_header
$INCLUDE        Flp1_asmlib_trap3
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_errors
*LIST
*PAGE           E X P R E S S    C O P Y
*--------------------------------------------------------------------
*       This routine is used when copying in unselective mode AND
*       both input and output medium are the same (OPDn or MDVn)
*
*       It works by doing a physical level block copy completely
*       by-passing the normal filing system interface
*
*           *****  N O T   Y E T    U S E A B L E  *****
*
*--------------------------------------------------------------------

EXPRESS_COPY

*       Check if mediums the same

*       Check if enough space on target

*       Allocate memory required

*       Set up fields to control this pass

*       Input routine

*       Output Routine

*PAGE           FILE SELECTION
*---------------------------------------------------------------------
*       This routine is used to check if you want to copy a file.
*
*       A number of checks are invoked.  Once a check has resulted
*       in the user being queried, then other queries will be
*       suppressed.
*
*       1) Wild Card copy check invoked.  
*       2) Check made on whether the file type is one that is not
*          normally compatible with the target machine.
*       3) IF file extension is PSION type, then first 20 bytes read to
*          allow XCHANGE compatibility to be checked. If necessary the
*          file extension will be changed for the destination file.
*       4) The 'select' flag examined to see if File Selection active.
*
*       'fileheader' contains relevant file-header
*       On exit filename in fileheader will have been updated if
*       necessary to name required on target machine.
*
*       ERROR RETURNS:  = 0     OK
*                      ERR_NC   File not to be copied
*                      Other    QDOS Error
*---------------------------------------------------------------------

SELECT_FILE
        lea     convert,a1
        clr.w   (a1)
        bsr     WILD_COPY_CHECK
        bne.s   @9
        bsr     TYPE_CHECK
        beq.s   @2
@1      lea     selyn,a0
        move.w  #1,(a0)                 ; preset answer to NO
        bra.s   COPY_QUERY_WARNING
@2      bsr     XCHANGE_CHECK
        bne.s   @1
        lea     selyn,a1
        clr.w   (a1)                    ; preset to YES
        move.w  select,d0               ; see if selection required
        bne.s   @5                      ; ... NO, then exit OK
        bra.s   COPY_QUERY
@5      moveq   #0,d0
@9      rts
convert dc.w    0
*PAGE
*-------------------------------------------------------------------
*       Routines to query whether file should be copied.
*-------------------------------------------------------------------

*       A1 will have the warning message required

COPY_QUERY_WARNING
        move.l  a1,-(SP)                ; save message address
        moveq   #2,d1                   ; RED ink for warning
        bsr     CONSOLE_INK
        move.l  (SP)+,a1                ; restore message address 
        bsr     CONSOLE_MESSAGE
        lea     filemsg,a1
COPY_QUERY
        lea     filemsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        lea     sourcename,a1
        bsr     CHANNEL_MESSAGE
        lea     selmsg,a1
        bsr     CONSOLE_GREEN_MESSAGE
        bsr     CONSOLE_YESNO_MESSAGE
        bsr     BEEP2

        lea     selyn,a5
        bsr     PICK_PARAMETER
        move.l  d0,-(SP)                ; save reply
        lea     xqlmsg,a1
        bsr     CLEAR_CONSOLE_LINE
        lea     filemsg,a1
        bsr     CLEAR_CONSOLE_LINE
        lea     selmsg,a1
        bsr     CLEAR_CONSOLE_LINE
        move.l  (SP)+,d0                ; restore reply
        bne.s   @6                      ; ESC = NO

        move.w  selyn,d0
        beq.s   @9
@6      lea     sourcename,a1
        bsr     NOT_COPIED
        lea     notcount,a1
        addq.w  #1,(a1)
        moveq   #ERR_NC,d0
@9      rts

filemsg dc.w    5,2,6
        dc.b    'FILE: '
selyn   dc.w    1
        dc.w    0,1
        dc.w    168
        dc.w    36,9,0,60
selmsg  dc.w    6,2,12
        dc.b    'Copy File:  '
copymsg dc.w    14
        dc.b    '   ... COPYING'





*  PAGE           W I L D     C H E C K I N G
*---------------------------------------------------------------------
*       This routine is used to check if the filename matches any
*       constraints imposed by Wild Card Copy feature.
*
*       'fileheader' contains relevant file header.
*
*       ERROR RETURNS:  ERR_NC          File Not to be copied
*---------------------------------------------------------------------

WILD_COPY_CHECK
        moveq   #0,d0
        rts
        
*PAGE           F I L E    T Y P E    C H E C K I N G
*---------------------------------------------------------------------
*       This routine is used to check if you want to copy a file
*       type that is not normally compatible with the target machine.
* 
*       'fileheader' contains relevant file header.
*
*       ERROR RETURNS:  = 0     OK, User not queried
*                      <> 0     Not OK, A1 = Error Message Address
*---------------------------------------------------------------------
TYPE_CHECK
        movem.l d1-d3/a0/a2/a3,-(SP)
        move.w  srctyp,d0               ; Source OPD ?
        beq.s   @3                      ; ... YES, then jump

*       QL file types

        move.w  desttyp,d0              ; Destination also QL ?
        bne.s   @2                      ; ... YES, then exit OK
        lea     fileheader,a0
        move.b  fh_type(a0),d1          ; QL Machine Code File ?
        bne.s   @5                      ; ... YES
@2      moveq   #0,d0
        bra.s   @9

*       OPD File types

@3      move.w  desttyp,d0              ; Destination also OPD ?
        beq.s   @2                      ; ... YES, exit OK
        move.b  fh_type(a0),d1          ; get file type
        subq.b  #1,d1                   ; 1 = OPD Machine Code File ?
        beq.s   @5
        subq.b  #2,d1                   ; 3 = OPD Catalogue File
        beq.s   @6
        subq.b  #1,d1                   ; 4 = OPD Save/Load Dump File ?
        beq.s   @6
        bra.s   @2
        
@5      lea     mcodmsg,a1              ; 'Machine Code' message
        bra.s   @7
@6      lea     xqlmsg,a1               ; 'Not Used on QL' message
@7      moveq   #ERR_NC,d0              ; set error reply
        lea     convert,a0
        move.w  #1,(a0)                 ; suppress conversion
@9      movem.l (SP)+,d1-d3/a0/a2/a3    ; restore registers
        rts
mcodmsg dc.w    4,2,18
        dc.b    'MACHINE CODE FILE '
xqlmsg  dc.w    4,2,24
        dc.b    'FILE TYPE NOT USED ON QL'
*PAGE           S P E C I A L   E X T E N S I O N
*-------------------------------------------------------------------
*       This routine checks to see if a file with one of the
*       extensions requiring special action has been encountered.
*       It also converts between OPD and QL extension types.
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D0                              File Type (0
*       A5      File Name Address
*
*------------------------------------------------------------------

NAME_CHECK
        movem.l d1-d3/a0/a2,-(SP)        
        move.w  srctyp,d0               ; get source type
        cmp.w   desttyp,d0              ; same as destination ?
        bne.s   @5                      ; ... NO, continue checking
@3      move.w  #1,d0                   ; set exit condition
        bra     name_check_exit         ; ... and exit
@5      move.w  srctyp,d0               ; source OPD ?
        beq.s   name_get_ext            ; ... YES, continue
        move.w  desttyp,d0              ; destination OPD
        bne.s   @3                      ; ... NO, no conversion
name_get_ext
        move.l  a5,a0
        move.w  (a0)+,d0                ; get name length
        cmpi.w  #4,d0                   ; test length
        ble     name_check_exit_ok      ; ... exit if too short
        add.w   d0,a0                   ; plus length
        subq.l  #4,a0                   ; set to beginning of extension
        moveq   #[4-1],d0               ; set for 4 characters
@3      move.b  0(a0,d0.w),d1           ; get a character
        ror.l   #8,d1                   ; move it
        dbra    d0,@3                   ; get rest of name
        ori.l   #$00202020,d1           ; convert to lower case

name_check_ext
        lea     extql,a1                ; expected source
        lea     extopd,a2               ; target
        move.w  desttyp,d0              ; check this way round
        beq.s   @1                      ; ... YES, jump
        exg     a1,a2                   ; ... NO, change over
@1      moveq   #[extql-extopd-6],d2    ; get first one to check
@2      cmp.l   0(a1,d2.w),d1           ; does name match
        beq.s   name_change             ; ...YES
        subq.w  #6,d2
        bpl.s   @2                      ; loop until finished
        bra     name_check_exit_ok      ; not found, then exit
name_change
        move.b  0(a2,d2.w),(a0)         ; change extension seperator
        move.w  4(a2,d2.w),d0           ; set type for return
        bra.s   name_check_exit
name_check_exit_ok
        moveq   #0,d0
name_check_exit
        movem.l (SP)+,d1-d3/a0/a2
        rts


*       ------------------------------------------------------
*                       EXTENSION TABLE
*                       ~~~~~~~~~~~~~~~
*       Each entry has corresponding entry in following table
*       Value following extension is data conversion option wanted
*               0       Conversion depends on parameter setting
*               1       No conversion for this file
*               2       Treat file as text file for conversion
*               3       Treat file as Quill file for conversion
*               4       Treat file as Archive Database file
*               5       Treat file as Archive Screen file
*               6       Treat file as Archive Object Program File
*               7       Treat file as Abacus File
*               8       Treat file as Easel File 
*               9       Treat file as Easel Picture file
*       -------------------------------------------------------
        ALIGN
extopd  dc.b    '_bas',0,2,'.doc',0,3,'.exp',0,2,'.lis',0,1
        dc.b    '.dbf',0,4,'.scn',0,5,'.prg',0,2,'_pro',0,6
        dc.b    '.aba',0,7,'.grf',0,8,'.pic',0,9
extql   dc.b    '_bas',0,2,'_doc',0,3,'_exp',0,2,'_lis',0,1
        dc.b    '_dbf',0,4,'_scn',0,5,'_prg',0,2,'_pro',0,6
        dc.b    '_aba',0,7,'_grf',0,8,'_pic',0,9
*PAGE           X C H A N G E   C O M P A T I B I L I T Y
*----------------------------------------------------------------------
*       This routine checks for any compatibility problems at the
*       XCHANGE level.
*
*       The file header is held in 'fileheader'
*
*       This routine is responsible for setting the flag 'convert'
*       to indicate the data conversion (if any) required.
*
*       ERROR RETURNS:  = 0     OK, User not queried
*                      <> 0     Not OK, A1 = Error Message Address 
*----------------------------------------------------------------------
XCHANGE_CHECK
        movem.l d1-d3/a0/a2/a5,-(SP)    ; save registers used
        lea     sourcename,a0
        lea     targetname,a2
        move.w  (a0),d0
        addq.w  #1,d0
@1      move.b  (a0)+,(a2)+
        dbra    d0,@1
        lea     targetname,a5
        bsr     NAME_CHECK
        lea     convert,a1              ; get convert flag
        move.w  d0,(a1)                 ; set required value
        lsl.w   #1,d0                   ; convert to displacement
        move.w  xchange_checks(d0.w),d0
        jmp     xchange_checks(d0.w)
xchange_checks
@1      dc.w    xchange_exit_ok-@1      ; 0 = Not Psion Type
        dc.w    xchange_exit_ok-@1      ; 1 = No Conversion required
        dc.w    xchange_exit_ok-@1      ; 2 = Text file
        dc.w    quill-@1                ; 3 = Quill Doc File
        dc.w    archive-@1              ; 4 = Archive Database File
        dc.w    screen-@1               ; 5 = Archive Screen File
        dc.w    object-@1               ; 6 = Archive Object File
        dc.w    abacus-@1               ; 7 = Abacus File
        dc.w    easel-@1                ; 8 = Easel File
        dc.w    picture-@1              ; 9 = Easel Picture File
xchange_exit_error
        moveq   #ERR_NC,d0
        bra.s   xchange_exit
xchange_exit_ok
        moveq   #0,d0
xchange_exit
        movem.l (SP)+,d1-d3/a0/a2/a5
        rts
*PAGE
QUILL
        bsr     XCHANGE_GET_HEADER
        cmpi.l  #'vrm1',2(a1)
        beq.s   @2
@1      lea     @8,a1
        bra     xchange_exit_error
@2      cmpi.l  #'qdf0',6(a1)
        beq     xchange_exit_ok
        cmpi.l  #'qdf1',6(a1)
        beq     xchange_exit_ok
        bra.s   @1
@8      dc.w    4,3,22
        dc.b    'Not a valid QUILL File'        
ARCHIVE
        bsr     XCHANGE_GET_HEADER
        cmpi.l  #'vrm1',2(a1)
        beq.s   @2
@1      lea     @8,a1
        bra     xchange_exit_error
@2      cmpi.l  #'dbf0',6(a1)
        beq     xchange_exit_ok
        bra.s   @1
@8      dc.w    4,3,24
        dc.b    'Not a valid ARCHIVE File'        
SCREEN
        bsr     XCHANGE_GET_HEADER
        cmpi.l  #'dbs2',(a1)
        beq     xchange_exit_ok
        cmpi.l  #'dbs1',(a1)
        beq.s   @3
        lea     @8,a1
        bra     xchange_exit_error
@3      lea     @9,a1
        bra     xchange_exit_error
@8      dc.w    4,3,22
        dc.b    'Not a Valid Screen File'        
@9      dc.w    4,3,28
        dc.b    'Not compatible with XCHANGE '
OBJECT
        lea     @8,a1
        bra     xchange_exit_error
@8      dc.w    4,3,24
        dc.b    'Not Supported by XCHANGE'
ABACUS
        bsr     XCHANGE_GET_HEADER
        cmpi.l  #'ABM1',(a1)
        beq     xchange_exit_ok
        lea     @8,a1
        bra     xchange_exit_error
@8      dc.w    4,3,24
        dc.b    'Not a valid ABACUS File '        
EASEL
        bra     xchange_exit_ok
PICTURE
        lea     @8,a1
        bra     xchange_exit_error
@8      dc.w    4,3,24
        dc.b    'Not Supported by XCHANGE'
xchange_get_header
        moveq   #IO_FSTRG,d0
        moveq   #20,d2
        moveq   #-1,d3
        move.l  srcchan,a0
        lea     xchangebuf,a1
        TRAP    #3
        lea     xchangebuf,a1
        rts
xchangebuf      ds.b    20
*PAGE           C H E C K    S P A C E    R O U T I N E S
*-------------------------------------------------------------------
*       Check space on output is enough for all files
*       If not selective mode will have to be used
*-------------------------------------------------------------------
CHECK_SPACE
        moveq   #0,d0
        rts
*PAGE
*---------------------------------------------------------------------
*       Output details for not copied message
*               A1 = Filename
*---------------------------------------------------------------------
NOT_COPIED
        move.l  a1,-(SP)
        moveq   #2,d1                   ; RED Ink
        bsr     SCREEN_INK
        lea     ncmsg,a1
        bsr     SCREEN_MESSAGE
        moveq   #7,d1                   ; White ink for filename
        bsr     SCREEN_INK
        move.l  (SP)+,a1
        bsr     CHANNEL_MESSAGE
        rts
ncmsg   dc.w    12
        dc.b    'NOT COPIED..'

*-------------------------------------------------------------------
*       Output text given by A1 to screen, maintaining D0 error code
*-------------------------------------------------------------------
SCREEN_ERROR_TEXT
        move.l  d0,-(SP)
        move.l  a1,-(SP)                ; save desired message pointer
        moveq   #2,d1                   ; Message in RED
        bsr     SCREEN_INK
        lea     errspce,a1
        bsr     SCREEN_MESSAGE
        move.l  (SP)+,a1                ; restore desired message
        bsr     CHANNEL_MESSAGE
        moveq   #7,d1
        bsr     SCREEN_INK             ; Ink back to YELLOW
        move.l  (SP)+,d0
        rts
errspce dc.w4
        dc.b    '    '
        
*-------------------------------------------------------------------
*       Output QDOS error text to screen according to D0
*-------------------------------------------------------------------
SCREEN_QDOS_ERROR
        move.l  d0,-(SP)                ; save error code
        beq.s   @9                      ; ... JUMP if no error
        moveq   #2,d1                   ; Message in RED
        bsr     SCREEN_INK
        lea     errspce,a1
        bsr     SCREEN_MESSAGE
        move.l  (SP),d0                 ; restore error code
        move.w  UT_ERR,a2
        jsr     (a2)
        moveq   #7,d1
        bsr     SCREEN_INK             ; Ink back to WHITE
        bsr     BEEP1                   ; sound alarm
@9      move.l  (SP)+,d0
        rts
        END
