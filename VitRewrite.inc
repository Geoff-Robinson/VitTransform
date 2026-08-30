! VitRewrite Class - Phase 3 of VitTransform (generalised Clarion code transformer)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Applies rule replacements to the token queue using the matches captured by
! VitMatch (capture mode):
!  - replacement built from the rule's raw repText, so the rule author's
!    spacing/spelling wins for literal tokens; metavars substitute as the
!    matched source span verbatim (source casing/spacing wins)
!  - fold(...) evaluated via VitTokenize.FoldStr; trimr(lit) strips trailing
!    spaces inside the quotes ('xx  ' -> 'xx', '  ' -> '')
!  - NOTE(...) appended as a trailing comment via InsertStringAtEOL
!  - DELETE removes the matched statement; leading trivia and any trailing
!    comment survive on the (now otherwise empty) line
!  - matches applied right-to-left per rule so token positions stay valid;
!    multi-line matched spans collapse to one line (logged)
! One ApplyAll = ONE pass over the rules in file order; the fixpoint loop is
! the Phase 5 driver's job.
!
! Requires StringTheory, VitTokenize, VitRules, VitMatch.
!
  INCLUDE('VitMatch.inc'),ONCE

OnceQType             QUEUE,TYPE      ! rules already applied under ONCE (per file, across fixpoint passes)
ruleId                  LONG
                      END

VitRewrite          CLASS,TYPE,MODULE('VitRewrite.clw'),LINK('VitRewrite.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
rl                     &VitRules
tk                     &VitTokenize
m                      &VitMatch   ! owned
syms                   &VitSymbols ! optional, not owned. A rule that shifts token positions sets syms.dirty and the
                                   !   rebuild happens LAZILY at the next consumer (EnsureFresh), so an untyped
                                   !   rule stretch costs no rebuilds at all - see the dirty flag in VitRewrite.clw
onceQ                  &OnceQType  ! owned; reset by Init (i.e. per file)
changeCount            LONG
skipCount              LONG
curMx                  LONG        ! current captured-match row (BindText context)
multiLine              BYTE        ! set when a bound span crossed a '|' continuation
widthSkips             LONG        ! matches refused because flattening would exceed maxWidth (L width policy)
maxWidth               LONG        ! allowed result-line width for continuation collapses; engine sets per file (0 = no limit)
keepCont               BYTE        ! render bound-span continuations VERBATIM (over-width fallback)
contEmits              LONG        ! spans emitted with preserved continuations in the current BuildRep
preserved              BYTE        ! this match applied with continuations preserved (report annotation)

Construct              Procedure()
Destruct               Procedure()
Init                   Procedure(VitRules pRl, VitTokenize pTk),virtual
SetSymbols             Procedure(VitSymbols pSyms),virtual ! attach a built symbol table (typed matching)
ApplyAll               Procedure(StringTheory pLog),LONG,PROC,virtual ! one pass, rules in file order; returns change count
ApplyRule              Procedure(LONG pRow, StringTheory pLog),virtual ! rules queue row; capture-match then apply reversed

! --- internals (left virtual for tinkering) ---
ApplyOne               Procedure(LONG pMx, StringTheory pLog),virtual ! one captured match (rules buffer holds the rule)
BuildRep               Procedure(StringTheory pOut),virtual ! substituted + folded replacement text
SubstText              Procedure(STRING pText, StringTheory pOut),virtual ! metavars + fold()/trimr(), quote-aware
BindText               Procedure(LONG pMvx, StringTheory pOut),virtual ! rendered source span for a binding of curMx
RenderSpan             Procedure(LONG pS, LONG pE, StringTheory pOut),virtual ! tok + interior trivia; continuations -> ' '
TrimrLit               Procedure(StringTheory pInOut),virtual ! strip trailing spaces inside a quoted literal
ComputeLitLen          Procedure(STRING pLit),LONG,virtual ! RUNTIME length of a quoted literal's content; -1 = not countable (caller keeps len(...) spelling)
ComputeByteLit         Procedure(STRING pNum),STRING,virtual ! the literal SOURCE TEXT for a byte value (61 -> quote = quote); blank = not a plain byte number
ComputeLitByte         Procedure(STRING pLit),LONG,virtual ! byte value of a ONE-character literal ('=' -> 61, '<9>' -> 9); -1 = not a single char (caller keeps val(...) spelling)
BuildNote              Procedure(StringTheory pOut),virtual
MatchingParenPos       Procedure(STRING pText, LONG pOpen),LONG,virtual ! within text, quote-aware; 0 = unmatched
IsLabelChar            Procedure(STRING pC),LONG,virtual
                    END
