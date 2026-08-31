! VitSymbols Class - Phase 4 of VitTransform (generalised Clarion code transformer)
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
! innermost-out. Structure blocks (GROUP/QUEUE/CLASS/FILE/MAP/...) are
! skipped whole - field-level typing is a future addition.
!
! Type canonicalisation: built-in keywords compared bare (STRING(20) is
! STRING; CSTRING is NOT STRING); classes by caseless name; &Type matches
! Type (isRef reported but ignored by the matcher per spec); LIKE(x)
! resolved through to x at lookup time (cycle-capped).
!
! Deviation from handover section 3: vitWordStore interning NOT used - the
! matcher only needs name->type lookup, plain queues suffice and keep Phase 4
! free of the vitWordStore/VitBigFile dependency. Veto if ids are wanted.
!
! Requires StringTheory and VitTokenize (include those first).
!
vs:maxName            EQUATE(255) ! Names are TRUNCATED to fit, and the symbol/type/proof queues are matched ON these
                                  !   strings, so two long names sharing a prefix collide. 255 is past any Clarion
                                  !   label. (Same failure as vt:maxVarLen, which is why both are generous.)
vs:maxSlots           EQUATE(512) ! one prototype's parameter TYPE tokens, '|'-terminated. A prototype with more
                                  !   parameters than fit records NONE, and the arity test carries the call on its
                                  !   own - a partial slot list would silently narrow on the wrong position.

! scope kinds
vs:scModule           EQUATE(1)
vs:scProc             EQUATE(2)
vs:scMethod           EQUATE(3)
vs:scRoutine          EQUATE(4)
! "this field's declaring scope could not be determined". NOT a scope id, and
! deliberately negative so it can never equal a use site's answer: ScopeContaining
! returns 0 for a module-level token, and 0 has to keep meaning MODULE LEVEL.
vs:scUnknown          EQUATE(-1)

ScopeQType            QUEUE,TYPE
scopeId                 LONG
kind                    BYTE               ! vs:sc*
parentId                LONG               ! routine -> its procedure; proc/method -> module
startTok                LONG
endTok                  LONG
selfClass               STRING(vs:maxName) ! methods: upper receiver class name
                      END

SymQType              QUEUE,TYPE
nameU                   STRING(vs:maxName) ! upper-cased identifier
scopeId                 LONG
typeU                   STRING(vs:maxName) ! upper canonical type keyword / class name; LIKE target while isLike
isRef                   BYTE               ! declared with &
isLike                  BYTE               ! typeU holds the LIKE target, resolve at lookup
declTok                 LONG
isField                 BYTE               ! structure field published as PRE:name - typed for matching, but
                                           !   NEVER an UnusedVars/AutoCheck candidate (its decl line is structure layout)
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
vs:tkOther            EQUATE(5)             ! FILE/VIEW/WINDOW/... tracked for nesting, rarely a receiver

TypeDefQType          QUEUE,TYPE
typeU                   STRING(vs:maxName)  ! upper structure/type name (named type, class, or instance label)
kind                    BYTE                ! vs:tk*
parentU                 STRING(vs:maxName)  ! CLASS(parent) / GROUP(base) inheritance target; '' = none
fromRaw                 BYTE                ! recorded from the RAW in-file stream - see TypeFieldQType.fromRaw
                      END

TypeFieldQType        QUEUE,TYPE
ownerU                  STRING(vs:maxName)  ! the type this field belongs to
nameU                   STRING(vs:maxName)  ! field name (upper)
fieldTypeU              STRING(vs:maxName)  ! declared type (upper): class/named-type/keyword, or synthetic for anon inline
isRef                   BYTE                ! declared with &
isLike                  BYTE                ! fieldTypeU holds the LIKE target
declScope               LONG                ! the scope this field was DECLARED in, at the finest granularity the
                                            !   scope table has - the ROUTINE if it is inside one, else the PROC/METHOD,
                                            !   else 0 for module level. Routine granularity is load-bearing: a routine's
                                            !   DATA is invisible to its procedure's code, and the coarser answer would
                                            !   offer it there. vs:scUnknown means the scan could not tell, and an
                                            !   unknown row is never narrowed to - which is the refusal, unchanged.
declTok                 LONG                ! the TOKEN the field was declared at. A LIKE(someVariable) field
                                            !   has to resolve that variable from where the DECLARATION stands,
                                            !   not from the use site, or an inner-scope shadow of the target
                                            !   wins and the field takes the wrong type. 0 = not known, which
                                            !   is what the include-EXPANDED pass records: its positions index
                                            !   a different stream from the scope table, and 0 refuses.
fromRaw                 BYTE                ! this row was read from the RAW in-file stream, so declScope and declTok
                                            !   are positions in the stream the scope table was measured on - and they
                                            !   go STALE the moment a rewrite moves a token. Every Build under include
                                            !   expansion DROPS these rows and re-reads them; the expanded rows, which
                                            !   carry no positions to go stale, are built once per file and kept.
                      END

! method PROTOTYPE return types, recorded from CLASS (and other pushed structure)
! bodies by BuildTypeRegistry. The return class is the attribute directly after the
! prototype's closing paren (,String / ,Long / ,Real / a class name); '' = none.
! Overloads are NOT deduped - a keyed GET lands on an arbitrary row of the (owner,name)
! run, fine while overloads agree on the return class.  Veto if dedupe wanted
TypeMethodQType       QUEUE,TYPE
ownerU                  STRING(vs:maxName)  ! the class whose body declares the prototype
nameU                   STRING(vs:maxName)  ! method name (upper)
retClassU               STRING(vs:maxName)  ! return class (upper); '' = no return type
retRef                  BYTE                ! return carries * or & (pointer/reference return)
isVirtual               BYTE                ! the prototype carries VIRTUAL - a derived class may override it, so
                                            !   NOTHING learned from the body in this file may be assumed at a call site
argMin                  LONG                ! parameters that must be supplied (no '=' default, not <omittable>)
argMax                  LONG                !   and the total declared. -1/-1 = the prototype had no '(' we could read, so
                                            !   arity is UNKNOWN and the row matches any call. Overloads are legal and
                                            !   deliberate Clarion - GetTok is declared (LONG),STRING and (LONG,ST,ST) -
                                            !   so the return class is a property of the OVERLOAD, not of the name.
p1TypeU                 STRING(vs:maxName)  ! first parameter's TYPE token, for the tie arity cannot break
pSlotsU                 STRING(vs:maxSlots) ! EVERY parameter's TYPE token, '|'-terminated, in order, MARKER-STRIPPED
                                            !   ('*STRING' records as STRING - the spelling a call site can produce).
                                            !   p1TypeU is slot 1 and stays; this generalises the same test to every
                                            !   position. The decoration principle: a prototype is identified by its
                                            !   parameter TYPES only - names and defaults never appear, so nothing can
                                            !   drift. Wanted per ARGUMENT, not as a whole-signature key (see ArgAdmits).
fromRaw                 BYTE                ! recorded from the RAW in-file stream - see TypeFieldQType.fromRaw
                      END

! prototype ATTRIBUTES that can follow the closing paren - never return types
! VIRTUAL was already stepped past here; it is now also RECORDED (isVirtual above).
vs:protoAttrs         EQUATE(' VIRTUAL DERIVED PROC REPLACE PRIVATE PROTECTED FINAL NAME DLL PASCAL C RAW BINDABLE TYPE ')

! the answer CallArg1Type gives for an argument that is a numeric or quoted
! LITERAL. Not a type name - it cannot collide with one, since no Clarion label starts
! with '#' - and it means "definitely a value, definitely not a class instance", which is
! a POSITIVE fact about the argument and so may exclude a class-typed parameter. Distinct
! from '', which means "could not tell" and excludes nothing.
vs:scalarArg          EQUATE('#SCALAR')

VitSymbols          CLASS,TYPE,MODULE('VitSymbols.clw'),LINK('VitSymbols.clw',STRINGTheoryLinkMode),DLL(STRINGTheoryDLLMode)
tk                     &VitTokenize
scopes                 &ScopeQType
syms                   &SymQType
types                  &TypeDefQType    ! Design B type registry (owned)
fields                 &TypeFieldQType  ! Design B field table (owned)
methods                &TypeMethodQType ! method return-type table (owned)
expTk                  &VitTokenize     ! .red-expanded token stream (NOT owned; engine sets it). When set,
                                        !   Build sources the type registry from this superset, so cross-file
                                        !   header types survive post-rewrite resymbols.
hdrBuilt               BYTE             ! expTk registry built for the current file (stable - skip the re-scan
                                        !   on resymbol). Engine clears it, with expTk, when moving to the next file.
runClash               LONG             ! times ResolveMember refused because an (owner,name) run
                                        !   disagreed - the SCOPE-BLIND registry unioning two procedures'
                                        !   same-named local types - AND the use site's own scope could not
                                        !   pick one of them out. Refusing is correct and it COSTS conversions;
                                        !   this counts them, so the price of the residual blindness is a
                                        !   number instead of an argument.
runScoped              LONG             ! times that narrowing RESCUED a refusal - the run disagreed and
                                        !   exactly one of its rows was declared where the use site could see it.
                                        !   runClash's CONTROL: a zero clash count means nothing unless something
                                        !   in the same run is non-zero, and this is the half that must move.
regSorted              BYTE             ! syms/types/fields sorted for keyed GETs (set at Build end; FindTypeDef falls back to linear while building)
regRaw                 BYTE             ! WHICH PASS is running: BuildTypeRegistry sets it from pScoped and the
                                        !   three Add methods stamp it onto every row they add. It is how the raw
                                        !   rows are told from the expanded ones when the raw ones have to go.
dirty                  BYTE             ! token stream edited since the last Build - rebuild before the next CONSUMER reads (EnsureFresh)
traceReg               BYTE             ! build a BuildTypeRegistry decision trace into regTrace (engine sets = verbose)
regTrace               &StringTheory    ! the trace (owned) - every opener/nest/pop/resync decision with token index
regEofDepth            LONG             ! depth left at EOF of the last registry scan (0 = balanced)
regEofStack            LONG             ! owner-stack entries left at EOF (0 = fully popped) - non-zero = the desync signature

Construct              Procedure()
Destruct               Procedure()
Build                  Procedure(VitTokenize pTk),LONG,PROC,virtual ! returns symbol count
EnsureFresh            Procedure(),virtual ! Build(self.tk) if dirty - called at every consumer entry
Lookup                 Procedure(STRING pName, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef),LONG,virtual ! true = resolved
_List                  Procedure(StringTheory pOut),virtual ! dump for eyeballing
! --- Design B: member/field typing over the type registry ---
BuildTypeRegistry      Procedure(VitTokenize pTk, BYTE pScoped),virtual ! scan structure defs -> types/fields (append; call per unit). pScoped = pTk's token positions line up with the scope table, so a field's declaring scope can be recorded; 0 = record vs:scUnknown (the include-EXPANDED stream, whose positions do not line up)
ResolveMember          Procedure(STRING pOwnerU, STRING pNameU, LONG pUseTok),STRING,virtual ! one hop: field type (walks parentU); '' if none. pUseTok = the USE SITE's token, consulted only when the (owner,name) run disagrees - see ScopeNarrow. NO default: every caller must say where it is asking from, and a caller that cannot must pass 0 and be told nothing
LookupChain            Procedure(STRING pHeadTypeU, STRING pSegsBar, LONG pUseTok),STRING,virtual ! walk '|'-delimited segs; terminal typeU or ''. pUseTok is passed to every hop
FindTypeDef            Procedure(STRING pTypeU),LONG,virtual ! types row; 0 = none
ArgAdmits              Procedure(STRING pSlotsU, LONG pArgCount, STRING pArgTypesU),LONG,virtual ! could THIS CALL be this prototype? Tests every argument position the caller could type. Narrows only on a positive determination, per position - was P1Admits, which tested position 1 only
ArityAdmits            Procedure(LONG pArgMin, LONG pArgMax, LONG pArgCount),LONG,virtual ! could a call with pArgCount arguments be THIS prototype? -1 anywhere = unknown = yes
MethodReturnClass      Procedure(STRING pOwnerU, STRING pNameU, *BYTE pIsRef, LONG pArgCount, STRING pArgTypesU),STRING,virtual ! prototype return class, walks parentU (derived shadows parent); '' = none/unknown. pArgCount selects the OVERLOAD (-1 = caller does not know, consider all rows)
MethodIsVirtual        Procedure(STRING pOwnerU, STRING pNameU),LONG,virtual ! -1 = NO prototype visible, 0 = visible and not virtual, 1 = VIRTUAL anywhere in the parentU chain
_ListTypes             Procedure(StringTheory pOut),virtual ! registry dump for eyeballing

! --- internals (left virtual for tinkering) ---
AddScope               Procedure(BYTE pKind, LONG pParent, LONG pStartTok, STRING pSelfClass),LONG,virtual
AddSym                 Procedure(STRING pNameU, LONG pScope, STRING pTypeU, BYTE pIsRef, BYTE pIsLike, LONG pDeclTok, BYTE pIsField=0),virtual
ParseParams            Procedure(LONG pOpenTok, LONG pScope),virtual ! pOpenTok = the '(' token
SetScopeEnds           Procedure(),virtual ! backward pass, mirrors GetData
LookupIn               Procedure(STRING pNameU, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef, LONG pDepth),LONG,virtual
ScopeContaining        Procedure(LONG pTokPos, BYTE pKind1, BYTE pKind2),LONG,virtual ! a scopeId, NOT a scopes row - unlike FindSym below; 0 = none
FindSym                Procedure(STRING pNameU, LONG pScopeId),LONG,virtual ! syms row; 0 = none
TokText                Procedure(LONG pIx),STRING,virtual
TokIsEOL               Procedure(LONG pIx),LONG,virtual
TokLevel               Procedure(LONG pIx),STRING,virtual ! token level mark: + - / or blank
IsColOneLabel          Procedure(LONG pIx),LONG,virtual ! firstOnLine, no strBefore, label text
IsLabelTok             Procedure(STRING pTok),LONG,virtual
IsDottedLabel          Procedure(STRING pTok),LONG,virtual ! 'Class.Method' -> pos of the '.', else 0 (IsLabelTok rejects '.')
ColOneMethodDot        Procedure(LONG pIx),LONG,virtual ! col-1 'Class.Method' impl label -> '.' pos, else 0
! --- Design B internals ---
AddTypeDef             Procedure(STRING pTypeU, BYTE pKind, STRING pParentU),virtual
AddTypeField           Procedure(STRING pOwnerU, STRING pNameU, STRING pTypeU, BYTE pIsRef, BYTE pIsLike, LONG pDeclScope, LONG pDeclTok),virtual ! pDeclScope: the innermost scope of the DECLARATION - routine, else proc/method, else 0 for module level; vs:scUnknown = could not tell. pDeclTok: the declaration's own token, 0 = not known. No default, for AddTypeMethod's reason - BuildTypeRegistry is the only caller and passes all seven
AddTypeMethod          Procedure(STRING pOwnerU, STRING pNameU, STRING pRetClassU, BYTE pRetRef, BYTE pIsVirtual, LONG pArgMin, LONG pArgMax, STRING pP1TypeU, STRING pSlotsU),virtual ! ; pIsVirtual and arity. NO defaults: a STRING parameter cannot carry one, and Clarion requires every defaulted parameter to follow the undefaulted ones - so pIsVirtual's old =0 had to go too. BuildTypeRegistry is the only caller and passes all eight.
StructKind             Procedure(STRING pKwU),BYTE,virtual ! GROUP/QUEUE/CLASS/RECORD -> vs:tk*; 0 = not a structure keyword
                    END
