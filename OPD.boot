1 CLS#0:PAPER#2,0:CLS#2
2 REPeat mainloop
3 WINDOW 512,202,0,0:PAPER 0:CLS:BORDER 16,0
4 CSIZE 3,1:OVER 1
5 FOR x=0 TO 4
6  INK 2+2*(x>2)
7  CURSOR 65-x,15-x
8  PRINT " OPD/QL INTERCHANGE "
9 END FOR x
10 CSIZE 2,0:OVER 0
11 AT 4,1:INK 2:PRINT " 1985, D.J.Walker      Release 2.51";
12 CSIZE 3,0:AT 6,9:PAPER 4:INK 0:PRINT " OPTIONS ":PAPER 0:CSIZE 2,0
13 menuline 8,1,"","Quit to SUPERBASIC"
14 menuline 10,2,"OPDCOPY: ","OPD/QL File Copy"
15 menuline 12,3,"OPDLOAD: ","Load   OPD Driver"
16 menuline 13,4,"OPDEND:  ","Unload OPD Driver"
17 AT 15,13:PAPER 2: INK 0
18 REPeat loop
19 opt$=INKEY$(-1):opt=CODE(opt$)
20 IF opt>=50 AND opt<=53 THEN PRINT " Loading ";
21 SELect ON opt
22   =49: CLOSE#1:OPEN#1,con:CLS: STOP
23   =50: EXEC_W 'Flp1_opdcopy':NEXT mainloop
24   =51: EXEC_W 'Flp1_opdload':EXIT loop
25   =52: EXEC_W 'Flp1_opdend':EXIT loop
26   =REMAINDER : BEEP 2000,200
27 END SELect 
28 END REPeat loop
29 END REPeat mainloop
30 DEFine PROCedure menuline (pos,num,prog,text)
31 AT pos,4:INK 6:PRINT num;". ";
32 INK 2:PRINT prog;:INK 4:PRINT text
33 END DEFine 
