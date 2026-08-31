! Test for issue #17: the hoist pass pairs an inner IF with the outer
! block's ELSE/END - a statement is hoisted out of the wrong branch.
! https://github.com/msarson/VitTransform/issues/17
!
! rules.txt eats the inner block's inline END, so MatchLevel pairs the
! INNER "if b" with the OUTER end and HoistFindElse hands it the OUTER
! else. Under that wrong pairing both "branches" begin with identical
! "x = 5" lines, so TryStartHoist deletes the else-branch copy and
! hoists the true copy above the INNER if - inside the outer TRUE
! branch.
!
! EXPECTED: no hoist (under the real pairing the outer true branch
!           starts with a block line and the tails differ; the inner
!           if has no else).
! ACTUAL:   x = 5 is deleted from the ELSE path and lands inside the
!           outer TRUE branch - it no longer executes when a is false.
!
! Run:  run.bat

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

a    long
b    long
x    long
r    long

  code
  if a
    x = 5
    if b
    r = 1
  else
    r = 2
  end
  return
