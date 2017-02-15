*                        PHYSICAL LAYER
*                        ~~~~~~~~~~~~~~
*       This is set up as a polled task.  It is responsible for
*       the transfer of microdrive (OPD) blocks between memory
*       and the physical medium
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       A3      Device def block
*       A6      System Variables
*       A7      Sup Stack (64 bytes max)
*
*       REGISTERS SMASHED:      D0-D7,A0-A5
*
*       A5 is normally used for Physical Definition Block
*
*====================================================================

*       Decide if OPD Physical layer is meant to be active

OPD_PHYSICAL_LAYER
        lea     opdrun,a0
        move.b  sv_mdrun(a6),d1         ; is a drive active ?
        bne.s   check_if_OPD            ; ... YES, see what type
reset_all_exit
        clr.l   (a0)                    ; clear all OPD flags
quick_exit
        rts

check_if_OPD
        cmp.b   (a0),d1                 ; is OPD drive running

        IFEQ    TASK
        beq.s   READ_SECTOR_HEADER      ; ... YES, go to process
        ENDC

        IFNE    TASK
        beq     quick_exit              ; ... YES, exit immediately
        ENDC

        cmp.b   (opdchk-opdrun)(a0),d1  ; see if drive checked for type
        beq.s   quick_exit              ; ... YES, exit
        cmp.b   (opdwait-opdrun)(a0),d1 ; 2nd interrupt on this drive?
        beq.s   check_tape_type         ; ... YES, continue
        move.b  d1,(opdwait-opdrun)(a0) ; ... NO, set 1st flag
        bra.s   quick_exit              ; ... and exit

*----------------------------------------------------------------------
*       Check for wrong device type specified by user
*----------------------------------------------------------------------

CHECK_TAPE_TYPE
        clr.l   (a0)
        bsr.s   GET_READY
        tst.b   sv_mdrun(a6)            ; check for tape stopped
        beq     stop_drive
        lea     access,a1
        move.l  a5,a4                   ; save access level address
        lea     10(SP),a5               ; set buffer
        cmpa.l  fs_drivr(a4),a1         ; should OPD Driver be active ?
        beq     opd_tape                ; ... YES
        bra     ql_tape                 ; ... NO
        PAGE
*----------------------------------------------------------------------
*       Routine to Calculate standard addresses
*----------------------------------------------------------------------

GET_READY
        move.l  (SP)+,a2                ; take return address off stack
        move.w  SR,-(SP)                ; store status register
        ori.w   #$0700,SR               ; ... and disable interrupts
        clr.l   d1
        clr.l   d2
        move.b  sv_mdrun(a6),d1         ; get drive
        lea     sv_mdsta(a6),a4
        sf      -1(a4,d1.w)             ; clear pending ops for drive
        lea     sv_mddid(a6),a5         ; drive id table address
        move.b  -1(a5,d1.w),d2          ; get drive id
        move.l  (sv_fsdef-sv_mddid)(a5,d2.w),a5 ; get phy. def.
        move.l  mctrl,a3                ; set microdrive control reg
        suba.w  #14,SP                  ; space for sector header
        move.w  d2,-(SP)                ;     + drive id
        clr.l   -(SP)                   ;     + space for slave block
        move.l  a5,-(SP)                ;     + phy. def.
        jmp     (a2)

*----------------------------------------------------------------------
*       Read next sector header and check medium
*----------------------------------------------------------------------

READ_SECTOR_HEADER
        bsr.s   GET_READY
        lea     10(SP),a5               ; buffer address
        bsr     OPD_READ_HEADER
        bra.s   bad_medium
        bra.s   check_medium

*----------------------------------------------------------------------
*       Bad Medium Message routine
*----------------------------------------------------------------------

Bad_medium
        move.l  (SP),a5                 ; restore phy def pointer
        lea     fs_mname(a5),a1
        tst.b   (a1)                    ; medium name null ?
        beq.s   L15                     ; ... if so ignore error
        suba.l  a0,a0                   ; set for channel 0
        moveq   #9,d2
        move.w  UT_MTEXT,a2             ; output name
        jsr     2(a2)
        moveq   #err_fe,d0              ; Bad medium message
        move.w  UT_ERR,a2
        jsr     (a2)
L15     bsr     RESET_PHYSICAL_DEF
        st      fs_flag1(a5)            ; set flag -ve for error
        bra     stop_drive
        PAGE
*----------------------------------------------------------------------
*       check the medium has not changed
*       ... and what actions are required
*----------------------------------------------------------------------

check_medium
        move.l  (SP),a5                 ; restore physical def pointer
        lea     10(SP),a1               ; buffer address
        addq.l  #2,a1                   ; ... after header
        lea     fs_mname(a5),a2         ; stored name address
        moveq   #4,d0
L28     cmpm.w  (a1)+,(a2)+             ; check medium
        bne.s   new_medium              ; ... different, so check OK
        dbra    d0,L28                  ; loop until finished
check_only_action
        tst.b   fs_flag1(a5)            ; check action required flag
        beq     check_retries           ; ... No, then jump
        sf      fs_flag1(a5)            ; set to normal I/O
c_exit  bra     physical_exit           ; ...and exit

*---------------------------------------------------------------------
*       New Medium routine
*
*       Get sector map and new medium name (as long as there were
*       not files still open on old medium).
*----------------------------------------------------------------------
new_medium
        tst.b   fs_flag1(a5)            ; see if medium check required
        ble.s   bad_medium              ; ... if not, bad medium
        tst.b   fs_files(a5)            ; all files closed ?
        bne.s   bad_medium              ; ... if not, error message
        bsr     RESET_PHYSICAL_DEF
        lea     fs_vol(a5),a5           ; set buffer address
        bsr     OPD_READ_VOLUME_MAP
        bne.s   bad_medium
        move.l  (SP),a5                 ; restore a5
        lea     10(SP),a1               ; header buffer address
        addq.l  #2,a1                   ; ... afer flag/number
        lea     fs_mname(a5),a2         ; destination address
        move.l  (a1)+,(a2)+             ; move medium name
        move.l  (a1)+,(a2)+
        move.w  (a1)+,(a2)+
        sf      fs_flag1(a5)            ; set flag as OK
n_exit  bra     physical_exit

*----------------------------------------------------------------------
*       Retry count checks
*----------------------------------------------------------------------

check_retries
        add.w   d7,d7                   ; convert sector number to disp
        bne.s   check_action            ; ... jump if not zero
        addq.b  #1,fs_flag2(a5)         ; update retry count
        cmpi.b  #8,fs_flag2(a5)         ; see if limit reached
        bgt     bad_medium              ; ... YES then error
        PAGE
*----------------------------------------------------------------------
*       Determine action (if any) on next sector
*----------------------------------------------------------------------

check_action
        moveq   #0,d1
        adda.w  d7,a5
        move.w  fs_action(a5),d1        ; any action ?
        beq     update_rundown          ; ... NO, update rundown
        tst.b   sv_mdcnt(a6)            ; ... YES, check run up
        bmi.s   L45                     ; still
        clr.b   sv_mdcnt(a6)            ; clear run_up/run_down count
L45     tst.w   d1
        blt     map_io                  ; map is required action

*----------------------------------------------------------------------
*       Convert slave table entry to address
*       (and store result for later reference)
*----------------------------------------------------------------------

get_slave_status
        lsl.l   #3,d1                  ; convert slave block id to disp
        move.l  sv_btbas(a6),a4
        adda.l  d1,a4                   ; add to start of table
        move.l  a4,4(SP)                ; store address on stack
        lsl.l   #6,d1                   ; convert to rel.address
        lea     0(a6,d1.l),a1           ; .. set buffer address

*----------------------------------------------------------------------
*       Do action required on current block
*----------------------------------------------------------------------

block_io
        btst    #bt_wreq,(a4)           ; write bit set ?
        bne.s   write_block
        btst    #bt_accs,(a4)           ; accessible bit set ?
        bne.s   verify_block
read_block
        bsr     OPD_READ
        bra.s   u_exit                 ; Read Fail
        bra.s   verify_read_ok
verify_block
        bsr     OPD_VERIFY
        bra.s   verify_fail
verify_read_ok
        moveq   #bt_true,d0             ; set for true copy
        clr.w   fs_action(a5)           ; clear down action
        move.l  (SP),a5                 ; restore phy. def ptr
        sf      fs_flag2(a5)            ; set OK flag
        bra.s   update_slave_status     ; go to reset block status
verify_fail
        moveq   #bt_updt,d0             ; set to write again
        bra.s   update_slave_status
write_block
        tst.b   sv_mdcnt(a6)
        bmi.s   u_exit                  ; if negative, complete run_up
        move.w  fs_sam(a5),-(SP)        ; put file/block on stack
        bsr     OPD_WRITE
        addq.l  #2,SP                   ; remove file/block from stack
        moveq   #bt_aver,d0             ; status = awaiting verify
        PAGE
*----------------------------------------------------------------------
*       Update slave block entry status with result of I/O
*----------------------------------------------------------------------

update_slave_status
       moveq   #-16,d1                 ; mask F0
       move.l  4(SP),a4                ; slave block entry address
       and.b   (a4),d1                 ; keep drive identity
       or.b    d0,d1                   ; add required status
       move.b  d1,(a4)                 ; store it
       move.b  #5,sv_mdcnt(a6)         ; set new rundown value
u_exit bra.s   physical_exit

*----------------------------------------------------------------------
*       Update run-up/Run down counter
*----------------------------------------------------------------------

update_rundown
        addq.b  #1,sv_mdcnt(a6)         ; update counter
        cmpi.b  #7,sv_mdcnt(a6)         ; see if expired
        blt.s   physical_exit           ; ... NO, then jump

*----------------------------------------------------------------------
*       Check if any further actions after run up expires
*----------------------------------------------------------------------

further_actions
        clr.b   sv_mdcnt(a6)            ; set for rundown=0
        move.w  #224,d0                 ; set loop count (225 blocks)
        move.l  (SP),a5                 ; restore phy. def.
        lea     fs_action(a5),a5        ; get action table address
L66     tst.w   (a5)+                   ; see if action on this block
        bne.s   physical_exit           ; ... if yes, reset rundown
        dbra    d0,L66                  ; loop until finished

*----------------------------------------------------------------------
*       Stop drive
*----------------------------------------------------------------------

stop_drive
        bsr     DESEL                   ; deselct drives
        lea     opdrun,a0
        clr.l   (a0)                    ; clear OPD flags
        sf.b    sv_mdrun(a6)            ; clear down drive running
        ori.b   #pc_maskg,sv_pcint(a6)  ; enable gap interrupts

*----------------------------------------------------------------------
*       See if Other drive needs starting
*       If not, then re-enable RS232 port
*----------------------------------------------------------------------

other_drives
        moveq   #8,d1
        lea     sv_mdsta(a6),a5
L72     tst.b   -1(a5,d1.w)             ; action outstanding ?
        bne.s   next_drive              ; ... YES, go to start drive
        subq.b  #1,d1                   ; ... NO, set for next drive
        bne.s   L72                     ; loop until finished
        andi.b  #$FF-pc_maskg,sv_pcint(a6) ; suppress gap interrupts
        bsr     RS232_set                  ; restart RS232
        bra.s   physical_exit

*----------------------------------------------------------------------
*       Outstanding action, so start new drive
*----------------------------------------------------------------------

next_drive
        move.b  d1,sv_mdrun(a6)          ; set new drive running
        bsr     SELEC                    ; start drive
        move.b  #-6,sv_mdcnt(a6)           ; set run_up value
        ori.b   #$FF-pc_maskg,sv_pcint(a6) ; enable gap interrupts
        PAGE
*----------------------------------------------------------------------
*       Exit after completing all actions for this entry
*----------------------------------------------------------------------

physical_exit
        adda.w  #24,SP                  ; restore stack
        move.w  (SP)+,SR                ; restore status register
        rts

*----------------------------------------------------------------------
*       Routine to Write/Verify Volume Header
*----------------------------------------------------------------------

map_io
       move.l  (SP),a1                 ; Phy def pointer
       lea     fs_vol(a1),a1           ; Set buffer address
       addq.w  #1,d1                   ; see if write
       bne.s   map_verify              ; ... jump if no
       tst.b   sv_mdcnt(a6)            ; still running up?
       bmi.s   physical_exit
map_write
       move.w  fs_sam(a5),-(SP)        ; set file/block
       bsr     OPD_WRITE
       addq.l  #2,SP                   ; remove file/block from stack
       moveq   #-2,d1                  ; set for verify
       bra.s   map_io_exit
map_verify
       bsr     OPD_VERIFY
       bra.s   map_verify_fail
       moveq   #0,d1                   ; set as OK
       bra.s   map_io_exit
map_verify_fail
        moveq   #-1,d1                  ; verify failed, rewrite
map_io_exit
        move.w  d1,fs_action(a5)        ; reset action
        bra.s   physical_exit
        PAGE
*----------------------------------------------------------------------
*       Routines to tidy up after a cartridge has been changed.
*       by releasing slave blocks and then reseting the in-store
*       Physical Definition information.
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       A5      Phy. Def Addresss
*
*       REGISTERS SMASHED:      D0,D1,A1
*----------------------------------------------------------------------

RESET_PHYSICAL_DEF
        moveq   #15,d0
        lea     SV_FSDEF+64(a6),a1
L91     cmpa.l  -(a1),a5                ; this one matches ?
        beq.s   L92                     ; ... YES, then ID in D0
        dbra    d0,L91                  ; ... ELSE loop
L92     lsl.w   #4,d0                   ; move to left nibble
        ori.w   #1,d0                   ; add available bit
        move.l  SV_BTBAS(a6),a1         ; start of slave block table
L93     move.b  #$F1,d1                 ; mask to screen out status
        and.b   BT_DRV(a1),d1           ; ...leaving drive/avail info
        cmp.b   d1,d0                   ; matches ?
        bne.s   L95                     ; ... NO, jump
        move.b  #BT_EMPTY,(a1)          ; ... YES, set as empty
L95     addq.w  #8,a1                   ; next block
        cmpa.l  SV_BTTOP(a6),a1         ; end of table ?
        blt.s   L93                     ; ... NO, loop
        lea     fs_action(a5),a1
        move.w  #223,d0                 ; set for 224 entries
L97     clr.w   (a1)+                   ; clear down action table
        dbra    d0,L97
        lea     FS_MNAME(A5),a1
        moveq   #11,d0                  ; set for 12 bytes
L98     clr.b   (a1)+                   ; clear down medium name
        dbra    d0,L98
        rts
        PAGE
*--------------------------------------------------------------------
*       The following routines are used to allow for the fact that
*       the User might have accidentally used the wrong device type
*       for the tape actually loaded.  If no action is taken they
*       would spin indefintely.
*-------------------------------------------------------------------

wrong_device
        lea     wrongmsg,a1
        move.l  (SP),a5
        move.b  fs_drivn(a5),d1         ; get drive
        add.b   #'0',d1                 ; convert to ASCII
        move.b  d1,36(a1)               ; store drive number in message
        suba.l  a0,a0
        move.w  UT_MTEXT,a2
        jsr     (a2)
        bsr     RESET_PHYSICAL_DEF
        st      fs_flag1(a5)            ; set access level flag
        bra     STOP_DRIVE
wrongmsg dc.w   36
        dc.b    10,'OPDDriver: Wrong format in drive  ',10

ql_tape
        bsr     MDV_READ_HEADER         ; should be QL tape
        bra.s   wrong_device            ; ... NO, error exit
        clr.b   d1                      ; ... YES clear opd running
set_results
        lea     opdrun,a0
        move.b  d1,(a0)                 ; store OPD running state
        move.b  sv_mdrun(a6),(opdchk-opdrun)(a0) ; set checked drive
        bra     physical_exit

opd_tape
        bsr     OPD_READ_HEADER         ; should be OPD tape
        bra.s   wrong_device            ; ... NO, error exit
        bsr     OPD_READ_HEADER         ; check again for accident
        bra.s   wrong_device
        move.b  sv_mdrun(a6),d1         ; ... YES, set for OPD running
        andi.b  #$FF-pc_maskg,sv_pcint(a6) ; disable gap interrupts
        bra.s   set_results
        PAGE
*----------------------------------------------------------------------
*               READ VOLUME MAP
*               ~~~~~~~~~~~~~~
*
*               ENTRY           EXIT
*               ~~~~~           ~~~~
*       D0                      Error Code
*       A5      Buffer Address
*
*       REGISTERS SMASHED:      D1-D4,D6-D7,A1-A2,A4
*----------------------------------------------------------------------

OPD_READ_VOLUME_MAP
        clr.w   -(SP)                   ; set timeout
L112    bsr     OPD_READ_HEADER
        bra.s   L117
        move.l  a5,a1                   ; buffer address
        bsr     OPD_READ
        bra.s   L115                    ; ... ignore error blocks
        cmp.b   #1,d1                   ; copy 1 ?
        beq.s   L114                    ; ... yes, check block
        cmp.b   #2,d1                   ; copy 2 ?
        bne.s   L115                    ; ... no, next block
L114    cmpi.b  #1,d2                   ; correct block
        beq.s   L118                    ; ... yes, OK exit
L115    subq.b  #1,(SP)                 ; reduce count
        bne.s   L112                    ; ... loop if not expired
        moveq   #err_nf,d0
        bra.s   L119
L117    moveq   #err_fe,d0
        bra.s   L119
L118    moveq   #0,d0
L119    addq.l  #2,SP                   ; remove retry count from stack
        move.b  d0,d0
        rts
