! VitRewrite Class - the rewriter of VitTransform (generalised Clarion code transformer)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Applies rule replacements to the token queue using the matches captured by
! VitMatch (capture mode):
!  - replacement built from the rule's raw repText, so the rule author's spacing
!    wins; a word the SOURCE also spells keeps the source's capitalisation, and
!    metavars substitute as the matched source span verbatim
!  - fold(...) evaluated via VitTokenize.FoldStr; trimr(lit) strips trailing
!    blanks inside the quotes however they are spelled ('xx  ' -> 'xx',
!    'x<32>' -> 'x', ' {3}' -> ''); chr(nn), len(lit)
!    and val(lit) of a quoted literal are worked out and written as source text
!  - NOTE(...) appended as a trailing comment via InsertStringAtEOL
!  - DELETE removes the matched statement; leading trivia and any trailing
!    comment survive on the (now otherwise empty) line
!  - matches applied right-to-left per rule so token positions stay valid;
!    multi-line matched spans collapse to one line (logged)
!  - a replacement written as `stmt ; stmt` goes in as two lines when the match
!    was two statements too (a ';' inside the pattern), or when the match stood
!    alone on its line; a match that shares its line with anything else keeps it
!  - a rule that would change how many statements stand in an EXECUTE arm (a
!    DELETE, a COMMENT, two statements joined or one written as two) is refused
!    there and logged: the arms are counted by position
! One ApplyAll = ONE pass over the rules in file order; the fixpoint loop is
! VitEngine's job.
!
! Requires StringTheory, VitTokenize, VitRules, VitMatch.
!
  INCLUDE('VitMatch.inc'),ONCE

OnceQType             QUEUE,TYPE                                              ! rules already applied under ONCE (per file, across fixpoint passes)
ruleId                  LONG
                      END

CacheRuleQType        QUEUE,TYPE                                              ! grouped dispatch: one rule whose matches on the current stream are known
ruleRow                 LONG
nMatch                  LONG
dChain                  LONG                                                  ! the counters its scan moved, taken back off at the time (see MatchGroup) and moved at every load
dRtf                    LONG
dSkip                   LONG
dMatch                  LONG
                      END

CacheMatchQType       QUEUE,TYPE                                              !   its matches, in the order the walk found them
ruleRow                 LONG
seq                     LONG
sPos                    LONG
ePos                    LONG
skipped                 BYTE
                      END

CacheBindQType        QUEUE,TYPE                                              !   and their bindings
ruleRow                 LONG
seq                     LONG
mvx                     LONG
sPos                    LONG
ePos                    LONG
                      END

PlanQType             QUEUE,TYPE                                              ! the rules a pass visits, in order (the engine fills it; the group walk reads it)
ruleRow                 LONG
                      END

VitRewrite          CLASS,TYPE,MODULE('VitRewrite.clw'),LINK('VitRewrite.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
rl                     &VitRules
tk                     &VitTokenize
m                      &VitMatch                                              ! owned
syms                   &VitSymbols                                            ! optional, not owned. A rule that shifts token positions sets syms.dirty and the rebuild happens LAZILY at the next
                                                                              !   consumer (EnsureFresh), so an untyped rule stretch costs no rebuilds at all - see the dirty flag in VitRewrite.clw
onceQ                  &OnceQType                                             ! owned; reset by Init (i.e. per file)
changeCount            LONG
skipCount              LONG                                                   ! matches refused for an interior comment, on the LAST full pass - a site, not an attempt
curMx                  LONG                                                   ! current captured-match row (BindText context)
multiLine              BYTE                                                   ! set when a bound span crossed a '|' continuation
widthSkips             LONG                                                   ! matches applied FLAT, over maxWidth, as their continuations could not be kept; split later
maxWidth               LONG                                                   ! allowed result-line width for continuation collapses; engine sets per file (0 = no limit)
keepCont               BYTE                                                   ! render bound-span continuations VERBATIM (over-width fallback)
contEmits              LONG                                                   ! spans emitted with preserved continuations in the current BuildRep
preserved              BYTE                                                   ! this match applied with continuations preserved (report annotation)
dispatch               BYTE                                                   ! --dispatch: 0 = classic (each rule walks the file itself), 1 = grouped (rules sharing an anchor walk it together; answers kept per stream version)
plan                   &PlanQType                                             ! the pass's rules in order (the engine's; not owned)
cVer                   LONG                                                   ! the stream version the cache holds answers for
cRules                 &CacheRuleQType                                        ! the cache (owned): the rules answered,
cMatch                 &CacheMatchQType                                       !   their matches,
cBind                  &CacheBindQType                                        !   and the bindings
cHits                  LONG                                                   ! this file: scans answered from the cache,
cMiss                  LONG                                                   !   walks made,
cWalks                 LONG                                                   !   of which group walks,
cMembers               LONG                                                   !   and the further rules those walks answered for

Construct              Procedure()
Destruct               Procedure()
Init                   Procedure(VitRules pRl, VitTokenize pTk),virtual
SetSymbols             Procedure(VitSymbols pSyms),virtual                    ! attach a built symbol table (typed matching)
ApplyAll               Procedure(StringTheory pLog),LONG,PROC,virtual         ! one pass, rules in file order; returns change count
ApplyRule              Procedure(LONG pRow, StringTheory pLog),virtual        ! rules queue row; capture-match then apply reversed
OnceDone               Procedure(LONG pRuleId),LONG,virtual                   ! ONCE already applied for this file?
CacheFresh             Procedure(),virtual                                    ! empty the cache when the stream has moved since it was filled
CacheLoad              Procedure(LONG pRow),LONG,virtual                      ! 1 = the rule's matches were known: matches/bindRecs filled, counters moved as a repeated scan would
ClassicScan            Procedure(LONG pRow),virtual                           ! the classic capture: MatchRule into matches/bindRecs
CacheStore             Procedure(LONG pRow, LONG pDChain, LONG pDRtf, LONG pDSkip, LONG pDMatch),virtual ! keep the matches tagged pRow in m.matches
GroupScan              Procedure(LONG pRow),virtual                           ! a miss: walk pRow's group (or pRow alone) and cache every member's answer

! --- internals (left virtual for tinkering) ---
ApplyOne               Procedure(LONG pMx, StringTheory pLog),virtual         ! one captured match (rules buffer holds the rule)
LeadIsCol1             Procedure(StringTheory pLead),LONG,virtual             ! 1 = this trivia puts its token in column 1 - none at all, or ending at a line feed
ArmOfExecute           Procedure(LONG pTok),LONG,virtual                      ! the EXECUTE whose arm the statement at pTok is; 0 = none
BuildRep               Procedure(StringTheory pOut),virtual                   ! substituted + folded replacement text
SubstText              Procedure(STRING pText, StringTheory pOut),virtual     ! metavars + fold()/trimr(), quote-aware
BindText               Procedure(LONG pMvx, StringTheory pOut),virtual        ! rendered source span for a binding of curMx
RenderSpan             Procedure(LONG pS, LONG pE, StringTheory pOut),virtual ! tok + interior trivia; continuations -> ' '
TrimrLit               Procedure(StringTheory pInOut),virtual                 ! drop a quoted literal's trailing blanks however spelled; clip(lit) when unreadable
ComputeLitLen          Procedure(STRING pLit),LONG,virtual                    ! RUNTIME length of a quoted literal's content; -1 = not countable (caller keeps len(...) spelling)
ComputeByteLit         Procedure(STRING pNum),STRING,virtual                  ! the literal SOURCE TEXT for a byte value (61 -> quote = quote); blank = not a plain byte number
ComputeLitByte         Procedure(STRING pLit),LONG,virtual                    ! byte value of a ONE-character literal ('=' -> 61, '<9>' -> 9); -1 = not a single char (caller keeps val(...) spelling)
BuildNote              Procedure(StringTheory pOut),virtual
MatchingParenPos       Procedure(STRING pText, LONG pOpen),LONG,virtual       ! within text, quote-aware; 0 = unmatched
IsLabelChar            Procedure(STRING pC),LONG,virtual
                    END
