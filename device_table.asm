
        xdef    maxdrv,devicetable,devicecount
        xdef    opdname,mdvname,flpname,ramname

*       Highest Device Number used

maxdrv  dc.w    4

*       Names of device types known to system
        
devicecount     dc.w    [[ramname-devicetable]/6]
devicetable
opdname dc.w    3
        dc.b    'Opd0'
mdvname dc.w    3
        dc.b    'Mdv0'
flpname dc.w    3
        dc.b    'Flp0'
ramname dc.w    3
        dc.b    'Ram0'
