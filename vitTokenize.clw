! Vitesse Tokenize Class 29Sep2019
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

reservedWords STRING(' ACCEPT AND APPLICATION ASSERT BEGIN BREAK BY CASE CHOOSE CLASS CODE COMPILE CONST CYCLE DATA DO ELSE ELSIF END EXECUTE EXIT'          &|
                     ' FILE FUNCTION GOTO GROUP IF INCLUDE ITEMIZE LOOP MAP MODULE MEMBER MENU MENUBAR NEW NOT NULL OF OMIT OPTION OR OROF PRAGMA PROCEDURE' &|
                     ' QUEUE PROGRAM RECORD RETURN ROUTINE SECTION SHEET TAB THEN TIMES TO TOOLBAR UNTIL WINDOW WHILE XOR '                                  &|
                     ' INTERFACE VIEW JOIN REPORT HEADER FOOTER DETAIL FORM OLE ') ! structures that were missing entirely.
                                                                                 ! A word must be HERE before TokenType's level CASE can
                                                                                 ! ever see it, so both lists have to gain them together.


dataTypes STRING(' LONG STRING CSTRING PSTRING REAL ULONG BYTE SHORT USHORT DATE TIME ULONG DECIMAL PDECIMAL'                                                & |
                 ' SREAL BFLOAT4 BFLOAT8 ANY WINDOW FILE QUEUE SIGNED UNSIGNED VIEW KEY GROUP ')
! ------------------------------------------------------------------------------------
VitTokenize.Construct Procedure()
separators String('<9,32>')
delimiters String('()[]{{}:,.;=')                                                ! note that : is a delimiter in [1:5] or [a:z] but not in a variable name xx::something
operators  String('<<>~+-/*%^&')

x          long,auto
 code
  self.tokens   &= new TokenQType
  self.vars     &= new VarTypeQType
  self.searchQ  &= new searchQType
  self.searchSt &= new StringTheory
  self.lineMap  &= new TokLineMapQType                                           ! preview line map (inert until MapInit arms mapOn)
  self.lineMap2 &= new TokLineMapQType

  clear(self.separatorA)                                                         ! not really needed but initialize all to true
  loop x = 1 to size(separators)
    self.separatorA[val(separators[x])+1] = TRUE
  end

  clear(self.delimiter)                                                          ! not really needed but initialize all to true
  loop x = 1 to size(delimiters)
    self.delimiter[val(delimiters[x])+1] = TRUE
  end

  clear(self.operator)                                                           ! not really needed but initialize all to true
  loop x = 1 to size(operators)
    self.operator[val(operators[x])+1] = TRUE
  end

  self.ignoreOmittedCode = 1                                                     ! honour the declared BYTE(1) default EXPLICITLY.
                                                                                 ! Clarion does NOT apply inline initial values to NEW'd CLASS reference data
                                                                                 ! members, so the .inc 'BYTE(1)' was silently 0 at runtime -> the OMIT state
                                                                                 ! machine (gated on this flag, ParseText ~line 136) never ran, so an
                                                                                 ! unconditional omit('...') block leaked its (non-'!'-prefixed) prose into the
                                                                                 ! token stream, where dotted words (e.g. 'and works...)') desynced the label
                                                                                 ! merge and hit the fatal stop() below. Absorbed OMIT text is preserved on
                                                                                 ! rejoin via strBefore, so this stays byte-lossless. See test.clw omit cases.

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

  free(self.lineMap) ! plain LONG rows - nothing referenced to dispose per-row
  dispose(self.lineMap)
  free(self.lineMap2)
  dispose(self.lineMap2)

! ------------------------------------------------------------------------------------
VitTokenize.ParseText  Procedure(STRING pFileName)
st          StringTheory
 code
  if not st.LoadFile(pFileName)
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
! is the property every gate in this project ultimately rests on.
!
! It does three things at once, which is why it is long: it cuts the text into tokens, it
! classifies each one (type, and later varType), and it marks block structure in level -
! '+' opens, '-' closes, '/' is else/elsif.
!
! THE LEVEL MARKS ARE THE SUBTLE PART, and most tokenizer bugs this project has had were
! really level bugs: something that looked like a structure keyword opened a block nothing
! closed, and the damage surfaced hundreds of lines away. Two rules earn their complexity:
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
omitEol        Long,auto         ! end of the OMIT directive's own line - the terminator search starts AFTER it
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
newQ           &TokenQType       ! colon-merge rebuild target
mergePosQ   QUEUE,PRE(mp)        ! newQ rows whose merged text needs TokenType
row           long
            END
mergedTx    StringTheory         ! merged token text builder
consumedTo  long,auto
lastQx      long,auto
prevType    string(1),auto
currType    string(1)
prevCh      string(1)            ! the PREVIOUS token when it was a single character ('&' ',' etc),
                                 !   which is what tells an attribute or a reference from a declaration
prevStrIx   long                 ! token index of one of the EIGHT new structure keywords.
                                 !   They open only in DECLARATION position - next token ',' '(' or EOL
prevBrkIx   long                 ! token index of a BREAK just seen (0 = none). BREAK is a report
                                 !   STRUCTURE only when a '(' follows; bare BREAK is a statement.
prevLoop    long                 ! previous token was LOOP - so an UNTIL/WHILE here is the loop HEADER
                                 !   (pre-test, still needs an END), not the post-test terminator
parenDep    long                 ! '(' depth within the STATEMENT - a structure keyword inside
                                 !   parentheses is a parameter type or an attribute, never a block
decln       string(vt:maxVarLen) ! declaration
tok         StringTheory
strBefore   StringTheory
tempST      StringTheory
svBefore    StringTheory         ! review C1: the strBefore accumulated up to (and only) the OMIT keyword
!--------
! following are really for GetNextToken but put here for speed
inComment   Long,auto
inQuotes    Long,auto
!startPos    Long,auto
!--------
 code
  self.FreeToks()

!-----------
! self.traceIt = true
!-----------

  st.LineEndings(st:unix)                                                     ! convert CRLF to LF '<10>'
  self.tokens.type = ' '                                                      ! default to space for now
  pos = 1
  state = 0
  loop
    do GetNextToken
    if state = 4 then state = 0.                                              !do NOT move this (state 4 means we finished omit but want to retain 'beforeString' text in GetNextToken)
    case state
    of 0                                                                      ! normal state - not special OMIT processing
      if Tok._DataEnd or strBefore._DataEnd
        do AddToken
        if self.ignoreOmittedCode and tok._DataEnd = 4 and upper(tok.valueptr[1 : 4]) = 'OMIT'
          do OmitIsDirective                                                  ! a METHOD named Omit is not the directive
          if omitDir
            svPos = pos                                                       ! save position
            svBefore.setValue(strBefore) ! review C1: snapshot the pre-OMIT whitespace only; states 1-3 do not free strBefore, so GetNextToken would otherwise leave the interior header ws in it AND the slice below re-captures the same ws -> duplicate
            state = 1
            cycle
          end
        end
      end
      if ~Tok._DataEnd then break.

    of 1                                                                      ! omit looking for (
      if tok._DataEnd = 1 and tok.valuePtr[1] = '('
        state = 2                                                             ! omit looking for literal
      else
        pos = svPos; state = 0                                                ! revert - not simple omit
      end

    of 2                                                                      ! omit looking for literal
      if tok._dataEnd > 2 and tok.startsWith('''') and tok.endsWith('''')
        tempST.setvalue(tok)
        tempST.unquote('''')                                                  ! store the string we will search for end of OMIT
        state = 3
      else
        pos = svPos; state = 0                                                ! revert - not simple omit
      end

    of 3                                                                      ! omit looking for ')'
      if tok._DataEnd = 1 and tok.valuePtr[1] = ')'
        ! the terminator search starts on the NEXT line, never on the rest of the OMIT
        ! line itself. Starting it here found a terminator sitting in a trailing COMMENT on
        ! the directive line - `OMIT('**end**')  ! runs to **end**` - and closed the block
        ! before it had begun, leaving everything that should have been omitted live. The
        ! compiler ends the block at a SUBSEQUENT line holding the terminator.
        omitEol = st.findByte(10, pos)                                        ! end of the OMIT directive's own line
        if omitEol
          pos = st.findChars(tempST.valuePtr[1 : tempST._dataEnd],omitEol + 1)
        else
          pos = 0                                                             ! OMIT on the last line: nothing can terminate it
        end
        if pos
          ! search to end of line
          pos = st.findByte(10, pos)                                          ! <line feed>
          if pos
            self.deleteTok(records(self.tokens))                              ! delete OMIT from token queue
            tempST.setValue(st.slice(svPos-4,pos))
            tempST.replace('<10>','<13,10>')
            strBefore.setValue(svBefore) ! review C1: keep only the pre-OMIT ws; the slice already holds the whole OMIT block (incl. interior ws), so appending it once avoids the duplicate
            strBefore.append(tempST)                                          ! we append all the chars in the omit to the "before" string
            state = 4                                                         ! finished with omit but want to preserve 'before' text when getting next token
            pos += 1
            cycle
          else
            ! end of file found - no further lines
            pos = st._dataEnd + 1
            self.deleteTok(records(self.tokens))                              ! delete OMIT from token queue
            tempST.setValue(st.slice(svPos-4))                                ! slice to EOF
            tempST.replace('<10>','<13,10>')
            strBefore.setValue(svBefore)                                      ! review C1: keep only the pre-OMIT ws (see above); slice holds the whole block
            strBefore.append(tempST)                                          ! we append all the chars in the omit to the "before" string
            tok.free()
            do AddToken
            break                                                             ! EOF
          end
        else
          pos = svPos                                                         ! revert - not simple omit
        end
      else
        pos = svPos                                                           ! revert - not simple omit
      end
      state = 0
    else
      self.TraceIt('unexpected state ' & state & ' in VitTokenize.ParseText') ! should never happen...
    end                                                                       ! case
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
        colonCount = 1                                                                    ! run of adjacent ':' tokens starting at x
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
        consumedTo = x + colonCount - 1                          ! default: prev & ':'xN (token ends with colon)
        tempST.free()
        if ~errorcode() and x + colonCount <= records(self.tokens)
          if not self.tokens.tok &= NULL and self.tokens.strBefore &= NULL
            tempST.setValue(self.tokens.tok)                     ! next token's text - merge it too
            consumedTo = x + colonCount
          end
        end
        lastQx = records(newQ)
        get(newQ, lastQx)
        mergedTx.setValue(newQ.tok)
        mergedTx.append(all(':', colonCount))
        if tempST._DataEnd then mergedTx.append(tempST).         ! prev & ':'xN & next
        dispose(newQ.tok)
        newQ.tok &= new STRING(mergedTx._DataEnd)
        newQ.tok  = mergedTx.getValue()
        put(newQ)
        mp:row = lastQx                                          ! retype after the swap (SetTok parity)
        add(mergePosQ)
        loop z = x to consumedTo                                 ! consumed records: text already copied - dispose their strings
          get(self.tokens, z)
          if errorcode() then break.
          dispose(self.tokens.tok)
          dispose(self.tokens.strBefore)
        end
        x = consumedTo
        cycle
      end
    end
    get(self.tokens, x)                                          ! re-load (the run lookahead moved the buffer)
    if errorcode() then break.
    ! EVERY QUEUE HAS ITS OWN RECORD BUFFER: get() filled self.tokens' buffer, but add(newQ)
    ! appends newQ's buffer - copy field-by-field first (same TYPE; references copy as pointers).
    ! Without this the rebuild appended newQ's STALE buffer: garbage records, duplicated &STRING
    ! pointers, and a double-dispose GPF in FreeToks (the round-1 crash).
    newQ.lineNo      = self.tokens.lineNo
    newQ.firstOnLine = self.tokens.firstOnLine
    newQ.strBefore  &= self.tokens.strBefore
    newQ.tok        &= self.tokens.tok
    newQ.type        = self.tokens.type
    newQ.varType     = self.tokens.varType
    newQ.level       = self.tokens.level
    add(newQ)                                                    ! transfer the record (pointers move with it)
  end
  free(self.tokens)                                              ! plain free: never disposes the transferred &STRINGs
  dispose(self.tokens)
  self.tokens &= newQ
  loop z = 1 to records(mergePosQ)                               ! retype the merged tokens (what SetTok's TokenType call did)
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
      case val(self.getTok(x-1))                                 ! val() reads the FIRST BYTE, which is safe in THIS position:
                                                                 !   '(' and ',' are delimiters and always stand alone, and the
                                                                 !   '<<' tested for is the omittable-parameter marker that opens
                                                                 !   a prototype argument. No multi-character token that could
                                                                 !   appear immediately before a '*TYPE' starts with one of them.
                                                                 !   (This comment used to say "do NOT use val() here" - on the
                                                                 !   line that does; the code is right, the warning was not.)
      of 40 orof 44 orof 60                                      ! '(' orof <comma> orof '<<'
        self.getTok(x+1,StrBefore,Tok)
        if tok._DataEnd and ~strBefore._DataEnd                  ! no spaces between
          self.SetTok(x,'*' & tok.valueptr[1 : tok._DataEnd])    ! combine with following token
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
          self.setTok(x,':=:')                                   ! combine three tokens
          self.DeleteTok(x+2)
          self.DeleteTok(x+1)
        end
      end
    end
  end

  ! check for decimal points in numbers eg. 123.45
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break.        ! no more tokens

    prevType = currType
    currType = ' '
    if size(self.Tokens.tok) = 1 and self.Tokens.tok = '.'
      if self.Tokens.strBefore &= NULL and prevType = vt:Integer ! eg 123.
        self.Tokens.Type = vt:decPoint                           ! d = decimal point
        currType = vt:decPoint                                   ! d =decimal point
        put(self.tokens)
      end
      cycle
    end

    if self.Tokens.Type = vt:Integer or self.Tokens.Type = 'N'   ! integer, or an exponent tail like 5e3
      currType = self.Tokens.Type
      if prevType = vt:decPoint and self.Tokens.strBefore &= NULL
        ! combine three tokens 123|.|45 into one token 123.45
        self.SetTok(x-2,self.getTok(x-2) & '.' & self.getTok(x)) ! combine three tokens into one
        self.tokens.type = 'N'                                   ! numeric with dec point
        put(self.tokens)
        self.DeleteTok(x)
        self.DeleteTok(x-1)
        x -= 2
      end
    end
  end                                                            !loop

  ! check if we can merge labels  eg.  x.y.getvalue() then combine x.y
  state = 0
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break.        ! no more tokens
    case state
    of 0                                                         ! looking for label
      if self.tokens.type = vt:label
        state = 1
      end
    of 1                                                         ! have label looking for dot
      ! A SPACE BEFORE THE MEMBER DOT IS LEGAL CLARION AND THE NAME MERGES ACROSS IT.
      ! `x.y .getvalue()` is one member reference written with a gap. Requiring NO leading
      ! trivia on the dot meant the merge gave up and handed the reference back as THREE
      ! tokens, and every consumer that reads a member as one token was then looking at
      ! something it did not recognise. Nine of them answer "cannot prove" and leave the code
      ! alone, which is safe by accident rather than by design; the tenth silently deleted
      ! a load-bearing guard. Merging here fixes the whole class at the source instead
      ! of one consumer at a time.
      ! THE GAP IS DROPPED. The merge builds its text from the two label
      ! texts and a literal '.', so the dot's trivia was never carried anyway - it is disposed
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
      ! clip the space straight out of it, and no plain-space gap would ever merge again.
      if self.tokens.tok = '.'
        mergeGap = choose(self.tokens.strBefore &= NULL or |
                          ~self.tokens.strBefore        or |
                          tempST.IsAll('<32,9>', self.tokens.strBefore, false))
      else
        mergeGap = 0
      end
      if mergeGap
        state = 2
      else
        state = 0
      end
    of 2                                                           ! have label. looking for another label
      if self.tokens.strBefore &= NULL and self.tokens.type = vt:label
        state = 3
      else
        state = 0
      end
    of 3                                                           ! have label.label
      !if pMergeLabels !or self.tokens.tok <> '('  !!NB. GCR 13Oct2021 removed 'or condition' as joined ST._dataEnd into one token (not sure if this will muck up something else??)
      if pMergeLabels or self.tokens.tok <> '('                    !!NB. GCR 13Oct2021 REINSTATED 'or condition' as mucked up variable checking in NetMaps.clw
        ! combine labels
        self.SetTok(x-3,self.getTok(x-3) & '.' & self.getTok(x-1)) ! combine three tokens into one
        if self.tokens.type <> vt:label
          if self.stopIt
            self.TraceIt('expected label but got type [' & self.tokens.type & ']' & |
               '<13,10>Token No: ' & pointer(self.tokens)                         & |
               '<13,10>Line No: ' & self.tokens.LineNo                            & |
               '<13,10>Tok: [' & choose(~self.tokens.tok &= Null,self.tokens.tok,'') & ']')
          end
        end
        self.DeleteTok(x-1)
        self.DeleteTok(x-2)
        x -= 3                                            ! go back to label
        state = 1
      else
        state = 0
      end
    end
  end                                                     !loop

!  self.SetLineNumbers()

  ! check for END statements including dots '.'
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break. ! no more tokens

    prevType = currType
    currType = ' '

    ! A STRUCTURE KEYWORD CANNOT OPEN A BLOCK INSIDE PARENTHESES. TokenType marks
    ! QUEUE / GROUP / FILE / RECORD / CLASS / MODULE and the rest with level '+' on the word
    ! alone, but at paren depth > 0 the same word is a parameter TYPE or an attribute:
    !     Trace           PROCEDURE(Queue pQueue), virtual        <- a TYPE
    !     SerializeGroup  PROCEDURE(*Group pGroup, ...)           <- a TYPE
    ! StringTheory.inc line 594 is the first form, and it opened a level that never closed:
    ! its '-' was taken by the enclosing StringTheory CLASS's END, so the CLASS ran to EOF
    ! unmatched and every expanded stream that includes StringTheory came out one level
    ! short. --dumptokens found it - exactly ONE offending token in the whole closure.
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
    ! worse failure than the one being fixed. Bounding it to one statement is the point.
    if size(self.Tokens.tok) = 1 and (val(self.Tokens.tok) = 10 or val(self.Tokens.tok) = 59)
      parenDep = 0                                        ! EOL or ';' - parens cannot span a statement
    elsif self.Tokens.tok = '('
      parenDep += 1
    elsif self.Tokens.tok = ')'
      if parenDep then parenDep -= 1.
    elsif parenDep > 0 and self.Tokens.Level = '+'
      self.Tokens.Level = ' '                             ! a type or an attribute - it opens nothing.
      put(self.tokens)                                    ! RETAINED, but NOT for the declaration
    end                                                   !   structures - the guard at the promotion below excludes
                                                          !   parenDep already. What is left for this to catch is the
                                                          !   SIX unconditional openers (IF/CASE/LOOP/EXECUTE/BEGIN/
                                                          !   ACCEPT) and anything added to that CASE later, so it
                                                          !   stays as a backstop rather than being deleted with the
                                                          !   other two.
                                                          !
                                                          ! the `prevAmp` demotion that stood here is GONE.
                                                          !   It demoted `grp &GROUP` (a REFERENCE type, which declares
                                                          !   nothing and has no END). a later round took the declaration
                                                          !   structures OFF the unconditional level CASE and put
                                                          !   `prevCh <<> '&'` into the promotion guard at :558, so the
                                                          !   word never reaches level '+' for this to demote. It read
                                                          !   as load-bearing - it cited StringTheory.clw:6124 - and it
                                                          !   had not been able to fire ever since.

    ! THE POST-TESTED LOOP. Clarion writes a loop two ways -
    !     LOOP UNTIL cond      pre-test:  UNTIL is part of the HEADER, an END still closes it
    !     loop                 post-test: UNTIL is the terminator, and there is NO END
    !       ...
    !     until cond
    ! Neither UNTIL nor WHILE carried a level mark, so the post-test form left its LOOP
    ! open forever - two of StringTheory.clw's four unmatched opens (source 10802, 12057).
    ! The two forms differ by ONE token: in the pre-test the word FOLLOWS LOOP directly; in
    ! the post-test it starts its own statement, so the token before it is an EOL. That is
    ! the same lookback as the ',' and '&' tests above, which is why this is here and not in
    ! a round of its own - I said it needed more care than it does.
    ! LEVEL ONLY, deliberately not type vt:end: a good deal of code tests for an END token
    ! by TYPE, and an UNTIL is not an END - it just closes the same structure.
    ! `prevCh <<> '.'` only.
    ! THE RULE ITSELF IS CORRECT AND MUST STAY. Clarion has two LOOP forms:
    !     LOOP UNTIL x      pre-test  - the loop still needs an END
    !     LOOP ... UNTIL x  post-test - the UNTIL *IS* the terminator, there is no END
    ! `~prevLoop` is what tells them apart, and in the post-test form the '-' is exactly
    ! right - the loop really does close here. Nothing about that changes.
    ! What the guard adds is the ONE case where the word is neither: a method call such as
    ! `q.until('x')`, where a '-' would close a structure that was never opened and steal a
    ! real END. The legitimate post-test form is untouched, because the token before UNTIL
    ! there is the EOL, and prevCh holds the EOL's own character (a single LF), not '.'.
    ! No StringTheory method is called `until` or `while` today, so unlike join and break
    ! this one is prevention rather than an observed failure - said plainly so nobody later
    ! reads it as evidenced.
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
    ! Both forms are in booki274.clw (a real-world corpus file, NOT SHIPPED): the structure at 76 with its END at
    ! 102, bare statements at 253, 256, 347, 349, 354, 360, 369 and inline ones at 274, 309.
    ! Leaving it out is NOT a harmless under-reach: with BREAK not opening, the END at 102
    ! closes the REPORT instead, and the FOOTER, FORM and final END after it all mis-nest.
    if prevBrkIx and size(self.Tokens.tok) = 1 and self.Tokens.tok = '('
      get(self.tokens, prevBrkIx)
      self.Tokens.Level = '+'
      put(self.tokens)
      get(self.tokens, x)                                 ! restore the buffer the loop is working on
    end
    ! BREAK carried NO declaration-position guard, so
    ! `st.break('x')` promoted exactly like `st.join(` did - it is in the census above as
    ! `+r 1188-break`. Same four conditions as the guard below.
    if upper(self.Tokens.tok) = 'BREAK' and ~parenDep and prevCh <> '&' and prevCh <> ',' and prevCh <> '.'
      prevBrkIx = x
    else
      prevBrkIx = 0
    end

    ! THE EIGHT NEW STRUCTURES OPEN ONLY IN DECLARATION POSITION.
    ! put INTERFACE VIEW JOIN REPORT HEADER FOOTER DETAIL FORM straight into the level
    ! CASE, which marked them EVERYWHERE the word appeared. booki274.clw (corpus, NOT SHIPPED) showed the cost:
    !     Report               REPORT,AT(...)          the structure
    !     Report{PROP:FlushPreview} = True             the SAME NAME, used as an identifier
    ! and the second opened a block that never closed. `Report` is the Clarion template's
    ! default name for a report, so this would hit almost any real one. Uses inside
    ! parentheses - SetTarget(Report), Close(Report) - were already saved by the paren rule;
    ! the property-syntax one was not.
    ! A DECLARATION is followed by ',' (attributes), '(' (a parent class or a FILE), or the
    ! end of the line. An identifier use is followed by '{', '=', an operator, a ')'. So
    ! these eight are OFF the level CASE and promoted here, once the NEXT token says which
    ! it is - the same shape as the BREAK rule above, and for the same reason.
    ! The PRE-EXISTING declaration structures go through this SAME test now - WINDOW
    ! APPLICATION QUEUE GROUP FILE RECORD CLASS ITEMIZE MENUBAR MENU TOOLBAR SHEET TAB
    ! OPTION MODULE are listed in the CASE below beside the eight. They were left alone
    ! when this was first written; they carry the IDENTICAL exposure, because
    ! Window and Report are the Clarion template's own default LABELS, so a line like
    ! Window{PROP:Text} = 'x' was opening a block that nothing ever closed. That is why
    ! they moved out of the unconditional-open CASE in the level marker.
    if prevStrIx
      if self.Tokens.tok = ',' or self.Tokens.tok = '(' |
         or (size(self.Tokens.tok) = 1 and val(self.Tokens.tok) = 10)
        get(self.tokens, prevStrIx)
        self.Tokens.Level = '+'
        put(self.tokens)
        get(self.tokens, x)                                                        ! restore the buffer the loop is on
      end
    end
    ! The three DEMOTION rules above (paren depth, '&', and the MODULE-after-comma) all
    ! test for level '+', so now that these keywords default to BLANK they never fire for
    ! them. Their conditions have to be applied HERE instead, as a guard on the promotion:
    !   parenDep    `PROCEDURE(Queue pQueue)` - a parameter TYPE
    !   prevCh '&'  `grp &GROUP`              - a REFERENCE type
    !   prevCh ','  `CLASS,TYPE,MODULE('x')`  - an ATTRIBUTE. Without this the MODULE would
    !               be promoted by the '(' that follows it, undoing the demotion completely.
    !   prevCh '.'  `st.join('x')`             - a METHOD CALL. and
    !               PROVED not argued: TestData\r108join.clw gave `exptk level census +22 -13
    !               [UNBALANCED]` with the dump naming nine promoted method names -
    !               join, join, record, group, queue, file, option, menu, break - and two more
    !               (`queue`, `group`) inside StringTheory.clw itself under --thorough. Every
    !               one of these words is BOTH a Clarion structure and a StringTheory method,
    !               so `st.queue()` opened a level that nothing ever closed and every scope
    !               below it was one level too deep - which makes VitEngine's balance guards
    !               refuse and pollutes the type registry. Silent missed transforms.
    !               The third join in that fixture, `q.setValue(st.join(','))`, was NOT
    !               promoted - parenDep already caught it. That is the existing guard working,
    !               and it is why this is one more exclusion rather than a redesign.
    !               NOTE for later: the review argues the real rule is POSITIVE - a declaration
    !               keyword only ever appears at token index 1 or 2 of a statement, and
    !               parenDep already resets at every statement boundary so a sibling counter
    !               would state that directly and close the whole class. That is the better
    !               shape; this is the fix that is proven against the evidence in hand.
    prevStrIx = 0
    if self.Tokens.Type = vt:reservedWord and ~parenDep and prevCh <> '&' and prevCh <> ',' and prevCh <> '.'
      case upper(self.Tokens.tok)
      of   'INTERFACE' orof 'VIEW'        orof 'JOIN'    orof 'REPORT'             ! the eight added later
      orof 'HEADER'    orof 'FOOTER'      orof 'DETAIL'  orof 'FORM'
      orof 'OLE'                                                                   ! see the census note below
      orof 'WINDOW'    orof 'APPLICATION' orof 'QUEUE'   orof 'GROUP'              ! and the PRE-EXISTING
      orof 'FILE'      orof 'RECORD'      orof 'CLASS'   orof 'ITEMIZE'            !   declaration structures, which
      orof 'MENUBAR'   orof 'MENU'        orof 'TOOLBAR' orof 'SHEET'   orof 'TAB' !   have the identical exposure
      orof 'OPTION'    orof 'MODULE'
        prevStrIx = x
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
    ! `Window{PROP:Text} = 'x'` carries exactly the same hazard as `Report` - and WINDOW is one
    ! of the ORIGINAL keywords, not one of the later additions. The origin of a keyword says
    ! nothing about the risk; treating the two sets differently would fix the rarer case and
    ! leave the commoner one.
    !
    ! THE CODE STRUCTURES ARE EXCLUDED ON PURPOSE, and this is what makes the rule safe:
    !     IF ~p          CASE EVENT()        LOOP i = 1 TO 3        EXECUTE n
    ! each is followed by an EXPRESSION, never by ',' '(' or EOL, so requiring declaration
    ! position would stop them opening at all and unbalance every procedure in existence.
    ! Only DATA and CONTROL structures take the test - they are the ones always followed by
    ! attributes, a parent/file in parentheses, or nothing.
    ! ACCEPT, BEGIN and MAP are also left out: they are followed by EOL anyway, so the test
    ! would pass trivially and there is nothing to gain by widening the blast radius.

    ! MODULE is BOTH a structure and an ATTRIBUTE, and TokenType (which sees one
    ! token at a time) gave it level '+' unconditionally. So a perfectly ordinary
    !     sigTool  CLASS,TYPE,MODULE('sigtool.clw')   ... END
    ! opened TWO levels and closed ONE. Everything below it was swallowed into a runaway
    ! block: the fixture reported `symtab 1 scope(s), 0 symbol(s)` for a file with
    ! fifteen procedure bodies, and every analysis that keys on scope silently did nothing.
    ! Inside a MAP a MODULE structure always STARTS a statement; as an attribute it always
    ! follows a comma. That is the whole distinction, and it needs the previous token, which
    ! is why the demotion lives here in the walk rather than in TokenType.
    prevCh = choose(size(self.Tokens.tok) = 1, self.Tokens.tok, ' ')               ! for the NEXT iteration

    ! the MODULE-attribute demotion that stood here is GONE, and so are
    ! prevComma/thisComma. It demoted the MODULE in `CLASS,TYPE,MODULE('x')`. a later round put
    ! `prevCh <<> ','` into the promotion guard at :558 - the comment there names this exact
    ! case - so MODULE-after-comma is never promoted and there is nothing left to demote.
    ! The behaviour is preserved by the guard, not by this block.

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
    end

    if prevType <> vt:dot then cycle.

    if (not self.Tokens.strBefore &= NULL) ! there is ws after the dot
      prevIsEnd = TRUE
    else
      if size(self.tokens.tok) = 1
        case val(self.Tokens.tok)
        of 46 orof 59 orof 10              ! '.' orof ';'
          prevIsEnd = TRUE
        else
          prevIsEnd = false
        end
      else
        prevIsEnd = false
      end
    end

    if prevIsEnd
      get(self.tokens,x-1)                 ! do NOT use setTok here as it will set type
      self.Tokens.Type = vt:end
      self.Tokens.Level = '-'
      put(self.tokens)
    end
  end                                      !loop

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
    if self.Tokens.firstOnLine and self.tokens.strBefore &= NULL and self.tokens.type = vt:label
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
        self.tokens.varType = vt:Key ! was vt:Like - a copy/paste, and vt:Key was declared but never assigned
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
        self.tokens.varType = '?'                                     ! generally a class other than StringTheory
      end
      put(self.tokens)
      self.Vars.varName = upper(self.tokens.tok)
      get(self.vars,+self.vars.varName)
      if errorcode()
        self.vars.varTypes = self.tokens.varType                      ! note this will take one char and clear the rest
        add(self.vars,+self.vars.varName)
        cycle
      end
      if self.vars.varTypes = self.tokens.varType then cycle.         ! already there with same type
      z = instring(self.tokens.varType, self.vars.varTypes,1,1)       ! do we already have one like this?
      case z
      of 0
        self.vars.varTypes = self.tokens.varType & self.vars.varTypes ! put new type in position 1
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
      if self.tokens.tok <> '&' then decln = self.tokens.tok.         ! do not include '&' on reference vars
    end
  end
  self.traceIt = false

  self.CheckLevels()                                                  ! check levels do not go negative



! ---- IS THIS `OMIT` THE DIRECTIVE, OR A METHOD THAT SPELLS IT? -------------------------------
! The machine above fires on any four-character token reading OMIT and then wants '(' , a
! literal, ')'. A METHOD CALL is exactly that shape - `x.Omit('**zz**')` - and the tokenizer
! leaves a method's dot as its own token, because the label merge is suppressed before a '('.
! So the call entered the machine, and it COMMITTED whenever that literal's text appeared again
! anywhere later in the file: everything between was swallowed into leading trivia as omitted
! code. Not a missed conversion - the statements in the gap never became tokens at all, so every
! pass after it reasoned about a file with a hole in it, and nothing said a word.
! MEASURED, both ways, on the same file with only the method's NAME changed: `x.Omit(...)` gave
! 0 changes with the following statement gone; `x.Skip(...)` gave 1 with it intact.
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
  self.TokenType()                               ! sets self.tokens.type
  Add(self.Tokens)
!? assert(~errorcode())


GetNextToken routine
! find next token - we treat space/tab as whitespace - pos has position and we return token and advance pos to next unconsumed char

! self.TraceIt('entering GetNextToken at position ' & pos & ' ' & self.DescribeChar(St.sub(pos)) & ' Continuation='&inContinuation)
  tok.free()
  if ~state then strBefore.free().               ! we do NOT free if in OMIT
  inComment = false
  inQuotes = false
!  startPos = pos

  loop pos = pos to st._DataEnd                  ! skip of initial spaces and tabs
    case val(st.valueptr[pos])
    of 32  orof 9                                ! space or tab
      strBefore.append(st.valueptr[pos])
    of 124                                       ! '|'
      strBefore.append(st.valueptr[pos])
      inContinuation = true
    else
      if ~inContinuation then break.
      ! in continuation so just treat as comment until new line
      if st.valuePtr[pos] = '<10>'               ! EOL - end of line
        strBefore.append('<13,10>')              ! with continuation we store CRLF as part of the "before token" string
        inContinuation = false
        inPicture      = 0                       ! the other place a newline is consumed - a picture dies at one either way
        picEsc         = 0
      else
        strBefore.append(st.valueptr[pos])
      end
    end
  end

  loop pos = pos to st._DataEnd
!?   self.TraceIt('at pos ' & pos & ' ' & self.DescribeChar(st.valuePtr[pos]) )
    if st.valuePtr[pos] = '<10>'                 ! EOL - end of line
      inPicture = 0                              ! a picture never spans a physical line, so an unclosed one dies here
      picEsc    = 0
      if ~tok._DataEnd
        tok.setvalue('<10>')
        pos += 1
      end
      break
    elsif inComment
      strBefore.append(st.valueptr[pos])
    elsif inquotes
      if st.valuePtr[pos] = ''''                 ! endquote
        inquotes = false
      end
      tok.append(St.valuePtr[pos])
    elsif st.valuePtr[pos] = '|' and ~inPicture  ! continuation ('|' inside @K is the documented "stop here" indicator)
      if ~tok._DataEnd
        tok.setvalue('|')
        pos += 1
      end
      inContinuation = true
      break
    elsif st.valuePtr[pos] = '!' and ~inPicture
      if tok._DataEnd
        break                                    ! end of token
      else
        inComment = true
        strBefore.append(st.valueptr[pos])
      end
    elsif st.valuePtr[pos] = '''' and ~inPicture ! startquote (a quote inside @P is an edit char - LRM p157's own example)
      inquotes = true
      tok.append(st.valuePtr[pos])
    elsif self.SeparatorA[val(st.valuePtr[pos])+1]
      if ~tok._DataEnd
        if self.stopIt
          self.TraceIt('error in vitTokenize.parseText - unexpected white space at position' & pos & |             ! The 'cycle'
             choose(~omitted(pFilename),' in ' & clip(pFilename),'')                               & |             ! already recovers by skipping the char, so this was
             '<13,10,13,10>character is [' & st.valuePtr[pos] &'] in:<13,10,13,10>' & self.GetCurrentLine(st,pos)) ! only a debug assertion.
        end
        cycle                                                                                                      ! skip initial whitespace - should NOT happen as skipped ws at top
      else
        break
      end
    elsif self.Delimiter[val(st.valuePtr[pos])+1]
      if ~tok._DataEnd
        tok.append(st.valuePtr[pos])
        pos += 1
        ! `=<` and `=>` are DOCUMENTED spellings of `<=` and `>=` (LRM p528's combined
        ! operator table lists both pairs). '=' is a delimiter, not an operator, so it never
        ! reached the two-character merge below and those two came out as two tokens.
        if st.valuePtr[pos-1] = '=' and pos <= st._DataEnd
          if st.valuePtr[pos] = '<<' or st.valuePtr[pos] = '>'
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
          if st.valuePtr[pos] = '=' or |                                      ! two-char operators: '+=' '~=' '<<=' '>=' ...
             (st.valuePtr[pos-1] = '<<' and st.valuePtr[pos] = '>') or |       ! '<<>'
             (st.valuePtr[pos-1] = '~'                             and |                                   ! '~<' and '~>' are documented
              (st.valuePtr[pos] = '<<' or st.valuePtr[pos] = '>')) !   spellings of "not less" / "not greater"
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
      picClose  = tok.valuePtr[2] ! same case as the opener - the LRM requires the pair to match
      picEsc    = 0
    end
  elsif picEsc
    picEsc = 0                    ! this char was escaped by '\' - never the closing delimiter
  elsif st.valuePtr[pos] = '\' and upper(picClose) = 'K'
    picEsc = 1                    ! @K only: the NEXT character is a display character
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
! following written late on 13Sep2023 but not used or tested - left as may be of future use
!VitTokenize.FindLastTokOnLine Procedure(LONG pLineNumber) !,LONG,virtual ! returns tokNumber GCR 13Sep2023
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
ln     long(1)                                                                                       ! line number
prevLn long
slnX   long,auto                     !
  code
  if self.mapOn then self.MapFold().                                                                 ! compose the preview line map BEFORE the restamp erases the old coordinates
  ! set line numbers in the queue - we check for <10> token and also in strBefore
  loop x = 1 to records(self.tokens)
    get(self.tokens,x)
    if errorcode() then break. !or self.Tokens.tok &= NULL then break.  ! no more tokens !!! GCR 23Sep2023 remove check for null tok as can have null tok on last line (had a file with just a few spaces on last line)
    if not self.Tokens.strBefore &= NULL
      loop slnX = 1 to size(self.Tokens.strBefore)                                                   ! count LF bytes directly - the old ST setValue+count allocated per token on a hot post-edit pass
        if val(self.Tokens.strBefore[slnX]) = 10 then ln += 1.
      end
    end
    self.Tokens.lineNo = ln
    if ln <> prevLn
      prevLn = ln
      self.tokens.firstOnLine = true
      if self.Tokens.type = vt:reservedWord and self.Tokens.strBefore &= NULL then self.TokenType(). ! cannot be a reserved word in col 1
    else
      self.tokens.firstOnLine = false
    end
    put(self.Tokens)
    if size(self.tokens.tok) = 1 and val(self.Tokens.tok) = 10 then ln += 1.
  end

! ------------------------------------------------------------------------------------
! (S4 preview LINE MAP). lineMap holds, for every line of the text as of the
! LAST lineNo stamp, the ORIGINAL source line it descends from. MapInit sizes it as
! identity from the current stream; MapFold composes it across an edit round: after
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
        if val(self.Tokens.strBefore[slnX]) = 10 then ln += 1.
      end
    end
    if size(self.tokens.tok) = 1 and val(self.Tokens.tok) = 10 then ln += 1.
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
ln      long(1)                      ! new-structure line of the token in hand
mapped  long                         ! last new line already given a map entry
lastOld long(1)                      ! monotone floor for old lineNo readings
oldLn   long,auto
j       long,auto
oj      long,auto
nOld    long,auto
lk      long,auto                    ! survivor lookahead cursor
brk     long,auto                    ! lookahead hit the next line's strBefore LF
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
        if val(self.Tokens.strBefore[slnX]) = 10 then ln += 1.
      end
    end
    if ln > mapped                                                               ! first token to land on new line ln
      oldLn = self.Tokens.lineNo
      if oldLn < lastOld                                                         ! zero/stale line HEAD. InsertString clears lineNo, so a rule
        oldLn = 0                                                                ! whose match STARTS the line (rule 543 `if s = '' ==> if ~s`) left
        lk = x                                                                   ! head tokens with lineNo 0 at fold time and the line mapped to its
        loop                                                                     ! PREDECESSOR (the demo lhs6/lhs7 -> rhs5 field bug). The unreplaced
          get(self.tokens, lk)                                                   ! tail / EOL token still carries the TRUE old line - find a SURVIVOR
          if errorcode() then break.                                             ! on the SAME new line before falling back to the carry.
          if lk > x and not self.Tokens.strBefore &= NULL
            brk = 0                                                              ! a later token whose strBefore holds an LF starts the NEXT line
            loop slnX2 = 1 to size(self.Tokens.strBefore)
              if val(self.Tokens.strBefore[slnX2]) = 10 then brk = 1 ; break.
            end
            if brk then break.
          end
          if self.Tokens.lineNo >= lastOld
            oldLn = self.Tokens.lineNo                                           ! survivor found (the EOL token always survives an in-line rewrite)
            break
          end
          if size(self.tokens.tok) = 1 and val(self.Tokens.tok) = 10 then break. ! line closed - no survivor
          lk += 1
        end
        if ~oldLn then oldLn = lastOld.                                          ! fully-inserted line (multi-line replacement): carry
        get(self.tokens, x)                                                      ! restore the walk's queue buffer
      end
      if oldLn > nOld then oldLn = nOld.
      loop j = mapped + 1 to ln                                                  ! entries for this token's line + any strBefore interior lines
        oj = oldLn - (ln - j)                                                    ! interior (comment/blank) lines sit just above their carrier
        if oj < lastOld then oj = lastOld.
        get(self.lineMap, oj)
        if errorcode() then break.
        self.lineMap2.srcLn = self.lineMap.srcLn
        add(self.lineMap2)
      end
      mapped  = ln
      lastOld = oldLn
    end
    if size(self.tokens.tok) = 1 and val(self.Tokens.tok) = 10 then ln += 1.
  end
  loop j = mapped + 1 to ln ! trailing line(s) after the last token (text ending in an LF)
    get(self.lineMap, nOld)
    if errorcode() then break.
    self.lineMap2.srcLn = self.lineMap.srcLn
    add(self.lineMap2)
  end
  free(self.lineMap)        ! lineMap <- lineMap2
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
VitTokenize.CheckLevels Procedure                          ! check levels do not go negative: a '-' needs to match an earlier '+'
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
    of 48 to 57                                           ! 0 to 9
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
  of   65 to 90            ! A-Z
  orof 97 to 122           ! a-z
  orof 95                  ! '_'
    ! first char OK
  else
    return FALSE           ! first character invalid
  end

  ! characters 2 to end can also have digit or colon
  loop x = 2 to size(self.tokens.tok)
    case val(self.tokens.tok[x])
    of   48 to 57          ! 0 to 9
    orof 65 to 90          ! A-Z
    orof 97 to 122         ! a-z
    orof 58        orof 95 ! ':' orof '_'
      !cycle
    of   46                ! '.'
      if x = size(self.tokens.tok)
        return FALSE       ! dot on end not allowed but allow compound x.y.z
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
  if self.Tokens.firstOnLine and self.tokens.strBefore &= NULL
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
haveExp     long                                      ! an E/e exponent has been seen...
expDigit    long                                      !        ...and at least one digit followed it
 code

  ! reset level BEFORE the single-character CASE below, not after it.
  ! Every token shares one queue record buffer, and the single-char arms RETURN early - so a
  ! '+ - * / %% ^ .' token would otherwise INHERIT the previous token's level mark - the '-'
  ! of `return -1` picking up level 'x' from the RETURN, for instance.
  ! Today's visible cost is only a miscount, but the dangerous case is a '+' leak - `IF -x`,
  ! `LOOP -n TIMES` and `CASE -x` all put a sign straight after a keyword marked '+', which
  ! would give an unmatched OPEN and put every scope below it one level too deep. That is the
  ! same failure the OLE fix cured, arriving by a different road.
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

!--- GCR 27Aug2021 the following code for literal was commented out but don't know why?  reinstating it.
  elsif size(self.Tokens.tok) > 1 and self.Tokens.tok[1] = '''' and self.Tokens.tok[size(self.Tokens.tok)] = ''''
    self.Tokens.type = vt:Literal                     ! note: GCR 27Aug2021 was L but changed to ' to not confuse with Long
    return
  end

  self.tokens.type = ' '                              ! default    moved down to here GCR 31Oct2019 to leave type for '.' "as is" so do not lose vt:end values
  self.tokens.level = ' '                             ! (already cleared above; harmless, and keeps this block readable on its own)
  if self.TokenIsReservedWord()
    self.Tokens.type = vt:reservedWord
    case upper(self.tokens.tok)
    ! ONLY THE CODE STRUCTURES OPEN UNCONDITIONALLY. Each is followed by an
    ! EXPRESSION - `IF ~p`, `CASE EVENT()`, `LOOP i = 1 TO 3`, `EXECUTE n` - so there is no
    ! declaration shape to test for, and none of these words is ever a variable name.
    ! The DATA and CONTROL structures moved OUT of here, to the declaration-position test in
    ! ParseText's walk: WINDOW QUEUE GROUP FILE RECORD CLASS MODULE ITEMIZE MENUBAR MENU
    ! TOOLBAR SHEET TAB OPTION APPLICATION, plus the eight added later. They open only when
    ! the next token is ',' '(' or EOL, because `Window` and `Report` are the Clarion
    ! template's own default LABELS and `Window{PROP:Text} = 'x'` must not open anything.
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
  ! the exponent form is now typed. `1.5e3` arrives as `1` `.` `5e3` (the '.' is a
  ! delimiter), and with `5e3` falling out of this loop untyped the three could never merge, so
  ! a rule keyed on a numeric type never saw the number at all. Round-trip was never at risk -
  ! the bytes are the same either way - which is exactly why nothing reported it.
  ! KNOWN LIMIT, deliberately not fixed here: the LRM's other bases - binary `1011b`, octal
  ! `3403o`, hex `0CD1F74FH` (p496) - still fall out untyped, because their terminator letters
  ! are ambiguous with hex digits ('B' is both) and telling them apart means deciding the base
  ! from the LAST character before validating the digits. That is a bigger change than the
  ! flagged one, with the same silent-miss consequence and no demonstrated need; it wants its
  ! own round and its own fixture.
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
! change is inert: if a round moves nothing in the gated round trips, JoinToks is the
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
    ! GCR 23Sep2023 we need to be careful because with continuations ('|') there is no <10> token but CRLF is included in strBefore
    !               of first token on next line.
      if not self.tokens.tok &= NULL and self.tokens.tok = '<10>'
        if toEOL = eWithComments and not self.tokens.strBefore &= NULL
          st.append(self.tokens.strBefore)
        end
        break
      end
      if self.tokens.firstOnLine and x > pStart ! continuation line - CRLF is in StrBefore
        if self.tokens.strBefore &= NULL then self.TraceIt('expecting continuation line: line ' & self.tokens.LineNo);break.
        y = instring('<13,10>', self.tokens.strBefore,1,1)
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
  get(self.Tokens,svPtr) ! restore queue to previous state


! ------------------------------------------------------------------------------------
VitTokenize.FreeToks     Procedure() !, virtual
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
  end                !   ParseText on a reused tokenizer and changes LEVEL stamping of identical
                     !   text - measured as a census of +392 against +385 on byte-identical
                     !   streams. Every parse is self-contained; the backwards declaration pass
                     !   rebuilds vars fresh.
  clear(self.tokens) ! free() leaves the RECORD BUFFER holding the
                     !   last row, and firstOnLine is written only by SetLineNumbers - AddToken
                     !   never assigns it. TokenIsReservedWord READS it during tokenising, before
                     !   SetLineNumbers has run: `if firstOnLine and strBefore &= NULL then return
                     !   FALSE`. So on a REUSED tokenizer (RejoinReparse after every rewrite round)
                     !   a stale TRUE would stop every column-1 token being a reserved word for
                     !   the whole pass. Same class as the per-parse vars table two lines above,
                     !   so clear it for the same reason.
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
  if self.Tokens &= null or |
     ~pSrc               or |
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
! BACKWARDS (pSrc > pDst) each token lands after the one before it, so pDst advances by one
! each time. Moving forwards needs no such step, because every move shifts the remaining
! source tokens down onto pSrc for free.
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
    if pSrc > pDst then pDst += 1.
  end
  return st:ok

! ------------------------------------------------------------------------------------
! The token text at pTokNumber, or '' if there is none.
!
! '' IS AMBIGUOUS HERE and you cannot tell the two cases apart: no such token, and a token
! whose tok is NULL, both come back as ''. That is fine for the usual "is this a comma"
! question and wrong for anything that has to know a token EXISTS. Use Records() for the
! bound, or the three-argument overload below, when the difference matters.
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
VitTokenize.GetCurrLineComment   Procedure(stringTheory pSt, long pTokNumber) !virtual   GCR 22Sep2023
  code
  pSt.free()
  loop
    Get(self.tokens,pTokNumber)
    if errorcode() then return.
    if not self.tokens.tok &= NULL and self.tokens.tok = '<10>' ! EOL; the null test first - tok is a reference and may be unset
      if not self.Tokens.strBefore &= null
        pSt.setValue(self.Tokens.strBefore)
      end
      break
    end

    ! GCR 22Sep2023 we need to be careful because with continuations ('|') there is no <10> token but CRLF is included in strBefore
    !               of first token on next line.
    if self.tokens.firstOnLine                                  ! continuation line - CRLF is in StrBefore
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
!
! If pTokNumber does not exist it appends a new trivia-only token at the end of the stream,
! the same way AppendStrBefore does.
! ------------------------------------------------------------------------------------
VitTokenize.InsertStringAtEOL    Procedure(long pTokNumber, string pStr, byte pComment=1) !,virtual    GCR 13Sep2023 useful for adding comments at EOL
! insert string at end of current line
! if pComment is 1 we make it a comment (prepend ' ! ') or append to existing comment
! if pComment is 2 we make it a comment (prepend ' ! ') and PREPEND to existing text
! if pComment is 3 then NOT a comment and treat ';' and 'THEN' as logical EOL (for when line has several logical lines combined) GCR 5Dec2023
isCmt byte,auto                                                                                                                                    ! mode 1 or 2 = comment; mode 0 and mode 3 are not
  code
  if size(pStr) = 0 then return.

! self.traceIt = true

  loop
! self.TraceIt('InsertStringAtEOL:  token ' & pTokNumber)
    Get(self.tokens,pTokNumber)
    if errorcode()
! self.TraceIt('InsertStringAtEOL:  token does not exist so add new one on end')
      ! token does not exist so add new one on end
      ! the test is "is this mode a COMMENT", and `~pComment` is not it. Mode 3 inserts a
      ! REAL TOKEN (VitEngine:872 adds a ')' that way), and ~3 is 0, so this fallback used to
      ! prepend ' ! ' and comment the bracket OUT. Modes: 0 = plain text, 1 and 2 = comment,
      ! 3 = real token. Both the allocation and the text must ask the same question.
      isCmt = choose(pComment = 1 or pComment = 2)
      clear(self.tokens)
      self.Tokens.strBefore &= new string(size(pStr)+choose(~isCmt,0,3))                                                                           ! if comment add extra 3 for ' ! '
      self.tokens.strBefore = choose(~isCmt,pStr,' ! '&pStr)
      add(self.Tokens)                                                                                                                             ! note: is added to END of queue
?     assert(~errorcode())
      break
    end
    if not self.tokens.tok &= NULL and (self.tokens.tok = '<10>' or (pComment = 3 and (self.tokens.tok = ';' or lower(self.tokens.tok) = 'then'))) ! EOL; the null test first - tok is a reference and may be unset
! self.TraceIt('InsertStringAtEOL:  EOL')
      if pComment=3
!        self.AppendStrBefore(pTokNumber, pStr)
        self.InsertString(pTokNumber, pStr)                                                                                                        ! 3 = not a comment so insert tokens not comment

      elsif self.Tokens.strBefore &= null                                                                                                          !or self.Tokens.strBefore = ''
        self.SetStrBefore(pTokNumber,choose(~pComment,pStr,' ! '&pStr))
      elsif pComment=2                                                                                                                             ! make comment and prepend to existing text
        self.PrependStrBefore(pTokNumber, ' ! ' & pStr)
      elsif ~pComment or instring('!',self.Tokens.strBefore,1,1)
        self.AppendStrBefore(pTokNumber,' ' & pStr)
      else
        self.AppendStrBefore(pTokNumber, ' ! ' & pStr)
      end
      break
    end

    ! GCR 23Sep2023 we need to be careful because with continuations ('|') there is no <10> token but CRLF is included in strBefore
    !               of first token on next line.
    if self.tokens.firstOnLine                                                                                                                     ! continuation line - CRLF is in StrBefore
! self.TraceIt('InsertStringAtEOL: first on line: ' & self.tokens.tok )
      if self.tokens.strBefore &= NULL
        self.TraceIt('VitTokenize.InsertStringAtEOL - expecting continuation line: line ' & self.tokens.LineNo)
      else
        do ContinuationWork ! separate so ST object is not unnecessarily instantiated
      end
      break
    end

    pTokNumber += 1
  end
!self.traceIt = false


continuationWork routine
  data
st StringTheory             ! put this into routine so only declared when needed
y  long,auto                ! position of an existing '!' in the post-bar text
  code
  st.setValue(self.tokens.strBefore)
  st.split('<13,10>')
  if st.records() = 1
    self.TraceIt('VitTokenize.InsertStringAtEOL - expecting CRLF in continuation line: line ' & self.tokens.LineNo)
  end
  st.setValueFromLine(1)    ! text before CRLF
  if pComment=2             ! make comment and prepend to existing text
    st.replace('|',' ',1)   ! get rid of first | continuation char as we are adding one at start
    st.clip()
    st.prepend(' | ' & pStr)
  elsif ~pComment
    st.append(pStr)         ! caller wants raw text, not a comment
  elsif st.containsByte(33) ! a comment is already parked after the bar - add to it, '!'
    y = st.findByte(33)     ! and go in FIRST: matches are applied right-to-left, '!'
    st.setValue(st.sub(1, y) & ' ' & pStr & |   ! so inserting each new note just after
                st.sub(choose(y + 1 < 0, st._DataEnd + y + 1 + 1, y + 1), st._DataEnd - y)) ! the '!' rebuilds left-to-right order
  elsif st.containsByte(124)                                                                ! a line ending in a continuation bar takes its '|'
    st.append(' ! ' & pStr)                                                                 ! comments AFTER the bar - Clarion ignores everything past it, so
  else                                                                                      ! this is the right home for them. Append with a ' | ' separator:
    st.append(' | ' & pStr)                                                                 ! raw text with no separator and no '!' runs several notes
  end                                                                                       ! together, as in `... or |'[''&'''''`
  st.setLine(1,st)
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
  if (not omitted(pStrBefore)) and size(pStrBefore) ! size, NOT truthiness - see the banner above
    self.Tokens.strBefore &= new string(size(pStrBefore))
    self.tokens.strBefore = pStrBefore
  end
  self.TokenType()                                  ! sets self.tokens.type
  add(self.Tokens,pTokNumber)                       ! note if pTokNumber is zero then is added to END of queue
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
    pEnd += records(self.tokens)        ! pEnd of 0 = last record,  pEnd of -1 means "last but one" = second last etc.
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
  of 43 ! '+'  ! search forwards for matching '-'
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
  of 45 ! '-'  ! search backwards for matching '+'
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
! Read the direction off the loop, not off the name: this one runs `pStart to 1 by -1`. The
! banner used to say FORWARD, which is what MatchLeftBracket does.
! ------------------------------------------------------------------------------------
VitTokenize.MatchRightBracket  Procedure(String pLeftBracket, String pRightBracket, Long pStart=0) ! searches BACKWARDS and returns matching token number
ans     long
depth   long
x       long,auto
  code
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
! Fold a string onto continuation lines so it fits, returning the folded text.
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
! Fold tokens pStart..pEnd onto continuation lines, in place.
! ------------------------------------------------------------------------------------
VitTokenize.FoldStr               Procedure(LONG pStart=1, LONG pEnd=0) !STRING, virtual
x              long,auto
cb             long,auto                                  ! close bracket
endTok         long,auto
endOffset      long,auto
eOff           long,auto                                  ! endoffset used when recursing down on expression in brackets
svPEnd         long,auto                                  ! store end for Plus loop
svMEnd         long,auto                                  ! store end for Multiplication loop
calc           stringTheory
firstNumTok    LONG                                       ! indicate position of first eligible number token - we will add others to this token
insertNegative LONG                                       ! used when amt in brackets is negative eg. X+(2-4) or (2-4)+X
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
      ! see if we can do simple evaluate
      calc.SetValue(evaluate(self.JoinToks(pStart,pEnd)))
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
! note for now we are only folding positive numbers eg. 4*5 but not (yet) 4*-5
 data
state    long
isNumber long
isMult   long
 code

  loop x = pStart to pEnd

    Get(self.Tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break. ! no more tokens

    case val(self.tokens.type)
    of 73  orof 78                                        ! 'I' orof 'N'
      isNumber = TRUE
      isMult = FALSE
    of 109                                                ! 'm'          ! multiplication type - tok is * or / or %
      isNumber = FALSE
      isMult = TRUE
    else
      isNumber = FALSE
      isMult = FALSE
    end

    case state
    of 0                                                  ! looking for first numeric token
      if isNumber
        state = 1
        calc.SetValue(self.tokens.tok)
      end
    of 1                                                  ! looking for multiplication type
      if isMult
        state = 2
        calc.cat(self.tokens.tok,1)
      elsif ~isNumber
        state = 0
      end
    of 2                                                  ! looking for second number
      if isNumber
        calc.append(self.tokens.tok)
        calc.SetValue(evaluate(calc.getValue()))
        if calc._DataEnd and calc._DataEnd < 15           ! too many digits might mean rounding
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

FoldAdditions routine                                     ! includes subtractions
 data
prevPlusMinus LONG,AUTO                                   ! indicate if prev token was + or -
currPlusMinus LONG(1)                                     ! indicate if curr token is + or - NB. assume first is '+'  eg. "4 - 1" is "+4-1"
ready         LONG                                        ! indicate we have form +number or -number and are ready to see if next token is also + or -

 code
  calc.free()
  firstNumTok = 0

  x = pStart - 1

  loop
    pEnd = records(self.tokens) - endOffset               ! adjust end position in case there have been deletions
    ! change of policy - GCR 4Oct2019 if a token deletion has occurred, then exit and start over (is performed in a loop until unchanged)
    if svPEnd <> pEnd then break.

    x += 1
    if x > pEnd then break.

    Get(self.Tokens,x)
    if errorcode() or self.Tokens.tok &= NULL then break. ! no more tokens

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
    if self.tokens.type = 'p'   !self.Tokens.tok = '+' or self.Tokens.tok = '-'
      currPlusMinus = TRUE
      if x=pStart and self.tokens.tok = '+'
        ! GCR 10Oct2019: delete leading + sign
        self.DeleteTok(x)
        self.SetStrBefore(x,'') ! remove spacing before next token
        cycle
      end
    else
      currPlusMinus = FALSE
    end

    if currPlusMinus or self.Delimiter[val(self.Tokens.tok[1])+1]
      if ready                  ! do we have +number or -number preceding this?
        ready = FALSE
        if firstNumTok
          do FoldIt
        elsif self.GetTok(x-1) = 0
          self.DeleteTok(x-1)
          self.DeleteTok(x-2)
          x -= 2
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

      if prevPlusMinus and (endTok = x+3 and self.GetTok(x+1) = '-')
        self.DeleteTok(x+3)
        case val(self.GetTok(x-1))
        of 43 orof 45                                                                 ! '+' orof '-'
          self.setTok(x-1, choose(self.getTok(x-1) = '+','-','+'))                    ! reverse the sign prior to the brackets
          endTok -= 1
        else
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
      if x = pEnd and firstNumTok and firstNumTok < x and self.GetTok(x) <> 0
        x+=1
        do FoldIt
      elsif x = pEnd and self.GetTok(x) = 0
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
    of 43 orof 45                                                                     ! '+' orof '-'
      if calc.GetValue() < 0
        self.setTok(firstNumTok-1,'-')
      else
        self.setTok(firstNumTok-1,'+')
      end
    else
      if calc.GetValue() < 0
        InsertNegative = true                                                         ! insert negative sign
      end
    end
    if insertNegative
      self.setTok(firstNumTok,'-','')
      self.setTok(firstNumTok+1,abs(calc.getValue()),'')
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

! ------------------------------------------------------------------------------------
! By-value front end for InsertString - see the overload below.
! ------------------------------------------------------------------------------------
VitTokenize.InsertString          Procedure(LONG pPos=1, STRING in) !,virtual
st StringTheory
 code
  st.SetValue(in)                         ! do NOT clip as may want space before following existing token
  self.InsertString(pPos,st)

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
VitTokenize.InsertString          Procedure(LONG pPos=1, StringTheory in) !,virtual
! tokenize and insert string at a given position
tk VitTokenize
x  long,auto
 code
  if ~in._DataEnd then return.

  tk.ParseText(in)

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
    self.tokens.level = tk.tokens.level ! review H1: carry the level mark (+/-/'/'x) so spliced keywords are not left blank for same-pass level consumers
    add(self.Tokens,pPos)
?   assert(~errorcode())
  end

VitTokenize.GetParms              Procedure(StringTheory pParms,*LONG pStart,*LONG pEnd) !,LONG,virtual
! finds next opening bracket and then gets parameters split into pParms line queue - returns number of parameters
x            long,auto
cb           long                       ! close bracket
 code
  pParms.free(true)                     ! true means also free lines Q

  if pStart < 1 then pStart = 1.
  if pEnd < 1 or pEnd > Records(self.tokens)
    pEnd = records(self.tokens)
  end

  loop x = pStart to pEnd
    Get(self.tokens, x)
    if not self.tokens.tok &= NULL and self.tokens.tok = '('
      pStart = x                        ! set actual start bracket
      break
    end
  end
  if not self.tokens.tok &= NULL and self.tokens.tok = '(' and pStart < pEnd
    cb = self.MatchLeftBracket('(',')',pStart)
  end
  if ~cb or cb > pEnd
    pEnd = 0                            ! indicate no matching end bracket
    return 0                            ! no parameters
  end
  pEnd = cb                             ! added GCR 2Jan2020 at Cowes - set pEnd to closing bracket
  self.JoinToks(pParms,pStart+1,cb-1)   ! get parameters into parameter ST object
  pParms.split(',','''-(','''-)',,st:clip,st:left,'-',st:nested)
  return pParms.Records()               ! return number of parameters

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
  return 0                                                  ! not found

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
  x = self.FindFirstTokNumOnLine(pSearchLine+1,pStartAtTok) ! search for first tok on next line
  if x then return x - 1.                                   ! point to last tok on desired line (prev line)
  get(self.tokens,records(self.tokens))                     ! if not found, see if it matches last token
  if self.Tokens.lineNo = pSearchLine then x = pointer(self.Tokens).
  return x                                                  ! will be 0 if not found

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
sx         long,auto                                        ! walk cursor for a boundary line that carries no token
  code
  ! the bounds wanted are ">= pStartLine" and "<= pEndLine", NOT "= pStartLine" and
  ! "= pEndLine+1". A BLANK or COMMENT-ONLY line carries no token of its own - its text lives
  ! in the strBefore of the next real token - so a keyed get on that line number MISSES, and a
  ! blank boundary line is the most ordinary thing in a source file. What the miss used to do:
  !   at the START, `return 0` - the token reported ABSENT from a range that may well hold it;
  !   at the END, endTok left 0, which FindTok reads as "to EOF" - matches handed back from
  !   OUTSIDE the range asked for, which is the worse of the two.
  ! "we want >= not just =" - The keyed get is kept as the
  ! fast path; the walk below runs only when it misses.
  if pStartLine > 1
    self.Tokens.lineNo = pStartLine
    get(self.tokens,self.Tokens.lineNo)
    if ~errorcode()
      startTok = pointer(self.Tokens)
?     if ~self.tokens.firstOnLine then stop('ErrorA in FindTokInLines - Token ' & pointer(self.Tokens) & ' = ' & self.tokens.tok & ' not marked as first on line ' & self.Tokens.lineNo & ' (= ' & pStartLine & ')').
    else
      startTok = 0                                          ! no token ON that line - take the first one AFTER it
      loop sx = 1 to records(self.tokens)
        get(self.Tokens,sx)
        if errorcode() then break.
        if self.Tokens.lineNo >= pStartLine
          startTok = sx
          break
        end
      end
      if ~startTok then return 0.                           ! nothing at or after that line at all
    end
  else
    startTok = 1
  end
  if pEndLine
    self.Tokens.lineNo = pEndLine+1                         ! we get first tok on next line then subtract 1
    get(self.tokens,self.Tokens.lineNo)
    if ~errorcode()
?     if ~self.tokens.firstOnLine then stop('ErrorB in FindTokInLines - Token ' & pointer(self.Tokens) & ' = ' & self.tokens.tok & ' not marked as first on line ' & self.Tokens.lineNo & ' (= ' & pStartLine & ')').
      endTok = pointer(self.Tokens) - 1
    else
      loop sx = startTok to records(self.tokens)            ! no token on the line after the range -
        get(self.Tokens,sx)                                 !   walk to the first token PAST it
        if errorcode() then break.
        if self.Tokens.lineNo > pEndLine
          endTok = sx - 1
          break
        end
      end
      ! none past it: the range runs to the end of the stream, and endTok 0 says exactly that
    end
  end

  return self.FindTok(pStr,startTok,endTok,st:nocase)       !note: endTok of 0 means to EOF

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
state        long                                           ! which token are we looking for?
prevState    long                                           ! previous state
seqFrom      long                                           ! the token this attempt STARTED on - where a failed attempt rewinds to
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

  if self.sepChar <> in[1]      or |
     self.noCaseChar <> in[2]   or |
     self.wsBeforeChar <> in[3] or |
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
      self.searchQ.noCase = TRUE ; self.searchQ.wsBefore = TRUE ! explicit init - without it an un-prefixed/1-char element inherits the previous element's QUEUE BUFFER residue (order-dependent). PERMISSIVE defaults: the vtxaDiff-ported patterns were verified byte-for-byte against the legacy behaviour, where inheritance made elements ws-tolerant + caseless in practice (strict FALSE defaults dropped 26 verified CheckCaseStatements conversions on tests.clw)

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
        x -= state                                                  ! reset to first token
        Get(self.tokens, x)
        ! lookup the variable name in tokens variables queue to see if it is defined with this type
        if self.vars.varName <> self.tokens.Tok
          self.vars.varName = self.tokens.Tok
          get(self.vars,+self.vars.varName)
          if errorcode()
            self.vars.varTypes = ''
          end
        end
        if self.vars.varTypes[1] = FirstVarType or instring(FirstVarType,self.vars.varTypes,1,1)
          ! matches OK
          ans = x
          break
        else
          state = 0                                                 ! not a match - go back and start all over
          cycle
        end
      else
        ans = x-state                                               ! we have match - return first token in the sequence
        break
      end
    elsif ~state and FirstVarType
      seqFrom = x                                                   ! this attempt starts here
      state = 1                                                     ! we skip first parm of type and check it at end if/when everything else matches
      cycle
    else
      if ~state then seqFrom = x.                                   ! this attempt starts here
      state += 1
    end
    if state <> prevState
      get(self.searchQ,state)
      prevState = state
    end
    Get(self.tokens, x)
    if not self.tokens.strBefore &= NULL and ~self.searchQ.wsBefore ! not allowed to have ws before token
      do SeqRestart
      cycle
    end
    if self.tokens.Tok &= NULL then break.
    if size(self.searchQ.Tok) > 1 and self.searchQ.Tok[1] = '%'     ! substitution parameter
      if self.searchQ.Tok[2] = '*'
      ! wildcard anything OK
      elsif self.searchQ.Tok[2] = vt:Literal
        if self.tokens.type = vt:Literal
          ! matches OK
        else
          do SeqRestart                                             ! not a match - restart one token after this attempt began
        end
      elsif inrange(val(self.searchQ.Tok[2]),48,57)                 ! is 2nd char a digit?
        seqNum = self.searchQ.Tok[2 : size(self.searchQ.Tok)]       ! strip off first char to give how many toks to go back for required value
        if ~seqNum then self.TraceIt('invalid seqNum ' & self.searchQ.Tok[2 : size(self.searchQ.Tok)] & ' in vitTokenize.FindSeq : ' & in).
        if (self.searchQ.noCase  and upper(self.getTok(x-seqNum)) = upper(self.getTok(x))) or |
           (~self.searchQ.noCase and self.getTok(x-seqNum) = self.getTok(x))
          ! matches OK
        else
          do SeqRestart ! not a match - restart one token after this attempt began
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
        if self.vars.varTypes[1] = self.searchQ.Tok[2] or instring(self.searchQ.Tok[2],self.vars.varTypes,1,1)
          ! matches OK
        else
          do SeqRestart ! not a match - restart one token after this attempt began
        end
      else              ! state = 1
        firstVarType = self.searchQ.Tok[2]
      end
    else
      if self.searchQ.Tok = choose(~self.searchQ.noCase, self.tokens.tok, upper(self.tokens.tok))
        ! matches OK
      else
        do SeqRestart   ! not a match - restart one token after this attempt began
      end
    end
  end
  return ans

! ---- a failed attempt restarts one token after the token this attempt BEGAN on, not one
!      token after the one that FAILED. Without the rewind the scan walks straight past any
!      OVERLAPPING match: [val,(,chr,(] against `val(val(chr(65)))` found nothing, because the
!      failure at the second `val` consumed it and the real match starting THERE was never
!      tried. The FirstVarType arm above has always backtracked - it says `x -= state` before
!      it resets - so this only makes the ordinary mismatch paths agree with the one that was
!      already right. It cannot loop: seqFrom is set only where state leaves 0, so each restart
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
! With no filename it invents a timestamped one in the CURRENT DIRECTORY. It used to put that
! default under .\testdata\ - a directory that exists in this project and nowhere else, so for
! anyone else the save failed, and the failure was trace-only (both off by default): the
! documented level-census workflow produced nothing at all, silently. The CLI always passes an
! explicit name, so this default is for embedders. This is the tool of choice
! when a level census does not balance: the dump shows each token's level mark, and the
! structure that opened without closing is visible in a way the source is not.
! ------------------------------------------------------------------------------------
VitTokenize.DumpTokens Procedure(<string pFilename>) !,virtual ! dump token list to disk - optionally provide file name
dumpST  StringTheory
dumpSeq long,static,thread ! add seq number as clock resolution is such that sometimes files were overwritten if time diff < .01 secs
dumpFn  string(512),auto   ! the name actually used, so the failure message can NAME it
  code
  dumpSeq += 1
  self._List(dumpST,true)  ! st tokens - one per line - second parm is show extra columns
  dumpFn = choose(~omitted(pFilename), pFilename, 'tokenize file on ' & clip(left(format(today(),@d12))) & |
           ' at ' & clip(left(format(clock(),@T05))) & format(clock()%100,@n02) & format(dumpSeq%1000,@n03) & '.txt')
  if not dumpSt.SaveFile(dumpFn)
    self.dumpFailed = 1    ! a caller can SEE the failure now; TraceIt alone ships off
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
inner   long,auto                              ! length of the text between the quotes
z       long,auto
gEnd    long,auto
gz      long,auto
best    long
bestD   long
bd      long,auto
bnd     long,auto                              ! the boundary: last char of the unit just consumed
  code
  get(self.tokens, pTokNumber)
  if errorcode() then return 0.
  if self.Tokens.tok &= NULL then return 0.
  if size(self.Tokens.tok) < 12 then return 0. ! nothing worth cutting
  if self.Tokens.tok[1] <> '''' then return 0.
  if self.Tokens.tok[size(self.Tokens.tok)] <> '''' then return 0.
  inner = size(self.Tokens.tok) - 2
  z = 1
  loop while z <= inner
    case val(self.Tokens.tok[z + 1])           ! inner character z
    of 39                                      ! <single quote>
      z += 2                                   ! '' escaped quote - atomic
    of 60                                      ! '<'
      if z + 2 <= inner and self.Tokens.tok[z + 2] = '<'
        z += 2                                 ! << escaped less-than - atomic
      else
        gEnd = 0
        loop gz = z + 1 to inner
          if self.Tokens.tok[gz + 1] = '>' then gEnd = gz ; break.
        end
        if gEnd
          ! ---- an escape GROUP is not really atomic. A long one
          !      splits at any of its commas, because two groups concatenate to the same bytes:
          !          '<0,1,2,3,4,5>'   ==   '<0,1,2>' & '<3,4,5>'
          !      Without this a literal that IS one long group had nowhere to cut at all and the
          !      line stayed wide. Offered as a NEGATIVE offset so SplitLongLiteral can tell the
          !      two cut shapes apart: the comma is REPLACED by '>>' ... '<<', not just cut at.
          loop gz = z + 1 to gEnd - 1
            if self.Tokens.tok[gz + 1] <> ',' or |
               gz < 4 or inner - gz < 4
              cycle
            end
            bd = gz - pWant
            if bd < 0 then bd = -bd.
            bd += 8                           ! a plain boundary is tidier - prefer it when close
            if gz < pWant then bd += 4.       ! see the LONGER-FIRST note in PickBreak
            if ~best or bd < bestD
              bestD = bd
              best  = -gz                     ! NEGATIVE = cut inside an escape group
            end
          end
          z = gEnd + 1                        ! then step over the whole group
        else
          z += 1                              ! a stray '<' - treat as one character
        end
      end
    of 123                                    ! '{{'
      if z + 2 <= inner and self.Tokens.tok[z + 2] = '{{'
        z += 2
      else
        z += 1
      end
    else
      z += 1
    end
    ! ---- THE BOUNDARY IS z - 1: THE LAST CHARACTER OF THE UNIT JUST CONSUMED. ----
    ! Every branch above has already stepped z PAST its unit, so z names the first character
    ! of the NEXT one - which has not been examined yet. Offering z as the cut therefore puts
    ! the boundary one character right of the one actually verified, and the character it
    ! lands in front of may be the first half of an atomic pair: on 'aaaa''bbbb' the cut fell
    ! BETWEEN the two quotes of the escaped pair, ending the string early and producing source
    ! that does not compile. Keep the one closest to pWant.
    if z > inner then break.
    bnd = z - 1
    if bnd < 4 or inner - bnd < 4 then cycle. ! never leave a stub
    bd = bnd - pWant
    if bd < 0 then bd = -bd.
    ! break on a WORD boundary where there is one. The first half ends
    ! with inner character z, so a cut whose last character is a space reads as
    !     'so it is plain text ' & |
    !     'and must never be closed'
    ! instead of splitting `text` down the middle. A penalty rather than a hard rule, so a
    ! literal with no spaces at all - a long escape group, a path, a key - can still be cut.
    if self.Tokens.tok[bnd + 1] <> ' ' then bd += 16.
    if bnd < pWant then bd += 4.              ! see the LONGER-FIRST note in PickBreak
    if ~best or bd < bestD
      bestD = bd
      best  = bnd                             ! POSITIVE = plain boundary cut
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
  ! BLANK and drop it. This call is what exercises that guard, so TestData\r108split.clw is its
  ! end-to-end gate: if AddTok ever stops keeping the space, that fixture shows it.
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
! and they are. A single sweep therefore stops holding pieces it WOULD break if it looked
! again - which is precisely what running the tool a second time did to them, and why an
! --style=extreme run (whose deferred slice widens lines after the fixpoint) came back changed
! on a second run: three lines of NetWeb V1400.clw. The two phases now sweep until a
! sweep breaks nothing. The cap is a runaway guard, not a budget; hitting it leaves lines long,
! which is the same safe outcome as having no candidate at all.
!===============================================================================================
VitTokenize.SplitWideLines Procedure(LONG pMaxWidth)
lineQ       QUEUE,PRE(lq)                            ! one row per CODE token on the line under test
tokIx         LONG    !   its token index
endW          LONG    !   rendered width of the line UP TO AND INCLUDING it
depth         LONG    !   paren depth AFTER it
kind          LONG    !   0 = not a candidate, 1 = after ',', 2 = after the operator, 3 = after '('
used          BYTE    !   already broken here
            END
cutQ        QUEUE,PRE(cq) ! segment boundaries, in width order: 0 .. lineWidth
atW           LONG
            END
x           long,auto
w           long
dep         long
minAmp      long      ! shallowest depth any '&' reached on this line
ind         string(64)
indLen      long
contInd     byte      ! the line ending here is CONTINUED - a bar in its trivia
cz          long,auto ! scan cursor over a broken token's own trivia
sb          stringTheory
q           long,auto
z           long,auto
lastNl      long,auto
tk1         string(1),auto
firstTok    long
split       long
segS        long,auto
segE        long,auto
best        long,auto
bestScore   long,auto
sc2         long,auto
mid         long,auto
prevW       long,auto
progress    byte
lz          long,auto                 ! phase 2 - long-literal splitting
lw          long
lindW       long                      ! the line's indent, as a WIDTH: a fixed
lsTok       long                      ! first token of the STATEMENT lz sits in
lq3         long,auto                 !   and the walk back to find it
                                      !   string cannot hold one - four spaces
                                      !   and sixty-four are the same value once
                                      !   padded, and clip() reduces both to none
lstart      long
lcut        long,auto
sweep       long,auto                 ! sweeps of the two phases made so far
sweepStart  long,auto                 !   what `split` stood at as this sweep began
  code
  if pMaxWidth < 40 then return 0.
  loop sweep = 1 to 12
    sweepStart = split
    do OnePass
    if split = sweepStart then break. ! a sweep that breaks nothing - the file has settled
  end
  return split

! ---- ONE sweep: phase 1 breaks between tokens, phase 2 cuts a literal that is the whole payload ----
OnePass routine
  free(lineQ) ; free(cutQ)
  w = 0 ; dep = 0 ; firstTok = 0 ; ind = '' ; indLen = 0 ; minAmp = 0
  loop x = 1 to records(self.tokens)
    get(self.tokens, x)
    if errorcode() then break.

    if not self.Tokens.strBefore &= NULL
      lastNl = 0
      loop z = 1 to size(self.Tokens.strBefore)
        if val(self.Tokens.strBefore[z]) = 10 then lastNl = z.
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
          indLen = size(self.Tokens.strBefore) - lastNl
          if indLen > size(ind) then indLen = size(ind).
          ind = ''
          loop z = 1 to indLen
            ind[z] = self.Tokens.strBefore[lastNl + z]
          end
        end
        do FinishLine
        w = size(self.Tokens.strBefore) - lastNl
        indLen = w
        if indLen > size(ind) then indLen = size(ind).
        ind = ''
        loop z = 1 to indLen
          ind[z] = self.Tokens.strBefore[lastNl + z]
        end
      else
        ! THE FIRST TOKEN AFTER AN EXPLICIT <10> TOKEN CARRIES THE WHOLE INDENT, and there is no
        ! newline in it to find - the newline was a token of its own, and the branch above only
        ! fires when the line end is INSIDE strBefore. Both spellings occur. Without this the
        ! indent was never captured for the second kind, indLen stayed 0, and ApplyBreak wrote
        ! its continuation at column 3 - `sb.append('  ')` plus the broken token's own single
        ! space - however deep the statement was. VitSymbols.clw 607 is 16 columns in and its
        ! remainder landed at 3, beside the author's own continuations at 38.
        if ~w and ~indLen
          indLen = size(self.Tokens.strBefore)
          if indLen > size(ind) then indLen = size(ind).
          ind = ''
          loop z = 1 to indLen
            ind[z] = self.Tokens.strBefore[z]
          end
        end
        w += size(self.Tokens.strBefore)
      end
    end

    if self.Tokens.tok &= NULL then cycle.
    if size(self.Tokens.tok) = 1 and val(self.Tokens.tok) = 10
      do FinishLine
      w = 0 ; ind = '' ; indLen = 0 ; contInd = 0
      cycle
    end

    if ~firstTok then firstTok = x.
    tk1 = self.Tokens.tok[1]
    if size(self.Tokens.tok) = 1 and tk1 = '(' then dep += 1.
    w += size(self.Tokens.tok)

    clear(lineQ)
    lq:tokIx = x
    lq:endW  = w
    lq:kind  = 0
    lq:used  = 0
    if size(self.Tokens.tok) = 1
      case val(tk1)
      of 44         ! <comma>
        if dep = 1 then lq:kind = 1. ! outermost call's argument separator
      of 38         ! '&'
        lq:kind = 2 ! depth decided AFTER the line is known - see FinishLine
      of 40         ! '('
        if dep = 1 then lq:kind = 3. ! the opening paren of the outermost call
      end
      if tk1 = '&'
        if ~minAmp or dep < minAmp then minAmp = dep.
      end
    else
      ! AND / OR are the natural place to wrap a long condition, and Parser.clw is
      ! full of them - `if (UPPER(x) = 'PROCEDURE' OR UPPER(x) = 'FUNCTION')` had no candidate
      ! at all before this and stayed 102 characters wide. Break BEFORE the word, like '&', so
      ! the operator starts the continuation line and the condition reads down the page.
      if upper(self.Tokens.tok) = 'AND' or upper(self.Tokens.tok) = 'OR'
        if self.Tokens.type = vt:reservedWord then lq:kind = 2.
        if upper(self.Tokens.tok) = 'AND' or upper(self.Tokens.tok) = 'OR'
          if ~minAmp or dep < minAmp then minAmp = dep.
        end
      end
    end
    if size(self.Tokens.tok) = 1 and tk1 = ')' then dep -= 1.
    lq:depth = dep
    add(lineQ)
  end
  do FinishLine
  free(lineQ) ; free(cutQ)

  ! ---- PHASE 2: lines that are STILL over-wide because their payload is one long literal.
  !      Phase 1 breaks only BETWEEN tokens, so a 140-character literal is indivisible to it -
  !      observed on r108split.clw at --width=100, where OpenParen and Unsplittable came
  !      back at 162 and 173 with no candidate left. A literal can be cut; this does it.
  !      Walk BACKWARDS: SplitLongLiteral inserts two tokens, which shifts every index AFTER
  !      the cut, so going back to front leaves the not-yet-visited part of the queue untouched.
  !      Same reason the delete loops elsewhere in this file iterate backwards.
  loop lz = records(self.tokens) to 1 by -1
    do LitLineWidth ! lz -> lw (line width), lind (its indent), lstart (first token)
    if lw <= pMaxWidth then cycle.
    ! the '?' refusal has to be HERE as well. Phase 1 declining to break a '?'
    ! line just hands it to this phase, which cuts the literal instead and produces the
    ! same broken continuation - which is exactly what happened when only FinishLine was
    ! guarded (vitTokenize.clw 2956 again, cut inside 'not marked as ').
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
      if not self.Tokens.tok &= NULL and size(self.Tokens.tok) = 1 and val(self.Tokens.tok) = 10
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
    if size(self.Tokens.tok) < 24 then cycle.       ! not the reason the line is wide
    lcut = self.LitSafeCut(lz, size(self.Tokens.tok) / 2)
    if ~lcut then cycle.                            ! nowhere safe - leave the line wide
    if self.SplitLongLiteral(lz, lcut, lindW) then split += 1.
  end

! ---- width of the physical line token lz sits on, and that line's indent ----
LitLineWidth routine
  data
lq2  long,auto
lz2  long,auto
lnl  long,auto
  code
  lw = 0 ; lindW = 0 ; lstart = 0 ! lstart: 0 rather than the LAST line's, so a caller can test it
  loop lq2 = lz to 1 by -1        ! back to the start of this line
    get(self.tokens, lq2)
    if errorcode() then break.
    if not self.Tokens.strBefore &= NULL
      lnl = 0
      loop lz2 = 1 to size(self.Tokens.strBefore)
        if val(self.Tokens.strBefore[lz2]) = 10 then lnl = lz2.
      end
      if lnl
        lindW = size(self.Tokens.strBefore) - lnl
        lstart = lq2
        break
      end
    end
    if not self.Tokens.tok &= NULL and size(self.Tokens.tok) = 1 and val(self.Tokens.tok) = 10
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
    if lq2 > lstart and not self.Tokens.tok &= NULL and size(self.Tokens.tok) = 1 and val(self.Tokens.tok) = 10 then break.
    if lq2 > lstart and not self.Tokens.strBefore &= NULL
      ! a PHYSICAL line also ends where a newline appears inside the NEXT token's
      ! trivia - that is exactly what phase 1 writes when it breaks a line (' |' + CRLF + indent).
      ! Stopping only at an EOL token measured straight through those breaks and returned the
      ! width of the whole LOGICAL statement, so phase 2 saw lines as over-wide that phase 1 had
      ! already brought under the limit and split their literals for nothing. Observed:
      ! st.Replace(...) had its commas broken correctly and then had two literals cut as well.
      lnl = 0
      loop lz2 = 1 to size(self.Tokens.strBefore)
        if val(self.Tokens.strBefore[lz2]) = 10 then lnl = lz2.
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
  lw += lindW                  ! THE INDENT IS PART OF THE LINE. clip() of an
                               !   all-spaces indent is empty, so measuring it that
                               !   way added nothing and a line pushed over the
                               !   limit by its indent alone was never split.

! ---- the line just ended: cut it until every piece fits, or nothing more helps ----
FinishLine routine
  if ~records(lineQ) then do ResetLine ; exit.
  get(lineQ, records(lineQ))
  if lq:endW <= pMaxWidth then do ResetLine ; exit.
  ! NEVER SPLIT A LINE THAT BEGINS WITH '?'. The marker belongs to the PHYSICAL
  ! line, so a continuation of it is not marked and the compiler reads the tail as a
  ! statement of its own. Splitting one produced source Clarion rejects - vitTokenize.clw
  ! 2956, a 200-plus character '?' debug line, came back as
  !     ?     if ~self.tokens.firstOnLine then stop('...' & |
  !        & self.tokens.tok & ...
  ! and every token of the second line was an error. Found by BUILDING extreme-transformed
  ! source (bootstrap.bat); no text-level check could have seen it. Leaving the line long
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
    prevW = lq:endW ! every kind cuts AFTER its token - see ApplyBreak
    if prevW <= segS + 12 or |   ! refuse a stub like `st.SetValue( |`
       segE - prevW <= 12                     !   at either end - a break that helps nobody
      cycle
    end
    sc2 = prevW - mid
    if sc2 < 0 then sc2 = -sc2.
    sc2 += (lq:kind - 1) * 24                 ! a ',' is worth ~24 chars of distance over an '&', and '&' over a '('
    ! LONGER FIRST : when a cut cannot be even, put the LONGER piece on
    ! the first line - a full line followed by a short one reads better than the reverse. So a
    ! candidate BEFORE the midpoint (which would shorten the first piece) carries a small
    ! penalty. Deliberately small: it breaks ties and nudges near-ties, and never overrides a
    ! candidate that is genuinely closer to the middle or of a better KIND.
    if prevW < mid then sc2 += 4.
    if ~best or sc2 < bestScore
      bestScore = sc2
      best = q                                ! the lineQ ROW, resolved to a token in ApplyBreak
    end
  end

! ---- insert the continuation at the chosen candidate and record the new boundary ----
ApplyBreak routine
  get(lineQ, best)
  lq:used = 1
  put(lineQ)
  sb.setValue(' |<13,10>')
  if indLen then sb.append(ind[1 : indLen]).
  if ~contInd then sb.append('  ').           ! two past the statement - unless we are joining
                                              !   continuations the author already placed, in
                                              !   which case land exactly on their column
  ! EVERY KIND CUTS AFTER ITS TOKEN, INCLUDING THE OPERATOR. A concatenation or a wrapped
  ! condition ends its line with the operator and the bar - `expr & |` - and picks the next line
  ! up with the operand. Cutting BEFORE the operator instead left it stranded at the start of the
  ! continuation, which is a second spelling of the same statement and reads as scrappy beside the
  ! rows the author wrote by hand.
  ! THE REST OF THIS CLASS ALREADY ASSUMES THE OPERATOR-AT-END FORM. AlignComments carries a
  ! padPrev flag whose whole purpose is the pair `& |`, set for exactly '&', 'AND' and 'OR'
  ! immediately before a bar, so that the two move as one unit. Those are precisely the tokens
  ! marked kind 2 here. A splitter that emits the opposite spelling is the one part of the tool
  ! disagreeing with the rest of it.
  z = lq:tokIx + 1
  prevW = lq:endW
  get(self.tokens, z)
  if ~errorcode()
    if self.Tokens.strBefore &= NULL
      self.SetStrBefore(z, sb.getValue())
    else
      ! THE BROKEN TOKEN CARRIES ITS OWN LEADING SPACE - the one that separated it from what
      ! is now the line above. Kept, it sits on top of the indent and the joined line lands one
      ! column right of the continuations it was supposed to join. Drop it, but only when it is
      ! nothing but spaces: this trivia can hold a comment, and that must survive.
      if contInd
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

ResetLine routine
  free(lineQ)
  free(cutQ)
  firstTok = 0
  dep = 0
  minAmp = 0

!===============================================================================================
! strip trailing spaces and tabs from every line.  this is NEW behaviour,
! not something AlignComments was already doing - AlignComments splits with st:Clip but only into
! a LOCAL StringTheory it uses to measure comment columns, and never writes that copy back.
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
! layout-only run over source the rules have nothing to say about - a 13,415-line file with
! every rule evaluated and nothing written is the case this exists for. Clipping IS therefore
! a sufficient reason to rewrite a file on its own; the full reasoning is at
! the call site in VitEngine, above the cosmetic stages.
!===============================================================================================
VitTokenize.ClipLines  Procedure()
stBefore stringTheory,static,thread
x        long,auto
clipped  long
svPtr    long,auto
oldLen   long,auto
  code
  svPtr = pointer(self.tokens)                                                                ! restore the queue position at the end
  loop x = 1 to records(self.tokens)
    get(self.tokens, x)
    if errorcode() then break.
    if self.Tokens.strBefore &= NULL then cycle.                                              ! no trivia on this token at all
    stBefore.setValue(self.Tokens.strBefore)
    oldLen = stBefore._dataEnd
    ! (a) whitespace sitting immediately before an EMBEDDED line ending. Only two paths put a
    !     newline INSIDE strBefore - the `|` continuation branch (strBefore.append('<13,10>')) and
    !     the OMIT/COMPILE slice (tempST.replace) - and both store CRLF, so the CR forms fire.
    loop while stBefore.replace('<32,13>','<13>') or stBefore.replace('<9,13>','<13>') or stBefore.replace('<32,10>','<10>') or stBefore.replace('<9,10>','<10>').
    ! (b) THE ORDINARY CASE, and the one that matters. A line ending is its OWN TOKEN
    !     (tok.setvalue('<10>') in the scanner) - it is not trivia. So on a normal line the trailing
    !     whitespace is simply the TAIL of the EOL token's strBefore, with no newline byte
    !     after it for (a) to match against. Verified the hard way: with only
    !     (a) in place, a fixture with 30 trailing-whitespace lines came back with 25 - the
    !     five that WERE clipped being exactly the continuation line and the OMIT block.
    !     Trimming the tail is safe precisely BECAUSE this token is the newline: anything
    !     immediately before it is by definition at end of line. For any OTHER token, a
    !     trailing strBefore space is the gap between two tokens on one line (`a  =  b`) and
    !     removing it would weld them together - hence the guard.
    !     Comments live in this same strBefore, ahead of the tail, so AlignComments' padding
    !     (which it PREPENDS) is never disturbed.
    if not self.Tokens.tok &= NULL and self.Tokens.tok = '<10>' then stbefore.clip('<32,9>'). ! remove spaces and tabs from end
    if oldLen <> stBefore._dataEnd
      clipped += 1
      self.SetStrBefore(x, stBefore.getValue())                                               ! empty is fine - SetStrBefore stores &NULL for a zero-size value
    end
  end
  get(self.Tokens, svPtr)
  return clipped

!===============================================================================================
!   - line up the TYPE column of a run of declarations.
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
! Only ever moves a type RIGHT, to max(label) + 2. A run whose labels already agree is left
! untouched, and the same worth-it test the CASE aligner uses applies: if lining a run up would
! widen its longest line past the limit, leave it alone.
!===============================================================================================
VitTokenize.AlignDeclTypes Procedure(LONG pMaxWidth)
lnQ     QUEUE,PRE(dq)                                ! one row per declaration line in the run
labIx     LONG    ! the label token
typIx     LONG    ! the token after it - the type
labW      LONG    ! width of the label
gap       LONG    ! spaces between label and type, as the author left them
lineW     LONG    ! width of the whole line as it stands
        END
x       long,auto
q       long,auto
nsp     long,auto
nInd    long,auto ! trailing whitespace run counting TABS as well - the column-1 test, see DeclIndent
z       long,auto
labTok  long,auto
wid     long
alignQ  long      ! every type in the run already starts in the same column
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
    if size(self.Tokens.tok) = 1 and val(self.Tokens.tok) = 10 ! end of a line
      labTok = 0
      cycle
    end
    if self.Tokens.firstOnLine
      labTok = 0
      if self.Tokens.type = vt:label
        do DeclIndent                                          ! -> nsp
        if ~nInd then labTok = x.                              ! a label in COLUMN 1 - ANY indent, tab included, means it is not one
      end
      if ~labTok then do FlushDecl.                            ! not a declaration - the run ends
      cycle
    end
    if ~labTok then cycle.
    ! ---- this is the token straight after a column-1 label: the TYPE ----
    if self.Tokens.type = vt:reservedWord
      do FlushDecl                                             ! PROCEDURE / CLASS / QUEUE ... - not a variable
      labTok = 0
      cycle
    end
    do DeclIndent                                              ! gap before the type -> nsp
    get(self.tokens, labTok)
    if errorcode() then labTok = 0 ; cycle.
    wid = size(self.Tokens.tok)
    get(self.tokens, x)
    clear(lnQ)
    dq:labIx = labTok
    dq:typIx = x
    dq:labW  = wid
    dq:gap   = nsp                                             ! for the already-aligned test
    dq:lineW = wid + nsp + size(self.Tokens.tok)
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
!      COUNTING ONE WAY GOT IT WRONG, MEASURED. Breaking the loop at a tab made a
!      tab-terminated indent read as nsp = 0, and `if ~nsp` takes that for column 1 - so a
!      tab-indented STATEMENT entered the declaration run as label-plus-type and the aligner
!      re-spaced executable code. `<9>x = 1` came back `<9>x  = 1`, on a DEFAULT run, with
!      the '=' pushed into a column to meet the line below it. Nothing stopped it further
!      down: '=' is not a reserved word, so the type-token break never fired.
!      Space-indented files could never reach it, because a real column-1 label carries a
!      NULL strBefore - which is why every gate stayed green over it.
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
    if dc = ' '
      nsp += 1
      nInd += 1
    elsif val(dc) = 9
      nInd += 1
    else
      break
    end
  end

! ---- the run ended: push every type out to one space past the longest label ----
FlushDecl routine
  if records(lnQ) < 2 then free(lnQ) ; exit.         ! a single declaration has nothing to line up with
  ! ---- A RUN THAT IS ALREADY ALIGNED IS LEFT ALONE, whatever column it chose.
  !      There is no right constant here, which is what two rounds of evidence just showed:
  !        +2 rewrote parser.CountRefMarks, whose `i long,auto` / `n long,auto` were already
  !           level, into `i  long,auto`
  !        +1 then rewrote r109over's declarations, whose author had used the perfectly
  !           ordinary two-space gutter, into a one-space one
  !      Both are the same fault wearing opposite signs: the tool changing a block that was
  !      already consistent, to suit a number it picked. The author's column is a decision,
  !      and a format-preserving rewriter has nothing to say about it. Only a RAGGED run - one
  !      whose types genuinely do not line up - gets an opinion, and then the column is one
  !      space past the longest label, as this routine has always claimed.
  alignQ = 1
  get(lnQ, 1)
  z = dq:labW + dq:gap                 ! the column the first declaration starts its type in
  loop q = 2 to records(lnQ)
    get(lnQ, q)
    if dq:labW + dq:gap <> z then alignQ = 0 ; break.
  end
  if alignQ then free(lnQ) ; exit.     ! already level - nothing to say
  wid = 0 ; origW = 0
  loop q = 1 to records(lnQ)
    get(lnQ, q)
    if dq:labW > wid then wid = dq:labW.
    if dq:lineW > origW then origW = dq:lineW.
  end
  ! ONE space past the longest label, which is what the line above this
  ! routine claims and what the README documents. Write `wid += 2` and the longest
  ! label in every run gets TWO spaces after it - and in a run where the labels are all the same
  ! length that is every line: `i long,auto` and `n long,auto`, already perfectly aligned, come
  ! back as `i  long,auto`. That is a file the tool changed for no gain at all, which is the one
  ! thing a format-preserving rewriter must not do. With +1 such a run is left exactly as
  ! written - the gap is already 1, so the "already exactly right" test below skips it.
  wid += 1                             ! the column every type starts in
  newW = 0
  loop q = 1 to records(lnQ)
    get(lnQ, q)
    z = wid + (dq:lineW - dq:labW - 1) ! what this line becomes
    if z > newW then newW = z.
  end
  if pMaxWidth > 0 and newW > pMaxWidth and origW <= pMaxWidth
    free(lnQ) ; exit                   ! would push a fitting run over the limit
  end
  loop q = 1 to records(lnQ)
    get(lnQ, q)
    get(self.tokens, dq:typIx)
    if errorcode() then cycle.
    if not self.Tokens.strBefore &= NULL
      if instring('<10>', self.Tokens.strBefore, 1, 1) or |   ! a continuation - leave it
         size(self.Tokens.strBefore) = wid - dq:labW ! already exactly right
        cycle
      end
    end
    sb.setValue(all(' ', wid - dq:labW))
    self.SetStrBefore(dq:typIx, sb.getValue())
    moved += 1
  end
  free(lnQ)

!===============================================================================================
! - line up the OF labels of a CASE under its OROF labels.
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
! ONLY MOVES RIGHT, and only OF lines, for the same reason AlignComments only moves right: a
! pass that can move things both ways can oscillate, and this runs inside no fixpoint that
! would catch it. A CASE with no OROF at all is left completely alone - there is nothing to
! line up against, and shifting its OF lines would just be a change for its own sake.
!
! Cosmetic, after convergence. Works on the token stream rather than joined text, so a literal
! or a comment containing the word `of` cannot be mistaken for a label: only a token that is
! FIRST ON ITS LINE and carries the level mark the tokenizer gives a CASE label is considered.
!===============================================================================================
VitTokenize.AlignCaseLabels Procedure(LONG pMaxWidth)
cellQ   QUEUE,PRE(cl)                                ! every token on every OF/OROF label line
grp       LONG    ! which CASE block  - column 1 aligns across ALL of it
run       LONG    ! which contiguous stretch of label lines - columns 2+ align within one
lineNo    LONG
col       LONG    ! position of this token on its line, 1-based
seg       LONG    ! which ';'-separated segment it belongs to
tokIx     LONG
wid       LONG
gap       LONG    ! spaces before it as the author left them (col 1 = the indent)
        END
widQ    QUEUE,PRE(wq) ! widest token in each column
key       LONG    ! col 1 -> the CASE id;  col 2+ -> the run id
col       LONG
wid       LONG
        END
runQ    QUEUE,PRE(rn) ! one row per contiguous stretch
id        LONG
origMax   LONG    ! widest label line as the author left it
newMax    LONG    ! widest it would become
skip      BYTE
        END
grpQ    QUEUE,PRE(gp) ! open structures, innermost last
id        LONG
        END
x       long,auto
q       long,auto
seq     long,auto ! CASE blocks seen
runSeq  long,auto ! contiguous label stretches seen
segNo   long      ! ';'-separated segment within the current line
semQ    QUEUE,PRE(sm) ! the runs that use ';' arms - segment mode is PER RUN
id        LONG
        END
semIx   long,auto
eolRun  long,auto ! line endings since the last label line
lineSeq long,auto
lastGrp long,auto ! the CASE the previous label belonged to
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
lnCells long      ! cells on the line under test
gDelim  long,auto ! IsDelim's answer - shared by it and GlueTight
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
    if size(self.Tokens.tok) = 1 and val(self.Tokens.tok) = 10
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
        if upper(self.Tokens.tok) = 'OF' or upper(self.Tokens.tok) = 'OROF' or upper(self.Tokens.tok) = 'ELSE'
          if records(grpQ)
            get(grpQ, records(grpQ))
            if gp:id
              ! a RUN is a stretch of label lines close enough together to read as one
              ! block. EVERY column aligns within one run, never across the whole CASE.
              !   - a dispatch CASE can hold dozens of branches hundreds of lines apart, and
              !     grouping them all meant one enormous label line vetoed alignment for every
              !     short block in the same CASE (Parser.clw: 44- and 55-character blocks
              !     left ragged because a 183-character line lived elsewhere in that CASE)
              !   - and column 1 keyed on the CASE meant an isolated `of 'IF'` was padded out to
              !     match an `orof` 350 lines away that you cannot see from there. Keying column
              !     1 on the run fixes that by itself: a run with no OROF in it has a column-1
              !     width of 2, so the pad computes to a single space and nothing moves.
              ! TEN LINES is the gap that ends a run - the same window AlignComments uses. It has
              ! to be a gap rather than strict adjacency, because `of 'A' / stmt / orof 'B'` is
              ! one block to the eye and must still line up.
              ! a run NEVER spans two different CASE blocks. Do NOT try to force the break by
              ! setting eolRun to 9 when a structure opens or closes: the test is `> 10`, so it
              ! never fires, and labels from a PREVIOUS case join the next one's run. That gives
              ! `of   1` / `of   3` in a CASE with no
              ! OROF in it at all, padded to match an OROF in an earlier, unrelated CASE.
              if gp:id <> lastGrp then runSeq += 1 ; lastGrp = gp:id.
              if eolRun > 10 then runSeq += 1. ! ... and a long gap ends one inside a CASE
              inLab   = 1
              lineSeq += 1
              col      = 0
              segNo    = 1                     ! segment 1 is everything before the first ';'
              eolRun   = 0
            end
          end
        end
      end
    end
    if ~inLab then cycle.
    ! statements after a ';' ARE columns, deliberately. A CASE arm
    ! written as
    !     of 35   ; dtype = 'LONG'       ; init = ' = 0'
    !     of 36   ; dtype = 'REAL'       ; init = ' = 0'
    !     of 34   ; dtype = 'STRING(32)' ; init = ''
    ! is a table, and lining the ';' up is the point of it. An earlier cut of this stopped
    ! collecting at the ';' - that was the wrong reading of the same evidence. What made those
    ! lines come back absurdly wide was the run-spanning bug fixed above: the run reached into a
    ! DIFFERENT case whose labels were far longer, and every column was sized to suit those.
    col += 1
    do CellGap
    ! a top-level ';' starts a new SEGMENT, and is a segment of its own. See the note
    ! on segment mode below.
    if size(self.Tokens.tok) = 1 and self.Tokens.tok[1] = ';'
      segNo += 2
      curRun = runSeq                          ! mark THIS RUN as a ';' run
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

  ! ---- a gap the author did not write is not ours to invent. See GlueTight. ----
  do GlueTight

  ! ---- SEGMENT MODE. When arms are written `of 35 ; dtype = 'LONG' ; ...` the thing
  !      that has to line up is the ';' SEPARATORS, not the tokens - and an `else ; return` arm
  !      has a completely different token shape from an `of` arm, so aligning by token index
  !      pushes them further apart rather than together (of's column 2 is `35`, else's is `;`).
  !      So: if ANY label line uses a top-level ';', every cell below becomes a SEGMENT - the
  !      run of tokens between separators - instead of a single token. Nothing INSIDE a segment
  !      moves; only where each segment begins. A file with no ';' arms keeps token columns,
  !      which is what the multi-OROF tables need.
  ! segment mode is decided PER RUN, not for the whole file. Do NOT set one
  ! flag when ANY label line anywhere uses a ';': that switches every run over and collapses
  ! the multi-OROF tables (which have no ';') to one cell per line, so they stop aligning
  ! internally. A file with both shapes shows it - an `of 'VIRTUAL' orof 'DERIVED' ...` block goes
  ! ragged the moment the flag went file-wide.
  if records(semQ)
    loop q = 1 to records(cellQ)
      get(cellQ, q)
      curRun = cl:run
      do FindSem
      if ~semIx then cycle. ! a token-column run - leave it alone
      cl:col = cl:seg       ! the segment IS the column from here on
      put(cellQ)
    end
    do MergeSegments
  end

  ! ---- a label line with only ONE cell has nothing after it to line up, so it must
  !      not set a column width either. `else` on its own is the case: adding ELSE to the run
  ! so that `else ; return` could line up with `of 35 ; ...` also made a bare
  !      `else` four characters wide set column 1 for every `of` in the same CASE - and a CASE
  !      with no OROF and no ';' started coming out as `of   'PRE'` when it should not have been
  !      touched at all. Parser.clw 5374/5380. Counting cells says it directly: nothing
  !      follows a lone `else`, so it has no opinion about where anything goes.
  loop q = 1 to records(cellQ)
    get(cellQ, q)
    curLine = cl:lineNo
    do CellsOnLine          ! -> lnCells
    if lnCells < 2 then cycle.
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
  !      whole run, so a 23-line block containing 'CONVERTANSITOOEM' had every other line padded
  !      out to suit it - 79 characters became 122 (Parser.clw). Refuse that.
  !      The absolute-width clause now only applies to a run that FITS to begin with.
  !      Refusing because the result exceeds the limit is right when alignment would PUSH it
  !      over; it is wrong for a run already wider than the limit, which was being left ragged
  !      for a width problem alignment did not cause and could not fix. ----
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
      ! COLUMN 2's PAD BELONGS IN origMax, and leaving it out made this
      ! whole routine non-idempotent. PASS 3 pads column 2 WHETHER OR NOT the run is
      ! skipped - that is the pad that puts `of` under `orof`, and it is deliberate.
      ! So a run measured as written, then padded, comes back on the NEXT run two
      ! characters wider per line: origMax grows, newMax does not, and a run that
      ! failed `newMax > origMax + 20` by a hair now passes it. Columns 3+ that were
      ! refused on the first run are aligned on the second, and the file changes
      ! again for no reason a reader can see.
      !   FOUND on real code, not by reading: a corpus sweep transformed 161
      !   files and then transformed its own output, and jFiles.clw / jFilesV303.clw
      !   moved the second time - under `optimised`, so nothing to do with the style
      !   that found it. Minimal repro is TestData\alignidem.clw.
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
  end

  ! ---- PASS 3: pad each token so the next column starts one space past the widest entry in the
  !      column before it. the padding goes AFTER the keyword, not before it -
  !          of   'VIRTUAL' orof 'DERIVED' orof 'PROC'
  !          orof 'NAME'    orof 'DLL'     orof 'C'
  !      COLUMN 2 is always padded, even in a run that failed the test above: that padding is
  !      what puts the two spaces after `of` so it lines up under `orof`, it is never more than
  !      a couple of characters, and leaving it out is what was spotted on Parser.clw. ----
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
      if instring('<10>', self.Tokens.strBefore, 1, 1) or |   ! a continuation broke the line here
         size(self.Tokens.strBefore) = pad ! already exactly right
        cycle
      end
    end
    sb.setValue(all(' ', pad))
    self.SetStrBefore(cl:tokIx, sb.getValue())
    moved += 1
  end
  free(cellQ) ; free(widQ) ; free(runQ) ; free(semQ)
  return moved

! ---- whitespace immediately before the current token, since the last newline ----
!      A TAB COUNTS AS ONE, and that is an approximation made on purpose. A tab has no
!      honest width here - it depends on where the tab stops fall - but the alternative was
!      worse: breaking the loop at a tab reported a gap of ZERO where there plainly is one,
!      so a tab-indented CASE block measured its widths against a column that does not
!      exist. One is wrong by an unknown amount; zero is wrong by the whole gap and claims
!      to be exact. The sibling counter in AlignDeclTypes had the same spaces-only loop and
!      it was worse there - it misread a tab-indented STATEMENT as a column-1 declaration
!      and re-spaced live code, measured on a default run.
CellGap routine
  data
gz  long,auto
gc  string(1),auto
  code
  prevW = 0
  if self.Tokens.strBefore &= NULL then exit.
  loop gz = size(self.Tokens.strBefore) to 1 by -1
    gc = self.Tokens.strBefore[gz]
    if gc = ' ' or val(gc) = 9
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
!      TERMINATOR, so the file comes back carrying ENDs nobody wrote - a level census of
!      +1638 -1641 on output where the same file reads +1638 -1638 on input. The tool's own
!      tokenizer would disagree with what the tool had just written, and the next build would
!      be made from it.
!      So: everything between two delimiters - `of`, `orof`, `else`, `;` - folds into ONE cell,
!      the way MergeSegments already folds a `;` segment. Only where a cell BEGINS can move;
!      the spacing inside an arm is the author's and is copied through untouched.
!      This is not a restriction on the tables the feature was built for. In
!          of   'VIRTUAL' orof 'DERIVED' orof 'PROC'
!      every value is a single token with a delimiter either side, so it is its own cell
!      exactly as before and those blocks align identically.
!      A ';' run is skipped outright - MergeSegments owns it, and folding a tightly written
!      `of 35; dtype = ...` here would swallow the ';' that mode is built on. ----
GlueTight routine
  data
gz    long,auto
gw    long,auto
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
      get(cellQ, gz + 1)            ! IsDelim read the TOKEN queue - re-fix this cursor
      delete(cellQ)
    end
    get(cellQ, gkeep)
    cl:wid = gw
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
! The hard part is not the arithmetic, it is NOT MOVING THINGS THAT ALREADY AGREE. Two separate
! bugs here let a comment column drift right through a 2 -> 4 -> 2 reindent and never come
! back, both with the same shape: a decision that should depend only on the CODE was keyed to
! the state the previous pass had left behind. Group membership now forms by ADJACENCY rather
! than by current column, and the width guard measures the line as it WOULD BE at the target
! rather than as it stands.
!
! The non-oscillation argument for the pull-left is written out in full further down this
! procedure. Read it before changing anything here - it is the reasoning that keeps repeated
! runs stable, and it is not reconstructible from the code.
! ------------------------------------------------------------------------------------
VitTokenize.AlignComments  Procedure(LONG pMaxWidth)
! One pass per RUN of adjacent comment rows: find the run, compute the narrowest column that
! clears every member's code, and put the whole run there. Nothing is stepped towards, and no
! row is left where it lies - both are how a second run over the output changes nothing.
! we only move comments to the right - to avoid possible endless loop of moving left and right
st     stringTheory
! #Removed as not used: stOmit stringTheory

CmtQ queue       ! comment queue
pos      long           ! pos of start of comment ('!' or '|')
adjust   long
freeze   long           ! if first char non-space on line then don't move
kind     long           ! 1 = '!' comment, 2 = '|' continuation. Both settle in the SAME
lineLen  long           !   column; kind only decides whether a marker with nothing after it freezes.
codeEnd  long           ! column of the last non-space character before the marker, so a block
padPrev  long           !   can be pulled back LEFT without jamming a comment against its own code.
opener   long           ! this line OPENS a structure (tokenizer '+' level). It never SETS a column - a
                        !   CLASS header 126 characters wide would otherwise drag the fields under it out
                        !   to match - but it may TAKE one, so it settles with the block it sits in.
frzKind  long           ! WHY a row is frozen, because the two reasons want different treatment:
                        !   1 = it must not move at all: a full-line or margin comment (reading a TAB as
                        !       code once made these walk one column right per run, for ever), a bare '!'
                        !       with no text, or a line of dots. These ANCHOR - the column belongs to them
                        !       and the rows around them settle onto it, PROVIDED THEY CARRY THE SAME
                        !       MARKER. A '!' column and a '|' column are different things, so a change
                        !       of kind ends a run and stops a look-back, in both directions and whether
                        !       the row is an anchor or not. A PROTOTYPE is NOT one of these:
                        !       it is an `opener` above, free to take a column but never to set one.
                        !   2 = `end ! text`. It may not set a column either - one word of code says
                        !       nothing about where the block's comments belong - but it MAY take one, so
                        !       it lines up with the statements it closes instead of stranding them.
hangFrom long           ! the row this one HANGS from - a whole-line comment written in the
                        !   comment field under a trailing comment is PART of that comment, so it is a
                        !   PASSENGER: it takes the anchor's Adjust and sets nobody's column. 0 = not one.
hangLen  long           ! on the ANCHOR, the longest lineLen among its passengers. Anchor and
                        !   passengers travel by the SAME delta, so the width tests measure the wider of
                        !   the two - otherwise a run is offered a column that takes the hanging text
                        !   past the limit while the row with the code on it still fits.
     end                ! set when the marker is a '|' immediately preceded by '&'. The pair
                        !   `& |` moves as ONE unit, so the padding goes on the '&' token, not the '|'.
                        ! lineLen = the line as it stands, so an adjustment can refuse to push it over the limit.

OpenQ queue             ! lines that OPEN a structure. A CLASS/QUEUE/
opLine  long            !   GROUP header is not a member of the comment run for
      end               !   the fields inside it - it is an ANCHOR. Taken from the
                        !   tokenizer's own '+' level marks, so there is no keyword
                        !   list to keep and no width threshold to guess at.
opInCode      byte,auto ! the OpenQ walk is inside a procedure body
opIx          long      ! monotonic cursor into OpenQ - the line loop only goes forward
opTok         long,auto
x             long,auto
! #Removed as not used: y             long,auto
!prev          long,auto
! #Removed as not used: inQuotes      long,auto
svPtr         long,auto
cmtCol        long,auto
cmtLine       long,auto
! #Removed as not used: ce            long,auto                                        ! scan cursor for codeEnd
! #Removed as not used: ampPos        long,auto                                        ! first column of the operator in an `op |` pair
! #Removed as not used: ampLen        long,auto                                        ! 1 for '&', 2 for OR, 3 for AND, 0 for none
acTrim        long,auto            ! leading spaces to remove for a NEGATIVE adjust
acKeep        long,auto
ppNeed        long,auto            ! spaces an `op |` row needs before its operator
ppKeep        long,auto            !   ... and how many are there now
acZ           long,auto
pl            long,auto            ! pull-left run scan
plEnd         long,auto
plCol         long,auto
plMin         long,auto
plKind        long,auto            ! the run's marker kind - '!' and '|' do not tighten together
plNbr         long,auto            ! column of the block immediately above, 0 = none
plLast        long,auto
plTgt         long,auto            ! this row's target column
plWid         long,auto            ! the widest text this row must carry -
                                   !   its own, or its widest passenger's
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
cbNCode       long                 ! how many code tokens on the line
cbFirstU      string(vt:maxVarLen) ! its first, second and last, uppercased
cbSecondU     string(vt:maxVarLen)
cbLastU       string(vt:maxVarLen)
cbLastSz      long
cbAllDot      long                 ! every code token on it is a '.'
cbLine        long                 ! the line number being built
plWho         long,auto            ! --acdiag: which cmtQ row set plMin ...
plWhy         string(6),auto       !   ... and by which branch. The pull-left
                                   !   floor is the whole ratchet question, and
                                   !   "min 88" with no answer to "whose 88?"
                                   !   cost an evening.
plFroze       byte
hgX           long,auto            ! the hanging-comment passes
hgAnc         long,auto            !   the row a passenger hangs from
hgEnd         long,auto            !   that anchor's codeEnd - the edge of the comment field
hgLen         long,auto            !   a passenger's own line length, read before the anchor is fetched
hgAdj         long,auto            !   the anchor's Adjust, which the passenger takes
moved         long                 ! comments actually moved - the caller counts it as a change

 code
  st.free()
  svPtr = pointer(self.tokens)     ! save pointer position for restore at end
  CmtQ.adjust = 0                  ! just to be sure

  self.SetLineNumbers              ! renumber lines as doing deletes of toks and then insertString can muck these up or leave 0 line nos.

  self.joinToks(st)
!------- temp for debugging
!  self.DumpTokens() ! make sure we have a dump file on disk to use when checking warning/error messages
!  st.SaveFile('AC join before.txt')
!------- temp?
  st.split('<13,10>',,,,st:Clip)   ! decided to clip lines

  ! which lines OPEN a structure? SetLineNumbers ran above, so token lineNo
  ! and the line index below are the same numbering. Tokens are in order, so OpenQ comes
  ! out sorted and the line loop can walk it with a monotonic cursor.
  ! WHICH OPENERS ARE HEADERS, AND WHICH ARE JUST LINES. A structure opener keeps its own
  ! column and sets nobody else's, which is right for a DECLARATION header: a CLASS line 126
  ! characters wide put its comment at 128 and dragged every field comment under it out to
  ! match. It is wrong for an opener inside a procedure's CODE, where `if`, `loop` and the
  ! one-line `if x then y.` are ordinary statements whose comments belong to the block around
  ! them - treating those as headers splits an evenly-aligned procedure into three columns
  ! (VitSymbols.ArgAdmits came back at 31 / 52 / 17 where the author had one column at 52).
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
      of 'PROCEDURE' orof 'FUNCTION' orof 'ROUTINE'
        opInCode = 0
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
  cbCol = 0 ; cbCode = 0 ; cbPos = 0 ; cbKind = 0 ; cbInCmt = 0 ; cbTxt = 0
  cbNCode = 0 ; cbFirstU = '' ; cbSecondU = '' ; cbLastU = '' ; cbLastSz = 0
  cbPrevEnd = 0 ; cbAllDot = 1 ; cbLine = 1
  opIx = 1
  loop cbT = 1 to records(self.tokens)
    get(self.tokens, cbT)
    if errorcode() then break.
    ! ---- the trivia in front of this token ----
    if not self.tokens.strBefore &= NULL
      loop cbI = 1 to size(self.tokens.strBefore)
        cbCh = self.tokens.strBefore[cbI]
        if val(cbCh) = 10             ! a newline ANYWHERE closes the line
          do CbEndLine
          cycle
        end
        if val(cbCh) = 13 then cycle. ! carries no column of its own
        cbCol += 1
        if cbPos                      ! past the marker: is there TEXT?
          if cbCh <> ' ' and val(cbCh) <> 9 then cbTxt = 1.
          cycle
        end
        if cbInCmt then cycle.
        if cbCh = '!'
          cbPos = cbCol ; cbKind = 1 ; cbInCmt = 1
        elsif cbCh = '|'
          cbPos = cbCol ; cbKind = 2
        end
      end
    end
    if self.tokens.tok &= NULL then cycle.
    if size(self.tokens.tok) = 1 and val(self.tokens.tok) = 10                 ! the newline as a token of its own
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
    if cbNCode = 1 then cbFirstU = cbLastU.
    if cbNCode = 2 then cbSecondU = cbLastU.
    if cbLastU <> '.' then cbAllDot = 0.
  end
  do CbEndLine                                                                 ! and the last line, which may have
                                                                               !   no newline after it at all

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
  ! whole-line comment is a comment of its own, not the tail of one.
  !
  ! *** THIS LOOP IS THE ONLY THING THAT SETS hangFrom AND hangLen. *** Three places downstream
  ! read them - the run walk skips a passenger so it neither votes for a column nor ends a run,
  ! the width test measures the anchor against its widest passenger, and the look-back refuses
  ! to land on a row that is not settled yet. All three fail SILENTLY and identically if this
  ! loop stops running: every passenger simply reverts to being frozen where it lies while its
  ! anchor moves off without it. Nothing reports that, so it is not visible from the output of
  ! one file - only from reading two columns where there should be one.
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
    if CmtQ.Pos < 2                                                            ! code with no comment, a blank line, or a
      hgAnc = 0                                                                !   marker in column 1 - the chain ends here
      cycle
    end
    if CmtQ.codeEnd                                                            ! CODE and a comment: this row is an anchor
      hgAnc = hgX
      hgEnd = CmtQ.codeEnd
      cycle
    end
    if ~hgAnc then cycle.                                                      ! a whole-line comment hanging from nothing
    if CmtQ.Pos <= hgEnd                                                       ! at the MARGIN, not in the comment field -
      hgAnc = 0                                                                !   a comment of its own, and it ends the chain
      cycle
    end
    hgLen = CmtQ.lineLen - CmtQ.Pos + 1                                        ! its TEXT WIDTH - marker to end of line - because the
                                                                               !   passenger lands on the ANCHOR'S column, not its own.
                                                                               !   Read before the get() below moves the buffer.
    CmtQ.hangFrom = hgAnc
    put(CmtQ)
    get(CmtQ, hgAnc)
    if errorcode() then cycle.
    if hgLen > CmtQ.hangLen                                                    ! the anchor carries its WIDEST passenger
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
  ! run it again on its own output and the code is the same, so the answer is the same. An
  ! earlier design settled columns by moving each comment RIGHT to match its neighbour, one hop
  ! per pass. That could not oscillate, but it made the column a RATCHET - widen the code once
  ! and the column followed; narrow it again and nothing brought it back, so 2 -> 4 -> 2 landed
  ! two characters right of where it began, on every comment in 29 files. This pass replaced it,
  ! and the ratchet is gone because there is nothing left to accumulate.
  !
  ! WHY IT CANNOT OSCILLATE:
  !   - it runs ONCE over each run, not iteratively
  !   - the target is COMPUTED from the run (max codeEnd + 2), not stepped towards
  !   - a run containing a FROZEN row is left alone entirely. A frozen row is an anchor - the
  !     column belongs to it - and that is what "only when all its members agree" means
  !   - the answer depends on the CODE alone, so a second run over the output recomputes it
  ! ------------------------------------------------------------------------------------------
  pl = 1
  loop while pl <= records(CmtQ)
    get(cmtQ, pl)
    if CmtQ.Pos < 2 or CmtQ.freeze or CmtQ.opener                              ! a REFUSED row is an anchor, and
      pl += 1
      cycle
    end
    plCol  = CmtQ.Pos + CmtQ.Adjust
    plMin  = CmtQ.codeEnd + 2
    plWho  = pl ; plWhy = 'first'
    plKind = CmtQ.kind                                                         ! see the note below
    plFroze = 0
    plEnd  = pl
    plLast = pl                                                                ! last row that actually took part
    ! LOOK BACK FIRST. A frozen row is an anchor: it cannot move, so the column belongs to it and
    ! a run sitting just BELOW one at the same column must not be tightened away from it. Scanning
    ! FORWARD only leaves an anchor behind the cursor invisible: three CASE arms written at column
    ! 57 to match a frozen comment seven lines above get pulled back to 55 on their own, out of
    ! step with the block they belong to.
    do PullLookBack                                                            ! may set plFroze
    loop while plEnd + 1 <= records(CmtQ)                                      ! how far does this column run?
      plEnd += 1
      get(cmtQ, plEnd)
      ! a line with NO COMMENT has Pos = 0, and CmtQ holds a row for EVERY line - so
      ! this must SKIP those, so the walk `cycle`s past them. Do NOT
      ! use `break` here: that ends the run at the first uncommented line, so two comments with
      ! one plain statement between them become two runs of one, each pulled left to its own
      ! code, and they stop lining up with each other.
      if CmtQ.Pos < 2
        if plEnd - plLast > 10 then break.                                     ! ... but a long gap still ends it
        cycle
      end
      if CmtQ.hangFrom                                                         ! a PASSENGER travels with its anchor: it is neither a
        plLast = plEnd                                                         !   vote (it has no column of its own to tighten) nor a
        cycle                                                                  !   floor (it is not settled until its anchor is). It
      end                                                                      !   does not END the run either - leaving plLast behind
                                                                               !   would move every later run boundary in the file,
                                                                               !   because a run starts at the previous one plus 1.
                                                                               !   Skipped BEFORE the kind test below, or a kind-1
                                                                               !   hanging row would end a kind-2 run it sits inside.
      ! RUN MEMBERSHIP MUST NOT DEPEND ON THE CURRENT COLUMN. Write it as
      !     if CmtQ.Pos + CmtQ.Adjust <> plCol then break.
      ! and that one line is a ratchet: membership decides the run's floor (the widest
      ! member's code), the floor decides the column, and membership would be keyed on the very
      ! thing the previous pass just changed - so the answer depends on where the comments came
      ! in, not on the code. Measured on Parser.clw, the SAME rows at indent 2:
      !     leg 1  PL run 1019-1021  col 32 min 29  -> PULL 3   -> column 29
      !     leg 3  PL run 1019-1033  col 31 min 31  -> stay     -> column 31
      !     leg 1  PL run 1293-1305  col 76 min 76  -> stay     -> column 76
      !     leg 3  PL run 1293-1306  col 95 min 89  -> PULL 6   -> column 89
      ! Same code, same floors, different RUN BOUNDARIES, so different answers - and 70 of the
      ! 77 markers that differ across such a round trip sit at exactly the column the previous
      ! leg left them in. So a group is what the README says it is: comments of one kind close
      ! together, "within a ten-line window". Adjacency is a property of the SOURCE, so both
      ! legs build the same groups and compute the same column.
      if CmtQ.kind <> plKind then break.
      if CmtQ.opener                                                           ! A HEADER SETS NO FLOOR - its line is as
        plLast = plEnd                                                         !   long as the declaration happens to be, and
        cycle                                                                  !   letting it vote drags the fields under it
      end                                                                      !   out to match. But it must not END the run
                                                                               !   either: that splits one visual block in two
                                                                               !   and each half is then tightened to its own
                                                                               !   code. Vote and take are different powers,
                                                                               !   and ending a run is neither of them.
      ! only rows of the SAME KIND tighten together. A '!' comment and a '|' continu-
      ! ation settle into one shared column when they are near each other - that is deliberate,
      ! everything after either one is ignored by the compiler - but they are not the same block
      ! when it comes to giving space BACK. A continuation sits at the end of a long statement,
      ! a comment at the end of a short declaration, and the run can only tighten as far as its
      ! widest member's code allows. On ParserV2 two declaration comments at column 80
      ! could move back only THREE characters, because a wrapped `if` two lines below happened to
      ! put its '|' in the same column and its code ran to 75. --acdiag reported `adj -3` where I
      ! expected -49, which is what pointed at the member rather than the mechanism.
      ! a frozen row is an anchor for the WHOLE block, so it is INCLUDED in the run
      ! and does not end it. Break here and the rows after the anchor start a fresh run with no
      ! anchor in it, and that one gets pulled left on its own - which is how three CASE arms
      ! land at column 56 while the commented lines above and below them stay at 58.
      ! AN ANCHOR RAISES THE GROUP'S FLOOR; IT DOES NOT VETO THE GROUP. A frozen row cannot
      ! move, so the group simply cannot tighten past it - which is a floor, and says so. A
      ! veto is too blunt: it also stops a group that has merely been PUSHED onto an anchor's
      ! column from ever coming back, and that is one of the two shapes the
      ! ratchet took. Treating it as a floor keeps every case the veto was protecting (the group
      ! still cannot leave its anchor) while letting everything else settle where the code says.
      if CmtQ.freeze and CmtQ.frzKind <> 2                                     ! an `end ! text` row raises NO floor - its own
                                                                               !   one word of code says nothing about where the
                                                                               !   block's comments belong
        if CmtQ.Pos + CmtQ.Adjust > plMin
          plMin = CmtQ.Pos + CmtQ.Adjust
          plWho = plEnd ; plWhy = 'frozen'
        end
      elsif CmtQ.codeEnd + 2 > plMin
        plMin = CmtQ.codeEnd + 2
        plWho = plEnd ; plWhy = 'code'
      end
      plLast = plEnd
    end
    plEnd = plLast                                                             ! the run ends at its last MEMBER
    ! land on the block above if there is one and it clears our code
    if plNbr and plNbr > plMin then plMin = plNbr ; plWho = 0 ; plWhy = 'nbr'. ! the block above is a floor too, not a ceiling
    ! --acdiag REPORTS THE PULL-LEFT DECISION, which is the one that decides whether a block
    ! can give space back - i.e. whether 2 -> 4 -> 2 returns. Measured on Parser.clw: of 77
    ! markers that differ across the round trip, 70 sit at EXACTLY the column out4 left them
    ! in, so the pull is declining 70 times and nothing said why.
    if self.acDiag
      self.TraceIt('PL run ' & pl & '-' & plEnd & ': col-in ' & plCol & ' min ' & plMin & |
                   ' kind ' & plKind & ' nbr ' & plNbr                                  & |
                   choose(plFroze = 1, ' has-anchor', '')                               & |
                   choose(plMin >= plCol, ' no-room-vs-first', '')                      & |
                   ' -> col ' & plMin & ' [set by row ' & plWho & ' via ' & clip(plWhy) & ']')
    end
    if plMin >= 2
      loop x = pl to plEnd
        get(cmtQ, x)
        if CmtQ.Pos < 2                                                                or |   ! no comment on this line - nothing to move
           CmtQ.freeze and CmtQ.frzKind <> 2                    ! an anchor set the floor and does not move.
          cycle
        end
                                                                !   An `end ! text` row set no floor, so it is free to
                                                                !   be SET to the block's column HERE - and only here.
                                                                !   Nothing may move it afterwards: that path caps a
                                                                !   total move at 40 columns, so whether it could join
                                                                !   would depend on where it started, and the 2-4-2
                                                                !   round trip stopped returning (8 files, not 3).
                                                                !   `end ! text` is not one: it sets no floor, so
                                                                !   it is free to land on the block's column.
        ! SET the column rather than shifting by a common delta. The group's members do not
        ! have to arrive sharing a column - requiring that is the ratchet - so there is no
        ! single delta to apply. plMin is the floor every member cleared, so every member goes
        ! there, and the answer depends only on the code.
        ! THE WIDTH TEST MUST NOT LOOK AT WHERE THE COMMENT CURRENTLY IS. The first
        ! cut of it read `CmtQ.lineLen <= pMaxWidth` - a cap that only
        ! blocks a line which FITS - and lineLen is the line AS IT STANDS, padding and all. So
        ! the same row answered differently on the two legs of the round trip:
        !   leg 1  comment at col 28, line 116 long, fits -> cap applies -> refuses the move
        !   leg 3  comment at col 125, line 213 long, already over -> cap does not apply ->
        !          the row is set to 125 and stays there
        ! Same code, same group, same target of 125, opposite outcomes - the ratchet again, one
        ! layer down from the one fixed before it.
        ! What is invariant is the marker and its text: lineLen - Pos does not depend on the
        ! padding in front of it. So measure the line AS IT WOULD BE at the target, and when it
        ! will not fit, put the row at its OWN floor instead of the group's. That is still
        ! decided entirely by the code, so both legs agree; and a comment too long to sit at
        ! the shared column sits as far left as it can rather than being left where it lay.
        plTgt = plMin
        ! A HEADER JOINS THE BLOCK'S COLUMN ONLY WHEN THAT COLUMN CLEARS ITS OWN CODE, and
        ! takes its own floor when it does not - it never comes left of its own declaration.
        !
        ! IT MUST NOT SIMPLY BE LEFT WHERE IT LIES. A header's own floor cannot move under a
        ! reindent, because a header is only ever marked outside executable code - but plMin
        ! belongs to the RUN, and a run is adjacency within a ten-line window, which does not
        ! stop at the end of a procedure. So a run can hold an executable row whose floor DOES
        ! move, this comparison can fall either side of the line between one indent and the
        ! next, and a row left where it lay would keep whichever column the other leg gave it.
        ! Every arm here computes a column from the code, and that is what makes 2 -> 4 -> 2
        ! come back. TestData\openerrt2.clw is such a run, sized to land either side.
        if CmtQ.opener and plTgt < CmtQ.codeEnd + 2
          plTgt = CmtQ.codeEnd + 2
        end
        ! MEASURE THE WIDEST TEXT THIS ROW CARRIES, which is not always its own. An anchor's
        ! passengers travel to the anchor's column, so a column that fits the anchor can still
        ! take a hanging row past the limit - and the passenger has no say of its own, having
        ! already been told where it lands. hangLen is the widest passenger measured from its
        ! marker to end of line; the anchor's own is one less than that, being measured from
        ! the marker exclusive, so the two are compared in the same units here.
        plWid = CmtQ.lineLen - CmtQ.Pos
        if CmtQ.hangLen - 1 > plWid then plWid = CmtQ.hangLen - 1.
        if pMaxWidth > 0 and plTgt + plWid > pMaxWidth
          plTgt = CmtQ.codeEnd + 2                              ! cannot join - its own floor
          if plTgt < 2 then plTgt = 2.
        end
        CmtQ.Adjust = plTgt - CmtQ.Pos
        put(cmtQ)
      end
    end
    pl = plEnd + 1
  end

  ! ---- THE PASSENGERS TRAVEL ----------------------------------------------
  ! Every column has now been decided - each run has been put where its code says it goes -
  ! so a passenger can now be told where its anchor went.
  ! It lands on the anchor's COLUMN, and the first cut of this took the anchor's ADJUST instead -
  ! on the argument that a hanging row written one character left of the row above (36 under
  ! 37, in one real file) is the author's own offset and should survive. The fixture
  ! refused that: AlignDeclTypes runs BEFORE this routine and had re-columned the declaration,
  ! moving the anchor's marker one right, so the delta preserved a stagger the author never
  ! wrote - anchor at 73, its own two rows at 72. Landing on the column cannot do that, and the
  ! real files agree it is what authors mean: VitRules.inc 178-185 and VitEngine.inc 155-159 both
  ! have anchor and hanging rows written at exactly the same column. The indentation INSIDE a
  ! hanging comment ('!   this one') is text after the marker and survives either way.
  ! It works whichever way the anchor moved, which matters - both directions are real, and the
  ! pull-left one only shows up on files whose comments sit far right of short code.
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
    hgAdj = CmtQ.Pos + CmtQ.Adjust                              ! the anchor's FINAL column
    get(CmtQ, hgX)
    if errorcode() then cycle.
    if hgAdj = CmtQ.Pos then cycle.                             ! already there - nothing to move
    CmtQ.Adjust = hgAdj - CmtQ.Pos
    put(CmtQ)
  end

  ! ---- DIAGNOSTIC, --acdiag only. Transforms nothing. Runs LAST, after the pull-left
  !      pass, so it reports the state that actually reaches the file. Placed BEFORE the
  !      pull-left it reports everything as fine - true at that point, and useless, because the
  !      lines it stays silent about are exactly the ones moved afterwards.
  !      Three times now this arithmetic has been read as correct and three times the output has
  !      disagreed, so this reports what it actually decided per line instead of what it looks
  !      like it should decide. For every row that ends up at a DIFFERENT column from the row
  !      above it, print both, and the reason it could not be moved. Read the two columns and
  !      the reason together - a row that says `frozen` when it plainly has code before its
  !      comment means the freeze rule is wrong; one that says `window` means the 10-line rule
  !      is.
  if self.acDiag
    cmtCol = 0 ; cmtLine = 0
    loop x = 1 to records(CmtQ)
      get(cmtQ, x)
      if CmtQ.Pos < 2 then cycle.
      if cmtLine and CmtQ.Pos + CmtQ.Adjust <> cmtCol
        self.TraceIt('AC line ' & x & ': col ' & (CmtQ.Pos + CmtQ.Adjust)    & |
                     ' but line ' & cmtLine & ' is at ' & cmtCol             & |
                     ' - pos ' & CmtQ.Pos & ' adj ' & CmtQ.Adjust            & |
                     ' codeEnd ' & CmtQ.codeEnd & ' lineLen ' & CmtQ.lineLen & |
                     ' kind ' & CmtQ.kind                                    & |
                     choose(CmtQ.freeze = 1, ' FROZEN', '')                  & |
                     choose(x - cmtLine > 10, ' OUT-OF-WINDOW', '')          & |
                     choose(pMaxWidth > 0 and CmtQ.lineLen + (cmtCol - CmtQ.Pos - CmtQ.Adjust) > pMaxWidth, ' CAPPED', ''))
      end
      cmtCol  = CmtQ.Pos + CmtQ.Adjust
      cmtLine = x
    end
  end

  ! now adjust comment positions in tokens Q
  loop x = 1 to records(CmtQ)
    get(cmtQ,x)
    ! *** NORMALISING AN `op |` GAP USED TO BE CONDITIONAL ON A MOVE, and that is what kept
    ! VitRegex.clw 2525 off the round trip: it read `or   |` on the leg that left the row alone
    ! and `or |` on the leg that moved it. Making it unconditional was tried once and BACKED OUT,
    ! because normalising SLID THE '|' two columns left and broke three lines in vitTokenize.clw
    ! to fix one here. The reason it slid: Pos was a GUESS at the column the '|' would have once
    ! the gap was squeezed, while the padding went on the OPERATOR - so a row's column and the
    ! text it was computed from disagreed, and the apply could only give back whitespace that
    ! happened to be there (`acTrim > acKeep - 1` below).
    ! Pos is now the '|' WHERE IT IS, and the operator is placed from it: the gap in front of
    ! the operator is Pos + Adjust - codeEnd - 1, decided by the code and the target and nothing
    ! else. Squeezing therefore never moves a '|' - the slack goes in front of the operator -
    ! so it is safe on EVERY such row, and both legs write the same text. ***
    ! A padPrev row comes through even when it is NOT moving: its gap is normalised from the
    ! CODE, so a row that stays put still gets the same text on both legs of a round trip. That
    ! is what the earlier attempt at this line was reaching for; it failed because normalising
    ! MOVED the '|' two columns left. It no longer does - the slack goes in front of the operator.
    if ~CmtQ.Adjust and ~CmtQ.padPrev then cycle.
    if ~CmtQ.Pos then self.TraceIt('VitTokenize.AlignComments: unexpected lack of comment pos on line ' & x);cycle.

! vers1: following code did not allow for breaks in line numbers where there is a complete comment line
!    self.Tokens.lineNo = x+1  ! get first token of line after
!    get(self.tokens,self.Tokens.lineNo)

! vers2: following code mucked up other things - perhaps because the sort is not "stable"
!    sort(self.tokens, +self.Tokens.lineNo)
!    clear(self.tokens)
!    self.Tokens.lineNo = x+1  ! get first token of line after
!    get(self.tokens,position(self.tokens))  ! do this to allow for breaks in line numbers where there is a complete comment line

! vers3: first try vers 1 then if fails start at current line number and read forward until line number changes
    self.Tokens.lineNo = x+1                                    ! get first token of line after
    get(self.tokens,self.Tokens.lineNo)
    if errorcode()
      self.Tokens.lineNo = x                                    ! get first token of curr line
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
      get(self.tokens,records(self.tokens))                     ! get last record
    else
      get(self.tokens,pointer(self.Tokens)-1)                   ! get previous record to get last token on line x
      if errorcode() then get(self.tokens,1).                   ! get first token line
    end
    if errorcode() then self.TraceIt('unexpected error getting last token record for line ' & x & ' Errorcode = ' & errorcode()).
    if self.tokens.LineNo <> x then self.TraceIt('VitTokenize.AlignComments: did not find last token on line - ' & x & ' line=' & self.tokens.LineNo);cycle.

    if not self.tokens.tok &= NULL and self.tokens.tok = '<10>' ! EOL; the null test first - tok is a reference and may be unset
      if self.Tokens.strBefore &= null
        self.TraceIt('VitTokenize.AlignComments: did not find comment #1 on line ' & x)
        cycle
      end
    elsif CmtQ.padPrev and not self.tokens.tok &= NULL and |
          (self.tokens.tok = '&' or upper(self.tokens.tok) = 'AND' or upper(self.tokens.tok) = 'OR')
      ! `& |` moves together. The '|' lives in the NEXT token's leading trivia, so
      ! padding that token would slide the '|' right and leave the '&' behind. Pad the '&'
      ! instead - the '|' sits one space after it and comes along.
      ! and squeeze the gap between them to ONE space, so the '&' column is fixed
      ! relative to the '|' column and lining one up lines up the other.
      do NormaliseAmpGap
    else
      get(self.tokens,pointer(self.Tokens)+1)            ! get next record
      if errorcode() or not self.Tokens.firstOnLine
        self.TraceIt('VitTokenize.AlignComments: did not find comment #2 on line ' & x)
        cycle
      end
    end
    ! Adjust can be NEGATIVE - the pull-left pass computes one whenever a block can
    ! give space back. `all(' ', -2)` is an empty string, so for the whole life of the pull-left
    ! pass every leftward move was computed, logged, and then silently thrown away here: the
    ! lines simply stayed where they naturally fell. That is what made the CASE arms sit at 56
    ! while the commented lines around them sat at 58 - not a run-grouping fault at all, which
    ! is where I looked three times. --acdiag reporting `adj -2` on a line the file showed
    ! UNMOVED is what finally separated "decided" from "applied".
    if CmtQ.padPrev
      ! AN `op |` ROW IS PLACED, NOT NUDGED. Everything else here moves by a DELTA, which is
      ! fine when the thing being padded is the marker itself. For one of these the padding
      ! goes on the OPERATOR while the column belongs to the '|' two characters past it, and a
      ! delta then depends on the gap the author happened to leave. Compute the gap instead:
      ! the layout is [code][gap][operator][one space][|], the '|' is to land at Pos + Adjust,
      ! and codeEnd already carries the operator, so gap = Pos + Adjust - codeEnd - 1. That is
      ! decided by the CODE and the target alone, so both legs of a round trip write the same
      ! text - which is the whole point, and why this runs even when Adjust is 0.
      ppNeed = CmtQ.Pos + CmtQ.Adjust - CmtQ.codeEnd - 1
      if ppNeed < 1 then ppNeed = 1.                     ! one space is the floor, always
      ppKeep = 0
      loop acZ = 1 to size(self.Tokens.strBefore)        ! anything but spaces in there and this
        if self.Tokens.strBefore[acZ] <> ' ' then break. !   is not the simple mid-line gap this
        ppKeep += 1                                      !   arithmetic describes - leave it alone
      end
      if ppKeep = size(self.Tokens.strBefore) and ppNeed <> ppKeep
        self.SetStrBefore(pointer(self.Tokens), all(' ', ppNeed))
        moved += 1
      end
    elsif CmtQ.Adjust > 0
      self.SetStrBefore(pointer(self.Tokens),all(' ',CmtQ.Adjust) & self.Tokens.strBefore)
      moved += 1
    else
      acTrim = -CmtQ.Adjust                              ! how many leading spaces to give back
      acKeep = 0
      loop acZ = 1 to size(self.Tokens.strBefore)        ! ... but only ones that are really there
        if self.Tokens.strBefore[acZ] <> ' ' then break.
        acKeep += 1
      end
      if acTrim > acKeep - 1 then acTrim = acKeep - 1.   ! never close the gap completely
      if acTrim > 0
        self.SetStrBefore(pointer(self.Tokens), |
                          self.Tokens.strBefore[acTrim + 1 : size(self.Tokens.strBefore)])
        moved += 1
      end
    end
  end
!---- for debugging
! self.joinToks(st)
! st.SaveFile('AC join after.txt')
! stop('have done AC joint after.txt')
!----
  get(self.Tokens,svPtr) ! restore queue to previous state
  return moved

! ---- leave exactly one space between the '&' just processed and the '|' that follows
!      it in the NEXT token's leading trivia. Called with the queue positioned on the '&'. ----
! ---- write the run's ceiling into every member of it ----------------------
NormaliseAmpGap routine
  data
ngSv  long,auto
ngZ   long,auto
ngSp  long,auto
  code
  ngSv = pointer(self.Tokens)
  get(self.Tokens, ngSv + 1)
  if ~errorcode() and not self.Tokens.strBefore &= NULL
    ngSp = 0
    loop ngZ = 1 to size(self.Tokens.strBefore) ! count the spaces in front of the '|'
      if self.Tokens.strBefore[ngZ] <> ' ' then break.
      ngSp += 1
    end
    if ngSp > 1 and ngZ <= size(self.Tokens.strBefore)
      if self.Tokens.strBefore[ngZ] = '|'       ! only when it really is the continuation
        self.SetStrBefore(ngSv + 1, ' ' & self.Tokens.strBefore[ngZ : size(self.Tokens.strBefore)])
      end
    end
  end
  get(self.Tokens, ngSv)

! ---- look at what sits just ABOVE the run: a frozen anchor at our own column vetoes the pull,
!      and a block at a DIFFERENT column is what we should be coming back to join. ----

! ---- close the physical line: classify it and add its row -----------------------------------
! FREEZE says the row may not move; frzKind says why, because the two reasons want different
! treatment further down.
!   1 = it must not move at all: a full-line comment, a bare '!' with nothing after it, a line
!       of dots. These ANCHOR - the column belongs to them.
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
  if cbPos
    if ~cbCode                                                  ! nothing but whitespace before it
      CmtQ.freeze = 1 ; CmtQ.frzKind = 1
    elsif cbKind = 1 and ~cbTxt               ! a bare '!' with no text
      CmtQ.freeze = 1 ; CmtQ.frzKind = 1
    elsif cbAllDot and cbNCode                ! a line of dots
      CmtQ.freeze = 1 ; CmtQ.frzKind = 1
    elsif cbNCode = 1 and cbFirstU = 'END'    ! `end ! text`
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
    if cbSecondU = 'PROCEDURE' or cbSecondU = 'FUNCTION' ! a prototype is a header too
      CmtQ.opener = 1
    end
    if cbKind = 2 and (cbLastU = '&' or cbLastU = 'AND' or cbLastU = 'OR')
      CmtQ.padPrev = 1
      CmtQ.codeEnd = cbPrevEnd + 1 + cbLastSz ! as if the gap were one space
    end
  end
  add(CmtQ)
  cbLine += 1
  cbCol = 0 ; cbCode = 0 ; cbPos = 0 ; cbKind = 0 ; cbInCmt = 0 ; cbTxt = 0
  cbNCode = 0 ; cbFirstU = '' ; cbSecondU = '' ; cbLastU = '' ; cbLastSz = 0
  cbPrevEnd = 0 ; cbAllDot = 1

PullLookBack routine
  data
lb  long,auto
sv  long,auto
  code
  sv = pointer(CmtQ)
  plNbr = 0
  loop lb = pl - 1 to 1 by -1
    if pl - lb > 10 then break. ! the same 10-line window a run uses
    get(CmtQ, lb)
    if errorcode() then break.
    if CmtQ.Pos < 2 or |   ! no comment on that line - keep looking
       CmtQ.hangFrom                                          ! a PASSENGER's column is not settled yet, so it
      cycle
    end
                                                              !   is not the block to land on - keep looking up, and the
                                                              !   next thing found is its own anchor, which IS settled
    ! A DIFFERENT MARKER IS NOT OUR BLOCK, BUT IT IS NOT A WALL EITHER - KEEP LOOKING UP.
    ! A '!' row and a '|' row do not tighten together, and the run walk still ends a run at a
    ! change of kind for the reason recorded there: a wrapped statement's '|' sits at the end of
    ! long code, and letting it into a run of declaration comments raises the floor so the whole
    ! block can barely give any space back. That is about MEMBERSHIP, and it stands.
    ! Landing is a different power. Breaking here as well made a single '|' row a WALL: the rows
    ! below it could not see the column established above it, so one comment continued across a
    ! wrapped condition came out in three columns - the heading and its first rows on the block's
    ! column, the wrapped row on its own, and every row after it tightened to its own code as
    ! though nothing preceded it. Skipping instead is the same treatment a passenger gets above,
    ! and for the same reason: this row is not the thing to land on, so look past it.
    ! WHY THIS CANNOT TIGHTEN ANYTHING FURTHER LEFT: plNbr is only ever taken when it is GREATER
    ! than the floor already computed, so finding a block that was previously hidden can raise a
    ! run's floor and never lower it. The failure direction is a run that gives back less space
    ! than it might, not one that jams a comment against its code.
    ! The 10-line window still bounds the walk, and an opener still stops it.
    if CmtQ.kind <> plKind
      cycle
    end
    if CmtQ.opener                                            ! the line above OPENS a structure, so it is
      break
    end
                                                              !   a header, not the block we should land on. Letting a
                                                              !   CLASS/QUEUE header be the floor candidate is how the
                                                              !   fields under it kept its column even after the run
                                                              !   itself stopped including it.
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
    plNbr = CmtQ.Pos + CmtQ.Adjust
    if CmtQ.freeze then plFroze = 1.
    break
  end
  get(CmtQ, sv)


!==================
VitTokenize.FindNotInLiteralOrComment PROCEDURE  (stringTheory pSt, string pNeedle,long pStartCol, long pNoCase) !,long ! Declare Procedure
! added here from vtxadiff GCR 23Sep2023
x        long,auto
inQuotes long
  code
  ! note we assume we have a single line of code.
  x = 1
  loop
    pStartCol = pSt.instring(pNeedle,,pStartCol,,pNoCase)
    if ~pStartCol then return 0.                              ! not found
  ! scan along line until we reach pPos
    loop x = x to pStartCol - 1
      if inquotes
        if pSt.valuePtr[x] = ''''                             ! endquote
          inquotes = false
        end
      else
        case val(pSt.valuePtr[x])
        of 39                                                 !val('''') ! startquote
          inquotes = true
        of 33 orof 124                                        ! val('!') orof val('|') ! rest of line is a comment
          return 0                                            ! not found as rest of line is in a comment
!        of 13 orof 10
!          stop('unexpected line break in VitTokenize.FindNotInLiteralOrComment')
        end
      end
    end
    if ~inQuotes then return pStartCol.                       ! found and not in quotes or comment
    pStartCol += 1
    x = pStartCol
  end
