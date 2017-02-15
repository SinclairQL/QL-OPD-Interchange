***********************************************************************
**                                                                   **
**          OPD Device Driver - End  Module                          **
**          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~                          **
**                                                                   **
**                                      LAST AMENDED: 25/04/86       **
***********************************************************************

        xdef    OPDEND

        xref    FIND_DRIVER
        xref    devicetable,devicecount
        xref    opdname,mdvname,flpname,ramname,newname

*NOLIST
$INCLUDE        Flp1_asmlib_trap1
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_system
$INCLUDE        Flp1_asmlib_channels
$INCLUDE        Flp1_asmlib_files
$INCLUDE        Flp1_asmlib_errors
*LIST

*       Job Start Block

OPDEND
        bra.s   start
        ds.b    4
        dc.w    $4afb
        dc.w    7
        dc.b    'OPDEnd  '

*PAGE        
*       Examine list of device drivers to see if already loaded

START
        moveq   #0,d0
        trap    #1
        move.l  a0,a6
        lea     opdname,a0
        bsr     FIND_DRIVER             ; OPD Driver Loaded ?
        beq.s   @2                      ; ... YES, continue
        lea     msg2,a1                 ; ... NO, message
        bsr     MESSAGE
        bra     exit                    
@2      lea     [-ch_next](a1),a5       ; convert to correct base

*       Unlink modules (if linked) when all actions completed

@4      tst.b   sv_mdrun(a6)            ; physical layer finished ?
        beq.s   check_files
        moveq   #mt_susjb,d0
        moveq   #-1,d1
        moveq   #5,d3
        sub.l   a1,a1
        trap    #1
        bra.s   @4

check_files
        moveq   #[15*4],d4              ; set to scan file definitions
        lea     sv_fsdef(a6),a4         ; start of table

@2      tst.l   0(a4,d4.w)              ; see if file def. set
        beq.s   @5                      ; ... NO, go for next
        move.l  0(a4,d4.w),a0           ; get file def address
        move.l  fs_drivr(a0),a2         ; get driver access layer
        lea     [-ch_next](a2),a2       ; ... set true base
        cmpa.l  a2,a5                   ; is it an OPD drive
        bne.s   @5                      ; no, so jump
        move.b  fs_files(a0),d0         ; check files all closed
        bne.s   files_not_closed        ; ... NO, then error
        clr.l   0(a4,d4.w)              ; clear phy. def pointer
        move.b  fs_drivn(a0),d0         ; get drive number
        lea     sv_mddid(a6),a3
        cmp.b   [-1](a3,d0.w),d4        ; see if drive id set
        bne.s   @4                      ; ... NO, so jump
        clr.b   [-1](a3,d0.w)           ; clear drive id
        clr.b   [sv_mdsta-sv_mddid-1](a3,d0.w)  ; ...and actions

@4      moveq   #mt_rechp,d0            ; release heap trap
        trap    #1                      ; ... execute
        
@5      subq    #4,d4                   ; go for next
        bpl     @2                      ; loop if not finished
        bra     mdv_idle
        
files_not_closed
        lea     msg3,a1
        move.b  fs_drivn(a0),28(a1)     ; drive number into message
        add.b   #'0',28(a1)             ; convert to ASCII
        bsr     message
        moveq   #err_iu,d0
        bra     exit
mdv_idle        
        moveq   #mt_rpoll,d0            ; unlink polled task 
        lea     ch_lpoll(a5),a0
        tst.l   (a0)                    ; see if linked
        beq.s   @3                      ; ... NO, then skip unlink
        trap    #1

@3      moveq   #mt_rschd,d0            ; unlink scheduler task
        lea     ch_lsch(a5),a0
        tst.l   (a0)                    ; see if linked
        beq.s   @5                      ; ... NO, then skip unlink
        trap    #1

@5      moveq   #mt_rdd,d0              ; unlink access layer
        lea     ch_next(a5),a0      
        trap    #1

*       Release memory allocated

@6      moveq   #mt_rechp,d0             ; release memory
        move.l  a5,a0
        trap    #1
        lea     msg1,a1                 ; finished message
        bsr     message
        moveq   #0,d0
        bra.s   exit

not_found
        lea     msg2,a1
        bsr     message
        moveq   #err_nf,d0      

exit
        lea     opdend,a2
        tst.w   6(a2)                   ; acting as subroutinr?
        bne.s   @2
        rts                             ; yes, then return
@2      move.l  d0,d3                   ; set error code
        moveq   #mt_frjob,d0            ; force unload
        moveq   #-1,d1                  ; ... this job
        trap    #1

*       Output the message given by A1

message 
        lea     opdend+6,a2
        tst.w   (a2)
        beq.s   @9
        move.l  a1,-(a7)
        lea     msg0,a1
        move.w  ut_mtext,a2
        sub.l   a0,a0
        jsr     (a2)
        move.l  (a7)+,a1
        move.w  ut_mtext,a2
        sub.l   a0,a0
        jsr     (a2)
@9      rts

msg0    dc.w    8
        dc.b    'OPDEnd: '
msg1    dc.w    10
        dc.b    'COMPLETED',10
msg2    dc.w    18
        dc.b    'DRIVER NOT LOADED',10
msg3    dc.w    28
        dc.b    'FILES STILL OPEN ON DRIVE  ',10
        END
