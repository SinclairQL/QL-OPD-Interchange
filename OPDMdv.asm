
********************************************************************
**                                                                **
**               M I C R O D R I V E    A C C E S S               **
**                                                                **
**      These routines are responsible for the actual Physical    **
**      Physical I/O to microdrive.  They are used both in the    **
**      OPD Device Driver, and also in the OPD/QL Toolkit.        **
**                                                                **
**                                    LAST AMENDED:  20/04/87     **
********************************************************************

*--------------------------------------------------------------------
*                             IMPORTANT
*                             =========
*
*       Conditional compilation variables must be set to control
*       whether these routines tap into the QL ROM or not.
*       Some of then have only been validated as correct for
*       the following ROM versions:-
*
*                      AH, JM, JS
*
*       ROMWRITE       0 means take write routines from ROM, 1 otherwise
*       ROM            0 means take other routines from ROM, 1 otherwise
*
*       This additional code that will be included if these variables
*       are set to 0 is equivalent to the ROM code (JM version).
*---------------------------------------------------------------------

*       The routines contained in this file are as follows:

*               MDV_START,             OPD_START
*               MDV_STOP,              OPD_STOP
*               MDV_READ,              OPD_READ
*               MDV_WRITE,             OPD_WRITE
*               MDV_VERIFY,            OPD_VERIFY
*               MDV_SECTOR,            OPD_SECTOR
*               MDV_READ_HEADER,       OPD_READ_HEADER
*               MDV_POSITION,          OPD_POSITION
*
*                        BLOCK_WRITE
*                        BLOCK_READ
*                        BLOCK_VERIFY
*                        GAP

*       Additional routines in file OPDMdvx_asm

*               MDV_SPIN,              OPD_SPIN
*               MDV_FILE_BLOCK,        OPD_FILE_BLOCK
        PAGE
*--------------------------------------------------------------------
*               START A MICRODRIVE
*               (NOTE. Switches from User ro Supervisor Mode)
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       SR                              SUPERVISOR MODE if no error
*       D3      drive number
*       A3                              $18020 = MDV control reg
*       A6                              System Variables
*
*       ERRORS:
*               ERR_OR      Drive number out of range
*
*       REGISTERS SMASHED:      D1,D2
*--------------------------------------------------------------------

MDV_START
OPD_START
        and.w   #$FF,d3                 ; screen out any unwanted bits
        cmpi.b  #1,d3                   ; less than 1 ?
        blt.s   error_out_of_range      ; ... YES, error
        cmpi.b  #8,d3                   ; greater than 8
        bgt.s   error_out_of_range      ; ... NO, then continue
        move.l  (SP)+,a3                ; save return address
        moveq   #MT_INF,d0              ; system information required
        TRAP    #1
        move.l  a0,a6                   ; set system variables address
        TRAP    #0                      ; ensure supervisory mode
        move.l  a3,-(SP)                ; set return addrress
        move.w  d3,d1                   ; set drive to start
START_INTERNAL
        moveq   #PC_MDVMD,d0            ; set for microdrive mode
        bsr.s   RS232_WAIT              ; wait for RS232 to complete
        ori.w   #$0700,SR               ; disable all interrupts
        move.l  PC_MCTRL,a3             ; a3 = mdv control register
        bsr.s   SELEC                   ; start drive
        moveq   #0,d0                   ; ok
        rts

RS232_WAIT
        move.b  d0,-(SP)
L2      subq.w  #1,SV_TIMO(a6)          ; decrement time-out
        blt.s   L4                      ; done ?
        move.w  #(20000*15-82)/36,d0    ; time = 18*n+42 cycles
L3      dbra    d0,L3
        bra.s   L2                      ; repeat until timeout expires
L4      clr.w   SV_TIMO(a6)             ; clear wait
        andi.b  #PC_NOTMD,SV_TMODE(a6)  ; not RS232
        move.b  (SP)+,d0
        or.b    d0,SV_TMODE(a6)         ; either mdv or net
        andi.b  #($FF-PC_MASKT),SV_PCINT(a6) ; disable transmit interrupt
rs232_exit
        move.b  SV_TMODE(a6),PC_TCTRL   ; set transmit control
        rts
SELEC
        moveq   #PC_SELEC,d2            ; clock in select bit first
        subq.w  #1,d1                   ; loop count = drive -1
        bra.s   clk_loop

error_out_of_range
        moveq   #ERR_OR,d0
        rts
        PAGE
*-------------------------------------------------------------------
*       STOP A MICRODRIVE RUNNING
*       (NOTE.  Switches from Supervisor to User mode)
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       SR      SUPERVISOR MODE         USER MODE if no error
*
*       A6      System Variables        preserved
*
*       ERRORS:         None
*
*       REGISTERS SMASHED:      D0,D1,D2,A3
*-------------------------------------------------------------------

MDV_STOP
OPD_STOP
        move.l  PC_MCTRL,A3             ; mdv control register
        bsr.s   DESEL                   ; wind it down
        bsr.s   RS232_SET               ; re-enable RS232
        move.l  (SP)+,a3                ; save return address
        andi.w  #$D8FF,SR               ; enable interrupts+User Mode
        moveq   #0,d0                   ; set good return code
        jmp     (a3)                    ; ... and return

RS232_SET
        bclr    #PC__SERB,SV_TMODE(a6)  ; set RS232 mode
        ori.b   #PC_MASKT,SV_PCINT(a6)  ; enable transmit interrupt
        bra.s   rs232_exit

DESEL
        moveq   #PC_DESEL,d2            ; clock in deselect bit first
        moveq   #7,d1                   ; deselect all
clk_loop
        move.b  d2,(a3)                 ; clock high
        moveq   #(18*15-40)/4,d0        ; time 2*n +20 cycles
        ror.l   d0,d0
        bclr    #PC__SCLK,d2            ; clock low
        move.b  d2,(a3)                 ; ..clocks d2.0 into first drv
        moveq   #(18*15-40)/4,d0        ; time = 2*n+20 cycles
        ror.l   d0,d0
        moveq   #PC_DESEL,d2            ; clock high, so deselect
        dbra    d1,clk_loop
        rts
        PAGE
*--------------------------------------------------------------------
*       READ NEXT SECTOR HEADER (leaving  tape just before data block)
*
*               ENTRY                  EXIT
*               ~~~~~                  ~~~~
*       D7                             Sector Number
*       A1                             Buffer End
*       A5      Buffer start
*
*       ERRORS:
*       ~~~~~~  ERR_FE    No valid header found
*
*       REGISTERS SMASHED: D0,D1,D3,D4,D6,A2,A4
*--------------------------------------------------------------------

MDV_READ_HEADER
        pea     MDV_SECTOR_HEADER
        bra.s   read_header
OPD_READ_HEADER
        pea     OPD_SECTOR_HEADER
read_header
        move.w  #20,-(SP)              ; set timeout count field
Lab32   subq.w  #1,(SP)                ; timeout expired ?
        beq.s   Lab38                  ; ... YES, error
        move.l  a5,a1                  ; set buffer address
        move.l  2(SP),a2               ; get required routine
        jsr     (a2)                   ; ... and try to read header block
        bra.s   Lab38                  ; ERROR: Bad Medium
        bra.s   Lab32                  ; ERROR: Bad Header (Try again)
        moveq   #0,d0                  ; set OK return
        bra.s   Lab39                  ; ... and exit
Lab38   moveq   #ERR_FE,d0             ; set error condition
Lab39   addq.l  #6,SP                  ; remove timeout/JSR fields
        rts
        PAGE
*------------------------------------------------------------------
*       POSITION TAPE AFTER A SPECIFIED SECTOR HEADER
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D2      Required sector         Preserved
*       D7                              Sector Number
*       A1                              Buffer end
*       A5      Buffer address          Preserved
*
*       ERRORS:
*       ~~~~~~  ERR_NF     Sector not found
*               ERR_FE     Bad Medium/Wrong Format
*
*       REGISTERS SMASHED:  D0,D1,D3,D4,D6,D7,A1,A2,A4
*------------------------------------------------------------------

MDV_POSITION
        pea     MDV_READ_HEADER
        bra.s   position
OPD_POSITION
        pea     OPD_READ_HEADER
position
        clr.w   -(SP)                  ; clear space for scanned count
Lab53   addq.b  #1,(SP)                ; update scanned count
        beq.s   Lab58                  ; ... expired, ERROR
        move.l  2(SP),a2               ; get required routine
        jsr     (a2)                   ; ... and call it
        bne.s   Lab59                  ; ... ERROR, exit immediately
        cmp.b   d7,d2                  ; see if required sector
        bne.s   Lab53                  ; ... NO, try again
        moveq   #0,d0                  ; set OK retrun
        bra.s   Lab59                  ; ... and exit
Lab58   moveq   #ERR_NF,d0
Lab59   addq.w  #6,SP                  ; remove stack work fields
        rts
        PAGE
*----------------------------------------------------------------------
*       ROUTINE TO WRITE A MICRODRIVE DATA BLOCK
*
*       Interrupts must be disabled
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       A1      Buffer start            Buffer end
*       A3      $18020 MDV control reg  Preserved
*       A7      Pointer to word         Preserved
*               containing file/block
*
*       RETURN + 0      OK
*
*       REGISTERS SMASHED:  D0,D1,D3,D4,D5,D6,A0,A2,A4
*----------------------------------------------------------------------


MDV_WRITE

        IFEQ    ROMWRITE
OPD_WRITE
        ENDC
        move.w  MD_WRITE,a2
        jmp     $4000(a2)

        IFNE    ROMWRITE
OPD_WRITE
        move.b  #PC_ERAS,(a3)           ; set to erase mode
        move.w  gap1,d0                 ; set wait count
Lab111  dbra    d0,Lab111               ; wait for GAP 2
        move.l  a1,a0                   ; save data buffer address
        lea     4(SP),a1                ; set File/Block address
        moveq   #1,d1                   ; set for length of 2
        lea     Lab112,a4
        bra     OPD_BLOCK_WRITE
Lab112  move.l  a0,a1                   ; restore data buffer address
        move.w  #511,d1                 ; set for length of 512
        lea     Lab113,a4
        bra     OPD_BLOCK_WRCONT
Lab113  moveq   #PC_READ,d4             ; get MDV read(idle) mask
        moveq   #48,d0                  ; set wait count
Lab114  dbra    d0,Lab114               ; ... and wait
        move.b  d4,(a3)                 ; switch to idle
        rts
        ENDC
        PAGE
*----------------------------------------------------------------------
*       Routine to write a Microdrive block of a specified length
*
*       Interrupts must be disabled
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D1      Block Length (-1)
*       A1      Buffer start            Buffer end
*       A3      $18020 MDV control reg  Preserved
*
*       RETURN + 0      OK
*
*       REGISTERS SMASHED:  D1,D3,D4,D5,D6
*----------------------------------------------------------------------

MDV_BLOCK_WRITE
OPD_BLOCK_WRITE

        IFEQ    ROMWRITE
        move.w  MD_WRITE,a2
        jmp     $4000+52(a2)
        ENDC

        IFNE    ROMWRITE
        moveq   #PC_WRITE,d0
        move.b  d0,(a3)
        move.b  d0,(a3)
        moveq   #PC__TXFL,d6
        lea     2(a3),a2

*       Write continuation.
*               D5 contains pre-amble length (-1)

opd_block_wrcont
        moveq   #9,d5                   ; set for 10 byte pre-amble
        moveq   #0,d4                   ; set pre-amble data
Lab136  bsr.s   Lab138                  ; write a byte
        subq.b  #1,d5                   ; reduce remainder count
        bge.s   Lab136
        moveq   #-1,d4                  ; set for $FF bytes
        bsr.s   Lab138                  ; ... first track
        bsr.s   Lab138                  ; ... other track
        move.w  #$0F0F,d3               ; initialise for checksum
        moveq   #0,d4
Lab137  move.b  (a1)+,d4
        add.w   d4,d3
        bsr.s   Lab138
        dbra    d1,@7
        move.w  d3,d4
        bsr.s   Lab138
        lsr.w   #8,d4
        bsr.s   Lab138
        jmp     (a4)

*       Routine to write byte
*       D4.B contains byte
*       D6   contains 'buffer full' bit number

Lab138  btst    d6,(a3)
        bne.s   Lab138
        move.b  d4,(a2)
        rts
        ENDC
        PAGE
*----------------------------------------------------------------------
*       Routine to read a Microdrive Sector Header.  The OPD routine
*       is always different to the MDV version.
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D7                              Sector Number
*       A1      Buffer start            Buffer end
*       A3      $18020 MDV control reg  Preserved
*
*       RETURN + 0      Bad Medium
*              + 2      Bad Sector Header
*              + 4      OK
*
*       REGISTERS SMASHED:  D0,D1,D3,D4,D6,A2,A4
*----------------------------------------------------------------------

MDV_SECTOR_HEADER
        move.w  MD_SECTR,a2
        jmp     (a2)
OPD_SECTOR_HEADER
        bsr     OPD_GAP                 ; position in gap
        rts                             ; ... ERROR: Bad Medium
        addq.l  #2,(SP)                 ; change return to bad header
        moveq   #11,d1                  ; set for header (12 bytes)
        bsr     BLOCK_READ              ; read the next block
        bra.s   Lab159                  ; ...ERROR: Bad Header
        cmpi.b  #$FF,-12(a1)            ; check for header start byte
        bne.s   Lab159                  ; ... ERROR: Bad Header
        moveq   #0,d7
        move.b  -11(a1),d7              ; set sector number
        addq.l  #2,(SP)                 ; set for OK return
Lab159  rts
        PAGE
*----------------------------------------------------------------------
*       Routines to READ and VERIFY a Microdrive Sector
*               (Interrupts MUST be disabled)
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D1                              File Number
*       D2                              Block within file
*       A1      Buffer start            Buffer end
*       A3      $18020 MDV control reg  Preserved
*
*       RETURN + 0      Bad Read/Verify
*              + 2      OK
*
*       REGISTERS SMASHED:  D0,D3,D4,D6,A2,A4
*----------------------------------------------------------------------

MDV_READ
        IFEQ    ROM
OPD_READ
        ENDC
        move.w  MD_READ,a2
        jmp     $4000(a2)

        IFNE    ROM
OPD_READ
        lea     OPD_BLOCK_READ,a0
        bra.s   opd_readverify
        ENDC

MDV_VERIFY
        IFEQ    ROM
OPD_VERIFY
        ENDC

        move.w  MD_VERIN,a2
        jmp     $4000(a2)

        IFNE    ROM
OPD_VERIFY
        lea     OPD_BLOCK_VERIFY,a0
opd_readverify
        bsr     OPD_GAP                 ; find interblock gap
        rts                             ; ... ERROR - Not Found
        move.l  a1,-(SP)                ; save buffer address
        clr.w   -(SP)                   ; clear area for file/block No.
        move.l  SP,a1                   ; set buffer address
        moveq   #1,d1                   ; set for 2 bytes (-1)
        bsr.s   OPD_BLOCK_READ
        bra.s   Lab176                  ; ... ERROR return
        moveq   #PC__RXRD,d1            ; Read Buffer Ready
        move.b  d1,(a3)                 ; ... Track 1
        move.b  d1,(a3)                 ; ... Track 2
        move.w  #511,d1                 ; set for 512 bytes (-1)
        move.l  2(SP),a1                ; set buffer address
        jsr     (a0)
        bra.s   Lab176                  ; ... ERROR return
        addq.l  #2,6(SP)                ; set OK return
Lab176  moveq   #0,d1                   ; clear reply registers
        moveq   #0,d2
        move.b  1(SP),d2                ; ... block number
        move.b  (SP)+,d1                ; ... file number
        addq.l  #4,SP                   ; clear stacked buffer address
        rts
        ENDC
        PAGE
*----------------------------------------------------------------------
*       Routines to read and verify a Microdrive block
*               (Interrupts MUST be disabled)
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       D1      Block length-1
*       A1      Buffer start            Buffer end
*       A3      $18020 MDV control reg  Preserved
*
*       RETURN + 0      Bad Read
*              + 2      OK
*
*       REGISTERS SMASHED:  D0,D3,D4,D6,A2,A4
*----------------------------------------------------------------------

BLOCK_READ
        IFEQ    ROM
        move.w  MD_READ,a2
        adda.w  $4002(a2),a2
        jmp     $4002(a2)
        ENDC

        IFNE    ROM
        bsr.s   set_registers
Lab192  btst    d6,(a3)                 ; read buffer empty ?
        dbne    d0,Lab192               ; ... YES, loop
        move.b  (a2),d4                 ; get data byte
        exg     a2,a4                   ; swap tracks
        move.b  d4,(a1)+                ; ... add to buffer
        add.w   d4,d3                   ; ... update checksum
        tst.w   d0                      ; count expired ?
        blt.s   return                  ; ... YES, exit
        moveq   #20,d0                  ; reset wait count
        subq.w  #1,d1                   ; block completed ?
        bge.s   Lab192                  ; ... NO, loop
        bra.s   Checksum                ; ... YES, jump
        ENDC

BLOCK_VERIFY
        IFEQ    ROM
        move.w  MD_VERIN,a2
        adda.w  $4002(a2),a2
        jmp     $4002(a2)
        ENDC

        IFNE    ROM
        bsr.s   set_registers
Lab212  btst    d6,(a3)                 ; read buffer empty ?
        dbne    d0,Lab212               ; ... YES, loop
        move.b  (a2),d4                 ; get data byte
        exg     a2,a4                   ; swap tracks
        cmp.b   (a1)+,d4                ; check byte matches
        bne.s   return                  ; ... NO, error return
        add.w   d4,d3                   ; update checksum
        tst.w   d0                      ; count expired ?
        blt.s   return                  ; ... YES, exit
        moveq   #20,d0                  ; reset wait count
        subq.w  #1,d1                   ; block completed ?
        bge.s   Lab212                  ; ... NO, loop
        PAGE
*       Routine to calculate checksum

Checksum
Lab222  btst    d6,(a3)                 ; read buffer empty ?
        dbne    d0,Lab222               ; ... YES, loop
        move.b  (a2),d4                 ; get byte
        exg     a2,a4
        ror.w   #8,d4                   ; rotate
        tst.w   d0
        blt.s   return
        moveq   #20,d0                  ; reset countdown
        addq.w  #1,d1                   ; first byte of checksum ?
        beq.s   Lab222                  ; ... YES, get next
        cmp.w   d4,d3                   ; matches ?
        bne.s   return                  ; ... NO, exit
        addq.l  #2,(SP)                 ; ... YEs, set OK return
return  rts

*       Set up registers for reading a block

Set_Registers
        move.w  #256,d0         ; wait count
        move.w  #$0F0F,d3       ; checksum start value
        moveq   #0,d4           ; clear data input register
        moveq   #PC__RXRD,d6    ; MDV read buffer ready bit
        lea     2(a3),a2        ; MDV Buffer Track 1 address
        lea     3(a3),a4        ; MDV Buffer Track 2 address
        rts
        ENDC
        PAGE
*----------------------------------------------------------------------
*       Routine to find a gap between microdrive blocks
*               (Interrupts MUST be disabled)
*
*               ENTRY                   EXIT
*               ~~~~~                   ~~~~
*       A3      $18020 MDV control reg  Preserved
*
*       RETURN + 0      Gap not found
*              + 2      OK
*
*       REGISTERS SMASHED:  D0,D1,(A2)
*----------------------------------------------------------------------

OPD_GAP
GAP
        IFEQ    ROM
        move.w  MD_SECTR,a2
        adda.w  $4002(a2),a2
        jmp     $4002(a2)
        ENDC

        IFNE    ROM
        moveq   #0,d1
Lab242  subq.w  #1,d1
        beq.s   Lab249
        btst    #PC__GAP,(a3)           ; gap found ?
        beq.s   Lab242                  ; ... NO, loop
        moveq   #0,d1                   ; set wait count
Lab243  subq.w  #1,d1                   ; reduce count
        beq.s   Lab249                  ; exit if expires
        moveq   #23,d0                  ; set length countdown
Lab244  btst    #PC__GAP,(a3)           ; still gap ?
        bne.s   Lab243
        dbra    d0,@4
        move.b  #PC__RXRD,d1            ; read buffer ready status
        move.b  d1,(a3)                 ; first track
        moveq   #8,d0                   ; wait count
Lab246  dbra    d0,@6                   ; ... wait
        move.b  d1,(a3)                 ; other track
        addq.l  #2,SP                   ; set OK return
@9      rts
        ENDC

