! Test for issue #21: ApplyOne's width check omits the match line's own
! indent, so deeply indented multi-line spans flatten past allowW with
! overWide = 0.
! https://github.com/msarson/VitTransform/issues/21
!
! The prefix loop (VitRewrite.clw ~:270, "loop while wt < sPos") never
! runs when the match starts the line, so wResult misses the indent
! that the spanW side counts and that ApplyOne re-applies on output.
!
! EXPECTED: the rewrite is width-skipped (1 width-skip in the report) -
!           the flattened line would be ~95 columns against an
!           allowance of ~67 (widest original line + 12).
! ACTUAL:   the rewrite is applied, the output line is ~95 columns,
!           and the report says 0 width-skip(s).
!
! Run:  run.bat

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

r    long
bbb  long
ccc  long

  code
                                        r = alpha(bbb, |
                                                  ccc)
  return
