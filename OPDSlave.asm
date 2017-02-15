
*=============================================== AMENDED: 20/04/87
*                        FORCED SLAVING          ~~~~~~~~~~~~~~~~~
*                        ~~~~~~~~~~~~~~
*       This routine is responsible for forcing the writing of slave
*       blocks so that memory can be released
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       A1      Base of Slave Block
*       A2      Phy. Def Block Base
*       A6      System Variables        Preserved
*
*       REGISTERS SMASHED: D0,D2-D3
*
*       ERRORS:         None
*       ~~~~~~
*==================================================================

OPD_SLAVE
        sf      fs_flag1(a2)            ; clear flag
OPD_START_PHYSICAL
        bsr     START_PHYSICAL

        IFNE    TASK
        movem.l d1-d7/a0-a5,-(SP)
L215    bsr     OPD_PHYSICAL_LAYER
        tst.b   sv_mdrun(a6)
        beq.s   L219
        move.b  opdrun,d1
        beq.s   L215
L217    move.b  opdrun,d1               ; OPD drive running ?
        beq.s   L219                    ; ... NO, exit
        bsr     READ_SECTOR_HEADER      ; call physical layer
        bra.s   L217
L219    movem.l (SP)+,d1-d7/a0-a5       ; restore registers
        ENDC

        rts

START_PHYSICAL
        moveq   #0,d1                   ; Clear register
        move.b  FS_DRIVN(a2),d1         ; ...and set drive
        lea     SV_MDRUN(a6),a3
        st      (SV_MDSTA-SV_MDRUN)(a3,d1.w) ; set for pending ops
        tst.b   (a3)                    ; see if drives already running
        bne.s   L219                    ; ... YES, exit
        moveq   #PC_MDVMD,d0            ; set microdrive mode
        bsr     RS232_WAIT              ; wait for any RS232 to complete
        move.b  d1,(a3)                 ; set as this drive running
        move.b  #-6,SV_MDCNT(a6)        ; set run up/down counter
        lea     PC_MCTRL,a3             ; set microdrive control reg address
        bsr     SELEC                   ; start drive
        ori.b   #$20,SV_PCINT(a6)       ; set new interrupt mask
        move.b  SV_PCINT(a6),PC_INTR    ; ... and set it
        rts

