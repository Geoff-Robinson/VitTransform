! Harness for issue #25: FindNotInLiteralOrComment resumes its re-scan
! one byte past a rejected match without classifying that byte, so a
! quote at the rejected position inverts the literal/comment state for
! the rest of the line.
! https://github.com/msarson/VitTransform/issues/25
!
! vitTokenize.clw ~:5551: after a match is rejected as in-quotes, the
! code does pStartCol += 1; x = pStartCol - the byte AT the rejected
! position is never classified. When that byte is a quote (an escaped
! quote pair inside a literal), inQuotes flips out of step and a later
! needle inside a COMMENT can be reported as found.
!
! NOTE: no shipped code calls this method today (vtxaDiff port kept in
! the public class API) - the defect is latent for library consumers.
!
! Case A (bug): find an escaped-quote pair in a line where both
!   occurrences sit in a literal or a comment - expected 0.
! Case B (control): find the real comment bang - expected 11.
!
! Exit 1 while the bug is present; writes result.txt.

  program

  include('StringTheory.inc'),ONCE
  include('vitTokenize.inc'),ONCE

  map
  end

tk    VitTokenize
sA    StringTheory
sB    StringTheory
rep   StringTheory
rA    long
rB    long

  code
  sA.setValue('a = <39>x<39,39>y<39> ! z <39> woo <39,39>')
  sB.setValue('y = <39>a!b<39> ! real')
  rA = tk.FindNotInLiteralOrComment(sA, '<39,39>', 0, 0)
  rB = tk.FindNotInLiteralOrComment(sB, '!', 0, 0)

  rep.setValue('issue #25 harness: FindNotInLiteralOrComment state tracking<13,10>')
  rep.append('case A  needle QQ in [' & sA.getValue() & ']: returned ' & rA & '  (expected 0 - the only match past the literal sits in the comment)<13,10>')
  rep.append('case B  needle !  in [' & sB.getValue() & ']: returned ' & rB & '  (expected 11 - control)<13,10>')
  if rA = 0 and rB = 11
    rep.append('RESULT: PASS<13,10>')
    rep.SaveFile('result.txt')
  else
    rep.append('RESULT: FAIL - the rejected-match byte is skipped unclassified; issue #25 is present<13,10>')
    rep.SaveFile('result.txt')
    halt(1)
  end
