! Test for issue #20: cosmetic.txt's header contradicts its DEFAULTSTYLE.
! https://github.com/msarson/VitTransform/issues/20
!
! Header (cosmetic.txt:36): "NOTHING BELOW IS ON BY DEFAULT except
! comment alignment. A plain VitTransform cosmetic.txt src out aligns
! trailing comments and does nothing else."
! But :231 defines STYLE tidy = aligncomments + keywordcase-upper +
! reindent-2 + splitstatements, and :233 makes tidy the DEFAULTSTYLE.
!
! EXPECTED (per the header): this file comes back unchanged apart from
!           comment alignment.
! ACTUAL:   keywords are upper-cased and the body reindented - a
!           whole-file re-layout the header says cannot happen.
!
! Run:  run.bat   (deliberately NO switches)

  program

  map
Demo procedure()
  end

  code
  Demo()

Demo procedure()

r    byte

  code
  if r
      r = 0
  end
  return
