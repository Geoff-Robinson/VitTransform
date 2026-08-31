! Test for issue #18: BuiltinKnownRanges folds a decidable choose() in a
! LOOP WHILE header using facts that only hold BEFORE iteration 1.
! https://github.com/msarson/VitTransform/issues/18
!
! The walk's own spec defends against exactly this ("a non-IF block
! opener clears every fact: LOOP..., so a fact made above the opener is
! not valid at the top of the body on the second iteration") - but S2
! edits are staged BEFORE KrLevelWalk processes the line's own level
! marks (VitEngine.clw ~:6575), so on the LOOP header line itself the
! choose() is decided from the pre-loop fact.
!
! x = len(nm) seeds rk:nonNeg; "x >= 0" is in the decidable set (TRUE
! for nonNeg); the body then drives x negative, so the header is NOT
! loop-invariant.
!
! EXPECTED: the header choose() is left alone.
! ACTUAL:   "loop while choose(x >= 0, 1, 0)" becomes "loop while 1" -
!           an infinite loop.
!
! Run:  run.bat  (--group=analysis)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

x    long,auto
y    long,auto
nm   string(20),auto

  code
  nm = 'abc'
  x = len(nm)
  y = 1
  loop while choose(x >= 0, 1, 0)
    x -= 1
  end
  return
