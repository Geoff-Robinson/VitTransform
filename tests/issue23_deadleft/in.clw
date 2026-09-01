! Test for issue #23: DlShapeAt never checks the token after the
! literal 1, so left(st.sub(1 + p, k)) qualifies as "starts at 1" and
! a meaningful left() is deleted.
! https://github.com/msarson/VitTransform/issues/23
!
! VitEngine.clw ~:5998: if GetTok(nx + 1) <> '1' then return 0 - and
! nothing tests GetTok(nx + 2), so "1 + p" passes as the literal 1.
! st.sub(1 + p, ...) can return content with leading spaces even on a
! trimmed receiver (interior spaces shift to the front of the slice),
! so the left() does real work.
!
! EXPECTED: the left() is kept (read does not start at character 1).
! ACTUAL:   x = left(st.sub(1 + p, 3)) becomes x = st.sub(1 + p, 3).
!
! Run:  run.bat  (--group=deadchoose)

  program

  include('StringTheory.inc'),ONCE

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

st   StringTheory
x    string(20)
p    long

  code
  st.setValue('a b')
  st.trim()
  p = 1
  x = left(st.sub(1 + p, 3))
  return
