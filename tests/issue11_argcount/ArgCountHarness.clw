! Harness for issue #11: CallArgCount/CallArgTypes count commas inside
! [ ] subscripts as argument separators.
! https://github.com/msarson/VitTransform/issues/11
!
! Both scanners (VitMatch.clw ~:810 and ~:855) track only ( ) depth.
! A comma inside a bracket subscript is depth-0 to them, so
! st.Append(names[i,j]) counts as TWO arguments. ArityAdmits
! (VitSymbols.clw) then excludes the real 1-argument overload and the
! typed-metavar gate at VitMatch.clw:1586 silently skips the match (or
! picks a wrong-arity overload when one exists). Every sibling scanner
! in the file counts [ ] too (e.g. DepthDelta ~:1589) - these two are
! the outliers.
!
! EXPECTED: Append(names[i,j]) has 1 argument.
! ACTUAL:   CallArgCount returns 2.
!
! Exit 1 while the bug is present; writes result.txt.
! Build: open ArgCountHarness.sln (local CLARION120.RED adds ..\..).

  program

  include('StringTheory.inc'),ONCE
  include('vitTokenize.inc'),ONCE
  include('VitRules.inc'),ONCE
  include('VitSymbols.inc'),ONCE
  include('VitMatch.inc'),ONCE

  map
  end

rl     VitRules
tk     VitTokenize
m      VitMatch
rules  StringTheory
src    StringTheory
rep    StringTheory
i      long
open1  long
open2  long
c1     long
c2     long
tokTxt string(32)

  code
  rules.setValue('alpha = 1  ==>  alpha = 9')
  if rl.ParseText(rules)
    rep.setValue('SETUP FAILED: dummy ruleset did not parse<13,10>')
    rep.SaveFile('result.txt')
    halt(2)
  end
  src.setValue('  st.Append(names[i,j])<13,10>  st.Append(names)<13,10>')
  tk.ParseText(src)
  m.Init(rl, tk)

  loop i = 1 to tk.records()                 ! first and second '(' tokens
    tokTxt = tk.GetTok(i)
    if tokTxt = '('
      if ~open1
        open1 = i
      else
        open2 = i
        break
      end
    end
  end

  c1 = m.CallArgCount(open1)                 ! st.Append(names[i,j]) - one argument
  c2 = m.CallArgCount(open2)                 ! st.Append(names)      - control

  rep.setValue('issue #11 harness: CallArgCount vs bracket subscripts<13,10>')
  rep.append('st.Append(names[i,j])  args counted: ' & c1 & '  (expected 1)<13,10>')
  rep.append('st.Append(names)       args counted: ' & c2 & '  (expected 1)<13,10>')
  if c1 = 1 and c2 = 1
    rep.append('RESULT: PASS<13,10>')
    rep.SaveFile('result.txt')
  else
    rep.append('RESULT: FAIL - a comma inside [ ] was counted as an argument separator; issue #11 is present<13,10>')
    rep.SaveFile('result.txt')
    halt(1)
  end
