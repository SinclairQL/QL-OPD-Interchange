
*--------------------------------------------------------------------
*       READ A SPECIFIED BLOCK FOR A SPECIFED FILE
*
*               ENTRY                  EXIT
*               ~~~~~                  ~~~~
*       D1      File Number            Presrved
*       D2      Block Number           Preserved
*       D7                             Sector Address
*       A5      Buffer Address         Preserved
*       ERRORS:
*       ~~~~~~
*       REGISTERS SMASHED:
*--------------------------------------------------------------------

MDV_FILE_BLOCK
        pea     MDV_READ_HEADER
        bra.s   file_block
OPD_FILE_BLOCK
        pea     OPD_READ_HEADER
file_block
        clr.w   -(SP)                  ; clear work field
        move.w  d1,-(SP)               ; save file number
        move.w  d2,-(SP)               ; save block number
Lab72   subq.w  #1,4(SP)               ; update scanned count
        beq.s   Lab78                  ; ... expired, error
        move.l  6(SP),a2               ; get required header routine
        jsr     (a2)                   ; ... and call it
        bne.s   Lab79                  ; exit immediately if error
        move.l  a5,a1                  ; set buffer address
        bsr     MDV_READ               ; read same for MDV and OPD
        bra.s   Lab72                  ; ignore error blocks
        cmp.b   2(SP),d1               ; check file number
        bne.s   Lab72                  ; ... wrong, try again
        cmp.b   (SP),d1                ; check block number
        bne.s   Lab72                  ; ... wrong, try again
        moveq   #0,d0                  ; set for OK return
        bra.s   Lab79
Lab78   moveq   #ERR_NF,d0             ; ERROR - Not found
Lab79   move.w  (SP)+,d2               ; remove block number
        move.w  (SP)+,d1               ; remove file number
        addq.l  #4,SP                  ; remove work fields from stack
        tst.l   d0                     ; reset condition code
        rts
        PAGE
*----------------------------------------------------------------------
*       CHECK THE FORMAT OF A MICRODRIVE
*
*               ENTRY                  EXIT
*               ~~~~~                  ~~~~
*       D3      Drive
*
*       ERRORS:
*       ~~~~~~  ERR_BP   Drive number invalid
*               ERR_FE   No valid sector header found
*
*       REGISTERS SMASHED: D0,D1,D3,D4,D6,A2,A4
*----------------------------------------------------------------------

MDV_SPIN
        pea     MDV_READ_HEADER        ; set for QL format
        bra.s   spin
OPD_SPIN
        pea     OPD_READ_HEADER        ; set for OPD format
spin
        move.l  (SP)+,d5               ; get required routine
        bsr     MDV_START              ; start drive
        bne.s   Lab99                  ; ...ERROR, exit immediately
        move.l  d5,a2                  ; get required routine
        jsr     (a2)                   ; ... and do it
        move.l  d0,d5                  ; save error code
        bsr     MDV_STOP               ; stop drive
        move.l  d5,d0                  ; restore error code
Lab99   rts
