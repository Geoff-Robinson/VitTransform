! Test for issue #29: CandOK's gd1Lit gate bypasses the two-word
! NOT-operator equivalence.
! https://github.com/msarson/VitTransform/issues/29
!
! The candidate gate (VitMatch.clw ~:1410) compares the pattern's
! leading literal with LitMatches only; the postings machinery carries
! AnchorNotPair for the NOT = spelling, but a candidate rejected here
! never reaches it.
!
! EXPECTED: both comparisons rewritten to 98.
! ACTUAL:   only the <> spelling converts; NOT = keeps 99.
!
! Run:  run.bat

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

x    long
y    long
r    long

  code
  if x <> 99 then r = 1.
  if y NOT = 99 then r = 2.
  return
