
*-----------------------------------------------------------------
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D0                              Error Key
*       D1      Drive Number            Good Sectors
*       D2                              Total Sectors
*       A1      Medium Name Pointer
*       A3      Directory Driver Linkage
*       A6      System Variables
*
*       REGISTERS SMASHED:  D3-D7,A0-A5
*
*       ERRORS:         FF      Format failed
*                       IU      In Use
*                       OM      Out of memory
*-----------------------------------------------------------------

*       Constants

catalog dc.b    '!CAT1 '                ; catalog name
mctrl   dc.l    pc_mctrl

*       Work Areas (on stack)

memory_base     equ     0
map_base        equ     4
hdr_base        equ     8
buf_base        equ     12
medium_base     equ     16
sectors         equ     20
drive           equ     24
good            equ     26
total           equ     28
work_size       equ     30              ; total space required

OPD_FORMAT
        tst.b   sv_mdrun(a6)            ; drive in use ?
        bne     ERROR_IN_USE            ; ... YES, then error exit
        suba.w  #work_size,SP           ; reserve stack area
        move.w  d1,drive(SP)            ; save drive
        move.l  a1,medium_base(SP)      ; save medium name address

*       Find out if a Physical definition block already exists for
*       this drive.

        moveq   #15,d7                  ; set loop count (-1)
L302    move.l  d7,d0                   ; get current ID
        lsl.l   #2,d0                   ; x4 to give displacement
        lea     SV_FSDEF(a6),a4
        adda.l  d0,a4
        tst.l   (a4)                    ; used ?
        beq.s   L308                    ; NO, jump
        move.l  (a4),a5                 ; get address of Phy Def
        move.b  FS_DRIVN(a5),d1         ; ... and extract drive number
        cmp.b   drive+1(SP),d1          ; same drive ?
        bne.s   L308                    ; ... NO, jump
        lea     access,a1               ; get OPD access level address
        cmpa.l  FS_DRIVR(a5),a1         ; OPD drive ?
        beq.s   format_clear            ; ... YES, go to clear
L308    dbra    d7,L302                 ; loop for next
        bra.s   format_memory
        PAGE
*       Check that there are no files still open on this drive. If not
*       clear down any in-store information for this drive

format_clear
        tst.b   FS_FILES(a5)
        beq.s   L315
        moveq   #ERR_IU,d0
        bra     opd_format_exit5
L315    bsr     RESET_PHYSICAL_DEF      ; Phy Def pointer in A5

*       Allocate memory required for formatting

format_memory
        move.l  #(16+512+12+620),d1     ; space wanted
        move.w  MM_ALCHP,a0             ; allocate heap vector
        jsr     (a0)
        bne     opd_format_exit5        ; ... Failed, then exit

*       Set up and store pointers

        move.l  a0,memory_base(SP)      ; memory_base
        lea     16(a0),a0
        move.l  a0,map_base(SP)         ; map_base
        lea     512(a0),a0
        move.l  a0,hdr_base(SP)         ; hdr_base
        lea     12(a0),a0
        move.l  a0,buf_base(SP)         ; buf_base
        clr.w   good(SP)
        clr.w   total(SP)

*       Initialise volume map

init_map
        move.l  map_base(SP),a0
        move.b  #1,vol_flag(a0)         ; set for non-kernel formatting
        move.l  #'ICL ',vol_icl(a0)
        lea     vol_name(a0),a2
        moveq   #9,d1
L333    move.b  #' ',(a2)+              ; spacefill medium name
        dbra    d1,L333
        lea     vol_name(a0),a2
        move.l  medium_base(SP),a1
        move.w  (a1)+,d1                ; get users count
        addq.w  #5,a1                   ; skip over device name
        subq.w  #5,d1                   ; ... and adjust count
        cmpi.w  #8,d1                   ; less than 8 ?
        bls.s   L334                    ; ... YES, then OK
        moveq   #8,d1                   ; ... else set length to 8
L334    move.b  (a1)+,(a2)+             ; move across name
        subq.w  #1,d1
        bgt.s   L334
        PAGE
*       Read existing volume map for volume data (if you can)
*       ... and move across lifetime field

        move.w  drive(SP),d3
        bsr     OPD_START
        bne     opd_start_failed
        move.l  buf_base(SP),a5
        bsr     OPD_READ_VOLUME_MAP
        bne.s   init_buffer             ; failed, then continue
        move.l  buf_base(SP),a4
        move.l  map_base(SP),a5
        move.l  (a4),(a5)               ; move across lifetime field


*       Initialise header & data buffers for writing

init_buffer
        move.l  hdr_base(SP),a0
        moveq   #-1,d0
        move.w  d0,(a0)+                ; set first byte to $FF
        move.l  map_base(SP),a4
        lea     vol_name(a4),a4
        moveq   #9,d1
L353    move.b  (a4)+,(a0)+             ; move across medium name
        dbra    d1,L353
        move.l  buf_base(SP),a0
        move.l  #$00000F0F,(a0)+        ; block header + checksum
        clr.l   (a0)+                   ; skip 10 bytes zero pre-amble
        clr.l   (a0)+
        clr.w   (a0)+
        move.w  d0,(a0)+                ; move two bytes $FF to end
        move.w  #(590/2-1),d1           ; set loop count
L355    move.w  #$AA55,(a0)+            ; set test pattern
        dbra    d1,L355

opd_format_write
        lea     table_base,a5
        move.b  #pc_eras,(a3)           ; set erase on/write off
        move.l  hdr_base(SP),a1
L361    moveq   #11,d1                  ; set for 12 bytes (-1)
        move.w  fmtgap2,d0              ; set wait count for GAP 2
L362    dbra    d0,L362                 ; ... and wait
        bsr     opd_format_block_write  ; ... then write header block
        move.w  #589,d1                 ; set for 590 bytes (-1)
        move.w  fmtgap1,d0              ; set wait count for GAP 1
L363    dbra    d0,L363                 ; ... and wait
        move.l  buf_base(SP),a1
        bsr     opd_format_block_write  ; then write data block
        move.l  hdr_base(SP),a1
        subq.b  #1,1(a1)                ; decrement block number
        bcc.s   L361                    ; loop until complete
        PAGE
opd_format_verify
        move.b  #pc_read,(a3)           ; switch to write mode
L372    move.l  hdr_base(SP),a5         ; re-use sector header space
        bsr     OPD_READ_HEADER         ; look for sector header
        bne     opd_format_failed
        move.l  buf_base(SP),a1
        bsr     OPD_GAP                 ; wait for gap
        bra.s   L372                    ; ... ERROR - ignore block
        move.w  #589,d1                 ; set for 590 bytes (-1)
        bsr     BLOCK_VERIFY
        bra.s   L372                    ; ... ERROR - ignore block
        add.w   d7,d7                   ; double sector number
        move.l  map_base(SP),a1
        subq.b  #1,vol_sam(a1,d7.w)     ; decrement to give read count
        cmpi.b  #-4,vol_sam(a1,d7.w)    ; finished ?
        bne.s   L372
        bra.s   opd_format_check
L378    bra     opd_format_failed

opd_format_block_write
        lea     L382,a4
        bra     OPD_BLOCK_WRITE
L382    moveq   #PC_ERAS,d4
        moveq   #48,d0                  ; set wait count
L383    dbra    d0,L383
        move.b  d4,(a3)
        rts

*       Now see what blocks are OK

opd_format_check
        moveq   #0,d5                   ; clear checked count
        move.l  map_base(SP),a1
        lea     vol_sam(a1),a1
L391    subq.b  #1,(a1)                 ; convert entry to neg number
        cmpi.b  #$FE,(a1)               ; passed format ?
        st.b    (a1)                    ; set as flawed in case not
        bgt.s   L393                    ; ... Failed twice/missing
        beq.s   L392                    ; ... failed once
        addq.w  #1,good(SP)             ; update good count
        move.b  #0,(a1)                 ; set as OK/Available
L392    move.w  d5,total(SP)            ; set highest sector found
        move.b  (a1),d4                 ; ... save status
        move.l  a1,a4                   ; save map address
L393    sf.b    1(a1)                   ; clear block within file
        addq.w  #2,a1                   ; update for next entry
        addq.w  #1,d5                   ; update checked count
        cmpi.b  #225,d5                 ; end reached ?
        bcc.s   L391                    ; ... NO, go for next
        st.b    (a4)                    ; map out highest for safety
        addq.b  #2,d4                   ; ... but check it
        beq.s   L394                    ; ... jump if OK
        subq.w  #1,good(SP)             ; ... else reduce good count
        PAGE
*       Now write standard empty blocks to each sector

L394    move.w  #250,-(SP)              ; set count to more than max
        clr.w   -(SP)                   ; set for file 0/block 0
L395    move.l  hdr_base+4(SP),a5       ; re-use sector header space
        bsr     OPD_READ_HEADER         ; look for sector header
        bne     opd_format_failed
        move.l  buf_base+4(SP),a1       ; set buffer address
        adda.w  #16,a1                  ; ... after header data
        bsr     OPD_WRITE               ; write standard block
        subq.w  #1,2(SP)                ; reduce count
        bne.s   L395                    ; loop until complete
        addq.l  #4,SP                   ; remove work fields

*       Complete Volume map set up

        move.l  map_base(SP),a1
        move.w  total(SP),d0
        move.b  d0,vol_size(a1)         ; set total size
        move.b  d0,vol_flaws(a1)
        move.w  good(SP),d0
        sub.b   d0,vol_flaws(a1)        ; flaws = total - good
        subq.b  #4,d0                   ; free = good - 4 (for catalog)
        move.b  d0,vol_free(a1)

*       Initialise Catalog file entries
*       (re-use data buffer for workspace)

init_cat
        moveq   #127,d1
        move.l  buf_base(SP),a0
L411    clr.l   (a0)+
        dbra    d1,L411
        move.l  buf_base(SP),a0
        move.b  #3,fd_type(a0)          ; set file type for catalog
        move.l  #1024,fd_size(a0)       ; size = 2 x512
        move.b  #1,fd_num(a0)           ; File Number 1
        moveq   #5,d1
        lea     catalog,a1
L412    move.b  (a1)+,(a0)+             ; File name
        dbra    d1,L412
        moveq   #13,d1
L413    move.b  #' ',(a0)+              ; Spacefil directory
        dbra    d1,L413
        moveq   #MT_RCLCK,d0
        TRAP    #1
        move.l  buf_base(SP),a0
        sub.l   adjdate,d1              ; convert date to OPD base
        move.l  d1,fd_ctime(a0)
        move.l  d1,fd_utime(a0)

        moveq   #10,d0                  ; now !CAT2
        lea     44(a0),a1
L414    move.l  (a0)+,(a1)+
        dbra    d0,L414
        move.l  buf_base(SP),a0
        move.b  #2,(fd_num+44)(a0)
        addq.b  #1,(fd_name+4+44)(a0)
        PAGE
*       Allocate blocks for catalog

allocate_catalog
        move.l  map_base(SP),a0         ; start of vol header buffer
        lea     sectors(SP),a1          ; set sector pointer
        clr.l   (a1)
        moveq   #20,d0
        moveq   #1,d1                   ; file 1
        bsr.s   L428
        moveq   #127,d0                 ; 2nd copy at half way
        moveq   #2,d1                   ; file 2
        bsr.s   L428
        bra.s   write_catalog

L428    moveq   #1,d2                   ; block 1
        bsr.s   get_map_entry
        subq.w  #7,d0
        bsr.s   get_map_entry
        rts

*       This routine is used to find a free map entry.
*               D0 = start sector for search
*               D1 = required file number
*               D2 = required block number
*               A0 = Volume header buffer
*               A1 = address to store sector number

get_map_entry
L432    move.w  d0,d4
        add.w   d4,d4
        move.b  vol_sam(a0,d4.w),d3     ; is sector free ?
        beq.s   L433                    ; ... YES, jump
        dbra    d0,L432
        move.w  #225,d0
        bra.s   L432
L433    move.b  d1,vol_sam(a0,d4.w)     ; set file number
        move.b  d2,(vol_sam+1)(a0,d4.w) ; ... and block number
        move.b  d0,(a1)+                ; store sector number
        addq.b  #1,d2                   ; update block number
        rts

*       Write catalogs

write_catalog
        move.b  sectors(SP),d2
        move.l  map_base(SP),a1
        bsr.s   write_catalog_block

        move.b  sectors+1(SP),d2
        move.l  buf_base(SP),a1
        bsr.s   write_catalog_block

        move.b  sectors+2(SP),d2
        move.l  map_base(SP),a1
        bsr.s   write_catalog_block

        move.b  sectors+3(SP),d2
        move.l  buf_base(SP),a1
        bsr.s   write_catalog_block

        clr.l   d7
        bra.s   opd_format_exit
        PAGE
*       Write the block given by A1 to the sector given by D2

write_catalog_block
        move.l  hdr_base+4(SP),a5
        move.l  a1,-(SP)                ; save buffer address
        bsr     OPD_POSITION
        bra.s   L458                    ; ... ERROR
        move.l  (SP)+,a1                ; restore buffer address
        move.l  map_base+4(SP),a0       ; calculate map entry address
        andi.w  #$FF,d2
        add.w   d2,d2                   ; convert to index
        move.w  vol_sam(a0,d2.w),-(SP)  ; set file/block
        bsr     OPD_WRITE
        addq.l  #2,SP                   ; remove file/block
        rts
L458    adda.w #12,SP                   ; remove buffer/2 x links
opd_format_failed
        moveq   #ERR_FF,d7
        bra.s   opd_format_exit
opd_start_failed
        move.l  d0,d7
        bra.s   opd_format_exit2
opd_format_exit
        bsr     DESEL                   ; deselect drive
        bsr     RS232_SET               ; reset RS232
        andi.w  #$F8E0,SR               ; re-enable interrupts
opd_format_exit2
        move.l  memory_base(SP),a0
        move.w  MM_RECHP,a2
        jsr     (a2)
        move.w  good(SP),d1             ; good sectors
        move.w  total(SP),d2            ; total sectors
        move.l  d7,d0                   ; return code
opd_format_exit5
        adda.w  #work_Size,SP           ; remove work fields
        tst.l   d0
        rts
