MODULE Display;  (*NW 5.11.2013, others...*)
(* Adapted for a customizable framebuffer size and variable base address *)

  IMPORT SYSTEM;

  CONST replace* = 0; paint* = 1; invert* = 2;  (*modes*)

  TYPE Frame* = POINTER TO FrameDesc;
    FrameMsg* = RECORD END ;
    Handler* = PROCEDURE (F: Frame; VAR M: FrameMsg);
    FrameDesc* = RECORD next*, dsc*: Frame;
        X*, Y*, W*, H*: INTEGER;
        handle*: Handler
      END ;

  VAR Base*, Width*, Height*, Depth*, Span, Pack, black*, white*, bgcolor*, fgcolor*: INTEGER;
    arrow*, star*, hook*, updown*, block*, cross*, grey*: INTEGER;
    (*a pattern is an array of bytes; the first is its width (< 32), the second its height, the rest the raster*)

  PROCEDURE Handle*(F: Frame; VAR M: FrameMsg);
  BEGIN
    IF (F # NIL) & (F.handle # NIL) THEN F.handle(F, M) END
  END Handle;

  (* raster ops *)

  PROCEDURE Dot*(col, x, y, mode: INTEGER);
    VAR a, v, b: INTEGER; u, s: SET;
  BEGIN a := Base + (x DIV Pack)*4 + y*Span;
    SYSTEM.GET(a, u);
    IF Depth = 1 THEN
      s := {x MOD 32}
    ELSE
      s := {(x MOD Pack)*Depth .. (((x+1) MOD Pack)*Depth)-1};
    END;
    IF mode = paint THEN SYSTEM.PUT(a, u + s)
    ELSIF mode = invert THEN SYSTEM.PUT(a, u / s)
    ELSE (*mode = replace*)
      IF col # black THEN SYSTEM.PUT(a, u + s) ELSE SYSTEM.PUT(a, u - s) END
    END
  END Dot;

  PROCEDURE ReplConst*(col, x, y, w, h, mode: INTEGER);
    VAR al, ar, a0, a1, i: INTEGER; left, right, mid, pix, pixl, pixr: SET;
  BEGIN 
    al := Base + y*Span;
    ar := ((x+w-1) DIV Pack)*4 + al; 
    al := (x DIV Pack)*4 + al;
    IF ar = al THEN
      mid := {(x MOD Pack)*Depth .. ((((x+w) MOD Pack))*Depth)-1};
      a1 := al;
      FOR i := 1 TO h DO
        SYSTEM.GET(a1, pix);
        IF mode = invert THEN SYSTEM.PUT(a1, pix / mid)
        ELSIF (mode = replace) & (col = black) THEN (*erase*) SYSTEM.PUT(a1, pix - mid)
        ELSE (* (mode = paint) OR (mode = replace) & (col # black) *) SYSTEM.PUT(a1, pix + mid)
        END;
        INC(a1, Span)
      END
    ELSE
      left  := {(x MOD Pack)*Depth .. 31};
      right := {0 .. ((((x+w) MOD Pack))*Depth)-1};
      a0 := al;
      FOR i := 1 TO h DO
        SYSTEM.GET(a0, pixl); SYSTEM.GET(ar, pixr);
        IF mode = invert THEN
          SYSTEM.PUT(a0, pixl / left);
          FOR a1 := a0+4 TO ar-4 BY 4 DO SYSTEM.GET(a1, pix); SYSTEM.PUT(a1, -pix) END ;
          SYSTEM.PUT(ar, pixr / right)
        ELSIF (mode = replace) & (col = black) THEN (*erase*)
          SYSTEM.PUT(a0, pixl - left);
          FOR a1 := a0+4 TO ar-4 BY 4 DO SYSTEM.PUT(a1, {}) END ;
          SYSTEM.PUT(ar, pixr - right)
        ELSE (* (mode = paint) OR (mode = replace) & (col # black) *)
          SYSTEM.PUT(a0, pixl + left);
          FOR a1 := a0+4 TO ar-4 BY 4 DO SYSTEM.PUT(a1, {0 .. 31}) END ;
          SYSTEM.PUT(ar, pixr + right)
        END ;
        INC(ar, Span); INC(a0, Span)
      END
    END
  END ReplConst;


  PROCEDURE CopyPattern*(col, patadr, x, y, mode: INTEGER);  (*only for modes = paint, invert*)
    VAR a0, pwd, i, j: INTEGER;
      w, h, pbt: BYTE; b0,pix: SET;
  BEGIN SYSTEM.GET(patadr, w); SYSTEM.GET(patadr+1, h); INC(patadr, 2);
    a0 := Base + (x DIV Pack)*4 + y*Span;
    FOR i := 1 TO h DO
      (*build pattern line; w < 32*)
      SYSTEM.GET(patadr, pbt); INC(patadr); pwd := pbt;
      IF w > 8 THEN SYSTEM.GET(patadr, pbt); INC(patadr); pwd := pbt*100H + pwd;
        IF w > 16 THEN SYSTEM.GET(patadr, pbt); INC(patadr); pwd := pbt*10000H + pwd;
          IF w > 24 THEN SYSTEM.GET(patadr, pbt); INC(patadr); pwd := pbt*1000000H + pwd END
        END
      END ;
      IF Depth = 1 THEN
        SYSTEM.GET(a0, pix);
        IF mode = invert THEN SYSTEM.PUT(a0, SYSTEM.VAL(SET, LSL(pwd, x MOD 32)) / pix)
        ELSE SYSTEM.PUT(a0, SYSTEM.VAL(SET, LSL(pwd, x MOD 32)) + pix)
        END;
      ELSE
	
	FOR j:= 0 TO 31 DO
          b0:=SYSTEM.VAL(SET,pwd);
	  pbt := 255;
	  IF mode=invert THEN
            IF j IN b0 THEN 
               SYSTEM.GET(a0+j+(x MOD Pack),pbt); 
	       IF pbt = 255 THEN pbt := 0 ELSE pbt := 255 END;
               SYSTEM.PUT(a0+j+(x MOD Pack),pbt) 
            END
	  ELSE
	    IF j IN b0 THEN SYSTEM.PUT(a0+j+(x MOD Pack),pbt) END
	  END
	END
      END ;
      IF (x MOD 32) + w > 32 THEN (*spill over*)
        IF Depth = 1 THEN
          SYSTEM.GET(a0+4, pix);

          IF mode = invert THEN SYSTEM.PUT(a0+4, SYSTEM.VAL(SET, ASR(pwd, -(x MOD 32))) / pix)
          ELSE                  SYSTEM.PUT(a0+4, SYSTEM.VAL(SET, ASR(pwd, -(x MOD 32))) + pix)
          END
        END
      END;
      INC(a0, Span)
    END
  END CopyPattern;

  PROCEDURE CopyImage*(sx, sy, sw, sh, sdepth, sspan, dx, dy, ddepth, dspan, mode: INTEGER); (*only for mode = replace*)
    VAR sa, da, sa0, sa1, d, len: INTEGER;
      u0, u1, u2, u3, v0, v1, v2, v3, n: INTEGER;
      end, step: INTEGER;
      src, dst, spill: SET;
      m0, m1, m2, m3: SET;
  BEGIN
    u0 := sx DIV Pack; u1 := sx MOD Pack; u2 := (sx+sw) DIV Pack; u3 := (sx+sw) MOD Pack;
    v0 := dx DIV Pack; v1 := dx MOD Pack; v2 := (dx+sw) DIV Pack; v3 := (dx+sw) MOD Pack;
    sa := Base + u0*4 + sy*Span; da := Base + v0*4 + dy*Span;
    d := da - sa; n := u1 - v1;   (*displacement in words and bits*)
    len := (u2 - u0) * 4;
    m0 := {v1 .. 31}; m2 := {v3 .. 31}; m3 := m0 / m2;
    IF d >= 0 THEN (*copy up, scan down*) sa0 := sa + (sh-1)*Span; end := sa-Span; step := -Span
    ELSE (*copy down, scan up*) sa0 := sa; end := sa + sh*Span; step := Span
    END ;
    WHILE sa0 # end DO
      IF n >= 0 THEN (*shift right*) m1 := {n .. 31};
        IF v1 + sw >= 32 THEN
          SYSTEM.GET(sa0+len, src); src := ROR(src, n);
          SYSTEM.GET(sa0+len+d, dst);
          SYSTEM.PUT(sa0+len+d, (dst * m2) + (src - m2));
          spill := src - m1;
          FOR sa1 := sa0 + len-4 TO sa0+4  BY -4 DO
            SYSTEM.GET(sa1, src); src := ROR(src, n);
            SYSTEM.PUT(sa1+d, spill + (src * m1));
            spill := src - m1
          END ;
          SYSTEM.GET(sa0, src); src := ROR(src, n);
          SYSTEM.GET(sa0+d, dst);
          SYSTEM.PUT(sa0+d, (src * m0) + (dst - m0))
        ELSE SYSTEM.GET(sa0, src); src := ROR(src, n);
          SYSTEM.GET(sa0+d, dst);
          SYSTEM.PUT(sa0+d, (src * m3) + (dst - m3))
        END
      ELSE (*shift left*) m1 := {-n .. 31};
        SYSTEM.GET(sa0, src); src := ROR(src, n);
        SYSTEM.GET(sa0+d, dst);
        IF v1 + sw < 32 THEN
          SYSTEM.PUT(sa0+d, (dst - m3) + (src * m3))
        ELSE SYSTEM.PUT(sa0+d, (dst - m0) + (src * m0));
          spill := src - m1;
          FOR sa1 := sa0+4 TO sa0 + len-4 BY 4 DO
            SYSTEM.GET(sa1, src); src := ROR(src, n);
            SYSTEM.PUT(sa1+d, spill + (src * m1));
            spill := src - m1
          END ;
          SYSTEM.GET(sa0+len, src); src := ROR(src, n);
          SYSTEM.GET(sa0+len+d, dst);
          SYSTEM.PUT(sa0+len+d, (src - m2) + (dst * m2))
        END
      END ;
      INC(sa0, step)
    END
  END CopyImage;

  PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: INTEGER);
  BEGIN
    CopyImage(sx, sy, w, h, Depth, Span, dx, dy, Depth, Span, mode)
  END CopyBlock;



  PROCEDURE ReplPattern*(col, patadr, x, y, w, h, mode: INTEGER);
  (* pattern width = 32, fixed; pattern starts at patadr+4, for mode = invert only *)
    VAR al, ar, a0, a1, i: INTEGER;
      pta0, pta1: INTEGER;  (*pattern addresses*)
      ph: BYTE;
      left, right, mid, pix, pixl, pixr, ptw: SET;
  BEGIN al := Base + y*Span; SYSTEM.GET(patadr+1, ph);
    pta0 := patadr+4; pta1 := ph*4 + pta0;
    ar := ((x+w-1) DIV 32)*4 + al; al := (x DIV 32)*4 + al;
    IF ar = al THEN
      mid := {(x MOD 32) .. ((x+w-1) MOD 32)};
      a1 := al;
      FOR i := 1 TO h DO
        SYSTEM.GET(a1, pix); SYSTEM.GET(pta0, ptw); SYSTEM.PUT(a1, (pix - mid) + (pix/ptw * mid)); INC(pta0, 4);
        IF pta0 = pta1 THEN pta0 := patadr+4 END;
        INC(a1, Span);
      END
    ELSE
      left := {(x MOD 32) .. 31}; right := {0 .. ((x+w-1) MOD 32)};
      a0 := al;
      FOR i := 1 TO h DO
        SYSTEM.GET(a0, pixl); SYSTEM.GET(pta0, ptw); SYSTEM.PUT(a0, (pixl - left) + (pixl/ptw * left));
        FOR a1 := a0+4 TO ar-4 BY 4 DO SYSTEM.GET(a1, pix); SYSTEM.PUT(a1, pix/ptw) END ;
        SYSTEM.GET(ar, pixr); SYSTEM.PUT(ar, (pixr - right) + (pixr/ptw * right));
        INC(pta0, 4); INC(ar, Span);
        IF pta0 = pta1 THEN pta0 := patadr+4 END;
        INC(a0, Span)
      END
    END
  END ReplPattern;

  PROCEDURE InitResolution;
  VAR magic: INTEGER;
  BEGIN
    black := 0;
    white := 1;
    Pack  := 32;
    SYSTEM.GET(Base, magic);
    IF magic = 53697A65H THEN
      SYSTEM.GET(Base + 4, Width);
      SYSTEM.GET(Base + 8, Height);
      Depth := 1;
      Span := 128;
    ELSIF magic = 53697A66H THEN
      SYSTEM.GET(Base + 4, Width);
      SYSTEM.GET(Base + 8, Height);
      Depth := 1;
      Span := Width DIV 8
    ELSIF magic = 53697A67H THEN
      SYSTEM.GET(Base + 4, Width);
      SYSTEM.GET(Base + 8, Height);
      SYSTEM.GET(Base + 12, Depth);
      Span := Depth * Width DIV 8;
      Pack := 32 DIV Depth;
      white := 255;
    ELSE
      Width := 1024; Height := 768; Span := 128; Depth := 1
    END;
    bgcolor := black;
    fgcolor := white;
  END InitResolution;

BEGIN SYSTEM.GET(12,Base); INC(Base,16); InitResolution;
  arrow := SYSTEM.ADR($0F0F 0060 0070 0038 001C 000E 0007 8003 C101 E300 7700 3F00 1F00 3F00 7F00 FF00$);
  star := SYSTEM.ADR($0F0F 8000 8220 8410 8808 9004 A002 C001 7F7F C001 A002 9004 8808 8410 8220 8000$);
  hook := SYSTEM.ADR($0C0C 070F 8707 C703 E701 F700 7F00 3F00 1F00 0F00 0700 0300 01$);
  updown := SYSTEM.ADR($080E 183C 7EFF 1818 1818 1818 FF7E3C18$);
  block := SYSTEM.ADR($0808 FFFF C3C3 C3C3 FFFF$);
  cross := SYSTEM.ADR($0F0F 0140 0220 0410 0808 1004 2002 4001 0000 4001 2002 1004 0808 0410 0220 0140$);
  grey := SYSTEM.ADR($2002 0000 5555 5555 AAAA AAAA$)
END Display.
