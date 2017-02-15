******************************************************************
**                                                              **
**                      OPDLOAD                                 **
**                      ~~~~~~~                                 **
**      This loads up the OPD Device Driver.                    **
**                                                              **
**                                      LAST AMENDED: 19/07/86  **
******************************************************************

        xref    FIND_DRIVER,FIND_CODE,devname

*NOLIST
$INCLUDE        Flp1_asmlib_trap1
$INCLUDE        Flp1_asmlib_trap2
$INCLUDE        Flp1_asmlib_trap3
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_system
$INCLUDE        Flp1_asmlib_errors
$INCLUDE        Flp1_asmlib_channels
*LIST


*PAGE           P R O G R A M    C O D E
*       Job Start Block

        bra.s   start
scrid   dc.l    0                       ; error channel (NON STANDARD)
        dc.w    $4AFB                   ; standard tag
        dc.w    7                       ; name length
        dc.b    'OPDLoad '              ; name text
        
$INCLUDE        Flp2_device_table_asm

*       Examine list of device drivers to see if already loaded

START
        moveq   #MT_INF,d0
        TRAP    #1
        move.l  a0,a6

        lea     opdname,a0              ; look for OPD Device type
        bsr     FIND_DRIVER             ; Found ?
        bne.s   initialise_opd          ; ... NO, continue load
        lea     opddef,a0               ; ... YES, store address
        lea     [-ch_next](a1),a1       ; convert base
        move.l  a1,(a0)                 ; store result
        lea     msg3,a1
        bsr     MESSAGE
        moveq   #err_ex,d0
        bra     exit

*       Open code file for driver

initialise_opd
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #0,d3
        lea     opdfile,a0
        TRAP    #2
        tst.b   d0
        beq.s   get_header
        lea     msg5,a1
        bsr     MESSAGE
        moveq   #err_nf,d0
        bra     exit

*       Get file header details

get_header
        lea     opdchan,a1
        move.l  a0,(a1)                 ; save channel id
        moveq   #FS_HEADR,d0
        moveq   #64,d2
        moveq   #-1,d3
        lea     hdrbuf,a1
        TRAP    #3

*       Output Serial Number

        lea     msg8,a1                 ; text part
        bsr     MESSAGE
        move.w  UT_MINT,a2
        move.w  hdrbuf+6,d1             ; numeric part
        jsr     (a2)
        lea     newline,a1
        move.w  UT_MTEXT,a2
        jsr     (a2)

*       Get medium details to set up encryption keys

get_medium
        lea     keys,a1
        move.b  hdrbuf+10,(a1)
        tst.b   (a1)                    ; see if encrypted ?
        beq.s   get_memory              ; jump if not
        moveq   #FS_MDINF,d0
        moveq   #-1,d3
        lea     mediumbuf,a1
        move.l  opdchan,a0
        TRAP    #3
        lea     keys+1,a1
        move.b  d1,(a1)                 ; store good sectors for key
        move.b  keys,d2
        eor.b   d1,d2
        cmpi.b  #'C',d2
        beq.s   get_memory
        cmpi.b  #'M',d2
        beq.s   get_memory

invalid_copy
        lea     msg4,a1
        bsr     MESSAGE
        moveq   #err_nf,d0
        bra     exit

mediumbuf       ds.b    16
keys            ds.l    1

*  Get memory for Driver

get_memory        
        moveq   #MT_ALCHP,d0            ; allocate memory trap
        move.l  hdrbuf,d1               ; length required
        moveq   #0,d2                   ; use job 0 to stop de_allocate
        TRAP    #1
        tst.b   d0
        bne     exit_error
        
load_opd
        lea     opddef,a1
        move.l  a0,(a1)                 ; save start address
        moveq   #FS_LOAD,d0
        move.l  opdchan,a0              ; restore channel id
        move.l  opddef,a1               ; base address
        move.l  hdrbuf,d2               ; size
        move.l  #-1,d3                  ; timeout (=forever)
        TRAP    #3
        tst.b   d0
        bne     exit_error_release

*       Copy some addresses from MDV handler
             
find_mdv
        lea     mdvname,a0            
        bsr     FIND_DRIVER
        lea     [-ch_next](a1),a5
        move.l  opddef,a1
        move.l  ch_slave(a5),ch_ql_slave(a1)
        
*       Convert relative addresses to absolute ones
*       for Physical Layer module

absolute
        move.l  opddef,a5
        move.l  opddef,d5
        tst.l   ch_poll(a5)             ; Link required ?
        beq.s   @1                      ; ... NO, then jump
        add.l   d5,ch_poll(a5)
@1      tst.l   ch_sch(a5)              ; Link required ?
        beq.s   @2                      ; ... NO, then jump
        add.l   d5,ch_sch(a5)
@2      add.l   d5,ch_slave(a5)
        add.l   d5,ch_formt(a5)
*        add.l   d5,ch_start+2(a5)
*        add.l   d5,ch_stop+2(a5)
*        add.l   d5,ch_sectr+2(a5)
*        tst.l   ch_write+2(a5)         ; see if ROM routine to be used
*        beq.s   @3                      ; ... YES, jump
*        add.l   d5,ch_write+2(a5)
*@3      add.l   d5,ch_spin+2(a5)
*        add.l   d5,ch_position+2(a5)
*        add.l   d5,ch_read_header+2(a5)
*        add.l   d5,ch_ql_read_header+2(a5)

*       Convert addresses for Access Layer Module

        lea     ch_inout+2(a5),a4       ; base for branch
        add.w   ch_inout+2(a5),a4       ; ... + displacement
        move.l  a4,ch_inout(a5)         ; ... = answer
        lea     ch_open+2(a5),a4
        add.w   ch_open+2(a5),a4
        move.l  a4,ch_open(a5)
        lea     ch_close+2(a5),a4
        add.w   ch_close+2(a5),a4
        move.l  a4,ch_close(a5)

*       Set up links for routines which map onto standard QDOS
*       microdrive vectors.

*        move.l  #$4000,d1

*        tst.l   ch_write+2(a5)          ; see if already set for RAM
*        bne.s   @4                      ; ... YES, jump
*        clr.l   d0
*        move.w  MD_WRITE,d0
*        add.l   d1,d0
*        move.l  d0,ch_write+2(a5)

*@4      clr.l   d0
*        move.w  MD_READ,d0
*        add.l   d1,d0
*        move.l  d0,ch_read+2(a5)

*        clr.l   d0
*        move.w  MD_VERIN,d0
*        add.l   d1,d0
*        move.l  d0,ch_verin+2(a5)
        

*       Set up links into routines that are internal to the microdrive
*       vectors (and thus not officially available or documented).
*
*       NOTE. This has only been verified as being correct for the
*             following ROMS:-
*                       AH, JM, JS, MG

*        move.w  MD_SECTR,a2             ; get QDOS vector
*        add.l   d1,a2                   ; add MD_ adjustment
*        add.w   2(a2),a2                ; + displacement from MD_SECTR
*        addq.l  #2,a2                  ; ... and allow for instruction
*        move.l  a2,ch_gap+2(a5)         ; gap routine address

*        move.w  MD_WRITE,a2             ; get QDOS vector
*        add.l   d1,a2                   ; ... + standard adjustment
*@5      addq.l  #2,a2
*        cmp.w   #$4E75,[-2](a2)         ; look for RTS
*        bne.s   @5
*        move.l  a2,ch_block_write+2(a5)

*        move.w  MD_READ,a2              ; get QDOS vector
*        add.l   d1,a2                   ; add MD_ adjustment
*        add.w   2(a2),a2                ; + displacement from MD_READ
*        addq.l  #2,a2                  ; ... and allow for instruction
*        move.l  a2,ch_block_read+2(a5)  ; read block routine address

*        move.w  MD_VERIN,a2             ; get QDOS vector
*        add.l   d1,a2                   ; add MD_ adjustment
*        add.w   2(a2),a2                ; + displacement from MD_VERIN
*        moveq   #2,d2
*        add.l   a2,d2                  ; ... and allow for instruction
*       move.l  d2,ch_block_verify+2(a5) ; verify block routine address

*       Get tape code to complete key

get_code
        lea     devname,a0
        move.l  opdfile+2,2(a0)         ; set required device type
        bsr     FIND_DRIVER             ; scan device drivers
        move.b  opdfile+5,d1            ; set drive number
        sub.b   #'0',d1                 ; convert to binary
        bsr     FIND_CODE               ; scan physical def blocks
        lea     keys+2,a1
        move.w  d1,(a1)                 ; ... set extract code
       
*       decrypts the file

decrypt
        move.b  keys,d0                 ; see if encrypted
        beq     exit_ok                 ; ... and jump if not
        move.l  opddef,a1
        add     #ch_ql_read_header+10,a1 ; start after vectors
        moveq   #127,d1
        move.l  keys,d2
@1      eor.l   d2,(a1)+
        dbra    d1,@1
        bra     exit_ok

exit_error_release

        move.l  d0,-(SP)
        moveq   #MT_RECHP,d0            ; release heap trap
        move.l  opddef,a0               ; start address
        TRAP    #1
        move.l  (SP)+,d0

exit_error
        move.l  d0,-(SP)
        lea     msg6,a1
        bsr     MESSAGE
        move.l  (SP),d0                 ; restore error code
        move.w  UT_ERR,a2               ; QDOS message
        jsr     (a2)
        move.l  (SP)+,d0
        bra.s   exit
        
*       OK return

exit_ok
        move.l  opddef,a5
        moveq   #MT_LDD,d0              ; set to link directory driver
        lea     ch_next(a5),a0          ; Access level pointer
        TRAP    #1
@2      moveq   #MT_LPOLL,d0            ; set to link polled task
        lea     ch_lpoll(a5),a0         ; physical layer pointer
        tst.l   4(a0)                   ; link set ?
        beq.s   @4                      ; ... NO, skip link
        TRAP    #1                      ; ... YES, link in to QDOS
@4      moveq   #MT_LSCHD,d0            ; set to link scheduler task
        lea     ch_lsch(a5),a0          ; physical layer pointer
        tst.l   4(a0)                   ; link set ?
        beq.s   @6                      ; ... NO,  skip link
        TRAP    #1                      ; ... YES, link in to QDOS
@6      moveq   #0,d0                   ; set OK exit


*       Exit.  If free-standing program then output success/failure
*       message acording to error code.
*       (NOTE OPD Driver Code File left to QDOS to close)

exit
        move.l  d0,-(SP)                ; store reply code
        cmp.b   #err_ex,d0
        beq.s   @5
        tst.b   d0
        bne.s   @3
        lea     msg1,a1
        bra.s   @4
@3      lea     msg2,a1
@4      bsr     message
        move.l  (SP)+,d3                ; restore reply code
@5      moveq   #MT_FRJOB,d0
        moveq   #-1,d1
        TRAP    #1

*       Output the message given by A1

MESSAGE
        lea     2(a1),a2                ; start of message text
        move.w  (a1),d1                 ; message length
        subq.w  #1,d1                   ; converted to loop count
        moveq   #1,d2                   ; start encryption value
@1      sub.b   d2,(a2)+                ; de-encrypt character
        addq    #1,d2                   ; ... next code
        dbra    d1,@1                   ; loop until finished
        move.l  a1,-(SP)                ; save message address
        lea     msg0,a1                 ; set program ID address
        move.l  scrid,a0                ; channel to use
        move.w  UT_MTEXT,a2
        jsr     (a2)
        move.l  (SP)+,a1                ; restore message address
        move.w  UT_MTEXT,a2
        jsr     (a2)
@9      rts

*PAGE           DATA AREAS
msg0    dc.w    8
        dc.b    'OPDLoad:'
msg1    dc.w    13
        dc.l    [' INI'+$01020304],['TIAL'+$05060708]
        dc.l    ['ISED'+$090a0b0c]
        dc.b    [10+$0D],0
msg2    dc.w    13
        dc.l    [' ABA'+$01020304],['NDON'+$05060708]
        dc.l    ['ED  '+$090a0b0c]
        dc.b    [10+$0D],0
msg3    dc.w    17
        dc.l    [' ALR'+$01020304],['EADY'+$05060708]
        dc.l    [' LOA'+$090a0b0c],['DED '+$0d0e0f10]
        dc.b    [10+$11],0
msg4    dc.w    21
        dc.l    [' UNA'+$01020304],['UTHO'+$05060708]
        dc.l    ['RISE'+$090a0b0c],['D CO'+$0d0e0f10]
        dc.l    ['PY  '+$11121314]
        dc.b    [10+$15],0
msg5    dc.w    25
        dc.l    [' CAN'+$01020304],['NOT '+$05060708]
        dc.l    ['FIND'+$090a0b0c],[' DRI'+$0d0e0f10]
        dc.l    ['VER '+$11121314],['CODE'+$15161718]
        dc.b    [10+$19],0
msg6    dc.w    8
        dc.l    [' ERR'+$01020304],['OR: '+$05060708]
msg8    dc.w    15
        dc.l    [' Ser'+$01020304],['ial '+$05060708]
        dc.l    ['Numb'+$090a0b0c],['er  '+$0d0e0f10]
newline dc.w    1
        dc.b    10,0
opdfile dc.w    14
        dc.b    'Flp1_OPDdriver'
hdrbuf  ds.b    64
opddef  dc.l    0
opdchan dc.l    0
initbuf dc.l    0
        END
