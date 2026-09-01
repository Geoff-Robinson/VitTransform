! Test for issue #19: val(chr(EXPR)) collapse drops parentheses.
! https://github.com/msarson/VitTransform/issues/19
!
! CheckCaseStatements pass 2a rewrites val(chr(x)) to x with no
! single-token arity guard (pass 2b directly below has one). A
! multi-token EXPR loses its parentheses and the arithmetic changes.
!
! EXPECTED: y = val(chr(i + 1)) * 2 left alone (or wrapped: (i + 1) * 2)
! ACTUAL:   y = i + 1 * 2   - evaluates i + 2 instead of (i + 1) * 2
!
! Run:  run.bat  (--only=1185 = BUILTIN CheckCaseStatements)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

i    long
y    long

  code
  i = 3
  y = val(chr(i + 1)) * 2
  return
