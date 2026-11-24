! VitRewrite - the rewriter of VitTransform
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! See VitRewrite.inc header. Splicing uses these vitTokenize primitives:
! DeleteToks disposes strBefore (so the leading
! trivia of the first matched token is saved and restored around the splice),
! InsertString inserts tokenized text AT the given position, and
! InsertStringAtEOL walks to the line end (continuation-aware) and merges
! ' ! <note>' into the EOL trivia.
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

! ====================================================================================
VitRewrite.Construct Procedure()
  code
  self.m     &= new VitMatch
  self.onceQ &= new OnceQType
  self.cRules &= new CacheRuleQType
  self.cMatch &= new CacheMatchQType
  self.cBind  &= new CacheBindQType
  self.plan   &= NULL
  self.rl    &= NULL
  self.tk    &= NULL

! ------------------------------------------------------------------------------------
VitRewrite.Destruct Procedure()
  code
  dispose(self.m)
  if not self.onceQ &= NULL
    free(self.onceQ)
    dispose(self.onceQ)
  end
  if not self.cRules &= NULL then free(self.cRules) ; dispose(self.cRules).
  if not self.cMatch &= NULL then free(self.cMatch) ; dispose(self.cMatch).
  if not self.cBind  &= NULL then free(self.cBind)  ; dispose(self.cBind).

! ------------------------------------------------------------------------------------
VitRewrite.Init Procedure(VitRules pRl, VitTokenize pTk)
  code
  self.rl &= pRl
  self.tk &= pTk
  self.m.Init(pRl, pTk)
  self.changeCount = 0
  self.skipCount   = 0
  self.widthSkips  = 0 !
  free(self.onceQ)     ! ONCE is per file
  free(self.cRules)    ! the match cache is per file too
  free(self.cMatch)
  free(self.cBind)
  self.cVer = -1
  self.cHits = 0
  self.cMiss = 0
  self.cWalks = 0
  self.cMembers = 0

! ------------------------------------------------------------------------------------
VitRewrite.SetSymbols Procedure(VitSymbols pSyms)
  code
  self.syms   &= pSyms
  self.m.syms &= pSyms

! ------------------------------------------------------------------------------------
VitRewrite.ApplyAll Procedure(StringTheory pLog)
r  long,auto
  code
  if self.rl &= NULL or self.tk &= NULL then return 0.
  loop r = 1 to records(self.rl.rules)
    get(self.rl.rules, r)
    if errorcode() then break.
    if self.rl.rules.kind <> vr:kindRule then cycle.
    if self.rl.rules.skip then cycle.
    if ~self.rl.GroupActive(self.rl.rules.groupId) then cycle. ! unselected GROUP
    self.ApplyRule(r, pLog)
  end
  return self.changeCount

! ------------------------------------------------------------------------------------
! Capture all matches for one rule, then apply them right-to-left so earlier
! token positions stay valid. Line numbers are refreshed afterwards.
! ------------------------------------------------------------------------------------
VitRewrite.ApplyRule Procedure(LONG pRow, StringTheory pLog)
mx        long,auto
svChanges long,auto
spA       long,auto ! the match's span and the stream's length before ApplyOne - NotePatch's input
spB       long,auto
spN       long,auto
spC       long,auto !   and the change count, to tell an applied match from a skipped one
  code
  get(self.rl.rules, pRow)
  if errorcode() then return.
  ! ONCE already applied for this file?
  if self.rl.rules.once and self.OnceDone(self.rl.rules.ruleId) then return.
  ! grouped dispatch: a known answer, or a walk that answers for the whole group (GroupScan);
  ! the second load cannot fail, GroupScan having stored pRow's answer
  if self.dispatch
    self.CacheFresh()
    if self.CacheLoad(pRow)
      self.cHits += 1
    else
      self.GroupScan(pRow)
      if ~self.CacheLoad(pRow) then return.
    end
    ! the walk left the rules buffer on another rule; the apply below reads this one
    get(self.rl.rules, pRow)
  else
    self.ClassicScan(pRow)
  end
  if ~records(self.m.matches) then return.
  svChanges = self.changeCount
  loop mx = records(self.m.matches) to 1 by -1
    get(self.m.matches, mx)
    if errorcode() then cycle.
    spA = self.m.matches.sPos ; spB = self.m.matches.ePos ; spN = self.tk.records() ; spC = self.changeCount
    self.ApplyOne(mx, pLog)
    if self.changeCount <> spC ! it applied: the span, as the postings patch needs it
      self.m.NotePatch(spA, spB, spB - spA + 1 + self.tk.records() - spN)
    end
    ! ONCE: at most one APPLIED match per file. The matcher stops at its first clean match, but a
    ! match it skipped for an interior comment before that one is still in the list, and CarryChk
    ! can carry it - so the first application ends the loop here, or the rule would fire twice.
    if self.rl.rules.once and self.changeCount <> svChanges then break.
  end
  if self.changeCount <> svChanges
    if self.rl.rules.once
      clear(self.onceQ)
      self.onceQ.ruleId = self.rl.rules.ruleId
      add(self.onceQ)
    end
    self.tk.SetLineNumbers()   ! token positions/lines changed
    self.m.Changed()           ! anchor counts stale - token stream mutated. (REBUILD PER FIRING RULE - do not defer it to once per pass. Every edit shifts the file TAIL, so deferral cascades one wave
                               !   per pass, and it flips who wins OVERLAPPING sites, costing byte-parity. Per-firing-rule is the correct freshness contract; make the rebuild cheaper instead.)
    if not self.syms &= NULL
      self.syms.dirty = 1      ! positions shifted - rebuild LAZILY at the next consumer (EnsureFresh); untyped rule stretches skip the rebuild entirely
    end
  end

! ------------------------------------------------------------------------------------
VitRewrite.ClassicScan Procedure(LONG pRow)
scratch   StringTheory
  code
  free(self.m.matches)
  free(self.m.bindRecs)
  self.m.capture = true
  self.m.MatchRule(pRow, scratch) ! rules buffer now holds this rule
  self.m.capture = false

! ------------------------------------------------------------------------------------
VitRewrite.OnceDone Procedure(LONG pRuleId)
mx  long,auto
  code
  loop mx = 1 to records(self.onceQ)
    get(self.onceQ, mx)
    if errorcode() then break.
    if self.onceQ.ruleId = pRuleId then return 1.
  end
  return 0

! ------------------------------------------------------------------------------------
! GROUPED DISPATCH (--dispatch=grouped). The classic loop gives every rule its
! own walk of the file, every pass. Here a rule's matches, once found, are kept - with the
! stream version they were found on - and thrown away the moment the stream changes; and a
! rule that has to walk takes with it every later rule of the pass whose anchor is the same
! key (MatchGroup), so an anchor's occurrences are walked once for all of them. Both give
! the classic answer by construction: a cached match is applied only to the stream it was
! found on, and a shared walk gives each member exactly the turns its own walk would have.
! On a settled pass - every last pass, and the only pass on a file the rules leave alone -
! each anchor is walked once instead of once per rule; on a changing pass each firing costs
! the re-walks the classic loop costs. --dispatch=classic gives each rule its own walk.
! ------------------------------------------------------------------------------------
VitRewrite.CacheFresh Procedure()
  code
  if self.cVer = self.m.streamVer then return.
  free(self.cRules) ; free(self.cMatch) ; free(self.cBind)
  if not self.m.pendMissQ &= NULL then free(self.m.pendMissQ). ! names a discarded walk deferred go with it
  self.cVer = self.m.streamVer

! ---- 1 = pRow's matches on this stream are known: m.matches/m.bindRecs hold them again, and
!      the counters and the receiver list move as the scan this load stands in for would have
!      moved them (the walk itself moved nothing - see MatchGroup)
VitRewrite.CacheLoad Procedure(LONG pRow)
mx  long,auto
b   long,auto
n   long,auto
  code
  self.cRules.ruleRow = pRow
  get(self.cRules, self.cRules.ruleRow)
  if errorcode() then return 0.
  free(self.m.matches) ; free(self.m.bindRecs)
  loop mx = 1 to records(self.cMatch)
    get(self.cMatch, mx)
    if errorcode() then break.
    if self.cMatch.ruleRow <> pRow then cycle.
    clear(self.m.matches)
    self.m.matches.sPos    = self.cMatch.sPos
    self.m.matches.ePos    = self.cMatch.ePos
    self.m.matches.skipped = self.cMatch.skipped
    self.m.matches.ruleRow = pRow
    add(self.m.matches)
    n = records(self.m.matches)
    loop b = 1 to records(self.cBind)
      get(self.cBind, b)
      if errorcode() then break.
      if self.cBind.ruleRow <> pRow or self.cBind.seq <> self.cMatch.seq then cycle.
      clear(self.m.bindRecs)
      self.m.bindRecs.matchIx = n
      self.m.bindRecs.mvx     = self.cBind.mvx
      self.m.bindRecs.sPos    = self.cBind.sPos
      self.m.bindRecs.ePos    = self.cBind.ePos
      add(self.m.bindRecs)
    end
  end
  ! the receivers the walk refused for this rule go on the list now, in the order it met them
  ! (a later load finds none - they are taken off below); the counters move at every load,
  ! the first being the rule's turn and a later one a scan classic would have repeated
  loop b = 1 to records(self.m.pendMissQ)
      get(self.m.pendMissQ, b)
      if errorcode() then break.
      if self.m.pendMissQ.ruleRow = pRow then self.m.NoteMissName(self.m.pendMissQ.recv).
    end
    loop b = records(self.m.pendMissQ) to 1 by -1
      get(self.m.pendMissQ, b)
      if errorcode() then cycle.
      if self.m.pendMissQ.ruleRow = pRow then delete(self.m.pendMissQ).
    end
  self.m.chainUnres  += self.cRules.dChain
  self.m.rtFallbacks += self.cRules.dRtf
  self.m.skipCount   += self.cRules.dSkip
  self.m.matchCount  += self.cRules.dMatch
  return 1

! ---- keep the matches tagged pRow in m.matches, with their bindings and the counters the
!      scan moved, as the answer for pRow on the current stream
VitRewrite.CacheStore Procedure(LONG pRow, LONG pDChain, LONG pDRtf, LONG pDSkip, LONG pDMatch)
mx   long,auto
b    long,auto
seq  long
  code
  clear(self.cRules)
  self.cRules.ruleRow = pRow
  self.cRules.dChain  = pDChain
  self.cRules.dRtf    = pDRtf
  self.cRules.dSkip   = pDSkip
  self.cRules.dMatch  = pDMatch
  loop mx = 1 to records(self.m.matches)
    get(self.m.matches, mx)
    if errorcode() then break.
    if self.m.matches.ruleRow <> pRow then cycle.
    seq += 1
    clear(self.cMatch)
    self.cMatch.ruleRow = pRow
    self.cMatch.seq     = seq
    self.cMatch.sPos    = self.m.matches.sPos
    self.cMatch.ePos    = self.m.matches.ePos
    self.cMatch.skipped = self.m.matches.skipped
    add(self.cMatch)
    loop b = 1 to records(self.m.bindRecs)
      get(self.m.bindRecs, b)
      if errorcode() then break.
      if self.m.bindRecs.matchIx <> mx then cycle.
      clear(self.cBind)
      self.cBind.ruleRow = pRow
      self.cBind.seq     = seq
      self.cBind.mvx     = self.m.bindRecs.mvx
      self.cBind.sPos    = self.m.bindRecs.sPos
      self.cBind.ePos    = self.m.bindRecs.ePos
      add(self.cBind)
    end
  end
  self.cRules.nMatch = seq
  add(self.cRules, self.cRules.ruleRow)

! ---- a miss: pRow walks, and every later rule of the pass whose anchor is the same key
!      walks with it (see MatchGroup); each member's answer is cached
VitRewrite.GroupScan Procedure(LONG pRow)
anchor   StringTheory
a2       StringTheory
scratch  StringTheory
key      STRING(80)
k2       STRING(80)
aCount   long,auto
ix       long,auto
cand     long,auto
mx       long,auto
sChain   long,auto
sRtf     long,auto
sSkip    long,auto
sMatch   long,auto
dChain   long,auto
dRtf     long,auto
dSkip    long,auto
dMatch   long,auto
  code
  free(self.m.matches) ; free(self.m.bindRecs) ; free(self.m.grpQ)
  self.cMiss += 1
  sChain = self.m.chainUnres ; sRtf = self.m.rtFallbacks ; sSkip = self.m.skipCount ; sMatch = self.m.matchCount
  self.m.capture = true
  aCount = self.m.EnterRule(pRow, anchor)
  if aCount > 0 and anchor._DataEnd <= size(self.m.grpQ.anchorTx) and not self.m.anchorPost &= NULL and not self.plan &= NULL
    self.m.FreqKey(anchor.getValue(), key)
    if self.m.FindFirstPost(key)
      self.m.AddMember(pRow, anchor)
      ! the later rules of this pass whose rarest literal is this key join the walk. litIdx
      ! names every rule with the key among its literals; EnterRule says whether it is the
      ! one PickAnchor chooses on this stream, and leaves the rule set up for AddMember.
      clear(self.m.litIdx)
      self.m.litIdx.keyText = key
      ix = position(self.m.litIdx)
      loop ix = ix to records(self.m.litIdx)
        get(self.m.litIdx, ix)
        if errorcode() then break.
        if self.m.litIdx.keyText <> key then break.
        cand = self.m.litIdx.ruleRow
        if cand <= pRow then cycle.                                               ! earlier rules have had their turn this pass
        self.plan.ruleRow = cand
        get(self.plan, self.plan.ruleRow)
        if errorcode() then cycle.                                                ! not visited this pass (SKIP, a group switched off, --only=, --skip=)
        self.cRules.ruleRow = cand
        get(self.cRules, self.cRules.ruleRow)
        if ~errorcode() then cycle.                                               ! already answered on this stream
        if self.m.EnterRule(cand, a2) <= 0 then cycle.                            ! nothing for it to match here
        if self.rl.rules.once and self.OnceDone(self.rl.rules.ruleId) then cycle. ! ONCE and spent: ApplyRule would not scan it
        if a2._DataEnd > size(self.m.grpQ.anchorTx) then cycle.
        self.m.FreqKey(a2.getValue(), k2)
        if k2 <> key then cycle.                                                  ! its rarest literal is another key: another walk
        self.m.AddMember(cand, a2)
      end
      self.cWalks += 1
      self.cMembers += records(self.m.grpQ) - 1
      self.m.MatchGroup(key, scratch)
      self.m.capture = false
      loop mx = 1 to records(self.m.grpQ)
        get(self.m.grpQ, mx)
        if errorcode() then break.
        self.CacheStore(self.m.grpQ.ruleRow, self.m.grpQ.dChain, self.m.grpQ.dRtf, self.m.grpQ.dSkip, self.m.grpQ.dMatch)
      end
      return
    end
  end
  ! not groupable - a pattern with no literal, an anchor absent or too long, or no postings:
  ! the walk MatchRule gives it, and its answer is kept all the same
  self.m.MatchRule(pRow, scratch)
  self.m.capture = false
  dChain = self.m.chainUnres - sChain ; dRtf = self.m.rtFallbacks - sRtf ; dSkip = self.m.skipCount - sSkip ; dMatch = self.m.matchCount - sMatch
  self.m.chainUnres = sChain ; self.m.rtFallbacks = sRtf ; self.m.skipCount = sSkip ; self.m.matchCount = sMatch
  self.CacheStore(pRow, dChain, dRtf, dSkip, dMatch)                              ! the walk moved nothing; the load does


! ------------------------------------------------------------------------------------
! Could this leading trivia put the token it belongs to in COLUMN 1? Trivia that ENDS at a
! line feed always does; trivia holding an indent never does - an indent is spaces AFTER the
! feed, and column 1 is where Clarion expects a LABEL. NO TRIVIA AT ALL answers 1 as well,
! and there it means MAYBE: a token glued to the one in front of it carries no trivia either.
! The caller turns a 1 into "do not force mid-line" and the splice settles it from the token
! in front, which is the only thing that can tell the two apart.
! ------------------------------------------------------------------------------------
VitRewrite.LeadIsCol1 Procedure(StringTheory pLead)
  code
  if ~pLead._DataEnd then return 1.
  if pLead.valuePtr[pLead._DataEnd] = '<10>' then return 1.
  return 0

! ------------------------------------------------------------------------------------
! Is the statement at pTok one of an EXECUTE's ARMS - is the innermost block round it an
! EXECUTE? A statement inside an IF, a LOOP or a BEGIN that is an arm is in a sequence of its
! own and answers 0. The walk goes back over the level marks to the enclosing opener: a '-'
! met on the way closed a block that ended before pTok, so the '+' matching it is counted off
! against it, and the first '+' left over is the opener asked. It stops at the CODE or ROUTINE
! that starts the body. Returns the EXECUTE token, 0 = not an arm. The engine asks the same
! question of its builtins (VitEngine.ArmOfExecute).
! ------------------------------------------------------------------------------------
VitRewrite.ArmOfExecute Procedure(LONG pTok)
closed long
x      long,auto
  code
  loop x = pTok - 1 to 1 by -1
    get(self.tk.tokens, x)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    case self.tk.tokens.level
    of '-'
      closed += 1
    of '+'
      if closed
        closed -= 1
      else
        if upper(self.tk.tokens.tok) = 'EXECUTE' then return x.
        return 0
      end
    else
      if ~closed
        case upper(self.tk.tokens.tok)
        of 'CODE' orof 'ROUTINE'
          return 0
        end
      end
    end
  end
  return 0

! ------------------------------------------------------------------------------------
VitRewrite.ApplyOne Procedure(LONG pMx, StringTheory pLog)
sPos     long,auto
ePos     long,auto
ln       long,auto
noOp     long
svML     byte,auto
overWide long ! WidthChk verdict
wResult  long ! computed result-line width
oldSpan  StringTheory
newTxt   StringTheory
noteTxt  StringTheory
lead     StringTheory
repMid   byte,auto
oldExact StringTheory
carried  byte
outerOk  byte
outNoOp  byte
spcOnly  byte ! OuterCarry for an ordinary one-line match: only the spacing is at stake
oneLine  byte
lineShr  byte ! LineShareChk verdict: a DELETE or COMMENT whose statement does not have the rest of its line to itself
execArm  byte ! ExecArmChk verdict: the match is an EXECUTE arm and the rule would change how many statements stand there
! ---- insTxt is newTxt as spliced in: a `stmt ; stmt` replacement broken into lines (SplitStmts)
insTxt   StringTheory
  code
  get(self.m.matches, pMx)
  if errorcode() then return.
  sPos = self.m.matches.sPos
  ePos = self.m.matches.ePos
  self.curMx = pMx
  ln = self.tk.MapLine(self.m.LineOf(sPos))             ! log lines in SOURCE coordinates for the preview (MapLine is identity in batch); ln is log-only in this proc
  self.m.SpanText(sPos, ePos, oldSpan)

  if self.m.matches.skipped and choose(self.rl.rules.isDelete or self.rl.rules.isComment) ! a deletion or a comment-out would lose the comment inside
    self.skipCount += 1                                 !   the span; an ordinary replacement tries CarryChk below
    pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' SKIP interior-comment: ' & oldSpan.getValue() & '<13,10>')
    return
  end

  ! statement surgery: what the line keeps after it decides
  if self.rl.rules.isDelete or self.rl.rules.isComment
    do LineShareChk
    if lineShr then return.
  end
  do ExecArmChk
  if execArm then return.

  if self.rl.rules.isDelete
    self.m.TokBefore(sPos, lead)
    self.tk.DeleteToks(sPos, ePos)
    if lead._DataEnd
      self.tk.PrependStrBefore(sPos, lead.getValue())   ! keep indent/preceding trivia; trailing comment already lives on the EOL token
    end
    self.changeCount += 1
    pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' DELETE: ' & oldSpan.getValue() & '<13,10>')
    return
  end

  if self.rl.rules.isComment                            ! comment-out mode - the statement survives as
    svML = self.multiLine                               !   ONE comment line at the original indent. Tokens are DELETED and the
    self.RenderSpan(sPos, ePos, oldExact)               !   text carried as trivia on the survivor token, so nothing can ever
    self.multiLine = svML                               !   re-match it: fixpoint-safe by construction, and the LINE survives
    noteTxt.free()                                      !   (line map stays 1:1 - the zebra deletion corner never arises).
    if not self.rl.rules.noteQ &= NULL                  ! NOTE(...) = the human explanation; bindings resolve BEFORE DeleteToks
      if records(self.rl.rules.noteQ)
        self.BuildNote(noteTxt)
      end
    end
    if ~noteTxt._DataEnd then noteTxt.setValue('removed by rule ' & self.rl.rules.ruleId).
    self.m.TokBefore(sPos, lead)
    self.tk.DeleteToks(sPos, ePos)
    self.tk.PrependStrBefore(sPos, lead.getValue() & '! ' & oldExact.getValue() & '  ! ' & noteTxt.getValue())
    self.changeCount += 1
    pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' COMMENT: ' & oldSpan.getValue() & '<13,10>')
    return
  end

  self.multiLine = false
  carried = 0
  if self.m.matches.skipped                             ! a comment inside the span: build with the span's own trivia kept,
    do CarryChk                                         !   and take the conversion only if every comment came through once
    if ~carried
      noteTxt.free()                                    ! the rule's NOTE, built BEFORE OuterCarry moves a token: its bindings are read from the stream
      if not self.rl.rules.noteQ &= NULL
        if records(self.rl.rules.noteQ) then self.BuildNote(noteTxt).
      end
      do OuterCarry                                     ! the other half: the match's unchanged head and tail keep their
      if outerOk                                        !   tokens, comments and all; only the middle is rebuilt - and the
                                                        !   note goes on, as it does for every other applied match
        if noteTxt._DataEnd
          self.tk.InsertStringAtEOL(sPos, noteTxt.getValue())
        end
        return
      end
      if outNoOp then return.
      self.skipCount += 1
      pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' SKIP interior-comment: ' & oldSpan.getValue() & '<13,10>')
      return
    end
  else
    do OneLineChk                                       ! a match on one line keeps your spacing on every token the rule
    if oneLine                                          !   leaves alone; only the part that changes is spaced as the rule
      noteTxt.free()                                    !   spells it
      if not self.rl.rules.noteQ &= NULL
        if records(self.rl.rules.noteQ) then self.BuildNote(noteTxt).
      end
      spcOnly = 1
      do OuterCarry
      spcOnly = 0
      if outerOk
        if noteTxt._DataEnd
          self.tk.InsertStringAtEOL(sPos, noteTxt.getValue())
        end
        return
      end
    end
    self.BuildRep(newTxt)
  end
  if ~newTxt._DataEnd
    pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' ERROR empty replacement built - not applied<13,10>')
    return
  end
  do NoOpCheck                                          ! replacement identical to source span: not a change
  if noOp then return.
  self.preserved = carried
  if ~carried and self.multiLine and self.maxWidth > 0  ! width policy: a continuation collapse may not
    do WidthChk                                         !   produce a line wider than maxWidth - respect the codebase width
    if overWide                                         !   (+ a few chars) capped at ~200.
      self.keepCont  = 1                                ! instead of refusing, re-render the replacement with the
      self.contEmits = 0                                !   span's ORIGINAL continuations preserved - the conversion applies
      self.BuildRep(newTxt)                             !   and the formatting survives
      self.keepCont  = 0
      if self.contEmits <> 1 or ~newTxt._DataEnd        ! 0 = trivia vanished; >1 = the metavar is duplicated in the
        ! DO NOT LOSE THE TRANSFORM. Do NOT `return` here: that refuses the conversion outright
        ! whenever the original continuations cannot be carried into the replacement. Build it
        ! flat and accept the wide line instead - SplitWideLines runs after convergence,
        ! alongside AlignComments, and breaks any over-wide line at a sensible point. A wide
        ! line that gets tidied later is strictly better than a conversion that never happened.
        ! widthSkips counts it so the report can say how often this path was taken.
        self.keepCont  = 0
        self.BuildRep(newTxt)                           ! rebuild FLAT - the keepCont attempt above left newTxt half-formed
        self.widthSkips += 1
        pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' width: flattened to ' & wResult & |
                    ' chars (limit ' & self.maxWidth & ') - continuations not preservable, line split later<13,10>')
      else
        self.preserved = 1
      end
    end
  end
  if not self.rl.rules.noteQ &= NULL
    if records(self.rl.rules.noteQ)
      self.BuildNote(noteTxt)
    end
  end

  do SplitStmts                                         ! a two-statement replacement goes in as two lines
  self.m.TokBefore(sPos, lead)
  ! COLUMN 1 OR NOT, and the scratch tokenizer has to be told. Parsed as though it began a
  ! line, a replacement starting RETURN, EXIT or ACCEPT comes back typed as a LABEL, and that
  ! type is copied into the stream. The trivia is put back a line later so the token is not in
  ! column 1 at all - but nothing re-types it, and SetLineNumbers only ever converts a reserved
  ! word TO a label, never back. Structure keywords survive because they force a re-parse;
  ! RETURN, EXIT, ACCEPT, NOT, DO, BREAK and CYCLE do not, so the mis-type lasts the run.
  ! What LeadIsCol1 reads is the TRIVIA ALONE: trivia ending at a line feed is column 1, an
  ! indent after the feed is not, and no trivia at all is a maybe the splice settles itself.
  repMid = choose(~self.LeadIsCol1(lead))
  self.tk.DeleteToks(sPos, ePos)
  self.tk.InsertString(sPos, insTxt, repMid)
  self.tk.SetStrBefore(sPos, lead.getValue())           ! original leading trivia wins over any parse artefact
  if noteTxt._DataEnd
    ! a note for a line that ends in a '|' continuation belongs AFTER
    ! the bar - Clarion ignores everything past it, so that is where a per-line comment
    ! lives. InsertStringAtEOL walks there and separates the notes it finds already
    ! present (continuationWork); without that separator several notes on one line run
    ! together into a single unreadable string.
    self.tk.InsertStringAtEOL(sPos, noteTxt.getValue())
  end
  self.changeCount += 1
  pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ': ' & oldSpan.getValue() & ' ==> ' & newTxt.getValue() & |
              choose(~carried, choose(~self.preserved, choose(~self.multiLine, '', '   (multi-line span collapsed)'), '   (continuations preserved)'), '   (interior comment carried)') & '<13,10>')

NoOpCheck routine
  ! compare against the EXACT source span (original spacing); identical
  ! replacement = nothing to do. Keeps casing-normalisation rules safe and
  ! stops any rule from driving the fixpoint without changing bytes.
  noOp = false
  if carried then self.keepCont = 1.    ! compare like with like: the carried build kept the span's trivia
  self.RenderSpan(sPos, ePos, oldExact)
  self.keepCont = 0
  ! DO NOT save multiLine here and restore it afterwards - that throws away the one answer that
  ! is actually correct. BuildRep renders each BINDING, and RenderSpan
  ! only inspects trivia for `i > pS`, so a binding of ONE token never looks at trivia at all -
  ! a '|' sitting between '(' and that token is inside the matched SPAN but outside the binding,
  ! leaving multiLine false. The width policy below is then never consulted and the span gets
  ! flattened at any width. The call above renders the WHOLE span and does see it. RenderSpan only
  ! ever SETS multiLine, never clears it, so simply not restoring gives the union of the two
  ! answers - which is right, because DeleteToks removes the span's interior trivia either way.
  if oldExact.equals(newTxt, st:clip) then noOp = true.

! ---- A DELETE or a COMMENT takes a whole statement out, and both assume the statement has the
!      rest of its line to itself. A COMMENT keeps the statement's text as ONE comment in front
!      of the token after it, and a comment runs to the end of the line - so a terminator dot,
!      an ELSE or a second statement after the match would be commented out with it, and the
!      block above loses its end. A DELETE after THEN or ELSE on the same line - `if x then
!      st.crop().` - would leave `if x then .`, a clause with nothing in it, and how the compiler
!      reads that is not settled; a clause whose statements go on below the line keeps a body.
!      Both are refused and logged; the statement stays as written. ----
LineShareChk routine
  data
lsPrv  StringTheory
  code
  lineShr = 0
  if self.rl.rules.isComment
    if ~self.m.TokIsEOL(ePos + 1) then lineShr = 1.
    do LineShareSay
    exit
  end
  if sPos < 2 then exit.
  lsPrv.setValue(self.m.TokText(sPos - 1))
  lsPrv.upper()
  case lsPrv.getValue()
  of 'THEN' orof 'ELSE'
    if ~self.m.TokIsEOL(ePos + 1) then lineShr = 1.
  end
  do LineShareSay

! ---- the refusal, said in the log. skipCount is not touched: it counts a match left alone
!      because a comment inside it had nowhere to go, and the report prints it as comment-skip(s)
LineShareSay routine
  if ~lineShr then exit.
  pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' SKIP ' & choose(~self.rl.rules.isDelete, 'comment-out', 'delete') & |
              ' shares its line: ' & oldSpan.getValue() & '<13,10>')

! ---- An EXECUTE runs ONE of its statements, picked by position, so its arms are counted. A rule
!      that takes a statement out (DELETE, COMMENT), joins two into one (a ';' inside the pattern)
!      or writes one as two (a ';' in the replacement) renumbers every arm below it, and the same
!      value then runs a different statement - it still compiles. So such a match is refused when
!      its statement is an arm, and said. A pattern of two statements reads them as running one
!      after the other, which two arms never do, so it is refused there even when it writes two.
!      A statement inside an IF, a LOOP or a BEGIN that is an arm is in a sequence of its own. ----
ExecArmChk routine
  data
eaT  long,auto
eaN  long
eaD  byte
  code
  execArm = 0
  if self.rl.rules.isDelete or self.rl.rules.isComment then eaD = 1.
  if ~eaD and not self.rl.rules.patQ &= NULL
    loop eaT = 1 to records(self.rl.rules.patQ) - 1
      get(self.rl.rules.patQ, eaT)
      if errorcode() then break.
      if self.rl.rules.patQ.mvx or self.rl.rules.patQ.tok &= NULL then cycle.
      if self.rl.rules.patQ.tok = ';' then eaD = 1 ; break.
    end
  end
  if ~eaD and not self.rl.rules.repQ &= NULL
    loop eaT = 1 to records(self.rl.rules.repQ)
      get(self.rl.rules.repQ, eaT)
      if errorcode() then break.
      if self.rl.rules.repQ.tok &= NULL then cycle.
      if ~eaN and self.rl.rules.repQ.tok = ';' then eaD = 1 ; break.
      eaN += self.m.DepthDelta(clip(self.rl.rules.repQ.tok))
    end
  end
  if ~eaD then exit.
  if ~self.ArmOfExecute(sPos) then exit.
  execArm = 1
  pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' SKIP EXECUTE arm, where each statement is one arm: ' & |
              oldSpan.getValue() & '<13,10>')

! ---- A match whose span holds a comment is not refused outright (the ReplaceToks design, the
!      cheap half). The replacement is built with the bindings' original trivia kept - a comment's
!      trivia is `! text`, its line break and the next indent, the same thing the width policy
!      keeps - and taken only when every comment inside the span comes through EXACTLY ONCE. A
!      comment on a token the rule itself spells, a binding the replacement drops, or a binding it
!      repeats, each fail that test, and the match is skipped: no comment is ever lost
!      silently. Non-comment trivia (absorbed OMIT prose) is held to the same test. ----

! ---- Is the whole match on one line? Only then does OuterCarry run for an ordinary match: a match
!      that runs over several lines keeps its continuations through keepCont and the width policy. ----
OneLineChk routine
  data
lz  long,auto
lb  StringTheory
  code
  oneLine = 1
  loop lz = sPos + 1 to ePos
    self.m.TokBefore(lz, lb)
    if lb.findByte(10) then oneLine = 0 ; break.
  end

CarryChk routine
  data
cz   long,auto
cp   long,auto
ce   long,auto
c1   long,auto
bt   StringTheory
cmt  StringTheory
  code
  carried = 0
  self.keepCont  = 1
  self.contEmits = 0
  self.BuildRep(newTxt)
  self.keepCont  = 0
  if self.contEmits <> 1 or ~newTxt._DataEnd then exit.                       ! 0 = the trivia vanished; more than 1 = a binding is repeated
  loop cz = sPos + 1 to ePos
    self.m.TokBefore(cz, bt)
    cp = 1
    loop
      loop while cp <= bt._DataEnd                                            ! the next run of text that is not layout
        case val(bt.valuePtr[cp])
        of 32 orof 9 orof 13 orof 10 orof 124                                 ! <space> orof <tab> orof <carriage return> orof <line feed> orof '|'
          cp += 1
        else
          break
        end
      end
      if cp > bt._DataEnd then break.
      ce = bt.findByte(13, cp)                                                ! the run ends at the line break, or at the end
      if ~ce then ce = bt._DataEnd + 1.
      cmt.setValue(bt.slice(cp, ce - 1))
      cmt.trim()
      if cmt._DataEnd
        c1 = newTxt.findChars(cmt.valuePtr[1 : cmt._DataEnd])
        if ~c1 then exit.                                                     ! that comment is not in the result
        if newTxt.findChars(cmt.valuePtr[1 : cmt._DataEnd],c1 + 1) then exit. ! ... or is in it twice
      end
      cp = ce + 1
    end
  end
  carried = 1

! ---- The ReplaceToks design, the other half: the replacement is tokenized and walked
!      against the matched span from BOTH ends. Every token that matches (caselessly) is KEPT with
!      its trivia - its comment, bar, line break and indent - and only takes the replacement's
!      spelling, so a case rule still does its work; only the MIDDLE, between the common prefix
!      and the common suffix, is deleted and rebuilt. Reached when CarryChk could not carry every
!      comment (a comment on a token the rule itself spells is outside every binding). Taken only
!      when every comment inside the span sits on a kept token, or on the first token of the
!      middle, whose trivia moves onto whatever replaces it; a comment further inside the middle
!      has nowhere to go and the match is skipped. A ';' the rule wrote OUTSIDE a
!      literal makes the replacement two statements, which is SplitStmts' business and is not
!      attempted here; a ';' inside a literal is ordinary text and does not refuse the rescue. ----
OuterCarry routine
  data
oz    long,auto
n     long,auto    ! tokens in the flat replacement
k     long         ! the common prefix
m     long         ! the common suffix
oldN  long,auto    ! tokens in the span
midS  long,auto    ! the old middle, midS..midE (midE < midS = empty)
midE  long,auto
newN  long,auto    ! tokens in the new middle
nSet  long         ! kept tokens whose spelling changes
bt    StringTheory
sb    StringTheory
sb2   StringTheory ! what the REPLACEMENT puts between its new middle and the suffix
tk    StringTheory
tk2   StringTheory
mid   StringTheory ! the new middle as text, with the replacement's own spacing inside it
repTk VitTokenize  ! the flat replacement, tokenized
recA  long,auto    ! the stream's size before the new middle goes in
ins   long,auto    ! the tokens it became in the stream
keepL byte,auto    ! the trivia in front of the old middle stays: it is the match's own lead, or more than spaces
  code
  outerOk   = 0
  outNoOp = 0
  bt.setValue(self.rl.rules.repText)
  if self.rl.PosOutsideQuotes(bt, ';') then exit.
  self.keepCont = 0
  self.BuildRep(newTxt)                                                          ! FLAT: the replacement as the rule spells it
  if ~newTxt._DataEnd then exit.
  ! repTk EXISTS ONLY TO BE COMPARED WITH THE FILE, so it has to tokenize the way the file
  ! does, so midLine is NOT set here. Setting it says "a fragment has no column 1" - true, but
  ! it also turns OFF the label merge, because that gates on BufColOne, and BufColOne is 0
  ! whenever midLine is set. The file merges a dotted name that is not a call - `st.value`,
  ! `self.count` - into ONE token; with midLine set repTk would leave it as three. The prefix
  ! walk would then compare `st.value` with `st`, break at the first token on both ends, and
  ! OuterCarry would give up with k + m = 0 - the "head and tail kept with their comments"
  ! rescue lost for any replacement whose head or tail is a dotted reference, most of them.
  ! Nothing here reads a TYPE - the walk compares text - so the typing midLine protects
  ! does not matter to this object. What reaches the stream is re-parsed by InsertString, and
  ! that is told it is a fragment separately.
  repTk.ParseText(newTxt)
  n = repTk.Records()
  if n < 1 then exit.
  oldN = ePos - sPos + 1
  loop while k < oldN and k < n                                                  ! the common prefix, caseless
    if upper(self.tk.GetTok(sPos + k)) <> upper(repTk.GetTok(k + 1)) then break.
    k += 1
  end
  loop while m < oldN - k and m < n - k                                          ! the common suffix, caseless, clear of the prefix
    if upper(self.tk.GetTok(ePos - m)) <> upper(repTk.GetTok(n - m)) then break.
    m += 1
  end
  ! A + OR - AT THE EDGE OF THE MIDDLE BELONGS TO IT. Whether one is a sign or an operator depends on
  ! the token beside it, and the middle is where that changes: `u.length() - 1` becomes `-1`, and a
  ! kept '-' would keep the space that suited the operator - `adjustLength(- 1)`.
  loop while m > 0
    tk.setValue(self.tk.GetTok(ePos - m + 1))
    if tk.getValue() <> '-' and tk.getValue() <> '+' then break.
    m -= 1
  end
  loop while k > 0
    tk.setValue(self.tk.GetTok(sPos + k - 1))
    if tk.getValue() <> '-' and tk.getValue() <> '+' then break.
    k -= 1
  end
  if k + m = 0 then exit.                                                        ! nothing kept: the plain rebuild is all there is
  midS = sPos + k
  midE = ePos - m
  newN = n - k - m
  loop oz = midS + 1 to midE                                                     ! a comment strictly inside the middle has nowhere to go
    self.m.TokBefore(oz, bt)
    if bt._DataEnd
      if ~bt.isAll('<32,9,13,10,124>') then exit.
    end
  end
  loop oz = 1 to k                                                               ! would anything change at all? The replacement builder keeps
    if self.tk.GetTok(sPos + oz - 1) <> repTk.GetTok(oz) then nSet += 1.         !   the source's spelling of a word both sides spell, so a
  end                                                                            !   case-only rule can arrive here with nothing to do - that is
  loop oz = 1 to m                                                               !   a no-op, not a change, or the fixpoint would never settle
    if self.tk.GetTok(ePos - oz + 1) <> repTk.GetTok(n - oz + 1) then nSet += 1.
  end
  if spcOnly and midE < midS and ~newN then exit.                                ! the same words: the rule is about spacing, and its spacing wins
  if ~nSet and midE < midS and ~newN then outNoOp = 1 ; exit.
  ! ---- from here the conversion is taken: the kept tokens take the replacement's spelling
  loop oz = 1 to k
    if self.tk.GetTok(sPos + oz - 1) <> repTk.GetTok(oz) then self.tk.SetTok(sPos + oz - 1, repTk.GetTok(oz)).
  end
  loop oz = 1 to m
    if self.tk.GetTok(ePos - oz + 1) <> repTk.GetTok(n - oz + 1) then self.tk.SetTok(ePos - oz + 1, repTk.GetTok(n - oz + 1)).
  end
  mid.free()
  loop oz = k + 1 to n - m                                                       ! the new middle, spaced as the rule spells it
    repTk.GetTok(oz, sb, tk)
    if oz > k + 1 then mid.append(sb).
    mid.append(tk)
  end
  ! ---- the new middle goes in. The spacing BETWEEN TWO KEPT TOKENS is the author's; the spacing
  !      on either side of the new middle is the rule's, because one of the two tokens beside it is
  !      new. The trivia in front of the whole match (k = 0) is the line's indent, or what parts the
  !      match from the code before it, and it stays in front. Trivia that holds anything but spaces
  !      - a comment, a bar, a line break - is never replaced: it leads what replaces the old middle.
  !      The new middle is COUNTED IN THE STREAM after it goes in, not taken from repTk, so the
  !      count holds however the splice tokenises a dotted name such as `tok.valuePtr`.
  sb.free()
  if k + 1 <= n then repTk.GetTok(k + 1, sb, tk).                                ! the rule's spacing in front of the new middle
  sb2.free()
  if k + newN + 1 <= n then repTk.GetTok(k + newN + 1, sb2, tk2).                !   and after it, in front of the suffix
  self.m.TokBefore(midS, lead)                                                   ! the old middle's first token - or, with no old middle, the token the new one goes in front of
  keepL = choose(k = 0 or (lead._DataEnd and ~lead.isAll('<32,9>')))
  if midE >= midS then self.tk.DeleteToks(midS, midE).
  recA = records(self.tk.tokens)
  if newN > 0 then self.tk.InsertString(midS, mid, choose(k > 0 or ~self.LeadIsCol1(lead))).
  ins = records(self.tk.tokens) - recA
  if ins
    if k = 0 or (midE >= midS and keepL)                                         ! the left edge
      self.tk.SetStrBefore(midS, lead.getValue())
    else
      self.tk.SetStrBefore(midS, sb.getValue())
    end
    if m > 0                                                                     ! the right edge: the suffix's first token
      self.m.TokBefore(midS + ins, bt)
      if (midE < midS and k = 0) or ~bt._DataEnd or bt.isAll('<32,9>')           !   (with nothing removed and k = 0 it carries the lead just placed)
        self.tk.SetStrBefore(midS + ins, sb2.getValue())
      end
    end
  elsif midE >= midS                                                             ! nothing replaces the old middle
    if keepL
      if lead._DataEnd then self.tk.PrependStrBefore(midS, lead.getValue()).     ! a comment in that trivia goes in front of what follows
    elsif m > 0
      self.m.TokBefore(midS, bt)
      if ~bt._DataEnd or bt.isAll('<32,9>') then self.tk.SetStrBefore(midS, sb.getValue()).
    end
  end
  self.changeCount += 1
  pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ': ' & oldSpan.getValue() & ' ==> ' & newTxt.getValue() & |
              choose(~spcOnly, '   (head and tail kept with their comments: ' & k & ' + ' & m & ' token(s))', '') & '<13,10>')
  outerOk = 1

WidthChk routine
  data
wt     long,auto
lsTok  long,auto
wlf    long,auto
wfz    long,auto
lineW  long,auto
spanW  long,auto
allowW long,auto
wsb    StringTheory
  code
  ! the width limit is LOCAL - the widest ORIGINAL line of the construct
  ! being edited (its own deliberate formatting), NOT the file maximum (one outlier
  ! wide line - a long comment or the sig literal - would inflate the file cap and let
  ! a 465-char flatten through as "in-limit"). allowed = spanW + 12 capped at 200;
  ! a construct already wider than 200 is respected as-is, never extended. Result:
  ! deliberately wrapped constructs PRESERVE and their | columns stay put.
  overWide = 0
  wResult  = newTxt._DataEnd
  wt = sPos                                       ! find the physical line start
  loop while wt > 1
    get(self.tk.tokens, wt)
    if errorcode() then break.
    if self.tk.tokens.firstOnLine then break.
    wt -= 1
  end
  lsTok = wt
  loop while wt < sPos                            ! prefix width (line start .. match start)
    get(self.tk.tokens, wt)
    if errorcode() then break.
    if not self.tk.tokens.strBefore &= NULL
      wsb.setValue(self.tk.tokens.strBefore)
      wlf = wsb._DataEnd                          ! indent = chars after the LAST LF
      loop while wlf > 0
        if wsb.valuePtr[wlf] = '<10>' then break.
        wlf -= 1
      end
      wResult += wsb._DataEnd - wlf
    end
    if not self.tk.tokens.tok &= NULL
      wResult += size(self.tk.tokens.tok)
    end
    wt += 1
  end
  get(self.tk.tokens, sPos)                       ! the MATCH-START token's own strBefore belongs in the result
  if ~errorcode()                                 !   width: the line INDENT when the match starts the line (the
    if not self.tk.tokens.strBefore &= NULL       !   normal case, where the prefix loop above never runs), or the
      wsb.setValue(self.tk.tokens.strBefore)      !   gap before the match otherwise. ApplyOne re-applies it on
      wlf = wsb._DataEnd                          !   output and the spanW side below counts it, so leaving it out
      loop while wlf > 0                          !   here would under-count the result by exactly the indent
        if wsb.valuePtr[wlf] = '<10>' then break.
        wlf -= 1
      end
      wResult += wsb._DataEnd - wlf
    end
  end
  wt = ePos + 1
  loop                                            ! tail width to end of line
    if wt > self.tk.records() then break.
    if self.m.TokIsEOL(wt) then break.
    get(self.tk.tokens, wt)
    if errorcode() then break.
    ! STOP AT THE LINE END. TokIsEOL only knows a '<10>' TOKEN, and a continuation is not one -
    ! the break lives as CR/LF inside the next token's trivia - so without this test the walk
    ! would go straight through every continuation and keep adding, the next line's indent
    ! included; the result would over-count and the width policy refuse conversions that fit.
    ! The prefix walk above and the spanW walk below test for the feed in the same way.
    if not self.tk.tokens.strBefore &= NULL
      wsb.setValue(self.tk.tokens.strBefore)
      wfz = wsb.findByte(13)                      ! CR first: in a CRLF break it is the earlier of the two
      if ~wfz then wfz = wsb.findByte(10).
      if wfz                                      ! the line ends inside this trivia
        wResult += wfz - 1
        break
      end
      wResult += wsb._DataEnd
    end
    if not self.tk.tokens.tok &= NULL
      wResult += size(self.tk.tokens.tok)
    end
    wt += 1
  end
  wt = lsTok                                      ! spanW: widest ORIGINAL line of the construct
  lineW = 0
  spanW = 0
  loop
    if wt > self.tk.records() then break.
    if self.m.TokIsEOL(wt)
      if wt > ePos then break.                    ! the EOL closing the construct's last line
      if lineW > spanW then spanW = lineW.        ! a real statement LF inside the span
      lineW = 0
      wt += 1
      cycle
    end
    get(self.tk.tokens, wt)
    if errorcode() then break.
    if not self.tk.tokens.strBefore &= NULL
      wsb.setValue(self.tk.tokens.strBefore)
      if wsb.containsByte(10)                     ! continuation: line break lives in trivia <line feed>
        if lineW > spanW then spanW = lineW.
        wlf = wsb._DataEnd
        loop while wlf > 0
          if wsb.valuePtr[wlf] = '<10>' then break.
          wlf -= 1
        end
        lineW = wsb._DataEnd - wlf                ! new line starts with its indent
      else
        lineW += wsb._DataEnd
      end
    end
    if not self.tk.tokens.tok &= NULL
      lineW += size(self.tk.tokens.tok)
    end
    wt += 1
  end
  if lineW > spanW then spanW = lineW.
  if spanW >= 200
    allowW = spanW
  else
    allowW = choose(spanW + 12 > 200, 200, spanW + 12)
  end
  if wResult > allowW then overWide = 1.

! ---- a replacement the rule wrote as `stmt ; stmt` is spliced in as two LINES, the second
!      indented like the line the match starts on, when the MATCH was two statements as well -
!      an interior ';' in the pattern - or when the match stood alone on its line: one
!      statement per line is what a person writes, and a pass that looks for a statement of its
!      own (InlineSingleUse, TrimAtSplit) sees the second one (ruled 14 Sep 2026). A match
!      that shares its line with anything else - a one-line IF around it, a statement after it,
!      a continuation - keeps its line, and so does a span that ran over several lines or
!      carried an interior comment. Only a ';' the RULE wrote counts, and bound text never carries
!      one - an EXPR extent stops at a depth-0 ';', ARGS sit inside their parens, a literal is
!      quoted - so the built text is split outside quotes at bracket depth 0. ParseText stores
!      a line ending as a '<10>' token and the indent as the next token's trivia, and
!      InsertString parses what it is given, so '<10>' plus the indent is all the splice
!      needs; JoinToks writes CRLF. The log keeps the one-line form. A line that opens with a
!      column-1 label - `Again  a = 1` - is indented to where its statement begins: as many
!      spaces as the label is long, then the gap after it. A statement written in column 1
!      would be a label (ruled 30 Oct 2026). ----
SplitStmts routine
  data
ssI    long,auto
ssDep  long,auto
ssQ    byte,auto
ssTk   long,auto
ssLf   long,auto
ssSb   StringTheory
ssInd  StringTheory ! the line break and the indent to put after it
ssCmt  StringTheory ! the line's trailing comment, to go before the first break
  code
  insTxt.setValue(newTxt)
  if self.rl.rules.repText &= NULL or self.rl.rules.patQ &= NULL then exit.
  if ~ssSb.findByte(59, 1,, self.rl.rules.repText) then exit. ! <semi-colon>
  ssLf = 0                                                    ! the pattern has an interior ';' - the match was two statements
  loop ssTk = 1 to records(self.rl.rules.patQ) - 1
    get(self.rl.rules.patQ, ssTk)
    if errorcode() then break.
    if self.rl.rules.patQ.tok &= NULL or self.rl.rules.patQ.mvx then cycle.
    if self.rl.rules.patQ.tok = ';' then ssLf = 1 ; break.
  end
  if ssLf and carried then exit.                              ! a carried match keeps its line: the text holds the span's own comments, and a ';' inside one of them is not a statement boundary
  if ~ssLf                                                    ! a one-statement match: two lines only when it stood alone on its line
    if self.multiLine or carried then exit.
    get(self.tk.tokens, sPos)
    if errorcode() or ~self.tk.tokens.firstOnLine then exit.
    get(self.tk.tokens, ePos + 1)
    if errorcode() then exit.
    if self.tk.tokens.tok &= NULL then exit.
    if self.tk.tokens.tok[1] <> '<10>' then exit.
    ssLf = 1
  end
  ssTk = sPos                                                 ! the first token on the match's physical line ...
  loop while ssTk > 1
    get(self.tk.tokens, ssTk)
    if errorcode() then break.
    if self.tk.tokens.firstOnLine then break.
    ssTk -= 1
  end
  ssInd.setValue('<10>')
  if ssTk < sPos and self.m.IsColOneStart(ssTk)               ! a label opens the line: the statement starts after it
    ssInd.append(all(' ', len(self.m.TokText(ssTk))))
    ssTk += 1
  end
  self.m.TokBefore(ssTk, ssSb)                                ! ... and its indent: the trivia after the last line feed
  ssLf = ssSb._DataEnd
  loop while ssLf > 0
    if ssSb.valuePtr[ssLf] = '<10>' then break.
    ssLf -= 1
  end
  if ssLf < ssSb._DataEnd then ssInd.append(ssSb.valuePtr[ssLf + 1 : ssSb._DataEnd]).
  ssCmt.free()                                                ! a trailing comment stays on the FIRST line, where the author put it: it moves
  get(self.tk.tokens, ePos + 1)                               !   from the line end's trivia into the text, ahead of the first break
  if ~errorcode() and not self.tk.tokens.tok &= NULL and self.tk.tokens.tok[1] = '<10>' and not self.tk.tokens.strBefore &= NULL
    if ssSb.findByte(33, 1,, self.tk.tokens.strBefore)        ! '!'
      ssCmt.setValue(self.tk.tokens.strBefore)
      ! IT IS *NOT* CLEARED HERE. The gate that lets this routine run is a quote-blind search
      ! for a ';' anywhere in the replacement, while the arm below that puts the comment back
      ! is quote-aware and depth-aware and refuses a ';' at either end. A replacement whose
      ! only ';' sits INSIDE A LITERAL therefore reaches this point and never reaches that
      ! arm, so clearing the trivia here would take the author's trailing comment out of the
      ! file with nothing left to put it back. The stream loses the comment at the moment it
      ! is APPENDED, so every path that does not append it leaves it where the author wrote it.
    end
  end
  insTxt.free()
  ssDep = 0 ; ssQ = 0 ; ssI = 0
  loop while ssI < newTxt._DataEnd
    ssI += 1
    if newTxt.valuePtr[ssI] = ''''
      ssQ = 1 - ssQ                                           ! a doubled quote toggles twice and lands where it started
    elsif ~ssQ
      case val(newTxt.valuePtr[ssI])
      of 40 orof 91                                           ! '(' orof '['
        ssDep += 1
      of 41 orof 93                                           ! ')' orof ']'
        ssDep -= 1
      of 59                                                   ! <semi-colon>
        if ~ssDep and ssI > 1 and ssI < newTxt._DataEnd
          ssTk = insTxt._DataEnd                              ! drop the spaces before the ';' ...
          loop while ssTk > 0 and insTxt.valuePtr[ssTk] = ' '
            ssTk -= 1
          end
          insTxt.setLength(ssTk)
          if ssCmt._DataEnd then insTxt.append(ssCmt) ; self.tk.SetStrBefore(ePos + 1, '') ; ssCmt.free(). ! cleared HERE, where it is actually placed
          insTxt.append(ssInd)
          loop while ssI < newTxt._DataEnd and newTxt.valuePtr[ssI + 1] = ' '
            ssI += 1                                          ! ... and after it
          end
          cycle
        end
      end
    end
    insTxt.append(newTxt.valuePtr[ssI])
  end

! ------------------------------------------------------------------------------------
VitRewrite.BuildRep Procedure(StringTheory pOut)
  code
  pOut.free()
  if self.rl.rules.repText &= NULL then return.
  self.SubstText(self.rl.rules.repText, pOut)

! ------------------------------------------------------------------------------------
! Walk the rule's replacement text: copy literally, but substitute declared
! metavars with their bound source text and evaluate fold(...)/trimr(...)
! (recursing into their argument first, so a fold() written in the rule never
! confuses a fold(...) that arrives inside bound source text). fold() combines
! numbers only: text holding a call keeps the call (VitMatch.FoldSafe), since
! day(today()) - 1 has a value only when the program runs.
! ------------------------------------------------------------------------------------
VitRewrite.SubstText Procedure(STRING pText, StringTheory pOut)
i        long,auto
j        long,auto
n        long,auto
op       long,auto
closePos long,auto
mvx      long,auto
folded   long
litLen   long,auto
litTxt   string(24),auto ! chr(nn) fold result - the literal source text
srcOk    byte            ! the source spells this word too - keep its case
srcSt    StringTheory    ! that spelling
word     StringTheory
inner    StringTheory
bt       StringTheory
cmpA     StringTheory
cmpB     StringTheory
  code
  n = len(clip(pText))
  i = 1
  loop while i <= n
    if pText[i] = ''''                                       ! quoted literal: copy verbatim (doubled quotes stay inside)
      j = i + 1
      loop while j <= n
        if pText[j] = ''''
          if j < n and pText[j+1] = ''''
            j += 2
            cycle
          end
          break
        end
        j += 1
      end
      if j > n then j = n.
      pOut.append(pText[i : j])
      i = j + 1
      cycle
    end
    if self.IsLabelChar(pText[i]) and ~inrange(val(pText[i]), 48, 57) and pText[i] <> ':'
      j = i                                                  ! label run: starts with letter or _
      loop while j < n and self.IsLabelChar(pText[j+1])
        j += 1
      end
      word.setValue(pText[i : j])
      ! THIS gate decides which words are helper calls at all - a word that fails
      ! it is written out VERBATIM. Every branch below needs its word here too: without
      ! it, val('=') would go through into the output and BuiltinCheckCase fold it
      ! afterwards, prepending a second trailing comment. Add a branch, add it here too.
      case lower(word.getValue())
      of   'fold' orof 'trimr'                               |
      orof 'len'  orof 'val'                                 |
      orof 'chr'
        op = j + 1
        loop while op <= n and pText[op] = ' '
          op += 1
        end
        if op <= n and pText[op] = '('
          closePos = self.MatchingParenPos(pText, op)
          if closePos
            inner.free()
            if closePos > op + 1
              self.SubstText(pText[op+1 : closePos-1], inner)
            end
            if lower(choose(word._DataEnd < 1, '', word.valuePtr[1 : word._DataEnd])) = 'fold'
              bt.setValue(self.m.FoldSafe(inner.getValue()))
              do FoldCompare                                 ! use FoldStr's text only if it actually folded
              if folded
                pOut.append(bt)
              else
                pOut.append(inner)                           ! unfoldable: keep the rule's own spelling/spacing
              end
            elsif lower(choose(word._DataEnd < 1, '', word.valuePtr[1 : word._DataEnd])) = 'chr' ! chr(nn) -> the literal SOURCE TEXT for that byte, the
              litTxt = self.ComputeByteLit(inner.getValue()) !   inverse of val(lit): 61 -> '=' as source, not a
              if litTxt                                      !   runtime chr() call, which is what makes the readable
                pOut.append(clip(litTxt))                    !   direction actually readable
              else                                           ! not a plain byte number: keep the chr(...) spelling, which
                pOut.append('chr(')                          ! is valid Clarion and means the same thing at runtime
                pOut.append(inner)
                pOut.append(')')
              end
            elsif lower(choose(word._DataEnd < 1, '', word.valuePtr[1 : word._DataEnd])) = 'val' ! val(lit) -> the literal's BYTE value, for
              litLen = self.ComputeLitByte(inner.getValue()) !   st.findChar('=') -> st.findByte(61)
              if litLen >= 0
                pOut.append(litLen & '')                     ! numeric-to-string conversion carries no spaces
              else                                           ! not a single character: keep the val(...) spelling, which
                pOut.append('val(')                          ! is valid Clarion and means the same thing at runtime
                pOut.append(inner)
                pOut.append(')')
              end
            elsif lower(choose(word._DataEnd < 1, '', word.valuePtr[1 : word._DataEnd])) = 'len' ! len(lit) -> the literal's RUNTIME length
              litLen = self.ComputeLitLen(inner.getValue())
              if litLen >= 0
                pOut.append(litLen & '')                     ! numeric-to-string conversion carries no spaces
              else                                           ! not a countable single literal: keep the len(...)
                pOut.append('len(')                          ! spelling - valid Clarion, the compiler folds it
                pOut.append(inner)
                pOut.append(')')
              end
            else
              self.TrimrLit(inner)
              pOut.append(inner)
            end
            i = closePos + 1
            cycle
          end
        end
      end
      mvx = self.rl.FindMetaVar(word.getValue())
      if mvx
        self.BindText(mvx, bt)
        pOut.append(bt)
      else
        ! a word the rule spells out, which the SOURCE also spells,
        ! keeps the SOURCE's capitalisation. Rules are written lower case, so without
        ! this a rule that only meant to drop a clip would also restyle the author's
        ! keyword - UPPER(CLIP(x)) & y would come back as upper(x) & y. That contradicts
        ! the tool's own contract ("formatting changes only happen when you ask", and
        ! KeywordCase is the opt-in way to ask), and it would be INCONSISTENT inside
        ! one line: a metavar carries the source text verbatim, so `upper(LEFT(...))`
        ! would come out with LEFT in caps and upper in lower case.
        ! A word the rule INTRODUCES (a renamed method, an equate) is not in the
        ! source span, so it keeps the rule's spelling - which is what makes a
        ! canonical-spelling rule like clipLen -> clipLength still work.
        do SrcCase
        if srcOk
          pOut.append(srcSt)
        else
          pOut.append(word)
        end
      end
      i = j + 1
      cycle
    end
    pOut.append(pText[i])
    i += 1
  end
  return


! ---- find the SOURCE's spelling of `word` inside the matched span ----
! Sets srcOk/srcSt. The span is the tokens this match consumed, read BEFORE the
! splice - BuildRep runs ahead of DeleteToks, so they are still there. Reserved
! words count as well as labels ('r' and 'b'), so a rule that writes `if` beside
! a source `IF` keeps the caps too. A member reference arrives as ONE token - the
! tokenizer merges a dotted name that is not a call - and SubstText cut the
! replacement at the dot, so a token holding a dot is compared segment by segment
! as well; without that the source's spelling of a property name could never be
! found and the rule's spelling would restyle it. First occurrence wins; a source
! that spells one identifier two ways in one statement is its own problem.
SrcCase routine
  data
sx  long,auto
ss  long,auto
se  long,auto
sd  long,auto
sp  long,auto
sn  long,auto
  code
  srcOk = 0
  get(self.m.matches, self.curMx)
  if errorcode() then exit.
  ss = self.m.matches.sPos
  se = self.m.matches.ePos
  loop sx = ss to se
    get(self.tk.tokens, sx)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL or                             |
       self.tk.tokens.type <> 'b' and self.tk.tokens.type <> 'r'
      cycle
    end
    if upper(self.tk.tokens.tok) = upper(word.getValue())
      srcSt.setValue(self.tk.tokens.tok)
      srcOk = 1
      break
    end
    sn = len(clip(self.tk.tokens.tok))
    if ~sn or ~instring('.', self.tk.tokens.tok[1 : sn], 1, 1) then cycle.
    sd = 1
    loop sp = 1 to sn + 1
      if sp <= sn and self.tk.tokens.tok[sp] <> '.' then cycle.
      if sp > sd and upper(self.tk.tokens.tok[sd : sp - 1]) = upper(word.getValue())
        srcSt.setValue(self.tk.tokens.tok[sd : sp - 1])
        srcOk = 1
        break
      end
      sd = sp + 1
    end
    if srcOk then break.
  end
FoldCompare routine
  ! folded = FoldStr's output differs from the input beyond whitespace
  folded = false
  if ~bt._DataEnd then exit.
  cmpA.setValue(bt)
  cmpB.setValue(inner)
  cmpA.removeByte(32)  ! remove all <space>
  cmpB.removeByte(32)  ! remove all <space>
  if ~cmpA.equals(cmpB, st:clip) then folded = true.

! ------------------------------------------------------------------------------------
VitRewrite.BindText Procedure(LONG pMvx, StringTheory pOut)
b  long,auto
  code
  pOut.free()
  loop b = 1 to records(self.m.bindRecs)
    get(self.m.bindRecs, b)
    if self.m.bindRecs.matchIx <> self.curMx or |
       self.m.bindRecs.mvx <> pMvx
      cycle
    end
    self.RenderSpan(self.m.bindRecs.sPos, self.m.bindRecs.ePos, pOut)
    return
  end

! ------------------------------------------------------------------------------------
! Source span rendered verbatim: token text plus INTERIOR trivia (spacing wins).
! A continuation inside the span (strBefore holding CR/LF) collapses to one
! space, unless keepCont is set - then the trivia, an interior comment included,
! is appended verbatim, so CarryChk and the over-width path keep the span's breaks.
! ------------------------------------------------------------------------------------
VitRewrite.RenderSpan Procedure(LONG pS, LONG pE, StringTheory pOut)
i       long,auto
hadCont long
bt      StringTheory
  code
  pOut.free()
  loop i = pS to pE
    if i > pS
      self.m.TokBefore(i, bt)
      if bt._DataEnd
        if bt.containsA('<10,13>') ! <carriage return> <line feed>
          if self.keepCont         ! over-width fallback - keep the original
            pOut.append(bt)        !   continuation trivia (| + newline + indent)
            hadCont = 1            !   so the conversion applies WITHOUT flattening
          else
            pOut.append(' ')
          end
          self.multiLine = true
        else
          pOut.append(bt)
        end
      end
    end
    pOut.append(self.m.TokText(i))
  end
  if hadCont
    self.contEmits += 1            ! one count per preserved SPAN (safety: >1 span in a replacement = revert to skip)
  end

! ------------------------------------------------------------------------------------
! len(lit) support: the RUNTIME length of a quoted literal's content.
! Escape-aware: doubled '' << {{ each count 1; a bare < opens a char-code group
! <a,b,...> counting one per code; C{n} makes C count n in total (Clarion repeat).
! Anything else unexpected (stray quote, unclosed group, zero repeat, not a single
! quoted literal) returns -1 and the caller keeps the rule's own len(...) spelling,
! which is valid Clarion the compiler folds itself - graceful degradation.
! ------------------------------------------------------------------------------------
VitRewrite.ComputeLitLen Procedure(STRING pLit)
n     long,auto
i     long,auto
j     long,auto
cnt   long
grpN  long,auto
rep   long,auto
  code
  n = len(clip(pLit))              ! content ends at the closing quote - clip is safe
  if n < 2 or pLit[1] <> '''' or pLit[n] <> '''' then return -1.
  i = 2
  loop while i <= n - 1
    case val(pLit[i])
    of 39                          ! <single quote>
      if i + 1 <= n - 1 and pLit[i+1] = '''' then cnt += 1; i += 2; cycle.
      return -1                    ! stray single quote inside - not ONE literal
    of 60                          ! '<<'
      if i + 1 <= n - 1 and pLit[i+1] = '<<' then cnt += 1; i += 2; cycle.
      grpN = 1                     ! char-code group: <a,b,...> = one char per code
      j = i + 1
      loop while j <= n - 1 and pLit[j] <> '>'
        if pLit[j] = ',' then grpN += 1.
        if pLit[j] <> ',' and pLit[j] <> ' ' and (val(pLit[j]) < 48 or val(pLit[j]) > 57) then return -1.
        j += 1
      end
      if j > n - 1 then return -1. ! unclosed group
      cnt += grpN
      i = j + 1
    of 123                         ! '{{'
      if i + 1 <= n - 1 and pLit[i+1] = '{{' then cnt += 1; i += 2; cycle.
      if ~cnt then return -1.      ! repeat with nothing before it
      rep = 0                      ! C{k}: C counts k in total (C itself already counted 1)
      j = i + 1
      loop while j <= n - 1 and val(pLit[j]) >= 48 and val(pLit[j]) <= 57
        rep = rep * 10 + pLit[j]
        j += 1
      end
      if j > n - 1 or pLit[j] <> '}' or rep < 1 then return -1.
      cnt += rep - 1
      i = j + 1
    else
      cnt += 1
      i += 1
    end
  end
  return cnt

! ------------------------------------------------------------------------------------
! the inverse of ComputeLitByte - the literal SOURCE TEXT for a byte value, so a
! rule can emit st.findChar('=') from st.findByte(61). Every quote/bracket in the
! result is built with chr() rather than written out: a Clarion literal containing a
! quote needs four of them in the source, and escape-doubling ('' < {) is easy to get
! wrong, so the arithmetic form is the safe spelling.
! Blank = not a plain 0-255 number, and the caller then keeps the chr(...) spelling.
! ------------------------------------------------------------------------------------
VitRewrite.ComputeByteLit Procedure(STRING pNum)
s   string(20),auto
n   long,auto
i   long,auto
ln  long,auto
  code
  s  = left(pNum)                                       ! LEFT strips the leading blanks a spaced rule spelling
  ln = len(clip(s))                                     ! leaves - no CLIP: assigning to a fixed STRING pads anyway
  if ~ln then return ''.
  loop i = 1 to ln
    if val(s[i]) < 48 or val(s[i]) > 57 then return ''. ! digits only (the isConst guard already assures this)
  end
  n = s
  if n > 255 then return ''.
  case n
  of 39                                                 ! a quote is written twice inside a literal
    return chr(39) & chr(39) & chr(39) & chr(39)
  of 60                                                 ! '<' opens an escape group, so it is doubled
    return chr(39) & chr(60) & chr(60) & chr(39)
  of 123                                                ! '{' opens a repeat group, so it is doubled
    return chr(39) & chr(123) & chr(123) & chr(39)
  end
  case n
  of 32 to 126
  else                                                  ! unprintable: the <nn> code spelling
    return chr(39) & chr(60) & n & chr(62) & chr(39)
  end
  return chr(39) & chr(n) & chr(39)

! ------------------------------------------------------------------------------------
! the BYTE value of a literal that is exactly ONE character, so a rule
! can emit st.findByte(61) from st.findChar('='). ComputeLitLen does the escape-aware
! counting and has already proven the literal well formed by the time we look at the
! content, so this only has to decode the four spellings a single character can take:
! '' (a quote, 39), '<<' (a literal <, 60), '<nn>' (a character code), '{{' (123), or
! a plain byte. -1 = not one character, and the caller then keeps the val(...) spelling.
! ------------------------------------------------------------------------------------
VitRewrite.ComputeLitByte Procedure(STRING pLit)
n   long,auto
v   long
j   long,auto
  code
  if self.ComputeLitLen(pLit) <> 1 then return -1.
  n = len(clip(pLit))
  if n < 3 then return -1.                       ! '' alone is the empty literal
  case val(pLit[2])
  of 39                                          ! <single quote>
    return 39                                    ! '''' = one quote character
  of 60                                          ! '<<'
    if n >= 4 and pLit[3] = '<<' then return 60. ! '<<<<' = one '<' character
    v = 0
    j = 3
    loop while j <= n - 1 and val(pLit[j]) >= 48 and val(pLit[j]) <= 57
      v = v * 10 + pLit[j]
      j += 1
    end
    if j = 3 or v > 255 then return -1.          ! no digits, or not a byte
    return v
  of 123                                         ! '{{'
    return 123                                   ! '{{{{' = one '{' character
  end
  return val(pLit[2])

! ------------------------------------------------------------------------------------
! 'xx  ' -> 'xx'   '  ' -> ''   - the literal's trailing BLANKS go, however they are
! spelled: a space, a <32> code (in any numeric form), the 32s that end a code group
! ('x<9,32>' -> 'x<9>'), or a repeat of a blank ('ab {3}' -> 'ab'). Everything before them
! keeps its spelling, doubled quotes included. A literal this cannot read - an unclosed group,
! a code that is not a byte, a repeat straight after a code group - is written as clip(lit),
! which is what the rule's trimr() stands for. Not a literal -> unchanged.
! ------------------------------------------------------------------------------------
VitRewrite.TrimrLit Procedure(StringTheory pInOut)
n       long,auto
i       long,auto
j       long,auto
k       long,auto
c       long,auto
cd      long,auto
rep     long,auto
lastC   long,auto
lastNB  long
inGrp   byte
full    StringTheory
cut     StringTheory
  code
  pInOut.trim()
  n = pInOut._DataEnd
  if n < 2 or pInOut.valuePtr[1] <> '''' or pInOut.valuePtr[n] <> '''' then return.
  ! full is the content walked so far as written; cut is the same with its trailing blanks off
  lastC = -1
  i = 2
  loop while i <= n - 1
    c = val(pInOut.valuePtr[i])
    if (c = 39 or c = 60 or c = 123) and i < n - 1 and pInOut.valuePtr[i + 1] = pInOut.valuePtr[i]
      full.append(pInOut.valuePtr[i : i + 1])
      cut.setValue(full)
      lastC = c
      inGrp = 0
      i += 2
      cycle
    end
    case c
    of 39
      do Unread
      return
    of 60
      lastNB = 0
      k = i + 1
      j = k
      loop
        if j > n - 1 then do Unread ; return.
        case val(pInOut.valuePtr[j])
        of 44 orof 62 ! <comma> orof '>'
          if j = k then do Unread ; return.
          cd = self.m.LitCode(pInOut.valuePtr[k : j - 1])
          if cd < 0 then do Unread ; return.
          if cd <> 32 then lastNB = j - 1.
          lastC = cd
          if pInOut.valuePtr[j] = '>' then break.
          k = j + 1
        end
        j += 1
      end
      if lastC <> 32
        full.append(pInOut.valuePtr[i : j])
        cut.setValue(full)
      elsif lastNB
        cut.setValue(full)
        cut.append(pInOut.valuePtr[i : lastNB] & '>')
        full.append(pInOut.valuePtr[i : j])
      else
        full.append(pInOut.valuePtr[i : j])
      end
      inGrp = 1
      i = j + 1
    of 123
      j = i + 1
      rep = 0
      loop while j <= n - 1 and rep <= 255 and val(pInOut.valuePtr[j]) >= 48 and val(pInOut.valuePtr[j]) <= 57
        rep = rep * 10 + val(pInOut.valuePtr[j]) - 48
        j += 1
      end
      if j = i + 1 or j > n - 1 or pInOut.valuePtr[j] <> '}' or lastC < 0 or inGrp or rep < 1 or rep > 255
        do Unread
        return
      end
      full.append(pInOut.valuePtr[i : j])
      if lastC <> 32 then cut.setValue(full).
      i = j + 1
    else
      full.append(pInOut.valuePtr[i])
      if c <> 32 then cut.setValue(full).
      lastC = c
      inGrp = 0
      i += 1
    end
  end
  pInOut.setValue('''' & cut.getValue() & '''')

! ---- the literal cannot be read: keep its value by keeping the clip
Unread routine
  pInOut.enclose('clip(', ')')

! ------------------------------------------------------------------------------------
VitRewrite.BuildNote Procedure(StringTheory pOut)
t   long,auto
bt  StringTheory
nm  string(24),auto ! charname() result
  code
  pOut.free()
  loop t = 1 to records(self.rl.rules.noteQ)
    get(self.rl.rules.noteQ, t)
    if errorcode() then break.
    if self.rl.rules.noteQ.mvx
      self.BindText(self.rl.rules.noteQ.mvx, bt)
      if self.rl.rules.noteQ.func = vr:nfCharName                       ! '<10>' -> <line feed>, and any
        nm = self.tk.CharNameOfByte(self.ComputeLitByte(bt.getValue())) ! character with no
        if nm then bt.setValue(nm,st:clip).                             ! special name prints as itself
      end
      pOut.append(bt)
    elsif not self.rl.rules.noteQ.txt &= NULL
      pOut.append(self.rl.rules.noteQ.txt)
    end
  end

! ------------------------------------------------------------------------------------
VitRewrite.MatchingParenPos Procedure(STRING pText, LONG pOpen)
i        long,auto
n        long,auto
depth    long,auto
inQuote  long
  code
  n = len(clip(pText))
  depth = 0
  loop i = pOpen to n
    if inQuote
      if pText[i] = '''' then inQuote = false. ! doubled quotes toggle out-in: harmless for counting
      cycle
    end
    case val(pText[i])
    of 39                                      ! <single quote>
      inQuote = true
    of 40                                      ! '('
      depth += 1
    of 41                                      ! ')'
      depth -= 1
      if ~depth then return i.
    end
  end
  return 0

! ------------------------------------------------------------------------------------
VitRewrite.IsLabelChar Procedure(STRING pC)
  code
  case val(pC)
  of   65 to 90  ! A-Z
  orof 97 to 122 ! a-z
  orof 48 to 57  ! 0-9
  orof 95        ! _
  orof 58        ! :
    return true
  end
  return false
