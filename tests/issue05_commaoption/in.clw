! Test for issue #5: "pat ==> DELETE, ONCE" splices literal text.
! https://github.com/msarson/VitTransform/issues/5
!
! EXPECTED: the "r = 1" statement is DELETED (comma option form is
!           documented as legal at VitRules.clw:~388).
! ACTUAL:   the statement is REPLACED by the literal tokens "DELETE ,"
!           - which is not Clarion and does not compile.
!
! Run:  run.bat

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

r    byte

  code
  r = 1
  return
