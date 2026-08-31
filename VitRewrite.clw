! VitRewrite - Phase 3 of VitTransform
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

! ------------------------------------------------------------------------------------
VitRewrite.Init Procedure(VitRules pRl, VitTokenize pTk)
  code
  self.rl &= pRl
  self.tk &= pTk
  self.m.Init(pRl, pTk)
  self.changeCount = 0
  self.skipCount   = 0
  self.widthSkips  = 0                             !
  free(self.onceQ)                                 ! ONCE is per file

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
scratch   StringTheory
mx        long,auto
svChanges long,auto
  code
  get(self.rl.rules, pRow)
  if errorcode() then return.
  if self.rl.rules.once           ! ONCE already applied for this file?
    loop mx = 1 to records(self.onceQ)
      get(self.onceQ, mx)
      if self.onceQ.ruleId = self.rl.rules.ruleId then return.
    end
  end
  free(self.m.matches)
  free(self.m.bindRecs)
  self.m.capture = true
  self.m.MatchRule(pRow, scratch) ! rules buffer now holds this rule
  self.m.capture = false
  if ~records(self.m.matches) then return.
  svChanges = self.changeCount
  loop mx = records(self.m.matches) to 1 by -1
    self.ApplyOne(mx, pLog)
  end
  if self.changeCount <> svChanges
    if self.rl.rules.once
      clear(self.onceQ)
      self.onceQ.ruleId = self.rl.rules.ruleId
      add(self.onceQ)
    end
    self.tk.SetLineNumbers() ! token positions/lines changed
    self.m.freqDirty = true ! anchor counts stale - token stream mutated. (REBUILD PER FIRING RULE - do not defer it to once per pass. Every edit shifts the file TAIL, so deferral cascades one wave per pass, and it flips who wins OVERLAPPING sites, costing byte-parity. Per-firing-rule is the correct freshness contract; make the rebuild cheaper instead.)
    if not self.syms &= NULL
      self.syms.dirty = 1    ! positions shifted - rebuild LAZILY at the next consumer (EnsureFresh); untyped rule stretches skip the rebuild entirely
    end
  end

! ------------------------------------------------------------------------------------
VitRewrite.ApplyOne Procedure(LONG pMx, StringTheory pLog)
sPos     long,auto
ePos     long,auto
ln       long,auto
noOp     long
svML     byte,auto
overWide long                ! WidthChk verdict
wResult  long                ! computed result-line width
oldSpan  StringTheory
newTxt   StringTheory
noteTxt  StringTheory
lead     StringTheory
oldExact StringTheory
  code
  get(self.m.matches, pMx)
  if errorcode() then return.
  sPos = self.m.matches.sPos
  ePos = self.m.matches.ePos
  self.curMx = pMx
  ln = self.tk.MapLine(self.m.LineOf(sPos)) ! log lines in SOURCE coordinates for the preview (MapLine is identity in batch); ln is log-only in this proc
  self.m.SpanText(sPos, ePos, oldSpan)

  if self.m.matches.skipped
    self.skipCount += 1
    pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' SKIP interior-comment: ' & oldSpan.getValue() & '<13,10>')
    return
  end

  if self.rl.rules.isDelete
    self.m.TokBefore(sPos, lead)
    self.tk.DeleteToks(sPos, ePos)
    if lead._DataEnd
      self.tk.PrependStrBefore(sPos, lead.getValue()) ! keep indent/preceding trivia; trailing comment already lives on the EOL token
    end
    self.changeCount += 1
    pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' DELETE: ' & oldSpan.getValue() & '<13,10>')
    return
  end

  if self.rl.rules.isComment                          ! comment-out mode (design note 71c, not shipped) - survives as
    svML = self.multiLine                             !   ONE comment line at the original indent. Tokens are DELETED and the
    self.RenderSpan(sPos, ePos, oldExact)             !   text carried as trivia on the survivor token, so nothing can ever
    self.multiLine = svML                             !   re-match it: fixpoint-safe by construction, and the LINE survives
    noteTxt.free()                                    !   (line map stays 1:1 - the zebra deletion corner never arises).
    if not self.rl.rules.noteQ &= NULL                ! NOTE(...) = the human explanation; bindings resolve BEFORE DeleteToks
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
  self.BuildRep(newTxt)
  if ~newTxt._DataEnd
    pLog.append('rule ' & self.rl.rules.ruleId & ' line ' & ln & ' ERROR empty replacement built - not applied<13,10>')
    return
  end
  do NoOpCheck                                   ! replacement identical to source span: not a change
  if noOp then return.
  self.preserved = 0
  if self.multiLine and self.maxWidth > 0        ! width policy: a continuation collapse may not
    do WidthChk                                  !   produce a line wider than maxWidth - respect the codebase width
    if overWide                                  !   (+ a few chars) capped at ~200.
      self.keepCont  = 1                         ! instead of refusing, re-render the replacement with the
      self.contEmits = 0                         !   span's ORIGINAL continuations preserved - the conversion applies
      self.BuildRep(newTxt)                      !   and the formatting survives
      self.keepCont  = 0
      if self.contEmits <> 1 or ~newTxt._DataEnd ! 0 = trivia vanished; >1 = the metavar is duplicated in the
        ! DO NOT LOSE THE TRANSFORM. Do NOT `return` here: that refuses the conversion outright
        ! whenever the original continuations cannot be carried into the replacement. Build it
        ! flat and accept the wide line instead - SplitWideLines runs after convergence,
        ! alongside AlignComments, and breaks any over-wide line at a sensible point. A wide
        ! line that gets tidied later is strictly better than a conversion that never happened.
        ! widthSkips counts it so the report can say how often this path was taken.
        self.keepCont  = 0
        self.BuildRep(newTxt)                    ! rebuild FLAT - the keepCont attempt above left newTxt half-formed
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

  self.m.TokBefore(sPos, lead)
  self.tk.DeleteToks(sPos, ePos)
  self.tk.InsertString(sPos, newTxt)
  self.tk.SetStrBefore(sPos, lead.getValue()) ! original leading trivia wins over any parse artefact
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
              choose(self.preserved, '   (continuations preserved)', choose(self.multiLine, '   (multi-line span collapsed)', '')) & '<13,10>')

NoOpCheck routine
  ! compare against the EXACT source span (original spacing); identical
  ! replacement = nothing to do. Keeps casing-normalisation rules safe and
  ! stops any rule from driving the fixpoint without changing bytes.
  noOp = false
  self.RenderSpan(sPos, ePos, oldExact)
  ! DO NOT save multiLine here and restore it afterwards - that throws away the one answer that
  ! is actually correct. BuildRep renders each BINDING, and RenderSpan
  ! only inspects trivia for `i > pS`, so a binding of ONE token never looks at trivia at all -
  ! a '|' sitting between '(' and that token is inside the matched SPAN but outside the binding,
  ! leaving multiLine false. The width policy below is then never consulted and the span gets
  ! flattened at any width. The call above renders the WHOLE span and does see it. RenderSpan only
  ! ever SETS multiLine, never clears it, so simply not restoring gives the union of the two
  ! answers - which is right, because DeleteToks removes the span's interior trivia either way.
  if choose(oldExact._DataEnd < 1, '', oldExact.valuePtr[1 : oldExact._DataEnd]) = newTxt.getValue() then noOp = true.

WidthChk routine
  data
wt     long,auto
lsTok  long,auto
wlf    long,auto
lineW  long
spanW  long,auto
allowW long,auto
wsb    StringTheory
  code
  ! the width limit is LOCAL - the widest ORIGINAL line of the construct
  ! being edited (its own deliberate formatting), NOT the file maximum (one outlier
  ! wide line - a long comment or the sig literal - inflated the file cap and let
  ! 465-char flattens through as "in-limit"). allowed = spanW + 12 capped at 200;
  ! a construct already wider than 200 is respected as-is, never extended. Result:
  ! deliberately wrapped constructs PRESERVE and their | columns stay put.
  overWide = 0
  wResult  = newTxt._DataEnd
  wt = sPos              ! find the physical line start
  loop while wt > 1
    get(self.tk.tokens, wt)
    if errorcode() then break.
    if self.tk.tokens.firstOnLine then break.
    wt -= 1
  end
  lsTok = wt
  loop while wt < sPos   ! prefix width (line start .. match start)
    get(self.tk.tokens, wt)
    if errorcode() then break.
    if not self.tk.tokens.strBefore &= NULL
      wsb.setValue(self.tk.tokens.strBefore)
      wlf = wsb._DataEnd ! indent = chars after the LAST LF
      loop while wlf > 0
        if val(wsb.valuePtr[wlf]) = 10 then break.
        wlf -= 1
      end
      wResult += wsb._DataEnd - wlf
    end
    if not self.tk.tokens.tok &= NULL
      wResult += size(self.tk.tokens.tok)
    end
    wt += 1
  end
  wt = ePos + 1
  loop ! tail width to end of line
    if wt > self.tk.records() then break.
    if self.m.TokIsEOL(wt) then break.
    get(self.tk.tokens, wt)
    if errorcode() then break.
    if not self.tk.tokens.strBefore &= NULL
      wResult += size(self.tk.tokens.strBefore)
    end
    if not self.tk.tokens.tok &= NULL
      wResult += size(self.tk.tokens.tok)
    end
    wt += 1
  end
  wt = lsTok                               ! spanW: widest ORIGINAL line of the construct
  lineW = 0
  spanW = 0
  loop
    if wt > self.tk.records() then break.
    if self.m.TokIsEOL(wt)
      if wt > ePos then break.             ! the EOL closing the construct's last line
      if lineW > spanW then spanW = lineW. ! a real statement LF inside the span
      lineW = 0
      wt += 1
      cycle
    end
    get(self.tk.tokens, wt)
    if errorcode() then break.
    if not self.tk.tokens.strBefore &= NULL
      wsb.setValue(self.tk.tokens.strBefore)
      if wsb.containsByte(10)              ! continuation: line break lives in trivia <line feed>
        if lineW > spanW then spanW = lineW.
        wlf = wsb._DataEnd
        loop while wlf > 0
          if val(wsb.valuePtr[wlf]) = 10 then break.
          wlf -= 1
        end
        lineW = wsb._DataEnd - wlf         ! new line starts with its indent
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
! confuses a fold(...) that arrives inside bound source text).
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
    if pText[i] = ''''   ! quoted literal: copy verbatim (doubled quotes stay inside)
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
      j = i ! label run: starts with letter or _
      loop while j < n and self.IsLabelChar(pText[j+1])
        j += 1
      end
      word.setValue(pText[i : j])
      ! THIS gate decides which words are helper calls at all - a word that fails
      ! it is written out VERBATIM. the val/chr branches were added later below but not their
      ! words here, so val('=') survived into the output and BuiltinCheckCase folded it
      ! afterwards, prepending a second trailing comment. Add a branch, add it here too.
      case lower(word.getValue())
      of   'fold' orof 'trimr'  |
         orof 'len'  orof 'val' |
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
              bt.setValue(self.tk.FoldStr(inner.getValue()))
              do FoldCompare                                                                     ! use FoldStr's text only if it actually folded
              if folded
                pOut.append(bt)
              else
                pOut.append(inner)                                                               ! unfoldable: keep the rule's own spelling/spacing
              end
            elsif lower(choose(word._DataEnd < 1, '', word.valuePtr[1 : word._DataEnd])) = 'chr' ! chr(nn) -> the literal SOURCE TEXT for that byte, the
              litTxt = self.ComputeByteLit(inner.getValue())                                     !   inverse of val(lit): 61 -> '=' as source, not a
              if litTxt                                                                          !   runtime chr() call, which is what makes the readable
                pOut.append(clip(litTxt))                                                        !   direction actually readable
              else                                                                               ! not a plain byte number: keep the chr(...) spelling, which
                pOut.append('chr(')                                                              ! is valid Clarion and means the same thing at runtime
                pOut.append(inner)
                pOut.append(')')
              end
            elsif lower(choose(word._DataEnd < 1, '', word.valuePtr[1 : word._DataEnd])) = 'val' ! val(lit) -> the literal's BYTE value, for
              litLen = self.ComputeLitByte(inner.getValue())                                     !   st.findChar('=') -> st.findByte(61)
              if litLen >= 0
                pOut.append(litLen & '')                                                         ! numeric-to-string conversion carries no spaces
              else                                                                               ! not a single character: keep the val(...) spelling, which
                pOut.append('val(')                                                              ! is valid Clarion and means the same thing at runtime
                pOut.append(inner)
                pOut.append(')')
              end
            elsif lower(choose(word._DataEnd < 1, '', word.valuePtr[1 : word._DataEnd])) = 'len' ! len(lit) -> the literal's RUNTIME length
              litLen = self.ComputeLitLen(inner.getValue())
              if litLen >= 0
                pOut.append(litLen & '')                                                         ! numeric-to-string conversion carries no spaces
              else                                                                               ! not a countable single literal: keep the len(...)
                pOut.append('len(')                                                              ! spelling - valid Clarion, the compiler folds it
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
        ! this a rule that only meant to drop a clip also restyled the author's
        ! keyword - UPPER(CLIP(x)) & y came back as upper(x) & y. That contradicts the
        ! tool's own contract ("formatting changes only happen when you ask", and
        ! KeywordCase is the opt-in way to ask), and it was already INCONSISTENT
        ! inside one line: a metavar carries the source text verbatim, so
        ! `upper(LEFT(...))` came out with LEFT in caps and upper in lower case.
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
! a source `IF` keeps the caps too. First occurrence wins; a source that spells
! one identifier two ways in one statement is its own problem.
SrcCase routine
  data
sx  long,auto
ss  long,auto
se  long,auto
  code
  srcOk = 0
  get(self.m.matches, self.curMx)
  if errorcode() then exit.
  ss = self.m.matches.sPos
  se = self.m.matches.ePos
  loop sx = ss to se
    get(self.tk.tokens, sx)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL or |
       self.tk.tokens.type <> 'b' and self.tk.tokens.type <> 'r'
      cycle
    end
    if upper(self.tk.tokens.tok) = upper(word.getValue())
      srcSt.setValue(self.tk.tokens.tok)
      srcOk = 1
      break
    end
  end
FoldCompare routine
  ! folded = FoldStr's output differs from the input beyond whitespace
  folded = false
  if ~bt._DataEnd then exit.
  cmpA.setValue(bt)
  cmpB.setValue(inner)
  cmpA.removeByte(32) ! remove all <space>
  cmpB.removeByte(32) ! remove all <space>
  if choose(cmpA._DataEnd < 1, '', cmpA.valuePtr[1 : cmpA._DataEnd]) <> cmpB.getValue() then folded = true.

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
! space - interior comments never reach here, the matcher skip-guards them.
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
    self.contEmits += 1 ! one count per preserved SPAN (safety: >1 span in a replacement = revert to skip)
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
        rep = rep * 10 + val(pLit[j]) - 48
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
! quote needs four of them in the source, and this file has already been bitten three
! times by escape-doubling ('' < {), so the arithmetic form is the safe spelling.
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
  if n < 32 or n > 126                                  ! unprintable: the <nn> code spelling
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
      v = v * 10 + val(pLit[j]) - 48
      j += 1
    end
    if j = 3 or v > 255 then return -1.          ! no digits, or not a byte
    return v
  of 123                                         ! '{{'
    return 123                                   ! '{{{{' = one '{' character
  end
  return val(pLit[2])

! ------------------------------------------------------------------------------------
! 'xx  ' -> 'xx'   '  ' -> ''   (trailing spaces inside the quotes only;
! doubled quotes in the content are preserved). Not a literal -> unchanged.
! ------------------------------------------------------------------------------------
VitRewrite.TrimrLit Procedure(StringTheory pInOut)
x  long,auto
  code
  pInOut.trim()
  if pInOut._DataEnd < 2 or |
     pInOut.valuePtr[1] <> '''' or pInOut.valuePtr[pInOut._DataEnd] <> ''''
    return
  end
  x = pInOut._DataEnd - 1
  loop while x > 1 and pInOut.valuePtr[x] = ' '
    x -= 1
  end
  if x < 2
    pInOut.setValue('''''')                                             ! empty literal
  else
    pInOut.setValue('''' & pInOut.valuePtr[2 : x] & '''')
  end

! ------------------------------------------------------------------------------------
VitRewrite.BuildNote Procedure(StringTheory pOut)
t   long,auto
bt  StringTheory
nm  string(24),auto                                                     ! charname() result
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
c  long,auto
  code
  c = val(pC)
  case c
  of   65 to 90  ! A-Z
  orof 97 to 122 ! a-z
  orof 48 to 57  ! 0-9
  orof 95        ! _
  orof 58        ! :
    return true
  end
  return false
