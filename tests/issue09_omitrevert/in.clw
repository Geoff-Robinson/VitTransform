! Test for issue #9: stale inContinuation after an OMIT-state-machine
! revert makes live code vanish from the token stream.
! https://github.com/msarson/VitTransform/issues/9
!
! Fetching the unquoted token "flag" (glued to the "|") inside OMIT
! state 2 sets inContinuation (vitTokenize.clw ~:1044); state 2 then
! reverts (pos = svPos; state = 0) because the operand is not a quoted
! literal - but never clears the flag. On the re-scan the rest of the
! line is swallowed as continuation trivia: "(" and "flag" never become
! tokens. The OmitX control line below is byte-identical in shape and
! keeps its tokens.
!
! Rejoin is byte-lossless, so the OUTPUT looks fine - the loss is only
! visible in the token stream (--dumptokens): every downstream analysis
! sees a hole in the statement.
!
! EXPECTED: the Omit line tokenizes like the OmitX line: rc = Omit (
!           flag | ...
! ACTUAL:   after "Omit" the "(" and "flag" tokens are missing.
!
! Run:  run.bat   (uses --dumptokens and shows the relevant dump lines)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

rc    long
flag  long

  code
  rc = Omit(flag| 1, 2)
  rc = OmitX(flag| 1, 2)
  return
