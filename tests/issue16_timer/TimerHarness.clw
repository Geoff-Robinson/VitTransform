! Harness for issue #16: vitTimer Duration() rounds instead of
! truncating, so displays like "2 hours 50 minutes" appear for 1h50m.
! https://github.com/msarson/VitTransform/issues/16
!
! vitTimer.clw:~48: L:Hours = L:Duration / 360000 and
! L:Mins = L:Duration / 6000 rely on Clarion round-on-assignment,
! while each remainder is taken independently with %. A .5+ fraction
! rounds the quotient UP but the remainder still holds the full rest.
!
! Case A: 1h50m  (660000 ticks) -> "2 hours 50 minutes " (units double-counted)
! Case B: 59m59s (359900 ticks) -> "1 hour 60 minutes 59 seconds" for a
!         duration under one hour.
!
! EXPECTED: "1 hour 50 minutes " and "59 minutes 59 seconds".
! Exit 1 while the bug is present; writes result.txt.

  program

  include('StringTheory.inc'),ONCE
  include('vitTimer.inc'),ONCE

  map
  end

tmr    VitTimer
a      string(64)
b      string(64)
rep    StringTheory ! needs no ST calls beyond SaveFile/append
okA    long
okB    long

  code
  tmr.StartDate = 80000 ; tmr.EndDate = 80000
  tmr.StartTime = 100   ; tmr.EndTime = 100 + 660000     ! 1h 50m
  a = tmr.Duration()
  tmr.StartTime = 100   ; tmr.EndTime = 100 + 359900     ! 59m 59s
  b = tmr.Duration()

  okA = choose(a = '1 hour 50 minutes')
  okB = choose(b = '59 minutes 59 seconds')

  rep.setValue('issue #16 harness: vitTimer.Duration rounding<13,10>')
  rep.append('1h50m  (660000 ticks): "' & clip(a) & '"  expected "1 hour 50 minutes"<13,10>')
  rep.append('59m59s (359900 ticks): "' & clip(b) & '"  expected "59 minutes 59 seconds"<13,10>')
  if okA and okB
    rep.append('RESULT: PASS<13,10>')
    rep.SaveFile('result.txt')
  else
    rep.append('RESULT: FAIL - quotients round up while remainders keep the rest; issue #16 is present<13,10>')
    rep.SaveFile('result.txt')
    halt(1)
  end
