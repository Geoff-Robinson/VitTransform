! Test for issue #10: CodeTokOfScope mistakes a column-1 "code" label
! for the CODE statement, so AutoCheck strips valid AUTO attributes.
! https://github.com/msarson/VitTransform/issues/10
!
! CodeTokOfScope (VitEngine.clw ~:12410) accepts ANY first-on-line
! token spelled CODE - it lacks the label-position exclusion
! (strBefore &= NULL) that BuiltinUnusedVars applies for exactly this
! case. A local variable named "code" (legal: labels are column 1)
! makes the walk treat the rest of the DATA SECTION as executable
! code, so the later local x reads as "read before write" and its
! valid ,auto is removed with a false note.
!
! EXPECTED: x keeps ,auto (it is written before it is read).
! ACTUAL:   x loses ,auto and gains the "AUTO unsafe" note.
!
! Run:  run.bat   (--only runs BUILTIN AutoCheck alone)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

code  long
x     long ! AUTO unsafe: read before write

  code
  code = 1
  x    = 2
  code = code + x
  return
