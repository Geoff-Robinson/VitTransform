! Test for issue #3: BuiltinCheckCase rewrites CASE arms it never validated.
! https://github.com/msarson/VitTransform/issues/3
!
! The validation loop's "operand must end here" guard (VitEngine.clw
! ~:1022) ends in cycle - skipping just that arm - instead of refusing
! the whole CASE, but the wrap loop below (~:1095) then wraps EVERY
! of/orof/to operand's first token in val() unconditionally. One valid
! single-char arm ('a') is enough to set allSingle, and the selector
! (ch, declared string(1)) passes SelGuard, so the CASE converts.
!
! EXPECTED: the CASE is left alone (one arm's operand is an expression,
!           so the single-token val() wrap cannot represent it).
! ACTUAL:   case ch -> case val(ch); of 'a' -> of 97; and the
!           NEVER-VALIDATED arm of 'b' & pad -> of 98 & pad.
!           That still compiles but compares differently: 'b' = 'bx'
!           was false, while val(ch) 98 against '98' & 'x' ('98x')
!           converts numerically and matches - the r = 2 branch now
!           runs when it never did before.
!
! Run:  run.bat  (--only=1185 = the BUILTIN CheckCaseStatements line in
!        vitrules.txt, so nothing else changes the file)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

ch   string(1)
pad  string(3)
r    byte

  code
  ch  = 'b'
  pad = 'x'
  case val(ch)
  of 97 ! 'a'
    r = 1
  of 98 & pad ! 'b'
    r = 2
  end
  return
