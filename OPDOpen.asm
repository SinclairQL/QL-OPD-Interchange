
*=================================================================
*                    OPEN FILES
*                    ~~~~~~~~~~
*       This routine is responsible for opening/deleting files
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D0                              Error Key
*       A0      Channel block           Preserved
*       A1      Physical Def block      Preserved
*       A3      Dir. Driver Linkage
*       A6      System Variables        Preserved
*
*       REGISTERS SMASHED: D1-D7,A1-A5
*
*       ERRORS:
*
*==================================================================

OPD_OPEN

        IFEQ    LOCKED
        bsr     ACTIVE_START
        bne.s   OPD_OPEN
        bsr.s   OPEN
        bra     ACTIVE_END
OPEN
        ENDC

        move.l  a1,a2                   ; save phy def block
        moveq   #0,d1
        move.b  fs_drivn(a2),d1         ; get drive number
        clr.l   d0
        move.b  fs_drive(a0),d0         ; get drive identity
        lsl.b   #2,d0                   ; ... x 4

*       See if this drive is OK to use.  IT must not be used if there
*       is a MDV drive with files open.

        lea     sv_mdrun(a6),a4
        clr.l   d5
        move.b  (sv_mddid-sv_mdrun-1)(a4,d1.w),d5  ; old drive id
        movea.l (sv_fsdef-sv_mdrun)(a4,d5.w),a5         ; phy def addr
        cmp.b   d0,d5                   ; same ?
        beq.s   open_medium_check       ; ... YES, so OK to use
        tst.b   d5                      ; used before ?
        beq.s   open_medium_check       ; ... NO, so check
        tst.b   fs_files(a5)            ; files still open ?
        beq.s   open_medium_check       ; ... NO, so check
error_in_use
        moveq   #err_iu,d0
        rts
        PAGE
*       Set drive details, and then check medium

open_medium_check
        move.b  d0,(sv_mddid-sv_mdrun-1)(a4,d1.w) ; set drive id * 4
        cmp.b   (a4),d1                 ; see if drive running
        beq.s   search_prepare          ; ... YES, then jump
        tst.b   (sv_mdsta-sv_mdrun-1)(a4,d1.w) ; see if outstanding op
        bne.s   search_prepare          ; ... YES, then jump
        move.b  #1,fs_flag1(a2)         ; set check only flag
        bsr     OPD_START_PHYSICAL
L614    tst.b   fs_flag1(a2)            ; check reply
        bmi.s   error_not_found
        bne.s   L614
        cmpi.l  #'ICL ',fs_vol+vol_ICL(a2)      ; check OPD tape
        beq.s   search_prepare
error_not_found
        moveq   #err_nf,d0
nf_exit rts

*       Get ready to search directory

search_prepare
        move.w  #1,fs_filnr(a0)         ; set for after directory
        move.l  #$00020058,fs_eblok(a0) ; set end after catalogs
        bsr     READ_FILE_HEADER
        bne.s   nf_exit
        bsr     set_file_pointers
        cmpi.b  #4,fs_acces(a0)         ; directory mode access ?
        beq     exit_ok2
        move.w  fs_eblok(a0),d4         ; get block count
        subq.l  #2,d4                   ; reduce to data block count
        mulu    #11,d4                  ; ... convert to entries
        moveq   #0,d6                   ; set for no free entry found

search_directory
        bsr     READ_FILE_HEADER
        bne.s   nf_exit
        tst.l   fs_spare+fh_length(a0)  ; check not deleted file
        bne.s   L631                    ; ... NO, then jump
        tst.l   fs_spare+fh_name(a0)    ; check name as well
        beq.s   L632                    ; ... YES, then slot free
L631    movem.l a0/a2/a6,-(SP)          ; save registers
        suba.l  a6,a6                   ; A6 relative addresses
        lea     fs_spare+fh_name(a0),a1 ; name in header
        lea     fs_name(a0),a0          ; name in channel block
        moveq   #1,d0                   ; case independent comparison
        move.w  UT_CSTR,a2
        jsr     (a2)
        movem.l (SP)+,a0/a2/a6          ; restore registers
        beq     old_file_entry
        bra.s   next_dir_entry
L632    tst.w   d6                      ; empty slot already found ?
        bne.s   next_dir_entry          ; ... YES, then jump
        move.w  fs_filnr(a0),d6         ; ... NO, then set as found
next_dir_entry
        addq.w  #1,fs_filnr(a0)         ; increment file number
        cmp.w   fs_filnr(a0),d4         ; end reached ?
        bge.s   search_directory        ; ... NO, then loop
        PAGE
new_file_entry
        move.b  fs_acces(a0),d0         ; get access mode wanted
        bmi     exit_ok2                ; ... delete ,then exit
        cmpi.b  #2,d0                   ; read mode ?
        blt     ERROR_NOT_FOUND
        tst.w   d6                      ; spare slot found ?
        bne.s   @4                      ; yes, then jump

*       Write a new catalog block

        move.l  d4,d6                   ; save intended file number
        add.l   #1,d6                   ; ...one larger than largest
        moveq   #0,d0
        move.b  fs_free(a2),d0          ; get current free space
        subq.w  #2,d0                   ; allow for 2 more catalog blok
        bmi     ERROR_DRIVE_FULL
        move.w  #2,fs_filnr(a0)         ; set for !CAT2
        move.l  fs_eblok(a0),-(SP)      ; save old EOF
        bsr.s   NEW_CATALOG_BLOCK       ; write blank block
        subq.w  #1,fs_filnr(a0)         ; set for !CAT1
        move.l  (SP)+,fs_eblok(a0)      ; restore previous EOF
        bsr.s   NEW_CATALOG_BLOCK
        bsr     READ_FILE_HEADER        ; read catalog entry
        addi.l  #512,fs_spare+fh_length(a0) ; file length + 1 block
        bsr     WRITE_FILE_HEADER       ; rewrite new values
@4      move.w  d6,fs_filnr(a0)         ; set file number
        bra.s   set_up_header

*       Write a zero filled block to catalog file given by FS_FILNR

new_catalog_block
        move.l  fs_eblok(a0),fs_nblok(a0)       ; set next to EOF
        move.w  #511,d4                 ; set block size to 512
L652    moveq   #IO_SBYTE,d0
        moveq   #0,d1                   ; byte of zero
        bsr     OPD_INOUT               ; write byte
        dbra    d4,L652                 ; loop until finished
        rts

set_up_header
        moveq   #63,d0
L662    clr.b   fs_spare(a0,d0.w)       ; clear down header
        dbra    d0,L662
        move.w  fs_name(a0),d0          ; get length
        cmpi.b  #12,d0                  ; truncate to 12 if too long
        ble.s   L665
        moveq   #12,d0
L665    addq.w  #1,d0                   ; allow for length field
        lea     fs_name(a0),a5          ; name from header
        lea     fs_spare+fh_name(a0),a4 ; destination
L666    move.b  (a5)+,(a4)+             ; move across name
        dbra    d0,L666
        bsr     get_date
        move.l  d1,fs_spare+fh_rdate(a0) ; set reference date
        bsr     WRITE_FILE_HEADER
        bne.s   exit2
        bsr.s   set_file_pointers
        bra.s   exit_ok2

*       Set pointers for file

set_file_pointers
        move.l  fs_spare+fh_length(a0),d0
        lsl.l   #7,d0
        lsr.w   #7,d0
        move.l  d0,fs_eblok(a0)         ; set EOF
        addq.w  #1,fs_eblok(a0)         ; allow for base 1
        clr.l   fs_nblok(a0)            ; set start to zero
        addq.w  #1,fs_nblok(a0)         ; then allow for base 1
        move.l  filestart,fs_nblokdir(a0)
        rts
        PAGE
*       File found, so check action requested

old_file_entry
        move.b  fs_acces(a0),d0         ; get access mode
        blt.s    OPD_DELETE             ; ... negative means delete
        subq.b  #2,d0                   ; see if read only
        bmi.s   L688                    ; ... YES, so ok
        subq.b  #1,d0                   ; see if overwrite
        bne.s   error_exists            ; ... NO, so error
        bsr.s   OPD_DELETE              ; ... YES, first delete
        bra.s   set_up_header           ; then treat as OK
L688    bsr.s   set_file_pointers
exit_ok2
        moveq   #0,d0
exit2    rts

error_exists
        moveq   #err_ex,d0
        rts
        PAGE
*----------------------------------------------------------------------
*               DELETE a file
*
*       This is a special variety of the OPEN channel trap
*----------------------------------------------------------------------

OPD_DELETE
        cmpi.w  #2,fs_filnr(a0)         ; check not catalogue file
        ble     ERROR_READ_ONLY         ; ... reject if it is
        clr.w   (fs_spare+fh_name)(a0)
        clr.l   (fs_spare+fh_length)(a0)
        bsr     WRITE_FILE_HEADER

*       Free any map entries and outstanding actions

        move.l  filestart,fs_nblok(a0)  ; set to start
        moveq   #fs_trunc,d0            ; set to truncate file
        bsr     OPD_INOUT
        rts

get_date
        move.l  a0,-(SP)
        moveq   #mt_rclck,d0
        TRAP    #1
        move.l  (SP)+,a0
        move.l  d1,(fs_spare+fh_udate)(a0)
        rts
        PAGE
*=================================================================
*                         CLOSE A FILE
*                         ~~~~~~~~~~~~
*       This routine handles closing OPD channels
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D0                              Error Key
*       A0      Channel def block       Preserved
*       A3      Directory Driver block
*       A6      System variables        Preserved
*
*       REGISTERS SMASHED: D0-D3,A0-A3
*
*       ERRORS:         None
*=================================================================

OPD_CLOSE

        IFEQ    LOCKED
        bsr     ACTIVE_START
        bne.s   OPD_CLOSE
        bsr.s   CLOSE
        bra     ACTIVE_END
CLOSE
        ENDC
        move.l  fs_eblok(a0),d3         ; get end-point
        sub.l   #$0010000,d3            ; reduce to zero base
        beq.s   L702                    ; ... null, so must process
        tst.b   fs_updt(a0)             ; see if file updated
        beq.s   L706                    ; ... NO, then quick exit
L702    bsr     get_date
        lsl.w   #7,d3                   ; convert end pointer to length
        lsr.l   #7,d3
        bne.s   L704                    ; jump if not null file
        clr.w   FS_SPARE+FH_NAME(a0)    ; ... else clear name also
L704    move.l  d3,FS_SPARE+FH_LENGTH(a0)
        addq.w  #1,FS_FILNR(a0)
        bsr     make_directory_position
        move.l  FS_NBLOK(a0),FS_EBLOK(a0)
        subq.w  #1,FS_FILNR(a0)
        bsr     write_file_header
        bsr     OPD_SLAVE               ; ensure written away

*       decrement file count in physical def block

L706    moveq   #0,d0
        move.b  FS_DRIVE(a0),d0         ; get the drive id
        lsl.b   #2,d0                   ; convert it to offset
        lea     SV_FSDEF(a6),a2
        move.l  0(a2,d0.w),a2           ; get address (base + offset)
        subq.b  #1,FS_FILES(a2)         ; decrement open count

*       unlink the file

        lea     FS_NEXT(a0),a0
        lea     SV_FSLST(a6),a1
        move.w  UT_UNLNK,a2
        jsr     (a2)
        lea     -FS_NEXT(a0),a0         ; restore a0 to channel base
        move.w  MM_RECHP,a2             ; set to release memory
        jmp     (a2)                    ; execute & exit
