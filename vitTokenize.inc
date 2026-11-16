! Vitesse Tokenize Class 29Sep2019
!
! (c) 2019-2026 Geoffrey C. Robinson.
! Released under the MIT License - see LICENSE.
!
! scans Clarion source and breaks into tokens in a queue
! requires StringTheory from Capesoft
!
vt:maxVarLen          EQUATE(255)                                                      ! was 50, which TRUNCATED longer labels - and since the vars queue is
                                                                                       ! KEYED on varName, two labels sharing their first 50 chars merged into one row
                                                                                       ! and the second one's type was filed against the first. 255 is past Clarion's limit.

vt:label              EQUATE('b')
vt:literal            EQUATE('''')                                                     ! was L but changed to ' 27Aug2021 so no confusion with Long
vt:decPoint           EQUATE('d')
vt:plusMinus          EQUATE('p')
vt:multiplication     EQUATE('m')
vt:exponentiation     EQUATE('^')
vt:Integer            EQUATE('I')
vt:NumericWithDecPt   EQUATE('N')
vt:end                EQUATE('e')                                                      ! could be END or end etc. or '.'
vt:dot                EQUATE('.')                                                      ! used when checking for 'End' type dots
vt:reservedWord       EQUATE('r')
!------
! variable types eg. String, Long, StringTheory etc
vt:String             EQUATE('S')
vt:CString            EQUATE('C')
vt:PString            EQUATE('P')
vt:AString            EQUATE('A')
vt:Any                EQUATE('a')
vt:PDecimal           EQUATE('n')                                                      ! was 'p', which COLLIDED with vt:Procedure - a PDECIMAL variable and a
                                                                                       ! PROCEDURE label were indistinguishable downstream. 'n' was free ('D' is vt:Decimal).
vt:Decimal            EQUATE('D')
vt:StringTheory       EQUATE('s')
vt:Long               EQUATE('L')
vt:ULong              EQUATE('U')
vt:Byte               EQUATE('B')
vt:Real               EQUATE('R')
vt:Short              EQUATE('H')
vt:UShort             EQUATE('h')
vt:Procedure          EQUATE('p')                                                      ! keeps 'p'; vt:PDecimal moved instead (fewer sites to disturb)
vt:Routine            EQUATE('r')
vt:Map                EQUATE('M')
vt:Group              EQUATE('g')
vt:Class              EQUATE('c')
vt:Queue              EQUATE('q')
vt:Equate             EQUATE('e')
vt:Like               EQUATE('l')
vt:File               EQUATE('f')
vt:Key                EQUATE('k')
vt:Blob               EQUATE('b')
vt:Memo               EQUATE('m')
vt:Date               EQUATE('d')
vt:Time               EQUATE('t')
vt:View               EQUATE('v')
vt:SReal              EQUATE('E')
vt:Window             EQUATE('w')
vt:BFloat4            EQUATE('o')
vt:BFloat8            EQUATE('O')


TokenQType            QUEUE,TYPE
lineNo                  long
firstOnLine             byte                                                           ! true/false - is this the first token on this line?
strBefore               &STRING
tok                     &STRING
type                    STRING(1)                                                      ! see equates above: I=integer,N=numeric with dec pt,'=literal 'ABC', d=dec point,
                                                                                       ! p=Plus type (+-),m=Multiplication type (*/%),b=laBel
varType                 STRING(1)                                                      ! see equates above: s=StringTheory S=String L=Long B=Byte R=Real D=Decimal etc
level                   STRING(1)                                                      ! code "indent" level. + for if/group, - for end/., / for else elsif
                      END

searchQType           queue,type                                                       ! used when searching for a particular sequence of tokens
noCase                  long                                                           ! case insensitive search for this token?     true/false
wsBefore                long                                                           ! can there be white space before the token?  true/false
tok                     &STRING                                                        ! the token to search for
                      end

VarTypeQType          QUEUE,TYPE
varName                 STRING(vt:maxVarLen)
varTypes                STRING(32)                                                     ! an array in case diff values see equates above: s=StringTheory S=String L=Long B=Byte R=Real D=Decimal etc
                      END

NoteQType             QUEUE,TYPE                                                       ! one row per note InsertStringAtEOL adds while one rule is being applied - see NoteInOrder
lineNo                  long                                                           !   the line the note went on, as numbered when it went in
siteTok                 long                                                           !   the token the note was asked for - where its match sat
                      END

TokLineMapQType       QUEUE,TYPE                                                       ! record N = current-text line N -> ORIGINAL source line
srcLn                   LONG
                      END


VitTokenize         CLASS,TYPE,MODULE('VitTokenize.clw'),LINK('VitTokenize.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode) !,_ABCLinkMode_),DLL(_ABCDllMode_)
tokens                 &TokenQType
vars                   &VarTypeQType,private
searchQ                &searchQType, private
searchSt               &stringTheory,private
!reservedSt             &stringTheory,private

sepChar                string(1)
noCaseChar             string(1)
wsBeforeChar           string(1)

fileSize               LONG                                                            ! size of file read in
separatorA             BYTE,DIM(256)                                                   ! note separator is a RESERVED word hence added 'A'
delimiter              BYTE,DIM(256)
operator               BYTE,DIM(256)

ignoreOmittedCode      BYTE(1)                                                         ! option to ignore or process omitted code Note: ignoring omitted code means more vars #remove'd etc
midLine                BYTE                                                            ! this tokenizer is parsing a FRAGMENT spliced mid-line, so it has no column 1 at all
mergeTail              BYTE                                                            ! ParseText ended on `a.b` with no token after it - the merge waits for the token that follows (InsertString)
traceIt                BYTE                                                            ! turn on to start logging to debugOutput
logIt                  BYTE                                                            ! turn on to start logging to log file
stopIt                 BYTE                                                            ! turn on to give STOP() messages
acDiag                 BYTE                                                            ! --acdiag - report why AlignComments left each comment where it is
cmtGap                 LONG(1)                                                         ! --cmtgap=<n> - spaces between the code and the marker. 1 is the shipped behaviour
alignLimit             LONG                                                            ! --cmtlimit=<n> - a comment column never goes past column n to line anything up. 90 if not given
alignSlack             LONG                                                            ! --cmtslack=<n> - a block with nothing under the limit: widest within n of its narrowest. 60 if not given
alignOutlier           LONG                                                            ! --cmtoutlier=<n> - a floor more than n past the block's MIDDLE does not set the column. OFF unless given
declOutlier            LONG                                                            ! --decloutlier=<n> - a label more than n past the block's MIDDLE name does not set the type column. OFF unless given
cmtReach               LONG(3)                                                         ! --cmtreach=<n> - the reach: how much wider than the widest line that sets a column a neighbour may be and still move it. 3
cmtInner               LONG(12)                                                        ! --cmtinner=<n> - the reach for a plain line lying BETWEEN two commented rows of a run, which is inside the column they share. 0 = it never lifts the column
cmtFloor               BYTE                                                            ! --cmtfloor= - does a plain line set a floor: 0 near (touching a commented line, in reach), 1 commented (never, save a wrapped statement's last line), 2 all
contBracket            BYTE(1)                                                         ! --contindent=bracket - ON by default: a break inside a bracket starts its continuation one past that bracket, under the first argument, the column decided once per statement (BracketPlan, see ApplyBreak). --contindent=indent: every continuation takes the indent plus two
cmtKeep                BYTE(1)                                                         ! --cmtkeep=aligned - a GROUP of neighbouring comments that already share one column which still clears every one of them is left exactly as it is. ON by default
cmtOpBar               BYTE                                                            ! --cmtop=bar - the AND/OR/& before a bar ends one space before the bar (0 = anchored to the code, two past the widest carrier)
cmtEndCount            BYTE                                                            ! --cmtend=count - an `end ! text` row also counts towards the block column (0 = it only takes the column)
cmtBarCmt              BYTE                                                            ! --cmtbar=comment - on a line carrying BOTH a '|' and a '!', the '!' owns the shared column and the '|' sits in front of it. 0 = the '|' owns it, as shipped
cmtContNone            BYTE                                                            ! --cmtcont=none - a whole-line comment whose text is indented after the ! is NOT the continuation of the one above (0 = it is)
cmtRun                 LONG(10)                                                        ! --cmtrun=<n> - how far back a line looks for the comment column it joins - the look-back in PullLookBack, NOT the case-label window. 10
cmtSplitOnly           BYTE                                                            ! --cmtsplit=<n> - WrapComments cuts rows over the width and never joins rows back (0 = split and join, --cmtwrap)
contOp                 BYTE                                                            ! BUILTIN ContOp - 0 keep, 1 end, 2 front, 3 flush. The splitter and the aligner must know which side of a break the AND/OR/& sits on, or they spell it the other way from the pass
LogFn                  STRING(256)
dumpFailed             BYTE                                                            ! the last DumpTokens save FAILED. TraceIt and the log both ship OFF, so without
                                                                                       !   this a caller had no way to know the dump it asked for was never written.

lineMap                &TokLineMapQType                                                ! current-text line -> ORIGINAL source line; maintained only while mapOn (preview)
lineMap2               &TokLineMapQType                                                ! MapFold compose scratch (owned)
noteQ                  &NoteQType                                                      ! the notes added while one rule is being applied, so several on one line come out in source order (owned; emptied by SetLineNumbers)
ppTerms                &StringTheory                                                   ! the OMIT/COMPILE terminator strings of the file that END IN A BLANK OR A TAB, one per line (owned; ParseText fills it). The
                                                                                       !   pre-processor matches a terminator byte for byte, so ClipLines leaves the tail of a line holding one of them alone
mapOn                  BYTE                                                            ! armed by MapInit (TransformText preview only); CLI/batch never sets it -> zero cost there
tLineNums              LONG                                                            ! --timing: clock ticks spent in SetLineNumbers this file, and how many calls
nLineNums              LONG

! methods...
Construct              Procedure()
Destruct               Procedure()
FreeToks               Procedure(),virtual                                             ! free the entries in the tokens queue
FreeSearchQ            Procedure(),virtual                                             ! free the entries in the search queue
Records                Procedure(),LONG,virtual                                        ! returns number of records in tokens queue

ParseText              Procedure(STRING pfileName),virtual                             ! read file in to Tokens queue
ParseText              Procedure(StringTheory st,<string pFileName>,LONG pMergeLabels=FALSE),virtual ! put contents of ST in to Tokens queue
SetLineNumbers         Procedure(),virtual                                             ! set or update line numbers in self.tokens queue (folds the line map FIRST when mapOn)
MapInit                Procedure(),virtual                                             ! identity line map sized from the CURRENT stream (same line-count rule as SetLineNumbers); arms mapOn
MapFold                Procedure(),virtual                                             ! compose the stream's new-line->old-line structure into lineMap; MUST run before anything restamps lineNo
MapLine                Procedure(LONG pLn),LONG,virtual                                ! translate a CURRENT (last-stamp) line number to its ORIGINAL source line via lineMap; identity when mapOn is off (CLI) or out of range
CheckLevels            Procedure(),virtual                                             ! warn if levels go -ve (mismatched "end")
FindFirstTokOnLine     Procedure(LONG pLineNumber),LONG,virtual                        ! returns tokNumber or 0 if fails
!FindLastTokOnLine      Procedure(LONG pLineNumber),LONG,virtual ! returns tokNumber or 0 if fails

WriteText              Procedure(STRING pfileName),long,proc,virtual                   ! format output from tokens
JoinToks               Procedure(LONG pStart=1, LONG pEnd=0),STRING,virtual            ! return join tokens
JoinToks               Procedure(StringTheory st, LONG pStart=1, LONG pEnd=0),virtual  ! join tokens queue into ST
TokenIsAllDigits       Procedure(),LONG,virtual
TokenIsDecimal         Procedure(),LONG,virtual
TokenIsValidLabel      Procedure(),LONG,virtual
TokenIsReservedWord    Procedure(),LONG,virtual
TokenIsDataType        Procedure(),LONG,virtual
TokenType              Procedure(),virtual

InsertString           Procedure(LONG pPos=1, StringTheory in, BYTE pMid=0),virtual    ! tokenize and insert at a position. pMid=1 says the text is a FRAGMENT
InsertString           Procedure(LONG pPos=1, STRING in, BYTE pMid=0),virtual          !   and not the start of a line, so a leading reserved word stays one

MoveTok                Procedure(LONG pSrc, LONG pDst),LONG,proc,virtual               ! returns st:ok or st:notOK
MoveToks               Procedure(LONG pSrc, LONG pDst, LONG pNumToMove),LONG,proc,virtual ! returns st:ok or st:notOK

GetTok                 Procedure(LONG pTokNumber),STRING,proc,virtual
BufColOne              Procedure(),LONG,virtual                                        ! the buffered token stands in column 1 - no trivia in front, or trivia ending at a line feed (a folded OMIT block)
GetTok                 Procedure(LONG pTokNumber, StringTheory pStrBefore, StringTheory pTok),virtual
GetTokStartPos         Procedure(LONG pTokNumber), LONG,virtual                        ! find the start position of this token in the string
SetTok                 Procedure(long pTokNumber,STRING pValue,<string pStrBefore>),virtual
SetTok                 Procedure(long pTokNumber,*STRING pValue,<string pStrBefore>),virtual
InsertStringAtEOL      Procedure(long pTokNumber, string pStr, byte pComment=true),virtual
AlignComments          Procedure(LONG pMaxWidth),LONG,proc,virtual                     ! returns comments moved. pMaxWidth is NOT honoured - the width test is specified at plTgt = plMin and never built - a layout change, not a bug, so it waits for a ruling
AlignCaseLabels        Procedure(LONG pMaxWidth),LONG,proc,virtual                     ! column-align CASE labels. Returns tokens moved.
AlignDeclTypes         Procedure(LONG pMaxWidth),LONG,proc,virtual                     ! line up the TYPE column of a run of declarations. Returns lines moved.
WrapComments           Procedure(LONG pWidth),LONG,proc,virtual                        ! --cmtwrap=<n>: split a trailing comment that passes column n onto rows at its own column, join rows that fit. Returns lines changed.
ClipLines              Procedure(),LONG,proc,virtual                                   ! strip trailing spaces/tabs from every line. Returns lines clipped.
TermLine               Procedure(StringTheory pLine),LONG,virtual                      ! the line holds one of the ppTerms terminators - ClipLines keeps its tail
SplitWideLines         Procedure(LONG pMaxWidth),LONG,proc,virtual                     ! break over-wide lines at a sensible point. Returns lines split.
SplitLongLiteral       Procedure(LONG pTokNumber, LONG pCutAt, LONG pIndentW),LONG,proc,virtual ! cut ONE literal token into  'a' & | / 'b'
LitSafeCut             Procedure(LONG pTokNumber, LONG pWant),LONG,virtual             ! nearest escape-safe cut offset to pWant, 0 = none
GetCurrLineComment     Procedure(stringTheory pSt, long pTokNumber),virtual
PrependStrBefore       Procedure(long pTokNumber, string pStrBefore),virtual
AppendStrBefore        Procedure(long pTokNumber, string pStrAfter),virtual
SetStrBefore           Procedure(long pTokNumber, string pStrBefore),virtual
AddTok                 Procedure(long pTokNumber=0,STRING pValue,<string pStrBefore>),virtual
AddTok                 Procedure(long pTokNumber=0,*STRING pValue,<string pStrBefore>),virtual
DeleteTok              Procedure(long pTokNumber), virtual
DeleteToks             Procedure(long pStart, long pEnd), virtual

GetCurrentLine         Procedure(StringTheory pSt,LONG pPos),STRING,virtual

CharNameOfByte         Procedure(LONG pByte),STRING,virtual                            ! pretty name for an unprintable byte ('<newline>' etc); BLANK = no special name.
                                                                                       !   ONE table, shared by VitEngine.CharName and the rule NOTE charname() helper
FoldStr                Procedure(STRING in),STRING,virtual                             ! simplify integer numeric expressions eg. 4+1 -> 5  -4+1 -> -3
FoldStr                Procedure(LONG pStart=1, LONG pEnd=0), virtual
MatchLeftBracket       Procedure(String pLeftBracket, String pRightBracket, Long pStart=1),LONG,virtual ! returns matching token number
MatchRightBracket      Procedure(String pLeftBracket, String pRightBracket, Long pStart=0),LONG,virtual ! searches BACKWARDS; 0 = from the last token
GetParms               Procedure(StringTheory pParms,*Long pStart,*LONG pEnd), LONG, virtual ! returns number of parms

FindSeq                Procedure(STRING in,   LONG pStart=1, LONG pEnd=0),LONG,virtual ! find a sequence of tokens. 1st char is sep character,2ndChar is noCaseChar,3rd
                                                                                       !   char is ws char that indicates white space ok before token
FindTok                Procedure(STRING pStr, LONG pStart=1, LONG pEnd=0, BOOL pNoCase=false),LONG,virtual ! find a given token
FindTokInLines         Procedure(STRING pStr, LONG pStartLine=1, LONG pEndLine=0),LONG,virtual ! find a given token in a line number range
FindTokInLines         Procedure(*STRING pStr,LONG pStartLine=1, LONG pEndLine=0),LONG,virtual ! find a given token in a line number range
FindFirstTokNumOnLine  Procedure(LONG pSearchLine, LONG pStartAtTok=1),LONG,virtual    ! find first token on a given line
FindLastTokNumOnLine   Procedure(LONG pSearchLine, LONG pStartAtTok=1),LONG,virtual    ! find the last token on a given line



_List                  Procedure(StringTheory st,long pShowType=0), virtual            ! dumps the tokens to text for debugging purposes
TraceIt                Procedure(string pStr),virtual
DescribeChar           Procedure(string pStr),STRING,virtual
MatchLevel             Procedure(),LONG,proc,virtual                                   ! if current level is + position on matching - (and vice versa) Repositions in token Queue.
DumpTokens             Procedure(<string pFn>),virtual                                 ! dump token list to disk - optionally provide file name

FindNotInLiteralOrComment PROCEDURE(stringTheory pSt, string pNeedle,long pStartCol=0, long pNoCase=0),long,virtual
               END
