! VitMatch Class - Phase 2 of VitTransform (generalised Clarion code transformer)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Untyped anchored matching over a VitTokenize token queue, driven by the
! VitRules IR - the type checks themselves live in VitSymbols. Covers
! anchor selection, EXPR/ARGS extents, repeated-metavar equality, auto-guards,
! interior-comment skip. Reports match spans + metavar bindings; no rewriting
! (that is Phase 3, VitRewrite).
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

MatchBindQType        QUEUE,TYPE      ! one metavar binding within the current match
mvx                     LONG ! metaVars row
sPos                    LONG ! first token of bound span (source token queue)
ePos                    LONG ! last token; ePos < sPos = empty span (ARGS)
                      END

MatchRecQType         QUEUE,TYPE ! one captured match (capture mode, for the rewriter)
sPos                    LONG
ePos                    LONG
skipped                 BYTE ! interior-comment skip
                      END

BindRecQType          QUEUE,TYPE ! binding snapshot per captured match
matchIx                 LONG ! matches row this binding belongs to
mvx                     LONG
sPos                    LONG
ePos                    LONG
                      END

! Anchor-count cache (perf). Without it PickAnchor re-scans the whole token
! stream (CountTok, O(tokens)) for every pattern literal of
! every rule every pass - fine for goldens, but O(rules x literals x tokens x
! passes) on a corpus. Instead: collect the distinct pattern literals ONCE
! (BuildAnchorLits, sorted for binary search), then refresh their occurrence
! counts with ONE pass over the tokens whenever the stream changes
! (freqDirty). CountTok becomes an O(log distinctLiterals) lookup. keyText is
! LitMatches' notion of identity: quoted literals compared exactly (leading
! '), everything else upper-cased; truncation to the key width only ever
! MERGES distinct literals (overcount) - safe, since undercount is the only
! thing that could wrongly skip a rule, and this never undercounts.
AnchorLitQType        QUEUE,TYPE
keyText                 STRING(80)         ! FreqKey of a pattern literal (quoted: exact; else upper); trunc 80 = overcount-safe
cnt                     LONG               ! occurrences in the current token stream (valid while ~freqDirty)
                      END

AnchorPostQType       QUEUE,TYPE           ! one posting per OCCURRENCE of a pattern literal in the stream
keyText                 STRING(80)         ! same identity as AnchorLitQType.keyText
pos                     LONG               ! token position
                      END

ChainMissQType        QUEUE,TYPE           ! DISTINCT dotted receivers a typed rule refused because the
recvU                   STRING(vs:maxName) !   class or the member is NOT VISIBLE - not because it was the
                      END                  !   WRONG class, which is an ordinary no-match and stays silent

VitMatch            CLASS,TYPE,MODULE('VitMatch.clw'),LINK('VitMatch.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
rl                     &VitRules
tk                     &VitTokenize
syms                   &VitSymbols         ! NULL = untyped matching, no type gates
loose                  BYTE                ! --loose: typed metavars downgraded to ANYVAR
verbose                BYTE                ! log near-misses (type fails) to vlog
vlog                   &StringTheory       ! optional near-miss log target (not owned)
binds                  &MatchBindQType
matches                &MatchRecQType      ! captured matches (capture mode)
bindRecs               &BindRecQType       ! captured binding snapshots (capture mode)
capture                BYTE                ! when true, RecordMatch also fills matches/bindRecs
patQ                   &RulePartQType      ! current rule's pattern (reference, not owned)
patCount               LONG
anchorLits             &AnchorLitQType     ! distinct pattern literals + live counts (owned); NULL until first Init
anchorPost             &AnchorPostQType    ! postings (keyText,pos) sorted - MatchRule iterates its anchor's occurrences instead of every token
freqDirty              BYTE                ! anchorLits counts stale (token stream changed) - refresh on next CountTok
ruleId                 LONG
matchCount             LONG
skipCount              LONG
lastEnd                LONG                ! last source token consumed by a match of current rule
gdNoDot                BYTE                ! auto-guard: no '.' immediately before match start
gdNoSelf               BYTE                ! auto-guard: receiver metavar must not bind SELF
gdStmt                 BYTE                ! auto-guard: statement-anchored (DELETE / multi-stmt rep / assignment)
gd1Lit                 BYTE                ! pattern part 1 is a literal token
gd1IdMv                BYTE                ! pattern part 1 is an identifier metavar
gd2Dot                 BYTE                ! pattern part 2 is '.'
rtFallbacks            LONG                ! times the six-name fallback fired this file (engine logs when non-zero + resets)
chainUnres             LONG                ! typed matches refused this file because a dotted receiver's class
                                           !   or member could not be RESOLVED AT ALL. The commonest cause is the class
                                           !   being declared in an INCLUDE, which is invisible without --thorough - the
                                           !   one silent miss users actually hit. A WRONG class is not counted.
chainMissQ             &ChainMissQType     ! the distinct receivers behind that count (capped; owned)

Construct              Procedure()
Destruct               Procedure()
Init                   Procedure(VitRules pRl, VitTokenize pTk),virtual
MatchAll               Procedure(StringTheory pReport),LONG,PROC,virtual ! all non-SKIP rules; returns match count
MatchRule              Procedure(LONG pRow, StringTheory pReport),virtual ! pRow = rules queue row number

! --- internals (left virtual for tinkering) ---
ClassifyGuards         Procedure(),virtual
PickAnchor             Procedure(StringTheory pAnchor),LONG,virtual ! source occurrence count; -1 = pattern has no literal
CountTok               Procedure(STRING pLit),LONG,virtual ! occurrences of a pattern literal (cached via anchorLits)
BuildAnchorLits        Procedure(),virtual ! collect distinct pattern literals once; sorted for binary search
RefreshFreq            Procedure(),virtual ! recount anchorLits over the current token stream (one pass)
FindAnchorLit          Procedure(STRING pKey),LONG,virtual ! binary search anchorLits by key; 0 = absent
FindFirstPost          Procedure(STRING pKey),LONG,virtual ! FIRST anchorPost row for key; 0 = absent
FreqKey                Procedure(STRING pTok, *STRING pKeyOut),virtual ! LitMatches identity key: quoted exact, else upper, trunc 80
CandOK                 Procedure(LONG pS),LONG,virtual ! cheap shape gate before a full TryFrom
TryFrom                Procedure(LONG pS, StringTheory pReport),LONG,virtual ! 0 = no match, else last matched token pos
MatchHere              Procedure(LONG pP, LONG pS),LONG,virtual ! 0 = fail, else source pos AFTER matched span
LitMatches             Procedure(LONG pIx, *STRING pLit),LONG,virtual ! source token vs pattern literal (quoted = exact). *STRING: never written, and the hottest test in the matcher
OpCanon                Procedure(STRING pTok),STRING,virtual ! canonical spelling of an LRM combined operator ('=<' -> '<<='), '' if it has no synonym
OpCanonNot             Procedure(*STRING pTok),STRING,virtual ! class of an infix NOT plus this token: 'NOT <' is >=, not <
AnchorNotPair          Procedure(LONG pIx, *STRING pAnchorOp),LONG,virtual ! does the two-word NOT operator at pIx spell pAnchorOp (already canonical - computed once per rule)
NotInfixAt             Procedure(LONG pS),LONG,virtual ! is the NOT at pS the INFIX one of 'A NOT = B', not the prefix NOT of 'IF NOT x = 1'
TypeOK                 Procedure(LONG pMvx, LONG pS),LONG,virtual ! typed metavar vs symbol table; unresolved = false
! Design B0b: recombined dotted-receiver (self.Direct) typing for class-typed metavars.
NoteChainUnres         Procedure(STRING pRecv),virtual ! record a receiver whose class/member is not visible
ChainTypeOK            Procedure(LONG pMvx, LONG pS),LONG,virtual ! recombined receiver token resolves to the metavar's class
! return-type table: string-returning method-call spans bind like string variables.
CallArgCount           Procedure(LONG pOpenTok),LONG,virtual ! arguments in the call whose '(' is at pOpenTok; -1 = unreadable
CallArgTypes           Procedure(LONG pOpenTok),STRING,virtual ! one '|'-terminated slot per argument, in order - resolved TYPE, vs:scalarArg for a literal, EMPTY where we cannot tell. Was CallArg1Type, first argument only
MethodReturnsString    Procedure(STRING pRecvClassU, STRING pName, LONG pArgCount, STRING pArgTypesU),LONG,virtual ! header-derived registry lookup keyed by the receiver's resolved class; six-name FALLBACK only when the class has no registry typedef
ClassSatisfies         Procedure(LONG pMvx, STRING pClassU),LONG,virtual ! pClassU satisfies the metavar's class/typeset
RecvClass              Procedure(LONG pS),STRING,virtual ! (was RecvIsST): terminal class of the receiver token at pS (plain or dotted); '' = unresolved
ImplicitType           Procedure(STRING pTok),STRING,virtual ! implicit-variable suffix type - STRING/LONG/REAL, or empty
GuardOK                Procedure(),LONG,virtual ! ALL WHERE clauses in rules.guardQ must pass (AND)
GuardOneOK             Procedure(),LONG,virtual ! one clause - the LOADED rules.guardQ buffer row - against binds
SpanHasBoolOp          Procedure(LONG pS, LONG pE),LONG,virtual ! 1 = a depth-0 logical operator (AND/OR/XOR/NOT/~) in [pS,pE] - isSimple = ~this
LitLength              Procedure(STRING pTok),LONG,virtual ! logical char count of a quoted literal token; -1 = not one
BindSpan               Procedure(LONG pMvx, LONG pS, LONG pE),virtual
Unbind                 Procedure(),virtual ! remove most recent binding
FindBind               Procedure(LONG pMvx),LONG,virtual ! binds row, 0 = none
SpanEqual              Procedure(LONG pAS, LONG pAE, LONG pBS, LONG pBE),LONG,virtual ! caseless token-wise
SpanText               Procedure(LONG pS, LONG pE, StringTheory pOut),virtual ! tokens joined with single spaces
HasInteriorComment     Procedure(LONG pS, LONG pE),LONG,virtual
RecordMatch            Procedure(LONG pS, LONG pE, BYTE pSkipped, StringTheory pReport),virtual
TokText                Procedure(LONG pIx),STRING,virtual ! clipped token text; '' out of range / NULL
TokType                Procedure(LONG pIx),STRING,virtual ! token queue type field (vt:* equates)
TokIsEOL               Procedure(LONG pIx),LONG,virtual ! also true out of range
TokBefore              Procedure(LONG pIx, StringTheory pOut),virtual
LineOf                 Procedure(LONG pIx),LONG,virtual ! token queue lineNo (SetLineNumbers ran in ParseText)
StmtStart              Procedure(LONG pIx),LONG,virtual ! first token of the statement containing pIx
IsStmtEndAfter         Procedure(LONG pIx),LONG,virtual ! token pIx+1 terminates the statement
ExprContinuesAfter     Procedure(LONG pIx),LONG,virtual ! token pIx+1 CONTINUES the expression (& + - * / ^ %) - EXPREND refusal
StartsInsideBracket    Procedure(LONG pIx),LONG,virtual ! pIx sits inside an unclosed ( or [ of its own statement - INPARENS
IsMemberDot            Procedure(LONG pIx),LONG,virtual ! '.' at pIx is member access (vt:dot, not vt:end)
DepthDelta             Procedure(STRING pTok),LONG,virtual
IsAllDigits            Procedure(STRING pTok),LONG,virtual
                    END

VitGolden           CLASS,TYPE,MODULE('VitMatch.clw'),LINK('VitMatch.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
caseCount              LONG
passCount              LONG
failCount              LONG

! Case sections: --- rules / --- input then EITHER --- expect (match report,
! Phase 2) OR --- output (rewritten source after one ApplyAll pass, Phase 3).
! optional --- select block - lines 'style <name>' / 'group <names>' /
! 'nogroup <names>' feed VitRules.Resolve (the same resolver as the CLI), so
! golden cases exercise GROUP/CHOICE/STYLE selection semantics.
! optional --- userrules block - appended via VitRules.LoadUserText (the
! same append-load as --userrules=), so cases exercise ID offsetting and the
! opt-in default of user groups.
RunFile                Procedure(STRING pFn, StringTheory pOut),LONG,PROC,virtual ! returns fail count; -1 = load error
RunCase                Procedure(STRING pName, StringTheory pRules, StringTheory pUser, StringTheory pInput, |
   StringTheory pExpect, StringTheory pOutput, StringTheory pSelect, StringTheory pOut),virtual
SameReport             Procedure(StringTheory pA, StringTheory pB),LONG,virtual  ! line-wise, right-trimmed, ignores trailing blanks
                    END
