! VitEngine Class - Phase 5 of VitTransform (generalised Clarion code transformer)
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
!  - Builtins dispatch through DoBuiltin (virtual). TWENTY-ONE are wired; none
!    is a stub any more. AlignComments is the odd one out - cosmetic, so it is
!    deferred and run once after the fixpoint has converged, and it never counts
!    as a fixpoint change. The vtxaDiff009 ports (CombineAdjacentLiterals,
!    RemoveDoubledBrackets, the Check* family) work on self.tk; after a builtin
!    edits tokens RunPass rebuilds the symbol table, mirroring VitRewrite.
!    THE CASE IN DoBuiltin IS THE INVENTORY. Do not keep a list of them here:
!    a list in a comment goes stale the moment a builtin is added, and the CASE
!    cannot.
!    A builtin may set wantReparse to request rejoin->reparse->resymbol
!    (the UnusedVars OVER-cascade mechanism).
!  - ONCE is enforced by VitMatch (first match per scan) + VitRewrite.onceQ
!    (across passes). WHERE guards are evaluated by VitMatch.GuardOK.
!
! Requires StringTheory, VitTokenize, VitRules, VitSymbols, VitMatch,
! VitRewrite, VitTimer.
!
  INCLUDE('VitRewrite.inc'),ONCE
  INCLUDE('Preprocessor.inc'),ONCE                                                 ! .red-driven include expansion for the cross-file type registry

! AutoCheck verdicts. The design doc AutoCheck-spec.md is NOT shipped -
! the reasoning that matters is written out at BuiltinAutoCheck in VitEngine.clw
! DeclAttrBits masks
ab:auto               EQUATE(1)
ab:over               EQUATE(2)
ab:dim                EQUATE(4)
ab:static             EQUATE(8)
ab:thread             EQUATE(16)

RoutSpanQType         QUEUE,TYPE                                                   ! routine token spans of the cached scope
rStart                  LONG
rEnd                    LONG
                      END

DotRootQType          QUEUE,TYPE                                                   ! ROOTS of merged dotted tokens in the cached scope (guard, amortized)
rootU                   STRING(vs:maxName)
                      END

ac:unknown            EQUATE(0)                                                    ! default: touch nothing
ac:safe               EQUATE(1)                                                    ! assigned before every read on every path -> may ADD ,AUTO
ac:unsafe             EQUATE(2)                                                    ! read before write on some path -> may REMOVE ,AUTO

! KnownRanges - the value-range lattice.  Deliberately tiny: every fact records the
! receiver it is bounded by, and ANY doubt collapses to rk:none (see BuiltinKnownRanges).
rk:none               EQUATE(0)                                                    ! unknown - the default, and what any doubt collapses to
rk:zeroBound          EQUATE(1)                                                    ! 0 <= x <= <receiver>._DataEnd
rk:posBound           EQUATE(2)                                                    ! 1 <= x <= <receiver>._DataEnd
rk:nonNeg             EQUATE(3)                                                    ! x >= 0, no upper bound (no receiver)

! --receiver=: what to do about a Check* builtin's receiver when the symbol table cannot
! resolve it. These builtins find their work by METHOD NAME, so they can be pointed at any
! object that happens to have a same-named method (see README, D.3).
rm:assume             EQUATE(0)                                                    ! rewrite it as a StringTheory, identified or not
rm:check              EQUATE(1)                                                    ! DEFAULT: refuse if any use of it in scope is not a StringTheory method
rm:strict             EQUATE(2)                                                    ! refuse unless it PROVABLY resolves to a StringTheory

! DeadGuard / DeadLeft - which fact the ONE backward walk is being asked to prove about
! a receiver. Both are proved the same way and unproved by the same mutation list; only
! the statement being looked for differs (see VitEngine.DgProvenNonEmpty).
dg:wantGuard          EQUATE('GUARD')                                              ! NOT EMPTY, from   if R._DataEnd < 1 then return.
dg:wantTrim           EQUATE('TRIM')                                               ! NO LEADING SPACE, from   R.Trim()  or  R.setLeft()

! TrailingSpaces - how ONE textual use of a StringTheory receiver is classified.
! ts:bad is the default and any doubt collapses to it (see BuiltinTrailingSpaces).
ts:bad                EQUATE(0)                                                    ! the use may OBSERVE trailing spaces, or may CREATE them - refuses the region
ts:read               EQUATE(1)                                                    ! blind read: same answer with or without trailing spaces, and writes nothing
ts:cleanSet           EQUATE(2)                                                    ! clip()/trim()/removeByte(32)/setValue(x,st:clip) - the buffer is provably clean after it
ts:clipLen            EQUATE(3)                                                    ! recv.clipLength() - a blind read AND the target of simplification A1
ts:anchor             EQUATE(4)                                                    ! clip(recv.getValue()) - a blind read AND the target of simplification A2
ts:bare               EQUATE(5)                                                    ! a BARE receiver token (foo(st), st &= other) - refuses the receiver for the whole scope

! PROCEDURE SUMMARIES - what a procedure or method body IN THIS FILE provably RETURNS.
! sm:none is the default and ANY doubt collapses to it (see BuildSummaries). A summary is about
! the RETURN VALUE and nothing else - it says NOTHING about what the body did to a *STRING
! argument, and must never be read as if it did.
sm:none               EQUATE(0)                                                    ! unknown - the default, and what any doubt collapses to
sm:spaceless          EQUATE(1)                                                    ! the returned STRING contains NO SPACES AT ALL. Stronger than "no trailing
                                                                                   !   spaces" on purpose: setLength(n) truncates INTO the string, so only
                                                                                   !   "no spaces anywhere" rules out a cut EXPOSING one (DEVIATION 1)
sm:nonNeg             EQUATE(2)                                                    ! the returned number is >= 0
sm:posBound           EQUATE(3)                                                    ! the returned number is >= 1

! what ONE use of a StringTheory receiver can do to the SPACES in its buffer. This is a
! DIFFERENT question from the ts:* (which asks about TRAILING spaces and about blindness), so it
! is a separate ladder - see VitEngine.SmMethodKind, the one place this whitelist lives.
sk:bad                EQUATE(0)                                                    ! may put a space into the buffer, or we cannot tell - refuses
sk:read               EQUATE(1)                                                    ! reads only; writes nothing at all
sk:keep               EQUATE(2)                                                    ! writes, but can only REMOVE or TRUNCATE - a spaceless buffer stays spaceless
sk:strip              EQUATE(3)                                                    ! removeByte(n) - keeps, and removeByte(32) MAKES the buffer spaceless
sk:store              EQUATE(4)                                                    ! setValue(...) - the ARGUMENTS decide, and only a spaceless call qualifies
sk:repl               EQUATE(5)                                                    ! replace(old, new) - keeps only while `new` is a literal with no space in it
sk:trunc              EQUATE(6)                                                    ! setLength(n) - NOT sk:keep. StringTheory.SetLength GROWS as well as
                                                                                   !   truncates, padding the new space with byte 32, so it can put trailing
                                                                                   !   spaces INTO a spaceless buffer. Refused everywhere (it is absent from
                                                                                   !   SpaceKeepUse's CASE, so it lands on the safe default); the only place
                                                                                   !   it is ever accepted is TsTruncGuard, which matches the author's own
                                                                                   !   same-line proof that the call shrinks. Keep it OUT of that CASE.

TsProvenQType         QUEUE,TYPE                                                   ! one row per guarded setLength TrailingSpaces has ALREADY proved
tpNameU                 STRING(vs:maxName)                                         ! UPPER declaration label of the proc/method the proof was made in.
                                                                                   !   NOT the scopeId. Ids are positional and a scope-REMOVING
                                                                                   !   builtin (UnusedRoutines) renumbers them mid-run, so a banked proof
                                                                                   !   could migrate to a different procedure that inherited the id - and
                                                                                   !   `st` / `p - 1` are exactly the names that repeat. The label is
                                                                                   !   stable across a reparse unless the procedure is renamed, in which
                                                                                   !   case the proof simply stops matching and we refuse, as before.
tpRecvU                 STRING(vs:maxName)                                         ! UPPER receiver the proof is about
tpArgU                  STRING(vs:maxName)                                         ! UPPER setLength argument, token text joined - the proof's identity
                      END

SumQType              QUEUE,TYPE                                                   ! one row per proc/method body we could summarise
smOwnerU                STRING(vs:maxName)                                         ! UPPER class name for a method; '' for a plain procedure
smNameU                 STRING(vs:maxName)                                         ! UPPER procedure / method name
smFact                  BYTE                                                       ! sm:*
                      END

VitEngine           CLASS,TYPE,MODULE('VitEngine.clw'),LINK('VitEngine.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
rl                     &VitRules                                                   ! not owned
tk                     &VitTokenize                                                ! owned
syms                   &VitSymbols                                                 ! owned
rw                     &VitRewrite                                                 ! owned
tmr                    &VitTimer                                                   ! owned (class members must be references - GCR note)
pp                     &Preprocessor                                               ! include preprocessor (owned; NULL until SetupIncludes)
exptk                  &VitTokenize                                                ! tokenizer for the include-expanded source (owned)
ppLineMap              &LineMapQueue                                               ! expanded-line -> origin header (owned)
ppSrc                  &StringTheory                                               ! expanded source buffer (owned)
recvMode               BYTE                                                        ! rm:assume / rm:check / rm:strict
dgPure                 &StringTheory                                               ! KnownRangePureList, for the
                                                                                   !   DeadGuard fact walk
stMeth                 &StringTheory                                               ! ' NAME NAME ' - every StringTheory method
useIncludes            BYTE                                                        ! include expansion enabled (SetupIncludes succeeded)
redPath                STRING(260)                                                 ! .red redirection file
rootDir                STRING(260)                                                 ! %ROOT% (Clarion install dir, e.g. c:\Clarion11)
config                 STRING(32)                                                  ! %CONFIGURATION% (Debug/Release)
! engine switches (CLI)
dryRun                 BYTE
verbose                BYTE
loose                  BYTE
widthArg               LONG                                                        ! --width=N. 0 = not given, use the per-file scan. -1 = --width=0, never split.
splitWidth             LONG                                                        ! the limit SplitWideLines works to. Absolute (200), NOT the per-file scan - see WidthPolicy.
acDiag                 BYTE                                                        ! --acdiag - passed to the tokenizer so AlignComments explains itself
onlyId                 LONG                                                        ! --only=<ruleId>  (0 = all)
skipId                 LONG                                                        ! --skip=<ruleId>  (0 = none)
outDir                 STRING(260)                                                 ! blank = in-place (only when inPlace set)
outSuffix              STRING(120)                                                 ! inserted before the extension of each output file (--outsuffix= and/or --outstamp)
inPlace                BYTE                                                        ! --in-place: overwrite originals (outDir blank); a timestamped .bak of each changed file is kept first
stamp                  STRING(40)                                                  ! ' on yyyymmdd at hhmmssth' - one per run; used by --outstamp and the in-place backup name
maxPasses              LONG                                                        ! default 20
! per-run state
totalChanges           LONG
filesChanged           LONG
filesDone              LONG
saveErrors             LONG                                                        ! failed WriteOutput saves (e.g. missing output dir)
loadErrors             LONG                                                        ! sources that were asked for and could not be loaded - these reach ERRORLEVEL
ppErrors               LONG                                                        ! headers that could not be expanded - the type registry is then incomplete
curPass                LONG
wantReparse            BYTE                                                        ! set by a builtin to request rejoin/reparse
rulesDirty             BYTE                                                        ! a level-hazard rule replacement fired since the last reparse. A MEMBER, not a
                                                                                   !   RunPass local: a rule that fires AFTER the last builtin of a pass must still force
                                                                                   !   the reparse before the NEXT pass's first builtin (and before the deferred FINAL
                                                                                   !   pass) - as a local the flag died at RunPass exit and the damage leaked across.
                                                                                   !   Cleared by RejoinReparse itself (whoever reparses, the stream is fresh).
sawAlign               BYTE                                                        ! AlignComments requested by the rule file (run once, after convergence)
txaSaid                BYTE                                                        ! the refusal has been logged for this file (once, not once per pass)
isTxa                  BYTE                                                        ! the current file is a .txa (template export), not plain source.
                                                                                   !   Set by TransformFile from the extension. It turns on the
                                                                                   !   pre/post wrap below AND refuses the three analyses that
                                                                                   !   cannot see template-generated code - see TxaPreProcess.
tsProven               &TsProvenQType                                              ! guarded-setLength proofs carried ACROSS passes (owned; per FILE, freed in TransformFile/TransformText)
progressFn             STRING(260)                                                 ! live progress file, overwritten per step; blank = off
progLast               LONG                                                        ! last Progress() write (clock centisec) - throttle disk writes
acScopeId              LONG                                                        ! scope the ac* cache below describes (0 = none)
acCodeT                LONG
acMainEnd              LONG
acBail                 BYTE                                                        ! GOTO/COMPILE/OMIT in the scope (or no CODE) -> verdict UNKNOWN
acWhyLine              LONG                                                        ! diag: source line of the token that made AutoVerdict return UNSAFE (0 = n/a)
acWhyTxt               STRING(900)                                                 ! diag: conviction state + push/pop ledger for the traced symbol
acWhyElig              STRING(80)                                                  ! WHY: why AutoEligible refused the last symbol it was asked about ('' = it did not)
acRoutQ                &RoutSpanQType                                              ! routines of the cached scope
acDotQ                 &DotRootQType                                               ! sorted roots of the scope's merged dotted tokens (may hold dups; hit/miss lookup only)
sums                   &SumQType                                                   ! per-file procedure summaries (owned); rebuilt by BuildSummaries at every consumer entry
curFile                STRING(260)

Construct              Procedure()
Destruct               Procedure()
Init                   Procedure(VitRules pRl),virtual
SetupIncludes          Procedure(STRING pRedPath, STRING pRootDir, STRING pConfig),BYTE,PROC,virtual ! enable include expansion; returns 1 if enabled
TransformFile          Procedure(STRING pFn, StringTheory pLog),LONG,PROC,virtual  ! returns changes for this file
TransformText          Procedure(StringTheory pSrc, StringTheory pOut, StringTheory pLog),LONG,PROC,virtual ! in-process preview - transform a text buffer, never writes; pOut = transformed text, returns change count. Uses the SAME parse/symbols/fixpoint/resolver as TransformFile (honesty invariant).
RunPass                Procedure(StringTheory pLog),LONG,virtual                   ! one pass; returns its change count
RepHasLevelKeyword     Procedure(),LONG,virtual                                    ! current rule replacement carries IF/LOOP/CASE/ELSE/END/... (level damage possible)
DoBuiltin              Procedure(LONG pRow, StringTheory pLog),LONG,virtual        ! change count; may set wantReparse
BuiltinCombineLiterals Procedure(StringTheory pLog),LONG,virtual                   ! 'abc' & 'xyz' -> 'abcxyz'; '<13><10>' -> '<13,10>' (vtxaDiff port)
BuiltinDoubledBrackets Procedure(StringTheory pLog),LONG,virtual                   ! foo((x)) -> foo(x) (vtxaDiff port)
BuiltinCheckCase       Procedure(StringTheory pLog),LONG,virtual                   ! case 'x' -> case val('x') -> integers + name comments (vtxaDiff checkCaseStatements + checkVals)
BuiltinCheckReplaces   Procedure(StringTheory pLog),LONG,virtual                   ! replace() arg cleanup + replaceByte/removeByte (vtxaDiff port)
BuiltinCheckRemoves    Procedure(StringTheory pLog),LONG,virtual                   ! remove() arg cleanup + removeByte (vtxaDiff port)
BuiltinCheckSplits     Procedure(StringTheory pLog),LONG,virtual                   ! st.split() positional booleans -> st:clip / st:left
BuiltinCheckInLine     Procedure(StringTheory pLog),LONG,virtual                   ! st.inline() -> st:noCase / st:wholeLine / st:begins / st:clip
BuiltinCheckCat        Procedure(StringTheory pLog),LONG,virtual                   ! cat -> Append incl. literal truncation (vtxaDiff port)
BuiltinUnusedVars      Procedure(StringTheory pLog),LONG,virtual                   ! comment out unused declarations; internal OVER-cascade (vtxaDiff CheckForUnusedVars)
RemoveUnusedPass       Procedure(StringTheory pPrefix, StringTheory pExclU, StringTheory pLog),LONG,virtual ! one scan of the symbol table; returns count commented
SymUsed                Procedure(STRING pNameU, LONG pStart, LONG pEnd, LONG pDeclLine),LONG,virtual ! name referenced as a token after its decl line, within scope
! --- UnusedRoutines: comment out routines never invoked via DO in their owning proc ---
BuiltinUnusedRoutines  Procedure(StringTheory pLog),LONG,virtual                   ! comment out unreferenced ROUTINEs; DO-cascade via wantReparse
RemoveUnusedRoutinesPass Procedure(StringTheory pPrefix, StringTheory pExclU, StringTheory pLog),LONG,virtual ! one scan of routine scopes; returns count commented
RoutineReferenced      Procedure(STRING pNameU, LONG pProcStart, LONG pProcEnd),LONG,virtual ! a `DO <pNameU>` token pair anywhere in the owning proc span
CommentOutSpan         Procedure(LONG pStartTok, LONG pEndTok, STRING pHeader),LONG,PROC,virtual ! '!'-prefix every first-on-line token in the span (header on line 1); returns lines commented
! --- UnreachableCode: comment code after an unconditional RETURN/EXIT/BREAK/CYCLE/GOTO ---
BuiltinUnreachableCode Procedure(StringTheory pLog),LONG,virtual                   ! comment statements after an unconditional transfer, per scope
RemoveUnreachablePass  Procedure(StringTheory pPrefix, StringTheory pLog),LONG,virtual ! one scan of proc/method/routine exec ranges
WalkUnreachable        Procedure(LONG pExecStart, LONG pExecEnd, StringTheory pPrefix, StringTheory pLog),LONG,virtual ! dead-state walk over one code range; returns lines commented
IsTransferKw           Procedure(STRING pKwU),LONG,virtual                         ! RETURN/EXIT/BREAK/CYCLE/GOTO = unconditional transfer of control
FirstTokAfterLine      Procedure(LONG pTok),LONG,virtual                           ! first token on a later line than pTok's (0 if none) - routine exec start when no CODE keyword
! --- UnusedAssignments: comment assignments to a simple local never READ (write-only var) ---
BuiltinUnusedAssignments Procedure(StringTheory pLog),LONG,virtual                 ! comment dead stores (whole-var assignments to never-read locals)
RemoveDeadStoresPass   Procedure(StringTheory pPrefix, StringTheory pLog),LONG,virtual ! one scan: per eligible local, classify reads/writes; comment writes if 0 reads
PerStoreDeadStores     Procedure(LONG pCodeT, LONG pEndT, STRING pNameU, BYTE pAllowEnd, StringTheory pPrefix, StringTheory pLog),LONG,virtual ! v2: straight-line per-store liveness (overwritten-before-read) for a read>0 var; pAllowEnd=0 for STATIC/THREAD
RhsSingleSafe          Procedure(LONG pAssignTok),LONG,virtual                     ! 1 = RHS is a single non-'(' token ending the line (no call, no continuation) = side-effect-free
! --- HoistCommonBranchCode: move common trailing code out of an IF/ELSE/END (END-hoist) ---
BuiltinHoistCommonBranchCode Procedure(StringTheory pLog),LONG,virtual             ! one hoist per pass, wantReparse -> fixpoint peels a run one line at a time
HoistOnePass           Procedure(StringTheory pLog),LONG,virtual                   ! find the first clean IF/ELSE/END and END-hoist (then START-hoist) one common statement
HoistFindElse          Procedure(LONG pIfTok, LONG pEndTok),LONG,virtual           ! single depth-1 ELSE token, or 0 if not a clean two-branch IF (ELSIF/OF/no-else/multi)
TryEndHoist            Procedure(LONG pIfTok, LONG pElseTok, LONG pEndTok, StringTheory pLog),LONG,virtual ! perform the END-hoist if both trailing statements are identical single lines; 1=done
TryStartHoist          Procedure(LONG pIfTok, LONG pElseTok, LONG pEndTok, StringTheory pLog),LONG,virtual ! perform the gated START-hoist if both leading statements are identical + independent of C; 1=done
StartMove              Procedure(LONG pSrc, LONG pDst, LONG pNum),virtual          ! backward block relocation (pDst<pSrc), order-preserving, via per-token MoveTok
FirstEolAfter          Procedure(LONG pTok),LONG,virtual                           ! first <10> token after pTok (0 if none)
SpanHasParen           Procedure(LONG pS, LONG pE),LONG,virtual                    ! a '(' anywhere in the span (call/grouping)
NameRoot               Procedure(STRING pName),STRING,virtual                      ! the name before any '.' or
                                                                                   !   ':' - what the STORAGE is
SpanHasName            Procedure(STRING pNameU, LONG pS, LONG pE),LONG,virtual     ! a label token caselessly = pNameU in the span
StmtIsPlainAssign      Procedure(LONG pFirst, LONG pCEnd),LONG,virtual             ! `label = ...` with no call -> only effect is writing the lhs
IsFirstOnLine          Procedure(LONG pTok),LONG,virtual                           ! token's firstOnLine flag (0 on error)
IsEolTok               Procedure(LONG pTok),LONG,virtual                           ! token is the physical newline (<10>)
LineStartOf            Procedure(LONG pEolTok),LONG,virtual                        ! first-on-line token of the line ending at pEolTok (0 if blank/error)
LineHasLevelMark       Procedure(LONG pFirst, LONG pEol),LONG,virtual              ! any +/-/'/' level mark in the line -> not a simple statement
LineHasComment         Procedure(LONG pFirst, LONG pEol),LONG,virtual              ! a '!' in any of the line's trivia (leading/interior/trailing)
LineCommentText        Procedure(LONG pFirst, LONG pEol, StringTheory pOut),virtual ! the line's comment TEXT, normalised - identical comments must not block a hoist
SpanTokEqual           Procedure(LONG pAF, LONG pAE, LONG pBF, LONG pBE),LONG,virtual ! caseless token-for-token span equality
! --- IfChainToCase (OPT-IN): `if E = a or E = b ... elsif E = c` -> `case E / of a orof b / of c` ---
BuiltinIfChainToCase   Procedure(StringTheory pLog),LONG,virtual ! collapse an OR-chain of equality tests on ONE repeated PURE expression into a CASE; bodies/ELSE/terminator untouched; refuses the whole IF on anything unusual
IfCasePureList         Procedure(StringTheory pOut),virtual ! the space-delimited UPPER list of calls allowed inside that repeated expression (rule files add more with PURE(a b))
! --- KnownRanges (S3, OPT-IN): retire a guard / a choose() that provably cannot go the other way, and collapse a computed sub() length into a slice() ---
BuiltinKnownRanges     Procedure(StringTheory pLog),LONG,virtual ! value-range walk over each proc/method main code: `if C then S.` with C provably TRUE -> S; choose(C,A,B) with C decided -> A or B; recv.sub(q, x - q + 1) -> recv.slice(q, x) when q and x are BOTH rk:posBound; every undecided comparison is left alone
BuiltinDeadGuard       Procedure(StringTheory pLog),LONG,virtual                   ! delete a guard THIS TOOL emitted when an earlier one proves it cannot fire
DgShapeAt              Procedure(LONG pIx, *STRING pRecvU, *LONG pEnd, *LONG pKeep),LONG,virtual !   the emitted choose() shape, on one receiver - pKeep is the one token that survives
DgProvenNonEmpty       Procedure(STRING pRecvU, LONG pIx, STRING pWant),LONG,virtual !   ONE backward walk: dg:wantGuard / dg:wantTrim, both unproved by the same mutation list
DgMemberAt             Procedure(LONG pIx, STRING pRecvU),STRING,virtual           !   '.NAME' when this token uses our receiver - merged (c._DataEnd) or split (c . Free)
DgGuardAt              Procedure(LONG pIx, STRING pRecvU),LONG,virtual             !   the whole one-line `if R._DataEnd < 1 then return`
BuiltinDeadLeft        Procedure(StringTheory pLog),LONG,virtual ! drop a left() that provably has nothing to strip - the receiver was Trim()med above and the read starts at character 1
DlShapeAt              Procedure(LONG pIx, *STRING pRecvU, *LONG pEnd),LONG,virtual !   left( R.valuePtr[1 : ... / left( R.sub(1, ...
DgRecvAt               Procedure(LONG pIx, *STRING pRecvU, *STRING pMemU, *LONG pNext),LONG,virtual ! read a member reference and NAME its receiver, either spelling
DgOpenAfter            Procedure(LONG pIx),LONG,virtual                            !   where the call bracket is, whichever spelling the member has
DgArgCountAt           Procedure(LONG pOpenIx),LONG,virtual                        !   arguments at depth 1; 99 = not a call bracket at all
DgSetLeftProves        Procedure(LONG pOpenIx),LONG,virtual                        !   does this setLeft() strip leading SPACES? Its What argument may be a sum
DgLastDot              Procedure(STRING pTok),LONG,virtual                         !   the LAST dot - the receiver of self.buf._DataEnd is self.buf, not self
DgIsMemberDot          Procedure(LONG pIx),LONG,virtual                            !   a '.' that JOINS, not the '.' that closes a block
KnownRangePureList     Procedure(StringTheory pOut),virtual ! the space-delimited UPPER list of calls that can move neither a tracked value nor a bound (rule files add more with PURE(a b))
! --- TrailingSpaces (spaceless mode, OPT-IN): make "no trailing spaces" TRUE, then simplify the uses that ask about them ---
BuiltinTrailingSpaces  Procedure(StringTheory pLog),LONG,virtual ! per proc/method, per local StringTheory: find a top-level point from which EVERY use is blind to trailing spaces AND cannot create any, insert recv.clip() there (once), and simplify the uses below it
TsMethodKind           Procedure(STRING pMethodU),LONG,virtual ! the ts:* kind a StringTheory method name COULD be, on its NAME alone; ts:bad for everything not on the list. The caller still has to validate the arguments - this is the one place the whitelist lives
! --- Procedure summaries: what a proc/method body IN THIS FILE provably RETURNS ---
BuildSummaries         Procedure(),virtual                                         ! rebuild self.sums for the CURRENT token stream (called at the entry of every consumer)
SummaryOf              Procedure(STRING pOwnerU, STRING pNameU),BYTE,virtual       ! the sm:* fact for one body; sm:none when there is no row (another file, a refusal, or an ambiguous overload)
SummaryOfCallAt        Procedure(LONG pFirst, LONG pLast, STRING pSelfClassU, *STRING pNameOut),BYTE,virtual ! the sm:* fact of the call occupying EXACTLY [pFirst..pLast]; pNameOut = the callee's source-case name, for the log
SmMethodKind           Procedure(STRING pMethodU),BYTE,virtual                     ! the sk:* a StringTheory method name COULD be, on its NAME alone - the one place that whitelist lives
SpaceKeepUse           Procedure(LONG pTok),LONG,virtual                           ! 1 = the use of the receiver AT pTok cannot put a space INTO the buffer
SpaceMakeUse           Procedure(LONG pTok),LONG,virtual                           ! 1 = the use of the receiver AT pTok is recv.removeByte(32) - it MAKES the buffer spaceless
! --- KeywordCase (OPT-IN, cosmetic): normalise reserved-word case ---
BuiltinKeywordCase     Procedure(StringTheory pLog),LONG,virtual                   ! recase type='r' keyword tokens to STYLE(lower|upper|title); identifiers untouched
RecaseWord             Procedure(STRING pText, STRING pStyleU),STRING,virtual      ! one word recased to the style (upper/title/lower)
IsScalarType           Procedure(STRING pUpperName),LONG,virtual                   ! 1 = a Clarion scalar data type that can never be a label (safe to recase)
IsRuntimeBuiltin       Procedure(STRING pUpperName),LONG,virtual                   ! 1 = a Clarion runtime builtin function (parser.IsRuntimeBuiltinName set); recase only in call position
IsClarionAttribute     Procedure(STRING pUpperName),LONG,virtual                   ! 1 = a decl/prototype attribute safe to recase after a ',' (dual-use TYPE/NAME/C/RAW excluded)
IsUserProc             Procedure(STRING pNameU),LONG,virtual ! 1 = pNameU is a user-declared proc/method here (so a builtin-named call that is really the user's proc is left alone)
BuiltinSplitStatements Procedure(StringTheory pLog),LONG,virtual                   ! split `a=1 ; b=2` at top-level ';' onto separate lines at the same indent; bail on any line with a level mark
BuiltinExpandOneLiners Procedure(StringTheory pLog),LONG,virtual ! inline `if C then S. [else T.]` (THEN or the ';' separator form) -> block form; flat single IF only, bail on extra-';'/ELSIF/nested/comment
BuiltinBlockEndStyle   Procedure(StringTheory pLog),LONG,virtual                   ! whole-line block terminator '.' <-> END via STYLE(end|period); inline/stacked terminators left
BuiltinReindent        Procedure(StringTheory pLog),LONG,virtual ! normalise executable block-body indent to WIDTH(n) from level marks; col-1 labels/data sections skipped; stack anchored to each opener's indent
! --- AutoCheck: ,AUTO safety analysis (definite-assignment). The design doc AutoCheck-spec.md is not shipped; see BuiltinAutoCheck ---
BuiltinAutoCheck       Procedure(StringTheory pLog),LONG,virtual                   ! ADD/REMOVE ,AUTO on SAFE/UNSAFE simple locals
AutoEligible           Procedure(LONG pSymRow, LONG pPersistOk=0),LONG,virtual ! 1 = a simple scalar local worth analysing (not param/ref/like/over/dim/routine-touched); pPersistOk keeps PERSISTENT locals (STATIC and THREAD) in - it says which question the caller is asking, "can this live on the stack" (no) or "does anything read it" (yes, storage is irrelevant)
AutoVerdict            Procedure(LONG pSymRow),LONG,virtual                        ! ac:safe / ac:unsafe / ac:unknown by definite-assignment over the scope CODE
NameRefdInRange        Procedure(STRING pNameU, LONG pStart, LONG pEnd),LONG,virtual ! bare-label token = pNameU anywhere in [pStart,pEnd] (member/qualified excluded)
CodeTokOfScope         Procedure(LONG pStart, LONG pEnd),LONG,virtual              ! token pos of the first col-1 'CODE' in the scope, else 0

ScopeIsConditional     Procedure(LONG pFromTok, LONG pToTok),LONG,virtual          ! OMIT/COMPILE in the range -
TriviaHasContinuation  Procedure(STRING pTrivia),LONG,virtual                      ! a '|' in leading trivia that
LevelSpanBalanced      Procedure(LONG pS, LONG pE),LONG,virtual                    ! 0 = opens outlive the span - refuse the walk (#1/#17)
SpanTriviaHasComment   Procedure(LONG pFromTok, LONG pToTok),LONG,virtual          ! a '!' in any of those tokens'
BuiltinMergeGuardChain Procedure(StringTheory pLog),LONG,virtual                   ! consecutive single-line IFs
                                                                                   !   setting the SAME thing -> one
MgSpanText             Procedure(LONG pS, LONG pE, StringTheory pOut),virtual      ! tokens joined, one space each
MgOneCharTest          Procedure(LONG pS, LONG pE, StringTheory pRecv),LONG,virtual ! r.containsByte(n) -> n
MgAllDigits            Procedure(STRING pTxt),LONG,virtual                         ! every character is 0-9
|' in leading trivia that
MgSpanRaw              Procedure(LONG pS, LONG pE, StringTheory pOut),virtual      ! tokens AS WRITTEN
MgCondIsPure           Procedure(LONG pS, LONG pE, StringTheory pPure),LONG,virtual ! every call in the span
                                                                                    !   only READS, so the test
                                                                                    !   may be short-circuited
                                                                                    !   is NOT inside a comment
                                                                                    !   the code there may not be
                                                                                    !   part of THIS build at all
MgCollapseRuns         Procedure(),LONG,virtual                                    ! one condition testing the
                                                                                   !   same receiver for several
                                                                                   !   characters -> one containsA
MgPlainRecv            Procedure(LONG pS, LONG pE),LONG,virtual                    ! the span is a bare name chain
                                                                                   !   a, a.b, a.b.c - and NOTHING
                                                                                   !   else. An operator, a '~' or
                                                                                   !   a call in there means the
                                                                                   !   receiver is not a receiver
MgSameStmt             Procedure(StringTheory pA, StringTheory pB),LONG,virtual    ! same statement? case-blind
                                                                                   !   for code, AS WRITTEN once a
                                                                                   !   literal is in it
MgQualClash            Procedure(StringTheory pLhs, StringTheory pRhs),LONG,virtual ! a qualified name in play
                                                                                    !   against a non-constant:
                                                                                    !   two spellings, one storage
MgOneStore             Procedure(StringTheory pOne, StringTheory pLhs, StringTheory pRhs),LONG,virtual ! ONE store; the target and
                                                                                   !   the source come back so the
                                                                                   !   caller can cross-check parts
MgStmtRepeatable       Procedure(StringTheory pStmt),LONG,virtual                  ! running this statement ONCE
                                                                                   !   is the same as running it
                                                                                   !   N times. A merge does
                                                                                   !   exactly that, so a chain
                                                                                   !   whose body is not
                                                                                   !   repeatable must not merge
MgAlphaFix             Procedure(StringTheory pAlpha),LONG,virtual                 ! fit the alphabet for
                                                                                   !   containsA, which CLIPS it:
                                                                                   !   0 = unusable, all spaces
MgLitAlphabet          Procedure(StringTheory pAlpha, StringTheory pOut),virtual   ! the alphabet as a Clarion
                                                                                   !   literal body, in the
                                                                                   !   CANONICAL spelling
MgLitByte              Procedure(LONG pB, StringTheory pOut),virtual               ! one byte, escaped for a
                                                                                   !   Clarion literal
MgCmtText              Procedure(LONG pEolTok, StringTheory pOut),virtual          ! the trailing comment on
                                                                                   !   this line, WHOLE - read at
                                                                                   !   flush time, so no fixed
                                                                                   !   field can cut an author's
                                                                                   !   words down to fit it
                                                                                   !
HoistAliasRisk         Procedure(LONG pTokPos, STRING pNameU),LONG,virtual         ! could the hoist's lhs be read
                                                                                   !   through an OVER alias? refuses
                                                                                   !   when it cannot tell
HasSiblingOver         Procedure(LONG pSymRow, STRING pNameU),LONG,virtual         ! another decl in this scope
                                                                                   !   is OVER this one - the fifth
                                                                                   !   spelling of one storage
DeclHasAttr            Procedure(LONG pDeclTok, STRING pAttrU),LONG,virtual        ! decl line carries the attribute keyword (AUTO/OVER/DIM/...), as a real token
DeclLineMentions       Procedure(LONG pDeclTok, STRING pNameU),LONG,virtual        ! does the decl LINE mention pNameU (e.g. OVER(V))?
AutoScopePrep          Procedure(LONG pScopeId),virtual                            ! fill the ac* cache for a scope (no-op when already cached)
RecvForeignUse         Procedure(LONG pRecvTok),LONG,virtual                       ! some use of this receiver
                                                                                   !   in scope is NOT a
                                                                                   !   StringTheory method
RecvIsOtherClass       Procedure(LONG pRecvTok),LONG,virtual                       ! this receiver PROVABLY names
                                                                                   !   something that is not a
                                                                                   !   StringTheory
DgMemberIsTarget       Procedure(LONG pTok),LONG,virtual                           ! this member is the TARGET of
                                                                                   !   an assignment, not a read
DgStmtIsBareName       Procedure(LONG pTok),LONG,virtual                           ! the statement is a bare name
                                                                                   !   - a call with no brackets
DgRecvIsLocal          Procedure(STRING pRecvU, LONG pAtTok),LONG,virtual          ! the receiver is a LOCAL, so
                                                                                   !   a parenless PROCEDURE call
                                                                                   !   cannot reach it
DeclIsString1          Procedure(LONG pDeclTok),LONG,virtual                       ! this declaration is a
                                                                                   !   STRING(1) - so a DIM'd
                                                                                   !   element is still one char
NameSliceOk            Procedure(STRING pNameU, LONG pAtTok),LONG,virtual          ! a single-index pick of this
                                                                                   !   name is PROVABLY one char -
                                                                                   !   don't know refuses
DeclAttrBits           Procedure(LONG pDeclTok),LONG,virtual                       ! one decl-line walk -> ab:* bitmask
CommentLineStart       Procedure(LONG pTok, STRING pHeader),virtual                ! insert pHeader at the PHYSICAL line start (after the last LF in strBefore)
AutoOutArgWrite        Procedure(LONG pTok, STRING pPrevU),LONG,virtual            ! 9b: 1 = a builtin writes V via an output arg here (CLEAR(V..)/GETPOSITION(feq,V..))
DeclLastTok            Procedure(LONG pDeclTok),LONG,virtual                       ! last token of the declaration statement (same line, before any trailing comment/EOL)
AddAutoAttr            Procedure(LONG pDeclTok),LONG,virtual                       ! append ',AUTO' to the decl; 1 = edited
RemoveAutoAttr         Procedure(LONG pDeclTok, StringTheory pNote),LONG,virtual   ! strip ',AUTO', append NOTE comment; 1 = edited
LineOfTok              Procedure(LONG pTok),LONG,virtual                           ! token queue lineNo
WidthPolicy            Procedure(StringTheory pSrc),virtual                        ! width limit from the source's own prevailing width. ONE copy, called by BOTH entry points.
LogLineOf              Procedure(LONG pTok),LONG,virtual ! LOG-facing line of a token: SOURCE coordinates in preview (tk.MapLine), stream line in batch. pLog use ONLY - never logic
GetSingleCharVal       Procedure(STRING pStr),LONG,virtual                         ! 0-255 or -1: 'x', '<13>', '''', doubled pairs, bare single digit
IsSingleChar           Procedure(STRING pStr),LONG,virtual                         ! GetSingleCharVal <> -1
CharName               Procedure(STRING pStr),STRING,virtual                       ! vtxaDiff DescribeChar: <tab>/<carriage return>/... else the literal itself
LitTruncate            Procedure(StringTheory pInOut, LONG pWant),virtual          ! truncate a RAW quoted literal to pWant logical chars (escape-aware)
SpanHasNL              Procedure(LONG pS, LONG pE),LONG,virtual                    ! any strBefore in span carries a line break (comment/continuation)
RejoinReparse          Procedure(),virtual                                         ! join -> reparse -> rebuild symbols
TxaPreProcess          Procedure(StringTheory pSrc),virtual                        ! .txa -> something the tokenizer can read
TxaPreOne              Procedure(StringTheory pSt),virtual                         !   one application within it
TxaPostProcess         Procedure(StringTheory pOut),virtual                        ! ... and exactly back again
TxaAnalysisRefused     Procedure(STRING pBuiltin),LONG,virtual                     ! 1 = this analysis is RESTRICTED on a .txa (per-scope gate does the restricting)
ScopeFullyEmbedded     Procedure(LONG pStartTok, LONG pEndTok),LONG,virtual        ! 1 = scope sits wholly inside one .txa embed (always 1 on a .clw)
CommentTriviaLines     Procedure(LONG pTok),virtual                                ! '!' every complete absorbed line inside pTok's strBefore (span commenting)
WriteOutput            Procedure(STRING pFn, StringTheory pLog),virtual
OutName                Procedure(STRING pFn),STRING,virtual                        ! outDir\name or pFn (in-place)
BackupName             Procedure(STRING pFn),STRING,virtual                        ! in-place backup path: stamp before the extension + '.bak' (e.g. Foo on 20260714 at 1430.clw.bak)
Progress               Procedure(STRING pMsg),virtual                              ! overwrite progressFn with one status line
                    END
