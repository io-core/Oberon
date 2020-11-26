(* begin-module-use-description
Module Input reads keyboard and mouse raw data and returns ASCII values and mouse state to Oberon.

end-module-use-description *)
(* begin-module-develop-description

(NW 5.10.86 / 15.11.90 Ceres-2; PDR 21.4.12 / NW 15.5.2013 Ceres-4 / PDW 19.4.2016)

**Input** is the interface to the keyboard and mouse in Oberon.

end-module-develop-description *)
MODULE Input; (*NW 5.10.86 / 15.11.90 Ceres-2; PDR 21.4.12 / NW 15.5.2013 Ceres-4 / PDW 19.4.2016*)
(* Adapted for a customizable framebuffer size -- see git history *)
  IMPORT SYSTEM;

  CONST 
    msAdr = -40; kbdAdr = -36;

  TYPE

  VAR 
    kbdCode: INTEGER; (*last keyboard code read*)
    Recd: BOOLEAN;
    MW, MH, MX, MY: INTEGER; (*mouse limits and coords*)
    MK: SET; (*mouse keys*)

(*FIFO implemented in hardware, because every read must be handled,
  including tracking the state of the Shift and Ctrl keys*)


  (* begin-section-description
## ---------- Keyboard
  end-section-description *)

  (* begin-procedure-description
---
**Peek** checks to see if a key has been pressed or released.
  end-procedure-description *)
  PROCEDURE Peek();
  BEGIN
    IF SYSTEM.BIT(msAdr, 28) THEN
      SYSTEM.GET(kbdAdr, kbdCode);
      kbdCode := (kbdCode DIV 1000000H MOD 100H) + (kbdCode DIV 10000H MOD 100H) * 100H;
      WHILE (~Recd) & (kbdCode = 0H) & (SYSTEM.BIT(msAdr, 28)) DO
        SYSTEM.GET(kbdAdr, kbdCode);
        kbdCode := (kbdCode DIV 1000000H MOD 100H) + (kbdCode DIV 10000H MOD 100H) * 100H;
      END;
      IF kbdCode # 0H THEN Recd := TRUE END;
   END;
  END Peek;


  (* begin-procedure-description
---
**Available** returns the available keypress.
  end-procedure-description *)
  PROCEDURE Available*(): INTEGER;
  BEGIN Peek();
    RETURN ORD(Recd)
  END Available;

  (* begin-procedure-description
---  
**ReadUnicode** delivers unicode values of pressed keys.
  end-procedure-description *)
  PROCEDURE ReadUnicode*(VAR codepoint: INTEGER);
  BEGIN
    WHILE ~Recd DO Peek() END ;
    codepoint := kbdCode;
    IF codepoint = 13 THEN codepoint := 10 END;
    Recd := FALSE
  END ReadUnicode;


  (* begin-section-description
## ---------- Mouse
  end-section-description *)

  (* begin-procedure-description
---  
**Mouse** provides the curent position and button state of the mouse.
  end-procedure-description *)
  PROCEDURE Mouse*(VAR keys: SET; VAR x, y: INTEGER);
    VAR w: INTEGER;
  BEGIN SYSTEM.GET(msAdr, w);
    keys := SYSTEM.VAL(SET, w DIV 1000000H MOD 8);
    x := w MOD 1000H; y := (w DIV 1000H) MOD 1000H;
    IF x >= MW THEN x := MW-1 END;
    IF y >= MH THEN y := MH-1 END
  END Mouse;

  (* begin-procedure-description
---  
**SetMouseLimits** restricts the mouse to the extent of the screen.
  end-procedure-description *)
  PROCEDURE SetMouseLimits*(w, h: INTEGER);
  BEGIN MW := w; MH := h
  END SetMouseLimits;


  (* begin-section-description
## ---------- Initialization
  end-section-description *)

  (* begin-procedure-description
---
**Init** sets the keyboard initial state and populates the scancode to ascii table.
  end-procedure-description *)
  PROCEDURE Init*;
  BEGIN Recd := FALSE;
  END Init;

BEGIN Init
END Input.
