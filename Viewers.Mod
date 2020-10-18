(* begin-module-use-description
Module Viewers implements base functionaltiy which may be extended for interacting with a pane or 'Viewer' in Oberon.

end-module-use-description *)
(* begin-module-develop-description

(JG 14.9.90 / NW 15.9.13 / AP 13.2.20 Extended Oberon)

**Viewers** introduces the core functionality for graphical interaction in Oberon.

Viewers operate on Frames, which are the arrangeable components of User interaction in Oberon.

Viewers coordinate via messages. Extensions of `Viewer` will extend `ViewerMsg` for corresponding functionaltiy.

Extensions of `Viewer` inherit the basic UI functionaltiy declared in this module, including the creation, expansion, closure, focus tracking, etc. of viewers.

end-module-develop-description *)
MODULE Viewers; (*JG 14.9.90 / NW 15.9.13 / AP 13.2.20 Extended Oberon*)
  IMPORT Display;

  CONST 
    restore* = 0; modify* = 1; suspend* = 2; (*message ids*)
    inf = 65535; DnLength* = 32;

  TYPE 
    Viewer* = POINTER TO ViewerDesc;
    ViewerDesc* = RECORD (Display.FrameDesc) prev, parent: Viewer;
      minH*, state*: INTEGER
    END;

    (*state > 1: displayed; state = 1: filler; state = 0: closed; state = -1: track or suspended filler; state < -1: suspended*)

    ViewerMsg* = RECORD (Display.FrameMsg)
      id*: INTEGER;                      (*restore, modify, suspend*)
      X*, Y*, W*, H*: INTEGER;
      state*: INTEGER
    END;

    Track = POINTER TO TrackDesc;
    TrackDesc = RECORD (ViewerDesc) under: Display.Frame END;

    DisplayArea* = POINTER TO DisplayDesc;  (*logical display area*)
    DisplayDesc* = RECORD (ViewerDesc)
      curW*, id*: INTEGER;
      name*: ARRAY DnLength OF CHAR;
      focus, (*focus viewer*)
      backup: Viewer (*last closed viewer*)
    END;

  VAR 
    CurDisplay*, root*: DisplayArea;
    FocusViewer*: Viewer;
    nextId: INTEGER;

  (* begin-section-description
## ---------- Oberon Message Handling
  end-section-description *)

  (* begin-procedure-description
---
**ThisViewer** finds the viewer containing the point represented by D, X, and Y.
  end-procedure-description *)
  PROCEDURE ThisViewer* (D: DisplayArea; X, Y: INTEGER): Viewer;
    VAR T, V: Display.Frame;
  BEGIN
    IF (X < inf) & (Y < D.H) THEN
      T := D.dsc;
      REPEAT T := T.next UNTIL X < T.X + T.W;
      V := T.dsc;
      REPEAT V := V.next UNTIL Y < V.Y + V.H
    ELSE V := NIL
    END;
    RETURN V(Viewer)
  END ThisViewer;

  (* begin-procedure-description
---
**This** passes the current display to ThisViewer to locate the viewer that contains a point.
  end-procedure-description *)
  PROCEDURE This* (X, Y: INTEGER): Viewer;  (*for backward compatibility*)
    VAR V: Viewer;
  BEGIN
    IF CurDisplay # NIL THEN V := ThisViewer(CurDisplay, X, Y) ELSE V := NIL END ;
    RETURN V
  END This;

  (* begin-procedure-description
---
**ThisDisplay** finds the DisplayArea of a Viewer.
  end-procedure-description *)
  PROCEDURE ThisDisplay* (V: Viewer): DisplayArea;
  BEGIN
    WHILE (V # NIL) & (V.parent # NIL) (*~display*) DO V := V.parent END;
    RETURN V(DisplayArea)
  END ThisDisplay;

  (* begin-procedure-description
---
**Next** cycles through the defined DisplayAreas 
  end-procedure-description *)
  PROCEDURE Next* (V: Viewer): Viewer;
  BEGIN
    IF (V IS DisplayArea) & (V.next = NIL) THEN V := root ELSE V := V.next(Viewer) END;
    RETURN V
  END Next;

  (* begin-procedure-description
---
**Prev** cycles (backwards) through the defined DisplayAreas.
  end-procedure-description *)
  PROCEDURE Prev* (V: Viewer): Viewer;
  BEGIN RETURN V.prev(Viewer)
  END Prev;

  (* begin-procedure-description
---
**SetFocus** assigns the focus (`FocusViewer` global variable) to the `Viewer` parameter. 
  end-procedure-description *)
  PROCEDURE SetFocus* (D: DisplayArea; V: Viewer);
  BEGIN D.focus := V;
    IF D = CurDisplay THEN FocusViewer := V END
  END SetFocus;

  (* begin-procedure-description
---
**GetFocus** returns the Viewer in a DisplayArea that has the focus. 
  end-procedure-description *)
  PROCEDURE GetFocus* (D: DisplayArea): Viewer;
  BEGIN RETURN D.focus
  END GetFocus;

  (* begin-procedure-description
---
**Adjust** sends a message to the Frame to handle the adjustment of its vertical position and extent.
  end-procedure-description *)
  PROCEDURE Adjust* (F: Display.Frame; id, Y, H: INTEGER);
    VAR M: ViewerMsg;
  BEGIN M.id := id; M.Y := Y; M.H := H; F.handle(F, M); F.Y := Y; F.H := H
  END Adjust;

  (* begin-procedure-description
---
**Open** prepares a new frame, adjusting other affected viewers via messages.
  end-procedure-description *)
  PROCEDURE Open* (D: DisplayArea; V: Viewer; X, Y: INTEGER);
    VAR T, v: Display.Frame; M: ViewerMsg;
  BEGIN
    IF (V.state = 0) & (X < inf) THEN
      IF Y > D.H THEN Y := D.H END;
      T := D.dsc.next; (*first track*)
      WHILE X >= T.X + T.W DO T := T.next END;
      v := T.dsc.next;
      WHILE Y > v.Y + v.H DO v := v.next END;
      IF Y < v.Y + V.minH THEN Y := v.Y + V.minH END;
      IF (v.next.Y # 0) & (Y > v.Y + v.H - v(Viewer).minH) THEN
        V.X := T.X; V.W := T.W; V.Y := v.Y; V.H := v.H;
        M.id := suspend; M.state := 0; v.handle(v, M); v(Viewer).state := 0;
        V.next := v.next; V.prev := v(Viewer).prev; v(Viewer).prev.next := V; v.next(Viewer).prev := V;
        V(Viewer).parent := T(Viewer); V.state := 2
      ELSE V.X := T.X; V.W := T.W; V.Y := v.Y; V.H := Y - v.Y;
        Adjust(v, modify, Y, v.Y + v.H - Y);
        V.next := v; V.prev := v(Viewer).prev; v(Viewer).prev.next := V; v(Viewer).prev := V;
        V(Viewer).parent := T(Viewer); V.state := 2
      END
    END
  END Open;

  (* begin-procedure-description
---
**Validate** ensures correct viewer state. 
  end-procedure-description *)
  PROCEDURE Validate* (V: Viewer; VAR Y, H: INTEGER);
    VAR D: DisplayArea; v: Display.Frame; s: INTEGER;
  BEGIN
    IF V.state > 1 THEN D := ThisDisplay(V);
      IF H < V.minH THEN H := V.minH END;
      v := V.prev; s := 0;
      WHILE v(Viewer).state > 1 DO s := s + v(Viewer).minH; v := v(Viewer).prev END;
      IF Y < s THEN Y := s END;
      v := V.next; s := 0;
      WHILE v(Viewer).state > 1 DO s := s + v(Viewer).minH; v := v.next END;
      IF Y > D.H - s - V.minH THEN Y := D.H - s - V.minH; H := V.minH
      ELSIF Y + H > D.H - s THEN H := D.H - s - Y
      END
    END
  END Validate;

  (* begin-procedure-description
---
**Change** adjusts a viewer. 
  end-procedure-description *)
  PROCEDURE Change* (V: Viewer; Y, H: INTEGER);
    CONST none = 0; self = 1; above = 2; below = 3;
    VAR v: Viewer; i, y, dY: INTEGER; m: ARRAY 3 OF INTEGER; up, down: BOOLEAN;
  BEGIN (*Y, H validated*)
    IF V.state > 1 THEN
      m[0] := none; m[1] := self; m[2] := none;
      up := Y + H > V.Y + V.H; down := Y + H < V.Y + V.H;
      IF Y < V.Y THEN m[0] := below;
        IF up THEN m[1] := above; m[2] := self ELSIF down THEN m[2] := above END
      ELSIF Y > V.Y THEN m[2] := below;
        IF up THEN m[0] := above ELSIF down THEN m[0] := self; m[1] := above END
      ELSE
        IF up THEN m[0] := above ELSIF down THEN m[2] := above ELSE m[1] := none END
      END;
      FOR i := 0 TO 2 DO
        IF m[i] = self THEN Adjust(V, modify, Y, H)
        ELSIF m[i] = above THEN v := V.next(Viewer);
          IF up THEN dY := Y + H - V.Y - V.H;
            WHILE (v.state > 1) & (dY > v.H - v.minH) DO dY := dY - v.H + v.minH; v := v.next(Viewer) END;
            y := v.Y + dY;
            Adjust(v, modify, y, v.H - dY); v := v.prev; y := y - v.minH;
            WHILE v # V DO Adjust(v, modify, y, v.minH); v := v.prev; y := y - v.minH END
          ELSE Adjust(v, modify, Y + H, v.Y + v.H - Y - H)
          END
        ELSIF m[i] = below THEN v := V.prev;
          IF v.state > 1 THEN
            IF Y > V.Y THEN Adjust(v, modify, v.Y, Y - v.Y)
            ELSE dY := V.Y - Y;
              WHILE (v.state > 1) & (dY > v.H - v.minH) DO dY := dY - v.H + v.minH; v := v.prev END;
              IF v.state > 1 THEN Adjust(v, modify, v.Y, v.H - dY); y := v.Y + v.H ELSE y := v.Y END;
              v := v.next(Viewer);
              WHILE v # V DO Adjust(v, modify, y, v.minH); y := y + v.H; v := v.next(Viewer) END
            END
          END
        END
      END
    END
  END Change;

  (* begin-procedure-description
---
**Spread** redistributes viewers vertically. 
  end-procedure-description *)
  PROCEDURE Spread* (D: DisplayArea; X, W: INTEGER); (*redistribute viewers vertically*)
    VAR T, t, v, fil: Display.Frame; M: ViewerMsg; Y, H: INTEGER;
  BEGIN
    IF X < inf THEN
      T := D.dsc.next;
      WHILE X >= T.X + T.W DO T := T.next END;
      t := T(Viewer).prev;
      WHILE X + W > T.X + T.W DO T := T.next END;
      M.id := restore;
      REPEAT t := t.next; fil := t.dsc; v := fil.next;
        IF v # fil THEN H := 0;
          REPEAT INC(H); v := v.next UNTIL v = fil;
          H := D.H DIV H; v := fil; Y := 0;
          REPEAT v := v.next; v.Y := Y;
            IF v.next = fil THEN v.H := D.H - Y; H := 0 ELSE v.H := H END;
            v.handle(v, M); Y := Y + v.H
          UNTIL v = fil
        END
      UNTIL t = T
    END
  END Spread;

  (* begin-procedure-description
---
**RestoreTrack** returns a track to its previous arrangement. 
  end-procedure-description *)
  PROCEDURE RestoreTrack (S: Display.Frame);
    VAR T, t, v: Display.Frame; M: ViewerMsg;
  BEGIN t := S(Viewer).prev; T := S(Track).under;
    WHILE T.next # NIL DO T := T.next END;
    t.next := S(Track).under; t.next(Viewer).prev := t(Viewer); T.next := S.next; T.next(Viewer).prev := T(Viewer);
    M.id := restore;
    REPEAT t := t.next; v := t.dsc;
      REPEAT v := v.next; v.handle(v, M); v(Viewer).state := - v(Viewer).state
      UNTIL v = t.dsc
    UNTIL t = T
  END RestoreTrack;

  (* begin-procedure-description
---
**Close** removes a viewer from a track.
  end-procedure-description *)
  PROCEDURE Close* (V: Viewer);
    VAR D: DisplayArea; T, U: Display.Frame; M: ViewerMsg;
  BEGIN
    IF V.state > 1 THEN D := ThisDisplay(V);
      U := V.next; T := D.dsc;
      REPEAT T := T.next UNTIL V.X < T.X + T.W;
      IF (T(Track).under = NIL) OR (U.next # V) THEN
        M.id := suspend; M.state := 0; V.handle(V, M); V.state := 0;
        Adjust(U, modify, V.Y, V.H + U.H);
        V.prev.next := V.next; V.next(Viewer).prev := V.prev; D.backup := V
      ELSE (*close track*)
        M.id := suspend; M.state := 0; V.handle(V, M); V.state := 0;
        U.handle(U, M); U(Viewer).state := 0; D.backup := V;
        RestoreTrack(T)
      END;
      V.next := NIL; V.prev := NIL; (*make other viewers unreachable from V*)
      IF D.focus = V THEN SetFocus(D, ThisViewer(D, 0, 0)) END
    END
  END Close;

  (* begin-procedure-description
---
**Recall** brings back the last closed viewer.
  end-procedure-description *)
  PROCEDURE Recall* (D: DisplayArea; VAR V: Viewer); (*last closed viewer*)
  BEGIN V := D.backup
  END Recall;

  (* begin-procedure-description
---
**Flush** permanently removes the last closed viewer. 
  end-procedure-description *)
  PROCEDURE Flush* (D: DisplayArea); (*last closed viewer*)
  BEGIN D.backup := NIL
  END Flush;

  (* begin-procedure-description
---
**Locate** determines the context of a viewer
  end-procedure-description *)
  PROCEDURE Locate* (D: DisplayArea; X, H: INTEGER; VAR fil, top, bot, alt, max: Display.Frame);
    VAR T, V: Display.Frame;
  BEGIN
    IF X < inf THEN
      T := D.dsc;
      REPEAT T := T.next UNTIL X < T.X + T.W;
      fil := T.dsc; top := fil(Viewer).prev; bot := fil.next;
      IF bot.next # fil THEN
        alt := bot.next; V := alt.next;
        WHILE (V # fil) & (alt.H < H) DO
          IF V.H > alt.H THEN alt := V END;
          V := V.next
        END
      ELSE alt := bot
      END;
      max := T.dsc; V := max.next;
      WHILE V # fil DO
        IF V.H > max.H THEN max := V END;
        V := V.next
      END
    END
  END Locate;

  (* begin-procedure-description
---
**Install** places frame F as a subframe into parent frame
  end-procedure-description *)
  PROCEDURE Install* (parent, F: Display.Frame); (*frame F as a subframe into parent frame*)
    VAR f: Display.Frame;
  BEGIN F.next := NIL;
    IF parent.dsc = NIL THEN parent.dsc := F
    ELSE f := parent.dsc;
      WHILE f.next # NIL DO f := f.next END;
      f.next := F
    END
  END Install;

  (* begin-procedure-description
---
**Remove** takes subframe F from its parent frame
  end-procedure-description *)
  PROCEDURE Remove* (parent, F: Display.Frame); (*subframe F from its parent frame*)
    VAR f, f0: Display.Frame;
  BEGIN
    IF parent.dsc = F THEN parent.dsc := F.next
    ELSE f0 := parent.dsc; f := f0.next;
      WHILE (f # NIL) & (f # F) DO f0 := f; f := f.next END;
      IF f # NIL THEN f0.next := f.next END
    END
  END Remove;

  (* begin-procedure-description
---
**InitFiller** initializes filler values.
  end-procedure-description *)
  PROCEDURE InitFiller (X, Y, W, H, minH: INTEGER; Filler: Viewer); (*except fields handle, parent, dsc*)
  BEGIN Filler.X := X; Filler.Y := Y; Filler.W := W; Filler.H := H; Filler.minH := minH;
    Filler.state := 1; Filler.next := Filler; Filler.prev := Filler
  END InitFiller;

  (* begin-procedure-description
---
**InitTrack** initializes a track.
  end-procedure-description *)
  PROCEDURE InitTrack* (D: DisplayArea; W, H: INTEGER; Filler: Viewer);
    VAR T, fillerTrack: Track; fillerViewer: Viewer;
  BEGIN InitFiller(D.curW, 0, W, H, 0, Filler); Filler.dsc := NIL;
    NEW(T); T.dsc := Filler; Filler.parent := T; T.parent := D; T.under := NIL;
    T.X := D.curW; T.Y := 0; T.W := W; T.H := H; T.minH := 0; T.state := -1; (*track*)
    fillerTrack := D.dsc(Track); fillerViewer := fillerTrack.dsc(Viewer);
    fillerViewer.X := D.curW + W; fillerViewer.W := inf - fillerViewer.X;
    fillerTrack.X := fillerViewer.X; fillerTrack.W := fillerViewer.W;
    T.next := fillerTrack; T.prev := fillerTrack.prev; T.prev.next := T; fillerTrack.prev := T;
    D.curW := D.curW + W
  END InitTrack;

  (* begin-procedure-description
---
**OpenTrack** opens a track. 
  end-procedure-description *)
  PROCEDURE OpenTrack* (D: DisplayArea; X, W: INTEGER; Filler: Viewer);
    VAR newT: Track; S, T, t, v: Display.Frame; M: ViewerMsg; v0: Viewer;
  BEGIN
    IF (X < inf) & (Filler.state = 0) THEN
      T := D.dsc.next;
      WHILE X >= T.X + T.W DO T := T.next END;
      S := T(Viewer).prev;
      WHILE X + W > T.X + T.W DO T := T.next END;
      M.id := suspend; t := S;
      REPEAT t := t.next; v := t.dsc;
        REPEAT v := v.next; M.state := -v(Viewer).state; v.handle(v, M); v(Viewer).state := M.state
        UNTIL v = t.dsc
      UNTIL t = T;
      InitFiller(S.next.X, 0, T.X + T.W - S.next.X, D.H, 0, Filler); Filler.dsc := NIL;
      NEW(newT); newT.dsc := Filler; Filler.parent := newT; newT.parent := D;
      newT.X := Filler.X; newT.Y := 0; newT.W := Filler.W; newT.H := D.H; newT.minH := 0;
      newT.state := -1; (*track*) newT.under := S.next; S.next(Viewer).prev := NIL;
      newT.next := T.next; newT.prev := S(Viewer); S.next := newT; T.next(Viewer).prev := newT; T.next := NIL
    END
  END OpenTrack;

  (* begin-procedure-description
---
**CloseTrack** closes a track. 
  end-procedure-description *)
  PROCEDURE CloseTrack* (D: DisplayArea; X: INTEGER);
    VAR T, V: Display.Frame; M: ViewerMsg; hasFocus: BOOLEAN;
  BEGIN
    IF X < inf THEN
      T := D.dsc;
      REPEAT T := T.next UNTIL X < T.X + T.W;
      IF T(Track).under # NIL THEN hasFocus := FALSE;
        M.id := suspend; M.state := 0; V := T.dsc;
        REPEAT V := V.next; V.handle(V, M); V(Viewer).state := 0;
          IF D.focus = V THEN hasFocus := TRUE END
        UNTIL V = T.dsc;
        RestoreTrack(T);
        IF hasFocus THEN SetFocus(D, ThisViewer(D, 0, 0)) END
      END
    END
  END CloseTrack;

  (* begin-procedure-description
---
**Broadcast** sends a message to all viewers in the current display
  end-procedure-description *)
  PROCEDURE Broadcast* (VAR M: Display.FrameMsg); (*to current display*)
    VAR T, V: Display.Frame;
  BEGIN
    IF CurDisplay # NIL THEN
      T := CurDisplay.dsc.next;
      WHILE T # CurDisplay.dsc DO
        V := T.dsc;
        REPEAT V := V.next; V.handle(V, M) UNTIL V = T.dsc;
        T := T.next
      END
    END
  END Broadcast;

  (* begin-procedure-description
---
**InitDisplay** prepares a display for use. 
  end-procedure-description *)
  PROCEDURE InitDisplay* (D: DisplayArea; W, H: INTEGER; name: ARRAY OF CHAR);
    VAR fillerTrack: Track; fillerViewer: Viewer;
  BEGIN D.id := nextId;
    D.name := name; D.curW := 0; D.focus := NIL; D.backup := NIL;
    D.X := 0; D.Y := 0; D.W := W; D.H := H; D.minH := 1; D.state := 0; D.parent := NIL;
    NEW(fillerTrack); InitFiller(0, 0, inf, H, 0, fillerTrack); D.dsc := fillerTrack;
    NEW(fillerViewer); InitFiller(0, 0, inf, H, 0, fillerViewer); fillerTrack.dsc := fillerViewer;
    fillerTrack.parent := D; fillerViewer.parent := fillerTrack; fillerViewer.dsc := NIL; D.focus := fillerViewer;
    IF root = NIL THEN root := D ELSE D.prev := root.prev; D.prev.next := D END;
    root.prev := D; D.next := NIL; nextId := nextId + 1
  END InitDisplay;

  (* begin-procedure-description
---
**SetDisplay** suspends the current display via a broadcast message and activates the chosen display via another broadcast message.
  end-procedure-description *)
  PROCEDURE SetDisplay* (D: DisplayArea);
    VAR M: ViewerMsg;
  BEGIN
    IF CurDisplay # NIL THEN M.id := suspend; M.state := 0; Broadcast(M); CurDisplay.state := 0 END;
    CurDisplay := D; D.state := 2; SetFocus(D, ThisViewer(D, 0, 0)); M.id := restore; Broadcast(M)
  END SetDisplay;

  (* begin-procedure-description
---
**GetDisplay** determines the current display.
  end-procedure-description *)
  PROCEDURE GetDisplay* (id: INTEGER): DisplayArea;
    VAR D: DisplayArea;
  BEGIN D := root;
    WHILE (D # NIL) & (id # D.id) DO D := D.next(DisplayArea) END;
    RETURN D
  END GetDisplay;

  (* begin-procedure-description
---
**CloseDisplay** closes a display if it is not the last display.
  end-procedure-description *)
  PROCEDURE CloseDisplay* (D: DisplayArea; hint: INTEGER); (*except last display*)
  BEGIN
    IF root.next # NIL THEN D.state := 0;
      IF D = root (*first*) THEN D.next(Viewer).prev := D.prev; root := D.next(DisplayArea)
      ELSIF D = root.prev (*last*) THEN root.prev := D.prev; D.prev.next := NIL
      ELSE D.next(Viewer).prev := D.prev; D.prev.next := D.next
      END;
      IF D = CurDisplay THEN D := GetDisplay(hint);
        IF D = NIL THEN SetDisplay(root) ELSE SetDisplay(D) END
      END
    END
  END CloseDisplay;

  (* begin-procedure-description
---
**The initialzation code for this module** merely sets the `root`, `CurDisplay` and `FocusViewer` module variables to `NIL` and the `nextID` module variable to `0`.

  end-procedure-description *)
BEGIN root := NIL; CurDisplay := NIL; FocusViewer := NIL; nextId := 0
END Viewers.
