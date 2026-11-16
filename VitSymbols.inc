! VitSymbols Class - the symbol table and type registry of VitTransform (generalised Clarion code transformer)
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! Scope-aware symbol table built once per source file from the VitTokenize
! token queue, modelled on vtxaDiff GetData (line-classified P/M/R/V entries
! with backward-computed scope ends), but token-based: the tokenizer already
! swallows OMITted code and stamps firstOnLine/level, so no line re-parsing.
!
! Scopes: module data -> procedure/method (params + locals; SELF in methods
! resolves to the receiver class) -> routine DATA sections. Lookup walks
! innermost-out. Structure blocks (GROUP/QUEUE/CLASS/FILE/MAP/...) are typed
! by the type registry (BuildTypeRegistry, ResolveMember, LookupChain), and a
! PRE(p) structure's fields are published under their prefix as well.
!
! Type canonicalisation: built-in keywords compared bare (STRING(20) is
! STRING; CSTRING is NOT STRING); classes by caseless name; &Type matches
! Type (isRef reported but ignored by the matcher per spec); LIKE(x)
! resolved through to x at lookup time (cycle-capped).
!
! Names are not interned (no vitWordStore): the matcher only needs name->type
! lookup, so plain queues suffice and keep this class free of the
! vitWordStore/VitBigFile dependency.
!
! Requires StringTheory and VitTokenize (include those first).
!
vs:maxName            EQUATE(255)                                                     ! Names are TRUNCATED to fit, and the symbol/type/proof queues are matched ON these strings, so two long names sharing
                                                                                      !   a prefix collide. 255 is past any Clarion label. (Same failure as vt:maxVarLen, which is why both are generous.)
vs:maxSlots           EQUATE(512)                                                     ! one prototype's parameter TYPE tokens, '|'-terminated. A prototype with more parameters than fit records NONE, and
                                                                                      !   the arity test carries the call on its own - a partial slot list would silently narrow on the wrong position.

! scope kinds
vs:scModule           EQUATE(1)
vs:scProc             EQUATE(2)
vs:scMethod           EQUATE(3)
vs:scRoutine          EQUATE(4)
vs:scMain             EQUATE(5)                                                       ! a PROGRAM's own CODE, from its CODE line to the first procedure: a procedure scope to a pass that asks for one (ruled 13 Sep 2026)
! "this field's declaring scope could not be determined". NOT a scope id, and
! deliberately negative so it can never equal a use site's answer: ScopeContaining
! returns 0 for a module-level token, and 0 has to keep meaning MODULE LEVEL.
vs:scUnknown          EQUATE(-1)

! the type a name is given when this table knows it is declared but cannot type it: a
! parameter with no type word, a declaration it cannot read, two declarations of it in one
! scope that disagree, or an outer declaration that one it cannot see may hide. No Clarion
! label is spelled '?', so no typed rule accepts it. It is answered as a reference too, so a
! pass that trusts only plain storage leaves the name alone.
vs:unknownType        EQUATE('?')

! what Visible found for a name at a token
vs:visNone            EQUATE(0)                                                       ! no declaration of it anywhere on the ladder
vs:visSym             EQUATE(1)                                                       ! one syms row answers
vs:visHidden          EQUATE(2)                                                       ! one hidden row answers
vs:visUnknown         EQUATE(3)                                                       ! declared, but which declaration binds, or what it is, cannot be told

ScopeQType            QUEUE,TYPE
scopeId                 LONG
kind                    BYTE                                                          ! vs:sc*
parentId                LONG                                                          ! routine -> its procedure; proc/method -> module
startTok                LONG
endTok                  LONG
selfClass               STRING(vs:maxName)                                            ! methods: upper receiver class name
hostId                  LONG                                                          ! a method of a class a procedure declares in its data: that procedure, whose locals the method
                                                                                      !   shares. -1 = such a method whose procedure cannot be told; 0 = none
unseen                  BYTE                                                          ! 1 = the data section INCLUDEs a file, so it may declare names this table never sees
                      END

! the MAP prototypes of the file by name: a name with two is an overload, and a summary of
! the one body here must not be credited to a call that may bind the other (VitEngine).
MapProtoQType         QUEUE,TYPE
nameU                   STRING(vs:maxName)
n                       LONG
retU                    STRING(vs:maxName)                                            ! the plain return type after the prototype's ')' - '' = none, or two prototypes that disagree
tok                     LONG                                                          ! the prototype's OWN first token, so its parameter list can be read on demand
                      END

! the MAP prototypes of the include-expanded stream, one row per prototype line, sorted by
! name: the files a MAP INCLUDEs are counted there as well as this file (ReadIncProtos).
IncProtoQType         QUEUE,TYPE
nameU                   STRING(vs:maxName)
sig                     STRING(vs:maxSlots)                                           ! the line's words (ProtoSig), to tell this file's own line from another
                      END

SymQType              QUEUE,TYPE
nameU                   STRING(vs:maxName)                                            ! upper-cased identifier
scopeId                 LONG
typeU                   STRING(vs:maxName)                                            ! upper canonical type keyword / class name; LIKE target while isLike
isRef                   BYTE                                                          ! declared with &
isLike                  BYTE                                                          ! typeU holds the LIKE target, resolve at lookup
declTok                 LONG
isField                 BYTE                                                          ! structure field published as PRE:name - typed for matching, but NEVER an
                                                                                      !   UnusedVars/AutoCheck candidate (its decl line is structure layout)
dimHeld                 BYTE                                                          ! 1 = an ARRAY whose DIM is not on its own line: an array parameter (*STRING[] p), or a field
                                                                                      !   inside a DIM'd structure, whose subscript is the structure's
linked                  BYTE                                                          ! 1 = declared EXTERNAL, DLL or EXPORT, or a field of a structure that is: another module
                                                                                      !   holds it or reaches it, so it is never the main code's own (FindOwn)
                      END

! NAMES A SCOPE DECLARES THAT ARE NOT FILED AS SYMBOLS: the label of a structure written as a
! block (a local QUEUE, GROUP or CLASS), a parameter with no type word, a declaration this table
! cannot read. They are kept apart from syms, so no pass that walks the symbols for candidates
! ever meets one, and Visible asks them, so each one HIDES an outer declaration of its name -
! which is what the compiler does with it.
HideQType             QUEUE,TYPE
nameU                   STRING(vs:maxName)
scopeId                 LONG
typeU                   STRING(vs:maxName)                                            ! a structure's own label - the type registry's name for it - or vs:unknownType
declTok                 LONG                                                          ! the label's token: a structure's DIM is read from its opener line
                      END

! NAMES DECLARED IN THE INCLUDE-EXPANDED STREAM outside every structure, with the type each is declared
! with. That stream carries no scopes, so a row says only that the name is declared somewhere the run
! read, and as what: an ASSUME line never answers for such a name (VitMatch.AssumeOf). Built with the
! expanded registry, once per file, and sorted by name.
IncDeclQType          QUEUE,TYPE
nameU                   STRING(vs:maxName)
typeU                   STRING(vs:maxName)                                            ! the type keyword or class name; vs:unknownType for a LIKE or a declaration that cannot be read
                      END

! --- Design B (member/field typing) - the cross-structure TYPE REGISTRY ---------------
! Records every structure DEFINITION (named TYPE, CLASS, or labelled instance) and its
! data members, so a dotted receiver (self.RequestData.DataStringTheory) can be walked
! field-by-field to its terminal type. Populated by BuildTypeRegistry from the same token
! stream (in-file structures, plus the .red-expanded include closure under --thorough).
! structure kinds
vs:tkGroup            EQUATE(1)
vs:tkQueue            EQUATE(2)
vs:tkClass            EQUATE(3)
vs:tkRecord           EQUATE(4)
vs:tkOther            EQUATE(5)                                                       ! FILE/VIEW/WINDOW/... tracked for nesting, rarely a receiver

TypeDefQType          QUEUE,TYPE
typeU                   STRING(vs:maxName)                                            ! upper structure/type name (named type, class, or instance label)
kind                    BYTE                                                          ! vs:tk*
parentU                 STRING(vs:maxName)                                            ! CLASS(parent) / GROUP(base) inheritance target; '' = none
                                                                                      !   vs:unknownType = the name is declared again with another parent, so which one applies cannot be told
fromRaw                 BYTE                                                          ! recorded from the RAW in-file stream - see TypeFieldQType.fromRaw
dimmed                  BYTE                                                          ! 1 = a declaration of this name, or a structure it sits in, carries DIM: owner.field[i] is then a
                                                                                      !   whole element, never one character
isInst                  BYTE                                                          ! 1 = the label of a structure declared as an instance, not a TYPE: a variable whose type is its own label
                      END

TypeFieldQType        QUEUE,TYPE
ownerU                  STRING(vs:maxName)                                            ! the type this field belongs to
nameU                   STRING(vs:maxName)                                            ! field name (upper)
fieldTypeU              STRING(vs:maxName)                                            ! declared type (upper): class/named-type/keyword, or synthetic for anon inline
isRef                   BYTE                                                          ! declared with &
isLike                  BYTE                                                          ! fieldTypeU holds the LIKE target
declScope               LONG                                                          ! the scope this field was DECLARED in, at the finest granularity the scope table has - the ROUTINE if it is
                                                                                      !   inside one, else the PROC/METHOD, else 0 for module level. Routine granularity is load-bearing: a routine's
                                                                                      !   DATA is invisible to its procedure's code, and the coarser answer would offer it there. vs:scUnknown means
                                                                                      !   the scan could not tell, and an unknown row is never narrowed to - which is the refusal, unchanged.
declTok                 LONG                                                          ! the TOKEN the field was declared at. A LIKE(someVariable) field has to resolve that variable from where the DECLARATION stands,
                                                                                      !   not from the use site, or an inner-scope shadow of the target wins and the field takes the wrong type. 0 = not known, which
                                                                                      !   is what the include-EXPANDED pass records: its positions index a different stream from the scope table, and 0 refuses.
fromRaw                 BYTE                                                          ! this row was read from the RAW in-file stream, so declScope and declTok are positions in the stream the scope table was
                                                                                      !   measured on - and they go STALE the moment a rewrite moves a token. Every Build under include expansion DROPS these
                                                                                      !   rows and re-reads them; the expanded rows, which carry no positions to go stale, are built once per file and kept.
noDim                   BYTE                                                          ! 1 = the declaration was read to its end and has no DIM, so x[i] of it is one character; 0 = DIM, or not known
                      END

! method PROTOTYPE return types, recorded from CLASS (and other pushed structure)
! bodies by BuildTypeRegistry. The return class is the attribute directly after the
! prototype's closing paren (,String / ,Long / ,Real / a class name); '' = none.
! Overloads are separate rows of one (owner,name) run: MethodReturnClass walks the
! run, picks by arity and argument types, and refuses when the candidates disagree
! on the return class.
TypeMethodQType       QUEUE,TYPE
ownerU                  STRING(vs:maxName)                                            ! the class whose body declares the prototype
nameU                   STRING(vs:maxName)                                            ! method name (upper)
retClassU               STRING(vs:maxName)                                            ! return class (upper); '' = no return type
retRef                  BYTE                                                          ! return carries * or & (pointer/reference return)
isVirtual               BYTE                                                          ! the prototype carries VIRTUAL - a derived class may override it, so NOTHING
                                                                                      !   learned from the body in this file may be assumed at a call site
argMin                  LONG                                                          ! parameters that must be supplied (no '=' default, not <omittable>)
argMax                  LONG                                                          !   and the total declared. -1/-1 = the prototype had no '(' we could read, so arity is UNKNOWN and the
                                                                                      !   row matches any call. Overloads are legal and deliberate Clarion - GetTok is declared (LONG),STRING
                                                                                      !   and (LONG,ST,ST) - so the return class is a property of the OVERLOAD, not of the name.
tok                     LONG                                                          ! the prototype's OWN first token, so its parameter list is read from source
p1TypeU                 STRING(vs:maxName)                                            ! first parameter's TYPE token, for the tie arity cannot break
pSlotsU                 STRING(vs:maxSlots)                                           ! EVERY parameter's TYPE token, '|'-terminated, in order, MARKER-STRIPPED ('*STRING' records as STRING - the
                                                                                      !   spelling a call site can produce). p1TypeU is slot 1 and stays; this generalises the same test to every
                                                                                      !   position. The decoration principle: a prototype is identified by its parameter TYPES only - names and defaults
                                                                                      !   never appear, so nothing can drift. Wanted per ARGUMENT, not as a whole-signature key (see ArgAdmits).
fromRaw                 BYTE                                                          ! recorded from the RAW in-file stream - see TypeFieldQType.fromRaw
                      END

! prototype ATTRIBUTES that can follow the closing paren - never return types
! VIRTUAL is stepped past here and also RECORDED (isVirtual above).
vs:protoAttrs         EQUATE(' VIRTUAL DERIVED PROC REPLACE PRIVATE PROTECTED FINAL NAME DLL PASCAL C RAW BINDABLE TYPE ')

! the answer CallArgTypes gives for an argument that is a numeric or quoted
! LITERAL. Not a type name - it cannot collide with one, since no Clarion label starts
! with '#' - and it means "definitely a value, definitely not a class instance", which is
! a POSITIVE fact about the argument and so may exclude a class-typed parameter. Distinct
! from '', which means "could not tell" and excludes nothing.
vs:scalarArg          EQUATE('#SCALAR')

! the SCALAR types of the language, space-wrapped for a whole-word test. A value parameter of
! one of these takes an argument of any other: the compiler converts on the call, and its
! overloading rules count every value parameter as one type. So two of these that differ are
! never a positive mismatch in ArgAdmits; a class or structure type against anything else is.
vs:scalarTypes        EQUATE(' BYTE SHORT USHORT LONG ULONG INT64 UINT64 REAL SREAL DECIMAL PDECIMAL BFLOAT4 BFLOAT8 STRING CSTRING PSTRING DATE TIME BOOL SIGNED UNSIGNED ')

VitSymbols          CLASS,TYPE,MODULE('VitSymbols.clw'),LINK('VitSymbols.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
tk                     &VitTokenize
scopes                 &ScopeQType
mapProtos              &MapProtoQType                                                 ! MAP prototypes by name (owned)
mapIncl                BYTE                                                           ! a MAP or MODULE of this file INCLUDEs a file, which may prototype a name again (Build); read only when incRead is 0
incProtos              &IncProtoQType                                                 ! the MAP prototypes of the include-expanded stream (owned)
incRead                BYTE                                                           ! incProtos was read for this file: the includes were read, so they answer instead of mapIncl
incMiss                BYTE                                                           ! a MAP or MODULE in the expanded stream holds an include that could not be read
incDecl                &IncDeclQType                                                  ! names the include-expanded stream declares outside any structure (owned)
syms                   &SymQType
hidden                 &HideQType                                                     ! names declared but not filed as symbols (owned)
types                  &TypeDefQType                                                  ! Design B type registry (owned)
fields                 &TypeFieldQType                                                ! Design B field table (owned)
methods                &TypeMethodQType                                               ! method return-type table (owned)
expTk                  &VitTokenize                                                   ! .red-expanded token stream (NOT owned; engine sets it). When set, Build sources the type
                                                                                      !   registry from this superset, so cross-file header types survive post-rewrite resymbols.
hdrBuilt               BYTE                                                           ! expTk registry built for the current file (stable - skip the re-scan on
                                                                                      !   resymbol). Engine clears it, with expTk, when moving to the next file.
runClash               LONG                                                           ! times ResolveMember refused because an (owner,name) run disagreed - the SCOPE-BLIND registry unioning two procedures'
                                                                                      !   same-named local types - AND the use site's own scope could not pick one of them out. Refusing is correct and it
                                                                                      !   COSTS conversions; this counts them, so the price of the residual blindness is a number instead of an argument.
runScoped              LONG                                                           ! times that narrowing RESCUED a refusal - the run disagreed and exactly one of its rows was declared where the use site could see it.
                                                                                      !   runClash's CONTROL: a zero clash count means nothing unless something in the same run is non-zero, and this is the half that must move.
stMeth                 &StringTheory                                                  ! the engine's ' NAME NAME ' list of every StringTheory method (NOT owned); PureStKin asks it
regSorted              BYTE                                                           ! syms/types/fields sorted for keyed GETs (set at Build end; FindTypeDef falls back to linear while building)
regRaw                 BYTE                                                           ! WHICH PASS is running: BuildTypeRegistry sets it from pScoped and the three Add methods stamp it onto every
                                                                                      !   row they add. It is how the raw rows are told from the expanded ones when the raw ones have to go.
dirty                  BYTE                                                           ! token stream edited since the last Build - rebuild before the next CONSUMER reads (EnsureFresh)
tBuild                 LONG                                                           ! --timing: clock ticks spent in Build this file, and how many calls
nBuild                 LONG
traceReg               BYTE                                                           ! build a BuildTypeRegistry decision trace into regTrace (engine sets = verbose)
regTrace               &StringTheory                                                  ! the trace (owned) - every opener/nest/pop/resync decision with token index
regEofDepth            LONG                                                           ! depth left at EOF of the last registry scan (0 = balanced)
regEofStack            LONG                                                           ! owner-stack entries left at EOF (0 = fully popped) - non-zero = the desync signature

Construct              Procedure()
Destruct               Procedure()
Build                  Procedure(VitTokenize pTk),LONG,PROC,virtual                   ! returns symbol count
EnsureFresh            Procedure(),virtual                                            ! Build(self.tk) if dirty - called at every consumer entry
Lookup                 Procedure(STRING pName, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef),LONG,virtual ! true = resolved
_List                  Procedure(StringTheory pOut),virtual                           ! dump for eyeballing
! --- Design B: member/field typing over the type registry ---
BuildTypeRegistry      Procedure(VitTokenize pTk, BYTE pScoped),virtual               ! scan structure defs -> types/fields (append; call per unit). pScoped = pTk's token positions line up with the scope table, so a
                                                                                      !   field's declaring scope can be recorded; 0 = record vs:scUnknown (the include-EXPANDED stream, whose positions do not line up)
ResolveMember          Procedure(STRING pOwnerU, STRING pNameU, LONG pUseTok),STRING,virtual ! one hop: field type (walks parentU); '' if none. pUseTok = the USE SITE's token, consulted
                                                                                             !   only when the (owner,name) run disagrees - see ScopeNarrow. NO default: every caller must
                                                                                             !   say where it is asking from, and a caller that cannot must pass 0 and be told nothing
LookupChain            Procedure(STRING pHeadTypeU, STRING pSegsBar, LONG pUseTok),STRING,virtual ! walk '|'-delimited segs; terminal typeU or ''. pUseTok is passed to every hop
PureStKin              Procedure(STRING pTypeU),BYTE,virtual                          ! 1 = a class derived from StringTheory, through headers held here, that overrides none of its methods
FindTypeDef            Procedure(STRING pTypeU),LONG,virtual                          ! types row; 0 = none
ArgAdmits              Procedure(STRING pSlotsU, LONG pArgCount, STRING pArgTypesU),LONG,virtual ! could THIS CALL be this prototype? Tests every argument position the caller
                                                                                                 !   could type. Narrows only on a positive determination, per position
ArityAdmits            Procedure(LONG pArgMin, LONG pArgMax, LONG pArgCount),LONG,virtual ! could a call with pArgCount arguments be THIS prototype? -1 anywhere = unknown = yes
MethodReturnClass      Procedure(STRING pOwnerU, STRING pNameU, *BYTE pIsRef, LONG pArgCount, STRING pArgTypesU),STRING,virtual ! prototype return class, walks parentU (derived shadows parent); '' = none/unknown.
                                                                                                                                !   pArgCount selects the OVERLOAD (-1 = caller does not know, consider all rows)
MethodIsVirtual        Procedure(STRING pOwnerU, STRING pNameU),LONG,virtual          ! -1 = NO prototype visible, 0 = visible and not virtual, 1 = VIRTUAL anywhere in the parentU chain
MethodProtoTok         Procedure(STRING pOwnerU, STRING pNameU),LONG,virtual          ! the ONE prototype's first token; 0 if none or overloaded (VIRTUAL is answered)
MethodProtoCount       Procedure(STRING pOwnerU, STRING pNameU),LONG,virtual          ! prototypes of the method seen from the class, parents included: 2+ = an overload
AddMapProto            Procedure(STRING pNameU, STRING pRetU, LONG pTok),virtual      ! one MAP / MODULE prototype of that name, from the scan
MapProtoAt             Procedure(LONG pIx),LONG,virtual                               ! the line's first token is a MAP / MODULE prototype, any column, keyword or not
MapProtoTok            Procedure(STRING pNameU),LONG,virtual                          ! the ONE prototype's first token; 0 if none or overloaded
MapProtoCount          Procedure(STRING pNameU),LONG,virtual                          ! MAP prototypes of that name: 2+ = an overload
ReadIncProtos          Procedure(),virtual                                            ! file incProtos from the include-expanded stream (Build, once per file)
IncProtoCount          Procedure(STRING pNameU),LONG,virtual                          ! prototypes of that name in incProtos; at one, its row is in the buffer
ProtoSig               Procedure(LONG pIx),STRING,virtual                             ! the words of the prototype line at pIx, upper-cased, no continuation bar
MapProtoRetAt          Procedure(LONG pIx),STRING,virtual                             ! the plain return type of the prototype at pIx: the keyword after its ')' - '' = none, a reference, a pointer
ProtoRetAt             Procedure(LONG pIx, *BYTE pIsRef),STRING,virtual               ! the return type of the prototype at pIx, pIsRef 1 for a * return; '' = none
ProcReturnAt           Procedure(LONG pTokPos, *BYTE pIsRef),STRING,virtual           ! what the procedure or method around pTokPos is prototyped to return; '' = nothing, or no prototype found
ProcReturnRead         Procedure(LONG pTok, *BYTE pRef, *BYTE pKnown),STRING,virtual  ! ProcReturnAt, and pKnown 0 when no single prototype was found
MapProtoReturn         Procedure(STRING pNameU),STRING,virtual                        ! that of the ONE MAP prototype of the name; '' = none, unknown, or an overload
IncDeclType            Procedure(STRING pNameU),STRING,virtual                        ! the type the include-expanded stream declares the name with; '' = not declared there, vs:unknownType = cannot be told
_ListTypes             Procedure(StringTheory pOut),virtual                           ! registry dump for eyeballing

! --- internals (left virtual for tinkering) ---
AddScope               Procedure(BYTE pKind, LONG pParent, LONG pStartTok, STRING pSelfClass),LONG,virtual
AddSym                 Procedure(STRING pNameU, LONG pScope, STRING pTypeU, BYTE pIsRef, BYTE pIsLike, LONG pDeclTok, BYTE pIsField=0, BYTE pLinked=0),virtual
ParseParams            Procedure(LONG pOpenTok, LONG pScope),virtual                  ! pOpenTok = the '(' token
SetScopeEnds           Procedure(),virtual                                            ! backward pass, mirrors GetData
LookupIn               Procedure(STRING pNameU, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef, LONG pDepth),LONG,virtual
DeclaredStrLen         Procedure(STRING pName, LONG pTokPos),LONG,virtual             ! the n of a plain `STRING(n)` local or global visible at pTokPos, read from the declaration
                                                                                      !   itself; 0 = not that (a reference, a LIKE, a field, an unknown, no length, a DIM)
DeclaredHasDim         Procedure(STRING pName, LONG pTokPos),LONG,virtual             ! 1 = the declaration carries DIM, 0 = it provably does not, -1 = cannot tell
DimOnLine              Procedure(LONG pDeclTok),LONG,virtual                          ! the same three answers for the declaration whose label is token pDeclTok
FieldOneChar           Procedure(STRING pOwnerU, STRING pNameU),LONG,virtual          ! 1 = owner.name[i] is one character: every row of the field a string or a reference to one, declared without DIM
VarOneChar             Procedure(STRING pName, LONG pTokPos),LONG,virtual             ! 1 = x[i] is one character: a variable, or a reference to a string, declared without DIM
FirstInstanceOf        Procedure(STRING pTypeU, LONG pTokPos),LONG,virtual            ! the declaration token of the first plain INSTANCE of that type (never a reference or a
                                                                                      !   LIKE) visible at pTokPos - routine, then procedure or method, then module; 0 = none
ScopeContaining        Procedure(LONG pTokPos, BYTE pKind1, BYTE pKind2),LONG,virtual ! a scopeId, NOT a scopes row - unlike FindSym below; 0 = none
FindSym                Procedure(STRING pNameU, LONG pScopeId),LONG,virtual           ! syms row; 0 = none
FindOwn                Procedure(STRING pNameU, LONG pScopeId),LONG,virtual           ! FindSym - and for the main CODE, a program-level name that no procedure, method or routine outside it mentions (ruled 13 Sep 2026)
Visible                Procedure(STRING pNameU, LONG pTok, *LONG pRow),LONG,virtual   ! vs:vis* - what the name at pTok binds to; pRow = its syms or hidden row
FindHidden             Procedure(STRING pNameU, LONG pScopeId),LONG,virtual           ! hidden row; 0 = none
SymRunLen              Procedure(LONG pRow),LONG,virtual                              ! rows sharing that row's scope and name: 2+ = declared twice in one scope
SymRunAgrees           Procedure(LONG pRow),LONG,virtual                              ! 1 = every row of that run says the same type, reference and LIKE
HiddenRunAgrees        Procedure(LONG pRow),LONG,virtual                              ! the same for a hidden row's run
AddHidden              Procedure(STRING pNm, LONG pSc, STRING pTy, LONG pTok),virtual ! file a name a scope declares that syms does not hold
TokText                Procedure(LONG pIx),STRING,virtual
TokIsEOL               Procedure(LONG pIx),LONG,virtual
TokLevel               Procedure(LONG pIx),STRING,virtual                             ! token level mark: + - / or blank
IsColOneLabel          Procedure(LONG pIx),LONG,virtual                               ! firstOnLine, no strBefore, label text
IsLabelTok             Procedure(STRING pTok),LONG,virtual
IsDottedLabel          Procedure(STRING pTok),LONG,virtual                            ! 'Class.Method' or 'Class.Interface.Method' -> pos of the first '.', else 0
ColOneMethodDot        Procedure(LONG pIx),LONG,virtual                               ! col-1 'Class.Method' impl label -> '.' pos, else 0
! --- Design B internals ---
AddTypeDef             Procedure(STRING pTypeU, BYTE pKind, STRING pParentU),virtual
AddTypeField           Procedure(STRING pOwnerU, STRING pNameU, STRING pTypeU, BYTE pIsRef, BYTE pIsLike, LONG pDeclScope, LONG pDeclTok),virtual ! pDeclScope: the innermost scope of the DECLARATION - routine, else
                                                                                                                                                  !   proc/method, else 0 for module level; vs:scUnknown = could not tell.
                                                                                                                                                  !   pDeclTok: the declaration's own token, 0 = not known.
                                                                                                                                                  !   No default, for AddTypeMethod's reason - BuildTypeRegistry
                                                                                                                                                  !   is the only caller and passes all seven
AddTypeMethod          Procedure(STRING pOwnerU, STRING pNameU, STRING pRetClassU, BYTE pRetRef, BYTE pIsVirtual, LONG pArgMin, LONG pArgMax, STRING pP1TypeU, STRING pSlotsU, LONG pTok),virtual ! ; pIsVirtual and arity. NO defaults:
                                                                                                                                                                                                  !   a STRING parameter cannot carry one,
                                                                                                                                                                                                  !   and Clarion requires every defaulted
                                                                                                                                                                                                  !   parameter to follow the undefaulted
                                                                                                                                                                                                  !   ones, so none of them carries one.
                                                                                                                                                                                                  !   BuildTypeRegistry is the only
                                                                                                                                                                                                  !   caller and passes all ten.
StructKind             Procedure(STRING pKwU),BYTE,virtual                            ! GROUP/QUEUE/CLASS/RECORD -> vs:tk*; 0 = not a structure keyword
                    END
