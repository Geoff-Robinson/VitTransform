! Test for issue #1: WalkUnreachable comments out live code.
! https://github.com/msarson/VitTransform/issues/1
!
! What happens: rules.txt (in this folder) rewrites the DEAD one-liner
! "if a then y = 1 end" into "y = 2" - its pattern consumes the END
! terminator. The engine decides whether a rule rewrite needs a level
! reparse by scanning only the REPLACEMENT tokens for level keywords
! (VitEngine.RepHasLevelKeyword :715) - it never considers the closes the
! PATTERN consumed - so the inner IF's '+' is left unrepaid and no reparse
! restores balance. BUILTIN UnreachableCode (WalkUnreachable,
! VitEngine.clw:~2736) then walks the stream: depth stays inflated past
! the dead line, the "depth = deadDepth" rejoin never fires at the live
! ELSE, and everything from ELSE down is commented out.
!
! WalkUnreachable is also the only dead-state walk WITHOUT the unmarked
! vt:end belt its five siblings wear (e.g. SmDepthWalk :4531) - any
! unmarked close reaching it corrupts output the same way.
!
! EXPECTED: only the dead one-liner gains the #Unreachable marker.
! ACTUAL:   the live ELSE arm, its body, the END, x = 3 and the final
!           return are commented out too - the output does not compile
!           and live code is destroyed.
!
! Run:  run.bat  (or: VitTransform tests\issue01_walkunreachable\rules.txt
!        tests\issue01_walkunreachable\in.clw tests\issue01_walkunreachable\out --batch)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

a    byte(0)
x    long(0)
y    long

  code
  if x = 0
    return
    if a then y = 1 end
  else
    x = 2
  end
  x = 3
  return
