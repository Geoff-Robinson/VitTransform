! vitTransform - the command-line driver for VitTransform
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
! switches (a switch NAME is read in any case; the value after an '=' is taken as typed):
!           --dry-run  --verbose  --timing  --loose  --in-place  --only=<name-or-id>  --skip=<name-or-id>  --passes=<n>
!           --width=<n>          longest line to allow before it is split. Default 240.
!                                --width=0 turns splitting off entirely. Minimum 40.
!                                Also caps the continuation-collapse check.
!           --kwupper=A,B,C      with a keyword-case group on: these keywords stay UPPER whatever
!                                the style - a user who capitalises keywords but likes IF, OR,
!                                AND, ELSE, CASE, OF and OROF to stand out. --kwlower= and
!                                --kwcapitalise= (or --kwcapitalize=, --kwtitle=) likewise. Repeatable.
!           --loose              the type checks off: every typed metavar matches, and a receiver
!                                is taken to be a StringTheory. For code the symbol table cannot type.
!           --cmtgap=<n>         how many spaces to leave between a line of code and the
!                                comment that follows it. Default 1, and at least 1.
!           --cmtlimit=<n>       the column a comment column never passes. The comments in a
!                                block - one PROCEDURE, ROUTINE or CODE line to the next -
!                                share one column, the widest of their lines that ends before
!                                the limit; a line whose code ends past it keeps its comment
!                                at its own end instead of dragging the column out. The
!                                AND/OR/& before the bars of a wrapped statement line up two
!                                past the widest line that carries one. 90 if not given, or given as 0.
!           --cmtslack=<n>       a block with no line under the limit at all takes the widest
!                                line within n of its narrowest. 60 if not given, or given as 0.
!           --cmtoutlier=<n>     ONE line much wider than the rest does not drag the block out
!                                to meet it: a line more than n past the MIDDLE of its block
!                                keeps its comment at its own end and the others stay where
!                                they were. Off unless given; 0 is off. Try 20.
!           --decloutlier=<n>    the same idea for the TYPE column of a run of declarations,
!                                measured in NAME width: a label more than n past the middle
!                                name keeps the gap it was written with. A name is a different
!                                measure from a line of code, so it has its own number. Off unless given; 0 is off. Try 20.
!           --cmtwrap=<n>        no line with a trailing comment is left wider than n: a long
!                                comment is split onto continuation rows in the same column,
!                                cut to similar lengths (the first a little longer if they
!                                cannot be equal), and continuation rows that fit are joined
!                                back. Off unless given; try 225.
!           --cmtsplit=<n>       like --cmtwrap but it only ever cuts: a comment row wider than n
!                                is split, and short rows are left as they were written rather
!                                than joined back. Give this or --cmtwrap, not both.
!           --cmtreach=<n>       how much a line with no comment of its own may widen the shared
!                                column: it has a say while its code ends within n characters of
!                                that column, and is left out when it ends further away. 3.
!           --cmtinner=<n>       how far the comment column may move right to clear a line with no
!                                comment of its own sitting BETWEEN two commented lines, so the
!                                column does not land to the left of code inside the group. 12;
!                                0 leaves those middle lines out of it.
!           --cmtfloor=<word>    whether lines with no comment help decide the comment column:
!                                near (only one sitting beside a commented line, and within
!                                --cmtreach - the default), commented (never), all (every line
!                                in the block).
!           --contindent=<word>  where a line the tool breaks picks up again: bracket (the default)
!                                starts it one past the bracket it broke inside, under the first
!                                argument, for every break of the statement, or the indent for all
!                                of them when one piece would not fit there; indent is the line's
!                                own indent plus two - see the README
!           --cmtkeep=<word>     aligned (the default) leaves a group of neighbouring comments that
!                                already share one column exactly as written, as long as that column
!                                still clears every line of code under it; off re-columns every
!                                comment from the code, tidy or not.
!           --cmtop=<word>       where the AND/OR/& at the end of a wrapped line sits: code (all
!                                of them two past the widest code in the group - the default) or
!                                bar (each one ending a space before its own bar).
!           --cmtend=<word>      a comment on an END: take (it moves to the column the other
!                                lines settled on, and the short END line does not pull that
!                                column left - the default) or count (it counts like any other).
!           --dispatch=<word>    how the rules walk a file: classic (each rule walks the whole
!                                file in its turn - the default) or grouped (rules that look for
!                                the same word walk it together, and a rule is not walked again
!                                until the file has changed). The result is the same either way.
!           --colseq=<word>      the order the program compares text in: standard (the character
!                                codes' own order - the default) or custom (the program sets its
!                                own with CLACOLSEQ or LOCALE, so a CASE keeps its character ranges).
!           --cmtbar=<word>      a line carrying BOTH a continuation bar and a comment: which of
!                                the two lines up with the column its block settled on. bar (the
!                                default) puts the | there and the comment after it; comment puts
!                                the ! there and the | in front of it, so a lone comment and a
!                                commented bar start in the same place.
!           --cmtcont=<word>     a whole-line comment whose text is indented after the marker:
!                                indent (it reads as more of the comment above - the default)
!                                or none (a comment in its own right).
!           --cmtrun=<n>         how far up the file a line looks for the comment column it should
!                                join: more than n lines below the last comment and it does not
!                                take part, so a long uncommented stretch starts a fresh column.
!                                0 = no looking back at all. 10.
!           --summary            show the end-of-run message box. OFF by default so a .BAT of
!                                many runs goes straight through unattended; every number in
!                                that box is in the report file. The box still opens when the
!                                run fails: a save that failed, a source that was never read,
!                                or an include that was not found. In a .BAT add --batch too,
!                                and those go to vt-batch.log instead of stopping the run.
!           --batch              UNATTENDED: never open a modal box. Everything that would have
!                                been one is appended to vt-batch.log instead - not suppressed,
!                                because each is something you must see (a rule file refused to
!                                load, output that is not on disk). Required by the autonomous
!                                build watcher, which has nobody to click OK. Also makes
!                                --thorough take the newest Clarion instead of asking.
!           --postcheck          development check on the word index the rule scan walks: the index
!                                is patched after every rule that fires, and this rebuilds it the
!                                slow way as well and compares the two, keeping the rebuild if they
!                                differ. The output is never affected; the report line is the point.
!           --acdiag             why did AlignComments leave that comment there? Reports the
!                                per-comment reason: FROZEN, and OUT-OF-WINDOW when the nearest
!                                commented line above is more than --cmtrun lines away.
!           --dumptokens         write the EXPANDED token stream to <<source>.tokens.txt with the
!                                level mark in column 1, and report THREE things: every
!                                level-opening token sitting INSIDE parentheses (where nothing
!                                can open a structure), every unmatched OPEN, and every CLOSE
!                                that closes nothing. Needs --thorough. For chasing an
!                                unbalanced expanded-token level census.
!   S1 selection (rule files with GROUP/CHOICE/STYLE lines; no switches = file defaults):
!     --style=<name>       apply a shipped STYLE or loaded profile by name
!     --stylefile=<file>   load a user stylefile/profile file (STYLE, SETTINGS, LASTUSED lines)
!     --group=<name>       select a group after the style. REPEAT the switch for several
!                          (--group=a --group=b), or write one comma list - BOTH work.
!                          Comma lists are equally fine inside STYLE lines and profile
!                          files.
!     --nogroup=<name>     deselect a group (repeatable, same rule)
!     --stversion=<n>      the StringTheory version your code is built with, if it is older
!                          than 3.90 (--stversion=3.84). A group marked NEEDST(3.90) is not
!                          run, even when asked for by name, and inLine is not written to
!                          walk backwards. Without it, 3.90 or later is assumed.
!     --ignoremarks        do not guard a StringTheory's base64, encoding and gzip marks (see
!                          README: it changes code that encodes a value, copies it and reads
!                          the copy's marks). Also SETTINGS ignoremarks=on in a profile.
!   the rule workbench:
!     --userrules=<file>   load a USER rulefile (plain DSL, GROUP blocks) APPENDED
!                          after the shipped rule file, before the stylefile; user
!                          ruleIds are offset by 500000 (rule 500096 = U96 in the
!                          workbench); default OFF = batch is byte-identical without it
!   every report carries the RESOLVED selection table - a report without its
!   selection is an unrepeatable experiment
!   output naming (inserted before the extension, so out\reindent.clw -> out\reindent<suffix>.clw):
!     --outsuffix=<s>  literal suffix, e.g. --outsuffix=Width2  -> reindentWidth2.clw. With the
!                      source directory as <outdir> the copies land beside the originals; a copy
!                      whose name is already a file there is refused before anything is written.
!     --outstamp       append ' on yyyymmdd at hhmmssth' (th = hundredths), e.g.
!                      reindent on 20260713 at 14302547.clw  (both combine: literal then stamp)
!     --nobanner       no "Processed by VitTransform ..." line at the top of each output file
!   cross-file type resolution (opt-in - needed for self.* dotted receivers):
!     --root=<dir>     Clarion install dir (%ROOT%, e.g. c:\Clarion11) - PRESENCE enables include expansion
!     --red=<file>     .red redirection file (default: the newest Clarion*.red in the working dir,
!                      else the newest in <root>\bin - its normal home)
!     --config=<name>  %CONFIGURATION% macro (default Release)
!     --define=<flags> extra project flags for the OMIT/COMPILE reading, comma-separated, each
!                      NAME or NAME=value (repeat the switch to add more). _C110_ and the like are
!                      already seeded from the .red file version, and _WIDTH32_ is 1 from Clarion 6
!                      on; use this for what a .red cannot tell, such as _Unicode_ or _ABCDllMode_,
!                      which read 0 without it. A flag named here wins over a seeded one, so
!                      _WIDTH32_=0 turns that one off.
!     --thorough       expand includes WITHOUT typing --root: %ROOT% is auto-discovered from the
!                      Windows uninstall registry (one install = used silently; several = you pick
!                      from a dialog - pass --root explicitly for unattended runs; --root overrides)
!     --receiver=<mode>  what to do when a Check* builtin's receiver cannot be resolved:
!                      assume = rewrite it as a StringTheory, check = refuse it if any use of
!                      it in scope is not a StringTheory method (DEFAULT), strict = refuse it
!                      unless it provably resolves. See README D.4.
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
    Say(STRING pMsg)                                        ! message() UNLESS --batch, in which case append to vt-batch.log. A modal box is fatal to an unattended run: the
                                                            !   autonomous watcher has nobody to click it and waits forever. Everything routed through here is something you MUST
                                                            !   see - a refusal to load, a save that failed - so in batch it goes to a file rather than being suppressed.
    NumArg(STRING pTxt, STRING pWhich, BYTE pZeroOk=0),LONG ! validate an all-digit numeric switch value (halt on bad). pZeroOk=1 for switches where 0 is a real setting, not a mistake.
    MakeDirs(STRING pPath)                                  ! mkdir every intermediate level of pPath
    DiscoverRoot(*STRING pVerName, BYTE pQuiet=0),STRING    ! newest installed Clarion root from the uninstall registry ('' = none found); pQuiet = never ask, take the newest
    FindNewestRed(STRING pDir),STRING                       ! default .red discovery: newest Clarion*.red in pDir ('' = none)
    MODULE('C Library')
      mkdir(*CSTRING),SIGNED,PROC,RAW,NAME('_mkdir')
    END
    ! SetErrorMode: a drive probe on an empty removable drive must not raise the OS "no disk"
    ! dialog on an unattended run - see DiscoverRoot. Its answer, the previous mode, is not wanted.
    MODULE('Windows')
      SetErrMode(ULONG m),PASCAL,NAME('SetErrorMode')
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
badSwitch  StringTheory                                     ! the unrecognised switch, if any - the run is refused, not warned about
okOnly     LONG                                             ! --only= names a rule that actually exists
okSkip     LONG                                             ! --skip= ditto
onlyArg    StringTheory                                     ! --only= as TYPED: a rule NAME, or an id (its line number)
skipArg    StringTheory                                     ! --skip= ditto
onlyWhat   StringTheory                                     ! the rule each one resolved to, echoed so a stale id is
skipWhat   StringTheory                                     !   caught by eye instead of quietly selecting the wrong rule
onlyByName BYTE                                             ! --only= was given a name rather than an id
skipByName BYTE                                             ! --skip= ditto
hit        BYTE,AUTO                                        ! this row is the one asked for
onlyHits   LONG                                             ! how many rules answered to it - more than one is
skipHits   LONG                                             !   refused, because picking the first would be a guess
onlyLines  StringTheory                                     ! their line numbers, to name the alternatives in the
skipLines  StringTheory                                     !   refusal rather than leave the user hunting
extraPos   StringTheory                                     ! a 4th positional, if any - now always half of an unquoted pathlit
badGrp     StringTheory                                     ! --group=/--nogroup= names the rule file does not declare
grpList    StringTheory                                     ! the list CheckGroupNames is walking
knownGrp   StringTheory                                     ! every group the rule file DOES declare, for the refusal message
badBi      StringTheory                                     ! BUILTIN lines naming a builtin this engine does not have
grpWhich   STRING(12)                                       ! which switch the current list came from
redArg     StringTheory                                     ! --red= value
defArg     StringTheory                                     ! --define= compile-time flags (repeats append); seeds the preprocessor under --thorough
setBody    StringTheory                                     ! the applied style's profile SETTINGS body
cmdLineU   StringTheory                                     ! the command line, upper-cased, for the command-line-wins test
kvSt       StringTheory                                     ! one key=value token from a SETTINGS line
setApplied StringTheory                                     ! the profile settings that took effect (for the report)
setNotes   StringTheory                                     ! and what the profile loop has to SAY - an item set aside. NOT outSt: that is freed before the report is written
setBad     StringTheory                                     ! the profile SETTINGS values the engine refused - they stop the run
setKeyS    STRING(40)                                       ! a SETTINGS key
setValS    STRING(64)                                       !   and its value
setErrS    STRING(200)                                      ! ApplyCmtSetting error text
setX       LONG,AUTO
setEq      LONG,AUTO
rootArg    StringTheory                                     ! --root= value (non-blank enables include expansion)
cfgArg     StringTheory                                     ! --config= value
sufArg     StringTheory                                     ! --outsuffix= literal suffix (inserted before the extension)
styleArg   StringTheory                                     ! --style= name
styleFn    StringTheory                                     ! --stylefile= path
grpArg     StringTheory                                     ! --group= comma list (repeats append)
nogrpArg   StringTheory                                     ! --nogroup= comma list (repeats append)
userFn     StringTheory                                     ! --userrules= path (user rulefile, append-loaded)
ruleTxt    StringTheory                                     ! the rule file as entered - the first thing after "using" on the Processed-by line
swTxt      StringTheory                                     ! every --switch as entered, in order - the rest of that line
swSeen     StringTheory                                     ! each --name=value switch that takes ONE value, as last given
swTwice    StringTheory                                     ! a report line for each one given again with another value
uGrps      LONG                                             ! groups the user rulefile added (report header)
uRules     LONG                                             ! rules the user rulefile added (hand + auto)
uRuleErrs  LONG                                             ! errors in the user rulefile - counted only when the run is refused (ShippedAlone)
styErrs    LONG                                             ! errors in the --stylefile= file, all found as it loads: a profile's lint finds warnings only
lintErrs   LONG,AUTO                                        ! errors once the rule files and the stylefile are loaded and linted
wantStamp  BYTE                                             ! --outstamp: append ' on yyyymmdd at hhmmssth'
wantSumm   BYTE                                             ! --summary shows the end-of-run message box. OFF by default so a bat of many runs goes
                                                            !   straight through unattended - every number in that box is in the report file anyway
batchMode  BYTE                                             ! --batch - never open a modal box; the autonomous watcher has nobody to click it
wantDump   BYTE                                             ! --dumptokens writes the EXPANDED token stream to disk with its level marks in column 1, and reports every '+' that never
                                                            !   gets a '-'. VitTokenize.DumpTokens existed already, but its call sites were both commented out, so nothing could
                                                            !   reach it. This is how you find an unbalanced `exptk level census` instead of guessing at it from keyword counts.
dumpIx     LONG,AUTO                                        !   (the census tells you a level is lost; this tells you WHICH token lost it)
dumpMt     LONG,AUTO
dumpLn     LONG,AUTO
dumpTx     STRING(128)
dumpNm     StringTheory                                     ! the dump is named after the SOURCE, so diagnosing three files in a row does not leave only the last one on disk
dumpSrc    StringTheory                                     ! the file the dump actually describes. With a WILDCARD sourcespec, exptk holds the LAST matched file's stream - naming the dump after the
                                                            !   spec built `*.clw.tokens.txt`, an illegal Windows name, and the save failed in silence while the report claimed the dump was on disk
dumpBad    LONG
thorough   BYTE                                             ! --thorough = include expansion with registry-discovered %ROOT%
noThorough BYTE                                             ! --nothorough - the explicit no. Beats a rule file's THOROUGH directive AND an explicit --root=, because it is the escape hatch
verNm      STRING(24)                                       ! which Clarion the registry scan found (for the report)
redVer     LONG                                             ! the version the .red file name gives (for the report)
redVerTx   STRING(28)                                       !   and as the report shows it
stampSt    StringTheory
csecs      LONG,AUTO                                        ! clock() = centiseconds since midnight
totSec     LONG,AUTO
sHH        LONG,AUTO
sMM        LONG,AUTO
sSS        LONG,AUTO
sTH        LONG,AUTO                                        ! hundredths of a second
outFn      StringTheory
FilesQ   QUEUE(File:queue),PRE(FQ)
         END
errs       LONG,AUTO
warns      LONG,AUTO
x          LONG
idx        LONG
posNo      LONG
isGolden   LONG
exitRc     BYTE                                             ! a failure the run SURVIVES (a save that failed, golden fails) - every exit path checks it and halts 1. Hard refusals halt(1) on the spot.
dirProbe   StringTheory                                     ! same-directory guard: probe filename written into <outdir>...
probeSt    StringTheory                                     !   ...and looked for in the SOURCE directory (see the guard below)
sufSameDir BYTE                                             ! that probe said yes while a suffix is in force: the copies land beside the originals, so every output name is checked
sufClash   StringTheory                                     !   and these are the output names that are already a file there, one per line
collFn     StringTheory                                     !   the source being checked
collOut    StringTheory                                     !   and the name its copy would take
swEq       LONG,AUTO                                        ! the '=' of a --name=value switch - the name in front of it is folded to lower case, the value is not
swLow      StringTheory                                     !   the switch with its name folded
outDirC    CSTRING(261),AUTO
pathish    BYTE                                             ! the unexpected 4th argument looks like half of an unquoted path, not half of a comma list
realFiles  LONG                                             ! wildcard rows that were actual FILES - the exit contract counts these
srcDir     StringTheory                                     ! the source spec's directory, its last separator kept: src\  \  C:  or blank
! the switches that take a value after their '=' - one with nothing there is told so; any other name is unknown
vtValueSw  EQUATE(' cmtbar= cmtcont= cmtend= cmtfloor= cmtgap= cmtinner= cmtkeep= cmtlimit= cmtop= cmtoutlier= cmtreach= cmtrun= cmtslack= cmtsplit= cmtwrap= colseq= config= contindent= decloutlier= define= ')
vtValueSw2 EQUATE(' dispatch= group= kwcapitalise= kwcapitalize= kwlower= kwtitle= kwupper= nogroup= only= outsuffix= passes= receiver= red= root= skip= stversion= style= stylefile= userrules= width= ')

  CODE
  ! ---- --batch is read FIRST, in a pass of its own, BEFORE anything can refuse ----
  ! It decides whether a refusal may open a modal box at all, and it is habitually written
  ! LAST. Reading it in argument order meant every refusal raised WHILE parsing opened a box
  ! on exactly the kind of run that exists because nobody is there to click it: a bad
  ! --only=/--passes=/--width= value (NumArg halts on the spot), an unknown switch, or a 4th
  ! positional - and those last two BREAK the loop, so a --batch after them was never read at
  ! all. MEASURED: `VitTransform rules.txt probe\With Space\sp.clw out --batch`.
  param.setValue(command())
  param.removeByte(34)                                                                   ! a quoted "--batch" is still --batch, and  ! remove all <double quote>
  param.replaceByte(9,32)                                                                !   a tab still separates arguments  ! replace all <tab> with <space>
  param.lower()                                                                          !   and --BATCH is --batch: a switch name is read in any case, here as in the loop below
  if param.FindChars(' --batch ') or                                                     |
     param.EndsWith(' --batch')   or                                                     | in case there is no space at the end
     param.StartsWith('--batch ')                                                        ! command() should add space at front so this is "just in case"
    batchMode = true
  end
  param.setValue(command())                                                              ! THE REAL LINE BACK. The pre-scan above flattens quotes and tabs to read ONE switch out of the line;
                                                                                         !   the split below needs the quoting intact, because that is what holds a spaced path together.
  param.replaceByte(9,32)                                                                ! a tab separates arguments here too - no file name can hold one
  param.split(' ','"','"',,st:clip,st:left)
  param.RemoveLines()
  loop x = 1 to param.records()
    param.SetValueFromLine(x)
    param.removeByte(34)                                                                 ! note: do it here NOT removeQuotes on the split as that only removes
                                                                                         !   first/last chars whereas ours can be embedded  ! remove all <double quote>
  ! ---- command line: positionals + --switches, in any order ----
    if param._DataEnd > 1 and param.valuePtr[1 : 2] = '--'
      if param._DataEnd = 2                                                              ! a bare '--' names no switch, and
        badSwitch.setValue(param)                                                        !   [3 : 2] slices BACKWARDS - Clarion
        break                                                                            !   does not bounds-check a slice
      end
      ! every switch, as entered, for the Processed-by line - a value with a space gets its quotes back
      if param.FindByte(32)
        swTxt.append(' "' & param.getValue() & '"')
      else
        swTxt.append(' ' & param.getValue())
      end
      ! THE NAME OF A SWITCH IS READ IN ANY CASE - --Dry-Run is --dry-run, and --BATCH is the
      ! one that matters, because a refusal it was meant to keep off the screen would otherwise
      ! be the box it opens. The VALUE after an '=' keeps the case it was typed in: a path, a
      ! suffix, a compile-time flag name.
      swEq = param.findByte(61)
      if swEq
        swLow.setValue(param.valuePtr[1 : swEq - 1])
        swLow.lower()
        swLow.append(param.valuePtr[swEq : param._DataEnd])
        param.setValue(swLow)
        do SwTwice
      else
        param.lower()
      end
      ! A BARE FLAG IS AN EXACT MATCH, so let CASE do the comparing. The '--' is already
      ! known by the time we are here, so the arms carry the name alone and there is no
      ! length to keep in step with the text beside it.
      case param.valuePtr[3 : param._DataEnd]                                            ! the '--' is known
      of 'dry-run'
        eng.dryRun = true
      of 'timing'
        eng.timing = true
      of 'postcheck'
        eng.rw.m.postCheck = true
      of 'verbose'
        eng.verbose = true
      of 'loose'
        eng.loose = true
      of 'thorough'                                                                      ! registry-discovered root
        thorough = true
      of 'nothorough'                                                                    ! and the way to turn it off again
        noThorough = true
      of 'ignoremarks'                                                                   ! the base64, encoding and gzip marks are the user's own risk
        eng.ignoreMarks = 1
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
      of 'batch'                                                                         ! also read in the pre-scan above
        batchMode = true
      of 'nobanner'
        eng.noBanner = true
      else
        ! ---- --name=VALUE. A prefix, so CASE cannot match it and these stay as tests. ----
        if param._DataEnd > 7 and param.valuePtr[3 : 7] = 'only='
          onlyArg.setValue(param.slice(8))                                               ! a NAME or an id - resolved once the rule file is loaded
        elsif param._DataEnd > 7 and param.valuePtr[3 : 7] = 'skip='
          skipArg.setValue(param.slice(8))
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'passes='
          eng.maxPasses = NumArg(param.slice(10), '--passes=')
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'cmtgap='                   ! spaces before a trailing comment
          eng.cmtGap = NumArg(param.slice(10), '--cmtgap=')
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'cmtlimit='
          eng.alignLimit = NumArg(param.slice(12), '--cmtlimit=', 1)
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'cmtslack='
          eng.alignSlack = NumArg(param.slice(12), '--cmtslack=', 1)
        elsif param._DataEnd > 13 and param.valuePtr[3 : 13] = 'cmtoutlier='
          eng.alignOutlier = NumArg(param.slice(14), '--cmtoutlier=', 1)
        elsif param._DataEnd > 14 and param.valuePtr[3 : 14] = 'decloutlier='
          eng.declOutlier = NumArg(param.slice(15), '--decloutlier=', 1)
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'kwupper='                ! keywords KeywordCase keeps UPPER whatever its style
          eng.kwUpper.append(',' & param.slice(11))
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'kwlower='
          eng.kwLower.append(',' & param.slice(11))
        elsif param._DataEnd > 15 and param.valuePtr[3 : 15] = 'kwcapitalise='
          eng.kwTitle.append(',' & param.slice(16))
        elsif param._DataEnd > 15 and param.valuePtr[3 : 15] = 'kwcapitalize='
          eng.kwTitle.append(',' & param.slice(16))
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'kwtitle='
          eng.kwTitle.append(',' & param.slice(11))
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'cmtwrap='
          eng.cmtWrap = NumArg(param.slice(11), '--cmtwrap=', 1)
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'cmtsplit='
          eng.cmtSplit = NumArg(param.slice(12), '--cmtsplit=', 1)
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'cmtreach='
          eng.cmtReach = NumArg(param.slice(12), '--cmtreach=', 1)
        elsif param._DataEnd > 12 and param.valuePtr[3 : 12] = 'stversion='
          if ~rl.IsStVersion(param.slice(13))
            Say('VitTransform: --stversion= expects a StringTheory version written as StringTheory:Version writes it, such as 3.84, got "' & param.slice(13) & '"')
            halt(1)
          end
          rl.stVersion = left(param.slice(13))
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'cmtinner='
          eng.cmtInner = NumArg(param.slice(12), '--cmtinner=', 1)                       ! 0 is a real setting: the inner rule is off
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'cmtrun='
          eng.cmtRun = NumArg(param.slice(10), '--cmtrun=', 1)
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'cmtfloor='
          case lower(param.slice(12))
          of 'near'      ; eng.cmtFloor = 0
          of 'commented' ; eng.cmtFloor = 1
          of 'all'       ; eng.cmtFloor = 2
          else
            Say('VitTransform: --cmtfloor= must be near, commented or all.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 13 and param.valuePtr[3 : 13] = 'contindent='
          case lower(param.slice(14))
          of 'indent'  ; eng.contBracket = 0
          of 'bracket' ; eng.contBracket = 1
          else
            Say('VitTransform: --contindent= must be indent or bracket.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'cmtkeep='
          case lower(param.slice(11))
          of 'off'     ; eng.cmtKeep = 0
          of 'aligned' ; eng.cmtKeep = 1
          else
            Say('VitTransform: --cmtkeep= must be off or aligned.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 8 and param.valuePtr[3 : 8] = 'cmtop='
          case lower(param.slice(9))
          of 'code' ; eng.cmtOpBar = 0
          of 'bar'  ; eng.cmtOpBar = 1
          else
            Say('VitTransform: --cmtop= must be code or bar.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'cmtend='
          case lower(param.slice(10))
          of 'take'  ; eng.cmtEndCount = 0
          of 'count' ; eng.cmtEndCount = 1
          else
            Say('VitTransform: --cmtend= must be take or count.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'dispatch='
          case lower(param.slice(12))
          of 'classic' ; eng.rw.dispatch = 0
          of 'grouped' ; eng.rw.dispatch = 1
          else
            Say('VitTransform: --dispatch= must be classic or grouped.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'colseq='
          case lower(param.slice(10))
          of 'standard' ; eng.colSeqCustom = 0
          of 'custom'   ; eng.colSeqCustom = 1
          else
            Say('VitTransform: --colseq= must be standard or custom.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'cmtbar='
          case lower(param.slice(10))
          of 'bar'     ; eng.cmtBarCmt = 0
          of 'comment' ; eng.cmtBarCmt = 1
          else
            Say('VitTransform: --cmtbar= must be bar or comment.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'cmtcont='
          case lower(param.slice(11))
          of 'indent' ; eng.cmtContNone = 0
          of 'none'   ; eng.cmtContNone = 1
          else
            Say('VitTransform: --cmtcont= must be indent or none.||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 8 and param.valuePtr[3 : 8] = 'width='                    ! line width for splitting
          eng.widthArg = NumArg(param.slice(9), '--width=', 1)                           ! 0 is legal here - see below
          if ~eng.widthArg
            eng.widthArg = -1                                                            ! --width=0 = never split (0 already means "not given")
          elsif eng.widthArg < 40
            Say('VitTransform: --width= must be 0 (never split) or at least 40.'                   & |
                '||A smaller limit would break almost every line, which is worse than a wide one.' & |
                '||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 11 and param.valuePtr[3 : 11] = 'receiver='               ! what to do about
          case lower(param.slice(12))                                                    !   a Check* receiver
          of 'assume' ; eng.recvMode = rm:assume                                         !   the tool cannot
          of 'check'  ; eng.recvMode = rm:check                                          !   resolve
          of 'strict' ; eng.recvMode = rm:strict
          else
            Say('VitTransform: --receiver= must be assume, check or strict.'                            & |
                '||  assume  rewrite an unresolvable receiver as a StringTheory'                        & |
                '|  check   refuse it if any use of it in scope is not a StringTheory method (default)' & |
                '|  strict  refuse it unless it provably resolves - use with --thorough'                & |
                '||Nothing has been changed.')
            halt(1)
          end
        elsif param._DataEnd > 6 and param.valuePtr[3 : 6] = 'red='                      ! .red redirection file
          redArg.setValue(param.slice(7))
        elsif param._DataEnd > 7 and param.valuePtr[3 : 7] = 'root='                     ! %ROOT%, and it ENABLES include expansion
          rootArg.setValue(param.slice(8))
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'config='                   ! %CONFIGURATION% (Debug/Release)
          cfgArg.setValue(param.slice(10))
        elsif param._DataEnd > 9 and param.valuePtr[3 : 9] = 'define='                   ! compile-time flags the preprocessor seeds (_WIDTH32_, _ABCDllMode_ ...); repeats append
          if defArg._DataEnd then defArg.append(',').
          defArg.append(param.slice(10))
        elsif param._DataEnd > 12 and param.valuePtr[3 : 12] = 'outsuffix='              ! literal suffix before the extension
          sufArg.setValue(param.slice(13))
        elsif param._DataEnd > 12 and param.valuePtr[3 : 12] = 'stylefile='              ! user stylefile / profile file
          styleFn.setValue(param.slice(13))
        elsif param._DataEnd > 12 and param.valuePtr[3 : 12] = 'userrules='              ! user rulefile, appended to the shipped rules
          userFn.setValue(param.slice(13))
        elsif param._DataEnd > 8 and param.valuePtr[3 : 8] = 'style='                    ! apply a STYLE/profile by name
          styleArg.setValue(param.slice(9))
        elsif param._DataEnd > 8 and param.valuePtr[3 : 8] = 'group='                    ! select group(s); repeats append
          if grpArg._DataEnd then grpArg.append(',').
          grpArg.append(param.slice(9))
        elsif param._DataEnd > 10 and param.valuePtr[3 : 10] = 'nogroup='                ! deselect group(s); repeats append
          if nogrpArg._DataEnd then nogrpArg.append(',').
          nogrpArg.append(param.slice(11))
        elsif param.EndsWith('=') and instring(' ' & param.valuePtr[3 : param._DataEnd] & ' ', vtValueSw & vtValueSw2, 1, 1)
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
      if param.FindByte(32)
        ruleTxt.setValue('"' & param.getValue() & '"')
      else
        ruleTxt.setValue(param)
      end
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
  eng.bannerUsing.setValue(ruleTxt)                                                      ! the Processed-by line: the rule file, then the switches
  eng.bannerUsing.append(swTxt)
  if badSwitch._DataEnd
    Say('VitTransform: unknown switch ' & clip(badSwitch.getValue())                           & |
        '||Nothing has been changed. The full switch list is in README.md (Appendix B) and in' & |
        ' the usage header of vitTransform.clw.')
    halt(1)
  end
  if eng.cmtWrap and eng.cmtSplit
    ! ONE choice with two answers, so given both the run would silently take one of them.
    ! Name the two settings that disagree instead - a switch the user has typed is never ignored.
    Say('VitTransform: --cmtwrap= and --cmtsplit= cannot both be given.'           &     |
        '||Both set the width a trailing comment is cut at. --cmtwrap= also joins' &     |
        ' rows that fit back together; --cmtsplit= only cuts.'                     &     |
        '||Nothing has been changed.')
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
  ! A SWITCH TYPED WITH ONE DASH OR A SLASH IS NOT AN OUTPUT DIRECTORY. Only a word that starts
  ! with two dashes is read as a switch, so -dry-run or /batch in third place would be taken as
  ! the <outdir>, and the run would be a REAL one, writing into a new folder of that name. It is
  ! refused as an unknown switch is. A folder that already exists is still taken as named.
  if eng.outDir and (eng.outDir[1] = '-' or eng.outDir[1] = '/') and ~exists(clip(eng.outDir))
    Say('VitTransform: unknown switch ' & clip(eng.outDir)                                  & |
        '||A switch starts with two dashes: --dry-run, --batch. A third argument that'      & |
        ' starts with - or / is taken as the <<outdir> only when that folder already'       & |
        ' exists. For a new one, write .\-name, or \name for a folder at the root.'         & |
        '||Nothing has been changed. The full switch list is in README.md (Appendix B) and' & |
        ' in the usage header of vitTransform.clw.')
    halt(1)
  end
  if ~fn._DataEnd
    ! REFUSE rather than defaulting. Falling back to a rule file of our own choosing means the
    ! next thing the user sees is a load failure naming a file they have never heard of.
    ! A tool other people run must never quietly choose its own input.
    Say('VitTransform: no rule file given.'                                              & |
        '||Usage:  VitTransform <<rulefile> <<source> [<<outdir>] [switches]'            & |
        '||The rule file that ships with VitTransform is  vitrules.txt'                  & |
        '||  VitTransform vitrules.txt src\*.clw out --dry-run    see what would change' & |
        '|  VitTransform vitrules.txt src\*.clw out              write into out\'        & |
        '||Useful groups:  --group=analysis   --group=deadcode   --style=readable'       & |
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
  csecs  = clock()                                                                       ! centiseconds since midnight
  totSec = int(csecs / 100)
  sTH    = csecs - totSec * 100                                                          ! hundredths (00..99)
  sHH    = int(totSec / 3600)
  totSec = totSec - sHH * 3600
  sMM    = int(totSec / 60)
  sSS    = totSec - sMM * 60
  stampSt.setValue(' on ' & format(year(today()), @n04) & format(month(today()), @n02) & format(day(today()), @n02) & |
                   ' at ' & format(sHH, @n02) & format(sMM, @n02) & format(sSS, @n02) & format(sTH, @n02))
  eng.stamp = stampSt.getValue()                                                         ! in-place backups use this

  ! golden files are detected by their first non-blank, non-comment line
  probe.LineEndings(st:unix)
  probe.split('<10>')
  loop x = 1 to probe.records()
    line.setValue(probe.getLine(x))
    line.trim()
    if ~line._DataEnd then cycle.
    case val(line.valuePtr[1])
    of 33 orof 124                                                                       ! '!' orof '|'                  ! comment or blank continuation line
      cycle
    end
    if line.startsWith('=== case') then isGolden = true.
    break
  end

  if isGolden
    ! ---- golden test mode ----
    gr.RunFile(fn.getValue(), outSt)
    outFn.setValue(fn)
    outFn.append(clip(stampSt.getValue()) & '.result.txt')                               ! date-time stamp so repeated golden runs keep separate results
    if not outSt.SaveFile(outFn.getValue())
      Say('Could not save results to ' & outFn.getValue() & '||' & outSt.LastError)
      exitRc = 1
    end
    if wantSumm                                                                          ! --summary only
      Say('VitMatch golden: ' & clip(fn.getValue()) &                                    |
              '|Cases: ' & gr.caseCount             &                                    |
              '|Pass:  ' & gr.passCount             &                                    |
              '|Fail:  ' & gr.failCount             &                                    |
              '||Results in ' & clip(outFn.getValue()))
    end
    if gr.failCount then exitRc = 1.                                                     ! failing goldens must reach the calling script
    if exitRc then halt(1).
    return
  end

  ! ---- rule file: lint + IR dump, always produced ----
  rl.LoadFile(fn.getValue())
  if userFn._DataEnd                                                                     ! user rulefile appends AFTER the shipped file,
    uGrps  = records(rl.groups)                                                          !        BEFORE the stylefile
    uRules = records(rl.rules)
    rl.LoadUserRules(userFn.getValue())
    uGrps  = records(rl.groups) - uGrps
    uRules = records(rl.rules) - uRules
  end
  if styleFn._DataEnd                                                                    ! profiles layer over the rule file's shipped styles
    styErrs = rl.LoadStyleFile(styleFn.getValue())
  end
  lintErrs = rl.Lint()
  rl.Resolve(styleArg.getValue(), grpArg.getValue(), nogrpArg.getValue())                ! THE resolver - also validates --style=
  ! ---- a profile SETTINGS line for the applied style: apply each alignment setting that a
  !      command-line switch did NOT give (the command line always wins)
  setBody.setValue(rl.SettingsFor(rl.appliedStyle))
  if setBody._DataEnd
    cmdLineU.setValue(upper(command()))
    setApplied.free()
    setBody.split(' ')
    loop setX = 1 to setBody.records()
      setBody.setValueFromLine(setX)
! #Removed as unnecessary:       kvSt.trim()
      if ~setBody._DataEnd then cycle.
      setEq = setBody.findByte(61)                                                       ! '='
      if setEq < 2 or setEq >= setBody._DataEnd                                          ! a key with no value slices BACKWARDS
        setNotes.append('[profile ' & clip(rl.appliedStyle) & ' SETTINGS: ' & setBody.getValue() & ' needs a value]<13,10>')
        cycle
      end
      setKeyS = setBody.valuePtr[1 : setEq - 1]
      setValS = setBody.valuePtr[setEq + 1 : setBody._DataEnd]
      if cmdLineU.findChars('--' & upper(clip(setKeyS)) & '=')                           ! given on the command line: it wins,
        setNotes.append('[profile ' & clip(rl.appliedStyle) & ' SETTINGS: ' & lower(clip(setKeyS)) & |   !   and the report says the profile's
                     ' set aside - the command line gives it]<13,10>')                   !   value was not the one used
        cycle
      end
      case upper(setKeyS)
      of 'CMTWRAP' orof 'CMTSPLIT'
        ! --cmtwrap= and --cmtsplit= are ONE choice with two answers, so an answer on the
        ! command line settles it. The profile does not then get to supply the other one and
        ! leave both in force: the command line wins here as it does for a key it names.
        if cmdLineU.findChars('--CMTWRAP=') or cmdLineU.findChars('--CMTSPLIT=')
          setNotes.append('[profile ' & clip(rl.appliedStyle) & ' SETTINGS: ' & lower(clip(setKeyS)) & |
                       ' set aside - the command line answers the same question with --cmtwrap= or --cmtsplit=]<13,10>')
          cycle
        end
      end
      if ~eng.ApplyCmtSetting(setKeyS, setValS, setErrS)
        setBad.append('|  ' & clip(setErrS))
      else
        setApplied.append(choose(setApplied._DataEnd = 0, '', ', ') & lower(clip(setKeyS)))
      end
    end
    if eng.cmtWrap and eng.cmtSplit
      ! The command-line guard for this pair runs BEFORE any profile is read. A SETTINGS body
      ! that names BOTH has nothing on the command line to settle it, so without this the run
      ! would take one of the two in silence - which is what that guard exists to prevent.
      Say('VitTransform: profile ' & clip(rl.appliedStyle) & ' sets both --cmtwrap= and'  & |
          ' --cmtsplit= in its SETTINGS line.'                                            & |
          '||Both set the width a trailing comment is cut at. --cmtwrap= also joins rows' & |
          ' that fit back together; --cmtsplit= only cuts. Give one, not both.'           & |
          '||Nothing has been changed.')
      halt(1)
    end
  end
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
      knownGrp.append(choose(knownGrp._DataEnd = 0, '', '|  ') & clip(rl.groups.name) &  |
                      choose(rl.groups.choiceName = '', '', '   (choice ' & clip(rl.groups.choiceName) & ')'))
    end
    Say('VitTransform: no such group in ' & clip(fn.getValue()) & '.' &                  |
        '||' & clip(badGrp.getValue())                                &                  |
        '||The groups this rule file actually declares are:'          &                  |
        '||  ' & clip(knownGrp.getValue())                            &                  |
        '||Nothing has been changed.')
    halt(1)
  end
  ! ---- --only= and --skip= take EITHER a rule NAME or a rule id.
  !      A NAME is the stable one: it is written on the rule with NAME(x) and it does not move.
  !      An id is the rule's LINE NUMBER in the rule file, so it moves whenever lines are added
  !      above it - and a moved id is the dangerous case, because it still matches SOMETHING and
  !      the wrong rule is then selected in silence. Names are optional and most rules have none,
  !      so ids stay supported; what is fixed here is the SILENCE. Whatever was asked for, the
  !      run says which rule it resolved to, so a stale id is caught by eye on the first run.
  if onlyArg._DataEnd or skipArg._DataEnd
    okOnly = choose(onlyArg._DataEnd = 0)                                                ! not asked for = nothing to check
    okSkip = choose(skipArg._DataEnd = 0)
    ! all digits = an id, anything else = a NAME. Decided ONCE, not per rule.
    onlyByName = choose(onlyArg._DataEnd <> 0 and onlyArg.IsAllDigits() = 0)
    skipByName = choose(skipArg._DataEnd <> 0 and skipArg.IsAllDigits() = 0)
    if onlyArg._DataEnd and ~onlyByName then eng.onlyId = onlyArg.getValue().
    if skipArg._DataEnd and ~skipByName then eng.skipId = skipArg.getValue().
    loop x = 1 to records(rl.rules)
      get(rl.rules, x)
      if errorcode() then break.
      ! keyed on "was it asked for", NOT on "have we found it" - stopping at the
      ! first match would leave onlyHits stuck at 1 and the ambiguity check below
      ! could never fire, which is precisely what it did until a probe asserted the
      ! exit code it was supposed to produce
      if onlyArg._DataEnd
        hit = 0
        if onlyByName
          if rl.rules.ruleName and upper(rl.rules.ruleName) = upper(onlyArg.getValue())
            hit = 1                                                                      ! an explicit NAME(x)
          elsif rl.rules.kind = vr:kindBuiltin and rl.rules.builtinName                  |
                and upper(rl.rules.builtinName) = upper(onlyArg.getValue())
            hit = 1                                                                      ! a builtin named by its own name.
          end                                                                            !   Still matched when it ALSO has a NAME(x): otherwise naming every Reindent line would make plain
                                                                                         !   --only=Reindent report "no such
                                                                                         !   rule", when the useful answer is
                                                                                         !   the list of names to choose from
        elsif rl.rules.ruleId = eng.onlyId
          hit = 1
        end
        if hit
          onlyHits += 1
          if onlyHits = 1                                                                ! first match wins; a SECOND one is refused below
            eng.onlyId = rl.rules.ruleId
            okOnly     = 1
            onlyWhat.setValue('rule ' & rl.rules.ruleId)
            if rl.rules.ruleName then onlyWhat.append(' ' & clip(rl.rules.ruleName)).
            if not rl.rules.srcText &= NULL then onlyWhat.append(': ' & clip(rl.rules.srcText)).
          end
          onlyLines.append(choose(onlyLines._DataEnd = 0, '', ', ') & rl.rules.ruleId &  |
                           choose(rl.rules.ruleName <> '', ' (' & clip(rl.rules.ruleName) & ')', ''))
        end
      end
      if skipArg._DataEnd                                                                ! see the --only= twin above
        hit = 0
        if skipByName
          if rl.rules.ruleName and upper(rl.rules.ruleName) = upper(skipArg.getValue())
            hit = 1
          elsif rl.rules.kind = vr:kindBuiltin and rl.rules.builtinName                  |
                and upper(rl.rules.builtinName) = upper(skipArg.getValue())
            hit = 1                                                                      ! see the --only= twin above
          end
        elsif rl.rules.ruleId = eng.skipId
          hit = 1
        end
        if hit
          skipHits += 1
          if skipHits = 1
            eng.skipId = rl.rules.ruleId
            okSkip     = 1
            skipWhat.setValue('rule ' & rl.rules.ruleId)
            if rl.rules.ruleName then skipWhat.append(' ' & clip(rl.rules.ruleName)).
            if not rl.rules.srcText &= NULL then skipWhat.append(': ' & clip(rl.rules.srcText)).
          end
          skipLines.append(choose(skipLines._DataEnd = 0, '', ', ') & rl.rules.ruleId &  |
                           choose(rl.rules.ruleName <> '', ' (' & clip(rl.rules.ruleName) & ')', ''))
        end
      end
    end
    ! A builtin's own name identifies it only where it is listed ONCE. Reindent,
    ! KeywordCase and BlockEndStyle appear several times with different settings, so
    ! the name picks out a GROUP of lines, not a line. Choosing the first would be a
    ! guess dressed up as an answer - say so instead, and name the alternatives.
    if onlyHits > 1 or skipHits > 1
      Say('VitTransform: that name is not enough to pick one rule.'                           & |
          choose(onlyHits > 1, '||  --only=' & onlyArg.getValue() & ' matches ' & onlyHits    & |
                 ' rules, at lines ' & onlyLines.getValue(), '')                              & |
          choose(skipHits > 1, '||  --skip=' & skipArg.getValue() & ' matches ' & skipHits    & |
                 ' rules, at lines ' & skipLines.getValue(), '')                              & |
          '||A builtin is named by its own name only where it is listed once. This one is'    & |
          ' listed several times with different settings. Use the LINE NUMBER of the one you' & |
          ' mean, or give that line a name of its own with NAME(x) and use that.'             & |
          '||Nothing has been changed.')
      halt(1)
    end
    if ~okOnly or ~okSkip
      Say('VitTransform: no rule in ' & clip(fn.getValue()) & ' answers to that.'              & |
          choose(okOnly = 0, '||  --only=' & onlyArg.getValue(), '')                           & |
          choose(okSkip = 0, '||  --skip=' & skipArg.getValue(), '')                           & |
          '||Give a rule NAME - written on the rule as NAME(x) - or a rule id. A BUILTIN is'   & |
          ' also named by its own name, so --only=UnreachableCode works without naming it.'    & |
          ' An id is the rule''s LINE NUMBER in the rule file, so ids move whenever lines are' & |
          ' added above them. Run the rule file on its own (VitTransform <<rulefile>) to dump' & |
          ' every rule with its current id and name.'                                          & |
          '||Nothing has been changed.')
      halt(1)
    end
    ! --only= keeps one rule alone and --skip= leaves one out, so the two naming the SAME rule
    ! leave nothing to run. One choice with two answers is refused, as --cmtwrap= with
    ! --cmtsplit= is and --in-place with an <outdir> is: a switch the user has typed is never
    ! passed over in silence.
    if onlyArg._DataEnd and skipArg._DataEnd and eng.onlyId = eng.skipId
      Say('VitTransform: --only=' & onlyArg.getValue() & ' and --skip=' & skipArg.getValue() & |
          ' both name rule ' & eng.onlyId & '.'                                              & |
          '||--only= runs that one rule alone and --skip= leaves it out, so together they'   & |
          ' would run nothing. Give one of them, not both.'                                  & |
          '||Nothing has been changed.')
      halt(1)
    end
    ! the echo itself is appended further down, AFTER outSt.free() - appending it here
    ! would put it in a buffer that is emptied before anything is written, and a message
    ! nobody ever sees is the same as no message at all
  end
  ! ---- a BUILTIN line naming a builtin this engine does not have is a rule-file ERROR, and
  !      the run is refused. Skipped instead, a misspelt name - or one a later version no
  !      longer has - does none of the work the line asked for, and the run still finishes 0.
  !      The refusal comes after the IR dump is written, so the dump carries the error too.
  badBi.free()
  eng.CheckBuiltinNames(rl, badBi)
  errs  = rl.ErrorCount()
  warns = rl.WarnCount()

  rl._List(outSt)
  outFn.setValue(fn)
  outFn.append(clip(stampSt.getValue()) & '.ir.txt')                                     ! date-time stamp so repeated lint/IR runs keep separate dumps
  if not outSt.SaveFile(outFn.getValue())
    Say('Could not save IR dump to ' & outFn.getValue() & '||' & outSt.LastError)
    exitRc = 1
  end
  ! A VALUE THE ENGINE REFUSES STOPS THE RUN, as a blank one does (ruled 17 Sep 2026). The
  ! setting WAS asked for: putting the default in its place lays the code out differently from
  ! the profile, and a line in the report is the only sign - the same answer the switch itself
  ! gets on the command line. It comes after the IR dump is written, which lists any value the
  ! rule-file loader itself refused.
  if setBad._DataEnd
    Say('VitTransform: profile ' & clip(rl.appliedStyle) & ' has a SETTINGS value this run' & |
        ' cannot use:|' & setBad.getValue()                                                 & |
        '||Correct the value on its SETTINGS line, or take the item out.'                   & |
        '||Nothing has been changed.')
    halt(1)
  end
  if badBi._DataEnd
    Say('VitTransform: no such builtin in ' & clip(fn.getValue()) & '.' &                |
        '||' & clip(badBi.getValue())                                   &                |
        '||The builtins this version of VitTransform has are:'          &                |
        '||  ' & eng.BuiltinNames()                                     &                |
        '||Nothing has been changed.')
    halt(1)
  end

  if ~srcSpec._DataEnd
    if wantSumm                                                                          ! --summary only
      Say('VitRules: parsed ' & clip(fn.getValue()) &                                    |
              '|Metavars: ' & records(rl.metaVars)  &                                    |
              '|Rules:    ' & records(rl.rules)     &                                    |
              '|Errors:   ' & errs                  &                                    |
              '|Warnings: ' & warns                 &                                    |
              '||IR dump written to ' & clip(outFn.getValue()))
    end
    if errs then exitRc = 1.                                                             ! lint mode: rule-file errors ARE the result
    if exitRc then halt(1).
    return
  end

  ! EACH ERROR IS COUNTED AGAINST THE FILE IT IS IN. The stylefile's errors are all found as it
  ! loads. The --userrules= file's are found as it loads AND by the lint, which reads the rule
  ! files together - so the rule file is loaded and linted once more, on its own, as VitStyle
  ! does, and every error the two give together beyond that is the user file's: a line of it
  ! that does not parse, a lint error in one of its rules, or one of its rules that undoes a
  ! rule of the shipped file.
  if errs
    if userFn._DataEnd then do ShippedAlone.
    Say('VitTransform: ' & errs & ' error(s) in ' & clip(fn.getValue())                                                 & |
            choose(uRuleErrs > 0, ' (' & uRuleErrs & ' of them from --userrules= ' & clip(userFn.getValue()) & ')', '') & |
            choose(styErrs > 0, ' (' & styErrs & ' of them from --stylefile= ' & clip(styleFn.getValue()) & ')', '')    & |
            ' - transform aborted.'                                                                                     & |
            '||See ' & clip(outFn.getValue()))
    halt(1)
  end

  ! ---- in-place safety: never overwrite the originals silently ----
  ! No <outdir> means "transform in place".  That is destructive, so it must be asked
  ! for explicitly with --in-place (which then keeps a timestamped .bak of each changed file).
  if ~len(clip(eng.outDir)) and ~eng.inPlace and ~eng.dryRun                             ! --dry-run WRITES NOTHING, so there is nothing to refuse.
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
  ! --in-place AND an <outdir> name two different destinations. The copies went to the
  ! directory and the switch was passed over in silence - no .bak, which is what the switch
  ! promises. One choice with two answers is refused, as --cmtwrap= with --cmtsplit= is.
  if eng.inPlace and len(clip(eng.outDir)) and ~eng.dryRun
    Say('VitTransform: --in-place and an <<outdir> cannot both be given.'                                      & |
        '||--in-place overwrites the originals where they are and keeps a timestamped .bak of each;'           & |
        ' an <<outdir> writes copies there and keeps no .bak. Say which one you want:'                         & |
        '|      VitTransform ' & clip(fn.getValue()) & ' ' & clip(srcSpec.getValue()) & ' --in-place'          & |
        '|      VitTransform ' & clip(fn.getValue()) & ' ' & clip(srcSpec.getValue()) & ' ' & clip(eng.outDir) & |
        '||Nothing has been changed.')
    halt(1)
  end

  ! (date-time stamp already computed above, before golden/IR output naming)

  ! ---- assemble the output-filename suffix (--outsuffix= literal and/or --outstamp date-time) ----
  ! Inserted before the extension by VitEngine.OutName,
  ! e.g.  out\reindent.clw  ->  out\reindentWidth2 on 20260713 at 14302547.clw
  if sufArg._DataEnd
    eng.outSuffix.setValue(sufArg)                                                       ! literal part first
  end
  if wantStamp
    eng.outSuffix.append(stampSt)                                                        ! then the date-time stamp
  end

  ! ---- transform mode ----
  ! --dry-run writes nothing, so it makes no <outdir> either.
  if eng.outDir and ~eng.dryRun
    outDirC = clip(eng.outDir)
    MakeDirs(outDirC)                                                                    ! _mkdir makes ONE level only; create every intermediate dir so out\sub works
  end

  ! ---- the source spec's directory, with its last separator: src\ for src\*.clw, \ for \*.clw,
  !      C: for C:*.clw, and nothing for a name in the working directory. A listed name is joined
  !      to it as it stands. Cut BEFORE the separator and given a '\' back, a root is lost: \*.clw
  !      would give the bare name, and that opens the file of that name in the CURRENT directory.
  x = srcSpec._DataEnd
  loop while x and srcSpec.valuePtr[x] <> '\' and srcSpec.valuePtr[x] <> '/' and srcSpec.valuePtr[x] <> ':'
    x -= 1
  end
  srcDir.free()
  if x then srcDir.setValue(srcSpec.sub(1, x)).

  ! ---- same-directory safety, part 2: an <outdir> that IS the source directory overwrites
  !      the originals just as surely as a blank one, and the blank-outdir guard above cannot
  !      see it - '.', 'src', '..\src' and an absolute path can all name the source directory,
  !      and no string compare settles that. The filesystem answers it directly: write a
  !      uniquely-named probe file into <outdir> and ask whether the SOURCE directory now
  !      contains it. With --outsuffix/--outstamp in force a same-directory <outdir> is allowed -
  !      the suffixed name of a copy is never its own original's - but it can be a SIBLING's:
  !      Order.clw with the suffix Old is OrderOld.clw, which may well be a source of its own,
  !      and it would be overwritten with no .bak. So the probe still runs, and a yes under a
  !      suffix turns on the file-by-file check below the file list instead of refusing here.
  !      --dry-run writes nothing. An unwritable probe proves nothing either way, so that skips
  !      the check - the per-file save errors report it, and they exit 1.
  sufSameDir = 0
  if eng.outDir and ~eng.dryRun
    dirProbe.setValue('vt-dirprobe' & clip(stampSt.getValue()) & '.tmp')
    probeSt.setValue('VitTransform same-directory probe - delete freely')
    if probeSt.SaveFile(clip(eng.outDir) & '\' & dirProbe.getValue())
      param.setValue(srcDir)                                                             ! '' = the sources are in the working directory
      param.append(dirProbe)
      x = exists(param.getValue())
      remove(clip(eng.outDir) & '\' & dirProbe.getValue())
      if x and eng.outSuffix._DataEnd then sufSameDir = 1 ; x = 0.
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
  ! say WHICH rule --only=/--skip= landed on. A name cannot drift, but an id is a line
  ! number and moves whenever lines are added above it - and a moved id still matches
  ! SOMETHING, so without this the wrong rule is selected in silence.
  if onlyWhat._DataEnd then outSt.append('[--only=' & onlyArg.getValue() & ' -> ' & onlyWhat.getValue() & ']<13,10>').
  if skipWhat._DataEnd then outSt.append('[--skip=' & skipArg.getValue() & ' -> ' & skipWhat.getValue() & ']<13,10>').
  if swTwice._DataEnd then outSt.append(swTwice).
  do GrpBoth
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
    rootArg.free()                                                                       ! nothing left to expand
  elsif rl.wantThorough and ~thorough and ~rootArg._DataEnd
    thorough = true
    outSt.append('[THOROUGH: requested by the rule file, line ' & rl.thoroughLine &      |
                 ' - --nothorough turns it off]<13,10>')
  end
  if thorough and ~rootArg._DataEnd                                                      ! --thorough without --root -> discover %ROOT% from the registry
    rootArg.setValue(DiscoverRoot(verNm))
    if ~rootArg._DataEnd
      if rl.wantThorough                                                                 ! say WHO asked, or the user
        Say('VitTransform: the rule file asks for THOROUGH (line ' & rl.thoroughLine & ') but no installed Clarion was found - supply --root=<<dir>, or run with --nothorough')
      else                                                                               !   hunts for a switch they never typed
        Say('VitTransform: --thorough found no installed Clarion in the registry - supply --root=<<dir>')
      end
      halt(1)
    end
    outSt.append('[--thorough: %ROOT% auto-discovered (' & clip(verNm) & '): ' & clip(rootArg.getValue()) & ']<13,10>')
  end
  if ~noThorough and ~thorough and ~rootArg._DataEnd                                     ! NO SWITCH: read the includes when a Clarion can be
    rootArg.setValue(DiscoverRoot(verNm, 1))                                             !   found, so a name declared in one is known in a
    if rootArg._DataEnd                                                                  !   plain run. None found is a plain run, as before.
      eng.softIncludes = 1                                                               !   A header it cannot read is then a NOTE, not an
      outSt.append('[includes read: ' & clip(verNm) & ' found at ' &                     |
                   clip(rootArg.getValue()) & ' - --nothorough turns this off]<13,10>')  !   error: nobody asked for the includes
    end
  end
  if rootArg._DataEnd                                                                    ! --root supplied -> enable cross-file type resolution
    if ~redArg._DataEnd                                                                  ! default .red: working dir first, then <root>\bin (its normal home)
      redArg.setValue(FindNewestRed(''))
      if ~redArg._DataEnd
        redArg.setValue(FindNewestRed(clip(rootArg.getValue()) & '\bin'))
      end
      if ~redArg._DataEnd
        redArg.setValue('Clarion110.red')                                                ! last resort; the preprocessor reports if truly absent
      end
    end
    eng.SetupIncludes(redArg.getValue(), rootArg.getValue(), cfgArg.getValue(), defArg.getValue())
    redVer = eng.pp.RedVersion(redArg.getValue())
    if redVer then redVerTx = redVer else redVerTx = 'from the file it chains to'.
    outSt.append('[include expansion ON  root=' & clip(rootArg.getValue()) &             |
                 '  red=' & clip(redArg.getValue())                        &             |
                 '  version=' & clip(redVerTx)                             &             |
                 '  config=' & choose(~cfgArg._DataEnd, 'Release', clip(cfgArg.getValue())) & ']<13,10>')
  elsif redArg._DataEnd or cfgArg._DataEnd or defArg._DataEnd
    ! the three switches feed include expansion and nothing else. Given without it they did
    ! nothing, and the report did not say so - a run asked to read its OMIT/COMPILE regions
    ! with --define= and no --thorough left every typed rule blind, with exit 0 and no word.
    outSt.append('[' & choose(~redArg._DataEnd, '', '--red= ') & choose(~cfgArg._DataEnd, '', '--config= ')    & |
                 choose(~defArg._DataEnd, '', '--define= ') & 'given, but include expansion is OFF, so it was' & |
                 ' not used - it needs --thorough, --root=<<dir>, or a THOROUGH line in the rule file]<13,10>')
  end
  if userFn._DataEnd                                                                     ! the report names its user rulefile + what it
    outSt.append('[userrules: ' & clip(userFn.getValue()) & '  groups=' & uGrps  &       |
                 '  rules=' & uRules & '  errors=' & rl.userErrors & ']<13,10>')         !     added - part of the repeatability header
  end
  rl.SelectionTable(outSt)                                                               ! every report carries its resolved selection
  if setApplied._DataEnd then outSt.append('[selection] alignment from profile ' & clip(rl.appliedStyle) & ': ' & setApplied.getValue() & '<13,10>'). ! which SETTINGS too
  if eng.ignoreMarks then outSt.append('[selection] marks: IGNORED - the base64, encoding and gzip marks of a StringTheory are not guarded (--ignoremarks or SETTINGS ignoremarks=on)<13,10>'). ! every report says so
  if setNotes._DataEnd then outSt.append(setNotes).                                      ! and which the profile loop set aside or refused - kept apart from outSt, which was freed abovek effect
  if srcSpec.containsA('*?')                                                             ! '?' '*'
    DIRECTORY(FilesQ, srcSpec.getValue(), ff_:NORMAL)
    sort(FilesQ, +FQ:Name)
    param.setValue(srcDir)                                                               ! reusing param as the path prefix
    if eng.outSuffix._DataEnd and (eng.inPlace or sufSameDir) and ~eng.dryRun            ! the copies land beside the originals: no copy may take the name of a file already there
      loop idx = 1 to records(FilesQ)
        get(FilesQ, idx)
        if band(FQ:attrib, ff_:DIRECTORY) then cycle.
        collFn.setValue(FQ:Name, st:clip)
        if param._DataEnd then collFn.prepend(param.getValue()).
        do SufCollide
      end
      do SufRefuse
    end
    loop idx = 1 to records(FilesQ)
      get(FilesQ, idx)
      if band(FQ:attrib, ff_:DIRECTORY) then cycle.                                      ! a subfolder matching src\* is not a source - the same filter the two sibling DIRECTORY sites apply
      realFiles += 1
      if param._DataEnd
        FQ:Name = param.getValue() & FQ:Name
      end
      eng.TransformFile(clip(FQ:Name), outSt)
      if wantDump then dumpSrc.setValue(clip(FQ:Name)).                                  ! the stream exptk will still hold at the dump
    end
    if ~realFiles                                                                        ! rows are not files: a queue holding only subfolders still
      outSt.append('no files matched ' & srcSpec.getValue() & '<13,10>')                 !   transformed nothing
      eng.loadErrors += 1                                                                ! a wildcard that reads NOTHING did not do what it was told:
    end                                                                                  !   count it NOT LOADED so the run exits 1 - a watched sweep that transforms nothing must not report success
  else
    if eng.outSuffix._DataEnd and (eng.inPlace or sufSameDir) and ~eng.dryRun            ! the one file, the same check
      collFn.setValue(srcSpec)
      do SufCollide
      do SufRefuse
    end
    eng.TransformFile(srcSpec.getValue(), outSt)
    if wantDump then dumpSrc.setValue(srcSpec).
  end
  totTmr.Stop()
  ! The progress file is for watching a run that is still going. A run that has finished takes
  ! it away, so a folder does not gather one per run; a run that stops part way leaves it, and
  ! its last line says where.
  if eng.progressFn then remove(clip(eng.progressFn)).

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
      dumpNm.setValue(probe.FileNameOnly(dumpSrc.getValue(), true))                      ! the LAST transformed file - what exptk holds
      dumpNm.append('.tokens.txt')
      if exists(dumpNm.getValue()) then remove(dumpNm.getValue()).                       ! so the exists() below can only be THIS run
      eng.exptk.DumpTokens(dumpNm.getValue())
      if ~exists(dumpNm.getValue())                                                      ! DumpTokens reports failure only to the debug
        outSt.append('--dumptokens: FAILED to write ' & clip(dumpNm.getValue()) &        |                 ! viewer; the report must not
                     ' - the dump is NOT on disk<13,10>')                                !   claim output that is not there
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
      dumpMt  = 0                                                                        ! reused: paren depth
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
        get(eng.exptk.tokens, dumpIx)                                                    ! MatchLevel works from the CURRENT record, and moves the pointer
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
        get(eng.exptk.tokens, dumpIx)                                                    ! MatchLevel works from the CURRENT record, and moves the pointer
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
  outSt.append('files: ' & eng.filesDone & '  changed: ' & eng.filesChanged            & |
               '  changes: ' & eng.totalChanges & '  time: ' & clip(totTmr.Duration()) & |
               choose(eng.dryRun, '  [dry-run]', '')                                   & |
               choose(~eng.loadErrors, '', '  NOT LOADED: ' & eng.loadErrors)          & |
               choose(~eng.ppErrors,   '', '  includes not read in ' & eng.ppErrors & ' file(s)') & '<13,10>') ! on the summary line, not just buried above
  if eng.ppNotes
    outSt.append('includes not found for ' & eng.ppNotes & ' file(s) - see above<13,10>')
  end

  outFn.setValue(fn)
  outFn.append(clip(stampSt.getValue()) & '.report.txt')                                 ! date-time stamp (' on yyyymmdd at hhmmssth') so repeated runs with the same rulefile keep separate reports instead of overwriting
  if not outSt.SaveFile(outFn.getValue())
    Say('Could not save report to ' & outFn.getValue() & '||' & outSt.LastError)
    exitRc = 1
  end
  ! the end-of-run box is --summary only, so a bat of many runs goes straight through. It
  ! still opens when the run fails in a way that must be seen: a save that failed, a source
  ! never read, an include not found. --batch sends it to vt-batch.log instead.
  if wantSumm or eng.saveErrors > 0 or eng.ppErrors > 0 or eng.loadErrors > 0
    Say('VitTransform: ' & clip(srcSpec.getValue())                                              & |
            '|Files:   ' & eng.filesDone                                                         & |
            '|Changed: ' & eng.filesChanged                                                      & |
            '|Changes: ' & eng.totalChanges                                                      & |
            '|Time:    ' & clip(totTmr.Duration())                                               & |
            choose(eng.dryRun, '|DRY RUN - nothing written', '')                                 & |
            choose(eng.saveErrors > 0, '|SAVE ERRORS: ' & eng.saveErrors & ' - see report!', '') & |
            choose(eng.loadErrors > 0, '|NOT LOADED: ' & eng.loadErrors                          & |
                                       ' - a source that was asked for was never read. A'        & |
                                       ' wildcard that matches nothing is the usual cause,'      & |
                                       ' and a typo in the path is the usual reason.', '')       & |
            choose(eng.ppErrors > 0, '|Includes not read in ' & eng.ppErrors & ' file(s).'       & |
                                     '||In each of those files an INCLUDE was not found, or a'   & |
                                     ' directive could not be read. Your code was still changed' & |
                                     ' wherever the tool could be sure; a rule that needs the'   & |
                                     ' type of something declared in a missing file left those'  & |
                                     ' places alone rather than guess.'                          & |
                                     '||The report names each file and where the tool looked.'   & |
                                     ' Giving it your Clarion folder (--root=) or your'          & |
                                     ' redirection file (--red=) usually finds them.', '')       & |
            '||Report in ' & clip(outFn.getValue()))
  end
  if eng.saveErrors > 0 or                                                               |   ! output that was asked for is not on disk
     eng.loadErrors > 0 or                                                               |   ! a SOURCE that was asked for was never read - the run did not do what it was told
     eng.ppErrors > 0                                                                    ! a HEADER that was asked for was never found - the type registry is incomplete, so typed rules judged against part of the program
    exitRc = 1
  end
  if exitRc then halt(1).
  return

! ---- the suffixed copy of collFn lands in the source directory (a same-directory <outdir>, or
!      --in-place): a file ALREADY THERE under the copy's name would be overwritten, and the
!      run keeps no .bak for it - it is not the file being transformed. The name is the engine's
!      own answer, so the two cannot disagree. Each clash goes on sufClash's list. ----
SufCollide routine
  collOut.setValue(eng.OutName(collFn.getValue()))
  if ~collOut._DataEnd then exit.
  if exists(collOut.getValue())
    sufClash.append(choose(~sufClash._DataEnd, '', '|') & '      ' & collFn.getValue() & '  would be written as  ' & collOut.getValue())
  end

! ---- and the refusal, before a single file is transformed: a novice has to be told what the
!      clash is and what to do about it, and nothing may have been changed by then. ----
SufRefuse routine
  if ~sufClash._DataEnd then exit.
  Say('VitTransform: with --outsuffix=' & eng.outSuffix.getValue() & ' the copies are written beside the' & |
      ' originals, and a copy would take the name of a file that is already there:'                       & |
      '||' & sufClash.getValue()                                                                          & |
      '||That file is not the one being transformed, so no .bak would be kept of it: it would simply be'  & |
      ' overwritten. Rename or move it, choose another suffix, or write the copies to a directory of'     & |
      ' their own:'                                                                                       & |
      '|      VitTransform ' & clip(fn.getValue()) & ' ' & clip(srcSpec.getValue()) & ' out'              & |
      '||Nothing has been changed.')
  halt(1)

! ---- every name in one --group=/--nogroup= list, checked against the rule file.
!      The list arrives comma-joined, whether the switch repeated or the user wrote one
!      comma list - both reach here identically. ----
CheckGroupNames routine
  data
cgZ   long,auto
cgNm  StringTheory
  code
  if ~grpList._DataEnd then exit.
  grpList.split(',',,,,st:clip,st:left)
  loop cgZ = 1 to grpList.records()
    cgNm.setValue(grpList.getLine(cgZ))
! #Removed as unnecessary:     cgNm.trim()
    if ~cgNm._DataEnd then cycle.
    if rl.FindGroup(cgNm.getValue()) then cycle.
    badGrp.append(choose(badGrp._DataEnd = 0, '', '|') & '  ' & clip(grpWhich) & clip(cgNm.getValue()))
  end

! ---- A GROUP SWITCHED BOTH ON AND OFF. --nogroup= is applied after --group=, so a group the two
!      name ends off: a command line built from pieces can switch a group on and a later piece
!      switch it off again on purpose (ruled 4 Nov 2026). But the report says so and names both, as
!      it does for a one-value switch given again. Names are matched as the rule file reads them
!      (FindGroup), so two spellings of one group are caught, and each group is named once. Every
!      name is known by now - an unknown one has been refused. ----
GrpBoth routine
  data
gbOn   StringTheory
gbOff  StringTheory
gbSaid StringTheory
gbI    long,auto
gbJ    long,auto
gbG    long,auto
  code
  if ~grpArg._DataEnd or ~nogrpArg._DataEnd then exit.
  gbOn.setValue(grpArg)
  gbOn.split(',',,,,st:clip,st:left)
  gbOff.setValue(nogrpArg)
  gbOff.split(',',,,,st:clip,st:left)
  loop gbI = 1 to gbOn.records()
    gbG = rl.FindGroup(gbOn.getLine(gbI))
    if ~gbG or gbSaid.findChars(',' & gbG & ',') then cycle.
    loop gbJ = 1 to gbOff.records()
      if rl.FindGroup(gbOff.getLine(gbJ)) <> gbG then cycle.
      outSt.append('[--group=' & gbOn.getLine(gbI) & ' and --nogroup=' & gbOff.getLine(gbJ))
      outSt.append(' name the same group: it is off - --nogroup= is applied after --group=]<13,10>')
      gbSaid.append(',' & gbG & ',')
      break
    end
  end

! ---- the rule file loaded and linted again, ON ITS OWN, only to count its own errors. Every error
!      the rule files give together beyond those is the --userrules= file's, once the stylefile's
!      are taken off - and those are all the stylefile's own, found as it loaded. Asked only when a
!      run is refused, so a run that goes ahead never reads the rule file twice. ----
ShippedAlone routine
  data
saRl  VitRules
  code
  saRl.LoadFile(fn.getValue())
  uRuleErrs = lintErrs - styErrs - saRl.Lint()

! ---- A SWITCH THAT TAKES ONE VALUE, GIVEN AGAIN WITH ANOTHER. The last value is the one used:
!      a command line built from pieces can set a value and then set it again
!      on purpose. But the report says so and names both, so a run that used another width or
!      another rule from the one meant is seen. The same value twice says nothing. --define=,
!      --group=, --nogroup= and the --kw...= lists take every value they are given, so they are
!      not asked about. param holds the switch with its name in lower case. ----
SwTwice routine
  data
twNm  StringTheory
twLn  StringTheory
twK   long,auto
  code
  twNm.setValue(param.valuePtr[1 : swEq])
  case twNm.getValue()
  of '--define='       orof '--group='        orof '--nogroup=' orof '--kwupper=' orof '--kwlower='
    exit
  of '--kwcapitalise=' orof '--kwcapitalize=' orof '--kwtitle='
    exit
  end
  loop twK = 1 to swSeen.records()
    twLn.setValue(swSeen.getLine(twK))
    if ~twLn.startsWith(twNm.getValue()) then cycle.
    if ~twLn.equals(param)
      swTwice.append('[' & twNm.getValue() & ' given again: ' & twLn.getValue())
      swTwice.append(', then ' & param.getValue() & ' - the last one is used]<13,10>')
    end
    swSeen.setLine(twK, param.getValuePtr())
    exit
  end
  swSeen.addLine(param.getValue())

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
  lg.append(clip(left(format(today(),@d12))) & ' ' & clip(left(format(clock(),@T04))) & '  ')
  lg.append(clip(pMsg))
  lg.append('<13,10>')
  lg.SaveFile('vt-batch.log', true) ! APPEND, in one call: a read-append-rewrite lost lines when two runs overlapped

! ====================================================================================
! validate a numeric switch value (--passes=, --width= and the --cmt*= family). A
! non-numeric value would coerce silently to 0 (--passes=x -> a zero-pass no-op), so it
! is an all-digit check: a bad value aborts with a message rather than doing the wrong
! thing quietly. pWhich is the switch name for the diagnostic.
! pZeroOk=1 where 0 is a setting rather than a slip. Among them --width=0 never splits; --cmtlimit=0 and
! --cmtslack=0 are the shipped 90 and 60, --cmtoutlier=0 and --decloutlier=0 are off. A profile
! may set any of them to 0, so a switch must be able to give 0 as well, over a profile's value.
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
    case val(v[i])
    of 48 to 57                                                                ! '0' to '9'
    else
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
! #Removed as not used: c      string(1),auto
  code
  full = clip(left(pPath))
  n = len(full)
  if ~n then return.
  loop i = 1 to n
    if (full[i] = '\' or full[i] = '/') and i > 1
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
DiscoverRoot PROCEDURE(*STRING pVerName, BYTE pQuiet)
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
      if loc[len(clip(loc))] = '\' then loc = sub(loc, 1, len(clip(loc)) - 1).        ! strip a trailing backslash
      do AddCandidate
    end
  end

  ! ---- source 2: <drive>:\Clarion* filesystem probe (copied-not-installed trees) ----
  SetErrMode(1)                                                                       ! SEM_FAILCRITICALERRORS: a probe of an empty removable drive fails quietly instead of raising the OS "no disk" dialog, which would stall an unattended run
  drives = 'CDEF'
  loc = path()                                                                        ! current dir - its drive letter joins the probe list
  if len(clip(loc)) >= 2 and loc[2] = ':' then drives = clip(drives) & upper(loc[1]).
  loop dx = 1 to len(clip(drives))
    dl = drives[dx]
    if dx > 4 and instring(dl, drives[1 : 4], 1, 1) then cycle.                       ! current drive already in C..F
    free(DirQ)
    directory(DirQ, dl & ':\Clarion*', ff_:DIRECTORY)
    loop kx = 1 to records(DirQ)
      get(DirQ, kx)
      if ~band(dq:attrib, ff_:DIRECTORY) or                                           |   ! files named Clarion* are not roots
         dq:name = '.' or dq:name = '..'
        cycle
      end
      loc = dl & ':\' & dq:name
      do ParseDirVer                                                                  ! 'Clarion11' -> nm/ver for sorting + display
      do AddCandidate
    end
  end

  if records(FoundQ) = 0
    return ''
  end
  sort(FoundQ, -fq:ver)                                                               ! newest first, whatever the source
  if records(FoundQ) = 1                                                              ! exactly one -> use it silently
    get(FoundQ, 1)
    pVerName = fq:nm
    return clip(fq:loc)
  end
  ! several -> let the user choose (newest listed first). An unattended/batch run
  ! should pass --root explicitly; this modal is the interactive convenience path.
  if batchMode or pQuiet                                                              ! --batch must never open this picker - a watcher cannot answer it.
    get(FoundQ, 1)                                                                    !   Newest wins and the report says so, which is repeatable; hanging is not.
    pVerName = fq:nm
    if pQuiet then return clip(fq:loc).                                               ! a run with no switch names it on its report line instead
    Say('VitTransform --batch: several Clarion installations found - using the newest, ' & |
        clip(fq:nm) & ' at ' & clip(fq:loc) & '. Pass --root=<<dir> to choose.')
    return clip(fq:loc)
  end
  t.setValue('Several Clarion installations were found - which %ROOT% should --thorough use?')
  loop qx = 1 to records(FoundQ)
    get(FoundQ, qx)
    t.append('<13,10>' & clip(fq:nm) & '  =  ' & clip(fq:loc))
    btns = choose(qx = 1, fq:nm, clip(btns) & '|' & fq:nm)
  end
  pick = message(t.getValue(), 'VitTransform --thorough', ICON:Question, clip(btns))
  if pick < 1 or pick > records(FoundQ) then pick = 1.                                ! Esc/odd return -> newest
  get(FoundQ, pick)
  pVerName = fq:nm
  return clip(fq:loc)

! ---- validate loc as a real Clarion root, dedupe, and add to FoundQ ----
! (registry path arrives with gq:nm/gq:ver set; filesystem path with fq-style vnum via ParseDirVer)
AddCandidate routine
  if ~exists(clip(loc) & '\libsrc\win\equates.clw') and ~exists(clip(loc) & '\libsrc\equates.clw')
    exit                           ! not a usable root (no include library)
  end
  dup = 0
  loop pick = 1 to records(FoundQ) ! reuse pick as a scratch index (set fresh below)
    get(FoundQ, pick)
    if upper(fq:loc) = upper(loc) then dup = 1 ; break.
  end
  if dup then exit.
  fq:loc = loc
  fq:nm  = gq:nm                   ! registry: proper name; filesystem: ParseDirVer filled gq:nm/gq:ver
  fq:ver = gq:ver
  add(FoundQ)

! ---- derive a display name + sortable version from a Clarion* directory name ----
! 'Clarion11' -> ver 110; 'Clarion9.1' -> 91; 'Clarion' (no digits) -> 0. Fills gq:nm/gq:ver
! (the scratch fields AddCandidate reads) so both sources share one add path.
ParseDirVer routine
  vnum = 0 ; frac = 0
  loop px = 8 to len(clip(dq:name))  ! chars after 'Clarion' (its OWN index - reusing kx would clobber the caller's DirQ loop, leaving only the FIRST Clarion* dir per drive visible)
    c = dq:name[px]
    case val(c)
    of 48 to 57                      ! '0' to '9'
      if frac
        vnum = vnum * 10 + c ; break ! one fractional digit is enough (9.1 -> 91)
      else
        vnum = vnum * 10 + c
      end
    of 46                            ! <dot>
      frac = 1
    else
      break
    end
  end
  if ~frac then vnum *= 10.          ! whole versions align: 11 -> 110 vs 9.1 -> 91
  gq:nm  = clip(dq:name) & ' (' & dl & ':)'
  gq:ver = vnum

! ====================================================================================
! Default-.red discovery: the newest Clarion*.red in pDir ('' = the working dir). With
! no --red, the working dir is searched first, then <root>\bin, the file's normal home
! (e.g. C:\Clarion11\bin\Clarion110.red). Returns the name joined to pDir, or '' when
! there is none.
! ------------------------------------------------------------------------------------
FindNewestRed PROCEDURE(STRING pDir)
RedQ  QUEUE(File:queue),PRE(rq)
      END
rx    long,auto
rn    long,auto
px    long,auto
rc    string(1),auto
best  string(FILE:MAXFILENAME),auto
bestN long,auto
  code
  directory(RedQ, choose(~pDir, '', clip(pDir) & '\') & 'Clarion*.red', ff_:NORMAL)
  best = '' ; bestN = -1
  loop rx = 1 to records(RedQ)
    get(RedQ, rx)
    if band(rq:attrib, ff_:DIRECTORY) then cycle.
    rn = 0 ! NUMERIC version compare - lexicographic picks Clarion90.red over Clarion120.red ('9' > '1')
    loop px = 8 to len(clip(rq:name))
      rc = rq:name[px]
      if rc < '0' or rc > '9' then break.
      rn = rn * 10 + rc
    end
    ! one digit is a whole version, as the preprocessor reads it: Clarion9.red is 90, newer than 80
    if px = 9 then rn *= 10.
    if rn > bestN then best = rq:name ; bestN = rn.
  end
  if ~best then return ''.
  return choose(~pDir, '', clip(pDir) & '\') & clip(best)
