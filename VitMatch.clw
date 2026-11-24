! VitMatch - the matcher of VitTransform
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! The matcher + golden-test runner. See VitMatch.inc header for the
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

! ------------------------------------------------------------------------------------
! The base answer to isPlain(): not known, so the guard refuses. The engine derives a class that knows.
! ------------------------------------------------------------------------------------
VitPlainAsk.IsPlain Procedure(LONG pTok)
  code
  return 0

! The base answer to marksSafe(): not known either, so the guard refuses.
VitPlainAsk.MarksSafe Procedure(LONG pTok)
  code
  return 0

! ====================================================================================
VitMatch.Construct Procedure()
  code
  self.binds    &= new MatchBindQType
  self.matches  &= new MatchRecQType
  self.bindRecs &= new BindRecQType
  self.rl       &= NULL
  self.tk       &= NULL
  self.plainAsk &= NULL
  self.patQ     &= NULL
  self.anchorLits &= NULL
  self.anchorPost &= NULL
  self.chainMissQ &= new ChainMissQType !
  self.grpQ       &= new GroupMemQType
  self.litIdx     &= new LitIdxQType
  self.pendMissQ  &= new PendMissQType
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
  if not self.chainMissQ &= NULL !
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
  if not self.spanQ &= NULL
    free(self.spanQ)
    dispose(self.spanQ)
  end
  if not self.grpQ &= NULL
    free(self.grpQ)
    dispose(self.grpQ)
  end
  if not self.litIdx &= NULL
    free(self.litIdx)
    dispose(self.litIdx)
  end
  if not self.pendMissQ &= NULL
    free(self.pendMissQ)
    dispose(self.pendMissQ)
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
  if self.anchorPost &= NULL then self.anchorPost &= new AnchorPostQType. !
  self.BuildAnchorLits()                                                  ! rebuild EVERY Init, not only when empty: LoadUserRules/LoadUserText can APPEND rules after a first transform (the VitStyle workbench
                                                                          !   flow), and a stale set lets an appended rule match NOTHING. BuildAnchorLits free()s first, and the rule walk is cheap per file.
  self.Changed()                                                          ! new file/case: recount on first CountTok, and the stream version moves
  self.patchable = 0                                                      !   the first count is a full walk; patches follow it
  if self.spanQ &= NULL then self.spanQ &= new PatchSpanQType.
  free(self.spanQ)

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
! the anchor occurrence. Matches never overlap (lastEnd). The per-rule set-up is
! EnterRule and the work at one anchor occurrence is TryPosting, so that the group walk
! (MatchGroup, grouped dispatch) does the same things in the same order for several
! rules at once.
! ------------------------------------------------------------------------------------
VitMatch.MatchRule Procedure(LONG pRow, StringTheory pReport)
anchor   StringTheory
aCount   long,auto
i        long,auto
s        long,auto
e        long,auto
ss       long,auto
N        long,auto
svMatch  long,auto
pKey     STRING(80) !
pr       long,auto
  code
  aCount = self.EnterRule(pRow, anchor)
  if ~aCount then return.                                ! no such rule, an empty pattern, or the anchor literal absent: nothing can match
  N = self.tk.records()
  pr = 0                                                 ! ,auto - and the postings test below reads it on BOTH paths
  if aCount > 0 and not self.anchorPost &= NULL          ! walk ONLY the anchor's occurrences (postings built by RefreshFreq)
    self.FreqKey(anchor.getValue(), pKey)
    pr = self.FindFirstPost(pKey)
  end
  ! no postings for a key the count says IS present means the anchor was never
  ! collected, so CountTok answered from its defensive full scan. Returning here would turn
  ! that defence into ZERO matches for the rule - silently, and only for the rule it rescued.
  ! Fall through to the linear loop below instead, which needs no postings.
  if aCount > 0 and not self.anchorPost &= NULL and pr
    loop pr = pr to records(self.anchorPost)
      get(self.anchorPost, pr)
      if errorcode() then break.
      if self.anchorPost.keyText <> pKey then break.
      if self.TryPosting(self.anchorPost.pos, 0, anchor.getValue(), pReport) and self.rl.rules.once
        break                                            ! ONCE: at most one applied match per file
      end
    end
    return
  end
  loop i = 1 to N                                        ! no-literal patterns (aCount<0): try every position
    if i <= self.lastEnd then cycle.
    if self.TokIsEOL(i) then cycle.
    if aCount > 0
      if self.anchDot                                    ! the same question at the fallback walk: only a block
        if self.TokText(i) <> '.' then cycle.            !   TERMINATOR can stand where the pattern ends a
        if self.IsMemberDot(i) then cycle.               !   fragment with a '.'
      elsif ~self.LitMatches(i, anchor.valuePtr[1 : anchor._DataEnd])
        if ~self.anchorOp then cycle.                    ! the anchor has no two-word spelling, so nothing else can qualify
        if ~self.AnchorNotPair(i, self.anchorOp) then cycle.
      end                                                ! fallback path (postings unavailable)
      if self.preLitOn and ~self.PreLitOK(i) then cycle.
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
      break                                              ! ONCE: at most one applied match per file
    end
  end

! ------------------------------------------------------------------------------------
! MatchRule's set-up for one rule, on its own so the group walk can do it for each member:
! the rules buffer holds the rule, patQ and the guard flags are loaded, lastEnd is 0, the
! anchor is picked (pAnchor holds its text, anchorIx its pattern part), the literal in front
! of it noted, and anchorOp holds the anchor's canonical spelling when it is a comparator.
! Returns what PickAnchor returns - the anchor's count in the file, -1 for a pattern with no
! literal - or 0 when there is nothing to match (no such rule, an empty pattern, the anchor
! absent from the file).
! ------------------------------------------------------------------------------------
VitMatch.EnterRule Procedure(LONG pRow, StringTheory pAnchor)
aCount   long,auto
  code
  get(self.rl.rules, pRow)
  if errorcode() then return 0.
  self.patQ &= self.rl.rules.patQ
  if self.patQ &= NULL then return 0.
  self.patCount = records(self.patQ)
  if ~self.patCount then return 0.
  self.ruleId = self.rl.rules.ruleId
  self.capRow = pRow
  if self.rl.rules.gdCached                                                         ! guards are pure pattern facts - classify once per rule, reuse across files
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
  aCount = self.PickAnchor(pAnchor)
  self.SetPreLit(aCount)
  if self.verbose and not self.vlog &= NULL                                         ! DIAG: which anchor each rule picked + whether it got skipped
    self.vlog.append('[scan] rule ' & self.ruleId & ' anchor=' & choose(aCount<0,'(no-literal)',clip(pAnchor.getValue())) & |
                     ' aCount=' & aCount & ' gd1Lit=' & self.gd1Lit & ' gd1IdMv=' & self.gd1IdMv                          & |
                     choose(~self.preLitOn, '', ' preLit=' & clip(self.preLit))                                           & |
                     choose(aCount=0,'  <<SKIPPED anchor-absent>>','') & '<13,10>')
  end
  ! ONCE per rule, not once per candidate: '' for all but a comparison operator, and then the
  ! candidate loops skip the two-word test on a single byte.
  ! L: slice rather than getValue() - the slice reads the buffer where it lies, getValue()
  ! copies it - and choose() is what guards the slice. Clarion short-circuits and evaluates
  ! only what it needs, so the valuePtr[1 : 0] that an EMPTY anchor would form never happens.
  ! It can be empty: aCount of -1 means the pattern has no literal to anchor on at all.
  self.anchorOp = choose(~pAnchor._DataEnd, '', self.OpCanon(pAnchor.valuePtr[1 : pAnchor._DataEnd]))
  self.PatFacts()
  return aCount

! ------------------------------------------------------------------------------------
! The work at ONE occurrence of the current rule's anchor, token pI: is it past the last
! match, is it the anchor (or its two-word NOT spelling), is the literal in front of it
! there - then every start from the statement's first token up to pI is tried until one
! matches. pStmt is that first token when the caller already knows it (the group walk finds
! it once per occurrence), 0 to find it here. pAnchorTx is the anchor's text. Returns 1 when
! a match was recorded - the ONCE test in the callers reads it.
! ------------------------------------------------------------------------------------
VitMatch.TryPosting Procedure(LONG pI, LONG pStmt, STRING pAnchorTx, StringTheory pReport)
s        long,auto
e        long,auto
ss       long,auto
svMatch  long,auto
  code
  if pI <= self.lastEnd then return 0.
  if self.anchDot                                            ! the anchor is a pattern '.' that ENDS a fragment - a block
    if self.TokText(pI) <> '.' then return 0.                !   TERMINATOR, which is the one dot LitMatches refuses
    if self.IsMemberDot(pI) then return 0.                   !   outright, so it cannot arbitrate THIS rule's postings
  elsif ~self.LitMatches(pI, pAnchorTx)                      ! STRING(80) keys can MERGE distinct literals - postings are a superset, LitMatches
    if ~self.anchorOp then return 0.                         !   is the arbiter (AnchorNotPair covers the two-word NOT form it cannot see)
    if ~self.AnchorNotPair(pI, self.anchorOp) then return 0.
  end
  if self.preLitOn and ~self.PreLitOK(pI) then return 0.     ! the literal in front of the anchor is not there: no start can work
  if pStmt
    ss = pStmt
  else
    ss = self.StmtStart(pI)
  end
  if ss <= self.lastEnd then ss = self.lastEnd + 1.
  svMatch = self.matchCount
  loop s = ss to pI
    if self.TokIsEOL(s) then cycle.
    if ~self.CandOK(s) then cycle.
    e = self.TryFrom(s, pReport)
    if e
      self.lastEnd = e
      break
    end
  end
  return choose(self.matchCount > svMatch)

! ------------------------------------------------------------------------------------
! THE GROUP WALK (grouped dispatch). grpQ holds the rules whose anchor is the
! key pKey - each entered through EnterRule and saved by AddMember - and the postings of
! that key are walked ONCE: at every occurrence each member still walking gets its turn, in
! rules-queue order, exactly the turn MatchRule would have given it at that occurrence, with
! its own lastEnd. The statement start is found once per occurrence and shared. What each
! member would have found on its own walk of the same stream, it finds here; the rewriter
! keeps the answers per rule (its cache) and throws the lot away the moment the stream
! changes, so no rule ever applies a match found on a stream that has moved. A ONCE member
! leaves the walk after its first recorded match, as its own walk would have stopped. THE
! WALK ITSELF MOVES NO COUNTER: what each member's turns add to chainUnres, rtFallbacks,
! skipCount and matchCount is taken back off and kept with the member (dChain..dMatch), and
! the receivers it refuses wait in pendMissQ; the rewriter moves the counters and lists the
! names at the member's own turn (CacheLoad), and again at each later turn on the same
! stream, exactly as the member's own scans would have. A member whose answer is discarded
! before its turn (the stream moved) leaves no trace, as classic leaves none. Captures into
! matches/bindRecs (capture mode), each match tagged with its rule's row. Returns the number
! of matches recorded.
! ------------------------------------------------------------------------------------
VitMatch.MatchGroup Procedure(STRING pKey, StringTheory pReport)
pr       long,auto
i        long,auto
stmt     long,auto
mem      long,auto
live     long,auto
sChain   long,auto
sRtf     long,auto
sSkip    long,auto
sMatch   long,auto
  code
  if self.grpQ &= NULL or ~records(self.grpQ) then return 0.
  pr = self.FindFirstPost(pKey)
  if ~pr then return 0.
  live = records(self.grpQ)
  loop pr = pr to records(self.anchorPost)
    get(self.anchorPost, pr)
    if errorcode() then break.
    if self.anchorPost.keyText <> pKey then break.
    i = self.anchorPost.pos
    stmt = 0
    loop mem = 1 to records(self.grpQ)
      get(self.grpQ, mem)
      if errorcode() then break.
      if self.grpQ.done then cycle.
      if i <= self.grpQ.lastEnd then cycle.   ! inside this member's last match: TryPosting would say the same
      self.LoadMember()
      self.deferMiss = 1                      ! refused receivers wait for the member's own turn (CacheLoad lists them)
      if ~stmt then stmt = self.StmtStart(i). ! once per occurrence, for every member
      sChain = self.chainUnres ; sRtf = self.rtFallbacks ; sSkip = self.skipCount ; sMatch = self.matchCount
      if self.TryPosting(i, stmt, self.grpQ.anchorTx, pReport)
        self.grpQ.nMatch += 1
        if self.grpQ.once                     ! ONCE: at most one applied match per file
          self.grpQ.done = 1
          live -= 1
        end
      end
      self.grpQ.lastEnd = self.lastEnd
      self.grpQ.dChain += self.chainUnres - sChain
      self.grpQ.dRtf   += self.rtFallbacks - sRtf
      self.grpQ.dSkip  += self.skipCount - sSkip
      self.grpQ.dMatch += self.matchCount - sMatch
      self.chainUnres = sChain ; self.rtFallbacks = sRtf ; self.skipCount = sSkip ; self.matchCount = sMatch
      put(self.grpQ)
    end
    if ~live then break.
  end
  self.deferMiss = 0
  return records(self.matches)

! ------------------------------------------------------------------------------------
! AddMember: the rule just entered (EnterRule) joins the group walk, with the state
! MatchGroup must restore at each occurrence; pAnchor is the anchor text EnterRule returned.
! LoadMember: the member in the grpQ buffer becomes the current rule.
! ------------------------------------------------------------------------------------
VitMatch.AddMember Procedure(LONG pRow, StringTheory pAnchor)
  code
  if self.grpQ &= NULL then return.
  clear(self.grpQ)
  self.grpQ.ruleRow  = pRow
  self.grpQ.ruleId   = self.ruleId
  self.grpQ.patCount = self.patCount
  self.grpQ.gdStmt   = self.gdStmt
  self.grpQ.gdNoDot  = self.gdNoDot
  self.grpQ.gdNoSelf = self.gdNoSelf
  self.grpQ.gd1Lit   = self.gd1Lit
  self.grpQ.gd1IdMv  = self.gd1IdMv
  self.grpQ.gd2Dot   = self.gd2Dot
  self.grpQ.anchorIx = self.anchorIx
  self.grpQ.anchorTx = pAnchor.getValue()
  self.grpQ.anchorOp = self.anchorOp
  self.grpQ.preLit   = self.preLit
  self.grpQ.preLitOn = self.preLitOn
  self.grpQ.once     = self.rl.rules.once
  add(self.grpQ)

VitMatch.LoadMember Procedure()
  code
  get(self.rl.rules, self.grpQ.ruleRow)
  self.patQ    &= self.rl.rules.patQ
  self.patCount = self.grpQ.patCount
  self.ruleId   = self.grpQ.ruleId
  self.capRow   = self.grpQ.ruleRow
  self.gdStmt   = self.grpQ.gdStmt
  self.gdNoDot  = self.grpQ.gdNoDot
  self.gdNoSelf = self.grpQ.gdNoSelf
  self.gd1Lit   = self.grpQ.gd1Lit
  self.gd1IdMv  = self.grpQ.gd1IdMv
  self.gd2Dot   = self.grpQ.gd2Dot
  self.anchorIx = self.grpQ.anchorIx
  self.anchorOp = self.grpQ.anchorOp
  self.preLit   = self.grpQ.preLit
  self.preLitOn = self.grpQ.preLitOn
  self.lastEnd  = self.grpQ.lastEnd
  self.PatFacts()

! ------------------------------------------------------------------------------------
! The token stream changed. Every place that changes it calls this, which sets freqDirty and
! counts the change (streamVer), which is what the rewriter's match cache is keyed by: a
! rule's matches found on one version of the stream are never applied to another.
! ------------------------------------------------------------------------------------
VitMatch.Changed Procedure()
  code
  self.freqDirty = true
  self.streamVer += 1

! ------------------------------------------------------------------------------------
! Auto-guards per spec 3.6, computed once per rule:
!  - bare function pattern  (literal label + '(')      -> no '.' before match
!  - mv.method pattern      (identifier metavar + '.') -> no '.' before match, receiver <> SELF
!  - statement anchoring for DELETE and COMMENT rules, assignment-shaped patterns
!    (a '=' as the second pattern token unless the rule carries INPARENS, or any
!    compound, reference or deep assignment operator there),
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
  if self.rl.rules.isDelete  or                                                  |
     self.rl.rules.isComment or                                                  |   ! commenting-out is statement surgery too
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
  case p2tok.getValue()                                                          ! compound assignments are assignment-shaped too - without this they got NO statement anchoring
  of '+=' orof '-=' orof '*=' orof '/=' orof '^=' orof '%=' orof '&=' orof ':=:' ! the six compound forms, the reference and the deep assignment (:=: is ONE token)
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
    if self.patQ.mvx or                 |
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
    ! gives up at "anchor literal absent" before comparing anything. (The one-token synonyms
    ! would fail the same way if FreqKey did not canonicalise them.) They make poor anchors
    ! anyway - PickAnchor wants the RAREST literal and operators are the commonest tokens
    ! there are - so the only patterns this changes are those with no other literal at all,
    ! which fall to the linear scan and still match.
    aTx.setValue(self.patQ.tok,st:clip) ! captured BEFORE the peeks below move the buffer
    cmpT = aTx.getValue()               ! *STRING callee needs a variable; 4 bytes, and anything longer truncates to 4 and still fails its one-character test
    ! A single-token comparison operator IS still a fine anchor: FreqKey canonicalises the
    ! one-token synonyms and RefreshFreq posts the two-word `NOT =` form under the same key, so
    ! the count is right whichever way the source spells it. What CANNOT anchor is either half
    ! of a two-word `NOT =` in the PATTERN: source spelling it `<>` contains no `NOT` and no
    ! `=`, so either would count 0 and skip the rule. Peek one row each way to recognise the
    ! pair. (Excluding operators outright also works, but it is much slower: rules with no
    ! other literal then fall to the linear scan.)
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
    if best and ~bestCnt then break.    ! cannot get rarer than absent
    ! THEN, ELSE and a terminator dot end the part an anchor may come from, as an interior ';'
    ! does. Every start tried runs from the statement start of the anchor, and that is found by
    ! walking back no further than the nearest THEN, ELSE or terminator - so an anchor past one
    ! could never reach the pattern's first token, and the rule would match or not depending
    ! on which of its words happens to be rarer in the file. The word itself may still anchor.
    case upper(choose(aTx._DataEnd < 1, '', aTx.valuePtr[1 : aTx._DataEnd]))
    of 'THEN' orof 'ELSE'
      break
    of '.'
      if self.PatDotEnds(t) then break.
    end
  end
  self.anchorIx = best
  if ~best then return -1.
  return bestCnt

! ------------------------------------------------------------------------------------
! THE LITERAL IN FRONT OF THE ANCHOR, checked before any start is tried.
!
! MatchRule tries, at every posting of the anchor, every token from the statement's first
! token up to the anchor as a start. When the pattern begins with a metavariable there is no
! cheap start test (CandOK), so a rule like `w1 <> clip(w)` pays a MatchHere - with the
! leading EXPR enumerating its extents - at every one of those tokens, at every one of the
! 900 places `clip` occurs in a large file: quadratic in the statement's length. Three such
! rules can cost a third of the scan time on a big file. Yet whichever start is tried, the
! pattern part in front of the anchor must match the token in front of the posting; when it
! is a literal and it is not there, no start can work. So it is checked once per posting.
!
! ONLY LITERALS MATCHHERE MATCHES ONE WAY. Words and numbers are left out (a dotted name may
! arrive merged, so the token in front is not always the one the pattern names), and so are
! quoted literals, '.', ';' and '~', which MatchHere reads by rules of their own; the anchor
! itself must not be a comparator with a two-word spelling (its own start would move), and
! the literal must not be the second word of a NOT pair. A two-byte comparator's two-word
! spelling (`NOT =` for `<>`) is accepted, exactly as MatchHere accepts it. The output cannot
! change: a posting this refuses is one MatchHere would have refused at that same token.
! ------------------------------------------------------------------------------------
VitMatch.SetPreLit Procedure(LONG pCount)
t  StringTheory
  code
  self.preLitOn = 0
  if pCount <= 0 or self.anchorIx < 2 then return.
  get(self.patQ, self.anchorIx)
  if errorcode() or self.patQ.mvx or self.patQ.tok &= NULL then return.
  t.setValue(self.patQ.tok,st:clip)
  if ~t._DataEnd or self.OpCanon(t.getValue()) then return.                         ! the anchor is a comparator: left alone
  get(self.patQ, self.anchorIx - 1)
  if errorcode() or self.patQ.mvx or self.patQ.tok &= NULL then return.
  if not self.patQ.mvTail &= NULL then return.
  t.setValue(self.patQ.tok,st:clip)
  if t._DataEnd < 1 or t._DataEnd > size(self.preLit) then return.
  case val(t.valuePtr[1])
  of 48 to 57 orof 65 to 90 orof 97 to 122 orof 95 orof 39 orof 46 orof 59 orof 126 ! a number, a word, a quoted literal, '.', ';', '~'
    return
  end
  if self.anchorIx > 2
    get(self.patQ, self.anchorIx - 2)
    if ~errorcode() and ~self.patQ.mvx and not self.patQ.tok &= NULL
      if upper(self.patQ.tok) = 'NOT' then return.                                  ! the second word of a NOT pair
    end
  end
  self.preLit   = t.getValue()
  self.preLitOn = 1

VitMatch.PreLitOK Procedure(LONG pI)
opC  string(4),auto
cmpT string(4),auto
  code
  if pI < 2 then return 0.
  if self.LitMatches(pI - 1, self.preLit) then return 1.
  if pI < 3 or len(clip(self.preLit)) <> 2 then return 0.
  opC = self.OpCanon(self.preLit[1 : 2])
  if ~opC then return 0.
  cmpT = self.TokText(pI - 1)
  if self.NotInfixAt(pI - 2) and opC = self.OpCanonNot(cmpT) then return 1. ! `NOT =` for `<>`, as MatchHere reads it
  return 0

! ------------------------------------------------------------------------------------
! PatFacts - the two pattern facts the candidate gates need, answered ONCE per rule rather
! than once per candidate, exactly as anchorOp is.
!
! anchDot. A pattern '.' that ENDS a fragment is a block TERMINATOR, and that is the ONE
! dot LitMatches refuses outright - every other pattern dot is member access, which is what
! it reads a pattern dot as. So when PickAnchor lands on such a dot LitMatches cannot
! arbitrate its postings: it would refuse every terminator dot in the file, and the rule
! would match nothing at all, silently.
!
! pat1NotOp. When pattern part 1 is the word NOT opening a two-word operator, the operator it
! spells. Source may spell the same operator in one token (`NOT <` is `>=`), and MatchHere
! consumes the two pattern parts for that one token - so CandOK must let the start through,
! and OpCanon('NOT') is '', which is why the comparator test there cannot see it.
!
! Leaves the patQ buffer on part 1.
! ------------------------------------------------------------------------------------
VitMatch.PatFacts Procedure()
  code
  self.anchDot   = 0
  self.pat1NotOp = ''
  self.pat1Expr  = 0
  self.repNot    = 0
  if self.patQ &= NULL then return.
  if self.anchorIx > 0
    get(self.patQ, self.anchorIx)
    if ~errorcode() and ~self.patQ.mvx and not self.patQ.tok &= NULL
      if self.patQ.tok = '.'
        self.anchDot = self.PatDotEnds(self.anchorIx)
      end
    end
  end
  get(self.patQ, 1)                                                                 ! a pattern opening with an EXPR metavar: CandOK keeps its start off a statement keyword
  if ~errorcode() and self.patQ.mvx
    get(self.rl.metaVars, self.patQ.mvx)
    if ~errorcode() and self.rl.metaVars.kind = vr:mvExpr then self.pat1Expr = 1.
  end
  if not self.rl.rules.repQ &= NULL                                                 ! a replacement opening with ~ or NOT: TryFrom's EXPREND test also refuses a comparison after the match
    get(self.rl.rules.repQ, 1)
    if ~errorcode() and ~self.rl.rules.repQ.mvx and not self.rl.rules.repQ.tok &= NULL
      if self.rl.rules.repQ.tok = '~' or upper(self.rl.rules.repQ.tok) = 'NOT' then self.repNot = 1.
    end
  end
  if self.patCount < 2 then return.
  get(self.patQ, 1)
  if errorcode() or self.patQ.mvx or self.patQ.tok &= NULL then return.
  if upper(self.patQ.tok) <> 'NOT' then return.
  get(self.patQ, 2)
  if ~errorcode() and ~self.patQ.mvx and not self.patQ.tok &= NULL
    self.pat1NotOp = self.OpCanonNot(self.patQ.tok)
  end
  get(self.patQ, 1)

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
      if self.patchable and not self.spanQ &= NULL and records(self.spanQ) ! a firing rule's spans: patch
        self.PatchPostings()
      else                                                                 ! a re-lex or a built-in edit: the full walk
        self.RefreshFreq()
      end
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
  ! the stream's `=<` and a pattern's `<=` land on the same row. Without this the synonym test
  ! in LitMatches is unreachable: PickAnchor asks CountTok how often the pattern's rarest literal
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
  if pTok[1] = ''''       ! quoted literal: exact case
    pKeyOut = pTok[1 : w]
  else                    ! identifier/keyword/operator: caseless
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
row  long,auto
  code
  if self.anchorLits &= NULL then self.anchorLits &= new AnchorLitQType.
  free(self.anchorLits)
  if self.rl &= NULL then return.
  if not self.litIdx &= NULL then free(self.litIdx).
  loop r = 1 to records(self.rl.rules)
    get(self.rl.rules, r)
    if errorcode() then break.
    if self.rl.rules.kind <> vr:kindRule or       |
       self.rl.rules.patQ &= NULL
      cycle
    end
    loop t = 1 to records(self.rl.rules.patQ)
      get(self.rl.rules.patQ, t)
      if errorcode() then break.
      if self.rl.rules.patQ.tok &= NULL or        |
         self.rl.rules.patQ.mvx         or        |   ! metavar, not a literal
         self.rl.rules.patQ.tok = ';'             ! statement boundary/assertion
        cycle
      end
      self.FreqKey(self.rl.rules.patQ.tok, key)
      if ~key then cycle.
      if not self.litIdx &= NULL                  ! the group walk asks which rules carry a key
        self.litIdx.keyText = key
        self.litIdx.ruleRow = r
        add(self.litIdx)                          ! dups (a key twice in one pattern) collapsed below
      end
      self.anchorLits.keyText = key
      self.anchorLits.cnt     = 0
      add(self.anchorLits)                        ! dups allowed here; collapsed after the sort
    end
  end
  if ~records(self.anchorLits) then return.
  sort(self.anchorLits, +self.anchorLits.keyText)
  row = records(self.anchorLits)                  ! collapse adjacent duplicates, top-down
  loop while row > 1
    get(self.anchorLits, row)
    key = self.anchorLits.keyText
    get(self.anchorLits, row - 1)
    if key = self.anchorLits.keyText
      get(self.anchorLits, row)
      delete(self.anchorLits)
    end
    row -= 1
  end
  if self.litIdx &= NULL or ~records(self.litIdx) then return.
  sort(self.litIdx, +self.litIdx.keyText, +self.litIdx.ruleRow)
  row = records(self.litIdx)                      ! collapse a key repeated within one pattern
  loop while row > 1
    get(self.litIdx, row)
    key = self.litIdx.keyText
    r   = self.litIdx.ruleRow
    get(self.litIdx, row - 1)
    if key = self.litIdx.keyText and r = self.litIdx.ruleRow
      get(self.litIdx, row)
      delete(self.litIdx)
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
  code
  if self.anchorLits &= NULL then return.
  if self.anchorPost &= NULL then self.anchorPost &= new AnchorPostQType.
  self.RefreshInto(self.anchorLits, self.anchorPost)
  if not self.spanQ &= NULL then free(self.spanQ).   ! a rebuild pays every span off
  self.patchable = 1

! ------------------------------------------------------------------------------------
! RefreshInto - RefreshFreq's walk, into the queues given: the live ones from RefreshFreq,
! scratch ones from PatchPostings' --postcheck, which compares the two.
! ------------------------------------------------------------------------------------
VitMatch.RefreshInto Procedure(AnchorLitQType pLits, AnchorPostQType pPost)
i    long,auto
key2 STRING(80),AUTO ! canonical key of a two-word NOT operator opening at i
cmpT string(4),auto  ! a variable for the *STRING callee
n    long,auto
row  long,auto
key  STRING(80)
rfT0 long,auto       ! --timing
  code
  loop row = 1 to records(pLits)
    get(pLits, row)
    pLits.cnt = 0
    put(pLits)
  end
  free(pPost)                                               ! rebuild postings with the counts
  if self.tk &= NULL then return.
  rfT0 = clock()
  n = self.tk.records()
  loop i = 1 to n
    if self.TokIsEOL(i) then cycle.
    self.FreqKey(self.TokText(i), key)
    if ~key then cycle.
    row = self.FindAnchorLit(key)
    if row
      get(pLits, row)
      pLits.cnt += 1
      put(pLits)
      if not pPost &= NULL                                  ! record the occurrence
        pPost.keyText = pLits.keyText
        pPost.pos     = i
        add(pPost)
      end
    end
    ! An infix `NOT` opening a two-word operator is ALSO posted under that operator's canonical
    ! key, so a rule anchored on `<>` still finds source that spells it `NOT =`. Without this
    ! the anchor count comes back 0 and MatchRule gives up before comparing anything - and the
    ! alternative, refusing to anchor on comparison operators at all, is much slower, because
    ! rules then fall to the linear scan. Posted IN ADDITION to its own 'NOT' key, so a
    ! rule that genuinely anchors on the word NOT is unaffected. One probe per NOT token.
    if key = 'NOT' and self.NotInfixAt(i)                   ! `key` is already this token's upper text -
      cmpT = self.TokText(i + 1)
      key2 = self.OpCanonNot(cmpT)                          !   test it before paying for NotInfixAt, which would otherwise run on EVERY token of every refresh
      if key2
        row = self.FindAnchorLit(key2)
        if row
          get(pLits, row)
          pLits.cnt += 1
          put(pLits)
          if not pPost &= NULL
            pPost.keyText = pLits.keyText
            pPost.pos     = i
            add(pPost)
          end
        end
      end
    end
  end
  if not pPost &= NULL
    sort(pPost, +pPost.keyText, +pPost.pos)                 ! +pos is LOAD-BEARING: MatchRule's lastEnd/ONCE logic needs ascending positions
                                                            !   within each key run, and POSITION() lower-bounds on this active sort order
  end
  rfT0 = clock() - rfT0 ; if rfT0 < 0 then rfT0 += 8640000. ! --timing, across midnight
  self.nRefresh += 1 ; self.tRefresh += rfT0

! ------------------------------------------------------------------------------------
! NotePatch - a firing rule replaced tokens pA..pB, in the positions of BEFORE it fired, with
! pN tokens. VitRewrite applies a rule's matches highest first, so every span it notes is
! below the ones already noted and its positions are still the pre-fire ones. More spans than
! a patch is worth (a rule that fires everywhere) hands the file back to the full rebuild.
! ------------------------------------------------------------------------------------
VitMatch.NotePatch Procedure(LONG pA, LONG pB, LONG pN)
  code
  if self.spanQ &= NULL then self.spanQ &= new PatchSpanQType.
  ! EVERY span held here must be measured against the SAME stream, because PatchPostings reads
  ! them as one coordinate base. Normally they are: the next rule asks CountTok for its anchor
  ! count and that drains the queue first. But a rule whose pattern has no literal to anchor on
  ! never asks - PickAnchor returns -1 before it reaches CountTok - so a rule firing after one
  ! of those would stack its spans on top of the earlier rule's, in coordinates one edit apart,
  ! and every posting would then move by the wrong amount. Refuse the patch instead and let the
  ! next count take the full walk, which is right whatever the base.
  if ~records(self.spanQ)
    self.spanVer = self.streamVer
  elsif self.spanVer <> self.streamVer
    self.patchable = 0
    return
  end
  if records(self.spanQ) >= 2000 then self.patchable = 0 ; return.
  self.spanQ.a = pA
  self.spanQ.b = pB
  self.spanQ.n = pN
  add(self.spanQ)

! ------------------------------------------------------------------------------------
! PatchPostings - the postings brought up to date from the spans, instead of a walk over
! every token (ruled 14 Sep 2026). Three moves, after
! one refusal - a span whose EDGE is what decides a two-word `NOT <cmp>` posting just outside
! it cannot be patched, and goes to the full rebuild:
!   1. a posting inside a replaced span goes;
!   2. every other posting moves by the total change in length of the spans below it;
!   3. the tokens now standing in each span are read for anchor words, as RefreshInto reads
!      them, and posted - the two-word `NOT =` form included.
! Then the postings are sorted as RefreshInto sorts them and the per-key counts recomputed
! from them. Under --postcheck a full rebuild into scratch queues follows, the two are
! compared row for row, and a difference is counted (postMiss) and the rebuild kept - so a
! wrong patch can never reach the output, only the report.
! ------------------------------------------------------------------------------------
VitMatch.PatchPostings Procedure()
sp      long,auto
pr      long,auto
i       long,auto
shift   long,auto
gone    byte,auto
row     long,auto
newA    long,auto
newE    long,auto
cum     long,auto
key     STRING(80)
key2    STRING(80),AUTO
cmpT    string(4),auto
nRefSv  long,auto ! --timing's rebuild counters, put back after the --postcheck reference rebuild
tRefSv  long,auto
t0      long,auto
chkLits &AnchorLitQType
chkPost &AnchorPostQType
bad     long,auto
  code
  if self.anchorLits &= NULL or self.anchorPost &= NULL or self.spanQ &= NULL then self.RefreshFreq() ; return.
  if ~records(self.spanQ) then self.RefreshFreq() ; return.
  t0 = clock()
  sort(self.spanQ, +self.spanQ.a)
  ! ---- a span whose EDGE decides a two-word `NOT <cmp>` posting: rebuild, do not patch
  ! A posting's own key comes from its own token, but the derived `NOT =` key comes from the
  ! token AFTER the NOT, and whether that NOT is infix at all from the token BEFORE it. Step 3
  ! re-reads only the tokens INSIDE a span, so a NOT posting standing just outside one can have
  ! had its key decided by tokens the span has since replaced: the posting is then stale, or -
  ! worse - missing, and a missing anchor posting can take the key's count to 0, at which point
  ! the rule stops firing on the rest of the file and the patched run and a rebuilt one disagree.
  ! Re-reading one token either side would double-post wherever two spans meet, so these few
  ! files go to the full rebuild instead. The two tests below are exactly the two dependencies
  ! that cross an edge; everything else a posting reads is inside the span, and re-read, or is
  ! not touched at all.
  cum = 0
  loop sp = 1 to records(self.spanQ)
    get(self.spanQ, sp)
    if errorcode() then break.
    newA = self.spanQ.a + cum
    newE = newA + self.spanQ.n - 1
    cum += self.spanQ.n - (self.spanQ.b - self.spanQ.a + 1)
    ! the NOT below the span: its comparator is the span's FIRST token now. Whether it is infix
    ! is read from the token before it, which the span did not touch, so that half still stands.
    if upper(self.TokText(newA - 1)) = 'NOT' and self.NotInfixAt(newA - 1)
      self.RefreshFreq()
      return
    end
    ! the NOT above the span: the span's LAST token is what says whether it is infix. Its
    ! comparator is outside and unchanged, so only a NOT that really has one can be affected.
    if upper(self.TokText(newE + 1)) = 'NOT'
      cmpT = self.TokText(newE + 2)
      if self.OpCanonNot(cmpT)
        self.RefreshFreq()
        return
      end
    end
  end
  ! ---- 1 and 2: drop the postings inside a span, move the rest
  pr = 1
  loop while pr <= records(self.anchorPost)
    get(self.anchorPost, pr)
    if errorcode() then break.
    shift = 0 ; gone = 0
    loop sp = 1 to records(self.spanQ)
      get(self.spanQ, sp)
      if errorcode() then break.
      if self.spanQ.a > self.anchorPost.pos then break.                 ! spans are sorted: the rest lie above this posting
      if self.anchorPost.pos <= self.spanQ.b then gone = 1 ; break.     ! inside the span
      shift += self.spanQ.n - (self.spanQ.b - self.spanQ.a + 1)
    end
    if gone
      delete(self.anchorPost)
      cycle                                                             ! the next row moved into pr
    end
    if shift
      self.anchorPost.pos += shift
      put(self.anchorPost)
    end
    pr += 1
  end
  ! ---- 3: post the new tokens of every span
  cum = 0
  loop sp = 1 to records(self.spanQ)
    get(self.spanQ, sp)
    if errorcode() then break.
    newA = self.spanQ.a + cum
    newE = newA + self.spanQ.n - 1
    cum += self.spanQ.n - (self.spanQ.b - self.spanQ.a + 1)
    loop i = newA to newE
      if i < 1 or i > self.tk.records() then cycle.
      if self.TokIsEOL(i) then cycle.
      self.FreqKey(self.TokText(i), key)
      if ~key then cycle.
      row = self.FindAnchorLit(key)
      if row
        get(self.anchorLits, row)
        self.anchorPost.keyText = self.anchorLits.keyText
        self.anchorPost.pos     = i
        add(self.anchorPost)
      end
      if key = 'NOT' and self.NotInfixAt(i)
        cmpT = self.TokText(i + 1)
        key2 = self.OpCanonNot(cmpT)
        if key2
          row = self.FindAnchorLit(key2)
          if row
            get(self.anchorLits, row)
            self.anchorPost.keyText = self.anchorLits.keyText
            self.anchorPost.pos     = i
            add(self.anchorPost)
          end
        end
      end
    end
  end
  sort(self.anchorPost, +self.anchorPost.keyText, +self.anchorPost.pos)
  ! ---- the counts, from the postings
  loop row = 1 to records(self.anchorLits)
    get(self.anchorLits, row)
    self.anchorLits.cnt = 0
    put(self.anchorLits)
  end
  loop pr = 1 to records(self.anchorPost)
    get(self.anchorPost, pr)
    if errorcode() then break.
    row = self.FindAnchorLit(self.anchorPost.keyText)
    if row
      get(self.anchorLits, row)
      self.anchorLits.cnt += 1
      put(self.anchorLits)
    end
  end
  free(self.spanQ)
  self.postPatched += 1
  t0 = clock() - t0 ; if t0 < 0 then t0 += 8640000.
  self.nPatch += 1 ; self.tPatch += t0
  if ~self.postCheck then return.
  ! ---- --postcheck: the full walk into scratch queues, compared row for row; a difference keeps the rebuild
  nRefSv = self.nRefresh ; tRefSv = self.tRefresh                       ! the reference rebuild is a CHECK, not a rebuild - --timing must not count it
  chkLits &= new AnchorLitQType
  chkPost &= new AnchorPostQType
  loop row = 1 to records(self.anchorLits)
    get(self.anchorLits, row)
    chkLits.keyText = self.anchorLits.keyText
    chkLits.cnt     = 0
    add(chkLits)
  end
  self.RefreshInto(chkLits, chkPost)
  self.nRefresh = nRefSv ; self.tRefresh = tRefSv
  bad = 0
  if records(chkPost) <> records(self.anchorPost)
    bad = 1
  else
    loop pr = 1 to records(chkPost)
      get(chkPost, pr)
      get(self.anchorPost, pr)
      if chkPost.keyText <> self.anchorPost.keyText or chkPost.pos <> self.anchorPost.pos then bad = 1 ; break.
    end
  end
  if ~bad
    loop row = 1 to records(chkLits)
      get(chkLits, row)
      get(self.anchorLits, row)
      if chkLits.cnt <> self.anchorLits.cnt then bad = 1 ; break.
    end
  end
  if bad                                                                ! the patch was wrong: say so, and keep the rebuild
    self.postMiss += 1
    free(self.anchorPost)
    loop pr = 1 to records(chkPost)
      get(chkPost, pr)
      self.anchorPost.keyText = chkPost.keyText
      self.anchorPost.pos     = chkPost.pos
      add(self.anchorPost)
    end
    ! FREE removes every memory key the queue had, so the rebuild is installed with the
    ! (keyText,pos) order gone - and FindFirstPost reads the postings through POSITION(),
    ! which lower-bounds on the ACTIVE sort order and cannot rebuild one for itself the way
    ! a keyed GET can. Sort it back, exactly as RefreshInto and the patch above do.
    sort(self.anchorPost, +self.anchorPost.keyText, +self.anchorPost.pos)
    loop row = 1 to records(chkLits)
      get(chkLits, row)
      get(self.anchorLits, row)
      self.anchorLits.cnt = chkLits.cnt
      put(self.anchorLits)
    end
  end
  free(chkLits) ; dispose(chkLits)
  free(chkPost) ; dispose(chkPost)

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
! There is no walk-back from SOME matching row to the first, and none is needed - the
! POSITION lower-bound idiom below lands on the first row of the run directly.
! ------------------------------------------------------------------------------------
VitMatch.FindFirstPost Procedure(STRING pKey)
fpr long,auto
  code
  ! the POSITION(queue) idiom - with the buffer CLEARed (pos = 0) and keyText
  ! set, POSITION lower-bounds on the active (keyText,pos) sort order: it returns the FIRST
  ! row of pKey's run; on a miss it returns the next-greater row (or RECORDS+1), which the
  ! caller's keyText-change break handles. Documented behaviour, no bookkeeping.
  if self.anchorPost &= NULL then return 0.
  clear(self.anchorPost)
  self.anchorPost.keyText = pKey
  fpr = position(self.anchorPost)
  if ~fpr or fpr > records(self.anchorPost) then return 0. ! nothing at or after the key
  get(self.anchorPost, fpr)
  if errorcode() then return 0.
  if self.anchorPost.keyText <> pKey then return 0.        ! POSITION lower-bounds, so a next-greater row is a MISS -
  return fpr                                               !   report it as 0 so the caller's no-postings rescue can fire

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
  if self.loose or                                                                     |
     self.syms &= NULL
    return true
  end
  get(self.rl.metaVars, pMvx)
  if errorcode() then return false.                                                    ! REFUSE on a failed metavar fetch. Returning true would make a TYPED gate accept anything - the type check disappears and the
                                                                                       !   rule rewrites what it was never meant to touch. ClassSatisfies refuses on this condition too - all three must agree.
  if self.rl.metaVars.kind = vr:mvAnyVar or                                            |
     self.rl.metaVars.kind <> vr:mvTyped and self.rl.metaVars.kind <> vr:mvClass and self.rl.metaVars.kind <> vr:mvTypeSet
    return true
  end
  ok = self.syms.Lookup(self.TokText(pS), pS, tU, rf)
  if ~ok                                                                               ! undeclared: ASSUME patterns may supply a type
    tU = upper(self.AssumeOf(self.TokText(pS)))
    if tU then ok = true.
  end
  if ok and self.rl.metaVars.kind = vr:mvTypeSet                                       ! membership in the named TYPESET
    tsx = self.rl.FindTypeSet(self.rl.metaVars.typeName)
    if tsx
      get(self.rl.typeSets, tsx)
      if self.rl.typeSets.members.findChars(' ' & clip(tU) & ' ') then return true.
    end
  elsif ok and upper(self.rl.metaVars.typeName) = tU
    return true
  end
  if self.verbose and not self.vlog &= NULL
    self.vlog.append('rule ' & self.rl.rules.ruleId & ' line ' & self.LineOf(pS) & ' type-miss: ' & |
                     self.TokText(pS) & ' is ' & choose(~ok, 'unresolved', clip(tU))              & |
                     ', rule wants ' & clip(self.rl.metaVars.typeName) & '<13,10>')
  end
  ! UNRESOLVED only, and only a RECEIVER - a token followed by '.'. `ok` with the
  ! wrong type is an ordinary no-match and must stay silent (see NoteChainUnres), and an
  ! unresolved token that is NOT a receiver is usually a keyword or a runtime function
  ! sitting where a typed metavar could have bound: counting those would name UPPER, END,
  ! DELETE, CYCLE and CLIP on a real file, which is noise wearing a signal's
  ! clothes. A receiver is the case the advice can actually help with.
  ! IsMemberDot, not a raw '.' test: a one-liner's TERMINATOR dot is also a '.' token, and
  ! testing the text alone would report TRUE and FALSE as receivers - `if x then return
  ! true.` names TRUE, which is no receiver.
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
! declaration living in an INCLUDE, which is invisible without --thorough: a receiver
! declared in an include does not convert, and without this line the run just does
! less, silently.
! ------------------------------------------------------------------------------------
VitMatch.NoteChainUnres Procedure(STRING pRecv)
! #Removed as not used: r    long,auto
! #Removed as not used: nmU  string(vs:maxName),auto
  code
  self.chainUnres += 1
  ! a group-walk member's turn: the name waits for the member's own turn (CacheLoad lists it
  ! then), so the list reads in the order the classic walk would have met the receivers
  if self.deferMiss and not self.pendMissQ &= NULL
    clear(self.pendMissQ)
    self.pendMissQ.ruleRow = self.capRow
    self.pendMissQ.recv    = pRecv
    add(self.pendMissQ)
    return
  end
  self.NoteMissName(pRecv)

VitMatch.NoteMissName Procedure(STRING pRecv)
r    long,auto
nmU  string(vs:maxName),auto
  code
  if self.chainMissQ &= NULL or                 |
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
! The tokenizer recombines a member-access receiver into ONE token
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
  if self.loose or                                                                      |
     self.syms &= NULL
    return true
  end
  get(self.rl.metaVars, pMvx)
  if errorcode() then return false.                                                     ! REFUSE on a failed metavar fetch. Returning true would make a TYPED gate accept anything - the type check disappears and the
                                                                                        !   rule rewrites what it was never meant to touch. ClassSatisfies refuses on this condition too - all three must agree.
  if self.rl.metaVars.kind <> vr:mvClass and self.rl.metaVars.kind <> vr:mvTyped and self.rl.metaVars.kind <> vr:mvTypeSet then return true.
  txt = self.TokText(pS)
  tLen = len(clip(txt))
  dotP = segs.findByte(46, 1,, txt)                                                     ! <dot>
  if dotP < 2 or dotP >= tLen then return false.
  head = upper(sub(txt, 1, dotP - 1))                                                   ! receiver head (before first '.')
  ok = self.syms.Lookup(head, pS, tU, rf)                                               ! self -> receiver class; local/param -> its type
  if ~ok
    tU = upper(self.AssumeOf(head))
    if tU then ok = true.
  end
  if ~ok and self.syms.FindTypeDef(head)                                                ! dot-form: a labelled structure INSTANCE (Grp GROUP / UseQ QUEUE)
    tU = head                                                                           ! is a registry typedef under its own label, not a symbol - the label IS the type
    ok = true
  end
  if self.verbose and not self.vlog &= NULL                                             ! DIAG: trace EVERY chain check (not just misses)
    self.vlog.append('[chain] rule ' & self.rl.rules.ruleId & ' tok@' & pS & ' "' & clip(txt) & '" head=' & clip(head) & |
                     ' selfLookup=' & choose(~ok,'FAIL','ok->' & clip(tU)) & '<13,10>')
  end
  if ~ok
    ! only a real identifier is worth reporting. A quoted LITERAL holding a dot (`'.target='''`)
    ! and a decimal number (2.5) are single tokens too, and split into a "head" that resolves to
    ! nothing, and reporting them would fill the line with "receivers" that are only
    ! literals. So a head that is not a name is refused without a word.
    if self.rl.IsLabelToken(head)
      self.NoteChainUnres(txt)                                                          ! the HEAD has no known class - not visible, not wrong
    end
    return false
  end
  segs.setValue(sub(txt, dotP + 1, tLen - dotP))                                        ! remaining members: 'Direct' or 'Inner.Payload'
  segs.replaceByte(46, 124)                                                             ! replace all <dot> with '|'
  term = self.syms.LookupChain(tU, segs.getValue(), pS)                                 ! pS: the receiver token IS the use site, and that is what tells two procedures' same-named local types apart
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
    ! not apply, and saying so would put hundreds of useless names on the line for a
    ! class of any size (every method of it named with a dot), even with --thorough
    ! on.
    if ~self.syms.FindTypeDef(tU) then self.NoteChainUnres(txt).
    return false
  end
  if self.rl.metaVars.kind = vr:mvTypeSet                                               ! dot-form: terminal must be a member of the named TYPESET
    tsx = self.rl.FindTypeSet(self.rl.metaVars.typeName)
    if tsx
      get(self.rl.typeSets, tsx)
      if self.rl.typeSets.members.findChars(' ' & clip(term) & ' ') then return true.
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
    of '[' orof '{{'                    ! a subscript or a property nests like parens: the comma
      depth += 1                        !   in names[i,j] or ?L{P, 1} is not an argument separator.
    of ']' orof '}'                     !   Every sibling scanner counts these (DepthDelta)
      depth -= 1
      if depth < 1 then return -1.      ! malformed - refuse, do not guess (mirrors the EOL refusal)
    of ','
      if depth = 1 then n += 1.         ! a separator at OUR level ends an argument
    end
    if depth = 1 and self.TokText(e) <> ',' then seen = 1.
  end
  if ~seen then return 0.               ! '()' - a real arity of zero, not an unknown
  return n + 1                          ! k separators = k+1 arguments

! ------------------------------------------------------------------------------------
! what TYPE is each argument of the call whose '(' sits at pOpenTok? Returns one
! '|'-terminated slot per argument, in order, each holding what we could work out about it and
! EMPTY where we could not; '' when the list is too long to hold. Only a positive fact may
! exclude an overload. The rule per slot:
!   a quoted literal or a number  -> vs:scalarArg  (definitely a value, so not a class instance)
!   a single label token          -> its class, or '' when the symbol table cannot place it
!   anything else                 -> '' - a multi-token expression like `a + b` or `f(x)` is a
!                                   different job, and guessing it would be the wrong kind of
!                                   confident
! An empty slot narrows nothing (see VitSymbols.ArgAdmits), so typing every argument rather than
! the first alone can only ever ADD resolutions: a call settled by argument one stays settled, and
! one that argument one leaves ambiguous may be settled by a later argument.
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
    if txt = '[' or txt = '{{' then dep += 1.   ! subscript and property commas are not separators
    if txt = ']' or txt = '}' then dep -= 1.
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
  if t - first = 1                    ! exactly one token - the only shape we type
    txt = self.TokText(first)
    if txt
      if txt[1] = ''''
        one = vs:scalarArg            ! a quoted literal
      elsif numeric(clip(txt))
        one = vs:scalarArg            ! a number
      elsif self.rl.IsLabelToken(txt)
        one = self.RecvClass(first)   ! '' when the symbol table cannot place it
      end
    end
  end
  res.append(clip(one) & '|')

! ------------------------------------------------------------------------------------
! does method pName on receiver class pRecvClassU return a STRING?
! Header truth first: when the registry has a typedef for the class, the answer comes
! from the prototype return-type table (inheritance via parentU; a *String / &String
! reference return COUNTS as string - it is a string value in expression context
! veto if ref returns should refuse). A StringTheory object whose class header was not
! read takes the six-name fallback below - StringTheory declares all six as returning a
! String - and it is counted for the per-file report line. Any OTHER class the registry does
! not know answers no: its methods may be named like StringTheory's and return a number,
! and `if clip(obj.Left(1))` would lose a clip that kept the test true.
! pArgCount selects the OVERLOAD. -1 = the caller does not know its own arity,
! which considers every row - for any caller that cannot count its arguments.
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
  if upper(pRecvClassU) <> 'STRINGTHEORY' then return false.
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
      if self.rl.typeSets.members.findChars(' ' & clip(upper(pClassU)) & ' ') then return true.
    end
    return false
  of vr:mvClass orof vr:mvTyped
    return choose(upper(self.rl.metaVars.typeName) = upper(pClassU))
  end
  return false

! ------------------------------------------------------------------------------------
! the TERMINAL CLASS of the receiver token at pS (plain
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
  dotP = instring('.', txt[1 : tLen], 1, 1)
  if ~dotP                                              ! plain identifier receiver
    if ~self.rl.IsLabelToken(txt) then return ''.
    ok = self.syms.Lookup(txt, pS, tU, rf)
    if ~ok
      tU = upper(self.AssumeOf(txt))
      if tU then ok = true.
    end
    if ~ok then return ''.
    return clip(tU)
  end
  if dotP < 2 or dotP >= tLen then return ''.           ! dotted chain receiver (self.buf etc)
  head = upper(sub(txt, 1, dotP - 1))
  ok = self.syms.Lookup(head, pS, tU, rf)
  if ~ok
    tU = upper(self.AssumeOf(head))
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
! The dotted field at token pS - self.searchQ.Tok, Q.tok - is ONE character once subscripted:
! the head resolves as RecvClass resolves it, the segments before the last walk to the field's
! OWNER, and the registry answers for the last one (FieldOneChar). Loose mode answers no: it
! guesses types, and a guess is not a declaration read.
! ------------------------------------------------------------------------------------
VitMatch.DottedOneChar Procedure(LONG pS)
txt   STRING(vs:maxName),AUTO
head  STRING(vs:maxName),AUTO
segs  StringTheory
tU    STRING(vs:maxName)
rf    BYTE
dotP  long,auto
lastP long,auto
tLen  long,auto
  code
  if self.loose or self.syms &= NULL then return false.
  txt = self.TokText(pS)
  tLen = len(clip(txt))
  if ~tLen then return false.
  segs.setValue(txt[1 : tLen])
  dotP = segs.findByte(46)                                            ! the first <dot>
  lastP = tLen
  loop while lastP > dotP and txt[lastP] <> '.'                       ! and the last
    lastP -= 1
  end
  if dotP < 2 or lastP >= tLen or lastP = dotP + 1 then return false. ! no head, no field, or an empty segment between
  head = upper(txt[1 : dotP - 1])
  if ~self.syms.Lookup(head, pS, tU, rf)
    if ~self.syms.FindTypeDef(head) then return false.                ! a labelled structure instance
    tU = head
  end
  if lastP > dotP                                                     ! segments between the head and the field
    segs.setValue(txt[dotP + 1 : lastP - 1])
    segs.replaceByte(46, 124)                                         ! replace all <dot> with <pipe>
    tU = self.syms.LookupChain(tU, segs.getValue(), pS)
    if ~tU then return false.
  end
  return self.syms.FieldOneChar(tU, upper(txt[lastP + 1 : tLen]))

! ------------------------------------------------------------------------------------
! The implicit type of an identifier. SUFFIXED with " is an implicit STRING(32), with # an implicit LONG, with $ an
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
  of 34             ! "
    return 'STRING'
  of 35             ! #
    return 'LONG'
  of 36             ! $
    return 'REAL'
  end
  return ''

! ------------------------------------------------------------------------------------
! The type an ASSUME line gives a name the symbol table cannot place - unless the run has read a
! declaration of the name. A structure the author declared as an instance (`stack CLASS` in an
! INCLUDEd header) is one: its own label is its type, so no ASSUME answers for it. A name declared
! with a type in an INCLUDEd file the run read (`stLog MyLogST`) is another: it answers the type it
! is declared with (IncDeclType), and a declaration that cannot be read answers nothing. Nor does a name
! with a colon: a PRE-prefixed field is filed under that spelling and found before this, so one that reaches here
! is a structure's field spelled Struct:field, whose type is the field's, not the name pattern's.
! ------------------------------------------------------------------------------------
VitMatch.AssumeOf Procedure(STRING pName)
r   long,auto
aT  STRING(vs:maxName),AUTO
  code
  if instring(':', pName, 1, 1) then return ''.
  aT = self.rl.AssumeType(pName)
  if ~aT then return ''.
  if ~(self.syms &= NULL)
    r = self.syms.FindTypeDef(upper(pName))
    if r
      get(self.syms.types, r)
      if ~errorcode() and self.syms.types.isInst then return ''.
    end
    aT = self.syms.IncDeclType(upper(pName))
    if aT = vs:unknownType then return ''.
    if aT then return clip(aT).
    aT = self.rl.AssumeType(pName)
  end
  return clip(aT)

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
  ! so the rule HAS a WHERE - and the answer must be the SAFE direction. Returning true would
  ! let a rule fire with its guard never evaluated; every sibling defensive read in this class
  ! answers false. A guard we cannot evaluate has not passed.
  if self.rl.rules.guardQ &= NULL then return false.
  loop g = 1 to records(self.rl.rules.guardQ) ! WHERE is an AND-list - every clause must pass
    get(self.rl.rules.guardQ, g)
    if errorcode() then return false.
    if ~self.GuardOneOK() then return false.
  end
  return true

! ------------------------------------------------------------------------------------
! THE GUARD WALK - what an earlier test in the code proves about a name at a use site,
! for two WHERE guards: isOneChar (pKind 1: `size(w) = 1`, `len(w) = 1`) and isNonNull
! (pKind 2: `not w &= NULL`). Three places a guard can stand, all sound under Clarion's
! short-circuit AND/OR and its AND-over-OR precedence:
!
!   * IN THE SAME STATEMENT, before the use, joined to it by AND - `size(w) = 1 and
!     (val(w) = 10 or val(w) = 59)`. An OR after the guard at the guard's bracket depth or
!     shallower breaks it (`size(w) = 1 and a or val(w) = 10` evaluates val whatever size
!     said); one nested deeper does not. A NOT in front of the guard, or of a bracket group
!     holding it, breaks it, and so does a bracket group holding it that is a call's argument
!     list, a subscript or a property, or has an OR in it. When the use is past a THEN, the
!     guard must decide the whole condition, as a block header must. An ELSE, an ELSIF or a
!     '.' ends what the guard covers; so does a ';' unless the guard was the condition of an
!     IF whose THEN came first; and so does a ',' at the guard's depth or shallower - in
!     `choose(len(w) = 1, 0, val(w) = 59)` the third argument is read when the guard is false.
!   * AS THE HEADER OF A BLOCK THE STATEMENT IS IN - `if size(w) = 1` a line above - found by
!     walking back statement by statement, counting the blocks opened and closed on the way
!     (the tokenizer's level marks, so `x = 1.` closes a block as surely as END does). The
!     body runs only when the whole condition is true, so an OR anywhere in a bracket group
!     holding the guard - before it or after it - breaks it. A header whose ELSE or ELSIF
!     branch we are in proves nothing.
!   * AS A JUMP a statement above - `if w &= NULL then cycle.`, `if size(w) <> 1 then exit.`:
!     past it, the opposite holds. The test must decide the jump on its own - OR-joined at
!     every level, never AND or XOR - and the THEN a bare cycle/exit/return/break. The jump
!     must be in the same branch as the use: a jump in the IF branch above an ELSE, in an
!     earlier CASE arm or in another EXECUTE arm never ran before it.
!
! In all three the test must stand WHOLE as an operand of AND or OR: arithmetic, '&' and the
! comparisons bind tighter, so `len(w) = 1 + k`, `m + len(w) = 1` and `(len(w) = 1) = 0` test
! something else, and `Util.Len(w)` is a method, not the builtin (GuardEdges).
!
! AND NOTHING IN BETWEEN MAY HAVE CHANGED THE NAME: from the guard down to the use, no
! statement may assign it or an ancestor of it (`w = `, `w[2] = `, `self.tk.tokens = `,
! wherever the statement starts - after THEN, after ELSE, after a ';'), hand it or an
! ancestor whole to a call that is not a plain read (`get(self.tk.tokens, j)`, `Foo(w)`
! taking it by address), or DO a routine, which shares the procedure's data. Nor may it CALL
! anything but a builtin that only reads, whatever the name is: a procedure can write any
! global or module variable, a method of a class the procedure declares shares its data as
! a routine does, and a call handed the name earlier may have kept a reference to it -
! `Fill()`, `Hlp.Load()`, `self.Drop()`, or a procedure called by its name alone (CallAt).
! When the use is inside a LOOP and the guard is outside it, the rest of the loop body, and
! the UNTIL or WHILE condition that closes it, run again before the use on the next pass, so
! they must not change the name either. An ACCEPT loop with the guard outside it proves
! nothing at all: between its passes the runtime writes what the user typed into every USE
! variable. A statement that only READS the name or a sibling field is fine. And once the
! guard is found, the name must not be one that can be written under another name the walk
! does not read (GuardAliased). Anything the walk cannot read stops it with a no: a missed
! rewrite costs nothing, a wrong one is a bug in someone's program.
! A LABEL IN COLUMN 1 is a place a GOTO can land, past every test above it. A label line
! between the guard and the use ends the walk; a label on the use's OWN line leaves only a
! guard in the use's own statement, which runs after the GOTO lands. An INCLUDE between the
! two splices in text the walk cannot read, and a '?' in column 1 starts a statement that a
! debug build runs - `? w = ';ab'` assigns w there, it does not compare it.
! ------------------------------------------------------------------------------------
VitMatch.GuardWalk Procedure(LONG pS, STRING pNameU, BYTE pKind)
gwS      long,auto ! first token of the statement being looked at
gwE      long,auto ! the EOL token that ends it (exclusive end)
gwU      long,auto ! first token of the statement the use is in
gwT      long,auto ! the last token of a header's condition
gwN      long,auto ! the blocks the statement opens, less the blocks it closes
gwDep    long,auto ! blocks closed on the way back
gwSkip   byte,auto ! the lines above, up to the next header, are another branch or arm
gwJump   byte,auto ! a jump guard stands in the block the walk is in; its header says whether it ran
gwHd     StringTheory
  code
  ! ---- the statement the use is in ----
  gwS = pS
  loop
    if gwS <= 1 then break.
    if self.TokIsEOL(gwS - 1) then break.
    gwS -= 1
  end
  gwU = gwS
  if self.StmtTouches(gwS, pS - 1, pNameU) then return false.                ! changed on the use's own line, before the use
  if self.CondGuards(gwS, pS - 1, pNameU, pKind, 2) then return true.
  if self.IsColOneStart(gwS) then return false.                              ! a GOTO can land on the use's own line, past every guard above
  ! ---- then back, statement by statement ----
  gwDep = 0 ; gwSkip = 0 ; gwJump = 0
  loop
    if gwS <= 2 then break.
    gwE = gwS - 1                                                            ! the EOL ending the previous statement
    gwS = gwE
    loop
      if gwS <= 1 then break.
      if self.TokIsEOL(gwS - 1) then break.
      gwS -= 1
    end
    if gwS >= gwE then cycle.                                                ! a blank line
    if self.IsColOneStart(gwS) then break.                                   ! a ROUTINE, a label, a declaration: out of the body
    if ~gwJump and self.StmtTouches(gwS, gwE - 1, pNameU) then return false. ! the name may have changed since - no guard survives that
    gwN = self.LevelNet(gwS, gwE - 1)
    gwHd.setValue(upper(self.TokText(gwS)))
    if gwN < 0                                                               ! END, or a statement ending in '.': a block closed on the way
      gwDep -= gwN
      cycle
    end
    if gwN > 0
      if gwDep >= gwN
        gwDep -= gwN                                                         ! the header of a block closed on the way
        cycle
      end
      if gwDep or gwN > 1 then return false.                                 ! not a shape the walk reads
      case gwHd.getValue()                                                   ! the header of the block the walk is in
      of 'IF'
        if gwJump then return true.
        if gwSkip
          gwSkip = 0                                                         ! we are in its ELSE or ELSIF branch
          cycle
        end
        gwT = self.ThenAtTop(gwS + 1, gwE - 1)                               ! `if c then` with its block on the lines below
        if gwT
          gwT -= 1
        else
          gwT = gwE - 1
        end
        if self.CondGuards(gwS + 1, gwT, pNameU, pKind, 1) then return true.
      of 'LOOP'
        if gwJump then return true.                                          ! the jump is inside the loop and runs on every pass
        if self.LoopTouches(gwS, gwU, pNameU) then return false.             ! the next pass runs the rest of the body before the use
      of 'ACCEPT'
        if gwJump then return true.
        return false                                                         ! between passes the runtime writes every USE variable
      of 'CASE'
        if gwJump then return true.
        gwSkip = 0
      of 'BEGIN'
        if gwJump then return true.
        gwSkip = 1                                                           ! a BEGIN block is an EXECUTE arm: the lines above are the other arms
      of 'EXECUTE'
        if gwJump and ~gwSkip then return false.                             ! the jump was another arm
        if gwJump then return true.
        gwSkip = 0
      else
        return false
      end
      cycle
    end
    if gwDep then cycle.                                                     ! inside a block closed on the way
    case gwHd.getValue()
    of 'ELSE' orof 'ELSIF' orof 'OF' orof 'OROF'
      gwSkip = 1
    of 'IF'
      if ~gwJump and ~gwSkip and self.IsJumpGuard(gwS, gwE - 1, pNameU, pKind) then gwJump = 1.
    end
  end
  return gwJump

! ------------------------------------------------------------------------------------
! the guard walk proves pKind of pNameU at the use pS, and the name is not one that can be
! written under another name the walk does not read
! ------------------------------------------------------------------------------------
VitMatch.GuardProved Procedure(LONG pS, STRING pNameU, BYTE pKind)
  code
  if ~self.GuardWalk(pS, pNameU, pKind) then return false.
  return choose(~self.GuardAliased(pS, pNameU, pKind))

! ------------------------------------------------------------------------------------
! can pNameU be written under ANOTHER name, so that a statement the walk reads as leaving
! it alone changes it after all? 1 = it can, and no guard proves anything about it:
!   * a field with a prefix (`Cus:Name`, `Que:Tok`): its record, queue or group is assigned,
!     cleared or read into WHOLE under its own label;
!   * a by-address parameter (`*STRING p`, the whole-string test only): it IS the caller's
!     variable, which may be a global this procedure assigns by its own name;
!   * a variable declared OVER another, or one another declaration lays OVER;
!   * a string a reference is pointed at (`ref &= w`, the whole-string test only - a write
!     through `ref` is a write to w), or one whose ADDRESS is taken.
! The whole file is searched, not only the procedure: a same-named variable elsewhere costs
! a rewrite, which is the safe direction.
! ------------------------------------------------------------------------------------
VitMatch.GuardAliased Procedure(LONG pS, STRING pNameU, BYTE pKind)
gaI    long,auto
gaDecl byte
gaC    STRING(1),auto
gaW    StringTheory
  code
  gaW.setValue(pNameU)
  if gaW.containsByte(58) then return true.
  if pKind = 1 and self.ByAddressParam(pS, pNameU) then return true.
  loop gaI = 1 to self.tk.records()
    get(self.tk.tokens, gaI)
    if errorcode() then return true.
    if self.tk.tokens.tok &= NULL then cycle.
    if self.tk.tokens.tok = '<10>'
      gaDecl = 0
      cycle
    end
    if self.tk.tokens.firstOnLine and self.tk.tokens.strBefore &= NULL
      gaDecl = choose(upper(self.tk.tokens.tok) = pNameU)
    end
    gaC = upper(self.tk.tokens.tok[1])
    case val(gaC)
    of 38 ! '&'
      if self.tk.tokens.tok = '&=' and pKind = 1
        if upper(self.TokText(gaI + 1)) = pNameU then return true.
        if self.TokText(gaI + 1) = '(' and upper(self.TokText(gaI + 2)) = pNameU then return true.
      end
    of 79 ! 'O'
      if upper(self.tk.tokens.tok) = 'OVER'
        if gaDecl or upper(self.TokText(gaI + 2)) = pNameU then return true.
      end
    of 65 ! 'A'
      if upper(self.tk.tokens.tok) = 'ADDRESS'
        if upper(self.TokText(gaI + 2)) = pNameU then return true.
      end
    end
  end
  return false

! ------------------------------------------------------------------------------------
! is pNameU a parameter of the procedure or method around pS that is passed by address -
! `*STRING p`, `<*CSTRING p>`, `CONST *CSTRING p` on its header line? 1 = it is.
! ------------------------------------------------------------------------------------
VitMatch.ByAddressParam Procedure(LONG pS, STRING pNameU)
bpSc  long,auto
bpI   long,auto
bpT   StringTheory
  code
  if self.syms &= NULL then return true.
  bpSc = self.syms.ScopeContaining(pS, vs:scProc, vs:scMethod)
  if ~bpSc then return false.
  get(self.syms.scopes, bpSc)
  if errorcode() then return true.
  loop bpI = self.syms.scopes.startTok + 1 to self.tk.records()
    if self.TokIsEOL(bpI) then break.
    if upper(self.TokText(bpI)) <> pNameU then cycle.
    if self.TokText(bpI - 2) = '*' then return true.
    bpT.setValue(self.TokText(bpI - 1))
    if bpT._DataEnd and bpT.valuePtr[1] = '*' then return true.
    break
  end
  return false

! ------------------------------------------------------------------------------------
! the blocks the tokens pS..pE open, less the blocks they close, from the tokenizer's level
! marks: IF, LOOP, CASE, EXECUTE, BEGIN and ACCEPT open; END, a '.' terminator and the
! UNTIL or WHILE that ends a LOOP close. A one-line IF opens and closes: 0.
! ------------------------------------------------------------------------------------
VitMatch.LevelNet Procedure(LONG pS, LONG pE)
lnI   long,auto
lnN   long
  code
  loop lnI = pS to pE
    get(self.tk.tokens, lnI)
    if errorcode() then cycle.
    case self.tk.tokens.level
    of '+'
      lnN += 1
    of '-'
      lnN -= 1
    end
  end
  return lnN

! ------------------------------------------------------------------------------------
! could the next pass of the LOOP whose header is at pHead change pNameU before the use?
! The body from the use's statement pFrom down to the loop's END runs again first. A loop
! closed by UNTIL or WHILE tests its condition before that pass too, so the walk reads to
! the end of the closing STATEMENT, not to its first word: `until Next(w)` may change w.
! ------------------------------------------------------------------------------------
VitMatch.LoopTouches Procedure(LONG pHead, LONG pFrom, STRING pNameU)
ltE   long,auto
  code
  get(self.tk.tokens, pHead)
  if errorcode() then return true.
  ltE = self.tk.MatchLevel()
  if ltE <= pFrom then return true. ! no END found: what the next pass does is unknown
  loop
    if self.TokIsEOL(ltE + 1) then break.
    ltE += 1
  end
  return self.StmtTouches(pFrom, ltE, pNameU)

! ------------------------------------------------------------------------------------
! does the condition in pS..pE prove the guard for pNameU? pMode says where it stands:
!   2 - the statement the use is in, up to the use: the guard must be joined to the use by
!       AND. An ELSE, ELSIF, END or '.' ends what it covers, and a ';' does too unless a
!       THEN came between; past a THEN it must decide the whole condition, as in mode 1.
!   1 - a block header: the body runs whenever the whole condition is true, so no OR may
!       stand in a bracket group holding the guard, before it or after it.
!   0 - a jump's condition: the test is `size(w) <> 1` / `w &= NULL`, and no AND or XOR
!       may stand in a bracket group holding it.
! A NOT (or ~) in front of the test, or of a bracket group holding it, refuses; so does a
! bracket group holding it that is a call's argument list - `foo(size(w) = 1)` tests
! nothing about w - or a subscript or a property: '[' and '{' count as brackets too. A ','
! at the guard's depth or shallower ends what it covers, as a ';' does: what follows it is
! another argument. And the test, or a bracket group holding it as that group closes, must
! stand whole between its neighbours (GuardEdges).
! ------------------------------------------------------------------------------------
VitMatch.CondGuards Procedure(LONG pS, LONG pE, STRING pNameU, BYTE pKind, BYTE pMode)
cgI     long,auto
cgK     long,auto
cgDep   long
cgG     long,auto    ! depth of the innermost bracket group holding the guard, -1 = no guard (yet, or any more)
cgHit   byte
cgNew   byte         ! the token just read is the guard
cgPre   byte         ! an OR stood before the guard in a group holding it (mode 2)
cgThen  byte         ! a THEN at depth 0 since the guard (mode 2)
cgBrk   byte,dim(32) ! element n: the open group at depth n - 1 holds an OR (modes 1 and 2) or an AND or XOR (mode 0)
cgOpen  long,dim(32) ! element n: the '(' that opened the group at depth n - 1
tk      StringTheory
  code
  cgG = -1
  loop cgI = pS to pE
    tk.setValue(self.TokText(cgI))
    if ~tk._DataEnd then cycle.
    if tk._DataEnd = 1
      case val(tk.valuePtr[1])
      of 40 orof 91 orof 123                                              ! '(' '[' '{'
        if cgDep >= 31 then return false.                                 ! nested deeper than the walk reads
        cgDep += 1
        cgBrk[cgDep + 1] = 0
        cgOpen[cgDep + 1] = cgI
        cycle
      of 41 orof 93 orof 125                                              ! ')' ']' '}'
        if cgDep <= 0 then return false.                                  ! more closes than opens: not a range the walk reads
        if cgG = cgDep                                                    ! the group holding the guard closes: the guard now stands for
          if cgBrk[cgDep + 1] or self.IsCallOpen(cgOpen[cgDep + 1], pS) or self.NegatedAt(cgOpen[cgDep + 1], pS) or ~self.GroupWhole(cgOpen[cgDep + 1], cgI, pS, pE)
            cgG = -1                                                      !   the group, unless it is a subscript or a property, has an OR
            cgHit = 0                                                     !   in it, is a call's argument list, or has a NOT or an operator beside it
          else
            cgG -= 1
          end
        end
        cgDep -= 1
        cycle
      end
    end
    case upper(tk.getValue())
    of 'OR'   orof 'OROF'  orof 'XOR'
      if pMode or upper(tk.getValue()) = 'XOR'                            ! a jump's test may be OR-joined, never XOR-joined
        if cgG >= 0 and cgDep <= cgG
          cgG = -1                                                        ! the guard no longer covers what follows
          cgHit = 0
        end
        cgBrk[cgDep + 1] = 1
      end
    of 'AND'
      if ~pMode
        if cgG >= 0 and cgDep <= cgG
          cgG = -1                                                        ! a jump that needs something else too
          cgHit = 0
        end
        cgBrk[cgDep + 1] = 1
      end
    of 'THEN'
      if pMode = 2 and ~cgDep and cgG >= 0
        if cgPre
          cgG = -1                                                        ! past the THEN the guard must decide the whole condition
          cgHit = 0
        else
          cgThen = 1
        end
      end
    of 'ELSE' orof 'ELSIF' orof 'END' orof '.'
      if pMode = 2 and ~cgDep and ~self.IsMemberDot(cgI)
        cgG = -1                                                          ! the branch or the statement the guard held for is over
        cgHit = 0
      end
    of ';'
      if pMode = 2 and ~cgDep and ~cgThen
        cgG = -1                                                          ! a guard that is not an IF's condition holds only to its ';'
        cgHit = 0
      end
    of ','
      if cgG >= 0 and cgDep <= cgG
        cgG = -1
        cgHit = 0
      end
    of 'SIZE' orof 'LEN'
      if pKind <> 1 or cgG >= 0 then cycle.
      if self.ocLenOnly and upper(self.TokText(cgI)) = 'SIZE' then cycle.
      if cgI + 5 > pE then cycle.
      if self.TokText(cgI + 1) <> '(' or upper(self.TokText(cgI + 2)) <> pNameU or self.TokText(cgI + 3) <> ')' then cycle.
      if self.TokText(cgI + 5) <> '1' then cycle.
      if pMode and self.TokText(cgI + 4) <> '=' then cycle.
      if ~pMode and self.TokText(cgI + 4) <> '<<>' and self.TokText(cgI + 4) <> '~=' then cycle.
      if self.NegatedAt(cgI, pS) then return false.
      if ~self.GuardEdges(cgI - 1, cgI + 6, pS, pE) then cycle.
      cgNew = 1
    else
      if pKind <> 2 or cgG >= 0 then cycle.
      if upper(tk.getValue()) <> pNameU then cycle.
      if cgI + 2 > pE then cycle.
      if self.TokText(cgI + 1) <> '&=' or upper(self.TokText(cgI + 2)) <> 'NULL' then cycle.
      if pMode
        if cgI <= pS or upper(self.TokText(cgI - 1)) <> 'NOT' then cycle. ! the block form is `not w &= NULL`
        if self.NegatedAt(cgI - 1, pS) then return false.
        if ~self.GuardEdges(cgI - 2, cgI + 3, pS, pE) then cycle.
      else
        if self.NegatedAt(cgI, pS) then return false.                     ! the jump form is `w &= NULL`
        if ~self.GuardEdges(cgI - 1, cgI + 3, pS, pE) then cycle.         ! and it stands whole: no operator beside it
      end
      cgNew = 1
    end
    if cgNew
      cgNew = 0
      cgPre = 0
      loop cgK = 1 to cgDep + 1
        if cgBrk[cgK] then cgPre = 1.
      end
      if cgPre and pMode <> 2 then return false.                          ! a header or a jump: the test alone does not decide
      cgG = cgDep
      cgHit = 1
      cgThen = 0
    end
  end
  return cgHit

! ------------------------------------------------------------------------------------
! is the token at pIx negated - a NOT or ~ right before it, or right before the '(' that
! opens the group it starts?
! ------------------------------------------------------------------------------------
VitMatch.NegatedAt Procedure(LONG pIx, LONG pS)
! #Removed as not used: nt  StringTheory
  code
  if pIx <= pS then return false.
  case upper(self.TokText(pIx - 1))
  of '~' orof 'NOT'
    return true
  of '('
    if pIx - 1 > pS
      case upper(self.TokText(pIx - 2))
      of '~' orof 'NOT'
        return true
      end
    end
  end
  return false

! ------------------------------------------------------------------------------------
! does a guard test - or the bracket group holding one - stand WHOLE as an operand of AND
! or OR? pB is the token in front of it and pA the token after it; outside pS..pE is the
! start or the end of the condition, which is fine. Arithmetic, '&' and the comparisons
! bind tighter than AND and OR, so `len(w) = 1 + k`, `m + len(w) = 1` and `(len(w) = 1) = 0`
! compare something else; and in `Util.Len(w)` the name is a method of the program, not the
! builtin. In front: '(' ',' AND OR XOR IF ELSIF WHILE UNTIL. After: ')' AND OR XOR THEN.
! ------------------------------------------------------------------------------------
VitMatch.GuardEdges Procedure(LONG pB, LONG pA, LONG pS, LONG pE)
  code
  if pB >= pS
    case upper(self.TokText(pB))
    of '(' orof ',' orof 'AND' orof 'OR' orof 'XOR' orof 'IF' orof 'ELSIF' orof 'WHILE' orof 'UNTIL'
    else
      return false
    end
  end
  if pA <= pE
    case upper(self.TokText(pA))
    of ')' orof 'AND' orof 'OR' orof 'XOR' orof 'THEN'
    else
      return false
    end
  end
  return true

! ------------------------------------------------------------------------------------
! the bracket group from pO to pC holds the guard: is it a round bracket that only groups,
! standing whole between its neighbours? A subscript `x[...]` or a property `x{...}`
! holding the guard tests nothing about the name.
! ------------------------------------------------------------------------------------
VitMatch.GroupWhole Procedure(LONG pO, LONG pC, LONG pS, LONG pE)
  code
  if self.TokText(pO) <> '(' or self.TokText(pC) <> ')' then return false.
  return self.GuardEdges(pO - 1, pC + 1, pS, pE)

! ------------------------------------------------------------------------------------
! is the '(' at pIx the start of a call's argument list - `foo(`, `self.Bar(` - rather than
! a bracket that groups? A name in front of it says call; an operator, a bracket, a comma
! or a keyword that takes an expression says group.
! ------------------------------------------------------------------------------------
VitMatch.IsCallOpen Procedure(LONG pIx, LONG pS)
icT   StringTheory
  code
  if pIx <= pS then return false.
  icT.setValue(upper(self.TokText(pIx - 1)))
  if ~icT._DataEnd then return false.
  case val(icT.valuePtr[1])
  of 65 to 90 orof 95 ! 'A' to 'Z' orof '_'
  else
    return false
  end
  case icT.getValue()
  of   'IF'     orof 'ELSIF' orof 'AND' orof 'OR'   orof 'XOR'  orof 'NOT'  orof 'WHILE'   orof 'UNTIL'
  orof 'RETURN' orof 'CASE'  orof 'OF'  orof 'OROF' orof 'THEN' orof 'ELSE' orof 'EXECUTE' orof 'TO'    orof 'BY'
    return false
  end
  return true

! ------------------------------------------------------------------------------------
! is the token at pIx inside an expression, so that an `=` after it compares and an `&=`
! tests a reference? After an operator, a bracket, a comma, or a keyword that takes an
! expression, yes. At the start of a line, after a ';', THEN or ELSE, after the column-1
! '?' that marks a debug statement, or after anything else, a statement can start there,
! and `w = ` is an assignment.
! ------------------------------------------------------------------------------------
VitMatch.ExprBefore Procedure(LONG pIx)
ebT   StringTheory
  code
  if pIx <= 1 then return false.
  if self.TokIsEOL(pIx - 1) then return false.
  ebT.setValue(upper(self.TokText(pIx - 1)))
  if ~ebT._DataEnd then return false.
  case val(ebT.valuePtr[1])
  of 65 to 90 orof 95 orof 48 to 57 orof 39 ! 'A' to 'Z' orof '_' orof '0' to '9' orof <single quote>
    case ebT.getValue()
    of   'IF'     orof 'ELSIF' orof 'WHILE' orof 'UNTIL' orof 'AND'     orof 'OR' orof 'XOR' orof 'NOT'
    orof 'RETURN' orof 'CASE'  orof 'OF'    orof 'OROF'  orof 'EXECUTE' orof 'TO' orof 'BY'
      return true
    end
    return false
  of 59 orof 46 orof 124 orof 63            ! <semi-colon> orof <dot> orof '|' orof '?'
    return false
  end
  return true

! ------------------------------------------------------------------------------------
! the '(' of the bracket the token at pIx stands in, looking no further back than pS;
! 0 = none
! ------------------------------------------------------------------------------------
VitMatch.OpenBefore Procedure(LONG pIx, LONG pS)
obI   long,auto
obDep long
  code
  loop obI = pIx - 1 to pS by -1
    case self.TokText(obI)
    of ')'
      obDep += 1
    of '('
      if ~obDep then return obI.
      obDep -= 1
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! a builtin that only reads what it is handed and writes no variable of the program, so
! handing it the name, or calling it between the guard and the use, changes nothing. The
! name alone is not proof: BuiltinReadAt also asks that the call is not a method and not
! a procedure of the file's own MAP.
! ------------------------------------------------------------------------------------
VitMatch.ReadOnlyCall Procedure(STRING pU)
  code
  case pU
  of   'SIZE'     orof 'LEN'       orof 'VAL'     orof 'CLIP'     orof 'SUB'     orof 'UPPER'   orof 'LOWER'
  orof 'LEFT'     orof 'RIGHT'     orof 'CENTER'  orof 'INSTRING' orof 'STRPOS'  orof 'MATCH'   orof 'NUMERIC'
  orof 'CHR'      orof 'ALL'       orof 'FORMAT'  orof 'DEFORMAT' orof 'INLIST'  orof 'CHOOSE'  orof 'INT'
  orof 'ABS'      orof 'RECORDS'   orof 'POINTER' orof 'OMITTED'  orof 'INRANGE' orof 'ISALPHA' orof 'ISUPPER'
  orof 'ISLOWER'  orof 'EVENT'     orof 'FIELD'   orof 'FOCUS'    orof 'KEYCODE' orof 'CHOICE'  orof 'ERROR'
  orof 'TODAY'    orof 'CLOCK'     orof 'BAND'    orof 'BOR'      orof 'BXOR'    orof 'BSHIFT'  orof 'ACCEPTED'
  orof 'SELECTED' orof 'ERRORCODE'
    return true
  end
  return false

! ------------------------------------------------------------------------------------
! a single-line `if <cond> then <jump>.` whose condition proves the guard by jumping away
! when it FAILS: `if w &= NULL then cycle.`, `if size(w) <> 1 then exit.`
! ------------------------------------------------------------------------------------
VitMatch.IsJumpGuard Procedure(LONG pS, LONG pE, STRING pNameU, BYTE pKind)
jgT   long,auto
! #Removed as not used: jt    StringTheory
  code
  jgT = self.ThenAtTop(pS + 1, pE)
  if ~jgT then return false.
  case upper(self.TokText(jgT + 1))
  of 'CYCLE' orof 'EXIT' orof 'RETURN' orof 'BREAK'
  else
    return false
  end
  return self.CondGuards(pS + 1, jgT - 1, pNameU, pKind, 0)

! ------------------------------------------------------------------------------------
! the THEN at bracket depth 0 in pS..pE, 0 = none (a block IF has no THEN)
! ------------------------------------------------------------------------------------
VitMatch.ThenAtTop Procedure(LONG pS, LONG pE)
ttI   long,auto
ttDep long
tt    StringTheory
  code
  loop ttI = pS to pE
    tt.setValue(self.TokText(ttI))
    if tt._DataEnd = 1
      if tt.valuePtr[1] = '(' then ttDep += 1.
      if tt.valuePtr[1] = ')' then ttDep -= 1.
    end
    if ~ttDep and upper(tt.getValue()) = 'THEN' then return ttI.
  end
  return 0

VitMatch.HasThenAtTop Procedure(LONG pS, LONG pE)
  code
  return choose(self.ThenAtTop(pS, pE) <> 0)

! ------------------------------------------------------------------------------------
! could the tokens pS..pE have changed pNameU? An assignment to it or to an ancestor
! (`w = `, `w[2] = `, `self.tk.tokens = `) where a statement starts; a compound or deep
! assignment anywhere; the name or an ancestor handed whole to a call that is not a plain
! read (`free(w)`, `get(self.tk.tokens, j)`, `Foo(w)`); a method called on it or on an
! ancestor (`self.Drop(`, which the tokenizer leaves as `self` `.` `Drop` `(`); a DO; and
! ANY call that is not a builtin that only reads (CallAt). A dotted name is written through
! the same field of another object too, which may be the same object under another name
! (`o &= self`, then `o.buf &= NULL`). Reads, and sibling fields, are fine.
! ------------------------------------------------------------------------------------
VitMatch.StmtTouches Procedure(LONG pS, LONG pE, STRING pNameU)
stI    long,auto
stL    long,auto
stN    long,auto ! the token after the name, past a subscript or a slice
stD    long,auto
stO    long,auto
nm     StringTheory
tk     StringTheory
nx     StringTheory
pv     StringTheory
  code
  nm.setValue(pNameU)
  loop stI = pS to pE
    tk.setValue(upper(self.TokText(stI)))
    if ~tk._DataEnd then cycle.
    if tk.getValue() = 'DO' then return true.                                 ! a ROUTINE shares the procedure's data and may assign the name
    if tk.getValue() = 'INCLUDE' then return true.                            ! an included file is code the walk cannot read
    if self.CallAt(stI, pS, pE) then return true.
    if tk.getValue() <> pNameU and ~self.SameField(tk.getValue(), pNameU)
      ! an ancestor: the name up to one of its dots
      stL = tk._DataEnd
      if stL >= nm._DataEnd then cycle.
      if nm.valuePtr[1 : stL] <> tk.getValue() or nm.valuePtr[stL + 1] <> '.' then cycle.
    end
    stN = stI + 1
    if self.TokText(stN) = '['
      stD = 0
      loop stN = stI + 1 to pE
        case self.TokText(stN)
        of '['
          stD += 1
        of ']'
          stD -= 1
          if ~stD then break.
        end
      end
      if stD then return true.                                                ! a subscript the walk cannot read to its end
      stN += 1
    end
    nx.setValue(self.TokText(stN))
    pv.setValue(self.TokText(stI - 1))
    case nx.getValue()
    of ':=:' orof '+=' orof '-=' orof '*=' orof '/=' orof '^=' orof '%='      ! deep and compound assignment
      return true
    of '='   orof '&='                                                        ! plain and reference assignment where a statement starts;
      if ~self.ExprBefore(stI) then return true.                              !   in an expression `=` compares and `&=` tests a reference
    end
    if (pv.getValue() = '(' or pv.getValue() = ',') and (nx.getValue() = ')' or nx.getValue() = ',')
      stO = self.OpenBefore(stI, pS)                                          ! handed whole to a call: DISPOSE, FREE, CLEAR, a queue verb,
      if stO and self.IsCallOpen(stO, pS)                                     !   a procedure taking it by address
        if ~self.BuiltinReadAt(stO) then return true.
      end
    end
    if self.IsMemberDot(stN) then return true.                                ! a method called on it or an ancestor: `self.Drop(` is split at the '.'
  end
  return false

! ------------------------------------------------------------------------------------
! does the token at pIx CALL something other than a builtin that only reads? Between the
! guard and the use any call stops the walk, whatever the name is: a procedure can write
! any global or module variable, a method of a class the procedure declares shares its
! data as a routine does, and a procedure handed the name earlier may have kept a reference
! to it. A call is
!   * a name and '(' - `Fill()`, `Hlp.Load()`, `self.Drop()` - unless its ')' lies past pE:
!     a call whose argument list holds the use runs after its arguments are read;
!   * a name alone as a statement - Clarion calls a procedure by its name alone too;
!   * a name in an expression that is not provably DATA (NameIsData): a procedure called
!     without brackets reads exactly like a variable;
!   * a statement that sets a property (`?w{PROP:ScreenText} = `), which may move a value
!     into a USE variable.
! TRUE and FALSE are the standard equates and are read as data.
! ------------------------------------------------------------------------------------
VitMatch.CallAt Procedure(LONG pIx, LONG pS, LONG pE)
caD   long,auto
caK   long,auto
caT   StringTheory
  code
  caT.setValue(self.TokText(pIx))
  if ~caT._DataEnd then return false.
  if caT.getValue() = '('
    if ~self.IsCallOpen(pIx, pS) or self.BuiltinReadAt(pIx) then return false.
    caD = 0
    loop caK = pIx to pE
      case self.TokText(caK)
      of '('
        caD += 1
      of ')'
        caD -= 1
        if ~caD then return true.
      end
    end
    return false
  end
  if ~self.ExprBefore(pIx)
    if self.TokText(pIx + 1) = '{{' then return true.
    return choose(self.TokType(pIx) = vt:label and self.IsStmtEndAfter(pIx))
  end
  if self.TokType(pIx) <> vt:label then return false.
  if self.TokText(pIx + 1) = '(' or self.IsMemberDot(pIx + 1) then return false.
  case upper(caT.getValue())
  of 'TRUE' orof 'FALSE'
    return false
  end
  return choose(~self.NameIsData(pIx))

! ------------------------------------------------------------------------------------
! does the name at pIx provably read DATA? A plain name must resolve in the symbol table,
! be an implicit variable, have a type the rule file assumes for it, or be a structure the
! registry knows; a dotted name must resolve hop by hop to a FIELD - a method called without
! brackets does not. A StringTheory's own _DataEnd and valuePtr are fields, its header read or not. A name that does not resolve is not data: it may be a procedure
! declared in an INCLUDE this run did not read.
! ------------------------------------------------------------------------------------
VitMatch.NameIsData Procedure(LONG pIx)
ndD   long,auto
ndR   BYTE
ndU   STRING(vs:maxName)
ndT   StringTheory
ndS   StringTheory
  code
  if self.syms &= NULL then return false.
  ndT.setValue(self.TokText(pIx))
  if ~ndT._DataEnd then return false.
  ndD = ndT.findByte(46)
  if ~ndD
    if self.syms.Lookup(ndT.getValue(), pIx, ndU, ndR) then return true.
    if self.ImplicitType(ndT.getValue()) then return true.
    if self.rl.AssumeType(ndT.getValue()) then return true.
    if self.syms.FindTypeDef(upper(ndT.getValue())) then return true.
    return false
  end
  if ndD < 2 or ndD >= ndT._DataEnd then return false.
  ndS.setValue(upper(ndT.valuePtr[1 : ndD - 1]))
  if ~self.syms.Lookup(ndS.getValue(), pIx, ndU, ndR)
    ndU = upper(self.AssumeOf(ndS.getValue()))
    if ~ndU
      if ~self.syms.FindTypeDef(ndS.getValue()) then return false.
      ndU = ndS.getValue()
    end
  end
  ndS.setValue(upper(ndT.valuePtr[ndD + 1 : ndT._DataEnd]))
  if upper(ndU) = 'STRINGTHEORY' and inlist(ndS.getValue(), '_DATAEND', 'VALUEPTR') then return true. ! its own fields
  ndS.replaceByte(46, 124)
  if self.syms.LookupChain(ndU, ndS.getValue(), pIx) then return true.
  return false

! ------------------------------------------------------------------------------------
! is the '(' at pOpen the argument list of a builtin that only reads what it is handed?
! The name in front must be one ReadOnlyCall knows, with no member '.' before it - in
! `Util.Len(` and `st.Clip(` it names a method of the program, which may do anything - and
! the file's MAP must not prototype a procedure of that name, which would be called instead.
! ------------------------------------------------------------------------------------
VitMatch.BuiltinReadAt Procedure(LONG pOpen)
brU   StringTheory
  code
  if pOpen <= 1 then return false.
  brU.setValue(upper(self.TokText(pOpen - 1)))
  if ~self.ReadOnlyCall(brU.getValue()) then return false.
  if pOpen > 2 and self.TokText(pOpen - 2) = '.' then return false.
  if self.syms &= NULL then return true.
  if self.syms.MapProtoCount(brU.getValue()) then return false.
  return true

! ------------------------------------------------------------------------------------
! do two dotted names end in the same field - `o.buf` and `self.buf`? Another object of the
! same class may be the same object under another name (`o &= self`), so a write to the one
! is treated as a write to the other.
! ------------------------------------------------------------------------------------
VitMatch.SameField Procedure(STRING pTokU, STRING pNameU)
sfI   long,auto
sfT   long
sfN   long
sfA   StringTheory
sfB   StringTheory
  code
  sfA.setValue(pTokU)
  sfB.setValue(pNameU)
  loop sfI = sfA._DataEnd - 1 to 2 by -1
    if sfA.valuePtr[sfI] = '.' then sfT = sfI ; break.
  end
  loop sfI = sfB._DataEnd - 1 to 2 by -1
    if sfB.valuePtr[sfI] = '.' then sfN = sfI ; break.
  end
  if ~sfT or ~sfN then return false.
  return choose(sfA.valuePtr[sfT + 1 : sfA._DataEnd] = sfB.valuePtr[sfN + 1 : sfB._DataEnd])

! ------------------------------------------------------------------------------------
! a column-1 start: a label line - a ROUTINE, a PROCEDURE, a declaration - the walk has
! left the body it started in
! ------------------------------------------------------------------------------------
VitMatch.IsColOneStart Procedure(LONG pIx)
  code
  get(self.tk.tokens, pIx)
  if errorcode() then return true.
  if ~self.tk.tokens.firstOnLine then return false.
  if not self.tk.tokens.strBefore &= NULL then return false.
  return self.rl.IsLabelToken(self.TokText(pIx))

! ------------------------------------------------------------------------------------
! One WHERE clause - the LOADED rules.guardQ buffer row - against the current binds.
! A compare guard renders the bound span, folds it (fold(), and a bare metavar folds
! too), unquotes a literal result and compares it, trailing-space-blind, against the
! stored guard value (NULL = ''). A class test asks the binding its is*() question -
! the vr:ct* tests of VitRules.inc, from isConst (folds to an integer) to isNonNull
! (proved by an earlier test in the code: the guard walk above).
! ------------------------------------------------------------------------------------
VitMatch.GuardOneOK Procedure()
b      long,auto
eq     long,auto
txt    StringTheory
val    StringTheory
tU     STRING(vs:maxName)
rf     BYTE
prv    StringTheory ! the token before a '(' - a name there makes it a CALL
! #Removed as not used: cf     STRING(1)    !   its last character, which is what decides that
wasLit BYTE         ! the bound metavar text was a quoted LITERAL (case-sensitive) rather than an identifier/EXPR (caseless)
lv     StringTheory ! a quoted literal's value, for the compare guard
ocDep  long,auto    ! isOneChar: bracket depth walking back through a slice
ocK    long,auto    ! isOneChar: the slice's opening bracket
cnX    long,auto    ! isCaseNeutral: a character of the token
kn     BYTE         ! returnsValue: 1 when the procedure's prototype was read
  code
  b = self.FindBind(self.rl.rules.guardQ.mvx)
  if ~b then return false.                                                             ! lint guarantees presence; defensive
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
      txt.setValue(self.FoldSafe(txt.getValue()))
      if self.IsAllDigits(txt.getValue()) then return true.
      return false
    of vr:ctVar
      if self.binds.sPos <> self.binds.ePos then return false.
      if ~self.rl.IsLabelToken(self.TokText(self.binds.sPos)) then return false.
      if self.syms &= NULL then return true.                                           ! no table: any identifier counts as a var
      if self.syms.Lookup(self.TokText(self.binds.sPos), self.binds.sPos, tU, rf) then return true.
      if self.rl.AssumeType(self.TokText(self.binds.sPos)) then return true.
      return false
    of vr:ctNoConcat                                                                   ! no depth-0 & in the binding: it binds looser
      return choose(~self.SpanHasConcat(self.binds.sPos, self.binds.ePos))             !   than + and -, so it would regroup
    of vr:ctWhole                                                                      ! every operand a whole number: a LONG
      return self.SpanIsWhole(self.binds.sPos, self.binds.ePos)                        !   truncates the fraction of each part
    of vr:ctSimple                                                                     ! no depth-0 logical operator in the binding
      if self.SpanHasBoolOp(self.binds.sPos, self.binds.ePos) then return false.
      return true
    of vr:ctBoolExpr                                                                   ! the EXACT complement of isSimple above:
      if self.SpanHasBoolOp(self.binds.sPos, self.binds.ePos) then return true.        !   the binding HAS a depth-0 logical operator,
      return false                                                                     !   so it is a LOGICAL expression valued 1 or 0
    of vr:ctPure                                                                       ! NO call/property access in the binding - pure
      loop b = self.binds.sPos to self.binds.ePos                                      !   arithmetic over vars/literals, safe for a
        txt.setValue(self.TokText(b))                                                  !   replacement to evaluate twice. '(' refuses calls
        if txt._DataEnd = 1                                                            !   AND paren-groups (conservative under-fire);
          if txt.valuePtr[1] = '(' or txt.valuePtr[1] = '{{' then return false.        ! '{' refuses x{{prop}
        end
      end
      return self.NamesAreData(self.binds.sPos, self.binds.ePos)                       ! and every name reads data: a bare Tick is a call
    of vr:ctCallFree                                                                   ! the binding CALLS nothing, but
      loop b = self.binds.sPos to self.binds.ePos                                      !   GROUPING parens are allowed:
        txt.setValue(self.TokText(b))                                                  !   `y + (3 * z)` evaluates twice
        if txt._DataEnd <> 1 then cycle.                                               !   as safely as `y`, and isPure
        if txt.valuePtr[1] = '{{' then return false.                                   !   refuses it only because of the
        if txt.valuePtr[1] <> '(' or                                                   |   !   bracket. '{' is a property.
           b <= self.binds.sPos                                                        ! opens the binding: grouping
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
        ! a NAME immediately before '(' is
        case val(prv.valuePtr[prv._DataEnd])                                           !   a call - `f(`, `self.M(`,
        of 65 to 90 orof 97 to 122 orof 48 to 57 orof 95 orof 58 orof 46               ! 'A' to 'Z' orof 'a' to 'z' orof '0' to '9' orof '_' orof <colon> orof <dot>   !   `pre:fld(`. Anything else -
          return false                                                                 !   an operator, a comma, another
        end                                                                            !   '(' - is grouping.
      end
      return self.NamesAreData(self.binds.sPos, self.binds.ePos)                       ! and no name is a procedure called bare - Tick
    of vr:ctCaseNeutral                                                                ! the binding is unchanged
      loop b = self.binds.sPos to self.binds.ePos                                      !   by EITHER case fold, which is exactly what
        txt.setValue(self.TokText(b))                                                  !   upper(x) = lower(x) tests - the two agree only when
        if txt._DataEnd and txt.valuePtr[1] = ''''                                     !   there is no letter present. A quoted literal is
          if ~self.LitValue(txt.getValue(), lv) then return false.                     !   tested for the characters it stands for, so '<97>'
          txt.setValue(lv)                                                             !   is the letter a; one this cannot read refuses. Any
        end                                                                            !   other token is tested as written: '::' and '/'
        loop cnX = 1 to txt._DataEnd                                                   !   pass, ' of ' and 'X' do not. A character from 127 up
          if val(txt.valuePtr[cnX]) >= 127 then return false.                          !   refuses, typed or written as a code: a program's
        end                                                                            !   CLACASE setting may pair any of them as a capital
        if upper(choose(txt._DataEnd < 1, '', txt.valuePtr[1 : txt._DataEnd])) <> lower(txt.getValue()) !   and a small letter (LRM), so whether one has a
          return false                                                                 !   case cannot be known here.
        end
      end
      return true
    of vr:ctSpaceless                                                                  ! the binding holds NO space anywhere, so a clip() on whatever it is
      loop b = self.binds.sPos to self.binds.ePos                                      !   searched against cannot change the answer: a clip
        txt.setValue(self.TokText(b))                                                  !   only ever removes TRAILING BLANKS, and a needle with
        if txt._DataEnd and txt.valuePtr[1] = ''''                                     !  no space in it could never have matched inside them.
          if ~self.LitValue(txt.getValue(), lv) then return false.                     ! A quoted literal is tested for the characters it
          txt.setValue(lv)                                                             !   stands for, so ' ', '<32>' and ' {3}' all answer
        end                                                                            !   FALSE - which is the answer that matters; one this
        if txt.containsByte(32) then return false.                                     !   cannot read refuses.
      end
      return true
    of vr:ctByte                                                                       ! the binding is ONE integer literal in 0-255, so
      if self.binds.sPos <> self.binds.ePos then return false.                         !   chr() in the replacement can spell it as the
      txt.setValue(self.TokText(self.binds.sPos))                                      !   character - 'A' for 65, '<10>' for 10
      if ~txt._DataEnd or txt._DataEnd > 3 then return false.
      if ~self.IsAllDigits(txt.getValue()) then return false.
      if txt.getValue() > 255 then return false.
      return true
    of vr:ctOneChar                                                                    ! the binding is provably ONE character. val() reads
      if self.TokText(self.binds.ePos) = ']'                                           !   the first character and nothing else, so only then
        ocDep = 0 ; ocK = 0                                                            !   does `x = chr(n)` say what `val(x) = n` said.
        loop b = self.binds.ePos - 1 to self.binds.sPos + 1 by -1                      ! A SLICE: back from the closing bracket to its opener;
          txt.setValue(self.TokText(b))                                                !   anything spelling a range - a ':' token, or a token
          if txt.containsByte(58) then return false.                                   !   holding one, `1:2` - refuses. A prefixed label as
          if txt._DataEnd <> 1 then cycle.                                             !   the index is refused too: a missed rewrite costs
          case val(txt.valuePtr[1])                                                    !   nothing, a range read as an index would be wrong
          of 93                                                                        ! ']'
            ocDep += 1
          of 91                                                                        ! '['
            if ~ocDep
              ocK = b
              break
            end
            ocDep -= 1
          end
        end
        if ocK <= self.binds.sPos then return false.
        ! x[i]: the opener is past the first token - but the SHAPE is not the whole answer.
        ! One character is what x[i] means for a plain string; with DIM it selects a whole
        ! ELEMENT, and `x[i] = chr(n)` would then compare all of it where val() read one
        ! byte. So the declaration has to be read, and it converts only when it was read and
        ! says no DIM: a name that does not resolve, a LIKE, a reference to anything but a
        ! string, or a declaration continued with a bar all refuse. A dotted field is read
        ! through the type registry, which recorded its declaration as it read it.
        txt.setValue(self.TokText(self.binds.sPos))
        if txt.containsByte(46) then return self.DottedOneChar(self.binds.sPos).       ! <dot>
        if self.syms &= NULL then return false.
        return self.syms.VarOneChar(txt.getValue(), self.binds.sPos)
      end
      if self.binds.sPos <> self.binds.ePos then return false.                         ! A VARIABLE declared STRING(1), by its declaration
      if ~self.rl.IsLabelToken(self.TokText(self.binds.sPos)) then return false.       !   text - the type keyword alone carries no length
      if self.syms &= NULL then return false.
      if self.syms.DeclaredStrLen(self.TokText(self.binds.sPos), self.binds.sPos) = 1 then return true.
      ! A STRING, CSTRING or PSTRING VARIABLE - never a reference - under a `size(w) = 1` or
      ! `len(w) = 1` guard: in the same statement, as the header of the block the statement is in,
      ! or as a jump above (`if size(w) <> 1 then cycle.`) - the guard walk. A &STRING never takes
      ! the whole-string form: its rewrite is the first-character one, isNonNull.
      txt.setValue(self.TokText(self.binds.sPos))
      if txt.containsByte(46) then return false.                                       ! a dotted field is read as a reference: isNonNull's job  ! <dot>
      if ~self.syms.Lookup(txt.getValue(), self.binds.sPos, tU, rf) then return false.
      if rf then return false.
      if tU <> 'STRING' and tU <> 'CSTRING' and tU <> 'PSTRING' then return false.
      self.ocLenOnly = choose(tU <> 'STRING')                                          ! a CSTRING's size counts its terminator, a
      if self.GuardProved(self.binds.sPos, upper(txt.getValue()), 1)                   !   PSTRING's its length byte: size(w) = 1
        self.ocLenOnly = 0                                                             !   proves one character for a STRING alone
        return true
      end
      self.ocLenOnly = 0
      return false
    of vr:ctNonNull                                                                    ! the binding is a string VARIABLE with a first character.
      if self.binds.sPos <> self.binds.ePos then return false.                         !   A STRING, CSTRING or PSTRING is never null and never
      if self.syms &= NULL then return false.                                          !   empty - STRING(0) does not exist - so val(w) = n
      txt.setValue(self.TokText(self.binds.sPos))                                      !   IS w[1] = chr(n); a &STRING needs a null test the
      if txt.containsByte(46)                                                          !   guard walk can prove. A DOTTED FIELD - self.tk.tokens.tok -  ! <dot>
        tU = self.RecvClass(self.binds.sPos)                                           !   resolves through the chain resolver, which gives its TYPE
        rf = 1                                                                         !   but not whether it is a reference: so it is read as one
      elsif ~self.syms.Lookup(txt.getValue(), self.binds.sPos, tU, rf)
        return false
      end
      if tU <> 'STRING' and tU <> 'CSTRING' and tU <> 'PSTRING' then return false.
      if ~rf then return true.
      return self.GuardProved(self.binds.sPos, upper(txt.getValue()), 2)
    of vr:ctPlain                                                                      ! a plain local that only the code around it can reach,
      if self.binds.sPos <> self.binds.ePos then return false.                         !   and that nothing there marks, streams or hands on: the
      if self.plainAsk &= NULL then return false.                                      !   in-place respellings of setValue keep the base64 and
      return self.plainAsk.IsPlain(self.binds.sPos)                                    !   encoding marks setValue clears (ruled 29 Oct 2026)
    of vr:ctMarksSafe                                                                  ! the marks are all that differ: under --ignoremarks any
      if self.binds.sPos <> self.binds.ePos then return false.                         !   object, else a plain local as isPlain() asks
      if self.plainAsk &= NULL then return false.
      return self.plainAsk.MarksSafe(self.binds.sPos)
    of vr:ctReturnsRef                                                                 ! the procedure around the match is prototyped *STRING: a
      if self.syms &= NULL then return false.                                          !   reference goes back as a variable or NULL, never a choose()
      tU = self.syms.ProcReturnAt(self.binds.sPos, rf)
      return choose(rf and tU = 'STRING')
    of vr:ctReturnsValue                                                               ! prototyped to return a value or nothing, not a reference.
      if self.syms &= NULL then return false.                                          !   With no prototype found it refuses: in a *STRING procedure
      tU = self.syms.ProcReturnRead(self.binds.sPos, rf, kn)                           !   the choose() the rule writes does not compile (ruled
      return choose(kn and ~rf)                                                        !   29 Oct 2026)
    of vr:ctNotNumber                                                                  ! NOT a number. clip() of one is text - '0', never blank - so
      if self.binds.sPos <> self.binds.ePos then return true.                          !   a compare of it with text is not a compare of the number,
      txt.setValue(self.TokText(self.binds.sPos))                                      !   and dropping the clip makes it one. An expression is not
      if self.IsAllDigits(txt.getValue()) then return false.                           !   looked into; a number literal, or ONE name declared as a
      if self.syms &= NULL then return true.                                           !   number, refuses
      if txt.containsByte(46)                                                          ! <dot>
        tU = self.RecvClass(self.binds.sPos)
      elsif ~self.syms.Lookup(txt.getValue(), self.binds.sPos, tU, rf)
        tU = self.ImplicitType(txt.getValue())                                         ! a name with no type the run can see is NOT
        if ~tU then tU = self.rl.AssumeType(txt.getValue()).                           !   proved text - it may be a number declared
      end
      if ~tU or tU = vs:unknownType then return false.                                 !   in an INCLUDE this run did not read
      val.setValue(' BYTE SHORT USHORT LONG ULONG INT64 UINT64 DECIMAL PDECIMAL REAL SREAL BFLOAT4 BFLOAT8 SIGNED UNSIGNED ')
      return choose(~val.findChars(' ' & clip(upper(tU)) & ' '))
    end
    return false
  end

  ! compare guard
  if self.rl.rules.guardQ.func = vr:gfLen                                              ! len(mv) op integer - numeric, own path
    b = -1                                                                             ! reuse b: logical length; -1 = not a single quoted literal
    if self.binds.sPos = self.binds.ePos
      b = self.LitLength(self.TokText(self.binds.sPos))
    end
    if self.rl.rules.guardQ.val &= NULL then return false.                             ! parser guarantees digits; defensive
    val.setValue(self.rl.rules.guardQ.val)
    eq = choose(b = val.getValue())                                                    ! LONG vs digit string: numeric compare
    if self.rl.rules.guardQ.op = vr:opEq then return eq.
    return 1 - eq
  end
  self.SpanText(self.binds.sPos, self.binds.ePos, txt)
  txt.setValue(self.FoldSafe(txt.getValue()))                                          ! gfFold and bare metavar both fold (spec 2.2). No gfTrimr arm: the compare below
                                                                                       !   is trailing-space-blind already, so a trimr arm could never change the answer.
  if txt._DataEnd > 1
    if txt.valuePtr[1] = '''' and txt.valuePtr[txt._DataEnd] = ''''
      txt.unquote('''')
      wasLit = 1                                                                       ! it was a quoted literal -> compare its content case-sensitively
      if self.binds.sPos = self.binds.ePos                                             ! ONE literal token compares by the VALUE it spells:
        if ~self.LitValue(self.TokText(self.binds.sPos), lv) then return false.        !   '<32>' and ' {3}' are as blank as ' ' is, and
        txt.setValue(lv)                                                               !   one this cannot read refuses
      end
    end
  end
  if not self.rl.rules.guardQ.val &= NULL
    val.setValue(self.rl.rules.guardQ.val)
    if wasLit                                                                          ! the rule's own literal is read the same way
      if self.LitValue('''' & val.getValue() & '''', lv) then val.setValue(lv).
    end
  end
  ! Clarion identifiers are caseless, so an identifier/EXPR guard (e.g. WHERE V <> 'SELF')
  ! must compare caselessly - matching the engine's own gdNoSelf guard. Only a bound LITERAL, whose
  ! content is case-significant, compares exactly.
  if wasLit
    eq = txt.equals(val, st:clip)
  else
    eq = choose(upper(choose(txt._DataEnd < 1, '', txt.valuePtr[1 : txt._DataEnd])) = upper(val.getValue()))
  end
  if self.rl.rules.guardQ.op = vr:opEq then return eq.
  return 1 - eq

! ------------------------------------------------------------------------------------
! does the token span [pS,pE] hold an & at depth 0? It binds looser than + - * / ^ %, so a binding holding one,
! written beside one of them, is read with another grouping: `a & b - 1` is a & (b - 1). Inside brackets it is grouped.
! ------------------------------------------------------------------------------------
VitMatch.SpanHasConcat Procedure(LONG pS, LONG pE)
i      long,auto
depth  long
t      StringTheory
  code
  loop i = pS to pE
    if self.TokIsEOL(i) then cycle.
    t.setValue(self.TokText(i))
    if t._DataEnd <> 1 then cycle.
    case val(t.valuePtr[1])
    of 40 orof 91 ! '(' orof '['
      depth += 1
    of 41 orof 93 ! ')' orof ']'
      depth -= 1
    of 38         ! '&'
      if ~depth then return 1.
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! isWhole(): is every operand in the span [pS,pE] a whole number, so that the sum it stands in
! has no fraction to lose? A LONG parameter truncates a fraction once, for the whole sum. Split
! the sum in two and each part is truncated on its own: with n = 5, 10 - n / 2 gives 7, but
! 0 - n / 2 gives -2 and 10 + -2 gives 8. So the span may hold integer literals, names declared
! with a whole-number type (BYTE, SHORT, USHORT, LONG, ULONG, INT64, UINT64, SIGNED, UNSIGNED,
! or an implicit name ending in #), the operators + - * and %, and brackets that group or
! subscript. Anything else refuses: / or ^, a number with a decimal point, a quoted literal, a
! call, a property, or a name of another type or one this run cannot place.
! ------------------------------------------------------------------------------------
VitMatch.SpanIsWhole Procedure(LONG pS, LONG pE)
i    long,auto
t    StringTheory
tU   StringTheory
  code
  if self.syms &= NULL then return false.
  loop i = pS to pE
    if self.TokIsEOL(i) then cycle.
    t.setValue(self.TokText(i))
    if ~t._DataEnd then cycle.
    case val(t.valuePtr[1])
    of 48 to 57
      if t.containsByte(46) then return false.
    of 65 to 90 orof 97 to 122 orof 95
      if self.TokText(i + 1) = '(' then return false.
      tU.setValue(self.RecvClass(i))
      if ~tU._DataEnd then tU.setValue(self.ImplicitType(t.getValue())).
      tU.upper()
      tU.enclose(' ', ' ')
      if ~instring(tU.getValue(), ' BYTE SHORT USHORT LONG ULONG INT64 UINT64 SIGNED UNSIGNED ', 1, 1)
        return false
      end
    else
      if t._DataEnd > 1 and inlist(t.valuePtr[1], '+', '-') and self.IsAllDigits(t.valuePtr[2 : t._DataEnd]) then cycle.
      if t._DataEnd <> 1 then return false.
      case val(t.valuePtr[1])
      of 43 orof 45 orof 42 orof 37 orof 40 orof 41 orof 91 orof 93 orof 44 ! '+' orof '-' orof '*' orof '%' orof '(' orof ')' orof '[' orof ']' orof <comma>
      else
        return false
      end
    end
  end
  return true

! ------------------------------------------------------------------------------------
! FoldStr's folded text of pIn, or pIn itself when the fold changed a NAME. Folding adds and
! multiplies numbers and leaves every name where it is, so the names of the folded text, in
! order, are those of pIn. FoldStr hands no call to the runtime's EVALUATE, which runs any
! Clarion builtin it is given: day(today()) - 1 would come back as the day the tool ran, and
! upper('k') as K - a name the program never wrote. This is the second check on the same
! point: a fold that lost, gained or changed a name is not used.
! ------------------------------------------------------------------------------------
VitMatch.FoldSafe Procedure(STRING pIn)
fs   StringTheory
cs   StringTheory
nl   StringTheory
ni   StringTheory
cn   long
nIn  long,auto
x    long,auto
q    byte
inW  byte
  code
  fs.setValue(self.tk.FoldStr(pIn))
  cs.setValue(pIn)
  do CountNames
  nIn = cn
  ni.setValue(nl)
  cs.setValue(fs)
  do CountNames
  if cn <> nIn then return pIn.
  if cn and ~ni.equals(nl, st:clip) then return pIn.
  return fs.getValue()

! the names in cs, outside quotes, counted in cn and listed in nl: a run of name characters that
! starts with a letter, '_' or '?'. A run that starts with a digit is a number, 0FFh as much as 12.
CountNames routine
  cn = 0
  q = 0
  inW = 0
  nl.free()
  loop x = 1 to cs._DataEnd
    if q
      if cs.valuePtr[x] = '''' then q = 0.
      cycle
    end
    case val(cs.valuePtr[x])
    of 39
      q = 1
      inW = 0
    of 65 to 90 orof 97 to 122 orof 95 orof 63
      if ~inW then cn += 1 ; inW = 1 ; nl.append(' ').
    of 48 to 57 orof 46 orof 58
      if ~inW then inW = 2.
    else
      inW = 0
    end
    if inW = 1 then nl.append(cs.valuePtr[x]).
  end

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
    case upper(t.getValue())
    of 'AND' orof 'OR' orof 'XOR' orof 'NOT'
      return 1
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! Logical character count of a quoted literal token, honouring Clarion string
! escapes: doubled '' << {{ count 1; <13> counts 1 and <13,10> counts 2 (one
! per comma-separated value); x{5} is x repeated 5 times total. Returns -1 for
! anything that is not a well-formed quoted literal - a quote inside that is not doubled ends the
! literal there, so `'[' & clip(t) & ']'` is an expression, not one literal (a len() guard then fails
! '=' and passes '<>'). Works on the RAW token text - no unquoting.
! ------------------------------------------------------------------------------------
VitMatch.LitLength Procedure(STRING pTok)
! #Removed as not used: t     StringTheory
grp   StringTheory
n     long
i     long,auto
j     long,auto
rep   long,auto
  code
  if len(pTok) < 2 or                                   |
     pTok[1] <> '''' or pTok[len(pTok)] <> ''''
    return -1
  end
  i = 2
  loop while i <= len(pTok) - 1
    if i < len(pTok) - 1
      case pTok[i : i+1]
      of '''''' orof '<<<<' orof '{{{{'
        n += 1
        i += 2
        cycle
      end
    end
    if pTok[i] = '''' then return -1.
    if pTok[i] = '<<'                                   ! char-code group: <13> or <13,10,...>
      j = i + 1
      loop while j <= len(pTok) - 1 and pTok[j] <> '>'
        j += 1
      end
      if j > len(pTok) - 1 or j = i + 1 then return -1. ! unterminated or empty <>
      grp.setValue(pTok[i+1 : j-1])
      if ~grp.isAll('0123456789, ') then return -1.
      n += grp.Count(',') + 1                           ! one char per comma-separated value
      i = j + 1
      cycle
    end
    if pTok[i] = '{{'                                   ! repeat group: {5} = previous char x5 total
      j = i + 1
      loop while j <= len(pTok) - 1 and pTok[j] <> '}'
        j += 1
      end
      if j > len(pTok) - 1 or j = i + 1 then return -1.
      grp.setValue(pTok[i+1 : j-1])
      if ~grp.IsAllDigits() or ~n then return -1.       ! non-numeric count, or nothing to repeat
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
! The VALUE a quoted literal token spells, into pOut: '' << {{ are one character each, a
! <a,b,...> group is one character per code, and C{n} is C n times in all. A guard that
! compares a literal compares this, so '<32>' and ' {3}' are as blank as ' ' is. Returns 1
! when the token is one literal this can read, 0 when it is not - a stray quote, an unclosed
! group, a code that is not a byte, or a repeat with nothing plain in front of it (what
! repeats after a code group is not settled, so it is not guessed).
! ------------------------------------------------------------------------------------
VitMatch.LitValue Procedure(STRING pTok, StringTheory pOut)
n      long,auto
i      long,auto
j      long,auto
k      long,auto
c      long,auto
rep    long,auto
lastC  long,auto
inGrp  byte
  code
  pOut.free()
  n = len(clip(pTok))
  if n < 2 or pTok[1] <> '''' or pTok[n] <> '''' then return 0.
  lastC = -1
  i = 2
  loop while i <= n - 1
    c = val(pTok[i])
    if (c = 39 or c = 60 or c = 123) and i < n - 1 and pTok[i + 1] = pTok[i]
      pOut.append(pTok[i])
      lastC = c
      inGrp = 0
      i += 2
      cycle
    end
    case c
    of 39
      return 0
    of 60
      k = i + 1
      j = k
      loop
        if j > n - 1 then return 0.
        case val(pTok[j])
        of 44 orof 62 ! <comma> orof '>'
          if j = k then return 0.
          lastC = self.LitCode(pTok[k : j - 1])
          if lastC < 0 then return 0.
          pOut.append(chr(lastC))
          if pTok[j] = '>' then break.
          k = j + 1
        end
        j += 1
      end
      inGrp = 1
      i = j + 1
    of 123
      j = i + 1
      rep = 0
      loop while j <= n - 1 and rep <= 255 and val(pTok[j]) >= 48 and val(pTok[j]) <= 57
        rep = rep * 10 + val(pTok[j]) - 48
        j += 1
      end
      if j = i + 1 or j > n - 1 or pTok[j] <> '}' or lastC < 0 or inGrp or rep < 1 or rep > 255 then return 0.
      if rep > 1 then pOut.append(all(chr(lastC), rep - 1)).
      i = j + 1
    else
      pOut.append(pTok[i])
      lastC = c
      inGrp = 0
      i += 1
    end
  end
  return 1

! ------------------------------------------------------------------------------------
! The character a code inside a literal's <...> group stands for. The LRM allows a code in any
! numeric constant form: decimal 32, hexadecimal 20h, binary 100000b, octal 40o or 40q; blanks
! around it are ignored. -1 = not a code this can read, or not a byte.
! ------------------------------------------------------------------------------------
VitMatch.LitCode Procedure(STRING pCode)
s     StringTheory
n     long,auto
x     long,auto
d     long,auto
base  long,auto
v     long
  code
  s.setValue(pCode)
  s.removeByte(32)
  n = s._DataEnd
  if n < 1 then return -1.
  base = 10
  case upper(s.valuePtr[n])
  of 'H'
    base = 16
  of 'B'
    base = 2
  of 'O' orof 'Q'
    base = 8
  end
  if base <> 10 then n -= 1.
  if n < 1 then return -1.
  loop x = 1 to n
    d = val(upper(s.valuePtr[x]))
    case d
    of 48 to 57
      d -= 48
    of 65 to 70
      d -= 55
    else
      return -1
    end
    if d >= base then return -1.
    v = v * base + d
    if v > 255 then return -1.
  end
  return v

! ------------------------------------------------------------------------------------
! Does every NAME in [pS..pE] read DATA? Clarion calls a procedure that takes no parameters by
! its label alone - `x = s[Tick : Tick]` calls Tick twice - so a span with no bracket in it can
! still call something. A plain name must resolve in the symbol table, which holds data and
! not procedures; a dotted name must resolve hop by hop to a field. A StringTheory's own _DataEnd and valuePtr are
! fields, whether or not its header was read. A name that does not
! resolve may be a procedure, or data declared in an INCLUDE, which the table does not hold, and
! answers 0: a missed rewrite costs nothing. An implicit variable (n#, s", r$) is data by its
! spelling. Reserved words, operators, literals and numbers are not names. The engine makes
! the same proof for the names in a condition (CondNamesAreData).
! ------------------------------------------------------------------------------------
VitMatch.NamesAreData Procedure(LONG pS, LONG pE)
i     long,auto
dotP  long,auto
rf    byte
head  STRING(vs:maxName),AUTO
tU    STRING(vs:maxName)
txt   StringTheory
segs  StringTheory
  code
  if self.syms &= NULL then return 0.
  loop i = pS to pE
    if self.TokType(i) <> vt:label then cycle.
    txt.setValue(self.TokText(i))
    if ~txt._DataEnd then return 0.
    if self.ImplicitType(txt.getValue()) then cycle.
    dotP = txt.findByte(46)
    if ~dotP
      if ~self.syms.Lookup(txt.getValue(), i, tU, rf) then return 0.
      cycle
    end
    if dotP < 2 or dotP >= txt._DataEnd then return 0.
    head = upper(txt.sub(1, dotP - 1))
    if ~self.syms.Lookup(head, i, tU, rf) then return 0.
    segs.setValue(txt.slice(dotP + 1))
    if upper(tU) = 'STRINGTHEORY' and inlist(upper(segs.getValue()), '_DATAEND', 'VALUEPTR') then cycle. ! its own fields
    segs.replaceByte(46, 124)
    if ~self.syms.LookupChain(tU, segs.getValue(), i) then return 0.
  end
  return 1

! ------------------------------------------------------------------------------------
! The LRM's combined-operator table (p528) gives more than one spelling for the same
! operator, and a rule written with one of them must match code written with another - or
! a rule matching <= silently misses code written =<. Returns the
! canonical spelling for anything with a synonym, or '' for everything else.
!   <= = < ~ >   less than or equal / not greater than
!   >= = > ~ <   greater than or equal / not less than
!   <> ~ =       not equal
! chr() rather than a literal because '<' and '{' double inside a Clarion string.
! The LRM's two-word forms (NOT = / NOT < / NOT >) are two TOKENS and are not in this table:
! NotInfixAt, OpCanonNot and AnchorNotPair read the pair as one operator instead.
! ------------------------------------------------------------------------------------
VitMatch.OpCanon Procedure(STRING pTok)
ocS  string(2),auto ! a spaced comparison with its blanks dropped
ocN  long,auto
ocZ  long,auto
  code
  ! The tight spellings need no clip and no upper: CASE on a string already ignores trailing
  ! spaces, and an operator holds no letters so there is no case to fold. The spellings are written as
  ! CONSTANTS with '<' doubled, rather than built with chr() concatenation on every call.
  case pTok
  of '<<=' orof '=<<' orof '~>'  ! '<=' '=<' '~>'
    return '<<='
  of '>='  orof '=>'  orof '~<<' ! '>=' '=>' '~<'
    return '>='
  of '<<>' orof '~='             ! '<>' '~='
    return '<<>'
  end
  ! A comparison the tokenizer joined across blanks (`< >`, `~ =`, `= <`) is the same operator
  ! as its tight spelling: drop the blanks and answer for that. Only a token longer than two
  ! characters can be one, so every tight spelling has been answered above without this.
  if len(clip(pTok)) < 3 then return ''.
  ocS = ''
  ocN = 0
  loop ocZ = 1 to len(clip(pTok))
    case val(pTok[ocZ])
    of 32 orof 9
      cycle
    end
    ocN += 1
    if ocN > 2 then return ''.
    ocS[ocN] = pTok[ocZ]
  end
  if ocN < 2 then return ''.
  return self.OpCanon(ocS)

! ------------------------------------------------------------------------------------
! Does the two-word operator opening at pIx (an infix NOT plus its comparator) spell the same
! operator as pAnchor? RefreshFreq posts such a position under the canonical key, so the
! postings walk offers it as a candidate - and LitMatches, which compares ONE token to one
! token, cannot see why it qualifies. This is the arbiter for that case and nothing else.
! ------------------------------------------------------------------------------------
VitMatch.AnchorNotPair Procedure(LONG pIx, *STRING pAnchorOp)
cmpT  string(4),auto ! a variable for the *STRING callee
  code
  if ~self.NotInfixAt(pIx) then return 0.
  cmpT = self.TokText(pIx + 1)
  if pAnchorOp = self.OpCanonNot(cmpT) then return 1.
  return 0

! ------------------------------------------------------------------------------------
! The class of the operator formed by an infix NOT and the token AFTER it. This is NOT the
! same mapping as OpCanon: the second token is a BARE comparator, and the NOT inverts it -
!   NOT =  is  <>        NOT <  is  >=  (not less)        NOT >  is  <=  (not greater)
! - which is why `NOT <` cannot simply canonicalise as `<`. '' if the token cannot follow a
! NOT to make an operator. (LRM p528: "A ~< B, A >= B, A NOT < B - True when A is not less".)
! ------------------------------------------------------------------------------------
VitMatch.OpCanonNot Procedure(*STRING pTok)
c  string(1),auto
b  byte,over(c)   ! L: compare the BYTE, not the string
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
  ! every pattern dot is read here as MEMBER ACCESS, so a fragment-ending '.' (a block
  ! terminator) is refused by the next line; the callers that want one - MatchHere, CandOK,
  ! the anchor walks - ask PatDotEnds / IsMemberDot themselves
  if pLit = '.' and ~self.IsMemberDot(pIx) then return false. ! a pattern member-dot must not match a vt:end TERMINATOR dot (st. free(q) after THEN would lose the IF terminator)
  if pLit[1] = ''''                                           ! quoted literal: exact, case-sensitive
    if self.TokText(pIx) = pLit then return true.
    return false
  end
  if upper(self.TokText(pIx)) = upper(pLit) then return true.
  ! same operator, different documented spelling. FIRST BYTE GATE: a failed compare is
  ! the ordinary case here - this is the hottest test in the matcher, run for every candidate
  ! and every literal token of every attempt - and every spelling with a synonym begins with
  ! one of four characters. One indexed byte keeps every other token out of OpCanon.
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
! It must never refuse a start MatchHere would take, so the literal test admits every
! spelling MatchHere admits: a comparator's two-word NOT form in EITHER direction, and a
! pattern '.' that ends a fragment matching a block terminator.
! ------------------------------------------------------------------------------------
VitMatch.CandOK Procedure(LONG pS)
ckOp  string(4),auto
  code
  if self.gd1Lit
    get(self.patQ, 1)
    if errorcode() or self.patQ.tok &= NULL then return true.
    if self.LitMatches(pS, self.patQ.tok) then return true.   ! the member itself - no clip() copy; = ignores trailing spaces anyway
    ckOp = self.OpCanon(self.patQ.tok)                        ! a leading comparator also matches its two-word NOT spelling
    if ckOp then return self.AnchorNotPair(pS, ckOp).         !   ('<<>' vs 'NOT =') - the postings walk already admits these
    ! and the other direction, which the comparator test above cannot cover: a pattern that
    ! OPENS `NOT =` matches source spelling it `<>`, as MatchHere does. OpCanon('NOT') is '',
    ! so without this the start would never be tried. PatFacts read the pair once per rule.
    if self.pat1NotOp then return choose(self.pat1NotOp = self.OpCanon(self.TokText(pS))).
    ! A '.' that ENDS a pattern fragment is a block TERMINATOR. LitMatches reads every pattern
    ! dot as member access and refuses a terminator dot outright, so the test above refuses the
    ! one token MatchHere's terminator arm accepts - and a rule whose pattern opens with such a
    ! dot would match nothing. Ask what that arm asks. PatDotEnds leaves the buffer on part 1.
    if self.patQ.tok = '.' and self.PatDotEnds(1)
      return choose(self.TokText(pS) = '.' and ~self.IsMemberDot(pS))
    end
    return false
  end
  ! A pattern that OPENS with an EXPR metavar is tried from every token of the statement, the
  ! statement's first word included - and an EXPR extent stops at THEN, ELSE, a comma or a
  ! terminator, never at the word in front of it. So from `if a <> clip(b)` the first start that
  ! lets the rest of the pattern match would bind w1 = `if a`, keyword and all, and only a
  ! rule putting w1 back first and unchanged would come out right. No expression begins with
  ! the word that opens or continues a statement, so such a start is refused here.
  if self.pat1Expr
    if instring(' ' & upper(self.TokText(pS)) & ' ', ' IF ELSIF CASE OF OROF LOOP WHILE UNTIL RETURN EXECUTE DO TO BY TIMES ', 1, 1) then return false.
  end
  if self.gd1IdMv
    if ~self.rl.IsLabelToken(self.TokText(pS)) and ~instring('.', self.TokText(pS), 1, 1) |
       and ~self.ImplicitType(self.TokText(pS))                                           |
       then return false.                                                                 ! a recombined 'self.Direct' receiver token has a '.' and isn't a bare label; implicit variables (total#,
                                                                                          !   s", r$) are variables too - MatchHere's arm accepts them, so the gate must not discard them first
    if self.gd2Dot and self.TokText(pS + 1) <> '.' then return false.
  end
  return true

! ------------------------------------------------------------------------------------
! Full pattern match attempt at pS, guards applied. Returns last matched token
! position (also for a logged interior-comment skip, so the scan moves on), or 0.
!
! NOTBOOL and EXPREND read the tokens round gS..gE: the match widened out through every
! bracket that holds nothing else and only groups - never a call's own bracket (IsCallOpen),
! where the match is an argument. What stands outside such a bracket is what uses the match:
! `if (clip(n))` is tested by the IF, `(clip(n)) = s` is compared, `(clip(s)) & 'x'` is joined
! on. EXPRSTART and the comparison test of EXPREND read the match's own edges: a bracket in
! front of the match stops anything binding into it, and a bracket kept round a negated
! value keeps `(~a) = b` grouped as written.
! ------------------------------------------------------------------------------------
VitMatch.TryFrom Procedure(LONG pS, StringTheory pReport)
r  long,auto
e  long,auto
gS long,auto
gE long,auto
  code
  free(self.binds)
  if self.gdNoDot and pS > 1
    if self.TokText(pS-1) = '.' and self.IsMemberDot(pS-1) then return 0.            ! a vt:end terminator dot before pS is not a receiver context
  end
  if self.gdStmt
    if self.StmtStart(pS) <> pS then return 0.
  end
  r = self.MatchHere(1, pS)
  if ~r then return 0.
  e = r - 1
  if self.gdStmt and ~self.IsStmtEndAfter(e) then return 0.
  if self.rl.rules.inParens and ~self.StartsInsideBracket(pS) then return 0.         ! INPARENS: the match must sit inside an unclosed bracket of its own statement,
                                                                                     !   which is what proves an '=' here is a comparison and not an assignment
  gS = pS
  gE = e
  loop while self.TokText(gS - 1) = '(' and self.TokText(gE + 1) = ')'
    if self.IsCallOpen(gS - 1, 0) then break.
    gS -= 1 ; gE += 1
  end
  if self.rl.rules.notBool and self.MatchIsTruthTest(gS, gE) then return 0.          ! NOTBOOL: never a match that stands as a TRUE/FALSE value
  if self.rl.rules.exprStart and self.ExprContinuesBefore(pS) then return 0.         ! EXPRSTART: the operand must START here - an operator in front binds into the match
  if self.rl.rules.exprEnd and self.ExprContinuesAfter(gE) then return 0.            ! EXPREND: the operand must END here - a continuing binary operator means padding/structure the rewrite would corrupt; refuse, no match
  if self.rl.rules.exprEnd and self.repNot and self.CompareFollows(e) then return 0. ! EXPREND, and the replacement opens with ~ or NOT: a comparison after the match groups left - (a <> b) = x - while
                                                                                     !   ~a = b is ~(a = b), so the rewritten text would compare something else; refuse, no match
  if self.gdNoSelf
    if upper(self.TokText(pS)) = 'SELF' then return 0.                               ! bare SELF receiver excluded; a recombined 'self.Direct' token is not 'SELF' so passes
  end
  if self.rl.rules.guardKind
    if ~self.GuardOK() then return 0.                                                ! WHERE guard rejects: no match at all
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
pt       StringTheory       ! pattern token text
opC      string(4),auto     ! canonical spelling of a comparison operator with synonyms ('' = has none)
nOp      string(4),auto     ! the same for a two-word NOT pair on the PATTERN side
cmpT     string(4),auto     ! a variable for the *STRING callees
t        StringTheory       ! source token text
pmvx     long,auto
kind     byte,auto
b        long,auto
L        long,auto
e        long,auto
r        long,auto
depth    long,auto
d        long,auto
c        long,auto
dotPos   long,auto          ! '.' pos in a recombined member-access receiver token
recvU    STRING(vs:maxName) ! resolved class of a method-call receiver
cands    QUEUE              ! EXPR candidate end positions
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
    if pt._DataEnd = 1 and pt.valuePtr[1] = '.' and self.PatDotEnds(pP)                  ! a dot that ENDS a pattern fragment is a block
      if self.TokText(pS) <> '.' or self.IsMemberDot(pS) then return 0.                  !   terminator - `then cycle.` - and matches only a
      return self.MatchHere(pP+1, pS+1)                                                  !   terminator dot. Every OTHER pattern dot is member
    end                                                                                  !   access, which is what LitMatches reads it as
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
      elsif pt._DataEnd = 3 and upper(pt.valuePtr[1 : 3]) = 'NOT' and pP < self.patCount ! pattern `NOT =` vs source `<>` (slice the three bytes rather than getValue() a copy of them)
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

  if not self.patQ.mvTail &= NULL                                                        ! dotted metavar occurrence (st._DataEnd) - a
    if self.TokIsEOL(pS) then return 0.                                                  ! constrained literal: source must be ONE merged token
    pt.setValue(self.patQ.mvTail,st:clip)                                                ! equal to <head binding>.<tail> (caseless); never binds.
    b = self.FindBind(pmvx)                                                              ! Lint guarantees a plain occurrence bound the head
    if ~b then return 0.                                                                 ! earlier in the pattern.
    get(self.binds, b)
    if self.binds.sPos <> self.binds.ePos then return 0.                                 ! single-token bindings only (receivers)
    pt.prepend(clip(self.TokText(self.binds.sPos)) & '.')
    t.setValue(self.TokText(pS),st:clip)
    if t._DataEnd <> pt._DataEnd or                                                      |
       upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) <> upper(pt.getValue())
      return 0
    end
    return self.MatchHere(pP+1, pS+1)
  end

  case kind
  of vr:mvTyped orof vr:mvClass orof vr:mvAnyVar orof vr:mvTypeSet                       ! one identifier token, type-checked against the symbol table
    if self.TokIsEOL(pS) then return 0.
    ! return-type table: a method-RESULT span <recv>.<method>(args) binds a
    ! STRING-classed metavar when the receiver's class RESOLVES and the class's headers
    ! declare the method ,String (any registry-known class, inheritance walked;
    ! six-name fallback for registry-unknown classes). Makes string method results bind
    ! like string variables everywhere, so no rule needs a shape of its own for
    ! one. Tried FIRST; any refusal falls through to the single-token paths below.
    ! mvAnyVar excluded (variables only). Gate order: metavar class first (cheap),
    ! receiver resolution second, method lookup last.
    if kind <> vr:mvAnyVar and ~self.TokIsEOL(pS+1) and ~self.TokIsEOL(pS+2) and ~self.TokIsEOL(pS+3)
      ! IsMemberDot, NOT a raw '.' test - the reason is written out at IsMemberDot, and
      ! every sibling asks it too. A one-liner's TERMINATOR dot is also a '.' token, so a
      ! raw test would bind `if c then q9 = s1. left (s1)` as a method-result span ACROSS
      ! the end of the statement and emit `q9 = use(s1. left (s1))` - the IF's terminating
      ! period deleted and the following lines swallowed into the THEN clause. It compiles.
      if self.TokText(pS+1) = '.' and self.IsMemberDot(pS + 1)                           |
         and self.TokText(pS+3) = '(' and self.rl.IsLabelToken(self.TokText(pS+2))

        recvU = ''
        if self.ClassSatisfies(pmvx, 'STRING') then recvU = self.RecvClass(pS).
        if recvU and self.MethodReturnsString(recvU, self.TokText(pS+2), self.CallArgCount(pS+3), self.CallArgTypes(pS+3)) ! pS+3 is the open paren
          depth = 1                                                                      ! balanced arg scan from the '('
          e = pS + 4
          loop
            if self.TokIsEOL(e) then depth = -1; break.                                  ! no close before EOS - not a call span
            d = self.DepthDelta(self.TokText(e))
            if depth + d = 0 then break.                                                 ! e = the matching ')'
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
    ! the same name. An implicit variable is another matter: it IS a plain identifier, so
    ! ANYVAR binds it (below).
    if kind <> vr:mvAnyVar then dotPos = instring('.', self.TokText(pS), 1, 1).          ! dot-form: mvTyped/mvTypeSet chains too - the single-id path refuses a dotted token, so this only ADDS matches
    if dotPos > 1                                                                        ! the tokenizer recombines a member-access receiver into ONE token (self.Direct)
      if ~self.ChainTypeOK(pmvx, pS) then return 0.                                      ! type it by splitting on '.' and walking the registry
    elsif self.ImplicitType(self.TokText(pS))                                            ! IMPLICIT variables (clarion.help implicit_variables) -
      ! ANYVAR binds an implicit variable too. `total#` IS an identifier - the whole
      ! meaning of ANYVAR - so this arm is not gated against ANYVAR: the fall-through
      ! demands IsLabelToken, which a '#'/'"'/'$' suffix fails. A typed
      ! metavar reaches ClassSatisfies below; ANYVAR has no type to satisfy, so it just binds.
      if kind <> vr:mvAnyVar
        if ~self.ClassSatisfies(pmvx, self.ImplicitType(self.TokText(pS))) then return 0. !   s" = STRING(32), n# = LONG, r$ = REAL; typed by SUFFIX, never
      end                                                                                !   declared, so the symbol table can never know them
    else
      if ~self.rl.IsLabelToken(self.TokText(pS)) then return 0.
      if ~self.TypeOK(pmvx, pS) then return 0.
    end
    b = self.FindBind(pmvx)                                                              ! bind as ONE token (recombined or plain); repeated-metavar equality is SpanEqual - caseless for identifiers, exact for quoted literals
    if b
      get(self.binds, b)
      if ~self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, pS) then return 0.
      return self.MatchHere(pP+1, pS+1)
    end
    self.BindSpan(pmvx, pS, pS)
    r = self.MatchHere(pP+1, pS+1)
    if ~r then self.Unbind().
    return r

  of vr:mvLiteral                                                                        ! one quoted string literal token
    if self.TokIsEOL(pS) then return 0.
    t.setValue(self.TokText(pS))
    if ~t._DataEnd or                                                                    |
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

  of vr:mvConst                                                                          ! CONST binds an all-digit token only; fold() is the rewriter's
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

  of vr:mvArgs                                                                           ! whole (...) content; lint guarantees '(' before, ')' after
    depth = 1
    e = pS
    loop
      if self.TokIsEOL(e) then return 0.                                                 ! no close before end of statement/file
      d = self.DepthDelta(self.TokText(e))
      if depth + d = 0 then break.                                                       ! e is the matching ')'
      depth += d
      e += 1
    end
    b = self.FindBind(pmvx)
    if b
      get(self.binds, b)
      if ~self.SpanEqual(self.binds.sPos, self.binds.ePos, pS, e-1) then return 0.
      return self.MatchHere(pP+1, e)
    end
    self.BindSpan(pmvx, pS, e-1)                                                         ! possibly empty span (ePos < sPos)
    r = self.MatchHere(pP+1, e)                                                          ! pattern part pP+1 is the ')'
    if ~r then self.Unbind().
    return r

  of vr:mvExpr
    b = self.FindBind(pmvx)
    if b                                                                                 ! repeated EXPR: must equal first binding
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
        if t._DataEnd = 1 and t.valuePtr[1] = '.' and ~self.IsMemberDot(e) then break.   ! a vt:end terminator dot ends the statement - the extent must not swallow it (StmtStart treats it as a boundary too)
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
    loop c = records(cands) to 1 by -1                                                   ! greedy: longest extent first
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
  if pAE < pAS then return true.   ! both spans empty
  o = pBS - pAS
  loop i = pAS to pAE
    if self.TokIsEOL(i) or self.TokIsEOL(i+o) then return false.
    ta.setValue(self.TokText(i))
    tb.setValue(self.TokText(i+o))
    ! LitMatches' notion of identity, NOT a blanket fold. A quoted literal is CONTENT
    ! and compares case-sensitively - which is what LitMatches and FreqKey do, so a
    ! blanket upper() here would make repeated-metavar equality the one place in the
    ! matcher where 'Yes' and 'YES' are one string: foo(w,w) would match foo('Yes','YES')
    ! and the rewrite emit ONE for both. Everything else in a span is a Clarion identifier or
    ! keyword, where the language itself is caseless, so those stay folded.
    if (ta._DataEnd and ta.valuePtr[1] = '''') or (tb._DataEnd and tb.valuePtr[1] = '''')
      if ~ta.equals(tb, st:clip) then return false.
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
! #Removed as not used: c    string(1),auto
  code
  loop i = pS+1 to pE
    self.TokBefore(i, bt)
    loop x = 1 to bt._DataEnd
      case val(bt.valuePtr[x])
      of 32 orof 9 orof 13 orof 10 orof 124 ! <space> orof <tab> orof <carriage return> orof <line feed> orof '|'
        cycle
      end
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
    self.matches.ruleRow = self.capRow
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
  if errorcode() then return true. ! a missing token IS a boundary - stopping a scan here is the REFUSING answer, unlike the two typed gates above, where true meant "accept anything".
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
! A column-1 label on the line is not part of the statement after it - `Again  n += 1` is the
! statement `n += 1` (ruled 30 Oct 2026) - so a statement that starts the line starts after one.
VitMatch.StmtStart Procedure(LONG pIx)
j   long,auto
t   StringTheory
  code
  loop j = pIx - 1 to 1 by -1
    if self.TokIsEOL(j)
      if j + 1 < pIx and self.IsColOneStart(j + 1) then return j + 2.
      return j + 1
    end
    t.setValue(self.TokText(j))
    if t._DataEnd = 1 and t.valuePtr[1] = ';' then return j + 1.
    if upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) = 'THEN' or upper(choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])) = 'ELSE' then return j + 1.
    if t._DataEnd = 1 and t.valuePtr[1] = '.' and ~self.IsMemberDot(j) then return j + 1.
  end
  if 1 < pIx and self.IsColOneStart(1) then return 2.
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
                                                                                                     !  with StmtStart; vitTokenize mode-3 logical-EOL precedent)
  return false

! ------------------------------------------------------------------------------------
! EXPREND support: does the token AFTER pIx continue the expression the match
! ended inside? A single-char binary operator (& + - * / ^ %) glues more operand onto
! the matched span - the one case the EXPREND rules must refuse (a clip dropped there
! leaves padding INTERNAL; a collapsed blank/zero test changes the operand's shape).
! Anything else - EOL, ';', terminator '.', THEN/ELSE/END, and/or/xor, ')' - ends the
! operand, so the match stands. Blacklist deliberately: unknown next token = fire, the
! same permissiveness every un-optioned rule has. A '|' continuation is trivia
! in the NEXT token's strBefore, so a continued '& lit' still presents as '&' here.
! TryFrom asks this past any bracket that only groups the match: `(clip(s)) & 'x'`
! joins on to the match as surely as `clip(s) & 'x'` does.
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
! The other thing that can follow an EXPREND match: a comparison. Comparisons group left to
! right, so `a <> b = x` is `(a <> b) = x` and a replacement that keeps the comparison's shape
! keeps that grouping. One that opens with ~ or NOT does not: ~a = b is ~(a = b) (see
! ExprContinuesBefore), so `~st.equals(st2) = x` would negate the second comparison instead of
! the first. TryFrom asks this only for such a replacement. Every single-token spelling, the
! spaced ones through OpCanon, and the word NOT - which after an operand can only be the infix
! one of `NOT =`, `NOT <`, `NOT >`.
! ------------------------------------------------------------------------------------
VitMatch.CompareFollows Procedure(LONG pIx)
nxt  StringTheory
  code
  if self.TokIsEOL(pIx + 1) then return false.
  nxt.setValue(self.TokText(pIx + 1))
  if ~nxt._DataEnd then return false.
  if self.OpCanon(nxt.getValue()) then return true.
  case nxt.getValue()
  of '=' orof '<<' orof '>' orof '<<>' orof '<<=' orof '>=' orof '~=' orof '~<<' orof '~>' orof '=<<' orof '=>'
    return true
  end
  if upper(nxt.getValue()) = 'NOT' then return true.
  return false

! ------------------------------------------------------------------------------------
! NOTBOOL support: is the match at [pS..pE] used as a TRUE/FALSE value, or compared? A rewrite
! that keeps a value's text but changes its type answers differently there. clip(n) of a
! number is never blank, so `if clip(n)` is always true, while `if n` is a test for zero. And
! clip(n) is TEXT: `if s = clip(n)` compares two strings, `if s = n` compares numbers - a blank
! s equals a zero n - whatever stands on the other side, a variable, a literal or a call, and
! under every comparison operator. So the match refuses when it is the whole condition of IF,
! ELSIF, LOOP WHILE or UNTIL, the value a CASE tests or an OF gives, the upper bound of an OF's
! range after its TO (compared with the CASE value as the OF is), an operand of NOT, ~, AND,
! OR or XOR, the argument that is choose()'s condition, or either side of a comparison in any
! spelling. An '=' that ASSIGNS is no comparison (AssignEqAt): `s = clip(n)` as a statement
! puts the same text in s either way, and still converts - unless the target takes the type it
! is given, as an ANY or an untyped (?) parameter does, or is a name this run cannot place
! (DestKeepsType). A RETURN converts to the type the procedure is prototyped to return; it
! refuses when that is untyped (,?) or the prototype cannot be read (ReturnKeepsType). Either
! refusal is for the match as the WHOLE value; `s = clip(n) & 'x'` is text either way. TryFrom
! hands this the match widened out through any bracket that only groups it, so `if (clip(n))` is read at the IF and
! `(clip(n)) = s` at the '='. The type also picks the answer where the match is an ARGUMENT: every value of
! choose() sets the type it returns - a LONG among STRINGs makes it a number - and a method, or a procedure with
! two prototypes, may take another overload. So an argument of choose(), of a method, or of such a procedure refuses;
! one of a builtin or of a procedure with one prototype converts, unless ArgTypeMayChange says the type can still
! pick the answer there. The first argument of assert() is a truth test, as choose()'s is: it fails on zero or blank.
! ------------------------------------------------------------------------------------
VitMatch.MatchIsTruthTest Procedure(LONG pS, LONG pE)
prv  STRING(vs:maxName),AUTO
nxt  STRING(vs:maxName),AUTO
k    long,auto
d    long
c    STRING(vs:maxName),AUTO
  code
  prv = upper(self.TokText(pS - 1))
  nxt = upper(self.TokText(pE + 1))
  case prv
  of 'IF'     orof 'ELSIF' orof 'WHILE' orof 'UNTIL' orof 'NOT' orof '~'  orof 'AND' orof 'OR' orof 'XOR'
    return true
  of 'CASE'   orof 'OF'    orof 'OROF'
    return true
  of 'TO'
    if inlist(upper(self.TokText(self.StmtStart(pS - 1))), 'OF', 'OROF') then return true.
  of 'RETURN'
    if self.IsStmtEndAfter(pE) and self.ReturnKeepsType(pS) then return true.
  of '('
    if upper(self.TokText(pS - 2)) = 'CHOOSE' and (nxt = ',' or nxt = ')') then return true.
  of '='
    if ~self.AssignEqAt(pS - 1) then return true.
    if self.IsStmtEndAfter(pE) and self.DestKeepsType(pS - 1) then return true.
  of '<<'     orof '>'     orof '<<>'   orof '<<='   orof '>='  orof '~=' orof '~<<' orof '~>' orof '=<<' orof '=>'
    return true
  end
  if self.OpCanon(prv) then return true.
  case nxt
  of 'AND' orof 'OR' orof 'XOR' orof 'THEN'
    return true
  end
  if self.CompareFollows(pE) then return true.
  if prv <> '(' and prv <> ',' then return false.
  loop k = pS - 1 to 1 by -1                                               ! the call the match is an argument of
    c = self.TokText(k)
    case c
    of ')' orof ']' orof '}'
      d += 1
    of '(' orof '[' orof '{{'
      if ~d then break.
      d -= 1
    end
  end
  if k < 2 or self.TokText(k) <> '(' then return false.
  c = upper(self.TokText(k - 1))
  if c = 'CHOOSE' then return true.
  if instring('.', c, 1, 1) or self.TokText(k - 2) = '.' then return true. ! a method: its overloads are not read here
  if c = 'ASSERT' and k = pS - 1 and (nxt = ',' or nxt = ')') then return true.
  if self.syms &= NULL then return false.
  if self.syms.MapProtoCount(c) > 1 or self.syms.IncProtoCount(c) > 1 then return true.
  return self.ArgTypeMayChange(c, k, pS)

! ------------------------------------------------------------------------------------
! NOTBOOL support: may the argument that starts at pS, in the call to pNameU whose '(' is at pOpen,
! be read with another type than the one it is given? The name has at most one prototype the run
! has seen. With one, the parameter in that place is read from it: an untyped one (? or <?>) takes
! the type of what it is passed - clip(n) passes the STRING '0', which is true, and n the LONG 0,
! which is false - so it answers yes, as it does when the parameter cannot be found in the
! prototype. With none, the name is taken for a builtin of the Clarion runtime. That holds only
! in a PROGRAM file, once the run has read every file the MAP INCLUDEs. A MEMBER module, or an
! include fragment with no module statement, also calls procedures declared in a MAP the run does
! not read; and an include the run has not read (the includes were not read, or one could not
! be) may prototype the name, more than once. In either case only a name the runtime is known
! to own answers no.
! ------------------------------------------------------------------------------------
VitMatch.ArgTypeMayChange Procedure(STRING pNameU, LONG pOpen, LONG pS)
sg   StringTheory
ch   STRING(1),AUTO
tk   long,auto
x    long,auto
ai   long
pi   long
d    long
q    byte
  code
  if ~self.syms.MapProtoCount(pNameU) and ~self.syms.IncProtoCount(pNameU)
    if self.syms.isMember or self.syms.incMiss or (~self.syms.incRead and self.syms.mapIncl)
      return choose(~self.RuntimeOwns(pNameU, pOpen))
    end
    return false
  end
  loop x = pOpen + 1 to pS - 1
    case self.TokText(x)
    of '(' orof '[' orof '{{'
      d += 1
    of ')' orof ']' orof '}'
      d -= 1
    of ','
      if ~d then ai += 1.
    end
  end
  tk = self.syms.MapProtoTok(pNameU)
  if tk
    sg.setValue(self.syms.ProtoSig(tk))
  elsif self.syms.IncProtoCount(pNameU) = 1
    sg.setValue(self.syms.incProtos.sig,st:clip)
  else
    return true
  end
  x = sg.findByte(40)         ! '('
  if ~x then return true.
  d = 0
  loop x = x + 1 to sg._DataEnd
    ch = sg.valuePtr[x]
    if q
      if ch = '''' then q = 0.
      cycle
    end
    case val(ch)
    of 39                     ! <single quote>
      q = 1
    of 40 orof 91             ! '(' orof '['
      d += 1
    of 41 orof 93             ! ')' orof ']'
      if ~d then return true.
      d -= 1
    of 44                     ! <comma>
      if ~d then pi += 1.
    else
      if pi = ai and ~d and ch <> ' ' and ch <> '<<' and ch <> '*' then return choose(ch = '?').
    end
  end
  return true

! ------------------------------------------------------------------------------------
! NOTBOOL support: may the target of the assigning '=' at pEq take the TYPE of the value it is
! given, rather than convert it? An ANY does - it receives the value of the source, type and
! all - and so does an untyped parameter (? or <?>): clip(n) puts the STRING '0' there, which is
! true, and n the LONG 0, which is false. The target is the name the statement opens with, or
! that name subscripted. It answers yes for an ANY or an untyped parameter, for a name this run
! cannot place, and for any other target, a property among them: only a declared type proves
! that the value converts.
! ------------------------------------------------------------------------------------
VitMatch.DestKeepsType Procedure(LONG pEq)
ss   long,auto
tU   STRING(vs:maxName),AUTO
  code
  if self.syms &= NULL then return true.
  ss = self.StmtStart(pEq)
  if ss < 1 or ss >= pEq then return true.
  if ss + 1 < pEq
    if self.TokText(ss + 1) <> '[' or self.TokText(pEq - 1) <> ']' then return true.
  end
  tU = upper(self.RecvClass(ss))
  if ~tU then tU = self.ImplicitType(self.TokText(ss)).
  if ~tU or tU = 'ANY' or tU = vs:unknownType then return true.
  return false

! ------------------------------------------------------------------------------------
! NOTBOOL support: may the RETURN at pIx hand back the value's own TYPE? A RETURN converts to
! the type the procedure or method is prototyped to return, so this answers no only when that
! prototype was read and names a type. An untyped return (,?) keeps the type - clip(n) returns
! the STRING '0', which is true, and n the LONG 0, which is false - and a prototype the run
! could not read may be one.
! ------------------------------------------------------------------------------------
VitMatch.ReturnKeepsType Procedure(LONG pIx)
tU   STRING(vs:maxName),AUTO
rf   BYTE
kn   BYTE
  code
  if self.syms &= NULL then return true.
  tU = upper(self.syms.ProcReturnRead(pIx, rf, kn))
  if ~kn or ~tU or tU = 'ANY' or tU = vs:unknownType then return true.
  return false

! ------------------------------------------------------------------------------------
! a name the Clarion runtime owns, for a call whose name no prototype the run has read explains:
! the read-only builtins, the ones that show a value or stop the program, and the procedures the
! runtime prototypes in BUILTINS.CLW whose parameters all have a type, so a number and its text
! reach them the same way (ISSTRING, the one with an untyped parameter, is left out). A program
! may declare a procedure of its own with one of these names, so a name from the last group
! answers yes only for a call with as many arguments as one of the runtime's prototypes takes.
! ------------------------------------------------------------------------------------
VitMatch.RuntimeOwns Procedure(STRING pU, LONG pOpen)
ac   long,auto
  code
  if self.ReadOnlyCall(pU) then return true.
  case pU
  of 'MESSAGE' orof 'STOP' orof 'HALT' orof 'ASSERT'
    return true
  end
  ac = self.CallArgCount(pOpen)
  if ac < 0 then return false.
  case pU
  of   'CLIPBOARD' orof 'COMMAND' orof 'LONGPATH' orof 'PATH' orof 'PUSHBIND' orof 'SETCURSOR' orof 'SETPENCOLOR'
  orof 'SETPENSTYLE' orof 'SETPENWIDTH' orof 'SHORTPATH' orof 'SHUTDOWN' orof 'UNBIND'
    return choose(ac <= 1)
  of   'ALERT' orof 'ALIAS' orof 'BEEP' orof 'DESTROY' orof 'DISABLE' orof 'DISPLAY' orof 'DRAGID'
  orof 'DROPID' orof 'ENABLE' orof 'ERASE' orof 'HELP' orof 'HIDE' orof 'IDLE' orof 'PRINTERDIALOG'
  orof 'SETTARGET' orof 'UNHIDE' orof 'UNTIE' orof 'UPDATE'
    return choose(ac <= 2)
  of   'PRINTERDIALOGA' orof 'SELECT'
    return choose(ac <= 3)
  of   'BLANK'
    return choose(ac <= 4)
  of   'GETPOSITION' orof 'SETPOSITION' orof 'UNREGISTER' orof 'UNREGISTEREVENT'
    return choose(ac <= 5)
  of   'ACOS' orof 'ASIN' orof 'ATAN' orof 'BOF' orof 'BYTES' orof 'CHAIN' orof 'CHANGES'
  orof 'CLOSE' orof 'CONTENTS' orof 'COS' orof 'DAY' orof 'DEBUGHOOK' orof 'DELETE' orof 'DUPLICATE'
  orof 'EMPTY' orof 'EOF' orof 'EVALUATE' orof 'EXISTS' orof 'FIXFORMAT' orof 'FLUSH' orof 'FORWARDKEY'
  orof 'FREE' orof 'FREEZE' orof 'GETNULLS' orof 'LOG10' orof 'LOGE' orof 'MONTH' orof 'NAME'
  orof 'NEXT' orof 'NOMEMO' orof 'PACK' orof 'POSITION' orof 'PRESS' orof 'PRESSKEY' orof 'PREVIOUS'
  orof 'RELEASE' orof 'RESUME' orof 'SET3DLOOK' orof 'SETCLIPBOARD' orof 'SETCLOCK' orof 'SETCOMMAND' orof 'SETDROPID'
  orof 'SETEXITCODE' orof 'SETKEYCHAR' orof 'SETKEYCODE' orof 'SETPATH' orof 'SETTODAY' orof 'SIN' orof 'SQRT'
  orof 'STATUS' orof 'STREAM' orof 'TAN' orof 'TYPE' orof 'UNFIXFORMAT' orof 'UNLOAD' orof 'UNLOCK'
  orof 'UNQUOTE' orof 'WATCH' orof 'YEAR'
    return choose(ac = 1)
  of   'CONVERTANSITOOEM' orof 'CONVERTOEMTOANSI' orof 'ENDPAGE' orof 'GETSTATE' orof 'HOLD' orof 'LOCALE' orof 'LOCK'
  orof 'OPEN' orof 'QUOTE' orof 'REMOVE' orof 'SHARE' orof 'SUSPEND'
    return choose(ac >= 1 and ac <= 2)
  of   'BUILD' orof 'COLORDIALOG' orof 'COMPRESS' orof 'NOTIFICATION' orof 'NOTIFY' orof 'POLYGON' orof 'RUN'
  orof 'SET'
    return choose(ac >= 1 and ac <= 3)
  of   'FILEDIALOG' orof 'POPUP' orof 'POST' orof 'PUTINI'
    return choose(ac >= 1 and ac <= 4)
  of   'FILEDIALOGA' orof 'START'
    return choose(ac >= 1 and ac <= 5)
  of   'FONTDIALOG' orof 'GETFONT' orof 'SETFONT'
    return choose(ac >= 1 and ac <= 6)
  of   'FONTDIALOGA'
    return choose(ac >= 1 and ac <= 7)
  of   'BINDEXPRESSION' orof 'CHANGE' orof 'COPY' orof 'FREESTATE' orof 'HOWMANY' orof 'INSTANCE' orof 'ISGROUP'
  orof 'RANDOM' orof 'REGET' orof 'RENAME' orof 'RESET' orof 'SEND' orof 'SETLAYOUT' orof 'SETNULLS'
  orof 'SKIP' orof 'TIED' orof 'UNFREEZE' orof 'WHERE' orof 'WHO'
    return choose(ac = 2)
  of   'CALL' orof 'DECOMPRESS' orof 'DELETEREG' orof 'GETGROUP' orof 'RESTORESTATE' orof 'TIE' orof 'WHAT'
    return choose(ac >= 2 and ac <= 3)
  of   'GETINI' orof 'GETREG'
    return choose(ac >= 2 and ac <= 4)
  of   'BUFFER' orof 'CLONE'
    return choose(ac >= 2 and ac <= 5)
  of   'DATE' orof 'DIRECTORY' orof 'GETREGSUBKEYS' orof 'GETREGVALUES'
    return choose(ac = 3)
  of   'SHOW'
    return choose(ac >= 3 and ac <= 4)
  of   'PUTREG' orof 'REGISTER' orof 'REGISTEREVENT'
    return choose(ac >= 3 and ac <= 5)
  of   'IMAGE'
    return choose(ac >= 3 and ac <= 6)
  of   'LINE'
    return choose(ac >= 4 and ac <= 5)
  of   'BOX' orof 'ELLIPSE' orof 'ROUNDBOX'
    return choose(ac >= 4 and ac <= 6)
  of   'ARC'
    return choose(ac >= 6 and ac <= 7)
  of   'CHORD'
    return choose(ac >= 6 and ac <= 8)
  of   'PIE'
    return choose(ac >= 6 and ac <= 10)
  end
  return false

! ------------------------------------------------------------------------------------
! Is the '=' at pIx an ASSIGNMENT? A comparison is valid only in a condition, so an '=' at
! depth 0 of a statement that opens with its target - a name, a subscript, a member or a
! property - assigns. An '=' inside a bracket, or in a statement that opens with IF, ELSIF,
! CASE, LOOP or another word that takes a condition, compares; so does one with anything but
! the target in front of it. Unsure answers 0, a comparison, which only refuses a rewrite.
! ------------------------------------------------------------------------------------
VitMatch.AssignEqAt Procedure(LONG pIx)
ss   long,auto
x    long,auto
dep  long
w    STRING(vs:maxName),AUTO
  code
  ss = self.StmtStart(pIx)
  if ss < 1 or ss >= pIx then return false.
  loop x = ss to pIx - 1
    w = upper(self.TokText(x))
    if ~dep
      case w
      of   'IF'   orof 'ELSIF'  orof 'WHILE'   orof 'UNTIL' orof 'CASE' orof 'OF'  orof 'OROF'
      orof 'LOOP' orof 'RETURN' orof 'EXECUTE' orof 'AND'   orof 'OR'   orof 'XOR' orof 'NOT'
        return false
      end
      case val(w[1])
      of 65 to 90 orof 95 orof 63 orof 46 orof 91 orof 123
      else
        return false
      end
    end
    dep += self.DepthDelta(w)
  end
  return choose(~dep)

! ------------------------------------------------------------------------------------
! EXPRSTART support: does the token BEFORE pIx bind into the expression the match starts?
! The mirror of ExprContinuesAfter, for the left-hand edge. A rule that replaces a WHOLE
! comparison is right only where the comparison really starts at the match:
!     if 'x' & st.getValue() = st2.getValue()
! reads as ('x' & st.getValue()) = st2.getValue(), so a match starting at st would rewrite
! the wrong comparison and the result would still compile. The tokens that bind into the
! match are the ones at a tighter level than a comparison (& + - * / ^ %) and the
! comparisons themselves, which group left to right: in  x = a = b  the left operand of
! the second = is  x = a . An '=' that assigns (AssignEqAt) binds nothing: its left side is the target, and a
! comparison cannot be assigned. A bracket, a comma, a keyword such as IF or AND, or a line
! start leave the match standing - and so do NOT and ~, which bind more loosely than a
! comparison: ~a = b is ~(a = b). The LRM says so, and the compiler agrees, measured for
! strings, numbers and getValue() alike.
! ------------------------------------------------------------------------------------
VitMatch.ExprContinuesBefore Procedure(LONG pIx)
prv  StringTheory
  code
  if pIx < 2 or self.TokIsEOL(pIx - 1) then return false. ! a statement starts here - nothing in front
  prv.setValue(self.TokText(pIx - 1))
  if self.OpCanon(prv.getValue()) then return true.       ! a comparison with more than one spelling, spaced ones included
  if prv.getValue() = '=' and self.AssignEqAt(pIx - 1) then return false.
  case prv.getValue()
  of '&' orof '*'  orof '+' orof '-'   orof '/'   orof '^'  orof '%'
    return true
  of '=' orof '<<' orof '>' orof '<<>' orof '<<=' orof '>=' orof '~=' orof '~<<' orof '~>' orof '=<<' orof '=>'
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
! A property's braces count too (DepthDelta), but a PROP assignment
! (`?Ctl{PROP:Text} = clip(x)`) closes them before its '=', so it still reads as depth 0
! and is refused, which is the safe direction: that one really is an assignment.
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
! A '.' in a pattern is a block TERMINATOR when it ends a fragment - the last token of
! the pattern, or the token before an interior ';' - because a member dot is always
! followed by a name. `then cycle.` and `then return c.` are the shapes. The pattern rows
! carry no token type, so this is decided by position. Leaves the patQ buffer on row pP.
! ------------------------------------------------------------------------------------
VitMatch.PatDotEnds Procedure(LONG pP)
pdEnds long,auto
  code
  if pP >= self.patCount
    pdEnds = true
  else
    get(self.patQ, pP + 1)
    pdEnds = choose(~errorcode() and ~self.patQ.mvx and not self.patQ.tok &= NULL and self.patQ.tok = ';')
  end
  get(self.patQ, pP)
  return pdEnds

! ------------------------------------------------------------------------------------
VitMatch.TokType Procedure(LONG pIx)
  code
  if pIx < 1 or pIx > self.tk.records() then return ''.
  get(self.tk.tokens, pIx)
  if errorcode() then return ''.
  return self.tk.tokens.type

! ------------------------------------------------------------------------------------
! How far a token moves the bracket depth: ( [ and a property's { open, ) ] } close. The
! braces count because the comma in ?List{PROPLIST:Width, 1} belongs to the property, not to
! the argument list the property stands in - an extent that stopped there would take the
! property's index for the next argument.
! ------------------------------------------------------------------------------------
VitMatch.DepthDelta Procedure(STRING pTok)
  code
  case pTok
  of '(' orof '[' orof '{{'
    return 1
  of ')' orof ']' orof '}'
    return -1
  end
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
! VitGolden - golden-format test runner
! File format:  === case <name> / --- rules / --- input, then --- expect (the exact match
! report, see VitMatch.inc) or --- output (the rewritten source); optional --- select and
! --- userrules blocks.
! ====================================================================================
VitGolden.RunFile Procedure(STRING pFn, StringTheory pOut)
src     StringTheory
! #Removed as not used: line    StringTheory
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
  src.lineEndings(st:unix)                                          ! replace all <carriage return> with <line feed>
  src.split('<10>')
  loop x = 1 to src.records()
    src.setValueFromLine(x)
    if src._DataEnd > 7 and src.valuePtr[1 : 8] = '=== case'
      if started
        self.RunCase(name.getValue(), rules, usrBlk, input, expect, output, selBlk, pOut)
      end
      started = true
      name.setValue(src.slice(9))
      name.trim()
      rules.free()
      usrBlk.free()
      input.free()
      expect.free()
      output.free()
      selBlk.free()
      self.caseWidth = 0
      state = 0
      cycle
    end
    if src._DataEnd > 9 and src.valuePtr[1 : 10] = '--- width '     ! the width the rewriter respects for this case, on the same line
      self.caseWidth = src.slice(11)
      cycle
    end
    if src._DataEnd > 12 and src.valuePtr[1 : 13] = '--- userrules' ! user-rulefile block for this case
      state = 6
      cycle
    end
    if src._DataEnd > 8 and src.valuePtr[1 : 9] = '--- rules'
      state = 1
      cycle
    end
    if src._DataEnd > 8 and src.valuePtr[1 : 9] = '--- input'
      state = 2
      cycle
    end
    if src._DataEnd > 9 and src.valuePtr[1 : 10] = '--- expect'
      state = 3
      cycle
    end
    if src._DataEnd > 9 and src.valuePtr[1 : 10] = '--- output'
      state = 4
      cycle
    end
    if src._DataEnd > 9 and src.valuePtr[1 : 10] = '--- select'     ! selection for this case
      state = 5
      cycle
    end
    case state
    of 1
      rules.append(src.getValue() & '<13,10>')
    of 2
      input.append(src.getValue() & '<13,10>')
    of 3
      expect.append(src.getValue() & '<13,10>')
    of 4
      output.append(src.getValue() & '<13,10>')
    of 5
      selBlk.append(src.getValue() & '<13,10>')
    of 6
      usrBlk.append(src.getValue() & '<13,10>')
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
! #Merged into rep: res    StringTheory
rwLog  StringTheory
selLn  StringTheory       ! one --- select line
! #Removed as not used: selUp  StringTheory
sStyle STRING(vr:maxName) ! the selection's style name, for Resolve - a name is bounded by vr:maxName (a fixed string by ruling, 14 Sep 2026)
sGrp   StringTheory
sNoGrp StringTheory
i      long,auto
  code
  self.caseCount += 1
  crl.ParseText(pRules)
  if pUser._DataEnd                  ! append-load the case's user rulefile block -
    crl.LoadUserText(pUser)          !     the same path as --userrules= (ids offset by vr:userBase)
  end
  crl.Lint()
  ! parse the --- select block (style <name> / group <names> / nogroup <names>)
  ! and ALWAYS resolve - the golden runner uses the same resolver as the CLI, so a
  ! case with no select block runs the file defaults through the same code path.
  if pSelect._DataEnd
    pSelect.LineEndings(st:unix)
    pSelect.split('<10>',,,,st:clip,st:left)
    loop i = 1 to pSelect.records()
      selLn.setValue(pSelect.getLine(i))
! #Removed as unnecessary:       selLn.trim()
      if ~selLn._DataEnd then cycle.
      if selLn._DataEnd > 6 and upper(selLn.valuePtr[1 : 6]) = 'STYLE '
        sStyle = left(selLn.valuePtr[7 : selLn._DataEnd])
      elsif selLn._DataEnd > 6 and upper(selLn.valuePtr[1 : 6]) = 'GROUP '
        if sGrp._DataEnd then sGrp.append(',').
        sGrp.append(selLn.valuePtr[7 : selLn._DataEnd])
      elsif selLn._DataEnd > 8 and upper(selLn.valuePtr[1 : 8]) = 'NOGROUP '
        if sNoGrp._DataEnd then sNoGrp.append(',').
        sNoGrp.append(selLn.valuePtr[9 : selLn._DataEnd])
      else
        crl.AddIssue(0, vr:sevError, 'bad --- select line (expected style/group/nogroup): ' & selLn.getValue())
      end
    end
  end
  crl.Resolve(clip(sStyle), sGrp.getValue(), sNoGrp.getValue())
  if crl.ErrorCount()
    self.failCount += 1
    pOut.append('FAIL ' & clip(pName) & ' - rule lint/resolve errors:<13,10>')
    loop i = 1 to records(crl.issues)
      get(crl.issues, i)
      pOut.append('  line ' & crl.issues.lineNo & ' ' & choose(crl.issues.sev = vr:sevError, 'ERROR', 'WARN ') & ' ' & clip(crl.issues.msg) & '<13,10>')
    end
    return
  end
  ctk.ParseText(pInput)              ! ParseText(StringTheory,<fileName>,pMergeLabels) overload
  csym.Build(ctk)                    ! golden cases match TYPED, like the real engine

  if pOutput._DataEnd                ! ---- rewrite mode ----
    rw.Init(crl, ctk)
    rw.maxWidth = self.caseWidth     ! the --- width block, so a case can reach the continuation policy the engine sets per file
    rw.SetSymbols(csym)
    rw.ApplyAll(rwLog)
    ctk.JoinToks(rep)                ! whole file back to text, as-is format
    if self.SameReport(rep, pOutput)
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
      pOut.append(rep)
      if rep._DataEnd
        if rep.valuePtr[rep._DataEnd] <> '<10>' then pOut.append('<13,10>').
      end
      pOut.append('--- log ---<13,10>')
      pOut.append(rwLog)
      pOut.append('--- end ---<13,10>')
    end
    return
  end

  m.Init(crl, ctk)                   ! ---- match-report mode ----
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
na  long,auto
i   long,auto
  code
  a.setValue(pA)
  b.setValue(pB)
  a.lineEndings(st:unix) ! replace all <carriage return> with <line feed>
  b.lineEndings(st:unix) ! replace all <carriage return> with <line feed>
  a.clip('<32,10>')
  a.split('<10>',,,,st:clip)
  b.clip('<32,10>')
  b.split('<10>',,,,st:clip)
  na = a.records()
  if na <> b.records() then return false.
  loop i = 1 to na
    a.setValueFromLine(i)
    b.setValueFromLine(i)
    if a._DataEnd <> b._DataEnd or (a._DataEnd and a.valuePtr[1 : a._DataEnd] <> b.valuePtr[1 : b._DataEnd]) then return false.
  end
  return true
