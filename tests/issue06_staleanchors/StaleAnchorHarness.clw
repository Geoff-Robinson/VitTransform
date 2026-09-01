! Harness for issue #6: FindFirstPost's "no postings" rescue is dead
! code, so a rule appended after the anchor set is built silently
! matches nothing.
! https://github.com/msarson/VitTransform/issues/6
!
! VitMatch.Init only calls BuildAnchorLits when anchorLits is EMPTY
! ("rules are fixed across files: build once"), and nothing else ever
! rebuilds it. VitRules.LoadUserText APPENDS a rule to a loaded set -
! the VitStyle rule-workbench flow - so the appended rule's anchor
! literal is missing from the postings. CountTok's defensive full scan
! still says the anchor IS present (aCount above 0), FindFirstPost
! misses - but POSITION returns the next-greater row or RECORDS+1 on a
! miss, NEVER 0, so the "and pr" rescue (VitMatch.clw ~:171) that is
! documented to fall through to the linear scan cannot fire: the
! postings walk breaks on the first keyText mismatch and the rule
! finds zero matches, silently.
!
! Sequence here: parse ruleset A (alpha rule), transform once (anchors
! now built), append rule B (beta rule) via LoadUserText, transform the
! SAME source again on the SAME engine, then once more on a FRESH
! engine sharing the same rules object.
!
! EXPECTED: run 2 and run 3 both rewrite beta = 2 to beta = 9.
! ACTUAL:   run 2 leaves beta untouched (stale anchors); run 3 works -
!           proving the rule is fine and the cached anchor set is not.
!
! Returns exit code 1 while the bug is present; writes result.txt.
! Build: open StaleAnchorHarness.sln (local CLARION120.RED adds ..\..).

  program

  include('StringTheory.inc'),ONCE
  include('vitTokenize.inc'),ONCE
  include('VitRules.inc'),ONCE
  include('VitSymbols.inc'),ONCE
  include('VitMatch.inc'),ONCE
  include('VitRewrite.inc'),ONCE
  include('vitTimer.inc'),ONCE
  include('VitEngine.inc'),ONCE

  map
  end

rl     VitRules
eng    VitEngine
eng2   VitEngine
rules  StringTheory
usrTxt StringTheory
src    StringTheory
out1   StringTheory
out2   StringTheory
out3   StringTheory
log    StringTheory
rep    StringTheory
c1     long
c2     long
c3     long
ok2    long
ok3    long

  code
  rules.setValue('alpha = 1  ==>  alpha = 9')
  if rl.ParseText(rules)
    rep.setValue('SETUP FAILED: ruleset A did not parse<13,10>')
    rep.SaveFile('result.txt')
    halt(2)
  end
  rl.Resolve('', '', '')

  src.setValue('  alpha = 1<13,10>  beta = 2<13,10>')

  eng.Init(rl)
  eng.progressFn = ''
  c1 = eng.TransformText(src, out1, log)             ! run 1: builds anchorLits

  usrTxt.setValue('beta = 2  ==>  beta = 9')
  if rl.LoadUserText(usrTxt)
    rep.setValue('SETUP FAILED: appended rule B did not parse<13,10>')
    rep.SaveFile('result.txt')
    halt(2)
  end
  rl.Resolve('', '', '')

  log.free()
  c2 = eng.TransformText(src, out2, log)             ! run 2: SAME engine, stale anchors

  eng2.Init(rl)
  eng2.progressFn = ''
  log.free()
  c3 = eng2.TransformText(src, out3, log)            ! run 3: FRESH engine, same rules

  ok2 = choose(out2.instring('beta = 9', 1, 1) > 0)
  ok3 = choose(out3.instring('beta = 9', 1, 1) > 0)

  rep.setValue('issue #6 harness: rule appended via LoadUserText after first transform<13,10>')
  rep.append('run 1 (ruleset A only)      changes: ' & c1 & '<13,10>')
  rep.append('run 2 (same engine + B)     changes: ' & c2 & '  beta rewritten: ' & choose(ok2, 'YES', 'NO') & '<13,10>')
  rep.append('run 3 (fresh engine + B)    changes: ' & c3 & '  beta rewritten: ' & choose(ok3, 'YES', 'NO') & '<13,10>')
  if ok2 and ok3
    rep.append('RESULT: PASS - appended rule fired on the reused engine<13,10>')
    rep.SaveFile('result.txt')
  elsif ~ok2 and ok3
    rep.append('RESULT: FAIL - appended rule silently matched nothing on the reused engine (stale anchorLits; the pr=0 rescue never fires); issue #6 is present<13,10>')
    rep.SaveFile('result.txt')
    halt(1)
  else
    rep.append('RESULT: INCONCLUSIVE - rule B did not fire even on a fresh engine; harness assumption broken<13,10>')
    rep.SaveFile('result.txt')
    halt(2)
  end
