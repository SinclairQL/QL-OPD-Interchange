*-----------------------------------------------------------------
*                      INPUT-OUTPUT ROUTINE
*                      ~~~~~~~~~~~~~~~~~~~~
*
*       This is the main input/output routine for the OPD
*       Driver.
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D0      Trap Code               Error key
*       D1      ... Trap Parameter      Continuation value
*       D2      ... Trap Parameter
*       D3      0 for first call
*               -1 for continuations
*       A0      Channel def block
*       A1      ... Trap Parameters     Continuation value
*       A2      ... Trap Parameters
*       A6      System Variables        Preserved
*
*       REGISTERS SMASHED: D2-D7,A2-A5
*
*       TRAPS SUPPORTED:
*       ~~~~~~~~~~~~~~~
*         $00     IO_PEND                 $40     FS_CHECK
*         $01     IO_FBYTE                $41     FS_FLUSH
*         $02     IO_FLINE                $42     FS_POSAB
*         $03     IO_FSTRG                $43     FS_POSRE
*         $05     IO_SBYTE                $45     FS_MDINF
*         $07     IO_SSTRG                $46     FS_HEADS
*                                         $47     FS_HEADR
*                                         $48     FS_LOAD
*                                         $49     FS_SAVE
*                                         $4A     FS_RENAM
*                                         $4B     FS_TRUNC
*---------------------------------------------------------------------

OPD_INPUT_OUTPUT

        IFEQ    LOCKED
        bsr.s   ACTIVE_START
        bne.s   io_exit
        bsr.s   OPD_INPUT_OUTPUT_X
ACTIVE_END
        clr.b   fs_active(a0)           ; clear lock
        tst.b   d0                      ; set reply condition
io_exit
        rts
ACTIVE_START
        tas     fs_active(a0)
        beq.s   io_exit
error_not_complete
        moveq   #err_nc,d0
        rts
        PAGE
OPD_INPUT_OUTPUT_X
        ENDC
        moveq   #64,d6                  ; check to see if
        sub.l   fs_nblok(a0),d6         ;   QDOS has copied the
        bne.s   L815                    ;     channel block for a
        clr.l   fs_nblok(a0)            ;       shared file
        addq.w  #1,fs_nblok(a0)         ;         and reset if so
        move.l  filestart,fs_nblokdir(a0)
L815    moveq   #0,d6
        move.b  fs_drive(a0),d6         ; get the drive id
        lsl.b   #2,d6
        lea     sv_fsdef(a6),a2
        move.l  0(a2,d6.w),a2           ;get physical def address in a2
        lsl.b   #2,d6                   ; convert to id in nibble
        cmpi.b  #$40,d0                 ; IO_ entry ?
        bcs     io_routines
        cmpi.b  #$4B,d0                 ; in range ?
        bhi.s   error_bad_parameter
        sub.w   #$40,d0                 ; reduce to base 0
        lsl.w   #1,d0                   ; convert to table displacement
        move.w  table(d0.w),d0          ; get jump displacement
        jmp     table(d0.w)             ; ... and jump to routine
table   dc.w    CHECK-table
        dc.w    FLUSH-table
        dc.w    POSAB-table
        dc.w    POSRE-table
        dc.w    error_bad_parameter-table
        dc.w    MDINF-table
        dc.w    HEADS-table
        dc.w    HEADR-table
        dc.w    LOAD-table
        dc.w    SAVE-table
        dc.w    RENAM-table
        dc.w    TRUNC-table

        IFNE    LOCKED
error_not_complete
        moveq   #err_nc,d0
        rts
        ENDC

error_bad_parameter
        moveq   #err_bp,d0
        rts
        PAGE
*--------------------------------------------------------------------
*
*       This routine is used to call the I/O routines internally from
*       within the access level.
*
*       REGISTERS SMASHED: D0-D1,A0-A3
*--------------------------------------------------------------------

OPD_INOUT
        movem.l d0/d2/d4-d7/a4-a5,-(SP)
L822    movem.l (SP),d0/d2
        moveq   #0,d3                   ; set for first entry

        IFEQ     LOCKED
        bsr     OPD_INPUT_OUTPUT_X
        ENDC

        IFNE    LOCKED
        bsr     OPD_INPUT_OUTPUT
        ENDC

        cmpi.b  #err_nc,d0              ; see if incomplete
        beq.s   L822                    ; loop if so
        addq.w  #4,SP
        movem.l (SP)+,d2/d4-d7/a4-a5
        tst.b   d0
        rts
        PAGE
*---------------------------------------------------------------------
*       Routines to check/force all buffers clear
*---------------------------------------------------------------------

CHECK
        moveq   #bt_true,d4
        moveq   #-1,d5
        bra.s   flush2



FLUSH
        moveq   #bt_actn,d4
        moveq   #0,d5
flush2  move.b  fs_drive(a0),d3
        lsl.b   #4,d3
        bset    #0,d3                   ; set first bit
        move.w  fs_filnr(a0),d2
        move.l  sv_btbas(a6),a4
L834    moveq   #-15,d0                 ; $F1 mask
        and.b   (a4),d0                 ; mask in drive/available
        cmp.b   d3,d0                   ; This drive ?
        bne.s   L836                    ; ... jump if not
        cmp.w   bt_filnr(a4),d2         ; This file  ?
        bne.s   L836                    ; ... jump if not
        move.b  (a4),d0
        eor.b   d5,d0
        and.w   d4,d0
        bne     start_slave
L836    addq.w  #8,a4                   ; next entry
        cmpa.l  sv_bttop(a6),a4         ; end  ?
        blt.s   L834                    ; ... No, then loop
        moveq   #0,d0
        rts
*---------------------------------------------------------------------
*       Get information about medium
*---------------------------------------------------------------------

MDINF
        lea     fs_mname(a2),a3
        move.l  (a3)+,(a1)+              ; medium name
        move.l  (a3)+,(a1)+
        move.w  (a3)+,(a1)+
        moveq   #0,d1
        move.b  fs_vol+vol_free(a2),d1
        swap    d1
        move.b  fs_vol+vol_size(a2),d1
        sub.b   fs_vol+vol_flaws(a2),d1
        moveq   #0,d0
        rts
        PAGE
*--------------------------------------------------------------------
*       Position file pointer routines
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D1.L    Position/displacement   File Position
*
*       REGISTERS SMASHED:
*--------------------------------------------------------------------

POSAB
        move.l  filestart,fs_nblok(a0)     ; set to normal start
        move.l  filestart,fs_nblokdir(a0)  ; .. and directory access

POSRE
        tst.l   d3                      ; first entry ?
        bne.s   L849                    ; no, then continuation
        bsr     directory_move_logical
        move.l  fs_nblok(a0),d0
L843    sub.l   filestart,d0            ; convert to file position
        lsl.w   #7,d0
        lsr.l   #7,d0
        add.l   d1,d0                   ; add parameter value
        move.l  d0,d1
        bpl.s   L845                    ; before beginning ?
        moveq   #0,d1                   ; ... yes, set to beginning
        moveq   #0,d0
L845    lsl.l   #7,d0
        lsr.w   #7,d0
        add.l   filestart,d0
        cmp.l   fs_eblok(a0),d0         ; end of file passed ?
        ble.s   L848                    ; ... NO jump
        move.l  fs_eblok(a0),d0         ; get end position
        moveq   #0,d1                   ; ... plus zero displacement
        bra.s   L843                    ; ... and rejoin earlier
L848    move.l  d0,fs_nblok(a0)         ; update file position
        bsr     directory_move_real
L849    moveq   #0,d0                   ; set as FS_PEND
        bra     join_io_routines        ; ... A1 contains file position
        PAGE
*--------------------------------------------------------------------
*       Load a file into memory
*               D2.L    Length of file in bytes
*               A1      Base address for load
*--------------------------------------------------------------------

LOAD
        moveq   #io_fstrg,d0            ; set for string input
        cmpi.b  #4,fs_acces(a0)         ; directory access ?
        beq     join_io_routines        ; ... YES, read string
        cmpi.l  #$400,d2                ; less than 1K ?
        blt     join_io_routines        ; ... YES, read string
        bsr     FLUSH                   ; clear down slave blocks
        beq.s   L861
        rts

*       When drive stopped, then set up and start it for the
*       load process.

L861    bsr     START_PHYSICAL          ; start drive if idling
        lea     $18020,a3               ; set MDV control reg
        andi.b  #$FF-PC_MASKG,SV_PCINT(a6)      ; disable gap interrupt
        move.b  SV_PCINT(a6),1(a3)      ; set interrupt register
        ori.w   #$0700,SR               ; shut out outside world
        move.b  FS_DRIVN(a2),d0         ; get drive wanted
        cmp.b   SV_MDRUN(a6),d0         ; is required drive active ?
        beq.s   L862                    ; ... YES, can load
        moveq   #ERR_NC,d7              ; ... NO, set not complete
        bra     load_exit               ; ... and exit
L862    moveq   #7,d0                   ; set loop count
        lea     fs_spare(a0),a5
L863    clr.l   (a5)+                   ; clear area for bit map
        dbra    d0,L863
        move.l  fs_eblok(a0),d2         ; get end of file
        clr.w   d2                      ; clear any part block
        move.l  d2,fs_nblok(a0)         ; ... set for end of load
        swap    d2                      ; get block
        subq.w  #1,d2                   ; allow for base 1
        move.w  d2,d0                   ; save answer for later
        lea     fs_spare(a0),a5         ; start of bit map
        lsr.w   #3,d0                   ; get total bytes in bit map
        bra.s   L866
L865    st      (a5)+                   ; set complete bytes
L866    dbra    d0,L865                 ; loop until finished
        move.w  #$FF00,d1
        and.b   #7,d2                   ; get bits within last byte
        beq.s   L868                    ; ....NONE, then jump
        rol.w   d2,d1                   ; get bits into last byte
        move.b  d1,(a5)                 ; set last few bits of map
L868    movem.l a0/a1/a2/a4,-(a7)       ; save important registers
        clr.b   fs_flag2(a2)            ; clear retry count
        bra.s   load_check_finish
load_read_sector
        move.l  (a7),a0                 ; restore channel block address
        lea     fs_spare+(256/8)(a0),a5 ; set buffer address
        bsr     OPD_READ_HEADER         ; get next header
        bra.s   load_bad_medium         ; bad medium
        movem.l (a7),a0/a1/a2/a4        ; restore standard registers
        add.w   d7,d7                   ; convert sector to map displ.
        bne.s   load_check_wanted       ; jump if not sector zero

*       Sector Zero found, so check retry counts

        addq.b  #1,fs_flag2(a2)         ; update retry count
        cmpi.b  #8,fs_flag2(a2)         ; see if expired
        bge.s   load_bad_medium         ; ... if so, error exit
        PAGE
*       See if sector found needs to be loaded

load_check_wanted
        move.b  fs_sam(a2,d7.w),d0      ; find out who it belongs to
        cmp.b   (fs_filnr+1)(a0),d0     ; is it this file ?
        bne.s   load_read_sector        ; ... NO, go for next sector
        moveq   #0,d4                   ; clear work register
        move.b  (fs_sam+1)(a2,d7.w),d4  ; get block number within file
        subq.l  #1,d4                   ; convert to base zero
        move.l  d4,d7                   ; save result
        moveq   #7,d5                   ; set bit mask
        and.w   d4,d5                   ; get bit to test
        lsr.w   #03,d4                  ; ... and byte to test
        btst    d5,fs_spare(a0,d4.w)    ; loaded/not needed?
        beq.s   load_read_sector        ; ... YES, go for next sector
        bra.s   load_read               ; ... NO, go to read data block

load_bad_medium
        moveq   #err_fe,d7              ; ... else bad_medium
        bra.s   load_set_end

*       Calculate address at which to be loaded and then read it in

load_read
        lsl.w   #8,d7                   ; x 256
        add.l   d7,d7                   ;    x2 = displacement in file
        adda.l  d7,a1                   ; set start address
        move.w  d4,a5                   ; save D4 across read
        bsr     OPD_READ
        bra.s   load_read_sector        ; bad read - ignore it
        movem.l (a7),a0/a1/a2/a4        ; restore standard regs
        bclr    d5,fs_spare(a0,a5.w)    ; clear bit to say needs load

*       See if all of file blocks required loaded

load_check_finish
        moveq   #7,d0                   ; set loop count
        lea     fs_spare(a0),a5         ; get bit map address
L873    tst.l   (a5)+                   ; more to do?
        bne.s   load_read_sector        ; ... YES, do it
        dbra    d0,L873                 ; loop until finished
        moveq   #0,d7                   ; set OK so far

*       Tidy up before exiting

load_set_end
        movem.l (a7)+,a0/a1/a2/a4       ; remove work fields from stack
        clr.l   d1
        move.w  fs_nblok(a0),d1         ; get end of load
        subq.l  #1,d1                   ; allow for base 1
        lsl.l   #8,d1                   ; x 256
        lsl.l   #1,d1                   ;       x 2 = 512 = length
        adda.l  d1,a1                   ; set point reached
        move.l  fs_nblok(a0),-(SP)      ; save end position
        bsr     READ_FILE_HEADER        ; restore file header
        move.l  (SP)+,fs_nblok(a0)      ; restore end position
        PAGE
*       Tidy up after load.  If necessary start process to get last
*       incomplete block into store.

load_exit

        IFNE    TASK
        bsr     OPD_SLAVE               ; ********** STOP Drive ?
        ENDC

        andi.w  #$F8FF,SR               ; re-enable interrupts
        move.l  d7,d0                   ; set reply condition
        beq.s   L883                    ; ... No, continue
L882    rts
L883    move.l  fs_eblok(a0),d2         ; get end position
        sub.l   fs_nblok(a0),d2         ; calculate amount left
        beq.s   L882                    ; ... exit if none
        moveq   #io_fstrg,d0            ; set for string read
        bsr     OPD_INOUT               ; use internal call
        bra.s   L882                    ; and exit on completion
        PAGE
*------------------------------------------------------------------
*       Save a file from memory
*------------------------------------------------------------------

SAVE
        bsr     directory_read_only
        moveq   #io_sstrg,d0            ; set string write
        bra     join_io_routines

*------------------------------------------------------------------
*       Read a file header
*               D2.W    Buffer length
*               A1      Buffer address
*------------------------------------------------------------------

HEADR
        cmpi.b  #4,fs_acces(a0)
        bne.s   L891
        bsr     read_file_header
L891    moveq   #0,d1
        cmpi.w  #64,d2                  ; check within range
        blt.s   L892                    ; ... jump if so
        move.w  #64,d2                  ; ... else set to max
L892    lea     fs_header(a0),a4        ; get source address
L893    move.b  (a4)+,(a1)+
        add.w   #1,d1
        subq.w  #1,d2
        bne.s   L893
        bra.s   L909

*------------------------------------------------------------------
*       Set first 14 bytes of header
*------------------------------------------------------------------

HEADS
        bsr     directory_read_only
        moveq   #13,d0                  ; set loop count of 14
        lea     fs_header(a0),a4        ; get header start
L902    move.b  (a1)+,(a4)+
        dbra    d0,L902
        moveq   #14,d1
L909    bra.s   L919

error_bad_name
        moveq   #err_bn,d0
        rts
        PAGE
*------------------------------------------------------------------
*       Rename a file
*------------------------------------------------------------------

RENAM
        bsr     directory_read_only     ; check not directory access
        move.w  (a1)+,d4                ; get name length
        subq.w  #5,d4                   ; see if too short
        bls.s   error_bad_name          ; ... error if yes
        cmpi.w  #12,d4                  ; see if too long
        bhi.s   error_bad_name          ; ... error if yes
        move.l  #$DFDFDFFF,d0           ; set up mask
        and.l   (a1)+,d0                ; AND device part
        sub.b   fs_drivn(a2),d0         ; remove drive
        cmpi.l  #'OPD0',d0              ; see if right device type
L912    bne.s   error_bad_name
        cmpi.b  #'_',(a1)+              ; and finally underscore
        bne.s   L912
        cmpi.b  #1,fs_acces(a0)         ; check for shared access
        beq     error_read_only         ; ... if so, rename not allowed
        move.w  d4,fs_name(a0)          ; set file length
        move.w  d4,fs_spare+fh_name(a0) ; ... and in header
        lea     fs_name+2(a0),a3
        lea     fh_name+2+fs_spare(a0),a4
L914    move.b  (a1),(a3)+              ; move to channel block
        move.b  (a1)+,(a4)+             ; ... and to file header
        subq.w  #1,d4                   ; decrement remainder
        bne.s   L914                    ; ... loop until finished
renam_end
        move.l  fs_nblok(a0),-(SP)      ; save current file positions
        move.l  fs_eblok(a0),-(SP)
        bsr     WRITE_FILE_HEADER       ; write changed header
        move.l  (SP)+,fs_eblok(a0)      ; restore file positions
        move.l  (SP)+,fs_nblok(a0)
L919    moveq   #0,d0
        rts
        PAGE
*------------------------------------------------------------------
*       Truncate file at current position
*------------------------------------------------------------------

TRUNC
        bsr     directory_read_only     ; check not directory access
        move.l  fs_nblok(a0),d4         ; get current position
        move.l  d4,fs_eblok(a0)         ; store as end position
        subq.w  #1,d4                   ; set to last valid character
        bpl.s   L921
        sub.l   filestart,d4
L921    swap    d4                      ; get block to right of reg.
        move.w  fs_filnr(a0),d5

*       clear down map/action flags in phy/ def block

        lea     fs_sam(a2),a4           ; start of map area
        move.l  a4,a3                   ; and save start point
        adda.w  #448,a4                 ; start at end of area
L922    cmp.b   (a4),d5                 ; this file ?
        bne.s   L923                    ; ... jump if not
        cmp.b   1(a4),d4                ; before current position
        bcc.s   L923                    ; ... jump if so
        clr.w   (a4)                    ; clear entry
        clr.w   (fs_action-fs_sam)(a4)  ; ... and outstanding action
        addq.b  #1,fs_free(a2)          ; update free sector count
L923    subq.l  #2,a4                   ; step back
        cmpa.l  a3,a4                   ; finished
        bge.s   L922                    ; ... no, then loop

*       clear down slave area

        move.l  sv_btbas(a6),a4         ; start of slave table
L925    moveq   #-15,d0                 ; Mask F1
        and.b   (a4),d0                 ; look at slave block
        cmp.b   d0,d6                   ; this drive ?
        bne.s   L926                    ; ... jump if not
        cmp.w   bt_filnr(a4),d5         ; this file ?
        bne.s   L926                    ; ... jump if not
        cmp.w   bt_block(a4),d4         ; current file position ?
        bcc.s   L926                    ; ... jump if earlier/equal
        move.b  #1,(a4)                 ; set block as free
L926    addq.l  #8,a4                   ; update to next slave entry
        cmpa.l  sv_bttop(a6),a4         ; finished ?
        blt.s   L925                    ; ... no, then loop for more
        bsr     WRITE_MAP               ; set flags to update map
        st      fs_updt(a0)             ; set file update marker
        bsr     WRITE_MAP               ; set for map update
        bsr     OPD_SLAVE               ; start write process
        bra.s   L919

