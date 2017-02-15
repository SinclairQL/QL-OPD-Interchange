
*======================================================================
*       These are the general IO_routines used for reading/writing
*       General Register Usage is:
*               D1      File Position/Length transfered
*               D3      Read/Write + terminator Indicator
*                                          0 = Status only (FS_PEND)
*                                        -ve = write
*                                       $100 = read, no terminator
*                                      >$100 = read, with terminator
*               D4      File Position (Block/Byte)
*               D5      File/Block
*               D6      Drive Id x 16 (ie. 1 nibble to left)
*               D7      Address at which read/write finishes
*               A1      Current Buffer address
*               A4      Current Slave Block Entry Address
*               A5      Current Slave Block Address
*=====================================================================

IO_ROUTINES
        ext.l   d1                      ; convert to 32 bit values
        ext.l   d2
join_io_routines
        cmpi.b  #7,d0                   ; check within range
        bhi     error_bad_parameter
        moveq   #0,d7                   ; clear
        tst.l   d3                      ; first entry ?
        beq.s   L932                    ; ... yes, then jump
        sub.l   d1,d7                   ; ... no, allow for transfered
L932    subq.b  #4,d0                   ; Trap value #4 ?
        beq     error_bad_parameter     ; ... not supported for MDV
        blt.s   INPUT                   ; jump if input
OUTPUT
        move.b  fs_acces(a0),d3         ; get access mode
        subq.b  #1,d3                   ; mode 1 (shared file) ?
        beq     error_out_of_range      ; ...YES, then error
        bsr     directory_read_only     ; check not directory access
        moveq   #-1,d3
        subq.w  #2,d0                   ; trap value=6
        beq     error_bad_parameter     ; ... not supported
        bmi.s   BYTE_IO                 ; trap value=5
        bpl.s   STRING_IO               ; trap value=7

*       Set the terminating character (if any) for string input

INPUT
        moveq   #0,d3                   ; set no terminator
        addq.b  #4,d0
        beq.s   BYTE_IO                 ; Trap value = 0 (FS_PEND)
        move.w  #256,d3                 ; set for NO terminator
        subq.b  #2,d0
        blt.s   BYTE_IO
        bgt.s   STRING_IO
        moveq   #10,d3                  ; set LF terminating character
        PAGE
*----------------------------------------------------------------------
*       Determine type of access required, so that end condition and
*       Return conditions set correctly.
*----------------------------------------------------------------------

*       Set IO finish condition & call main loop

STRING_IO
        add.l   a1,d7                   ; set end address
        move.l  d7,-(a7)                ; save it
        add.l   d2,d7                   ;
        bsr.s   io_main_loop            ;
        move.l  a1,d1                   ;
        sub.l   (a7)+,d1                ; convert to length
        rts

*       Set IO finish condition & Call main loop

BYTE_IO
        move.l  d1,-(a7)
        lea     3(a7),a1                 ; byte pointer to data
        move.l  a1,d7
        addq.l  #1,d7                    ; set end address
        bsr.s   io_main_loop             ; call main move routine
        move.l  (a7)+,d1                 ; restore original data
b_exit  rts
        PAGE
*----------------------------------------------------------------------
*       Main loop for actually transferring data to/from the
*       Slave blocks and the user buffer.
*----------------------------------------------------------------------

io_main_loop
        tst.b   fs_flag1(a2)            ; check status flag
        bmi     error_bad_medium        ; ... error if -ve
        move.l  fs_filnr(a0),d5
        move.l  fs_nblok(a0),d4
        cmp.l   fs_eblok(a0),d4         ; end of file reached
        blt.s   before_end_of_file
        bgt     error_end_of_file
        tst.b   d3                      ; check for write mode
        bge     error_end_of_file
        tst.w   d4                      ; see if start of block
        beq.s   write_new_block

*       If before the end of file, then find slave block, or else a
*       new one is allocated and existing contents read in

before_end_of_file
        cmpi.b  #4,fs_acces(a0)
        beq     directory_read
        bsr     find_slave_block        ; see if block in memory
        bne.s   b_exit                  ; ... exit if not complete
        tst.w   d4                      ; see if first char in block
        bne     check_slave_status      ; ... and jump if not

*       If end-of-file not reached, then start read of following
*       block also in advance

read_next_block
        move.l  a4,-(SP)                ; save current slave block id
        addq.w  #1,d5                   ; update block number
        moveq   #0,d2
        move.w  d5,d2                   ; get block
        swap    d2                      ; convert to block/byte
        cmp.l   fs_eblok(a0),d2         ; see if beyond end ?
        bge.s   L953                    ; ... jump if not
        bsr     load_slave_block        ; go to get next block
L953    move.l  (SP)+,a4                ; reset original slave block
        subq.w  #1,d5                   ; ... and block number
        bra.s   check_slave_status
        PAGE
*----------------------------------------------------------------------
*       This routine is used to write a new block of the file.
*       A new slave block is allocated, and then the map searched
*       to set up the correct block number
*----------------------------------------------------------------------

write_new_block
        cmp.l   a1,d7                   ; see if finished
        bls     exit_ok
        bsr     get_slave_block
        bsr     initialise_map_search
        subq.b  #1,d2                   ; see if first block
        bne.s   L962                    ; .. if not file must exist
        moveq   #-40,d0                 ; ... else set optimum start
        add.w   fs_last(a2),d0          ; add last sector allocated
        bra.s   L963
L962    bsr     find_map_entry          ; find last sector allocated
L963    addq.b  #1,d2                   ; restore D2 to intended
        subq.w  #8,d0                   ; go back 4 blocks
        bpl.s   L965                    ; ... and jump if not too far
        move.w  #450,d1                 ; set to end of potential map
L964    subq.w  #2,d1                   ; search backwards
        cmpi.b  #$FF,fs_sam(a2,d1.w)    ; see if flawed
        beq.s   L964                    ; ... and ignore if yes
        add.w   d1,d0                   ; set current position
L965    move.w  d0,-(SP)                ; store scan start
L966    subq.w  #2,d0                   ; next block
        bpl.s   L967                    ; ... before beginning
        move.w  #448,d0                 ; reset to end value
L967    tst.b   fs_sam(a2,d0.w)         ; sector free ?
        beq.s   drive_not_full          ; .. yes
        cmp.w   (a7),d0                 ; value=start ?
        bne.s   L966                    ; ... no, then continue looking
        addq.l  #2,SP                   ; ... YES, tidy stack
error_drive_full
        moveq   #err_df,d0              ; ... ERROR exit
        rts
drive_not_full
        subq.b  #1,fs_free(a2)          ; reduce free count
        move.w  d2,fs_sam(a2,d0.w)      ; set as in use
        move.w  d0,fs_last(a2)          ; store last allocated
        bsr     write_map               ; set to update copy on tape
        addq.l  #2,SP                   ; tidy stack
        move.w  d0,2(a4)                ; store block number
        ori.b   #bt_true,(a4)           ; slave status to accessible
        PAGE
*----------------------------------------------------------------------
*       This point is used once the relevant slave blocks are known
*       to be in store to determine if the end of the transfer has
*       yet been reached, and if not to read/write bytes.
*----------------------------------------------------------------------

check_slave_status
        move.l  a4,fs_cblok(a0)         ; store as current slave entry
        btst    #bt_accs,(a4)           ; see if contents accessible
        beq     start_slave             ; ... if not then start process
        tst.w   d3                      ; status only
        beq.s   exit_ok                 ; ... YES, exit
        move.l  a4,d0                   ; get slave block address
        sub.l   sv_btbas(a6),d0         ; convert to entry number
        lsl.l   #6,d0                   ; ... then address displacement
        move.l  d0,a5
        adda.l  a6,a5                   ; calculate real address
        adda.w  d4,a5                   ; add address in blovk
        tst.w   d3                      ; see if reading
        bgt.s   read_byte               ; ... and jump if yes
write_byte
        cmp.l   a1,d7                   ; see if finished
        bls.s   L977                    ; ... jump if so
        move.b  (a1)+,(a5)+             ; move across data character
        bsr.s   increment_file_position
        bne.s   write_byte              ; loop if not block boundary

        IFEQ    TASK
        bsr     OPD_SLAVE               ; start write process
        ENDC

L977    st      fs_updt(a0)             ; set update flag
        bsr.s   set_update_action
        move.l  d4,fs_nblok(a0)
        cmp.l   fs_eblok(a0),d4
        blt.s   check_end_condition
        move.l  d4,fs_eblok(a0)
        bra.s   check_end_condition
exit_ok
        moveq   #0,d0
        rts
        PAGE
*       This routine is used to read a byte(s)

read_byte
        moveq   #0,d0
L982    move.l  d4,fs_nblok(a0)         ; store point reached
        cmp.l   a1,d7                   ; finished ?
        bls.s   check_end_condition     ; ... YES, then jump
        cmp.l   fs_eblok(a0),d4         ; End of file reached ?
        beq.s   error_end_of_file       ; ... Yes, then error
L983    move.b  (a5)+,d0                ; get character
        move.b  d0,(a1)+                ; store it in buffer
        cmp.w   d0,d3                   ; terminating character?
        bne.s   L984                    ; jump if not
        move.l  a1,d7                   ; set end to current
L984    bsr.s   increment_file_position
        bne.s   L982
        move.l  d4,fs_nblok(a0)
check_end_condition
        cmp.l   a1,d7                   ; finished ?
        bhi     io_main_loop            ; ... NO, then loop for more
        cmpi.w  #10,d3                  ; CR return required
        bne.s   exit_ok                 ; No, then exit OK
        cmp.b   d0,d3                   ; CR found
        beq.s   exit_ok
error_buffer_overflow
        moveq   #err_bo,d0
        rts
error_end_of_file
        moveq #err_ef,d0
        rts

increment_file_position
        addq.w  #1,d4                   ; next character position
        btst    #9,d4                   ; >511?
        beq.s   L988                    ; if not exit
        addq.w  #1,d5                   ; update file/block pointer
        add.l   #($00010000-512),d4     ; update block/char pointer
L988    tst.w   d4                      ; set condition code
        rts

set_update_action
        moveq   #bt_updt,d0             ; set updated mask/bits
        or.b    d6,d0                   ; ... plus drive id etc
        move.b  d0,(a4)                 ; ... and store in slave entry
set_action
        move.l  a4,d1
        sub.l   sv_btbas(a6),d1
        lsr.l   #3,d1                   ; convert to slave entry number
        adda.w  2(a4),a2                ; ... add displacment
        move.w  d1,fs_action(a2)        ; and set action flag
        suba.w  2(a4),a2                ; restore a2
        sf      fs_flag2(a2)            ; clear flag2 for phy layer
        rts
        PAGE
*---------------------------------------------------------------------
*       This routine looks for the slave block, and if neccesary
*       starts read process to get it into memory
*
*       Scan starts at 'FS_CBLOK', or 'SV_BTPNT' if that not set
*       and works backwards through the Slave Block Table.
*---------------------------------------------------------------------

find_slave_block
        move.l  fs_cblok(a0),a4         ; get last slave block accessed
        move.l  a4,d0                   ; was there one ?
        bne.s   load_slave_block        ; ... YES, jump
        move.l  sv_btpnt(a6),a4         ; ... NO
load_slave_block
        move.l  a4,a5                   ; save value of start point
L993    moveq   #bt_inuse,d0
        and.b   (a4),d0                 ; is block empty
        beq.s   L995                    ; ... yes, go for next
        moveq   #-16,d0                 ; Mask $F0
        and.b   (a4),d0                 ; screen out drive id
        cmp.b   d0,d6                   ; this drive ?
        bne.s   L995                    ; ... NO, go for next
        cmp.l   4(a4),d5                ; this file/block ?
        bne.s   L995                    ; ... NO, go for next
        moveq   #0,d0                   ; ...YES, then OK return
        rts
L995    subq.l  #8,a4                   ; Next entry
        cmpa.l  sv_btbas(a6),a4         ; Bottom of table reached ?
        bge.s   L997                    ; ... NO, then jump
        move.l  sv_bttop(a6),a4         ; ... YES, reset to top
L997    cmpa.l  a4,a5                   ; Start point reached ?
        bne.s   L993                    ; ... NO, continue scan
        bsr     search_map              ; ... YES, find it in map
        bsr     get_slave_block         ; allocate slave block
        move.w  d0,2(a4)                ; store slave block id
        ori.b   #bt_rreq,(a4)           ; set read request
        bsr.s   set_action              ; set phy layer action required
start_slave
        bsr     OPD_SLAVE               ; start physical layer
        moveq   #err_nc,d0
        rts
        PAGE
*-------------------------------------------------------------------
*       These following routines are used for searching the map for
*       an existing entry corresponding to D5
*-------------------------------------------------------------------

search_map
        bsr.s   initialise_map_search
        bsr.s   find_map_entry
        rts
initialise_map_search
        move.w  #450,d0
        move.l  d5,d2
        lsl.w   #8,d2                   ; set file/block word
        lsr.l   #8,d2
        rts
find_map_entry
L1001   subq.w  #2,d0                   ; next entry
        bmi.s   L1003                   ; ... error if before beginning
        cmp.w   fs_sam(a2,d0.w),d2      ; this one ?
        bne.s   L1001                   ; ... no, then try again
        rts
L1003   addq.w  #8,a7                   ; remove 2 x return address
error_bad_medium
        moveq   #err_fe,d0
        rts

*-------------------------------------------------------------------
*       This routine is responsible for setting up the flags to make
*       the physical layer write new copies of the volume map.
*-------------------------------------------------------------------

write_map
        movem.l d0/d5,-(a7)
        move.l  #$00010001,d5           ; set for !CAT1
        bsr.s   search_map              ; ... find sector
        add.w   #512,d0                 ; allow for only 8 bit displ.
        move.w  #-1,fs_vol(a2,d0.w)     ; ... set flag to write
        move.l  #$00020001,d5           ; set to !CAT2 value
        bsr.s   search_map              ; ... find sector
        add.w   #512,d0
        move.w  #-1,fs_vol(a2,d0.w)     ; ... set flag to write
        movem.l (a7)+,d0/d5
        rts
        PAGE
*----------------------------------------------------------------------
*       This routine finds a free slave block to use.
*
*       The search starts at 'SV_BTPNT', and moves forward.
*----------------------------------------------------------------------

get_slave_block
        move.l  sv_btpnt(a6),a4
        move.l  a4,a5                   ; save start point
L1011   addq.w  #8,a4                   ; increment
        cmpa.l  sv_bttop(a6),a4         ; end of table ?
        blt.s   L1013                   ; ... no, then jump
        move.l  sv_btbas(a6),a4         ; ... yes, reset to start
L1013   moveq   #15,d1                  ; Mask 0F
        and.b   (a4),d1                 ; mask out drive
        subq.b  #1,d1                   ; see if free
        beq.s   L1016                   ; ... yes, so use it
        subq.b  #2,d1                   ; now see if true copy
        beq.s   L1016                   ; ... yes, so use it
        cmpa.l  a5,a4                   ; finished scan
        bne.s   L1011                   ; ... no, then loop
        bsr     OPD_SLAVE               ; start physical layer
        addq.l  #4,SP                   ; remove return address
        bra     error_not_complete

L1016   move.l  a4,sv_btpnt(a6)         ; save last block found
        move.l  a4,fs_cblok(a0)         ; ... and set current for file
        move.b  d6,(a4)                 ; set as drive
        ori.b   #1,(a4)                 ; ... in use
        move.l  d5,bt_filnr(a4)         ; ... for file/block
        rts
