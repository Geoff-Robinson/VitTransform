! vitTransform - driver for VitTransform (Phases 1-5)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! usage:
!   VitTransform <rulefile>                       lint + IR dump -> <rulefile> on <stamp>.ir.txt
!   VitTransform <goldenfile>                     golden tests (file starts '=== case') -> <file> on <stamp>.result.txt
!   VitTransform <rulefile> <sourcespec> [outdir] [switches]
!                                                 transform mode; wildcards ok in sourcespec;
!                                                 no outdir = overwrite originals - REQUIRES --in-place
!                                                 (a timestamped .bak of each changed file is kept first);
!                                                 report -> <rulefile> on yyyymmdd at hhmmssth.report.txt
!
! exit code (ERRORLEVEL): 0 = clean run. 1 = anything a calling script must see - a refused
!   switch or rule file, rule-file lint errors, a save that failed, golden-test failures.
!   HALT() with NO argument exits 0 (LRM: "If omitted, the default is zero"), so every
!   failure path names the 1 explicitly - Say-then-return read as SUCCESS to every .bat.
!
! switches: --dry-run  --verbose  --loose  --in-place  --only=<ruleId>  --skip=<ruleId>  --passes=<n>
!           --width=<n>          longest line to allow before it is split. Default: the file's own
!                                prevailing width + 12, capped at 200 - a file already wider than
!                                200 is respected as-is. --width=0 turns splitting off entirely.
!                                Minimum 40. Also caps the continuation-collapse check.
!           --summary            show the end-of-run message box. OFF by default so a .BAT of
!                                many runs goes straight through unattended; every number in
!                                that box is in the report file. A SAVE FAILURE still shows.
!           --batch              UNATTENDED: never open a modal box. Everything that would have
!                                been one is appended to vt-batch.log instead - not suppressed,
!                                because each is something you must see (a rule file refused to
!                                load, output that is not on disk). Required by the autonomous
!                                build watcher, which has nobody to click OK. Also makes
!                                --thorough take the newest Clarion instead of asking.
!           --acdiag             why did AlignComments leave that comment there? Reports the
!                                per-comment reason (FROZEN / OUT-OF-WINDOW / CAPPED).
!           --dumptokens         write the EXPANDED token stream to <<source>.tokens.txt with the
!                                level mark in column 1, and report THREE things: every
!                                level-opening token sitting INSIDE parentheses (where nothing
!                                can open a structure), every unmatched OPEN, and every CLOSE
!                                that closes nothing. Needs --thorough. For chasing an
!                                unbalanced expanded-token level census.
!   S1 selection (rule files with GROUP/CHOICE/STYLE lines; no switches = file defaults):
!     --style=<name>       apply a shipped STYLE or loaded profile by name
!     --stylefile=<file>   load a user stylefile/profile file (STYLE + LASTUSED lines)
!     --group=<name>       select a group after the style. REPEAT the switch for several
!                          (--group=a --group=b), or write one comma list - BOTH work.
!                          Comma lists are equally fine inside STYLE lines and profile
!                          files.
!     --nogroup=<name>     deselect a group (repeatable, same rule)
!   the rule workbench:
!     --userrules=<file>   load a USER rulefile (plain DSL, GROUP blocks) APPENDED
!                          after the shipped rule file, before the stylefile; user
!                          ruleIds are offset by 500000 (rule 500096 = U96 in the
!                          workbench); default OFF = batch is byte-identical without it
!   every report carries the RESOLVED selection table - a report without its
!   selection is an unrepeatable experiment
!   output naming (inserted before the extension, so out\reindent.clw -> out\reindent<suffix>.clw):
!     --outsuffix=<s>  literal suffix, e.g. --outsuffix=Width2  -> reindentWidth2.clw
!     --outstamp       append ' on yyyymmdd at hhmmssth' (th = hundredths), e.g.
!                      reindent on 20260713 at 14302547.clw  (both combine: literal then stamp)
!   cross-file type resolution (opt-in - needed for self.* dotted receivers):
!     --root=<dir>     Clarion install dir (%ROOT%, e.g. c:\Clarion11) - PRESENCE enables include expansion
!     --red=<file>     .red redirection file (default: Clarion110.red in the working dir,
!                      else the newest Clarion*.red in <root>\bin - its normal home)
!     --config=<name>  %CONFIGURATION% macro (default Release)
!     --thorough       expand includes WITHOUT typing --root: %ROOT% is auto-discovered from the
!                      Windows uninstall registry (one install = used silently; several = you pick
!                      from a dialog - pass --root explicitly for unattended runs; --root overrides)
!     --receiver=<mode>  what to do when a Check* builtin's receiver cannot be resolved:
!                      assume = rewrite it as a StringTheory, check = refuse it if any use of
!                      it in scope is not a StringTheory method (DEFAULT), strict = refuse it
!                      unless it provably resolves. See README D.3.
!     --nothorough     the explicit NO. Beats a THOROUGH directive in the rule file AND an
!                      explicit --root=: it is the escape hatch, so nothing outranks it.
!     THOROUGH         (rule-file directive, not a switch) a shipped rule file may ASK for
!                      include expansion, because a rule set full of typed StringTheory
!                      receivers cannot do its job without it. The command line still decides.
!
!
  PROGRAM

  INCLUDE('StringTheory.inc'),ONCE
  INCLUDE('VitTokenize.inc'),ONCE
  INCLUDE('VitRules.inc'),ONCE
  INCLUDE('VitSymbols.inc'),ONCE
  INCLUDE('VitMatch.inc'),ONCE
  INCLUDE('VitRewrite.inc'),ONCE
  INCLUDE('VitTimer.inc'),ONCE
  INCLUDE('VitEngine.inc'),ONCE

  MAP
    Say(STRING pMsg)                                        ! message() UNLESS --batch, in which case append to vt-batch.log.
                                                            !   A modal box is fatal to an unattended run: the autonomous watcher has
                                                            !   nobody to click it and waits forever. Everything routed through here
                                                            !   is something you MUST see - a refusal to load, a save that failed -
                                                            !   so in batch it goes to a file rather than being suppressed.
    NumArg(STRING pTxt, STRING pWhich, BYTE pZeroOk=0),LONG ! validate an all-digit numeric switch value (halt on bad).
                                                 !   pZeroOk=1 for switches where 0 is a real setting, not a mistake.
    MakeDirs(STRING pPath)                                  ! mkdir every intermediate level of pPath
    DiscoverRoot(*STRING pVerName),STRING                   ! Q1: newest installed Clarion root from the uninstall registry ('' = none found)
    FindRedInBin(STRING pRoot),STRING                       ! default .red discovery: newest Clarion*.red in <root>\bin ('' = none)
    MODULE('C Library')
      mkdir(*CSTRING),SIGNED,PROC,RAW,NAME('_mkdir')
    END
  END

rl         VitRules
gr         VitGolden
eng        VitEngine
totTmr     VitTimer
probe      StringTheory
line       StringTheory
outSt      StringTheory
fn         StringTheory
srcSpec    StringTheory
param      StringTheory
badSwitch  StringTheory   ! the unrecognised switch, if any - the run is refused, not warned about
okOnly     LONG           ! --only= names a rule that actually exists
okSkip     LONG           ! --skip= ditto
extraPos   StringTheory   ! a 4th positional, if any - now always half of an unquoted pathlit
badGrp     StringTheory   ! --group=/--nogroup= names the rule file does not declare
grpList    StringTheory   ! the list CheckGroupNames is walking
knownGrp   StringTheory   ! every group the rule file DOES declare, for the refusal message
grpWhich   STRING(12)     ! which switch the current list came from
redArg     StringTheory   ! --red= value
rootArg    StringTheory   ! --root= value (non-blank enables include expansion)
cfgArg     StringTheory   ! --config= value
sufArg     StringTheory   ! --outsuffix= literal suffix (inserted before the extension)
styleArg   StringTheory   ! --style= name
styleFn    StringTheory   ! --stylefile= path
grpArg     StringTheory   ! --group= comma list (repeats append)
nogrpArg   StringTheory   ! --nogroup= comma list (repeats append)
userFn     StringTheory   ! --userrules= path (user rulefile, append-loaded)
uGrps      LONG           ! groups the user rulefile added (report header)
uRules     LONG           ! rules the user rulefile added (hand + auto)
wantStamp  BYTE           ! --outstamp: append ' on yyyymmdd at hhmmssth'
wantSumm   BYTE           ! --summary shows the end-of-run message box. OFF by default so a bat of many runs goes straight through unattended - every number in that box is in the report file anyway
batchMode  BYTE           ! --batch - never open a modal box; the autonomous watcher has nobody to click it
wantDump   BYTE           ! --dumptokens writes the EXPANDED token stream to disk with
                          !   its level marks in column 1, and reports every '+' that never gets a '-'.
                          !   VitTokenize.DumpTokens existed already, but its call sites were both
                          !   commented out, so nothing could reach it. This is how you find an unbalanced
                          !   `exptk level census` instead of guessing at it from keyword counts.
dumpIx     LONG,AUTO      !   (the census tells you a level is lost; this tells you WHICH token lost it)
dumpMt     LONG,AUTO
dumpLn     LONG,AUTO
dumpTx     STRING(128)
dumpNm     StringTheory   ! the dump is named after the SOURCE, so diagnosing three files
                          !   in a row does not leave only the last one on disk
dumpSrc    StringTheory   ! the file the dump actually describes. With a WILDCARD sourcespec,
                          !   exptk holds the LAST matched file's stream - naming the dump
                          !   after the spec built `*.clw.tokens.txt`, an illegal Windows
                          !   name, and the save failed in silence while the report claimed
                          !   the dump was on disk
dumpBad    LONG
thorough   BYTE           ! Q1: --thorough = include expansion with registry-discovered %ROOT%
noThorough BYTE           ! --nothorough - the explicit no. Beats a rule file's THOROUGH
                          !   directive AND an explicit --root=, because it is the escape hatch
verNm      STRING(24)     ! Q1: which Clarion the registry scan found (for the report)
stampSt    StringTheory
csecs      LONG,AUTO      ! clock() = centiseconds since midnight
totSec     LONG,AUTO
sHH        LONG,AUTO
sMM        LONG,AUTO
sSS        LONG,AUTO
sTH        LONG,AUTO      ! hundredths of a second
outFn      StringTheory
FilesQ   QUEUE(File:queue),PRE(FQ)
         END
errs      LONG,AUTO
warns     LONG,AUTO
x         LONG
idx       LONG
posNo     LONG
isGolden  LONG
exitRc    BYTE            ! a failure the run SURVIVES (a save that failed, golden fails) - every
                          !   exit path checks it and halts 1. Hard refusals halt(1) on the spot.
dirProbe  StringTheory    ! same-directory guard: probe filename written into <outdir>...
probeSt   StringTheory    !   ...and looked for in the SOURCE directory (see the guard below)
outDirC   CSTRING(261),AUTO
pathish   BYTE            ! the unexpected 4th argument looks like half of an unquoted path, not half of a comma list
realFiles LONG            ! wildcard rows that were actual FILES - the exit contract counts these (#13)

  CODE
  ! ---- --batch is read FIRST, in a pass of its own, BEFORE anything can refuse ----
  ! It decides whether a refusal may open a modal box at all, and it is habitually written
  ! LAST. Reading it in argument order meant every refusal raised WHILE parsing opened a box
  ! on exactly the kind of run that exists because nobody is there to click it: a bad
  ! --only=/--passes=/--width= value (NumArg halts on the spot), an unknown switch, or a 4th
  ! positional - and those last two BREAK the loop, so a --batch after them was never read at
  ! all. MEASURED: `VitTransform rules.txt probe\With Space\sp.clw out --batch`.
  param.setValue(command())
  param.removeByte(34)    ! a quoted "--batch" is still --batch, and remove all <double quote>
  param.replaceByte(9,32) !   a tab still separates arguments replace all <tab> with <space>
  if param.FindChars(' --batch ') or |
     param.EndsWith(' --batch')   or | in case there is no space at the end
     param.StartsWith('--batch ')             ! command() should add space at front so this is "just in case"
    batchMode = true
  end
  param.setValue(command())                   ! THE REAL LINE BACK. The pre-scan above
                                              !   flattens quotes and tabs to read ONE
                                              !   switch out of the line; the split below
                                              !   needs the quoting intact, because that
                                              !   is what holds a spaced path together.
  param.split(' ','"','"',,st:clip,st:left)
  param.RemoveLines()
  loop x = 1 to param.records()
    param.SetValueFromLine(x)
    param.removeByte(34)                      ! note: do it here NOT removeQuotes on the split as that only removes first/last chars whereas ours can be embedded remove all <double quote>
  ! ---- command line: positionals + --switches, in any order ----
    if param._DataEnd > 1 and param.valuePtr[1 : 2] = '--'
      if param._DataEnd = 2                   ! a bare '--' names no switch, and
        badSwitch.setValue(param)             !   [3 : 2] slices BACKWARDS - Clarion
        break                                 !   does not bounds-check a slice
      end
      ! A BARE FLAG IS AN EXACT MATCH, so let CASE do the comparing. The '--' is already
      ! known by the time we are here, so the arms carry the name alone and there is no
      ! length to keep in step with the text beside it.
      case param.valuePtr[3 : param._DataEnd] ! the '--' is known
      of 'dry-run'
        eng.dryRun = true
      of 'verbose'
        eng.verbose = true
      of 'loose'
        eng.loose = true
      of 'thorough'                           ! registry-discovered root
        thorough = true
      of 'nothorough'                         ! and the way to turn it off again
        noThorough = true
      of 'outstamp'
        wantStamp = true
      of 'summary'
        wantSumm = true
      of 'in-place'
        eng.inPlace = true
      of 'acdiag'
        eng.acDiag = true
      of 'dumptokens'
        wantDump = true
      of 'batch'                                                      ! also read in the pre-scan above
        batchMode = true
      else
        ! ---- --name=VALUE. A prefix, so CASE cannot match it and these stay as tests. ----
        if param._DataEnd > 7 and param.valuePtr[3 : 7] = 'only='
          eng.onlyId = NumArg(param.slice(8), '--only=')
        elsif param._DataEnd > 7 and param.valuePtr[3 : 7] = 'skip='
          eng.skipId = NumArg(param.slice(8), '--skip=')
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'passes='
          eng.maxPasses = NumArg(param.slice(10), '--passes=')
        elsif param._DataEnd > 8 and param.valuePtr[3 : 8] = 'width=' ! line width for splitting
          eng.widthArg = NumArg(param.slice(9), '--width=', 1)        ! 0 is legal here - see below
          if ~eng.widthArg
            eng.widthArg = -1                                         ! --width=0 = never split (0 already means "not given")
          elsif eng.widthArg < 40
            Say('VitTransform: --width= must be 0 (never split) or at least 40.'                   & |
                '||A smaller limit would break almost every line, which is worse than a wide one.' & |
                '||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'receiver=' ! what to do about
          case lower(param.slice(12))                                      !   a Check* receiver
          of 'assume' ; eng.recvMode = rm:assume                           !   the tool cannot
          of 'check'  ; eng.recvMode = rm:check                            !   resolve
          of 'strict' ; eng.recvMode = rm:strict
          else
            Say('VitTransform: --receiver= must be assume, check or strict.'                            & |
                '||  assume  rewrite an unresolvable receiver as a StringTheory'                        & |
                '|  check   refuse it if any use of it in scope is not a StringTheory method (default)' & |
                '|  strict  refuse it unless it provably resolves - use with --thorough'                & |
                '||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 6 and param.valuePtr[3 : 6] = 'red='         ! .red redirection file
          redArg.setValue(param.slice(7))
        elsif param._DataEnd > 7 and param.valuePtr[3 : 7] = 'root='        ! %ROOT%, and it ENABLES include expansion
          rootArg.setValue(param.slice(8))
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'config='      ! %CONFIGURATION% (Debug/Release)
          cfgArg.setValue(param.slice(10))
        elsif param._DataEnd > 12 and param.valuePtr[3 : 12] = 'outsuffix=' ! literal suffix before the extension
          sufArg.setValue(param.slice(13))
        elsif param._DataEnd > 12 and param.valuePtr[3 : 12] = 'stylefile=' ! user stylefile / profile file
          styleFn.setValue(param.slice(13))
        elsif param._DataEnd > 12 and param.valuePtr[3 : 12] = 'userrules=' ! user rulefile, appended to the shipped rules
          userFn.setValue(param.slice(13))
        elsif param._DataEnd > 8 and param.valuePtr[3 : 8] = 'style='       ! apply a STYLE/profile by name
          styleArg.setValue(param.slice(9))
        elsif param._DataEnd > 8 and param.valuePtr[3 : 8] = 'group='       ! select group(s); repeats append
          if grpArg._DataEnd then grpArg.append(',').
          grpArg.append(param.slice(9))
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'nogroup='   ! deselect group(s); repeats append
          if nogrpArg._DataEnd then nogrpArg.append(',').
          nogrpArg.append(param.slice(11))
        elsif param.EndsWith('=', st:NoClip)
          ! A SWITCH THAT TAKES A VALUE, WITH NO VALUE. Every test above needs at least one
          ! character past the '=', so an empty one falls through to here - and calling it an
          ! unknown switch would send the user hunting for a typo in a name that is spelt
          ! perfectly well. Say what is actually missing.
          Say('VitTransform: ' & clip(param.getValue()) & ' needs a value.'                     & |
              '||Write it as ' & clip(param.getValue()) & '<<value>, with no space around the ' & |
              '''=''.'                                                                          & |
              '||Nothing has been changed.')
          halt(1)
        else
          ! A SWITCH WE DO NOT UNDERSTAND MEANS WE DO NOT KNOW WHAT WAS WANTED. A typo like
          !   --dry-runn or --in-palce would otherwise make a DIFFERENT run from the one
          !   asked for - in place, over someone's source. Refuse, and name it.
          badSwitch.setValue(param)
          break
        end
      end
      cycle
    end
    posNo += 1
    case posNo
    of 1
      fn.setValue(param)
    of 2
      srcSpec.setValue(param)
    of 3
      eng.outDir = param.getValue()
    else
      ! A FOURTH POSITIONAL IS REFUSED, NOT IGNORED. What lands here is an unquoted path
      ! with a space in it, arriving as two arguments - so say so rather than treating the
      ! tail of somebody's path as an output directory.
      extraPos.setValue(param)
      break
    end
  end
  if badSwitch._DataEnd
    Say('VitTransform: unknown switch ' & clip(badSwitch.getValue())                           & |
        '||Nothing has been changed. The full switch list is in README.md (Appendix B) and in' & |
        ' the usage header of vitTransform.clw.')
    halt(1)
  end
  if extraPos._DataEnd
    ! An extra positional is half of an unquoted path, so the message says so and says what
    ! to do about it. A '\', '/' or '.' in the fragment is the tell. Quoting a positional
    ! works - measured: a quoted `probe\With Space\sp.clw` transforms and writes its
    ! output, and unquoted it lands here.
    pathish = 0
    if extraPos.containsA('\/.') then pathish = 1.
    Say('VitTransform: unexpected 4th argument ' & clip(extraPos.getValue())                                   & |
        '||Only <<rulefile> <<source> <<outdir> are positional.'                                               & |
        choose(~pathish, '', '||That looks like part of a PATH. Clarion splits the command line on SPACES, so' & |
                             ' an unquoted path with a space in it arrives as several arguments.'              & |
                             '|Quote it:   VitTransform vitrules.txt "C:\My Source\a.clw" out')                & |
        '||A comma-separated list such as --group=a,b is FINE and does not cause this.'                        & |
        '||Nothing has been changed.')
    halt(1)
  end
  if ~fn._DataEnd
    ! REFUSE rather than defaulting. Falling back to a rule file of our own choosing means the
    ! next thing the user sees is a load failure naming a file they have never heard of.
    ! A tool other people run must never quietly choose its own input.
    Say('VitTransform: no rule file given.'                                                                    & |
        '||Usage:  VitTransform <<rulefile> <<source> [<<outdir>] [switches]'                                  & |
        '||The rule file that ships with VitTransform is  vitrules.txt'                                        & |
        '||  VitTransform vitrules.txt src\*.clw out --dry-run    see what would change'                       & |
        '|  VitTransform vitrules.txt src\*.clw out              write into out\'                              & |
        '||Useful groups:  --group=analysis   --group=deadcode   --style=readable'                             & |
        '||Nothing has been changed.')
    halt(1)
  end

  if not probe.LoadFile(fn.getValue())
    Say('Could not load ' & clip(fn.getValue()) & '||' & probe.LastError)
    halt(1)
  end

  ! ---- date-time stamp: computed ONCE per run, BEFORE any output file is named, so the golden
  !      .result.txt, the IR .ir.txt and the transform .report.txt all share it and repeated runs
  !      never overwrite each other.  Also used by --outstamp (output filename) + the in-place .bak
  !      name.  th = hundredths.
  csecs  = clock()              ! centiseconds since midnight
  totSec = int(csecs / 100)
  sTH    = csecs - totSec * 100 ! hundredths (00..99)
  sHH    = int(totSec / 3600)
  totSec = totSec - sHH * 3600
  sMM    = int(totSec / 60)
  sSS    = totSec - sMM * 60
  stampSt.setValue(' on ' & format(year(today()), @n04) & format(month(today()), @n02) & format(day(today()), @n02) & |
                   ' at ' & format(sHH, @n02) & format(sMM, @n02) & format(sSS, @n02) & format(sTH, @n02))
  eng.stamp = stampSt.getValue()                           ! in-place backups use this

  ! golden files are detected by their first non-blank, non-comment line
  probe.LineEndings(st:unix)
  probe.split('<10>')
  loop x = 1 to probe.records()
    line.setValue(probe.getLine(x))
    line.trim()
    if ~line._DataEnd then cycle.
    case val(line.valuePtr[1])
    of 33 orof 124                                         ! '!' orof '|'                  ! comment or blank continuation line
      cycle
    end
    if line.startsWith('=== case') then isGolden = true.
    break
  end

  if isGolden
    ! ---- golden test mode (Phases 2-4) ----
    gr.RunFile(fn.getValue(), outSt)
    outFn.setValue(fn)
    outFn.append(clip(stampSt.getValue()) & '.result.txt') ! date-time stamp so repeated golden runs keep separate results
    if not outSt.SaveFile(outFn.getValue())
      Say('Could not save results to ' & outFn.getValue() & '||' & outSt.LastError)
      exitRc = 1
    end
    if wantSumm                                            ! --summary only
      Say('VitMatch golden: ' & clip(fn.getValue()) & |
              '|Cases: ' & gr.caseCount             & |
              '|Pass:  ' & gr.passCount             & |
              '|Fail:  ' & gr.failCount             & |
              '||Results in ' & clip(outFn.getValue()))
    end
    if gr.failCount then exitRc = 1.                                      ! failing goldens must reach the calling script
    if exitRc then halt(1).
    return
  end

  ! ---- rule file: lint + IR dump (Phase 1), always produced ----
  rl.LoadFile(fn.getValue())
  if userFn._DataEnd                                                      ! user rulefile appends AFTER the shipped file,
    uGrps  = records(rl.groups)                                           !        BEFORE the stylefile
    uRules = records(rl.rules)
    rl.LoadUserRules(userFn.getValue())
    uGrps  = records(rl.groups) - uGrps
    uRules = records(rl.rules) - uRules
  end
  if styleFn._DataEnd                                                     ! profiles layer over the rule file's shipped styles
    rl.LoadStyleFile(styleFn.getValue())
  end
  rl.Lint()
  rl.Resolve(styleArg.getValue(), grpArg.getValue(), nogrpArg.getValue()) ! THE resolver - also validates --style=
  ! ---- an unknown --group=/--nogroup= NAME was a WARNING and the run went
  !      ahead without it. A warning only reaches the report, so what you saw was a run that
  !      finished cleanly and quietly did not do the thing you asked for. This is exactly the
  !      case fixed for an unrecognised SWITCH, and the argument is the same: a name we
  !      do not know means we do not know what was wanted.
  !      The shape to guard against: a caller asks for
  !          --group=cosmetic-keywordcase-lower
  !      while the rule file carries
  !          GROUP cosmetic-keywordcase, OFF
  !      so the group named does not exist, KeywordCase never runs, and AND/OR/NOT/XOR come
  !      back upper case. Warn rather than refuse and no report answers the question WHY,
  !      because nothing was wrong enough to say so.
  !      The message names the group AND lists the real ones - a refusal that does not tell you
  !      the valid spellings just moves the guessing somewhere else.
  badGrp.free()
  grpList.setValue(grpArg)
  grpWhich = '--group='
  do CheckGroupNames
  grpList.setValue(nogrpArg)
  grpWhich = '--nogroup='
  do CheckGroupNames
  if badGrp._DataEnd
    knownGrp.free()
    loop x = 1 to records(rl.groups)
      get(rl.groups, x)
      if errorcode() then break.
      knownGrp.append(choose(knownGrp._DataEnd = 0, '', '|  ') & clip(rl.groups.name) & |
                      choose(rl.groups.choiceName = '', '', '   (choice ' & clip(rl.groups.choiceName) & ')'))
    end
    Say('VitTransform: no such group in ' & clip(fn.getValue()) & '.'                 & |
        '||' & clip(badGrp.getValue())                                                & |
        '||The groups this rule file actually declares are:'                          & |
        '||  ' & clip(knownGrp.getValue())                                            & |
        '||Nothing has been changed.')
    halt(1)
  end
  ! ---- --only=/--skip= take a ruleId, and a ruleId is the rule's LINE NUMBER in the
  !      rule file. Insert a comment or a blank line above a rule and every id below it moves.
  !      Nothing validated the number, so a stale id silently did one of two wrong things: it
  !      matched a DIFFERENT rule than the one meant, or it matched nothing at all and the run
  !      reported 0 changes - indistinguishable from "that rule found nothing here". Say so.
  if eng.onlyId or eng.skipId
    okOnly = choose(eng.onlyId = 0) ! 0 = not asked for = nothing to check
    okSkip = choose(eng.skipId = 0)
    loop x = 1 to records(rl.rules)
      get(rl.rules, x)
      if errorcode() then break.
      if eng.onlyId and rl.rules.ruleId = eng.onlyId then okOnly = 1.
      if eng.skipId and rl.rules.ruleId = eng.skipId then okSkip = 1.
    end
    if ~okOnly or ~okSkip
      Say('VitTransform: no rule has that id in ' & clip(fn.getValue()) & '.'               & |
          choose(okOnly = 0, '||  --only=' & eng.onlyId, '')                                & |
          choose(okSkip = 0, '||  --skip=' & eng.skipId, '')                                & |
          '||A rule id is its LINE NUMBER in the rule file, so ids move whenever lines are' & |
          ' added above them. Open the rule file at that line, or run the rule file on its' & |
          ' own (VitTransform <<rulefile>) to dump every rule with its current id.'         & |
          '||Nothing has been changed.')
      halt(1)
    end
  end
  errs  = rl.ErrorCount()
  warns = rl.WarnCount()

  rl._List(outSt)
  outFn.setValue(fn)
  outFn.append(clip(stampSt.getValue()) & '.ir.txt') ! date-time stamp so repeated lint/IR runs keep separate dumps
  if not outSt.SaveFile(outFn.getValue())
    Say('Could not save IR dump to ' & outFn.getValue() & '||' & outSt.LastError)
    exitRc = 1
  end

  if ~srcSpec._DataEnd
    if wantSumm                                      ! --summary only
      Say('VitRules: parsed ' & clip(fn.getValue()) & |
              '|Metavars: ' & records(rl.metaVars)  & |
              '|Rules:    ' & records(rl.rules)     & |
              '|Errors:   ' & errs                  & |
              '|Warnings: ' & warns                 & |
              '||IR dump written to ' & clip(outFn.getValue()))
    end
    if errs then exitRc = 1.                         ! lint mode: rule-file errors ARE the result
    if exitRc then halt(1).
    return
  end

  if errs
    Say('VitTransform: ' & errs & ' error(s) in ' & clip(fn.getValue())                                                 & |
            choose(rl.userErrors > 0, ' (' & rl.userErrors & ' from --userrules= ' & clip(userFn.getValue()) & ')', '') & |
            ' - transform aborted.'                                                                                     & |
            '||See ' & clip(outFn.getValue()))
    halt(1)
  end

  ! ---- in-place safety: never overwrite the originals silently ----
  ! No <outdir> means "transform in place".  That is destructive, so it must be asked
  ! for explicitly with --in-place (which then keeps a timestamped .bak of each changed file).
  if ~len(clip(eng.outDir)) and ~eng.inPlace and ~eng.dryRun ! --dry-run WRITES NOTHING, so there is nothing to refuse.
                                                             ! Without that exemption the guard aborts first and the README
                                                             ! safe-first-run line cannot be run at all.
    Say('VitTransform: no <<outdir> given - refusing to overwrite the originals by default.'       & |
            '||  Write transformed copies to a directory:'                                         & |
            '|      VitTransform ' & clip(fn.getValue()) & ' ' & clip(srcSpec.getValue()) & ' out' & |
            '||  ...or overwrite the originals in place (a timestamped .bak of each'               & |
            '|  changed file is written first):'                                                   & |
            '|      VitTransform ' & clip(fn.getValue()) & ' ' & clip(srcSpec.getValue()) & ' --in-place')
    halt(1)
  end

  ! (date-time stamp already computed above, before golden/IR output naming)

  ! ---- assemble the output-filename suffix (--outsuffix= literal and/or --outstamp date-time) ----
  ! Inserted before the extension by VitEngine.OutName,
  ! e.g.  out\reindent.clw  ->  out\reindentWidth2 on 20260713 at 14302547.clw
  if sufArg._DataEnd
    eng.outSuffix = sufArg.getValue()                        ! literal part first
  end
  if wantStamp
    eng.outSuffix = clip(eng.outSuffix) & stampSt.getValue() ! then the date-time stamp
  end

  ! ---- transform mode (Phase 5) ----
  if eng.outDir
    outDirC = clip(eng.outDir)
    MakeDirs(outDirC)                                        ! _mkdir makes ONE level only; create every intermediate dir so out\sub works
  end

  ! ---- same-directory safety, part 2: an <outdir> that IS the source directory overwrites
  !      the originals just as surely as a blank one, and the blank-outdir guard above cannot
  !      see it - '.', 'src', '..\src' and an absolute path can all name the source directory,
  !      and no string compare settles that. The filesystem answers it directly: write a
  !      uniquely-named probe file into <outdir> and ask whether the SOURCE directory now
  !      contains it. --outsuffix/--outstamp runs are exempt (the suffixed output name cannot
  !      collide with an original) and --dry-run writes nothing. An unwritable probe proves
  !      nothing either way, so that skips the check - the per-file save errors report it,
  !      and they exit 1.
  if eng.outDir and ~eng.outSuffix and ~eng.dryRun
    dirProbe.setValue('vt-dirprobe' & clip(stampSt.getValue()) & '.tmp')
    probeSt.setValue('VitTransform same-directory probe - delete freely')
    if probeSt.SaveFile(clip(eng.outDir) & '\' & dirProbe.getValue())
      param.setValue(probe.PathOnly(srcSpec.getValue()))     ! '' = the sources are in the working directory
      if param._DataEnd then param.append('\').
      param.append(dirProbe)
      x = exists(param.getValue())
      remove(clip(eng.outDir) & '\' & dirProbe.getValue())
      if x
        Say('VitTransform: <<outdir> ' & clip(eng.outDir) & ' is the source directory - writing'          & |
            ' there would overwrite the originals, and the <<outdir> path keeps no .bak.'                 & |
            '||  Write the copies somewhere else:'                                                        & |
            '|      VitTransform ' & clip(fn.getValue()) & ' ' & clip(srcSpec.getValue()) & ' out'        & |
            '||  ...or overwrite the originals deliberately (a timestamped .bak of each'                  & |
            '|  changed file is written first):'                                                          & |
            '|      VitTransform ' & clip(fn.getValue()) & ' ' & clip(srcSpec.getValue()) & ' --in-place' & |
            '||Nothing has been changed.')
        halt(1)
      end
    end
  end
  totTmr.Start()
  outSt.free()
  eng.Init(rl)
  ! THE RULE FILE MAY ASK FOR INCLUDE EXPANSION. Precedence, in order, and the
  ! reason for it: --nothorough is the explicit NO and wins over everything, because an
  ! implicit switch you cannot turn off is worse than no switch; then the command line's
  ! own --thorough / --root=, which were always the loudest thing in the room; then the
  ! shipped rule file's THOROUGH directive, which travels with the rules that need it.
  ! A rule set full of typed StringTheory receivers cannot do its job without expansion,
  ! and that is a property of the RULES rather than of the style chosen to run them.
  if noThorough
    thorough = 0
    if rootArg._DataEnd or rl.wantThorough
      outSt.append('[--nothorough: include expansion OFF for this run'                                     & |
                   choose(rl.wantThorough, ' - the rule file asked for it at line ' & rl.thoroughLine, '') & |
                   ']<13,10>')
    end
    rootArg.free() ! nothing left to expand
  elsif rl.wantThorough and ~thorough and ~rootArg._DataEnd
    thorough = true
    outSt.append('[THOROUGH: requested by the rule file, line ' & rl.thoroughLine                          & |
                 ' - --nothorough turns it off]<13,10>')
  end
  if thorough and ~rootArg._DataEnd         ! Q1: --thorough without --root -> discover %ROOT% from the registry
    rootArg.setValue(DiscoverRoot(verNm))
    if ~rootArg._DataEnd
      if rl.wantThorough                    ! say WHO asked, or the user
        Say('VitTransform: the rule file asks for THOROUGH (line ' & rl.thoroughLine & ') but no installed Clarion was found - supply --root=<<dir>, or run with --nothorough')
      else                                  !   hunts for a switch they never typed
        Say('VitTransform: --thorough found no installed Clarion in the registry - supply --root=<<dir>')
      end
      halt(1)
    end
    outSt.append('[--thorough: %ROOT% auto-discovered (' & clip(verNm) & '): ' & clip(rootArg.getValue()) & ']<13,10>')
  end
  if rootArg._DataEnd                       ! --root supplied -> enable cross-file type resolution
    if ~redArg._DataEnd                     ! default .red: working dir first, then <root>\bin (its normal home)
      if exists('Clarion110.red')
        redArg.setValue('Clarion110.red')
      else
        redArg.setValue(FindRedInBin(rootArg.getValue()))
        if ~redArg._DataEnd
          redArg.setValue('Clarion110.red') ! last resort; the preprocessor reports if truly absent
        end
      end
    end
    eng.SetupIncludes(redArg.getValue(), rootArg.getValue(), cfgArg.getValue())
    outSt.append('[include expansion ON  root=' & clip(rootArg.getValue()) & |
                 '  red=' & clip(redArg.getValue())                        & |
                 '  config=' & choose(cfgArg._DataEnd, clip(cfgArg.getValue()), 'Release') & ']<13,10>')
  end
  if userFn._DataEnd                        ! the report names its user rulefile + what it
    outSt.append('[userrules: ' & clip(userFn.getValue()) & '  groups=' & uGrps & |
                 '  rules=' & uRules & '  errors=' & rl.userErrors & ']<13,10>') !     added - part of the repeatability header
  end
  rl.SelectionTable(outSt)                                                       ! every report carries its resolved selection
  if srcSpec.containsA('*?')                                                     ! '?' '*'
    DIRECTORY(FilesQ, srcSpec.getValue(), ff_:NORMAL)
    sort(FilesQ, +FQ:Name)
    param.setValue(probe.PathOnly(srcSpec.getValue()))                           ! reusing param as the path prefix
    loop idx = 1 to records(FilesQ)
      get(FilesQ, idx)
      if band(FQ:attrib, ff_:DIRECTORY) then cycle.                              ! a subfolder matching src\* is not a source (#13) -
                                                                                 !   the same filter the two sibling DIRECTORY sites apply
      realFiles += 1
      if param._DataEnd
        FQ:Name = param.getValue() & '\' & FQ:Name
      end
      eng.TransformFile(clip(FQ:Name), outSt)
      if wantDump then dumpSrc.setValue(clip(FQ:Name)).                          ! the stream exptk will still hold at the dump
    end
    if ~realFiles                                                                ! rows are not files: a queue holding only subfolders still
      outSt.append('no files matched ' & srcSpec.getValue() & '<13,10>')         !   transformed nothing (#13 review)
      eng.loadErrors += 1                                                        ! a wildcard that reads NOTHING did not do what it was told:
    end                                                                          !   count it NOT LOADED so the run exits 1 - a watched sweep
                                                                                 !   that transforms nothing must not report success (#13)
  else
    eng.TransformFile(srcSpec.getValue(), outSt)
    if wantDump then dumpSrc.setValue(srcSpec).
  end
  totTmr.Stop()

  ! ---- --dumptokens. Two outputs, and the second is the useful one.
  !      DumpTokens writes one token per line with the level mark in COLUMN 1, so you can
  !      read the block structure the tokenizer actually built. Then MatchLevel - which
  !      already walks forward from a '+' counting depth - names every '+' that never finds
  !      its '-'. The `exptk level census` line tells you a level was lost; this says WHICH
  !      token lost it, which is the difference between a fix and a guess.
  !      Expanded stream only: without --thorough there is nothing in exptk to dump.
  if wantDump
    if eng.exptk &= NULL
      outSt.append('--dumptokens: no expanded stream - add --thorough<13,10>')
    elsif ~dumpSrc._DataEnd
      outSt.append('--dumptokens: no file was transformed - nothing to dump<13,10>')
    else
      dumpNm.setValue(probe.FileNameOnly(dumpSrc.getValue(), true))              ! the LAST transformed file - what exptk holds
      dumpNm.append('.tokens.txt')
      eng.exptk.DumpTokens(dumpNm.getValue())
      if ~exists(dumpNm.getValue())                                              ! DumpTokens reports failure only to the debug
        outSt.append('--dumptokens: FAILED to write ' & clip(dumpNm.getValue()) & |                 ! viewer; the report must not
                     ' - the dump is NOT on disk<13,10>')                        !   claim output that is not there
        exitRc = 1
      else
        outSt.append('--dumptokens: expanded token stream written to ' & clip(dumpNm.getValue()) & |
                     '  (column 1 = level: + opens, - closes, / else-arm, x exit)<13,10>')
      end
      ! ---- (a) OPENS INSIDE PARENTHESES. This is the one that names a CULPRIT.
      !      A structure keyword can only open a block at statement level; inside
      !      parentheses it is a TYPE or an ATTRIBUTE - `Procedure (Queue pQueue)`,
      !      `CLASS,TYPE,MODULE('x.clw')`. Every hit here is a token the tokenizer
      !      marked '+' that cannot possibly be opening anything.
      !
      !      Why not just report unmatched opens? Because MatchLevel cannot name the
      !      culprit, and neither can anything else. Given a spurious '+' inside a real
      !      CLASS ... END, the spurious one takes the END (depth reaches 0 there) and
      !      the CLASS reports as unmatched. The report would name the VICTIM. A stack
      !      walk gives the same answer - "CLASS unclosed" and "Queue unclosed" produce
      !      identical mark sequences, so the information simply is not in the marks.
      !      Paren depth is independent evidence, which is why it can point at the
      !      offender. It is also exactly the predicate the proposed fix would use, so
      !      this listing doubles as a preview of what that fix would change.
      dumpBad = 0
      dumpMt  = 0 ! reused: paren depth
      loop dumpIx = 1 to records(eng.exptk.tokens)
        get(eng.exptk.tokens, dumpIx)
        if errorcode() then break.
        if eng.exptk.tokens.tok &= NULL
          dumpTx = ''
        else
          dumpTx = eng.exptk.tokens.tok
        end
        if dumpTx = '('
          dumpMt += 1
        elsif dumpTx = ')'
          if dumpMt then dumpMt -= 1.
        elsif eng.exptk.tokens.level = '+' and dumpMt > 0
          dumpBad += 1
          if dumpBad <= 50
            outSt.append('  OPENS INSIDE PARENTHESES at expanded line ' & eng.exptk.tokens.lineNo & |
                         ', token ' & dumpIx & ', paren depth ' & dumpMt & ': ' & clip(dumpTx)    & |
                         '   <<- cannot be a structure here<13,10>')
          end
        end
      end
      if dumpBad > 50 then outSt.append('  (' & dumpBad & ' in all - first 50 shown)<13,10>').
      outSt.append('--dumptokens: ' & dumpBad & ' level-opening token(s) inside parentheses<13,10>')

      ! ---- (b) UNMATCHED OPENS. Read these as "the structure that failed to close",
      !      NOT as the offender - see the note above. Useful because it bounds the
      !      search to one structure's span in tokendump.txt.
      dumpBad = 0
      loop dumpIx = 1 to records(eng.exptk.tokens)
        get(eng.exptk.tokens, dumpIx)
        if errorcode() then break.
        if eng.exptk.tokens.level <> '+' then cycle.
        dumpLn = eng.exptk.tokens.lineNo
        if eng.exptk.tokens.tok &= NULL
          dumpTx = ''
        else
          dumpTx = eng.exptk.tokens.tok
        end
        get(eng.exptk.tokens, dumpIx) ! MatchLevel works from the CURRENT record, and moves the pointer
        if ~eng.exptk.MatchLevel()
          dumpBad += 1
          if dumpBad <= 20
            outSt.append('  never closed: ' & clip(dumpTx) & ' opened at expanded line ' & dumpLn & |
                         ', token ' & dumpIx & '  (the VICTIM - look INSIDE its span)<13,10>')
          end
        end
      end
      if dumpBad > 20 then outSt.append('  (' & dumpBad & ' in all - first 20 shown)<13,10>').
      outSt.append('--dumptokens: ' & dumpBad & ' unmatched open(s)<13,10>')

      ! ---- (c) UNMATCHED CLOSES - the mirror of (b), and the half that was missing.
      !      (b) visits only '+' tokens, so a '-' that closes nothing was never examined:
      !      vitWordStore.clw reported 0 and 0 while its census read +139 -145, six MORE
      !      closes than opens. Every open could find a close, so every open matched; the
      !      six orphans were all on the '-' side and nothing ever looked there.
      !      MatchLevel already walks both ways (of 45 -> search backwards for '+'), so this
      !      is the same call from the other end, not a new mechanism.
      !      An END that closes nothing is a compile error in real Clarion, so a hit here is
      !      EITHER genuinely malformed source OR a construct we mark '-' wrongly - and the
      !      token name says which. Do not assume the file is at fault.
      dumpBad = 0
      loop dumpIx = 1 to records(eng.exptk.tokens)
        get(eng.exptk.tokens, dumpIx)
        if errorcode() then break.
        if eng.exptk.tokens.level <> '-' then cycle.
        dumpLn = eng.exptk.tokens.lineNo
        if eng.exptk.tokens.tok &= NULL
          dumpTx = ''
        else
          dumpTx = eng.exptk.tokens.tok
        end
        get(eng.exptk.tokens, dumpIx) ! MatchLevel works from the CURRENT record, and moves the pointer
        if ~eng.exptk.MatchLevel()
          dumpBad += 1
          if dumpBad <= 20
            outSt.append('  closes nothing: ' & clip(dumpTx) & ' at expanded line ' & dumpLn & |
                         ', token ' & dumpIx & '<13,10>')
          end
        end
      end
      if dumpBad > 20 then outSt.append('  (' & dumpBad & ' in all - first 20 shown)<13,10>').
      outSt.append('--dumptokens: ' & dumpBad & ' unmatched close(s)<13,10>')
    end
  end

  outSt.append('---<13,10>')
  outSt.append('files: ' & eng.filesDone & '  changed: ' & eng.filesChanged                  & |
               '  changes: ' & eng.totalChanges & '  time: ' & clip(totTmr.Duration())       & |
               choose(eng.dryRun, '  [dry-run]', '')                                         & |
               choose(~eng.loadErrors, '', '  NOT LOADED: ' & eng.loadErrors)                & |
               choose(~eng.ppErrors,   '', '  HEADERS NOT FOUND: ' & eng.ppErrors) & '<13,10>') ! on the summary line, not just buried above

  outFn.setValue(fn)
  outFn.append(clip(stampSt.getValue()) & '.report.txt') ! date-time stamp (' on yyyymmdd at hhmmssth') so repeated runs with the same rulefile keep separate reports instead of overwriting
  if not outSt.SaveFile(outFn.getValue())
    Say('Could not save report to ' & outFn.getValue() & '||' & outSt.LastError)
    exitRc = 1
  end
  ! the end-of-run box is --summary only, so a bat of many runs goes straight
  ! through. Every number in it is already in the report. The ONE exception is a save
  ! failure: the output you asked for is not on disk, and that must always be seen.
  if wantSumm or eng.saveErrors > 0 or eng.ppErrors > 0
    Say('VitTransform: ' & clip(srcSpec.getValue())                                              & |
            '|Files:   ' & eng.filesDone                                                         & |
            '|Changed: ' & eng.filesChanged                                                      & |
            '|Changes: ' & eng.totalChanges                                                      & |
            '|Time:    ' & clip(totTmr.Duration())                                               & |
            choose(eng.dryRun, '|DRY RUN - nothing written', '')                                 & |
            choose(eng.saveErrors > 0, '|SAVE ERRORS: ' & eng.saveErrors & ' - see report!', '') & |
            choose(eng.ppErrors > 0, '|HEADERS NOT FOUND: ' & eng.ppErrors                       & |
                                     ' - the type registry is incomplete, so typed rules saw'    & |
                                     ' only part of the program. See report!', '')               & |
            '||Report in ' & clip(outFn.getValue()))
  end
  if eng.saveErrors > 0                                                                         or |   ! output that was asked for is not on disk
     eng.loadErrors > 0                                                                         or |   ! a SOURCE that was asked for was never read - the run did not do what it was told
     eng.ppErrors > 0 ! a HEADER that was asked for was never found - the type registry is incomplete, so typed rules judged against part of the program
    exitRc = 1
  end
  if exitRc then halt(1).
  return

! ---- every name in one --group=/--nogroup= list, checked against the rule file.
!      The list arrives comma-joined, whether the switch repeated or the user wrote one
!      comma list - both reach here identically. ----
CheckGroupNames routine
  data
cgZ   long,auto
cgNm  StringTheory
  code
  if ~grpList._DataEnd then exit.
  grpList.split(',')
  loop cgZ = 1 to grpList.records()
    cgNm.setValue(grpList.getLine(cgZ))
    cgNm.trim()
    if ~cgNm._DataEnd then cycle.
    if rl.FindGroup(cgNm.getValue()) then cycle.
    badGrp.append(choose(badGrp._DataEnd = 0, '', '|') & '  ' & clip(grpWhich) & clip(cgNm.getValue()))
  end

! ---------------------------------------------------------------------------
! every modal box goes through here. Under --batch it becomes a line in
! vt-batch.log instead. NOT suppressed - each of these is a thing the run needs
! you to know (a rule file refused to load, output that is not on disk), and an
! unattended watcher cannot click OK. Suppressing them would trade a hang for a
! silent wrong answer, which is worse.
! ---------------------------------------------------------------------------
Say  PROCEDURE(STRING pMsg)
lg   StringTheory
  code
  if ~batchMode
    message(pMsg)
    return
  end
  lg.LoadFile('vt-batch.log') ! absent file = empty; append and rewrite
  lg.append(clip(left(format(today(),@d12))) & ' ' & clip(left(format(clock(),@T04))) & '  ')
  lg.append(clip(pMsg))
  lg.append('<13,10>')
  lg.SaveFile('vt-batch.log')

! ====================================================================================
! validate a numeric switch value (--only=/--skip=/--passes=). A non-numeric
! value would coerce silently to 0 (--only=reindent -> run every rule; --passes=x -> a
! zero-pass no-op), so it is an all-digit check: a bad value aborts with a message rather
! than doing the wrong thing quietly. pWhich is the switch name for the diagnostic.
! ------------------------------------------------------------------------------------
NumArg  PROCEDURE(STRING pTxt, STRING pWhich, BYTE pZeroOk=0)
v    string(21),auto
i    long,auto
n    long,auto
  code
  v = left(pTxt)
  n = len(clip(v))
  if ~n
    Say('VitTransform: ' & clip(pWhich) & ' requires a number')
    halt(1)
  end
  if n > 9
    Say('VitTransform: ' & clip(pWhich) & ' value is too long: ' & clip(pTxt)) ! >9 digits silently overflowed the LONG
    halt(1)
  end
  loop i = 1 to n
    if v[i] < '0' or v[i] > '9'
      Say('VitTransform: ' & clip(pWhich) & ' expects a number, got "' & clip(pTxt) & '"')
      halt(1)
    end
  end
  if v = 0 and ~pZeroOk
    Say('VitTransform: ' & clip(pWhich) & ' must be 1 or more')                ! --passes=0 was a silent no-op run.
                                                                               ! --width=0 is a REAL setting (never split),
                                                                               ! so it passes pZeroOk=1 and reaches its own handling.
    halt(1)
  end
  return v                                                                     ! string -> LONG return: deformats the validated digits

! ====================================================================================
! _mkdir creates a single level only, so an outdir like out\sub with an absent
! out fails and every save then fails silently. Walk the path and mkdir each intermediate
! level (harmless if a level already exists) before the final one.
! ------------------------------------------------------------------------------------
MakeDirs  PROCEDURE(STRING pPath)
full   cstring(261)
seg    cstring(261),auto
i      long,auto
n      long,auto
c      string(1),auto
  code
  full = clip(left(pPath))
  n = len(full)
  if ~n then return.
  loop i = 1 to n
    c = full[i]
    if (c = '\' or c = '/') and i > 1
      seg = sub(full, 1, i-1) ! path up to (not incl.) this separator
      mkdir(seg)              ! -1 if it already exists: harmless
    end
  end
  mkdir(full)                 ! the final level

! ====================================================================================
! --thorough root discovery: find installed Clarions.
! TWO sources, both validated, feeding one candidate list (newest first):
!   1. REGISTRY - each properly-installed Clarion registers a product GUID under
!      HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall with InstallLocation =
!      %ROOT%. (32-bit process, so GETREG is WOW64-redirected to SOFTWARE\WOW6432Node -
!      exactly where the 32-bit Clarion installer writes.)
!   2. FILESYSTEM - <drive>:\Clarion* directory probe on C/D/E/F + the current drive.
!      Needed in the real world: a Clarion tree COPIED from a backup (e.g. after a PC
!      swap) runs fine but never registered, so the registry knows nothing (a real
!      machine - the case that motivated this fallback).
! A candidate only counts if it really is a Clarion root: %ROOT%\libsrc\win\equates.clw
! exists (or the pre-C8 %ROOT%\libsrc\equates.clw) - that is precisely what --thorough
! include expansion needs. Exactly one candidate -> used silently; several -> the user
! picks from a button dialog (batch runs should pass --root explicitly); none -> ''.
! ------------------------------------------------------------------------------------
DiscoverRoot PROCEDURE(*STRING pVerName)
GuidQ  QUEUE,PRE(gq)
guid     string(40)
nm       string(24)
ver      long
       END
FoundQ QUEUE,PRE(fq)
nm       string(24)
loc      string(261)
ver      long
       END
DirQ   QUEUE(File:queue),PRE(dq)
       END
drives string(5)
dl     string(1)
btns   string(260)
t      StringTheory
pick   long,auto
loc    string(261)
qx     long,auto
dx     long,auto
kx     long,auto
px     long,auto ! ParseDirVer's own index
dup    byte
vnum   long
frac   byte
c      string(1)
  code
  gq:guid = '{{8B14DD30-5F0D-11EA-72AE-145397C02CD6}' ; gq:nm = 'Clarion 12'      ; gq:ver = 120 ; add(GuidQ)
  gq:guid = '{{40387FE0-70B9-11E8-41BB-330DD2345AF1}' ; gq:nm = 'Clarion 11/11.1' ; gq:ver = 110 ; add(GuidQ)
  gq:guid = '{{9B04EBD0-8ACA-11E4-4823-04D0CF9C0029}' ; gq:nm = 'Clarion 10'      ; gq:ver = 100 ; add(GuidQ)
  gq:guid = '{{5FBB5960-7EDC-11E3-3D6C-05B078044AE1}' ; gq:nm = 'Clarion 9.1'     ; gq:ver = 91  ; add(GuidQ)
  gq:guid = '{{905A4CB0-90B8-11E2-3D6C-299385554AE1}' ; gq:nm = 'Clarion 9'       ; gq:ver = 90  ; add(GuidQ)
  gq:guid = '{{19336650-F595-11DF-72AE-06609D572CD6}' ; gq:nm = 'Clarion 8'       ; gq:ver = 80  ; add(GuidQ)
  gq:guid = '{{479A07C0-EF05-11DE-6DF1-18371B021649}' ; gq:nm = 'Clarion 7.1-7.3' ; gq:ver = 71  ; add(GuidQ)
  gq:guid = '{{01D4BB50-BD48-11DB-6784-067D01F418BE}' ; gq:nm = 'Clarion 7'       ; gq:ver = 70  ; add(GuidQ)
  pVerName = ''

  ! ---- source 1: the uninstall registry ----
  loop qx = 1 to records(GuidQ)
    get(GuidQ, qx)
    loc = GETREG(REG_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' & clip(gq:guid), 'InstallLocation')
    if loc
      if loc[len(clip(loc))] = '\' then loc = sub(loc, 1, len(clip(loc)) - 1). ! strip a trailing backslash
      do AddCandidate
    end
  end

  ! ---- source 2: <drive>:\Clarion* filesystem probe (copied-not-installed trees) ----
  drives = 'CDEF'
  loc = path()                                                                 ! current dir - its drive letter joins the probe list
  if len(clip(loc)) >= 2 and loc[2] = ':' then drives = clip(drives) & upper(loc[1]).
  loop dx = 1 to len(clip(drives))
    dl = drives[dx]
    if dx > 4 and instring(dl, drives[1 : 4], 1, 1) then cycle.                ! current drive already in C..F
    free(DirQ)
    directory(DirQ, dl & ':\Clarion*', ff_:DIRECTORY)
    loop kx = 1 to records(DirQ)
      get(DirQ, kx)
      if ~band(dq:attrib, ff_:DIRECTORY) or |   ! files named Clarion* are not roots
         dq:name = '.' or dq:name = '..'
        cycle
      end
      loc = dl & ':\' & dq:name
      do ParseDirVer                                                           ! 'Clarion11' -> nm/ver for sorting + display
      do AddCandidate
    end
  end

  if records(FoundQ) = 0
    return ''
  end
  sort(FoundQ, -fq:ver)                                                        ! newest first, whatever the source
  if records(FoundQ) = 1                                                       ! exactly one -> use it silently
    get(FoundQ, 1)
    pVerName = fq:nm
    return clip(fq:loc)
  end
  ! several -> let the user choose (newest listed first). An unattended/batch run
  ! should pass --root explicitly; this modal is the interactive convenience path.
  if batchMode                                                                 ! --batch must never open this picker - a watcher cannot answer it.
    get(FoundQ, 1)                                                             !   Newest wins and the report says so, which is repeatable; hanging is not.
    pVerName = fq:nm
    Say('VitTransform --batch: several Clarion installations found - using the newest, ' & |
        clip(fq:nm) & ' at ' & clip(fq:loc) & '. Pass --root=<<dir> to choose.')
    return fq:loc
  end
  t.setValue('Several Clarion installations were found - which %ROOT% should --thorough use?')
  loop qx = 1 to records(FoundQ)
    get(FoundQ, qx)
    t.append('<13,10>' & clip(fq:nm) & '  =  ' & clip(fq:loc))
    btns = choose(qx = 1, fq:nm, clip(btns) & '|' & fq:nm)
  end
  pick = message(t.getValue(), 'VitTransform --thorough', ICON:Question, clip(btns))
  if pick < 1 or pick > records(FoundQ) then pick = 1. ! Esc/odd return -> newest
  get(FoundQ, pick)
  pVerName = fq:nm
  return clip(fq:loc)

! ---- validate loc as a real Clarion root, dedupe, and add to FoundQ ----
! (registry path arrives with gq:nm/gq:ver set; filesystem path with fq-style vnum via ParseDirVer)
AddCandidate routine
  if ~exists(clip(loc) & '\libsrc\win\equates.clw') and ~exists(clip(loc) & '\libsrc\equates.clw')
    exit                                               ! not a usable root (no include library)
  end
  dup = 0
  loop pick = 1 to records(FoundQ)                     ! reuse pick as a scratch index (set fresh below)
    get(FoundQ, pick)
    if upper(fq:loc) = upper(loc) then dup = 1 ; break.
  end
  if dup then exit.
  fq:loc = loc
  fq:nm  = gq:nm                                       ! registry: proper name; filesystem: ParseDirVer filled gq:nm/gq:ver
  fq:ver = gq:ver
  add(FoundQ)

! ---- derive a display name + sortable version from a Clarion* directory name ----
! 'Clarion11' -> ver 110; 'Clarion9.1' -> 91; 'Clarion' (no digits) -> 0. Fills gq:nm/gq:ver
! (the scratch fields AddCandidate reads) so both sources share one add path.
ParseDirVer routine
  vnum = 0 ; frac = 0
  loop px = 8 to len(clip(dq:name))                    ! chars after 'Clarion' (its OWN index - reusing kx would clobber the caller's DirQ loop, leaving only the FIRST Clarion* dir per drive visible)
    c = dq:name[px]
    if c >= '0' and c <= '9'
      if frac
        vnum = vnum * 10 + (val(c) - 48) ; break       ! one fractional digit is enough (9.1 -> 91)
      else
        vnum = vnum * 10 + (val(c) - 48)
      end
    elsif c = '.'
      frac = 1
    else
      break
    end
  end
  if ~frac then vnum = vnum * 10.                      ! whole versions align: 11 -> 110 vs 9.1 -> 91
  gq:nm  = clip(dq:name) & ' (' & dl & ':)'
  gq:ver = vnum

! ====================================================================================
! Default-.red discovery: the redirection file normally sits in
! <root>\bin (e.g. C:\Clarion11\bin\Clarion110.red). When no --red is given and the
! working dir has no Clarion110.red, take the newest Clarion*.red from <root>\bin.
! Returns the FULL path, or '' when none found.
! ------------------------------------------------------------------------------------
FindRedInBin PROCEDURE(STRING pRoot)
RedQ  QUEUE(File:queue),PRE(rq)
      END
rx    long,auto
rn    long,auto
px    long,auto
rc    string(1),auto
best  string(64),auto
bestN long,auto
  code
  if ~pRoot then return ''.
  directory(RedQ, clip(pRoot) & '\bin\Clarion*.red', ff_:NORMAL)
  best = '' ; bestN = -1
  loop rx = 1 to records(RedQ)
    get(RedQ, rx)
    if band(rq:attrib, ff_:DIRECTORY) then cycle.
    rn = 0 ! NUMERIC version compare - lexicographic picks Clarion90.red over Clarion120.red ('9' > '1')
    loop px = 8 to len(clip(rq:name))
      rc = rq:name[px]
      if rc < '0' or rc > '9' then break.
      rn = rn * 10 + (val(rc) - 48)
    end
    if rn > bestN then best = rq:name ; bestN = rn.
  end
  if ~best then return ''.
  return clip(pRoot) & '\bin\' & clip(best)
