(* begin-module-short-description
Tests the interrupt functionality of Oberon
end-module-short-description *)


(* begin-module-use-description
Module TestInt tests the Interrupt functionality of Oberon

end-module-use-description *)
(* begin-module-develop-description

Module TestInt enables or disables the central interrupt and registers an interrupt procedure that blinks an LED.

end-module-develop-description *)
MODULE TestInt;
 IMPORT SYSTEM;

 VAR led, cnt: INTEGER;

  (* begin-procedure-description
---
**Int** fields the system millisecond interrupt and toggles the LED every half second.
  end-procedure-description *)
 PROCEDURE* Int; (*interrupt handler called every millisecond*)
 BEGIN 
   INC(cnt);
   IF cnt = 500 THEN led := 3 - led; LED(led); cnt := 0 END 
 END Int;

  (* begin-procedure-description
---
**On** enables the system millisecond interrupt.
  end-procedure-description *)
 PROCEDURE On*;
 BEGIN SYSTEM.LDPSR(1)
 END On;

  (* begin-procedure-description
---
**Off** disables the system millisecond interrupt.
  end-procedure-description *)
 PROCEDURE Off*;
 BEGIN SYSTEM.LDPSR(0)
 END Off;

  (* begin-procedure-description
---
**The initialzation code for this module** installs the Int interrupt procedure in the system interrupt vector.
  end-procedure-description *)
BEGIN led := 1; cnt := 0; (*install Int at address 4*)
 SYSTEM.PUT(4, 0E7000000H + (SYSTEM.ADR(Int) DIV 4) - 2) (* relative forward branch with pc already incremented *) 
END TestInt.
