! Vitesse Tokenize Class
!
! (c) 2019-2026 Geoffrey C. Robinson.
! Released under the MIT License - see LICENSE.
!
! scans Clarion source and breaks into tokens in a queue
! requires StringTheory from Capesoft
!
! ============================================================================================
! THE TOKEN STREAM, which is the one model everything else in VitTransform is built on.
! Read this before using any of the primitives below - most of their surprises follow from it.
!
! Source becomes ONE QUEUE of tokens, self.tokens, indexed from 1. Each row is:
!
!     tok        &STRING   the token text itself
!     strBefore  &STRING   EVERYTHING between the previous token and this one
!     lineNo               source line
!     firstOnLine          is this the first token on its line
!     type                 what kind of token - literal, label, operator, number ...
!     varType              the declared type, once the symbol table has been built
!     level                block mark: '+' opens, '-' closes, '/' is else/elsif
!
! THE WHOLE TRICK IS strBefore. Indentation, the gaps between tokens, comments, and line
! continuations are not tokens - they are trivia, and they are carried on the NEXT token as
! strBefore. So the file is exactly the concatenation of strBefore & tok down the queue, and
! JoinToks does precisely that. That is why a transform can be lossless: rewrite the tok of a
! token and nothing you did not touch can move, because the whitespace is not yours to lose.
!
! Two consequences worth having in mind:
!  - A LINE ENDING IS ITS OWN TOKEN (tok = '<10>'), not trivia. Trailing whitespace at the end
!    of a line is therefore the TAIL of that EOL token's strBefore. Code that trims trailing
!    space must key on the EOL token; trimming any other token's strBefore would weld two
!    tokens together.
!  - DELETING A TOKEN DELETES ITS strBefore, i.e. the indent in front of it. Every splice that
!    removes the first token on a line has to save that trivia and put it back on whatever
!    token ends up first - see how VitRewrite brackets DeleteToks with TokBefore and
!    PrependStrBefore.
!
! tok and strBefore are REFERENCES (&STRING), allocated with NEW. Anything that drops a row
! must dispose both, and anything that MOVES a row should carry the references rather than
! copy the text - moving is then lossless and costs nothing. DeleteTok does the disposing;
! MoveTok deliberately does not.
! ============================================================================================
!
  MEMBER

  Include('VitTokenize.inc'),ONCE
!  Include('VitTimer.inc'),ONCE
  Include('StringTheory.inc'),ONCE

  Map
!   SortByWord(*WordGroupType w1, *WordGroupType w2),LONG
!   SortByLength(*WordGroupType w1, *WordGroupType w2),LONG
!   SortByLengthDescending(*WordGroupType w1, *WordGroupType w2),LONG  ! descending order on length (biggest to smallest len)
!   Module('')
!     CRC32(*STRING buffer,ULONG size,ULONG crc),ULONG,RAW,NAME('CLA$CRC32')
!     vwsSleep(long pMilliseconds), pascal, proc, name('Sleep')
!     MemChr(ulong buf, long c, unsigned count), long, name('_memchr')
!   End
  End

! note END removed from following list as processed separately with '.'
!reservedWords          STRING(' Accept And Assert Begin Break By CaseChooseCodeCompileConstCycleDataDoElseElsifEndExecuteExit' & |
!                              'FunctionGotoIfIncludeLoopMemberNewNotNullOfOmitOrOrofPragmaProcedureProgramReturn'    & |
!                              'RoutineSectionThenTimesToUntilWhileXor')

reservedWords STRING(' ACCEPT AND APPLICATION ASSERT BEGIN BREAK BY CASE CHOOSE CLASS CODE COMPILE CONST CYCLE DATA DETAIL DO ELSE ELSIF END EXECUTE EXIT' & |
                     ' FILE FOOTER FORM FUNCTION GOTO GROUP HEADER IF INCLUDE INTERFACE ITEMIZE JOIN LOOP MAP MEMBER MENU MENUBAR MODULE NEW NOT NULL OF'  & |
                     ' OLE OMIT OPTION OR OROF PRAGMA PROCEDURE PROGRAM QUEUE RECORD REPORT RETURN ROUTINE SECTION SHEET TAB THEN TIMES TO TOOLBAR UNTIL'  & |
                     ' VIEW WHILE WINDOW XOR ')
! A word has to be in reservedWords above before TokenType will recognise it as a reserved word, so a new keyword goes in BOTH
! places: here, and the level CASE in TokenType. dataTypes is a separate list with its own lookup and is not affected.


dataTypes STRING(' LONG STRING CSTRING PSTRING REAL ULONG BYTE SHORT USHORT DATE TIME ULONG DECIMAL PDECIMAL' & |
                 ' SREAL BFLOAT4 BFLOAT8 ANY WINDOW FILE QUEUE SIGNED UNSIGNED VIEW KEY GROUP ')
! ------------------------------------------------------------------------------------
VitTokenize.Construct Procedure()
separators String('<9,32>')
delimiters String('()[]{{}:,.;=') ! note that : is a delimiter in [1:5] or [a:z] but not in a variable name xx::something
operators  String('<<>~+-/*%^&')

x          long,auto
 code
  self.tokens   &= new TokenQType
  self.vars     &= new VarTypeQType
  self.searchQ  &= new searchQType
  self.searchSt &= new StringTheory
  self.lineMap  &= new TokLineMapQType ! preview line map (inert until MapInit arms mapOn)
  self.lineMap2 &= new TokLineMapQType
  self.noteQ    &= new NoteQType
  self.ppTerms  &= new StringTheory

  clear(self.separatorA)               ! not really needed but initialize all to true
  loop x = 1 to size(separators)
    self.separatorA[val(separators[x])+1] = TRUE
  end

  clear(self.delimiter)                ! not really needed but initialize all to true
  loop x = 1 to size(delimiters)
    self.delimiter[val(delimiters[x])+1] = TRUE
  end

  clear(self.operator)                 ! not really needed but initialize all to true
  loop x = 1 to size(operators)
    self.operator[val(operators[x])+1] = TRUE
  end

  self.ignoreOmittedCode = 1           ! honour the declared BYTE(1) default EXPLICITLY.
                                       ! Clarion does NOT apply inline initial values to NEW'd CLASS reference data
                                       ! members, so without this the .inc 'BYTE(1)' is silently 0 at runtime -> the
                                       ! OMIT state machine (gated on this flag in ParseText's state 0) never runs, and
                                       ! an unconditional omit('...') block leaks its (non-'!'-prefixed) prose into the
                                       ! token stream, where dotted words (e.g. 'and works...)') desync the label
                                       ! merge and trip the gated diagnostic below. Absorbed OMIT text is preserved on
                                       ! rejoin via strBefore, so this stays byte-lossless.
  self.cmtGap   = 1                    ! and the comment-layout numbers, for the reason above: an initial value on a NEW'd
  self.cmtReach = 3                    !   class declaration never arrives, so EVERY member the .inc gives one has to be
  self.cmtRun   = 10
  self.cmtInner = 12                   !   repeated here or it reads 0. The engine overwrites all of them from its switches
  self.cmtKeep  = 1                    !   before it aligns anything; these are what a tokenizer used on its own gets, and
  self.contBracket = 1                 !   they are the shipped layout.

  self.LogFn = 'Log on ' & clip(left(format(today(),@d12))) & ' at ' & clip(left(format(clock(),@T05))) & '.txt'

! ------------------------------------------------------------------------------------
VitTokenize.Destruct  Procedure()
 code
  self.FreeToks()
  dispose(self.tokens)

  dispose(self.Vars)

  self.FreeSearchQ()
  dispose(self.searchQ)

  dispose(self.searchSt)

  free(self.lineMap)    ! plain LONG rows - nothing referenced to dispose per-row
  dispose(self.lineMap)
  free(self.lineMap2)
  dispose(self.lineMap2)
  free(self.noteQ)
  dispose(self.noteQ)
  dispose(self.ppTerms)

! ------------------------------------------------------------------------------------
VitTokenize.ParseText  Procedure(STRING pFileName)
st          StringTheory
 code
  ! a file that is there and holds nothing is empty, not unreadable: it parses to no tokens
  if not st.LoadFile(pFileName) and (st.winErrorCode or ~exists(clip(pFileName)))
    self.FreeToks()
    self.fileSize = 0
    message('Error in ParseText when trying to load file ' & clip(pFileName) & '||' & st.LastError)
  else
    self.fileSize = st._DataEnd
    self.ParseText(st,pFileName)
  end

! ------------------------------------------------------------------------------------
! THE TOKENIZER. Clarion source in, self.tokens out - see the token stream description at
! the top of this file for what a row is and why the trivia lives where it does. JoinToks
! is the exact inverse, and the pair round trips byte-for-byte on an untouched file, which
! is the property every lossless rewrite ultimately rests on.
!
! It does three things at once, which is why it is long: it cuts the text into tokens, it
! classifies each one (type, and later varType), and it marks block structure in level -
! '+' opens, '-' closes, '/' is else/elsif.
!
! THE LEVEL MARKS ARE THE SUBTLE PART, and a tokenizer mistake is most often a level
! mistake: something that looks like a structure keyword opens a block nothing closes,
! and the damage surfaces hundreds of lines away. Two rules earn their complexity:
!  - The CODE structures - IF CASE LOOP EXECUTE BEGIN ACCEPT - open unconditionally,
!    because each is followed by an expression and none is ever a variable name.
!  - The DATA and CONTROL structures open only in DECLARATION POSITION, decided by the
!    NEXT token being ',' '(' or end of line. Window and Report are the Clarion template's
!    own default labels, so Window{PROP:Text} = 'x' must not open anything.
!
! This is why the level census exists - counting opens against closes over a whole file is
! how a mis-parse gets caught HERE rather than as mangled output later. A file that does
! not balance is telling you about this procedure.
! ------------------------------------------------------------------------------------
VitTokenize.ParseText  Procedure(StringTheory st,<String pFilename>,LONG pMergeLabels=FALSE)
pos            Long,auto
svPos          Long,auto
omitDir        Long              ! is this OMIT the DIRECTIVE, or a method that spells it?
mergeGap       Long              ! the gap before a member dot is blanks only - the name merges across it
x              Long,auto
z              Long,auto
depth          Long,auto
state          Long,auto
prevIsEnd      Long,auto
inContinuation Long
inPicture      Long              ! inside an @P.../@K... picture, where ' ! and | are picture CONTENT, not
picClose       String(1)         !   quote/comment/continuation. picClose is the closing delimiter, CASE-SENSITIVE
picEsc         Long              !   per the LRM; picEsc handles @K's '\' escape (next char is a display char)
colonCount     long,auto
spA            string(1),auto    ! a spaced comparison: its first half
spGap          long,auto         !   and the length of the blanks after it
newQ           &TokenQType       ! colon-merge rebuild target
mergePosQ   QUEUE,PRE(mp)        ! newQ rows whose merged text needs TokenType
row           long
            END
mergedTx    StringTheory         ! merged token text builder
consumedTo  long,auto
lastQx      long,auto
prevType    string(1),auto
currType    string(1)
prevCh      string(1)            ! the PREVIOUS token when it was a single character ('&' ',' etc), which is what tells an attribute or a reference from a declaration
prevStrIx   long                 ! token index of a declaration-structure keyword (the promotion list below). They open only in DECLARATION position - next token ',' '(' or EOL
prevBrkIx   long                 ! token index of a BREAK just seen (0 = none). BREAK is a report STRUCTURE only when a '(' follows; bare BREAK is a statement.
prevLoop    long                 ! previous token was LOOP - so an UNTIL/WHILE here is the loop HEADER (pre-test, still needs an END), not the post-test terminator
parenDep    long                 ! '(' depth within the STATEMENT - a structure keyword inside parentheses is a parameter type or an attribute, never a block
stmtTok     long                 ! which token of its STATEMENT this one is, 1 = the first. A declaration structure stands at 1, or at 2 after a label
stmtLbl     long                 !   ... and the statement's first token stands in column 1, where a label goes
prevStrCall long                 !   ... and that keyword stands first in a statement of a CODE body, where a CALL goes
inCode      long                 ! inside a CODE body: from CODE, or a ROUTINE header, to the next PROCEDURE header or DATA
mapDep      long                 ! inside a MAP: 1 for the MAP itself, one more for each MODULE open inside it
mpAlone     long,auto            ! the word MAP stands alone in its statement: a line end, a ';' or a '.' follows it, or nothing
decln       string(vt:maxVarLen) ! declaration
tok         StringTheory
strBefore   StringTheory
tempST      StringTheory
svBefore    StringTheory         ! the strBefore accumulated up to (and only) the OMIT keyword
termStk     StringTheory         ! the terminators of the COMPILE and conditional OMIT blocks still open, innermost last
!--------
! following are really for GetNextToken but put here for speed
inComment   Long,auto
inQuotes    Long,auto
!startPos    Long,auto
!--------
 code
  self.FreeToks()
  self.ppTerms.FreeLines()                                                             ! the terminators are this text's own

!-----------
! self.traceIt = true
!-----------

  st.LineEndings(st:unix)                                                              ! convert CRLF to LF '<10>'
  self.tokens.type = ' '                                                               ! default to space for now
  pos = 1
  state = 0
  loop
    do GetNextToken
    if state = 4 then state = 0.                                                       !do NOT move this (state 4 means we finished omit but want to retain 'beforeString' text in GetNextToken)
    case state
    of 0                                                                               ! normal state - not special OMIT processing
      if Tok._DataEnd or strBefore._DataEnd
        do AddToken
        if tok._DataEnd > 2 and tok.valuePtr[1] = '''' then do PpTermNote.             ! a literal - the terminator of an OMIT or COMPILE when those two tokens stand in front of it
        if tok._DataEnd = 1 and tok.valuePtr[1] = '<10>' then do TermFold.
        if self.ignoreOmittedCode and tok._DataEnd = 4 and upper(tok.valueptr[1 : 4]) = 'OMIT'
          do OmitIsDirective                                                           ! a METHOD named Omit is not the directive
          if omitDir
            svPos = pos                                                                ! save position
            svBefore.setValue(strBefore)                                               ! snapshot the pre-OMIT whitespace only; states 1-3 do not free strBefore, so GetNextToken would otherwise
                                                                                       !   leave the interior header ws in it AND the slice below re-captures the same ws -> duplicate
            state = 1
            cycle
          end
        end
      end
      if ~Tok._DataEnd then break.

    of 1                                                                               ! omit looking for (
      if tok._DataEnd = 1 and tok.valuePtr[1] = '('
        state = 2                                                                      ! omit looking for literal
      else
        pos = svPos; state = 0; inContinuation = false                                 ! revert - not simple omit (and clear any lexer state the consumed tokens set: a glued '|' left the flag armed)
      end

    of 2                                                                               ! omit looking for literal
      if tok._dataEnd > 2 and tok.startsWith('''') and tok.endsWith('''')
        tempST.setvalue(tok)
        tempST.unquote('''')                                                           ! store the string we will search for end of OMIT
        if tempST._DataEnd                                                             ! a terminator ending in a blank or a tab: ClipLines must leave the line holding it alone
          if tempST.valuePtr[tempST._DataEnd] = ' ' or tempST.valuePtr[tempST._DataEnd] = '<9>' then self.ppTerms.addLine(tempST.getValue()).
        end
        state = 3
      else
        pos = svPos; state = 0; inContinuation = false                                 ! revert - not simple omit (and clear any lexer state the consumed tokens set: a glued '|' left the flag armed)
      end

    of 3                                                                               ! omit looking for ')'
      if tok._DataEnd = 1 and tok.valuePtr[1] = ')'
        ! the terminator search starts on the rest of the OMIT line itself, after its ')':
        ! measured, the compiler ends the block there when that line's comment holds the
        ! terminator - `OMIT('**end**')  ! runs to **end**` omits nothing below it.
        pos = st.findChars(tempST.valuePtr[1 : tempST._dataEnd], pos)
        if pos
          ! search to end of line
          pos = st.findByte(10, pos)                                                   ! <line feed>
          if pos
            self.deleteTok(records(self.tokens))                                       ! delete OMIT from token queue
            tempST.setValue(st.slice(svPos-4,pos))
            tempST.replace('<10>','<13,10>')
            strBefore.setValue(svBefore)                                               ! keep only the pre-OMIT ws; the slice already holds the whole OMIT block (incl. interior ws), so appending it once avoids the duplicate
            strBefore.append(tempST)                                                   ! we append all the chars in the omit to the "before" string
            state = 4                                                                  ! finished with omit but want to preserve 'before' text when getting next token
            pos += 1
            do TermFold
            cycle
          else
            ! end of file found - no further lines
            pos = st._dataEnd + 1
            self.deleteTok(records(self.tokens))                                       ! delete OMIT from token queue
            tempST.setValue(st.slice(svPos-4))                                         ! slice to EOF
            tempST.replace('<10>','<13,10>')
            strBefore.setValue(svBefore)                                               ! keep only the pre-OMIT ws (see above); slice holds the whole block
            strBefore.append(tempST)                                                   ! we append all the chars in the omit to the "before" string
            tok.free()
            do AddToken
            break                                                                      ! EOF
          end
        else
          pos = svPos; inContinuation = false                                          ! revert - not simple omit (see the note above)
        end
      else
        pos = svPos; inContinuation = false                                            ! revert - not simple omit (see the note above)
      end
      state = 0
    else
      self.TraceIt('unexpected state ' & state & ' in VitTokenize.ParseText')          ! should never happen...
    end                                                                                ! case
  end

  ! check if we are in [] and if not then combine fields with colon prefixes.
  ! rebuilt as a SINGLE forward pass into a fresh queue - the in-place version's
  ! per-merge DeleteToks (an O(n) queue shift each) made colon-dense files O(n^2). Semantics
  ! preserved exactly: adjacency via empty strBefore, adjacent-colon runs, chained a:b:c via
  ! merging into the LAST emitted record, ':' inside [] untouched, no merge at token #1.
  ! Transferred records carry their &STRING pointers into newQ; consumed records' strings are
  ! disposed here (their text was copied into the merge); free(old) never disposes targets.
  newQ &= new TokenQType
  free(mergePosQ)
  depth = 0
  x = 0
  loop
    x += 1
    if x > records(self.tokens) then break.
    get(self.tokens, x)
    if errorcode() then break.
    if not self.tokens.tok &= NULL and size(self.tokens.tok) = 1
      if self.tokens.tok = '['
        depth += 1
      elsif depth
        if self.tokens.tok = ']' then depth -= 1.
      elsif self.tokens.tok = ':' and records(newQ) > 0 and self.tokens.strBefore &= NULL ! records(newQ)>0 =  no-previous-token guard
        colonCount = 1                                                                 ! run of adjacent ':' tokens starting at x
        loop
          get(self.tokens, x + colonCount)
          if errorcode() then break.
          if not self.tokens.tok &= NULL and size(self.tokens.tok) = 1 and self.tokens.tok = ':' |
             and self.tokens.strBefore &= NULL
            colonCount += 1
            cycle
          end
          break
        end
        ! buffer holds the token AFTER the run - decide the merge-with-next NOW, before any
        ! other queue op clobbers errorcode()/the buffer (get(newQ) would reset both)
        consumedTo = x + colonCount - 1                                                ! default: prev & ':'xN (token ends with colon)
        tempST.free()
        if ~errorcode() and x + colonCount <= records(self.tokens)
          if not self.tokens.tok &= NULL and self.tokens.strBefore &= NULL
            tempST.setValue(self.tokens.tok)                                           ! next token's text - merge it too
            consumedTo = x + colonCount
          end
        end
        lastQx = records(newQ)
        get(newQ, lastQx)
        mergedTx.setValue(newQ.tok)
        mergedTx.append(all(':', colonCount))
        if tempST._DataEnd then mergedTx.append(tempST).                               ! prev & ':'xN & next
        dispose(newQ.tok)
        newQ.tok &= new STRING(mergedTx._DataEnd)
        newQ.tok  = mergedTx.getValue()
        put(newQ)
        mp:row = lastQx                                                                ! retype after the swap (SetTok parity)
        add(mergePosQ)
        loop z = x to consumedTo                                                       ! consumed records: text already copied - dispose their strings
          get(self.tokens, z)
          if errorcode() then break.
          dispose(self.tokens.tok)
          dispose(self.tokens.strBefore)
        end
        x = consumedTo
        cycle
      end
    end
    get(self.tokens, x)                                                                ! re-load (the run lookahead moved the buffer)
    if errorcode() then break.
    ! EVERY QUEUE HAS ITS OWN RECORD BUFFER: get() filled self.tokens' buffer, but add(newQ)
    ! appends newQ's buffer - copy field-by-field first (same TYPE; references copy as pointers).
    ! Without this the rebuild would append newQ's STALE buffer: garbage records, duplicated
    ! &STRING pointers, and a double-dispose GPF in FreeToks.
    newQ.lineNo      = self.tokens.lineNo
    newQ.firstOnLine = self.tokens.firstOnLine
    newQ.strBefore  &= self.tokens.strBefore
    newQ.tok        &= self.tokens.tok
    newQ.type        = self.tokens.type
    newQ.varType     = self.tokens.varType
    newQ.level       = self.tokens.level
    add(newQ)                                                                          ! transfer the record (pointers move with it)
  end
  free(self.tokens)                                                                    ! plain free: never disposes the transferred &STRINGs
  dispose(self.tokens)
  self.tokens &= newQ
  loop z = 1 to records(mergePosQ)                                                     ! retype the merged tokens (what SetTok's TokenType call did)
    get(mergePosQ, z)
    get(self.tokens, mp:row)
    if errorcode() then cycle.
    self.TokenType()
    put(self.tokens)
  end

  ! look for reference prototypes like *STRING
  loop x = 1 to self.records()
    tok.setValue(self.getTok(x))
    if tok._DataEnd = 1 and tok.valueptr[1] = '*'
      case val(self.getTok(x-1))                                                       ! val() reads the FIRST BYTE, which is safe in THIS position: '(' and ',' are delimiters and always stand
                                                                                       !   alone, and the '<<' tested for is the omittable-parameter marker that opens a prototype argument.
                                                                                       !   No multi-character token that could appear immediately before a '*TYPE' starts with one of them.
      of 40 orof 44 orof 60                                                            ! '(' orof <comma> orof '<<'
        self.getTok(x+1,StrBefore,Tok)
        if tok._DataEnd and ~strBefore._DataEnd                                        ! no spaces between
          self.SetTok(x,'*' & tok.valueptr[1 : tok._DataEnd])                          ! combine with following token
          self.DeleteTok(x+1)
        end
      end
    end
  end

  ! look for deep assignments ':=:' where this is in three consecutive tokens without any spacing between
  loop x = 1 to self.records()
    if self.getTok(x) = ':'
      Get(self.tokens, x+1)
      if ~errorcode() and self.tokens.strBefore &= NULL and (not self.tokens.tok &= NULL) and self.tokens.tok = '='
        Get(self.tokens, x+2)
        if ~errorcode() and self.tokens.strBefore &= NULL and (not self.tokens.tok &= NULL) and self.tokens.tok = ':'
          self.setTok(x,':=:')                                                         ! combine three tokens
          self.DeleteTok(x+2)
          self.DeleteTok(x+1)
        end
      end
    end
    ! A COMPARISON WRITTEN WITH BLANKS BETWEEN ITS HALVES - `< >`, `~ =`, `> =` - IS ONE OPERATOR,
    ! as it is to the compiler. It is joined here with the blanks kept in its text, so a rule
    ! written <> reads it, and the line is still written exactly as the author spelled it. Only
    ! the eight comparison pairs, and only across spaces and tabs: a comment, a | or a line break
    ! between the halves leaves them as two tokens.
    Get(self.tokens, x)
    if ~errorcode() and not self.tokens.tok &= NULL and size(self.tokens.tok) = 1 and instring(self.tokens.tok, '<<>~=', 1, 1)
      spA = self.tokens.tok
      Get(self.tokens, x+1)
      if ~errorcode() and not self.tokens.tok &= NULL and size(self.tokens.tok) = 1 and not self.tokens.strBefore &= NULL
        if instring(' ' & spA & self.tokens.tok & ' ', ' <<> <<= >= ~= ~<< ~> =<< => ', 1, 1)
          spGap = size(self.tokens.strBefore)
          loop z = 1 to spGap
            if self.tokens.strBefore[z] <> ' ' and self.tokens.strBefore[z] <> '<9>' then break.
          end
          if z > spGap                                                                 ! blanks only, all the way
            self.setTok(x, spA & self.tokens.strBefore & self.tokens.tok)
            self.DeleteTok(x+1)
          end
        end
      end
    end
  end

  ! check for decimal points in numbers eg. 123.45
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break.                              ! no more tokens

    prevType = currType
    currType = ' '
    if size(self.Tokens.tok) = 1 and self.Tokens.tok = '.'
      if self.Tokens.strBefore &= NULL and prevType = vt:Integer                       ! eg 123.
        self.Tokens.Type = vt:decPoint                                                 ! d = decimal point
        currType = vt:decPoint                                                         ! d =decimal point
        put(self.tokens)
      end
      cycle
    end

    if self.Tokens.Type = vt:Integer or self.Tokens.Type = 'N'                         ! integer, or an exponent tail like 5e3
      currType = self.Tokens.Type
      if prevType = vt:decPoint and self.Tokens.strBefore &= NULL
        ! combine three tokens 123|.|45 into one token 123.45
        self.SetTok(x-2,self.getTok(x-2) & '.' & self.getTok(x))                       ! combine three tokens into one
        self.tokens.type = 'N'                                                         ! numeric with dec point
        put(self.tokens)
        self.DeleteTok(x)
        self.DeleteTok(x-1)
        x -= 2
      end
    end
  end                                                                                  !loop

  ! check if we can merge labels  eg.  x.y.getvalue() then combine x.y
  state = 0
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break.                              ! no more tokens
    case state
    of 0                                                                               ! looking for label
      if self.tokens.type = vt:label
        state = 1
      end
    of 1                                                                               ! have label looking for dot
      ! A SPACE BEFORE THE MEMBER DOT IS LEGAL CLARION AND THE NAME MERGES ACROSS IT.
      ! `x.y .getvalue()` is one member reference written with a gap. Were the merge to
      ! require NO leading trivia on the dot, it would hand the reference back as THREE
      ! tokens, and every consumer that reads a member as one token would be looking at
      ! something it does not recognise. Most answer "cannot prove" and leave the code
      ! alone, which is safe by accident rather than by design; one can silently delete
      ! a load-bearing guard. Merging here settles the whole class at the source instead
      ! of one consumer at a time.
      ! THE GAP IS DROPPED. The merge builds its text from the two label
      ! texts and a literal '.', so the dot's trivia is not carried anyway - it is disposed
      ! with the token. `x.y .getvalue()` therefore comes out as `x.y.getvalue()`. That is a
      ! change to the user's layout, and it is bounded: nothing is written unless the file
      ! changed for some other reason, so this only ever appears in a file being rewritten
      ! already - the same bargain ClipLines makes.
      ! ONLY BLANKS. A comment, a continuation bar or a line break in that gap is not a name
      ! with a space in it, and crossing one would splice two different lines into one token.
      ! AND ONLY BEFORE THE DOT: state 2 below stays strict, because a dot followed by a space
      ! is Clarion's statement TERMINATOR, not a qualifier - asked of the compiler, not argued.
      ! THREE WAYS TO QUALIFY, as one short-circuiting chain: no gap, a BLANK gap, or a gap of
      ! spaces and tabs. The middle test is not just a shortcut for the common case - it is what
      ! keeps IsAll honest. IsAll reads a zero-length pTestString as "not supplied" and tests the
      ! RECEIVER'S OWN value instead, so reaching it with an empty gap would answer from whatever
      ! tempST happened to be holding. A blank gap is answered before that, so IsAll is only ever
      ! reached with a non-blank string - the fallback is unreachable by construction, not merely
      ! excluded. tempST is a VEHICLE for the method; its own value is never consulted.
      ! *** THE THIRD ARGUMENT IS pClip, NOT A CASE FLAG. *** false measures the alphabet with
      ! size() rather than clipLen(), which trims trailing SPACES. It changes nothing for
      ! '<32,9>', whose last byte is a tab - but write the alphabet '<9,32>' and the default would
      ! clip the space straight out of it, and no plain-space gap would ever merge.
      if self.tokens.tok = '.'
        mergeGap = choose(self.tokens.strBefore &= NULL or                             |
                          ~self.tokens.strBefore        or                             |
                          tempST.IsAll('<32,9>', self.tokens.strBefore, false))
      else
        mergeGap = 0
      end
      ! A TOKEN THAT IS NOT THE DOT MAY START A NAME OF ITS OWN. After a column-1 statement label
      ! the next word is the statement's first - `Again st._DataEnd = n` - and is looked at again
      ! as a label here, so its member reference merges exactly as it would with no label.
      if mergeGap
        state = 2
      else
        state = choose(self.tokens.type = vt:label)
      end
    of 2                                                                               ! have label. looking for another label
      ! NO GAP AFTER THE DOT - asked of the trivia itself, not of BufColOne. BufColOne answers 0
      ! for every token of a FRAGMENT (midLine), so a replacement spliced into the middle of a line
      ! would keep `self.sepTxt` as three tokens until the next RUN parsed the file again, and
      ! a builtin that reads a member as one token would refuse it on every pass left. midLine is
      ! about the fragment's FIRST word, and this is never the first word. A file parse agrees.
      ! NO GAP MEANS NONE AT ALL. After a line break the name is on another line: a '|' and a comment,
      ! or a folded OMIT block, sit in that gap, and merging across it would throw them away with the
      ! token - `n = G.|  ! the count` over `qty` would come out as one line with the comment gone.
      ! Such a name stays three tokens, and the END walk below does not take its dot for a terminator.
      if self.tokens.strBefore &= NULL and self.tokens.type = vt:label
        state = 3
      else
        state = 0
      end
    of 3                                                                               ! have label.label
      ! the 'or' test merges a dotted name that is not a call (ST._dataEnd) even without pMergeLabels:
      if pMergeLabels or self.tokens.tok <> '('                                        ! the variable checks read such a name as ONE token
        ! combine labels
        self.SetTok(x-3,self.getTok(x-3) & '.' & self.getTok(x-1))                     ! combine three tokens into one
        if self.tokens.type <> vt:label
          if self.stopIt
            self.TraceIt('expected label but got type [' & self.tokens.type & ']' &    |
               '<13,10>Token No: ' & pointer(self.tokens)                         &    |
               '<13,10>Line No: ' & self.tokens.LineNo                            &    |
               '<13,10>Tok: [' & choose(~self.tokens.tok &= Null,self.tokens.tok,'') & ']')
          end
        end
        self.DeleteTok(x-1)
        self.DeleteTok(x-2)
        x -= 3                                                                         ! go back to label
        state = 1
      else
        state = 0
      end
    end
  end                                                                                  !loop
  ! ENDED ON `a.b`: the merge above is decided by the token AFTER the name, and there is none. A
  ! file always has one (its line ends), a fragment may not - InsertString finishes it against
  ! the token the fragment lands in front of.
  self.mergeTail = choose(state = 3)

!  self.SetLineNumbers()

  ! check for END statements including dots '.'
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break.                              ! no more tokens

    prevType = currType
    currType = ' '

    ! A STRUCTURE KEYWORD CANNOT OPEN A BLOCK INSIDE PARENTHESES. TokenType marks
    ! QUEUE / GROUP / FILE / RECORD / CLASS / MODULE and the rest with level '+' on the word
    ! alone, but at paren depth > 0 the same word is a parameter TYPE or an attribute:
    !     Trace           PROCEDURE(Queue pQueue), virtual        <- a TYPE
    !     SerializeGroup  PROCEDURE(*Group pGroup, ...)           <- a TYPE
        ! A parameter TYPE given level '+' opens a level that never closes: its '-' is taken by
    ! the enclosing CLASS's END, that CLASS runs to EOF unmatched, and every stream that
    ! includes such a header comes out one level short.
    !
    ! This generalises the MODULE rule rather than adding a second special case. It is
    ! still needed and is NOT subsumed: in `CLASS,TYPE,MODULE('x.clw')` the MODULE sits at
    ! paren depth 0 - it is the '(' AFTER it that opens - so only the comma test catches it.
    !
    ! Depth resets at every STATEMENT boundary, which is an EOL **or a ';'**:
    ! `a = f(x) ; b = 2` is two statements on one line, and parens cannot span the ';'
    ! any more than they can span a newline. EOL alone would leak a stray '(' from the
    ! first statement into every later one on that line.
    ! EOL is the right test for the line case rather than the physical newline, because
    ! GetNextToken appends the newline to strBefore while inContinuation is set and emits NO
    ! EOL token, so a CONTINUED statement holds none and is not falsely split.
    ! The reset matters at all because a single stray '(' would otherwise leave depth stuck
    ! above zero and silently suppress EVERY structure open for the rest of the file - a far
    ! worse failure than the one it guards against. Bounding it to one statement is the point.
    if size(self.Tokens.tok) = 1 and (self.Tokens.tok[1] = '<10>' or self.Tokens.tok[1] = ';')
      parenDep = 0                                                                     ! EOL or ';' - parens cannot span a statement
    elsif self.Tokens.tok = '('
      parenDep += 1
    elsif self.Tokens.tok = ')'
      if parenDep then parenDep -= 1.
    elsif parenDep > 0 and self.Tokens.Level = '+'
      self.Tokens.Level = ' '                                                          ! a type or an attribute - it opens nothing.
      put(self.tokens)                                                                 ! a guard, but NOT for the declaration
    end                                                                                !   structures - the guard at the promotion below excludes parenDep already. What is left for this to catch is the SIX unconditional
                                                                                       !   openers (IF/CASE/LOOP/EXECUTE/BEGIN/ ACCEPT) and anything else put on that CASE.

    ! WHICH TOKEN OF ITS STATEMENT THIS IS, for the declaration-position test further down. A
    ! statement starts after an EOL or a ';', the same boundary parenDep resets at.
    if size(self.Tokens.tok) = 1 and (self.Tokens.tok[1] = '<10>' or self.Tokens.tok[1] = ';')
      stmtTok = 0
    else
      stmtTok += 1
      if stmtTok = 1 then stmtLbl = self.BufColOne().
    end

    ! WHERE THE STATEMENT STANDS: IN A CODE BODY, IN A MAP, OR IN DATA - for the same test. A CODE
    ! body holds statements, so a structure word that stands first in one, alone or with a '('
    ! after it, is a CALL of a procedure that has the structure's name - `Report`, `Menu()` - and
    ! opens nothing. A MAP holds prototypes, so there every such word but MODULE is a procedure's
    ! name. The body runs from CODE, or from a ROUTINE header, to the next PROCEDURE or FUNCTION,
    ! a routine's DATA or a SECTION; and a declaration that does open inside one ends it, which is
    ! what a template export gives when a window section follows an embed of code. A MAP ends at
    ! its own END; each MODULE inside it opens one more level, closed by its own.
    ! MAP takes no attributes, so the structure is the word alone in its statement, ended by the
    ! line, a ';' or its own '.'. A word with anything else after it is a name: a replacement such
    ! as `Map += 1` is parsed on its own, with no CODE in front of it, and the word stands first
    ! and indented there as the structure does.
    if self.Tokens.Type = vt:reservedWord
      case upper(self.Tokens.tok)
      of 'CODE'
        if stmtTok = 1 and ~stmtLbl then inCode = 1.
      of 'ROUTINE'
        if stmtTok = 2 and stmtLbl then inCode = 1.
      of 'DATA'      orof 'SECTION'
        if stmtTok = 1 then inCode = 0.
      of 'PROCEDURE' orof 'FUNCTION'
        inCode = 0
      end
    elsif self.Tokens.Type = vt:Map and self.Tokens.Level = '+'
      mpAlone = 1
      if x < records(self.tokens)
        get(self.tokens, x + 1)
        if ~errorcode() and not self.tokens.tok &= NULL
          if size(self.tokens.tok) > 1 or ~inlist(self.tokens.tok, '<10>', ';', '.') then mpAlone = 0.
        end
        get(self.tokens, x)
      end
      if stmtTok = 1 and ~stmtLbl and ~inCode and mpAlone
        mapDep = 1
      else                                                                             ! a NAME spelled Map - a column-1 label, a use in code, a word later in
        self.Tokens.Level = ' '                                                        !   a statement: the LRM lets MAP be a label, and only the structure
        self.Tokens.Type = vt:label                                                    !   stands first in its statement, indented, outside CODE
        put(self.tokens)
      end
    end

    ! THE POST-TESTED LOOP. Clarion writes a loop two ways -
    !     LOOP UNTIL cond      pre-test:  UNTIL is part of the HEADER, an END still closes it
    !     loop                 post-test: UNTIL is the terminator, and there is NO END
    !       ...
    !     until cond
    ! UNTIL and WHILE carry a level mark, so the post-test form closes its LOOP.
    ! The two forms differ by ONE token: in the pre-test the word FOLLOWS LOOP directly; in
    ! the post-test it starts its own statement, so the token before it is an EOL. That is
    ! the same lookback as the ',' and '&' tests above, which is why this is here and not in
    ! a pass of its own.
    ! LEVEL ONLY, deliberately not type vt:end: a good deal of code tests for an END token
    ! by TYPE, and an UNTIL is not an END - it just closes the same structure.
    ! THE RULE ITSELF IS CORRECT AND MUST STAY. Clarion has two LOOP forms:
    !     LOOP UNTIL x      pre-test  - the loop still needs an END
    !     LOOP ... UNTIL x  post-test - the UNTIL *IS* the terminator, there is no END
    ! `~prevLoop` is what tells them apart, and in the post-test form the '-' is exactly
    ! right - the loop really does close here. Nothing about that changes.
    ! What the guard adds is the ONE case where the word is neither: a method call such as
    ! `q.until('x')`, where a '-' would close a structure that was never opened and steal a
    ! real END. The legitimate post-test form is untouched, because the token before UNTIL
    ! there is the EOL, and prevCh holds the EOL's own character (a single LF), not '.'.
    ! No StringTheory method is called `until` or `while`, so unlike join and break this
    ! one is prevention: it guards a class that has such a method, not a StringTheory
    ! call known to go wrong.
    if ~prevLoop and self.Tokens.Type = vt:reservedWord and prevCh <> '.'
      case upper(self.Tokens.tok)
      of 'UNTIL' orof 'WHILE'
        self.Tokens.Level = '-'
        put(self.tokens)
      end
    end
    prevLoop = choose(upper(self.Tokens.tok) = 'LOOP')

    ! BREAK IS BOTH, and the two are told apart by ONE token.
    !     break1  BREAK(BOO:ResServId)    a REPORT structure - it has an END
    !     BREAK                           a statement - exits the enclosing LOOP
    ! Only the structure form takes a '(' . So BREAK is left OFF the level CASE (its default
    ! is blank, which keeps every `if ~p then break.` correct) and is promoted HERE, on the
    ! NEXT token, once a '(' proves what it is. Looking forward from BREAK would need a peek;
    ! looking back from '(' needs only what we already have.
    ! A REPORT often holds both forms: a BREAK structure with its END, and bare BREAK
    ! statements (and inline ones) in the code that prints it.
    ! Leaving it out is NOT a harmless under-reach: with BREAK not opening, the BREAK's END
    ! closes the REPORT instead, and the FOOTER, FORM and final END after it all mis-nest.
    if prevBrkIx and size(self.Tokens.tok) = 1 and self.Tokens.tok = '('
      get(self.tokens, prevBrkIx)
      self.Tokens.Level = '+'
      put(self.tokens)
      get(self.tokens, x)                                                              ! restore the buffer the loop is working on
    end
    ! BREAK takes the declaration-position guard too, or
    ! `st.break('x')` would promote exactly as `st.join(` would without it.
    ! Same four conditions as the guard below.
    if upper(self.Tokens.tok) = 'BREAK' and ~parenDep and prevCh <> '&' and prevCh <> ',' and prevCh <> '.'
      prevBrkIx = x
    else
      prevBrkIx = 0
    end

    ! DECLARATION STRUCTURES OPEN ONLY IN DECLARATION POSITION.
    ! INTERFACE VIEW JOIN REPORT HEADER FOOTER DETAIL FORM, and WINDOW APPLICATION QUEUE GROUP
    ! FILE RECORD CLASS ITEMIZE MENUBAR MENU TOOLBAR SHEET TAB OPTION MODULE with them, are not
    ! on the unconditional level CASE, because the same word is an identifier wherever a
    ! template's default label is reused:
    !     Report               REPORT,AT(...)          the structure
    !     Report{PROP:FlushPreview} = True             the SAME NAME, used as an identifier
    ! and marking the second would open a block that nothing ever closes. A DECLARATION is
    ! followed by ',' (attributes), '(' (a parent class or a FILE), or the end of the line;
    ! an identifier use is followed by '{', '=', an operator, a ')'. So these words are
    ! promoted here, once the NEXT token says which it is - the same shape as the BREAK rule
    ! above, and for the same reason. A use inside parentheses - SetTarget(Report),
    ! Close(Report) - is excluded by the paren rule already. In a CODE body only a ',' opens: a
    ! call is followed by its '(' or by the end of the line, never by an attribute list.
    if prevStrCall and self.Tokens.tok <> ',' then prevStrIx = 0.
    if prevStrIx
      if self.Tokens.tok = ',' or self.Tokens.tok = '('                                |
         or (size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>')
        get(self.tokens, prevStrIx)
        self.Tokens.Level = '+'
        put(self.tokens)
        inCode = 0
        if mapDep then mapDep += 1.
        get(self.tokens, x)                                                            ! restore the buffer the loop is on
      end
    end
    ! The paren-depth demotion above tests for level '+', and these keywords default to
    ! BLANK, so it never fires for them. Its condition, and three more, guard the promotion:
    !   parenDep    `PROCEDURE(Queue pQueue)` - a parameter TYPE
    !   prevCh '&'  `grp &GROUP`              - a REFERENCE type
    !   prevCh ','  `CLASS,TYPE,MODULE('x')`  - an ATTRIBUTE. Without this the MODULE would
    !               be promoted by the '(' that follows it, undoing the demotion completely.
    !   prevCh '.'  `st.join('x')`             - a METHOD CALL. Every one of join, record, group,
    !               queue, file, option, menu and break is BOTH a Clarion structure and a
    !               StringTheory method, so `st.queue()` would open a level that nothing closes
    !               and every scope below it would sit one level too deep.
    !   POSITION    A declaration keyword only ever stands at token 1 of its statement, or at
    !               token 2 straight after a label in column 1. Anywhere else it is a NAME being
    !               read: `CASE Option`, `IF NOT Option`, `RETURN Window` end a line with the word
    !               just as a declaration does, and opening a level there leaves every scope below
    !               it one level too deep. stmtTok and stmtLbl carry the position.
    prevStrIx = 0
    ! AN OPERATOR IN FRONT OF THE WORD MEANS IT IS BEING READ, NOT DECLARED. A declaration
    ! puts a structure keyword at the start of its line or straight after a label, never after
    ! an operator or an '='. Several of these words are ordinary variable names as well -
    ! `Tab`, `Option`, `Menu`, `Report`, `Window` - so `x = Tab` at the end of a line offers
    ! the same shape a declaration does (keyword, then end of line) and would open a level
    ! nothing ever closes. Everything below it would sit one level too deep, which makes the
    ! balance guards refuse and leaves the type registry short of scopes: silent missed
    ! transforms, the same symptom the method-call exclusion below guards against. Testing
    ! the whole operator table also covers the '&' of `grp &GROUP`.
    if self.Tokens.Type = vt:reservedWord and ~parenDep                                |
       and prevCh <> ',' and prevCh <> '.' and prevCh <> '='                           |
       and ~self.operator[val(prevCh)+1]
      case upper(self.Tokens.tok)
      of   'INTERFACE' orof 'VIEW'        orof 'JOIN'    orof 'REPORT'                 ! declaration words
      orof 'HEADER'    orof 'FOOTER'      orof 'DETAIL'  orof 'FORM'
      orof 'OLE'                                                                       ! see the census note below
      orof 'WINDOW'    orof 'APPLICATION' orof 'QUEUE'   orof 'GROUP'                  ! and the window, data
      orof 'FILE'      orof 'RECORD'      orof 'CLASS'   orof 'ITEMIZE'                !   and control structures, which
      orof 'MENUBAR'   orof 'MENU'        orof 'TOOLBAR' orof 'SHEET'   orof 'TAB'     !   have the identical exposure
      orof 'OPTION'    orof 'MODULE'
        if stmtTok = 1 or stmtTok = 2 and stmtLbl then prevStrIx = x.
        if mapDep and upper(self.Tokens.tok) <> 'MODULE' then prevStrIx = 0.
        prevStrCall = choose(inCode and stmtTok = 1)
      end
    end
    ! OLE takes an END, so it must appear in BOTH lists. Absent from them,
    ! TokenIsReservedWord returns FALSE and it types as a plain label.
    ! PROVED, not reasoned - a fixture holding one gives
    !     exptk level census +6 -7  [UNBALANCED]        1 unmatched close(s)
    !     closes nothing: END at expanded line 38, token 157
    ! with the dump showing ` bF  32-OLE` where SHEET and TAB above it show `+rF`. The OLE's own
    ! END then closes the TAB, and EVERY structure below it shuts one level early, leaving the
    ! WINDOW's END closing nothing. Symptom to recognise elsewhere: the type registry warns
    ! `scan ended unbalanced: depth -1`, i.e. a whole window's worth of scope silently wrong.
    ! reservedWords and this list must stay in step with the full set of END-taking Clarion
    ! structures - a word missing from either is this same bug waiting to happen.
    ! `Window` is the Clarion template's default LABEL for a window, so
    ! `Window{PROP:Text} = 'x'` carries exactly the same hazard as `Report`, so WINDOW takes
    ! the same test as the report words, and so does every other declaration structure.
    ! Treating the two sets differently would guard the rarer case and leave the commoner
    ! one.
    !
    ! THE CODE STRUCTURES ARE EXCLUDED ON PURPOSE, and this is what makes the rule safe:
    !     IF ~p          CASE EVENT()        LOOP i = 1 TO 3        EXECUTE n
    ! each is followed by an EXPRESSION, never by ',' '(' or EOL, so requiring declaration
    ! position would stop them opening at all and unbalance every procedure in existence.
    ! Only DATA and CONTROL structures take the test - they are the ones always followed by
    ! attributes, a parent/file in parentheses, or nothing.
    ! ACCEPT, BEGIN and MAP are also left out: they are followed by EOL anyway, so the test
    ! would pass trivially and there is nothing to gain by widening the blast radius.

    ! MODULE is BOTH a structure and an ATTRIBUTE. Inside a MAP a MODULE structure always
    ! STARTS a statement; as an attribute it always follows a comma, as in
    !     sigTool  CLASS,TYPE,MODULE('sigtool.clw')   ... END
    ! which must open ONE level, not two. That is the whole distinction, and it needs the
    ! previous token - which is why prevCh is kept here in the walk and tested at the promotion.
    prevCh = choose(size(self.Tokens.tok) = 1, self.Tokens.tok, ' ')                   ! for the NEXT iteration


    if size(self.Tokens.tok) = 1
      if self.Tokens.tok = '.'
        self.Tokens.Type = vt:dot
        currType = vt:dot
        put(self.tokens)
      end
    elsif upper(self.Tokens.tok) = 'END'
      currType = vt:end
      self.Tokens.Type = vt:end
      self.Tokens.Level = '-'
      put(self.tokens)
      if mapDep then mapDep -= 1.
    end

    if prevType <> vt:dot then cycle.

    if (not self.Tokens.strBefore &= NULL)                                             ! there is ws after the dot
      prevIsEnd = TRUE
      if self.Tokens.strBefore[1] = '|' then prevIsEnd = false.                        ! but a '|' straight after it continues a NAME (G.| over qty)
    else
      if size(self.tokens.tok) = 1
        case val(self.Tokens.tok)
        of 46 orof 59 orof 10                                                          ! '.' orof ';'
          prevIsEnd = TRUE
        else
          prevIsEnd = false
        end
      else
        prevIsEnd = false
      end
    end

    if prevIsEnd
      get(self.tokens,x-1)                                                             ! do NOT use setTok here as it will set type
      self.Tokens.Type = vt:end
      self.Tokens.Level = '-'
      put(self.tokens)
      if mapDep then mapDep -= 1.
    end
  end                                                                                  !loop

  ! the END-promotion above fires on the iteration AFTER a '.', driven by the
  ! following token. A '.' terminator at true EOF (a file with no trailing newline) has no
  ! following token, so it is never promoted and stays vt:dot -> its structure/IF '+' level
  ! is left unbalanced. Resolve the trailing dot here (at EOF a lone '.' is always a terminator).
  x = records(self.tokens)
  if x
    get(self.tokens, x)
    if ~errorcode() and ~(self.tokens.tok &= NULL)
      if size(self.tokens.tok) = 1 and self.tokens.tok = '.' and self.tokens.type = vt:dot
        self.tokens.type  = vt:end
        self.tokens.level = '-'
        put(self.tokens)
      end
    end
  end

  self.SetLineNumbers()

  !self.traceIt = true
  ! set the data type for variables - read backwards - just set those we are interested in
  loop x = self.records() to 1 by -1
    get(self.tokens,x)
    if self.Tokens.firstOnLine and self.BufColOne() and self.tokens.type = vt:label
      !if decln[1] = '&' then decln = decln[2 : size(decln)].
      decln = upper(decln)
      if decln[1 : 12] = 'STRINGTHEORY'
        self.tokens.varType = vt:StringTheory
      elsif decln[1 : 6] = 'STRING' and (decln[7] = '(' or decln[7] = ' ')
        self.tokens.varType = vt:String
      elsif decln[1 : 7] = 'CSTRING' and (decln[8] = '(' or decln[8] = ' ')
        self.tokens.varType = vt:CString
      elsif decln[1 : 7] = 'PSTRING' and (decln[8] = '(' or decln[8] = ' ')
        self.tokens.varType = vt:PString
      elsif decln[1 : 7] = 'ASTRING' and (decln[8] = '(' or decln[8] = ' ')
        self.tokens.varType = vt:AString
      elsif decln[1 : 4] = 'LONG' or decln[1 : 6] = 'SIGNED' or decln[1 : 8] = 'UNSIGNED'
        self.tokens.varType = vt:Long
      elsif decln[1 : 4] = 'BYTE'
        self.tokens.varType = vt:Byte
      elsif decln[1 : 4] = 'REAL'
        self.tokens.varType = vt:Real
      elsif decln[1 : 7] = 'DECIMAL'
        self.tokens.varType = vt:Decimal
      elsif decln[1 : 5] = 'ULONG'
        self.tokens.varType = vt:ULong
      elsif decln[1 : 5] = 'SHORT'
        self.tokens.varType = vt:Short
      elsif decln[1 : 6] = 'USHORT'
        self.tokens.varType = vt:UShort
      elsif decln[1 : 9] = 'PROCEDURE'
        self.tokens.varType = vt:Procedure
      elsif decln[1 : 7] = 'ROUTINE'
        self.tokens.varType = vt:Routine
      elsif decln[1 : 5] = 'GROUP'
        self.tokens.varType = vt:Group
      elsif decln[1 : 5] = 'CLASS'
        self.tokens.varType = vt:Class
      elsif decln[1 : 3] = 'ANY'
        self.tokens.varType = vt:Any
      elsif decln[1 : 5] = 'QUEUE'
        self.tokens.varType = vt:Queue
      elsif decln[1 : 6] = 'EQUATE'
        self.tokens.varType = vt:Equate
      elsif decln[1 : 8] = 'PDECIMAL'
        self.tokens.varType = vt:PDecimal
      elsif decln[1 : 4] = 'LIKE'
        self.tokens.varType = vt:Like
      elsif decln[1 : 4] = 'FILE'
        self.tokens.varType = vt:File
      elsif decln[1 : 4] = 'VIEW'
        self.tokens.varType = vt:View
      elsif decln[1 : 3] = 'KEY'
        self.tokens.varType = vt:Key                                                   ! KEY has a type of its own
      elsif decln[1 : 4] = 'BLOB'
        self.tokens.varType = vt:Blob
      elsif decln[1 : 4] = 'MEMO'
        self.tokens.varType = vt:Memo
      elsif decln[1 : 4] = 'DATE'
        self.tokens.varType = vt:Date
      elsif decln[1 : 4] = 'TIME'
        self.tokens.varType = vt:Time
      elsif decln[1 : 6] = 'WINDOW'
        self.tokens.varType = vt:Window
      elsif decln[1 : 5] = 'SREAL'
        self.tokens.varType = vt:SReal
      elsif decln[1 : 7] = 'BFLOAT4'
        self.tokens.varType = vt:BFloat4
      elsif decln[1 : 7] = 'BFLOAT8'
        self.tokens.varType = vt:BFloat8
      else
        self.traceIt('tok ' & x & '-' & self.tokens.tok & ' has declaration ' & decln)
        !cycle
        self.tokens.varType = '?'                                                      ! generally a class other than StringTheory
      end
      put(self.tokens)
      self.Vars.varName = upper(self.tokens.tok)
      get(self.vars,+self.vars.varName)
      if errorcode()
        self.vars.varTypes = self.tokens.varType                                       ! note this will take one char and clear the rest
        add(self.vars,+self.vars.varName)
        cycle
      end
      if self.vars.varTypes = self.tokens.varType then cycle.                          ! already there with same type
      z = st.findChars(self.tokens.varType, 1,, self.vars.varTypes)                    ! do we already have one like this?
      case z
      of 0
        self.vars.varTypes = self.tokens.varType & self.vars.varTypes                  ! put new type in position 1
        put(self.vars)
      of 1
        ! all good - is in first position
      else
        ! move to first position as we are reading backwards and want types to be in the order first declared in the file
        tempST.setValue(self.vars.varTypes)
        tempST.removeChars(self.tokens.varType)
        tempST.Prepend(self.tokens.varType)
        self.vars.varTypes = tempST.GetValue()
        put(self.vars)
      end
!      ! put warning that var has been used with different types
!      self.appendStrBefore(self.FindLastTokNumOnLine(self.tokens.lineNo,x), |
!             ' ! #Warning! this name has previously been used for a different type and may limit transformations')
    else
      if self.tokens.tok <> '&' then decln = self.tokens.tok.                          ! do not include '&' on reference vars
    end
  end
  self.traceIt = false

  self.CheckLevels()                                                                   ! check levels do not go negative



! ---- IS THIS `OMIT` THE DIRECTIVE, OR A METHOD THAT SPELLS IT? -------------------------------
! The machine above fires on any four-character token reading OMIT and then wants '(' , a
! literal, ')'. A METHOD CALL is exactly that shape - `x.Omit('**zz**')` - and the tokenizer
! leaves a method's dot as its own token, because the label merge is suppressed before a '('.
! Untested, the call would enter the machine and COMMIT whenever that literal's text appears
! again anywhere later in the file: everything between would be swallowed into leading trivia
! as omitted code. Not a missed conversion - the statements in the gap would never become tokens
! at all, so every pass after it would reason about a file with a hole in it, and nothing would
! say a word. The same file with only the method's NAME changed - `x.Skip(...)` - would keep
! the following statement; `x.Omit(...)` would lose it.
! A directive is never a member, so the test is the token before it. The MERGED spelling needs
! no test - `x.Omit` is one token and does not read as OMIT at all - and ':' cannot appear here,
! because the colon spelling substitutes for a member dot on every structure EXCEPT a CLASS, and
! only a class has methods.
OmitIsDirective routine
  data
odN long,auto
  code
  omitDir = 1
  odN = records(self.tokens)
  if odN < 2 then exit.
  get(self.tokens, odN - 1)
  if ~errorcode() and not self.tokens.tok &= NULL
    if self.tokens.tok = '.' then omitDir = 0.
  end
  get(self.tokens, odN) ! restore the buffer AddToken just wrote

! ---- the literal just added is the terminator of an OMIT or COMPILE directive when the two
!      tokens in front of it are the directive word and its '('. The pre-processor ends the block
!      at the first line that CONTAINS the terminator, byte for byte - so one that ends in a blank
!      or a tab is remembered, and ClipLines leaves the tail of a line holding it alone, or the
!      block would run on past its end in the clipped file. The simple OMIT is swallowed by the
!      state machine below and remembers its own terminator there; this is for a COMPILE, and for
!      an OMIT with a condition, whose block is tokenised. A method that spells one of the two
!      words can only add a string nothing will match: a line kept wide, never a wrong clip.
!      A directive that starts its statement - after a line break or a ';', where the pre-processor
!      takes one - also puts its terminator on termStk, so that TermFold can find the line that
!      ends the block. The rest of the directive's own line after its closing ')' is searched
!      first: measured, a terminator in its comment ends the block on that line, so nothing is
!      put on termStk. The condition is not searched: measured, COMPILE('End', EndIt = 1) keeps
!      its block open. When the ')' is not on this line - a '|' or a '!' comes first - nothing
!      on it is searched, and the rows after it are searched as continuation rows (TermCont).
!      A method call never starts its statement with the word, so it puts nothing there. ----
PpTermNote routine
  data
ptN   long,auto
ptDir long
ptBeg long
ptEol long,auto
ptAt  long
ptZ   long,auto
ptDep long,auto
ptQ   byte
ptLit StringTheory
  code
  ptN = records(self.tokens)
  if ptN < 3 then exit.
  get(self.tokens, ptN - 1)
  if ~errorcode() and not self.tokens.tok &= NULL
    if self.tokens.tok = '('
      get(self.tokens, ptN - 2)
      if ~errorcode() and not self.tokens.tok &= NULL
        case upper(self.tokens.tok)
        of 'OMIT' orof 'COMPILE'
          ptDir = 1
          ptBeg = 1
          if ptN > 3
            get(self.tokens, ptN - 3)
            if ~errorcode() and not self.tokens.tok &= NULL
              if self.tokens.tok <> '<10>' and self.tokens.tok <> ';' then ptBeg = 0.
            end
          end
        end
      end
    end
  end
  get(self.tokens, ptN) ! restore the buffer AddToken just wrote
  if ~ptDir then exit.
  ptLit.setValue(tok)
  ptLit.unquote('''')
  if ~ptLit._DataEnd then exit.
  if ptLit.valuePtr[ptLit._DataEnd] = ' ' or ptLit.valuePtr[ptLit._DataEnd] = '<9>' then self.ppTerms.addLine(ptLit.getValue()).
  if ptBeg
    ptEol = st.findByte(10, pos)
    if ~ptEol then ptEol = st._DataEnd + 1.
    ptDep = 1
    loop ptZ = pos to ptEol - 1
      case val(st.valuePtr[ptZ])
      of 39
        ptQ = 1 - ptQ
      of 40
        if ~ptQ then ptDep += 1.
      of 41
        if ~ptQ then ptDep -= 1.
        if ~ptDep then ptAt = ptZ + 1 ; break.
      of 33 orof 124
        if ~ptQ then break.
      end
    end
    if ptAt and ptAt < ptEol
      ptAt = st.findChars(ptLit.getValue(), ptAt)
      if ptAt and ptAt < ptEol then ptBeg = 0.
    end
  end
  if ptBeg then termStk.addLine(ptLit.getValue()).

! ---- THE LINE THAT ENDS A COMPILE BLOCK, OR AN OMIT WITH A CONDITION. The pre-processor ends
!      such a block at the first line that holds its terminator, byte for byte. Measured, the
!      search starts on the directive's own line: a terminator in that line's comment ends the
!      block there, and the lines below it are code. A line that holds the terminator in front
!      of any comment belongs to the directive and is not code. Read as code, a terminator
!      spelled with a word - `**END**`, `END***`, `End of include` - would give the word a level,
!      so the line would close the structure the block sits in and every scope below it would
!      sit one level too shallow; inside a CLASS, the methods after it would be read as
!      procedures of their own.
!      PpTermNote has searched the directive's own line. So at the start of each line after it,
!      while such a block is open, the line is searched for the terminator of the innermost one,
!      byte for byte, as the pre-processor searches it. Found in front of any comment, the whole
!      line goes into the trivia ahead of the next line, as a plain OMIT block does, and its
!      words open and close nothing; the output is unchanged. Found only in a comment, the block
!      ends with that line, and code in front of the comment is read as code: measured, it is in
!      the build exactly when its block is. A line that holds the terminator of an OUTER open
!      block ends that block and every one inside it, and stays code: an inner directive the
!      compiler never read, because it stood in a block that was skipped, cannot close anything.
!      On entry pos is the first byte of a line; each folded line moves it to the next one. ----
TermFold routine
  data
tfEol  long,auto
tfZ    long,auto
tfK    long,auto
tfAt   long,auto
tfQ    byte,auto
tfLn   StringTheory
  code
  loop while termStk.records() and pos <= st._DataEnd
    tfEol = st.findByte(10, pos)
    if ~tfEol then tfEol = st._DataEnd + 1.
    if tfEol = pos then break.
    tfLn.setValue(st.slice(pos, tfEol - 1))
    tfK = 0
    loop tfZ = termStk.records() to 1 by -1
      if tfLn.findChars(termStk.getLine(tfZ)) then tfK = tfZ ; break.
    end
    if ~tfK then break.
    if tfK < termStk.records()
      loop while termStk.records() >= tfK
        termStk.deleteLine(termStk.records())
      end
      break
    end
    tfQ = 0
    loop tfZ = 1 to tfLn._DataEnd
      if tfLn.valuePtr[tfZ] = '''' then tfQ = 1 - tfQ.
      if tfLn.valuePtr[tfZ] = '!' and ~tfQ then break.
    end
    tfAt = 0
    if tfZ > 1
      tfLn.setLength(tfZ - 1)
      tfAt = tfLn.findChars(termStk.getLine(tfK))
    end
    termStk.deleteLine(tfK)
    if ~tfAt then break.
    if state <> 4 then strBefore.free().
    strBefore.append(st.slice(pos, tfEol - 1))
    if tfEol > st._DataEnd
      pos = st._DataEnd + 1
    else
      strBefore.append('<13,10>')
      pos = tfEol + 1
    end
    state = 4
  end

! ---- A CONTINUATION ROW IS A LINE OF ITS OWN to the pre-processor, which ends an open block at
!      the first line that holds its terminator, byte for byte. GetNextToken reads the row after
!      a '|' as part of the statement it continues and adds no line end in front of it, so
!      TermFold never sees it; GetNextToken does this at the start of each such row instead. A
!      row that holds the terminator of an open block ends that block and every one inside it.
!      Its text stays code, wherever on it the terminator is: the statement it continues goes on
!      on it, and folding the row away would cut that statement in two. On entry pos is the line
!      feed in front of the row ----
TermCont routine
  data
tcEol  long,auto
tcZ    long,auto
tcK    long
tcLn   StringTheory
  code
  if pos >= st._DataEnd then exit.
  tcEol = st.findByte(10, pos + 1)
  if ~tcEol then tcEol = st._DataEnd + 1.
  if tcEol = pos + 1 then exit.
  tcLn.setValue(st.slice(pos + 1, tcEol - 1))
  loop tcZ = termStk.records() to 1 by -1
    if tcLn.findChars(termStk.getLine(tcZ)) then tcK = tcZ ; break.
  end
  if ~tcK then exit.
  loop while termStk.records() >= tcK
    termStk.deleteLine(termStk.records())
  end

AddToken routine
  if Tok._DataEnd
    self.tokens.tok &= new string(tok._DataEnd)
    self.tokens.tok = tok.valueptr[1 : tok._DataEnd]
  else
    self.tokens.tok &= NULL
  end
  if strBefore._DataEnd
    self.tokens.strBefore &= new string(strBefore._DataEnd)
    self.tokens.strBefore = strBefore.valueptr[1 : strBefore._DataEnd]
  else
    self.tokens.strBefore &= NULL
  end
  self.TokenType() ! sets self.tokens.type
  Add(self.Tokens)
!? assert(~errorcode())


GetNextToken routine
! find next token - we treat space/tab as whitespace - pos has position and we return token and advance pos to next unconsumed char

! self.TraceIt('entering GetNextToken at position ' & pos & ' ' & self.DescribeChar(St.sub(pos)) & ' Continuation='&inContinuation)
  tok.free()
  if ~state then strBefore.free().                                     ! we do NOT free if in OMIT
  inComment = false
  inQuotes = false
!  startPos = pos

  loop pos = pos to st._DataEnd                                        ! skip of initial spaces and tabs
    case val(st.valueptr[pos])
    of 32  orof 9                                                      ! space or tab
      strBefore.append(st.valueptr[pos])
    of 124                                                             ! '|'
      strBefore.append(st.valueptr[pos])
      inContinuation = true
    else
      if ~inContinuation then break.
      ! in continuation so just treat as comment until new line
      if st.valuePtr[pos] = '<10>'                                     ! EOL - end of line
        strBefore.append('<13,10>')                                    ! with continuation we store CRLF as part of the "before token" string
        inContinuation = false
        inPicture      = 0                                             ! the other place a newline is consumed - a picture dies at one either way
        picEsc         = 0
        if termStk.records() then do TermCont.
      else
        strBefore.append(st.valueptr[pos])
      end
    end
  end

  loop pos = pos to st._DataEnd
!?   self.TraceIt('at pos ' & pos & ' ' & self.DescribeChar(st.valuePtr[pos]) )
    if st.valuePtr[pos] = '<10>'                                       ! EOL - end of line
      inPicture = 0                                                    ! a picture never spans a physical line, so an unclosed one dies here
      picEsc    = 0
      if ~tok._DataEnd
        tok.setvalue('<10>')
        pos += 1
      end
      break
    elsif inComment
      strBefore.append(st.valueptr[pos])
    elsif inquotes
      if st.valuePtr[pos] = ''''                                       ! endquote
        inquotes = false
      end
      tok.append(St.valuePtr[pos])
      if ~inquotes                                                     ! a closing quote that is not doubled ENDS the
        if pos = st._DataEnd or st.valuePtr[pos+1] <> ''''             !   literal: a word written straight after it,
          pos += 1                                                     !   as in 'y'or, is a token of its own
          break
        end
      end
    elsif st.valuePtr[pos] = '|' and ~inPicture                        ! continuation ('|' inside @K is the documented "stop here" indicator)
      if ~tok._DataEnd
        tok.setvalue('|')
        pos += 1
      end
      inContinuation = true
      break
    elsif st.valuePtr[pos] = '!' and ~inPicture
      if tok._DataEnd
        break                                                          ! end of token
      else
        inComment = true
        strBefore.append(st.valueptr[pos])
      end
    elsif st.valuePtr[pos] = '''' and ~inPicture                       ! startquote (a quote inside @P is an edit char - LRM p157's own example)
      inquotes = true
      tok.append(st.valuePtr[pos])
    elsif self.SeparatorA[val(st.valuePtr[pos])+1]
      if ~tok._DataEnd
        if self.stopIt
          self.TraceIt('error in vitTokenize.parseText - unexpected white space at position' & pos & |             ! The 'cycle'
             choose(~omitted(pFilename),' in ' & clip(pFilename),'')                               & |             ! below recovers by skipping the char, so this is
             '<13,10,13,10>character is [' & st.valuePtr[pos] &'] in:<13,10,13,10>' & self.GetCurrentLine(st,pos)) ! only a debug assertion.
        end
        cycle                                                          ! skip initial whitespace - should NOT happen as skipped ws at top
      else
        break
      end
    elsif self.Delimiter[val(st.valuePtr[pos])+1]
      if ~tok._DataEnd
        tok.append(st.valuePtr[pos])
        pos += 1
        ! `=<` and `=>` are DOCUMENTED spellings of `<=` and `>=` (LRM p528's combined
        ! operator table lists both pairs). '=' is a delimiter, not an operator, so it never
        ! reaches the two-character merge below, and without this those two are two tokens.
        if st.valuePtr[pos-1] = '=' and pos <= st._DataEnd
          case val(st.valuePtr[pos])
          of 60 orof 62                                                ! '<<' orof '>'
            tok.append(st.valuePtr[pos])
            pos += 1
          end
        end
      end
      break
    elsif self.Operator[val(st.valuePtr[pos])+1]
      if ~tok._DataEnd
        tok.append(st.valuePtr[pos])
        pos += 1
        if pos <= st._DataEnd
          if st.valuePtr[pos] = '='                                 or |       ! two-char operators: '+=' '~=' '<<=' '>=' ...
             (st.valuePtr[pos-1] = '<<' and st.valuePtr[pos] = '>') or |       ! '<<>'
             (st.valuePtr[pos-1] = '~'                             and |       ! '~<' and '~>' are documented
              (st.valuePtr[pos] = '<<' or st.valuePtr[pos] = '>'))     !   spellings of "not less" / "not greater"
            tok.append(st.valuePtr[pos])
            pos += 1
          end
        end
      end
      break
    else
      tok.append(st.valuePtr[pos])
      do PictureTrack
    end
  end
! self.TraceIt('leaving GetNextToken at position ' & pos & ' with tok = ' & tok.GetValue())

! ---- track whether we are inside a DELIMITED picture token ----
!      The LRM is explicit that a picture may contain the very characters that switch the
!      lexer's mode. @P: "Any character other than < or # is considered an edit character",
!      and its own example list at p157 includes  @P<#' <#"P  - a single quote. @K lists '|'
!      in its syntax line as the "stop here" indicator, and '\' as an escape. So while a
!      picture is open those three are CONTENT, and the branches above stand down.
!      Only the delimited forms (@P..P, @K..K) are tracked, because only they have a defined
!      end - and only they can legally contain whitespace, so only they need to survive past
!      the token boundaries the delimiter/operator rules impose. The delimiters are CASE
!      SENSITIVE, which is what lets `@p<#:##PMp` carry an upper-case P as an edit character;
!      picClose keeps the opener's own case for exactly that.
!      State is per LINE (cleared at EOL above), so a malformed picture cannot leak.
!      (dataless routine -> no CODE statement)
PictureTrack routine
  if ~inPicture
    if tok._DataEnd = 2 and tok.valuePtr[1] = '@' and (upper(tok.valuePtr[2]) = 'P' or upper(tok.valuePtr[2]) = 'K')
      inPicture = 1
      picClose  = tok.valuePtr[2]   ! same case as the opener - the LRM requires the pair to match
      picEsc    = 0
    end
  elsif picEsc
    picEsc = 0                      ! this char was escaped by '\' - never the closing delimiter
  elsif st.valuePtr[pos] = '\' and upper(picClose) = 'K'
    picEsc = 1                      ! @K only: the NEXT character is a display character
  elsif st.valuePtr[pos] = picClose
    inPicture = 0
  end

! ------------------------------------------------------------------------------------
VitTokenize.FindFirstTokOnLine Procedure(LONG pLineNumber) !,LONG,virtual ! returns tokNumber
  code
  self.Tokens.lineNo = pLineNumber
  get(self.tokens,self.Tokens.lineNo)
  if errorcode()
    return 0
  elsif self.Tokens.firstOnLine
    return pointer(self.Tokens)
  else
    self.TraceIt('Error found in FindFirstTokOnLine - Token ' & pointer(self.Tokens) & ' = ' & self.tokens.tok & ' not marked as first on line ' & pLineNumber)
    return 0
  end

! ------------------------------------------------------------------------------------
! the following is not used or tested - kept as it may be of use
!VitTokenize.FindLastTokOnLine Procedure(LONG pLineNumber) !,LONG,virtual ! returns tokNumber
!  code
!  self.Tokens.lineNo = pLineNumber + 1
!  get(self.tokens,self.Tokens.lineNo)
!  if errorcode()
!    return records(self.tokens) ! return last entry in queue
!  elsif self.Tokens.firstOnLine
!    get(self.tokens, pointer(self.Tokens) - 1) ! subtract 1 to get last token on previous line
!    if self.Tokens.lineNo <> pLineNumber
!      stop('Error found in FindLastTokOnLine - Token ' & pointer(self.Tokens) & ' = ' & self.tokens.tok & |
!           ' is on line ' & self.Tokens.lineNo & ' not ' & pLineNumber)
!      return 0
!    else
!      return pointer(self.Tokens)
!    end
!  else
!    stop('Error found in LastFirstTokOnLine - Token ' & pointer(self.Tokens) & ' = ' & self.tokens.tok & ' not marked as first on line ' & pLineNumber)
!    return 0
!  end

! ------------------------------------------------------------------------------------
VitTokenize.SetLineNumbers Procedure ! set or update line numbers in self.tokens queue
x      long,auto
ln     long(1)                       ! line number
prevLn long
slnX   long,auto                     !
slnT0  long,auto                     ! --timing
  code
  slnT0 = clock()
  if self.mapOn then self.MapFold().                          ! compose the preview line map BEFORE the restamp erases the old coordinates
  free(self.noteQ)                                            ! a rule has finished firing: its notes are placed, so the registry that ordered them is done
  ! set line numbers in the queue - we check for <10> token and also in strBefore
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() then break.                                ! no more tokens. NOT `or self.Tokens.tok &= NULL then break`: the last line
                                                              !   can hold a token with a NULL tok (a last line of only spaces), and it still counts
    if not self.Tokens.strBefore &= NULL
      loop slnX = 1 to size(self.Tokens.strBefore)            ! count LF bytes directly - an ST setValue+count here allocates per token on a hot post-edit pass
        if self.Tokens.strBefore[slnX] = '<10>' then ln += 1.
      end
    end
    self.Tokens.lineNo = ln
    if ln <> prevLn
      prevLn = ln
      self.tokens.firstOnLine = true
      ! a reserved word in column 1 is an identifier - a label. BufColOne sees column 1 through a folded OMIT block.
      if self.Tokens.type = vt:reservedWord and self.BufColOne() then self.TokenType().
    else
      self.tokens.firstOnLine = false
    end
    put(self.Tokens)
    if size(self.tokens.tok) = 1 and self.tokens.tok = '<10>' then ln += 1.
  end
  slnX = clock() - slnT0                                      ! --timing, across midnight
  if slnX < 0 then slnX += 8640000.
  self.nLineNums += 1 ; self.tLineNums += slnX

! ------------------------------------------------------------------------------------
! (the preview LINE MAP). lineMap holds, for every line of the text as of the
! LAST lineNo stamp, the ORIGINAL source line it descends from. MapInit sizes it as
! identity from the current stream; MapFold composes it across an edit pass: after
! rewrites the stream carries a NEW line structure (LF tokens + LF bytes inside
! strBefore - the SAME two carriers SetLineNumbers counts) while every surviving token
! still holds its OLD lineNo, so one walk yields (newLine, oldLine) pairs and
! lineMap2[newLine] = lineMap[oldLine] is the composition. MapFold MUST therefore run
! BEFORE anything restamps lineNo: SetLineNumbers calls it first when mapOn is armed,
! and VitEngine.RejoinReparse calls it before the re-lex frees the tokens. Tokens
! inserted by rewrites can carry zero/stale lineNo - the monotone clamp heals them
! (line order is never reordered by rules). Lines that own no token (comment/blank
! lines riding in a strBefore) distribute backwards from their carrier token. Armed
! ONLY by the preview (VitEngine.TransformText); TransformFile/CLI never calls
! MapInit, so batch runs skip all of this at a single IF per renumber.
! ------------------------------------------------------------------------------------
VitTokenize.MapInit Procedure
x     long,auto
slnX  long,auto
ln    long(1)
  code
  self.mapOn = 0
  free(self.lineMap)
  loop x = 1 to records(self.tokens) ! line count by the SetLineNumbers rule
    get(self.tokens,x)
    if errorcode() then break.
    if not self.Tokens.strBefore &= NULL
      loop slnX = 1 to size(self.Tokens.strBefore)
        if self.Tokens.strBefore[slnX] = '<10>' then ln += 1.
      end
    end
    if size(self.tokens.tok) = 1 and self.tokens.tok = '<10>' then ln += 1.
  end
  loop x = 1 to ln                   ! identity: line x came from source line x
    self.lineMap.srcLn = x
    add(self.lineMap)
  end
  self.mapOn = 1

! ------------------------------------------------------------------------------------
VitTokenize.MapFold Procedure
x       long,auto
slnX    long,auto
slnX2   long,auto
ln      long(1)   ! new-structure line of the token in hand
mapped  long      ! last new line already given a map entry
lastOld long(1)   ! monotone floor for old lineNo readings
oldLn   long,auto
j       long,auto
oj      long,auto
nOld    long,auto
lk      long,auto ! survivor lookahead cursor
brk     long,auto ! lookahead hit the next line's strBefore LF
  code
  if ~self.mapOn then return.
  nOld = records(self.lineMap)
  if ~nOld then return.
  free(self.lineMap2)
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() then break.
    if not self.Tokens.strBefore &= NULL
      loop slnX = 1 to size(self.Tokens.strBefore)
        if self.Tokens.strBefore[slnX] = '<10>' then ln += 1.
      end
    end
    if ln > mapped                                                              ! first token to land on new line ln
      oldLn = self.Tokens.lineNo
      if oldLn < lastOld                                                        ! zero/stale line HEAD. InsertString clears lineNo, so a rule
        oldLn = 0                                                               ! whose match STARTS the line (`if s = '' ==> if ~s`) leaves
        lk = x                                                                  ! head tokens with lineNo 0 at fold time, which map the line to its
        loop                                                                    ! PREDECESSOR (the preview shows the wrong line). The unreplaced
          get(self.tokens, lk)                                                  ! tail / EOL token still carries the TRUE old line - find a SURVIVOR
          if errorcode() then break.                                            ! on the SAME new line before falling back to the carry.
          if lk > x and not self.Tokens.strBefore &= NULL
            brk = 0                                                             ! a later token whose strBefore holds an LF starts the NEXT line
            loop slnX2 = 1 to size(self.Tokens.strBefore)
              if self.Tokens.strBefore[slnX2] = '<10>' then brk = 1 ; break.
            end
            if brk then break.
          end
          if self.Tokens.lineNo >= lastOld
            oldLn = self.Tokens.lineNo                                          ! survivor found (the EOL token always survives an in-line rewrite)
            break
          end
          if size(self.tokens.tok) = 1 and self.tokens.tok = '<10>' then break. ! line closed - no survivor
          lk += 1
        end
        if ~oldLn then oldLn = lastOld.                                         ! fully-inserted line (multi-line replacement): carry
        get(self.tokens, x)                                                     ! restore the walk's queue buffer
      end
      if oldLn > nOld then oldLn = nOld.
      loop j = mapped + 1 to ln                                                 ! entries for this token's line + any strBefore interior lines
        oj = oldLn - (ln - j)                                                   ! interior (comment/blank) lines sit just above their carrier
        if oj < lastOld then oj = lastOld.
        get(self.lineMap, oj)
        if errorcode() then break.
        self.lineMap2.srcLn = self.lineMap.srcLn
        add(self.lineMap2)
      end
      mapped  = ln
      lastOld = oldLn
    end
    if size(self.tokens.tok) = 1 and self.tokens.tok = '<10>' then ln += 1.
  end
  loop j = mapped + 1 to ln                                                     ! trailing line(s) after the last token (text ending in an LF)
    get(self.lineMap, nOld)
    if errorcode() then break.
    self.lineMap2.srcLn = self.lineMap.srcLn
    add(self.lineMap2)
  end
  free(self.lineMap)                                                            ! lineMap <- lineMap2
  loop j = 1 to records(self.lineMap2)
    get(self.lineMap2, j)
    self.lineMap.srcLn = self.lineMap2.srcLn
    add(self.lineMap)
  end
  free(self.lineMap2)

! ------------------------------------------------------------------------------------
! translate a CURRENT line number to its ORIGINAL source line. Valid at ANY
! instant while mapOn: the fold-at-every-restamp discipline keeps lineMap indexed by
! the same coordinates token lineNo carries, so a line number read from the stream
! translates directly. Identity when the map is off (CLI
! batch: mapOn = 0 -> log line numbers unchanged, reports byte-identical) or out of
! range. Used by the engine's LOG emission so the preview's change log carries SOURCE
! line numbers - the Changes list then needs no after-the-fact remapping at all.
! ------------------------------------------------------------------------------------
VitTokenize.MapLine Procedure(LONG pLn)
  code
  if ~self.mapOn or pLn < 1 or pLn > records(self.lineMap) then return pLn.
  get(self.lineMap, pLn)
  if errorcode() then return pLn.
  return self.lineMap.srcLn

! ------------------------------------------------------------------------------------
VitTokenize.CheckLevels Procedure ! check levels do not go negative: a '-' needs to match an earlier '+'
x     long,auto
lev   long
  code

  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break. ! no more tokens
    case val(self.tokens.level)
    of 43                                                 ! '+'
      lev += 1
    of 45                                                 ! '-'
      if ~lev
        if self.stopIt then stop('warning: mismatched level "-" (end) at token ' & x & ' line: ' & self.tokens.lineNo).
      else
        lev -= 1
      end
    end
  end

! ------------------------------------------------------------------------------------
VitTokenize.TokenIsAllDigits  Procedure()                 !,LONG,virtual
x           long,auto
 code
  loop x = 1 to size(self.tokens.tok)
    case val(self.tokens.tok[x])
    of 48 to 57 ! 0 to 9
      !cycle
    else
      return FALSE
    end
  end
  return TRUE

! ------------------------------------------------------------------------------------
! TRUE only for a token that is digits with EXACTLY ONE decimal point in it.
!
! A plain integer answers FALSE - it has no point - so this is a test for "numeric WITH a
! decimal part", not for "is a number". Two points, any non-digit, or fewer than two
! characters all answer FALSE.
! ------------------------------------------------------------------------------------
VitTokenize.TokenIsDecimal  Procedure() !,LONG,virtual
! must have one decimal point and the rest digits
x           long,auto
haveDecPt   long
 code
  if size(self.tokens.tok) < 2 then return FALSE. ! must have at least one digit and dec point
  loop x = 1 to size(self.tokens.tok)
    case val(self.tokens.tok[x])
    of 48 to 57                                   ! 0 to 9
      !cycle
    of 46                                         ! '.'
      if haveDecPt
        return FALSE                              ! cannot have more than one dec pts
      else
        haveDecPt = TRUE
      end
    else
      return FALSE
    end
  end
  return haveDecPt


! ------------------------------------------------------------------------------------
! TRUE if the current token could be a Clarion identifier.
!
! First character must be a letter or underscore. After that digits, ':' and '_' are all
! allowed - the colon because Clarion equate names are full of them, as in vt:Literal.
!
! A '.' is permitted INSIDE the token so a compound reference like x.y.z stays one label,
! but a TRAILING dot is refused: at the end of a line a dot is a block terminator, not part
! of a name, and treating it as one would swallow the END of a structure.
! ------------------------------------------------------------------------------------
VitTokenize.TokenIsValidLabel  Procedure() !,LONG,virtual
x           long,auto
 code
  if self.tokens.tok &= NULL
    self.traceIt('ERROR: called TokenIsValidLabel() with NULL token')
    return FALSE
  end

  case val(self.tokens.tok[1])
  of   65 to 90                  ! A-Z
  orof 97 to 122                 ! a-z
  orof 95                        ! '_'
    ! first char OK
  else
    return FALSE                 ! first character invalid
  end

  ! characters 2 to end can also have digit or colon
  loop x = 2 to size(self.tokens.tok)
    case val(self.tokens.tok[x])
    of   48 to 57                ! 0 to 9
    orof 65 to 90                ! A-Z
    orof 97 to 122               ! a-z
    orof 58 orof 95              ! ':' orof '_'
      !cycle
    of   46                      ! '.'
      if x = size(self.tokens.tok)
        return FALSE             ! dot on end not allowed but allow compound x.y.z
      end
    else
      return FALSE
    end
  end
  return TRUE

! ------------------------------------------------------------------------------------
! Is the current token a Clarion reserved word?
!
! COLUMN 1 WINS OVER THE WORD LIST. A token that is first on its line with NO trivia in
! front of it is in column 1, and in Clarion column 1 is where a LABEL goes - so it is
! answered FALSE whatever it spells. That is what lets a variable legitimately called
! `Group` or `Queue` be declared without opening a structure.
!
! Note the test is `strBefore &= NULL`, i.e. no leading whitespace at all, which is exactly
! what SetStrBefore stores for a zero-length value. Anything indented, however little, is
! not in column 1 and is matched against the list normally.
!
! The list is deliberately generous and may name words that are not reserved in every
! context; callers that need certainty about DECLARATION structures use the
! declaration-position test in ParseText rather than this.
! ------------------------------------------------------------------------------------
VitTokenize.TokenIsReservedWord Procedure() !virtual  note: this may include some that are not official Clarion reserved words
 code
  if self.Tokens.firstOnLine and self.BufColOne()
    return FALSE ! if first token on line and in column 1 then it can be an identifier despite using a "reserved word"
  elsif size(self.Tokens.tok) > 1 and instring(' ' & upper(self.tokens.tok) & ' ',reservedWords,1,1)
    return TRUE
  else
    return FALSE
  end

! ------------------------------------------------------------------------------------
! TRUE if the token names a Clarion data type - LONG, STRING, DECIMAL and the rest.
!
! A plain lookup in the dataTypes list, with NO column-1 rule: unlike a reserved word, a
! type name in column 1 is still a type name. This is how the declaration-shaped lines that
! AutoCheck and the aligners work on get recognised.
! ------------------------------------------------------------------------------------
VitTokenize.TokenIsDataType Procedure() !virtual  note: data types that we look to put auto on
 code
  if size(self.Tokens.tok) > 1 and instring(' ' & upper(self.tokens.tok) & ' ',dataTypes,1,1)
    return TRUE
  else
    return FALSE
  end

! ------------------------------------------------------------------------------------
! Classify the current token into self.tokens.type - literal, label, number, operator.
!
! Called by AddTok and SetTok as a token goes in, so type is maintained for you and a caller
! rewriting a token never has to reclassify it by hand.
!
! The level reset at the top is load-bearing and the comment beneath it says why. Do not move
! it below the single-character CASE.
! ------------------------------------------------------------------------------------
VitTokenize.TokenType  Procedure() !virtual
! sets the token type in the current queue buffer
x           long,auto
haveDecPt   long
haveExp     long                   ! an E/e exponent has been seen...
expDigit    long                   !        ...and at least one digit followed it
 code

  ! reset level BEFORE the single-character CASE below, not after it.
  ! Every token shares one queue record buffer, and the single-char arms RETURN early - so a
  ! '+ - * / %% ^ .' token would otherwise INHERIT the previous token's level mark - the '-'
  ! of `return -1` picking up level 'x' from the RETURN, for instance.
  ! A '-' leak only miscounts, but the dangerous case is a '+' leak - `IF -x`,
  ! `LOOP -n TIMES` and `CASE -x` all put a sign straight after a keyword marked '+', which
  ! would give an unmatched OPEN and put every scope below it one level too deep. That is the
  ! same failure a missing OLE entry gives (see ParseText), arriving by a different road.
  self.tokens.level = ' '
  if size(self.Tokens.tok) = 1
    case val(self.Tokens.tok)
    of 43 orof 45                                     ! '+' orof '-'
      self.tokens.type = vt:plusMinus                 !'p'          ! indicates PLUS type (plus or minus)
      return
    of 42 orof 47 orof 37                             ! '*' orof '/' orof '%'
      self.tokens.type = vt:multiplication            !'m'     ! indicates MULTIPLICATION type (* / %)
      return
    of 46                                             ! '.'
      return
    of 94                                             ! '^'       ! ** not sure this is needed given it can only be one specific char not a few diff ones
      self.tokens.type = vt:exponentiation            !'^'     ! indicates EXPONENTIATION type (^)
      return
    end

!--- a quoted literal: it opens and closes with a quote
  elsif size(self.Tokens.tok) > 1 and self.Tokens.tok[1] = '''' and self.Tokens.tok[size(self.Tokens.tok)] = ''''
    self.Tokens.type = vt:Literal                     ! note: vt:Literal is ' rather than L, which reads like Long
    return
  end

  self.tokens.type = ' '                              ! default    set here, after the '.' arm, which leaves its type "as is" so a vt:end value is not lost
  self.tokens.level = ' '                             ! (already cleared above; harmless, and keeps this block readable on its own)
  if self.TokenIsReservedWord()
    self.Tokens.type = vt:reservedWord
    case upper(self.tokens.tok)
    ! ONLY THE CODE STRUCTURES OPEN UNCONDITIONALLY. Each is followed by an
    ! EXPRESSION - `IF ~p`, `CASE EVENT()`, `LOOP i = 1 TO 3`, `EXECUTE n` - so there is no
    ! declaration shape to test for, and none of these words is ever a variable name.
    ! The DATA and CONTROL structures are in the declaration-position test in ParseText's
    ! walk instead: WINDOW QUEUE GROUP FILE RECORD CLASS MODULE ITEMIZE MENUBAR MENU TOOLBAR
    ! SHEET TAB OPTION APPLICATION INTERFACE VIEW JOIN REPORT HEADER FOOTER DETAIL FORM. They
    ! open only when the next token is ',' '(' or EOL, because `Window` and `Report` are the
    ! Clarion template's own default LABELS and `Window{PROP:Text} = 'x'` must not open anything.
    of 'IF'   orof 'CASE' orof 'LOOP' orof 'EXECUTE' orof 'BEGIN' orof 'ACCEPT'
                              self.tokens.level = '+'
    of 'ELSE' orof 'ELSIF'  ; self.tokens.level = '/'
!    of 'END' ;               self.tokens.level = '-'  ! this will be done later as also need to check for '.' end
    of 'EXIT' orof 'RETURN' ; self.tokens.level = 'x' ! exit out of here - any code following in this level block is unreachable
    of 'OF'   orof 'OROF'   ; self.tokens.level = '/'
    of 'MAP'                ; self.tokens.level = '+' ; self.tokens.type = vt:Map
    end
    return
  end

  if self.TokenIsValidLabel()
    self.Tokens.type = vt:label                       ! label  - note l looks too much like I in some fonts so used b
    return
  end

  ! NUMERIC CONSTANTS. Anything reaching here starts with a digit - a Clarion label cannot, and
  ! the label test above has already run - so a leading digit is the licence to read a number.
  ! the exponent form is typed too. `1.5e3` arrives as `1` `.` `5e3` (the '.' is a
  ! delimiter), and with `5e3` falling out of this loop untyped the three could never merge, so
  ! a rule keyed on a numeric type would never see the number at all. Round trip is not at
  ! stake - the bytes are the same either way - so only a missed rewrite would show it.
  ! KNOWN LIMIT: the LRM's other bases - binary `1011b`, octal
  ! `3403o`, hex `0CD1F74FH` (p496) - fall out untyped, because their terminator letters
  ! are ambiguous with hex digits ('B' is both) and telling them apart means deciding the base
  ! from the LAST character before validating the digits. Such a number is left untyped, so a
  ! rule keyed on a numeric type passes it by: a missed rewrite, never a wrong one.
  ! The decimal and exponent forms are typed; see the loop below.
  loop x = 1 to size(self.tokens.tok)
    case val(self.tokens.tok[x])                      ! INDEX the character: val(tok) tests char 1 every iteration, which types 5.5/0FFh as Integer and stops FoldStr on the inconsistency
    of 48 to 57                                       ! 0 to 9
      if haveExp then expDigit = TRUE.                ! the exponent needs at least one digit of its own
    of 46                                             ! '.'
      if haveDecPt or haveExp
        return                                        ! one decimal point only, and never inside the exponent
      else
        haveDecPt = TRUE
      end
    of 69       orof 101                              ! 'E' 'e' - scientific notation
      if haveExp or x = 1 then return.                ! one exponent, and a number never starts with it
      haveExp = TRUE
    else
      return
    end
  end
  if haveExp and ~expDigit then return.               ! `5e` is not a number
  if haveDecPt or haveExp
    self.tokens.type = 'N'
  else
    self.tokens.type = vt:Integer
  end


! ------------------------------------------------------------------------------------
! Rejoin the whole stream and write it to pFileName. JoinToks does the work.
! ------------------------------------------------------------------------------------
VitTokenize.WriteText  Procedure(STRING pFileName)
st          StringTheory
 code
  self.JoinToks(st)
  return st.SaveFile(clip(pFileName))

! ------------------------------------------------------------------------------------
! THE INVERSE OF ParseText: the token stream back into text, strBefore & tok down the
! queue. This overload returns the result; the one below appends into a StringTheory the
! caller owns, which is what you want for a whole file.
!
! This is on EVERY WRITE PATH in the tool - nothing reaches disk, the preview panes or a
! report without coming through here. It is consequently the best single place to prove a
! change is inert: if a change moves nothing in a round trip, JoinToks is the
! reason you can believe it.
! ------------------------------------------------------------------------------------
VitTokenize.JoinToks  Procedure(LONG pStart=1,LONG pEnd=0)
st          StringTheory
 code
  self.JoinToks(st,pStart,pEnd)
  if st._DataEnd
    return st.valueptr[1 : st._DataEnd]
  else
    return ''
  end

! ------------------------------------------------------------------------------------
! Rejoin tokens pStart..pEnd into st. pEnd = 0 means to the end of the stream, and the two
! NEGATIVE values below are line-relative rather than counted back from the end - which is
! the opposite convention to DeleteToks, so do not carry an assumption between them.
!
! Output is CRLF. There is no LF-only mode: LF-only is not valid Clarion, so a file that
! arrives that way is normalised rather than preserved. See VitEngine.TransformFile.
! ------------------------------------------------------------------------------------
VitTokenize.JoinToks  Procedure(StringTheory st,LONG pStart=1,LONG pEnd=0)
! if pEnd = -1 then join to the end of the current line excluding comments
! if pEnd = -2 then join to the end of the current line including comments
x             long,auto
y             long,auto
svPtr         long,auto
toEOL         long
!eNoComments   equate(-1)
eWithComments equate(-2)
 code

  st.free()
  if pStart < 1 then pStart = 1.
  if pEnd < 0 then toEOL = pEnd.                ! join to the end of the current line (-1 no comments, -2 with comments)
  if pEnd < 1 or pEnd > Records(self.tokens)
    pEnd = records(self.tokens)
  end
  svPtr = pointer(self.tokens)                  ! save pointer position for restore at end
  loop x = pStart to pEnd
    Get(self.tokens, x)
    if toEOL
    ! careful: with continuations ('|') there is no <10> token but CRLF is included in strBefore
    !          of first token on next line.
      if not self.tokens.tok &= NULL and self.tokens.tok = '<10>'
        if toEOL = eWithComments and not self.tokens.strBefore &= NULL
          st.append(self.tokens.strBefore)
        end
        break
      end
      if self.tokens.firstOnLine and x > pStart ! continuation line - CRLF is in StrBefore
        if self.tokens.strBefore &= NULL then self.TraceIt('expecting continuation line: line ' & self.tokens.LineNo);break.
        y = st.findChars('<13,10>', 1,, self.tokens.strBefore)
        if y and toEOL = eWithComments
          st.append(sub(self.tokens.strBefore,1,y-1))
        else
          st.append('|')                        ! indicate this line is continued on next line (continuation line)
        end
        break
      end
    end
    if not self.tokens.strBefore &= NULL then st.append(self.tokens.strBefore).
    if not self.tokens.tok &= NULL
      if self.tokens.tok = '<10>'
        st.append('<13,10>')
      else
        st.append(self.tokens.tok)
      end
    end
  end
  get(self.Tokens,svPtr)                        ! restore queue to previous state


! ------------------------------------------------------------------------------------
VitTokenize.FreeToks     Procedure()            !, virtual
i               LONG,AUTO
 code
  if self.tokens &= null then return.

  LOOP i = 1 to records(self.tokens)
    get(self.tokens,i)
    dispose(self.Tokens.tok)
    dispose(self.Tokens.strBefore)
  END
  free(self.tokens)
  if not self.vars &= NULL
    free(self.vars)  ! the varType table is PER-PARSE. Left standing it survives into the next
  end                !   ParseText on a reused tokenizer and changes LEVEL stamping of identical text - the level census
                     !   differs on byte-identical streams. Every parse is self-contained; the backwards declaration pass rebuilds vars fresh.
  clear(self.tokens) ! free() leaves the RECORD BUFFER holding the last row, and firstOnLine is written only by SetLineNumbers - AddToken never assigns it. TokenIsReservedWord READS it during
                     !   tokenising, before SetLineNumbers has run: `if firstOnLine and strBefore &= NULL then return FALSE`. So on a REUSED tokenizer (RejoinReparse after every rewrite pass) a stale
                     !   TRUE would stop every column-1 token being a reserved word for the whole pass. Same class as the per-parse vars table two lines above, so clear it for the same reason.
  self.fileSize = 0  ! reset size of file read in

! ------------------------------------------------------------------------------------
! Empty the search pattern queue, disposing the token reference on every row.
!
! searchQ holds a SEQUENCE of tokens to look for, not a single token - see FindSeq. Call this
! between searches or the next pattern is appended to the last one.
! ------------------------------------------------------------------------------------
VitTokenize.FreeSearchQ     Procedure() !, virtual
i               LONG,AUTO
 code
  if self.searchQ &= null then return.

  LOOP i = 1 to records(self.searchQ)
    get(self.searchQ,i)
    dispose(self.searchQ.tok)
!    dispose(self.searchQ.tok2)
  END
  free(self.searchQ)

! ------------------------------------------------------------------------------------
! Move the token at pSrc to pDst. Returns st:ok or st:notOK; pDst = 0 means THE END.
!
! LOSSLESS BY CONSTRUCTION, and deliberately so: the row is re-added and the original
! deleted with a bare delete() - NOT DeleteTok - so the tok and strBefore references
! travel with it. Nothing is disposed, nothing is copied, so a move cannot lose or alter
! a byte of text or trivia. Do not "tidy" this into DeleteTok; that would dispose the very
! references the new row is still pointing at.
!
! The +1 is not an off-by-one, it is the correction FOR one: inserting ahead of pSrc has
! already pushed the source row down by one, so the delete has to look one further along.
! ------------------------------------------------------------------------------------
VitTokenize.MoveTok       Procedure(LONG pSrc, LONG pDst) !,LONG,proc,virtual
  code
  if self.Tokens &= null or               |
     ~pSrc               or               |
     pDst < 0                             ! note: destination 0 means end of queue
    return st:notOK
  end
  if pSrc = pDst then return st:ok.       ! do nothing but is ok
  Get(self.Tokens,pSrc)
  if errorcode() then return st:notOK.
  add(self.Tokens,pDst)                   ! note if pDst is zero then is moved to END of queue
  if errorcode() then return st:notOK.
  if pDst and pDst < pSrc then pSrc += 1. ! source is now one higher as inserted before
  get(self.tokens,pSrc)
  if errorcode() then return st:notOK.
  delete(self.tokens)                     ! note we do NOT dispose tok or strBefore as these are still used but now in diff (new) position in the queue.
  if errorcode() then return st:notOK.
  return st:ok

! ------------------------------------------------------------------------------------
! Move pNumToMove tokens starting at pSrc to pDst, one MoveTok at a time.
!
! ORDER IS PRESERVED, which is the only reason the loop is not a plain repeat: when moving
! BACKWARDS (pSrc > pDst) each token lands after the one before it, so BOTH pointers advance by
! one each time: the destination because the landed token now precedes the rest, the source
! because inserting ahead of it pushed the remaining block down one. Moving forwards needs no
! such step, because every move shifts the remaining source tokens down onto pSrc for free.
!
! pNumToMove is clamped to what actually exists from pSrc on, so asking for more than the
! stream holds moves the tail rather than failing.
! ------------------------------------------------------------------------------------
VitTokenize.MoveToks      Procedure(LONG pSrc, LONG pDst, LONG pNumToMove) !,LONG,proc,virtual
  code
  if pNumToMove < 1 then return st:notOK.
  if pSrc = pDst then return st:ok. ! do nothing but is ok
  if pNumToMove > records(self.tokens) - pSrc + 1 then pNumToMove = records(self.tokens) - pSrc + 1.
  loop pNumToMove times
    if self.moveTok(pSrc,pDst) <> st:ok then return st:notOK.
    if pDst and pSrc > pDst         ! backward: the landed token pushed the REMAINING block down one, (pDst = 0 is APPEND per MoveTok - neither pointer moves there)
      pDst += 1                     !   so the next block token sits at pSrc+1 - advance the source
      pSrc += 1                     !   alongside the destination or a survivor is moved instead
    end
  end
  return st:ok

! ------------------------------------------------------------------------------------
! Does the token in the buffer stand in COLUMN 1? Either nothing is in front of it, or what
! is in front of it ends at a line feed. The second case is the one every "strBefore &= NULL"
! test misses: a plain OMIT('***') block is folded, whole, into the strBefore of the
! token after it, so a column-1 label right after such a block carries the block in its
! trivia, and read by that test it would keep a keyword's type and level (`Loop LONG`),
! and a structure opener there would get no opener mark while its END still closed one.
! GET the token first; meaningful only for a first-on-line token.
! ------------------------------------------------------------------------------------
VitTokenize.BufColOne Procedure() !,LONG,virtual
  code
  ! A FRAGMENT HAS NO COLUMN 1. A replacement is parsed on its own before being spliced into
  !   the middle of a line, and its first token has no trivia in front of it - which is what
  !   this test reads as column 1. Column 1 is where a LABEL goes, so `if`, `exit` or `return`
  !   at the start of a replacement would come out typed as labels and be copied into the
  !   stream. Harmless where the structure keywords force a re-parse straight after, which is
  !   not true of EXIT, RETURN or ACCEPT. The caller says which it is; a file parse never sets it.
  if self.midLine then return 0.
  if self.tokens.strBefore &= NULL then return 1.
  if self.tokens.strBefore[size(self.tokens.strBefore)] = '<10>' then return 1.
  return 0

! ------------------------------------------------------------------------------------
! The token text at pTokNumber, or '' if there is none.
!
! '' IS AMBIGUOUS HERE and you cannot tell the two cases apart: no such token, and a token
! whose tok is NULL, both come back as ''. That is fine for the usual "is this a comma"
! question and wrong for anything that has to know a token EXISTS. Use Records() for the
! bound, or the three-argument overload below, when the difference matters.
!
! IT MOVES THE SHARED TOKEN BUFFER to pTokNumber and leaves it there - it does not put the
! caller's position back. A caller that reads self.tokens fields after calling this is
! reading token pTokNumber, not the one it fetched before.
! ------------------------------------------------------------------------------------
VitTokenize.GetTok       Procedure(LONG pTokNumber) !,STRING,proc,virtual
 code
  if self.Tokens &= null then return ''.

  Get(self.Tokens,pTokNumber)
  if errorcode() or self.Tokens.tok &= NULL
    return ''
  else
    return self.Tokens.tok
  end

! ------------------------------------------------------------------------------------
! Both halves of a token at once - its trivia into pStrBefore, its text into pTok.
!
! BOTH OUTPUTS ARE FREED FIRST, so they are always left in a defined state: a token that
! does not exist, or one whose halves are NULL, leaves you two EMPTY StringTheorys rather
! than whatever the caller happened to have in them. There is no return code - if you need
! to know the token was really there, check the bound before calling.
! ------------------------------------------------------------------------------------
VitTokenize.GetTok       Procedure(LONG pTokNumber, StringTheory pStrBefore, StringTheory pTok) !,virtual
 code
  pStrBefore.free()
  pTok.free()

  if not self.Tokens &= null
    Get(self.Tokens,pTokNumber)
    if ~errorcode()
      if not self.Tokens.StrBefore &= NULL then pStrBefore.setValue(self.Tokens.StrBefore).
      if not self.Tokens.Tok &= NULL       then pTok.setValue(self.Tokens.Tok).
    end
  end

!-----------------------------
VitTokenize.GetTokStartPos   Procedure(LONG pTokNumber) !, LONG,virtual  ! find the start position of this token in the string
pos long
x   long
 code
  if pTokNumber < 1 or pTokNumber > Records(self.tokens) then return 0.
  loop
    x += 1
    Get(self.tokens, x)
    if not self.tokens.strBefore &= NULL then pos += size(self.tokens.strBefore).
    if x = pTokNumber then return pos+1.
    if not self.tokens.tok &= NULL
      if self.tokens.tok = '<10>'
        pos += 2 ! assume CR/LF in original - maybe should be a flag?
      else
        pos += size(self.tokens.tok)
      end
    end
  end

!-----------------------------
! ------------------------------------------------------------------------------------
! By-value front end for SetTok. IT EXISTS ONLY TO CARRY "OMITTED" ACROSS THE CALL, and
! that is the whole point of the if/else below - it is not redundant.
!
! OMITTING pStrBefore and passing a BLANK one mean opposite things: omitted = leave the
! existing trivia alone, blank = replace it with nothing. If this forwarded pStrBefore
! unconditionally, omitted would arrive as blank at the next level and every caller that
! just wanted to change a token's TEXT would silently wipe the indent in front of it.
! ------------------------------------------------------------------------------------
VitTokenize.SetTok       Procedure(long pTokNumber,STRING pValue,<string pStrBefore>) !,virtual
 code
  if omitted(pStrBefore) ! do NOT remove this as blank string will replace existing StrBefore !!!
    self.setTok(pTokNumber, pValue)
  else
    self.setTok(pTokNumber, pValue, pStrBefore)
  end

! ------------------------------------------------------------------------------------
! Replace the text of token pTokNumber, and its trivia only if pStrBefore is given.
!
! IT ADDS RATHER THAN FAILS. If pTokNumber does not exist this calls AddTok, so a bad
! index does not raise anything - it appends. Worth knowing before using SetTok in a loop
! whose bound might be stale.
!
! When the token exists, IT LEAVES THE SHARED TOKEN BUFFER ON pTokNumber, the token it has
! just written, and callers rely on that to read the new fields straight back.
!
! Same-size values are written straight into the existing allocation; any other size
! disposes and re-allocates. type is recomputed by TokenType() either way, so a token
! rewritten from a label into an operator classifies correctly without the caller asking.
! ------------------------------------------------------------------------------------
VitTokenize.SetTok       Procedure(long pTokNumber,*STRING pValue,<string pStrBefore>) !,virtual
 code
  Get(self.tokens,pTokNumber)
  if errorcode()
    self.AddTok(pTokNumber, pValue, pStrBefore)
  else
    if address(pValue) and size(self.Tokens.tok) = size(pValue)
      self.tokens.tok = pValue
    else
      Dispose(self.Tokens.tok)
      if size(pValue) and address(pValue)
        self.Tokens.tok &= new string(size(pValue))
        self.tokens.tok = pValue
      else
        self.Tokens.tok &= NULL
      end
    end
    if not omitted(pStrBefore)
      dispose(self.Tokens.strBefore)
      if size(pStrBefore)
        self.Tokens.strBefore &= new string(size(pStrBefore))
        self.tokens.strBefore = pStrBefore
      else
        self.Tokens.strBefore &= NULL
      end
    end

    self.TokenType() ! sets self.tokens.type

    put(self.tokens)
?   assert(~errorcode())
  end

! ------------------------------------------------------------------------------------
! The trailing comment on the line containing pTokNumber, into pSt.
!
! A trailing comment is not a token - like all trivia it lives in the strBefore of the token
! that follows it, which for an end-of-line comment is the EOL token. So this is a lookup in
! the trivia, not a search of the stream.
! ------------------------------------------------------------------------------------
VitTokenize.GetCurrLineComment   Procedure(stringTheory pSt, long pTokNumber) !virtual
sTok long,auto                                                                ! the walk's own first token is never a continuation tail
  code
  pSt.free()
  sTok = pTokNumber
  loop
    Get(self.tokens,pTokNumber)
    if errorcode() then return.
    if not self.tokens.tok &= NULL and self.tokens.tok = '<10>' ! EOL; the null test first - tok is a reference and may be unset
      if not self.Tokens.strBefore &= null
        pSt.setValue(self.Tokens.strBefore)
      end
      break
    end

    ! careful: with continuations ('|') there is no <10> token but CRLF is included in strBefore
    !          of first token on next line.
    if self.tokens.firstOnLine and pTokNumber > sTok            ! continuation line - CRLF is in StrBefore
      if self.tokens.strBefore &= NULL
        self.TraceIt('VitTokenize.GetCurrLineComment - expecting continuation line: line ' & self.tokens.LineNo)
      else
        pSt.setValue(self.tokens.strBefore)
        pSt.setBefore('<13,10>')
      end
      break
    end

    pTokNumber += 1
  end
  return

! ------------------------------------------------------------------------------------
! Append text at the end of a line, usually as a comment - this is how the tool leaves a note
! beside a line it changed.
!
! It appends into the EOL token's strBefore rather than adding a token, because a comment IS
! trivia in this model. Nothing downstream can then match it as code, which is what makes an
! annotation safe to add inside a fixpoint: it cannot cause another rewrite.
!
! Mode 3 stops at a LOGICAL end of line - ';' or THEN - not just the physical one, so a note
! lands beside the statement it belongs to on a line carrying several.
! Mode 3 also walks THROUGH a '|' continuation to that end: a real token parked after a bar
! would be ignored by the compiler. Neither walker treats the token it STARTS
! on as a continuation tail, whatever its first-on-line mark says.
!
! If pTokNumber does not exist it appends a new trivia-only token at the end of the stream,
! the same way AppendStrBefore does.
! ------------------------------------------------------------------------------------
VitTokenize.InsertStringAtEOL    Procedure(long pTokNumber, string pStr, byte pComment=1) !,virtual    useful for adding comments at EOL
! insert string at end of current line
! if pComment is 1 we make it a comment (prepend ' ! '); a line that already has a comment gets it as a SECOND one, '  ! ' in front
! if pComment is 2 we make it a comment (prepend ' ! ') and PREPEND to existing text
! if pComment is 3 then NOT a comment and treat ';' and 'THEN' as logical EOL (for when line has several logical lines combined)
isCmt byte,auto ! mode 1 or 2 = comment; mode 0 and mode 3 are not
sTok  long,auto ! the walk's own first token is never a continuation tail
nEol  long,auto ! NoteInOrder: the line the note lands on, as numbered now - the registry's key
nRt   long,auto !   notes already on that line whose site is to the RIGHT of this one
nSep  long,auto !   the tool's own '  ! ' separators in the text
nIx   long,auto
nPos  long,auto
  code
  if size(pStr) = 0 then return.
  sTok = pTokNumber

! self.traceIt = true

  loop
! self.TraceIt('InsertStringAtEOL:  token ' & pTokNumber)
    Get(self.tokens,pTokNumber)
    if errorcode()
! self.TraceIt('InsertStringAtEOL:  token does not exist so add new one on end')
      ! token does not exist so add new one on end
      ! the test is "is this mode a COMMENT", and `~pComment` is not it. Mode 3 inserts a
      ! REAL TOKEN (the Check* builtins add a ')' that way), and ~3 is 0, so a `~pComment` test
      ! here would prepend ' ! ' and comment the bracket OUT. Modes: 0 = plain text, 1 and 2 = comment,
      ! 3 = real token. Both the allocation and the text must ask the same question.
      isCmt = choose(pComment = 1 or pComment = 2)
      clear(self.tokens)
      self.Tokens.strBefore &= new string(size(pStr)+choose(~isCmt,0,3)) ! if comment add extra 3 for ' ! '
      self.tokens.strBefore = choose(~isCmt,pStr,' ! '&pStr)
      add(self.Tokens)                                                   ! note: is added to END of queue
?     assert(~errorcode())
      break
    end
    if not self.tokens.tok &= NULL and (self.tokens.tok = '<10>' or (pComment = 3 and (self.tokens.tok = ';' or lower(self.tokens.tok) = 'then'))) ! EOL; the null test first - tok is a reference and may be unset
! self.TraceIt('InsertStringAtEOL:  EOL')
      if pComment=3
!        self.AppendStrBefore(pTokNumber, pStr)
        self.InsertString(pTokNumber, pStr)                              ! 3 = not a comment so insert tokens not comment

      elsif self.Tokens.strBefore &= null                                !or self.Tokens.strBefore = ''
        self.SetStrBefore(pTokNumber,choose(~pComment,pStr,' ! '&pStr))
      elsif pComment=2                                                   ! make comment and prepend to existing text
        self.PrependStrBefore(pTokNumber, ' ! ' & pStr)
      elsif ~pComment                                                    ! raw text - the caller wrote any separator it wants
        self.AppendStrBefore(pTokNumber,' ' & pStr)
      elsif instring('!',self.Tokens.strBefore,1,1)                      ! a comment is there already: the note goes in as a
        do NoteInOrder                                                   !   SECOND comment, not as more words of the first -
      else                                                               !   and among the notes already there, in SOURCE order
        self.AppendStrBefore(pTokNumber, ' ! ' & pStr)
      end
      break
    end

    ! careful: with continuations ('|') there is no <10> token but CRLF is included in strBefore
    !          of first token on next line.
    if self.tokens.firstOnLine and pTokNumber > sTok and pComment <> 3   ! continuation line - CRLF is in StrBefore
! self.TraceIt('InsertStringAtEOL: first on line: ' & self.tokens.tok )
      if self.tokens.strBefore &= NULL
        self.TraceIt('VitTokenize.InsertStringAtEOL - expecting continuation line: line ' & self.tokens.LineNo)
      else
        do ContinuationWork                                              ! separate so ST object is not unnecessarily instantiated
      end
      break
    end

    pTokNumber += 1
  end
!self.traceIt = false


! ---- a note goes in among the notes already on its line in SOURCE order. The notes of one rule
!      arrive right to left, because that is the order its matches are applied in, so a plain
!      append would reverse them. self.noteQ remembers, for the rule being applied, the site each
!      note was asked for; the new note goes in front of every note whose site is to its RIGHT.
!      The tool's own separator is '  ! ' (two spaces), so the k rightmost such separators are
!      the k notes to get ahead of. SetLineNumbers empties the registry when the rule is done.
NoteInOrder routine
  nEol = self.tokens.lineNo
  do NoteCountRight
  nPos = 0
  if nRt
    nSep = 0
    loop
      nIx = instring('  ! ', self.tokens.strBefore, 1, nPos + 1)
      if ~nIx then break.
      nSep += 1 ; nPos = nIx
    end
    if nRt > nSep then nRt = nSep.
    nIx = 0 ; nPos = 0
    loop while nIx < nSep - nRt + 1
      nPos = instring('  ! ', self.tokens.strBefore, 1, nPos + 1)
      nIx += 1
    end
  end
  if nPos < 2                                                                           ! nothing to its right, or nothing to get ahead of: after everything
    self.AppendStrBefore(pTokNumber, '  ! ' & pStr)
  else
    self.SetStrBefore(pTokNumber, self.tokens.strBefore[1 : nPos - 1] & '  ! ' & pStr & |
                                  self.tokens.strBefore[nPos : size(self.tokens.strBefore)])
  end
  do NoteRemember

! ---- nRt = the notes already registered on line nEol whose site is to the right of sTok
NoteCountRight routine
  nRt = 0
  loop nIx = 1 to records(self.noteQ)
    get(self.noteQ, nIx)
    if errorcode() then break.
    if self.noteQ.lineNo = nEol and self.noteQ.siteTok > sTok then nRt += 1.
  end

! ---- register this note: its line and the site it was asked for
NoteRemember routine
  clear(self.noteQ)
  self.noteQ.lineNo  = nEol
  self.noteQ.siteTok = sTok
  add(self.noteQ)

continuationWork routine
  data
st StringTheory ! put this into routine so only declared when needed
  code
  st.setValue(self.tokens.strBefore)
  st.split('<13,10>')
  if st.records() = 1
    self.TraceIt('VitTokenize.InsertStringAtEOL - expecting CRLF in continuation line: line ' & self.tokens.LineNo)
  end
  st.setValueFromLine(1)                 ! text before CRLF
  if pComment=2                          ! make comment and prepend to existing text
    st.replace('|',' ',1)                ! get rid of first | continuation char as we are adding one at start
    st.clip()
    st.prepend(' | ' & pStr)
  elsif ~pComment
    st.append(pStr)                      ! caller wants raw text, not a comment
  elsif st.containsByte(33)              ! a comment is already parked after the bar: the note goes in
    nEol = self.tokens.lineNo ; nPos = 0 !   as a second comment after it, and among the notes already
    do NoteCountRight                    !   there in SOURCE order - the same as on a plain line
    if nRt
      nSep = 0
      loop
        nIx = st.findChars('  ! ', nPos + 1)
        if ~nIx then break.
        nSep += 1 ; nPos = nIx
      end
      if nRt > nSep then nRt = nSep.
      nIx = 0 ; nPos = 0
      loop while nIx < nSep - nRt + 1
        nPos = st.findChars('  ! ', nPos + 1)
        nIx += 1
      end
    end
    if nPos < 2
      st.append('  ! ' & pStr)
    else
      st.insert(nPos, '  ! ' & pStr)
    end
    do NoteRemember
  elsif st.containsByte(124)             ! a line ending in a continuation bar takes its '|'
    st.append(' ! ' & pStr)              ! comments AFTER the bar - Clarion ignores everything past it, so
  else                                   ! this is the right home for them. Append with a ' | ' separator:
    st.append(' | ' & pStr)              ! raw text with no separator and no '!' runs several notes
  end                                    ! together, as in `... or |'[''&'''''`
  st.setLineFromValue(1)
  st.join('<13,10>')
  self.SetStrBefore(pTokNumber, st.getValue())

!  if pComment=2 ! make comment and prepend to existing text
!    self.PrependStrBefore(pTokNumber, ' | ' & pStr)            ! note use | for continuation not ! for comment
!  elsif pComment=0 or instring('|',sub(self.tokens.strBefore,1,y-1),1,1)
!    self.SetStrBefore(pTokNumber, sub(self.tokens.strBefore,1,y-1) & pStr & sub(self.tokens.strBefore,y,size(self.tokens.strBefore)-y+1))
!  else
!    self.AppendStrBefore(pTokNumber, ' | ' & pStr)
!  end

VitTokenize.PrependStrBefore    Procedure(long pTokNumber, string pStrBefore) !,virtual
! insert string at start of existing strBefore
  code
  if size(pStrBefore) = 0 then return.

  Get(self.tokens,pTokNumber)
  if errorcode()
    ! token does not exist so add new one on end
    clear(self.tokens)
    self.Tokens.strBefore &= new string(size(pStrBefore))
    self.tokens.strBefore = pStrBefore
    add(self.Tokens) ! note: is added to END of queue
?   assert(~errorcode())
  elsif self.Tokens.strBefore &= null
    self.SetStrBefore(pTokNumber,pStrBefore)
  else
    self.SetStrBefore(pTokNumber,pStrBefore & self.Tokens.strBefore)
  end

! ------------------------------------------------------------------------------------
! Add to the END of a token's existing trivia, keeping what is already there. The sibling
! PrependStrBefore puts it at the front. A zero-length pStrAfter returns immediately.
!
! IF THE TOKEN DOES NOT EXIST IT APPENDS A NEW ONE AT THE END OF THE STREAM - a row with
! trivia and NO tok. That is deliberate, and it is how trailing whitespace or a final
! comment can be carried after the last real token, but it means a stale index does not
! fail here: it grows the stream. Check your bound if that would be wrong.
! ------------------------------------------------------------------------------------
VitTokenize.AppendStrBefore    Procedure(long pTokNumber, string pStrAfter) !,virtual
  code
  if size(pStrAfter) = 0 then return.

  Get(self.tokens,pTokNumber)
  if errorcode()
    ! token does not exist so add new one on end
    clear(self.tokens)
    self.Tokens.strBefore &= new string(size(pStrAfter))
    self.tokens.strBefore = pStrAfter
    add(self.Tokens) ! note: is added to END of queue
?   assert(~errorcode())
  elsif self.Tokens.strBefore &= null
    self.SetStrBefore(pTokNumber,pStrAfter)
  else
    self.SetStrBefore(pTokNumber,self.Tokens.strBefore & pStrAfter)
  end


! ------------------------------------------------------------------------------------
! Replace a token's trivia outright - the indent, gap, comment or continuation in front
! of it. Traces and returns if the token does not exist; it will not create one.
!
! IT TESTS size(), NOT TRUTH, so a single space is stored rather than being read as blank,
! and a zero-length value sets the reference to NULL rather than an empty string. AddTok and
! both SetTok overloads guard the same way - all four trivia writers agree.
! ------------------------------------------------------------------------------------
VitTokenize.SetStrBefore    Procedure(long pTokNumber, string pStrBefore) !,virtual
 code
  Get(self.tokens,pTokNumber)
  if errorcode()
    self.TraceIt('error in VitTokenize.SetStrBefore: token# ' & pTokNumber & ' does not exist')
    return ! only works on existing token
  end

  dispose(self.Tokens.strBefore)
  if size(pStrBefore)
    self.Tokens.strBefore &= new string(size(pStrBefore))
    self.tokens.strBefore = pStrBefore
  else
    self.Tokens.strBefore &= NULL
  end

  put(self.tokens)
? assert(~errorcode())


! ------------------------------------------------------------------------------------
! Insert a new token BEFORE pTokNumber. pTokNumber = 0 (the default) means at the END.
!
! pStrBefore is guarded by size(), so ANY non-empty trivia is stored - a single space
! included. Omit the parameter, or pass a zero-length value, to add a token with none.
!
! GUARD ON size(), NEVER ON TRUTH. A bare string test in Clarion - `and pStrBefore` - is a
!     NON-BLANK test, so a lone ' ' reads as FALSE and the trivia is dropped without a word.
!     A single space in front of a token is exactly what a splice needs, and losing it welds
!     the token to its neighbour: `'te'& |` with the '&' against the quote. All four trivia
!     writers agree on size() for this reason - AddTok, SetStrBefore and both SetTok
!     overloads. Keep it that way; "a blank string is FALSE" catches people elsewhere too.
!
! type is set by TokenType() as the token goes in, so an added token is classified without
! the caller doing anything.
! ------------------------------------------------------------------------------------
VitTokenize.AddTok       Procedure(long pTokNumber=0,STRING pValue,<string pStrBefore>)
 code
  self.AddTok(pTokNumber, pValue, pStrBefore)

! ------------------------------------------------------------------------------------
! The by-reference implementation behind AddTok - see the banner on the overload above,
! including the single-space trap in the pStrBefore guard.
! ------------------------------------------------------------------------------------
VitTokenize.AddTok       Procedure(long pTokNumber=0,*STRING pValue,<string pStrBefore>)
 code

  clear(self.tokens)
  if size(pValue) and address(pValue)
    self.Tokens.tok &= new string(size(pValue))
    self.tokens.tok = pValue
  else
    self.TraceIt('error when adding token - no token passed')
  end
  if (not omitted(pStrBefore)) and size(pStrBefore)       ! size, NOT truthiness - see the banner above
    self.Tokens.strBefore &= new string(size(pStrBefore))
    self.tokens.strBefore = pStrBefore
  end
  self.TokenType()                                        ! sets self.tokens.type
  add(self.Tokens,pTokNumber)                             ! note if pTokNumber is zero then is added to END of queue
? assert(~errorcode())

! ------------------------------------------------------------------------------------
! Delete one token, disposing BOTH its references. Silent no-op if it does not exist.
!
! This takes the token's strBefore with it - the indent or gap in FRONT of it. If the token
! was first on its line, that line loses its indentation unless the caller puts the trivia
! back on whatever token becomes first. VitRewrite does exactly that, bracketing its
! deletes with TokBefore and PrependStrBefore.
! ------------------------------------------------------------------------------------
VitTokenize.DeleteTok    Procedure(long pTokNumber)
 code
  Get(self.Tokens,pTokNumber)
  if ~errorcode()
    dispose(self.Tokens.Tok)
    dispose(self.Tokens.strBefore)
    delete(self.Tokens)
?   assert(~errorcode())
  end

! ------------------------------------------------------------------------------------
! Delete the tokens pStart..pEnd inclusive.
!
! *** pEnd BELOW 1 COUNTS BACK FROM THE END, so pEnd = 0 means THE LAST TOKEN and pEnd = -1
!     means the last but one - it does pEnd += records(). A caller passing 0 meaning
!     "nothing to delete" would wipe from pStart to end of file. Guard the empty case
!     yourself; this procedure has no spelling for it.
!
! pStart below 1 is clamped to 1, pEnd past the end is clamped to the end, and pStart > pEnd
! returns having done nothing.
!
! It deletes BACKWARDS, which is why a range captured before the loop stays valid all the
! way through - removing the last row first cannot move the rows still to be removed. The
! same reason VitRewrite applies its matches right-to-left.
! ------------------------------------------------------------------------------------
VitTokenize.DeleteToks    Procedure(long pStart,long pEnd)
x       long,auto
 code
  if pStart < 1 then pStart = 1.
  if pEnd > records(self.tokens)
    pEnd = records(self.tokens)
  elsif pEnd < 1
    pEnd += records(self.tokens) ! pEnd of 0 = last record,  pEnd of -1 means "last but one" = second last etc.
  end
  if pStart > pEnd then return.

  loop x = pEnd to pStart by -1
    self.DeleteTok(x)
  end
! -----------------------------------------------------------------------------------------------
VitTokenize.Records              Procedure() !,LONG, virtual
 code
  return records(self.tokens)

! ------------------------------------------------------------------------------------
! The full text of the source line containing token pPos, into pSt.
! ------------------------------------------------------------------------------------
VitTokenize.GetCurrentLine       Procedure(StringTheory pSt,LONG pPos) !,STRING,virtual
stPos    long,auto
endPos   long,auto
 code
  if pPos > pSt._DataEnd then return ''.

  stPos = pSt.instring('<10>',-1,,pPos) ! Note we are searching backwards so set EndPos to pPos
!  if stPos
    stPos += 1
!  else
!    stPos = 1
!  end
  endPos = pSt.findByte(10, stPos)      ! <line feed>
  if endPos
    endPos -= 1
  else
    endPos = pSt._DataEnd               ! on last line
  end

  if endPos >= stPos
    return pSt.valueptr[stPos : endPos]
  else
    return ''
  end

! ------------------------------------------------------------------------------------
! Dump the token stream into st for diagnostics - the workhorse behind DumpTokens. pShowType
! adds each token's type and level marks.
! ------------------------------------------------------------------------------------
VitTokenize._List                 Procedure(StringTheory st, long pShowType=0) !, virtual
i                   LONG,AUTO
 code
  st.free()
  loop i = 1 to Records(self.tokens)
    Get(self.tokens, i)
    if self.tokens.tok &= NULL then break.
    if pShowType
      st.append(self.tokens.level & self.tokens.type & choose(~self.tokens.firstOnLine,' ','F') & |
                self.tokens.varType & right(self.tokens.lineNo,5) & '-')
    end
    if self.tokens.tok = '<10>'
      st.append('<<EOL><13,10>')
    else
      st.append(self.tokens.tok & '<13,10>')
    end
  end

! ------------------------------------------------------------------------------------
! From the CURRENT token, find the token that closes or opens it, and return its number.
!
! Reads self.tokens.level: on '+' it scans FORWARD for the matching '-', on '-' it scans back
! for the matching '+', counting depth so nested blocks are skipped whole. Returns 0 when
! nothing matches, which is what an unbalanced file looks like from here.
!
! This is only ever as right as the level marks, so a structure ParseText mis-classified shows
! up as a wrong or zero answer here rather than as anything obviously wrong at this end.
! ------------------------------------------------------------------------------------
VitTokenize.MatchLevel  Procedure() !,LONG,proc,virtual ! positions on matching + or - and  returns matching token number
ans     long
depth   long
x       long,auto
  code

  case val(self.tokens.level)
  of 43       ! '+'  ! search forwards for matching '-'
    depth = 1
    loop x = pointer(self.tokens)+1 to records(self.tokens) by 1
      get(self.tokens,x)
      case self.tokens.level
      of '+'
        depth += 1
      of '-'
        depth -= 1
        if ~depth
          ans = x
          break
        end
      end
    end
  of 45       ! '-'  ! search backwards for matching '+'
    depth = -1
    loop x = pointer(self.tokens)-1 to 1 by -1
      get(self.tokens,x)
      case self.tokens.level
      of '+'
        depth += 1
        if ~depth
          ans = x
          break
        end
      of '-'
        depth -= 1
      end
    end
  end
  return ans

! ------------------------------------------------------------------------------------
! From the current token, scan BACKWARDS for the bracket that opens the one you are on,
! counting depth so nested pairs are skipped. Returns 0 if there is no match.
!
! The bracket characters are passed in rather than assumed, so the same walk serves (), [] and
! {} - Clarion uses all three, and {} is property syntax rather than grouping.
! ------------------------------------------------------------------------------------
VitTokenize.MatchLeftBracket  Procedure(String pLeftBracket, String pRightBracket, Long pStart=1) ! returns matching token number
ans     long
depth   long
x       long,auto
  code
  if pStart < 1 then pStart = 1.
  loop x = pStart to records(self.tokens)                 !self.records()
    Get(self.Tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break. ! no matching bracket
    if self.Tokens.tok = pLeftBracket
      depth += 1
    elsif self.Tokens.tok = pRightBracket
      if depth
        depth -= 1
        if ~depth
          ans = x
          break
        end
      end
    end
  end
  return ans


! ------------------------------------------------------------------------------------
! The MIRROR of MatchLeftBracket: given a RIGHT bracket, scan BACKWARDS for the LEFT one that
! opens it, counting depth. Returns 0 if unmatched.
! Read the direction off the loop, not off the name: this one runs `pStart to 1 by -1`.
! ------------------------------------------------------------------------------------
VitTokenize.MatchRightBracket  Procedure(String pLeftBracket, String pRightBracket, Long pStart=0) ! searches BACKWARDS and returns matching token number
ans     long
depth   long
x       long,auto
  code
  ! THE DEFAULT MUST MATCH THE PROTOTYPE'S, and for a BACKWARD search that default is 0,
  ! meaning "start at the last token". Clarion substitutes the value written on the
  ! PROTOTYPE at the call site, so a 1 there would arrive here, pass the test below
  ! untouched, and reduce the loop to token 1 alone - which can never match and so
  ! returns 0 every time. The forward MatchLeftBracket defaults to 1 because that is
  ! where a forward search starts; the two are not interchangeable.
  if pStart < 1 or pStart > records(self.tokens) then pStart = records(self.tokens).
  ! note we search BACKWARDS
  loop x = pStart to 1 by -1
    Get(self.Tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break. ! no matching bracket??
    if self.Tokens.tok = pRightBracket
      depth += 1
    elsif self.Tokens.tok = pLeftBracket
      if depth
        depth -= 1
        if ~depth
          ans = x
          break
        end
      end
    end
  end
  return ans


! ------------------------------------------------------------------------------------
! the pretty name for a byte that has no readable printed form, so a generated
! comment can say <line feed> instead of '<10>'. BLANK = the byte has no special name
! and the caller should print the character itself. Lives HERE, not in VitEngine, so
! the CheckCase builtin and the rule-file NOTE charname() helper cannot drift apart.
! ------------------------------------------------------------------------------------
VitTokenize.CharNameOfByte Procedure(LONG pByte)
  code
  case pByte
  of   0 ; return '<<null>'
  of   9 ; return '<<tab>'
  of  10 ; return '<<line feed>'
  of  13 ; return '<<carriage return>'
  of  32 ; return '<<space>'
  of  34 ; return '<<double quote>'
  of  39 ; return '<<single quote>'
  of  44 ; return '<<comma>'
  of  46 ; return '<<dot>'
  of  58 ; return '<<colon>'
  of  59 ; return '<<semi-colon>'
  end
  return ''

! ------------------------------------------------------------------------------------
! Fold the integer arithmetic in a string - 4+1 -> 5, -4+1 -> -3 - returning the folded text.
! ------------------------------------------------------------------------------------
VitTokenize.FoldStr               Procedure(String in) !STRING, virtual
st  StringTheory,static,thread
tk  VitTokenize, static,thread
 code
  if ~in then return ''.

  st.SetValue(in)
  tk.ParseText(st,,TRUE) ! split up into tokens - third parameter means extreme merging of labels
! st.trace('split into ' & tk.records() & ' tokens')
! tk._List(st,true)
! st.trace(st.getvalue())

  tk.FoldStr()
  tk.joinToks(st)
  tk.freeToks()
  if st._DataEnd
    return st.valueptr[1 : st._DataEnd]
  else
    return ''
  end


! ------------------------------------------------------------------------------------
! Fold the integer arithmetic in tokens pStart..pEnd, in place.
! ------------------------------------------------------------------------------------
VitTokenize.FoldStr               Procedure(LONG pStart=1, LONG pEnd=0) !STRING, virtual
x              long,auto
cb             long,auto                                                ! close bracket
endTok         long,auto
endOffset      long,auto
eOff           long,auto                                                ! endoffset used when recursing down on expression in brackets
svPEnd         long,auto                                                ! store end for Plus loop
svMEnd         long,auto                                                ! store end for Multiplication loop
calc           stringTheory
firstNumTok    LONG                                                     ! indicate position of first eligible number token - we will add others to this token
insertNegative LONG                                                     ! used when amt in brackets is negative eg. X+(2-4) or (2-4)+X
tsX            long                                                     ! TermSign: the number it is asked about
tsSg           long                                                     !   ... and its answer, -1 to 2 - see TermSign
usOK           long                                                     ! UnarySafe: a '-' left in front of the rest keeps its value
zDone          long                                                     ! ZeroTerm deleted a 0 term
 code
  if pStart < 1 then pStart = 1.
  if pEnd < 1 or pEnd > Records(self.tokens)
    pEnd = records(self.tokens)
  end

  endOffset = records(self.tokens) - pEnd
L loop
    if pEnd <= pStart then break.                         ! cannot simplify
    svPEnd = pEnd
    do FoldAdditions
    pEnd = records(self.tokens) - endOffset               ! adjust end position in case there have been deletions
    if svPEnd <> pEnd then cycle.                         ! transformations made

    loop
      ! see if we can do simple evaluate - see EvalSpan
      do EvalSpan
      if calc._DataEnd and calc._DataEnd < 15             ! too many digits might mean rounding
        self.SetTok(pStart,calc.valuePtr[1 : calc._DataEnd])
        loop pEnd = pEnd to pStart+1 by - 1
          self.DeleteTok(pEnd)
        end
        break L
      end

      svMEnd = pEnd
      do FoldMultiplications
      pEnd = records(self.tokens) - endOffset             ! adjust end position in case there have been deletions
      if svMEnd = pEnd then break.                        ! no transformations made
    end

    pEnd = records(self.tokens) - endOffset               ! adjust end position in case there have been deletions
    !if svPEnd <> pEnd then cycle.  ! transformations made

    if svPEnd = pEnd then break.                          ! no transformations made
  end


FoldMultiplications routine                               ! includes divisions - calculate adjacent tokens eg. 4*6 or 10/2
! note only positive numbers are folded here eg. 4*5 but not 4*-5
!
! A '^' AGAINST EITHER END OF THE TRIPLE STOPS THE FOLD. Exponentiation binds tighter than
! multiplication, division and modulus, so in  2 * 3 ^ 2  the '^' takes the 3 and  2 * 3  is
! not a subexpression at all: folding it to 6 turns a length of 18 into 36. The same applies
! on the left - in  3 ^ 2 * 4  the 2 belongs to the '^'. FoldAdditions does not need this
! guard because it only folds at a delimiter, and the delimiter table holds none of
! * / % ^ - so this walk is the one place where a tighter operator can be stepped over.
! A '/' OR '%' ON THE LEFT OF THE TRIPLE STOPS IT TOO. Multiplication, division and modulus
! are ONE level, read left to right, so in  n / 2 * 3  the 2 belongs to the '/' and the value
! is  (n / 2) * 3 : folding  2 * 3  gives  n / 6 , a different number. A '*' on the left is
! safe in front of a '*' or a '/' -  n * 2 * 3  is  n * 6  whichever pair goes first - but NOT
! in front of a '%':  n * 4 % 3  is  (n * 4) % 3 , which is 0 when n is 3, and folding  4 % 3
! gives  n * 1 . Anything on the right is safe, because the walk takes the leftmost triple
! first, which is the order the language reads.
! Whole expressions go through Clarion's own EVALUATE first, which honours precedence; this
! routine only runs when that returned nothing, which is when a variable is present.
! A SIGN IN FRONT OF THE FIRST NUMBER IS LOOKED PAST. A minus straight after an operator is a
! unary minus and belongs to that operator's operand, so in  n / -2 * 3  the -2 is the right
! operand of the '/' and the value is (n / -2) * 3 - the same as the '/' with no sign at all.
 data
state    long
isNumber long
isMult   long
isMod    long
ltOp     string(2)
adjHat   long                                             ! a '^' sits against this triple - leave it alone
adjDiv   long                                             ! a '/' or '%' sits on the LEFT of this triple - leave it alone
 code

  loop x = pStart to pEnd

    Get(self.Tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break.   ! no more tokens

    case val(self.tokens.type)
    of 73  orof 78                                          ! 'I' orof 'N'
      isNumber = TRUE
      isMult = FALSE
    of 109                                                  ! 'm'          ! multiplication type - tok is * or / or %
      isNumber = FALSE
      isMult = TRUE
    else
      isNumber = FALSE
      isMult = FALSE
    end

    case state
    of 0                                                    ! looking for first numeric token
      if isNumber
        state = 1
        calc.SetValue(self.tokens.tok)
      end
    of 1                                                    ! looking for multiplication type
      if isMult
        state = 2
        calc.cat(self.tokens.tok,1)
        isMod = choose(self.tokens.tok = '%')
      elsif ~isNumber
        state = 0
      end
    of 2                                                    ! looking for second number
      if isNumber
        adjHat = false
        adjDiv = false
        if x - 3 >= pStart
          if self.GetTok(x - 3) = '^' then adjHat = true.   ! <first> is the right operand of a '^'
          if self.GetTok(x - 3) = '/' then adjDiv = true.   ! <first> is the right operand of a '/' - the same
          if self.GetTok(x - 3) = '%' then adjDiv = true.   !   level as the '*', and the language reads it first
          ltOp = self.GetTok(x - 3)
          if isMod and ltOp = '*' then adjDiv = true.
        end
        if x - 4 >= pStart                                  ! a SIGN in front of <first>: look past it to
          if inlist(self.GetTok(x - 3), '+', '-')           !   the operator it belongs to
            case self.GetTok(x - 4)
            of '^' orof '/' orof '%'
              adjDiv = true
            of '*'
              if isMod then adjDiv = true.
            end
          end
        end
        if x + 1 <= pEnd
          if self.GetTok(x + 1) = '^' then adjHat = true.   ! <second> is the left operand of a '^'
        end
        get(self.Tokens, x)                                 ! GetTok moved the record pointer - put it back
        if adjHat or adjDiv
          state = 0
          cycle
        end
        calc.append(self.tokens.tok)
        calc.SetValue(evaluate(calc.getValue()))
        if calc._DataEnd and calc._DataEnd < 15             ! too many digits might mean rounding
          self.setTok(x-2,calc.valuePtr[1 : calc._DataEnd])
          self.DeleteTok(x)
          self.DeleteTok(x-1)
          exit
        end
        state = 1
      else
        state = 0
      end
    end
  end

! A NUMBER IS ADDED TO ANOTHER ONLY WHEN BOTH ARE TERMS OF THE SAME SUM. TermSign decides it from
! the token in front of the number's sign: a minus straight after * / % ^ or after another sign is a
! unary minus that belongs to that operator's operand, so  n * -1 + 5  keeps its -1 and folds no
! further than  n * -1 + 5 . A sum also ends at an operator that binds looser than + and - ('&', a
! comparison, AND, OR, XOR, NOT): the numbers either side of it are in different operands - see
! LooserOp. A 0 term is dropped only where that leaves the value alone - see ZeroTerm.
FoldAdditions routine   ! includes subtractions
 data
prevPlusMinus LONG,AUTO ! indicate if prev token was + or -
currPlusMinus LONG(1)   ! indicate if curr token is + or - NB. assume first is '+'  eg. "4 - 1" is "+4-1"
ready         LONG      ! indicate we have form +number or -number and are ready to see if next token is also + or -
sgKeep        LONG,AUTO ! a ^ or % follows the bracket, so a sign inside it stays there

 code
  calc.free()
  firstNumTok = 0

  x = pStart - 1

  loop
    pEnd = records(self.tokens) - endOffset                                           ! adjust end position in case there have been deletions
    ! if a token deletion has occurred, then exit and start over (is performed in a loop until unchanged)
    if svPEnd <> pEnd then break.

    x += 1
    if x > pEnd then break.

    Get(self.Tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break.                             ! no more tokens

   !!----------------------------------------
   !! temporary code to check that type is correct in case we have moved tok value and not adjusted the type...
    if self.TokenIsAllDigits()
      if self.Tokens.type <> 'I'
        self.TraceIt('Unexpected type for token#' & x & ' value is ' & self.tokens.tok & ' type is [' & self.tokens.type & '] but expected I')
      end
    elsif self.TokenIsDecimal()
      if self.Tokens.type <> 'N'
        self.TraceIt('Unexpected type for token#' & x & ' value is ' & self.tokens.tok & ' type is [' & self.tokens.type & '] but expected N')
      end
    elsif self.TokenIsValidLabel()
      if self.Tokens.type <> vt:label
        self.TraceIt('Unexpected type for token#' & x & ' value is ' & self.tokens.tok & ' type is [' & self.tokens.type & '] but expected b')
      end

    elsif inlist(self.Tokens.tok,'+','-')
      if self.Tokens.type <> 'p'
        self.TraceIt('Unexpected type for token#' & x & ' value is ' & self.tokens.tok & ' type is [' & self.tokens.type & '] but expected p')
      end
    elsif inlist(self.Tokens.tok,'*','/','%')
      if self.Tokens.type <> 'm'
        self.TraceIt('Unexpected type for token#' & x & ' value is ' & self.tokens.tok & ' type is [' & self.tokens.type & '] but expected m')
      end
    elsif self.Tokens.type <> ' '
        self.TraceIt('Unexpected type for token#' & x & ' value is ' & self.tokens.tok & ' type is [' & self.tokens.type & '] but expected blank type')
    end
   !!----------------------------------------

    prevPlusMinus = currPlusMinus
    if self.tokens.type = 'p'                                                         !self.Tokens.tok = '+' or self.Tokens.tok = '-'
      currPlusMinus = TRUE
      if x=pStart and self.tokens.tok = '+'
        ! delete leading + sign
        self.DeleteTok(x)
        self.SetStrBefore(x,'')                                                       ! remove spacing before next token
        cycle
      end
    else
      currPlusMinus = FALSE
    end

    if currPlusMinus or self.Delimiter[val(self.Tokens.tok[1])+1]
      if ready                                                                        ! do we have +number or -number preceding this?
        ready = FALSE
        zDone = false
        if ~firstNumTok then do ZeroTerm.
        if firstNumTok
          do FoldIt
        elsif zDone
          cycle
        else
          firstNumTok = x-1
          if self.getTok(x-2) = '-'
            calc.SetValue(self.getTok(x-2) & self.getTok(x-1))
          else
            calc.SetValue(self.getTok(firstNumTok))
          end
        end
      end
      if currPlusMinus then cycle.
      ! we have a delimiter...

    else
      ready = false
    end

    if currPlusMinus then self.TraceIt('expected CurrPlusMinus to be false here');currPlusMinus = FALSE.

    do LooserOp
    if self.Tokens.tok = '('
      cb = self.MatchLeftBracket('(',')',x)
      if ~cb or cb > pEnd then break.                                                 ! cannot transform further
      if cb < x+4                                                                     ! less than 3 tokens in brackets so cannot transform
        x = cb                                                                        ! skip forward
        cycle
      end
      endTok = cb - 1                                                                 ! exclude the closing bracket for folding contents
      eOff = records(self.tokens) - endTok
      self.FoldStr(x+1,endTok)                                                        ! call recursively over the expression within the brackets
      endTok = records(self.tokens) - eoff                                            ! adjust endTok if folded
      endTok += 1                                                                     ! add 1 to point to closing bracket
      pEnd = records(self.tokens) - endOffset                                         ! adjust end position in case there have been deletions

      if self.getTok(x) <> '(' then self.TraceIt('expecting opening bracket at token ' & x & ' but got ' & self.getTok(x)).
      if self.getTok(endTok) <> ')' then self.TraceIt('expecting closing bracket at token ' & endTok & ' but got ' & self.getTok(endTok)).

      sgKeep = inlist(self.GetTok(x+4), '^', '%')
      if prevPlusMinus and (endTok = x+3 and self.GetTok(x+1) = '-') and ~sgKeep
        case val(self.GetTok(x-1))
        of 43 orof 45                                                                 ! '+' orof '-'
          self.setTok(x-1, choose(self.getTok(x-1) = '+','-','+'))                    ! reverse the sign prior to the brackets
          self.SetTok(x, self.GetTok(x+2))
          self.DeleteToks(x+1, x+3)
          endTok = x
        else
          self.DeleteTok(x+3)
          self.DeleteTok(x)                                                           ! x token is bracket
          endTok -= 2
        end
      end
      if endTok = x+2 and (x=1 or self.Operator[val(self.GetTok(x-1))+1])
        ! there is now only one token in the brackets so remove the brackets, retaining leading StrBefore
        self.SetTok(x, self.getTok(x+1))
        self.DeleteTok(x+2)
        self.DeleteTok(x+1)
        x -= 1
        currPlusMinus = prevPlusMinus                                                 ! as we are going back one token
       ! cycle
      else
        x = endTok                                                                    ! skip to after brackets
      end
    elsif self.Delimiter[val(self.getTok(x))+1]
      ! we have delimiter
      firstNumTok = 0
      currPlusMinus = true                                                            ! pretend we have +

    elsif prevPlusMinus and (self.Tokens.type = vt:Integer or self.Tokens.type = 'N') ! I=integer N=numeric with dec pt
      ! form is +123  or +123.45
      tsX = x ; do TermSign                                                           ! a TERM of the sum? See TermSign
      if tsSg < 0 then cycle.                                                         ! no - its sign belongs to the * / % ^ in front
      if x = pEnd and firstNumTok and firstNumTok < x and self.GetTok(x) <> 0
        x+=1
        do FoldIt
      elsif x = pEnd and self.GetTok(x) = 0 and tsSg = 2
        self.DeleteTok(x)
        self.DeleteTok(x-1)
      else
        ready = true                                                                  ! if following token is + or - then we can evaluate and combine them
      end
    end
  end                                                                                 !loop

foldIt routine
  calc.append(self.getTok(x-2) & self.getTok(x-1))
  calc.SetValue(evaluate(calc.getValue()))

  insertNegative = false
  if calc._DataEnd
    case val(self.GetTok(firstNumTok-1))
    of 43 orof 45                         ! '+' orof '-'
      if calc.GetValue() < 0
        self.setTok(firstNumTok-1,'-')
      else
        self.setTok(firstNumTok-1,'+')
      end
    else
      if calc.GetValue() < 0
        InsertNegative = true             ! insert negative sign
      end
    end
    if insertNegative
      self.setTok(firstNumTok,'-')
      self.AddTok(firstNumTok+1,abs(calc.getValue()))
      self.DeleteTok(x)
      self.DeleteTok(x-1)
      pEnd -= 1
    else
      self.setTok(firstNumTok,abs(calc.getValue()))
      self.DeleteTok(x-1)
      self.DeleteTok(x-2)
      pEnd -= 2
    end

    get(self.Tokens,pointer(self.tokens)) ! restore queue to previous state

  end

! ---- is the number at tsX a TERM of a sum, and what stands in front of it? Into tsSg:
!       0  no sign of its own: it starts the range, or follows a delimiter
!       1  a sign that starts an operand: first in the range, or after a delimiter, a comparison,
!          '&', AND, OR, XOR or NOT
!       2  a sign between two terms - an addition or a subtraction
!      -1  not a term: the sign follows * / % ^ or another sign, so it is a unary minus or plus
!          that belongs to that operator's operand. ----
TermSign routine
  tsSg = 0
  if tsX <= pStart then exit.
  get(self.Tokens, tsX - 1)
  if errorcode() or self.Tokens.type <> vt:plusMinus then exit.
  tsSg = 1
  if tsX - 1 <= pStart then exit.
  get(self.Tokens, tsX - 2)
  if errorcode() or self.Tokens.tok &= NULL then exit.
  case self.Tokens.type
  of vt:plusMinus    orof vt:multiplication orof vt:exponentiation
    tsSg = -1
  of vt:reservedWord
    tsSg = 1
  else
    if ~self.Operator[val(self.Tokens.tok[1])+1] and ~inlist(self.Tokens.tok[1], '(', '[', '{{', ',', ':', '=', ';')
      tsSg = 2
    end
  end

! ---- a 0 in front of token x, which is a sign or a delimiter: drop it where that leaves the value
!      alone, and say so in zDone. Between two terms -  k - 0 + n  - the 0 goes with its own sign.
!      With no term in front of it the 0 has no sign of its own to go with: before a '+' the 0 and
!      the '+' go ( 0 + n  is  n ); before a '-' the '-' stays as the sign of what follows ( 0 - n
!      is  -n ); before anything else the 0 IS the operand - f(a, 0) - and stays. A '-' left that way
!      is a unary minus, which binds tighter than ^ ( -n ^ 2  is  (-n) ^ 2 ), and with % the sign of
!      the answer depends on a compiler setting, so UnarySafe keeps the 0 in front of either. ----
ZeroTerm routine
  data
zFirst long,auto
  code
  zDone = false
  if self.GetTok(x-1) <> 0 then exit.
  tsX = x-1
  do TermSign
  if tsSg = 2
    self.DeleteTok(x-1)
    self.DeleteTok(x-2)
    zDone = true
  elsif tsSg >= 0 and x < pEnd
    zFirst = choose(tsSg = 1, x-2, x-1)
    if self.GetTok(x) = '+'
      self.SetTok(zFirst, self.GetTok(x+1))
      self.DeleteToks(zFirst+1, x+1)
      zDone = true
    elsif self.GetTok(x) = '-'
      do UnarySafe
      if usOK
        self.SetTok(zFirst, '-')
        self.DeleteToks(zFirst+1, x)
        get(self.Tokens, zFirst+1)
        if ~errorcode() and not self.Tokens.strBefore &= NULL and ~self.Tokens.strBefore
          self.SetStrBefore(zFirst+1, '')
        end
        zDone = true
      end
    end
  end

! ---- usOK: nothing after the '-' at token x is a ^ or a % outside brackets, so the '-' may become
!      a unary minus in front of the rest. Checked to the end of the range, not only to the end of
!      the term: a 0 kept that need not have been costs nothing but the fold. A sign straight after
!      the '-' keeps the 0 as well -  0 - -n  stays as it is rather than becoming  --n . ----
UnarySafe routine
  data
usT long,auto
usD long
  code
  usOK = true
  if inlist(self.GetTok(x + 1), '+', '-') then usOK = false.
  loop usT = x + 1 to pEnd
    case self.GetTok(usT)
    of '(' orof '['
      usD += 1
    of ')' orof ']'
      usD -= 1
    of '^' orof '%'
      if usD <= 0 then usOK = false ; break.
    end
  end

! ---- token x is an operator that binds looser than + and - : '&', a comparison, AND, OR, XOR or
!      NOT. The numbers either side of it are in different operands, so none before it is ever
!      added to one after it. Its GET is also what puts the buffer back on token x for the '(' test
!      after the call: the ready block in front of the call leaves it wherever FoldIt or GetTok last
!      read. ----
LooserOp routine
  get(self.Tokens, x)
  if errorcode() or self.Tokens.tok &= NULL then exit.
  if self.Tokens.type = ' ' and self.Operator[val(self.Tokens.tok[1])+1] then firstNumTok = 0.
  if inlist(upper(self.Tokens.tok), 'AND', 'OR', 'XOR', 'NOT') then firstNumTok = 0.

! ---- calc: what EVALUATE makes of tokens pStart to pEnd, or nothing. EVALUATE runs any builtin
!      call it is handed - clip('ab ') comes back as ab, upper('k') as K, today() as the day the
!      tool ran - so a span holding a name followed by '(' is never handed to it, at any depth of
!      the bracket walk. Nor is one holding a string literal or a '&' (39 and 38 below): the
!      answer is text, and written back as a token it loses its quotes. Only a number is kept. ----
EvalSpan routine
  data
esT long,auto
  code
  calc.free()
  loop esT = pStart to pEnd
    get(self.Tokens, esT)
    if errorcode() or self.Tokens.tok &= NULL then exit.
    case val(self.Tokens.tok[1])
    of 39 orof 38
      exit
    of 65 to 90 orof 97 to 122 orof 95 orof 63
      if inlist(upper(self.Tokens.tok), 'AND', 'OR', 'XOR', 'NOT') then cycle.
      if esT < pEnd and self.GetTok(esT + 1) = '(' then exit.
    end
  end
  calc.SetValue(evaluate(self.JoinToks(pStart,pEnd)))
  if ~numeric(calc.getValue()) then calc.free().

! ------------------------------------------------------------------------------------
! By-value front end for InsertString - see the overload below.
! ------------------------------------------------------------------------------------
VitTokenize.InsertString          Procedure(LONG pPos=1, STRING in, BYTE pMid=0) !,virtual
st StringTheory
 code
  st.SetValue(in) ! do NOT clip as may want space before following existing token
  self.InsertString(pPos,st,pMid)

! ------------------------------------------------------------------------------------
! TOKENIZE a string and splice the resulting tokens in at pPos.
!
! The text is parsed by a SCRATCH VitTokenize first, so what gets inserted is real tokens with
! their own type and level marks - not a lump of raw text. That is what lets inserted code be
! matched, re-indented and aligned by later passes exactly like code that was always there,
! and it is why a replacement can safely introduce a structure keyword.
!
! The cost is a second tokenizer per call, so this belongs on the splice path and not inside a
! tight loop.
! ------------------------------------------------------------------------------------
VitTokenize.InsertString          Procedure(LONG pPos=1, StringTheory in, BYTE pMid=0) !,virtual
! tokenize and insert string at a given position
tk   VitTokenize
x    long,auto
recA long,auto                                                                         ! the stream's token count before the splice
e    long,auto                                                                         ! the last token spliced in
 code
  if ~in._DataEnd then return.
  ! 0, or anything past the end, means THE END - this class's convention elsewhere. Clarion's ADD appends
  ! for such a pointer, and the last-to-first splice below would then land the tokens REVERSED; at
  ! records + 1 every later add goes in front of the previous one and the order is kept.
  if pPos < 1 or pPos > self.records() + 1 then pPos = self.records() + 1.

  ! pMid=1 says this text is a FRAGMENT, not the start of a line. Without it the scratch
  ! parses as though it began one, and a leading RETURN, EXIT or ACCEPT is re-classified as a
  ! LABEL - column 1 is the label column - and that type is copied into the real stream, where
  ! nothing ever converts it back. BufColOne asks the caller to say which it is; this is how.
  tk.midLine = pMid
  if ~pMid and pPos > 1                                                                 ! the caller did not say: the token before the splice point tells - anything but a
    get(self.tokens, pPos - 1)                                                          !   line end means the text lands mid-line, and its first word is no label
    if ~errorcode() and not self.tokens.tok &= NULL
      if ~(size(self.tokens.tok) = 1 and self.tokens.tok = '<10>') then tk.midLine = 1. ! the EOL token is the ONE LF byte, written '<10>' - never '<<10>', four characters of text that no token equals, which would read EVERY splice as mid-line
    end
  end
  tk.ParseText(in)
  recA = self.records()

  loop x = tk.records() to 1 by -1
    get(tk.tokens,x)
    clear(self.tokens)
    if tk.Tokens.tok &= null
      ! this should only ever happen on the last token where there is strBefore at end
      if x <> tk.records()
        self.TraceIt('error in VitTokenize.InsertString: null token at position ' & x & ' in string ' & in.getvalue())
      elsif tk.Tokens.strBefore &= null
        self.TraceIt('error in VitTokenize.InsertString: null token and strBefore at position ' & x & ' at end of string ' & in.getvalue())
      else
        ! need to insert strBefore at start of strBefore of following token
        self.PrependStrBefore(pPos, tk.Tokens.strBefore)
      end
      cycle
    end

    self.Tokens.tok &= new string(size(tk.Tokens.tok))
    self.tokens.tok = tk.Tokens.tok

    if not tk.Tokens.strBefore &= NULL
      self.Tokens.strBefore &= new string(size(tk.Tokens.strBefore))
      self.tokens.strBefore = tk.Tokens.strBefore
    end
    self.tokens.type = tk.tokens.type
    self.tokens.level = tk.tokens.level                                                 ! carry the level mark (+/-/'/'x) so spliced keywords are not left blank for same-pass level consumers
    add(self.Tokens,pPos)
?   assert(~errorcode())
  end
  ! THE FRAGMENT ENDED ON `a.b` (mergeTail): the merge its parse could not decide is decided here,
  ! against the token the text now sits in front of - joined unless that is '(', a method call,
  ! exactly as a parse of the whole line joins it. Without this, a rewrite whose new text ends on
  ! `self.sepTxt` would hand the stream three tokens, and every reader of a member as one token
  ! would refuse it on every pass that was left, until the NEXT run parsed the file again.
  if tk.mergeTail
    e = pPos + self.records() - recA - 1                                                ! the last token spliced in
    if e - 2 >= pPos and self.GetTok(e + 1) and self.GetTok(e + 1) <> '('
      self.SetTok(e - 2, self.GetTok(e - 2) & '.' & self.GetTok(e))
      self.DeleteTok(e)
      self.DeleteTok(e - 1)
    end
  end

VitTokenize.GetParms              Procedure(StringTheory pParms,*LONG pStart,*LONG pEnd) !,LONG,virtual
! finds next opening bracket and then gets parameters split into pParms line queue - returns number of parameters
x            long,auto
cb           long                                                                        ! close bracket
 code
  pParms.free(true)                   ! true means also free lines Q

  if pStart < 1 then pStart = 1.
  if pEnd < 1 or pEnd > Records(self.tokens)
    pEnd = records(self.tokens)
  end

  loop x = pStart to pEnd
    Get(self.tokens, x)
    if not self.tokens.tok &= NULL and self.tokens.tok = '('
      pStart = x                      ! set actual start bracket
      break
    end
  end
  if not self.tokens.tok &= NULL and self.tokens.tok = '(' and pStart < pEnd
    cb = self.MatchLeftBracket('(',')',pStart)
  end
  if ~cb or cb > pEnd
    pEnd = 0                          ! indicate no matching end bracket
    return 0                          ! no parameters
  end
  pEnd = cb                           ! set pEnd to closing bracket
  self.JoinToks(pParms,pStart+1,cb-1) ! get parameters into parameter ST object
  pParms.split(',','''-(','''-)',,st:clip,st:left,'-',st:nested)
  return pParms.Records()             ! return number of parameters

!-------------------------------------------------------------------------------------------
VitTokenize.FindTok            Procedure(STRING pStr,LONG pStart=1, LONG pEnd=0, LONG pNoCase=false) !,LONG,virtual
! find tok string within a range of tok #'s
x       long,auto
  code
  if pStart < 1 then pStart = 1.
  if pEnd < 1 or pEnd > records(self.tokens) then pEnd = records(self.tokens).
  if pNoCase
    pStr = upper(pStr)
    if pStr = lower(pStr)
      pNoCase = FALSE
    end
  end

  if pNoCase
    loop x = pStart to pEnd
      Get(self.Tokens,x)
      if errorcode() or self.Tokens.tok &= NULL then break. ! no match
      if upper(self.Tokens.tok) = pStr then return x.
    end
  else
    loop x = pStart to pEnd
      Get(self.Tokens,x)
      if errorcode() or self.Tokens.tok &= NULL then break. ! no match
      if self.Tokens.tok = pStr then return x.
    end
  end
  return 0                                                  ! not found


! ------------------------------------------------------------------------------------
! The number of the first token on source line pSearchLine, or 0 if that line has none.
!
! It walks forward from pStartAtTok and STOPS at the first token past the line, which is only
! correct because the stream is in line order - it is a scan with an early exit, not a search.
! Passing the previous answer as pStartAtTok is what keeps a walk over many lines linear
! rather than quadratic.
!
! A line with no tokens at all - blank, or nothing but trivia - answers 0.
! ------------------------------------------------------------------------------------
VitTokenize.FindFirstTokNumOnLine  Procedure(LONG pSearchLine, LONG pStartAtTok=1) !,LONG,virtual
x          long,auto
  code
  if pStartAtTok < 1 then pStartAtTok = 1.
  loop x = pStartAtTok to records(self.tokens)
    Get(self.Tokens,x)
    if self.Tokens.lineNo < pSearchLine then cycle.
    if self.Tokens.lineNo = pSearchLine then return x.
    !if self.Tokens.lineNo > pSearchLine then break.
    break
  end
  return 0 ! not found

! ------------------------------------------------------------------------------------
! The number of the last token on pSearchLine, or 0 if none.
!
! Defined as "one before the first token of the NEXT line", which is neat and has one corner:
! on the final line of the file there is no next line, so it falls back to checking whether the
! very last token of the stream sits on pSearchLine.
! ------------------------------------------------------------------------------------
VitTokenize.FindLastTokNumOnLine  Procedure(LONG pSearchLine, LONG pStartAtTok=1) !,LONG,virtual
x          long,auto
  code
  x = self.FindFirstTokNumOnLine(pSearchLine+1,pStartAtTok)          ! search for first tok on next line
  if x then return x - 1.                                            ! point to last tok on desired line (prev line)
  get(self.tokens,records(self.tokens))                              ! if not found, see if it matches last token
  if self.Tokens.lineNo = pSearchLine then x = pointer(self.Tokens).
  return x                                                           ! will be 0 if not found

! ------------------------------------------------------------------------------------
! By-value front end - see the overload below.
! ------------------------------------------------------------------------------------
VitTokenize.FindTokInLines      Procedure(STRING pStr,LONG pStartLine=1, LONG pEndLine=0) !,LONG,virtual
  code
  return self.FindTokInLines(pStr, pStartLine, pEndLine)

! ------------------------------------------------------------------------------------
! Find pStr, but only between source lines pStartLine and pEndLine.
!
! It converts the LINE range into a TOKEN range with FindFirst/FindLastTokNumOnLine and then
! hands off to FindTok, so the line bounds cost two scans and the search itself is unchanged.
! ------------------------------------------------------------------------------------
VitTokenize.FindTokInLines      Procedure(*STRING pStr,LONG pStartLine=1, LONG pEndLine=0) !,LONG,virtual
! we first find the start and end tok entries for this line range and then call findTok
startTok   long,AUTO
endTok     long
sx         long,auto ! walk cursor for a boundary line that carries no token
  code
  ! the bounds wanted are ">= pStartLine" and "<= pEndLine", NOT "= pStartLine" and
  ! "= pEndLine+1". A BLANK or COMMENT-ONLY line carries no token of its own - its text lives
  ! in the strBefore of the next real token - so a keyed get on that line number MISSES, and a
  ! blank boundary line is the most ordinary thing in a source file. What a miss would cost:
  !   at the START, `return 0` - the token reported ABSENT from a range that may well hold it;
  !   at the END, endTok left 0, which FindTok reads as "to EOF" - matches handed back from
  !   OUTSIDE the range asked for, which is the worse of the two.
  ! The keyed get is kept as the
  ! fast path; the walk below runs only when it misses.
  if pStartLine > 1
    self.Tokens.lineNo = pStartLine
    get(self.tokens,self.Tokens.lineNo)
    if ~errorcode()
      startTok = pointer(self.Tokens)
?     if ~self.tokens.firstOnLine then stop('ErrorA in FindTokInLines - Token ' & pointer(self.Tokens) & ' = ' & self.tokens.tok & ' not marked as first on line ' & self.Tokens.lineNo & ' (= ' & pStartLine & ')').
    else
      startTok = 0                                    ! no token ON that line - take the first one AFTER it
      loop sx = 1 to records(self.tokens)
        get(self.Tokens,sx)
        if errorcode() then break.
        if self.Tokens.lineNo >= pStartLine
          startTok = sx
          break
        end
      end
      if ~startTok then return 0.                     ! nothing at or after that line at all
    end
  else
    startTok = 1
  end
  if pEndLine
    self.Tokens.lineNo = pEndLine+1                   ! we get first tok on next line then subtract 1
    get(self.tokens,self.Tokens.lineNo)
    if ~errorcode()
?     if ~self.tokens.firstOnLine then stop('ErrorB in FindTokInLines - Token ' & pointer(self.Tokens) & ' = ' & self.tokens.tok & ' not marked as first on line ' & self.Tokens.lineNo & ' (= ' & pStartLine & ')').
      endTok = pointer(self.Tokens) - 1
    else
      loop sx = startTok to records(self.tokens)      ! no token on the line after the range -
        get(self.Tokens,sx)                           !   walk to the first token PAST it
        if errorcode() then break.
        if self.Tokens.lineNo > pEndLine
          endTok = sx - 1
          break
        end
      end
      ! none past it: the range runs to the end of the stream, and endTok 0 says exactly that
    end
  end

  return self.FindTok(pStr,startTok,endTok,st:nocase) !note: endTok of 0 means to EOF

!-------------------------------------------------------------------------------------------
VitTokenize.FindSeq               Procedure(STRING in,LONG pStart=1, LONG pEnd=0) !,LONG,virtual
! find a sequence of tokens. 1st char is sep character,
!                            2nd Char is noCaseChar,
!                            3rd char is ws char that indicates white space ok before token
! returns 1st token# of sequence
! eg. ',^ .,^slice, (' would match ".Slice(" and ".SLICE  (" etc
!
! note %* is wildcard and means anything goes
!      %4 would mean go back 4 tokens and see if that token matches
!
st           StringTheory,static,thread
state        long                                                                 ! which token are we looking for?
prevState    long                                                                 ! previous state
seqFrom      long                                                                 ! the token this attempt STARTED on - where a failed attempt rewinds to
i            long,auto
x            long,auto
ans          long
!L:NoCase     long,auto
SeqNum       long,auto
FirstVarType string(1)
 code
  if size(in) < 4
  ! need at least 3 special chars at front + 1 char data
    return 0
  end

  if self.sepChar <> in[1]      or                                                       |
     self.noCaseChar <> in[2]   or                                                       |
     self.wsBeforeChar <> in[3] or                                                       |
     self.searchSt.GetValue() <> in[4 : size(in)]

    ! different search string... need to re-parse search string and fill searchQ

    self.FreeSearchQ()
    self.searchSt.SetValue(in)
    self.sepChar      = self.searchSt.valueptr[1]
    self.noCaseChar   = self.searchSt.valueptr[2]
    self.wsBeforeChar = self.searchSt.valueptr[3]
    self.searchSt.RemoveFromPosition(1,3)
    self.searchSt.split(self.sepChar)
    loop i = 1 to self.searchSt.records()
    ! fill searchQ with sequence of tokens and whether there can be white-space before the token and if token is case sensitive
      st.SetValue(self.searchSt.GetLine(i))
      x = 1
      self.searchQ.noCase = TRUE ; self.searchQ.wsBefore = TRUE                          ! explicit init - without it an un-prefixed/1-char element inherits the previous element's QUEUE BUFFER residue (order-dependent).
                                                                                         !   PERMISSIVE defaults: the patterns are written for elements that are ws-tolerant + caseless unless
                                                                                         !   their prefix says otherwise (strict FALSE defaults would drop conversions such as CheckCaseStatements')

      if st._DataEnd > 2                                                             and |
         ((st.valueptr[1] = self.noCaseChar   and st.valueptr[2] = self.wsBeforeChar) or |
          (st.valueptr[1] = self.wsBeforeChar and st.valueptr[2] = self.noCaseChar))
        x = 3
        self.searchQ.noCase = TRUE
        self.searchQ.wsBefore = TRUE
      elsif st._DataEnd > 1
        self.searchQ.noCase = FALSE
        ! check if we just have one option
        if st.valueptr[1] = self.noCaseChar
          x = 2
          self.searchQ.noCase = TRUE
          self.searchQ.wsBefore = FALSE
        elsif st.valueptr[1] = self.wsBeforeChar
          self.searchQ.noCase = FALSE
          self.searchQ.wsBefore = TRUE
          x = 2
        end
      end

      if x > st._DataEnd
        self.TraceIt('invalid sequence string passed to vitTokenize.findSeq: ' & in)
      else
        self.searchQ.tok &= new string(st._DataEnd - x + 1)
        if self.searchQ.noCase
          self.searchQ.tok = upper(st.valueptr[x : st._DataEnd])
          if self.searchQ.tok = lower(self.searchQ.tok)
            self.searchQ.noCase = FALSE
          end
        else
          self.searchQ.tok = st.valueptr[x : st._DataEnd]
        end
!        self.searchQ.tok2 &= NULL
        add(self.SearchQ)
      end
    end
  end

  if pStart < 1 then pStart = 1.
  if pEnd < 1 or pEnd > Records(self.tokens)
    pEnd = records(self.tokens)
  end

!  state = 0
!  firstVarType = ''
  loop x = pStart to pEnd+1
    if x > pEnd and state < records(self.searchQ) then break.
    if state = records(self.searchQ)
      if FirstVarType
        ! we must check the type of the first var
        x -= state                                                                       ! reset to first token
        Get(self.tokens, x)
        ! lookup the variable name in tokens variables queue to see if it is defined with this type
        if self.vars.varName <> self.tokens.Tok
          self.vars.varName = self.tokens.Tok
          get(self.vars,+self.vars.varName)
          if errorcode()
            self.vars.varTypes = ''
          end
        end
        if self.vars.varTypes[1] = FirstVarType or st.findByte(val(FirstVarType), 1,, self.vars.varTypes)
          ! matches OK
          ans = x
          break
        else
          state = 0                                                                      ! not a match - go back and start all over
          cycle
        end
      else
        ans = x-state                                                                    ! we have match - return first token in the sequence
        break
      end
    elsif ~state and FirstVarType
      seqFrom = x                                                                        ! this attempt starts here
      state = 1                                                                          ! we skip first parm of type and check it at end if/when everything else matches
      cycle
    else
      if ~state then seqFrom = x.                                                        ! this attempt starts here
      state += 1
    end
    if state <> prevState
      get(self.searchQ,state)
      prevState = state
    end
    Get(self.tokens, x)
    if not self.tokens.strBefore &= NULL and ~self.searchQ.wsBefore                      ! not allowed to have ws before token
      do SeqRestart
      cycle
    end
    if self.tokens.Tok &= NULL then break.
    if size(self.searchQ.Tok) > 1 and self.searchQ.Tok[1] = '%'                          ! substitution parameter
      if self.searchQ.Tok[2] = '*'
      ! wildcard anything OK
      elsif self.searchQ.Tok[2] = vt:Literal
        if self.tokens.type = vt:Literal
          ! matches OK
        else
          do SeqRestart                                                                  ! not a match - restart one token after this attempt began
        end
      elsif inrange(val(self.searchQ.Tok[2]),48,57)                                      ! is 2nd char a digit?
        seqNum = self.searchQ.Tok[2 : size(self.searchQ.Tok)]                            ! strip off first char to give how many toks to go back for required value
        if ~seqNum then self.TraceIt('invalid seqNum ' & self.searchQ.Tok[2 : size(self.searchQ.Tok)] & ' in vitTokenize.FindSeq : ' & in).
        if (self.searchQ.noCase  and upper(self.getTok(x-seqNum)) = upper(self.getTok(x))) or |
           (~self.searchQ.noCase and self.getTok(x-seqNum) = self.getTok(x))
          ! matches OK
        else
          do SeqRestart                                                                  ! not a match - restart one token after this attempt began
        end
      elsif state > 1
        ! lookup the variable name in tokens variables queue to see if it is defined with this type
        if self.vars.varName <> self.tokens.Tok
          self.vars.varName = self.tokens.Tok
          get(self.vars,+self.vars.varName)
          if errorcode()
            self.vars.varTypes = ''
          end
        end
        if self.vars.varTypes[1] = self.searchQ.Tok[2] or st.findByte(val(self.searchQ.Tok[2]), 1,, self.vars.varTypes)
          ! matches OK
        else
          do SeqRestart                                                                  ! not a match - restart one token after this attempt began
        end
      else                                                                               ! state = 1
        firstVarType = self.searchQ.Tok[2]
      end
    else
      if self.searchQ.Tok = choose(~self.searchQ.noCase, self.tokens.tok, upper(self.tokens.tok))
        ! matches OK
      else
        do SeqRestart                                                                    ! not a match - restart one token after this attempt began
      end
    end
  end
  return ans

! ---- a failed attempt restarts one token after the token this attempt BEGAN on, not one
!      token after the one that FAILED. Without the rewind the scan walks straight past any
!      OVERLAPPING match: [val,(,chr,(] against `val(val(chr(65)))` would find nothing, because
!      the failure at the second `val` would consume it and the real match starting THERE would
!      never be tried. The FirstVarType arm above backtracks too - it says `x -= state` before
!      it resets - so the ordinary mismatch paths and that arm agree. It cannot loop: seqFrom
!      is set only where state leaves 0, so each restart
!      begins one token further along than the last and attempt starts strictly increase.
!      seqFrom = 0 means state never left 0, and then there is nothing to rewind to.
!      (dataless routine -> no CODE statement)
SeqRestart routine
  if seqFrom then x = seqFrom.
  state = 0

! ------------------------------------------------------------------------------------
! Diagnostic sink for this class: writes pStr to the debug viewer when traceIt is set, appends
! it to LogFn when Logit is set, and halts on it when StopIt is set. All three ship off, so a
! call to this is inert unless somebody is debugging.
! ------------------------------------------------------------------------------------
VitTokenize.TraceIt  PROCEDURE(STRING pStr)
  code
  if self.traceIt then self.searchSt.trace(pStr).
  if self.Logit   then self.searchSt.saveFileA(pStr & '<13,10>', self.LogFn, 1). ! write the file each time in case we crash (slow)
  if self.StopIt  then stop(pStr).

! ------------------------------------------------------------------------------------
! Render one character for a diagnostic - '(CR)', '(LF)', '(TAB)', or the character itself -
! each with its hex value. Unprintables below 32 come back as '.' plus the hex, so a trace line
! can never be mangled by the very bytes it is reporting.
! ------------------------------------------------------------------------------------
VitTokenize.DescribeChar Procedure(STRING pChar)
 code
  case val(pChar)
   of 13
    return '(CR) hex='& self.searchSt.byteToHex(val(pChar))
   of 10
    return '(LF) hex='& self.searchSt.byteToHex(val(pChar))
   of 9
    return '(TAB) hex='& self.searchSt.byteToHex(val(pChar))
  else
    if val(pChar) < 32
      return '"." hex='& self.searchSt.byteToHex(val(pChar))
    else
      return '"' & pChar & '" hex='& self.searchSt.byteToHex(val(pChar))
    end
  end

! ------------------------------------------------------------------------------------
! Write the whole token stream to a file, one token per line, for eyeballing.
!
! With no filename it invents a timestamped one in the CURRENT DIRECTORY, and that is
! deliberate: a default under a fixed folder such as .\testdata\ fails wherever that folder
! does not exist - trace-only (both off by default), so the documented level-census
! workflow would produce nothing at all, silently. The CLI always passes an
! explicit name, so this default is for embedders. This is the tool of choice
! when a level census does not balance: the dump shows each token's level mark, and the
! structure that opened without closing is visible in a way the source is not.
! ------------------------------------------------------------------------------------
VitTokenize.DumpTokens Procedure(<string pFilename>) !,virtual ! dump token list to disk - optionally provide file name
dumpST  StringTheory
dumpSeq long,static,thread                           ! add seq number as clock resolution is such that a file would be overwritten if time diff < .01 secs
dumpFn  string(512),auto                             ! the name actually used, so the failure message can NAME it
  code
  dumpSeq += 1
  self._List(dumpST,true)        ! st tokens - one per line - second parm is show extra columns
  dumpFn = choose(~omitted(pFilename), pFilename, 'tokenize file on ' & clip(left(format(today(),@d12))) & |
           ' at ' & clip(left(format(clock(),@T05))) & format(clock()%100,@n02) & format(dumpSeq%1000,@n03) & '.txt')
  if not dumpSt.SaveFile(dumpFn)
    self.dumpFailed = 1          ! the caller can SEE the failure; TraceIt alone ships off
    self.TraceIt('save of tokenize file failed: ' & clip(dumpFn))
  else
    self.dumpFailed = 0
  end


!===============================================================================================
! LitSafeCut: the nearest offset INSIDE a literal token at which it may legally be cut,
! measured from the start of the literal's inner text, or 0 if there is nowhere safe.
!
! Cutting a Clarion literal is ordinary and legal -
!     st.setValue('first half ' & |
!                 'second half')
! - the two halves concatenate to exactly the original value. The one rule is that the cut must
! not land INSIDE an atomic unit of the source spelling:
!     ''    an escaped quote        - cutting between them ends the string early
!     <<    an escaped less-than
!     {{    an escaped brace
!     <13,10>  an escape GROUP      - cutting inside it produces two meaningless fragments
! This walks the source characters and only ever returns a boundary BETWEEN whole units. It is
! about not corrupting the text, nothing else: WIDTH here is source characters as written, which
! is what you see on screen. ComputeLitLen answers the other question - what the literal decodes
! to at runtime - and is deliberately not used.
!===============================================================================================
VitTokenize.LitSafeCut  Procedure(LONG pTokNumber, LONG pWant)
inner   long,auto ! length of the text between the quotes
z       long,auto
gEnd    long,auto
gz      long,auto
best    long
bestD   long
bd      long,auto
bnd     long,auto ! the boundary: last char of the unit just consumed
  code
  get(self.tokens, pTokNumber)
  if errorcode() then return 0.
  if self.Tokens.tok &= NULL then return 0.
  if size(self.Tokens.tok) < 12 then return 0.            ! nothing worth cutting
  if self.Tokens.tok[1] <> '''' then return 0.
  if self.Tokens.tok[size(self.Tokens.tok)] <> '''' then return 0.
  inner = size(self.Tokens.tok) - 2
  z = 1
  loop while z <= inner
    case val(self.Tokens.tok[z + 1])                      ! inner character z
    of 39                                                 ! <single quote>
      z += 2                                              ! '' escaped quote - atomic
    of 60                                                 ! '<'
      if z + 2 <= inner and self.Tokens.tok[z + 2] = '<<'
        z += 2                                            ! << escaped less-than - atomic
      else
        gEnd = 0
        loop gz = z + 1 to inner
          if self.Tokens.tok[gz + 1] = '>' then gEnd = gz ; break.
        end
        if gEnd
          ! ---- an escape GROUP is not really atomic. A long one
          !      splits at any of its commas, because two groups concatenate to the same bytes:
          !          '<0,1,2,3,4,5>'   ==   '<0,1,2>' & '<3,4,5>'
          !      Without this a literal that IS one long group has nowhere to cut, and the
          !      line stays wide. Offered as a NEGATIVE offset so SplitLongLiteral can tell the
          !      two cut shapes apart: the comma is REPLACED by '>>' ... '<<', not just cut at.
          loop gz = z + 1 to gEnd - 1
            if self.Tokens.tok[gz + 1] <> ',' or          |
               gz < 4 or inner - gz < 4
              cycle
            end
            bd = gz - pWant
            if bd < 0 then bd = -bd.
            bd += 8                                       ! a plain boundary is tidier - prefer it when close
            if gz < pWant then bd += 4.                   ! see the LONGER-FIRST note in PickBreak
            if ~best or bd < bestD
              bestD = bd
              best  = -gz                                 ! NEGATIVE = cut inside an escape group
            end
          end
          z = gEnd + 1                                    ! then step over the whole group
        else
          z += 1                                          ! a stray '<' - treat as one character
        end
      end
    of 123                                                ! '{{'
      if z + 2 <= inner and self.Tokens.tok[z + 2] = '{{'
        z += 2
      else
        z += 1
      end
    else
      z += 1
    end
    ! ---- A REPEAT COUNT BELONGS TO THE CHARACTER IN FRONT OF IT. ----
    ! `'*{20}'` is twenty asterisks: the count applies to the character before the brace, so
    ! that character and its `{...}` are ONE unit. Cutting between them leaves a count with
    ! nothing to repeat on the second half, and cutting inside the braces splits the number
    ! itself - the first half then carries an unclosed brace and does not compile. Absorb the
    ! whole group into the unit just consumed, so no boundary is ever offered inside it. This
    ! is the same forward scan the escape group above uses for its '>'. A doubled `{{` is an
    ! escaped brace and never a count, so it is left for the case arm; a '{' with no closing
    ! '}' is left alone too, and the boundary in front of it stays available.
    if z <= inner and self.Tokens.tok[z + 1] = '{{'
      if z + 1 > inner or self.Tokens.tok[z + 2] <> '{{'
        gEnd = 0
        loop gz = z + 1 to inner
          if self.Tokens.tok[gz + 1] = '}' then gEnd = gz ; break.
        end
        if gEnd then z = gEnd + 1.
      end
    end
    ! ---- THE BOUNDARY IS z - 1: THE LAST CHARACTER OF THE UNIT JUST CONSUMED. ----
    ! Every branch above has already stepped z PAST its unit, so z names the first character
    ! of the NEXT one - which has not been examined yet. Offering z as the cut therefore puts
    ! the boundary one character right of the one actually verified, and the character it
    ! lands in front of may be the first half of an atomic pair: on 'aaaa''bbbb' it would
    ! fall BETWEEN the two quotes of the escaped pair, ending the string early and making source
    ! that does not compile. Keep the one closest to pWant.
    if z > inner then break.
    bnd = z - 1
    if bnd < 4 or inner - bnd < 4 then cycle.             ! never leave a stub
    bd = bnd - pWant
    if bd < 0 then bd = -bd.
    ! break on a WORD boundary where there is one. The first half ends
    ! with inner character z, so a cut whose last character is a space reads as
    !     'so it is plain text ' & |
    !     'and must never be closed'
    ! instead of splitting `text` down the middle. A penalty rather than a hard rule, so a
    ! literal with no spaces at all - a long escape group, a path, a key - can still be cut.
    if self.Tokens.tok[bnd + 1] <> ' ' then bd += 16.
    if bnd < pWant then bd += 4.                          ! see the LONGER-FIRST note in PickBreak
    if ~best or bd < bestD
      bestD = bd
      best  = bnd                                         ! POSITIVE = plain boundary cut
    end
  end
  return best

!===============================================================================================
! SplitLongLiteral: cut the literal at pTokNumber after pCutAt inner characters, into
!     'first part' & |
!     'second part'
! The value is unchanged; only where the line ends changes. Returns 1 if it cut.
!
! WHY THIS IS SAFE HERE AND NOWHERE ELSE. BUILTIN CombineAdjacentLiterals turns 'abc' & '123'
! back into 'abc123'. Inside the fixpoint the two would fight - split, recombine, re-split, no
! convergence. SplitWideLines runs AFTER convergence, beside AlignComments, where nothing
! re-matches, so the recombiner never sees this. Do not move it earlier.
!===============================================================================================
VitTokenize.SplitLongLiteral Procedure(LONG pTokNumber, LONG pCutAt, LONG pIndentW)
inner   long,auto
c       long,auto
a       stringTheory
b       stringTheory
sb      stringTheory
  code
  get(self.tokens, pTokNumber)
  if errorcode() then return 0.
  if self.Tokens.tok &= NULL then return 0.
  inner = size(self.Tokens.tok) - 2
  if ~pCutAt then return 0.
  if pCutAt > 0
    ! ---- plain boundary cut:  'first' & | / 'second' ----
    if pCutAt >= inner then return 0.
    a.setValue('''' & self.Tokens.tok[2 : pCutAt + 1] & '''')
    b.setValue('''' & self.Tokens.tok[pCutAt + 2 : inner + 1] & '''')
  else
    ! ---- cut INSIDE an escape group, at one of its commas. The comma itself is
    !      replaced by a closing '>>' on the first half and a fresh opening '<<' on the second,
    !      so  '<<0,1,2,3>>'  becomes  '<<0,1>>' & '<<2,3>>'  - the same bytes, two groups.
    !      Text either side of the group in the same literal rides along untouched:
    !          'abc<<0,1,2,3>>def'  ->  'abc<<0,1>>'  &  '<<2,3>>def'
    c = -pCutAt
    if c < 2 or c >= inner then return 0.
    a.setValue('''' & self.Tokens.tok[2 : c] & '>''')
    b.setValue('''<<' & self.Tokens.tok[c + 2 : inner + 1] & '''')
  end
  self.SetTok(pTokNumber, a.getValue())                    ! strBefore OMITTED = the leading trivia is kept
  sb.setValue(' |<13,10>')
  if pIndentW > 0 then sb.append(all(' ', pIndentW)).      ! the statement's own indent, then two more, so
  sb.append('  ')                                          !   the continuation sits under what it continues
  self.AddTok(pTokNumber + 1, b.getValue(), sb.getValue()) ! the second half, on its own line
  ! ... joined by an '&' with ONE SPACE in front of it. The space matters: without it the
  ! output reads 'te'& | with the ampersand jammed against the quote. It is passed straight to
  ! AddTok, which guards its trivia with size() - a truthiness guard would read a lone ' ' as
  ! BLANK and drop it. This call is what exercises that guard: if AddTok did not keep the
  ! space, every literal this splits would come out as 'te'& |.
  self.AddTok(pTokNumber + 1, '&', ' ')
  return 1

!===============================================================================================
! break a line that is wider than pMaxWidth at a sensible point, and keep breaking until
! every piece fits. COSMETIC ONLY: this runs after the fixpoint has converged, beside
! AlignComments and ClipLines. It changes where the line ENDS, never what the code says.
!
! WHY IT EXISTS. A conversion whose flattened result is too wide, and whose
! original continuations cannot be carried into the replacement, is still DONE - the wide line
! is taken and tidied here. Refusing such a conversion instead would silently lose the
! transform, which is the wrong trade for a tool other people run: a wide line that gets split
! afterwards beats a conversion that never happened.
!
! WHERE IT BREAKS, in order of preference - most natural Clarion wrap first:
!   1. after a ',' at the outermost call depth
!   2. before a top-level '&' in a concatenation
!   3. after the opening '(' of the outermost call
!   4. no candidate at all -> LEAVE THE LINE WIDE. Never guess.
!
! A LITERAL IS SPLIT ONLY IN PHASE 2, and only here. It is legal Clarion -
!     st.setValue('...150...' & |
!                 '...150...')
! - but BUILTIN CombineAdjacentLiterals ('abc' & '123' -> 'abc123') is ungrouped and on by
! default, so a literal split anywhere the fixpoint can still see it would be recombined and the
! two would fight for ever. THIS pass runs after convergence, which is what makes the cut safe;
! that is the reason it lives here and must not be moved.
!
! WIDTH IS WHAT YOU SEE ON SCREEN: source characters as written. A literal's escape sequences
! ('' for a quote, '<<13,10>>' for CRLF) are counted as the characters they occupy in the source,
! not as what they decode to. ComputeLitLen answers the other question - runtime length - and is
! deliberately not used here.
!
! Balanced pieces: the line is cut into ceil(width / max) roughly equal parts rather than
! greedily filling to the limit, so a 400-char line becomes two ~200s, not a 200 and a 200-ish
! remainder that then splits again unevenly.
!
! ONE CALL HAS TO SETTLE IT, AND THAT TAKES MORE THAN ONE SWEEP. Depth is counted per PHYSICAL
! line and reset at every line ending, so what is a candidate depends on breaks already made:
! in `packet.Append('a' & self.Make(x,y,z))` the commas sit at depth 2 and are not candidates,
! but once the '&' break has put `& self.Make(x,y,z)` on a line of its own they are at depth 1
! and they are. A single sweep would therefore stop holding pieces it WOULD break if it
! looked again - and a second run of the tool would break them, so a run (an --style=extreme
! one above all, whose deferred slice widens lines after the fixpoint) would not settle.
! So the two phases sweep until a
! sweep breaks nothing. The cap is a runaway guard, not a budget; hitting it leaves lines long,
! which is the same safe outcome as having no candidate at all.
!===============================================================================================
VitTokenize.SplitWideLines Procedure(LONG pMaxWidth)
lineQ       QUEUE,PRE(lq) ! one row per CODE token on the line under test
tokIx         LONG        !   its token index
endW          LONG        !   rendered width of the line UP TO AND INCLUDING it
depth         LONG        !   paren depth AFTER it
openW         LONG        !   column of the '(' still open there, 0 at depth 0 - --contindent=bracket
kind          LONG        !   0 = not a candidate, 1 = after ',', 2 = after the operator, 3 = after '('
used          BYTE        !   already broken here
            END
cutQ        QUEUE,PRE(cq) ! segment boundaries, in width order: 0 .. lineWidth
atW           LONG
            END
x           long,auto
w           long
dep         long
minAmp      long          ! shallowest depth any '&' reached on this line
opW         long,dim(32)  ! the column of the '(' open at each depth - --contindent=bracket
indSt       stringTheory  ! the line's indent, as text: what follows the last line feed in front of its first token, however deep
contInd     byte          ! the line ending here is CONTINUED - a bar in its trivia
cz          long,auto     ! scan cursor over a broken token's own trivia
sb          stringTheory
q           long,auto
z           long,auto
lastNl      long,auto
tk1         string(1),auto
firstTok    long
split       long
segS        long,auto
segE        long,auto
brCol       long,auto     ! --contindent=bracket: the column a break inside a bracket picks up at
brB         long,auto     !   the ONE column every break in the statement in hand picks up at - 0 means the indent
brRoom      long,auto     !   the width a piece may have: the first line from its own start, every other from brB
brStart     long,auto     !   where the piece in hand starts - the width at the last planned cut
brEnd       long,auto     !   the width of the whole line
brCut       long,auto     !   the lineQ row the piece in hand ends at
planQ       QUEUE,PRE(bp) ! the breaks the bracket plan makes, in line order
row           LONG        !   the lineQ row
            END
best        long,auto
bestScore   long,auto
sc2         long,auto
mid         long,auto
prevW       long,auto
progress    byte
lz          long,auto     ! phase 2 - long-literal splitting
lw          long
lindW       long          ! the line's indent, as a WIDTH - what SplitLongLiteral is handed
lsTok       long          ! first token of the STATEMENT lz sits in
lq3         long,auto     !   and the walk back to find it
lstart      long
lcut        long,auto
sweep       long,auto     ! sweeps of the two phases made so far
sweepStart  long,auto     !   what `split` stood at as this sweep began
frontOp     byte,auto     ! the axis wants the operator at the FRONT of a break
flushOp     byte,auto     ! and lined up under the word that opens the statement
picOn       byte          ! inside a @P or @K picture - see PicTrack
picEnd      string(1)     !   the letter that closes it, in its own case
picEsc      byte          !   @K only: the next character is a display character
picHere     byte          !   this token is a piece of a picture
  code
  if pMaxWidth < 40 then return 0.
  ! Decided once. self.contOp cannot change inside this call and both places that ask sit
  ! inside loops, so this is a test held rather than a test repeated.
  frontOp = choose(self.contOp >= 2)  ! 2 front, 3 front-and-flush - both open the next line
  flushOp = choose(self.contOp = 3)
  loop sweep = 1 to 12
    sweepStart = split
    do OnePass
    if split = sweepStart then break. ! a sweep that breaks nothing - the file has settled
  end
  return split

! ---- ONE sweep: phase 1 breaks between tokens, phase 2 cuts a literal that is the whole payload ----
OnePass routine
  free(lineQ) ; free(cutQ)
  w = 0 ; dep = 0 ; firstTok = 0 ; indSt.free() ; minAmp = 0
  loop x = 1 to records(self.tokens)
    get(self.tokens, x)
    if errorcode() then break.

    if not self.Tokens.strBefore &= NULL
      lastNl = 0
      loop z = 1 to size(self.Tokens.strBefore)
        if self.Tokens.strBefore[z] = '<10>' then lastNl = z.
      end
      if lastNl
        ! IS THE LINE THAT ENDS HERE CONTINUED? Its bar sits in this token's trivia ahead of the
        ! newline, so the answer is local. If it is, the author has ALREADY chosen where the
        ! continuations of this statement go - it is the indent that follows - and a break we add
        ! should join them instead of opening a column of its own two past the statement.
        contInd = 0
        loop z = 1 to lastNl
          if self.Tokens.strBefore[z] = '|' then contInd = 1.
        end
        if contInd
          indSt.free()
          if lastNl < size(self.Tokens.strBefore) then indSt.setValue(self.Tokens.strBefore[lastNl + 1 : size(self.Tokens.strBefore)]).
        end
        do FinishLine
        w = size(self.Tokens.strBefore) - lastNl
        indSt.free()
        if w then indSt.setValue(self.Tokens.strBefore[lastNl + 1 : size(self.Tokens.strBefore)]).
      else
        ! THE FIRST TOKEN AFTER AN EXPLICIT <10> TOKEN CARRIES THE WHOLE INDENT, and there is no
        ! newline in it to find - the newline was a token of its own, and the branch above only
        ! fires when the line end is INSIDE strBefore. Both spellings occur. Without this the
        ! indent would never be captured for the second kind, and ApplyBreak would write
        ! its continuation at column 3 - `sb.append('  ')` plus the broken token's own single
        ! space - however deep the statement is: a statement 16 columns in would have its
        ! remainder land at 3, beside the author's own continuations far to the right.
        if ~w and ~indSt._DataEnd
          indSt.setValue(self.Tokens.strBefore)
        end
        w += size(self.Tokens.strBefore)
      end
    end

    if self.Tokens.tok &= NULL then cycle.
    if size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>'
      do FinishLine
      w = 0 ; indSt.free() ; contInd = 0
      cycle
    end

    if ~firstTok then firstTok = x.
    tk1 = self.Tokens.tok[1]
    picHere = picOn
    do PicTrack
    if picOn then picHere = 1.
    if picHere then tk1 = ' '.
    if size(self.Tokens.tok) = 1 and tk1 = '(' then dep += 1.
    w += size(self.Tokens.tok)
    if size(self.Tokens.tok) = 1 and tk1 = '(' and dep >= 1 and dep <= 32
      opW[dep] = w                                        ! this '(' sits in column w, so its first argument starts at w + 1
    end

    clear(lineQ)
    lq:tokIx = x
    lq:endW  = w
    lq:kind  = 0
    lq:used  = 0
    if picHere                                            ! a piece of a picture - see PicTrack
    elsif size(self.Tokens.tok) = 1
      case val(tk1)
      of 44                                               ! <comma>
        if dep = 1 then lq:kind = 1.                      ! outermost call's argument separator
      of 38                                               ! '&'
        ! A CONCATENATION, OR THE MARKER OF A REFERENCE TYPE? `label &StringTheory,PRIVATE` and
        ! the `),&StringTheory` return type of a prototype carry the same single-char token, and
        ! a break after that one would part the type from its ampersand across a continuation.
        ! The token after a concatenation's '&' has a blank in front of it; the type a reference
        ! marker introduces is glued to it. Only the former is a candidate, and only a candidate
        ! sets the shallowest depth the line's candidates are held to.
        get(self.tokens, x + 1)
        if ~errorcode() and not self.Tokens.strBefore &= NULL
          lq:kind = 2                                     ! depth decided AFTER the line is known - see FinishLine
          if ~minAmp or dep < minAmp then minAmp = dep.
        end
        get(self.tokens, x)
      of 40                                               ! '('
        if dep = 1 then lq:kind = 3.                      ! the opening paren of the outermost call
      end
    else
      ! AND / OR are the natural place to wrap a long condition, and a parser is
      ! full of them - `if (UPPER(x) = 'PROCEDURE' OR UPPER(x) = 'FUNCTION')` has no other
      ! candidate at all and would stay 102 characters wide. Break BEFORE the word, like '&', so
      ! the operator starts the continuation line and the condition reads down the page.
      ! Only the OPERATOR is a candidate, so only the operator may set the shallowest depth
      ! the candidates on this line are held to.
      case upper(self.Tokens.tok)
      of 'AND' orof 'OR'
        if self.Tokens.type = vt:reservedWord
          lq:kind = 2
          if ~minAmp or dep < minAmp then minAmp = dep.
        end
      end
    end
    if size(self.Tokens.tok) = 1 and tk1 = ')' then dep -= 1.
    lq:depth = dep
    lq:openW = 0
    if dep >= 1 and dep <= 32 then lq:openW = opW[dep].       ! the bracket a break HERE would be inside
    add(lineQ)
  end
  do FinishLine
  free(lineQ) ; free(cutQ)

  ! ---- PHASE 2: lines that are STILL over-wide because their payload is one long literal.
  !      Phase 1 breaks only BETWEEN tokens, so a 140-character literal is indivisible to it,
  !      and at --width=100 a line holding one has no candidate left however it is
  !      laid out. A literal can be cut; this does it.
  !      Walk BACKWARDS: SplitLongLiteral inserts two tokens, which shifts every index AFTER
  !      the cut, so going back to front leaves the not-yet-visited part of the queue untouched.
  !      Same reason the delete loops elsewhere in this file iterate backwards.
  loop lz = records(self.tokens) to 1 by -1
    do LitLineWidth                                           ! lz -> lw (line width), lind (its indent), lstart (first token)
    if lw <= pMaxWidth then cycle.
    ! the '?' refusal has to be HERE as well. Phase 1 declining to break a '?'
    ! line just hands it to this phase, which cuts the literal instead and produces the
    ! same broken continuation - so this phase is guarded exactly as FinishLine is.
    if lstart
      get(self.tokens, lstart)
      if ~errorcode() and not self.Tokens.tok &= NULL
        if size(self.Tokens.tok) = 1 and self.Tokens.tok[1] = '?' then cycle.
        ! *** A PRE-PROCESSOR DIRECTIVE'S STRING IS NOT AN EXPRESSION. ***
        ! Cutting a literal joins the halves with '&', and Clarion's pre-processor does
        ! not evaluate that. Measured against the compiler (TestData\eqprobe2.clw):
        !     INCLUDE('EQUA' & 'TES.CLW')
        !     error : cif$fileopen EQUA.CLW The system cannot find the path specified
        ! It takes the FIRST literal and discards the rest WITHOUT A WORD - so the
        ! output names a different file, and says nothing. A wrong program, not a
        ! refusal and not a compile error, from a line whose only fault was being long.
        !
        ! The compiler proper evaluates it perfectly well, so the refusal is exactly
        ! this narrow. EQUATE values, STRING initial values, NAME() and DRIVER()
        ! attributes are all safe to cut - DRIVER('TOP' & 'SPEED') reaches the linker
        ! as TOPSPEED (TestData\eqprobe3.clw). And only the CUT is refused: a '|'
        ! continuation on a directive line is legal, so phase 1 may still break one
        ! (TestData\eqprobe4.clw).
        !
        ! OMIT / COMPILE / SECTION are refused on the MECHANISM rather than on a
        ! measurement - the same pre-processor reads them, ahead of the expression
        ! evaluator. No probe separates the two readings for those, because a
        ! terminator of '**' and one of '**zz' both end a block at a line reading
        ! `**zz`. Refusing costs a long line staying long; the other way silently
        ! omits a different amount of somebody's program.
      end
    end
    ! THE DIRECTIVE TEST ASKS THE STATEMENT, NOT THE PHYSICAL LINE. Phase 1 breaks between
    ! tokens and writes the break as trivia, so an indented OMIT can reach here with its
    ! terminator literal starting a CONTINUATION line - and the first token of that line is
    ! the literal itself, which sails past a guard that reads the line. Walking back to the
    ! last EOL TOKEN lands on the word that opened the statement instead: a continuation
    ! never produces one, whether the author wrote it or phase 1 did.
    ! The '?' refusal above stays on the physical line, because that marker really does
    ! belong to the line rather than to the statement.
    lsTok = 0
    loop lq3 = lz to 1 by -1
      get(self.tokens, lq3)
      if errorcode() then break.
      if not self.Tokens.tok &= NULL and size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>'
        lsTok = lq3 + 1
        break
      end
      lsTok = lq3
    end
    if lsTok
      get(self.tokens, lsTok)
      if ~errorcode() and not self.Tokens.tok &= NULL
        case upper(self.Tokens.tok)
        of 'INCLUDE' orof 'OMIT' orof 'COMPILE' orof 'SECTION'
          cycle
        end
      end
    end
    get(self.tokens, lz)
    if errorcode() then cycle.
    if self.Tokens.tok &= NULL then cycle.
    if self.Tokens.type <> vt:literal then cycle.
    if size(self.Tokens.tok) < 24 then cycle.             ! not the reason the line is wide
    ! aim at the middle of the INNER text - the quotes are not part of it, and
    ! LitSafeCut measures its offsets from inside them
    lcut = (size(self.Tokens.tok) - 2) / 2
    lcut = self.LitSafeCut(lz, lcut)
    if ~lcut then cycle.                                  ! nowhere safe - leave the line wide
    if self.SplitLongLiteral(lz, lcut, lindW) then split += 1.
  end

! ---- width of the physical line token lz sits on, and that line's indent ----
LitLineWidth routine
  data
lq2  long,auto
lz2  long,auto
lnl  long,auto
  code
  lw = 0 ; lindW = 0 ; lstart = 0                           ! lstart: 0 rather than the LAST line's, so a caller can test it
  loop lq2 = lz to 1 by -1                                  ! back to the start of this line
    get(self.tokens, lq2)
    if errorcode() then break.
    if not self.Tokens.strBefore &= NULL
      lnl = 0
      loop lz2 = 1 to size(self.Tokens.strBefore)
        if self.Tokens.strBefore[lz2] = '<10>' then lnl = lz2.
      end
      if lnl
        lindW = size(self.Tokens.strBefore) - lnl
        lstart = lq2
        break
      end
    end
    if not self.Tokens.tok &= NULL and size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>'
      lstart = lq2 + 1                                      ! the newline is a TOKEN here, so the indent is the
      get(self.tokens, lstart)                              !   whole of the next token's trivia rather than the
      if ~errorcode() and not self.Tokens.strBefore &= NULL ! tail of this one's
        lindW = size(self.Tokens.strBefore)
      end
      break
    end
    lstart = lq2
  end
  loop lq2 = lstart to records(self.tokens)                 ! forward to the end of it
    get(self.tokens, lq2)
    if errorcode() then break.
    if lq2 > lstart and not self.Tokens.tok &= NULL and size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>' then break.
    if lq2 > lstart and not self.Tokens.strBefore &= NULL
      ! a PHYSICAL line also ends where a newline appears inside the NEXT token's
      ! trivia - that is exactly what phase 1 writes when it breaks a line (' |' + CRLF + indent).
      ! Stopping only at an EOL token would measure straight through those breaks and return the
      ! width of the whole LOGICAL statement, so phase 2 would see lines as over-wide that phase 1
      ! had already brought under the limit and split their literals for nothing: a
      ! st.Replace(...) would have its commas broken correctly and then two literals cut as well.
      lnl = 0
      loop lz2 = 1 to size(self.Tokens.strBefore)
        if self.Tokens.strBefore[lz2] = '<10>' then lnl = lz2.
      end
      if lnl then break.
    end
    if not self.Tokens.strBefore &= NULL
      if lq2 > lstart
        lw += size(self.Tokens.strBefore)
      end
    end
    if not self.Tokens.tok &= NULL then lw += size(self.Tokens.tok).
  end
  lw += lindW                                               ! THE INDENT IS PART OF THE LINE. clip() of an all-spaces indent is empty, so measured that
                                                            !   way it adds nothing, and a line pushed over the limit by its indent alone stays whole.

! ---- the line just ended: cut it until every piece fits, or nothing more helps ----
FinishLine routine
  if ~records(lineQ) then do ResetLine ; exit.
  get(lineQ, records(lineQ))
  if lq:endW <= pMaxWidth then do ResetLine ; exit.
  ! NEVER SPLIT A LINE THAT BEGINS WITH '?'. The marker belongs to the PHYSICAL
  ! line, so a continuation of it is not marked and the compiler reads the tail as a
  ! statement of its own. Splitting one produces source Clarion rejects - a 200-plus
  ! character '?' debug line would come back as
  !     ?     if ~self.tokens.firstOnLine then stop('...' & |
  !        & self.tokens.tok & ...
  ! and every token of the second line would be an error - one that only a BUILD shows,
  ! never a check of the text. Leaving the line long
  ! is the right trade - it is the same refusal the splitter already makes when there is
  ! nowhere sensible to break.
  if firstTok
    get(self.tokens, firstTok)
    if ~errorcode() and not self.Tokens.tok &= NULL
      if size(self.Tokens.tok) = 1 and self.Tokens.tok[1] = '?' then do ResetLine ; exit.
    end
  end

  ! an '&' is a candidate only at the SHALLOWEST depth it reaches on this line.
  ! DO NOT test `dep = 0` here. In `st.SetValue(a & b & c)` every '&' sits at depth 1 because
  ! it is inside the call, so no '&' would ever qualify and the line would break after the '('
  ! instead - leaving `st.SetValue( |` and a 171-char remainder.
  loop q = 1 to records(lineQ)
    get(lineQ, q)
    if lq:kind = 2 and lq:depth <> minAmp
      lq:kind = 0
      put(lineQ)
    end
  end

  free(cutQ)
  cq:atW = 0 ; add(cutQ)       ! the line starts here
  get(lineQ, records(lineQ))
  cq:atW = lq:endW ; add(cutQ) ! ... and ends here

  ! --contindent=bracket: ONE ANSWER PER STATEMENT. BracketPlan asks, before anything is cut,
  ! whether the whole statement can be laid out under its bracket - every piece after the
  ! first starting at the bracket column and none of them over the width - and plans the cuts
  ! if it can: each line as LONG as it can be, cut at the last argument comma that still fits.
  ! When it cannot (an argument wider than the room under the bracket, or a bracket that opens
  ! too far right), the WHOLE statement takes the indent below, so a statement never comes back
  ! with its continuations in two columns. A line the author already continued, and the flush
  ! operator form, are never planned: they have a column of their own.
  brB = 0
  if self.contBracket and ~contInd and ~flushOp then do BracketPlan.
  if brB
    loop q = 1 to records(planQ)
      get(planQ, q)
      best = bp:row
      do ApplyBreak
    end
    do ResetLine
    exit
  end

  ! keep cutting the WIDEST over-wide segment until nothing helps. Do NOT compute
  ! ceil(width/max) breaks up front from the ORIGINAL width and then stop measuring: one
  ! poorly-placed break leaves a piece still far over the limit and nothing looks again.
  loop
    progress = 0
    loop q = 1 to records(cutQ) - 1
      get(cutQ, q)     ; segS = cq:atW
      get(cutQ, q + 1) ; segE = cq:atW
      if segE - segS <= pMaxWidth then cycle.
      do PickBreak             ! segS/segE -> best (token index) or 0
      if ~best then cycle.
      do ApplyBreak
      progress = 1
      break                    ! boundaries moved - restart the scan
    end
    if ~progress then break.
  end
  do ResetLine

! ---- best candidate strictly inside segS..segE, nearest the middle, kind 1 preferred ----
PickBreak routine
  best = 0 ; bestScore = 0
  mid = (segS + segE) / 2
  loop q = 1 to records(lineQ)
    get(lineQ, q)
    if ~lq:kind or lq:used then cycle.
    prevW = lq:endW               ! every kind cuts AFTER its token - see ApplyBreak
    ! EXCEPT a FRONT operator, which opens the NEXT line: the piece then ends where the
    ! token BEFORE it ended, and scoring it at lq:endW would measure a line that is never
    ! written, because the operator is not on it. The row is re-read afterwards, since the
    ! kind is wanted again below.
    if frontOp and lq:kind = 2
      if q = 1 then cycle.
      get(lineQ, q - 1)
      prevW = lq:endW
      get(lineQ, q)
    end
    if prevW <= segS + 12 or      |   ! refuse a stub like `st.SetValue( |`
       segE - prevW <= 12         !   at either end - a break that helps nobody
      cycle
    end
    sc2 = prevW - mid
    if sc2 < 0 then sc2 = -sc2.
    sc2 += (lq:kind - 1) * 24     ! a ',' is worth ~24 chars of distance over an '&', and '&' over a '('
    ! LONGER FIRST : when a cut cannot be even, put the LONGER piece on
    ! the first line - a full line followed by a short one reads better than the reverse. So a
    ! candidate BEFORE the midpoint (which would shorten the first piece) carries a small
    ! penalty. Deliberately small: it breaks ties and nudges near-ties, and never overrides a
    ! candidate that is genuinely closer to the middle or of a better KIND.
    if prevW < mid then sc2 += 4.
    if ~best or sc2 < bestScore
      bestScore = sc2
      best = q                    ! the lineQ ROW, resolved to a token in ApplyBreak
    end
  end

! ---- insert the continuation at the chosen candidate and record the new boundary ----
ApplyBreak routine
  get(lineQ, best)
  lq:used = 1
  put(lineQ)
  sb.setValue(' |<13,10>')
  ! --contindent=bracket: A BREAK INSIDE A BRACKET PICKS UP UNDER THE FIRST ARGUMENT, one past
  ! the bracket it broke inside, rather than two past the line's own indent:
  !     stFormatMessage(ulong dwFlags, ulong lpSource, ulong dwMessageId, |
  !                     ulong nSize, ulong Arguments), ulong, raw, pascal
  ! THE COLUMN IS DECIDED ONCE PER STATEMENT, by BracketPlan in FinishLine, and brB holds the
  ! answer for every break in it: the bracket column when the whole statement fits under the
  ! bracket, 0 - the indent - when any piece would not. A decision taken per break, with the
  ! splitter cutting the widest segment again and again, would answer differently as the
  ! remainder shrinks and send a statement back with its continuations in three columns; and a
  ! bracket column taken without asking whether the LAST piece fits would leave a line over the
  ! width. Both are what the plan exists to prevent. An operator break belongs to the contop axis
  ! and is left to it, and a line whose continuations the AUTHOR already placed still joins
  ! those, which is the better answer where it applies.
  brCol = brB
  if brCol
    sb.append(all(' ', brCol))                 ! under the first argument
  else
    if indSt._DataEnd then sb.append(indSt).
    if ~contInd and ~flushOp                   ! two past the statement - unless we are joining
      sb.append('  ')                          !   continuations the author already placed, in which
    end                                        !   case land exactly on their column; or flush, which
  end                                          !   lines the operator up under the statement itself
  ! THE END FORM CUTS AFTER ITS TOKEN, INCLUDING THE OPERATOR. A concatenation or a wrapped
  ! condition ends its line with the operator and the bar - `expr & |` - and picks the next line
  ! up with the operand. Cutting BEFORE the operator instead would leave it at the start of the
  ! continuation, which is a second spelling of the same statement and reads as scrappy beside the
  ! rows the author wrote by hand.
  ! AlignComments carries a padPrev flag whose whole purpose is the pair `& |`, set for exactly
  ! '&', 'AND' and 'OR' immediately before a bar, so that the two move as one unit. Those are
  ! precisely the tokens marked kind 2 here. The FRONT form (contOp 2 and 3) is the one
  ! exception, handled below: the bar goes in the operator's own leading trivia, so the operator
  ! opens the continuation. BuiltinContOp sets tk.contOp for both forms, so the splitter and the
  ! aligner always agree on which spelling is in force.
  z = lq:tokIx + 1
  prevW = lq:endW
  ! FRONT form puts the bar in the leading trivia of the OPERATOR itself, so the operator
  ! opens the continuation instead of closing the line above it, and the boundary moves back
  ! with it. The chosen row is restored afterwards.
  if frontOp and lq:kind = 2 and best > 1
    z = lq:tokIx
    get(lineQ, best - 1)
    prevW = lq:endW
    get(lineQ, best)
  end
  get(self.tokens, z)
  if ~errorcode()
    if self.Tokens.strBefore &= NULL
      self.SetStrBefore(z, sb.getValue())
    else
      ! THE BROKEN TOKEN CARRIES ITS OWN LEADING SPACE - the one that separated it from what
      ! is now the line above. Kept, it sits on top of the indent and the joined line lands one
      ! column right of the continuations it was supposed to join. Drop it, but only when it is
      ! nothing but spaces: this trivia can hold a comment, and that must survive.
      ! brCol joins this for the same reason: the bracket column is exact, and a leading space on
      ! top of it puts every wrapped argument one column right of the first one.
      if contInd or flushOp or brCol
        cz = 1
        loop while cz <= size(self.Tokens.strBefore)
          if self.Tokens.strBefore[cz] <> ' ' then break.
          cz += 1
        end
        if cz > size(self.Tokens.strBefore)
          self.SetStrBefore(z, sb.getValue()) ! all spaces - the indent replaces it
        else
          self.SetStrBefore(z, sb.getValue() & self.Tokens.strBefore[cz : size(self.Tokens.strBefore)])
        end
      else
        self.SetStrBefore(z, sb.getValue() & self.Tokens.strBefore)
      end
    end
    split += 1
  end
  cq:atW = prevW
  add(cutQ)
  sort(cutQ, cq:atW)

! ---- --contindent=bracket: can the WHOLE statement be laid out under its bracket? If so, plan
!      the cuts - each line as long as it can be - and set brB; if not, leave brB at 0 so every
!      break takes the indent. The bracket is the one the first argument comma sits inside; a
!      comma at the outermost depth inside a DIFFERENT bracket on the same line does not join
!      the plan. Only commas cut here - a piece too wide to fit between two of them is the plan
!      giving up, not a reason to cut it elsewhere. ----
BracketPlan routine
  data
bz   long,auto
  code
  free(planQ)
  brB = 0
  loop bz = 1 to records(lineQ)
    get(lineQ, bz)
    if lq:kind = 1 and lq:openW > 1 then brB = lq:openW ; break.
  end
  if ~brB then exit.
  get(lineQ, records(lineQ))
  brEnd   = lq:endW
  brStart = 0
  loop
    brRoom = choose(~brStart, pMaxWidth, pMaxWidth - brB) ! the first line from its own start, every other from the bracket
    if brEnd - brStart <= brRoom then break.              ! the rest fits, and the last piece carries no bar - the plan is complete
    brRoom -= 2                                           ! a piece that is cut ends with ' |', and those two count
    brCut = 0
    loop bz = 1 to records(lineQ)                         ! the LAST comma of the bracket that still fits
      get(lineQ, bz)
      if lq:kind <> 1 or lq:openW <> brB then cycle.
      if lq:endW <= brStart then cycle.
      if lq:endW - brStart > brRoom then break.           ! rows are in line order: nothing after this fits either
      brCut = bz
    end
    if ~brCut                                             ! a piece wider than the room under the bracket -
      brB = 0                                             !   the whole statement takes the indent instead
      free(planQ)
      exit
    end
    bp:row = brCut
    add(planQ)
    get(lineQ, brCut)
    brStart = lq:endW
  end

ResetLine routine
  free(lineQ)
  free(cutQ)
  firstTok = 0
  dep = 0
  minAmp = 0
  picOn = 0
  picEsc = 0

! ---- A PICTURE IS ONE WORD TO THE COMPILER, but the tokenizer hands a delimited one over in
!      pieces:  @P<#,###P  arrives as  @P < # , ###P . Its comma would be an argument comma to
!      OnePass, and a break there ends the picture early, so the line no longer compiles.
!      PicTrack follows a @P or @K picture from the token that opens it to the token holding
!      its closing letter - the same letter in the same case; under @K a '\' makes the next
!      character a display character. picHere marks every token from the opener to the closer:
!      none of them is a place to break, and tk1 is blanked so a bracket or a comma inside the
!      picture is read as the text it is. A picture never runs past its line, so ResetLine
!      ends one. ----
PicTrack routine
  data
pz    long,auto
pFrom long,auto
  code
  if picOn
    pFrom = 1
  else
    if size(self.Tokens.tok) < 2 or tk1 <> '@' then exit.
    if ~inlist(upper(self.Tokens.tok[2]), 'P', 'K') then exit.
    picOn = 1
    picEnd = self.Tokens.tok[2]
    picEsc = 0
    pFrom = 3
  end
  loop pz = pFrom to size(self.Tokens.tok)
    if picEsc
      picEsc = 0
    elsif self.Tokens.tok[pz] = '\' and upper(picEnd) = 'K'
      picEsc = 1
    elsif self.Tokens.tok[pz] = picEnd
      picOn = 0
      break
    end
  end

! ---- --cmtwrap=<n>: SPLIT a trailing comment whose line would pass n, and JOIN plain
!      continuation rows back onto it while they fit. Split and join together make this a
!      REFLOW to width n: run it again and nothing changes; move the column and it settles.
!      The marker stays in its column and continuation text sits two characters in from the
!      first row's text - '!' and three spaces, the usual way a comment is continued.
!
!      A JOIN takes only rows at the anchor's column whose text is indented, is not blank, and
!      does not begin like a bullet, a number or a `name = value` item. Anything else is
!      structure the author meant, and it stays where it is. A split is BALANCED, as
!      SplitWideLines is: the rows a comment needs are cut to similar lengths, the first a little
!      longer when they cannot be equal - never one full row and a stub. A word longer than the
!      room stays whole.
!
!      It works on the token stream the way ClipLines does. A line ending is its own '<10>'
!      token and a trailing comment is the tail of THAT token's strBefore, so the anchor is
!      one token, and each continuation row is one more '<10>' token whose strBefore is the
!      whole row. Splitting adds such tokens after the anchor; joining deletes them. No code
!      token is ever touched. The row count changes, so line numbers are re-stamped after.
!      The comment's words, and their order, never change.
VitTokenize.WrapComments  Procedure(LONG pWidth)
st        StringTheory ! a token's strBefore
wt        StringTheory ! the comment text, joined
gap       StringTheory ! the anchor's trivia before the marker
pfx       StringTheory ! the marker and the spaces after it
newAll    StringTheory ! the rows as they would be written, CRLF-joined
oldAll    StringTheory ! the rows as they are, the same way
row       StringTheory ! one continuation row's text
x         long,auto    ! the token walk. Not a LOOP counter: the stream is edited under it
j         long,auto
p         long,auto
col       long,auto    ! column the next token's strBefore starts at, 1-based
sCol      long,auto    !   ... and where this one's started
lastNl    long,auto    ! offset of the last newline inside strBefore, 0 = none
mCol      long,auto    ! the marker's column
k         long,auto    ! marker offset in strBefore, 1-based
pre       long,auto    ! length of the prefix: the marker and the spaces after it
room      long,auto    ! characters of text a row may carry
cut       long,auto    ! where a row is cut
nPass     long,auto    ! continuation rows under the anchor
nNew      long,auto    ! rows written
nRows     long,auto    ! rows the text still needs, at the continuation room
target    long,auto    ! the even share of it per row, rounded up
best      long,auto    ! the space nearest that share, and its score
bestSc    long,auto
sc        long,auto
roomC     long,auto    ! characters a CONTINUATION row may carry
lastCode  long         ! where the code of the row that anchors the comment field ended, 0 = no field
bad       byte,auto
changed   long
svPtr     long,auto
  code
  if pWidth < 20 then return 0.
  svPtr = pointer(self.tokens)
  col = 1
  x = 1
  loop while x <= records(self.tokens)
    get(self.tokens, x)
    if errorcode() then break.
    sCol = col
    lastNl = 0
    if not self.Tokens.strBefore &= NULL
      loop p = 1 to size(self.Tokens.strBefore)
        if self.Tokens.strBefore[p] = '<10>' then lastNl = p.
      end
      if lastNl
        col = size(self.Tokens.strBefore) - lastNl + 1
      else
        col += size(self.Tokens.strBefore)
      end
    end
    if self.Tokens.tok &= NULL
      x += 1
      cycle
    end
    if not (size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>')
      col += size(self.Tokens.tok)
      x += 1
      cycle
    end
    ! ---- a line ending: its strBefore holds the trailing comment, if there is one --------
    col = 1
    ! AN ANCHOR IS ANY COMMENT ROW IN THE COMMENT FIELD WHOSE TEXT IS NOT INDENTED - code in
    ! front of it or not. The field is what lies right of the code of the last commented code
    ! row; a blank line, a code row with no comment or a margin comment ends it. A whole-line
    ! row with indented text continues the comment above it and is taken up by that anchor;
    ! one with a single space after its marker is a comment of its own and wraps on its own.
    ! A whole-line row that follows no code is a banner: a column-1 row is left alone.
    if self.Tokens.strBefore &= NULL or lastNl
      lastCode = 0
      x += 1
      cycle
    end
    st.setValue(self.Tokens.strBefore)
    k = 0
    loop p = 1 to st._DataEnd
      if st.valuePtr[p] = '|' then break.                                         ! a continuation bar - not a plain comment
      if st.valuePtr[p] = '!'
        k = p
        break
      end
    end
    if ~k
      lastCode = 0
      x += 1
      cycle
    end
    mCol = sCol + k - 1
    if self.Tokens.firstOnLine
      ! a whole-line row: a banner or a margin comment ends the field; a continuation is
      ! taken up by its anchor; anything else is an anchor of its own
      if mCol < 2 or ~lastCode or mCol <= lastCode
        lastCode = 0
        x += 1
        cycle
      end
      if k + 2 <= st._DataEnd and st.valuePtr[k + 1] = ' ' and st.valuePtr[k + 2] = ' '
        x += 1
        cycle
      end
    else
      lastCode = sCol - 1
    end
    pre = 1
    loop p = k + 1 to st._DataEnd
      if st.valuePtr[p] <> ' ' then break.
      pre += 1
    end
    if k + pre > st._DataEnd                                                      ! a bare marker with nothing after it
      x += 1
      cycle
    end
    ! k = 1 is `code!` with no gap at all, and a [1 : 0] slice runs BACKWARDS in Clarion
    gap.free()
    if k > 1 then gap.setValue(st.valuePtr[1 : k - 1]).
    pfx.setValue(st.valuePtr[k : k + pre - 1])
    wt.setValue(st.valuePtr[k + pre : st._DataEnd])
    wt.clip()
    oldAll.setValue(st.valuePtr[k : st._DataEnd])
    oldAll.clip()
    ! ---- the continuation rows under it: '<10>' tokens whose whole row is a comment at mCol
    nPass = 0
    loop j = x + 1 to choose(~self.cmtSplitOnly, records(self.tokens), 0)         ! --cmtsplit=: no continuation row is gathered, so nothing is joined
      get(self.tokens, j)
      if errorcode() then break.
      if self.Tokens.tok &= NULL then break.
      if not (size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>') then break.
      if ~self.Tokens.firstOnLine or self.Tokens.strBefore &= NULL then break.
      st.setValue(self.Tokens.strBefore)
      if st._DataEnd < mCol + 3 then break.                                       ! room for the marker, two spaces and a character
      if st.valuePtr[mCol] <> '!' then break.
      bad = 0
      loop p = 1 to mCol - 1
        if st.valuePtr[p] <> ' '
          bad = 1
          break
        end
      end
      if bad then break.
      if st.valuePtr[mCol + 1] <> ' ' or st.valuePtr[mCol + 2] <> ' ' then break. ! text must be indented
      row.setValue(st.valuePtr[mCol + 1 : st._DataEnd])
      row.trim()
      if ~row._DataEnd then break.                                                ! a blank '!' row is a paragraph break
      do Refused
      if bad then break.
      wt.append(' ' & row.getValue())
      oldAll.append('<13,10>' & clip(st.valuePtr[mCol : st._DataEnd]))
      nPass += 1
    end
    ! ---- the reflow ----------------------------------------------------------------------
    newAll.free()
    nNew = 0
    room = pWidth - (mCol - 1) - pre
    if room < 1 then room = 1.
    roomC = pWidth - (mCol - 1) - 4
    if roomC < 1 then roomC = 1.
    loop
      cut = 0
      if wt._DataEnd > room
        ! BALANCED, as SplitWideLines is: the rows this text still needs at the narrower
        ! continuation room, then the even share of it per row - rounded UP, so the first row
        ! is the longer one when they cannot be equal - and the space nearest that share. A
        ! candidate before the share carries the splitter's small penalty.
        nRows = int((wt._DataEnd + roomC - 1) / roomC)
        if nRows < 2 then nRows = 2.
        target = int((wt._DataEnd + nRows - 1) / nRows)
        best = 0 ; bestSc = -1
        loop p = 2 to room + 1                                                    ! a space at p cuts a first row of p - 1
          if wt.valuePtr[p] <> ' ' then cycle.
          sc = p - 1 - target
          if sc < 0 then sc = -sc.
          if p - 1 < target then sc += 4.
          if bestSc < 0 or sc < bestSc
            bestSc = sc
            best = p
          end
        end
        cut = best
        if ~cut then cut = wt.findByte(32, room + 2).                             ! no space fits: the first after, the word stays whole
        ! never cut so that the remainder starts with something the join would refuse - a
        ! bullet, a number, a `name = value` entry - or the second run would not re-join what
        ! the first split, and the split would never settle. Move on to the next space.
        loop while cut
          row.setValue(wt.valuePtr[cut + 1 : wt._DataEnd])
          row.trim()
          do Refused
          if ~bad then break.
          p = wt.findByte(32, cut + 1)
          if ~p then break.
          cut = p
        end
      end
      if nNew then newAll.append('<13,10>').
      if ~cut
        newAll.append(choose(nNew = 0, pfx.getValue(), '!   ') & wt.getValue())
        nNew += 1
        break
      end
      newAll.append(choose(nNew = 0, pfx.getValue(), '!   ') & clip(wt.valuePtr[1 : cut - 1]))
      nNew += 1
      wt.removeFromPosition(1, cut)
      wt.trim()
      room = roomC
    end
    ! ---- write it, when it differs from what is there ----------------------------------
    if newAll._DataEnd and newAll._DataEnd = oldAll._DataEnd and newAll.valuePtr[1 : newAll._DataEnd] = oldAll.valuePtr[1 : oldAll._DataEnd]
      x += 1 + nPass
      cycle
    end
    newAll.split('<13,10>')
    self.SetStrBefore(x, gap.getValue() & newAll.getLine(1))
    if nPass then self.DeleteToks(x + 1, x + nPass).
    loop p = 2 to newAll.records()
      self.AddTok(x + p - 1, '<10>', all(' ', mCol - 1) & newAll.getLine(p))
    end
    changed += 1
    x += newAll.records()
  end
  if changed then self.SetLineNumbers().
  get(self.tokens, svPtr)
  return changed

! ---- sets bad: the text in `row` (trimmed) is one the join must REFUSE - blank, a bullet, a
!      numbered item, or a `name = value` list entry (a word, then '=', then a space). The
!      split asks the same question of every remainder it makes, so the two agree.
Refused routine
  data
rfP  long,auto
  code
  bad = 0
  if ~row._DataEnd
    bad = 1
    exit
  end
  case val(row.valuePtr[1])
  of 45 orof 42 orof 48 to 57                        ! '-' orof '*' orof '0' to '9'
    bad = 1
    exit
  end
  rfP = 1
  loop while rfP <= row._DataEnd
    case val(row.valuePtr[rfP])
    of 97 to 122 orof 65 to 90 orof 48 to 57 orof 95 ! 'a' to 'z' orof 'A' to 'Z' orof '0' to '9' orof '_'
      rfP += 1
    else
      break
    end
  end
  if rfP = 1 then exit.
  loop while rfP <= row._DataEnd and row.valuePtr[rfP] = ' '
    rfP += 1
  end
  if rfP < row._DataEnd and row.valuePtr[rfP] = '=' and row.valuePtr[rfP + 1] = ' ' then bad = 1.

!===============================================================================================
! strip trailing spaces and tabs from every line. AlignComments does not do this: it splits
! with st:Clip only into a LOCAL StringTheory it uses to measure comment columns, and never
! writes that copy back.
!
! WHY IT WORKS IN TRIVIA AND NOT ON TEXT. Trailing whitespace always lives in strBefore, never in
! a token, so no string literal is reachable from here and none can be damaged. Whitespace is
! removed ONLY where it sits immediately before a line ending: whitespace that merely ends a
! strBefore is the gap between two tokens on one line (`a  =  b`) and removing THAT would weld
! them together. Indent is untouched for the same reason - it FOLLOWS a line ending.
!
! LINE ENDINGS. CRLF everywhere: JoinToks always emits '<13,10>' and that is what is written.
! There is no LF-only mode, because LF-only is not valid Clarion source. The
! '<10>' -> '<13,10>' conversions in the OMIT/COMPILE handler (tempST.replace, on text lifted by
! st.slice straight out of the source buffer) and in the `|` continuation branch
! (strBefore.append('<13,10>')) exist to bring bypassed text UP to that
! convention - they are not exceptions to it.
! So the CRLF pair below is the one that should ever fire. The LF-only pair is kept as a cheap
! invariant check: if '<32,10>' ever matches, some path has let a BARE LF into strBefore, which
! is a bug worth finding rather than something to leave unclipped.
!
! NOT GATED, and deliberately so. The caller runs this unconditionally once the
! fixpoint has converged, and counts what it did as a change:
!     if self.tk.ClipLines() then fileChanges += 1.        ! VitEngine, after the cosmetic stages
! So a file whose only defect is trailing whitespace IS rewritten. That is the point of a
! layout-only run over source the rules have nothing to say about - a large file with every
! rule evaluated and nothing else to change is the case this exists for. Clipping IS therefore
! a sufficient reason to rewrite a file on its own; the full reasoning is at
! the call site in VitEngine, above the cosmetic stages.
!===============================================================================================
VitTokenize.ClipLines  Procedure()
stBefore stringTheory,static,thread
x        long,auto
clipped  long
svPtr    long,auto
oldLen   long,auto
keepTail long ! the line ending at this '<10>' token holds an OMIT/COMPILE terminator - its tail stays
mk       long,auto
  code
  svPtr = pointer(self.tokens)                   ! restore the queue position at the end
  loop x = 1 to records(self.tokens)
    get(self.tokens, x)
    if errorcode() then break.
    if self.Tokens.strBefore &= NULL then cycle. ! no trivia on this token at all
    stBefore.setValue(self.Tokens.strBefore)
    oldLen = stBefore._dataEnd
    ! (a) whitespace sitting immediately before an EMBEDDED line ending. Only two paths put a
    !     newline INSIDE strBefore - the `|` continuation branch (strBefore.append('<13,10>')) and
    !     the OMIT/COMPILE slice (tempST.replace) - and both store CRLF, so the CR forms fire.
    !     A file whose OMIT or COMPILE terminator ends in a blank is clipped line by line instead,
    !     and the line holding the terminator keeps its tail: the pre-processor matches the
    !     terminator byte for byte, so the clipped line would no longer end the block - and the
    !     next read of the file, this tool's own included, would omit everything below it.
    if self.ppTerms.records()
      do ClipKeepTerms
    else
      loop while stBefore.replace('<32,13>','<13>') or stBefore.replace('<9,13>','<13>') or stBefore.replace('<32,10>','<10>') or stBefore.replace('<9,10>','<10>').
    end
    ! (b) THE ORDINARY CASE, and the one that matters. A line ending is its OWN TOKEN
    !     (tok.setvalue('<10>') in the scanner) - it is not trivia. So on a normal line the trailing
    !     whitespace is simply the TAIL of the EOL token's strBefore, with no newline byte
    !     after it for (a) to match against. With only (a), trailing whitespace would
    !     be clipped on a continuation line and in an OMIT block and nowhere else - every
    !     ordinary line would keep its tail.
    !     Trimming the tail is safe precisely BECAUSE this token is the newline: anything
    !     immediately before it is by definition at end of line. For any OTHER token, a
    !     trailing strBefore space is the gap between two tokens on one line (`a  =  b`) and
    !     removing it would weld them together - hence the guard.
    !     Comments live in this same strBefore, ahead of the tail, so AlignComments' padding
    !     (which it PREPENDS) is never disturbed.
    if not self.Tokens.tok &= NULL and self.Tokens.tok = '<10>'
      keepTail = 0
      ! the same exception for a tokenised terminator line (COMPILE, a conditional OMIT)
      if self.ppTerms.records() then do TermLineAt.
      ! remove spaces and tabs from end
      ! A .txa MARKER on the line. A code line moved out of column 1 ENDS with its shift mark, so
      ! its own trailing blanks sit just before the mark: they go, as they would in a .clw. A
      ! template line commented out behind a marker is put back exactly, its blanks included.
      if ~keepTail and stBefore._DataEnd >= 2 and stBefore.endsWith('!<251>')
        stBefore.setLength(stBefore._DataEnd - 2)
        stBefore.clip('<32,9>')
        stBefore.append('!<251>')
        keepTail = 1
      end
      if ~keepTail
        loop mk = 250 to 255
          if stBefore.findChars('!' & chr(mk)) then keepTail = 1 ; break.
        end
      end
      if ~keepTail then stbefore.clip('<32,9>').
    end
    if oldLen <> stBefore._dataEnd
      clipped += 1
      self.SetStrBefore(x, stBefore.getValue())     ! empty is fine - SetStrBefore stores &NULL for a zero-size value
    end
  end
  get(self.Tokens, svPtr)
  return clipped

! ---- rule (a) one line at a time: the trivia is cut at its line feeds, every piece but the last
!      ends a line and loses the blanks before its carriage return - unless the piece holds a
!      terminator - and the last piece, the indent in front of the token, is left as it is. ----
ClipKeepTerms routine
  data
ckLn  stringTheory
ckOut stringTheory
ckZ   long,auto
ckCr  long,auto
  code
  ckLn.setValue(stBefore)
  ckLn.split('<10>')
  ckOut.free()
  loop ckZ = 1 to ckLn.records()
    ckLn.setValueFromLine(ckZ)
    if ckZ < ckLn.records()
      ckCr = 0
      if ckLn._DataEnd
        if ckLn.valuePtr[ckLn._DataEnd] = '<13>' then ckCr = 1 ; ckLn.setLength(ckLn._DataEnd - 1).
      end
      if ~self.TermLine(ckLn) then ckLn.clip('<32,9>').
      if ckCr then ckLn.append('<13>').
      ckLn.append('<10>')
    end
    ckOut.append(ckLn)
  end
  stBefore.setValue(ckOut)

! ---- rule (b)'s exception: the text of the physical line this '<10>' token ends - a terminator
!      inside it keeps the tail. When the trivia holds line endings of its own (a swallowed OMIT
!      block, a continuation) the line is what follows the last of them, and the tokens in front
!      of x are on earlier lines; otherwise it is rebuilt from those tokens. The queue is put back
!      on x. ----
TermLineAt routine
  data
tlJ  long,auto
tlNl long,auto
tlLn stringTheory
  code
  tlNl = stBefore._DataEnd
  loop while tlNl > 0
    if stBefore.valuePtr[tlNl] = '<10>' then break.
    tlNl -= 1
  end
  if tlNl
    if tlNl < stBefore._DataEnd then tlLn.setValue(stBefore.valuePtr[tlNl + 1 : stBefore._DataEnd]).
  else
    tlLn.setValue(stBefore)                                              ! the tail itself, blanks and any comment
    loop tlJ = x - 1 to 1 by -1
      get(self.tokens, tlJ)
      if errorcode() then break.
      if not self.Tokens.tok &= NULL
        if self.Tokens.tok = '<10>' then break.                          ! the line before this one
        tlLn.prepend(self.Tokens.tok)
      end
      if not self.Tokens.strBefore &= NULL then tlLn.prepend(self.Tokens.strBefore).
      if self.Tokens.firstOnLine then break.
    end
    get(self.tokens, x)
  end
  if self.TermLine(tlLn) then keepTail = 1.

! ------------------------------------------------------------------------------------
! Does the line hold one of the terminators ParseText remembered? A byte-for-byte search, as
! the pre-processor's own is - the trailing blank is part of what has to be there.
! ------------------------------------------------------------------------------------
VitTokenize.TermLine  Procedure(StringTheory pLine)
z  long,auto
  code
  if ~pLine._DataEnd then return 0.
  loop z = 1 to self.ppTerms.records()
    if pLine.findChars(self.ppTerms.getLine(z)) then return 1.
  end
  return 0

!===============================================================================================
! AlignDeclTypes - line up the TYPE column of a run of declarations.
!
!     proc      &ProcedureNode          proc      &ProcedureNode
!     mainProc &ProcedureNode     ->    mainProc  &ProcedureNode
!     retNode &RawNode                  retNode   &RawNode
!     dbg      StringTheory             dbg       StringTheory
!
! ONLY THE TYPE'S STARTING COLUMN MOVES. This is deliberately NOT the column aligner used for
! CASE labels: declaration lines do not have comparable token shapes - `proc & ProcedureNode`
! is three tokens where `dsqI LONG , AUTO` is four - so lining up column 3 and beyond would
! insert gaps inside a type, e.g. between the '&' and what it points at. The one thing worth
! aligning is where the type BEGINS, and everything after it is left exactly as written.
!
! WHAT COUNTS AS A DECLARATION LINE, and this is the whole risk in the pass: the first token on
! the line is a LABEL in COLUMN 1 - no leading whitespace - which in Clarion is what a data
! declaration looks like and a statement never does. A line whose second token is a reserved
! word (PROCEDURE, FUNCTION, ROUTINE, CLASS, GROUP, QUEUE, RECORD, FILE ...) is not a variable
! declaration but a header or a structure, so it BREAKS the run rather than joining it - other-
! wise `parser.ParseProgram PROCEDURE(...)` would set the column for the locals beneath it and
! push every type out to column 21.
!
! The type goes to column max(label) + 2 - one space past the longest label - and a row moves
! either way to reach it: right when its label is short, LEFT when its type was typed further
! out. The column is computed from the label widths every time, never stepped towards, which is
! what makes a second run over the output change nothing. A run whose types already share one
! column is left exactly as written, and the same worth-it test the CASE aligner uses applies:
! if lining a run up would widen its longest line past the limit, leave it alone.
!===============================================================================================
VitTokenize.AlignDeclTypes Procedure(LONG pMaxWidth)
lnQ     QUEUE,PRE(dq) ! one row per declaration line in the run
labIx     LONG        ! the label token
typIx     LONG        ! the token after it - the type
labW      LONG        ! width of the label
gap       LONG        ! spaces between label and type, as the author left them
lineW     LONG        ! width of the whole line as it stands
        END
x       long,auto
q       long,auto
nsp     long,auto
nInd    long,auto     ! trailing whitespace run counting TABS as well - the column-1 test, see DeclIndent
z       long,auto
labTok  long,auto
wid     long
alignQ  long          ! every type in the run already starts in the same column
dcCap   long          ! a label wider than this is an outlier - --decloutlier past the middle
dcOut   long          ! --decloutlier=<n>, or 20
newW    long
origW   long
sb      stringTheory
moved   long
  code
  free(lnQ)
  labTok = 0
  loop x = 1 to records(self.tokens)
    get(self.tokens, x)
    if errorcode() then break.
    if self.Tokens.tok &= NULL then cycle.
    if size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>' ! end of a line
      labTok = 0
      cycle
    end
    if self.Tokens.firstOnLine
      labTok = 0
      if self.Tokens.type = vt:label
        do DeclIndent                                         ! -> nsp
        if ~nInd then labTok = x.                             ! a label in COLUMN 1 - ANY indent, tab included, means it is not one
      end
      if ~labTok then do FlushDecl.                           ! not a declaration - the run ends
      cycle
    end
    if ~labTok then cycle.
    ! ---- this is the token straight after a column-1 label: the TYPE ----
    if self.Tokens.type = vt:reservedWord
      do FlushDecl                                            ! PROCEDURE / CLASS / QUEUE ... - not a variable
      labTok = 0
      cycle
    end
    do DeclIndent                                             ! gap before the type -> nsp
    get(self.tokens, labTok)
    if errorcode() then labTok = 0 ; cycle.
    wid = size(self.Tokens.tok)
    get(self.tokens, x)
    clear(lnQ)
    dq:labIx = labTok
    dq:typIx = x
    dq:labW  = wid
    dq:gap   = nsp                                            ! for the already-aligned test
    dq:lineW = wid + nsp + size(self.Tokens.tok)
    z = x                                                     ! the REST of the line - ,AUTO / ,DIM() / &Type tails count
    loop                                                      !   toward the real width. The EOL token's strBefore (a
      z += 1                                                  !   trailing comment) does not: comments are AlignComments'
      get(self.tokens, z)                                     !   business, and the guard protects the CODE column
      if errorcode() then break.
      if self.Tokens.tok &= NULL                              ! a trivia-only row still holds width - count it, keep walking
        if not self.Tokens.strBefore &= NULL
          dq:lineW += size(self.Tokens.strBefore)
        end
        cycle
      end
      if size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>' then break.
      if not self.Tokens.strBefore &= NULL
        dq:lineW += size(self.Tokens.strBefore)
      end
      dq:lineW += size(self.Tokens.tok)
    end
    get(self.tokens, x)                                       ! restore the buffer position
    add(lnQ)
    labTok = 0
  end
  do FlushDecl
  free(lnQ)
  return moved

! ---- spaces between the previous token and this one, since the last newline ----
! ---- the trailing whitespace run, counted TWO ways and both are needed ----
!      nsp counts SPACES ONLY and feeds the column arithmetic below, where a tab has no
!      honest width to contribute. nInd counts the run whatever it is made of, and answers
!      the only question the caller asks of it: is this label in column 1 or not?
!
!      COUNTING ONE WAY GETS IT WRONG. Breaking the loop at a tab would make a
!      tab-terminated indent read as nsp = 0, and `if ~nsp` takes that for column 1 - so a
!      tab-indented STATEMENT would enter the declaration run as label-plus-type and the
!      aligner re-space executable code: `<9>x = 1` would come back `<9>x  = 1`, on a DEFAULT
!      run, with the '=' pushed into a column to meet the line below it. Nothing would stop it
!      further down: '=' is not a reserved word, so the type-token break would never fire.
!      Space-indented files cannot reach it, because a real column-1 label carries a
!      NULL strBefore - so only a tab-indented file would show it.
DeclIndent routine
  data
dz  long,auto
dc  string(1),auto
  code
  nsp = 0
  nInd = 0
  if self.Tokens.strBefore &= NULL then exit.
  loop dz = size(self.Tokens.strBefore) to 1 by -1
    dc = self.Tokens.strBefore[dz]
    case val(dc)
    of 32       ! <space>
      nsp += 1
      nInd += 1
    of 9        ! <tab>
      nInd += 1
    else
      break
    end
  end

! ---- the run ended: push every type out to one space past the longest label ----
FlushDecl routine
  if records(lnQ) < 2 then free(lnQ) ; exit.                   ! a single declaration has nothing to line up with
  ! ---- A RUN THAT IS ALREADY ALIGNED IS LEFT ALONE, whatever column it chose.
  !      There is no right constant here: a fixed +2 rewrites a run whose author used a
  !      one-space gutter, a fixed +1 rewrites one written with the ordinary two-space
  !      gutter, and both are the same fault wearing opposite signs - the tool changing a
  !      block that was already consistent, to suit a number it picked. The author's column is a decision,
  !      and a format-preserving rewriter has nothing to say about it. Only a RAGGED run - one
  !      whose types genuinely do not line up - gets an opinion, and then the column is one
  !      space past the longest label, as this routine's banner says.
  dcCap = 0                                                    ! ONE very long NAME does not push every type in the
  dcOut = self.declOutlier                                     !   block out to clear it. OFF unless --decloutlier is
  if dcOut > 0 and records(lnQ) > 2                            !   given: a name is a different measure from a line of
    sort(lnQ, dq:labW)                                         !   code, so it gets its own number rather than sharing
    get(lnQ, (records(lnQ) + 1) / 2)                           !   --cmtoutlier's. Measured from the MIDDLE name, so
    dcCap = dq:labW + dcOut                                    !   two long names cannot shield each other.
  end                                                          ! AN OUTLIER HAS NO SAY IN WHETHER THE RUN IS LEVEL
  alignQ = 1                                                   !   either. Where the rest of the run already shares a
  z = 0                                                        !   column, the run is left EXACTLY as written - the
  loop q = 1 to records(lnQ)                                   !   author picked that column and a format-preserving
    get(lnQ, q)                                                !   rewriter has nothing to say about it. Tightening
    if dcCap and dq:labW > dcCap then cycle.                   !   the others up to clear the SHORT names instead
    if ~z                                                      !   would move live code LEFT for no gain at all.
      z = dq:labW + dq:gap
    elsif dq:labW + dq:gap <> z
      alignQ = 0 ; break
    end
  end
  if alignQ then free(lnQ) ; exit.                             ! already level - nothing to say
  wid = 0 ; origW = 0
  loop q = 1 to records(lnQ)
    get(lnQ, q)
    if dq:lineW > origW then origW = dq:lineW.
    if dcCap and dq:labW > dcCap then cycle.                   ! an outlier sets no column and takes none
    if dq:labW > wid then wid = dq:labW.
  end
  ! ONE space past the longest label, which is what the line above this
  ! routine claims and what the README documents. Write `wid += 2` and the longest
  ! label in every run gets TWO spaces after it - and in a run where the labels are all the same
  ! length that is every line: `i long,auto` and `n long,auto`, already perfectly aligned, come
  ! back as `i  long,auto`. That is a file the tool would change for no gain at all, the one
  ! thing a format-preserving rewriter must not do. With +1 such a run is left exactly as
  ! written - the gap is already 1, so the "already exactly right" test below skips it.
  wid += 1                                                     ! the column every type starts in
  newW = 0
  loop q = 1 to records(lnQ)
    get(lnQ, q)
    if dcCap and dq:labW > dcCap then cycle.                   ! an outlier sets no column and takes none
    z = wid + (dq:lineW - dq:labW - dq:gap)                    ! what this line becomes: the new column plus the line's REAL type+tail width - subtract the line's own gap, not a constant 1, or wide-gutter runs project too wide
    if z > newW then newW = z.
  end
  if pMaxWidth > 0 and newW > pMaxWidth and origW <= pMaxWidth
    free(lnQ) ; exit                                           ! would push a fitting run over the limit
  end
  loop q = 1 to records(lnQ)
    get(lnQ, q)
    if dcCap and dq:labW > dcCap then cycle.                   ! an outlier sets no column and takes none
    get(self.tokens, dq:typIx)
    if errorcode() then cycle.
    if not self.Tokens.strBefore &= NULL
      if sb.findByte(10, 1,, self.Tokens.strBefore)  or        |   ! a continuation - leave it  ! <line feed>
         size(self.Tokens.strBefore) = wid - dq:labW           ! already exactly right
        cycle
      end
    end
    sb.setValue(all(' ', wid - dq:labW))
    self.SetStrBefore(dq:typIx, sb.getValue())
    moved += 1
  end
  free(lnQ)

!===============================================================================================
! AlignCaseLabels - line up the OF labels of a CASE under its OROF labels.
!
!   case upper(tok)                        case upper(tok)
!   of 'IF'                     ->           of 'IF'
!   orof 'LOOP'                            orof 'LOOP'
!   of 'END'                                 of 'END'
!   end                                    end
!
! OROF is four characters and OF is two, so an OF line needs TWO MORE spaces of indent for the
! words to end in the same column. That is the whole rule.
!
! EVERY COLUMN IS COMPUTED FROM THE WIDTHS OF THE CELLS IN IT, and a row moves either way to
! reach it: an OF line in under its OROF, a gap typed wider than the column needs closed up, an
! OROF row continued with '|' to the indent of the row it lines up under. Computing the column,
! never stepping towards it, is what keeps a second run from moving anything - the widths are the
! same on the output, so the columns are - and this runs inside no fixpoint that would catch an
! oscillation. A CASE with no OROF at all is left completely alone - there is nothing to line up
! against, and shifting its OF lines would just be a change for its own sake.
!
! Cosmetic, after convergence. Works on the token stream rather than joined text, so a literal
! or a comment containing the word `of` cannot be mistaken for a label: only a token that is
! FIRST ON ITS LINE and carries the level mark the tokenizer gives a CASE label is considered.
!===============================================================================================
VitTokenize.AlignCaseLabels Procedure(LONG pMaxWidth)
cellQ   QUEUE,PRE(cl) ! every token on every OF/OROF label line
grp       LONG        ! which CASE block  - column 1 aligns across ALL of it
run       LONG        ! which contiguous stretch of label lines - columns 2+ align within one
lineNo    LONG
col       LONG        ! position of this token on its line, 1-based
seg       LONG        ! which ';'-separated segment it belongs to
tokIx     LONG
wid       LONG
gap       LONG        ! spaces before it as the author left them (col 1 = the indent)
glued     BYTE        ! an arm GlueTight made of more than one token (`65 to 90`)
        END
widQ    QUEUE,PRE(wq) ! widest token in each column
key       LONG        ! col 1 -> the CASE id;  col 2+ -> the run id
col       LONG
wid       LONG
        END
runQ    QUEUE,PRE(rn) ! one row per contiguous stretch
id        LONG
origMax   LONG        ! widest label line as the author left it
newMax    LONG        ! widest it would become
skip      BYTE
        END
grpQ    QUEUE,PRE(gp) ! open structures, innermost last
id        LONG
        END
lnQ     QUEUE,PRE(ln) ! one row per label line - see LineShapes
run       LONG
lineNo    LONG
cells     LONG        ! cells on the line after GlueTight
glued     BYTE        ! one of them is an arm of more than one token
odd       BYTE        ! its cell count differs from its run's, and the run holds an arm: columns 2+ stay as written
        END
x       long,auto
q       long,auto
seq     long,auto     ! CASE blocks seen
runSeq  long,auto     ! contiguous label stretches seen
segNo   long          ! ';'-separated segment within the current line
semQ    QUEUE,PRE(sm) ! the runs that use ';' arms - segment mode is PER RUN
id        LONG
        END
semIx   long,auto
eolRun  long,auto     ! line endings since the last label line
lineSeq long,auto
lastGrp long,auto     ! the CASE the previous label belonged to
col     long
inLab   byte,auto
curKey  long,auto
curRun  long,auto
prevW   long,auto
pad     long,auto
wIx     long,auto
rIx     long,auto
lnW     long
lnOrig  long
curLine long
lnCells long          ! cells on the line under test
lnIx    long,auto     ! FindLn's answers
lnOdd   byte
gDelim  long,auto     ! IsDelim's answer - shared by it and GlueTight
sb      stringTheory
moved   long
  code
  free(cellQ) ; free(widQ) ; free(runQ) ; free(grpQ) ; free(semQ)
  seq = 0 ; runSeq = 0 ; lineSeq = 0 ; inLab = 0 ; col = 0 ; eolRun = 99 ; lastGrp = -1

  ! ---- PASS 1: collect every token of every OF/OROF label line ----
  loop x = 1 to records(self.tokens)
    get(self.tokens, x)
    if errorcode() then break.
    if self.Tokens.tok &= NULL then cycle.
    if size(self.Tokens.tok) = 1 and self.Tokens.tok = '<10>'
      inLab = 0
      eolRun += 1
      cycle
    end
    if self.Tokens.level = '+'
      gp:id = 0
      if upper(self.Tokens.tok) = 'CASE'
        seq += 1
        gp:id = seq
      end
      add(grpQ)
      inLab = 0 ; eolRun = 9
      cycle
    end
    if self.Tokens.level = '-'
      if records(grpQ)
        get(grpQ, records(grpQ))
        delete(grpQ)
      end
      inLab = 0 ; eolRun = 9
      cycle
    end
    if self.Tokens.firstOnLine
      inLab = 0
      if self.Tokens.type = vt:reservedWord
        ! ELSE is a CASE arm too, and in a `of 35 ; ... / else ; return` table it has
        ! to line up with the rest of them. It only counts when the innermost open structure is
        ! a CASE - gp:id below - so the ELSE of an IF is never touched.
        case upper(self.Tokens.tok)
        of 'OF' orof 'OROF' orof 'ELSE'
          if records(grpQ)
            get(grpQ, records(grpQ))
            if gp:id
              ! a RUN is a stretch of label lines close enough together to read as one
              ! block. EVERY column aligns within one run, never across the whole CASE.
              !   - a dispatch CASE can hold dozens of branches hundreds of lines apart, and
              !     grouping them all would let one enormous label line veto alignment for every
              !     short block in the same CASE (short blocks left ragged because a very wide
              !     line lives elsewhere in that CASE)
              !   - and column 1 keyed on the CASE would pad an isolated `of 'IF'` out to
              !     match an `orof` 350 lines away that you cannot see from there. Keying column
              !     1 on the run settles that by itself: a run with no OROF in it has a column-1
              !     width of 2, so the pad computes to a single space and nothing moves.
              ! TEN LINES is the gap that ends a run HERE, in this walk. The comment aligner has no
              ! window like it. It has to be a gap rather than strict adjacency, because
              ! `of 'A' / stmt / orof 'B'` is one block to the eye and must still line up.
              ! a run NEVER spans two different CASE blocks. Do NOT try to force the break by
              ! setting eolRun to 9 when a structure opens or closes: the test is `> 10`, so it
              ! never fires, and labels from a PREVIOUS case join the next one's run. That gives
              ! `of   1` / `of   3` in a CASE with no
              ! OROF in it at all, padded to match an OROF in an earlier, unrelated CASE.
              ! THIS TEN IS NOT --cmtrun=, and must not be made into it. That switch sets how far a
              ! line looks back for the comment column it should join, which is a different walk. The
              ! two sentinels above - 99 to start, 9 at a structure boundary - are chosen to sit just
              ! UNDER this literal so that the break never fires on them. A smaller number here fires
              ! it at every structure boundary instead, which is the failure the note above describes.
              if gp:id <> lastGrp then runSeq += 1 ; lastGrp = gp:id.
              if eolRun > 10 then runSeq += 1.                                      ! ... and a long gap ends one inside a CASE
              inLab   = 1
              lineSeq += 1
              col      = 0
              segNo    = 1                                                          ! segment 1 is everything before the first ';'
              eolRun   = 0
            end
          end
        end
      end
    end
    if ~inLab then cycle.
    ! statements after a ';' ARE columns, deliberately. A CASE arm
    ! written as
    !     of 35;   dtype = 'LONG'       ; init = ' = 0'
    !     of 36;   dtype = 'REAL'       ; init = ' = 0'
    !     of 34;   dtype = 'STRING(32)' ; init = ''
    ! is a table, and lining the STATEMENTS up is the point of it, so collection does not stop
    ! at the ';'. What would make those lines come back absurdly wide is a run that reaches into
    ! a DIFFERENT case whose labels are far longer, with every column sized to suit those.
    col += 1
    do CellGap
    ! a top-level ';' ENDS a segment and starts the next. THE ';' ITSELF BELONGS TO THE SEGMENT
    ! BEFORE IT, with whatever gap the author gave it - `of 35;` and `of 35 ;` both stay as
    ! written (ruled 17 Sep 2026), and only where the NEXT segment begins is padded. See the
    ! note on segment mode below.
    if size(self.Tokens.tok) = 1 and self.Tokens.tok[1] = ';'
      segNo += 1
      curRun = runSeq                                                               ! mark THIS RUN as a ';' run
      do FindSem
      if ~semIx
        sm:id = runSeq
        add(semQ)
      end
    end
    clear(cellQ)
    cl:grp    = gp:id
    cl:run    = runSeq
    cl:lineNo = lineSeq
    cl:col    = col
    cl:seg    = choose(size(self.Tokens.tok) = 1 and self.Tokens.tok[1] = ';', segNo - 1, segNo)
    cl:tokIx  = x
    cl:wid    = size(self.Tokens.tok)
    cl:gap    = prevW
    add(cellQ)
  end
  free(grpQ)

  ! ---- --acdiag REPORTS WHAT PASS 1 COLLECTED, as it does for AlignComments: a packed
  !      multi-label CASE written across '|' continuation rows is not aligned, and
  !      deciding WHY from the source alone is
  !      guesswork - the row could be missing from cellQ, or collected onto one line, or
  !      collected correctly and then refused by the width test in PASS 2b. Those want three
  !      different fixes and the output looks identical for all three. One line per cell
  !      answers it. Costs nothing unless --acdiag is on. ----
  if self.acDiag
    self.TraceIt('ACL cells: ' & records(cellQ) & ' cell(s)')
    loop q = 1 to records(cellQ)
      get(cellQ, q)
      if errorcode() then break.
      get(self.tokens, cl:tokIx)
      self.TraceIt('ACL  run ' & cl:run & ' line ' & cl:lineNo & ' col ' & cl:col & |
                   ' seg ' & cl:seg & ' wid ' & cl:wid & ' gap ' & cl:gap         & |
                   ' tok ' & choose(self.tokens.tok &= NULL, '<<null>', clip(self.tokens.tok)))
    end
  end

  ! ---- a gap the author did not write is not ours to invent. See GlueTight. ----
  do GlueTight

  ! ---- SEGMENT MODE. When arms are written `of 35; dtype = 'LONG' ; ...` the thing
  !      that has to line up is the STATEMENTS after each ';', not the tokens - and an
  !      `else ; return` arm has a completely different token shape from an `of` arm, so
  !      aligning by token index pushes them further apart rather than together (of's column 2
  !      is `35`, else's is `;`). So: if ANY label line uses a top-level ';', every cell below
  !      becomes a SEGMENT - the run of tokens up to and INCLUDING the next separator - instead
  !      of a single token. Nothing INSIDE a segment moves, and that includes the ';' and the
  !      gap in front of it: `of 35;` and `of 35 ;` stay exactly as the author wrote them (ruled
  !      17 Sep 2026). Only where each segment begins is padded, so the statements after the
  !      separators line up one space past the widest `label;`. A file with no ';' arms keeps
  !      token columns, which is what the multi-OROF tables need.
  ! segment mode is decided PER RUN, not for the whole file. Do NOT set one
  ! flag when ANY label line anywhere uses a ';': that switches every run over and collapses
  ! the multi-OROF tables (which have no ';') to one cell per line, so they stop aligning
  ! internally. A file with both shapes would show it - an `of 'VIRTUAL' orof 'DERIVED' ...` block
  ! would go ragged.
  if records(semQ)
    loop q = 1 to records(cellQ)
      get(cellQ, q)
      curRun = cl:run
      do FindSem
      if ~semIx then cycle.                                                         ! a token-column run - leave it alone
      cl:col = cl:seg                                                               ! the segment IS the column from here on
      put(cellQ)
    end
    do MergeSegments
  end

  ! ---- a label line with only ONE cell has nothing after it to line up, so it must
  !      not set a column width either. `else` on its own is the case: ELSE is in the run
  !      so that `else ; return` can line up with `of 35 ; ...`, but a bare `else`, four
  !      characters wide, would then set column 1 for every `of` in the same CASE - and a CASE
  !      with no OROF and no ';' would come out as `of   'PRE'` when it should not be
  !      touched at all. Counting cells says it directly: nothing
  !      follows a lone `else`, so it has no opinion about where anything goes.
  do LineShapes
  loop q = 1 to records(cellQ)
    get(cellQ, q)
    curLine = cl:lineNo
    do CellsOnLine                                                                  ! -> lnCells
    if lnCells < 2 then cycle.
    curRun = cl:run ; do FindLn
    if lnOdd and cl:col >= 2 then cycle.                                            ! the odd line out feeds no width
    curKey = cl:run
    col    = cl:col
    prevW  = cl:wid
    do FindWid
    if wIx
      get(widQ, wIx)
      if prevW > wq:wid then wq:wid = prevW ; put(widQ).
    else
      wq:key = curKey ; wq:col = col ; wq:wid = prevW
      add(widQ)
    end
  end

  ! ---- PASS 2b: is aligning this run worth it?  One long entry sets a column's width for the
  !      whole run, so a 23-line block containing 'CONVERTANSITOOEM' would have every other line
  !      padded out to suit it - 79 characters becoming 122. Refuse that.
  !      The absolute-width clause applies only to a run that FITS to begin with.
  !      Refusing because the result exceeds the limit is right when alignment would PUSH it
  !      over; it is wrong for a run already wider than the limit, which would be left ragged
  !      for a width problem alignment did not cause and cannot fix. ----
  curLine = 0
  loop q = 1 to records(cellQ)
    get(cellQ, q)
    if cl:lineNo <> curLine
      do FlushLine
      curLine = cl:lineNo
      curRun  = cl:run
      lnW = 0 ; lnOrig = 0
    end
    if cl:col = 1
      lnW    += cl:gap + cl:wid
      lnOrig += cl:gap + cl:wid
    else
      curRun = cl:run ; curLine = cl:lineNo ; do FindLn
      if lnOdd and cl:col >= 3                                                      ! the odd line out keeps its own spacing
        lnW += cl:gap + cl:wid ; lnOrig += cl:gap + cl:wid ; prevW = cl:wid
        cycle
      end
      curKey = cl:run
      col    = cl:col - 1
      do FindWid
      if wIx
        get(widQ, wIx)
        pad = wq:wid - prevW + 1
        if pad < 1 then pad = 1.
      else
        pad = 1
      end
      lnW += pad + cl:wid
      ! COLUMN 2's PAD BELONGS IN origMax, and leaving it out would make this
      ! whole routine non-idempotent. PASS 3 pads column 2 WHETHER OR NOT the run is
      ! skipped - that is the pad that puts `of` under `orof`, and it is deliberate.
      ! So a run measured as written, then padded, comes back on the NEXT run two
      ! characters wider per line: origMax grows, newMax does not, and a run that
      ! failed `newMax > origMax + 20` by a hair would pass it. Columns 3+ refused
      ! on the first run would be aligned on the second, and the file would change
      ! again for no reason a reader can see.
      !   It shows on real code, under any style: transform a set of files, then
      !   transform the output, and a file holding such a CASE moves the second
      !   time. A second run must change nothing, so the pad is counted on both
      !   sides.
      ! The cap asks what ALIGNING costs. Column 2 is not part of that cost - it is
      ! going to happen either way - so it belongs on BOTH sides of the comparison.
      if cl:col = 2
        lnOrig += pad + cl:wid
      else
        lnOrig += cl:gap + cl:wid
      end
    end
    prevW = cl:wid
  end
  do FlushLine
  loop q = 1 to records(runQ)
    get(runQ, q)
    if rn:newMax > rn:origMax + 20
      rn:skip = 1
      put(runQ)
    elsif pMaxWidth > 0 and rn:newMax > pMaxWidth and rn:origMax <= pMaxWidth
      rn:skip = 1
      put(runQ)
    end
    ! --acdiag REPORTS THE WIDTH DECISION, which is the one that says whether a run aligns at
    ! all. Without it a skipped run and a run with nothing to do look identical in the output.
    if self.acDiag
      self.TraceIt('ACL run ' & rn:id & ': origMax ' & rn:origMax & ' newMax ' & rn:newMax & |
                   ' limit ' & pMaxWidth & ' -> ' & choose(rn:skip = 1, 'SKIP', 'align'))
    end
  end

  ! ---- PASS 2c: give every ROW of a run the SAME LEADING INDENT. ----
  !      A deliberate grant: two passes can write a line's indent, this one and Reindent.
  !
  !      WHY IT IS NEEDED. PASS 3 pads AFTER a token and never before one, which is a deliberate
  !      rule and a good one: it means this pass can never shove code sideways. But it also means
  !      it cannot reconcile rows that START in different places, and rows joined by '|' usually
  !      do, because the author typed them:
  !
  !          of   'IF'    orof 'LOOP'  ... |     <- indent 2, so column 1 ends at 4
  !             orof 'ELSE'  orof 'ELSIF' ...    <- indent 5, so column 1 ends at 9
  !
  !      Every later column inherits that offset and the block reads ragged however well the
  !      columns are computed. PASS 1 collects those rows correctly and PASS 2b agrees to align
  !      them - the diagnostic shows both.
  !
  !      *** THE ANCHOR ROW IS NEVER MOVED, and that is what makes this repeatable. *** The first
  !      row of a run keeps whatever indent it was given, and every following row is set to match
  !      it. The result is a function of the anchor alone, so a second run computes the same
  !      answer and the round trip is a fixed point - which is the property every rule in this
  !      procedure has to have, and one that is lost the moment a decision is keyed on the
  !      thing the previous pass has just changed.
  !
  !      Only rows that begin a NEW PHYSICAL LINE are touched - a strBefore holding a newline is
  !      exactly that test - and only in runs PASS 2b agreed to align. A skipped run is left
  !      entirely alone rather than half-tidied.
  lastGrp = -1
  lnW     = 0
  loop q = 1 to records(cellQ)
    get(cellQ, q)
    if cl:col <> 1 then cycle.
    curRun = cl:run
    do FindRun
    if rIx
      get(runQ, rIx)
      if rn:skip then cycle.
    end
    if cl:run <> lastGrp
      lastGrp = cl:run                                                              ! the anchor: measured, never moved
      lnW     = cl:gap
      cycle
    end
    if cl:gap = lnW then cycle.                                                     ! already where the anchor is
    get(self.tokens, cl:tokIx)
    if errorcode() then cycle.
    if self.Tokens.strBefore &= NULL then cycle.
    if ~sb.findByte(10, 1,, self.Tokens.strBefore) then cycle.                      ! same physical line, not a row  ! <line feed>
    sb.setValue(self.Tokens.strBefore)
    lnOrig = 0
    loop x = sb._DataEnd to 1 by -1                                                 ! keep everything up to the LAST newline
      if sb.valuePtr[x] = '<10>'
        lnOrig = x
        break
      end
    end
    if ~lnOrig then cycle.
    if lnOrig < sb._DataEnd then sb.setLength(lnOrig).
    if lnW > 0 then sb.append(all(' ', lnW)).
    self.SetStrBefore(cl:tokIx, sb.getValue())
    moved += 1
  end

  ! ---- PASS 3: pad each token so the next column starts one space past the widest entry in the
  !      column before it. the padding goes AFTER the keyword, not before it -
  !          of   'VIRTUAL' orof 'DERIVED' orof 'PROC'
  !          orof 'NAME'    orof 'DLL'     orof 'C'
  !      COLUMN 2 is always padded, even in a run that failed the test above: that padding is
  !      what puts the two spaces after `of` so it lines up under `orof`, it is never more than
  !      a couple of characters, and leaving it out leaves `of` short of `orof`. ----
  prevW = 0
  loop q = 1 to records(cellQ)
    get(cellQ, q)
    if cl:col = 1
      prevW = cl:wid
      cycle
    end
    curRun = cl:run
    do FindRun
    if rIx and cl:col > 2
      get(runQ, rIx)
      if rn:skip
        prevW = cl:wid
        cycle
      end
    end
    curLine = cl:lineNo ; do FindLn
    if lnOdd and cl:col >= 3                                                        ! the odd line out keeps its own spacing
      prevW = cl:wid
      cycle
    end
    curKey = cl:run
    col    = cl:col - 1
    do FindWid
    if ~wIx
      prevW = cl:wid
      cycle
    end
    get(widQ, wIx)
    pad   = wq:wid - prevW + 1
    prevW = cl:wid
    if pad < 1 then pad = 1.
    get(self.tokens, cl:tokIx)
    if errorcode() then cycle.
    if not self.Tokens.strBefore &= NULL
      if sb.findByte(10, 1,, self.Tokens.strBefore) or                              |   ! a continuation broke the line here  ! <line feed>
         size(self.Tokens.strBefore) = pad                                          ! already exactly right
        cycle
      end
    end
    sb.setValue(all(' ', pad))
    self.SetStrBefore(cl:tokIx, sb.getValue())
    moved += 1
  end
  free(cellQ) ; free(widQ) ; free(runQ) ; free(semQ) ; free(lnQ)
  return moved

! ---- whitespace immediately before the current token, since the last newline ----
!      A TAB COUNTS AS ONE, and that is an approximation made on purpose. A tab has no
!      honest width here - it depends on where the tab stops fall - but the alternative is
!      worse: breaking the loop at a tab would report a gap of ZERO where there plainly is
!      one, so a tab-indented CASE block would measure its widths against a column that does
!      not exist. One is wrong by an unknown amount; zero is wrong by the whole gap and claims
!      to be exact. The sibling counter in AlignDeclTypes counts the run whole for the same
!      reason, and there it matters more - a spaces-only loop would misread a tab-indented
!      STATEMENT as a column-1 declaration and re-space live code on a default run.
CellGap routine
  data
gz  long,auto
gc  string(1),auto
  code
  prevW = 0
  if self.Tokens.strBefore &= NULL then exit.
  loop gz = size(self.Tokens.strBefore) to 1 by -1
    gc = self.Tokens.strBefore[gz]
    case val(gc)
    of 32 orof 9 ! <space> orof <tab>
      prevW += 1
    else
      break
    end
  end

! ---- one label line measured: fold it into its RUN's two maxima ----
FlushLine routine
  if ~curLine then exit.
  do FindRun
  if ~rIx
    rn:id = curRun ; rn:origMax = lnOrig ; rn:newMax = lnW ; rn:skip = 0
    add(runQ)
  else
    get(runQ, rIx)
    if lnOrig > rn:origMax then rn:origMax = lnOrig.
    if lnW    > rn:newMax  then rn:newMax  = lnW.
    put(runQ)
  end

! ---- curKey + col -> wIx ----
! ---- lnQ: one row per label line - its cell count after GlueTight, and whether it holds an arm
!      glued from more than one token. Then, per token-column run that holds an arm anywhere: the
!      common cell count (the most frequent; the smaller on a tie), and every line of another count
!      is the odd one out - its columns 2+ are left as the author wrote them and feed no width.
!      Ragged tables of one-token labels (no arm) are not touched: their short rows align to the
!      long rows' leading columns. Without the odd-one-out test, a two-label line among ranges
!      (`orof 58 orof 95` under `orof 65 to 90`) would have its second label padded eight spaces
!      out, because column 2's width would come from the glued `65 to 90`.
LineShapes routine
  data
la    long,auto
lb    long,auto
lr    long,auto
lr2   long,auto
lc    long,auto
ln2   long,auto
lbest long,auto
lcnt  long,auto
larm  byte,auto
  code
  free(lnQ)
  loop la = 1 to records(cellQ)
    get(cellQ, la)
    curRun = cl:run ; curLine = cl:lineNo ; do FindLn
    if lnIx
      get(lnQ, lnIx)
      if cl:col > ln:cells then ln:cells = cl:col.
      if cl:glued then ln:glued = 1.
      put(lnQ)
    else
      clear(lnQ)
      ln:run = cl:run ; ln:lineNo = cl:lineNo ; ln:cells = cl:col ; ln:glued = cl:glued
      add(lnQ)
    end
  end
  loop la = 1 to records(lnQ)
    get(lnQ, la)
    if ln:odd then cycle.    ! its run is done
    lr = ln:run
    curRun = lr ; do FindSem
    if semIx then cycle.     ! a ';' run: segments, not cells
    larm = 0
    loop lb = 1 to records(lnQ)
      get(lnQ, lb)
      if ln:run = lr and ln:glued then larm = 1.
    end
    if ~larm then cycle.
    lbest = 0 ; lcnt = 0
    loop lb = 1 to records(lnQ)
      get(lnQ, lb)
      if ln:run <> lr then cycle.
      lc = ln:cells
      ln2 = 0
      loop lr2 = 1 to records(lnQ)
        get(lnQ, lr2)
        if ln:run = lr and ln:cells = lc then ln2 += 1.
      end
      if ln2 > lcnt or (ln2 = lcnt and lc < lbest) then lcnt = ln2 ; lbest = lc.
    end
    loop lb = 1 to records(lnQ)
      get(lnQ, lb)
      if ln:run = lr and ln:cells <> lbest then ln:odd = 1 ; put(lnQ).
    end
  end

FindLn routine
  data
fz  long,auto
  code
  lnIx = 0 ; lnOdd = 0
  loop fz = 1 to records(lnQ)
    get(lnQ, fz)
    if ln:run = curRun and ln:lineNo = curLine
      lnIx = fz ; lnOdd = ln:odd
      break
    end
  end

FindWid routine
  data
fz  long,auto
  code
  wIx = 0
  loop fz = 1 to records(widQ)
    get(widQ, fz)
    if wq:key = curKey and wq:col = col
      wIx = fz
      break
    end
  end

! ---- A COLUMN IS DELIMITED BY THE ARM KEYWORD, NOT BY A SPACE. Give every token of a
!      label line a column of its own and PASS 3, which gives every column at least one
!      space, re-spaces any CASE arm holding an EXPRESSION:
!          of self.Match(TK:Operator, ':')   ->   of self . Match ( TK:Operator , ':' )
!      That is not a cosmetic fault. A lone '.' with a space either side is a BLOCK
!      TERMINATOR, so the file would come back carrying ENDs nobody wrote - its level census
!      unbalanced on output where the same file balances on input. The tool's own
!      tokenizer would disagree with what the tool had just written, and the next build would
!      be made from it.
!      So: everything between two delimiters - `of`, `orof`, `else`, `;` - folds into ONE cell,
!      the way MergeSegments already folds a `;` segment. Only where a cell BEGINS can move;
!      the spacing inside an arm is the author's and is copied through untouched.
!      This is not a restriction on the tables the feature is for. In
!          of   'VIRTUAL' orof 'DERIVED' orof 'PROC'
!      every value is a single token with a delimiter either side, so it is its own cell
!      and those blocks align as a table.
!      A ';' run is skipped outright - MergeSegments owns it, and folding a tightly written
!      `of 35; dtype = ...` here would swallow the ';' that mode is built on. ----
GlueTight routine
  data
gz    long,auto
gw    long,auto
gm    long,auto ! tokens glued into the cell beyond its first
gln   long,auto
gkeep long,auto
gcol  long,auto
  code
  gz = 1
  loop while gz <= records(cellQ)
    get(cellQ, gz)
    gln    = cl:lineNo
    gkeep  = gz
    gw     = cl:wid
    gm     = 0
    curRun = cl:run
    do FindSem
    if semIx then gz += 1 ; cycle.  ! a ';' run - MergeSegments owns it
    do IsDelim
    if gDelim then gz += 1 ; cycle. ! a delimiter is a cell on its own
    loop
      if gz + 1 > records(cellQ) then break.
      get(cellQ, gz + 1)
      if cl:lineNo <> gln then break.
      do IsDelim
      if gDelim then break.         ! `orof` opens the next cell
      gw += cl:gap + cl:wid         ! the spacing INSIDE an arm is the author's
      gm += 1
      get(cellQ, gz + 1)            ! IsDelim read the TOKEN queue - re-fix this cursor
      delete(cellQ)
    end
    get(cellQ, gkeep)
    cl:wid   = gw
    cl:glued = choose(gm > 0)
    put(cellQ)
    gz = gkeep + 1
  end
  ! and renumber: PASS 2 and PASS 3 key the width table on (run, col), so a folded cell must
  ! not leave a hole in the numbering or two lines stop describing the same column.
  gln  = 0
  gcol = 0
  loop gz = 1 to records(cellQ)
    get(cellQ, gz)
    if cl:lineNo <> gln
      gln  = cl:lineNo
      gcol = 0
    end
    gcol += 1
    cl:col = gcol
    put(cellQ)
  end

! ---- is the cell in the cellQ buffer one of the arm delimiters? ----
IsDelim routine
  data
dSv long,auto
  code
  gDelim = 0
  dSv = pointer(self.tokens)
  get(self.tokens, cl:tokIx)
  if ~errorcode() and not self.Tokens.tok &= NULL
    if size(self.Tokens.tok) = 1 and self.Tokens.tok[1] = ';'
      gDelim = 1
    elsif upper(self.Tokens.tok) = 'OF' or upper(self.Tokens.tok) = 'OROF' or upper(self.Tokens.tok) = 'ELSE'
      gDelim = 1
    end
  end
  get(self.tokens, dSv)

! ---- fold every token of a segment into ONE cell - the first token keeps its gap,
!      and its width becomes the rendered width of the whole segment. The rest are dropped, so
!      nothing inside a segment is repositioned: only where each segment BEGINS can move. ----
MergeSegments routine
  data
mz    long,auto
mw    long,auto
mln   long,auto
mseg  long,auto
mkeep long,auto
  code
  mz = 1
  loop while mz <= records(cellQ)
    get(cellQ, mz)
    mln   = cl:lineNo
    mseg  = cl:seg
    mkeep = mz
    mw    = cl:wid
    curRun = cl:run
    do FindSem
    if ~semIx then mz += 1 ; cycle. ! not a ';' run - do not merge it
    loop
      if mz + 1 > records(cellQ) then break.
      get(cellQ, mz + 1)
      if cl:lineNo <> mln or cl:seg <> mseg then break.
      mw += cl:gap + cl:wid         ! the gap INSIDE the segment stays as written
      delete(cellQ)                 ! ... and the row goes
    end
    get(cellQ, mkeep)
    cl:wid = mw
    put(cellQ)
    mz = mkeep + 1
  end

! ---- how many cells does curLine have? ----
CellsOnLine routine
  data
cz  long,auto
sv  long,auto
  code
  lnCells = 0
  sv = pointer(cellQ)
  loop cz = 1 to records(cellQ)
    get(cellQ, cz)
    if cl:lineNo = curLine then lnCells += 1.
  end
  get(cellQ, sv)

! ---- curRun -> semIx: is this run a ';' run? ----
FindSem routine
  data
sz  long,auto
  code
  semIx = 0
  loop sz = 1 to records(semQ)
    get(semQ, sz)
    if sm:id = curRun
      semIx = sz
      break
    end
  end

! ---- curRun -> rIx ----
FindRun routine
  data
fz  long,auto
  code
  rIx = 0
  loop fz = 1 to records(runQ)
    get(runQ, fz)
    if rn:id = curRun
      rIx = fz
      break
    end
  end

! ------------------------------------------------------------------------------------
! Line up trailing comments and '|' continuations into columns.
!
! COSMETIC, AND RUN ONLY AFTER THE FIXPOINT HAS CONVERGED. The caller runs it once, outside the
! rule loop, and counts what it moved towards the file's change total - it must never be put
! INSIDE the loop, because alignment that fed back into the fixpoint could not settle.
!
! The hard part is not the arithmetic, it is NOT MOVING THINGS THAT ALREADY AGREE. A comment
! column drifts right through a 2 -> 4 -> 2 reindent and never comes back whenever a
! decision that should depend only on the CODE is keyed to the state the previous pass left
! behind. So group membership forms by ADJACENCY rather than by current column, and the
! width guard measures the line as it WOULD BE at the target rather than as it stands.
!
!
! The non-oscillation argument for the pull-left is written out in full further down this
! procedure. Read it before changing anything here - it is the reasoning that keeps repeated
! runs stable, and it is not reconstructible from the code.
! ------------------------------------------------------------------------------------
VitTokenize.AlignComments  Procedure(LONG pMaxWidth)
! One pass per RUN of adjacent comment rows: find the run, compute the narrowest column that
! clears every member's code, and put the whole run there. Nothing is stepped towards, and no
! row is left where it lies - both are how a second run over the output changes nothing.
! Comments move in either direction: a run is pulled LEFT when a narrower column still clears
! every member's code. The non-oscillation argument further down is what keeps a second run
! from moving anything back.
isuC   long,auto                   ! one member's code width, while gCode is accumulated
acGap  long,auto                   ! spaces between the code and the marker. --cmtgap=<n>, 1 as shipped -
acWid  long,auto                   ! one row's own code floor read into a local ONCE, and a 0 from a profile SETTINGS line is lifted to the shipped spacing.
opKey  long,auto                   ! the bar column a padPrev row will land at - also the block key
opCol  long,auto                   ! and the column its operator gets, two past the widest code in that block
opBlkQ QUEUE,PRE(bk)               ! one row per block: KEYED, so the three passes agree on what a block is
bkKey    long
bkWide   long                      ! widest opCode in the block
bkN      long                      ! how many bar rows are in the block. Two columns only mean something when there are two bars to line up - a lone bar keeps its operator beside it and joins the COMMENT column instead.
bkOk     byte                      ! 0 = the two columns will not fit, so the WHOLE block keeps one column
       END

CmtQ queue                         ! comment queue
pos      long                      ! pos of start of comment ('!' or '|')
adjust   long
freeze   long                      ! if first char non-space on line then don't move
kind     long                      ! 1 = '!' comment, 2 = '|' continuation. Both settle in the SAME
lineLen  long                      !   column; kind feeds padPrev, --cmtbar, the look-back and --acdiag, never the freeze.
codeEnd  long                      ! column of the last non-space character before the marker, so a block
padPrev  long                      !   can be pulled back LEFT without jamming a comment against its own code.
opCode   long                      ! padPrev rows only: the column the CODE ends at, WITHOUT the operator. codeEnd above deliberately includes it (`as if the gap were one space`), which is right for
                                   !   deciding a comment column and wrong for deciding the OPERATOR's column - that has to be free of the operator or a wider operator would push its own column right.
opGap    long                      ! spaces to write BEFORE the operator. 0 = fall back to the one-column form (operator one space in front of the bar), used when the block cannot fit two columns.
opBar    long                      ! spaces to write between the operator and the bar. 0 with opGap.
opRun    long                      ! which pull-left RUN this row belongs to. THE block key for the operator column, because a run is built from source adjacency and marker kind - both the same on either leg of
                                   !   a round trip. Keying on the resulting COLUMN instead would make this a no-op on exactly the ragged blocks it is there to fix.
opSz     long                      ! width of the operator token, so the fit test can be done without re-reading the token stream.
opener   long                      ! this line OPENS a structure (tokenizer '+' level). It never SETS a column - a CLASS header 126 characters wide would
                                   !   otherwise drag the fields under it out to match - but it may TAKE one, so it settles with the block it sits in.
frzKind  long                      ! WHY a row is frozen, because the two reasons want different treatment:
                                   !   1 = it must not move at all: a whole-line or margin comment (anything with no
                                   !       code in front of the marker, text or not; a TAB is not code), or a line of
                                   !       dots - a bare '!' after code is not one. These ANCHOR - the column belongs to them
                                   !       and the rows around them settle onto it, PROVIDED THEY CARRY THE SAME
                                   !       MARKER. A '!' column and a '|' column are different things, so a change
                                   !       of kind ends a run and stops a look-back, in both directions and whether
                                   !       the row is an anchor or not. A PROTOTYPE is NOT one of these:
                                   !       it is an `opener` above, free to take a column but never to set one.
                                   !   2 = `end ! text`. It may not set a column either - one word of code says
                                   !       nothing about where the block's comments belong - but it MAY take one, so
                                   !       it lines up with the statements it closes instead of stranding them.
hangFrom long                      ! the row this one HANGS from - a whole-line comment written in the comment field under a trailing comment is PART
                                   !   of that comment, so it is a PASSENGER: it takes the anchor's Adjust and sets nobody's column. 0 = not one.
hangLen  long                      ! on the ANCHOR, the longest lineLen among its passengers. Anchor and passengers travel by the SAME delta, so a width test that measured the anchor alone would miss the wider row. NO READER - the width test it is kept for is not applied; the loop that sets this says why
                                   !   of the two - otherwise a run is offered a column that takes the hanging text past the limit while the row with the code on it still fits.
blkStart long                      ! this line STARTS a new block, so a comment run never crosses it. A PROCEDURE, FUNCTION or ROUTINE written in column 1, and the CODE statement inside one.
                                   !   Both are places where the KIND of line changes wholesale, so the declarations above and the statements below have no business sharing a column.
txtInd   long                      ! the TEXT after the marker is indented - two or more spaces - which is how a continuation of the comment above is written.
barCmt   long                      ! the column of the '!' that follows a '|' on the same line, 0 = there is none. Measured always,
                                   !   whether or not --cmtbar= asks for it, so --acdiag can report what the row actually carries.
keepRow  byte                      ! this row is in a group whose comments ALREADY share one column that clears every one of them,
                                   !   so nothing here moves it. Set by KeepAligned, read by the apply loop. Per ROW and not per RUN:
                                   !   a ragged comment anywhere in a long block must not disable the rule for the tidy groups in it.
cmtBack  long                      ! how far RIGHT of Pos the marker that OWNS the column sits: 0 on every row but a bar carrying a
                                   !   comment, where the '!' owns it and the '|' is derived back from it. See --cmtbar=comment.
barSp    byte                      ! the '!' after the '|' is the first thing past it, with only SPACES between - the one shape whose gap
                                   !   the bar-comment pass rewrites. A tab, or text before the '!', and the row keeps what was typed.
cmtTo    long                      ! the column the '!' after this row's '|' lands on, 0 = the text after the bar is left alone. Set only
                                   !   in a run holding TWO or more such comments - see THE COMMENTS AFTER THE BARS LINE UP.
barAt    long                      ! the column the apply left this row's '|' on - Pos plus what it moved the bar by. Not always Pos + Adjust:
                                   !   a `&|` with no space keeps its spelling and lands one short, and a tab stops the padding. 0 = not reached.
barTok   long                      !   ... the token whose leading text holds that '|'
barCnt   byte                      !   ... and the apply counted the row as moved already
     end                           ! set when the marker is a '|' immediately preceded by '&'. The pair `& |` moves as ONE unit, so the padding goes on the '&' token, not the '|'.
                                   ! lineLen = the line as it stands, so an adjustment can refuse to push it over the limit.

OpenQ queue                        ! lines that OPEN a structure. A CLASS/QUEUE/
opLine  long                       !   GROUP header is not a member of the comment run for
      end                          !   the fields inside it - it is an ANCHOR. Taken from the tokenizer's own '+' level marks, so there is no keyword list to keep and no width threshold to guess at.
opInCode      byte,auto            ! the OpenQ walk is inside a procedure body
opIx          long                 ! monotonic cursor into OpenQ - the line loop only goes forward
opTok         long,auto
opLook        long,auto            ! the look past a ROUTINE header for a DATA section
x             long,auto
!prev          long,auto
svPtr         long,auto
cmtCol        long,auto
cmtLine       long,auto
acTrim        long,auto            ! leading spaces to remove for a NEGATIVE adjust
acKeep        long,auto
ppNeed        long,auto            ! spaces an `op |` row needs before its operator
ppKeep        long,auto            !   ... and how many are there now
acZ           long,auto
acShift       long,auto            ! how far the apply has moved THIS row's '|' - so Pos + acShift is where it IS
acCounted     byte,auto            !   ... and whether this row has been counted as moved already
acBarTok      long,auto            !   ... and the token whose leading text holds that '|'
acLf          long,auto            ! that text holds a line break and the row's own line starts after it - see MarkerLine
bqDist        long,auto            ! a bar comment's gap as typed, as a column distance
bqCol         long,auto            !   ... and the column it reaches riding along behind its bar
pl            long,auto            ! pull-left run scan
plEnd         long,auto
acAdj         byte,auto            ! this plain line touches a commented one
acEnd         long,auto            ! its code end, kept across the neighbour reads
plCol         long,auto
plMin         long,auto
plKind        long,auto            ! the FIRST row's marker kind. Read by PullLookBack (it will not LAND on a block of a different marker) and by --acdiag. NOT a membership or a voting test - this walk has neither
plNbr         long,auto            ! column of the block immediately above, 0 = none
plLast        long,auto
plKeep        byte,auto            ! EVERY group in this run was kept, so the run is untouched - KeepAligned
kaCol         long,auto            ! KeepAligned and KeepBankGroup share these, so they are the PROCEDURE's and not a
kaN           long,auto            !   routine's - a routine's own data is private to it. The column the group being
kaFlr         long,auto            !   weighed shares, how many rows are in it, and the widest code floor under it.
kaGrpS        long,auto            ! first row of that group
kaLast        long,auto            ! last commented row seen, so a gap can end a group
kaKept        long,auto            ! rows kept, against kaSeen weighed - equal means every group was kept
kaSeen        long,auto
kaOK          byte,auto            ! the group is still in ONE column
kaEnd         byte,auto            ! the group ends at this row
kaWhole       byte,auto            ! the walk reached the END of the run - see the plKeep gate
plTgt         long,auto            ! this row's target column
cbT           long,auto            ! the token walk that builds CmtQ
cbI           long,auto            !   and the character walk of its trivia
cbCh          string(1),auto
cbCol         long                 ! characters on the current line so far
cbCode        long                 ! column of the last CODE character
cbPrevEnd     long                 !   and of the one before the last token
cbPos         long                 ! the marker's column, once found
cbKind        long
cbInCmt       long                 ! past a '!': the rest is text
cbTxt         long                 ! the marker has text after it
cbSpAfter     long                 ! spaces between the marker and its text
cbTxtInd      long                 !   ... two or more = an indented continuation
cbBarCmt      long                 !   ... and the column of a '!' that follows the '|'
cbBarSp       byte                 !   ... with nothing but spaces between the two
cbBarTab      byte                 !   a tab after the marker
cbNCode       long                 ! how many code tokens on the line
cbFirstCol    long                 ! the column its FIRST code token starts at, so a label in column 1 can be told from an indented one
cbHasProc     byte                 ! PROCEDURE, FUNCTION or ROUTINE appears on
cbDepth       long
cbOpens       long
cbCloses      long
                                   !   this line. Not cbSecondU: a method is written
                                   !   `Class.Method PROCEDURE`, so the second token
                                   !   is the dot and the keyword is the fourth.
cbFirstU      string(vt:maxVarLen) ! its first, second and last, uppercased
cbSecondU     string(vt:maxVarLen)
cbLastU       string(vt:maxVarLen)
cbLastSz      long
cbAllDot      long                 ! every code token on it is a '.'
cbLine        long                 ! the line number being built
plWho         long,auto            ! --acdiag: which cmtQ row set plMin ...
plW1          long,auto            ! widest CODE floor in the run, and the next widest, so a
plNonCode     long,auto            ! floors that are NOT code widths - a frozen anchor, the block above. Kept apart so dropping a spike cannot fall below one of them.
plBar         long,auto
plPrevBar     long,auto
acLimit       long,auto
acOutlier     long,auto
pQ     QUEUE,PRE(pq)               ! the floor of every PLAIN line that TOUCHES a commented one in the
pqW      long                      !   run: such a line lifts the column when it is no more than self.cmtReach
pqX      long                      !   wider - or, whatever its width, when it lies BETWEEN two commented rows
       END                         !   wider than the column the commented lines set (PlainReach)
wQ     QUEUE,PRE(wq)               ! every CODE floor in the run, so the outlier test can
wqW      long                      !   ask how wide the MIDDLE of the block is. Comparing
       END                         !   against the next-widest instead lets two long lines shield each other - so a 145-character prototype would set the column for a whole .inc while a
                                   !   142-character one is beside it.
opGrp         long,auto            ! bar-group counter, stamped into CmtQ.opRun
opPrev        long,auto            !   the previous bar row, for the adjacency test
opGrpQ QUEUE,PRE(g)                ! one row per BAR GROUP - keyed, so every reader agrees what a group is
gKey     long
gCode    long                      ! widest CODE in the whole statement - every member including the row that CLOSES it, operator excluded. The OPERATOR column is two past
                                   !   this. A lone bar whose own code ends at 8 and whose statement runs to 22 has its operator at 24.
gWide    long                      ! the widest `codeEnd + 2` any bar in the group needs
gN       long                      ! how many bars are in it
gBack    long                      ! the widest bar-to-comment gap any bar in the group carries, so every bar in the group steps
                                   !   back by the SAME amount and the group's bars stay in one column. --cmtbar=comment only.
gCmt     long                      ! the NARROWEST column a comment after one of the group's bars reaches riding along behind it
gCmtN    long                      !   ... how many such comments there are. One alone has nothing to line up with
       END
plWhy         string(10),auto      !   ... and by which branch. The pull-left floor is the whole ratchet question, and "min 88" is no help without "whose 88?".
plFroze       byte
hgX           long,auto            ! the hanging-comment passes
hgAnc         long,auto            !   the row a passenger hangs from
hgEnd         long,auto            !   that anchor's codeEnd - the edge of the comment field
hgLen         long,auto            !   a passenger's own line length, read before the anchor is fetched
hgAdj         long,auto            !   the anchor's Adjust, which the passenger takes
moved         long                 ! comments actually moved - the caller counts it as a change

 code
  acLimit = self.alignLimit                                                         ! --cmtlimit=<n>: a column never goes past
  if ~acLimit then acLimit = 90.                                                    !   this to line anything up. 90 as shipped
  acOutlier = self.alignOutlier                                                     ! --cmtoutlier=<n>: OFF unless given. When given, a
                                                                                    !   floor more than n past the block MIDDLE does not
                                                                                    !   set the column - it keeps its own comment at its
                                                                                    !   own end and the rest stay where they were.
  acGap = self.cmtGap + 1                                                           ! the OFFSET from codeEnd to the marker, not
  if acGap < 2 then acGap = 2.                                                      !   the gap itself. A profile SETTINGS line can still deliver cmtgap=0, and
                                                                                    !   2 is the shipped spacing - one space.
  svPtr = pointer(self.tokens)                                                      ! save pointer position for restore at end
  CmtQ.adjust = 0                                                                   ! just to be sure

  self.SetLineNumbers                                                               ! renumber lines as doing deletes of toks and then insertString can muck these up or leave 0 line nos.

  ! which lines OPEN a structure? SetLineNumbers ran above, so token lineNo
  ! and the line index below are the same numbering. Tokens are in order, so OpenQ comes
  ! out sorted and the line loop can walk it with a monotonic cursor.
  ! WHICH OPENERS ARE HEADERS, AND WHICH ARE JUST LINES. A structure opener keeps its own
  ! column and sets nobody else's, which is right for a DECLARATION header: a CLASS line 126
  ! characters wide would put its comment at 128 and drag every field comment under it out
  ! to match. It is wrong for an opener inside a procedure's CODE, where `if`, `loop` and the
  ! one-line `if x then y.` are ordinary statements whose comments belong to the block around
  ! them - treating those as headers splits an evenly-aligned procedure into three columns
  ! (31 / 52 / 17 where the author had one column at 52).
  ! So the mark is only taken OUTSIDE code. CODE opens a body; the next PROCEDURE, FUNCTION
  ! or ROUTINE header closes it, and a ROUTINE has a CODE of its own.
  free(OpenQ)
  opInCode = 0
  loop opTok = 1 to records(self.tokens)
    get(self.tokens, opTok)
    if errorcode() then break.
    if self.tokens.type = vt:reservedWord
      case upper(self.tokens.tok)
      of 'CODE'
        opInCode = 1
      of 'PROCEDURE' orof 'FUNCTION'
        opInCode = 0
      of 'ROUTINE'                                                                       ! a routine's statements ARE its code unless a DATA section
        opInCode = 1                                                                     !   opens first - then its own CODE re-arms this. If it were 0,
        opLook = opTok + 1                                                               !   each `if` and `loop` in a data-less routine would then be
        loop                                                                             !   marked as a header
          get(self.tokens, opLook)
          if errorcode() then break.
          if self.tokens.firstOnLine
            if upper(self.tokens.tok) = 'DATA' then opInCode = 0.
            break
          end
          opLook += 1
        end
        get(self.tokens, opTok)
      end
    end
    if self.tokens.level = '+' and ~opInCode
      if ~records(OpenQ) or OpenQ.opLine <> self.tokens.lineNo
        OpenQ.opLine = self.tokens.lineNo
        add(OpenQ)
      end
    end
  end
  opIx = 1

  ! ---- ONE ROW PER PHYSICAL LINE, BUILT FROM THE TOKENS --------------------------------------
  ! Everything below decides WHERE a comment goes. This decides WHAT IS ON THE LINE, and it asks
  ! the token queue rather than re-reading the text.
  !
  ! *** THE DIFFERENCE THAT MATTERS IS CLASSIFICATION, NOT ARITHMETIC. *** The columns still have
  ! to be counted here - a token carries no column - so this walks the line adding up trivia and
  ! token widths exactly as a text scan would. What it does NOT have to do is work out what a
  ! character MEANS. A '|' can only be a continuation if it is in TRIVIA; inside an @K picture it
  ! is that picture's strip character and inside a literal it is text, and in both of those cases
  ! it is part of a TOKEN and this walk never looks at it. The same goes for a quote inside @P,
  ! and for the word `procedure` inside a string.
  !
  ! That is the whole reason for reading tokens: a scan of raw text has to re-derive which
  ! characters are code, and every time it got that wrong the alignment moved something it should
  ! not have. Here the tokenizer has already answered it.
  !
  ! ONE ROW PER PHYSICAL LINE, in order, because everything below indexes CmtQ by line. A line
  ! ends at a newline WHEREVER IT IS - as a token of its own, or inside a token's leading trivia,
  ! which is what a '|' continuation and a phase-1 line break both produce.
  free(CmtQ)
  cbCol = 0 ; cbCode = 0 ; cbPos = 0 ; cbKind = 0 ; cbInCmt = 0 ; cbTxt = 0 ; cbSpAfter = 0 ; cbTxtInd = 0 ; cbBarCmt = 0 ; cbBarSp = 0 ; cbBarTab = 0
  cbNCode = 0 ; cbFirstU = '' ; cbSecondU = '' ; cbLastU = '' ; cbLastSz = 0
  cbPrevEnd = 0 ; cbAllDot = 1 ; cbLine = 1
  cbFirstCol = 0 ; cbHasProc = 0
  cbOpens = 0 ; cbCloses = 0 ; cbDepth = 0
  opIx = 1
  loop cbT = 1 to records(self.tokens)
    get(self.tokens, cbT)
    if errorcode() then break.
    ! ---- the trivia in front of this token ----
    if not self.tokens.strBefore &= NULL
      loop cbI = 1 to size(self.tokens.strBefore)
        cbCh = self.tokens.strBefore[cbI]
        if cbCh = '<10>'                                                            ! a newline ANYWHERE closes the line
          do CbEndLine
          cycle
        end
        if cbCh = '<13>' then cycle.                                                ! carries no column of its own
        cbCol += 1
        if cbPos                                                                    ! past the marker: is there TEXT?
          if cbCh = ' ' or cbCh = '<9>'
            if ~cbTxt then cbSpAfter += 1.
            if cbCh = '<9>' then cbBarTab = 1.
          elsif ~cbTxt
            cbTxt = 1
            if cbSpAfter >= 2 then cbTxtInd = 1.
          end
          if cbKind = 2 and cbCh = '!' and ~cbBarCmt                                ! a '!' AFTER a '|': the row carries BOTH.
            cbBarCmt = cbCol                                                        !   AND short-circuits, so this costs one
          end                                                                       !   test on an ordinary row. kind = 2 is
                                                                                    !   what stops a '!' inside a comment's own
                                                                                    !   text reading as a second marker, and
                                                                                    !   ~cbBarCmt keeps the FIRST one.
          if cbBarCmt = cbCol and ~cbBarTab and cbSpAfter = cbCol - cbPos - 1       ! ONLY SPACES between the '|' and that '!', so
            cbBarSp = 1                                                             !   its gap is one the bar-comment pass may rewrite -
            if cbI < size(self.tokens.strBefore)                                    !   unless a .txa marker byte follows, which makes
              if val(self.tokens.strBefore[cbI + 1]) >= 250 then cbBarSp = 0.       !   the '!' a marker and not a comment
            end
          end
          cycle
        end
        if cbInCmt then cycle.
        case val(cbCh)
        of 33                                                                       ! '!'
          if cbI < size(self.tokens.strBefore) and val(self.tokens.strBefore[cbI + 1]) >= 250
            cbInCmt = 1                                                             ! a .txa MARKER, not a comment: the restore
          else                                                                      !   takes it off, so it has no column to keep
            cbPos = cbCol ; cbKind = 1 ; cbInCmt = 1
          end
        of 124                                                                      ! '|'
          cbPos = cbCol ; cbKind = 2
        end
      end
    end
    if self.tokens.tok &= NULL then cycle.
    if size(self.tokens.tok) = 1 and self.tokens.tok = '<10>'                       ! the newline as a token of its own
      do CbEndLine
      cycle
    end
    ! ---- the token itself: this is CODE, whatever it contains ----
    cbPrevEnd = cbCode
    cbCol    += size(self.tokens.tok)
    cbCode    = cbCol
    cbNCode  += 1
    cbLastU   = upper(self.tokens.tok)
    cbLastSz  = size(self.tokens.tok)
    if cbNCode = 1
      cbFirstU   = cbLastU
      cbFirstCol = cbCol - cbLastSz + 1
    end
    if cbNCode = 2 then cbSecondU = cbLastU.
    case cbLastU
    of 'PROCEDURE' orof 'FUNCTION' orof 'ROUTINE'
      cbHasProc = 1
    end
    if self.tokens.level = '+' then cbOpens += 1.
    if self.tokens.level = '-' then cbCloses += 1.
    if cbLastU <> '.' then cbAllDot = 0.
  end
  do CbEndLine                                                                      ! and the last line, which may have no newline after it at all

  ! ---- THE HANGING COMMENT -----------------------------------------------------------------
  ! A whole-line comment written in the COMMENT FIELD under a trailing comment is not a comment
  ! of its own - it is the rest of the one above it. It must therefore travel with that comment
  ! rather than settle on a column of its own, or one comment finishes in two columns, which is
  ! the author's own layout undone and reads worse than not moving it at all.
  !
  ! THE ANCHOR is the last line with CODE and a comment on it. A row hangs from it when its
  ! marker sits RIGHT OF THAT ANCHOR'S codeEnd - measured against the code actually on the line,
  ! so there is no width threshold to guess at. A comment at the LEFT MARGIN is not right of the
  ! code, so it is not a passenger and does not move: the freeze rule keeps it, and that is the
  ! rule that stops a tab-indented full-line comment walking one column right per run, for ever.
  !
  ! A line with no comment ENDS the chain, and so does a margin comment. Both mean the next
  ! whole-line comment is a comment of its own, not the tail of one. So does a continued line whose
  ! bar has no comment after it: it anchors nothing, and a comment line under it stays where it was
  ! typed (ruled 29 Oct 2026).
  !
  ! *** THIS LOOP IS THE ONLY THING THAT SETS hangFrom AND hangLen. *** TWO places read hangFrom -
  ! the run walk skips a passenger so it neither votes for a column nor ends a run, and the
  ! look-back refuses to land on a row that is not settled yet. Both fail SILENTLY and identically
  ! if this loop stops running: every passenger simply reverts to being frozen where it lies while
  ! its anchor moves off without it. Nothing reports that, so it is not visible from the output of
  ! one file - only from reading two columns where there should be one.
  !
  ! *** hangLen HAS NO READER, and that is not an oversight to tidy away. *** It is here for
  ! the WIDTH TEST described further down, at the `plTgt = plMin` site: measure the anchor against
  ! its WIDEST passenger, so a run is never offered a column that carries the hanging text past the
  ! limit while the row holding the code still fits. That test is not applied. LEAVE THE FIELD -
  ! deleting it throws away half of a design that is still wanted.
  ! The test is a layout change, not a fix: the width arrives as 240, and sources this tool is
  ! run over hold many lines longer than that, so honouring it would re-wrap them, which is a
  ! change of layout to be decided on its own.
  !
  ! WHAT THIS REFUSES, and it is a real case rather than a hypothetical one: when a RULE has
  ! rewritten the code on the anchor's line, that code can grow out PAST the hanging row's
  ! marker, and the row is then indistinguishable from a comment written at the margin - it sits
  ! LEFT of the anchor's codeEnd, which is the only test there is. Telling that apart from a
  ! margin comment needs the source as it stood BEFORE the rules ran, which this routine does
  ! not have and should not acquire. TestData\contcomment.clw case 5 pins the refusal, so a
  ! later change that decides differently does so on purpose.
  !
  ! Pos is tested before codeEnd because a row with no marker carries no comment field to be
  ! right of, and its code is what ends the chain rather than what anchors it.
  ! ------------------------------------------------------------------------------------------
  hgAnc = 0 ; hgEnd = 0
  loop hgX = 1 to records(CmtQ)
    get(CmtQ, hgX)
    if errorcode() then break.
    if CmtQ.Pos < 2                                                                 ! code with no comment, a blank line, or a
      hgAnc = 0                                                                     !   marker in column 1 - the chain ends here
      cycle
    end
    if CmtQ.codeEnd                                                                 ! CODE and a comment: this row is an anchor
      if CmtQ.kind = 2 and ~CmtQ.barCmt then hgAnc = 0 ; cycle.                     ! a bar with no comment after it holds nothing in place
      hgAnc = hgX
      hgEnd = CmtQ.codeEnd
      cycle
    end
    if ~hgAnc then cycle.                                                           ! a whole-line comment hanging from nothing
    ! A whole-line comment whose text is INDENTED after the marker is the
    ! continuation of the comment above it wherever its marker sits. The position test
    ! alone misses every continuation written under an OUTLIER at the block's column,
    ! and then freezes it there as an anchor. A margin comment is written with ONE
    ! space after its marker, so this test leaves margin comments alone.
    if CmtQ.Pos <= hgEnd and (~CmtQ.txtInd or self.cmtContNone)                     ! --cmtcont=none: an indented text is a comment of its own
      hgAnc = 0                                                                     ! at the MARGIN, not in the comment field -
      cycle                                                                         !   a comment of its own, and it ends the chain
    end
    hgLen = CmtQ.lineLen - CmtQ.Pos + 1                                             ! its TEXT WIDTH - marker to end of line - because the passenger lands on the
                                                                                    !   ANCHOR'S column, not its own. Read before the get() below moves the buffer.
    CmtQ.hangFrom = hgAnc
    put(CmtQ)
    get(CmtQ, hgAnc)
    if errorcode() then cycle.
    if hgLen > CmtQ.hangLen                                                         ! the anchor carries its WIDEST passenger
      CmtQ.hangLen = hgLen
      put(CmtQ)
    end
  end

  ! ---- THE COLUMN  ------------------------------------------------------------------
  ! Walk each RUN of adjacent comment rows and put the whole run at the narrowest column that
  ! still clears every member - one space past the longest piece of code in it.
  !
  ! *** THE COLUMN IS COMPUTED FROM THE CODE, NEVER STEPPED TOWARDS. *** That one property is
  ! what makes this pass idempotent and what makes a 2 -> 4 -> 2 reindent round trip return:
  ! run it again on its own output and the code is the same, so the answer is the same. A
  ! pass that moved each comment RIGHT to match its neighbour would be a RATCHET - widen the
  ! code once and the column follows; narrow it again and nothing brings it back - so
  ! nothing here accumulates.
  !
  ! WHY IT CANNOT OSCILLATE:
  !   - it runs ONCE over each run, not iteratively
  !   - the target is COMPUTED from the run (max codeEnd + 2), not stepped towards
  !   - a run containing a FROZEN row is left alone entirely. A frozen row is an anchor - the
  !     column belongs to it - and that is what "only when all its members agree" means
  !   - the answer depends on the CODE alone, so a second run over the output recomputes it
  ! ------------------------------------------------------------------------------------------
  ! ---- BAR GROUPS, BY ADJACENCY. --------------------------------------------------
  !      Two bars belong together when they are on CONSECUTIVE lines - that is what a wrapped
  !      statement looks like, and it is the only relationship the eye reads as "these line up".
  !
  !      The comment RUN is far too coarse for this. A run can be eighty lines long, because a
  !      run ends only at a PROCEDURE, ROUTINE or CODE line - a gap of any size does not end
  !      one. Grouping bars by the run would pull a bar out to column 114 to match bars THIRTY
  !      LINES AWAY, when the comments either side of it sit at 102.
  !
  !      Adjacency is a property of the source, so it is the same on both legs of a round trip -
  !      the test every rule in this procedure has to pass.
  !
  !      A LONE bar therefore has no group of its own and keeps the one-column shape: it joins the
  !      comment column like any other trailing marker and its operator sits one space in front of
  !      the bar. Two columns are only worth having when there are two bars to line up.
  opGrp  = 0
  opPrev = 0
  loop x = 1 to records(CmtQ)
    get(CmtQ, x)
    if errorcode() then break.
    ! EVERY BAR, not only the ones with an operator in front. A `|` after a
    ! string literal is just as much a wrapped line as one after `or` - two `orof`
    ! rows of one CASE would leave their bars at 71 and 69, each past its own
    ! code, if the grouping looked only at padPrev rows, because neither is
    ! padPrev. padPrev decides whether the OPERATOR gets a column of its own;
    ! it has nothing to do with where the BAR goes.
    if CmtQ.kind <> 2
      ! THE LAST LINE OF A CONTINUED STATEMENT CARRIES ITS COMMENT INTO THE
      ! SAME COLUMN AS THE BARS ABOVE IT. A row that directly follows a bar IS the closing
      ! physical line of that statement - the last row of a CASE label list ends what
      ! the rows above it continue - so its comment belongs where their bars are, not
      ! wherever its own run happens to settle, at 48, say, against bars at 71.
      !
      ! This is NOT a bar dragging unrelated comments out, which is forbidden:
      ! it is one statement finishing its own layout. Only the row IMMEDIATELY after a bar
      ! qualifies, and it is counted as a member for the COLUMN but never for gN - so it
      ! cannot turn a lone bar into a pair and win the operator its own column.
      if opPrev and x = opPrev + 1 and CmtQ.kind = 1
        CmtQ.opRun = opGrp
        put(CmtQ)
      end
      opPrev = 0                                                                    ! a non-bar row ends the run of bars
      cycle
    end
    if ~opPrev or x <> opPrev + 1                                                   ! not adjacent to the last bar - a new group
      opGrp += 1
    end
    CmtQ.opRun = opGrp
    put(CmtQ)
    opPrev = x
  end

  ! per bar-group: how many bars, and the widest floor any of them needs. The pull-left
  ! pass below reads this to place a bar, and the pass that positions the operator reads it again.
  free(opGrpQ)
  loop x = 1 to records(CmtQ)
    get(CmtQ, x)
    if errorcode() then break.
    ! gCode wants EVERY member, including the row that CLOSES the statement, so
    ! the kind test moved below the gN/gWide accumulation rather than gating the whole loop.
    if ~CmtQ.opRun then cycle.
    opGrpQ.gKey = CmtQ.opRun
    get(opGrpQ, opGrpQ.gKey)
    if errorcode()
      opGrpQ.gKey  = CmtQ.opRun
      opGrpQ.gCode = choose(~CmtQ.padPrev, 0, CmtQ.opCode)                          ! a member WITH an operator feeds gCode; one without waits for the pass below
      opGrpQ.gWide = CmtQ.codeEnd + acGap + CmtQ.cmtBack
      opGrpQ.gN    = 1
      opGrpQ.gBack = 0                                                              ! built field by field - an unset gBack would be
                                                                                    !   whatever the last get left in the buffer
      opGrpQ.gCmt  = 0 ; opGrpQ.gCmtN = 0                                           !   - and so would these two
      add(opGrpQ, opGrpQ.gKey)
    else
      isuC = choose(~CmtQ.padPrev, 0, CmtQ.opCode)                                  ! a member WITH an operator feeds gCode; the row that CLOSES the statement has none and waits for the pass below
      if isuC > opGrpQ.gCode then opGrpQ.gCode = isuC.
      if CmtQ.kind = 2                                                              ! gN and gWide are about BARS only
        opGrpQ.gN += 1
        if CmtQ.codeEnd + acGap + CmtQ.cmtBack > opGrpQ.gWide then opGrpQ.gWide = CmtQ.codeEnd + acGap + CmtQ.cmtBack.
      end
      put(opGrpQ)
    end
  end

  ! THE OPERATORS LINE UP TWO PAST THE WIDEST LINE THAT CARRIES ONE. A member with no
  ! operator - the line that closes the statement, or a bar after a literal - sets the operator
  ! column only when it is no more than self.cmtReach (--cmtreach=) wider than that, so a slightly longer closing
  ! line still keeps the operators clear of its text while a much longer one does not drag
  ! them to its end. Second
  ! pass, because the closing line comes after the bars whose widest it is measured against.
  loop x = 1 to records(CmtQ)
    get(CmtQ, x)
    if errorcode() then break.
    if ~CmtQ.opRun or CmtQ.padPrev then cycle.                                      ! only a member with NO operator
    opGrpQ.gKey = CmtQ.opRun
    get(opGrpQ, opGrpQ.gKey)
    if errorcode() then cycle.
    if CmtQ.codeEnd > opGrpQ.gCode and CmtQ.codeEnd - opGrpQ.gCode <= self.cmtReach
      opGrpQ.gCode = CmtQ.codeEnd                                                   ! within reach: it sets the column
      put(opGrpQ)
    end
  end


  ! THE GROUP STEPS BACK TOGETHER - ruled 10 Sep, per RUN not per row. A bar carrying a comment gives
  ! the column to the '!' and sits in front of it; a bar with nothing after it has no reason to move at
  ! all. Stepping each row back by its OWN gap would leave those two kinds of bar in DIFFERENT columns:
  ! thirteen bars in one column, five of them commented, would be split in two by per-row
  ! stepping, eight bars moving for no reason a reader would see. So the widest gap
  ! in the run is what every bar in it steps back by, and a run with no comment on any bar steps back
  ! by nothing - which is exactly where it already was.
  loop x = 1 to records(CmtQ)
    get(CmtQ, x)
    if errorcode() then break.
    if CmtQ.kind <> 2 or ~CmtQ.opRun or ~CmtQ.cmtBack then cycle.
    opGrpQ.gKey = CmtQ.opRun
    get(opGrpQ, opGrpQ.gKey)
    if errorcode() then cycle.
    if CmtQ.cmtBack > opGrpQ.gBack
      opGrpQ.gBack = CmtQ.cmtBack
      put(opGrpQ)
    end
  end
  loop x = 1 to records(CmtQ)
    get(CmtQ, x)
    if errorcode() then break.
    if CmtQ.kind <> 2 or ~CmtQ.opRun then cycle.                                    ! the row that CLOSES the statement joins opRun
                                                                                    !   but owns its own '!' - it must keep
                                                                                    !   cmtBack 0 or its comment is pushed gBack
                                                                                    !   past the column.
    opGrpQ.gKey = CmtQ.opRun
    get(opGrpQ, opGrpQ.gKey)
    if errorcode() then cycle.
    CmtQ.cmtBack = opGrpQ.gBack
    put(CmtQ)
  end
  pl = 1
  loop while pl <= records(CmtQ)
    get(cmtQ, pl)
    if CmtQ.Pos < 2 or CmtQ.freeze                                                  ! a REFUSED row is an anchor, and
      pl += 1
      cycle
    end
    plCol  = CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack
    plMin  = CmtQ.codeEnd + acGap + CmtQ.cmtBack
    plW1 = plMin                                                                    ! the seed is a code floor too
    free(wQ)
    wQ.wqW = plMin ; add(wQ)
    free(pQ)
    if pl > 1 and ~CmtQ.blkStart                                                    ! the plain line right ABOVE the first commented
      get(cmtQ, pl - 1)                                                             !   row is in this block too, and touches it
      if ~errorcode() and CmtQ.Pos < 2 and CmtQ.codeEnd
        pQ.pqW = CmtQ.codeEnd + acGap ; pQ.pqX = 0 ; add(pQ)                        ! ABOVE the run's first comment: not inside it
      end
      get(cmtQ, pl)
    end
    plBar = choose(CmtQ.kind = 2)
    plNonCode = 0                                                                   ! and nothing else has spoken yet
    plWho  = pl ; plWhy = 'first'
    plKind = CmtQ.kind                                                              ! see the note below
    plFroze = 0
    plEnd  = pl
    plLast = pl                                                                     ! last row that actually took part
    ! LOOK BACK FIRST. A frozen row is an anchor: it cannot move, so the column belongs to it and
    ! a run sitting just BELOW one at the same column must not be tightened away from it. Scanning
    ! FORWARD only leaves an anchor behind the cursor invisible: three CASE arms written at column
    ! 57 to match a frozen comment seven lines above would be pulled back to 55 on their own, out of
    ! step with the block they belong to.
    do PullLookBack                                                                 ! may set plFroze
    loop while plEnd + 1 <= records(CmtQ)                                           ! how far does this column run?
      plEnd += 1
      get(cmtQ, plEnd)
      plPrevBar = plBar ; plBar = choose(CmtQ.kind = 2 and CmtQ.Pos >= 2)
      if CmtQ.blkStart then break.
                                                                               !   a PROCEDURE, ROUTINE or CODE line -
                                                                               !   the declarations above one and the
                                                                               !   statements below have no business
                                                                               !   sharing a column
      ! a line with NO COMMENT has Pos = 0, and CmtQ holds a row for EVERY line - so
      ! this must SKIP those, so the walk `cycle`s past them. Do NOT
      ! use `break` here: that ends the run at the first uncommented line, so two comments with
      ! one plain statement between them become two runs of one, each pulled left to its own
      ! code, and they stop lining up with each other.
      if CmtQ.Pos < 2
        ! WHAT SEPARATES ONE BLOCK FROM THE NEXT: nothing but a PROCEDURE, ROUTINE or CODE
        ! line - the blkStart test above - so a gap is not a separator. The unmarked CLOSING
        ! line of a wrapped statement is part of that statement, and it votes with the
        ! statement's width.
        if (plPrevBar or self.cmtFloor = 2) and CmtQ.codeEnd                        ! --cmtfloor=all: every plain line sets a floor, as the closing line of a wrapped statement always does
          wQ.wqW = CmtQ.codeEnd + acGap ; add(wQ)
        elsif CmtQ.codeEnd
          ! A PLAIN LINE THAT TOUCHES A COMMENTED ONE counts within self.cmtReach (--cmtreach=) of the column the
          ! commented lines set - see PlainReach: a
          ! comment must not sit level with a slightly longer line beside it, and a line that is a
          ! lot longer, or not beside it, changes nothing. The neighbour below must be in this block.
          acEnd = CmtQ.codeEnd ; acAdj = 0
          get(cmtQ, plEnd - 1)
          if ~errorcode() and CmtQ.Pos >= 2 then acAdj = 1.
          get(cmtQ, plEnd + 1)
          if ~errorcode() and CmtQ.Pos >= 2 and ~CmtQ.blkStart then acAdj = 1.
          get(cmtQ, plEnd)
          if acAdj
            pQ.pqW = acEnd + acGap ; pQ.pqX = plEnd ; add(pQ)
          end
        end
        cycle
      end
      if CmtQ.hangFrom                                                              ! a PASSENGER travels with its anchor: it is neither a
        plLast = plEnd                                                              !   vote (it has no column of its own to tighten) nor a
        cycle                                                                       !   floor (it is not settled until its anchor is). It
      end                                                                           !   does not END the run either - leaving plLast behind would move every later run boundary in the file, because a run starts at
                                                                                    !   the previous one plus 1. Skipped BEFORE the kind test below, or a kind-1 hanging row would end a kind-2 run it sits inside.
      ! RUN MEMBERSHIP MUST NOT DEPEND ON THE CURRENT COLUMN. Write it as
      !     if CmtQ.Pos + CmtQ.Adjust <> plCol then break.
      ! and that one line is a ratchet: membership decides the run's floor (the widest
      ! member's code), the floor decides the column, and membership would be keyed on the very
      ! thing the previous pass just changed - so the answer would depend on where the comments
      ! came in, not on the code. The SAME rows at indent 2, read on two legs of a round trip:
      !     leg 1  PL run 1019-1021  col 32 min 29  -> PULL 3   -> column 29
      !     leg 3  PL run 1019-1033  col 31 min 31  -> stay     -> column 31
      !     leg 1  PL run 1293-1305  col 76 min 76  -> stay     -> column 76
      !     leg 3  PL run 1293-1306  col 95 min 89  -> PULL 6   -> column 89
      ! Same code, same floors, different RUN BOUNDARIES, so different answers - and the markers
      ! that differ across such a round trip sit at exactly the column the previous leg left
      ! them in. So a group has to be decided by the SOURCE and not by where the last leg
      ! put the comments. It is: a run spans from one PROCEDURE, ROUTINE or CODE line to the next
      ! and takes either marker, and a gap of any size does not end it. That is a property of the
      ! source, so both legs build the same groups and compute the same column.
      ! A BAR AND AN OPENER VOTE LIKE ANY OTHER MEMBER. The widest floor under the limit sets the
      ! column, so a wide bar or a wide header cannot drag the column out: past the limit it
      ! simply keeps its own end.
      ! ROWS OF EITHER KIND TIGHTEN TOGETHER, AND EITHER KIND VOTES. There is no marker test in
      ! this walk at all: a '!' comment and a '|' continuation settle into one shared column when
      ! they are near each other - deliberate, since everything after either one is ignored by the
      ! compiler - and the vote above is taken over both. `plKind` is not read here; it belongs to
      ! PullLookBack, which declines to LAND on a block of a different marker, and to --acdiag.
      ! WHAT LIMITS THE TIGHTENING IS THE WIDEST MEMBER'S CODE, not the kind of marker it carries.
      ! A continuation sits at the end of a long statement and a comment at the end of a short
      ! declaration, and the run can only tighten as far as its widest member allows. Two
      ! declaration comments at column 80 can move back only THREE characters when a wrapped
      ! `if` two lines below puts its '|' in the same column and its code runs to 75 - the
      ! member, not the mechanism, is what to look at when --acdiag reports a small
      ! adjustment where a large one is due.
      ! a frozen row is an anchor for the WHOLE block, so it is INCLUDED in the run
      ! and does not end it. Break here and the rows after the anchor start a fresh run with no
      ! anchor in it, and that one gets pulled left on its own - so three CASE arms would
      ! land at column 56 while the commented lines above and below them stay at 58.
      ! AN ANCHOR RAISES THE GROUP'S FLOOR; IT DOES NOT VETO THE GROUP. A frozen row cannot
      ! move, so the group simply cannot tighten past it - which is a floor, and says so. A
      ! veto is too blunt: it also stops a group that has merely been PUSHED onto an anchor's
      ! column from ever coming back, and that is one of the two shapes a
      ! ratchet takes. Treating it as a floor keeps every case a veto would protect (the group
      ! still cannot leave its anchor) while letting everything else settle where the code says.
      if CmtQ.freeze and CmtQ.frzKind <> 2                                          ! an `end ! text` row raises NO floor - its own one word of code says nothing about where the block's comments belong
        if CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack > plNonCode
          plNonCode = CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack
          plWho = plEnd ; plWhy = 'frozen'
        end
      else
        acWid = CmtQ.codeEnd + acGap + CmtQ.cmtBack                                 ! this row's own code floor
        if ~CmtQ.freeze or self.cmtEndCount                                         ! an `end ! text` row takes the column and
          wQ.wqW = acWid ; add(wQ)                                                  !   is not counted among the rows the
        end                                                                         !   column is measured over
        if acWid > plW1                                                             ! the widest code floor is the fallback
          plW1 = acWid                                                              !   column when nothing is under the limit
          plWho = plEnd ; plWhy = 'code'
        end
      end
      plLast = plEnd
    end
    plEnd = plLast                                                                  ! the run ends at its last MEMBER
    ! land on the block above if there is one and it clears our code
    ! THE COLUMN IS THE WIDEST FLOOR OF THE BULK, and a wider line keeps its comment at
    ! its own end. The whole of it is in BulkColumn below, and PlainReach then lifts it for a
    ! plain neighbour that is only a little wider.
    plMin = plW1
    do BulkColumn
    do PlainReach
    do KeepAligned
    if plNonCode > acLimit then plNonCode = 0.                                      ! an anchor past the limit lifts nothing
    if plNonCode > plMin then plMin = plNonCode ; plWhy = 'frozen'.                 ! an anchor is a floor the code cannot argue with
    if plNbr > acLimit then plNbr = 0.                                              ! nor does the block above, past it
    if plNbr and plNbr > plMin then plMin = plNbr ; plWho = 0 ; plWhy = 'nbr'.      ! the block above is a floor too, not a ceiling
    ! --acdiag REPORTS THE PULL-LEFT DECISION, which is the one that decides whether a block
    ! can give space back - i.e. whether 2 -> 4 -> 2 returns. A marker that differs across
    ! the round trip mostly sits at EXACTLY the column the previous leg left it in, so the pull
    ! is declining there, and without this line nothing would say why.
    if self.acDiag
      self.TraceIt('PL run ' & pl & '-' & plEnd & ': col-in ' & plCol & ' min ' & plMin       & |
                   ' kind ' & plKind & ' nbr ' & plNbr                                        & |
                   choose(plFroze = 1, ' has-anchor', '')                                     & |
                   choose(plMin >= plCol, ' no-room-vs-first', '')                            & |
                   ' -> col ' & plMin & ' [set by row ' & plWho & ' via ' & clip(plWhy) & ']' & |
                   choose(plKeep = 1, ' KEPT-ALIGNED', ''))
    end
    if plMin >= 2 and ~plKeep
      loop x = pl to plEnd
        get(cmtQ, x)
        if CmtQ.Pos < 2 or                                                          |   ! no comment on this line - nothing to move
           CmtQ.keepRow or                                                          |   ! its group is already in one column that clears it
           CmtQ.freeze and CmtQ.frzKind <> 2                                        ! an anchor set the floor and does not move.
          cycle
        end
                                                                !   An `end ! text` row set no floor, so it is free to
                                                                !   be SET to the block's column HERE - and only here.
                                                                !   Nothing may move it afterwards: a later move
                                                                !   would stop the 2-4-2 round trip returning on
                                                                !   more files. THERE IS NO CAP ON A TOTAL MOVE
                                                                !   anywhere in this procedure - do not reason from one.
                                                                !   `end ! text` is not one: it sets no floor, so
                                                                !   it is free to land on the block's column.
        ! SET the column rather than shifting by a common delta. The group's members do not
        ! have to arrive sharing a column - requiring that is the ratchet - so there is no
        ! single delta to apply. plMin is the floor every member cleared, so every member goes
        ! there, and the answer depends only on the code.
        ! THE WIDTH TEST MUST NOT LOOK AT WHERE THE COMMENT CURRENTLY IS. A test on
        ! `CmtQ.lineLen <= pMaxWidth` would cap only a line which FITS, and lineLen is the line
        ! AS IT STANDS, padding and all, so the same row would answer differently on the two
        ! legs of a round trip:
        !   leg 1  comment at col 28, line 116 long, fits -> cap applies -> refuses the move
        !   leg 3  comment at col 125, line 213 long, already over -> cap does not apply ->
        !          the row is set to 125 and stays there
        ! Same code, same group, same target, opposite outcomes - a ratchet.
        ! What is invariant is the marker and its text: lineLen - Pos does not depend on the
        ! padding in front of it. So measure the line AS IT WOULD BE at the target, and when it
        ! will not fit, put the row at its OWN floor instead of the group's. That is still
        ! decided entirely by the code, so both legs agree; and a comment too long to sit at
        ! the shared column sits as far left as it can rather than being left where it lay.
        plTgt = plMin
        ! A BAR ALIGNS WITH THE OTHER BARS, NOT WITH THE COMMENTS.
        ! A run can hold both, and when it does the comment column is often far narrower
        ! than the widest wrapped statement in it - a run can settle at 62 because a comment row
        ! set it while one bar in it needs 88. Left to `past my own code`, that bar and the
        ! next would sit 26 columns apart. So every bar in the run targets the widest bar's
        ! floor, and the comments keep theirs. The rule still holds - a bar sets no column FOR
        ! COMMENTS - it just does not have to LIVE in the comments.
        if CmtQ.opRun                                                               ! any bar, and the row that closes the statement
          opGrpQ.gKey = CmtQ.opRun
          get(opGrpQ, opGrpQ.gKey)
          if ~errorcode() and opGrpQ.gN > 1 and opGrpQ.gWide > plTgt
            plTgt = opGrpQ.gWide                                                    ! align with the ADJACENT bars, not the whole run
          end
        end
        ! A HEADER JOINS THE BLOCK'S COLUMN ONLY WHEN THAT COLUMN CLEARS ITS OWN CODE, and
        ! takes its own floor when it does not - it never comes left of its own declaration.
        !
        ! IT MUST NOT SIMPLY BE LEFT WHERE IT LIES. A row left where it lay keeps whichever
        ! column the previous leg put it in, which is the ratchet the rest of this walk refuses:
        ! what a row may do is read from the CODE, never from where the comments came in. So a
        ! header takes the block's column when that column clears its own code, and its own
        ! floor when it does not - both computed from the code, which is what makes 2 -> 4 -> 2
        ! come back. A RUN DOES NOT REACH ACROSS A PROCEDURE: it ends at a PROCEDURE, FUNCTION
        ! or ROUTINE line in column 1 and at the CODE statement inside one, and a gap of any
        ! size does not end one.
        ! NO ROW EVER COMES LEFT OF ITS OWN CODE. A header may take the block's column but
        ! never set it; this covers ANY row for the same reason, because the
        ! bar rule above creates a second kind of non-voting row. Both need the identical
        ! treatment - take the block's column when it clears your code, your own floor when it
        ! does not - so they get one rule rather than two. Without this a wide bar that did not
        ! vote would be dragged left into its own code, which is corruption rather than layout.
        ! Still computed entirely from the code, which is what makes 2 -> 4 -> 2 come back.
        if plTgt < CmtQ.codeEnd + acGap + CmtQ.cmtBack
          plTgt = CmtQ.codeEnd + acGap + CmtQ.cmtBack
        end
        CmtQ.Adjust = plTgt - CmtQ.cmtBack - CmtQ.Pos
        put(cmtQ)
      end
    end
    pl = plEnd + 1
  end

  ! ---- THE PASSENGERS TRAVEL ----------------------------------------------
  ! Every column has been decided by here - each run has been put where its code says it goes -
  ! so a passenger can be told where its anchor went.
  ! It lands on the anchor's COLUMN, not by the anchor's ADJUST. Taking the ADJUST would keep a
  ! hanging row written one character left of the row above (36 under 37) as the author's own
  ! offset - but AlignDeclTypes runs BEFORE this routine and may have re-columned the
  ! declaration, moving the anchor's marker one right, so the delta would preserve a stagger
  ! the author never wrote - anchor at 73, its own two rows at 72. Landing on the column cannot
  ! do that, and it is what authors mean: a comment continued under itself is written with
  ! anchor and hanging rows at exactly the same column. The indentation INSIDE a
  ! hanging comment ('!   this one') is text after the marker and survives either way.
  ! It works whichever way the anchor moved, which matters - both directions are real, and the
  ! pull-left one only shows up on files whose comments sit far right of short code.
  !
  !
  ! This runs BEFORE the --acdiag block on purpose, so the diagnostic reports the columns that
  ! actually reach the file rather than the state one pass earlier.
  ! The apply loop below needs no change at all: it moves any row carrying an Adjust.
  ! -----------------------------------------------------------------------------------
  loop hgX = 1 to records(CmtQ)
    get(CmtQ, hgX)
    if errorcode() then break.
    if ~CmtQ.hangFrom then cycle.
    hgAnc = CmtQ.hangFrom
    get(CmtQ, hgAnc)
    if errorcode() then cycle.
    hgAdj = CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack                                   ! the anchor's FINAL column
    get(CmtQ, hgX)
    if errorcode() then cycle.
    if hgAdj = CmtQ.Pos then cycle.                                                 ! already there - nothing to move
    CmtQ.Adjust = hgAdj - CmtQ.Pos
    put(CmtQ)
  end

  ! ---- DIAGNOSTIC, --acdiag only. Transforms nothing. Runs LAST, after the pull-left
  !      pass, so it reports the state that actually reaches the file. Placed BEFORE the
  !      pull-left it would report everything as fine - true at that point, and useless, because
  !      the lines it stays silent about are exactly the ones moved afterwards.
  !      This arithmetic reads as correct more easily than it is, so this reports what it
  !      actually decided per line instead of what it looks
  !      like it should decide. For every row that ends up at a DIFFERENT column from the row
  !      above it, print both, and the reason it could not be moved. Read the two columns and
  !      the reason together - a row that says `frozen` when it plainly has code before its
  !      comment means the freeze rule is wrong.
  !      OUT-OF-WINDOW IS A MEASUREMENT AND NOT A REASON. It says the nearest commented row above
  !      this one is more than --cmtrun lines away. A gap ends no run here - the run walk breaks
  !      only at a PROCEDURE, ROUTINE or CODE line - so it never explains why a row stayed where
  !      it is. What it does mark is a row the LOOK-BACK could not see past, because --cmtrun is
  !      what bounds that walk: a run whose FIRST row carries it had no block above it to land on.
  if self.acDiag
    cmtCol = 0 ; cmtLine = 0
    loop x = 1 to records(CmtQ)
      get(cmtQ, x)
      if CmtQ.Pos < 2 then cycle.
      if cmtLine and CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack <> cmtCol
        self.TraceIt('AC line ' & x & ': col ' & (CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack) & |
                     ' but line ' & cmtLine & ' is at ' & cmtCol                         & |
                     ' - pos ' & CmtQ.Pos & ' adj ' & CmtQ.Adjust                        & |
                     ' codeEnd ' & CmtQ.codeEnd & ' lineLen ' & CmtQ.lineLen             & |
                     ' kind ' & CmtQ.kind                                                & |
                     choose(CmtQ.freeze = 1, ' FROZEN', '')                              & |
                     choose(x - cmtLine > self.cmtRun, ' OUT-OF-WINDOW', ''))
      end
      cmtCol  = CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack
      cmtLine = x
    end
  end

  ! now adjust comment positions in tokens Q
  ! ---- GIVE THE TRAILING OPERATOR A COLUMN OF ITS OWN. ----
  !
  ! Placed FROM the bar - `Pos + Adjust - codeEnd - 1` - an operator lands at whatever "three
  ! left of the bar" happens to be, and moves whenever the COMMENT column moves: two things in
  ! one column and only one of them meaning anything.
  !
  ! So there are two columns and each is decided by something real:
  !     the OPERATOR column comes from the CODE  - two past the widest code in the block
  !     the BAR column stays the COMMENT column  - where it already is
  !
  !     if param.FindChars(' --batch ')    or |          code ends at 33, so `or` sits at 35
  !        param.EndsWith(' --batch')      or |          and the bars stay where they were
  !        param.StartsWith('--batch ')
  !
  ! *** BOTH COLUMNS ARE COMPUTED FROM CODE WIDTHS AND NOTHING ELSE, which is the property this
  ! whole procedure lives or dies by. opCode is the code end WITHOUT the operator - if the
  ! operator were included, a run holding both `and` and `or` would give itself a different
  ! column depending on which row was widest, and the answer would depend on the operators
  ! rather than on the code. Lose this property - key a decision on the thing the previous
  ! pass has just written - and repeated runs stop agreeing. ***
  !
  ! A BLOCK IS A PULL-LEFT RUN - CmtQ.opRun, stamped where the runs are formed. A run is built
  ! from source ADJACENCY and marker KIND, so it is the same on both legs of a round trip.
  !
  ! *** KEYING ON `Pos + Adjust` - the column the rows have ALREADY been given - would be
  ! that mistake verbatim. Rows whose bars are ragged (two at column 102, one at 109) would
  ! land in three separate blocks, each compute its own operator column, and NOTHING would
  ! MOVE: a no-op on precisely the blocks the pass exists to fix.
  ! A ragged answer can never be the key that groups the rows which are to be un-ragged. ***
  !
  ! IF THE TWO COLUMNS WILL NOT FIT, THE WHOLE BLOCK KEEPS ONE COLUMN. Falling back per-ROW
  ! would leave one row placed from the code and its neighbour placed from the bar, which reads
  ! worse than either rule applied consistently. opGap = 0 is that fallback and the apply below
  ! reads it.
  free(opBlkQ)
  loop x = 1 to records(CmtQ)                                                       ! widest code per block
    get(CmtQ, x)
    if errorcode() then break.
    if self.acDiag and CmtQ.Pos > 1
      self.TraceIt('IT2SEE row ' & x & ' kind ' & CmtQ.kind & ' padPrev ' & CmtQ.padPrev & |
                   ' run ' & CmtQ.opRun & ' pos ' & CmtQ.Pos & ' adj ' & CmtQ.Adjust & ' codeEnd ' & CmtQ.codeEnd)
    end
    if ~CmtQ.padPrev then cycle.
    opKey = CmtQ.opRun
    if ~opKey then cycle.
    opBlkQ.bkKey = opKey
    get(opBlkQ, opBlkQ.bkKey)
    if errorcode()
      opBlkQ.bkKey  = opKey
      opBlkQ.bkWide = CmtQ.opCode
      opBlkQ.bkN    = 1
      opBlkQ.bkOk   = 1
      add(opBlkQ, opBlkQ.bkKey)
    else
      opBlkQ.bkN += 1
      if CmtQ.opCode > opBlkQ.bkWide then opBlkQ.bkWide = CmtQ.opCode.
      put(opBlkQ)
    end
  end
  loop x = 1 to records(CmtQ)                                                       ! can every row of the block fit two columns?
    get(CmtQ, x)
    if errorcode() then break.
    if ~CmtQ.padPrev then cycle.
    opKey = CmtQ.opRun
    if ~opKey then cycle.
    opBlkQ.bkKey = opKey
    get(opBlkQ, opBlkQ.bkKey)
    if errorcode() then cycle.
    ! THE OPERATOR IS ANCHORED TO THE CODE, NOT TO THE BAR - that is --cmtop=code, the default. Two past the
    ! widest code in the BLOCK - a lone bar whose own code ends at 8, in a block that runs
    ! to 22, has its operator at 24. Switching this off for a lone bar, or measuring it over
    ! the bar group alone, would both be too narrow.
    ! --cmtop=bar anchors it to the BAR instead: the operator ends one space before the bar, whatever
    ! column the code stops at. The fit test below refuses the block either way when the code crowds it.
    opGrpQ.gKey = opKey                                                             ! FETCH the group before reading gCode -
    get(opGrpQ, opGrpQ.gKey)                                                        !   without this it is whatever the last
    if errorcode() then cycle.                                                      !   get left in the buffer
    opCol = choose(~self.cmtOpBar, opGrpQ.gCode + 2, CmtQ.Pos + CmtQ.Adjust - CmtQ.opSz - 1) ! --cmtop=bar: the operator ends one space before the bar
    if opCol - CmtQ.opCode - 1 < 1 or                                               |                ! gap before the operator
       CmtQ.Pos + CmtQ.Adjust - opCol - CmtQ.opSz < 1                               ! gap between the operator and the bar
      if self.acDiag
        self.TraceIt('IT2 REFUSE row ' & x & ' run ' & opKey & ' opCode ' & CmtQ.opCode & |
                     ' opSz ' & CmtQ.opSz & ' gCode ' & opGrpQ.gCode & ' bar ' & (CmtQ.Pos + CmtQ.Adjust))
      end
      opBlkQ.bkOk = 0
      put(opBlkQ)
    end
  end
  loop x = 1 to records(CmtQ)                                                       ! stamp the two gaps on the rows that fit
    get(CmtQ, x)
    if errorcode() then break.
    if ~CmtQ.padPrev then cycle.
    opKey = CmtQ.opRun
    if ~opKey then cycle.
    opBlkQ.bkKey = opKey
    get(opBlkQ, opBlkQ.bkKey)
    if errorcode() then cycle.
    if ~opBlkQ.bkOk then cycle.
    opGrpQ.gKey = opKey
    get(opGrpQ, opGrpQ.gKey)
    if errorcode() then cycle.
    opCol       = choose(~self.cmtOpBar, opGrpQ.gCode + 2, CmtQ.Pos + CmtQ.Adjust - CmtQ.opSz - 1)
    if self.acDiag
      self.TraceIt('IT2 row ' & x & ' run ' & opKey & ' opCode ' & CmtQ.opCode & ' opSz ' & CmtQ.opSz & |
                   ' gCode ' & opGrpQ.gCode & ' bar ' & (CmtQ.Pos + CmtQ.Adjust) & ' -> opCol ' & opCol) ! the column the code applies, under either --cmtop
    end
    CmtQ.opGap  = opCol - CmtQ.opCode - 1
    CmtQ.opBar  = CmtQ.Pos + CmtQ.Adjust - opCol - CmtQ.opSz
    put(CmtQ)
  end

  loop x = 1 to records(CmtQ)
    get(cmtQ,x)
    ! *** NORMALISING AN `op |` GAP IS UNCONDITIONAL, NOT TIED TO A MOVE: conditional, a row
    ! reads `or   |` on the leg that leaves it alone and `or |` on the leg that moves it, and
    ! the round trip never settles. It is safe unconditionally only because Pos is the '|'
    ! WHERE IT IS and the operator is placed from it: the gap in front of the operator is
    ! Pos + Adjust - codeEnd - 1, decided by the code and the target and nothing else. So
    ! squeezing never moves a '|' - the slack goes in front of the operator - and both legs
    ! write the same text. (A Pos that GUESSED the bar's column after the squeeze, with the
    ! padding on the operator, would slide the bar and disagree with its own text.) ***
    ! A padPrev row comes through even when it is NOT moving: its gap is normalised from the
    ! CODE, so a row that stays put still gets the same text on both legs of a round trip. This
    ! is only safe because normalising does NOT move the '|' - the slack goes in front of the
    ! operator, as the note above says. A row with a comment after its bar comes through as
    ! well, so that BarCmtCols knows where its bar is.
    if ~CmtQ.Adjust and ~CmtQ.padPrev and ~CmtQ.barSp then cycle.
    if ~CmtQ.Pos then self.TraceIt('VitTokenize.AlignComments: unexpected lack of comment pos on line ' & x);cycle.
    acShift = 0 ; acCounted = 0 ; acBarTok = 0

! not this: a keyed get alone does not allow for breaks in line numbers where there is a complete comment line
!    self.Tokens.lineNo = x+1  ! get first token of line after
!    get(self.tokens,self.Tokens.lineNo)

! nor this: re-sorting upsets other things - the sort is not "stable"
!    sort(self.tokens, +self.Tokens.lineNo)
!    clear(self.tokens)
!    self.Tokens.lineNo = x+1  ! get first token of line after
!    get(self.tokens,position(self.tokens))  ! do this to allow for breaks in line numbers where there is a complete comment line

! so: first try the keyed get, then if it fails start at current line number and read forward until line number changes
    self.Tokens.lineNo = x+1                                                        ! get first token of line after
    get(self.tokens,self.Tokens.lineNo)
    if errorcode()
      self.Tokens.lineNo = x                                                        ! get first token of curr line
      get(self.tokens,self.Tokens.lineNo)
      if errorcode()
        self.TraceIt('error did not find first token on line ' & x)
      else
        loop
          get(self.tokens,pointer(self.Tokens)+1)
          if errorcode() then break.
          if self.Tokens.lineNo <> x then break.
          ! keep going until we get a different line number
        end
      end
    end
    if errorcode()
      get(self.tokens,records(self.tokens))                                         ! get last record
    else
      get(self.tokens,pointer(self.Tokens)-1)                                       ! get previous record to get last token on line x
      if errorcode() then get(self.tokens,1).                                       ! get first token line
    end
    if errorcode() then self.TraceIt('unexpected error getting last token record for line ' & x & ' Errorcode = ' & errorcode()).
    if self.tokens.LineNo <> x then self.TraceIt('VitTokenize.AlignComments: did not find last token on line - ' & x & ' line=' & self.tokens.LineNo);cycle.

    if not self.tokens.tok &= NULL and self.tokens.tok = '<10>'                     ! EOL; the null test first - tok is a reference and may be unset
      if self.Tokens.strBefore &= null
        self.TraceIt('VitTokenize.AlignComments: did not find comment #1 on line ' & x)
        cycle
      end
      acBarTok = pointer(self.Tokens)                                               ! the '|' is in this token's own leading text
      do MarkerLine                                                                 ! a line break in that text: the row's own line
      if acLf then cycle.                                                           !   starts after it, and MarkerLine has moved it
    elsif CmtQ.padPrev and not self.tokens.tok &= NULL and                          |
          (self.tokens.tok = '&' or upper(self.tokens.tok) = 'AND' or upper(self.tokens.tok) = 'OR')
      ! `& |` moves together. The '|' lives in the NEXT token's leading trivia, so
      ! padding that token would slide the '|' right and leave the '&' behind. Pad the '&'
      ! instead - the '|' sits one space after it and comes along.
      ! and squeeze the gap between them to ONE space, so the '&' column is fixed
      ! relative to the '|' column and lining one up lines up the other.
      acBarTok = pointer(self.Tokens) + 1                                           ! the '|' is in the NEXT token's leading text
      do NormaliseAmpGap
    else
      get(self.tokens,pointer(self.Tokens)+1)                                       ! get next record
      if errorcode() or not self.Tokens.firstOnLine
        self.TraceIt('VitTokenize.AlignComments: did not find comment #2 on line ' & x)
        cycle
      end
      acBarTok = pointer(self.Tokens)
    end
    ! Adjust can be NEGATIVE - the pull-left pass computes one whenever a block can
    ! give space back. A negative Adjust cannot be applied by padding (all(' ', n) with
    ! n < 0 gives no spaces), so the else arm below removes that many leading spaces
    ! instead, never closing the gap completely, and counts the row as moved only when
    ! it changed.
    if CmtQ.padPrev
      ! AN `op |` ROW IS PLACED, NOT NUDGED. Everything else here moves by a DELTA, which is
      ! fine when the thing being padded is the marker itself. For one of these the padding
      ! goes on the OPERATOR while the column belongs to the '|' two characters past it, and a
      ! delta then depends on the gap the author happened to leave. Compute the gap instead:
      ! the layout is [code][gap][operator][one space][|], the '|' is to land at Pos + Adjust,
      ! and codeEnd already carries the operator, so gap = Pos + Adjust - codeEnd - 1. That is
      ! decided by the CODE and the target alone, so both legs of a round trip write the same
      ! text - which is the whole point, and why this runs even when Adjust is 0.
      ! when the block fits two columns, opGap was computed from the CODE and the
      ! operator is placed at ITS OWN column; opBar then carries the bar out to the comment
      ! column, which is where it already was. Otherwise fall through to the one-column form,
      ! where the operator is placed from the bar and sits one space in front of it.
      if CmtQ.opGap
        ppNeed = CmtQ.opGap
      else
        ppNeed = CmtQ.Pos + CmtQ.Adjust - CmtQ.codeEnd - 1
      end
      if ppNeed < 1 then ppNeed = 1.                                                ! one space is the floor, always
      ppKeep = 0
      loop acZ = 1 to size(self.Tokens.strBefore)                                   ! anything but spaces in there and this
        if self.Tokens.strBefore[acZ] <> ' ' then break.                            !   is not the simple mid-line gap this
        ppKeep += 1                                                                 !   arithmetic describes - leave it alone
      end
      if ppKeep = size(self.Tokens.strBefore) and ppNeed <> ppKeep
        acShift += ppNeed - ppKeep ; acCounted = 1
        self.SetStrBefore(pointer(self.Tokens), all(' ', ppNeed))
        moved += 1
      end
    elsif CmtQ.Adjust > 0
      acShift += CmtQ.Adjust ; acCounted = 1
      self.SetStrBefore(pointer(self.Tokens),all(' ',CmtQ.Adjust) & self.Tokens.strBefore)
      moved += 1
    else
      acTrim = -CmtQ.Adjust                                                         ! how many leading spaces to give back
      acKeep = 0
      loop acZ = 1 to size(self.Tokens.strBefore)                                   ! ... but only ones that are really there
        if self.Tokens.strBefore[acZ] <> ' ' then break.
        acKeep += 1
      end
      if acTrim > acKeep - 1 then acTrim = acKeep - 1.                              ! never close the gap completely
      if acTrim > 0
        self.SetStrBefore(pointer(self.Tokens),                                     |
                          self.Tokens.strBefore[acTrim + 1 : size(self.Tokens.strBefore)])
        moved += 1
        acShift -= acTrim ; acCounted = 1
      end
    end
    if CmtQ.barSp and acBarTok                                                      ! where the bar IS now, for BarCmtCols
      CmtQ.barAt  = CmtQ.Pos + acShift
      CmtQ.barTok = acBarTok
      CmtQ.barCnt = acCounted
      put(CmtQ)
    end
  end
  do BarCmtCols                                                                     ! the comments after the bars, once every bar is placed
!---- for debugging
! self.joinToks(st)
! st.SaveFile('AC join after.txt')
! stop('have done AC joint after.txt')
!----
  get(self.Tokens,svPtr)                                                            ! restore queue to previous state
  return moved

! ---- leave exactly one space between the '&' just processed and the '|' that follows
!      it in the NEXT token's leading trivia. Called with the queue positioned on the '&'. ----
NormaliseAmpGap routine
  data
ngSv   long,auto
ngZ    long,auto
ngSp   long,auto
ngWant long,auto
ngFire long,auto
  code
  ngSv = pointer(self.Tokens)
  get(self.Tokens, ngSv + 1)
  if ~errorcode() and not self.Tokens.strBefore &= NULL
    ngSp = 0
    loop ngZ = 1 to size(self.Tokens.strBefore)        ! count the spaces in front of the '|'
      if self.Tokens.strBefore[ngZ] <> ' ' then break.
      ngSp += 1
    end
    ! squeezing the gap between the operator and the bar to ONE space locks the
    ! two into a single column. With opBar set they are two
    ! separate columns - the operator on the code, the bar on the comments - so the gap
    ! between them is whatever carries the bar out to where it already is. opBar is 0
    ! when the block could not fit two columns, and then this is the one-space rule.
    ! EXACT placement only where this actually gave this row a column. Where it
    ! did not (opBar = 0) the one-column rule stands - squeeze a gap of more than one
    ! space, and leave a gap of none alone. Firing on ngSp <> 1 instead would make the pass
    ! INSERT a space into `&|`, a spelling change on rows the operator pass never touched -
    ! a long `&|` list of words would come back respaced. Widening a rule past the
    ! thing it is for is how a layout pass grows a second, unasked change.
    ngWant = 1
    ngFire = 0
    if CmtQ.opBar > 0
      ngWant = CmtQ.opBar
      if ngSp <> ngWant then ngFire = 1.
    elsif ngSp > 1
      ngFire = 1
    end
    if ngFire and ngZ <= size(self.Tokens.strBefore)
      if self.Tokens.strBefore[ngZ] = '|'              ! only when it really is the continuation
        acShift += ngWant - ngSp                       !   and the bar moves by the difference
        self.SetStrBefore(ngSv + 1, all(' ', ngWant) & self.Tokens.strBefore[ngZ : size(self.Tokens.strBefore)])
      end
    end
  end
  get(self.Tokens, ngSv)

! ---- THE COMMENTS AFTER THE BARS LINE UP. -------------------------------------------------
!      Everything from a '|' rightwards is copied through by the apply, so a comment after a bar
!      rides along behind it at whatever gap its author typed. Bars that start ragged move by DIFFERENT
!      amounts to line up, so comments that were lined up would come out ragged: typed at 40 behind bars
!      at 16 and 17, they would land at 61 and 60 behind bars lined up at 37. So a run holding two or more
!      such comments gives each one a column to land on - the NARROWEST any of them reaches riding
!      along, which is the gap the closest one already has. No comment goes further right than riding
!      along would take it, none comes closer to its bar than the comment gap - a row that could only
!      reach the column that way keeps its text as typed - and a lone one keeps its text as typed. The
!      bars are placed by now, so nothing in the operator and bar chain moves. Under --cmtbar=comment
!      the column is the one the run's bars were stepped back from.
!      IT IS MEASURED FROM WHERE EACH BAR IS - barAt - NOT FROM WHERE IT WAS MEANT TO GO. The two differ
!      when the apply cannot put a bar on its column: a `&|` written with no space keeps that spelling,
!      so its bar lands one short, and a tab in front of an operator or a bar stops the padding. A column
!      taken from Pos + Adjust would sit one past where such a comment rides, the comment would move right
!      to meet it, and the next run would measure the wider gap and move it again, one column a run. From
!      barAt a second run measures the same bars and the same gaps, and changes nothing. ----
BarCmtCols routine
  data
bqX long,auto
  code
  loop bqX = 1 to records(CmtQ)
    get(CmtQ, bqX)
    if errorcode() then break.
    if CmtQ.kind <> 2 or ~CmtQ.opRun or ~CmtQ.barSp or ~CmtQ.barTok then cycle.
    opGrpQ.gKey = CmtQ.opRun
    get(opGrpQ, opGrpQ.gKey)
    if errorcode() then cycle.
    bqDist = CmtQ.barCmt - CmtQ.Pos
    bqCol  = CmtQ.barAt + choose(CmtQ.cmtBack > bqDist, CmtQ.cmtBack, bqDist)
    if ~opGrpQ.gCmtN or bqCol < opGrpQ.gCmt then opGrpQ.gCmt = bqCol.
    opGrpQ.gCmtN += 1
    put(opGrpQ)
  end
  loop bqX = 1 to records(CmtQ)
    get(CmtQ, bqX)
    if errorcode() then break.
    if CmtQ.kind <> 2 or ~CmtQ.opRun or ~CmtQ.barSp or ~CmtQ.barTok then cycle.
    opGrpQ.gKey = CmtQ.opRun
    get(opGrpQ, opGrpQ.gKey)
    if errorcode() or opGrpQ.gCmtN < 2 then cycle.
    CmtQ.cmtTo = opGrpQ.gCmt
    put(CmtQ)
    if self.acDiag then self.TraceIt('BARCMT row ' & bqX & ' run ' & CmtQ.opRun & ': the comment after the bar to col ' & CmtQ.cmtTo).
    acBarTok  = CmtQ.barTok
    acShift   = CmtQ.barAt - CmtQ.Pos
    acCounted = CmtQ.barCnt
    do BarCmtGap
  end

! ---- the row's marker is in the leading text of its line's EOL token, and that text holds a line
!      break when the line above was continued with a '|' (or a folded OMIT block ends just above it):
!      the end of that line, its bar and the break come first, and the row's own line starts after the
!      LAST break. So that is where the row is padded or trimmed - padding the front would move the bar
!      of the line above instead. acLf = 0: no break, and the apply goes on as for any other row. ----
MarkerLine routine
  data
mlZ   long,auto
mlSp  long,auto
mlCut long,auto
mlEnd long,auto
  code
  acLf = 0
  if self.Tokens.strBefore &= NULL then exit.
  mlEnd = size(self.Tokens.strBefore)
  loop mlZ = mlEnd to 1 by -1
    if self.Tokens.strBefore[mlZ] = '<10>' then break.
  end
  if mlZ < 1 or mlZ >= mlEnd then exit.
  acLf = mlZ
  if CmtQ.Adjust > 0
    self.SetStrBefore(pointer(self.Tokens), self.Tokens.strBefore[1 : acLf] & all(' ', CmtQ.Adjust) & self.Tokens.strBefore[acLf + 1 : mlEnd])
    moved += 1
  elsif CmtQ.Adjust < 0
    mlSp = 0
    loop mlZ = acLf + 1 to mlEnd
      if self.Tokens.strBefore[mlZ] <> ' ' then break.
      mlSp += 1
    end
    mlCut = -CmtQ.Adjust
    if mlCut > mlSp - 1 then mlCut = mlSp - 1.
    if mlCut > 0
      self.SetStrBefore(pointer(self.Tokens), self.Tokens.strBefore[1 : acLf] & self.Tokens.strBefore[acLf + mlCut + 1 : mlEnd])
      moved += 1
    end
  end

! ---- put the '!' after this row's '|' on the column its run's comments line up on, CmtQ.cmtTo.
!      acShift is how far the apply moved the bar, so Pos + acShift is where the bar IS rather than
!      where it was meant to go. Only a gap of spaces is rewritten, only the one the walk measured,
!      and only when the '!' can reach the column without coming closer to its bar than the comment gap. ----
BarCmtGap routine
  data
bgZ    long,auto
bgBar  long,auto
bgSp   long,auto
bgWant long,auto
  code
  get(self.Tokens, acBarTok)
  if errorcode() or self.Tokens.strBefore &= NULL then exit.
  bgBar = 0
  loop bgZ = 1 to size(self.Tokens.strBefore)                                       ! the bar is the first thing that is not blank
    if self.Tokens.strBefore[bgZ] = ' ' or self.Tokens.strBefore[bgZ] = '<9>' then cycle.
    if self.Tokens.strBefore[bgZ] = '|' then bgBar = bgZ.
    break
  end
  if ~bgBar then exit.
  bgSp = 0
  loop bgZ = bgBar + 1 to size(self.Tokens.strBefore)
    if self.Tokens.strBefore[bgZ] <> ' ' then break.
    bgSp += 1
  end
  if bgSp + 1 <> CmtQ.barCmt - CmtQ.Pos then exit.                                  ! not the gap the walk measured
  if bgBar + bgSp >= size(self.Tokens.strBefore) or self.Tokens.strBefore[bgBar + bgSp + 1] <> '!' then exit.
  bgWant = CmtQ.cmtTo - (CmtQ.Pos + acShift) - 1                                    ! the spaces that put the '!' on the column
  if bgWant + 1 < acGap or bgWant = bgSp then exit.                                 ! acGap is at least 2, so bgWant is at least 1 past here
  self.SetStrBefore(acBarTok, self.Tokens.strBefore[1 : bgBar] & all(' ', bgWant) & |
                    self.Tokens.strBefore[bgBar + bgSp + 1 : size(self.Tokens.strBefore)])
  if ~acCounted then moved += 1.

! ---- close the physical line: classify it and add its row -----------------------------------
! FREEZE says the row may not move; frzKind says why, because the two reasons want different
! treatment further down.
!   1 = it must not move at all: a full-line comment (a bare '!' on a line of its own included),
!       or a line of dots. These ANCHOR - the column belongs to them.
!   2 = `end ! text`. One word of code says nothing about where a block's comments belong, so it
!       sets no column, but it MAY take one and line up with the statements it closes.
!
! An OPENER is a line that opens a structure, or a prototype. It sets no column either - its
! width is an accident of the declaration - but it may take one. The structure openers were
! found by the token pre-pass above (level '+', outside executable code); a prototype is
! recognised HERE, from the tokens: the second word of the line is PROCEDURE or FUNCTION. That
! cannot be fooled by a string containing the word, because a string is one token and this reads
! whole tokens.
!
! PADPREV is a '|' that follows a trailing '&', 'AND' or 'OR'. The pair moves as ONE unit, so
! codeEnd is set to where the operator WOULD end with a single space in front of it - which is
! what makes `codeEnd + 2` still mean "the leftmost column the '|' could occupy".
CbEndLine routine
  clear(CmtQ)
  CmtQ.pos     = cbPos
  CmtQ.adjust  = 0
  CmtQ.kind    = cbKind
  CmtQ.lineLen = cbCol
  CmtQ.codeEnd = cbCode
  CmtQ.txtInd  = cbTxtInd
  CmtQ.barCmt  = cbBarCmt                                 ! measurement, taken whether or not it is asked for
  CmtQ.barSp   = cbBarSp
  if cbKind = 2 and cbBarCmt and self.cmtBarCmt           ! --cmtbar=comment: the '!' owns the column and the
    CmtQ.cmtBack = cbBarCmt - cbPos                       !   '|' is derived back from it by this much
  end
  if cbPos
    if ~cbCode                                            ! nothing but whitespace before it
      CmtQ.freeze = 1 ; CmtQ.frzKind = 1
    ! A TRAILING BARE `!` IS ALIGNED, NOT REMOVED AND NOT FROZEN.
    !
    ! Freezing it here as an ANCHOR would leave an odd one out odd for ever: a frozen row
    ! may not move, so three rows at 82 and one at 83 could never be brought into line.
    !
    ! They are not removed - some banners carry a `!` on the right-hand
    ! side as a border, and a pass that deletes an empty trailing marker would take those
    ! with it. There is no way to tell a leftover from a border by looking at the marker,
    ! so the tool does not try: it lines them up and leaves the judgement to the author.
    !
    ! A WHOLE-LINE bare marker is still frozen, by the `~cbCode` test ABOVE this one - a
    ! marker with no code in front of it owns its line, and it is how a blank line is
    ! written inside a comment block. Only a marker that FOLLOWS code is freed.
    elsif cbAllDot and cbNCode                            ! a line of dots
      CmtQ.freeze = 1 ; CmtQ.frzKind = 1
    elsif cbNCode = 1 and cbFirstU = 'END'                ! `end ! text`
      CmtQ.freeze = 1 ; CmtQ.frzKind = 2
    end
    ! a structure opener, from the token pre-pass
    loop while opIx <= records(OpenQ)
      get(OpenQ, opIx)
      if errorcode() then break.
      if OpenQ.opLine < cbLine
        opIx += 1
        cycle
      end
      if OpenQ.opLine = cbLine then CmtQ.opener = 1.
      break
    end
    case cbSecondU
    of 'PROCEDURE' orof 'FUNCTION'              ! a prototype is a header too
      CmtQ.opener = 1
    end
    if cbKind = 2 and (cbLastU = '&' or cbLastU = 'AND' or cbLastU = 'OR')
      CmtQ.padPrev = 1
      CmtQ.codeEnd = cbPrevEnd + 1 + cbLastSz   ! as if the gap were one space
      CmtQ.opCode  = cbPrevEnd                  ! and the same width WITHOUT the operator
      CmtQ.opSz    = cbLastSz
    end
  end
  ! A PROCEDURE, FUNCTION or ROUTINE in column 1 AT DEPTH 0 is a definition and starts a
  ! block. Depth matters: a prototype inside a CLASS or MAP also has its label in column
  ! 1, and treating those as block starts would fragment the very declaration block they
  ! belong to. cbDepth is the depth this line STARTED at, before its own opens.
  !
  ! THIS RUNS FOR EVERY LINE, NOT ONLY COMMENTED ONES. The block above is inside
  ! `if cbPos`, and a CODE statement carries no comment - so a test placed in there never
  ! fires on the very line it is looking for, and the depth count never advances either.
  if cbFirstCol = 1 and cbHasProc and ~cbDepth
    CmtQ.blkStart = 1
  end
  ! ... and so does the CODE statement inside one, which is where the declarations end.
  ! Not a column-1 `code`, which is a variable of that name - the same distinction
  ! VitEngine.CodeTokOfScope already makes.
  if cbFirstU = 'CODE' and cbNCode = 1 and cbFirstCol > 1
    CmtQ.blkStart = 1
  end
  cbDepth += cbOpens - cbCloses
  if cbDepth < 0 then cbDepth = 0.
  add(CmtQ)
  cbLine += 1
  cbCol = 0 ; cbCode = 0 ; cbPos = 0 ; cbKind = 0 ; cbInCmt = 0 ; cbTxt = 0 ; cbSpAfter = 0 ; cbTxtInd = 0 ; cbBarCmt = 0 ; cbBarSp = 0 ; cbBarTab = 0
  cbNCode = 0 ; cbFirstU = '' ; cbSecondU = '' ; cbLastU = '' ; cbLastSz = 0
  cbPrevEnd = 0 ; cbAllDot = 1
  cbFirstCol = 0 ; cbHasProc = 0
  cbOpens = 0 ; cbCloses = 0

! ---- THE COLUMN RULE: ONE COLUMN PER BLOCK, AND IT NEVER GOES PAST --cmtlimit TO LINE ANYTHING UP.
!      wQ holds every voter's floor - code end plus the gap. The column is the widest floor
!      not past the limit (90); a line whose code ends past it keeps its comment at its own end,
!      which the apply loop's "never left of your own code" rule does on its own. A block with
!      no line under the limit at all takes the widest floor within --cmtslack (60) of its
!      narrowest. The limit is stated from the reader's side - comments must not go out to the
!      right - and it reproduces the author's own layout wherever that layout is good. Two
!      other definitions fail: a percentile ("at most 15% may be outliers") lets the six
!      widest rows of a procedure sit out although every one is within reach, and turns one
!      column into four; a budget from the narrowest row lets one `cycle ! why` at indent 4
!      make outliers of everything wider than 70.
!
!      AND, IF YOU ASK FOR IT, ONE VERY WIDE LINE DOES NOT DRAG ITS BLOCK OUT. Give --cmtoutlier
!      a number and a floor more than that past the MIDDLE of the block stops setting the column:
!      it keeps its own comment at its own end and the rest stay where they were. OFF unless
!      asked for. The MIDDLE, not the next line down: comparing against the next-widest lets
!      two long lines shield each other - a 145-character prototype beside a 142 would take a
!      whole file out to 148 while the declarations around them are 27 wide.
BulkColumn routine
  data
bcN    long,auto
bcIx   long,auto
bcCol  long,auto
bcLim  long,auto
bcSlk  long,auto
bcCap  long,auto
bcMed  long,auto
bcSrv  long,auto
bcStr  long,auto
bcLow  long,auto
bcAlt  long,auto
bcAst  long,auto ! --acdiag only: rows STRANDED above the column
  code
  bcN = records(wQ)
  if bcN < 1 then exit.
  sort(wQ, wQ.wqW)
  bcCap = acLimit
  if acOutlier > 0 and bcN > 2
    get(wQ, (bcN + 1) / 2)
    bcMed = wQ.wqW + acOutlier
    if bcMed < bcCap then bcCap = bcMed.
  end
  bcCol = 0 ; bcSrv = 0
  loop bcIx = 1 to bcN
    get(wQ, bcIx)
    if wQ.wqW > bcCap then break.
    bcCol = wQ.wqW
    bcSrv = bcIx                                                                     ! how many rows can actually REACH that column
  end
  ! A COLUMN NO ROW BUT THE ONE THAT SET IT CAN REACH IS NOT A COLUMN. The limit is there so ONE
  ! long line cannot push everyone's comments out to meet it. Where the run STRADDLES it - the
  ! bulk past it and one narrow line under it - it does the opposite: the narrow line sets a
  ! column none of the others can reach without landing on their own code, so each keeps its own
  ! end and one column becomes as many columns as there are lines. Four prototypes sharing column
  ! 106, floors 81, 99, 95 and 103, would come back at 83, 99, 95 and 103. So when the cap leaves a column
  ! exactly ONE row can use, it is set aside and the run is measured the way a run ENTIRELY past the
  ! limit already is - the budget from the narrowest - which puts those four in one column at 103.
  ! ONE row, not a minority: the limit is still what stops a long line dragging a block out to meet
  ! it, and a column two rows share is a column.
  if bcCol and bcSrv = 1 and bcN > 2
    bcCol = 0 ; plWhy = 'straddle'
  end
  if ~bcCol                                                                          ! nothing under the limit, or a cap that stranded the bulk: the budget from the narrowest
    bcSlk = self.alignSlack
    if ~bcSlk then bcSlk = 60.
    get(wQ, 1)
    bcLim = wQ.wqW + bcSlk
    bcCol = wQ.wqW
    loop bcIx = 2 to bcN
      get(wQ, bcIx)
      if wQ.wqW > bcLim then break.
      bcCol = wQ.wqW
    end
  end
  plMin = bcCol
  if plWhy <> 'straddle' then plWhy = 'bulk'.
  ! ---- DIAGNOSTIC, --acdiag only. Transforms nothing. What the column decision actually SAW, so
  !      the rule can be derived from the numbers instead of guessed: how many rows voted, the cap
  !      in force, the column chosen, how many rows can REACH that column, and how many are
  !      STRANDED above it and so keep their own end. A run whose stranded rows are most of it is
  !      the shatter the reader sees, and `reach` is what the straddle guard tests - it asks only
  !      whether reach is 1, which is the narrowest case of a general rule.
  if self.acDiag
    bcStr = 0                                                                        ! count them where the answer is final
    loop bcIx = 1 to bcN
      get(wQ, bcIx)
      if wQ.wqW > bcCol then bcStr += 1.
    end
    get(wQ, 1) ; bcLow = wQ.wqW                                                      ! the narrowest floor - what the fallback budgets from
    bcAlt = bcLow ; bcLim = bcLow + choose(self.alignSlack > 0, self.alignSlack, 60)
    loop bcIx = 2 to bcN                                                             ! what the straddle fallback WOULD choose here
      get(wQ, bcIx)
      if wQ.wqW > bcLim then break.
      bcAlt = wQ.wqW
    end
    bcAst = 0
    loop bcIx = 1 to bcN
      get(wQ, bcIx)
      if wQ.wqW > bcAlt then bcAst += 1.
    end
    self.TraceIt('BC run ' & pl & '-' & plEnd & ': rows ' & bcN & ' cap ' & bcCap &  |
                 ' col ' & bcCol & ' reach ' & bcSrv & ' stranded ' & bcStr       &  |
                 ' why ' & plWhy & ' | low ' & bcLow & ' alt ' & bcAlt            &  |
                 ' altstranded ' & bcAst)
  end

! ---- --cmtkeep=aligned: A RUN THAT IS ALREADY IN ONE COLUMN NEEDS NOTHING, SO NOTHING IS
!      DONE TO IT. The aligner exists to put ragged comments in one column; a run whose
!      comments are ALREADY in one column, and whose column still clears every one of them,
!      has nothing wrong with it, and every move from there is damage. Two shapes need it:
!      four prototypes sharing a column their code STRADDLES the limit on, which would come back
!      in four columns because only the narrowest floor is under the limit and the other three
!      cannot reach it; and a statement run whose shared column clears a wide plain line
!      in the middle of it, which would come back tightened to the left of that line.
!
!      TWO OR MORE ROWS, because one row is not aligned with anything, and no BAR in the run,
!      because a bar takes its column from the other bars rather than from the comments and
!      this rule has nothing to say about that.
!
!      IT LOOKS AT WHERE THE COMMENTS ALREADY ARE, which every other arm here refuses to do,
!      because computing the column from the CODE is what makes 2 -> 4 -> 2 come back. So the
!      ratchet is the thing to check, and it does not arise: indent 2 -> 4 -> 2 with this on
!      every leg brings the file back identical, and so does the same round trip with it off.
!      The reason is that a reindent moves a line WHOLE - the comment
!      travels with the code in front of it - so a run that was already in one column is still in
!      one column at the other indent, and the column it is held at tracks the code after all.
!
!      IT IS THE DEFAULT, AND THE SCOPE IT JUDGES OVER IS WHAT MAKES THAT SAFE. Weighed over a whole
!      RUN it could not be a default, for two reasons, both measured: a file would stop
!      round-tripping, because whether a run is already aligned is a property of the INPUT and
!      the input differs between the source and a reindented copy of it (one run held at 44 on one
!      leg and at 42 on the other); and --cmtreach, --cmtfloor=all and --cmtrun would go INERT on
!      any tidily written block, because a rule holding the whole run holds them too.
!      SO EACH GROUP OF NEIGHBOURING COMMENTS IS WEIGHED ON ITS OWN. A ragged comment anywhere in a
!      long block cannot switch the rule off for the tidy groups in it, and a group being held
!      cannot switch every other rule off for the rows outside it. Those switches show only on
!      a RAGGED block, and a reindent round trip run with --cmtkeep=off shows the ALIGNER
!      itself computing its column from the CODE, while this is a REFUSAL layer above it. A
!      second 2 -> 4 -> 2 cycle comes back
!      byte-identical, so the tool settles after one pass and does not drift.
KeepAligned routine
  data
kaX    long,auto
  code
  plKeep = 0
  if ~self.cmtKeep then exit.
  kaGrpS = 0 ; kaLast = 0 ; kaKept = 0 ; kaSeen = 0
  kaCol = 0 ; kaN = 0 ; kaFlr = 0 ; kaOK = 1 ; kaWhole = 0
  loop kaX = pl to plEnd + 1                                   ! one past the end, to settle the last group
    kaEnd = 0
    if kaX > plEnd
      kaEnd = 1
    else
      get(cmtQ, kaX)
      if errorcode() then kaEnd = 1.
    end
    if ~kaEnd
      if CmtQ.opRun then kaEnd = 1.                            ! a bar in the run - the bar rules own it
    end
    if ~kaEnd
      if CmtQ.Pos < 2 then cycle.                              ! no comment on this line - it does not end a group
      if CmtQ.freeze and CmtQ.frzKind <> 2 then cycle.         ! an anchor does not move either way
      if kaLast and kaX - kaLast > self.cmtRun then kaEnd = 1.
    end
    if kaEnd                                                   ! the gap test above already set it
      do KeepBankGroup
      if kaX > plEnd
        kaWhole = 1                                            ! the walk reached the run's end - every row was weighed
        break
      end
      get(cmtQ, kaX)
      if errorcode() then break.
      if CmtQ.opRun then break.                                ! a bar: the walk STOPS here and the rows past it were never weighed
    end
    kaSeen += 1 ; kaN += 1 ; kaLast = kaX
    if ~kaGrpS then kaGrpS = kaX.
    if ~kaCol
      kaCol = CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack
    elsif CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack <> kaCol
      kaOK = 0                                                 ! this GROUP is ragged - the aligner has work to do in it
    end
    if CmtQ.codeEnd + acGap + CmtQ.cmtBack > kaFlr
      kaFlr = CmtQ.codeEnd + acGap + CmtQ.cmtBack
    end
  end
  ! `plKeep` suppresses the apply loop for the WHOLE run, so it may only be set when the walk
  ! actually SAW the whole run. The walk stops at the first `opRun` row - a '|' continuation,
  ! whose column the bar rules own - and `kaSeen` then counts only the rows ABOVE that bar. Without
  ! `kaWhole` a tidy pair of comments followed later in the same procedure by a wrapped statement
  ! would make kaKept = kaSeen vacuously and turn AlignComments OFF for every row past the bar. The
  ! per-row `keepRow` marks are what actually hold a kept group; this flag is only the shortcut for
  ! the case where they cover everything, and a shortcut that fires when the walk stopped early is
  ! not a shortcut - on a default run it would switch the aligner off.
  if kaWhole and kaKept and kaKept = kaSeen then plKeep = 1.

! ---- bank the group that just ended: if its comments already share ONE column and that column
!      still clears every one of their code ends, mark its rows and let nothing move them.
KeepBankGroup routine
  data
kbX  long,auto
kbSv long,auto
  code
  if kaN >= 2 and kaOK and kaCol >= kaFlr
    kbSv = pointer(CmtQ)
    loop kbX = kaGrpS to kaLast
      get(cmtQ, kbX)
      if errorcode() then cycle.
      if CmtQ.Pos < 2 then cycle.
      if CmtQ.freeze and CmtQ.frzKind <> 2 then cycle.
      CmtQ.keepRow = 1
      put(CmtQ)
    end
    kaKept += kaN
    get(cmtQ, kbSv)
  end
  kaGrpS = 0 ; kaCol = 0 ; kaN = 0 ; kaFlr = 0 ; kaOK = 1

! ---- THE REACH: a plain line that touches a commented one lifts the column when it is no more
!      than self.cmtReach (--cmtreach=, 3 as shipped) wider than the column BulkColumn set,
!      never past the limit.
!      So comment rows move by one or two columns, whole
!      blocks at a time; counting a plain line ANYWHERE in the block would move about twice
!      as many, most of them for a line nowhere near them.
PlainReach routine
  data
prN    long,auto
prIx   long,auto
prBase long,auto
  code
  prN = records(pQ)
  if prN < 1 or self.cmtFloor = 1 then exit.         ! --cmtfloor=commented: a plain line never lifts the column
  sort(pQ, pQ.pqW)
  prBase = plMin
  loop prIx = 1 to prN                               ! sorted narrowest first, so the limit ends the walk
    get(pQ, prIx)
    if pQ.pqW > acLimit then break.
    if pQ.pqW > prBase + self.cmtReach
      ! OUT OF REACH, AND THAT SETTLES IT ONLY FOR A LINE AT THE EDGE OF THE RUN. A plain line
      ! lying BETWEEN two commented rows is INSIDE the column those rows share, and a column that
      ! comes left of code in its own run is a stagger, not alignment: a statement run sharing
      ! column 49 would land at 37, left of a line in the middle of it whose code runs to 44. The
      ! reach is there to stop a line NEAR the run voting from too far away, which is still what
      ! it does at the edges. An inner line gets its OWN reach, --cmtinner, and not the limit:
      ! unbounded it would re-column whole blocks at a time across a code base, because a wide
      ! statement between two comments would drag the column out to meet it.
      if ~self.cmtInner then cycle.                  ! --cmtinner=0: the inner rule is off
      if ~pQ.pqX or pQ.pqX >= plLast then cycle.
      if pQ.pqW > prBase + self.cmtInner then cycle. ! inside the run, but too far out even for that
      if pQ.pqW > plMin then plMin = pQ.pqW ; plWhy = 'inner'.
      cycle
    end
    if pQ.pqW > plMin then plMin = pQ.pqW ; plWhy = 'reach'.
  end

! ---- look at what sits just ABOVE the run: a frozen anchor at our own column vetoes the pull,
!      and a block at a DIFFERENT column is what we should be coming back to join. ----
PullLookBack routine
  data
lb  long,auto
sv  long,auto
  code
  sv = pointer(CmtQ)
  plNbr = 0
  loop lb = pl - 1 to 1 by -1
    if pl - lb > self.cmtRun then break.                      ! --cmtrun= is how far up this looks
    get(CmtQ, lb)
    if errorcode() then break.
    if CmtQ.blkStart then break.
                                                              !   cross a block boundary either
    if CmtQ.Pos < 2  or                                       |   ! no comment on that line - keep looking
       CmtQ.hangFrom                                          ! a PASSENGER's column is not settled yet, so it
      cycle
    end
                                                              !   is not the block to land on - keep looking up, and the
                                                              !   next thing found is its own anchor, which IS settled
    ! A DIFFERENT MARKER IS NOT OUR BLOCK, BUT IT IS NOT A WALL EITHER - KEEP LOOKING UP.
    ! A '!' row and a '|' row tighten together: the run walk lets a bar in AND gives it the same
    ! vote as any other member. The concern that a wrapped statement's '|' sits at the end of long
    ! code, and so could RAISE THE FLOOR until the block can barely give any space back, is real -
    ! but it is answered by --cmtlimit, not by withholding the vote: the widest floor UNDER THE
    ! LIMIT sets the column, and a row past the limit simply keeps its own end.
    ! The marker test below is this walk's own and decides only what to LAND on, never membership.
    ! Landing is a different power. Breaking here as well would make a single '|' row a WALL: the
    ! rows below it could not see the column established above it, so one comment continued across
    ! a wrapped condition would come out in three columns - the heading and its first rows on the block's
    ! column, the wrapped row on its own, and every row after it tightened to its own code as
    ! though nothing preceded it. Skipping instead is the same treatment a passenger gets above,
    ! and for the same reason: this row is not the thing to land on, so look past it.
    ! WHY THIS CANNOT TIGHTEN ANYTHING FURTHER LEFT: plNbr is only ever taken when it is GREATER
    ! than the floor already computed, so finding a block that was previously hidden can raise a
    ! run's floor and never lower it. The failure direction is a run that gives back less space
    ! than it might, not one that jams a comment against its code.
    ! The --cmtrun window still bounds the walk, and an opener still stops it.
    if CmtQ.kind <> plKind
      cycle
    end
    if CmtQ.opener                                            ! the line above OPENS a structure, so it is
      break
    end
                                                              !   a header, not the block we should land on. Letting a
                                                              !   CLASS/QUEUE header be the floor candidate lets the
                                                              !   fields under it keep its column though the run
                                                              !   itself does not include it.
    ! THIS is the block above us, and it is where we should land. Tightening a group
    ! to its own narrowest fit is right when it stands alone, but wrong when there is a column
    ! established immediately above it - it leaves the group one or two characters adrift, which
    ! reads worse than not moving at all - two declaration comments landing at 30 while the
    ! eight declarations above them sit at 31.
    ! DO NOT gate this on the neighbour's column differing from plCol, the CURRENT column of
    ! the group's first row: that is the ratchet again, since the group's incoming column must
    ! not decide anything. The row above has already been finalised by this same pass, so its
    ! column is settled and code-determined; take it as a floor candidate and let the max()
    ! above choose. Whether it is an anchor matters only to the diagnostic.
    plNbr = CmtQ.Pos + CmtQ.Adjust + CmtQ.cmtBack
    if CmtQ.freeze then plFroze = 1.
    break
  end
  get(CmtQ, sv)


!==================
VitTokenize.FindNotInLiteralOrComment PROCEDURE  (stringTheory pSt, string pNeedle,long pStartCol, long pNoCase) !,long ! Declare Procedure
! finds pNeedle on the line outside any literal or comment
x        long,auto
inQuotes long
  code
  ! note we assume we have a single line of code.
  x = 1
  loop
    pStartCol = pSt.instring(pNeedle,,pStartCol,,pNoCase)
    if ~pStartCol then return 0.        ! not found
  ! scan along line until we reach pPos
    loop x = x to pStartCol - 1
      if inquotes
        if pSt.valuePtr[x] = ''''       ! endquote
          inquotes = false
        end
      else
        case val(pSt.valuePtr[x])
        of 39                           !val('''') ! startquote
          inquotes = true
        of 33 orof 124                  ! val('!') orof val('|') ! rest of line is a comment
          return 0                      ! not found as rest of line is in a comment
!        of 13 orof 10
!          stop('unexpected line break in VitTokenize.FindNotInLiteralOrComment')
        end
      end
    end
    if ~inQuotes then return pStartCol. ! found and not in quotes or comment
    x = pStartCol                       ! classify the REJECTED byte too: skipping it leaves a quote at
    pStartCol += 1                      !   the match position uncounted and inverts the state
  end
