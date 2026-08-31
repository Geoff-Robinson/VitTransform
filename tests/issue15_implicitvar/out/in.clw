! Test for issue #15: CandOK's gd1IdMv gate rejects implicit variables,
! so a rule whose LEADING pattern part is an ANYVAR metavar never
! matches total# = total# + 1.
! https://github.com/msarson/VitTransform/issues/15
!
! MatchHere has an implicit-variable arm (VitMatch.clw ~:1625), so an
! implicit variable mid-pattern matches fine - but the candidate gate
! at ~:1417 filters the statement out before MatchHere ever runs when
! the metavar is the first pattern part. Position-dependent silent miss.
!
! The shipped compound-assign rule (v = v + c ==> v += c, ANYVAR v) is
! the demonstration: the declared control converts, the implicit
! variable line does not.
!
! EXPECTED: both lines become "+= 1".
! ACTUAL:   only the declared "total" converts; "total#" is untouched.
!
! Run:  run.bat  (--group=general-compound-assign)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

total  long

  code
  total += 1
  total# += 1
  return
