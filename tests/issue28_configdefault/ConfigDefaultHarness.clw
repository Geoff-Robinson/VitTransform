! Harness for issue #28: a blank configuration defaults %CONFIGURATION%
! to Debug while everything else in the ecosystem documents Release.
! https://github.com/msarson/VitTransform/issues/28
!
! Preprocessor.clw:68 defaults blank pConfig to Debug. vitTransform.clw
! masks it for the CLI by always passing Release (the report header
! prints config=Release for a blank switch), but any other consumer of
! the class inherits Debug.
!
! Exit 1 while the mismatch is present; writes result.txt.

  program

  include('StringTheory.inc'),ONCE
  include('Preprocessor.inc'),ONCE

  map
  end

pp    preprocessor
rep   StringTheory

  code
  pp.Init('dummy.clw', '', '', '')
  rep.setValue('issue #28 harness: preprocessor.Init with blank config<13,10>')
  rep.append('pp.Config = "' & clip(pp.Config) & '"  (documented default everywhere else: "Release")<13,10>')
  if clip(pp.Config) = 'Release'
    rep.append('RESULT: PASS<13,10>')
    rep.SaveFile('result.txt')
  else
    rep.append('RESULT: FAIL - blank config defaults to "' & clip(pp.Config) & '"; issue #28 is present<13,10>')
    rep.SaveFile('result.txt')
    halt(1)
  end
