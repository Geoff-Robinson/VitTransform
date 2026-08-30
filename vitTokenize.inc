! Vitesse Tokenize Class 29Sep2019
!
! (c) 2019-2026 Geoffrey C. Robinson.
! Released under the MIT License - see LICENSE.
!
! scans Clarion source and breaks into tokens in a queue
! requires StringTheory from Capesoft
!
vt:maxVarLen          EQUATE(255)  ! was 50, which TRUNCATED longer labels - and since the vars queue is
                                   ! KEYED on varName, two labels sharing their first 50 chars merged into one row
                                   ! and the second one's type was filed against the first. 255 is past Clarion's limit.

vt:label              EQUATE('b')
vt:literal            EQUATE('''') ! was L but changed to ' 27Aug2021 so no confusion with Long
vt:decPoint           EQUATE('d')
vt:plusMinus          EQUATE('p')
vt:multiplication     EQUATE('m')
vt:exponentiation     EQUATE('^')
vt:Integer            EQUATE('I')
vt:NumericWithDecPt   EQUATE('N')
vt:end                EQUATE('e')  ! could be END or end etc. or '.'
vt:dot                EQUATE('.')  ! used when checking for 'End' type dots
vt:reservedWord       EQUATE('r')
!------
! variable types eg. String, Long, StringTheory etc
vt:String             EQUATE('S')
vt:CString            EQUATE('C')
vt:PString            EQUATE('P')
vt:AString            EQUATE('A')
vt:Any                EQUATE('a')
vt:PDecimal           EQUATE('n')  ! was 'p', which COLLIDED with vt:Procedure - a PDECIMAL variable and a
                                   ! PROCEDURE label were indistinguishable downstream. 'n' was free ('D' is vt:Decimal).
vt:Decimal            EQUATE('D')
vt:StringTheory       EQUATE('s')
vt:Long               EQUATE('L')
vt:ULong              EQUATE('U')
vt:Byte               EQUATE('B')
vt:Real               EQUATE('R')
vt:Short              EQUATE('H')
vt:UShort             EQUATE('h')
vt:Procedure          EQUATE('p')  ! keeps 'p'; vt:PDecimal moved instead (fewer sites to disturb)
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
firstOnLine             byte            ! true/false - is this the first token on this line?
strBefore               &STRING
tok                     &STRING
type                    STRING(1)       ! see equates above: I=integer,N=numeric with dec pt,'=literal 'ABC', d=dec point,
                                        ! p=Plus type (+-),m=Multiplication type (*/%),b=laBel
varType                 STRING(1)       ! see equates above: s=StringTheory S=String L=Long B=Byte R=Real D=Decimal etc
level                   STRING(1)       ! code "indent" level. + for if/group, - for end/., / for else elsif
                      END

searchQType           queue,type        ! used when searching for a particular sequence of tokens
noCase                  long            ! case insensitive search for this token?     true/false
wsBefore                long            ! can there be white space before the token?  true/false
tok                     &STRING         ! the token to search for
                      end

VarTypeQType          QUEUE,TYPE
varName                 STRING(vt:maxVarLen)
varTypes                STRING(10)      ! an array in case diff values see equates above: s=StringTheory S=String L=Long B=Byte R=Real D=Decimal etc
                      END

TokLineMapQType       QUEUE,TYPE        ! record N = current-text line N -> ORIGINAL source line
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

fileSize               LONG             ! size of file read in
separatorA             BYTE,DIM(256)    ! note separator is a RESERVED word hence added 'A'
delimiter              BYTE,DIM(256)
operator               BYTE,DIM(256)

ignoreOmittedCode      BYTE(1)          ! option to ignore or process omitted code Note: ignoring omitted code means more vars #remove'd etc
traceIt                BYTE             ! turn on to start logging to debugOutput
logIt                  BYTE             ! turn on to start logging to log file
stopIt                 BYTE             ! turn on to give STOP() messages
acDiag                 BYTE             ! --acdiag - report why AlignComments left each comment where it is
LogFn                  STRING(256)
dumpFailed             BYTE             ! the last DumpTokens save FAILED. TraceIt and the log both ship OFF, so without this a
                                        !   caller had no way to know the dump it asked for was never written.

lineMap                &TokLineMapQType ! current-text line -> ORIGINAL source line; maintained only while mapOn (preview)
lineMap2               &TokLineMapQType ! MapFold compose scratch (owned)
mapOn                  BYTE             ! armed by MapInit (TransformText preview only); CLI/batch never sets it -> zero cost there

! methods...
Construct              Procedure()
Destruct               Procedure()
FreeToks               Procedure(),virtual ! free the entries in the tokens queue
FreeSearchQ            Procedure(),virtual ! free the entries in the search queue
Records                Procedure(),LONG,virtual ! returns number of records in tokens queue

ParseText              Procedure(STRING pfileName),virtual ! read file in to Tokens queue
ParseText              Procedure(StringTheory st,<string pFileName>,LONG pMergeLabels=FALSE),virtual ! put contents of ST in to Tokens queue
SetLineNumbers         Procedure(),virtual ! set or update line numbers in self.tokens queue (folds the line map FIRST when mapOn)
MapInit                Procedure(),virtual ! identity line map sized from the CURRENT stream (same line-count rule as SetLineNumbers); arms mapOn
MapFold                Procedure(),virtual ! compose the stream's new-line->old-line structure into lineMap; MUST run before anything restamps lineNo
MapLine                Procedure(LONG pLn),LONG,virtual ! translate a CURRENT (last-stamp) line number to its ORIGINAL source line via lineMap; identity when mapOn is off (CLI) or out of range
CheckLevels            Procedure(),virtual ! warn if levels go -ve (mismatched "end")
FindFirstTokOnLine     Procedure(LONG pLineNumber),LONG,virtual ! returns tokNumber or 0 if fails
!FindLastTokOnLine      Procedure(LONG pLineNumber),LONG,virtual ! returns tokNumber or 0 if fails

WriteText              Procedure(STRING pfileName),long,proc,virtual ! format output from tokens
JoinToks               Procedure(LONG pStart=1, LONG pEnd=0),STRING,virtual ! return join tokens
JoinToks               Procedure(StringTheory st, LONG pStart=1, LONG pEnd=0),virtual ! join tokens queue into ST
TokenIsAllDigits       Procedure(),LONG,virtual
TokenIsDecimal         Procedure(),LONG,virtual
TokenIsValidLabel      Procedure(),LONG,virtual
TokenIsReservedWord    Procedure(),LONG,virtual
TokenIsDataType        Procedure(),LONG,virtual
TokenType              Procedure(),virtual

InsertString           Procedure(LONG pPos=1, StringTheory in),virtual ! tokenize and insert string at a given position
InsertString           Procedure(LONG pPos=1, STRING in),virtual ! tokenize and insert string at a given position

MoveTok                Procedure(LONG pSrc, LONG pDst),LONG,proc,virtual ! returns st:ok or st:notOK
MoveToks               Procedure(LONG pSrc, LONG pDst, LONG pNumToMove),LONG,proc,virtual ! returns st:ok or st:notOK

GetTok                 Procedure(LONG pTokNumber),STRING,proc,virtual
GetTok                 Procedure(LONG pTokNumber, StringTheory pStrBefore, StringTheory pTok),virtual
GetTokStartPos         Procedure(LONG pTokNumber), LONG,virtual ! find the start position of this token in the string
SetTok                 Procedure(long pTokNumber,STRING pValue,<string pStrBefore>),virtual
SetTok                 Procedure(long pTokNumber,*STRING pValue,<string pStrBefore>),virtual
InsertStringAtEOL      Procedure(long pTokNumber, string pStr, byte pComment=true),virtual
AlignComments          Procedure(LONG pMaxWidth),LONG,proc,virtual ! returns comments moved; refuses to pad past pMaxWidth
AlignCaseLabels        Procedure(LONG pMaxWidth),LONG,proc,virtual ! column-align CASE labels. Returns tokens moved.
AlignDeclTypes         Procedure(LONG pMaxWidth),LONG,proc,virtual ! line up the TYPE column of a run of declarations. Returns lines moved.
ClipLines              Procedure(),LONG,proc,virtual ! strip trailing spaces/tabs from every line. Returns lines clipped.
SplitWideLines         Procedure(LONG pMaxWidth),LONG,proc,virtual ! break over-wide lines at a sensible point. Returns lines split.
SplitLongLiteral       Procedure(LONG pTokNumber, LONG pCutAt, LONG pIndentW),LONG,proc,virtual ! cut ONE literal token into  'a' & | / 'b'
LitSafeCut             Procedure(LONG pTokNumber, LONG pWant),LONG,virtual ! nearest escape-safe cut offset to pWant, 0 = none
GetCurrLineComment     Procedure(stringTheory pSt, long pTokNumber),virtual
PrependStrBefore       Procedure(long pTokNumber, string pStrBefore),virtual
AppendStrBefore        Procedure(long pTokNumber, string pStrAfter),virtual
SetStrBefore           Procedure(long pTokNumber, string pStrBefore),virtual
AddTok                 Procedure(long pTokNumber=0,STRING pValue,<string pStrBefore>),virtual
AddTok                 Procedure(long pTokNumber=0,*STRING pValue,<string pStrBefore>),virtual
DeleteTok              Procedure(long pTokNumber), virtual
DeleteToks             Procedure(long pStart, long pEnd), virtual

GetCurrentLine         Procedure(StringTheory pSt,LONG pPos),STRING,virtual

CharNameOfByte         Procedure(LONG pByte),STRING,virtual   ! pretty name for an unprintable byte ('<newline>' etc); BLANK = no special name. ONE table, shared by VitEngine.CharName and the rule NOTE charname() helper
FoldStr                Procedure(STRING in),STRING,virtual   ! simplify integer numeric expressions eg. 4+1 -> 5  -4+1 -> -3
FoldStr                Procedure(LONG pStart=1, LONG pEnd=0), virtual
MatchLeftBracket       Procedure(String pLeftBracket, String pRightBracket, Long pStart=1),LONG,virtual ! returns matching token number
MatchRightBracket      Procedure(String pLeftBracket, String pRightBracket, Long pStart=1),LONG,virtual ! returns matching token number
GetParms               Procedure(StringTheory pParms,*Long pStart,*LONG pEnd), LONG, virtual  ! returns number of parms

FindSeq                Procedure(STRING in,   LONG pStart=1, LONG pEnd=0),LONG,virtual  ! find a sequence of tokens. 1st char is sep character,2ndChar is noCaseChar,3rd char is ws char that indicates white space ok before token
FindTok                Procedure(STRING pStr, LONG pStart=1, LONG pEnd=0, BOOL pNoCase=false),LONG,virtual  ! find a given token
FindTokInLines         Procedure(STRING pStr, LONG pStartLine=1, LONG pEndLine=0),LONG,virtual  ! find a given token in a line number range
FindTokInLines         Procedure(*STRING pStr,LONG pStartLine=1, LONG pEndLine=0),LONG,virtual  ! find a given token in a line number range
FindFirstTokNumOnLine  Procedure(LONG pSearchLine, LONG pStartAtTok=1),LONG,virtual  ! find first token on a given line
FindLastTokNumOnLine   Procedure(LONG pSearchLine, LONG pStartAtTok=1),LONG,virtual  ! last first token on a given line



_List                  Procedure(StringTheory st,long pShowType=0), virtual  ! dumps the tokens to text for debugging purposes
TraceIt                Procedure(string pStr),virtual
DescribeChar           Procedure(string pStr),STRING,virtual
MatchLevel             Procedure(),LONG,proc,virtual  ! if current level is + position on matching - (and vice versa) Repositions in token Queue.
DumpTokens             Procedure(<string pFn>),virtual ! dump token list to disk - optionally provide file name

FindNotInLiteralOrComment PROCEDURE(stringTheory pSt, string pNeedle,long pStartCol=0, long pNoCase=0),long,virtual
               END
