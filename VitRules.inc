! VitRules Class - Phase 1 of VitTransform (generalised Clarion code transformer)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Parses a transformation rule file into an internal representation:
! metavariable table + rules queue. The rule-file language is documented in
! README.md, which ships with the tool, and the shipped vitrules.txt is the
! worked example.
! Provides _List (IR dump) and Lint. No matching/rewriting here - that is
! Phase 2/3 (VitMatcher / VitRewriter).
!
! Requires StringTheory (Capesoft) and VitTokenize.
!
vr:maxName            EQUATE(50)
vr:nfCharName         EQUATE(1)      ! NOTE(charname(mv)) - print <line feed> rather than '<10>'
vr:version            EQUATE('1.00') ! the release, as every report prints it
vr:buildNo            EQUATE(248) ! this engine's build number, compared against a rule file's NEEDBUILD line. KEEP IT MOVING WITH THE RELEASE: a build number that stands still while the engine changes makes NEEDBUILD refuse rule files this engine could in fact run, and it does that SILENTLY - only a rule file asking for a build in the gap ever notices.
vr:maxMsg             EQUATE(250)

! rule kinds
vr:kindRule           EQUATE(1)
vr:kindBuiltin        EQUATE(2)

! metavar kinds
vr:mvTyped            EQUATE(1)      ! built-in data type (STRING, LONG, ...) - typeName holds keyword
vr:mvClass            EQUATE(2)      ! class/user type (StringTheory, ...)    - typeName holds class name
vr:mvExpr             EQUATE(3)      ! EXPR    - one balanced expression, no depth-0 commas
vr:mvArgs             EQUATE(4)      ! ARGS    - zero or more comma-separated args, whole (...) content
vr:mvLiteral          EQUATE(5)      ! LITERAL - quoted string literal
vr:mvConst            EQUATE(6)      ! CONST   - integer literal or foldable
vr:mvAnyVar           EQUATE(7)      ! ANYVAR  - any identifier, untyped
vr:mvTypeSet          EQUATE(8)      ! TYPESET name - one identifier whose resolved type is IN the named set

! guard kinds
vr:guardNone          EQUATE(0)
vr:guardCompare       EQUATE(1)      ! [func(]mv[)] op 'literal'
vr:guardClassTest     EQUATE(2)      ! isConst(mv) / isLiteral(mv) / isVar(mv) / isSimple(mv)

! guard comparison operators
vr:opEq               EQUATE(1)
vr:opNeq              EQUATE(2)

! guard/replacement functions
vr:gfNone             EQUATE(0)
! (no EQUATE(1): there is deliberately no trimr() GUARD - the compare already ignores
!   trailing spaces, so it could never answer differently from the plain compare
!   trimr() as a REPLACEMENT helper exists and edits the
!   literal's real bytes - see VitRewrite.TrimrLit.)
vr:gfFold             EQUATE(2)
vr:gfLen              EQUATE(3) ! len(mv) - guard only: logical char count of a bound literal ('<13>' = 1); RHS is a bare integer

! guard class tests
vr:ctConst            EQUATE(1)
vr:ctLiteral          EQUATE(2)
vr:ctVar              EQUATE(3)
vr:ctSimple           EQUATE(4) ! isSimple(mv) - the binding has NO depth-0 logical operator
                                !   (AND OR XOR NOT ~), so a comparator adjacent to it is the condition's
                                !   ROOT. Gates the comparator-flip / ~w-collapse inverted-choose rules: a
                                !   compound condition (root is and/or/xor/not) fails it and falls through to
                                !   the ~() wrap. BXOR/BAND/BOR are FUNCTIONS (operands), not excluded.
vr:ctPure             EQUATE(5) ! isPure(mv) - NO '(' AND NO '{' ANYWHERE in the binding. Read the test, not
                                !   the name: it refuses `y + (3 * z)`, which calls nothing and is perfectly
                                !   safe to evaluate twice, purely because of the grouping brackets. Its own
                                !   comment used to promise "pure arithmetic over vars/literals", which is a
                                !   DIFFERENT and wider test - that one is isCallFree below. Where a rule
                                !   only needs "evaluating this twice is safe", isCallFree is the one to
                                !   reach for; isPure is the blunter instrument and every rule using it is
                                !   refusing arithmetic it could accept.
vr:ctCaseNeutral      EQUATE(6) ! isCaseNeutral(mv) - upper(binding) = lower(binding), i.e. it holds NO
                                !   letter, so neither case fold can change it. Lets a repeated fold be hoisted
                                !   out of a concatenation: upper(a) & lit & upper(b) -> upper(a & lit & b).
                                !   one symmetric test beats an isUpper/isLower pair - stricter (an
                                !   uppercase separator is refused too) but a single obvious property.
vr:ctBoolExpr         EQUATE(8) ! isBoolExpr(mv) - the binding HAS a depth-0 logical operator, so it is a
                                !   LOGICAL expression and its value is 1 or 0. The exact complement of
                                !   isSimple, and both are SpanHasBoolOp: isSimple asks "is the comparator
                                !   still the root", this asks "is the root a logical operator". WHERE has
                                !   no negation, so the complement has to be its own name rather than
                                !   `not isSimple(mv)`.
vr:ctCallFree         EQUATE(7) ! isCallFree(mv) - the binding CALLS nothing. A '(' whose previous
                                !   token ends in a name character is a call; one after an operator,
                                !   a comma, or at the start of the binding is GROUPING and is fine.
                                !   '{' is refused too, and the reason is in the LRM: a property expression MAY
                                !   ITSELF BE A METHOD CALL on an OLE or OCX control ("may also be used as an
                                !   executable statement ... when the property expression is a method call"),
                                !   and nothing in the syntax separates that from reading PROP:Text. NOT because
                                !   reading a property has side effects - that claim is not supported.
                                !   THIS IS THE TEST isPure SHOULD HAVE BEEN. isPure refuses ANY '(',
                                !   so it rejects `y + (3 * z)` - arithmetic that calls nothing and is
                                !   perfectly safe to evaluate twice. Its own comment says "pure
                                !   arithmetic over vars/literals", which is this test, not that one.

! issue severity
vr:sevError           EQUATE(1)
vr:sevWarn            EQUATE(2)

! Auto-reversed rules get ruleId = vr:revBase + source ruleId, so the
! forward and reverse spellings of one rule stay distinct in logs, ONCE tracking and
! --only= (rule files never approach 100000 lines).
vr:revBase            EQUATE(100000)

! Rules loaded from a USER rulefile (LoadUserRules) get
! ruleId = vr:userBase + line number, so two files cannot collide in logs, ONCE
! tracking, --only=/--skip= or the Changes list. Log lines read rule 500096; the
! workbench displays them as U96. A user rule auto-reversed by a user REVERSE group
! lands at vr:revBase + (vr:userBase + line) = 600000+ - still unambiguous.
vr:userBase           EQUATE(500000)

MetaVarQType          QUEUE,TYPE
name                    STRING(vr:maxName)
kind                    BYTE               ! vr:mv* equates
typeName                STRING(vr:maxName) ! for mvTyped (keyword) / mvClass (class name)
usedCount               LONG               ! references across all rules (for lint)
declLine                LONG               ! rule-file line of declaration
                      END

RulePartQType         QUEUE,TYPE           ! one token of a pattern or replacement
tok                     &STRING
mvx                     LONG               ! 0 = literal token, else pointer into metaVars queue
mvTail                  &STRING            ! non-NULL = dotted metavar occurrence - a pattern token like
                                           !   st._DataEnd merges into ONE token (vitTokenize label merge), so
                                           !   mvx = the HEAD metavar, mvTail = text after the first '.'; the
                                           !   matcher treats the row as a constrained literal (head must equal
                                           !   the metavar's existing binding). NULL = ordinary row.
                      END

NotePartQType         QUEUE,TYPE           ! one segment of a NOTE(...) string expression
mvx                     LONG               ! 0 = literal segment (txt), else metavar reference
txt                     &STRING            ! literal text (unquoted) when mvx = 0
func                    BYTE               ! vr:nfCharName = wrap the bound text in the pretty char name; 0 = plain
                      END

BParmQType            QUEUE,TYPE           ! one BUILTIN parameter: NAME or NAME(value)
name                    STRING(vr:maxName)
value                   &STRING            ! raw text inside brackets; NULL for bare flags
                      END

IssueQType            QUEUE,TYPE
lineNo                  LONG
sev                     BYTE               ! vr:sevError / vr:sevWarn
msg                     STRING(vr:maxMsg)
                      END

AssumeQType           QUEUE,TYPE           ! ASSUME <name-pattern> <Type>: type for identifiers that fail symbol lookup
namePat                 STRING(vr:maxName) ! upper; trailing * stripped
isPrefix                BYTE               ! pattern ended with *
typeName                STRING(vr:maxName)
declLine                LONG
                      END

TypeSetQType          QUEUE,TYPE           ! TYPESET NAME = A + B + ...: a named class of scalar types
name                    STRING(vr:maxName) ! set name as declared (compared caselessly)
members                 STRING(512)        ! EXPANDED member list, upper, space-wrapped: ' BYTE LONG ... ' (nested sets flattened at parse)
declLine                LONG
                      END

GroupQType            QUEUE,TYPE           ! GROUP <name>[,CHOICE(axis)][,DEFAULT][,OFF][,REVERSE(group)]
name                    STRING(vr:maxName)
choiceName              STRING(vr:maxName) ! blank = standalone on/off group
isDefault               BYTE               ! DEFAULT: the choice's file-default member (max one per choice)
isOff                   BYTE               ! OFF: standalone group defaults unselected (opt-in)
isFinal                 BYTE               ! FINAL - this group's rules are DEFERRED. They are skipped by every
                                           !   fixpoint pass and applied ONCE after convergence, before AlignComments.
                                           !   For a transform whose OUTPUT the analysis passes cannot read: the choose
                                           !   return form contains valuePtr, which SpaceKeepUse refuses by design, and
                                           !   is not one of the two spellings SmProveSpaceless recognises. Running it
                                           !   during convergence destroyed the summary parser.MaskSigBase needs.
revOfGrp                LONG               ! groups row whose rules this group auto-reverses (0 = none)
declLine                LONG
handCount               LONG               ! rules written in the group body
autoCount               LONG               ! rules generated by REVERSE expansion
dropDup                 LONG               ! reversals dropped: pattern already claimed in this group (hand override / many-to-one collapse)
dropSkip                LONG               ! reversals dropped: source rule not auto-reversible (warned)
selected                BYTE               ! resolution result; parse seeds the file default, Resolve() re-layers
isUser                  BYTE               ! declared in a USER rulefile (LoadUserRules) - mirrors StyleQType.isProfile;
                                           !   standalone user groups are forced opt-in (isOff)
                      END

StyleQType            QUEUE,TYPE           ! STYLE <name> = <group>[, <group>]...
name                    STRING(vr:maxName)
members                 STRING(1024)       ! member list as written (names resolved at Resolve time)
declLine                LONG
isProfile               BYTE               ! loaded via LoadStyleFile (user profile), not from the rule file
                      END

GuardQType            QUEUE,TYPE           ! one WHERE clause; a rule's WHERE is an AND-list of these
kind                    BYTE               ! vr:guard*
func                    BYTE               ! vr:gf*   (compare guards)
op                      BYTE               ! vr:op*   (compare guards)
ct                      BYTE               ! vr:ct*   (class-test guards)
mvx                     LONG               ! metavar under test
val                     &STRING            ! unquoted comparison literal; NULL = empty '' (fixed STRING cannot hold empty)
                      END

RuleQType             QUEUE,TYPE
ruleId                  LONG               ! rule-file line number (start line if continued)
kind                    BYTE               ! vr:kindRule / vr:kindBuiltin
skip                    BYTE               ! SKIP option
once                    BYTE               ! ONCE option
isDelete                BYTE               ! replacement is DELETE
isComment               BYTE               ! replacement is COMMENT (comment-out instead of remove)
exprEnd                 BYTE               ! EXPREND option - match must END its operand (next token may not
                                           !   continue the expression: & + - * / ^ %). Zero-width, checked at accept.
inParens                BYTE               ! INPARENS option - the match must START inside an unclosed ( or [ of its
                                           !   own statement. Zero-width, checked at accept. What it proves: an '=' at
                                           !   depth > 0 is a COMPARISON, never an assignment, because an assignment
                                           !   target closes every bracket it opens before its '='.
guardKind               BYTE               ! summary flag (non-zero = rule HAS guards - the matcher's cheap gate)
                                           !   + ParseGuard's scratch target; CONSUMERS read guardQ, not the fields below
guardFunc               BYTE               ! vr:gf*   (compare guards)     - ParseGuard scratch
guardOp                 BYTE               ! vr:op*   (compare guards)     - ParseGuard scratch
guardCT                 BYTE               ! vr:ct*   (class-test guards)  - ParseGuard scratch
guardMvx                LONG               ! metavar under test            - ParseGuard scratch
guardVal                &STRING            ! unquoted comparison literal; NULL = empty '' - ParseGuard scratch
guardQ                  &GuardQType        ! the parsed WHERE clauses (ANDed); NULL = no guards
builtinName             STRING(vr:maxName)
srcText                 &STRING            ! cleaned rule text (for dump / change log)
repText                 &STRING            ! raw replacement text (rewriter substitutes into this, keeping rule spacing)
patQ                    &RulePartQType
repQ                    &RulePartQType
noteQ                   &NotePartQType
bparmQ                  &BParmQType
gdCached                BYTE               ! guards below computed (they are PURE pattern facts - once per rule, not per file/pass)
gdStmt                  BYTE
gdNoDot                 BYTE
gdNoSelf                BYTE
gd1Lit                  BYTE
gd1IdMv                 BYTE
gd2Dot                  BYTE
groupId                 LONG               ! groups row this rule/builtin belongs to (0 = ungrouped = always active)
revOf                   LONG               ! rules row of the source rule when auto-reversed by REVERSE() (0 = authored)
                      END

VitRules            CLASS,TYPE,MODULE('VitRules.clw'),LINK('VitRules.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
metaVars               &MetaVarQType
rules                  &RuleQType
issues                 &IssueQType
assumes                &AssumeQType
typeSets               &TypeSetQType       ! TYPESET declarations
groups                 &GroupQType         ! GROUP declarations (selection state lives here)
styles                 &StyleQType         ! STYLE lines (rule-file styles + loaded profiles)
tk                     &VitTokenize        ! fragment tokenizer (same tokenizer as source side)
workQ                  &RulePartQType      ! transient - current pattern/replacement queue
curGroup               LONG                ! S1 parse state: open GROUP row (0 = none) - ParseRuleLine/ParseBuiltinLine tag rules with it
lastUsed               STRING(vr:maxName)  ! LASTUSED marker from a profile stylefile ('' = none) - for VitStyle
appliedStyle           STRING(vr:maxName)  ! style name the last Resolve() applied ('' = file defaults)
wantThorough           BYTE                ! the rule file carried a bare THOROUGH directive - it needs
                                           !   include expansion to do its job (typed receivers whose classes live
                                           !   in .inc files). ASKS for it; the command line still decides:
                                           !   --nothorough beats it, --thorough/--root= would have turned it on
                                           !   anyway. Shipped rule file only, like DEFAULTSTYLE.
thoroughLine           LONG                !   the line it was found on, for the report
defaultStyle           STRING(vr:maxName)  ! DEFAULTSTYLE line - the style a run with NO --style= gets.Its own
                                           !   resolver layer, above the per-axis file defaults and BELOW --style=,
                                           !   so it is a DEFAULT: applied only when no --style= is given. An
                                           !   explicit --style= REPLACES it outright - it
                                           !   does not layer over the default's picks.
styleFromDefault       BYTE                ! appliedStyle came from DEFAULTSTYLE, not from a switch - the report
                                           !   must say which, or two runs of the same command line differ in silence
deferPhase             BYTE                ! 0 = fixpoint passes (FINAL groups are INERT); 1 = the single deferred
                                           !   pass after convergence (ONLY FINAL groups run). GroupActive is the one
                                           !   place that reads it, so a rule cannot leak into the wrong phase.
inUserLoad             BYTE                ! ParseText is appending a USER rulefile (set by LoadUserText) -
                                           !   no FreeAll, line numbers offset by vr:userBase, STYLE/LASTUSED = errors
userErrors             LONG                ! error count from the user rulefile alone (design callers
                                           !   distinguish fatal-shipped from skip-user); reset by FreeAll

Construct              Procedure()
Destruct               Procedure()
FreeAll                Procedure(),virtual
FreePartQ              Procedure(),virtual ! frees/disposes self.workQ

LoadFile               Procedure(STRING pFn),LONG,PROC,virtual ! returns error count
ParseText              Procedure(StringTheory pSt),LONG,PROC,virtual
LoadStyleFile          Procedure(STRING pFn),LONG,PROC,virtual ! profile stylefile - STYLE + LASTUSED lines only; ADDS to styles (no FreeAll); returns error count
LoadUserRules          Procedure(STRING pFn),LONG,PROC,virtual ! user rulefile (plain DSL) - APPENDS to the loaded shipped set;
                                                               !   ruleIds offset by vr:userBase; load AFTER the rule file, BEFORE the
                                                               !   stylefile; returns the USER file's error count (also in self.userErrors)
LoadUserText           Procedure(StringTheory pSt),LONG,PROC,virtual ! LoadUserRules on an in-memory buffer (golden runner / workbench scratch)
Lint                   Procedure(),LONG,PROC,virtual ! adds issues; returns error count
_List                  Procedure(StringTheory pOut),virtual ! IR dump for eyeballing

ErrorCount             Procedure(),LONG,virtual
WarnCount              Procedure(),LONG,virtual
AddIssue               Procedure(LONG pLine, BYTE pSev, STRING pMsg),virtual

! --- internals (left virtual for tinkering) ---
ParseMetaVarLine       Procedure(StringTheory pLine, LONG pLineNo),virtual
ParseAssumeLine        Procedure(StringTheory pLine, LONG pLineNo),virtual
ParseNeedBuildLine     Procedure(StringTheory pLine, LONG pLineNo),virtual ! NEEDBUILD nn - refuse the file when this engine is older
AssumeType             Procedure(STRING pName),STRING,virtual ! assumed type for an unresolved identifier, '' = none
ParseTypeSetLine       Procedure(StringTheory pLine, LONG pLineNo),virtual ! TYPESET NAME = A + B + ...
FindTypeSet            Procedure(STRING pName),LONG,virtual ! typeSets row for a set name (caseless), 0 = none
ParseRuleLine          Procedure(StringTheory pLine, LONG pLineNo),virtual
ParseBuiltinLine       Procedure(StringTheory pLine, LONG pLineNo),virtual
ParseGroupLine         Procedure(StringTheory pLine, LONG pLineNo),virtual ! GROUP <name>[,CHOICE(x)][,DEFAULT][,OFF][,REVERSE(g)] - opens a group
ParseStyleLine         Procedure(StringTheory pLine, LONG pLineNo, BYTE pIsProfile),virtual ! STYLE <name> = <group>[, ...]
CloseGroup             Procedure(LONG pLineNo),virtual ! at ENDGROUP / next GROUP / STYLE / EOF - counts members, runs REVERSE expansion
ExpandReverse          Procedure(LONG pGrpRow, LONG pLineNo),virtual ! generate reversed copies of the source group's rules into pGrpRow
FreeRuleRow            Procedure(),virtual ! dispose the CURRENT rules buffer's heap parts + delete the row
NormalizeParts         Procedure(StringTheory pOut),virtual ! canonical text of self.workQ (metavars by name, keywords uppered, literals verbatim)
FindGroup              Procedure(STRING pName),LONG,virtual ! groups row (caseless), 0 = none
FindStyle              Procedure(STRING pName),LONG,virtual ! styles row (caseless, LAST match so a profile overrides a same-named shipped style), 0 = none
GroupActive            Procedure(LONG pGroupRow),LONG,virtual ! 1 = a rule with this groupId runs (row 0 = ungrouped = always)
Resolve                Procedure(STRING pStyle, STRING pGroups, STRING pNoGroups),LONG,PROC,virtual ! THE resolver - defaults -> style -> overrides ('' = not given); returns NEW error count
ApplyPick              Procedure(STRING pName, LONG pLine, STRING pSrc),virtual ! select one group by name (choice member deselects its siblings); unknown -> WARN + ignored
ApplyUnpick            Procedure(STRING pName, LONG pLine, STRING pSrc),virtual ! deselect one group by name; unknown -> WARN + ignored
SelectionTable         Procedure(StringTheory pOut),virtual ! append the RESOLVED selection (style, choice winners, group states) - report header + IR dump
IsGroupName            Procedure(STRING pName),LONG,virtual ! identifier chars plus '-' (kebab-case group/style names)
ParseOptions           Procedure(StringTheory pOpts, LONG pLineNo),virtual ! fills current self.rules buffer fields
ParseGuard             Procedure(StringTheory pText, LONG pLineNo),virtual ! parses ONE clause into the guard* scratch fields
ParseGuardList         Procedure(StringTheory pText, LONG pLineNo),virtual ! splits WHERE on top-level ' and ', copies each parsed clause to guardQ
ParseNoteExpr          Procedure(StringTheory pText, LONG pLineNo),virtual
TokenizeFragment       Procedure(STRING pText, LONG pLineNo, BYTE pIsPattern),virtual ! fills self.workQ

FindMetaVar            Procedure(STRING pName),LONG,virtual ! 0 if not found (caseless)
PosOutsideQuotes       Procedure(StringTheory pSt, STRING pNeedle, LONG pStart=1),LONG,virtual
FindOptionStart        Procedure(StringTheory pSt),LONG,virtual ! pos of WHERE/NOTE/ONCE/SKIP at depth 0, else 0
QuoteCount             Procedure(StringTheory pSt),LONG,virtual ! quote-byte count; callers test PARITY (odd = a quote is unterminated - doubled '' counts 2, so the test is escape-blind)
MatchingParen          Procedure(StringTheory pSt, LONG pOpenPos),LONG,virtual ! pos of matching ')' resp. quotes
IsLabelToken           Procedure(STRING pTok),LONG,virtual
IsLabelChar            Procedure(STRING pCh),LONG,virtual ! single-CHAR class test (letters/digits/_/:) - IsLabelToken on one char rejects digits, which made digits word boundaries
OneCharDiff            Procedure(STRING pA, STRING pB),LONG,virtual ! true if strings differ by <=1 edit
KindName               Procedure(BYTE pKind),STRING,virtual
                    END
