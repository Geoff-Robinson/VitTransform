! Test for issue #27: "INCLUDE not found" reports the section-relative
! line number - pLineOfs is omitted from the message (its neighbours at
! Preprocessor.clw ~:405 and ~:446 both include it).
! https://github.com/msarson/VitTransform/issues/27
!
! lib.inc's SECTION starts deep in the file; the missing include sits
! two lines into the section.
!
! EXPECTED: the error names the ABSOLUTE line in lib.inc (line 15).
! ACTUAL:   it names the section-relative line (line 2).
!
! Run:  run.bat  (needs --thorough for include expansion)

  program

  include('lib.inc','SecB'),ONCE

  map
  end

  code
