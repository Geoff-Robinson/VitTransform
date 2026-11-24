! VitMatch Class - the matcher of VitTransform (generalised Clarion code transformer)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Anchored matching over a VitTokenize token queue, driven by the VitRules IR,
! with the type questions (typed metavars, class tests, WHERE guards) answered
! through VitSymbols. Covers anchor selection, EXPR/ARGS extents, repeated-metavar
! equality, auto-guards, interior-comment skip. Reports match spans + metavar
! bindings; no rewriting (that is VitRewrite).
!
! Also declares VitGolden - runner for golden-format match tests. In the
! match-only variant the expect block holds the match report rather than
! rewritten code. Report line format produced per match:
!   rule <id> line <n>: <matched tokens joined by single spaces>
!     <metavar> = <bound tokens>          (one line per binding, 2-space indent)
! and for a skipped match:
!   rule <id> line <n> SKIP interior-comment: <matched tokens>
!
! Requires StringTheory, VitTokenize, VitRules.
!
  INCLUDE('VitRules.inc'),ONCE
  INCLUDE('VitSymbols.inc'),ONCE

MatchBindQType        QUEUE,TYPE                                                      ! one metavar binding within the current match
mvx                     LONG                                                          ! metaVars row
sPos                    LONG                                                          ! first token of bound span (source token queue)
ePos                    LONG                                                          ! last token; ePos < sPos = empty span (ARGS)
                      END

MatchRecQType         QUEUE,TYPE                                                      ! one captured match (capture mode, for the rewriter)
sPos                    LONG
ePos                    LONG
skipped                 BYTE                                                          ! interior-comment skip
ruleRow                 LONG                                                          ! the rule (rules queue row) that found it - the group walk captures for several rules at once
                      END

BindRecQType          QUEUE,TYPE                                                      ! binding snapshot per captured match
matchIx                 LONG                                                          ! matches row this binding belongs to
mvx                     LONG
sPos                    LONG
ePos                    LONG
                      END

GroupMemQType         QUEUE,TYPE                                                      ! one rule in a group walk (MatchGroup): its MatchRule state, restored at each anchor occurrence
ruleRow                 LONG                                                          ! rules queue row
ruleId                  LONG
patCount                LONG
gdStmt                  BYTE
gdNoDot                 BYTE
gdNoSelf                BYTE
gd1Lit                  BYTE
gd1IdMv                 BYTE
gd2Dot                  BYTE
anchorIx                LONG
anchorTx                STRING(200)                                                   ! the anchor's text (a rule with a longer literal walks alone)
anchorOp                STRING(4)
preLit                  STRING(96)
preLitOn                BYTE
once                    BYTE
lastEnd                 LONG                                                          ! this member's own lastEnd, carried between occurrences
done                    BYTE                                                          ! ONCE and matched: out of the walk
nMatch                  LONG                                                          ! matches recorded for it
dChain                  LONG                                                          ! what its turns added to chainUnres,
dRtf                    LONG                                                          !   rtFallbacks,
dSkip                   LONG                                                          !   skipCount
dMatch                  LONG                                                          !   and matchCount - replayed when the cached answer stands in for a scan
                      END

LitIdxQType           QUEUE,TYPE                                                      ! every (pattern literal key, rule) pair, sorted - which rules COULD anchor on a key
keyText                 STRING(80)
ruleRow                 LONG
                      END

! Anchor-count cache (perf). Without it PickAnchor re-scans the whole token
! stream (CountTok, O(tokens)) for every pattern literal of
! every rule every pass - fine for goldens, but O(rules x literals x tokens x
! passes) over many files. Instead: collect the distinct pattern literals ONCE
! (BuildAnchorLits, sorted for binary search), then refresh their occurrence
! counts with ONE pass over the tokens whenever the stream changes
! (freqDirty). CountTok becomes an O(log distinctLiterals) lookup. keyText is
! LitMatches' notion of identity: quoted literals compared exactly (leading
! '), everything else upper-cased; truncation to the key width only ever
! MERGES distinct literals (overcount) - safe, since undercount is the only
! thing that could wrongly skip a rule, and this never undercounts.
AnchorLitQType        QUEUE,TYPE
keyText                 STRING(80)                                                    ! FreqKey of a pattern literal (quoted: exact; else upper); trunc 80 = overcount-safe
cnt                     LONG                                                          ! occurrences in the current token stream (valid while ~freqDirty)
                      END

AnchorPostQType       QUEUE,TYPE                                                      ! one posting per OCCURRENCE of a pattern literal in the stream
keyText                 STRING(80)                                                    ! same identity as AnchorLitQType.keyText
pos                     LONG                                                          ! token position
                      END

PatchSpanQType        QUEUE,TYPE                                                      ! one row per applied match of a firing rule: the span it replaced, in the
a                       LONG                                                          !   token positions of BEFORE the rule fired, and how many tokens stand
b                       LONG                                                          !   there now (the postings are PATCHED from these, not rebuilt)
n                       LONG
                      END

ChainMissQType        QUEUE,TYPE                                                      ! DISTINCT dotted receivers a typed rule refused because the
recvU                   STRING(vs:maxName)                                            !   class or the member is NOT VISIBLE - not because it was the
                      END                                                             !   WRONG class, which is an ordinary no-match and stays silent

PendMissQType         QUEUE,TYPE                                                      ! grouped dispatch: a receiver a group-walk member refused, held until that member's own turn so the list above reads in the classic order
ruleRow                 LONG
recv                    STRING(vs:maxName)
                      END

! ---- what the isPlain() rule guard asks: is the StringTheory named at token pTok a plain local, that
!      nothing but the code around it can reach, mark, stream or hand on? The engine knows, and answers
!      through a class derived from this one; this one answers 0, so with no asker the guard refuses ----
VitPlainAsk         CLASS,TYPE,MODULE('VitMatch.clw'),LINK('VitMatch.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
IsPlain                Procedure(LONG pTok),BYTE,virtual                              ! 1 = plain
MarksSafe              Procedure(LONG pTok),BYTE,virtual                              ! 1 = --ignoremarks, or plain
                    END

VitMatch            CLASS,TYPE,MODULE('VitMatch.clw'),LINK('VitMatch.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
rl                     &VitRules
tk                     &VitTokenize
syms                   &VitSymbols                                                    ! NULL = untyped matching, no type gates
plainAsk               &VitPlainAsk                                                   ! isPlain()'s answer, not owned; NULL = the guard refuses
loose                  BYTE                                                           ! --loose: typed metavars downgraded to ANYVAR
ocLenOnly              BYTE                                                           ! isOneChar on a CSTRING or PSTRING: only len(w) = 1 proves one character
verbose                BYTE                                                           ! log near-misses (type fails) to vlog
vlog                   &StringTheory                                                  ! optional near-miss log target (not owned)
binds                  &MatchBindQType
matches                &MatchRecQType                                                 ! captured matches (capture mode)
bindRecs               &BindRecQType                                                  ! captured binding snapshots (capture mode)
capture                BYTE                                                           ! when true, RecordMatch also fills matches/bindRecs
patQ                   &RulePartQType                                                 ! current rule's pattern (reference, not owned)
patCount               LONG
anchorLits             &AnchorLitQType                                                ! distinct pattern literals + live counts (owned); NULL until first Init
anchorPost             &AnchorPostQType                                               ! postings (keyText,pos) sorted - MatchRule iterates its anchor's occurrences instead of every token
freqDirty              BYTE                                                           ! anchorLits counts stale (token stream changed) - refresh on next CountTok
tRefresh               LONG                                                           ! --timing: clock ticks spent in RefreshFreq this file, and how many rebuilds
nRefresh               LONG
spanQ                  &PatchSpanQType                                                ! the spans a firing rule replaced since the last refresh (owned; NotePatch)
patchable              BYTE                                                           ! the postings can be PATCHED from spanQ - 0 after a re-lex or a built-in edit, which have no spans
spanVer                LONG                                                           ! the stream version every span now in spanQ was measured against - spans of two versions cannot be patched together
postCheck              BYTE                                                           ! --postcheck: after every patch, rebuild in full and compare
postPatched            LONG                                                           !   patches made this file, and
postMiss               LONG                                                           !   how many the check found wrong (the rebuild is then kept)
tPatch                 LONG                                                           ! --timing: clock ticks in PatchPostings, and how many
nPatch                 LONG
ruleId                 LONG
matchCount             LONG
skipCount              LONG
lastEnd                LONG                                                           ! last source token consumed by a match of current rule
gdNoDot                BYTE                                                           ! auto-guard: no '.' immediately before match start
gdNoSelf               BYTE                                                           ! auto-guard: receiver metavar must not bind SELF
gdStmt                 BYTE                                                           ! auto-guard: statement-anchored (DELETE / COMMENT / multi-stmt rep / a ';' in the pattern / assignment)
gd1Lit                 BYTE                                                           ! pattern part 1 is a literal token
gd1IdMv                BYTE                                                           ! pattern part 1 is an identifier metavar
gd2Dot                 BYTE                                                           ! pattern part 2 is '.'
anchorIx               LONG                                                           ! the pattern part PickAnchor chose (0 = none)
preLit                 STRING(96)                                                     ! the literal that must stand right in front of the anchor - SetPreLit
preLitOn               BYTE                                                           !   and whether this rule has one to check by
anchorOp               STRING(4)                                                      ! the anchor as a canonical comparator ('' = it is not one) - set by EnterRule
anchDot                BYTE                                                           ! the anchor is a pattern '.' that ENDS a fragment - it matches a block TERMINATOR, the one dot LitMatches refuses
pat1NotOp              STRING(4)                                                      ! pattern part 1 is the word NOT opening a two-word operator - this is that operator, canonical ('' = it is not)
pat1Expr               BYTE                                                           ! pattern part 1 is an EXPR metavar - a candidate start may not be a word that opens or continues a statement (IF, RETURN, LOOP ...), which no expression begins with
repNot                 BYTE                                                           ! the replacement opens with ~ or NOT - under EXPREND a comparison AFTER the match refuses it too, because ~a = b is ~(a = b)
capRow                 LONG                                                           ! the rules row a captured match is tagged with (matches.ruleRow)
streamVer              LONG                                                           ! counts the token stream's changes (Changed); the rewriter's match cache is keyed by it
grpQ                   &GroupMemQType                                                 ! the members of the group walk in progress (owned)
litIdx                 &LitIdxQType                                                   ! (key, rule) pairs from BuildAnchorLits (owned) - the group walk's candidate members
deferMiss              BYTE                                                           ! inside a group walk, a member other than the leader has its turn: refused receivers go to pendMissQ, not the list
pendMissQ              &PendMissQType                                                 ! those receivers, by member (owned); the rewriter lists them at the member's turn
rtFallbacks            LONG                                                           ! times the six-name fallback fired this file (engine logs when non-zero + resets)
chainUnres             LONG                                                           ! typed matches refused this file because a dotted receiver's class or member could not be RESOLVED
                                                                                      !   AT ALL. The commonest cause is the class being declared in an INCLUDE, which is invisible
                                                                                      !   without --thorough - the one silent miss users actually hit. A WRONG class is not counted.
chainMissQ             &ChainMissQType                                                ! the distinct receivers behind that count (capped; owned)

Construct              Procedure()
Destruct               Procedure()
Init                   Procedure(VitRules pRl, VitTokenize pTk),virtual
MatchAll               Procedure(StringTheory pReport),LONG,PROC,virtual              ! all non-SKIP rules; returns match count
MatchRule              Procedure(LONG pRow, StringTheory pReport),virtual             ! pRow = rules queue row number

! --- internals (left virtual for tinkering) ---
ClassifyGuards         Procedure(),virtual
PickAnchor             Procedure(StringTheory pAnchor),LONG,virtual                   ! source occurrence count; -1 = pattern has no literal
SetPreLit              Procedure(LONG pCount),virtual                                 ! after PickAnchor: is there a literal to check in front of the anchor?
PreLitOK               Procedure(LONG pI),LONG,virtual                                ! 1 = the anchor posting at pI has it (or its two-word NOT spelling)
PatFacts               Procedure(),virtual                                            ! the per-rule pattern facts the candidate gates read: anchDot and pat1NotOp, once each
Changed                Procedure(),virtual                                            ! the token stream changed: freqDirty, and streamVer up
EnterRule              Procedure(LONG pRow, StringTheory pAnchor),LONG,virtual        ! MatchRule's per-rule set-up; returns PickAnchor's count (0 = nothing to match)
TryPosting             Procedure(LONG pI, LONG pStmt, STRING pAnchorTx, StringTheory pReport),LONG,virtual ! MatchRule's work at one anchor occurrence; 1 = a match was recorded
MatchGroup             Procedure(STRING pKey, StringTheory pReport),LONG,PROC,virtual ! the postings of pKey walked once for every member of grpQ (grouped dispatch)
AddMember              Procedure(LONG pRow, StringTheory pAnchor),virtual             ! the rule just entered joins grpQ
LoadMember             Procedure(),virtual                                            ! the grpQ buffer's member becomes the current rule
CountTok               Procedure(STRING pLit),LONG,virtual                            ! occurrences of a pattern literal (cached via anchorLits)
BuildAnchorLits        Procedure(),virtual                                            ! collect distinct pattern literals once; sorted for binary search
RefreshFreq            Procedure(),virtual                                            ! recount anchorLits over the current token stream (one pass)
RefreshInto            Procedure(AnchorLitQType pLits, AnchorPostQType pPost),virtual ! the same walk into the queues given - RefreshFreq's body, and --postcheck's reference
NotePatch              Procedure(LONG pA, LONG pB, LONG pN),virtual                   ! a firing rule replaced tokens pA..pB (positions before it fired) with pN tokens
PatchPostings          Procedure(),virtual                                            ! bring anchorLits/anchorPost up to date from spanQ - shift, drop, re-post the new spans
FindAnchorLit          Procedure(STRING pKey),LONG,virtual                            ! binary search anchorLits by key; 0 = absent
FindFirstPost          Procedure(STRING pKey),LONG,virtual                            ! FIRST anchorPost row for key; 0 = absent
FreqKey                Procedure(STRING pTok, *STRING pKeyOut),virtual                ! LitMatches identity key: quoted exact, else upper, trunc 80
CandOK                 Procedure(LONG pS),LONG,virtual                                ! cheap shape gate before a full TryFrom
TryFrom                Procedure(LONG pS, StringTheory pReport),LONG,virtual          ! 0 = no match, else last matched token pos
MatchHere              Procedure(LONG pP, LONG pS),LONG,virtual                       ! 0 = fail, else source pos AFTER matched span
LitMatches             Procedure(LONG pIx, *STRING pLit),LONG,virtual                 ! source token vs pattern literal (quoted = exact). *STRING: never written, and the hottest test in the matcher
OpCanon                Procedure(STRING pTok),STRING,virtual                          ! canonical spelling of an LRM combined operator ('=<' -> '<<='), '' if it has no synonym
OpCanonNot             Procedure(*STRING pTok),STRING,virtual                         ! class of an infix NOT plus this token: 'NOT <' is >=, not <
AnchorNotPair          Procedure(LONG pIx, *STRING pAnchorOp),LONG,virtual            ! does the two-word NOT operator at pIx spell pAnchorOp (already canonical - computed once per rule)
NotInfixAt             Procedure(LONG pS),LONG,virtual                                ! is the NOT at pS the INFIX one of 'A NOT = B', not the prefix NOT of 'IF NOT x = 1'
TypeOK                 Procedure(LONG pMvx, LONG pS),LONG,virtual                     ! typed metavar vs symbol table; unresolved = false
! recombined dotted-receiver (self.Direct) typing for class-typed metavars.
NoteChainUnres         Procedure(STRING pRecv),virtual                                ! record a receiver whose class/member is not visible
NoteMissName           Procedure(STRING pRecv),virtual                                ! the name half of NoteChainUnres: onto the distinct list, capped
ChainTypeOK            Procedure(LONG pMvx, LONG pS),LONG,virtual                     ! recombined receiver token resolves to the metavar's class
! return-type table: string-returning method-call spans bind like string variables.
CallArgCount           Procedure(LONG pOpenTok),LONG,virtual                          ! arguments in the call whose '(' is at pOpenTok; -1 = unreadable
CallArgTypes           Procedure(LONG pOpenTok),STRING,virtual                        ! one '|'-terminated slot per argument, in order - resolved TYPE, vs:scalarArg for a literal, EMPTY where we cannot tell
MethodReturnsString    Procedure(STRING pRecvClassU, STRING pName, LONG pArgCount, STRING pArgTypesU),LONG,virtual ! header-derived registry lookup keyed by the receiver's resolved class;
                                                                                                                   !   six-name FALLBACK only when the class has no registry typedef
ClassSatisfies         Procedure(LONG pMvx, STRING pClassU),LONG,virtual              ! pClassU satisfies the metavar's class/typeset
RecvClass              Procedure(LONG pS),STRING,virtual                              ! terminal class of the receiver token at pS (plain or dotted); '' = unresolved
DottedOneChar          Procedure(LONG pS),BYTE,virtual                                ! the dotted field at token pS, subscripted once, is one character: owner.field resolved, FieldOneChar asked
ImplicitType           Procedure(STRING pTok),STRING,virtual                          ! implicit-variable suffix type - STRING/LONG/REAL, or empty
AssumeOf               Procedure(STRING pName),STRING,virtual                         ! an ASSUME line's type for a name, '' when the registry knows it as a declared instance
GuardOK                Procedure(),LONG,virtual                                       ! ALL WHERE clauses in rules.guardQ must pass (AND)
GuardOneOK             Procedure(),LONG,virtual                                       ! one clause - the LOADED rules.guardQ buffer row - against binds
SpanHasBoolOp          Procedure(LONG pS, LONG pE),LONG,virtual                       ! 1 = a depth-0 logical operator (AND/OR/XOR/NOT/~) in [pS,pE] - isSimple = ~this
SpanHasConcat          Procedure(LONG pS, LONG pE),BYTE,virtual                       ! a depth-0 & in the span - noConcat()
SpanIsWhole            Procedure(LONG pS, LONG pE),BYTE,virtual                       ! every operand in the span is a whole number - integer literals and names of whole-number types - isWhole()
FoldSafe               Procedure(STRING pIn),STRING,virtual                           ! FoldStr's text of pIn, or pIn when the fold took a name away: EVALUATE ran a call such as today()
GuardWalk              Procedure(LONG pS, STRING pNameU, BYTE pKind),LONG,virtual     ! does an earlier test prove pKind (1 = size/len = 1, 2 = not NULL) of pNameU at pS? See the banner
CondGuards             Procedure(LONG pS, LONG pE, STRING pNameU, BYTE pKind, BYTE pMode),LONG,virtual ! the condition pS..pE proves the guard: 2 = the use's own statement, 1 = a block header, 0 = a jump
NegatedAt              Procedure(LONG pIx, LONG pS),LONG,virtual                      ! a NOT or ~ in front of the token, or of the bracket it opens
IsJumpGuard            Procedure(LONG pS, LONG pE, STRING pNameU, BYTE pKind),LONG,virtual ! `if <test> then cycle|exit|return|break.` whose failing test proves the guard past it
ThenAtTop              Procedure(LONG pS, LONG pE),LONG,virtual                       ! the THEN at bracket depth 0, 0 = none
HasThenAtTop           Procedure(LONG pS, LONG pE),LONG,virtual                       ! 1 = ThenAtTop finds one
StmtTouches            Procedure(LONG pS, LONG pE, STRING pNameU),LONG,virtual        ! the tokens may have changed the name: assigned it or an ancestor, handed it to a call that is not a read, a DO, any other call
LevelNet               Procedure(LONG pS, LONG pE),LONG,virtual                       ! blocks the tokens open, less the blocks they close, from the level marks
LoopTouches            Procedure(LONG pHead, LONG pFrom, STRING pNameU),LONG,virtual  ! the LOOP at pHead may change the name on its next pass, between pFrom and its END or closing condition
IsCallOpen             Procedure(LONG pIx, LONG pS),LONG,virtual                      ! the ( at pIx opens a call's argument list, not a bracket that groups
ExprBefore             Procedure(LONG pIx),LONG,virtual                               ! the token at pIx is inside an expression: an = after it compares
OpenBefore             Procedure(LONG pIx, LONG pS),LONG,virtual                      ! the ( of the bracket the token at pIx stands in, 0 = none
ReadOnlyCall           Procedure(STRING pU),LONG,virtual                              ! a builtin that only reads what it is handed and writes no variable
IsColOneStart          Procedure(LONG pIx),LONG,virtual                               ! a label line - the walk has left the body
LitLength              Procedure(STRING pTok),LONG,virtual                            ! logical char count of a quoted literal token; -1 = not one
GuardProved            Procedure(LONG pS, STRING pNameU, BYTE pKind),LONG,virtual     ! the guard walk proves pKind of pNameU at pS, and no other name can write it (GuardAliased)
GuardAliased           Procedure(LONG pS, STRING pNameU, BYTE pKind),LONG,virtual     ! the name can be written under another name: a prefixed field, a by-address parameter, OVER, ref &= w, ADDRESS
ByAddressParam         Procedure(LONG pS, STRING pNameU),LONG,virtual                 ! the name is a parameter passed by address (*TYPE) of the procedure around pS
GuardEdges             Procedure(LONG pB, LONG pA, LONG pS, LONG pE),LONG,virtual     ! a guard test stands whole as an operand of AND or OR: pB the token in front, pA the token after
GroupWhole             Procedure(LONG pO, LONG pC, LONG pS, LONG pE),LONG,virtual     ! the bracket group pO..pC holding a guard is a round bracket that stands whole
CallAt                 Procedure(LONG pIx, LONG pS, LONG pE),LONG,virtual             ! the token at pIx calls something other than a builtin that only reads
NameIsData             Procedure(LONG pIx),LONG,virtual                               ! the name at pIx provably reads data - a plain name resolves, a dotted one resolves to a field
BuiltinReadAt          Procedure(LONG pOpen),LONG,virtual                             ! the ( at pOpen follows a ReadOnlyCall builtin - not a method, not a MAP procedure of that name
SameField              Procedure(STRING pTokU, STRING pNameU),LONG,virtual            ! two dotted names end in the same field: o.buf and self.buf
LitValue               Procedure(STRING pTok, StringTheory pOut),LONG,virtual         ! the value a quoted literal token spells; 0 = not one this can read
LitCode                Procedure(STRING pCode),LONG,virtual                           ! one code of a literal's <...> group, any numeric form; -1 = not a byte
NamesAreData           Procedure(LONG pS, LONG pE),LONG,virtual                       ! every name in the span resolves to data - none can be a call without brackets
BindSpan               Procedure(LONG pMvx, LONG pS, LONG pE),virtual
Unbind                 Procedure(),virtual                                            ! remove most recent binding
FindBind               Procedure(LONG pMvx),LONG,virtual                              ! binds row, 0 = none
SpanEqual              Procedure(LONG pAS, LONG pAE, LONG pBS, LONG pBE),LONG,virtual ! token-wise: caseless, but a quoted literal must match exactly
SpanText               Procedure(LONG pS, LONG pE, StringTheory pOut),virtual         ! tokens joined with single spaces
HasInteriorComment     Procedure(LONG pS, LONG pE),LONG,virtual
RecordMatch            Procedure(LONG pS, LONG pE, BYTE pSkipped, StringTheory pReport),virtual
TokText                Procedure(LONG pIx),STRING,virtual                             ! clipped token text; '' out of range / NULL
TokType                Procedure(LONG pIx),STRING,virtual                             ! token queue type field (vt:* equates)
TokIsEOL               Procedure(LONG pIx),LONG,virtual                               ! also true out of range
TokBefore              Procedure(LONG pIx, StringTheory pOut),virtual
LineOf                 Procedure(LONG pIx),LONG,virtual                               ! token queue lineNo (SetLineNumbers ran in ParseText)
StmtStart              Procedure(LONG pIx),LONG,virtual                               ! first token of the statement containing pIx
IsStmtEndAfter         Procedure(LONG pIx),LONG,virtual                               ! token pIx+1 terminates the statement
ExprContinuesAfter     Procedure(LONG pIx),LONG,virtual                               ! token pIx+1 CONTINUES the expression (& + - * / ^ %) - EXPREND refusal
CompareFollows         Procedure(LONG pIx),LONG,virtual                               ! token pIx+1 is a comparison operator, in any spelling, the infix NOT included - EXPREND refuses it for a replacement opening with ~ or NOT
ExprContinuesBefore    Procedure(LONG pIx),LONG,virtual                               ! token pIx-1 BINDS INTO the expression (& + - * / ^ % or a comparison) - EXPRSTART refuses
MatchIsTruthTest       Procedure(LONG pS, LONG pE),BYTE,virtual                       ! NOTBOOL: the match at [pS..pE] is used as a TRUE/FALSE value
ArgTypeMayChange       Procedure(STRING pNameU, LONG pOpen, LONG pS),BYTE,virtual     ! NOTBOOL: the argument at pS may be read with another type - an untyped parameter, or prototypes not read
RuntimeOwns            Procedure(STRING pU, LONG pOpen),BYTE,virtual                  ! a name the Clarion runtime owns, for a call no prototype the run read explains
DestKeepsType          Procedure(LONG pEq),BYTE,virtual                               ! NOTBOOL: the target the '=' at pEq assigns may take the value's own type - an ANY, an untyped parameter, or a name not placed
ReturnKeepsType        Procedure(LONG pIx),BYTE,virtual                               ! NOTBOOL: a RETURN at pIx may hand back the value's own type - the procedure returns ? or its prototype was not read
AssignEqAt             Procedure(LONG pIx),LONG,virtual                               ! the '=' at pIx assigns: depth 0 of a statement that opens with its target
StartsInsideBracket    Procedure(LONG pIx),LONG,virtual                               ! pIx sits inside an unclosed ( or [ of its own statement - INPARENS
IsMemberDot            Procedure(LONG pIx),LONG,virtual                               ! '.' at pIx is member access (vt:dot, not vt:end)
PatDotEnds             Procedure(LONG pP),LONG,virtual                                ! pattern '.' at pP ENDS a fragment - a block terminator, not member access
DepthDelta             Procedure(STRING pTok),LONG,virtual
IsAllDigits            Procedure(STRING pTok),LONG,virtual
                    END

VitGolden           CLASS,TYPE,MODULE('VitMatch.clw'),LINK('VitMatch.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
caseCount              LONG
passCount              LONG
failCount              LONG
caseWidth              LONG                                                           ! optional --- width <n> block: the width the rewriter's continuation policy respects for this case; 0 = no policy, as the engine has it with no --width

! Case sections: --- rules / --- input then EITHER --- expect (match report)
! OR --- output (rewritten source after one ApplyAll pass).
! optional --- select block - lines 'style <name>' / 'group <names>' /
! 'nogroup <names>' feed VitRules.Resolve (the same resolver as the CLI), so
! golden cases exercise GROUP/CHOICE/STYLE selection semantics.
! optional --- userrules block - appended via VitRules.LoadUserText (the
! same append-load as --userrules=), so cases exercise ID offsetting and the
! opt-in default of user groups.
RunFile                Procedure(STRING pFn, StringTheory pOut),LONG,PROC,virtual     ! returns fail count; -1 = load error
RunCase                Procedure(STRING pName, StringTheory pRules, StringTheory pUser, StringTheory pInput, |
   StringTheory pExpect, StringTheory pOutput, StringTheory pSelect, StringTheory pOut),virtual
SameReport             Procedure(StringTheory pA, StringTheory pB),LONG,virtual       ! line-wise, right-trimmed, ignores trailing blanks
                    END
