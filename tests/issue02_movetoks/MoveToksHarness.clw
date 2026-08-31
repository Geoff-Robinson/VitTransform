! Harness for issue #2: MoveToks corrupts the token stream on any
! backward multi-token move.
! https://github.com/msarson/VitTransform/issues/2
!
! MoveToks (vitTokenize.clw:1773) loops MoveTok(pSrc,pDst) a fixed pSrc:
! after each backward MoveTok the next source token sits at pSrc+1, but
! the loop re-reads pSrc - which now holds a shifted survivor. MoveTok
! itself is correct; only the multi-token loop is wrong, and only for
! backward moves (pDst below pSrc). The engine's own END-hoist works
! around it with a hand-rolled StartMove (VitEngine.clw:3497), whose
! comment says exactly this - but the public method remains broken for
! any other caller.
!
! This program parses [A B C D E F], asks MoveToks(4,2,2) to move the
! block [D E] to position 2, and compares the result.
!
! EXPECTED: A D E B C F   (block moved intact, order preserved)
! ACTUAL:   A D C B E F   (C moved - never in the block; E never moved)
!
! Returns exit code 1 while the bug is present, 0 once fixed.
! Writes result.txt beside the exe either way.
!
! Build: open MoveToksHarness.sln (needs the repo root on the include
! path - the local CLARION120.RED here adds ..\.. for that; a local
! red is only picked up when it is NAMED like the version default in
! C:\Clarion\<<ver>>\bin, hence the name). StringTheory required, as
! for the main apps.

  program

  include('StringTheory.inc'),ONCE
  include('vitTokenize.inc'),ONCE

  map
  end

tk        VitTokenize
tk2       VitTokenize
src       StringTheory
src2      StringTheory
act2      StringTheory
actual    StringTheory
before    StringTheory
rep       StringTheory
expected  string(32)
tokTxt    string(32)
i         long
rc        long
rc2       long

  code
  src.setValue('A B C D E F')
  tk.ParseText(src)
  src2.setValue('A B C D')

  loop i = 1 to tk.records()
    tokTxt = tk.GetTok(i)
    if ~tokTxt then cycle.                     ! null token record
    if val(tokTxt) = 10 then cycle.            ! EOL token
    if before._DataEnd then before.append(' ').
    before.append(clip(tokTxt))
  end

  rc = tk.MoveToks(4, 2, 2)                    ! move the block [D E] to position 2

  tk2.ParseText(src2)
  rc2 = tk2.MoveToks(2, 0, 2)                  ! append case: pDst = 0 means END per MoveTok (review)

  loop i = 1 to tk.records()
    tokTxt = tk.GetTok(i)
    if ~tokTxt then cycle.
    if val(tokTxt) = 10 then cycle.
    if actual._DataEnd then actual.append(' ').
    actual.append(clip(tokTxt))
  end

  expected = 'A D E B C F'

  loop i = 1 to tk2.records()
    tokTxt = tk2.GetTok(i)
    if ~tokTxt then cycle.
    if val(tokTxt) = 10 then cycle.
    if act2._DataEnd then act2.append(' ').
    act2.append(clip(tokTxt))
  end

  rep.setValue('issue #2 harness: MoveToks(4,2,2) - move block [D E] to position 2<13,10>')
  rep.append('before:   ' & before.getValue() & '<13,10>')
  rep.append('expected: ' & clip(expected)    & '<13,10>')
  rep.append('actual:   ' & actual.getValue() & '<13,10>')
  rep.append('rc:       ' & rc & '  (st:ok = ' & st:ok & ' - note it reports success either way)<13,10>')
  rep.append('append:   MoveToks(2,0,2) on [A B C D] gave [' & act2.getValue() & ']  expected [A D B C]<13,10>')
  if actual.getValue() = clip(expected) and act2.getValue() = 'A D B C'
    rep.append('RESULT: PASS - backward multi-token move preserved the block<13,10>')
    rep.SaveFile('result.txt')
  else
    rep.append('RESULT: FAIL - a token outside the requested block was moved; issue #2 is present<13,10>')
    rep.SaveFile('result.txt')
    halt(1)
  end
