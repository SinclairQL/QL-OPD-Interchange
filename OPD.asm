        TTL     OPD DEVICE DRIVER   (Version 2.7)
        PLEN    70
********************************************************************
**                                                                **
**            O P D      D E V I C E     D R I V E R              **
**            =================================                   **
**                                                                **
**      This is a device driver for use on the Sinclair QL that   **
**      allows microdrive cartridges in ICL OPD format to be      **
**      read and written.                                         **
**                                        LAST UPDATED: 20/04/87  **
********************************************************************


TASK            equ     1               ; 0=Physical Layer runs as task
ROMWRITE        equ     0               ; 0=Write routine from ROM
ROM             equ     0               ; 0=remainder from ROM
LOCKED          equ     0               ; 0=Access Level locking used
*                                         to prevent multiple entries

*       STANDARD DEFINITIONS

        GET     'Flp1_asmlib_Errors'
        GET     'Flp1_asmlib_Trap1'
        GET     'Flp1_asmlib_Trap3'
        GET     'Flp1_asmlib_Vectors'
        GET     'Flp1_asmlib_Channels'
        GET     'Flp1_asmlib_Files'
        GET     'Flp1_asmlib_Slave_Block'
        GET     'Flp1_asmlib_System'
        GET     'Flp1_asmlib_Hardware'
        GET     'Flp1_asmlib_QL_Header'
        GET     'Flp1_asmlib_OPD_Volume'
        GET     'Flp1_asmlib_OPD_Header'
        PAGE
*--------------------------------------------------------------------
*                       DEVICE DEFINITON TABLE
*                       ~~~~~~~~~~~~~~~~~~~~~~
*       NOTE.  OPDLOAD is used to complete the set-up of this block,
*       by inserting the missing information and converting relative
*       addresses to absolute ones.
*--------------------------------------------------------------------
table_base
        dc.l    0
        dc.l    0                       ; interrupt loop
        dc.l    0
        dc.l    OPD_PHYSICAL_LAYER-table_base      ; polled loop
        dc.l    0
        dc.l    0
access  dc.l    0
        dc.l    OPD_INPUT_OUTPUT-table_base
        dc.l    OPD_OPEN-table_base
        dc.l    OPD_CLOSE-table_base
        dc.l    OPD_SLAVE-table_base
        dc.l    0                       ; Rename (not used)
        dc.l    0                       ; Reserved
        dc.l    OPD_FORMAT-table_base
        dc.l    40+512+512              ; Phy def block size
        dc.w    3                       ; Length of device name
        dc.b    'OPD0'                  ; Device Type Name

*----------------------------------------------------------------------
*  Extensions for OPD Device Driver
*----------------------------------------------------------------------

fmtgap1 dc.w    900                     ; format delay count for gap 1
fmtgap2 dc.w    1150                    ; format delay count for gap 2

opdrun          dc.b    0               ; OPD drive running
opdchk          dc.b    0               ; drive to be checked
opdwait         dc.b    0
                dc.b    0
        IFEQ    ROMWRITE
gap1    dc.w    1024                    ; normal delay count for gap 1
        ENDC

*               Constants
*               ~~~~~~~~~
adjdate         dc.l    (9*365+2)*24*3600       ; OPD to QL date adjust
filestart       dc.l    $00010000               ; block/byte file start
spaces          dc.l    '    '

        TTL     OPD DRIVER:  Physical Layer
        PAGE
        GET     'Flp2_OPDphysical_asm'

        TTL     PHYSICAL LAYER:  Microdrive I/O
        PAGE
        GET     'Flp2_OPDmdv_asm'

        TTL     'PHYSICAL LAYER:  Slaving Routine'
        PAGE
        GET     'Flp2_OPDSlave_asm'

        TTL     ACCESS LAYER:  Format Routine
        PAGE
        GET     'Flp2_OPDFormat_asm'

        TTL     ACCESS LAYER:  Open/Delete/Close
        PAGE
        GET     'Flp2_OPDOpen_asm'

        TTL     ACCESS LAYER: Input-Output
        PAGE
        GET     'Flp2_OPDIO_asm'

        TTL     ACCESS LAYER:  General IO Routine
        PAGE
        GET     'Flp2_OPDIOGen_asm'

        TTL     ACCESS LAYER:  Directory Mapping
        PAGE
        GET     'Flp2_OPDMap_asm'

        END


