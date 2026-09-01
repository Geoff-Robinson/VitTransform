! Test for issue #24: RemoveAutoAttr cannot remove an AUTO that sits on
! a continuation line, so the unsafe declaration re-fails every pass.
! https://github.com/msarson/VitTransform/issues/24
!
! RemoveAutoAttr (VitEngine.clw ~:12630) scans only tokens whose lineNo
! equals the declaration line's - an ,AUTO after a '|' continuation is
! on the next physical line, so the scan breaks before reaching it and
! returns 0. The unsafe-AUTO DECISION fires anyway.
!
! Both x and x2 are read before they are written, so both AUTOs are
! unsafe and must go.
!
! EXPECTED: both declarations lose AUTO and gain the note.
! ACTUAL:   x2 (inline) is fixed; x (continuation) keeps its AUTO with
!           no note - and the same failed work item repeats each pass.
!
! Run:  run.bat  (--only=1187 = BUILTIN AutoCheck)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

x    long ! AUTO unsafe: read before write
w    long ! AUTO unsafe: read before write  ! keepme
x2   long ! AUTO unsafe: read before write
y    long,auto

  code
  y = x
  y = w
  y = x2
  return
