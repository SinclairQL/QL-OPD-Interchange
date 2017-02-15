
****************************************** AMENDED: 20/04/87 *******
**                                                                **
**      The routines in this section handle the mapping of the    **
**      OPD catalog to/from QL directory formats                  **
**                                                                **
********************************************************************

*       Check if directory access, and error if so

directory_read_only
        cmpi.b  #4,fs_acces(a0)         ; directory access ?
        beq.s   L1023                   ; ... if yes, then jump
        rts
L1023   addq.l  #4,SP                   ; remove return address
error_read_only
        moveq   #err_ro,d0
        rts

*       Move logical values to normal header area

directory_move_logical
        cmpi.b  #4,fs_acces(a0)         ; directory access ?
        bne.s   L1039                   ; ... NO, exit
        move.l  fs_nblokdir(a0),fs_nblok(a0)
L1039   rts

*       Move logical values back to storage area, and then calculate
*       beginning of file header from logical position

directory_move_real
        cmpi.b  #4,fs_acces(a0)         ; directory access ?
        bne.s   L1049                   ; ... NO, exit
        move.l  fs_nblok(a0),fs_nblokdir(a0) ; store new value
        movem.l d0/d1,-(SP)             ; save registers used
        move.l  fs_nblokdir(a0),d0      ; get logical value
        sub.l   filestart,d0            ; convert to true length
        lsl.w   #7,d0
        lsr.l   #7,d0
        lsr.l   #6,d0                   ; Divide by 64 to get files
        divu    #11,d0                  ; Divide by 11 for blocks
        addq.w  #2,d0                   ; allow for map/base 0
        moveq   #44,d1
        swap    d0
        mulu    d0,d1                   ; calculate position in block
        move.w  d1,d0                   ; add position in block
        move.l  d0,fs_nblok(a0)
        movem.l (SP)+,d0/d1
L1049   rts
        PAGE
*----------------------------------------------------------------
*       This routine handles the read cycle when a directory is
*       being read
*----------------------------------------------------------------

directory_read
        clr.l   d0                      ; clear work register
L1101   cmp.l   a1,d7                   ; read finished ?
        bls     check_end_condition     ; ... yes, then go to set reply
        bsr.s   directory_get_ready
        beq.s   L1103                   ; jump if not header start
        sub.l   filestart,d4            ; convert to length
        lsl.w   #7,d4
        lsr.l   #7,d4
        lsr.w   #6,d4                   ; convert to file number
        addq.w  #3,d4                   ; add base 3
        move.w  d4,fs_filnr(a0)         ; store as required number
        bsr     READ_FILE_HEADER        ; get header
        beq.s   L1102                   ; ... OK, go to transfer data
        rts                             ; ... ERROR, then exit
L1102   tst.w   d3                      ; status only ?
        beq     EXIT_OK
        bsr.s   directory_get_ready
L1103   lea     fs_spare(a0),a5         ; get header start
        adda.w  d0,a5                   ; ... plus point in header
        move.b  (a5)+,d0                ; get source character
        move.b  d0,(a1)+                ; store in destination
        cmp.w   d0,d3                   ; see if terminator found ?
        bne.s   L1104                   ; ... and jump if not
        move.l  a1,d7                   ; ... else force end condition
L1104   bsr     increment_file_position ; update position
        move.l  d4,fs_nblokdir(a0)      ; ... store it
        bra.s   L1101                   ; ... loop for more

directory_get_ready
       move.l  fs_nblokdir(a0),d4
       move.b  d4,d0
       andi.b  #$3F,d0
       rts

*       This routine calculates the directory position from the
*       file number

make_directory_position
        move.l  d0,-(SP)                ; save registers used
        moveq   #0,d0
        move.w  fs_filnr(a0),d0
        subq.w  #1,d0                   ; convert to zero base
        divu    #11,d0
        addq    #2,d0                   ; allow for map + base 1
        move.w  d0,fs_nblok(a0)
        swap    d0
        mulu    #44,d0
        move.w  d0,fs_nbyte(a0)
        move.l  fs_nblok(a0),d0         ; get next position
        cmp.l   fs_eblok(a0),d0         ; after current end ?
        ble.s   L1208                   ; ... NO, then jump
        move.l  d0,fs_eblok(a0)         ; ... YES, then reset
L1208   move.l  (SP)+,d0                ; restore registers
        rts
        PAGE
*---------------------------------------------------------------------
*       Read/write file headers
*
*       The catalog position is calculated from the file number.
*----------------------------------------------------------------------

read_file_header
        moveq   #io_fstrg,d0            ; set to read
        bra.s   file_header

write_file_header
        bsr.s   header_ql_to_opd        ; change header to OPD format
        moveq   #io_sstrg,d0            ; set to write

file_header
        movem.l d1-d3,-(SP)
        move.l  d0,-(SP)                ; save action wanted
        cmpi.b  #io_fstrg,d0            ; read ?
        beq.s   L1305                   ; ... YES, jump !CAT2 access
        moveq   #2,d1                   ; set for !CAT2
        bsr.s   header
        bne.s   L1308
L1305   move.l  (SP),d0                 ; restore required action
        moveq   #1,d1                   ; set for !CAT1
        bsr.s   header
L1308   addq.l  #4,SP                   ; remove stored action
        movem.l (SP)+,d1-d3             ; restore registers
        bsr     header_opd_to_ql        ; restore/make QL format header
ccode   tst.b   d0                      ; set condition code
        rts

*       This routine reads/writes the header to the catalog copy
*       given by the value of D1

header
        move.l  a1,-(SP)                ; save registers used
        move.l  fs_acces(a0),-(SP)      ; save access/drive/file No.
        bsr.s   make_directory_position ; set up pointers
        move.w  d1,fs_filnr(a0)         ; set catalog file number
        move.b  #2,fs_acces(a0)         ; set for write access
        lea     fs_spare(a0),a1         ; file header buffer address
        moveq   #44,d2                  ; set I/O length
        bsr     OPD_INOUT
        move.l  (SP)+,fs_acces(a0)      ; restore access/drive/file No.
        move.l  (SP)+,a1                ; restore register used
        bra.s   ccode
        PAGE
*----------------------------------------------------------------------
*       Convert a QL format header into OPD format
*----------------------------------------------------------------------

header_ql_to_opd
        movem.l d0-d1/a2-a3,-(SP)       ; save registers used
        lea     fs_spare(a0),a3         ; set start of header pointer
        move.l  adjdate,d0
        move.l  fh_rdate(a3),fd_ctime(a3)
        sub.l   d0,fd_ctime(a3)
        move.l  fh_udate(a3),fd_utime(a3)
        sub.l   d0,fd_utime(a3)
        move.l  fh_user(a3),fd_extra(a3)
        move.l  fh_user+4(a3),fd_resrv(a3)
        move.l  fh_length(a3),-(SP)
        move.w  fh_key(a3),-(SP)
        moveq   #11,d0                  ; set for 12 bytes -1
L1402   move.b  #' ',fd_name(a3,d0.w)   ; spacefill name
        dbra    d0,L1402
        move.w  fh_name(a3),d0
        bne.s   L1404                   ; check name not null
        moveq   #11,d0
L1403   clr.b   fd_name(a3,d0.w)        ; clear name when null
        dbra    d0,L1403
        bra.s   L1407
L1404   cmpi.b  #12,d0                  ; check name not to long
        ble.s   L1406                   ; ... NO, then jump
        moveq   #12,d0                  ; ... YES, set to max
L1406   move.b  (fh_name+1)(a3,d0.w),(fd_name-1)(a3,d0.w)
        subq.w  #1,d0
        bne.s   L1406
L1407    move.w  (SP)+,d0                ; restore qual/type
        move.l  (SP)+,d1                ; restore size
        rol.w   #8,d0                   ; swap to type/qual
        move.w  d0,fd_type(a3)          ; store type/qual
        bne.s   L1408
        tst.l   fd_extra(a3)            ; see if field already set
        bne.s   L1408                   ; ...YES, jump logical size set
        move.l  d1,fd_extra(a3)         ; store logical size
L1408   addi.l  #511,d1                 ; round up size
        andi.w  #$FE00,d1               ; ... set to 512 multiple
        move.l  d1,fd_size(a3)          ; ... and store it
        move.b  fs_filnr+1(a0),fd_num(a3)
        clr.b   fd_flags(a3)
        move.l  spaces,fd_dir(a3)
        move.l  spaces,fd_dir+4(a3)
exit_ql_to_opd
        movem.l (SP)+,d0-d1/a2-a3
        rts
        PAGE
*----------------------------------------------------------------------
*       Convert an OPD format header into QL format
*----------------------------------------------------------------------

header_opd_to_ql
        movem.l d0-d1/a2-a3,-(SP)
        lea     fs_spare(a0),a3
        clr.l   fh_bdate(a3)
        move.l  adjdate,d0
        move.l  fd_utime(a3),fh_udate(a3)
        add.l   d0,fh_udate(a3)
        move.l  fd_ctime(a3),fh_rdate(a3)
        add.l   d0,fh_rdate(a3)
        move.l  fd_extra(a3),-(SP)
        move.l  fd_resrv(a3),-(SP)
        move.w  fd_type(a3),-(SP)
        move.l  fd_name(a3),fh_name+2(a3)
        move.l  fd_size(a3),fh_length(a3)
        move.l  fd_name+4(a3),fh_name+6(a3)
        move.l  fd_name+8(a3),fh_name+10(a3)
        moveq   #12,d1                  ; set default length to 12
        moveq   #11,d0
        lea     fh_name+2(a3),a2
L1503   cmpi.b  #' ',0(a2,d0.w)         ; remove trailing spaces
        bne.s   L1504
        subq.w  #1,d1                   ; reduce name length
        dbra    d0,L1503
L1504   tst.b   fh_name+2(a3)           ; check for deleted file
        bne.s   L1505                      ; jump if not
        moveq   #0,d1                   ; ... else set length to zero
L1505   move.w  d1,fh_name(a3)          ; store name length
        moveq   #35,d0                  ; loop count
        sub.w   d1,d0                   ; less actual length
        lea     fh_name+2(a3),a2
L1506   clr.b   0(a2,d1.w)              ; zero fill to end of name
        addq.w  #1,d1
        dbra    d0,L1506
        move.w  (SP)+,d0                ; restore type/qual
        ror.w   #8,d0                   ; make into qual/type
        move.w  d0,fh_key(a3)
        move.l  (SP)+,fh_user+4(a3)
        move.l  (SP)+,fh_user(a3)
        tst.w   fh_name(a3)             ; deleted file ?
        bne.s   L1507                   ; ... NO, then jump
        clr.l   fh_length(a3)           ; ... YES, then set to null
        bra.s   exit_opd_to_ql
L1507   move.w  fh_key(a3),d0           ; get qual/type
        beq.s   L1508                   ; ... data file, then jump
        cmpi.w  #$0202,d0               ; Basic save file ?
        beq.s   L1508                   ; ... YES, then jump
        cmpi.w  #$0005,d0               ; Basic publish file ?
        bne.s   exit_opd_to_ql          ; ... NO, then jump
L1508   clr.w   fh_key(a3)              ; change key/type to 0
        move.l  fh_user(a3),d0          ; logical size set ?
        beq.s   exit_opd_to_ql          ; ... NO, then jump
        move.l  d0,(a3)                 ; ... YES, set real=logical
        clr.l   fh_user(a3)             ; ... and clear user data
exit_opd_to_ql
        bra     exit_ql_to_opd
