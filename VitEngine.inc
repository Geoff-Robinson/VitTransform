! VitEngine Class - the driver of VitTransform (generalised Clarion code transformer)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Per-file transform driver: parse -> build symbols -> fixpoint loop over the
! rule file (rules AND builtins in file order; whole pass repeats until a pass
! makes zero changes, hard cap maxPasses with a did-not-converge warning) ->
! write output. The execution model and the CLI switches are documented in README.md.
!
!  - Untouched files are never rewritten (byte-lossless trivially).
!  - Changed files are ALWAYS written CRLF. The tokenizer emits CRLF on rejoin
!    and nothing converts it back. There is no LF-preserving mode: LF-only is
!    not valid Clarion, so preserving it would only ever apply to input the
!    compiler would reject. An LF-only file comes back normalised to CRLF.
!  - Builtins dispatch through DoBuiltin (virtual); its CASE is the inventory.
!    The comment aligner and the FINAL groups are deferred: they run once after
!    the fixpoint has converged, and never count as a fixpoint change. The vtxaDiff009 ports (CombineAdjacentLiterals,
!    RemoveDoubledBrackets, the Check* family) work on self.tk; after a builtin
!    edits tokens RunPass rebuilds the symbol table, mirroring VitRewrite.
!    THE CASE IN DoBuiltin IS THE INVENTORY. Do not keep a list of them here:
!    a list in a comment goes stale the moment a builtin is added, and the CASE
!    cannot. BuiltinNames is the one other list, because a refusal has to be able
!    to name the builtins that DO exist; the build's namecheck preflight compares
!    it with the CASE labels and fails if either has a name the other lacks.
!    A builtin may set wantReparse to request rejoin->reparse->resymbol
!    (the UnusedVars OVER-cascade mechanism).
!  - ONCE is enforced by VitMatch (first match per scan) + VitRewrite.onceQ
!    (across passes). WHERE guards are evaluated by VitMatch.GuardOK.
!
! Requires StringTheory, VitTokenize, VitRules, VitSymbols, VitMatch,
! VitRewrite, VitTimer.
!
  INCLUDE('VitRewrite.inc'),ONCE
  INCLUDE('Preprocessor.inc'),ONCE                                                     ! .red-driven include expansion for the cross-file type registry

! AutoCheck verdicts. The design doc AutoCheck-spec.md is NOT shipped -
! the reasoning that matters is written out at BuiltinAutoCheck in VitEngine.clw
! DeclAttrBits masks
ab:auto               EQUATE(1)
ab:over               EQUATE(2)
ab:dim                EQUATE(4)
ab:static             EQUATE(8)
ab:thread             EQUATE(16)

RoutSpanQType         QUEUE,TYPE                                                       ! routine token spans of the cached scope
rStart                  LONG
rEnd                    LONG
                      END

DotRootQType          QUEUE,TYPE                                                       ! ROOTS of merged dotted tokens in the cached scope (guard, amortized)
rootU                   STRING(vs:maxName)
                      END

ac:unknown            EQUATE(0)                                                        ! default: touch nothing
ac:safe               EQUATE(1)                                                        ! assigned before every read on every path -> may ADD ,AUTO
ac:unsafe             EQUATE(2)                                                        ! read before write on some path -> may REMOVE ,AUTO

! KnownRanges - the value-range lattice.  Deliberately tiny: every fact records the
! receiver it is bounded by, and ANY doubt collapses to rk:none (see BuiltinKnownRanges).
rk:none               EQUATE(0)                                                        ! unknown - the default, and what any doubt collapses to
rk:zeroBound          EQUATE(1)                                                        ! 0 <= x <= <receiver>._DataEnd
rk:posBound           EQUATE(2)                                                        ! 1 <= x <= <receiver>._DataEnd
rk:nonNeg             EQUATE(3)                                                        ! x >= 0, no upper bound (no receiver)

! --receiver=: what to do about a Check* builtin's receiver when the symbol table cannot
! resolve it. These builtins find their work by METHOD NAME, so they can be pointed at any
! object that happens to have a same-named method (see README, D.3).
rm:assume             EQUATE(0)                                                        ! rewrite it as a StringTheory, identified or not
rm:check              EQUATE(1)                                                        ! DEFAULT: refuse if any use of it in scope is not a StringTheory method
rm:strict             EQUATE(2)                                                        ! refuse unless it PROVABLY resolves to a StringTheory

! DeadGuard / DeadLeft - which fact the ONE backward walk is being asked to prove about
! a receiver. Both are proved the same way and unproved by the same mutation list; only
! the statement being looked for differs (see VitEngine.DgProvenNonEmpty).
dg:wantGuard          EQUATE('GUARD')                                                  ! NOT EMPTY, from   if R._DataEnd < 1 then return.
dg:wantTrim           EQUATE('TRIM')                                                   ! NO LEADING SPACE, from   R.Trim()  or  R.setLeft()

! TrailingSpaces - how ONE textual use of a StringTheory receiver is classified.
! ts:bad is the default and any doubt collapses to it (see BuiltinTrailingSpaces).
ts:bad                EQUATE(0)                                                        ! the use may OBSERVE trailing spaces, or may CREATE them - refuses the region
ts:read               EQUATE(1)                                                        ! blind read: same answer with or without trailing spaces, and writes nothing
ts:cleanSet           EQUATE(2)                                                        ! clip()/trim()/removeByte(32)/setValue(x,st:clip) - the buffer is provably clean after it
ts:clipLen            EQUATE(3)                                                        ! recv.clipLength() - a blind read AND the target of simplification A1
ts:anchor             EQUATE(4)                                                        ! clip(recv.getValue()) - a blind read AND the target of simplification A2
ts:bare               EQUATE(5)                                                        ! a BARE receiver token (foo(st), st &= other) - refuses the receiver for the whole scope

! PROCEDURE SUMMARIES - what a procedure or method body IN THIS FILE provably RETURNS.
! sm:none is the default and ANY doubt collapses to it (see BuildSummaries). A summary is about
! the RETURN VALUE and nothing else - it says NOTHING about what the body did to a *STRING
! argument, and must never be read as if it did.
sm:none               EQUATE(0)                                                        ! unknown - the default, and what any doubt collapses to
sm:spaceless          EQUATE(1)                                                        ! the returned STRING contains NO SPACES AT ALL. Stronger than "no trailing spaces" on purpose: setLength(n)
                                                                                       !   truncates INTO the string, so only "no spaces anywhere" rules out a cut EXPOSING one (DEVIATION 1)
sm:nonNeg             EQUATE(2)                                                        ! the returned number is >= 0
sm:posBound           EQUATE(3)                                                        ! the returned number is >= 1

! what ONE use of a StringTheory receiver can do to the SPACES in its buffer. This is a
! DIFFERENT question from the ts:* (which asks about TRAILING spaces and about blindness), so it
! is a separate ladder - see VitEngine.SmMethodKind, the one place this whitelist lives.
sk:bad                EQUATE(0)                                                        ! may put a space into the buffer, or we cannot tell - refuses
sk:read               EQUATE(1)                                                        ! reads only; writes nothing at all
sk:keep               EQUATE(2)                                                        ! writes, but can only REMOVE or TRUNCATE - a spaceless buffer stays spaceless
sk:strip              EQUATE(3)                                                        ! removeByte(n) - keeps, and removeByte(32) MAKES the buffer spaceless
sk:store              EQUATE(4)                                                        ! setValue(...) - the ARGUMENTS decide, and only a spaceless call qualifies
sk:repl               EQUATE(5)                                                        ! replace(old, new) - keeps only while `new` is a literal with no space in it
sk:trunc              EQUATE(6)                                                        ! setLength(n) - NOT sk:keep. StringTheory.SetLength GROWS as well as truncates, padding the new space with
                                                                                       !   byte 32, so it can put trailing spaces INTO a spaceless buffer. Refused everywhere (it is absent from
                                                                                       !   SpaceKeepUse's CASE, so it lands on the safe default); the only place it is ever accepted is TsTruncGuard,
                                                                                       !   which matches the author's own same-line proof that the call shrinks. Keep it OUT of that CASE.

TsProvenQType         QUEUE,TYPE                                                       ! one row per guarded setLength TrailingSpaces has ALREADY proved
tpNameU                 STRING(vs:maxName)                                             ! UPPER declaration label of the proc/method the proof was made in. NOT the scopeId. Ids are positional and a
                                                                                       !   scope-REMOVING builtin (UnusedRoutines) renumbers them mid-run, so a banked proof could migrate to a different procedure
                                                                                       !   that inherited the id - and `st` / `p - 1` are exactly the names that repeat. The label is stable across a reparse
                                                                                       !   unless the procedure is renamed, in which case the proof simply stops matching and we refuse, as before.
tpRecvU                 STRING(vs:maxName)                                             ! UPPER receiver the proof is about
tpArgU                  STRING(vs:maxName)                                             ! UPPER setLength argument, token text joined - the proof's identity
tpOrd                   LONG                                                           ! the setLength's place among the receiver's setLength calls in the scope's code - with the count, the SITE
tpCnt                   LONG                                                           !   how many there are: text alone names an expression, not the call it was proved for
                      END

SumQType              QUEUE,TYPE                                                       ! one row per proc/method body we could summarise
smOwnerU                STRING(vs:maxName)                                             ! UPPER class name for a method; '' for a plain procedure
smNameU                 STRING(vs:maxName)                                             ! UPPER procedure / method name
smFact                  BYTE                                                           ! sm:*
smParamRO               STRING(32)                                                     ! per parameter, by position: 'R' = the body only READS it, 'W' = it may write it but keeps no reference, '.' = it may keep one, or no answer (14 Sep, 28 Oct 2026)
                      END

DoRefQType            QUEUE,TYPE                                                       ! UnusedRoutines' index: one row per `DO name` in the file, built once per pass (BuildDoIndex)
drName                  STRING(vs:maxName)                                             ! UPPER name after the DO
drDo                    LONG                                                           ! the DO token, and
drAt                    LONG                                                           !   the name token - the pair must lie inside the span asked about
                      END

ClsDeclQType          QUEUE,TYPE                                                       ! and one row per column-1 `Name CLASS` line
cdName                  STRING(vs:maxName)                                             ! UPPER label
cdPos                   LONG                                                           ! its token
cdCode                  LONG                                                           ! the last CODE statement before it (0 = none): a declaration counts for a procedure only in its DATA section
                      END

TimeRowQType          QUEUE,TYPE                                                       ! --timing: one row per built-in, and one per rule, that ran in this file
trName                  STRING(70)                                                     ! the built-in's name; for a rule, 'rule' and its id, plus its NAME(...) when it has one
trTicks                 LONG                                                           ! clock ticks (1/100 s) spent in it
trCalls                 LONG                                                           ! built-in passes, or rule scans
trChg                   LONG                                                           ! changes it made
                      END

VitEngine           CLASS,TYPE,MODULE('VitEngine.clw'),LINK('VitEngine.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
rl                     &VitRules                                                       ! not owned
tk                     &VitTokenize                                                    ! owned
syms                   &VitSymbols                                                     ! owned
plainAsk               &VitPlainAsk                                                    ! owned: a VitEnginePlainAsk, the isPlain() guard's answer
rw                     &VitRewrite                                                     ! owned
tmr                    &VitTimer                                                       ! owned (class members must be references - GCR note)
pp                     &Preprocessor                                                   ! include preprocessor (owned; NULL until SetupIncludes)
exptk                  &VitTokenize                                                    ! tokenizer for the include-expanded source (owned)
ppLineMap              &LineMapQueue                                                   ! expanded-line -> origin header (owned)
ppSrc                  &StringTheory                                                   ! expanded source buffer (owned)
recvMode               BYTE                                                            ! rm:assume / rm:check / rm:strict
dgPure                 &StringTheory                                                   ! KnownRangePureList, for the DeadGuard fact walk
stMeth                 &StringTheory                                                   ! ' NAME NAME ' - every StringTheory method
urData                 &StringTheory                                                   ! ' NAME ' - names the data section of the AutoScopePrep scope mentions (UnseenRead)
urEsc                  &StringTheory                                                   ! ' NAME ' - names whose storage escapes in that scope's code: &=, ADDRESS(), BIND
urInc                  BYTE                                                            ! that scope INCLUDEs a file - in its data, its code or a method that follows it (ScopeIncludes)
lmNames                &StringTheory                                                   ! ' A B C ' - every name the local methods of procedure [lmProcS, lmProcE] use
lmProcS                LONG                                                            ! the procedure lmNames belongs to; -1 = list afresh
lmProcE                LONG
lmInc                  BYTE                                                            ! 1 = one of those methods INCLUDEs a file after its CODE
kwUpper                &StringTheory                                                   ! --kwupper=A,B,C - keywords KeywordCase puts in UPPER whatever its style (owned, ' A B C ')
kwLower                &StringTheory                                                   ! --kwlower=A,B,C - ditto, lower
kwTitle                &StringTheory                                                   ! --kwcapitalise=A,B,C (or --kwcapitalize=, --kwtitle=) - ditto, first letter capitalised
useIncludes            BYTE                                                            ! include expansion enabled (SetupIncludes succeeded)
softIncludes           BYTE                                                            ! the includes are read because a Clarion was found, not because the run asked: a header not found is a note
redPath                STRING(260)                                                     ! .red redirection file
ppDefines              STRING(512)                                                     ! --define= flags for the preprocessor (project compiler flags under --thorough)
rootDir                STRING(260)                                                     ! %ROOT% (Clarion install dir, e.g. c:\Clarion11)
config                 STRING(32)                                                      ! %CONFIGURATION% (Debug/Release)
! engine switches (CLI)
dryRun                 BYTE
verbose                BYTE
timing                 BYTE                                                            ! --timing: a second report line per file - where the run spent its time
tRules                 LONG                                                            !   clock ticks (1/100 s) in rule scans this file, and how many scans ran
nRules                 LONG
tBuiltins              LONG                                                            !   in built-in passes
nBuiltins              LONG
tReparse               LONG                                                            !   in RejoinReparse (a full re-lex)
nReparse               LONG
biTime                 &TimeRowQType                                                   !   the per-built-in breakdown for this file (owned)
ruTime                 &TimeRowQType                                                   !   the per-rule breakdown for this file (owned)
planQ                  &PlanQType                                                      ! grouped dispatch: the rules a pass visits, in order (BuildPlan; the group walk reads it through rw.plan)
loose                  BYTE
widthArg               LONG                                                            ! --width=N. 0 = not given, use the per-file scan. -1 = --width=0, never split.
splitWidth             LONG                                                            ! the limit SplitWideLines works to. Absolute (240), NOT the per-file scan - see WidthPolicy.
acDiag                 BYTE                                                            ! --acdiag - passed to the tokenizer so AlignComments explains itself
cmtGap                 LONG(1)                                                         ! --cmtgap=<n> - spaces between the code and a trailing comment. 1 = as shipped
alignLimit             LONG                                                            ! --cmtlimit=<n> - passed to the tokenizer
alignSlack             LONG                                                            ! --cmtslack=<n> - passed to the tokenizer
alignOutlier           LONG                                                            ! --cmtoutlier=<n> - passed to the tokenizer
declOutlier            LONG                                                            ! --decloutlier=<n> - passed to the tokenizer
cmtWrap                LONG                                                            ! --cmtwrap=<n> - reflow trailing comments so no line passes n. 0 = off
cmtSplit               LONG                                                            ! --cmtsplit=<n> - cut trailing comment rows over n, never join (exclusive with --cmtwrap=)
cmtReach               LONG(3)                                                         ! --cmtreach=<n> - passed to the tokenizer
cmtInner               LONG(12)                                                        ! --cmtinner=<n> - reach for a plain line BETWEEN two commented rows - passed to the tokenizer
cmtFloor               BYTE                                                            ! --cmtfloor= - 0 near, 1 commented, 2 all - passed to the tokenizer
contBracket            BYTE(1)                                                         ! --contindent=bracket - ON by default (ruled 17 Sep 2026); indent turns it off - passed to the tokenizer
ignoreMarks            BYTE                                                            ! --ignoremarks / SETTINGS ignoremarks=on: the base64, encoding and gzip marks are not guarded (ruled 10 Nov 2026; default off)
cmtKeep                BYTE(1)                                                         ! --cmtkeep=aligned - ON by default - passed to the tokenizer. --cmtkeep=off to align a tidy group anyway
cmtOpBar               BYTE                                                            ! --cmtop=bar - passed to the tokenizer
cmtEndCount            BYTE                                                            ! --cmtend=count - passed to the tokenizer
cmtBarCmt              BYTE                                                            ! --cmtbar=comment - passed to the tokenizer
cmtContNone            BYTE                                                            ! --cmtcont=none - passed to the tokenizer
cmtRun                 LONG(10)                                                        ! --cmtrun=<n> - passed to the tokenizer
colSeqCustom           BYTE                                                            ! --colseq=custom - the program sets its own collating sequence: a CASE keeps its character ranges
onlyId                 LONG                                                            ! --only=<name-or-id>, resolved to the rule id  (0 = all)
skipId                 LONG                                                            ! --skip=<name-or-id>, resolved to the rule id  (0 = none)
outDir                 STRING(260)                                                     ! blank = in-place (only when inPlace set)
outSuffix              &StringTheory                                                   ! inserted before the extension of each output file (--outsuffix= and/or --outstamp)
bannerUsing            &StringTheory                                                   ! the "using" part of the Processed-by line - the rule file and every switch, as entered (set by the CLI)
inPlace                BYTE                                                            ! --in-place: overwrite originals (outDir blank); a timestamped .bak of each changed file is kept first
stamp                  STRING(40)                                                      ! ' on yyyymmdd at hhmmssth' - one per run; used by --outstamp and the in-place backup name
noBanner               BYTE                                                            ! --nobanner: no Processed-by line at the top of an output file
maxPasses              LONG                                                            ! default 20
! per-run state
totalChanges           LONG
filesChanged           LONG
filesDone              LONG
saveErrors             LONG                                                            ! failed WriteOutput saves (e.g. missing output dir)
loadErrors             LONG                                                            ! sources that were asked for and could not be loaded - these reach ERRORLEVEL
ppErrors               LONG                                                            ! headers that could not be expanded - the type registry is then incomplete
ppNotes                LONG                                                            ! the same, in a run that read the includes only because a Clarion was found - a note, not a failure
curPass                LONG
wantReparse            BYTE                                                            ! set by a builtin to request rejoin/reparse
rulesDirty             BYTE                                                            ! a level-hazard rule replacement fired since the last reparse. A MEMBER, not a RunPass local: a rule that fires AFTER the last builtin
                                                                                       !   of a pass must still force the reparse before the NEXT pass's first builtin (and before the deferred FINAL pass) - as a local the
                                                                                       !   flag died at RunPass exit and the damage leaked across. Cleared by RejoinReparse itself (whoever reparses, the stream is fresh).
sawAlign               BYTE                                                            ! AlignComments requested by the rule file (run once, after convergence)
txaSaid                BYTE                                                            ! the refusal has been logged for this file (once, not once per pass)
isTxa                  BYTE                                                            ! the current file is a .txa (template export), not plain source. Set by TransformFile from the extension. It turns on
                                                                                       !   the pre/post wrap below AND refuses the three analyses that cannot see template-generated code - see TxaPreProcess.
tsProven               &TsProvenQType                                                  ! guarded-setLength proofs carried ACROSS passes (owned; per FILE, freed in TransformFile/TransformText)
progressFn             STRING(260)                                                     ! live progress file, overwritten per step; blank = off
progLast               LONG                                                            ! last Progress() write (clock centisec) - throttle disk writes
acScopeId              LONG                                                            ! scope the ac* cache below describes (0 = none)
acCodeT                LONG
acMainEnd              LONG
acBail                 BYTE                                                            ! GOTO/COMPILE/OMIT in the scope (or no CODE) -> verdict UNKNOWN
acWhyLine              LONG                                                            ! diag: source line of the token that made AutoVerdict return UNSAFE (0 = n/a)
acWhyTxt               STRING(900)                                                     ! diag: conviction state + push/pop ledger for the traced symbol
acWhyElig              STRING(120)                                                     ! WHY: why AutoEligible refused the last symbol it was asked about ('' = it did not)
hoistWhy               STRING(120)                                                     ! WHY: what stopped CondIsPureRead proving the last IF test it was asked about
acRoutQ                &RoutSpanQType                                                  ! routines of the cached scope
acDotQ                 &DotRootQType                                                   ! sorted roots of the scope's merged dotted tokens (may hold dups; hit/miss lookup only)
sums                   &SumQType                                                       ! per-file procedure summaries (owned); rebuilt by BuildSummaries at every consumer entry
doRefs                 &DoRefQType                                                     ! UnusedRoutines' index of every DO (owned) - see BuildDoIndex
clsDecls               &ClsDeclQType                                                   !   and of every column-1 CLASS declaration (owned)
doIdxOn                BYTE                                                            !   1 while the index is current: RoutineReferenced and LocalClassDeclared look it up instead of walking
lbClipNext             LONG                                                            ! LbClipLineAt's second answer: the first token past the clip line (a member: the method's second answer)
lbWhy                  STRING(200)                                                     ! LbValueReadOK's reason when it refuses (a member: its second answer)
lbSepTxt               STRING(96)                                                      ! LbSepAt's answers: the split's separator literal as written,
lbSepN                 LONG                                                            !   its length in bytes,
lbSepByte              LONG                                                            !   and that byte when there is only one
scOpen                 LONG                                                            ! SplitOwnArgs' answers: the split call's own brackets, found by
scClose                LONG                                                            !   depth across a '|' continuation,
scArgN                 LONG                                                            !   its number of arguments,
scSepTok               LONG                                                            !   the first argument's token when it is one token,
scQrm                  BYTE                                                            !   the fourth given and not false (pRemoveQuotes),
scQuo                  BYTE                                                            !   the second given and not '' or a space (pQuoteStart),
scClip                 BYTE                                                            !   st:clip as the fifth (pClip),
scSpace                BYTE                                                            !   and a lone space as an argument
slWhy                  STRING(200)                                                     ! SplitLineKind's reason when it answers 0,
slStmt                 LONG                                                            !   the split statement's first token - its receiver -
slLine                 LONG                                                            !   and the first token of its logical line
curFile                STRING(260)

Construct              Procedure()
Destruct               Procedure()
Init                   Procedure(VitRules pRl),virtual
SetupIncludes          Procedure(STRING pRedPath, STRING pRootDir, STRING pConfig, <STRING pDefines>),BYTE,PROC,virtual ! enable include expansion; returns 1 if enabled
ApplyCmtSetting        Procedure(STRING pKey, STRING pVal, *STRING pErr),BYTE,PROC,virtual ! set one alignment field from a name=value (profile SETTINGS or workbench); 1 ok, 0 fail (pErr says why)
ApplyAlignToTokenizer  Procedure(),virtual                                             ! hand those settings to the TOKENIZER, where the aligners read them. Called by BOTH entry points, so the preview cannot drift from a batch run
TransformFile          Procedure(STRING pFn, StringTheory pLog),LONG,PROC,virtual      ! returns changes for this file
TransformText          Procedure(StringTheory pSrc, StringTheory pOut, StringTheory pLog),LONG,PROC,virtual ! in-process preview - transform a text buffer, never writes; pOut = transformed text, returns change
                                                                                                            !   count. Uses the SAME parse/symbols/fixpoint/resolver as TransformFile (honesty invariant).
RunPass                Procedure(StringTheory pLog),LONG,virtual                       ! one pass; returns its change count
RepHasLevelKeyword     Procedure(),LONG,virtual                                        ! current rule replacement carries IF/LOOP/CASE/ELSE/END/... (level damage possible)
DoBuiltin              Procedure(LONG pRow, StringTheory pLog),LONG,virtual            ! change count; may set wantReparse
BuiltinNames           Procedure(),STRING,virtual                                      ! every name DoBuiltin dispatches, comma-separated, spelt as the README spells them
KnownBuiltin           Procedure(STRING pName),BYTE                                    ! 1 = BuiltinNames carries pName, in any case
CheckBuiltinNames      Procedure(VitRules pRl, StringTheory pBad),LONG,PROC            ! a BUILTIN line naming no builtin is a rule-file ERROR; pBad gets one line each; returns how many
BuiltinInlineSingleUse Procedure(StringTheory pLog),LONG,virtual                       ! v = <expr> immediately followed by a statement reading v ONCE -> the expression
BuiltinDropValueCopy   Procedure(StringTheory pLog),LONG,virtual                       ! a scratch object that only ever holds a COPY of another object's value, and only reads it, is that object
BuiltinTakeOverValue   Procedure(StringTheory pLog),LONG,virtual                       ! a scratch loaded with a copy of a local nothing mentions again is that local
BuiltinChangeBeforeSplit Procedure(StringTheory pLog),LONG,virtual                     ! a change made to every line of a split, one line at a time, is one change to the value before the split
BuiltinLineSearchToInLine Procedure(StringTheory pLog),LONG,virtual                    ! a loop that searches the lines for a value, one line at a time, is one inLine() call
BuiltinByteLoopToCall  Procedure(StringTheory pLog),LONG,virtual                       ! a byte-by-byte loop over the value is one StringTheory call - count, containsChar or findChar
BuiltinDeadValueWrite  Procedure(StringTheory pLog),LONG,virtual                       ! a value written to a StringTheory that nothing reads before the next write is a line that does nothing
BuiltinDeadLinesWrite  Procedure(StringTheory pLog),LONG,virtual                       ! a split whose lines nothing reads before the next split or freeLines did work nothing used
BuiltinCheckDeleteInLoop Procedure(StringTheory pLog),LONG,virtual                     ! REPORTS ONLY - deleteLine in a forward loop over the same lines skips the line after each delete
BuiltinFirstAddIsSet   Procedure(StringTheory pLog),LONG,virtual                       ! a += that is a zero-initialised local's FIRST write is an =, and the local can be AUTO
BuiltinLoopBlankRecords Procedure(StringTheory pLog),LONG,virtual                      ! the trailing-blank-record loop after a split. REPORTS ONLY - it names each site and, where it refuses, which of the seven guards said no
BuiltinClipAtSplit     Procedure(StringTheory pLog),LONG,virtual                       ! every read of a split's lines clips -> the clip moves onto the split, and the reads give theirs up
BuiltinDropLineBuffer  Procedure(StringTheory pLog),LONG,virtual                       ! a scratch object that only ever holds ONE LINE is the source object itself
BuiltinDeadTrim        Procedure(StringTheory pLog),LONG,virtual                       ! a trim()/clip() of a line from a lone-space split has nothing to strip: commented out
BuiltinCutToSplit      Procedure(StringTheory pLog),LONG,virtual                       ! a value cut at its first separator into a head and a tail is a split: line 1 and the lines after it
BuiltinSplitInPlace    Procedure(StringTheory pLog),LONG,virtual                       ! a scratch copied only to be split is the source split in place, joined back before the source is read again
BuiltinResplitToLines  Procedure(StringTheory pLog),LONG,virtual                       ! a joined range of lines split again on the same separator is those lines: the copy folds into the object
BuiltinTrimAtSplit     Procedure(StringTheory pLog),LONG,virtual                       ! every line read from a split is trimmed as it is loaded: the split trims them
BuiltinMergeDisjointLocals Procedure(StringTheory pLog),LONG,virtual                   ! two StringTheory locals never in use at once are one
BuiltinRepairNotes     Procedure(StringTheory pLog),LONG,virtual                       ! a note this tool wrote onto the end of a comment with no "!" of its own gets one - comment text only
RepairNoteText         Procedure(StringTheory pTxt),LONG,virtual                       ! the repair on one piece of comment text - every glued note phrase gets "  !" in front; returns how many
BuiltinIncludeBrackets Procedure(StringTheory pLog),LONG,virtual                       ! an INCLUDE written without brackets is written with them: INCLUDE 'x.clw' -> INCLUDE('x.clw'), the one-argument form only
BuiltinClippedCompare  Procedure(StringTheory pLog),LONG,virtual                       ! two values that are clipped lines of a split compare by length first, then bytes
CcValueAt              Procedure(LONG pIx, *STRING pRecvU, *LONG pEnd),LONG,virtual    ! ClippedCompare: a value read at pIx - getValue() or the direct read - its receiver and last token
CcRecvText             Procedure(LONG pIx),STRING,virtual                              ! ClippedCompare: the receiver as written, from the first token of a value read
BuiltinDirectReadEquals Procedure(StringTheory pLog),LONG,virtual                      ! a compare of two StringTheorys with a side read straight from the buffer becomes equals(), as st-equals writes the getValue() one
                                                                                       !   moves to the read and the store line goes. MOVES CODE: opt-in, own group, OFF
IsuSpanText            Procedure(LONG pS, LONG pE, StringTheory pOut),virtual          ! a token span rendered with its ORIGINAL spacing (strBefore), unlike MgSpanText which joins with one space
IsuNearMark            Procedure(LONG pFrom, LONG pTo),BYTE,virtual                    ! 1 = a store or its reads sit beside or inside code the always-true test marked
IsuStmtEnd             Procedure(LONG pFirst),LONG,virtual                             ! last token of the statement starting at pFirst, or 0 if it is continued with '|' or runs off the end
IsuNextStmt            Procedure(LONG pAfter),LONG,virtual                             ! first token of the next statement after pAfter, skipping EOLs; 0 = none
IsuIsWrite             Procedure(LONG pTok),LONG,virtual                               ! is pTok WRITTEN - next token '=' - rather than read? A write KILLS an earlier store
IsuExprType            Procedure(LONG pS, LONG pE, *LONG pWidth, *LONG pLit),STRING,virtual ! the static type of an expression: STRING (pWidth), BYTE..ULONG, SREAL, REAL; '' = not readable
IsuOperandType         Procedure(LONG pS, LONG pE, *LONG pWidth, *LONG pLit),STRING,virtual ! one operand of it: a token, a call, a StringTheory reader, a subscript
IsuJoinType            Procedure(LONG pS, LONG pE, *LONG pWidth),STRING,virtual        ! `a & b` at the top: a STRING, the sum of known widths or 0
IsuKeywordClass        Procedure(STRING pTypeU),STRING,virtual                         ! a type keyword as one of those classes
IsuLiteralWidth        Procedure(StringTheory pTok),LONG,virtual                       ! characters in a string literal, quotes off, escapes counted
IsuTypeExact           Procedure(LONG pSymRow, BYTE pIsST, LONG pS, LONG pE),LONG,virtual ! does the store's target hold the expression's value exactly? Ruled 13 Sep 2026
BuiltinCombineLiterals Procedure(StringTheory pLog),LONG,virtual                       ! 'abc' & 'xyz' -> 'abcxyz'; '<13><10>' -> '<13,10>' (vtxaDiff port)
BuiltinDoubledBrackets Procedure(StringTheory pLog),LONG,virtual                       ! foo((x)) -> foo(x) (vtxaDiff port)
BuiltinCheckCase       Procedure(StringTheory pLog),LONG,virtual                       ! case 'x' -> case val('x') -> integers + name comments (vtxaDiff checkCaseStatements + checkVals)
BuiltinCheckReplaces   Procedure(StringTheory pLog),LONG,virtual                       ! replace() arg cleanup + replaceByte/removeByte (vtxaDiff port)
BuiltinCheckRemoves    Procedure(StringTheory pLog),LONG,virtual                       ! remove() arg cleanup + removeByte (vtxaDiff port)
BuiltinCheckSplits     Procedure(StringTheory pLog),LONG,virtual                       ! st.split() positional booleans -> st:clip / st:left
BuiltinCheckInLine     Procedure(StringTheory pLog),LONG,virtual                       ! st.inline() -> st:noCase / st:wholeLine / st:begins / st:clip
BuiltinCheckCat        Procedure(StringTheory pLog),LONG,virtual                       ! cat -> Append incl. literal truncation (vtxaDiff port)
SplitCallArgs          Procedure(StringTheory pOut, LONG pS, LONG pE),virtual          ! a call's arguments one to a line, split at the commas outside every bracket
BuiltinUnusedVars      Procedure(StringTheory pLog),LONG,virtual                       ! comment out unused declarations; internal OVER-cascade (vtxaDiff CheckForUnusedVars)
RemoveUnusedPass       Procedure(StringTheory pPrefix, StringTheory pExclU, StringTheory pLog),LONG,virtual ! one scan of the symbol table; returns count commented
SymUsed                Procedure(STRING pNameU, LONG pStart, LONG pEnd, LONG pDeclLine),LONG,virtual ! name referenced as a token after its decl line, within scope
! --- UnusedRoutines: comment out routines never invoked via DO in their owning proc ---
BuiltinUnusedRoutines  Procedure(StringTheory pLog),LONG,virtual                       ! comment out unreferenced ROUTINEs; DO-cascade via wantReparse
LbClipLineAt           Procedure(LONG pFrom, STRING pNameU),LONG,virtual               ! LoopBlankRecords: is the line at pFrom exactly <name>.clip()? lbClipNext = the line after it
LbValueReadOK          Procedure(STRING pNameU, LONG pEndTok, LONG pTo),LONG,virtual   ! LoopBlankRecords' G2: 1 = no read of the value after the loop before a write certain to run; 0 = refused, lbWhy says
LbSepAt                Procedure(LONG pTok),LONG,virtual                               ! LoopBlankRecords' G1: the separator token pTok is a string literal? lbSepTxt/lbSepN/lbSepByte
LbEmitAt               Procedure(LONG pSplitTok, LONG pSepTok, LONG pLoopTok, LONG pPastTok, LONG pLogLine, StringTheory pLog),virtual ! LoopBlankRecords' edit: the loop goes, the clip or the strip loop goes in front of the split
SplitOwnArgs           Procedure(LONG pTail),LONG,virtual                              ! the split call's arguments, by depth from its own '(' - scOpen, scClose, scArgN, scSepTok, scQrm, scClip, scSpace
SplitLineKind          Procedure(LONG pTail, STRING pRecvU),LONG,virtual               ! 1 = the split is its whole line, 2 = it shares it with ;-joined plain statements, 0 = refused (slWhy)
RelineSplitLine        Procedure(LONG pTok),LONG,PROC,virtual                          ! put each ;-joined statement of the line on a line of its own, as SplitStatements does
GotoBackTop            Procedure(LONG pAt, LONG pFirst, LONG pLast),LONG,virtual       ! the earliest column-1 label at or above pAt that a GOTO after it names, 0 = none
RemoveUnusedRoutinesPass Procedure(StringTheory pPrefix, StringTheory pExclU, StringTheory pLog),LONG,virtual ! one scan of routine scopes; returns count commented
BuildDoIndex           Procedure(),virtual                                             ! UnusedRoutines: one walk of the file into doRefs and clsDecls, sorted by name
BuildPlan              Procedure(),virtual                                             ! grouped dispatch: fill planQ for this pass and hand it to the rewriter
PassVisits             Procedure(LONG pRow),LONG,virtual                               ! 1 = RunPass would give this rule its turn (kind, SKIP, group, --only=, --skip=)
RoutineReferenced      Procedure(STRING pNameU, LONG pProcStart, LONG pProcEnd),LONG,virtual ! a `DO <pNameU>` token pair anywhere in the owning proc span
RoutineRefByMethod     Procedure(STRING pNameU, LONG pProcStart, LONG pProcEnd, StringTheory pFileCls),LONG,virtual ! 1 = a method of a class in the proc's DATA DOes it; 2 = one of a class this file never declares does
LocalClassDeclared     Procedure(STRING pClsU, LONG pProcStart, LONG pProcEnd),LONG,virtual ! is `<pClsU> CLASS` a column-1 declaration between the proc header and its CODE?
FileClassList          Procedure(StringTheory pOut),virtual                            ! ' A B C ' - every column-1 CLASS label in the file, one scan
ProcIncludes           Procedure(LONG pStart, LONG pEnd),LONG,virtual                  ! an INCLUDE after the span's CODE statement - the included file may hold the DO
ScopeIncludes          Procedure(LONG pScopeId),LONG,virtual                           ! 1 = an INCLUDE in the scope (data, code, routines) or, for a procedure, in a method that follows it
MayHaveLocalMethods    Procedure(LONG pScopeId),LONG,virtual                           ! 1 = ask UsedInLocalMethods: a procedure, or a method whose data section declares a CLASS or INCLUDEs a file
CommentOutSpan         Procedure(LONG pStartTok, LONG pEndTok, STRING pHeader),LONG,PROC,virtual ! '!'-prefix every first-on-line token in the span (header on line 1); returns lines commented
! --- UnreachableCode: comment code after an unconditional RETURN/EXIT/BREAK/CYCLE/GOTO ---
BuiltinUnreachableCode Procedure(StringTheory pLog),LONG,virtual                       ! comment statements after an unconditional transfer, per scope
RemoveUnreachablePass  Procedure(StringTheory pPrefix, StringTheory pLog),LONG,virtual ! one scan of proc/method/routine exec ranges
WalkUnreachable        Procedure(LONG pExecStart, LONG pExecEnd, StringTheory pPrefix, StringTheory pLog),LONG,virtual ! dead-state walk over one code range; returns lines commented
IsTransferKw           Procedure(STRING pKwU),LONG,virtual                             ! RETURN/EXIT/BREAK/CYCLE/GOTO = unconditional transfer of control
FirstTokAfterLine      Procedure(LONG pTok),LONG,virtual                               ! first token on a later line than pTok's (0 if none) - routine exec start when no CODE keyword
! --- UnusedAssignments: comment assignments to a simple local never READ (write-only var) ---
BuiltinUnusedAssignments Procedure(StringTheory pLog),LONG,virtual                     ! comment dead stores (whole-var assignments to never-read locals)
RemoveDeadStoresPass   Procedure(StringTheory pPrefix, StringTheory pLog),LONG,virtual ! one scan: per eligible local, classify reads/writes; comment writes if 0 reads
PerStoreDeadStores     Procedure(LONG pCodeT, LONG pEndT, STRING pNameU, BYTE pAllowEnd, StringTheory pPrefix, StringTheory pLog),LONG,virtual ! v2: straight-line per-store liveness (overwritten-before-read)
                                                                                                                                               !   for a read>0 var; pAllowEnd=0 for STATIC/THREAD
RhsSingleSafe          Procedure(LONG pAssignTok),LONG,virtual                         ! 1 = RHS is a single non-'(' token ending the line (no call, no continuation) = side-effect-free
InExecute              Procedure(LONG pTok, LONG pFromT),LONG,virtual                  ! the enclosing EXECUTE's token, or 0 - its arms are alternatives, so dropping one RENUMBERS the rest
HayType                Procedure(STRING pTok, LONG pIx),STRING,virtual                 ! the type an instring() haystack token resolves to, dotted chains included; '' = unresolved
InstrOneChar           Procedure(LONG pS, LONG pE),BYTE,virtual                        ! 1 = the needle in tokens pS..pE is provably one character (InstringOneCharToST)
ValuePtrPick           Procedure(STRING pNameU, LONG pAt),LONG,virtual                 ! 1 = pNameU is a StringTheory's valuePtr, so a single-index pick of it is one character
ArmOfExecute           Procedure(LONG pTok),LONG,virtual                               ! the EXECUTE whose ARM the statement at pTok is (innermost block only), or 0
UsedInLocalMethods     Procedure(STRING pNameU, LONG pProcStart, LONG pProcEnd),LONG,virtual ! the name is used in a method of a class the procedure declares - they share its locals
UlmFill                Procedure(LONG pProcStart, LONG pProcEnd),virtual
ObjEscapes             Procedure(STRING pNameU, LONG pAtTok),BYTE,virtual              ! 1 = the object can be read without being named: a parameter, a reference, a local class's method, handed whole to a call
NameHolds              Procedure(STRING pOuterU, STRING pNameU),LONG,virtual           ! 1 = pNameU is a member of pOuterU, at any depth: SELF holds SELF.BUF
ObjReach               Procedure(STRING pNameU, LONG pAt, BYTE pWhat),STRING,virtual   ! why the object can be reached unseen, or blank: 1 a reference or a call that may keep one, 2 its Stream(), 4 the summaries are built, 8 only its lines matter
IsPlainAt              Procedure(LONG pTok),BYTE,virtual                               ! 1 = the StringTheory named at pTok is a plain local: nothing but its code reaches, marks, streams or hands it on
RenameTypeWhy          Procedure(STRING pFromU, STRING pToU, LONG pSc),STRING,virtual  ! why the mentions of local pFromU may not be renamed onto local pToU: not declared with one type word; blank = they may
UvPlainType            Procedure(STRING pTypeU),LONG,virtual                           ! 1 = declaring this type runs nothing: built-in data, a structure, a StringTheory
BuiltinHoistNeutralTest Procedure(StringTheory pLog),LONG,virtual                      ! a test against a literal with no letters moves above the case fold it reads, when nothing can read the fold on the jump path
BuiltinAlwaysTrueTest  Procedure(StringTheory pLog),LONG,virtual                       ! an IF on clip() or left() of a number is always true: the IF and its ELSE side are commented out, its own code kept
! --- HoistCommonBranchCode: move common trailing code out of an IF/ELSE/END (END-hoist) ---
BuiltinHoistCommonBranchCode Procedure(StringTheory pLog),LONG,virtual                 ! one hoist per pass, wantReparse -> fixpoint peels a run one line at a time
HoistArmEmpty          Procedure(LONG pFromTok, LONG pToTok),LONG,virtual              ! 1 = not one statement between the two tokens - an arm with nothing left in it
CondIsPureRead         Procedure(LONG pIfTok),LONG,virtual                             ! the IF test is ONE token that PROVABLY names data - never a call, never an unresolved name
HoistDeadIf            Procedure(LONG pIfTok, LONG pEndTok),LONG,virtual               ! 0 nothing to do, 1 commented the dead IF out, 2 arms empty but the
                                                                                       !   test is not provably a read - the caller reports that and leaves it
HoistDropElse          Procedure(LONG pIfTok, LONG pEndTok),LONG,virtual               ! 1 = the ELSE this run emptied, alone on its line and with no comment near it, is gone
HoistOnePass           Procedure(StringTheory pLog),LONG,virtual                       ! find the first clean IF/ELSE/END and END-hoist (then START-hoist) one common statement
HoistFindElse          Procedure(LONG pIfTok, LONG pEndTok),LONG,virtual               ! single depth-1 ELSE token, or 0 if not a clean two-branch IF (ELSIF/OF/no-else/multi)
TryEndHoist            Procedure(LONG pIfTok, LONG pElseTok, LONG pEndTok, StringTheory pLog),LONG,virtual ! perform the END-hoist if both trailing statements are identical single lines; 1=done
TryStartHoist          Procedure(LONG pIfTok, LONG pElseTok, LONG pEndTok, StringTheory pLog),LONG,virtual ! perform the gated START-hoist if both leading statements are identical + independent of C; 1=done
StartMove              Procedure(LONG pSrc, LONG pDst, LONG pNum),virtual              ! backward block relocation (pDst<pSrc), order-preserving, via per-token MoveTok
MoveLinesAbove         Procedure(LONG pSrc, LONG pDst, LONG pNum),virtual              ! StartMove of whole lines in front of the line at pDst; a folded OMIT block stays above them
FirstEolAfter          Procedure(LONG pTok),LONG,virtual                               ! first <10> token after pTok (0 if none)
FirstEolOrEnd          Procedure(LONG pTok),LONG,virtual                               ! the same, or one past the last token
SpanHasParen           Procedure(LONG pS, LONG pE),LONG,virtual                        ! a '(' anywhere in the span (call/grouping)
OpLevel                Procedure(LONG pTok),LONG,virtual                               ! how tightly an operator binds: 4 '^' .. 8 a comparison, 9 NOT, 10 AND, 11 OR/XOR; 0 = not one
SpanTopLevel           Procedure(LONG pS, LONG pE),LONG,virtual                        ! the loosest operator outside every bracket, as OpLevel numbers it; 0 = one term
SpanTopWord            Procedure(LONG pS, LONG pE, STRING pWordsU),LONG,virtual        ! the first token outside every bracket that is one of pWordsU (' OR XOR '); 0 = none
CondNamesAreData       Procedure(LONG pCS, LONG pCE),LONG,virtual                      ! every NAME in the span provably reads DATA - a parenless call carries no '(' to find
NameRoot               Procedure(STRING pName),STRING,virtual                          ! the name before any '.' or ':' - what the STORAGE is
SpanHasName            Procedure(STRING pNameU, LONG pS, LONG pE),LONG,virtual         ! a label token caselessly = pNameU in the span
StmtIsPlainAssign      Procedure(LONG pFirst, LONG pCEnd),LONG,virtual                 ! `label = ...` with no call -> only effect is writing the lhs
IsFirstOnLine          Procedure(LONG pTok),LONG,virtual                               ! token's firstOnLine flag (0 on error)
BeginsStmt             Procedure(LONG pTok),LONG,virtual                               ! pTok begins a statement: after a line end, ';', THEN, ELSE or a column-1 label
StoreHead              Procedure(LONG pTok),LONG,virtual                               ! `=` after the name at pTok stores: it begins its statement, follows a column-1 '?', or counts a LOOP. 2 = on a debug-only line
DebugLine              Procedure(LONG pTok),LONG,virtual                               ! the physical line pTok is on begins with the DEBUG mark, a '?' alone - it runs in debug builds only
IsEolTok               Procedure(LONG pTok),LONG,virtual                               ! token is the physical newline (<10>)
LineStartOf            Procedure(LONG pEolTok),LONG,virtual                            ! first-on-line token of the line ending at pEolTok (0 if blank/error)
LineHasLevelMark       Procedure(LONG pFirst, LONG pEol),LONG,virtual                  ! any +/-/'/' level mark in the line -> not a simple statement
LineHasComment         Procedure(LONG pFirst, LONG pEol),LONG,virtual                  ! a '!' in any of the line's trivia (leading/interior/trailing)
LineCommentText        Procedure(LONG pFirst, LONG pEol, StringTheory pOut),virtual    ! the line's comment TEXT, normalised - identical comments must not block a hoist
IndentOf               Procedure(LONG pTok, StringTheory pOut),virtual                 ! the trivia after the last line feed of pTok's strBefore - its indent, never a folded OMIT block
HasAbsorbedBlock       Procedure(LONG pTok),LONG,virtual                               ! pTok's strBefore holds a line feed - an OMIT block folded in front of it
AbsorbedBlockOf        Procedure(LONG pTok, StringTheory pOut),virtual                 ! pTok's strBefore up to its last line feed - a folded OMIT block, or nothing
InsertLinesAbove       Procedure(LONG pTok, StringTheory pTxt),virtual                 ! whole lines in front of the line at pTok; a folded OMIT block stays above them
LineBlocks             Procedure(LONG pFirst, LONG pLast, StringTheory pOut),virtual   ! every OMIT block folded in front of a line from pFirst to pLast, in order
SpanTokEqual           Procedure(LONG pAF, LONG pAE, LONG pBF, LONG pBE),LONG,virtual  ! caseless token-for-token span equality
! --- IfChainToCase (ungrouped, on by default): `if E = a or E = b ... elsif E = c` -> `case E / of a orof b / of c` ---
BuiltinMergeAdjacentCase Procedure(StringTheory pLog),LONG,virtual                     ! two tests of one expression, one after the other, become one CASE
BuiltinIfChainToCase   Procedure(StringTheory pLog),LONG,virtual                       ! collapse an OR-chain of equality tests on ONE repeated PURE expression into a CASE;
                                                                                       !   bodies/ELSE/terminator untouched; refuses the whole IF on anything unusual
IfCasePureList         Procedure(StringTheory pOut),virtual                            ! the space-delimited UPPER list of calls allowed inside that repeated expression (rule files add more with PURE(a b))
PureMethod             Procedure(STRING pNameU, StringTheory pPure),BYTE,virtual       ! 1 = a name on that pure list is a reader AFTER an object's '.': a StringTheory method that leaves the object as it was
PureMethodAt           Procedure(LONG pParen, StringTheory pPure),BYTE,virtual         ! 1 = the call whose '(' is at pParen is a method PureMethod takes, on a receiver that is a StringTheory
PureOwnList            Procedure(StringTheory pPure, StringTheory pOut),virtual        ! the names on that pure list this file gives a PROCEDURE of its own - a body here or a MAP prototype
PureProc               Procedure(STRING pNameU, StringTheory pPure, StringTheory pOwn),BYTE,virtual ! 1 = a call of that name with no object in front is the runtime's own reader on the list, and no procedure of the file's
! --- KnownRanges (S3, runs by default): retire a guard / a choose() that provably cannot go the other way, and collapse a computed sub() length into a slice() ---
BuiltinKnownRanges     Procedure(StringTheory pLog),LONG,virtual                       ! value-range walk over each proc/method main code: `if C then S.` with C provably TRUE -> S; choose(C,A,B) with C decided -> A
                                                                                       !   or B; recv.sub(q, x - q + 1) -> recv.slice(q, x) when q and x are BOTH rk:posBound; every undecided comparison is left alone
BuiltinDeadGuard       Procedure(StringTheory pLog),LONG,virtual                       ! delete a guard THIS TOOL emitted when an earlier one proves it cannot fire
DgShapeAt              Procedure(LONG pIx, *STRING pRecvU, *LONG pEnd, *LONG pKeep),LONG,virtual !   the emitted choose() shape, on one receiver - pKeep is the one token that survives
DgProvenNonEmpty       Procedure(STRING pRecvU, LONG pIx, STRING pWant),LONG,virtual   !   ONE backward walk: dg:wantGuard / dg:wantTrim, both unproved by the same mutation list
DgMemberAt             Procedure(LONG pIx, STRING pRecvU),STRING,virtual               !   '.NAME' when this token uses our receiver - merged (c._DataEnd) or split (c . Free)
DgGuardAt              Procedure(LONG pIx, STRING pRecvU),LONG,virtual                 !   the whole one-line `if R._DataEnd < 1 then return`
BuiltinDeadLeft        Procedure(StringTheory pLog),LONG,virtual                       ! drop a left() that provably has nothing to strip - the receiver was Trim()med above and the read starts at character 1
DlShapeAt              Procedure(LONG pIx, *STRING pRecvU, *LONG pEnd),LONG,virtual    !   left( R.valuePtr[1 : ... / left( R.sub(1, ...
DgRecvAt               Procedure(LONG pIx, *STRING pRecvU, *STRING pMemU, *LONG pNext),LONG,virtual ! read a member reference and NAME its receiver, either spelling
DgOpenAfter            Procedure(LONG pIx),LONG,virtual                                !   where the call bracket is, whichever spelling the member has
DgArgCountAt           Procedure(LONG pOpenIx),LONG,virtual                            !   arguments at depth 1; 99 = not a call bracket at all
DgSetLeftProves        Procedure(LONG pOpenIx),LONG,virtual                            !   does this setLeft() strip leading SPACES? Its What argument may be a sum
DgLastDot              Procedure(STRING pTok),LONG,virtual                             !   the LAST dot - the receiver of self.buf._DataEnd is self.buf, not self
DgIsMemberDot          Procedure(LONG pIx),LONG,virtual                                !   a '.' that JOINS, not the '.' that closes a block
KnownRangePureList     Procedure(StringTheory pOut),virtual                            ! the space-delimited UPPER list of calls that can move neither a tracked value nor a bound (rule files add more with PURE(a b))
! --- TrailingSpaces (spaceless mode, runs by default): make "no trailing spaces" TRUE, then simplify the uses that ask about them ---
BuiltinTrailingSpaces  Procedure(StringTheory pLog),LONG,virtual                       ! per proc/method, per local StringTheory: find a top-level point from which EVERY use is blind to trailing
                                                                                       !   spaces AND cannot create any, insert recv.clip() there (once), and simplify the uses below it
TsMethodKind           Procedure(STRING pMethodU),LONG,virtual                         ! the ts:* kind a StringTheory method name COULD be, on its NAME alone; ts:bad for everything not on the
                                                                                       !   list. The caller still has to validate the arguments - this is the one place the whitelist lives
! --- Procedure summaries: what a proc/method body IN THIS FILE provably RETURNS ---
BuildSummaries         Procedure(),virtual                                             ! rebuild self.sums for the CURRENT token stream (called at the entry of every consumer)
SummaryOf              Procedure(STRING pOwnerU, STRING pNameU),BYTE,virtual           ! the sm:* fact for one body; sm:none when there is no row (another file, a refusal, or an ambiguous overload)
TicksSince             Procedure(LONG pT0),LONG,virtual                                ! clock() ticks (1/100 s) since pT0, across midnight - the --timing counters
NoteTime               Procedure(TimeRowQType pQ, STRING pName, LONG pTicks, LONG pChg),virtual ! --timing: add one call's ticks and changes to pName's row of pQ
RuleTag                Procedure(),STRING,virtual                                      ! --timing: 'rule' and the current rule's id, plus its NAME(...) when it has one
Secs                   Procedure(LONG pTicks),STRING,virtual                           ! --timing: ticks as seconds, two decimals, no padding
TimeBreakdown          Procedure(STRING pFn, StringTheory pLog),virtual                ! --timing: the per-built-in and slowest-rule lines after the summary line
SummaryOfCallAt        Procedure(LONG pFirst, LONG pLast, STRING pSelfClassU, *STRING pNameOut),BYTE,virtual ! the sm:* fact of the call occupying EXACTLY [pFirst..pLast]; pNameOut = the callee's source-case name, for the log
ArgReadsOnly           Procedure(LONG pArgTok, STRING pSelfClassU),BYTE,virtual        ! 1 = the bare argument at pArgTok goes to a body of this file whose summary says it only READS that parameter (ruled 14 Sep 2026)
StCopyRecv             Procedure(LONG pRecvTok, LONG pArgTok),BYTE,virtual             ! 1 = the receiver at pRecvTok is a plain StringTheory local, whose setValue or append only copies the argument
ArgFact                Procedure(LONG pArgTok, STRING pSelfClassU),STRING,virtual      ! what the call around the bare argument at pArgTok does with it: R reads, W writes, . may keep it, P pure call, F copies it and its flags, blank no answer (ruled 28 Oct 2026)
ArgMayKeep             Procedure(LONG pArgTok, STRING pSelfClassU),LONG,virtual        ! 1 = the call around the argument at pArgTok may keep its address: a second name for it that outlives the call
ParamErrRead           Procedure(LONG pArgTok),LONG,virtual                            ! 1 = the call around the bare argument at pArgTok may read that object's lastError or winErrorCode
ArgMayWrite            Procedure(LONG pS, LONG pE, STRING pRd, *BYTE pSm),BYTE,virtual ! 1 = a call around the whole argument pS..pE - a buffer, a slice of it, its _DataEnd - may write through it
ReadOnlyCallAt         Procedure(LONG pParen),BYTE,virtual                             ! 1 = the call whose '(' is at pParen only reads what it is handed: MESSAGE and the like, or a StringTheory method on a short list
LinesOptAt             Procedure(LONG pAt),BYTE,virtual                                ! the setValue, append or prepend at pAt (its '(', name or receiver): 1 = it is given st:lines, 2 = an option not read here may hold it
BareArgLines           Procedure(LONG pTok),BYTE,virtual                               ! an object named whole at pTok, an argument: 0 = the call is a setValue, append or prepend that copies no lines, else LinesOptAt's answer; 2 = any other call, or none
BareNameIsCall         Procedure(LONG pTok),LONG,virtual                               ! the name at pTok may be a call with no brackets - it is not placed as data, an equate or a member
BareCallAt             Procedure(LONG pTok),LONG,virtual                               ! BareNameIsCall, but a StringTheory's own _DataEnd or valuePtr is data even when its fields are not known
SmMethodKind           Procedure(STRING pMethodU),BYTE,virtual                         ! the sk:* a StringTheory method name COULD be, on its NAME alone - the one place that whitelist lives
SpaceKeepUse           Procedure(LONG pTok),LONG,virtual                               ! 1 = the use of the receiver AT pTok cannot put a space INTO the buffer
SpaceMakeUse           Procedure(LONG pTok),LONG,virtual                               ! 1 = the use of the receiver AT pTok is recv.removeByte(32) - it MAKES the buffer spaceless
! --- KeywordCase (OPT-IN, cosmetic): normalise reserved-word case ---
BuiltinKeywordCase     Procedure(StringTheory pLog),LONG,virtual                       ! recase type='r' keyword tokens to STYLE(lower|upper|title); identifiers untouched
RecaseWord             Procedure(STRING pText, STRING pStyleU),STRING,virtual          ! one word recased to the style (upper/title/lower)
CaseStyleWord          Procedure(STRING pWordU),STRING,virtual                         ! the one word for a keyword-case style: CAPITALISE, CAPITALIZE, CAMEL and PASCAL are TITLE; anything else is itself
IsScalarType           Procedure(STRING pUpperName),LONG,virtual                       ! 1 = a Clarion scalar data type that can never be a label (safe to recase)
IsRuntimeBuiltin       Procedure(STRING pUpperName),LONG,virtual                       ! 1 = a Clarion runtime builtin function (parser.IsRuntimeBuiltinName set); recase only in call position
IsClarionAttribute     Procedure(STRING pUpperName),LONG,virtual                       ! 1 = a decl/prototype attribute safe to recase after a ',' (dual-use TYPE/NAME/C/RAW excluded)
IsUserProc             Procedure(STRING pNameU),LONG,virtual                           ! 1 = pNameU is a user-declared proc/method here (so a builtin-named call that is really the user's proc is left alone)
BuiltinSplitStatements Procedure(StringTheory pLog),LONG,virtual                       ! split `a=1 ; b=2` at top-level ';' onto separate lines at the same indent; bail on any line with a level mark
LineIndent             Procedure(LONG pLineStart, StringTheory pOut),virtual           ! SplitStatements' indent: the trailing spaces and tabs of the line's first token's strBefore
SemiTriviaBad          Procedure(LONG pSemi, StringTheory pTriv),BYTE,virtual          ! SplitStatements: 1 = beside the ';' is a line break that is not a '|' continuation
SemiToBreak            Procedure(LONG pSemi, StringTheory pIndent, StringTheory pTriv),BYTE,PROC,virtual ! SplitStatements: the ';' becomes the line break, the next statement takes pIndent; 1 = words kept
BuiltinChooseClip      Procedure(StringTheory pLog),LONG,virtual                       ! drop a dead clip() from the END of any ARM of a choose() assigned to a STRING - any number of arms, which is why it cannot be rules
BuiltinInstringToST    Procedure(StringTheory pLog, BYTE pLit=0),LONG,virtual          ! instring(needle, hay, 1[, start]) on a STRING variable becomes st.findChars(needle,
                                                                                       !   start,, hay) on a StringTheory already in scope - none in scope, no change
BuiltinInstringSliceToST Procedure(StringTheory pLog),LONG,virtual                     ! instring(x, st.valuePtr[lo : hi], 1[, start]) becomes st.findChars(x[, start][, hi]) - always on
BuiltinBracketAndOr    Procedure(StringTheory pLog),LONG,virtual                       ! where AND sits beside OR or XOR at one level, each AND run is bracketed - group and-or-brackets, off
BuiltinRejoinWrapped   Procedure(StringTheory pLog),LONG,virtual                       ! the inverse of SplitWideLines: a statement wrapped over two lines that would now FIT on one is put back. OPT-IN, own group, OFF
BuiltinExpandOneLiners Procedure(StringTheory pLog),LONG,virtual                       ! inline `if C then S. [else T.]` (THEN or the ';' separator form) -> block
                                                                                       !   form; flat single IF only, bail on extra-';'/ELSIF/nested/comment
BuiltinBlockEndStyle   Procedure(StringTheory pLog),LONG,virtual                       ! whole-line block terminator '.' <-> END via STYLE(end|period); inline/stacked terminators left
BuiltinContOp          Procedure(StringTheory pLog),LONG,virtual                       ! BUILTIN ContOp - which side of a wrapped line s break the AND/OR/& sits on
ContOpBarTok           Procedure(LONG pTok),LONG,virtual                               ! where a REAL continuation bar sits in that token s leading trivia, or 0
ContOpIsOp             Procedure(LONG pTok),LONG,virtual                               ! AND, OR or & at bracket depth 0 - the same three padPrev knows
ContOpDepth            Procedure(LONG pTok),LONG,virtual                               ! how many brackets are open in front of it on its own logical line
ContOpMove             Procedure(LONG pFrom, LONG pTo, StringTheory pLog),LONG,virtual ! hand the bar-carrying trivia across the operator
ContOpStmtIndent       Procedure(LONG pTok, StringTheory pOut),virtual                 ! the indent of the PHYSICAL LINE pTok sits on - what flush lines an operator up with
ContOpFlushOnly        Procedure(LONG pTok),LONG,virtual                               ! an operator ALREADY at the front still owes flush its column - re-indent, move nothing
BuiltinReindent        Procedure(StringTheory pLog),LONG,virtual                       ! normalise executable block-body indent to WIDTH(n) from level marks; col-1
                                                                                       !   labels/data sections skipped; stack anchored to each opener's indent
! --- AutoCheck: ,AUTO safety analysis (definite-assignment). The design doc AutoCheck-spec.md is not shipped; see BuiltinAutoCheck ---
BuiltinAutoCheck       Procedure(StringTheory pLog),LONG,virtual                       ! ADD/REMOVE ,AUTO on SAFE/UNSAFE simple locals
AutoEligible           Procedure(LONG pSymRow, LONG pPersistOk=0),LONG,virtual         ! 1 = a simple scalar local worth analysing (not param/ref/like/over/dim/routine-touched); pPersistOk
UnseenRead             Procedure(STRING pNameU),LONG,virtual                           ! 1 = named in another declaration, 2 = an INCLUDE, 3 = its storage escapes: read where the code scans cannot see
                                                                                       !   keeps PERSISTENT locals (STATIC and THREAD) in - it says which question the caller is asking,
                                                                                       !   "can this live on the stack" (no) or "does anything read it" (yes, storage is irrelevant)
AutoVerdict            Procedure(LONG pSymRow),LONG,virtual                            ! ac:safe / ac:unsafe / ac:unknown by definite-assignment over the scope CODE
NameRefdInRange        Procedure(STRING pNameU, LONG pStart, LONG pEnd),LONG,virtual   ! bare-label token = pNameU anywhere in [pStart,pEnd] (member/qualified excluded)
CodeTokOfScope         Procedure(LONG pStart, LONG pEnd),LONG,virtual                  ! token pos of the first col-1 'CODE' in the scope, else 0

ScopeIsConditional     Procedure(LONG pFromTok, LONG pToTok),LONG,virtual              ! OMIT/COMPILE in the range - the code there may not be part of THIS build at all
InCondBlock            Procedure(LONG pTok),LONG,virtual                               ! pTok lies in a COMPILE or conditional OMIT block some build leaves out
CondBlockAt            Procedure(LONG pTok, LONG pFrom=0),LONG,virtual                 ! the COMPILE or OMIT token of the innermost such block open at pTok, 0 = none
CondLeavesOut          Procedure(LONG pTok, LONG pRef),LONG,virtual                    ! some build leaves pTok out and keeps pRef: pTok is in a COMPILE or OMIT block pRef is not in
DeclIsSure             Procedure(LONG pSymRow, LONG pRef),LONG,virtual                 ! 1 = that row is the one declaration pRef reads in every build: declared once, in no block pRef is not in
MarkSetterAt           Procedure(STRING pNameU, LONG pFirst, LONG pLast, *BYTE pEnc),LONG,virtual ! the first mention that can set the object's base64 flag or encoding, or 0
NameShared             Procedure(LONG pTok, STRING pNameU),LONG,virtual                ! the storage has a second name: OVER, a &= on it, a field, a by-address parameter
ParamByAddr            Procedure(LONG pEnd),LONG,virtual                               ! the header parameter that ends at pEnd is passed by address
AddrParamsOf           Procedure(LONG pScope, LONG pSkip),LONG,virtual                 ! how many of the scope's parameters pass by address, pSkip's left out
MgRhsShared            Procedure(LONG pS, LONG pE),LONG,virtual                        ! MergeGuardChain: a right-hand side reads storage with a second name
PreOf                  Procedure(STRING pNameU, LONG pTok),STRING,virtual              ! the label of the structure a prefixed name's PRE belongs to, or blank
TriviaHasContinuation  Procedure(STRING pTrivia),LONG,virtual                          ! a '|' in leading trivia that is NOT inside a comment
LevelSpanBalanced      Procedure(LONG pS, LONG pE),LONG,virtual                        ! 0 = opens outlive the span - refuse the walk
SpanTriviaHasComment   Procedure(LONG pFromTok, LONG pToTok),LONG,virtual              ! a comment - a '!', or words after a '|' - in any of those tokens' leading trivia
BuiltinMergeGuardChain Procedure(StringTheory pLog),LONG,virtual                       ! consecutive single-line IFs setting the SAME thing -> one
MgSpanText             Procedure(LONG pS, LONG pE, StringTheory pOut),virtual          ! tokens joined, one space each
MgOneCharTest          Procedure(LONG pS, LONG pE, StringTheory pRecv),LONG,virtual    ! r.containsByte(n) -> n
MgAllDigits            Procedure(STRING pTxt),LONG,virtual                             ! every character is 0-9
MgSpanRaw              Procedure(LONG pS, LONG pE, StringTheory pOut),virtual          ! tokens AS WRITTEN
MgCondIsPure           Procedure(LONG pS, LONG pE, StringTheory pPure, StringTheory pAdd, StringTheory pOwn),LONG,virtual ! every call in the span only READS, so the test may be short-circuited
MgBareCall             Procedure(LONG pS, LONG pE, BYTE pStore),LONG,virtual           ! a name in the span may be a call with no brackets; pStore = 1 asks the right-hand sides only
MgCollapseRuns         Procedure(),LONG,virtual                                        ! one condition testing the same receiver for several characters -> one containsA
MgPlainRecv            Procedure(LONG pS, LONG pE),LONG,virtual                        ! the span is a bare name chain a, a.b, a.b.c - and NOTHING else. An
                                                                                       !   operator, a '~' or a call in there means the receiver is not a receiver
MgSameStmt             Procedure(StringTheory pA, StringTheory pB),LONG,virtual        ! same statement? case-blind for code, AS WRITTEN once a literal is in it
MgQualClash            Procedure(StringTheory pLhs, StringTheory pRhs),LONG,virtual    ! a qualified name in play against a non-constant: two spellings, one storage
MgOneStore             Procedure(StringTheory pOne, StringTheory pLhs, StringTheory pRhs),LONG,virtual ! ONE store; the target and the source come back so the caller can cross-check parts
MgStmtRepeatable       Procedure(StringTheory pStmt),LONG,virtual                      ! running this statement ONCE is the same as running it N times. A merge does
                                                                                       !   exactly that, so a chain whose body is not repeatable must not merge
MgAlphaFix             Procedure(StringTheory pAlpha),LONG,virtual                     ! fit the alphabet for containsA, which CLIPS it:
                                                                                       !   0 = unusable, all spaces
MgLitAlphabet          Procedure(StringTheory pAlpha, StringTheory pOut),virtual       ! the alphabet as a Clarion literal body, in the CANONICAL spelling
MgLitByte              Procedure(LONG pB, StringTheory pOut),virtual                   ! one byte, escaped for a Clarion literal
MgCmtText              Procedure(LONG pEolTok, StringTheory pOut),virtual              ! the trailing comment on this line, WHOLE - read at flush time, so no fixed field can cut an author's words down to fit it
DropLinesKeepCmts      Procedure(LONG pFirst, LONG pLastEol, LONG pCarryS=0, LONG pCarryE=0),LONG,PROC,virtual ! drop these lines; each comment comes back as a line at the first line's indent, and a folded OMIT block stays; returns how many
EolHasCmt              Procedure(LONG pEol),BYTE,virtual                               ! 1 = this EOL carries a trailing comment (the peek a log line takes before the drop)
TriviaCmtRows          Procedure(LONG pTok, StringTheory pOut),LONG,virtual            ! the comments riding this token's leading trivia - a '!', or words after a '|' - a row each
CmtRowsJoin            Procedure(StringTheory pRows, StringTheory pAcc),virtual        ! those rows joined onto pAcc as ONE comment
CmtToLineEnd           Procedure(LONG pEol, StringTheory pCmt),virtual                 ! a carried comment goes in front of this line's own, as one comment
TxaMarkOff             Procedure(StringTheory pS),BYTE,PROC,virtual                    ! on a .txa, the shift marker comes off the end of this text; 1 = it was there
TxaShiftOf             Procedure(LONG pTok),BYTE,virtual                               ! on a .txa, 1 = the line pTok is on began in column 1, so it ends with the shift marker
TxaMarkLines           Procedure(StringTheory pTxt, BYTE pShf),virtual                 ! on a .txa, each line of pTxt loses its shift marker and, when pShf, ends with one
                                                                                       !
HoistAliasRisk         Procedure(LONG pTokPos, STRING pNameU),LONG,virtual             ! could the hoist's lhs be read through an OVER alias? refuses when it cannot tell
HoistDbgMarker         Procedure(LONG pTok),LONG,virtual                               ! the line starts with a column-1 '?' - the DEBUG marker, which moving would unmake
HoistDbgPad            Procedure(StringTheory pIndent),STRING,virtual                  ! the indent for such a line, less the column the marker itself occupies
HoistTargetsClear      Procedure(LONG pFirst, LONG pCEnd, LONG pCS, LONG pCE),LONG,virtual ! every statement on the hoisted LINE clears the condition, not just the first
HasSiblingOver         Procedure(LONG pSymRow, STRING pNameU),LONG,virtual             ! another decl in this scope is OVER this one - the fifth spelling of one storage
DeclHasAttr            Procedure(LONG pDeclTok, STRING pAttrU),LONG,virtual            ! decl line carries the attribute keyword (AUTO/OVER/DIM/...), as a real token
DeclHasInitValue       Procedure(LONG pDeclTok),LONG,virtual                           ! the declaration's initial value: 1 = a number's, which can go; 2 = a string literal, which sets the length too; 0 = none
DropInitValue          Procedure(LONG pDeclTok, StringTheory pWas),LONG,proc,virtual   ! take a number's initial value out of the declaration; pWas = the type as it was written
DeclLineMentions       Procedure(LONG pDeclTok, STRING pNameU),LONG,virtual            ! does the decl LINE mention pNameU (e.g. OVER(V))?
AutoScopePrep          Procedure(LONG pScopeId),virtual                                ! fill the ac* cache for a scope (no-op when already cached)
RecvForeignUse         Procedure(LONG pRecvTok),LONG,virtual                           ! some use of this object is NOT a StringTheory method
RecvDeclAt             Procedure(STRING pNameU, LONG pTok),LONG,virtual                ! the declaration a plain name means at this token, or 0
RecvIsOtherClass       Procedure(LONG pRecvTok),LONG,virtual                           ! this receiver PROVABLY names something that is not a StringTheory
DgMemberIsTarget       Procedure(LONG pTok),LONG,virtual                               ! this member is the TARGET of an assignment, not a read
DgStmtIsBareName       Procedure(LONG pTok),LONG,virtual                               ! the statement is a bare name
                                                                                       !   - a call with no brackets
DgRecvIsLocal          Procedure(STRING pRecvU, LONG pAtTok),LONG,virtual              ! the receiver is a LOCAL, so a parenless PROCEDURE call cannot reach it
DeclIsString1          Procedure(LONG pDeclTok),LONG,virtual                           ! this declaration is a STRING(1) - so a DIM'd element is still one char
NameSliceOk            Procedure(STRING pNameU, LONG pAtTok),LONG,virtual              ! a single-index pick of this name is PROVABLY one char - don't know refuses
DeclAttrBits           Procedure(LONG pDeclTok),LONG,virtual                           ! one decl-line walk -> ab:* bitmask
CommentLineStart       Procedure(LONG pTok, STRING pHeader),virtual                    ! insert pHeader at the PHYSICAL line start (after the last LF in strBefore)
AutoOutArgWrite        Procedure(LONG pTok, STRING pPrevU),LONG,virtual                ! 9b: 1 = a builtin writes V via an output arg here (CLEAR(V..)/GETPOSITION(feq,V..))
ProtoParamIsRef        Procedure(LONG pProtoTok, LONG pPos, VitTokenize pTk),LONG,virtual ! 1 = parameter pPos of that prototype is declared BY REFERENCE
AutoArgIsRefParam      Procedure(LONG pTok, BYTE pUnknown=0),LONG,virtual              ! 1 = the name at pTok is an argument in a BY-REFERENCE slot
RuntimeSlotByValue     Procedure(STRING pU, LONG pOpen, LONG pSlot),LONG,virtual       ! 1 = the Clarion runtime's prototypes of pU take that slot of the call at pOpen by value
AutoAddrTaken          Procedure(LONG pTok, STRING pPrevU),LONG,virtual                ! 1 = V's ADDRESS is taken here, so the storage escapes and nothing is known
AutoSizeOnly           Procedure(LONG pTok, STRING pPrevU),LONG,virtual                ! 1 = V is the whole argument of SIZE(), which reads no byte of it - neither a read nor a write
AutoTokIsWrite         Procedure(LONG pTok),LONG,virtual                               ! 1 = the name token at pTok is an assignment TARGET. Used for the ZERO GUARD, where the question is asked about a name other than the one being walked
DeclLastTok            Procedure(LONG pDeclTok),LONG,virtual                           ! last token of the declaration statement (same line, before any trailing comment/EOL)
AddAutoAttr            Procedure(LONG pDeclTok),LONG,virtual                           ! append ',AUTO' to the decl; 1 = edited
RemoveAutoAttr         Procedure(LONG pDeclTok, StringTheory pNote),LONG,virtual       ! strip ',AUTO', append NOTE comment; 1 = edited
LineOfTok              Procedure(LONG pTok),LONG,virtual                               ! token queue lineNo
WidthPolicy            Procedure(StringTheory pSrc),virtual                            ! width limit from the source's own prevailing width. ONE copy, called by BOTH entry points.
LogLineOf              Procedure(LONG pTok),LONG,virtual                               ! LOG-facing line of a token: SOURCE coordinates in preview (tk.MapLine), stream line in batch. pLog use ONLY - never logic
GetSingleCharVal       Procedure(STRING pStr),LONG,virtual                             ! 0-255 or -1: 'x', '<13>', '''', doubled pairs, bare single digit
IsSingleChar           Procedure(STRING pStr),LONG,virtual                             ! GetSingleCharVal <> -1
CharName               Procedure(STRING pStr),STRING,virtual                           ! vtxaDiff DescribeChar: <tab>/<carriage return>/... else the literal itself
LitTruncate            Procedure(StringTheory pInOut, LONG pWant),virtual              ! truncate a RAW quoted literal to pWant logical chars (escape-aware)
LitBytes               Procedure(STRING pLit, StringTheory pOut),LONG,virtual          ! the bytes a RAW quoted literal stands for, escapes read, into pOut; 0 = not well formed
SpanHasNL              Procedure(LONG pS, LONG pE),LONG,virtual                        ! any strBefore in span carries a line break (comment/continuation)
RejoinReparse          Procedure(),virtual                                             ! join -> reparse -> rebuild symbols
TxaPreProcess          Procedure(StringTheory pSrc),virtual                            ! .txa -> something the tokenizer can read
TxaPreOne              Procedure(StringTheory pSt),virtual                             !   one application within it
TxaPostProcess         Procedure(StringTheory pOut),virtual                            ! ... and exactly back again
TxaAnalysisRefused     Procedure(STRING pBuiltin),LONG,virtual                         ! 1 = this analysis is RESTRICTED on a .txa (per-scope gate does the restricting)
ScopeFullyEmbedded     Procedure(LONG pStartTok, LONG pEndTok),LONG,virtual            ! 1 = scope sits wholly inside one .txa embed (always 1 on a .clw)
CommentTriviaLines     Procedure(LONG pTok),virtual                                    ! '!' every complete absorbed line inside pTok's strBefore (span commenting)
WriteOutput            Procedure(STRING pFn, StringTheory pLog),virtual
AddBanner              Procedure(StringTheory pOut),virtual                            ! the Processed-by line at the top of the text about to be written - after !ABCIncludeFile when that is line 1
OutName                Procedure(STRING pFn),STRING,virtual                            ! outDir\name or pFn (in-place)
BackupName             Procedure(STRING pFn),STRING,virtual                            ! in-place backup path: stamp before the extension + '.bak' (e.g. Foo on 20260714 at 1430.clw.bak)
Progress               Procedure(STRING pMsg),virtual                                  ! overwrite progressFn with one status line
                    END

! ---- the engine's answer to the isPlain() rule guard: it asks the engine that owns it ----
VitEnginePlainAsk   CLASS(VitPlainAsk),TYPE,MODULE('VitEngine.clw'),LINK('VitEngine.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
eng                    &VitEngine                                                      ! not owned
IsPlain                Procedure(LONG pTok),BYTE,virtual
MarksSafe              Procedure(LONG pTok),BYTE,virtual
                    END
