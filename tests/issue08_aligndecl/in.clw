! Test for issue #8: AlignDeclTypes' width guard measures fictional widths.
! https://github.com/msarson/VitTransform/issues/8
!
! dq:lineW (vitTokenize.clw ~:4015) is label + gap + FIRST TYPE TOKEN
! only - the ",auto,dim(4000)" tail is invisible to the guard - and the
! projection subtracts a constant 1 instead of dq:gap. So with
! --width=40 the guard approves an alignment whose real result is
! wider than 40.
!
! EXPECTED: the run is refused (aligning would push line "a" past 40).
! ACTUAL:   the types are aligned and the "a" line ends up 44 columns
!           wide with no over-width report.
!
! Run:  run.bat   (--width=40 --only=1201 so nothing else edits the file)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

a  long,auto,dim(4000)
reallyquitelonglabelname  byte

  code
  a[1] = 1
  reallyquitelonglabelname = 2
  return
