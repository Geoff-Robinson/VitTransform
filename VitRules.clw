! VitRules Class - Phase 1 of VitTransform
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Parses rule files into IR. See VitRules.inc for the structures, and README.md
! for the rule-file language.
!
  MEMBER

  Include('VitRules.inc'),ONCE
  Include('VitTokenize.inc'),ONCE
  Include('StringTheory.inc'),ONCE

  Map
  End

! built-in data type keywords for METAVARS declarations (leading+trailing space significant)
mvBuiltinTypes  STRING(' STRING CSTRING PSTRING ASTRING LONG ULONG BYTE SHORT USHORT REAL SREAL ' & |
                       'DATE TIME DECIMAL PDECIMAL BFLOAT4 BFLOAT8 ANY SIGNED UNSIGNED INT64 UINT64 ')

! ------------------------------------------------------------------------------------
VitRules.Construct Procedure()
  code
  self.metaVars &= new MetaVarQType
  self.rules    &= new RuleQType
  self.issues   &= new IssueQType
  self.assumes  &= new AssumeQType
  self.typeSets &= new TypeSetQType
  self.groups   &= new GroupQType
  self.styles   &= new StyleQType
  self.tk       &= new VitTokenize
  self.workQ    &= NULL

! ------------------------------------------------------------------------------------
VitRules.Destruct Procedure()
  code
  self.FreeAll()
  dispose(self.metaVars)
  dispose(self.rules)
  dispose(self.issues)
  dispose(self.assumes)
  dispose(self.typeSets)
  dispose(self.groups)
  dispose(self.styles)
  dispose(self.tk)

! ------------------------------------------------------------------------------------
VitRules.FreeAll Procedure()
x   long,auto
y   long,auto
  code
  loop x = 1 to records(self.rules)
    get(self.rules, x)
    self.workQ &= self.rules.patQ
    self.FreePartQ()
    self.workQ &= self.rules.repQ
    self.FreePartQ()
    if not self.rules.noteQ &= NULL
      loop y = 1 to records(self.rules.noteQ)
        get(self.rules.noteQ, y)
        dispose(self.rules.noteQ.txt)
      end
      free(self.rules.noteQ)
      dispose(self.rules.noteQ)
    end
    if not self.rules.bparmQ &= NULL
      loop y = 1 to records(self.rules.bparmQ)
        get(self.rules.bparmQ, y)
        dispose(self.rules.bparmQ.value)
      end
      free(self.rules.bparmQ)
      dispose(self.rules.bparmQ)
    end
    dispose(self.rules.srcText)
    dispose(self.rules.repText)
    dispose(self.rules.guardVal)
    if not self.rules.guardQ &= NULL
      loop y = 1 to records(self.rules.guardQ)
        get(self.rules.guardQ, y)
        dispose(self.rules.guardQ.val)
      end
      free(self.rules.guardQ)
      dispose(self.rules.guardQ)
    end
  end
  free(self.rules)
  free(self.metaVars)
  free(self.issues)
  free(self.assumes)
  free(self.typeSets)
  free(self.groups)
  free(self.styles)
  self.workQ &= NULL
  self.curGroup     = 0
  self.lastUsed     = ''
  self.appliedStyle = ''
  self.defaultStyle = ''    ! cleared with the styles it names - a second load must not
  self.styleFromDefault = 0 !   inherit the previous file's default
  self.deferPhase   = 0     ! FreeAll must not leave a load stuck in the deferred phase
  self.inUserLoad   = 0
  self.userErrors   = 0

! ------------------------------------------------------------------------------------
VitRules.FreePartQ Procedure()
x   long,auto
  code
  if self.workQ &= NULL then return.
  loop x = 1 to records(self.workQ)
    get(self.workQ, x)
    dispose(self.workQ.tok)
    dispose(self.workQ.mvTail)
  end
  free(self.workQ)
  dispose(self.workQ)
  self.workQ &= NULL

! ------------------------------------------------------------------------------------
VitRules.LoadFile Procedure(STRING pFn)
st   StringTheory
  code
  if not st.LoadFile(pFn)
    self.AddIssue(0, vr:sevError, 'could not load rule file ' & clip(pFn) & ' : ' & st.LastError)
    return self.ErrorCount()
  end
  return self.ParseText(st)

! ------------------------------------------------------------------------------------
VitRules.ParseText Procedure(StringTheory pSt)
x         long,auto
pos       long,auto
inHeader  long
pending   long                                                  ! continuation in progress
accLine   long                                                  ! rule-file line the accumulated logical line started on
line      StringTheory
acc       StringTheory
up        StringTheory
  code
  if ~self.inUserLoad then self.FreeAll().                      ! a user rulefile APPENDS to the shipped set
  pSt.LineEndings(st:unix)
  pSt.split('<10>')

  loop x = 1 to pSt.records()
    line.setValue(pSt.getLine(x))
    line.replaceByte(9, 32)                                     ! tabs to spaces replace all <tab> with <space>
    pos = self.PosOutsideQuotes(line, '!')                      ! strip comment
    if pos then line.setLength(pos-1).
    line.trim()

    if pending
      acc.append(' ')
      acc.append(line)
    else
      acc.setValue(line)
      accLine = x + choose(self.inUserLoad = 1, vr:userBase, 0) ! EVERY user-file line number
    end                                                         !   (ruleId, declLine, issue lineNo) carries the offset

    ! continuation? (trailing | after comment strip)
    if acc._DataEnd and acc.valuePtr[acc._DataEnd] = '|'
      acc.setLength(acc._DataEnd - 1)
      acc.trim()
      pending = true
      cycle
    end
    pending = false

    if ~acc._DataEnd then cycle.                                ! blank / comment-only line

    up.setValue(acc)
    up.upper()

    if up._DataEnd = 8 and up.valuePtr[1 : 8] = 'METAVARS'
      inHeader = true
      cycle
    end

    if up._DataEnd > 8 and up.valuePtr[1 : 8] = 'BUILTIN '
      inHeader = false
      self.ParseBuiltinLine(acc, accLine)
    elsif self.PosOutsideQuotes(acc, '==>')
      inHeader = false
      self.ParseRuleLine(acc, accLine)
    elsif up._DataEnd > 7 and up.valuePtr[1 : 7] = 'ASSUME '
      self.ParseAssumeLine(acc, accLine)                             ! allowed in or out of the METAVARS header
    elsif up._DataEnd > 8 and up.valuePtr[1 : 8] = 'TYPESET '
      self.ParseTypeSetLine(acc, accLine)                            ! allowed in or out of the METAVARS header
    elsif up._DataEnd > 6 and up.valuePtr[1 : 6] = 'GROUP '          ! opens a group (implicitly closes an open one)
      inHeader = false                                               !     NB: GROUP/ENDGROUP/STYLE/LASTUSED are effectively reserved
      self.CloseGroup(accLine)                                       !     first words - a METAVAR cannot be named after them
      self.ParseGroupLine(acc, accLine)
    elsif up._DataEnd = 8 and up.valuePtr[1 : 8] = 'ENDGROUP'        ! explicit close (optional - next GROUP/STYLE/EOF also close)
      inHeader = false
      if ~self.curGroup
        self.AddIssue(accLine, vr:sevWarn, 'ENDGROUP without an open GROUP')
      end
      self.CloseGroup(accLine)
    elsif up._DataEnd > 6 and up.valuePtr[1 : 6] = 'STYLE '          ! named bundle of group picks
      inHeader = false
      self.CloseGroup(accLine)
      if self.inUserLoad                                             ! the two files stay single-purpose -
        self.AddIssue(accLine, vr:sevError, 'STYLE lines belong in the profile file (--stylefile=), not a user rulefile: ' & acc.getValue())
      else
        self.ParseStyleLine(acc, accLine, 0)
      end
    elsif up._DataEnd > 13 and up.valuePtr[1 : 13] = 'DEFAULTSTYLE ' ! the style a run with NO --style= gets
      inHeader = false
      self.CloseGroup(accLine)
      if self.inUserLoad                                             ! same reason as STYLE: a user file must not be
        self.AddIssue(accLine, vr:sevError, |                    !   able to change the whole selection out from under
          'DEFAULTSTYLE belongs in the shipped rule file, not a user rulefile: ' & acc.getValue())
      else
        self.defaultStyle = left(acc.sub(14, vr:maxName))
        if ~self.defaultStyle
          self.AddIssue(accLine, vr:sevError, 'DEFAULTSTYLE needs a style name, e.g. DEFAULTSTYLE optimised')
        end
      end                                                        ! the name is checked in Resolve, where the STYLE lines
                                                                 ! below this one have all been parsed
    elsif choose(up._DataEnd < 1, '', up.valuePtr[1 : up._DataEnd]) = 'THOROUGH' ! this rule file needs include expansion
      inHeader = false                                                           ! A bare word - no argument. It ASKS; the command
      self.CloseGroup(accLine)                                                   ! line decides, and --nothorough overrides it.
      if self.inUserLoad                                                         ! Same reasoning as DEFAULTSTYLE: a user rulefile
        self.AddIssue(accLine, vr:sevError, |    !   must not reach out and change how the
          'THOROUGH belongs in the shipped rule file, not a user rulefile')      !   whole run reads the source tree.
      else
        self.wantThorough = 1                                                    ! WHY IT BELONGS IN THE FILE: a rule set full of
        self.thoroughLine = accLine                                              !   typed StringTheory receivers cannot do its
      end                                                                        !   job without expansion, and that is a property
                                                                                 !   of the RULES, not of the style you pick to
                                                                                 !   run them. One visible line beats a switch
                                                                                 !   everyone has to remember to type.
    elsif up._DataEnd > 10 and up.valuePtr[1 : 10] = 'NEEDBUILD '                ! minimum engine build this rule file requires
      inHeader = false                                                           ! An OLDER engine does not know the word and lands in the
      self.ParseNeedBuildLine(acc, accLine)                                      ! unrecognised-line error below = refuses to load, which is
                                                                                 ! the point: a rule file using a newer replacement fold or
                                                                                 ! guard would otherwise MIS-EMIT silently on an old exe (the
                                                                                 ! EXPREND lesson, but general - no canary rule needed).
    elsif up._DataEnd > 9 and up.valuePtr[1 : 9] = 'LASTUSED '                   ! profile-file marker (stored for VitStyle; inert here)
      if self.inUserLoad                                                         ! profile-file marker, not a user-rulefile line
        self.AddIssue(accLine, vr:sevError, 'LASTUSED belongs in the profile file, not a user rulefile')
      else
        self.lastUsed = left(acc.sub(10, vr:maxName))
      end
    elsif inHeader
      self.ParseMetaVarLine(acc, accLine)
    else
      if acc.findChars('==>') and band(self.QuoteCount(acc), 1)
        ! the line VISIBLY contains ==> - the reason it did not parse as a rule is an
        ! unterminated quote making PosOutsideQuotes read the ==> as literal text.
        ! Point at the actual defect instead of listing everything the line is not.
        self.AddIssue(accLine, vr:sevError, 'unbalanced quote hides the ==> on this line (an odd number of quotes means one is unterminated): ' & acc.getValue())
      else
        self.AddIssue(accLine, vr:sevError, 'unrecognised line (no ==>, and not one of '                                & |
                      'BUILTIN/ASSUME/TYPESET/GROUP/ENDGROUP/STYLE/DEFAULTSTYLE/THOROUGH/LASTUSED/NEEDBUILD/METAVARS, ' & |
                      'nor inside a METAVARS block): ' & acc.getValue()) ! the list must name EVERY keyword a
                                                                         !   line could have been, or the message
                                                                         !   sends the reader looking for a typo in
                                                                         !   the four it forgot to mention
      end
    end
  end
  if pending                                                             ! file ended on a '|' continuation - the accumulated rule would otherwise vanish silently
    self.AddIssue(accLine, vr:sevError, 'file ends inside a continued rule (trailing |): ' & acc.getValue())
  end
  self.CloseGroup(accLine)                                               ! EOF closes an open group (runs its REVERSE expansion)
  return self.ErrorCount()

! ------------------------------------------------------------------------------------
VitRules.ParseMetaVarLine Procedure(StringTheory pLine, LONG pLineNo)
words     StringTheory
z         long,auto
typeIdx   long,auto
typeWord  STRING(vr:maxName)                                             ! AUTO unsafe: read before write
name      STRING(vr:maxName)                                             ! AUTO unsafe: read before write
kind      BYTE
tName     STRING(vr:maxName)
count     long,AUTO
  code
  words.setValue(pLine)
  words.split(' ')

  ! find last non-blank word = the type
  typeIdx = 0
  loop z = words.records() to 1 by -1
    if words.getLine(z)
      typeIdx = z
      break
    end
  end
  if typeIdx < 2
    self.AddIssue(pLineNo, vr:sevError, 'METAVARS line needs at least one name and a type: ' & pLine.getValue())
    return
  end
  if len(clip(words.getLine(typeIdx))) > size(typeWord)
    ! the STRING(vr:maxName) assignment below would TRUNCATE silently, the truncated
    ! spelling would classify as an unknown class name, and the rule would never match
    self.AddIssue(pLineNo, vr:sevError, 'METAVARS type is longer than ' & size(typeWord) & ' characters: ' & clip(words.getLine(typeIdx)))
    return
  end
  typeWord = upper(words.getLine(typeIdx))

  case typeWord
  of 'EXPR'    ; kind = vr:mvExpr    ; tName = ''
  of 'ARGS'    ; kind = vr:mvArgs    ; tName = ''
  of 'LITERAL' ; kind = vr:mvLiteral ; tName = ''
  of 'CONST'   ; kind = vr:mvConst   ; tName = ''
  of 'ANYVAR'  ; kind = vr:mvAnyVar  ; tName = ''
  else
    if instring(' ' & clip(typeWord) & ' ', mvBuiltinTypes, 1, 1)
      kind = vr:mvTyped
    elsif self.FindTypeSet(typeWord) ! a declared TYPESET name
      kind = vr:mvTypeSet
    else
      kind = vr:mvClass
    end
    tName = words.getLine(typeIdx)   ! preserve original casing for dump
  end

  ! all preceding non-blank words are names
  count = 0
  loop z = 1 to typeIdx - 1
    if len(clip(words.getLine(z))) > size(name)
      ! silent truncation was worse than it looks: the truncated spelling went into the
      ! table, every FULL-length use in a pattern then loaded as a LITERAL, and the only
      ! diagnostic was "declared but never used" naming a spelling the author never wrote
      ! (CheckNearMiss exits for tokens over vr:maxName, so the use sites said nothing)
      self.AddIssue(pLineNo, vr:sevError, 'metavar name is longer than ' & size(name) & ' characters: ' & clip(words.getLine(z)))
      count += 1
      cycle
    end
    name = words.getLine(z)
    if ~name then cycle.
    count += 1
    if ~self.IsLabelToken(name)
      self.AddIssue(pLineNo, vr:sevError, 'invalid metavar name: ' & clip(name))
      cycle
    end
    if self.FindMetaVar(name)
      self.AddIssue(pLineNo, vr:sevError, 'duplicate metavar declaration: ' & clip(name))
      cycle
    end
    clear(self.metaVars)
    self.metaVars.name      = name
    self.metaVars.kind      = kind
    self.metaVars.typeName  = tName
    self.metaVars.usedCount = 0
    self.metaVars.declLine  = pLineNo
    add(self.metaVars)
  end
  if ~count
    self.AddIssue(pLineNo, vr:sevError, 'METAVARS line has type but no names: ' & pLine.getValue())
  end

! ------------------------------------------------------------------------------------
VitRules.ParseRuleLine Procedure(StringTheory pLine, LONG pLineNo)
sepPos    long,auto
optPos    long,auto
optEnd    long,auto ! end of the option WORD, for the operand-position message
hadComma byte                        ! the option arrived comma-separated - the deliberate spelling (#5)
kwPos     long,auto ! start of the last WORD of the replacement
kwU       StringTheory
patTxt    StringTheory
repTxt    StringTheory
optTxt    StringTheory
rep       StringTheory
  code
  sepPos = self.PosOutsideQuotes(pLine, '==>')
  if ~sepPos        ! caller guarantees, but be safe
    self.AddIssue(pLineNo, vr:sevError, 'internal: ==> not found')
    return
  end

  patTxt.setValue(pLine.valuePtr[1 : sepPos-1])
  patTxt.trim()
  if sepPos + 3 > pLine._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'rule has empty replacement (use DELETE to remove a statement)')
    return
  end
  repTxt.setValue(pLine.valuePtr[sepPos+3 : pLine._DataEnd])
  repTxt.trim()

  ! split replacement text from trailing options
  optPos = self.FindOptionStart(repTxt)
  if optPos
    optTxt.setValue(repTxt.valuePtr[optPos : repTxt._DataEnd])
    ! the five option words are ordinary identifiers, so a replacement whose TAIL is one
    ! - `x = skip` - has that tail eaten as an option and truncates to `x =` WITHOUT a word.
    ! An option can only follow a COMPLETE replacement, so an operator immediately in front of
    ! the word proves it was written as an OPERAND and the split is wrong. ',' is deliberately
    ! not in the set - it is a legal option separator (`DELETE, ONCE`) - and a replacement that
    ! is NOTHING but an option word falls through to the empty-replacement error below, which
    ! already says the right thing.
    optEnd = optPos
    loop while optEnd <= repTxt._DataEnd and self.IsLabelChar(repTxt.valuePtr[optEnd])
      optEnd += 1
    end
    repTxt.setLength(optPos - 1)
    repTxt.trim()
    hadComma = 0
    if repTxt._DataEnd
      if repTxt.valuePtr[repTxt._DataEnd] = ','       ! the comma separator spelling ('DELETE, ONCE') is legal -
        repTxt.setLength(repTxt._DataEnd - 1)         !   strip it (and re-trim) or the exact-length DELETE/COMMENT
        repTxt.trim()                                 !   tests below never fire and the rule loads as TEXT
        hadComma = 1                                  !   ...and the comma PROVES the option was deliberate (#5 review)
      end
    end
    ! *** AND A KEYWORD THAT TAKES AN OPERAND IS THE SAME MISTAKE ONE TOKEN EARLIER. ***
    ! The test below reads the last CHARACTER, so `x = once` is caught by its '='. But
    ! `return once` ends in 'n', and the option word was the RETURN VALUE - the rule loaded
    ! quietly as `return` with the ONCE option set, which is a different rule from the one
    ! written. RETURN and DO both take an operand and neither ends in punctuation.
    kwPos = repTxt._DataEnd
    loop while kwPos > 1 and self.IsLabelChar(repTxt.valuePtr[kwPos - 1])
      kwPos -= 1
    end
    if repTxt._DataEnd                                              ! empty after the split ('pat ==> ONCE'):
      kwU.setValue(upper(repTxt.valuePtr[kwPos : repTxt._DataEnd])) !   [0 : 0] would slice a freed buffer -
    else                                                            !   fall through to the empty-replacement
      kwU.free()                                                    !   error below, as the comment above says
    end
    if ~hadComma and repTxt._DataEnd and (choose(kwU._DataEnd < 1, '', kwU.valuePtr[1 : kwU._DataEnd]) = 'RETURN' or choose(kwU._DataEnd < 1, '', kwU.valuePtr[1 : kwU._DataEnd]) = 'DO')  ! a comma-separated option after RETURN/DO is the legal spelling, not a lost operand (#5 review)
      self.AddIssue(pLineNo, vr:sevError, 'rule option ' & upper(optTxt.sub(1, optEnd - optPos))       & |
                    ' sits where an OPERAND belongs - ' & clip(kwU.getValue()) & ' takes one, so the'  & |
                    ' replacement would silently become "' & repTxt.getValue() & '". Write the option' & |
                    ' after a comma if that is what you meant.')
      return
    end
    if repTxt._DataEnd
      case val(repTxt.valuePtr[repTxt._DataEnd])
      of 61 orof 43 orof 45 orof 42 orof 47 orof 38 orof 60 orof 62 orof 126 orof 40 orof 91 ! = + - * / & < > ~ ( [
        self.AddIssue(pLineNo, vr:sevError, 'rule option ' & upper(optTxt.sub(1, optEnd - optPos))     & |
                      ' sits where an OPERAND belongs - the replacement would silently truncate to "'  & |
                      repTxt.getValue() & '". The option words are read as options wherever they'      & |
                      ' appear at bracket depth 0, so rename the identifier: ' & pLine.getValue())
        return
      end
    end
  else
    optTxt.free()
  end

  if ~patTxt._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'rule has empty pattern')
    return
  end
  if ~repTxt._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'rule has empty replacement (use DELETE to remove a statement)')
    return
  end

  ! without this, an unterminated quote in the REPLACEMENT loads CLEAN and splices the junk:
  ! the stray quote hides every option keyword from FindOptionStart (a trailing
  ! WHERE/NOTE becomes replacement TEXT), and TokenizeFragment absorbs an open literal
  ! to end-of-fragment without complaint - the swallowed guard and the quote itself
  ! reach the user's source. Quote PARITY is the whole test: doubled ''
  ! counts 2, so odd proves an unterminated quote somewhere in the tail. The pattern
  ! side needs no twin - an odd quote before ==> hides ==> itself from
  ! PosOutsideQuotes and the line is refused in ParseText, with its own hint.
  if band(self.QuoteCount(repTxt), 1)
    self.AddIssue(pLineNo, vr:sevError, 'unbalanced quote in replacement - anything after it (a WHERE or NOTE included) would be spliced into the output as text: ' & repTxt.getValue())
    return
  end

  ! ---- initialise rule buffer ----
  clear(self.rules)
  self.rules.ruleId    = pLineNo
  self.rules.kind      = vr:kindRule
  self.rules.groupId   = self.curGroup ! 0 = ungrouped (always active)
  self.rules.guardKind = vr:guardNone
  self.rules.srcText  &= new STRING(pLine._DataEnd)
  self.rules.srcText   = pLine.getValue()
  self.rules.noteQ    &= NULL
  self.rules.bparmQ   &= NULL
  self.rules.guardVal &= NULL
  self.rules.guardQ   &= NULL
  self.rules.repText  &= NULL

  ! ---- pattern ----
  self.rules.patQ &= new RulePartQType
  self.workQ      &= self.rules.patQ
  self.TokenizeFragment(patTxt.getValue(), pLineNo, true)

  ! ---- replacement ----
  self.rules.repQ &= new RulePartQType
  rep.setValue(repTxt)
  rep.upper()
  if rep._DataEnd = 6 and rep.valuePtr[1 : 6] = 'DELETE'
    self.rules.isDelete = true
  elsif rep._DataEnd = 7 and rep.valuePtr[1 : 7] = 'COMMENT'
    self.rules.isComment = true        ! delete's comment-out sibling (VitRewrite comment path)
  else
    self.workQ &= self.rules.repQ
    self.TokenizeFragment(repTxt.getValue(), pLineNo, false)
    repTxt.trim()
    if repTxt._DataEnd
      self.rules.repText &= new STRING(repTxt._DataEnd)
      self.rules.repText  = repTxt.getValue()
    end
  end

  ! ---- options ----
  if optTxt._DataEnd
    self.ParseOptions(optTxt, pLineNo)
  end

  add(self.rules)

! ------------------------------------------------------------------------------------
! NEEDBUILD nn - the minimum engine build a rule file requires.
! An OLDER engine never reaches here: it does not know the word, so the line falls
! through to the unrecognised-line error and the file refuses to load. That is the
! whole point. Before this existed, a file using a new REPLACEMENT fold or option had
! to smuggle in a canary rule (v13b's EXPREND canary) - and a new fold was worse than
! that: an old engine silently emitted the fold's argument instead of its value, so
! val('=') became '=' and st.findByte('=') searched for byte 0. Loud beats clever.
! ------------------------------------------------------------------------------------
VitRules.ParseNeedBuildLine Procedure(StringTheory pLine, LONG pLineNo)
raw    StringTheory
need   long,auto
  code
  raw.setValue(pLine.sub(11, 20)) ! text after 'NEEDBUILD '
  raw.trim()
  if ~raw._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'NEEDBUILD needs a build number, e.g. NEEDBUILD 85')
    return
  end
  if ~raw.IsAllDigits()           ! ST method, as at the guard parser
    self.AddIssue(pLineNo, vr:sevError, 'NEEDBUILD takes a plain build number: ' & raw.getValue())
    return
  end
  ! *** A LONG WRAPS, AND THIS ONE WRAPPED TO ZERO. *** NEEDBUILD exists to REFUSE a file an
  ! old engine would mis-bind, so a NEEDBUILD that quietly passes is the failure it was
  ! written to prevent, inverted: 4294967296 came back as 0, and 0 is not greater than any
  ! build. The driver's NumArg has capped digits for exactly this reason since long before.
  if raw._DataEnd > 9
    self.AddIssue(pLineNo, vr:sevError, 'NEEDBUILD number is too long: ' & raw.getValue() & |
                  ' - a build number is at most 9 digits')
    return
  end
  need = raw.getValue()
  if need > vr:buildNo
    self.AddIssue(pLineNo, vr:sevError, 'this rule file needs engine build ' & need & ' - this is build ' & vr:buildNo)
  end

! ------------------------------------------------------------------------------------
! ASSUME <name-pattern> <Type>  - e.g. ASSUME st* StringTheory
! Supplies a type for identifiers that FAIL symbol lookup (declared variables
! always win). Trailing * = prefix match; otherwise exact. Caseless.
! ------------------------------------------------------------------------------------
VitRules.ParseAssumeLine Procedure(StringTheory pLine, LONG pLineNo)
words  StringTheory
pat    StringTheory
typ    StringTheory
z      long,auto
n      long
  code
  words.setValue(pLine)
  words.split(' ')
  loop z = 2 to words.records() ! word 1 = ASSUME
    if ~words.getLine(z) then cycle.
    n += 1
    case n
    of 1
      pat.setValue(words.getLine(z),st:clip)
    of 2
      typ.setValue(words.getLine(z),st:clip)
    end
  end
  if n <> 2
    self.AddIssue(pLineNo, vr:sevError, 'ASSUME needs exactly: ASSUME <<name-pattern> <<type>: ' & pLine.getValue())
    return
  end
  clear(self.assumes)
  if pat.valuePtr[pat._DataEnd] = '*'
    self.assumes.isPrefix = true
    pat.setLength(pat._DataEnd - 1)
  end
  pat.upper()
  if ~pat._DataEnd or ~self.IsLabelToken(pat.getValue())
    self.AddIssue(pLineNo, vr:sevError, 'ASSUME name pattern must be an identifier (optionally ending *): ' & pLine.getValue())
    return
  end
  if ~self.IsLabelToken(typ.getValue())
    self.AddIssue(pLineNo, vr:sevError, 'ASSUME type must be a type keyword or class name: ' & pLine.getValue())
    return
  end
  if pat._DataEnd > size(self.assumes.namePat)
    ! the assignments below TRUNCATE silently, and a truncated prefix pattern matches
    ! names the author never meant (a truncated exact pattern matches nothing at all)
    self.AddIssue(pLineNo, vr:sevError, 'ASSUME name pattern is longer than ' & size(self.assumes.namePat) & ' characters: ' & pLine.getValue())
    return
  end
  if typ._DataEnd > size(self.assumes.typeName)
    self.AddIssue(pLineNo, vr:sevError, 'ASSUME type is longer than ' & size(self.assumes.typeName) & ' characters: ' & pLine.getValue())
    return
  end
  self.assumes.namePat  = pat.getValue()
  self.assumes.typeName = typ.getValue()
  self.assumes.declLine = pLineNo
  add(self.assumes)

! ------------------------------------------------------------------------------------
VitRules.AssumeType Procedure(STRING pName)
a      long,auto
nameU  STRING(vr:maxName)
patLen long,auto
  code
  if ~records(self.assumes) then return ''.
  nameU = upper(pName)
  loop a = 1 to records(self.assumes)
    get(self.assumes, a)
    patLen = len(clip(self.assumes.namePat))
    if ~patLen then cycle.
    if self.assumes.isPrefix
      if len(clip(nameU)) >= patLen and nameU[1 : patLen] = self.assumes.namePat[1 : patLen]
        return clip(self.assumes.typeName)
      end
    elsif nameU = self.assumes.namePat
      return clip(self.assumes.typeName)
    end
  end
  return ''

! ------------------------------------------------------------------------------------
VitRules.ParseBuiltinLine Procedure(StringTheory pLine, LONG pLineNo)
x         long,auto
startPos  long,auto
closePos  long,auto
! #Removed as not used: vx        long,auto                                ! walk cursor for the WHERE literal's real closing quote
rest      StringTheory
  code
  clear(self.rules)
  self.rules.ruleId    = pLineNo
  self.rules.kind      = vr:kindBuiltin
  self.rules.groupId   = self.curGroup ! a BUILTIN inside a GROUP is selectable with it
  self.rules.srcText  &= new STRING(pLine._DataEnd)
  self.rules.srcText   = pLine.getValue()
  self.rules.patQ     &= NULL
  self.rules.repQ     &= NULL
  self.rules.noteQ    &= NULL
  self.rules.guardVal &= NULL
  self.rules.guardQ   &= NULL
  self.rules.repText  &= NULL
  self.rules.bparmQ   &= new BParmQType

  ! skip 'BUILTIN' word (8 chars incl. space, caller verified) then read name
  rest.setValue(pLine.valuePtr[9 : pLine._DataEnd])
  rest.trim()
  x = 1
  loop while x <= rest._DataEnd and self.IsLabelChar(rest.valuePtr[x])
    x += 1
  end
  if x = 1
    self.AddIssue(pLineNo, vr:sevError, 'BUILTIN needs a name')
    add(self.rules)
    return
  end
  self.rules.builtinName = rest.valuePtr[1 : x-1]

  ! remaining: comma-separated params - NAME or NAME(raw value)
  loop
    ! skip separators
    loop while x <= rest._DataEnd and (rest.valuePtr[x] = ' ' or rest.valuePtr[x] = ',')
      x += 1
    end
    if x > rest._DataEnd then break.

    ! read param name
    startPos = x
    loop while x <= rest._DataEnd and self.IsLabelChar(rest.valuePtr[x])
      x += 1
    end
    if x = startPos
      self.AddIssue(pLineNo, vr:sevError, 'bad BUILTIN parameter text near: ' & rest.valuePtr[startPos : rest._DataEnd])
      break
    end
    clear(self.rules.bparmQ)
    self.rules.bparmQ.name   = rest.valuePtr[startPos : x-1]
    self.rules.bparmQ.value &= NULL

    ! optional (value)
    if x <= rest._DataEnd and rest.valuePtr[x] = '('
      closePos = self.MatchingParen(rest, x)
      if ~closePos
        self.AddIssue(pLineNo, vr:sevError, 'unmatched ( in BUILTIN parameter ' & clip(self.rules.bparmQ.name))
        add(self.rules.bparmQ)
        break
      end
      if closePos > x + 1
        self.rules.bparmQ.value &= new STRING(closePos - x - 1)
        self.rules.bparmQ.value  = rest.valuePtr[x+1 : closePos-1]
      end
      x = closePos + 1
    end
    add(self.rules.bparmQ)
  end
  add(self.rules)

! ------------------------------------------------------------------------------------
VitRules.ParseOptions Procedure(StringTheory pOpts, LONG pLineNo)
x         long,auto
startPos  long,auto
nextOpt   long,auto
closePos  long,auto
word      StringTheory
sub       StringTheory
haveWhere long
haveNote  long
  code
  x = 1
  loop
    ! skip separators
    loop while x <= pOpts._DataEnd and (pOpts.valuePtr[x] = ' ' or pOpts.valuePtr[x] = ',')
      x += 1
    end
    if x > pOpts._DataEnd then break.

    startPos = x
    loop while x <= pOpts._DataEnd and self.IsLabelChar(pOpts.valuePtr[x])
      x += 1
    end
    if x = startPos
      self.AddIssue(pLineNo, vr:sevError, 'bad option text near: ' & pOpts.valuePtr[startPos : pOpts._DataEnd])
      return
    end
    word.setValue(pOpts.valuePtr[startPos : x-1])
    word.upper()

    case word.getValue()
    of 'SKIP'
      self.rules.skip = true

    of 'ONCE'
      self.rules.once = true

    of 'EXPREND'  ! end-of-OPERAND assertion - the operand must END where the pattern does
      self.rules.exprEnd = true

    of 'INPARENS' ! depth assertion - the match must START inside an unclosed bracket
      self.rules.inParens = true

    of 'WHERE'
      if haveWhere
        self.AddIssue(pLineNo, vr:sevError, 'only one WHERE guard per rule in v1')
        return
      end
      haveWhere = true
      ! guard text runs to the next option keyword or EOL
      sub.setValue(pOpts.valuePtr[x : pOpts._DataEnd])
      nextOpt = self.FindOptionStart(sub)
      if nextOpt
        sub.setLength(nextOpt - 1)
        x = x + nextOpt - 1
      else
        x = pOpts._DataEnd + 1
      end
      sub.trim()
      self.ParseGuardList(sub, pLineNo)

    of 'NOTE'
      if haveNote
        self.AddIssue(pLineNo, vr:sevError, 'only one NOTE per rule in v1')
        return
      end
      haveNote = true
      ! expect (...)
      loop while x <= pOpts._DataEnd and pOpts.valuePtr[x] = ' '
        x += 1
      end
      if x > pOpts._DataEnd or pOpts.valuePtr[x] <> '('
        self.AddIssue(pLineNo, vr:sevError, 'NOTE must be followed by (...)')
        return
      end
      closePos = self.MatchingParen(pOpts, x)
      if ~closePos
        self.AddIssue(pLineNo, vr:sevError, 'unmatched ( in NOTE')
        return
      end
      if closePos > x + 1
        sub.setValue(pOpts.valuePtr[x+1 : closePos-1])
      else
        sub.free()
      end
      self.ParseNoteExpr(sub, pLineNo)
      x = closePos + 1

    else
      self.AddIssue(pLineNo, vr:sevError, 'unknown rule option: ' & word.getValue())
      return
    end
  end

! ------------------------------------------------------------------------------------
! ------------------------------------------------------------------------------------
! a WHERE guard is an AND-list of clauses. Split on top-level ' and '
! (caseless, outside quotes and brackets - a quoted guard literal may contain
! ' and '), parse each clause with ParseGuard (which fills the guard* scratch
! fields on the rules row), and copy every successful clause into rules.guardQ.
! Success signal = scratch guardKind: it is set ONLY at the end of each ParseGuard
! success path (guardMvx is set earlier and survives later error returns, so it
! cannot be the signal). On any clause error the rule file lints an error and the
! engine refuses to run, so a partially-filled guardQ never executes.
! ------------------------------------------------------------------------------------
VitRules.ParseGuardList Procedure(StringTheory pText, LONG pLineNo)
piece     StringTheory
x         long,auto
startP    long,auto
depth     long
inQ       byte
  code
  startP = 1
  x = 1
  loop while x <= pText._DataEnd
    case val(pText.valuePtr[x])
    of 39         ! <single quote>
      inQ = 1 - inQ
    of 40 orof 91 ! '(' orof '['
      if ~inQ then depth += 1.
    of 41 orof 93 ! ')' orof ']'
      if ~inQ then depth -= 1.
    end
    if ~inQ and ~depth and x + 4 <= pText._DataEnd and upper(pText.valuePtr[x : x+4]) = ' AND '
      if x > startP
        piece.setValue(pText.valuePtr[startP : x-1])
      else
        piece.free()
      end
      do OnePiece
      startP = x + 5
      x = x + 5
      cycle
    end
    x += 1
  end
  if pText._DataEnd >= startP
    piece.setValue(pText.valuePtr[startP : pText._DataEnd])
  else
    piece.free()
  end
  do OnePiece
  return

OnePiece routine
  piece.trim()
  self.rules.guardKind = vr:guardNone          ! success signal (see header comment)
  self.rules.guardVal &= NULL                  ! defensive: never re-dispose a ref the queue row now owns
  self.ParseGuard(piece, pLineNo)
  if ~self.rules.guardKind then exit.          ! clause error - ParseGuard already issued it
  if self.rules.guardQ &= NULL then self.rules.guardQ &= new GuardQType.
  clear(self.rules.guardQ)
  self.rules.guardQ.kind = self.rules.guardKind
  self.rules.guardQ.func = self.rules.guardFunc
  self.rules.guardQ.op   = self.rules.guardOp
  self.rules.guardQ.ct   = self.rules.guardCT
  self.rules.guardQ.mvx  = self.rules.guardMvx
  self.rules.guardQ.val &= self.rules.guardVal ! ownership moves to the row
  add(self.rules.guardQ)
  self.rules.guardVal   &= NULL

! ------------------------------------------------------------------------------------
VitRules.ParseGuard Procedure(StringTheory pText, LONG pLineNo)
x         long                                 ! deliberately NOT ,auto: x is init-ed only in the guardCT-correlated one-liners, which the
                                               ! AutoCheck walk cannot prove (it would re-remove ,AUTO every run). Zero-init is equivalent here.
startPos  long,auto
closePos  long,auto
vx        long,auto                            ! walk cursor for the WHERE literal's real closing quote
up        StringTheory
mvName    StringTheory
val       StringTheory
  code
  if ~pText._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'empty WHERE guard')
    return
  end
  up.setValue(pText)
  up.upper()

  ! --- class tests: isConst(mv) / isLiteral(mv) / isVar(mv) ---
  self.rules.guardCT = 0
  if up._DataEnd > 8 and up.valuePtr[1 : 8] = 'ISCONST('   then self.rules.guardCT = vr:ctConst;   x = 8.
  if up._DataEnd > 10 and up.valuePtr[1 : 10] = 'ISLITERAL(' then self.rules.guardCT = vr:ctLiteral; x = 10.
  if up._DataEnd > 6 and up.valuePtr[1 : 6] = 'ISVAR('     then self.rules.guardCT = vr:ctVar;     x = 6.
  if up._DataEnd > 9 and up.valuePtr[1 : 9] = 'ISSIMPLE('  then self.rules.guardCT = vr:ctSimple;  x = 9.            ! no depth-0 logical op
  if up._DataEnd > 7 and up.valuePtr[1 : 7] = 'ISPURE('    then self.rules.guardCT = vr:ctPure;    x = 7.            ! no calls in the binding
  if up._DataEnd > 14 and up.valuePtr[1 : 14] = 'ISCASENEUTRAL(' then self.rules.guardCT = vr:ctCaseNeutral; x = 14. ! the binding holds no letter
  if up._DataEnd > 11 and up.valuePtr[1 : 11] = 'ISCALLFREE(' then self.rules.guardCT = vr:ctCallFree; x = 11.       ! calls nothing - grouping parens are fine
  if up._DataEnd > 11 and up.valuePtr[1 : 11] = 'ISBOOLEXPR(' then self.rules.guardCT = vr:ctBoolExpr; x = 11.       ! HAS a depth-0 logical op - a logical expression, valued 1 or 0
  if self.rules.guardCT
    closePos = self.MatchingParen(pText, x)
    if ~closePos
      self.AddIssue(pLineNo, vr:sevError, 'unmatched ( in WHERE class test')
      return
    end
    mvName.setValue(pText.valuePtr[x+1 : closePos-1])
    mvName.trim()
    self.rules.guardMvx = self.FindMetaVar(mvName.getValue())
    if ~self.rules.guardMvx
      self.AddIssue(pLineNo, vr:sevError, 'WHERE references undeclared metavar: ' & mvName.getValue())
      return
    end
    self.rules.guardKind = vr:guardClassTest
    do BumpUsed
    return
  end

  ! --- comparison: [fold(|len(] mv [)] op 'literal'  (len: op integer) ---
  ! There is deliberately NO trimr() guard: the compare
  ! below is Clarion's own, so trailing spaces are ALREADY ignored - trimr(x) = 'y'
  ! and x = 'y' could never answer differently, and a guard spelling that promises a
  ! distinction it cannot deliver is worse than none. trimr() in a REPLACEMENT is a
  ! different animal (it edits the literal's real bytes) and exists there. A rule
  ! writing trimr() in a WHERE lands in the generic undeclared-metavar error, which
  ! is the right answer for a word this language does not have.
  x = 1
  self.rules.guardFunc = vr:gfNone
  if up._DataEnd > 5 and up.valuePtr[1 : 5] = 'FOLD('
    self.rules.guardFunc = vr:gfFold
    x = 5
  elsif up._DataEnd > 4 and up.valuePtr[1 : 4] = 'LEN('
    self.rules.guardFunc = vr:gfLen
    x = 4
  end
  if self.rules.guardFunc
    closePos = self.MatchingParen(pText, x)
    if ~closePos
      self.AddIssue(pLineNo, vr:sevError, 'unmatched ( in WHERE function')
      return
    end
    mvName.setValue(pText.valuePtr[x+1 : closePos-1])
    mvName.trim()
    x = closePos + 1
  else
    startPos = x
    loop while x <= pText._DataEnd and self.IsLabelChar(pText.valuePtr[x])
      x += 1
    end
    if x = startPos
      self.AddIssue(pLineNo, vr:sevError, 'WHERE guard must start with a metavar or fold()/len()/isConst()/isLiteral()/isVar()/isSimple()/isPure()/isCaseNeutral()')
      return
    end
    mvName.setValue(pText.valuePtr[startPos : x-1])
  end

  self.rules.guardMvx = self.FindMetaVar(mvName.getValue())
  if ~self.rules.guardMvx
    self.AddIssue(pLineNo, vr:sevError, 'WHERE references undeclared metavar: ' & mvName.getValue())
    return
  end
  do BumpUsed

  ! operator
  loop while x <= pText._DataEnd and pText.valuePtr[x] = ' '
    x += 1
  end
  if x < pText._DataEnd and pText.valuePtr[x : x+1] = '<<>'
    self.rules.guardOp = vr:opNeq
    x += 2
  elsif x <= pText._DataEnd and pText.valuePtr[x] = '='
    self.rules.guardOp = vr:opEq
    x += 1
  else
    self.AddIssue(pLineNo, vr:sevError, 'WHERE guard needs = or <<> then a quoted literal')
    return
  end

  ! comparison value: quoted literal, or a bare integer for len()
  loop while x <= pText._DataEnd and pText.valuePtr[x] = ' '
    x += 1
  end
  if self.rules.guardFunc = vr:gfLen
    if x > pText._DataEnd
      self.AddIssue(pLineNo, vr:sevError, 'WHERE len() comparison needs an integer value')
      return
    end
    val.setValue(pText.valuePtr[x : pText._DataEnd])
    val.trim()
    if ~val.IsAllDigits()
      self.AddIssue(pLineNo, vr:sevError, 'WHERE len() comparison value must be a bare integer (no quotes)')
      return
    end
    get(self.metaVars, self.rules.guardMvx)
    if ~errorcode() and self.metaVars.kind <> vr:mvLiteral and self.rules.guardOp = vr:opEq
      ! len(non-literal) is always -1, so '=' can never pass; '<>' is the idiom
      ! for "anything except an n-char literal" and stays silent
      self.AddIssue(pLineNo, vr:sevWarn, 'len() = guard on a non-LITERAL metavar can never be true (non-literals have len -1); use <<> or a LITERAL metavar')
    end
    self.rules.guardVal &= new STRING(val._DataEnd)
    self.rules.guardVal  = val.getValue()
    self.rules.guardKind = vr:guardCompare
    return
  end
  if x > pText._DataEnd or pText.valuePtr[x] <> ''''
    self.AddIssue(pLineNo, vr:sevError, 'WHERE comparison value must be a quoted literal')
    return
  end
  val.setValue(pText.valuePtr[x : pText._DataEnd])
  val.trim()
  ! Walk the FIRST literal to its real close, then require that NOTHING follows it.
  ! The old test was "starts with a quote and does not END with one", which `WHERE w = 'a' 'b'`
  ! passes - it ends with a quote - so the junk folded into the comparison value quotes-and-all
  ! and the guard silently never matched anything. A doubled '' inside the literal is an
  ! escaped quote, not the close, which is why this walks rather than searching for the next.
  if val._DataEnd > 1 and val.valuePtr[1] = ''''
    vx = 2
    loop while vx <= val._DataEnd
      if val.valuePtr[vx] <> ''''
        vx += 1
      elsif vx < val._DataEnd and val.valuePtr[vx + 1] = ''''
        vx += 2 ! '' - an escaped quote, still inside the literal
      else
        break   ! the closing quote
      end
    end
    if vx > val._DataEnd
      self.AddIssue(pLineNo, vr:sevError, 'unterminated WHERE literal: ' & val.getValue())
      return
    end
    if vx < val._DataEnd
      self.AddIssue(pLineNo, vr:sevError, 'text after the WHERE literal: ' & val.getValue())
      return
    end
  end
  val.unquote('''')
  if val._DataEnd
    self.rules.guardVal &= new STRING(val._DataEnd)
    self.rules.guardVal  = val.getValue()
  else
    self.rules.guardVal &= NULL ! fixed STRING cannot hold '': NULL guardVal means empty literal
  end
  self.rules.guardKind = vr:guardCompare
  return

BumpUsed routine
  ! mark metavar used (guard reference)
  get(self.metaVars, self.rules.guardMvx)
  if ~errorcode()
    self.metaVars.usedCount += 1
    put(self.metaVars)
  end

! ------------------------------------------------------------------------------------
VitRules.ParseNoteExpr Procedure(StringTheory pText, LONG pLineNo)
x         long,auto
segStart  long,auto
inQ       long
seg       StringTheory
mvx       long,auto
  code
  self.rules.noteQ &= new NotePartQType
  if ~pText._DataEnd
    self.AddIssue(pLineNo, vr:sevWarn, 'empty NOTE()')
    return
  end

  ! split on & outside quotes; each segment is a quoted literal or a metavar name
  segStart = 1
  x = 1
  loop
    if x > pText._DataEnd or (pText.valuePtr[x] = '&' and ~inQ)
      seg.setValue(pText.valuePtr[segStart : choose(x > pText._DataEnd, pText._DataEnd, x-1)])
      seg.trim()
      do AddSeg
      if x > pText._DataEnd then break.
      segStart = x + 1
    elsif pText.valuePtr[x] = ''''
      inQ = 1 - inQ
    end
    x += 1
  end
  return

AddSeg routine
  if ~seg._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'empty segment in NOTE expression')
    exit
  end
  clear(self.rules.noteQ)
  if seg.valuePtr[1] = ''''
    seg.unquote('''')
    if ~seg._DataEnd
      self.AddIssue(pLineNo, vr:sevWarn, 'empty literal in NOTE contributes nothing - ignored')
      exit
    end
    self.rules.noteQ.mvx  = 0
    self.rules.noteQ.txt &= new STRING(seg._DataEnd)
    self.rules.noteQ.txt  = seg.getValue()
  else
    ! one helper is allowed around a metavar - charname(mv) prints the readable
    ! name of an unprintable character, so a generated comment reads `! <line feed>`
    ! instead of `! '<10>'` (the same wording BUILTIN CheckCaseStatements emits).
    if seg.clipLength() > 10 and lower(seg.sub(1, 9)) = 'charname(' |
       and seg.valuePtr[seg._DataEnd] = ')'
      self.rules.noteQ.func = vr:nfCharName
      seg.setValue(seg.valuePtr[10 : seg._DataEnd - 1])
      seg.trim()
    end
    mvx = self.FindMetaVar(seg.getValue())
    if ~mvx
      self.AddIssue(pLineNo, vr:sevError, 'NOTE references undeclared metavar: ' & seg.getValue())
      exit
    end
    self.rules.noteQ.mvx  = mvx
    self.rules.noteQ.txt &= NULL
    get(self.metaVars, mvx)
    if ~errorcode()
      self.metaVars.usedCount += 1
      put(self.metaVars)
    end
  end
  add(self.rules.noteQ)

! ------------------------------------------------------------------------------------
VitRules.TokenizeFragment Procedure(STRING pText, LONG pLineNo, BYTE pIsPattern)
frag   StringTheory
t      long,auto
mvx    long,auto
tokLen long,auto
dotP   long,auto          ! first '.' in a merged dotted token
  code
  if self.workQ &= NULL then return.
  ! leading space so the first identifier is not treated as a column-1 label
  frag.setValue(' ' & pText)
  self.tk.ParseText(frag) ! risk: fragment parsing - verify in dump

  loop t = 1 to self.tk.records()
    get(self.tk.tokens, t)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL or |
       self.tk.tokens.tok = '<10>' ! skip EOL tokens
      cycle
    end
    tokLen = len(clip(self.tk.tokens.tok))
    if ~tokLen then cycle.

    clear(self.workQ)
    self.workQ.mvTail &= NULL
    self.workQ.tok &= new STRING(tokLen)
    self.workQ.tok  = self.tk.tokens.tok
    mvx = 0
    if self.IsLabelToken(self.workQ.tok)
      mvx = self.FindMetaVar(self.workQ.tok)
    end
    if ~mvx and pIsPattern and tokLen > 2                    ! a property access like st._DataEnd arrives as ONE
      dotP = instring('.', self.workQ.tok, 1, 1)             ! merged token (vitTokenize label merge - only a following '('
      if dotP > 1 and dotP < tokLen                          ! blocks it), so a metavar HEAD makes this a dotted occurrence,
        if self.IsLabelToken(self.workQ.tok[1 : dotP-1])     ! not a literal (a literal would only ever match a source
          mvx = self.FindMetaVar(self.workQ.tok[1 : dotP-1]) ! variable literally named like the metavar)
          if mvx
            self.workQ.mvTail &= new STRING(tokLen - dotP)
            self.workQ.mvTail  = self.workQ.tok[dotP+1 : tokLen]
          end
        end
      end
    end
    self.workQ.mvx = mvx
    add(self.workQ)

    if mvx
      get(self.metaVars, mvx)
      if ~errorcode()
        self.metaVars.usedCount += 1
        put(self.metaVars)
      end
    end
  end

! ------------------------------------------------------------------------------------
VitRules.Lint Procedure()
r         long,auto
t         long,auto
m         long,auto
patSet    STRING(1),DIM(500) ! metavar-index presence in current rule's pattern - 500 metavar cap
mvCount   long,auto
base1     STRING(vr:maxName)
z         long,auto
bDepth    long,auto          ! bracket depth while scanning pattern for ';' boundaries
bCount    long,auto          ! interior ';' boundaries seen
nq        QUEUE              ! normalized rule texts for the inverse-pair scan
row         LONG             !     rules row
id          LONG             !     ruleId (for the message)
grpRow      LONG
patN        STRING(600)      !     600-char cap: a truncated-equal pair still flags (rare, safe side)
repN        STRING(600)
          END
sMembers  StringTheory       ! style member validation
memNm     StringTheory
chcAcc    StringTheory
normA     StringTheory
sName     STRING(vr:maxName),AUTO
sIsProf   BYTE,AUTO
sLine     long,auto
i2        long,auto
j2        long,auto
rowA      long,auto
idA       long,auto
grpA      long,auto
patA      STRING(600),AUTO
repA      STRING(600),AUTO
chcA      STRING(vr:maxName),AUTO
pairOK    BYTE,AUTO
  code
  mvCount = records(self.metaVars)
  ! patSet is DIM(500) and every use below is gated on `mvx <= 500`, so past that cap the
  ! presence checks quietly stop happening and Lint passes rules it has not actually checked -
  ! failing OPEN, where ExpandReverse fails CLOSED on the same cap. Say so instead. One error
  ! for the file, not one per rule: the cap is a property of this build, not of any one rule.
  if mvCount > 500
    self.AddIssue(0, vr:sevError, 'this rule file declares ' & mvCount & ' metavars; the lint checks that ' & |
                  'every replacement/WHERE/NOTE metavar appears in its pattern cover only the first 500, '  & |
                  'so rules using the rest would load UNCHECKED. Split the file.')
  end
  loop m = 1 to mvCount ! a TYPESET declared AFTER the METAVARS line that uses it would fall back to a silent dead mvClass
    get(self.metaVars, m)
    if self.metaVars.kind = vr:mvClass and self.FindTypeSet(self.metaVars.typeName)
      self.AddIssue(self.metaVars.declLine, vr:sevError, 'metavar ' & clip(self.metaVars.name) & ': TYPESET ' |
         & clip(self.metaVars.typeName) & ' is declared AFTER this METAVARS line - move the TYPESET above it')
    end
  end

  ! unused metavars
  loop m = 1 to mvCount
    get(self.metaVars, m)
    if ~self.metaVars.usedCount
      self.AddIssue(self.metaVars.declLine, vr:sevWarn, 'metavar declared but never used: ' & clip(self.metaVars.name))
    end
  end

  loop r = 1 to records(self.rules)
    get(self.rules, r)
    if self.rules.kind <> vr:kindRule then cycle.

    ! build pattern metavar set + pattern-side checks
    clear(patSet)
    self.workQ &= self.rules.patQ
    if not self.workQ &= NULL
      loop t = 1 to records(self.workQ)
        get(self.workQ, t)
        if self.workQ.mvx
          if not self.workQ.mvTail &= NULL                             ! a dotted occurrence VERIFIES the head, it never
            if self.workQ.mvx <= 500 and patSet[self.workQ.mvx] <> '1' ! BINDS it - so it does not set patSet, and
              get(self.metaVars, self.workQ.mvx)                       ! it needs a plain occurrence EARLIER
              self.AddIssue(self.rules.ruleId, vr:sevError, 'dotted metavar ' & clip(self.metaVars.name) |
                 & '.' & clip(self.workQ.mvTail) & ' needs ' & clip(self.metaVars.name) & ' bound earlier in the pattern')
            end
          else
            if self.workQ.mvx <= 500 then patSet[self.workQ.mvx] = '1'.
            do CheckArgsPlacement
          end
        else
          do CheckNearMiss
          do CheckLateDecl
        end
      end
      ! spec v0.3: ';' in a pattern = statement boundary - placement checks
      bDepth = 0
      bCount = 0
      loop t = 1 to records(self.workQ)
        get(self.workQ, t)
        if self.workQ.tok &= NULL then cycle.
        if ~self.workQ.mvx and self.workQ.tok = ';'
          if t = 1
            self.AddIssue(self.rules.ruleId, vr:sevError, 'pattern cannot start with a statement boundary '';'' (statement-start anchoring is automatic)')
          elsif bDepth
            self.AddIssue(self.rules.ruleId, vr:sevError, 'statement boundary '';'' inside brackets in pattern')
          elsif t < records(self.workQ)
            bCount += 1
          end
        elsif ~self.workQ.mvx
          case val(clip(self.workQ.tok))
          of 40 orof 91 ! '(' orof '['
            bDepth += 1
          of 41 orof 93 ! ')' orof ']'
            bDepth -= 1
          end
        end
      end
      if bCount > 1
        self.AddIssue(self.rules.ruleId, vr:sevWarn, 'pattern has ' & bCount + 1 & ' statement fragments - only two-fragment patterns are exercised so far')
      end
    end

    ! replacement references must exist in pattern
    self.workQ &= self.rules.repQ
    if not self.workQ &= NULL
      loop t = 1 to records(self.workQ)
        get(self.workQ, t)
        if self.workQ.mvx
          if self.workQ.mvx <= 500 and patSet[self.workQ.mvx] <> '1'
            get(self.metaVars, self.workQ.mvx)
            self.AddIssue(self.rules.ruleId, vr:sevError, 'replacement uses metavar not present in pattern: ' & clip(self.metaVars.name))
          end
          do CheckArgsPlacement
        else
          do CheckNearMiss
          do CheckLateDecl
        end
      end
    end

    ! guard / note references must exist in pattern (per WHERE clause)
    if not self.rules.guardQ &= NULL
      loop t = 1 to records(self.rules.guardQ)
        get(self.rules.guardQ, t)
        if self.rules.guardQ.mvx and self.rules.guardQ.mvx <= 500 and patSet[self.rules.guardQ.mvx] <> '1'
          get(self.metaVars, self.rules.guardQ.mvx)
          self.AddIssue(self.rules.ruleId, vr:sevError, 'WHERE uses metavar not present in pattern: ' & clip(self.metaVars.name))
        end
      end
    end
    if not self.rules.noteQ &= NULL
      loop t = 1 to records(self.rules.noteQ)
        get(self.rules.noteQ, t)
        if self.rules.noteQ.mvx
          if self.rules.noteQ.mvx <= 500 and patSet[self.rules.noteQ.mvx] <> '1'
            get(self.metaVars, self.rules.noteQ.mvx)
            self.AddIssue(self.rules.ruleId, vr:sevError, 'NOTE uses metavar not present in pattern: ' & clip(self.metaVars.name))
          end
        end
      end
    end
  end

  ! ---- style member consistency ----
  ! Shipped styles: unknown member / two members of one choice = author ERROR.
  ! Profiles: same findings degrade to WARN (design 5c - never refuse to load; the
  ! resolver drops/last-wins and the selection table shows what actually ran).
  loop r = 1 to records(self.styles)
    get(self.styles, r)
    sName   = self.styles.name
    sIsProf = self.styles.isProfile
    sLine   = self.styles.declLine
    sMembers.setValue(self.styles.members)
    sMembers.split(',')
    chcAcc.free()
    loop t = 1 to sMembers.records()
      memNm.setValue(sMembers.getLine(t))
      memNm.trim()
      if ~memNm._DataEnd then cycle.
      if memNm.valuePtr[1] = '-'                           ! negated member - validate the NAME, skip the
        memNm.setValue(memNm.valuePtr[2 : memNm._DataEnd]) !      choice-duplicate tracking (a deselect never
        memNm.trim()                                       !      competes for a choice)
        if ~memNm._DataEnd then cycle.
        m = self.FindGroup(memNm.getValue())
        if ~m
          if sIsProf
            self.AddIssue(sLine, vr:sevWarn, 'profile ' & clip(sName) & ' negates unknown group ' & memNm.getValue() & ' - dropped at resolve (rule file moved on?)')
          else
            self.AddIssue(sLine, vr:sevError, 'STYLE ' & clip(sName) & ' negates unknown group: ' & memNm.getValue())
          end
        end
        cycle
      end
      m = self.FindGroup(memNm.getValue())
      if ~m
        if sIsProf
          self.AddIssue(sLine, vr:sevWarn, 'profile ' & clip(sName) & ' names unknown group ' & memNm.getValue() & ' - dropped at resolve (rule file moved on?)')
        else
          self.AddIssue(sLine, vr:sevError, 'STYLE ' & clip(sName) & ' names unknown group: ' & memNm.getValue())
        end
        cycle
      end
      get(self.groups, m)
      if self.groups.choiceName
        if chcAcc.findChars(' ' & upper(clip(self.groups.choiceName)) & ' ')
          if sIsProf
            self.AddIssue(sLine, vr:sevWarn, 'profile ' & clip(sName) & ' picks two groups of choice ' & clip(self.groups.choiceName) & ' - the later pick wins')
          else
            self.AddIssue(sLine, vr:sevError, 'STYLE ' & clip(sName) & ' picks two groups of choice ' & clip(self.groups.choiceName))
          end
        else
          chcAcc.append(' ' & upper(clip(self.groups.choiceName)) & ' ')
        end
      end
    end
  end

  ! ---- inverse-pair detection (anti-ping-pong, layer 2) ----
  ! Two rules that are exact textual inverses converge only if selection can never
  ! activate both together: they must sit in two DIFFERENT groups of ONE choice.
  ! Anywhere else (both ungrouped, one ungrouped, same group, different choices)
  ! the pair could co-run and the fixpoint ping-pongs to the 20-pass cap: ERROR
  ! here at lint time instead.
  free(nq)
  loop r = 1 to records(self.rules)
    get(self.rules, r)
    if self.rules.kind <> vr:kindRule or self.rules.isDelete or self.rules.isComment then cycle. ! COMMENT is delete-shaped (no rep)
    nq.row    = r
    nq.id     = self.rules.ruleId
    nq.grpRow = self.rules.groupId
    self.workQ &= self.rules.patQ
    self.NormalizeParts(normA)
    nq.patN   = normA.getValue()
    self.workQ &= self.rules.repQ
    self.NormalizeParts(normA)
    nq.repN   = normA.getValue()
    ! a replacement CONTAINING its own pattern re-matches its own output,
    ! nesting one level per pass to the cap - the choose-fallback near-miss
    ! shape. Proper containment only - equal texts are the degenerate no-op
    ! case below. WARNING not error: a WHERE guard CAN break the cycle, and
    ! the 600-char normalize cap could in principle false-positive.
    if nq.patN <> nq.repN and nq.patN and instring(clip(nq.patN), clip(nq.repN), 1, 1)
      self.AddIssue(nq.id, vr:sevWarn, |
         'rule ' & nq.id & ': replacement CONTAINS its own pattern - each pass re-wraps its own output (never converges); restructure the replacement or verify a guard breaks the cycle')
    end
    if nq.patN = nq.repN then cycle. ! degenerate; not an inverse-pair candidate
    add(nq)
  end
  loop i2 = 1 to records(nq) - 1
    get(nq, i2)
    rowA = nq.row
    idA  = nq.id
    grpA = nq.grpRow
    patA = nq.patN
    repA = nq.repN
    loop j2 = i2 + 1 to records(nq)
      get(nq, j2)
      if nq.patN <> repA or nq.repN <> patA then cycle.
      pairOK = 0
      if grpA and nq.grpRow and grpA <> nq.grpRow                                ! different groups...
        get(self.groups, grpA)
        chcA = self.groups.choiceName
        get(self.groups, nq.grpRow)
        if chcA and upper(chcA) = upper(self.groups.choiceName) then pairOK = 1. ! ...of one choice
      end
      if ~pairOK
        self.AddIssue(idA, vr:sevError, 'rules ' & idA & ' and ' & nq.id & ' are exact inverses and could run together (ping-pong) - put them in two GROUPs of one CHOICE')
      end
    end
  end
  free(nq)

  self.workQ &= NULL
  return self.ErrorCount()

CheckArgsPlacement routine
  ! ARGS must be the sole content between ( and )
  data
prevOK byte,AUTO
nextOK byte,AUTO
svPtr  long,AUTO
  code
  get(self.metaVars, self.workQ.mvx)
  if errorcode() or self.metaVars.kind <> vr:mvArgs then exit.
  svPtr = t
  prevOK = false
  nextOK = false
  get(self.workQ, svPtr - 1)
  if ~errorcode() and self.workQ.tok = '(' then prevOK = true.
  get(self.workQ, svPtr + 1)
  if ~errorcode() and self.workQ.tok = ')' then nextOK = true.
  get(self.workQ, svPtr) ! restore
  if ~prevOK or ~nextOK
    self.AddIssue(self.rules.ruleId, vr:sevError, 'ARGS metavar ' & clip(self.metaVars.name) & ' must be the entire (...) content')
  end

CheckNearMiss routine
  ! literal token that closely resembles a declared metavar -> probable typo
  data
tokBase STRING(vr:maxName)
  code
  if ~self.IsLabelToken(self.workQ.tok) then exit.
  if len(clip(self.workQ.tok)) > vr:maxName then exit.
  ! strip trailing digits from the token
  tokBase = self.workQ.tok
  loop while tokBase and inrange(val(tokBase[len(clip(tokBase))]), 48, 57)
    tokBase = sub(tokBase, 1, len(clip(tokBase)) - 1)
  end
  loop z = 1 to mvCount
    get(self.metaVars, z)
    ! declared-name base (trailing digits stripped)
    base1 = self.metaVars.name
    loop while base1 and inrange(val(base1[len(clip(base1))]), 48, 57)
      base1 = sub(base1, 1, len(clip(base1)) - 1)
    end
    if upper(tokBase) = upper(base1) and upper(self.workQ.tok) <> upper(self.metaVars.name)
      self.AddIssue(self.rules.ruleId, vr:sevWarn, 'token ''' & clip(self.workQ.tok) & ''' resembles metavar '''        & |
                    clip(self.metaVars.name) & ''' - declare it or rename (treated as literal)')
      exit
    end
    if self.OneCharDiff(upper(clip(self.workQ.tok)), upper(clip(self.metaVars.name)))
      self.AddIssue(self.rules.ruleId, vr:sevWarn, 'token ''' & clip(self.workQ.tok) & ''' is one edit from metavar ''' & |
                    clip(self.metaVars.name) & ''' - possible typo (treated as literal)')
      exit
    end
  end

CheckLateDecl routine
  ! exact-name use of a metavar whose METAVARS line sits BELOW this rule. Names
  ! resolve at parse time in FILE ORDER, so the token loaded as a LITERAL and the
  ! rule can never match what its author meant - and every other lint is blind to
  ! it by construction: identical is not a near-miss (CheckNearMiss requires the
  ! spellings to differ), and one later legitimate use keeps usedCount above zero,
  ! which silences the never-used warning too. Fail closed: an error, not a warn -
  ! a rule that WANTS to match the literal spelling of a later metavar's name can
  ! rename one of the two.
  data
ldx long,auto
  code
  if self.workQ.tok &= NULL then exit.
  if ~self.IsLabelToken(self.workQ.tok) then exit.
  ldx = self.FindMetaVar(self.workQ.tok)
  if ~ldx then exit.
  get(self.metaVars, ldx)
  if self.metaVars.declLine > self.rules.ruleId
    self.AddIssue(self.rules.ruleId, vr:sevError, 'metavar ' & clip(self.metaVars.name) & ' is used here but its METAVARS line is BELOW this rule (line ' |
       & self.metaVars.declLine & ') - names resolve in file order, so this token loaded as a LITERAL; move the METAVARS line above the rule')
  end

! ------------------------------------------------------------------------------------
VitRules._List Procedure(StringTheory pOut)
r     long,auto
t     long,auto
m     long,auto
g     long,auto ! guardQ row
line  StringTheory
crlf  EQUATE('<13,10>')
  code
  pOut.free()
  pOut.append('VitRules IR dump - ' & format(today(),@d17) & ' ' & format(clock(),@T04) & crlf)
  pOut.append('Metavars: ' & records(self.metaVars) & crlf)
  loop m = 1 to records(self.metaVars)
    get(self.metaVars, m)
    pOut.append('  ' & m & '. ' & clip(self.metaVars.name) & '  ' & clip(self.KindName(self.metaVars.kind)))
    if self.metaVars.typeName then pOut.append(':' & clip(self.metaVars.typeName)).
    pOut.append('  (used ' & self.metaVars.usedCount & ')' & crlf)
  end
  loop m = 1 to records(self.assumes)
    get(self.assumes, m)
    pOut.append('  ASSUME ' & clip(self.assumes.namePat) & choose(self.assumes.isPrefix, '*', '') & |
                ' -> ' & clip(self.assumes.typeName) & crlf)
  end
  loop m = 1 to records(self.typeSets)
    get(self.typeSets, m)
    pOut.append('  TYPESET ' & clip(self.typeSets.name) & ' =' & clip(self.typeSets.members) & crlf)
  end
  loop m = 1 to records(self.groups)                    ! S1 selection constructs
    get(self.groups, m)
    line.setValue('  GROUP ' & clip(self.groups.name) & choose(self.groups.isUser = 1, ' (user)', ''))
    if self.groups.choiceName then line.append(', CHOICE(' & clip(self.groups.choiceName) & ')').
    if self.groups.isDefault then line.append(', DEFAULT').
    if self.groups.isOff then line.append(', OFF').
    if self.groups.revOfGrp
      g = self.groups.revOfGrp                          ! reuse g (guard row var) as a scratch row here
      get(self.groups, g)
      line.append(', REVERSE(' & clip(self.groups.name) & ')')
      get(self.groups, m)
    end
    if self.groups.isFinal then line.append(', FINAL'). ! FINAL was in neither dump nor selection table, and it
                                                        !   is the one group attribute that changes WHEN rules run
    line.append('  [' & self.groups.handCount & ' hand + ' & self.groups.autoCount & ' auto')
    if self.groups.dropDup then line.append(', ' & self.groups.dropDup & ' collapsed').
    if self.groups.dropSkip then line.append(', ' & self.groups.dropSkip & ' skipped').
    line.append(choose(self.groups.selected = 1, ' - selected]', ' - unselected]'))
    pOut.append(line.getValue() & crlf)
  end
  loop m = 1 to records(self.styles)
    get(self.styles, m)
    pOut.append('  STYLE ' & clip(self.styles.name) & ' = ' & clip(self.styles.members) & |
                choose(self.styles.isProfile = 1, '  (profile)', '') & crlf)
  end
  if records(self.groups) or records(self.styles)
    self.SelectionTable(pOut) ! resolved selection (file defaults unless Resolve ran)
  end
  pOut.append(crlf & 'Rules: ' & records(self.rules) & crlf)

  loop r = 1 to records(self.rules)
    get(self.rules, r)
    pOut.append(crlf & '#' & self.rules.ruleId)
    case self.rules.kind
    of vr:kindBuiltin
      pOut.append(' BUILTIN ' & clip(self.rules.builtinName))
      if not self.rules.bparmQ &= NULL
        loop t = 1 to records(self.rules.bparmQ)
          get(self.rules.bparmQ, t)
          pOut.append('  ' & clip(self.rules.bparmQ.name))
          if not self.rules.bparmQ.value &= NULL
            pOut.append('=(' & self.rules.bparmQ.value & ')')
          end
        end
      end
      pOut.append(crlf)
    of vr:kindRule
      pOut.append(' RULE')
      if self.rules.skip then pOut.append(' SKIP').
      if self.rules.once then pOut.append(' ONCE').
      if self.rules.exprEnd then pOut.append(' EXPREND').
      if self.rules.inParens then pOut.append(' INPARENS').
      if self.rules.isDelete then pOut.append(' DELETE').
      if self.rules.isComment then pOut.append(' COMMENT').
      if self.rules.groupId    ! group membership + auto-reverse provenance
        g = self.rules.groupId ! (g reused as a scratch row; re-fetched per guard below)
        get(self.groups, g)
        if ~errorcode() then pOut.append('  [group ' & clip(self.groups.name) & ']').
      end
      if self.rules.revOf then pOut.append('  [auto-reverse of rule ' & self.rules.ruleId - vr:revBase & ']').
      pOut.append(crlf)

      pOut.append('  pat:')
      self.workQ &= self.rules.patQ
      do DumpParts
      pOut.append(crlf)

      pOut.append('  rep:')
      if self.rules.isDelete
        pOut.append(' <<DELETE>')
      elsif self.rules.isComment
        pOut.append(' <<COMMENT>')
      else
        self.workQ &= self.rules.repQ
        do DumpParts
      end
      pOut.append(crlf)

      if not self.rules.guardQ &= NULL ! one line per WHERE clause (ANDed)
        loop g = 1 to records(self.rules.guardQ)
          get(self.rules.guardQ, g)
          if self.rules.guardQ.kind = vr:guardClassTest
            get(self.metaVars, self.rules.guardQ.mvx)
            pOut.append('  where: ' & choose(self.rules.guardQ.ct, 'isConst', 'isLiteral', 'isVar', 'isSimple', 'isPure', |
                        'isCaseNeutral', 'isCallFree', 'isBoolExpr')                                                    & |                          ! five names for SIX vr:ct values. CHOOSE returns
                        '(' & clip(self.metaVars.name) & ')' & crlf) !   its LAST expression when the index is out of range, so
                                                                     !   vr:ctCaseNeutral (6) printed as 'isPure' - and rules 891
                                                                     !   and 892 of the shipped file use isCaseNeutral. The IR dump
                                                                     !   is what a human reads to check what a rule MEANS.
          elsif self.rules.guardQ.kind = vr:guardCompare
            get(self.metaVars, self.rules.guardQ.mvx)
            line.free()
            if self.rules.guardQ.func = vr:gfFold  then line.append('fold(').
            if self.rules.guardQ.func = vr:gfLen   then line.append('len(').
            line.append(clip(self.metaVars.name))
            if self.rules.guardQ.func then line.append(')').
            line.append(choose(self.rules.guardQ.op = vr:opEq, ' = ', ' <<> '))
            if self.rules.guardQ.func = vr:gfLen                     ! len: bare integer, unquoted
              if not self.rules.guardQ.val &= NULL then line.append(self.rules.guardQ.val).
            else
              line.append('''')
              if not self.rules.guardQ.val &= NULL then line.append(self.rules.guardQ.val).
              line.append('''')
            end
            pOut.append('  where: ' & line.getValue() & crlf)
          end
        end
      end

      if not self.rules.noteQ &= NULL and records(self.rules.noteQ)
        pOut.append('  note: ')
        loop t = 1 to records(self.rules.noteQ)
          get(self.rules.noteQ, t)
          if t > 1 then pOut.append(' & ').
          if self.rules.noteQ.mvx
            get(self.metaVars, self.rules.noteQ.mvx)
            ! print the charname() wrapper when the segment carries it. Without this the
            ! dump showed two different NOTEs - `NOTE(mv)` and `NOTE(charname(mv))` - as the
            ! same line, and the IR dump exists to be compared against the rule file.
            if self.rules.noteQ.func = vr:nfCharName
              pOut.append('charname(<<' & clip(self.metaVars.name) & '>)')
            else
              pOut.append('<<' & clip(self.metaVars.name) & '>')
            end
          else
            pOut.append('''' & self.rules.noteQ.txt & '''')
          end
        end
        pOut.append(crlf)
      end
    end
  end

  pOut.append(crlf & 'Issues: ' & self.ErrorCount() & ' error(s), ' & self.WarnCount() & ' warning(s)' & crlf)
  loop r = 1 to records(self.issues)
    get(self.issues, r)
    pOut.append('  line ' & self.issues.lineNo & ' ' & choose(self.issues.sev = vr:sevError, 'ERROR', 'WARN ') & |
                ' ' & clip(self.issues.msg) & crlf)
  end
  self.workQ &= NULL
  return

DumpParts routine
  if self.workQ &= NULL
    pOut.append(' <<none>')
    exit
  end
  loop t = 1 to records(self.workQ)
    get(self.workQ, t)
    if self.workQ.mvx
      get(self.metaVars, self.workQ.mvx)
      pOut.append(' <<' & clip(self.metaVars.name) & ':' & clip(self.KindName(self.metaVars.kind)) & '>')
      if not self.workQ.mvTail &= NULL then pOut.append('.' & clip(self.workQ.mvTail)).   ! dotted occurrence
    else
      pOut.append(' ' & self.workQ.tok)
    end
  end

! ------------------------------------------------------------------------------------
VitRules.ErrorCount Procedure()
x   long,auto
n   long
  code
  loop x = 1 to records(self.issues)
    get(self.issues, x)
    if self.issues.sev = vr:sevError then n += 1.
  end
  return n

! ------------------------------------------------------------------------------------
VitRules.WarnCount Procedure()
x   long,auto
n   long
  code
  loop x = 1 to records(self.issues)
    get(self.issues, x)
    if self.issues.sev = vr:sevWarn then n += 1.
  end
  return n

! ------------------------------------------------------------------------------------
VitRules.AddIssue Procedure(LONG pLine, BYTE pSev, STRING pMsg)
  code
  clear(self.issues)
  self.issues.lineNo = pLine
  self.issues.sev    = pSev
  self.issues.msg    = pMsg
  add(self.issues)

! ------------------------------------------------------------------------------------
VitRules.FindMetaVar Procedure(STRING pName)
x   long,auto
  code
  loop x = 1 to records(self.metaVars)
    get(self.metaVars, x)
    if upper(self.metaVars.name) = upper(pName) then return x.
  end
  return 0

! ------------------------------------------------------------------------------------
! Count of quote bytes in pSt. Escape-blind ON PURPOSE: a doubled '' contributes 2, so
! callers test PARITY - an odd count proves an unterminated quote somewhere, with no
! need to walk the escape grammar.
! ------------------------------------------------------------------------------------
VitRules.QuoteCount Procedure(StringTheory pSt)
x  long,auto
n  long
  code
  loop x = 1 to pSt._DataEnd
    if pSt.valuePtr[x] = '''' then n += 1.
  end
  return n

! ------------------------------------------------------------------------------------
VitRules.PosOutsideQuotes Procedure(StringTheory pSt, STRING pNeedle, LONG pStart=1)
x    long,auto
nl   long,auto
inQ  long
  code
  nl = size(pNeedle)
  if ~nl or pSt._DataEnd < nl then return 0.
  loop x = pStart to pSt._DataEnd - nl + 1
    if inQ
      if pSt.valuePtr[x] = '''' then inQ = 0.
    elsif pSt.valuePtr[x] = ''''
      inQ = 1
    elsif pSt.valuePtr[x : x+nl-1] = pNeedle
      return x
    end
  end
  return 0

! ------------------------------------------------------------------------------------
VitRules.FindOptionStart Procedure(StringTheory pSt)
! find first whole-word WHERE / NOTE / ONCE / SKIP / EXPREND / INPARENS at bracket depth 0, outside quotes
x       long,auto
depth   long
inQ     long
wStart  long,auto
word    StringTheory
prevCh  string(1),auto
  code
  x = 1
  prevCh = ' '
  loop while x <= pSt._DataEnd
    if inQ
      if pSt.valuePtr[x] = '''' then inQ = 0.
      prevCh = pSt.valuePtr[x]
      x += 1
      cycle
    end
    case val(pSt.valuePtr[x])
    of 39 ! <single quote>
      inQ = 1
      prevCh = ''''
      x += 1
      cycle
    of 40 ! '('
      depth += 1
      prevCh = '('
      x += 1
      cycle
    of 41 ! ')'
      depth -= 1
      prevCh = ')'
      x += 1
      cycle
    of 91 ! '['                       ! a bracket subscript nests like parens: an option word
      depth += 1                      !   inside q.buf[i, skip] is a FIELD, not an option
      prevCh = '['
      x += 1
      cycle
    of 93 ! ']'
      depth -= 1
      prevCh = ']'
      x += 1
      cycle
    end
    ! a word glued to '.' (member access, e.g. rec.Note) or ':' (prefix, e.g. PRE:Skip)
    ! is part of a qualified name, NOT a trailing option keyword - exclude those boundaries.
    if ~depth and ~self.IsLabelChar(prevCh) and prevCh <> '.' and prevCh <> ':' and self.IsLabelChar(pSt.valuePtr[x])
      wStart = x
      loop while x <= pSt._DataEnd and self.IsLabelChar(pSt.valuePtr[x])
        x += 1
      end
      word.setValue(pSt.valuePtr[wStart : x-1])
      word.upper()
      case word.getValue()
      of 'WHERE' orof 'NOTE' orof 'ONCE' orof 'SKIP' orof 'EXPREND' orof 'INPARENS'
        return wStart
      end
      prevCh = pSt.valuePtr[x-1]
      cycle
    end
    prevCh = pSt.valuePtr[x]
    x += 1
  end
  return 0

! ------------------------------------------------------------------------------------
VitRules.MatchingParen Procedure(StringTheory pSt, LONG pOpenPos)
x      long,auto
depth  long,auto
inQ    long
  code
  if pOpenPos > pSt._DataEnd or pSt.valuePtr[pOpenPos] <> '(' then return 0.
  depth = 0
  loop x = pOpenPos to pSt._DataEnd
    if inQ
      if pSt.valuePtr[x] = '''' then inQ = 0.
      cycle
    end
    case val(pSt.valuePtr[x])
    of 39 ! <single quote>
      inQ = 1
    of 40 ! '('
      depth += 1
    of 41 ! ')'
      depth -= 1
      if ~depth then return x.
    end
  end
  return 0

! ------------------------------------------------------------------------------------
VitRules.IsLabelToken Procedure(STRING pTok)
! true if pTok consists only of label characters (A-Z a-z 0-9 _ :) and starts with a letter or _
x    long,auto
c    long,auto
tLen long,auto
  code
  tLen = len(clip(pTok))
  if ~tLen then return false.
  loop x = 1 to tLen
    c = val(pTok[x])
    case c
    of   65 to 90                 ! A-Z
    orof 97 to 122                ! a-z
    orof 95                       ! _
    of   48 to 57                 ! 0-9
    orof 58                       ! :
      if x = 1 then return false. ! must not start with digit or colon
    else
      return false
    end
  end
  return true

! ------------------------------------------------------------------------------------
VitRules.OneCharDiff Procedure(STRING pA, STRING pB)
! true if the (clipped) strings differ by exactly one substitution, insertion, or deletion
aLen  long,auto
bLen  long,auto
x     long,auto
y     long,auto ! the earlier AutoCheck missed the compound  x = 1; y = 1  write - restored
diffs long
  code
  aLen = len(clip(pA))
  bLen = len(clip(pB))
  if ~aLen or ~bLen or |
     pA = pB    ! identical is not a near-miss
    return false
  end

  if aLen = bLen
    loop x = 1 to aLen
      if pA[x] <> pB[x] then diffs += 1.
      if diffs > 1 then return false.
    end
    return choose(diffs = 1)
  end

  if abs(aLen - bLen) <> 1 then return false.
  ! one insertion/deletion: walk both, allow a single skip on the longer string
  if aLen > bLen
    x = 1; y = 1
    loop while y <= bLen
      if pA[x] = pB[y]
        x += 1; y += 1
      else
        diffs += 1
        if diffs > 1 then return false.
        x += 1 ! skip one char of the longer string
      end
    end
    return true
  else
    x = 1; y = 1
    loop while x <= aLen
      if pA[x] = pB[y]
        x += 1; y += 1
      else
        diffs += 1
        if diffs > 1 then return false.
        y += 1
      end
    end
    return true
  end

! ------------------------------------------------------------------------------------
VitRules.KindName Procedure(BYTE pKind)
  code
  case pKind
  of vr:mvTyped   ; return 'TYPE'
  of vr:mvClass   ; return 'CLASS'
  of vr:mvExpr    ; return 'EXPR'
  of vr:mvArgs    ; return 'ARGS'
  of vr:mvLiteral ; return 'LITERAL'
  of vr:mvConst   ; return 'CONST'
  of vr:mvAnyVar  ; return 'ANYVAR'
  of vr:mvTypeSet ; return 'TYPESET'
  end
  return '?'

! ------------------------------------------------------------------------------------
! TYPESET NAME = MEMBER + MEMBER + ...
! Declares a named class of scalar types so one typed rule can cover them all, e.g.
!   TYPESET INT = BYTE + LONG + ULONG + SHORT + USHORT + INT64 + UINT64
!   TYPESET NUM = INT + DECIMAL + PDECIMAL + REAL + SREAL + BFLOAT4 + BFLOAT8 + SIGNED + UNSIGNED
!   TYPESET STR = STRING + CSTRING + PSTRING
! A member may be a scalar type keyword OR a previously-declared set (composition -
! expanded HERE at parse time, so the matcher only ever does one membership test).
! Unknown member words are kept (future Clarion types) but warned about (typo guard).
! ------------------------------------------------------------------------------------
VitRules.ParseTypeSetLine Procedure(StringTheory pLine, LONG pLineNo)
work      StringTheory
work2     StringTheory
word2     STRING(vr:maxName),AUTO
z2        long,auto
name      STRING(vr:maxName),AUTO
members   STRING(512),AUTO
word      STRING(vr:maxName),AUTO
eqPos     long,auto
z         long,auto
tsx       long,auto
count     long,auto
  code
  work.setValue(pLine)
  work.RemoveFromPosition(1,8) ! text after 'TYPESET '
  eqPos = work.findByte(61)    ! '='
  if ~eqPos
    self.AddIssue(pLineNo, vr:sevError, 'TYPESET needs NAME = member + member: ' & pLine.getValue())
    return
  end
  name = left(work.sub(1, eqPos - 1))
  if ~name or ~self.IsLabelToken(name)
    self.AddIssue(pLineNo, vr:sevError, 'TYPESET has no valid name: ' & pLine.getValue())
    return
  end
  ! the name must not shadow anything the METAVARS type position already means
  if instring(' ' & upper(clip(name)) & ' ', mvBuiltinTypes, 1, 1) |
     or upper(name) = 'EXPR' or upper(name) = 'ARGS' or upper(name) = 'LITERAL' or upper(name) = 'CONST' or upper(name) = 'ANYVAR'
    self.AddIssue(pLineNo, vr:sevError, 'TYPESET name collides with a built-in type/kind: ' & clip(name))
    return
  end
  if self.FindTypeSet(name)
    self.AddIssue(pLineNo, vr:sevError, 'duplicate TYPESET name: ' & clip(name))
    return
  end

  work.RemoveFromPosition(1,eqPos)          ! member list text
  work.replaceByte(43, 32)                  ! replace all '+' with <space>
  work.split(' ')
  members = ''
  count = 0
  loop z = 1 to work.records()
    word = upper(work.getLine(z))
    if ~word then cycle.
    tsx = self.FindTypeSet(word)
    if tsx                                  ! composition: flatten a previously-declared set
      get(self.typeSets, tsx)
      work2.setValue(self.typeSets.members) ! dedupe each included member - blind concat amplifies duplicates toward the size cap
      work2.split(' ')
      loop z2 = 1 to work2.records()
        word2 = upper(work2.getLine(z2))
        if ~word2 or |
           instring(' ' & clip(word2) & ' ', ' ' & clip(members) & ' ', 1, 1)
          cycle
        end
        if len(clip(members)) + len(clip(word2)) + 2 > size(members)
          self.AddIssue(pLineNo, vr:sevError, 'TYPESET ' & clip(name) & ' member list exceeds ' & size(members) & ' characters')
          return
        end
        members = clip(members) & ' ' & word2
      end
      count += 1
      cycle
    end
    if ~instring(' ' & clip(word) & ' ', mvBuiltinTypes, 1, 1)
      self.AddIssue(pLineNo, vr:sevWarn, 'TYPESET ' & clip(name) & ': member ' & clip(word) & ' is not a known Clarion scalar type (kept - check the spelling)')
    end
    if instring(' ' & clip(word) & ' ', ' ' & clip(members) & ' ', 1, 1) then cycle. ! dedupe
    if len(clip(members)) + len(clip(word)) + 2 > size(members)                      ! refuse silent truncation - it drops members mid-word AND can lose the trailing sentinel space
      self.AddIssue(pLineNo, vr:sevError, 'TYPESET ' & clip(name) & ' member list exceeds ' & size(members) & ' characters')
      return
    end
    members = clip(members) & ' ' & word
    count += 1
  end
  if ~count
    self.AddIssue(pLineNo, vr:sevError, 'TYPESET ' & clip(name) & ' has no members')
    return
  end
  clear(self.typeSets)
  self.typeSets.name     = name
  self.typeSets.members  = clip(members) & ' ' ! space-wrapped for the membership instring
  self.typeSets.declLine = pLineNo
  add(self.typeSets)

! ------------------------------------------------------------------------------------
! typeSets row whose name caselessly equals pName; 0 = no such set.
! ------------------------------------------------------------------------------------
VitRules.FindTypeSet Procedure(STRING pName)
z  long,auto
  code
  if self.typeSets &= NULL then return 0.
  loop z = 1 to records(self.typeSets)
    get(self.typeSets, z)
    if upper(self.typeSets.name) = upper(pName) then return z.
  end
  return 0

! ------------------------------------------------------------------------------------
! character-class test for the per-character word scans (options, guards, BUILTIN
! params). Letters, digits, '_' and ':' are label characters. NB IsLabelToken on a
! SINGLE character rejects a digit ("must not start with a digit"), which silently made
! digits word boundaries - 'flag1skip' parsed as 'flag1' + SKIP, 'WHERE e2' as metavar e.
! ------------------------------------------------------------------------------------
VitRules.IsLabelChar Procedure(STRING pCh)
  code
  case val(pCh[1])
  of   65 to 90  ! A-Z
  orof 97 to 122 ! a-z
  orof 48 to 57  ! 0-9
  orof 95        ! _
  orof 58        ! :
    return true
  end
  return false

! ====================================================================================
! GROUP / CHOICE / STYLE selection + REVERSE auto-derivation.
! Design: clarion-transformer-selection-design-v02.md. There is exactly ONE resolver
! (Resolve) and it lives here, engine-side - the CLI, the golden runner and (later)
! VitStyle all call it, so preview-vs-real divergence is impossible by construction.
! ------------------------------------------------------------------------------------
VitRules.IsGroupName Procedure(STRING pName)
x   long,auto
n   long,auto
  code
  n = len(clip(pName))
  if ~n or n > vr:maxName then return false.
  if ~inrange(val(upper(pName[1])), 65, 90) then return false. ! must start with a letter
  loop x = 2 to n
    if ~self.IsLabelChar(pName[x]) and pName[x] <> '-' then return false.
  end
  return true

! ------------------------------------------------------------------------------------
VitRules.FindGroup Procedure(STRING pName)
g      long,auto
nameU  STRING(vr:maxName),AUTO
  code
  nameU = upper(left(pName))
  loop g = 1 to records(self.groups)
    get(self.groups, g)
    if upper(self.groups.name) = nameU then return g.
  end
  return 0

! ------------------------------------------------------------------------------------
! LAST match wins so a user profile loaded after the rule file overrides a shipped
! style of the same name - design 5c.
! ------------------------------------------------------------------------------------
VitRules.FindStyle Procedure(STRING pName)
s      long,auto
nameU  STRING(vr:maxName),AUTO
  code
  nameU = upper(left(pName))
  if nameU = 'OPTIMIZE' or nameU = 'OPTIMIZED' or nameU = 'OPTIMISE' then nameU = 'OPTIMISED'. ! silently accept the US spelling - also the style is optimisED, so we add 'D' if needed
  loop s = records(self.styles) to 1 by -1
    get(self.styles, s)
    if upper(self.styles.name) = nameU then return s.
  end
  return 0

! ------------------------------------------------------------------------------------
! GROUP <name>[, CHOICE(<axis>)][, DEFAULT][, OFF][, REVERSE(<group>)]
! Members follow until ENDGROUP / the next GROUP / a STYLE line / EOF. The group's
! default selection is seeded HERE so every consumer sees correct file defaults even
! when Resolve is never called.
! ------------------------------------------------------------------------------------
VitRules.ParseGroupLine Procedure(StringTheory pLine, LONG pLineNo)
parts    StringTheory
piece    StringTheory
up       StringTheory
z        long,auto
g2       long,auto
gName    STRING(vr:maxName)
gChoice  STRING(vr:maxName)
gDefault BYTE
gOff     BYTE
gFinal   BYTE
gRev     long
  code
  parts.setValue(pLine.valuePtr[7 : pLine._DataEnd]) ! after 'GROUP '
  parts.split(',')                                   ! names and single-arg attrs never contain commas
  loop z = 1 to parts.records()
    piece.setValue(parts.getLine(z))
    piece.trim()
    if ~piece._DataEnd then cycle.
    up.setValue(piece)
    up.upper()
    if z = 1
      if ~self.IsGroupName(piece.getValue())
        self.AddIssue(pLineNo, vr:sevError, 'GROUP name must start with a letter and use letters/digits/_/:/- only: ' & piece.getValue())
        return
      end
      if self.FindGroup(piece.getValue())
        self.AddIssue(pLineNo, vr:sevError, 'duplicate GROUP name: ' & piece.getValue())
        return
      end
      gName = piece.getValue()
    elsif up._DataEnd > 8 and up.valuePtr[1 : 7] = 'CHOICE(' and up.valuePtr[up._DataEnd] = ')'
      gChoice = left(piece.valuePtr[8 : piece._DataEnd - 1])
      if ~self.IsGroupName(gChoice)
        self.AddIssue(pLineNo, vr:sevError, 'CHOICE name must start with a letter and use letters/digits/_/:/- only: ' & clip(gChoice))
        return
      end
    elsif up._DataEnd = 7 and up.valuePtr[1 : 7] = 'DEFAULT'
      gDefault = true
    elsif up._DataEnd = 3 and up.valuePtr[1 : 3] = 'OFF'
      gOff = true
    elsif up._DataEnd = 5 and up.valuePtr[1 : 5] = 'FINAL' ! deferred - see GroupQType.isFinal
      gFinal = true
    elsif up._DataEnd > 9 and up.valuePtr[1 : 8] = 'REVERSE(' and up.valuePtr[up._DataEnd] = ')'
      gRev = self.FindGroup(left(piece.valuePtr[9 : piece._DataEnd - 1]))
      if ~gRev
        self.AddIssue(pLineNo, vr:sevError, 'REVERSE(' & left(piece.valuePtr[9 : piece._DataEnd - 1]) & '): group not found - the reversed group must be declared EARLIER in the file')
        return
      end
    else
      self.AddIssue(pLineNo, vr:sevError, 'unknown GROUP attribute (expected CHOICE(x) / DEFAULT / OFF / FINAL / REVERSE(g)): ' & piece.getValue())
      return
    end
  end
  if ~gName
    self.AddIssue(pLineNo, vr:sevError, 'GROUP needs a name')
    return
  end

  ! ---- attribute consistency ----
  if gDefault and gOff
    self.AddIssue(pLineNo, vr:sevError, 'GROUP ' & clip(gName) & ': DEFAULT and OFF are contradictory')
    return
  end
  if gOff and gChoice
    self.AddIssue(pLineNo, vr:sevWarn, 'GROUP ' & clip(gName) & ': OFF is meaningless on a CHOICE member (unselected unless DEFAULT or picked) - ignored')
    gOff = false
  end
  if gDefault and ~gChoice
    if self.inUserLoad    ! user groups are opt-in - DEFAULT cannot turn one on
      self.AddIssue(pLineNo, vr:sevWarn, 'GROUP ' & clip(gName) & ': DEFAULT on a standalone user group is ignored - user groups are opt-in (select via a profile or --group=)')
    else
      self.AddIssue(pLineNo, vr:sevWarn, 'GROUP ' & clip(gName) & ': DEFAULT on a standalone group is redundant (standalone groups default ON)')
    end
  end
  if gChoice and gDefault ! DEFAULT uniqueness per choice
    loop g2 = 1 to records(self.groups)
      get(self.groups, g2)
      if self.groups.isDefault and upper(self.groups.choiceName) = upper(gChoice)
        self.AddIssue(pLineNo, vr:sevError, 'choice ' & clip(gChoice) & ' already has DEFAULT member ' & clip(self.groups.name))
        return
      end
    end
  end
  if gRev                 ! anti-ping-pong: a REVERSE pair must share one CHOICE
    get(self.groups, gRev)
    if ~gChoice or upper(self.groups.choiceName) <> upper(gChoice)
      self.AddIssue(pLineNo, vr:sevError, 'GROUP ' & clip(gName) & ': REVERSE(' & clip(self.groups.name) & ') requires BOTH groups in the same CHOICE - mutual exclusion is what makes reversal safe')
      return
    end
  end

  clear(self.groups)
  self.groups.name       = gName
  self.groups.choiceName = gChoice
  self.groups.isDefault  = gDefault
  self.groups.isOff      = gOff
  self.groups.isFinal    = gFinal                                                          ! deferred to after convergence
  self.groups.revOfGrp   = gRev
  self.groups.declLine   = pLineNo
  self.groups.isUser     = self.inUserLoad                                                 ! origin marker - SelectionTable/IR show (user)
  if self.inUserLoad and ~gChoice                                                          ! standalone user groups are OPT-IN (like
    self.groups.isOff = 1                                                                  !   cosmetics) - off unless a profile or --group=
  end                                                                                      !   picks them; isOff persists through Resolve layer 0
  self.groups.selected   = choose(gChoice <> '', gDefault, choose(self.groups.isOff <> 1)) ! file-default seed
  add(self.groups)
  self.curGroup = records(self.groups)

! ------------------------------------------------------------------------------------
! STYLE <name> = <group>[, <group>]...   One syntax for shipped styles and saved
! profiles (pIsProfile marks the source). Member names resolve at Lint/Resolve time,
! never line numbers, so styles survive rule-file edits.
! ------------------------------------------------------------------------------------
VitRules.ParseStyleLine Procedure(StringTheory pLine, LONG pLineNo, BYTE pIsProfile)
eqPos  long,auto
s      long,auto
nm     StringTheory
mem    StringTheory
  code
  eqPos = self.PosOutsideQuotes(pLine, '=')
  if ~eqPos or eqPos <= 7
    self.AddIssue(pLineNo, vr:sevError, 'STYLE needs: STYLE <<name> = <<group>[, <<group>]...: ' & pLine.getValue())
    return
  end
  nm.setValue(pLine.valuePtr[7 : eqPos - 1])
  nm.trim()
  if ~self.IsGroupName(nm.getValue())
    self.AddIssue(pLineNo, vr:sevError, 'STYLE name must start with a letter and use letters/digits/_/:/- only: ' & nm.getValue())
    return
  end
  s = self.FindStyle(nm.getValue())
  if s
    get(self.styles, s)
    if self.styles.isProfile = pIsProfile
      self.AddIssue(pLineNo, vr:sevError, 'duplicate STYLE name: ' & nm.getValue())
      return
    elsif pIsProfile
      self.AddIssue(pLineNo, vr:sevWarn, 'profile ' & nm.getValue() & ' overrides a shipped style of the same name')
    end
  end
  if eqPos >= pLine._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'STYLE ' & nm.getValue() & ' has no members')
    return
  end
  mem.setValue(pLine.valuePtr[eqPos + 1 : pLine._DataEnd])
  mem.trim()
  if ~mem._DataEnd
    self.AddIssue(pLineNo, vr:sevError, 'STYLE ' & nm.getValue() & ' has no members')
    return
  end
  if mem._DataEnd > size(self.styles.members)
    self.AddIssue(pLineNo, vr:sevError, 'STYLE ' & nm.getValue() & ' member list is longer than ' & size(self.styles.members) & ' characters - split it or shorten group names')
    return
  end
  clear(self.styles)
  self.styles.name      = nm.getValue()
  self.styles.members   = mem.getValue()
  self.styles.declLine  = pLineNo
  self.styles.isProfile = pIsProfile
  add(self.styles)

! ------------------------------------------------------------------------------------
! Close the open group: count its authored members, then run REVERSE expansion.
! Expansion happens BEFORE curGroup clears so the generated rules are tagged with the
! group by the normal ParseRuleLine path. Safe to call when no group is open.
! ------------------------------------------------------------------------------------
VitRules.CloseGroup Procedure(LONG pLineNo)
g    long,auto
r    long,auto
n    long
  code
  if ~self.curGroup then return.
  g = self.curGroup
  loop r = 1 to records(self.rules)
    get(self.rules, r)
    if self.rules.groupId = g then n += 1.
  end
  get(self.groups, g)
  self.groups.handCount = n
  put(self.groups)
  if self.groups.revOfGrp then self.ExpandReverse(g, pLineNo).
  self.curGroup = 0

! ------------------------------------------------------------------------------------
! REVERSE(source): for every rule of the source group, synthesise the swapped rule
! (replacement ==> pattern, trailing options carried verbatim) and parse it through
! the NORMAL rule path, so reversed rules are ordinary IR everywhere downstream.
! Rules added to the source group flow through automatically.
!   Not auto-reversible (WARNed, dropSkip): BUILTIN members, DELETE rules,
!     multi-statement patterns (the ';' semantics do not mirror), and rules whose
!     replacement/WHERE/NOTE would use a metavar the new pattern cannot bind.
!   Dropped silently (dropDup): a reversed pattern already claimed in this group -
!     covers BOTH the hand-override contract (a hand rule in the REVERSE group body
!     replaces its auto twin) and many-to-one families collapsing to the first
!     spelling in file order. Counters land in the IR dump GROUP line.
! Generated ruleId = vr:revBase + source ruleId - distinct for ONCE / --only / logs.
! ------------------------------------------------------------------------------------
VitRules.ExpandReverse Procedure(LONG pGrpRow, LONG pLineNo)
srcGrp   long,auto
r        long,auto
c        long,auto
n0       long,auto
n1       long,auto
newRow   long,auto
srcId    long,auto
sepPos   long,auto
optPos   long,auto
bad      long,auto
t        long,auto
nAuto    long
nDup     long
nSkip    long
srcTxt   StringTheory
patTxt   StringTheory
repTxt   StringTheory
optTxt   StringTheory
synth    StringTheory
newPatN  StringTheory
candN    StringTheory
patSet   STRING(1),DIM(500)
  code
  get(self.groups, pGrpRow)
  srcGrp = self.groups.revOfGrp
  n0 = records(self.rules)
  loop r = 1 to n0
    get(self.rules, r)
    if self.rules.groupId <> srcGrp then cycle.
    srcId = self.rules.ruleId
    if self.rules.kind = vr:kindBuiltin
      self.AddIssue(pLineNo, vr:sevWarn, 'REVERSE: BUILTIN ' & clip(self.rules.builtinName) & ' (line ' & srcId & ') is not reversible - skipped')
      nSkip += 1
      cycle
    end
    if self.rules.isDelete
      self.AddIssue(pLineNo, vr:sevWarn, 'REVERSE: rule ' & srcId & ' DELETEs its pattern - not reversible, skipped')
      nSkip += 1
      cycle
    end
    if self.rules.isComment                                        !
      self.AddIssue(pLineNo, vr:sevWarn, 'REVERSE: rule ' & srcId & ' COMMENTs its pattern out - not reversible, skipped')
      nSkip += 1
      cycle
    end
    if self.rules.srcText &= NULL then nSkip += 1 ; cycle.
    srcTxt.setValue(self.rules.srcText)
    sepPos = self.PosOutsideQuotes(srcTxt, '==>')
    if ~sepPos then nSkip += 1 ; cycle.
    patTxt.setValue(srcTxt.valuePtr[1 : sepPos - 1])
    patTxt.trim()
    repTxt.setValue(srcTxt.valuePtr[sepPos + 3 : srcTxt._DataEnd])
    repTxt.trim()
    optPos = self.FindOptionStart(repTxt)
    if optPos
      optTxt.setValue(repTxt.valuePtr[optPos : repTxt._DataEnd])
      repTxt.setLength(optPos - 1)
      repTxt.trim()
    else
      optTxt.free()
    end
    if self.PosOutsideQuotes(patTxt, ';') or self.PosOutsideQuotes(repTxt, ';')
      self.AddIssue(pLineNo, vr:sevWarn, 'REVERSE: rule ' & srcId & ' is a multi-statement pattern - '';'' does not mirror, skipped (write the reverse by hand)')
      nSkip += 1
      cycle
    end

    ! the generated pattern carries a trailing ';' END-OF-STATEMENT ASSERTION.
    ! Without it a reversed bare form PREFIX-MATCHES longer expressions and corrupts
    ! them: reverse of `if sc <> '' ==> if sc` is `if sc`, which would match the
    ! front of `if s = 'abc'` and emit `if s <> '' = 'abc'`. With the assertion the
    ! real sites (statement/condition ends right after) still fire and every longer
    ! expression refuses. Accepted known-miss (same class as the len(clip()) bare
    ! forms): a mid-condition term followed by and/or fails the assertion. NB a hand
    ! rule that wants to OVERRIDE an auto twin must spell the same trailing ';' or
    ! the normalized patterns will not collide.
    synth.setValue(repTxt)
    synth.append(' ;  ==>  ')
    synth.append(patTxt)
    if optTxt._DataEnd
      synth.append('   ')
      synth.append(optTxt)
    end
    n1 = records(self.rules)
    self.ParseRuleLine(synth, vr:revBase + srcId)
    if records(self.rules) = n1 then nSkip += 1 ; cycle. ! parse refused (issue already logged)
    newRow = records(self.rules)
    get(self.rules, newRow)
    self.rules.revOf = r
    put(self.rules)

    ! every metavar the new replacement / WHERE / NOTE uses must bind in the new pattern
    clear(patSet)
    bad = 0
    self.workQ &= self.rules.patQ
    if not self.workQ &= NULL
      loop t = 1 to records(self.workQ)
        get(self.workQ, t)
        if self.workQ.mvx and self.workQ.mvx <= 500 and self.workQ.mvTail &= NULL
          patSet[self.workQ.mvx] = '1'
        end
      end
    end
    self.workQ &= self.rules.repQ
    if not self.workQ &= NULL
      loop t = 1 to records(self.workQ)
        get(self.workQ, t)
        if self.workQ.mvx
          if self.workQ.mvx > 500 or patSet[self.workQ.mvx] <> '1' then bad = 1.
        end
      end
    end
    if not self.rules.guardQ &= NULL
      loop t = 1 to records(self.rules.guardQ)
        get(self.rules.guardQ, t)
        if self.rules.guardQ.mvx
          if self.rules.guardQ.mvx > 500 or patSet[self.rules.guardQ.mvx] <> '1' then bad = 1.
        end
      end
    end
    if not self.rules.noteQ &= NULL
      loop t = 1 to records(self.rules.noteQ)
        get(self.rules.noteQ, t)
        if self.rules.noteQ.mvx
          if self.rules.noteQ.mvx > 500 or patSet[self.rules.noteQ.mvx] <> '1' then bad = 1.
        end
      end
    end
    if bad
      get(self.rules, newRow)
      self.FreeRuleRow()
      self.AddIssue(pLineNo, vr:sevWarn, 'REVERSE: rule ' & srcId & ' uses a metavar only in its replacement - cannot auto-reverse (write the reverse by hand)')
      nSkip += 1
      cycle
    end

    ! duplicate pattern inside this group: hand override / many-to-one collapse
    get(self.rules, newRow)
    self.workQ &= self.rules.patQ
    self.NormalizeParts(newPatN)
    bad = 0
    loop c = 1 to newRow - 1
      get(self.rules, c)
      if self.rules.groupId <> pGrpRow or |
         self.rules.kind <> vr:kindRule
        cycle
      end
      self.workQ &= self.rules.patQ
      self.NormalizeParts(candN)
      if choose(candN._DataEnd < 1, '', candN.valuePtr[1 : candN._DataEnd]) = newPatN.getValue() then bad = 1 ; break.
    end
    if bad
      get(self.rules, newRow)
      self.FreeRuleRow()
      nDup += 1
      cycle
    end
    nAuto += 1
  end
  self.workQ &= NULL
  get(self.groups, pGrpRow)
  self.groups.autoCount = nAuto
  self.groups.dropDup   = nDup
  self.groups.dropSkip  = nSkip
  put(self.groups)

! ------------------------------------------------------------------------------------
! Dispose the CURRENT rules-buffer row's heap parts and delete it - the per-row block
! of FreeAll for one row. Caller must have get()'d the row first.
! ------------------------------------------------------------------------------------
VitRules.FreeRuleRow Procedure()
y   long,auto
  code
  self.workQ &= self.rules.patQ
  self.FreePartQ()
  self.workQ &= self.rules.repQ
  self.FreePartQ()
  if not self.rules.noteQ &= NULL
    loop y = 1 to records(self.rules.noteQ)
      get(self.rules.noteQ, y)
      dispose(self.rules.noteQ.txt)
    end
    free(self.rules.noteQ)
    dispose(self.rules.noteQ)
  end
  if not self.rules.bparmQ &= NULL
    loop y = 1 to records(self.rules.bparmQ)
      get(self.rules.bparmQ, y)
      dispose(self.rules.bparmQ.value)
    end
    free(self.rules.bparmQ)
    dispose(self.rules.bparmQ)
  end
  dispose(self.rules.srcText)
  dispose(self.rules.repText)
  dispose(self.rules.guardVal)
  if not self.rules.guardQ &= NULL
    loop y = 1 to records(self.rules.guardQ)
      get(self.rules.guardQ, y)
      dispose(self.rules.guardQ.val)
    end
    free(self.rules.guardQ)
    dispose(self.rules.guardQ)
  end
  delete(self.rules)

! ------------------------------------------------------------------------------------
! Canonical text of self.workQ for pattern-identity compares (REVERSE dedup and the
! inverse-pair lint): metavars render as %NAME (dotted tails kept), keyword and
! identifier tokens fold to upper, quoted literals stay verbatim (their case counts).
! ------------------------------------------------------------------------------------
VitRules.NormalizeParts Procedure(StringTheory pOut)
t   long,auto
  code
  pOut.free()
  if self.workQ &= NULL then return.
  loop t = 1 to records(self.workQ)
    get(self.workQ, t)
    if t > 1 then pOut.append(' ').
    if self.workQ.mvx
      get(self.metaVars, self.workQ.mvx)
      pOut.append('%' & upper(clip(self.metaVars.name)))
      if not self.workQ.mvTail &= NULL then pOut.append('.' & upper(clip(self.workQ.mvTail))).
    elsif not self.workQ.tok &= NULL
      if self.workQ.tok[1] = ''''
        pOut.append(clip(self.workQ.tok))
      else
        pOut.append(upper(clip(self.workQ.tok)))
      end
    end
  end

! ------------------------------------------------------------------------------------
! The one active-set test every executor uses (VitEngine.RunPass, VitRewrite.ApplyAll,
! VitMatch.MatchAll). Row 0 = ungrouped = always active. Unknown rows fail OPEN so a
! stale groupId can never silently disable a rule.
! ------------------------------------------------------------------------------------
VitRules.GroupActive Procedure(LONG pGroupRow)
  code
  ! FINAL groups are DEFERRED. The engine runs its fixpoint with deferPhase 0, during
  ! which they are inert, then makes ONE more pass with deferPhase 1, during which ONLY they
  ! run. Both halves live here so a rule cannot leak into the wrong phase, and an UNGROUPED
  ! rule (groupId 0) is by definition never deferred - it has no group to carry the flag.
  if ~pGroupRow then return choose(self.deferPhase <> 1).
  get(self.groups, pGroupRow)
  if errorcode() then return choose(self.deferPhase <> 1).
  if self.deferPhase = 1
    if ~self.groups.isFinal then return 0. ! deferred pass: everything else has had its turn
  else
    if self.groups.isFinal then return 0.  ! fixpoint: its output is unreadable to the analyses
  end
  return self.groups.selected

! ------------------------------------------------------------------------------------
! THE resolver. Layers, in order:
!   0. file defaults - re-seeded on every call, so Resolve is idempotent and
!      Resolve('','','') is exactly the no-switch behaviour
!   1. pStyle: a shipped STYLE or loaded profile, by name (unknown = ERROR)
!   2. pGroups / pNoGroups: comma-separated individual overrides (unknown = WARN,
!      ignored - the graceful-degrade contract of design 5c)
! Selection state lands in groups.selected; SelectionTable prints what resolved.
! ------------------------------------------------------------------------------------
VitRules.Resolve Procedure(STRING pStyle, STRING pGroups, STRING pNoGroups)
g        long,auto
s        long,auto
z        long,auto
errs0    long,auto
sLine    long,auto
sName    STRING(vr:maxName)
styNm    STRING(vr:maxName)                  ! the style ApplyOneStyle is to apply
styWhy   STRING(20)                          ! what to call it if the name is unknown
styOk    LONG                                ! ApplyOneStyle found and applied it
list     StringTheory
nm       StringTheory
knownSty StringTheory                        ! the style names this file declares, for the unknown-name refusal
  code
  errs0 = self.ErrorCount()
  self.appliedStyle = ''
  loop g = 1 to records(self.groups)         ! layer 0: file defaults
    get(self.groups, g)
    if self.groups.choiceName
      self.groups.selected = self.groups.isDefault
    else
      self.groups.selected = choose(self.groups.isOff <> 1)
    end
    put(self.groups)
  end
  self.styleFromDefault = 0
  if self.defaultStyle and ~pStyle           ! layer 0b: DEFAULTSTYLE from the rule file - applied ONLY
    styNm  = self.defaultStyle               !   when no explicit style was asked for. An explicit
    styWhy = 'DEFAULTSTYLE'                  !   --style= REPLACES the default rather than layering over
    do ApplyOneStyle                         !   it: under layering, anything the
    if styOk then self.styleFromDefault = 1. !   default switched on that the chosen style never mentions
  end                                        !   stayed on - fastcompare-negatives leaked into an
                                             !   readable run - so the style you ask for is the style
                                             !   you get. Axes the chosen style does not name still fall
                                             !   back to their per-axis DEFAULT members (layer 0 above).
  if pStyle                                  ! layer 1: style / profile. Bare-string IF is the non-blank
                                             !   test and the compare behind it is trailing-space-blind,
                                             !   so clip() here was the exact redundancy this tool removes
                                             !
    styNm  = pStyle
    styWhy = 'style/profile'
    do ApplyOneStyle
    if styOk then self.styleFromDefault = 0. ! an explicit switch owns the report line
  end
  if pGroups                                 ! layer 2: individual overrides
    list.setValue(pGroups)
    list.split(',')
    loop z = 1 to list.records()
      nm.setValue(list.getLine(z))
      nm.trim()
      if ~nm._DataEnd then cycle.
      self.ApplyPick(nm.getValue(), 0, '--group')
    end
  end
  if pNoGroups
    list.setValue(pNoGroups)
    list.split(',')
    loop z = 1 to list.records()
      nm.setValue(list.getLine(z))
      nm.trim()
      if ~nm._DataEnd then cycle.
      self.ApplyUnpick(nm.getValue(), 0, '--nogroup')
    end
  end
  return self.ErrorCount() - errs0

! ---- apply ONE named style's member list. Shared by the DEFAULTSTYLE layer and the
!      --style= layer so the two can never drift; styWhy names the source in the error. ----
ApplyOneStyle routine
  styOk = 0
  s = self.FindStyle(styNm)
  if ~s
    ! NAME THE VALID SPELLINGS. A refusal that does not name them is one the caller cannot
    ! act on - it just moves the guessing somewhere else - which is why the --group= refusal
    ! in vitTransform.clw lists every group the file declares. A STYLE name needs it more
    ! than a group name does: it is a word rather than an identifier, so it has spellings,
    ! and `optimised` is one that plenty of people will reach for with a z. FindStyle is
    ! caseless but EXACT, so `optimized` matches nothing and this message is the only thing
    ! that can tell them why.
    knownSty.free()
    loop z = 1 to records(self.styles)
      get(self.styles, z)
      if errorcode() then break.
      knownSty.append(choose(~knownSty._DataEnd, '', ', ') & clip(self.styles.name)) ! clip is load-bearing - name is a fixed STRING and append takes the padding
    end
    self.AddIssue(0, vr:sevError, 'unknown ' & clip(styWhy) & ': ' & clip(styNm) & |
                  choose(~knownSty._DataEnd, '', ' - this rule file declares: ' & knownSty.getValue()))
    exit
  end
  styOk = 1
  get(self.styles, s)
  sName = self.styles.name
  sLine = self.styles.declLine
  self.appliedStyle = sName
  list.setValue(self.styles.members)
  list.split(',')
  loop z = 1 to list.records()
    nm.setValue(list.getLine(z))
    nm.trim()
    if ~nm._DataEnd then cycle.
    if nm.valuePtr[1] = '-'                                   ! -name member = DESELECT (choice -> none /
      nm.setValue(nm.valuePtr[2 : nm._DataEnd]) !      standalone off) - how a saved profile expresses
      nm.trim()                                 !      "off" for something the file defaults turn on
      if nm._DataEnd then self.ApplyUnpick(nm.getValue(), sLine, 'style ' & clip(sName)).
    else
      self.ApplyPick(nm.getValue(), sLine, 'style ' & clip(sName))
    end
  end

! ------------------------------------------------------------------------------------
VitRules.ApplyPick Procedure(STRING pName, LONG pLine, STRING pSrc)
g      long,auto
g2     long,auto
chcU   STRING(vr:maxName),AUTO
  code
  g = self.FindGroup(pName)
  if ~g
    self.AddIssue(pLine, vr:sevWarn, 'unknown group ''' & clip(pName) & ''' in ' & clip(pSrc) & ' - ignored')
    return
  end
  get(self.groups, g)
  if self.groups.choiceName
    chcU = upper(self.groups.choiceName)
    loop g2 = 1 to records(self.groups) ! selecting a choice member deselects its siblings
      get(self.groups, g2)
      if upper(self.groups.choiceName) = chcU
        self.groups.selected = choose(g2 = g)
        put(self.groups)
      end
    end
  else
    self.groups.selected = 1
    put(self.groups)
  end

! ------------------------------------------------------------------------------------
VitRules.ApplyUnpick Procedure(STRING pName, LONG pLine, STRING pSrc)
g   long,auto
  code
  g = self.FindGroup(pName)
  if ~g
    self.AddIssue(pLine, vr:sevWarn, 'unknown group ''' & clip(pName) & ''' in ' & clip(pSrc) & ' - ignored')
    return
  end
  get(self.groups, g)
  self.groups.selected = 0 ! for a choice member this means its choice -> none
  put(self.groups)

! ------------------------------------------------------------------------------------
! The resolved-selection table: printed in every transform report
! header and in the IR dump. A report without its selection is an unrepeatable
! experiment - this table is what makes one repeatable.
! ------------------------------------------------------------------------------------
VitRules.SelectionTable Procedure(StringTheory pOut)
g      long,auto
g2     long,auto
r      long,auto
n      long
first  long,auto
chc    STRING(vr:maxName),AUTO
chcU   STRING(vr:maxName),AUTO
win    STRING(vr:maxName),AUTO
winU   BYTE,AUTO ! winning member came from the user rulefile
crlf   EQUATE('<13,10>')
  code
  if ~records(self.groups) and ~records(self.styles)
    pOut.append('[selection: no GROUP/STYLE lines - all rules always-on]' & crlf)
    return
  end
  pOut.append('[selection] style: ' & choose(self.appliedStyle <> '', clip(self.appliedStyle), '(file defaults)') & |
              choose(self.styleFromDefault = 1, ' (file default - DEFAULTSTYLE)', '') & crlf) ! WHERE it came from,
                                                                                              !   or the same command line
                                                                                              !   behaves differently in
                                                                                              !   two files with no sign

  loop g = 1 to records(self.groups)
    get(self.groups, g)
    if ~self.groups.choiceName then cycle.
    chc  = self.groups.choiceName
    chcU = upper(chc)
    first = 1                                                                                 ! print each choice once, at its first member
    loop g2 = 1 to g - 1
      get(self.groups, g2)
      if upper(self.groups.choiceName) = chcU then first = 0 ; break.
    end
    if ~first then cycle.
    win = ''
    winU = 0
    loop g2 = 1 to records(self.groups)
      get(self.groups, g2)
      if upper(self.groups.choiceName) = chcU and self.groups.selected
        win = self.groups.name
        winU = self.groups.isUser
        break
      end
    end
    pOut.append('[selection]   choice ' & clip(chc) & ' -> ' & choose(win <> '', clip(win) & choose(winU = 1, ' (user)', ''), '(none)') & crlf)
  end
  loop g = 1 to records(self.groups)
    get(self.groups, g)
    if self.groups.choiceName then cycle.
    pOut.append('[selection]   group ' & clip(self.groups.name) & choose(self.groups.isUser = 1, ' (user)', '') & ': ' & choose(self.groups.selected = 1, 'ON', 'off') & |
                choose(self.groups.isFinal = 1, ' (FINAL - deferred to the last pass)', '') & crlf)   !
  end
  loop r = 1 to records(self.rules)
    get(self.rules, r)
    if ~self.rules.groupId then n += 1.
  end
  pOut.append('[selection]   ungrouped rules: ' & n & ' (always on)' & crlf)

! ------------------------------------------------------------------------------------
! Load a user stylefile / profile file: STYLE and LASTUSED lines only ('!' comments,
! blanks and '|' continuations as in rule files). ADDS to the loaded rule file's
! styles (no FreeAll) so profiles layer over shipped styles.
! ------------------------------------------------------------------------------------
VitRules.LoadStyleFile Procedure(STRING pFn)
st        StringTheory
line      StringTheory
acc       StringTheory
up        StringTheory
x         long,auto
pos       long,auto
pending   long
accLine   long
errs0     long,auto
  code
  errs0 = self.ErrorCount()
  if not st.LoadFile(pFn)
    self.AddIssue(0, vr:sevError, 'could not load stylefile ' & clip(pFn) & ' : ' & st.LastError)
    return self.ErrorCount() - errs0
  end
  st.LineEndings(st:unix)
  st.split('<10>')
  loop x = 1 to st.records()
    line.setValue(st.getLine(x))
    line.replaceByte(9, 32) ! tabs to spaces replace all <tab> with <space>
    pos = self.PosOutsideQuotes(line, '!')
    if pos then line.setLength(pos - 1).
    line.trim()
    if pending
      acc.append(' ')
      acc.append(line)
    else
      acc.setValue(line)
      accLine = x
    end
    if acc._DataEnd and acc.valuePtr[acc._DataEnd] = '|'
      acc.setLength(acc._DataEnd - 1)
      acc.trim()
      pending = true
      cycle
    end
    pending = false
    if ~acc._DataEnd then cycle.
    up.setValue(acc)
    up.upper()
    if up._DataEnd > 6 and up.valuePtr[1 : 6] = 'STYLE '
      self.ParseStyleLine(acc, accLine, 1)
    elsif up._DataEnd > 9 and up.valuePtr[1 : 9] = 'LASTUSED '
      self.lastUsed = left(acc.sub(10, vr:maxName))
    else
      self.AddIssue(accLine, vr:sevWarn, 'stylefile line ignored (only STYLE and LASTUSED are read here): ' & acc.getValue())
    end
  end
  if pending ! the same guard ParseText's end-of-file arm has. Without it a
    self.AddIssue(accLine, vr:sevError, |                         ! stylefile ending on a '|' drops the accumulated STYLE line in
                  'stylefile ends inside a continued line (trailing |): ' & acc.getValue()) ! silence and the profile applies without it
  end
  return self.ErrorCount() - errs0

! ------------------------------------------------------------------------------------
! Load a USER rulefile - plain DSL, GROUP blocks with
! rules inside, same syntax as the shipped file. APPENDS to the loaded shipped set
! (ParseText skips FreeAll under inUserLoad); every line number is offset by
! vr:userBase so ruleIds, declLines and issue lines cannot collide with shipped ones.
! STYLE/LASTUSED lines are errors here (they belong in the profile file). Load order:
! shipped rule file, then this, then the stylefile. Lint() afterwards runs on the
! COMBINED set, so metavar/group collisions and near-misses against shipped rules come
! free. Returns the user file's OWN error count (also kept in self.userErrors) so
! callers can distinguish fatal-shipped from skip-user; a scratch instance +
! LoadUserText is the workbench's draft-isolation path.
! ------------------------------------------------------------------------------------
VitRules.LoadUserRules Procedure(STRING pFn)
st     StringTheory
errs0  long,auto
  code
  errs0 = self.ErrorCount()
  if not st.LoadFile(pFn)
    self.AddIssue(0, vr:sevError, 'could not load user rulefile ' & clip(pFn) & ' : ' & st.LastError)
    self.userErrors += self.ErrorCount() - errs0
    return self.ErrorCount() - errs0
  end
  return self.LoadUserText(st)

! ------------------------------------------------------------------------------------
! LoadUserRules on an in-memory buffer (the golden runner's --- userrules block;
! the workbench lint/test path on a SCRATCH VitRules). NB pSt is modified (split).
! ------------------------------------------------------------------------------------
VitRules.LoadUserText Procedure(StringTheory pSt)
errs0  long,auto
  code
  errs0 = self.ErrorCount()
  self.inUserLoad = 1
  self.ParseText(pSt)
  self.inUserLoad = 0
  self.userErrors += self.ErrorCount() - errs0
  return self.ErrorCount() - errs0
