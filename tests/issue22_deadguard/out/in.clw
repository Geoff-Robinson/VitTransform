! Test for issue #22: DeadGuard's compound-assignment write detection
! omits %= and ^=, so it deletes a guard a modulo-assign can re-arm.
! https://github.com/msarson/VitTransform/issues/22
!
! The member-write scan (VitEngine.clw ~:5498) recognises += -= *= /= &=
! as stores but lets %= and ^= fall through as reads (the tokenizer
! merges all seven compound heads; the sibling scan at ~:5108 covers
! all seven).
!
! Demo1: st._DataEnd %= 4 CAN zero _DataEnd between the dominating
!        guard and the choose(), so the choose() guard is live - but
!        DeadGuard misses the write and deletes it, leaving a slice
!        that faults on an unbound valuePtr when _DataEnd hits 0.
! Demo2: identical shape with -= 4 - the write IS seen, guard kept.
!
! EXPECTED: both guards kept.
! ACTUAL:   Demo1's choose() collapses to the bare slice; Demo2's stays.
!
! Run:  run.bat  (--group=deadchoose)

  program

  include('StringTheory.inc'),ONCE

  map
Demo1 procedure()
Demo2 procedure()
  end

  code
  Demo1()
  Demo2()

Demo1 procedure()

st   StringTheory
x    string(20),auto

  code
  st.setValue('abcdefgh')
  if st._DataEnd < 1 then return.
  st._DataEnd %= 4
  x = st.valuePtr[1 : st._DataEnd]
  return

Demo2 procedure()

st   StringTheory
x    string(20),auto

  code
  st.setValue('abcdefgh')
  if st._DataEnd < 1 then return.
  st._DataEnd -= 4
  x = choose(st._DataEnd < 1, '', st.valuePtr[1 : st._DataEnd])
  return
