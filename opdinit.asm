******************************************************************
*                      OPD STANDARD INITIALISATION              **
*                      ~~~~~~~~~~~~~~~~~~~~~~~~~~~              **
*                                                               **
*      This module is responsible for doing initialisation      **
*      that is common to the OPDCOPY and OPDDIAG programs.      **
*      This includes the following:-                            **
*                                                               **
*               - Opening up the Windows                        **
*               - Output the Title, Copyright, Version messages **
*               - Loading the OPD Device Driver if needed       **
*                                                               **
*                                      LAST UPDATED: 01/01/87   **
******************************************************************

Version         equ     '2.7 '

        xdef    INITIALISATION,opddriver,opdflag
        xref    conid,scrid,actid,errid
        xref    devicetable,devicecount,fileheader,opdname

        xref    CONSOLE_MESSAGE,CLEAR_CONSOLE_LINE
        xref    SCREEN_MESSAGE,SCREEN_NEWLINE
        xref    ACTION_MESSAGE
        xref    ERROR_MESSAGE,ERROR_CLEAR,QDOS_ERROR_MESSAGE,BEEP
        xref    CHANNEL_MESSAGE
        
        xref    title,QUIT,SUICIDE

        xref    CHANNEL_NORMAL,CONSOLE_NORMAL
        xref    CHANNEL_LARGE,CONSOLE_LARGE
        xref    CONSOLE_LARGE_WIDE,CHANNEL_LARGE_WIDE
        xref    CONSOLE_INK,ACTION_INK,SCREEN_INK,CHANNEL_INK
        xref    CONSOLE_STRIP,CONSOLE_POSITION

*NOLIST
$INCLUDE        Flp1_asmlib_trap1
$INCLUDE        flp1_asmlib_trap2
$INCLUDE        flp1_asmlib_trap3
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_QL_header
$INCLUDE        Flp1_asmlib_channels
$INCLUDE        flp1_asmlib_errors
*LIST
*PAGE           SCREEN INITIALISATION
INITIALISATION
        moveq   #mt_inf,d0              ; get system information
        trap    #1
        exg     a0,a6                   ; set System Variables pointer

*       Clear the total screen fast

@2      move.l  #$20000,a0              ; start of screen
        move.w  #$2000-1,d0             ; loop count
@3      clr.l   (a0)+
        dbra    d0,@3
       
*       Open the Windows
        
        lea     headid,a1               ; Headings
        bsr     OPEN_WINDOW

        lea     scrid,a1                ; Screen
        bsr     OPEN_WINDOW
        bsr     CHANNEL_NORMAL

        lea     conid,a1                ; Console
        bsr     OPEN_WINDOW
        bsr     CHANNEL_NORMAL

        lea     errid,a1                ; Error
        bsr     OPEN_WINDOW
        bsr     CHANNEL_LARGE

        lea     actid,a1                ; Action
        bsr     OPEN_WINDOW
        bsr     CHANNEL_LARGE

*       Output the Title Message
 
        move.l  headid,a0
        bsr     CHANNEL_LARGE_WIDE
        moveq   #4,d7                   ; set loop count
@5      cmpi.w  #1,d7
        bne.s   @6
        moveq   #4,d1                   ; change to green ink
        bsr     CHANNEL_INK
@6      moveq   #sd_pixp,d0             ; pixel position
        moveq   #80,d1                  ; x co-ordinate = 80
        lsl.l   #1,d1                   ;               x 2 = 160
        add.l   d7,d1                   ;               + displacement
        move.l  d7,d2                   ; y co-ordinate = displacement
        addq.l  #3,d2                   ;               + 3 from top
        trap    #3
        lea     title,a1
        bsr     CHANNEL_MESSAGE
        moveq   #IO_SBYTE,d0
        moveq   #' ',d1
        TRAP    #3
        moveq   #SD_SETMD,d0
        moveq   #1,d1                   ; transparent background
        TRAP    #3
        dbra    d7,@5

*       Output the Copyright & Release Messages

        bsr     CHANNEL_NORMAL
        moveq   #0,d1                   ; black ink
        bsr     CHANNEL_INK
        moveq   #SD_PIXP,d0             ; pixel position
        moveq   #2,d1                   ; x co-ordinate
        moveq   #4,d2                   ; y co-ordinate
        TRAP    #3
        lea     copymsg,a1              ; Copyright Message
        bsr     CHANNEL_MESSAGE
        moveq   #SD_PIXP,d0             ; pixel position
        moveq   #2,d1                   ; x co-ordinate
        moveq   #14,d2                  ; y co-ordinate
        TRAP    #3
        lea     namemsg,a1              ; Name Message
        bsr     CHANNEL_MESSAGE
        moveq   #SD_PIXP,d0             ; pixel position
        move.w  #348,d1                 ; x co-ordinate
        moveq   #4,d2                   ; y co-ordinate
        TRAP    #3
        lea     relmsg,a1               ; Release Message
        bsr     CHANNEL_MESSAGE
        moveq   #SD_PIXP,d0             ; pixel position
        move.w  #384,d1                 ; x co-ordinate
        moveq   #14,d2                  ; y co-ordinate
        TRAP    #3
        lea     versmsg,a1              ; Version Message
        bsr     CHANNEL_MESSAGE
        bra.s   opdload
        
OPEN_WINDOW
        move.l  a1,-(SP)                ; save channel ID address
        addq.l  #4,a1                   ; update to description address
        move.w  UT_CON,a2               ; Open Console Window 
        jsr     (a2)                    ; ... Vector
        move.l  (SP)+,a1                ; restore channel ID addrss
        tst.b   d0                      ; Open OK ?
        bne     SUICIDE                 ; ... NO, abandon pogram
        move.l  a0,(a1)                 ; ... YES, save channel ID
        rts        

headid  dc.l    0                       ; channel id
        dc.b    0,0                     ; Border   colour,width
        dc.b    2,0                     ; colours  paper,ink
        dc.w    436,28                  ; size     width, height
        dc.w    38,10                   ; origins  x,y
        
copymsg dc.w    6
        dc.b    ' 1985'
namemsg dc.w    8
        dc.b    'D.Walker'
relmsg  dc.w    8
        dc.b    'Release '
versmsg dc.w    4
        dc.l    version
*PAGE           OPD DRIVER LOADING (When Required)
*********************************************************************
**
**                      LOAD OPD DRIVER
**
**      The following code invokes the OPDLOAD program (if necessary)
**      to load the OPD DRIVER.
**
**      EXIT CONDITIONS
**              D0              Error Condition
**              opdflag         Set if driver had to be loaded
**              opddriver       Address of OPD Driver
**
********************************************************************

        xref    FIND_DRIVER

*       Load Device Driver if necessary

opdload
        lea     opdflag,a0
        sf      (a0)                    ; clear loaded flag
        lea     opdname,a0
        bsr     FIND_DRIVER
        beq.s   opdload_address
        
*       Open File for OPDLoad program & read header

        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #0,d3
        lea     opdfile,a0
        TRAP    #2
        tst.b   d0
        bne.s   opdload_exit   
        moveq   #FS_HEADR,d0
        moveq   #16,d2
        moveq   #-1,d3
        lea     fileheader,a1
        TRAP    #3
        tst.b   d0
        bne.s   opdload_exit
        move.l  a0,-(SP)                ; save channel id

*       Create Job

        moveq   #MT_CJOB,d0             ; create job trap
        moveq   #-1,d1                  ; owned by this job
        lea     fileheader,a0
        move.l  (a0),d2                 ; code length
        move.l  fh_user(a0),d3          ; data length
        sub.l   a1,a1                   ; start address=0
        TRAP    #1
        tst.b   d0
        bne.s   opdload_exit
        lea     opdjob,a1        
        move.l  d1,(a1)
        lea     opddriver,a1
        move.l  a0,(a1)
        
*       Load File

        moveq   #FS_LOAD,d0
        move.l  fileheader,d2           ; file length
        moveq   #-1,d3                  ; wait for completion
        move.l  a0,a1                   ; base address for load
        move.l  (SP)+,a0                ; channel address
        TRAP    #3
        tst.b   d0                      ; worked ?
        bne.s   opdload_exit            ; ... NO, then exit
        moveq   #IO_CLOSE,d0            ; ... YES, close file
        TRAP    #2
        
*       Activate Job

        move.l  opddriver,a0
        move.l  scrid,2(a0)             ; set channel for messages
        
        moveq   #MT_ACTIV,d0            ; activate job trap
        move.l  opdjob,d1               ; opdload job
        moveq   #127,d2                 ; maximum priority
        moveq   #-1,d3                  ; wait for completion
        TRAP    #1                      ; DO it
        tst.b   d0
        bne.s   opdload_exit
        lea     opdflag,a0
        st      (a0)                    ; set flag for loaded
opdload_address
        lea     opdname,a0
        bsr     FIND_DRIVER
        lea     opddriver,a0
        lea     [-ch_next](a1),a1
        move.l  a1,(a0)
        moveq   #0,d0                   ; set for good return
opdload_exit
        rts                             ; return with error code

opdjob          dc.l    0               ; job id
opdfile         dc.w    12
                dc.b    'Flp1_OPDLoad'
opddriver       dc.l    0
opdflag         dc.b    0,0
        END
