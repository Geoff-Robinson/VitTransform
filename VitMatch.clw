! VitMatch - Phase 2 of VitTransform
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Untyped matcher + golden-test runner. See VitMatch.inc header for the
! report format. What it relies on from vitTokenize: strBefore is &STRING; the
! ParseText(StringTheory,...) overload takes full source; continuations
! put '|'/comment/CRLF into the NEXT token's strBefore (no EOL token);
! ParseText runs SetLineNumbers() and retypes END-terminator dots to
! vt:end, so lineNo and dot classification come from the token queue.
!
!
  MEMBER

  Include('StringTheory.inc'),ONCE
  Include('VitTokenize.inc'),ONCE
  Include('VitRules.inc'),ONCE
  Include('VitMatch.inc'),ONCE
  Include('VitRewrite.inc'),ONCE

  MAP
  END

! return-type table, DEMOTED TO FALLBACK: used ONLY when the receiver's
! resolved class has no typedef in the type registry (headers absent - fixture runs
! without --root, ASSUME'd receivers in files that never include the class header).
! When the registry KNOWS the class, the header-derived method table is the sole
! authority - including refusals (a class method absent from its headers never binds,
! even if its name appears below). Do not grow this list; grow the headers.
stringReturners STRING(' GETVALUE GETLINE SUB SLICE LEFT RIGHT ')

! ====================================================================================
VitMatch.Construct Procedure()
  code
  self.binds    &= new MatchBindQType
  self.matches  &= new MatchRecQType
  self.bindRecs &= new BindRecQType
  self.rl       &= NULL
  self.tk       &= NULL
  self.patQ     &= NULL
  self.anchorLits &= NULL
  self.anchorPost &= NULL
  self.chainMissQ &= new ChainMissQType                          !
  self.freqDirty  = true

! ------------------------------------------------------------------------------------
VitMatch.Destruct Procedure()
  code
  if not self.binds &= NULL
    free(self.binds)
    dispose(self.binds)
  end
  if not self.matches &= NULL
    free(self.matches)
    dispose(self.matches)
  end
  if not self.bindRecs &= NULL
    free(self.bindRecs)
    dispose(self.bindRecs)
  end
  if not self.chainMissQ &= NULL                                 !
    free(self.chainMissQ)
    dispose(self.chainMissQ)
  end
  if not self.anchorLits &= NULL
    free(self.anchorLits)
    dispose(self.anchorLits)
  end
  if not self.anchorPost &= NULL
    free(self.anchorPost)
    dispose(self.anchorPost)
  end
  self.patQ &= NULL

! ------------------------------------------------------------------------------------
VitMatch.Init Procedure(VitRules pRl, VitTokenize pTk)
  code
  self.rl &= pRl
  self.tk &= pTk
  self.matchCount = 0
  self.skipCount  = 0
  if self.anchorLits &= NULL then self.anchorLits &= new AnchorLitQType.
  if self.anchorPost &= NULL then self.anchorPost &= new AnchorPostQType.   !
  if ~records(self.anchorLits) then self.BuildAnchorLits().                 ! rules are fixed across files: build once
  self.freqDirty = true                                                     ! new file/case: recount on first CountTok

! ------------------------------------------------------------------------------------
VitMatch.MatchAll Procedure(StringTheory pReport)
r  long,auto
  code
  if self.rl &= NULL or self.tk &= NULL then return 0.
  loop r = 1 to records(self.rl.rules)
    get(self.rl.rules, r)
    if errorcode() then break.
    if self.rl.rules.kind <> vr:kindRule then cycle.
    if self.rl.rules.skip then cycle.
    if ~self.rl.GroupActive(self.rl.rules.groupId) then cycle. ! unselected GROUP
    self.MatchRule(r, pReport)
  end
  return self.matchCount

! ------------------------------------------------------------------------------------
! One rule over the whole token stream. Anchor scan: find the rule's rarest
! literal token, then try every start position from the statement start up to
! the anchor occurrence. Matches never overlap (lastEnd).
! ------------------------------------------------------------------------------------
VitMatch.MatchRule Procedure(LONG pRow, StringTheory pReport)
anchor   StringTheory
anchorOp string(4),auto                            ! this rule's anchor as a canonical operator ('' = it is not one)
aCount   long,auto
i        long,auto
s        long,auto
e        long,auto
ss       long,auto
N        long,auto
svMatch  long,auto
pKey     STRING(80)                                !
pr       long,auto
  code
  get(self.rl.rules, pRow)
  if errorcode() then return.
  self.patQ &= self.rl.rules.patQ
  if self.patQ &= NULL then return.
  self.patCount = records(self.patQ)
  if ~self.patCount then return.
  self.ruleId = self.rl.rules.ruleId
  if self.rl.rules.gdCached                        ! guards are pure pattern facts - classify once per rule, reuse across files/passes
    self.gdStmt   = self.rl.rules.gdStmt
    self.gdNoDot  = self.rl.rules.gdNoDot
    self.gdNoSelf = self.rl.rules.gdNoSelf
    self.gd1Lit   = self.rl.rules.gd1Lit
    self.gd1IdMv  = self.rl.rules.gd1IdMv
    self.gd2Dot   = self.rl.rules.gd2Dot
  else
    self.ClassifyGuards()
    self.rl.rules.gdCached = 1
    self.rl.rules.gdStmt   = self.gdStmt
    self.rl.rules.gdNoDot  = self.gdNoDot
    self.rl.rules.gdNoSelf = self.gdNoSelf
    self.rl.rules.gd1Lit   = self.gd1Lit
    self.rl.rules.gd1IdMv  = self.gd1IdMv
    self.rl.rules.gd2Dot   = self.gd2Dot
    put(self.rl.rules)
  end
  self.lastEnd = 0
  N = self.tk.records()
  aCount = self.PickAnchor(anchor)
  if self.verbose and not self.vlog &= NULL ! DIAG: which anchor each rule picked + whether it got skipped
    self.vlog.append('[scan] rule ' & self.ruleId & ' anchor=' & choose(aCount<0,'(no-literal)',clip(anchor.getValue())) & |
                     ' aCount=' & aCount & ' gd1Lit=' & self.gd1Lit & ' gd1IdMv=' & self.gd1IdMv                         & |
                     choose(aCount=0,'  <<SKIPPED anchor-absent>>','') & '<13,10>')
  end
  if ~aCount then return.                       ! anchor literal absent: rule cannot match this file
  ! ONCE per rule, not once per candidate: '' for all but a comparison operator, and then the
  ! candidate loops below skip the two-word test on a single byte.
  ! L: slice rather than getValue() - the slice reads the buffer where it lies, getValue()
  ! copies it - and choose() is what guards the slice. Clarion short-circuits and evaluates
  ! only what it needs, so the valuePtr[1 : 0] that an EMPTY anchor would form never happens.
  ! It can be empty: aCount of -1 means the pattern has no literal to anchor on at all.
  anchorOp = choose(~anchor._DataEnd, '', self.OpCanon(anchor.valuePtr[1 : anchor._DataEnd]))
  pr = 0                                        ! ,auto - and the postings test below reads it on BOTH paths
  if aCount > 0 and not self.anchorPost &= NULL ! walk ONLY the anchor's occurrences (postings built by RefreshFreq)
    self.FreqKey(anchor.getValue(), pKey)
    pr = self.FindFirstPost(pKey)
  end
  ! no postings for a key the count says IS present means the anchor was never
  ! collected, so CountTok answered from its defensive full scan. Returning here turned that
  ! defence into ZERO matches for the rule - silently, and only for the rule it rescued.
  ! Fall through to the linear loop below instead, which needs no postings.
  if aCount > 0 and not self.anchorPost &= NULL and pr
    loop pr = pr to records(self.anchorPost)
      get(self.anchorPost, pr)
      if errorcode() then break.
      if self.anchorPost.keyText <> pKey then break.
      i = self.anchorPost.pos
      if i <= self.lastEnd then cycle.
      if ~self.LitMatches(i, anchor.valuePtr[1 : anchor._DataEnd])
        if ~anchorOp then cycle.                ! the anchor has no two-word spelling, so nothing else can qualify
        if ~self.AnchorNotPair(i, anchorOp) then cycle.
      end ! STRING(80) keys can MERGE distinct literals - postings are a superset, LitMatches is the arbiter (AnchorNotPair covers the two-word NOT form it cannot see)
      ss = self.StmtStart(i)
      if ss <= self.lastEnd then ss = self.lastEnd + 1.
      svMatch = self.matchCount
      loop s = ss to i
        if self.TokIsEOL(s) then cycle.
        if ~self.CandOK(s) then cycle.
        e = self.TryFrom(s, pReport)
        if e
          self.lastEnd = e
          break
        end
      end
      if self.rl.rules.once and self.matchCount > svMatch
        break                    ! ONCE: at most one applied match per file
      end
    end
    return
  end
  loop i = 1 to N                ! no-literal patterns (aCount<0): try every position
    if i <= self.lastEnd then cycle.
    if self.TokIsEOL(i) then cycle.
    if aCount > 0
      if ~self.LitMatches(i, anchor.valuePtr[1 : anchor._DataEnd])
        if ~anchorOp then cycle. ! the anchor has no two-word spelling, so nothing else can qualify
        if ~self.AnchorNotPair(i, anchorOp) then cycle.
      end                        ! fallback path (postings unavailable)
      ss = self.StmtStart(i)
      if ss <= self.lastEnd then ss = self.lastEnd + 1.
    else
      ss = i
    end
    svMatch = self.matchCount
    loop s = ss to i
      if self.TokIsEOL(s) then cycle.
      if ~self.CandOK(s) then cycle.
      e = self.TryFrom(s, pReport)
      if e
        self.lastEnd = e
        break
      end
    end
    if self.rl.rules.once and self.matchCount > svMatch
      break ! ONCE: at most one applied match per file
    end
  end

! ------------------------------------------------------------------------------------
! Auto-guards per spec 3.6, computed once per rule:
!  - bare function pattern  (literal label + '(')      -> no '.' before match
!  - mv.method pattern      (identifier metavar + '.') -> no '.' before match, receiver <> SELF
!  - statement anchoring for DELETE rules, assignment-shaped patterns,
!    multi-statement replacements (depth-0 ';' in the replacement), and
!    multi-statement PATTERNS (interior ';' boundary part, spec v0.3).
!    A trailing pattern ';' (end-of-statement assertion) does NOT anchor.
!    Deliberate deviation from a literal reading of spec 3.6: plain method-call
!    patterns with single-expression replacements (the getval/assign renames)
!    are NOT statement-anchored, so they also match inside expressions.
! ------------------------------------------------------------------------------------
VitMatch.ClassifyGuards Procedure()
p1tok  StringTheory
p2tok  StringTheory
p1mvx  long,auto
kind   byte,AUTO
t      long,auto
depth  long,auto
  code
  self.gdNoDot  = 0
  self.gdNoSelf = 0
  self.gdStmt   = 0
  self.gd1Lit   = 0
  self.gd1IdMv  = 0
  self.gd2Dot   = 0
  get(self.patQ, 1)
  if errorcode() then return.
  if self.patQ.tok &= NULL then return.
  p1tok.setValue(self.patQ.tok,st:clip)
  p1mvx = self.patQ.mvx
  if ~p1mvx then self.gd1Lit = 1.
  get(self.patQ, 2)
  if ~errorcode()
    if not self.patQ.tok &= NULL
      p2tok.setValue(self.patQ.tok,st:clip)
    end
  end
  kind = 0
  if p1mvx
    get(self.rl.metaVars, p1mvx)
    if ~errorcode() then kind = self.rl.metaVars.kind.
  end
  if ~p1mvx and self.rl.IsLabelToken(p1tok.getValue()) and p2tok._DataEnd = 1 and p2tok.valuePtr[1] = '('
    self.gdNoDot = 1
  end
  if p1mvx and (kind = vr:mvTyped or kind = vr:mvClass or kind = vr:mvAnyVar or kind = vr:mvTypeSet)
    self.gd1IdMv = 1
    if p2tok._DataEnd = 1 and p2tok.valuePtr[1] = '.'
      self.gd2Dot   = 1
      self.gdNoDot  = 1
      self.gdNoSelf = 1
    end
  end
  if self.rl.rules.isDelete  or |
     self.rl.rules.isComment or |   ! commenting-out is statement surgery too
     p2tok._DataEnd = 1 and p2tok.valuePtr[1] = '=' and ~self.rl.rules.inParens
    self.gdStmt = 1
  end
                                                               ! the '=' as second pattern token means
                                                               ! ASSIGNMENT-SHAPED, so anchor it to a whole statement -
                                                               ! UNLESS the rule carries INPARENS, which asserts the exact
                                                               ! opposite. The two cannot both hold: a match starting
                                                               ! inside an unclosed bracket never starts a statement, so
                                                               ! leaving this on would make every INPARENS rule of this
                                                               ! shape silently unreachable rather than wrong - the worst
                                                               ! kind of quiet. INPARENS is itself the proof that the '='
                                                               ! is not an assignment, which is what the anchoring was for.
  case p2tok.getValue()                                        ! compound assignments are assignment-shaped too - without this they got NO statement anchoring
  of '+=' orof '-=' orof '*=' orof '/=' orof '&=' orof ':=' orof '=:'
    self.gdStmt = 1
  end
  ! spec v0.3: an interior ';' pattern part is a statement boundary; such
  ! patterns anchor to statement start. A trailing ';' is only an
  ! end-of-statement assertion and must NOT anchor the start - the
  ! 'and st.findChar(w) ;' context rules match mid-statement.
  loop t = 1 to records(self.patQ) - 1
    get(self.patQ, t)
    if errorcode() then break.
    if self.patQ.tok &= NULL then cycle.
    if ~self.patQ.mvx and self.patQ.tok = ';'
      self.gdStmt = 1
      break
    end
  end
  if not self.rl.rules.repQ &= NULL
    depth = 0
    loop t = 1 to records(self.rl.rules.repQ)
      get(self.rl.rules.repQ, t)
      if errorcode() then break.
      if self.rl.rules.repQ.tok &= NULL then cycle.
      if ~depth and self.rl.rules.repQ.tok = ';'
        self.gdStmt = 1
        break
      end
      depth += self.DepthDelta(clip(self.rl.rules.repQ.tok))
    end
  end

! ------------------------------------------------------------------------------------
VitMatch.PickAnchor Procedure(StringTheory pAnchor)
aTx      StringTheory   ! the candidate's text, held while the two peeks move the patQ buffer
cmpT     string(4),auto ! a variable for the *STRING callees below
t        long,auto
best     long,AUTO
bestCnt  long,AUTO
cnt      long,auto
  code
  best = 0
  bestCnt = 0
  loop t = 1 to self.patCount
    get(self.patQ, t)
    if errorcode() then break.
    if self.patQ.mvx or |
       self.patQ.tok &= NULL
      cycle
    end
    if self.patQ.tok = ';'              ! spec v0.3 statement boundary
      if t < self.patCount then break.  ! interior: anchor from fragment 1 ONLY - MatchRule's
                                        ! candidate scan is statement-local (StmtStart of the anchor)
      cycle                             ! trailing assertion: not a literal to anchor on
    end
    ! A comparison operator with SYNONYMS is never the anchor. The anchor is looked up by a
    ! single-token frequency key, and the two-word `NOT =` form has no such key - so anchoring
    ! a rule on `<>` against a file that spells it `NOT =` returns a count of 0 and MatchRule
    ! gives up at "anchor literal absent" before comparing anything. (That is exactly how the
    ! one-token synonyms failed until FreqKey learned to canonicalise.) They make poor anchors
    ! anyway - PickAnchor wants the RAREST literal and operators are the commonest tokens
    ! there are - so the only patterns this changes are those with no other literal at all,
    ! which fall to the linear scan and still match.
    aTx.setValue(self.patQ.tok,st:clip) ! captured BEFORE the peeks below move the buffer
    cmpT = aTx.getValue()               ! *STRING callee needs a variable; 4 bytes, and anything longer
                                        !   truncates to 4 and still fails its one-character test
    ! A single-token comparison operator IS still a fine anchor: FreqKey canonicalises the
    ! one-token synonyms and RefreshFreq posts the two-word `NOT =` form under the same key, so
    ! the count is right whichever way the source spells it. What CANNOT anchor is either half
    ! of a two-word `NOT =` in the PATTERN: source spelling it `<>` contains no `NOT` and no
    ! `=`, so either would count 0 and skip the rule. Peek one row each way to recognise the
    ! pair. (Excluding operators outright also works and is what this did first - it cost 35%
    ! on the corpus, because rules with no other literal then fell to the linear scan.)
    if upper(choose(aTx._DataEnd < 1, '', aTx.valuePtr[1 : aTx._DataEnd])) = 'NOT'
      if t < self.patCount
        get(self.patQ, t + 1)
        if ~errorcode() and ~self.patQ.mvx and not self.patQ.tok &= NULL
          if self.OpCanonNot(self.patQ.tok) then cycle.
        end
      end
    elsif self.OpCanonNot(cmpT) and t > 1
      get(self.patQ, t - 1)
      if ~errorcode() and ~self.patQ.mvx and not self.patQ.tok &= NULL
        if upper(self.patQ.tok) = 'NOT' then cycle.
      end
    end
    cnt = self.CountTok(aTx.getValue())
    if ~best or cnt < bestCnt
      best    = t
      bestCnt = cnt
      pAnchor.setValue(aTx)
    end
    if best and ~bestCnt then break. ! cannot get rarer than absent
  end
  if ~best then return -1.
  return bestCnt

! ------------------------------------------------------------------------------------
VitMatch.CountTok Procedure(STRING pLit)
i    long,auto
n    long,auto
cnt  long
key  STRING(80)
row  long,auto
  code
  if not self.anchorLits &= NULL
    if self.freqDirty
      self.RefreshFreq()
      self.freqDirty = false
    end
    self.FreqKey(pLit, key)
    row = self.FindAnchorLit(key)
    if row
      get(self.anchorLits, row)
      return self.anchorLits.cnt
    end
    ! literal not in the precomputed set (should not happen - every pattern
    ! literal is collected) - fall through to a defensive full scan
  end
  n = self.tk.records()
  loop i = 1 to n
    if self.LitMatches(i, pLit) then cnt += 1.
  end
  return cnt

! ------------------------------------------------------------------------------------
! FreqKey - LitMatches' notion of token identity, as a fixed-width sort key.
! A quoted literal (leading ') is compared case-sensitively; everything else
! caselessly. Truncation to the key width merges distinct long literals, which
! can only OVERcount a count (never drop it to a false 0), so it never causes a
! rule to be wrongly skipped. Anchors are short tokens in practice, so real
! anchor counts are exact.
! ------------------------------------------------------------------------------------
VitMatch.FreqKey Procedure(STRING pTok, *STRING pKeyOut)
w    long,auto
opC  string(4),auto
  code
  ! plain Clarion string ops (no StringTheory): this runs once per token per
  ! RefreshFreq, so object construction per call would dominate.
  pKeyOut = ''
  ! an operator with more than one documented spelling keys under its CANONICAL one, so
  ! the stream's `=<` and a pattern's `<=` land on the same row. Without this the fix in
  ! LitMatches is unreachable: PickAnchor asks CountTok how often the pattern's rarest literal
  ! occurs, the count for `<=` comes back 0 against a stream that spells it `=<`, and MatchRule
  ! returns at "anchor literal absent" before any token is ever compared. The postings list is
  ! keyed the same way, so the candidate positions are right too.
  opC = self.OpCanon(pTok)
  if opC
    pKeyOut = opC
    return
  end
  w = len(clip(pTok))
  if ~w then return.
  if w > 80 then w = 80.
  if pTok[1] = '''' ! quoted literal: exact case
    pKeyOut = pTok[1 : w]
  else              ! identifier/keyword/operator: caseless
    pKeyOut = upper(pTok[1 : w])
  end

! ------------------------------------------------------------------------------------
! BuildAnchorLits - collect the distinct literal tokens across every rule's
! pattern, once (rules are fixed for the run). ';' boundary/assertion parts and
! metavars are not literals. Result is sorted by keyText for FindAnchorLit's
! binary search. Counts are filled later by RefreshFreq.
! ------------------------------------------------------------------------------------
VitMatch.BuildAnchorLits Procedure()
r    long,auto
t    long,auto
key  STRING(80)
prev STRING(80),AUTO
row  long,auto
  code
  if self.anchorLits &= NULL then self.anchorLits &= new AnchorLitQType.
  free(self.anchorLits)
  if self.rl &= NULL then return.
  loop r = 1 to records(self.rl.rules)
    get(self.rl.rules, r)
    if errorcode() then break.
    if self.rl.rules.kind <> vr:kindRule or |
       self.rl.rules.patQ &= NULL
      cycle
    end
    loop t = 1 to records(self.rl.rules.patQ)
      get(self.rl.rules.patQ, t)
      if errorcode() then break.
      if self.rl.rules.patQ.tok &= NULL  or |
         self.rl.rules.patQ.mvx          or |   ! metavar, not a literal
         self.rl.rules.patQ.tok = ';' ! statement boundary/assertion
        cycle
      end
      self.FreqKey(self.rl.rules.patQ.tok, key)
      if ~key then cycle.
      self.anchorLits.keyText = key
      self.anchorLits.cnt     = 0
      add(self.anchorLits)            ! dups allowed here; collapsed after the sort
    end
  end
  if ~records(self.anchorLits) then return.
  sort(self.anchorLits, +self.anchorLits.keyText)
  row = records(self.anchorLits)      ! collapse adjacent duplicates, top-down
  loop while row > 1
    get(self.anchorLits, row)
    key = self.anchorLits.keyText
    get(self.anchorLits, row - 1)
    prev = self.anchorLits.keyText
    if key = prev
      get(self.anchorLits, row)
      delete(self.anchorLits)
    end
    row -= 1
  end

! ------------------------------------------------------------------------------------
! RefreshFreq - one pass over the current token stream, recounting each
! distinct pattern literal. O(tokens x log distinctLiterals). Called from
! CountTok when freqDirty; freqDirty is set wherever the token stream is
! mutated (rule fire, builtin edit, rejoin/reparse) so the count=0 skip stays
! correct.
! ------------------------------------------------------------------------------------
VitMatch.RefreshFreq Procedure()
i    long,auto
key2 STRING(80),AUTO                                         ! canonical key of a two-word NOT operator opening at i
cmpT string(4),auto                                          ! a variable for the *STRING callee
n    long,auto
row  long,auto
key  STRING(80)
  code
  if self.anchorLits &= NULL then return.
  loop row = 1 to records(self.anchorLits)
    get(self.anchorLits, row)
    self.anchorLits.cnt = 0
    put(self.anchorLits)
  end
  if not self.anchorPost &= NULL then free(self.anchorPost). ! rebuild postings with the counts
  if self.tk &= NULL then return.
  n = self.tk.records()
  loop i = 1 to n
    if self.TokIsEOL(i) then cycle.
    self.FreqKey(self.TokText(i), key)
    if ~key then cycle.
    row = self.FindAnchorLit(key)
    if row
      get(self.anchorLits, row)
      self.anchorLits.cnt += 1
      put(self.anchorLits)
      if not self.anchorPost &= NULL      ! record the occurrence
        self.anchorPost.keyText = self.anchorLits.keyText
        self.anchorPost.pos     = i
        add(self.anchorPost)
      end
    end
    ! An infix `NOT` opening a two-word operator is ALSO posted under that operator's canonical
    ! key, so a rule anchored on `<>` still finds source that spells it `NOT =`. Without this
    ! the anchor count comes back 0 and MatchRule gives up before comparing anything - and the
    ! alternative, refusing to anchor on comparison operators at all, cost 35% on the corpus
    ! because rules then fell to the linear scan. Posted IN ADDITION to its own 'NOT' key, so a
    ! rule that genuinely anchors on the word NOT is unaffected. One probe per NOT token.
    if key = 'NOT' and self.NotInfixAt(i) ! `key` is already this token's upper text -
      cmpT = self.TokText(i + 1)
      key2 = self.OpCanonNot(cmpT)        !   test it before paying for NotInfixAt,
                                          !   which would otherwise run on EVERY token
                                          !   of every refresh
      if key2
        row = self.FindAnchorLit(key2)
        if row
          get(self.anchorLits, row)
          self.anchorLits.cnt += 1
          put(self.anchorLits)
          if not self.anchorPost &= NULL
            self.anchorPost.keyText = self.anchorLits.keyText
            self.anchorPost.pos     = i
            add(self.anchorPost)
          end
        end
      end
    end
  end
  if not self.anchorPost &= NULL
    sort(self.anchorPost, +self.anchorPost.keyText, +self.anchorPost.pos) ! +pos is LOAD-BEARING: MatchRule's lastEnd/ONCE logic needs ascending positions within each key run, and POSITION() lower-bounds on this active sort order
  end

! ------------------------------------------------------------------------------------
! FindAnchorLit - binary search the sorted anchorLits by key. 0 = not present.
! ------------------------------------------------------------------------------------
VitMatch.FindAnchorLit Procedure(STRING pKey)
  code
  ! keys are UNIQUE (deduped at build) and the queue is sorted by keyText, so a keyed
  ! GET binary-searches natively.
  if self.anchorLits &= NULL then return 0.
  self.anchorLits.keyText = pKey
  get(self.anchorLits, self.anchorLits.keyText)
  if errorcode() then return 0.
  return pointer(self.anchorLits)

! ------------------------------------------------------------------------------------
! FIRST anchorPost row whose keyText = pKey (postings sorted keyText,pos). 0 = absent.
! this banner used to describe a binary search landing on SOME matching row and then
! WALKING BACK to the first. There is no walk-back in the body and there never needs to be -
! the POSITION lower-bound idiom below lands on the first row of the run directly. The comment
! described an implementation that was considered, not the one that is here.
! ------------------------------------------------------------------------------------
VitMatch.FindFirstPost Procedure(STRING pKey)
  code
  ! the POSITION(queue) idiom - with the buffer CLEARed (pos = 0) and keyText
  ! set, POSITION lower-bounds on the active (keyText,pos) sort order: it returns the FIRST
  ! row of pKey's run; on a miss it returns the next-greater row (or RECORDS+1), which the
  ! caller's keyText-change break handles. Documented behaviour, no bookkeeping.
  if self.anchorPost &= NULL then return 0.
  clear(self.anchorPost)
  self.anchorPost.keyText = pKey
  return position(self.anchorPost)

! ------------------------------------------------------------------------------------
! Typed metavar gate: resolve the identifier in the symbol
! table for its scope; unresolvable = no match. ANYVAR always passes; no
! symbol table attached or --loose = untyped (everything passes). CSTRING is
! not STRING; &Type equals Type (isRef ignored); class names caseless.
! ------------------------------------------------------------------------------------
VitMatch.TypeOK Procedure(LONG pMvx, LONG pS)
tU  STRING(vs:maxName)
rf  BYTE
ok  LONG,AUTO
tsx LONG,AUTO ! typeSets row
  code
  if self.loose or |
     self.syms &= NULL
    return true
  end
  get(self.rl.metaVars, pMvx)
  if errorcode() then return false. ! REFUSE on a failed metavar fetch. Returning true would make a
                                    !   TYPED gate accept anything - the type check disappears and the
                                    !   rule rewrites what it was never meant to touch. ClassSatisfies
                                    !   refuses on this condition too - all three must agree.
  if self.rl.metaVars.kind = vr:mvAnyVar or |
     self.rl.metaVars.kind <> vr:mvTyped and self.rl.metaVars.kind <> vr:mvClass and self.rl.metaVars.kind <> vr:mvTypeSet
    return true
  end
  ok = self.syms.Lookup(self.TokText(pS), pS, tU, rf)
  if ~ok                                         ! undeclared: ASSUME patterns may supply a type
    tU = upper(self.rl.AssumeType(self.TokText(pS)))
    if tU then ok = true.
  end
  if ok and self.rl.metaVars.kind = vr:mvTypeSet ! membership in the named TYPESET
    tsx = self.rl.FindTypeSet(self.rl.metaVars.typeName)
    if tsx
      get(self.rl.typeSets, tsx)
      if instring(' ' & clip(tU) & ' ', self.rl.typeSets.members, 1, 1) then return true.
    end
  elsif ok and upper(self.rl.metaVars.typeName) = tU
    return true
  end
  if self.verbose and not self.vlog &= NULL
    self.vlog.append('rule ' & self.rl.rules.ruleId & ' line ' & self.LineOf(pS) & ' type-miss: ' & |
                     self.TokText(pS) & ' is ' & choose(ok, clip(tU), 'unresolved')               & |
                     ', rule wants ' & clip(self.rl.metaVars.typeName) & '<13,10>')
  end
  ! UNRESOLVED only, and only a RECEIVER - a token followed by '.'. `ok` with the
  ! wrong type is an ordinary no-match and must stay silent (see NoteChainUnres), and an
  ! unresolved token that is NOT a receiver is usually a keyword or a runtime function
  ! sitting where a typed metavar could have bound: the first cut of this diagnostic named
  ! UPPER, END, DELETE, CYCLE and CLIP on a real file, which is noise wearing a signal's
  ! clothes. A receiver is the case the advice can actually help with.
  ! IsMemberDot, not a raw '.' test: a one-liner's TERMINATOR dot is also a '.' token, and
  ! testing the text alone reported TRUE and FALSE as receivers - `if x then return true.`
  ! Measured on Preprocessor.clw, where they were the only two names left.
  if ~ok and self.IsMemberDot(pS + 1) then self.NoteChainUnres(self.TokText(pS)).
  return false

! ------------------------------------------------------------------------------------
! a typed rule refused because the thing it looked at could not be RESOLVED AT
! ALL - an identifier the symbol table does not hold, or a dotted receiver whose class or
! member is not in the type registry. Count it, and keep the DISTINCT names so the report
! can say which ones.
!
! WHAT IS NOT COUNTED, and that distinction is the whole value of the line: something that
! resolved to the WRONG type. `sc` wanted a STRING and found a LONG is an ordinary
! no-match - the rule correctly did not apply - and counting those would bury the signal
! under every rule that behaved perfectly.
!
! WHY IT IS WORTH A LINE AT ALL: the commonest cause of an unresolved one is the
! declaration living in an INCLUDE, which is invisible without --thorough. That is the
! miss users actually hit that would not convert, because
! self.PPDefines is declared in Preprocessor.inc), and until now the tool said nothing
! about it - the run just did less, silently, which is the failure mode this project
! keeps paying for.
! ------------------------------------------------------------------------------------
VitMatch.NoteChainUnres Procedure(STRING pRecv)
r    long,auto
nmU  string(vs:maxName),auto
  code
  self.chainUnres += 1
  if self.chainMissQ &= NULL or |
     records(self.chainMissQ) >= 40             ! the COUNT keeps counting; the NAMES stop at a readable few
    return
  end
  nmU = upper(pRecv)
  if ~nmU then return.
  loop r = 1 to records(self.chainMissQ)
    get(self.chainMissQ, r)
    if errorcode() then break.
    if self.chainMissQ.recvU = nmU then return. ! already listed - distinct names only
  end
  self.chainMissQ.recvU = nmU
  add(self.chainMissQ)

! ------------------------------------------------------------------------------------
! Design B0b: the tokenizer recombines a member-access receiver into ONE token
! ('self.Direct', 'self.Inner.Payload'). Type it by splitting on the FIRST '.': the head
! resolves via Lookup (self -> receiver class; else a declared local/param), falling back
! to the registry for a labelled structure instance (Grp GROUP - the label IS the typedef;
! dot-form), and the rest (dots -> '|') walk the type registry to a terminal type
! that must equal the metavar's class OR scalar type OR belong to its TYPESET (mvTyped/
! mvTypeSet chains - mirrors TypeOK). Any unresolved hop = false (conservative).
! ------------------------------------------------------------------------------------
VitMatch.ChainTypeOK Procedure(LONG pMvx, LONG pS)
txt    STRING(vs:maxName),AUTO
head   STRING(vs:maxName),AUTO
segs   StringTheory
tU     STRING(vs:maxName)
rf     BYTE
ok     long,AUTO
term   STRING(vs:maxName),AUTO
dotP   long,auto
tLen   long,auto
tsx    long,auto ! dot-form: TYPESET row for terminal membership
  code
  if self.loose or |
     self.syms &= NULL
    return true
  end
  get(self.rl.metaVars, pMvx)
  if errorcode() then return false.         ! REFUSE on a failed metavar fetch. Returning true would make a
                                            !   TYPED gate accept anything - the type check disappears and the
                                            !   rule rewrites what it was never meant to touch. ClassSatisfies
                                            !   refuses on this condition too - all three must agree.
  if self.rl.metaVars.kind <> vr:mvClass and self.rl.metaVars.kind <> vr:mvTyped and self.rl.metaVars.kind <> vr:mvTypeSet then return true.
  txt = self.TokText(pS)
  tLen = len(clip(txt))
  dotP = instring('.', txt, 1, 1)
  if dotP < 2 or dotP >= tLen then return false.
  head = upper(sub(txt, 1, dotP - 1))       ! receiver head (before first '.')
  ok = self.syms.Lookup(head, pS, tU, rf)   ! self -> receiver class; local/param -> its type
  if ~ok
    tU = upper(self.rl.AssumeType(head))
    if tU then ok = true.
  end
  if ~ok and self.syms.FindTypeDef(head)    ! dot-form: a labelled structure INSTANCE (Grp GROUP / UseQ QUEUE)
    tU = head                               ! is a registry typedef under its own label, not a symbol - the label IS the type
    ok = true
  end
  if self.verbose and not self.vlog &= NULL ! DIAG: trace EVERY chain check (not just misses)
    self.vlog.append('[chain] rule ' & self.rl.rules.ruleId & ' tok@' & pS & ' "' & clip(txt) & '" head=' & clip(head) & |
                     ' selfLookup=' & choose(ok,'ok->' & clip(tU),'FAIL') & '<13,10>')
  end
  if ~ok
    ! a quoted LITERAL containing a dot reaches this path too - `'.target='''`
    ! splits into a "head" that resolves to nothing - and naming those as receivers is
    ! noise. Measured on NetWeb V1400.clw with --thorough already on, where the residual
    ! twelve "receivers" were ALL literals. Only a real identifier is worth reporting.
    if self.TokType(pS) <> vt:literal
      self.NoteChainUnres(txt)                          ! the HEAD has no known class - not visible, not wrong
    end
    return false
  end
  segs.setValue(sub(txt, dotP + 1, tLen - dotP))        ! remaining members: 'Direct' or 'Inner.Payload'
  segs.replaceByte(46, 124)                             ! replace all <dot> with '|'
  term = self.syms.LookupChain(tU, segs.getValue(), pS) ! pS: the receiver token IS the use site, and that is what tells two procedures' same-named local types apart
  if self.verbose and not self.vlog &= NULL
    self.vlog.append('[chain] rule ' & self.rl.rules.ruleId & ' segs=' & clip(segs.getValue()) & |
                     ' term=' & choose(term = '','(unresolved)',clip(term)) & ' wants=' & clip(self.rl.metaVars.typeName) & '<13,10>')
  end
  if ~term
    ! head typed, member not in the registry. Count it ONLY when the head's CLASS
    ! is itself unknown to the registry - that is the visibility case, and the shape it takes:
    ! self resolves to PREPROCESSOR, PREPROCESSOR's fields live in the .inc, and without
    ! --thorough nothing ever read it. If the class IS known, the member is simply not a
    ! field of the wanted type (`self.ParseDirective` is a METHOD), the rule correctly does
    ! not apply, and saying so would put 904 useless names on the line - measured, not
    ! guessed: that is what the first cut of this diagnostic printed for Preprocessor.clw
    ! WITH --thorough already on.
    if ~self.syms.FindTypeDef(tU) then self.NoteChainUnres(txt).
    return false
  end
  if self.rl.metaVars.kind = vr:mvTypeSet ! dot-form: terminal must be a member of the named TYPESET
    tsx = self.rl.FindTypeSet(self.rl.metaVars.typeName)
    if tsx
      get(self.rl.typeSets, tsx)
      if instring(' ' & clip(term) & ' ', self.rl.typeSets.members, 1, 1) then return true.
    end
  elsif upper(self.rl.metaVars.typeName) = term
    return true
  end
  if self.verbose and not self.vlog &= NULL
    self.vlog.append('chain-miss: rule ' & self.rl.rules.ruleId & ' ' & clip(txt) & ' head=' & clip(head) & |
                     '->' & clip(tU) & ' terminal=' & choose(term = '', '(unresolved)', clip(term))       & |
                     ' wants ' & clip(self.rl.metaVars.typeName) & '<13,10>')
  end
  return false

! ------------------------------------------------------------------------------------
! ------------------------------------------------------------------------------------
! how many arguments does the call whose '(' sits at pOpenTok pass?
! -1 = cannot tell (not a '(', or no matching ')' before end of statement), which every
! consumer must treat as "consider all overloads" rather than as a count of zero.
! Commas are counted at the TOP level only - a nested call or a sub-expression's commas
! belong to it, not to us.
! ------------------------------------------------------------------------------------
VitMatch.CallArgCount Procedure(LONG pOpenTok)
e      long,auto
depth  long,auto
n      long,auto
seen   byte,auto
  code
  if self.TokIsEOL(pOpenTok) then return -1.
  if self.TokText(pOpenTok) <> '(' then return -1.
  depth = 1
  n     = 0
  seen  = 0
  e     = pOpenTok
  loop
    e += 1
    if self.TokIsEOL(e) then return -1. ! statement ended before the ')' - refuse, do not guess
    case self.TokText(e)
    of '('
      depth += 1
    of ')'
      depth -= 1
      if ~depth then break.
    of ','
      if depth = 1 then n += 1.         ! a separator at OUR level ends an argument
    end
    if depth = 1 and self.TokText(e) <> ',' then seen = 1.
  end
  if ~seen then return 0.               ! '()' - a real arity of zero, not an unknown
  return n + 1                          ! k separators = k+1 arguments

! ------------------------------------------------------------------------------------
! what TYPE is the first argument of the call whose '(' sits at pOpenTok?
!   <type name>    the argument is a single identifier and the symbol table resolved it
!   vs:scalarArg   it is a numeric or quoted LITERAL - a value, certainly not a class
!   ''             anything else: no arguments, a multi-token expression, or an
!                  identifier that did not resolve
! Only the first two are positive facts, and only a positive fact is allowed to exclude an
! overload. A multi-token expression is deliberately NOT typed here - working out what
! `a + b` or `f(x)` evaluates to is a different job, and guessing it would be the wrong
! kind of confident.
! ------------------------------------------------------------------------------------
! EVERY argument, not just the first. Returns one '|'-terminated slot per argument,
! in order, each holding what we could work out about it and EMPTY where we could not. The rule
! per slot is exactly what CallArg1Type applied to slot 1, unchanged:
!   a quoted literal or a number  -> vs:scalarArg  (definitely a value, so not a class instance)
!   a single label token          -> its class, or '' when the symbol table cannot place it
!   anything else                 -> '' - a multi-token expression like `a + b` or `f(x)` is a
!                                   different job, and guessing it would be the wrong kind of
!                                   confident
! An empty slot narrows nothing (see VitSymbols.ArgAdmits), so widening from one argument to all
! of them can only ever ADD resolutions: a call settled by argument one is still settled, and one
! that was ambiguous may now be settled by a later argument.
VitMatch.CallArgTypes Procedure(LONG pOpenTok)
t     long,auto
dep   long,auto
txt   STRING(vs:maxName),AUTO
one   STRING(vs:maxName),AUTO
res   stringTheory
first long
  code
  if self.TokIsEOL(pOpenTok) then return ''.
  if self.TokText(pOpenTok) <> '(' then return ''.
  t = pOpenTok + 1
  if self.TokIsEOL(t) then return ''.
  if self.TokText(t) = ')' then return ''.      ! no arguments at all
  dep   = 0
  first = t
  loop
    if self.TokIsEOL(t) then break.
    txt = self.TokText(t)
    if txt = '(' then dep += 1.
    if txt = ')'
      if ~dep
        do OneSlot                              ! the last argument, closed by ')'
        break
      end
      dep -= 1
    end
    if txt = ',' and ~dep
      do OneSlot
      first = t + 1
    end
    t += 1
  end
  if res._DataEnd > vs:maxSlots then return ''. ! too long to hold - say nothing at all rather than a partial list
  return choose(res._DataEnd < 1, '', res.valuePtr[1 : res._DataEnd])

! ---- tokens first..t-1 are one argument: type it if it is a single token we recognise ----
OneSlot routine
  one = ''
  if t - first = 1                              ! exactly one token - the only shape we type
    txt = self.TokText(first)
    if txt
      if txt[1] = ''''
        one = vs:scalarArg                      ! a quoted literal
      elsif numeric(clip(txt))
        one = vs:scalarArg                      ! a number
      elsif self.rl.IsLabelToken(txt)
        one = self.RecvClass(first)             ! '' when the symbol table cannot place it
      end
    end
  end
  res.append(clip(one) & '|')

! ------------------------------------------------------------------------------------
! does method pName on receiver class pRecvClassU return a STRING?
! Header truth first: when the registry has a typedef for the class, the answer comes
! from the prototype return-type table (inheritance via parentU; a *String / &String
! reference return COUNTS as string - it is a string value in expression context
! veto if ref returns should refuse). Registry-unknown class = six-name fallback
! (preserves the behaviour for header-less runs); counted for the per-file report line.
! pArgCount selects the OVERLOAD. -1 = the caller does not know its own arity,
! which considers every row - the behaviour, kept for any caller that cannot count.
! ------------------------------------------------------------------------------------
VitMatch.MethodReturnsString Procedure(STRING pRecvClassU, STRING pName, LONG pArgCount, STRING pArgTypesU)
retU  string(vs:maxName),auto
rf    byte
  code
  if not self.syms &= NULL
    if self.syms.FindTypeDef(pRecvClassU)
      retU = self.syms.MethodReturnClass(pRecvClassU, pName, rf, pArgCount, pArgTypesU) ! arity + EVERY argument's type pick the OVERLOAD
      return choose(retU = 'STRING')
    end
  end
  if instring(' ' & upper(clip(pName)) & ' ', stringReturners, 1, 1)
    self.rtFallbacks += 1                                                               ! count POSITIVES only - bindings the header table could not provide
    if self.verbose and not self.vlog &= NULL
      self.vlog.append('rettype-fallback: ' & clip(pRecvClassU) & '.' & clip(pName) & ' (class not in registry)<13,10>')
    end
    return true
  end
  return false

! ------------------------------------------------------------------------------------
! does class pClassU satisfy the metavar's declared class / scalar type / TYPESET?
! (The shared tail of TypeOK/ChainTypeOK, standalone so the span binder can ask about a
! COMPUTED class - the method's return type - instead of a token's looked-up type.)
! ------------------------------------------------------------------------------------
VitMatch.ClassSatisfies Procedure(LONG pMvx, STRING pClassU)
tsx  long,auto
  code
  get(self.rl.metaVars, pMvx)
  if errorcode() then return false.
  case self.rl.metaVars.kind
  of vr:mvTypeSet
    tsx = self.rl.FindTypeSet(self.rl.metaVars.typeName)
    if tsx
      get(self.rl.typeSets, tsx)
      if instring(' ' & clip(upper(pClassU)) & ' ', self.rl.typeSets.members, 1, 1) then return true.
    end
    return false
  of vr:mvClass orof vr:mvTyped
    return choose(upper(self.rl.metaVars.typeName) = upper(pClassU))
  end
  return false

! ------------------------------------------------------------------------------------
! (was RecvIsST): the TERMINAL CLASS of the receiver token at pS (plain
! identifier or recombined dotted chain); '' = unresolved. Same head+chain walk as
! ChainTypeOK, but the class comes back to the caller instead of being compared to a
! fixed STRINGTHEORY - MethodReturnsString then keys the header-derived table with it.
! loose mode answers STRINGTHEORY (preserves the loose behaviour: span binding
! stays available, gated by the method table alone; diagnostic mode only).
! ------------------------------------------------------------------------------------
VitMatch.RecvClass Procedure(LONG pS)
txt   STRING(vs:maxName),AUTO
head  STRING(vs:maxName),AUTO
segs  StringTheory
tU    STRING(vs:maxName)
rf    BYTE
ok    long,auto
dotP  long,auto
tLen  long,auto
  code
  if self.loose then return 'STRINGTHEORY'.
  if self.syms &= NULL then return ''.
  txt = self.TokText(pS)
  tLen = len(clip(txt))
  if ~tLen then return ''.
  dotP = instring('.', clip(txt), 1, 1)
  if ~dotP                                              ! plain identifier receiver
    if ~self.rl.IsLabelToken(txt) then return ''.
    ok = self.syms.Lookup(txt, pS, tU, rf)
    if ~ok
      tU = upper(self.rl.AssumeType(txt))
      if tU then ok = true.
    end
    if ~ok then return ''.
    return clip(tU)
  end
  if dotP < 2 or dotP >= tLen then return ''.           ! dotted chain receiver (self.buf etc)
  head = upper(sub(txt, 1, dotP - 1))
  ok = self.syms.Lookup(head, pS, tU, rf)
  if ~ok
    tU = upper(self.rl.AssumeType(head))
    if tU then ok = true.
  end
  if ~ok and self.syms.FindTypeDef(head)                ! labelled structure instance
    tU = head
    ok = true
  end
  if ~ok then return ''.
  segs.setValue(sub(clip(txt), dotP + 1, tLen - dotP))
  segs.replaceByte(46, 124)                             ! replace all <dot> with <pipe>
  return self.syms.LookupChain(tU, segs.getValue(), pS) ! pS: the use site, for the scope narrowing - see ChainTypeOK

! ------------------------------------------------------------------------------------
! WHERE guard on the current match. Compare guards render the bound span,
! apply trimr()/fold() (bare metavar = folded per spec 2.2), unquote a literal
! result, then compare exactly against the stored guard value (NULL = '').
! Class tests: isConst = folds to an integer; isLiteral = one quoted token;
! isVar = one identifier that resolves in the symbol table (label suffices
! when no symbol table is attached).
! ------------------------------------------------------------------------------------
! ------------------------------------------------------------------------------------
! an identifier
! SUFFIXED with " is an implicit STRING(32), with # an implicit LONG, with $ an
! implicit REAL. They are never declared, so suffix IS the type. The prefix must be
! label-shaped; a bare suffix char, literals and operators return ''.
! ------------------------------------------------------------------------------------
VitMatch.ImplicitType Procedure(STRING pTok)
tl  long,auto
  code
  tl = len(clip(pTok))
  if tl < 2 then return ''.
  if ~self.rl.IsLabelToken(sub(pTok, 1, tl - 1)) then return ''.
  case val(pTok[tl])
  of 34 ! "
    return 'STRING'
  of 35 ! #
    return 'LONG'
  of 36 ! $
    return 'REAL'
  end
  return ''

! ------------------------------------------------------------------------------------
! Does the current match satisfy the rule's WHERE clause.
!
! A WHERE IS AN AND-LIST: every clause must hold, so the first failure returns false. An empty
! guard queue answers true - a rule with no WHERE is unconstrained, not unsatisfiable.
!
! Read failure also answers false, which is the safe direction here: refusing to fire a rule
! loses a transform, firing one on an unverified guard changes code the rule was not meant to
! touch.
! ------------------------------------------------------------------------------------
VitMatch.GuardOK Procedure()
g     long,auto
  code
  ! a NULL guardQ here is an impossible state - the only caller tests guardKind first,
  ! so the rule HAS a WHERE - and the answer must be the SAFE direction. Returning true let a
  ! rule fire with its guard never evaluated; every sibling defensive read in this class
  ! answers false. A guard we cannot evaluate has not passed.
  if self.rl.rules.guardQ &= NULL then return false.
  loop g = 1 to records(self.rl.rules.guardQ) ! WHERE is an AND-list - every clause must pass
    get(self.rl.rules.guardQ, g)
    if errorcode() then return false.
    if ~self.GuardOneOK() then return false.
  end
  return true

! ------------------------------------------------------------------------------------
! One WHERE clause - the LOADED rules.guardQ buffer row - against the current binds.
! Body unchanged from the earlier single-guard GuardOK apart from field names.
! ------------------------------------------------------------------------------------
VitMatch.GuardOneOK Procedure()
b      long,auto
eq     long,auto
txt    StringTheory
val    StringTheory
tU     STRING(vs:maxName)
rf     BYTE
prv    StringTheory        ! the token before a '(' - a name there makes it a CALL
cf     STRING(1)           !   its last character, which is what decides that
wasLit BYTE                ! the bound metavar text was a quoted LITERAL (case-sensitive) rather than an identifier/EXPR (caseless)
  code
  b = self.FindBind(self.rl.rules.guardQ.mvx)
  if ~b then return false. ! lint guarantees presence; defensive
  get(self.binds, b)

  if self.rl.rules.guardQ.kind = vr:guardClassTest
    case self.rl.rules.guardQ.ct
    of vr:ctLiteral
      if self.binds.sPos <> self.binds.ePos then return false.
      txt.setValue(self.TokText(self.binds.sPos))
      if txt._DataEnd and txt.valuePtr[1] = '''' then return true.
      return false
    of vr:ctConst
      self.SpanText(self.binds.sPos, self.binds.ePos, txt)
      txt.setValue(self.tk.FoldStr(txt.getValue()))
      if self.IsAllDigits(txt.getValue()) then return true.
      return false
    of vr:ctVar
      if self.binds.sPos <> self.binds.ePos then return false.
      if ~self.rl.IsLabelToken(self.TokText(self.binds.sPos)) then return false.
      if self.syms &= NULL then return true.                                    ! no table: any identifier counts as a var
      if self.syms.Lookup(self.TokText(self.binds.sPos), self.binds.sPos, tU, rf) then return true.
      if self.rl.AssumeType(self.TokText(self.binds.sPos)) then return true.
      return false
    of vr:ctSimple                                                              ! no depth-0 logical operator in the binding
      if self.SpanHasBoolOp(self.binds.sPos, self.binds.ePos) then return false.
      return true
    of vr:ctBoolExpr                                                            ! the EXACT complement of isSimple above:
      if self.SpanHasBoolOp(self.binds.sPos, self.binds.ePos) then return true. !   the binding HAS a depth-0 logical operator,
      return false                                                              !   so it is a LOGICAL expression valued 1 or 0
    of vr:ctPure                                                                ! NO call/property access in the binding - pure
      loop b = self.binds.sPos to self.binds.ePos                               !   arithmetic over vars/literals, safe for a
        txt.setValue(self.TokText(b))                                           !   replacement to evaluate twice. '(' refuses calls
        if txt._DataEnd = 1                                                     !   AND paren-groups (conservative under-fire);
          if txt.valuePtr[1] = '(' or txt.valuePtr[1] = '{{' then return false. ! '{' refuses x{{prop}
        end
      end
      return true
    of vr:ctCallFree                                                            ! the binding CALLS nothing, but
      loop b = self.binds.sPos to self.binds.ePos                               !   GROUPING parens are allowed:
        txt.setValue(self.TokText(b))                                           !   `y + (3 * z)` evaluates twice
        if txt._DataEnd <> 1 then cycle.                                        !   as safely as `y`, and isPure
        if txt.valuePtr[1] = '{{' then return false.                            !   refuses it only because of the
        if txt.valuePtr[1] <> '(' or |   !   bracket. '{' is a property.
           b <= self.binds.sPos                                                                         ! opens the binding: grouping
          cycle
        end
        prv.setValue(self.TokText(b - 1))
        if ~prv._DataEnd then cycle.
        ! AN OPERATOR SPELLED AS A WORD ends in a letter, so the name test below would read
        ! `not (a)` or `x and (y)` as a call and refuse a binding that calls nothing. These
        ! four are operators, never procedures, so a '(' after one of them is grouping.
        case upper(prv.getValue())
        of 'AND' orof 'OR' orof 'XOR' orof 'NOT'
          cycle
        end
        cf = prv.valuePtr[prv._DataEnd]                                                                 ! a NAME immediately before '(' is
        case val(cf)                                                                                    !   a call - `f(`, `self.M(`,
        of 65 to 90 orof 97 to 122 orof 48 to 57 orof 95 orof 58 orof 46 ! 'A' to 'Z' orof 'a' to 'z' orof '0' to '9' orof '_' orof <colon> orof <dot>   !   `pre:fld(`. Anything else -
          return false                                                                                  !   an operator, a comma, another
        end                                                                                             !   '(' - is grouping.
      end
      return true
    of vr:ctCaseNeutral                                                                                 ! the binding is unchanged
      loop b = self.binds.sPos to self.binds.ePos                                                       !   by EITHER case fold, which is exactly what
        txt.setValue(self.TokText(b))                                                                   !   upper(x) = lower(x) tests - the two agree only when
        if upper(choose(txt._DataEnd < 1, '', txt.valuePtr[1 : txt._DataEnd])) <> lower(txt.getValue()) !   there is no letter present. Written as the test
          return false                                                                                  !   itself rather than a character scan, so the code
        end                                                                                             !   says what the guard means. The raw bound text is
      end                                                                                               !   scanned, quotes included: '::' and '/' pass, ' of '
      return true                                                                                       !   and 'X' do not.
    end
    return false
  end

  ! compare guard
  if self.rl.rules.guardQ.func = vr:gfLen                                                               ! len(mv) op integer - numeric, own path
    b = -1                                                                                              ! reuse b: logical length; -1 = not a single quoted literal
    if self.binds.sPos = self.binds.ePos
      b = self.LitLength(self.TokText(self.binds.sPos))
    end
    if self.rl.rules.guardQ.val &= NULL then return false.                                              ! parser guarantees digits; defensive
    val.setValue(self.rl.rules.guardQ.val)
    eq = choose(b = val.getValue())                                                                     ! LONG vs digit string: numeric compare
    if self.rl.rules.guardQ.op = vr:opEq then return eq.
    return 1 - eq
  end
  self.SpanText(self.binds.sPos, self.binds.ePos, txt)
  txt.setValue(self.tk.FoldStr(txt.getValue()))                                                         ! gfFold and bare metavar both fold (spec 2.2).
                                                                                                        !   gfTrimr retired: the compare below is
                                                                                                        !   trailing-space-blind already, so a trimr arm
                                                                                                        !   could never change the answer.
  if txt._DataEnd > 1
    if txt.valuePtr[1] = '''' and txt.valuePtr[txt._DataEnd] = ''''
      txt.unquote('''')
      wasLit = 1                                                                                        ! it was a quoted literal -> compare its content case-sensitively
    end
  end
  if not self.rl.rules.guardQ.val &= NULL
    val.setValue(self.rl.rules.guardQ.val)
  end
  ! Clarion identifiers are caseless, so an identifier/EXPR guard (e.g. WHERE V <> 'SELF')
  ! must compare caselessly - matching the engine's own gdNoSelf guard. Only a bound LITERAL, whose
  ! content is case-significant, compares exactly.
  if wasLit
    eq = choose(choose(txt._DataEnd < 1, '', txt.valuePtr[1 : txt._DataEnd]) = val.getValue())
  else
    eq = choose(upper(choose(txt._DataEnd < 1, '', txt.valuePtr[1 : txt._DataEnd])) = upper(val.getValue()))
  end
  if self.rl.rules.guardQ.op = vr:opEq then return eq.
  return 1 - eq

! ------------------------------------------------------------------------------------
! does the token span [pS,pE] contain a DEPTH-0 logical operator? The logical
! infix operators AND / OR / XOR (and prefix NOT / ~) are the only operators of LOWER
! precedence than a relational comparator, so if one sits at depth 0 in a comparator
! operand then the comparator is NOT the condition's root and a comparator-flip would
! mis-scope the negation (isSimple = ~SpanHasBoolOp). Operators nested inside parens
! (depth>0) do not count - `f(x or y) = c` keeps '=' as root. NB BAND/BOR/BXOR/BSHIFT
! are FUNCTIONS (their name is a depth-0 token but they are operands, never infix), so
! they are deliberately NOT in this set - excluding them would wrongly refuse the flip
! on the common `BAND(x,mask) = 0` idiom.
! ------------------------------------------------------------------------------------
VitMatch.SpanHasBoolOp Procedure(LONG pS, LONG pE)
i      long,auto
depth  long
t      StringTheory
u      STRING(12),AUTO
  code
  loop i = pS to pE
    if self.TokIsEOL(i) then cycle.
    t.setValue(self.TokText(i))
    if ~t._DataEnd then cycle.
    if t._DataEnd = 1 and (t.valuePtr[1] = '(' or t.valuePtr[1] = '[')
      depth += 1
      cycle
    end
    if t._DataEnd = 1 and (t.valuePtr[1] = ')' or t.valuePtr[1] = ']')
      depth -= 1
      cycle
    end
    if depth then cycle. ! nested (inside a call/index) - not a condition-level operator
    if t._DataEnd = 1 and t.valuePtr[1] = '~' then return 1.
    u = upper(t.getValue())
    case u
    of 'AND' orof 'OR' orof 'XOR' orof 'NOT'
      return 1
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! Logical character count of a quoted literal token, honouring Clarion string
! escapes: doubled '' << {{ count 1; <13> counts 1 and <13,10> counts 2 (one
! per comma-separated value); x{5} is x repeated 5 times total. Returns -1 for
! anything that is not a well-formed quoted literal (a len() guard then fails
! '=' and passes '<>'). Works on the RAW token text - no unquoting.
! ------------------------------------------------------------------------------------
VitMatch.LitLength Procedure(STRING pTok)
t     StringTheory
grp   StringTheory
n     long
i     long,auto
j     long,auto
rep   long,auto
  code
  t.setValue(pTok)
  if t._DataEnd < 2 or |
     t.valuePtr[1] <> '''' or t.valuePtr[t._DataEnd] <> ''''
    return -1
  end
  i = 2
  loop while i <= t._DataEnd - 1
    if i < t._DataEnd - 1
      if t.valuePtr[i : i+1] = '''''' or t.valuePtr[i : i+1] = '<<<<' or t.valuePtr[i : i+1] = '{{{{'
        n += 1
        i += 2
        cycle
      end
    end
    if t.valuePtr[i] = '<<'                              ! char-code group: <13> or <13,10,...>
      j = i + 1
      loop while j <= t._DataEnd - 1 and t.valuePtr[j] <> '>'
        j += 1
      end
      if j > t._DataEnd - 1 or j = i + 1 then return -1. ! unterminated or empty <>
      grp.setValue(t.valuePtr[i+1 : j-1])
      if ~grp.isAll('0123456789, ') then return -1.
      n += grp.Count(',') + 1                            ! one char per comma-separated value
      i = j + 1
      cycle
    end
    if t.valuePtr[i] = '{{'                              ! repeat group: {5} = previous char x5 total
      j = i + 1
      loop while j <= t._DataEnd - 1 and t.valuePtr[j] <> '}'
        j += 1
      end
      if j > t._DataEnd - 1 or j = i + 1 then return -1.
      grp.setValue(t.valuePtr[i+1 : j-1])
      if ~grp.IsAllDigits() or ~n then return -1.        ! non-numeric count, or nothing to repeat
      rep = grp.getValue()
      if rep > 0 then n += rep - 1.
      i = j + 1
      cycle
    end
    n += 1
    i += 1
  end
  return n

! ------------------------------------------------------------------------------------
! The LRM's combined-operator table (p528) gives more than one spelling for the same
! operator, and a rule written with one of them must match code written with another - that
! was 's actual complaint: "rules matching <= silently miss code written =<". Returns the
! canonical spelling for anything with a synonym, or '' for everything else.
!   <= = < ~ >   less than or equal / not greater than
!   >= = > ~ <   greater than or equal / not less than
!   <> ~ =       not equal
! chr() rather than a literal because '<' and '{' double inside a Clarion string.
! KNOWN LIMIT: the LRM's two-word forms (NOT = / NOT < / NOT >) are two TOKENS and are not
! equated here - that needs multi-token equivalence in the matcher, not a spelling table.
! ------------------------------------------------------------------------------------
VitMatch.OpCanon Procedure(STRING pTok)
  code
  ! No local, no clip, no upper: CASE on a string already ignores trailing spaces, and an
  ! operator holds no letters so there is no case to fold. The spellings are written as
  ! CONSTANTS with '<' doubled, rather than built with chr() concatenation on every call.
  case pTok
  of '<<=' orof '=<<' orof '~>'  ! '<=' '=<' '~>'
    return '<<='
  of '>='  orof '=>'  orof '~<<' ! '>=' '=>' '~<'
    return '>='
  of '<<>' orof '~='             ! '<>' '~='
    return '<<>'
  end
  return ''

! ------------------------------------------------------------------------------------
! The class of the operator formed by an infix NOT and the token AFTER it. This is NOT the
! same mapping as OpCanon: the second token is a BARE comparator, and the NOT inverts it -
!   NOT =  is  <>        NOT <  is  >=  (not less)        NOT >  is  <=  (not greater)
! - which is why `NOT <` cannot simply canonicalise as `<`. '' if the token cannot follow a
! NOT to make an operator. (LRM p528: "A ~< B, A >= B, A NOT < B - True when A is not less".)
! ------------------------------------------------------------------------------------
! Does the two-word operator opening at pIx (an infix NOT plus its comparator) spell the same
! operator as pAnchor? RefreshFreq posts such a position under the canonical key, so the
! postings walk offers it as a candidate - and LitMatches, which compares ONE token to one
! token, cannot see why it qualifies. This is the arbiter for that case and nothing else.
! ------------------------------------------------------------------------------------
VitMatch.AnchorNotPair Procedure(LONG pIx, *STRING pAnchorOp)
cmpT  string(4),auto                      ! a variable for the *STRING callee
  code
  if ~self.NotInfixAt(pIx) then return 0.
  cmpT = self.TokText(pIx + 1)
  if pAnchorOp = self.OpCanonNot(cmpT) then return 1.
  return 0

! ------------------------------------------------------------------------------------
VitMatch.OpCanonNot Procedure(*STRING pTok)
c  string(1),auto
b  byte,over(c)                           ! L: compare the BYTE, not the string
  code
  ! THE clip() IS LOAD-BEARING - do not drop it. Callers hand this a fixed-width local (the
  ! *STRING has to bind to a variable, and a token's text is assigned into one), so '=' arrives
  ! PADDED. Without the clip, len() reports the variable's declared width and every comparator
  ! is rejected as "not one character". With it, the test is on the content and the caller's
  ! width does not matter - which is what keeps this independent of how each caller declares.
  if len(clip(pTok)) <> 1 then return ''. ! only a one-character comparator can follow NOT
  c = pTok
  case b
  of 61 ; return '<<>'                    ! NOT =  ->  <>
  of 60 ; return '>='                     ! NOT <  ->  >=   (not less)
  of 62 ; return '<<='                    ! NOT >  ->  <=   (not greater)
  end
  return ''

! ------------------------------------------------------------------------------------
! Is the token at pS the INFIX `NOT` of an LRM combined operator - `A NOT = B` - rather than
! the boolean prefix NOT of `IF NOT x = 1`? The LRM's own examples are infix ("A <> B, A ~= B,
! A NOT = B - True when A is not equal to B", p528), and the two readings are genuinely
! different code: a prefix NOT negates the comparison that follows it, so equating that one
! would bind the pattern's LEFT operand to whatever happened to sit before the NOT.
! Infix means the previous token ENDS an operand - an identifier, a number, a literal, or a
! closing bracket. A reserved word (IF, AND, OR, RETURN), an operator or a line start does not.
! ------------------------------------------------------------------------------------
VitMatch.NotInfixAt Procedure(LONG pS)
t    StringTheory
  code
  if upper(self.TokText(pS)) <> 'NOT' then return 0.
  if pS < 2 then return 0.
  if self.TokIsEOL(pS - 1) then return 0.
  t.setValue(self.TokText(pS - 1))
  if ~t._DataEnd then return 0.
  if t.valuePtr[t._DataEnd] = ')' or t.valuePtr[t._DataEnd] = ']' then return 1.
  case self.TokType(pS - 1)
  of vt:label orof vt:Integer orof vt:NumericWithDecPt orof vt:literal
    return 1
  end
  return 0

! ------------------------------------------------------------------------------------
! pLit is *STRING - BY REFERENCE (L). It is never written here, and this is the hottest test
! in the matcher: every candidate, every pattern token, every attempt. A plain STRING
! parameter copies the text on every one of those calls.
! ------------------------------------------------------------------------------------
VitMatch.LitMatches Procedure(LONG pIx, *STRING pLit)
opC  string(4),auto
  code
  if self.TokIsEOL(pIx) then return false.
  if ~pLit then return false.
  if pLit = '.' and ~self.IsMemberDot(pIx) then return false. ! a pattern member-dot must not match a vt:end TERMINATOR dot (st. free(q) after THEN would lose the IF terminator)
  if pLit[1] = ''''                                           ! quoted literal: exact, case-sensitive
    if self.TokText(pIx) = pLit then return true.
    return false
  end
  if upper(self.TokText(pIx)) = upper(pLit) then return true.
  ! same operator, different documented spelling. FIRST BYTE GATE: a failed compare is
  ! the ordinary case here - this is the hottest test in the matcher, run for every candidate
  ! and every literal token of every attempt - and every spelling with a synonym begins with
  ! one of four characters. One indexed byte keeps the rest of the corpus out of OpCanon.
  case val(pLit[1])
  of 60 orof 62 orof 126 orof 61                              ! '<' '>' '~' '='
    opC = self.OpCanon(pLit)
    if opC and opC = self.OpCanon(self.TokText(pIx)) then return true.
  end
  return false

! ------------------------------------------------------------------------------------
! Cheap shape gate: rejects a candidate start position without the cost of a
! full TryFrom (and without the verbose type-miss noise). Pattern part 1
! literal -> the token must equal it; identifier metavar -> the token must be
! a label, followed by '.' when the pattern says receiver.method.
! ------------------------------------------------------------------------------------
VitMatch.CandOK Procedure(LONG pS)
  code
  if self.gd1Lit
    get(self.patQ, 1)
    if errorcode() or self.patQ.tok &= NULL then return true.
    return self.LitMatches(pS, self.patQ.tok)                                                                      ! the member itself - no clip() copy; = ignores trailing spaces anyway
  end
  if self.gd1IdMv
    if ~self.rl.IsLabelToken(self.TokText(pS)) and ~instring('.', clip(self.TokText(pS)), 1, 1) then return false. ! B0b: a recombined 'self.Direct' receiver token has a '.' and isn't a bare label
    if self.gd2Dot and self.TokText(pS + 1) <> '.' then return false.
  end
  return true

! ------------------------------------------------------------------------------------
! Full pattern match attempt at pS, guards applied. Returns last matched token
! position (also for a logged interior-comment skip, so the scan moves on), or 0.
! ------------------------------------------------------------------------------------
VitMatch.TryFrom Procedure(LONG pS, StringTheory pReport)
r  long,auto
e  long,auto
  code
  free(self.binds)
  if self.gdNoDot and pS > 1
    if self.TokText(pS-1) = '.' and self.IsMemberDot(pS-1) then return 0.    ! a vt:end terminator dot before pS is not a receiver context
  end
  if self.gdStmt
    if self.StmtStart(pS) <> pS then return 0.
  end
  r = self.MatchHere(1, pS)
  if ~r then return 0.
  e = r - 1
  if self.gdStmt and ~self.IsStmtEndAfter(e) then return 0.
  if self.rl.rules.inParens and ~self.StartsInsideBracket(pS) then return 0. ! INPARENS: the match must sit inside an unclosed
                                                                             !   bracket of its own statement, which is what proves
                                                                             !   an '=' here is a comparison and not an assignment
  if self.rl.rules.exprEnd and self.ExprContinuesAfter(e) then return 0.     ! EXPREND: the operand must END here - a continuing
                                                                             !   binary operator means padding/structure the rewrite
                                                                             !   would corrupt; refuse, no match
  if self.gdNoSelf
    if upper(self.TokText(pS)) = 'SELF' then return 0.                       ! bare SELF receiver excluded; a recombined 'self.Direct' token is not 'SELF' so passes
  end
  if self.rl.rules.guardKind
    if ~self.GuardOK() then return 0.                                        ! WHERE guard rejects: no match at all
  end
  if self.HasInteriorComment(pS, e)
    self.skipCount += 1
    self.RecordMatch(pS, e, true, pReport)
    return e
  end
  self.matchCount += 1
  self.RecordMatch(pS, e, false, pReport)
  return e

! ------------------------------------------------------------------------------------
! The core recursive matcher: pattern part pP against source position pS.
! EXPR is greedy with backtracking over balanced depth-0 extents, which yields
! the spec's last-depth-0-operator split for free. Repeated metavars compare
! caseless against their first binding.
! ------------------------------------------------------------------------------------
VitMatch.MatchHere Procedure(LONG pP, LONG pS)
pt       StringTheory                                                                    ! pattern token text
opC      string(4),auto                                                                  ! canonical spelling of a comparison operator with synonyms ('' = has none)
nOp      string(4),auto                                                                  ! the same for a two-word NOT pair on the PATTERN side
cmpT     string(4),auto                                                                  ! a variable for the *STRING callees
t        StringTheory                                                                    ! source token text
pmvx     long,auto
kind     byte,auto
b        long,auto
L        long,auto
e        long,auto
r        long,auto
depth    long,auto
d        long,auto
c        long,auto
dotPos   long,auto                                                                       ! B0b: '.' pos in a recombined member-access receiver token
recvU    STRING(vs:maxName)                                                              ! resolved class of a method-call receiver
cands    QUEUE                                                                           ! EXPR candidate end positions
epos       LONG
         END
  code
  if pP > self.patCount then return pS.                                                  ! whole pattern matched; pS = pos after span
  get(self.patQ, pP)
  if errorcode() then return 0.
  if self.patQ.tok &= NULL then return 0.
  pt.setValue(self.patQ.tok,st:clip)
  pmvx = self.patQ.mvx

  if ~pmvx                                                                               ! literal pattern token
    if pt._DataEnd = 1 and pt.valuePtr[1] = ';'                                          ! spec v0.3: statement boundary
      if pP = self.patCount                                                              ! trailing ; = zero-width end-of-statement assertion
        if self.IsStmtEndAfter(pS - 1) then return pS.                                   ! nothing consumed: span excludes it
        return 0
      end
      e = pS                                                                             ! interior ; = consume a run of ';'/EOL tokens
      loop while e <= self.tk.records()
        t.setValue(self.TokText(e))
        if ~(t._DataEnd >= 1 and t.valuePtr[1 : t._DataEnd] = ';') and ~(t._DataEnd >= 1 and t.valuePtr[1 : t._DataEnd] = '<10>') then break.
        e += 1
      end
      if e = pS then return 0.                                                           ! at least one boundary token required
      return self.MatchHere(pP+1, e)
    end
    if ~self.LitMatches(pS, self.patQ.tok)
      ! The LRM's combined-operator table also gives TWO-WORD spellings - `A NOT = B` for
      ! `<>`, `A NOT < B` for `>=`, `A NOT > B` for `<=` - and they are the same operators, so
      ! a rule written either way matches source written either way. Equated in BOTH
      ! directions, which is the only way it stays a synonym rather than a special case.
      ! LitMatches cannot do it because it compares ONE token to one token; here we can
      ! consume two of either side. The infix test is what keeps `IF NOT x = 1` out of it.
      ! LENGTH FIRST. A failed literal compare is the ordinary case in matching - it happens
      ! for most tokens of most attempts - so this must not cost string work. Every spelling
      ! with a synonym is exactly 2 characters and the pattern-side word is exactly 3, so one
      ! integer test takes the whole hot path out of the probe below.
      opC = ''
      if pt._DataEnd = 2 then opC = self.OpCanon(pt.valuePtr[1 : 2]).                    ! two bytes, sliced not copied
      if opC                                                                             ! pattern `<>` vs source `NOT =`
        cmpT = self.TokText(pS + 1)
        if self.NotInfixAt(pS) and opC = self.OpCanonNot(cmpT)
          return self.MatchHere(pP+1, pS+2)
        end
      elsif pt._DataEnd = 3 and upper(pt.valuePtr[1 : 3]) = 'NOT' and pP < self.patCount ! pattern `NOT =` vs source `<>`
                                                                                    !   (L: slice the three bytes rather
                                                                                    !   than getValue() a copy of them)
        get(self.patQ, pP + 1)                                                           ! pt already holds row pP's text, so the buffer is free
        if ~errorcode() and ~self.patQ.mvx and not self.patQ.tok &= NULL
          nOp = self.OpCanonNot(self.patQ.tok)                                           ! once, and without a clip() copy
          if nOp and nOp = self.OpCanon(self.TokText(pS))
            return self.MatchHere(pP+2, pS+1)
          end
        end
      end
      return 0
    end
    return self.MatchHere(pP+1, pS+1)
  end

  get(self.rl.metaVars, pmvx)
  if errorcode() then return 0.
  kind = self.rl.metaVars.kind

  if not self.patQ.mvTail &= NULL                        ! dotted metavar occurrence (st._DataEnd) - a
    if self.TokIsEOL(pS) then return 0.                  ! constrained literal: source must be ONE merged token
    pt.setValue(self.patQ.mvTail,st:clip)                ! equal to <head binding>.<tail> (caseless); never binds.
    b = self.FindBind(pmvx)                              ! Lint guarantees a plain occurrence bound the head
    if ~b then return 0.                                 ! earlier in the pattern.
    get(self.binds, b)
    if self.binds.sPos <> self.binds.ePos then return 0. ! single-token bindings only (receivers)
    pt.prepend(clip(self.TokText(self.binds.sPos)) & '.')
    t.setValue(self.TokText(pS),st:clip)
    if t._DataEnd <> pt._DataEnd or |
       upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) <> upper(pt.getValue())
      return 0
    end
    return self.MatchHere(pP+1, pS+1)
  end

  case kind
  of vr:mvTyped orof vr:mvClass orof vr:mvAnyVar orof vr:mvTypeSet ! one identifier token, type-checked against the symbol table
    if self.TokIsEOL(pS) then return 0.
    ! return-type table: a method-RESULT span <recv>.<method>(args) binds a
    ! STRING-classed metavar when the receiver's class RESOLVES and the class's headers
    ! declare the method ,String (any registry-known class, inheritance walked;
    ! six-name fallback for registry-unknown classes). Makes string method results bind
    ! like string variables everywhere (kills the per-shape rule class at the
    ! root). Tried FIRST; any refusal falls through to the existing single-token paths.
    ! mvAnyVar excluded (variables only). Gate order: metavar class first (cheap),
    ! receiver resolution second, method lookup last.
    if kind <> vr:mvAnyVar and ~self.TokIsEOL(pS+1) and ~self.TokIsEOL(pS+2) and ~self.TokIsEOL(pS+3)
      ! IsMemberDot, NOT a raw '.' test - the reason is written out at :658 and this
      ! is the one sibling that did not ask. A one-liner's TERMINATOR dot is also a '.'
      ! token, so `if c then q9 = s1. left (s1)` bound a method-result span ACROSS the end
      ! of the statement and emitted `q9 = use(s1. left (s1))` - the IF's terminating
      ! period deleted and the following lines swallowed into the THEN clause. It compiles.
      if self.TokText(pS+1) = '.' and self.IsMemberDot(pS + 1) |
         and self.TokText(pS+3) = '(' and self.rl.IsLabelToken(self.TokText(pS+2))

        recvU = ''
        if self.ClassSatisfies(pmvx, 'STRING') then recvU = self.RecvClass(pS).
        if recvU and self.MethodReturnsString(recvU, self.TokText(pS+2), self.CallArgCount(pS+3), self.CallArgTypes(pS+3)) ! pS+3 is the open paren
          depth = 1                                                                                                        ! balanced arg scan from the '('
          e = pS + 4
          loop
            if self.TokIsEOL(e) then depth = -1; break.                                                                    ! no close before EOS - not a call span
            d = self.DepthDelta(self.TokText(e))
            if depth + d = 0 then break.                                                                                   ! e = the matching ')'
            depth += d
            e += 1
          end
          if depth >= 0
            b = self.FindBind(pmvx)
            if b
              get(self.binds, b)
              if self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, e)
                r = self.MatchHere(pP+1, e+1)
                if r then return r.
              end
            else
              self.BindSpan(pmvx, pS, e)
              r = self.MatchHere(pP+1, e+1)
              if r then return r.
              self.Unbind()
            end
          end
        end
      end
    end
    dotPos = 0
    ! ANYVAR deliberately does NOT take the dot-form: it means a plain identifier, and a
    ! recombined `self.Direct` receiver is a member ACCESS. A typed metavar takes it because
    ! there is a chain to type; ANYVAR would just be binding a different kind of thing under
    ! the same name. That is the rationale found missing - the implicit-variable half of
    ! the same asymmetry had none either, and turned out to be a plain miss (fixed below).
    if kind <> vr:mvAnyVar then dotPos = instring('.', clip(self.TokText(pS)), 1, 1). ! dot-form: mvTyped/mvTypeSet chains too - a dotted token always REFUSED the single-id path before, so this only ADDS matches
    if dotPos > 1                                                                         ! B0b: the tokenizer recombines a member-access receiver into ONE token (self.Direct)
      if ~self.ChainTypeOK(pmvx, pS) then return 0.                                       ! type it by splitting on '.' and walking the registry
    elsif self.ImplicitType(self.TokText(pS))                                             ! IMPLICIT variables (clarion.help implicit_variables) -
      ! ANYVAR binds an implicit variable too. `total#` IS an identifier - the whole
      ! meaning of ANYVAR - and it was refused only because this arm was gated against ANYVAR
      ! and the fall-through demands IsLabelToken, which a '#'/'"'/'$' suffix fails. A typed
      ! metavar reaches ClassSatisfies below; ANYVAR has no type to satisfy, so it just binds.
      if kind <> vr:mvAnyVar
        if ~self.ClassSatisfies(pmvx, self.ImplicitType(self.TokText(pS))) then return 0. !   s" = STRING(32), n# = LONG, r$ = REAL; typed by SUFFIX, never
      end                                                                                 !   declared, so the symbol table can never know them
    else
      if ~self.rl.IsLabelToken(self.TokText(pS)) then return 0.
      if ~self.TypeOK(pmvx, pS) then return 0.
    end
    b = self.FindBind(pmvx) ! bind as ONE token (recombined or plain); repeated-metavar equality is SpanEqual - caseless for identifiers, exact for quoted literals
    if b
      get(self.binds, b)
      if ~self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, pS) then return 0.
      return self.MatchHere(pP+1, pS+1)
    end
    self.BindSpan(pmvx, pS, pS)
    r = self.MatchHere(pP+1, pS+1)
    if ~r then self.Unbind().
    return r

  of vr:mvLiteral                                                                         ! one quoted string literal token
    if self.TokIsEOL(pS) then return 0.
    t.setValue(self.TokText(pS))
    if ~t._DataEnd or |
       t.valuePtr[1] <> ''''
      return 0
    end
    b = self.FindBind(pmvx)
    if b
      get(self.binds, b)
      if ~self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, pS) then return 0.
      return self.MatchHere(pP+1, pS+1)
    end
    self.BindSpan(pmvx, pS, pS)
    r = self.MatchHere(pP+1, pS+1)
    if ~r then self.Unbind().
    return r

  of vr:mvConst ! integer literal only in Phase 2 (fold() is Phase 3)
    if ~self.IsAllDigits(self.TokText(pS)) then return 0.
    b = self.FindBind(pmvx)
    if b
      get(self.binds, b)
      if ~self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, pS) then return 0.
      return self.MatchHere(pP+1, pS+1)
    end
    self.BindSpan(pmvx, pS, pS)
    r = self.MatchHere(pP+1, pS+1)
    if ~r then self.Unbind().
    return r

  of vr:mvArgs                                                                         ! whole (...) content; lint guarantees '(' before, ')' after
    depth = 1
    e = pS
    loop
      if self.TokIsEOL(e) then return 0.                                               ! no close before end of statement/file
      d = self.DepthDelta(self.TokText(e))
      if depth + d = 0 then break.                                                     ! e is the matching ')'
      depth += d
      e += 1
    end
    b = self.FindBind(pmvx)
    if b
      get(self.binds, b)
      if ~self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, e-1) then return 0.
      return self.MatchHere(pP+1, e)
    end
    self.BindSpan(pmvx, pS, e-1)                                                       ! possibly empty span (ePos < sPos)
    r = self.MatchHere(pP+1, e)                                                        ! pattern part pP+1 is the ')'
    if ~r then self.Unbind().
    return r

  of vr:mvExpr
    b = self.FindBind(pmvx)
    if b                                                                               ! repeated EXPR: must equal first binding
      get(self.binds, b)
      L = self.binds.ePos - self.binds.sPos + 1
      if L < 1 then return 0.
      if ~self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, pS+L-1) then return 0.
      return self.MatchHere(pP+1, pS+L)
    end
    ! collect balanced candidate extents: every prefix whose depth returns to 0,
    ! stopping at depth-0 , ; ) ] THEN ELSE or end of statement
    depth = 0
    e = pS
    loop
      if self.TokIsEOL(e) then break.
      t.setValue(self.TokText(e))
      if ~t._DataEnd then break.
      if ~depth
        if t._DataEnd = 1 and t.valuePtr[1] = ',' or t._DataEnd = 1 and t.valuePtr[1] = ';' or t._DataEnd = 1 and t.valuePtr[1] = ')' or t._DataEnd = 1 and t.valuePtr[1] = ']' then break.
        if upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) = 'THEN' or upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) = 'ELSE' then break.
        if t._DataEnd = 1 and t.valuePtr[1] = '.' and ~self.IsMemberDot(e) then break. ! a vt:end terminator dot ends the statement - the extent must not swallow it (StmtStart treats it as a boundary too)
      end
      d = self.DepthDelta(t.getValue())
      if depth + d < 0 then break.
      depth += d
      if ~depth
        cands.epos = e
        add(cands)
      end
      e += 1
    end
    loop c = records(cands) to 1 by -1                                                 ! greedy: longest extent first
      get(cands, c)
      self.BindSpan(pmvx, pS, cands.epos)
      r = self.MatchHere(pP+1, cands.epos + 1)
      if r
        free(cands)
        return r
      end
      self.Unbind()
    end
    free(cands)
    return 0
  end
  return 0

! ------------------------------------------------------------------------------------
VitMatch.BindSpan Procedure(LONG pMvx, LONG pS, LONG pE)
  code
  clear(self.binds)
  self.binds.mvx  = pMvx
  self.binds.sPos = pS
  self.binds.ePos = pE
  add(self.binds)

! ------------------------------------------------------------------------------------
VitMatch.Unbind Procedure()
  code
  if ~records(self.binds) then return.
  get(self.binds, records(self.binds))
  delete(self.binds)

! ------------------------------------------------------------------------------------
VitMatch.FindBind Procedure(LONG pMvx)
b  long,auto
  code
  loop b = 1 to records(self.binds)
    get(self.binds, b)
    if self.binds.mvx = pMvx then return b.
  end
  return 0

! ------------------------------------------------------------------------------------
VitMatch.SpanEqual Procedure(LONG pAS, LONG pAE, LONG pBS, LONG pBE)
i  long,auto
o  long,auto
ta StringTheory
tb StringTheory
  code
  if pAE - pAS <> pBE - pBS then return false.
  if pAE < pAS then return true. ! both spans empty
  o = pBS - pAS
  loop i = pAS to pAE
    if self.TokIsEOL(i) or self.TokIsEOL(i+o) then return false.
    ta.setValue(self.TokText(i))
    tb.setValue(self.TokText(i+o))
    ! LitMatches' notion of identity, NOT a blanket fold. A quoted literal is CONTENT
    ! and compares case-sensitively - which is what LitMatches (:1062) and FreqKey do, so a
    ! blanket upper() here made repeated-metavar equality the one place in the matcher where
    ! 'Yes' and 'YES' were the same string: foomatched foo('Yes','YES') and the rewrite
    ! then emitted ONE of them for both. Everything else in a span is a Clarion identifier or
    ! keyword, where the language itself is caseless, so those stay folded.
    if (ta._DataEnd and ta.valuePtr[1] = '''') or (tb._DataEnd and tb.valuePtr[1] = '''')
      if choose(ta._DataEnd < 1, '', ta.valuePtr[1 : ta._DataEnd]) <> tb.getValue() then return false.
    else
      if upper(choose(ta._DataEnd < 1, '', ta.valuePtr[1 : ta._DataEnd])) <> upper(tb.getValue()) then return false.
    end
  end
  return true

! ------------------------------------------------------------------------------------
VitMatch.SpanText Procedure(LONG pS, LONG pE, StringTheory pOut)
i  long,auto
  code
  pOut.free()
  loop i = pS to pE
    if self.TokIsEOL(i) then cycle.
    if pOut._DataEnd then pOut.append(' ').
    pOut.append(self.TokText(i))
  end

! ------------------------------------------------------------------------------------
! Any non-layout trivia (i.e. a comment, or OMIT/COMPILE text) attached before
! an interior token of the span. Leading trivia of the FIRST token is allowed -
! it is preserved by the rewriter, never lost.
! ------------------------------------------------------------------------------------
VitMatch.HasInteriorComment Procedure(LONG pS, LONG pE)
i    long,auto
x    long,auto
bt   StringTheory
c    string(1),auto
  code
  loop i = pS+1 to pE
    self.TokBefore(i, bt)
    loop x = 1 to bt._DataEnd
      c = bt.valuePtr[x]
      if c = ' ' or c = '<9>' or c = '<13>' or c = '<10>' or c = '|' then cycle.
      return true
    end
  end
  return false

! ------------------------------------------------------------------------------------
VitMatch.RecordMatch Procedure(LONG pS, LONG pE, BYTE pSkipped, StringTheory pReport)
span   StringTheory
bs     StringTheory
b      long,auto
ln     long,auto
mIx    long,auto
  code
  if self.capture
    clear(self.matches)
    self.matches.sPos    = pS
    self.matches.ePos    = pE
    self.matches.skipped = pSkipped
    add(self.matches)
    mIx = records(self.matches)
    loop b = 1 to records(self.binds)
      get(self.binds, b)
      clear(self.bindRecs)
      self.bindRecs.matchIx = mIx
      self.bindRecs.mvx     = self.binds.mvx
      self.bindRecs.sPos    = self.binds.sPos
      self.bindRecs.ePos    = self.binds.ePos
      add(self.bindRecs)
    end
  end
  if self.capture then return. ! ApplyRule discards the report - skip SpanText for the match and every binding
  ln = self.LineOf(pS)
  self.SpanText(pS, pE, span)
  if pSkipped
    pReport.append('rule ' & self.ruleId & ' line ' & ln & ' SKIP interior-comment: ' & span.getValue() & '<13,10>')
    return
  end
  pReport.append('rule ' & self.ruleId & ' line ' & ln & ': ' & span.getValue() & '<13,10>')
  loop b = 1 to records(self.binds)
    get(self.binds, b)
    get(self.rl.metaVars, self.binds.mvx)
    if errorcode() then cycle.
    self.SpanText(self.binds.sPos, self.binds.ePos, bs)
    pReport.append('  ' & clip(self.rl.metaVars.name) & ' = ' & bs.getValue() & '<13,10>')
  end

! ------------------------------------------------------------------------------------
VitMatch.TokText Procedure(LONG pIx)
  code
  if pIx < 1 or pIx > self.tk.records() then return ''.
  get(self.tk.tokens, pIx)
  if errorcode() then return ''.
  if self.tk.tokens.tok &= NULL then return ''.
  return clip(self.tk.tokens.tok)

! ------------------------------------------------------------------------------------
VitMatch.TokIsEOL Procedure(LONG pIx)
  code
  if pIx < 1 or pIx > self.tk.records() then return true.
  get(self.tk.tokens, pIx)
  if errorcode() then return true. ! a missing token IS a boundary - stopping a scan
                                   !   here is the REFUSING answer, unlike the two typed gates
                                   !   above, where true meant "accept anything".
  if self.tk.tokens.tok &= NULL or |
     self.tk.tokens.tok = '<10>'
    return true
  end
  return false

! ------------------------------------------------------------------------------------
VitMatch.TokBefore Procedure(LONG pIx, StringTheory pOut)
  code
  pOut.free()
  if pIx < 1 or pIx > self.tk.records() then return.
  get(self.tk.tokens, pIx)
  if errorcode() then return.
  if self.tk.tokens.strBefore &= NULL then return.
  pOut.setValue(self.tk.tokens.strBefore)

! ------------------------------------------------------------------------------------
VitMatch.LineOf Procedure(LONG pIx)
  code
  ! ParseText runs SetLineNumbers(), so the queue's lineNo is authoritative
  ! (correct across '|' continuations, where counting EOL tokens is not)
  if pIx < 1 or pIx > self.tk.records() then return 0.
  get(self.tk.tokens, pIx)
  if errorcode() then return 0.
  return self.tk.tokens.lineNo

! ------------------------------------------------------------------------------------
VitMatch.StmtStart Procedure(LONG pIx)
j   long,auto
t   StringTheory
  code
  loop j = pIx - 1 to 1 by -1
    if self.TokIsEOL(j) then return j + 1.
    t.setValue(self.TokText(j))
    if t._DataEnd = 1 and t.valuePtr[1] = ';' then return j + 1.
    if upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) = 'THEN' or upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) = 'ELSE' then return j + 1.
    if t._DataEnd = 1 and t.valuePtr[1] = '.' and ~self.IsMemberDot(j) then return j + 1.
  end
  return 1

! ------------------------------------------------------------------------------------
VitMatch.IsStmtEndAfter Procedure(LONG pIx)
nxt  StringTheory
  code
  if self.TokIsEOL(pIx + 1) then return true.                                                        ! also true past end of file
  nxt.setValue(self.TokText(pIx + 1))
  if nxt._DataEnd = 1 and nxt.valuePtr[1] = ';' then return true.
  if nxt._DataEnd = 1 and nxt.valuePtr[1] = '.' and self.TokType(pIx + 1) = vt:end then return true. ! inline END terminator
  if upper(choose(nxt._DataEnd < 1, '', nxt.valuePtr[1 : nxt._DataEnd])) = 'ELSE' or upper(choose(nxt._DataEnd < 1, '', nxt.valuePtr[1 : nxt._DataEnd])) = 'END' then return true.
  if upper(choose(nxt._DataEnd < 1, '', nxt.valuePtr[1 : nxt._DataEnd])) = 'THEN' then return true.  ! spec v0.3: a condition ends at THEN (symmetric
                                                       ! with StmtStart; vitTokenize mode-3 logical-EOL precedent)
  return false

! ------------------------------------------------------------------------------------
! EXPREND support: does the token AFTER pIx continue the expression the match
! ended inside? A single-char binary operator (& + - * / ^ %) glues more operand onto
! the matched span - the one case the EXPREND rules must refuse (a clip dropped there
! leaves padding INTERNAL; a collapsed blank/zero test changes the operand's shape).
! Anything else - EOL, ';', terminator '.', THEN/ELSE/END, and/or/xor, ')' - ends the
! operand, so the match stands. Blacklist deliberately: unknown next token = fire, the
! same permissiveness every un-optioned rule has today. A '|' continuation is trivia
! in the NEXT token's strBefore, so a continued '& lit' still presents as '&' here.
! ------------------------------------------------------------------------------------
VitMatch.ExprContinuesAfter Procedure(LONG pIx)
nxt  StringTheory
  code
  if self.TokIsEOL(pIx + 1) then return false.          ! line ends (also past EOF) - operand over
  nxt.setValue(self.TokText(pIx + 1))
  if nxt._DataEnd <> 1 then return false.               ! all continuing operators are single-char
  case val(nxt.valuePtr[1])
  of 38 orof 42 orof 43 orof 45 orof 47 orof 94 orof 37 ! & * + - / ^ %
    return true
  end
  return false

! ------------------------------------------------------------------------------------
! INPARENS support: does the match START inside a bracket its own statement opened and
! has not closed?
!
! WHAT IT PROVES, and it is worth stating because one rule leans its whole safety on it:
! AN '=' AT DEPTH > 0 IS A COMPARISON, NEVER AN ASSIGNMENT. An assignment target is a
! name, a name[subscript], or a name.field, and every bracket it opens it closes again
! before the '=' - so the '=' of an assignment is always at depth 0 of its statement.
! Anything deeper is inside a call's argument list, a subscript expression, or a
! parenthesised condition, and Clarion has no assignment expression to put there.
! That is what lets `x = clip(y)` be rewritten inside choose(...) while the same text as
! a whole statement is left alone - the case the introducer-anchored rules cannot reach,
! because there is no introducer to anchor to.
!
! Counts '[' as well as '(' deliberately: an unclosed subscript is just as good a proof.
! Braces are NOT counted - the tokenizer does not bracket them here, and a PROP
! assignment (`?Ctl{PROP:Text} = clip(x)`) therefore reads as depth 0 and is refused,
! which is the safe direction: that one really is an assignment.
! ------------------------------------------------------------------------------------
VitMatch.StartsInsideBracket Procedure(LONG pIx)
s      long,auto
i      long,auto
depth  long
  code
  s = self.StmtStart(pIx)
  if ~s or s >= pIx then return false. ! statement starts AT the match - depth 0 by construction
  loop i = s to pIx - 1
    depth += self.DepthDelta(self.TokText(i))
  end
  return choose(depth > 0)

! ------------------------------------------------------------------------------------
! The tokenizer's ParseText post-pass retypes END-terminator dots to vt:end
! (spacing-based); anything still typed vt:dot is member access.
! ------------------------------------------------------------------------------------
VitMatch.IsMemberDot Procedure(LONG pIx)
  code
  if self.TokText(pIx) <> '.' then return false.
  if self.TokType(pIx) = vt:end then return false.
  return true

! ------------------------------------------------------------------------------------
VitMatch.TokType Procedure(LONG pIx)
  code
  if pIx < 1 or pIx > self.tk.records() then return ''.
  get(self.tk.tokens, pIx)
  if errorcode() then return ''.
  return self.tk.tokens.type

! ------------------------------------------------------------------------------------
VitMatch.DepthDelta Procedure(STRING pTok)
  code
  if pTok = '(' or pTok = '[' then return 1.
  if pTok = ')' or pTok = ']' then return -1.
  return 0

! ------------------------------------------------------------------------------------
VitMatch.IsAllDigits Procedure(STRING pTok)
x    long,auto
n    long,auto
  code
  n = len(clip(pTok))
  if ~n then return false.
  loop x = 1 to n
    if val(pTok[x]) < 48 or val(pTok[x]) > 57 then return false.
  end
  return true

! ====================================================================================
! VitGolden - golden-format match-test runner (Phase 2)
! File format:  === case <name> / --- rules / --- input / --- expect
! The expect block holds the exact match report (see VitMatch.inc header).
! ====================================================================================
VitGolden.RunFile Procedure(STRING pFn, StringTheory pOut)
src     StringTheory
line    StringTheory
name    StringTheory
rules   StringTheory
input   StringTheory
expect  StringTheory
output  StringTheory
selBlk  StringTheory ! optional --- select block (SELECT is a Clarion statement - avoid the name)
usrBlk  StringTheory ! optional --- userrules block (append-loaded like --userrules=)
x       long,auto
state   long
started long
  code
  self.caseCount = 0
  self.passCount = 0
  self.failCount = 0
  if not src.LoadFile(pFn)
    pOut.append('could not load golden file ' & clip(pFn) & ' : ' & src.LastError & '<13,10>')
    return -1
  end
  src.replace('<13,10>', '<10>')
  src.replaceByte(13, 10) ! replace all <carriage return> with <line feed>
  src.split('<10>')
  loop x = 1 to src.records()
    line.setValue(src.getLine(x))
    if line._DataEnd > 7 and line.valuePtr[1 : 8] = '=== case'
      if started
        self.RunCase(name.getValue(), rules, usrBlk, input, expect, output, selBlk, pOut)
      end
      started = true
      name.setValue(line.slice(9))
      name.trim()
      rules.free()
      usrBlk.free()
      input.free()
      expect.free()
      output.free()
      selBlk.free()
      state = 0
      cycle
    end
    if line._DataEnd > 12 and line.valuePtr[1 : 13] = '--- userrules' ! user-rulefile block for this case
      state = 6
      cycle
    end
    if line._DataEnd > 8 and line.valuePtr[1 : 9] = '--- rules'
      state = 1
      cycle
    end
    if line._DataEnd > 8 and line.valuePtr[1 : 9] = '--- input'
      state = 2
      cycle
    end
    if line._DataEnd > 9 and line.valuePtr[1 : 10] = '--- expect'
      state = 3
      cycle
    end
    if line._DataEnd > 9 and line.valuePtr[1 : 10] = '--- output'
      state = 4
      cycle
    end
    if line._DataEnd > 9 and line.valuePtr[1 : 10] = '--- select' ! selection for this case
      state = 5
      cycle
    end
    case state
    of 1
      rules.append(line.getValue() & '<13,10>')
    of 2
      input.append(line.getValue() & '<13,10>')
    of 3
      expect.append(line.getValue() & '<13,10>')
    of 4
      output.append(line.getValue() & '<13,10>')
    of 5
      selBlk.append(line.getValue() & '<13,10>')
    of 6
      usrBlk.append(line.getValue() & '<13,10>')
    end
  end
  if started
    self.RunCase(name.getValue(), rules, usrBlk, input, expect, output, selBlk, pOut)
  end
  pOut.append('---<13,10>')
  pOut.append('cases: ' & self.caseCount & '  pass: ' & self.passCount & '  fail: ' & self.failCount & '<13,10>')
  return self.failCount

! ------------------------------------------------------------------------------------
VitGolden.RunCase Procedure(STRING pName, StringTheory pRules, StringTheory pUser, StringTheory pInput, StringTheory pExpect, StringTheory pOutput, StringTheory pSelect, StringTheory pOut)
crl    VitRules
ctk    VitTokenize
csym   VitSymbols
m      VitMatch
rw     VitRewrite
rep    StringTheory
res    StringTheory
rwLog  StringTheory
selLn  StringTheory         ! one --- select line
selUp  StringTheory
sStyle StringTheory         ! accumulated selection args for Resolve
sGrp   StringTheory
sNoGrp StringTheory
i      long,auto
  code
  self.caseCount += 1
  crl.ParseText(pRules)
  if pUser._DataEnd         ! append-load the case's user rulefile block -
    crl.LoadUserText(pUser) !     the same path as --userrules= (ids offset by vr:userBase)
  end
  crl.Lint()
  ! parse the --- select block (style <name> / group <names> / nogroup <names>)
  ! and ALWAYS resolve - the golden runner uses the same resolver as the CLI, so a
  ! case with no select block runs the file defaults through the same code path.
  if pSelect._DataEnd
    pSelect.LineEndings(st:unix)
    pSelect.split('<10>')
    loop i = 1 to pSelect.records()
      selLn.setValue(pSelect.getLine(i))
      selLn.trim()
      if ~selLn._DataEnd then cycle.
      selUp.setValue(selLn)
      selUp.upper()
      if selUp._DataEnd > 6 and selUp.valuePtr[1 : 6] = 'STYLE '
        sStyle.setValue(selLn.valuePtr[7 : selLn._DataEnd])
        sStyle.trim()
      elsif selUp._DataEnd > 6 and selUp.valuePtr[1 : 6] = 'GROUP '
        if sGrp._DataEnd then sGrp.append(',').
        sGrp.append(selLn.valuePtr[7 : selLn._DataEnd])
      elsif selUp._DataEnd > 8 and selUp.valuePtr[1 : 8] = 'NOGROUP '
        if sNoGrp._DataEnd then sNoGrp.append(',').
        sNoGrp.append(selLn.valuePtr[9 : selLn._DataEnd])
      else
        crl.AddIssue(0, vr:sevError, 'bad --- select line (expected style/group/nogroup): ' & selLn.getValue())
      end
    end
  end
  crl.Resolve(sStyle.getValue(), sGrp.getValue(), sNoGrp.getValue())
  if crl.ErrorCount()
    self.failCount += 1
    pOut.append('FAIL ' & clip(pName) & ' - rule lint/resolve errors:<13,10>')
    loop i = 1 to records(crl.issues)
      get(crl.issues, i)
      pOut.append('  line ' & crl.issues.lineNo & ' ' & choose(crl.issues.sev = vr:sevError, 'ERROR', 'WARN ') & ' ' & clip(crl.issues.msg) & '<13,10>')
    end
    return
  end
  ctk.ParseText(pInput) ! ParseText(StringTheory,<fileName>,pMergeLabels) overload
  csym.Build(ctk)       ! Phase 4: golden cases match TYPED, like the real engine

  if pOutput._DataEnd   ! ---- rewrite mode (Phase 3) ----
    rw.Init(crl, ctk)
    rw.SetSymbols(csym)
    rw.ApplyAll(rwLog)
    ctk.JoinToks(res)   ! whole file back to text, as-is format
    if self.SameReport(res, pOutput)
      self.passCount += 1
      pOut.append('PASS ' & clip(pName) & '<13,10>')
    else
      self.failCount += 1
      pOut.append('FAIL ' & clip(pName) & '<13,10>')
      pOut.append('--- expected ---<13,10>')
      pOut.append(pOutput)
      if pOutput._DataEnd
        if pOutput.valuePtr[pOutput._DataEnd] <> '<10>' then pOut.append('<13,10>').
      end
      pOut.append('--- actual ---<13,10>')
      pOut.append(res)
      if res._DataEnd
        if res.valuePtr[res._DataEnd] <> '<10>' then pOut.append('<13,10>').
      end
      pOut.append('--- log ---<13,10>')
      pOut.append(rwLog)
      pOut.append('--- end ---<13,10>')
    end
    return
  end

  m.Init(crl, ctk) ! ---- match-report mode (Phase 2) ----
  m.syms &= csym
  m.MatchAll(rep)
  if self.SameReport(rep, pExpect)
    self.passCount += 1
    pOut.append('PASS ' & clip(pName) & '<13,10>')
  else
    self.failCount += 1
    pOut.append('FAIL ' & clip(pName) & '<13,10>')
    pOut.append('--- expected ---<13,10>')
    pOut.append(pExpect)
    if pExpect._DataEnd
      if pExpect.valuePtr[pExpect._DataEnd] <> '<10>' then pOut.append('<13,10>').
    end
    pOut.append('--- actual ---<13,10>')
    pOut.append(rep)
    if rep._DataEnd
      if rep.valuePtr[rep._DataEnd] <> '<10>' then pOut.append('<13,10>').
    end
    pOut.append('--- end ---<13,10>')
  end

! ------------------------------------------------------------------------------------
VitGolden.SameReport Procedure(StringTheory pA, StringTheory pB)
a   StringTheory
b   StringTheory
la  StringTheory
lb  StringTheory
na  long,auto
nb  long,auto
i   long,auto
  code
  a.setValue(pA)
  b.setValue(pB)
  a.replace('<13,10>', '<10>')
  a.replaceByte(13, 10) ! replace all <carriage return> with <line feed>
  b.replace('<13,10>', '<10>')
  b.replaceByte(13, 10) ! replace all <carriage return> with <line feed>
  a.split('<10>')
  b.split('<10>')
  na = a.records()
  loop while na > 0
    la.setValue(a.getLine(na),st:clip)
    if la._DataEnd then break.
    na -= 1
  end
  nb = b.records()
  loop while nb > 0
    lb.setValue(b.getLine(nb),st:clip)
    if lb._DataEnd then break.
    nb -= 1
  end
  if na <> nb then return false.
  loop i = 1 to na
    la.setValue(a.getLine(i),st:clip)
    lb.setValue(b.getLine(i),st:clip)
    if choose(la._DataEnd < 1, '', la.valuePtr[1 : la._DataEnd]) <> lb.getValue() then return false.
  end
  return true
