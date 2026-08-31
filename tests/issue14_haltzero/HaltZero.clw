! Harness for issue #14: halt() with no argument exits 0.
! https://github.com/msarson/VitTransform/issues/14
!
! VitStyle's two fatal startup paths (VitStyle.clw:343 - default rule
! file missing; :555 - rule file has errors) both end in a bare halt().
! This program IS that call: run it and check %ERRORLEVEL%.
!
! vitTransform.clw:17-18 documents the trap explicitly ("every failure
! path names the 1 explicitly - Say-then-return read as SUCCESS to
! every .bat") - VitStyle predates that discipline.
!
! EXPECTED (for a fatal path): exit code 1.
! ACTUAL: exit code 0 - scripts cannot detect that VitStyle refused
!         to start.

  program

  map
  end

  code
  halt()
