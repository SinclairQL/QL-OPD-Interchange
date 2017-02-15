******************************************************************
**                                                              **
**                      OPDFIND                                 **
**                      ~~~~~~~                                 **
**      These subroutinesare used by the following programs:    **
**              OPDLOAD                                         **
**              OPDEND                                          **
**              OPDCOPY                                         **
**              OPDBLOCK                                        **
**                                      LAST AMENDED: 26/04/86  **
******************************************************************

        xdef    FIND_DRIVER,FIND_CODE,FIND_PHYSICAL,devname
        xref    mdvname,opdname,flpname,ramname,newname
        xref    devicetable,devicecount
        
*       STANDARD DEFINITIONS

*NOLIST
$INCLUDE        Flp1_asmlib_system
$INCLUDE        Flp1_asmlib_files
$INCLUDE        Flp1_asmlib_vectors
$INCLUDE        Flp1_asmlib_channels
$INCLUDE        Flp1_asmlib_errors
*LIST

*PAGE
*----------------------------------------------------------------------
*       Find the Device Driver
*               Entry   A0 = Device name string
*               Return  D0 = -ve if not found
*                       A0 = Device Name String
*                       A1 = Access Link Level address
*----------------------------------------------------------------------

FIND_DRIVER
        movem.l d1/a2,-(SP)
        lea     sv_ddlst(a6),a1         ; start of list
@2      tst.l   (a1)                    ; see if list finished
        beq.s   @7                      ; ... YES, error exit
        move.l  (a1),a1                 ; ... NO, get address
        movem.l a0-a1/a6,-(SP)          ; save registers used
        lea     [ch_drnam-ch_next](a1),a1 ; set device name address
        sub.l   a6,a6                   ; make A6 relative
        moveq   #1,d0                   ; case independent
        move.w  UT_CSTR,a2
        jsr     (a2)
        movem.l (SP)+,a0-a1/a6          ; restore registers used
        bne.s   @2                      ; ... Loop if no match
        moveq   #0,d0                   ; ... Else set OK reply
        bra.s   @9                      ; ... and exit
@7      moveq   #err_nf,d0
@9      movem.l (SP)+,d1/a2
        rts

*PAGE
*----------------------------------------------------------------------
*       Find the Physical Def Block details
*               Entry   D0 = Drive type
*                       D1 = Drive number
*               Exit    D0 = Error code
*                       D1 = device/Drive code id
*                       A0 = Device name string
*                       A1 = Access Level link address
*                       A2 = Phys Def block
*---------------------------------------------------------------------

FIND_PHYSICAL
        mulu    #6,d0
        lea     devicetable,a1
        lea     devname,a0
        move.l  2(a1,d0.w),2(a0)
        bsr.s   FIND_DRIVER
        bne.s   @9
        bsr.s   FIND_CODE
@9      rts
*PAGE
*----------------------------------------------------------------------
*       Find the code for a given drive
*       Entry   A1 Driver access Link level
*               D1 contains required drive
*       Exit    D0 -ve means not found
*               D1 contains code
*               A1 Driver Access Link Level
*               A2 Physical Definition Block
*----------------------------------------------------------------------

FIND_CODE
        movem.l d2-d3/a3,-(SP)          ; save registers used
        moveq   #[4*15],d2              ; set loop count-1
        lea     sv_fsdef(a6),a3         ; set table base
@2      move.l  0(a3,d2.w),d3           ; see if value set
        beq.s   @6                      ; ... NO, go for next
        move.l  d3,a2
        cmp.b   fs_drivn(a2),d1         ; drive numbers match ?
        bne.s   @6                      ; ... No, go for next
        cmp.l   fs_drivr(a2),a1         ; driver addresses match ?
        beq.s   @8                      ; ... YES, good exit
@6      subq.l  #4,d2
        bpl.s   @2
        moveq   #err_nf,d0
        bra.s   @9
@8      move.w  fs_mname+10(a2),d1      ; set tape id
        moveq   #0,d0
@9      movem.l (SP)+,d2-d3/a3          ; restore registers used
        rts
devname dc.w    3
        dc.b    '    '
        END
