! VitSymbols - Phase 4 of VitTransform
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! See VitSymbols.inc header. Build() walk: one pass over the token queue.
! Structure blocks are skipped by depth-counting the tokenizer's level
! marks ('+' on GROUP/QUEUE/CLASS/FILE/MAP/... , '-' on END and inline
! terminator dots). Declarations are recognised only in data regions:
! module data (until CODE or the first procedure), procedure locals
! (until CODE), routine DATA sections (until CODE).
!
!
  MEMBER

  Include('StringTheory.inc'),ONCE
  Include('VitTokenize.inc'),ONCE
  Include('VitSymbols.inc'),ONCE

  MAP
  END

! ====================================================================================
VitSymbols.Construct Procedure()
  code
  self.scopes &= new ScopeQType
  self.syms   &= new SymQType
  self.types  &= new TypeDefQType
  self.fields &= new TypeFieldQType
  self.methods &= new TypeMethodQType              !
  self.regTrace &= new StringTheory                ! registry decision trace
  self.tk     &= NULL
  self.expTk  &= NULL                              ! not owned; engine points this at its expanded stream
  self.hdrBuilt = 0

! ------------------------------------------------------------------------------------
VitSymbols.Destruct Procedure()
  code
  if not self.scopes &= NULL
    free(self.scopes)
    dispose(self.scopes)
  end
  if not self.syms &= NULL
    free(self.syms)
    dispose(self.syms)
  end
  if not self.types &= NULL
    free(self.types)
    dispose(self.types)
  end
  if not self.fields &= NULL
    free(self.fields)
    dispose(self.fields)
  end
  if not self.methods &= NULL                      !
    free(self.methods)
    dispose(self.methods)
  end
  if not self.regTrace &= NULL
    dispose(self.regTrace)                         !
  end

! ------------------------------------------------------------------------------------
VitSymbols.Build Procedure(VitTokenize pTk)
N          long,auto
x          long,AUTO
t2         long,auto
t3         long,auto
t4         long,auto
t5         long,auto
w2         StringTheory
isRef      byte
isLike     byte
typeU      StringTheory
curProc    long               ! scopes id of current proc/method (0 = none)
curRout    long
dataScope  long,AUTO          ! scopes id receiving declarations (0 = in code)
blockDepth long
protoBlock byte               ! current block is a MAP/CLASS/INTERFACE/MODULE - i.e. it LEGITIMATELY
                              ! holds column-1 PROCEDURE/FUNCTION prototypes, so the resync below must
                              ! NOT mistake them for real procedure definitions (would split the scope
                              ! and orphan the enclosing procedure's locals -> UnusedVars over-removal)
modScope   long,auto
fldPre     string(vs:maxName) ! field typing: PRE prefix of the structure being skipped ('' = none)
fldScope   long               ! scope receiving its PRE:name field symbols
lvl        string(1),auto
dotPos     long,auto          ! '.' position inside a Class.Method label token
  code
  self.tk &= pTk
  free(self.scopes)
  free(self.syms)
  N = pTk.records()
  modScope  = self.AddScope(vs:scModule, 0, 1, '')
  dataScope = modScope
  x = 0
  loop
    x += 1
    if x > N then break.
    if self.TokIsEOL(x) then cycle.

    if blockDepth > 0                                                                                                           ! inside GROUP/QUEUE/CLASS/MAP/... - skip whole block
      if self.IsColOneLabel(x) or self.ColOneMethodDot(x)                                                                       ! resync: a procedure/method/routine is never inside a data
        t2 = x + 1                                                                                                              ! structure, so if we see one at column 1 the block's END was
        if ~self.TokIsEOL(t2)                                                                                                   ! mis-levelled (e.g. a single-line 'g GROUP(t),AUTO.' whose
          w2.setValue(upper(self.TokText(t2)))                                                                                  ! inline '.' terminator carries no '-' level) - recover here
          if (w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'PROCEDURE' or w2._DataEnd = 8 and w2.valuePtr[1 : 8] = 'FUNCTION') and ~protoBlock
            blockDepth = 0                                                                                                      ! a proc inside a DATA structure => the block's END was mis-levelled
          elsif w2._DataEnd = 7 and w2.valuePtr[1 : 7] = 'ROUTINE' or w2._DataEnd = 1 and w2.valuePtr[1] = '.'
            blockDepth = 0                                                                                                      ! rather than blanking symbol resolution to the next stray '-'
          end                                                                                                                   ! NB. inside a MAP/CLASS (protoBlock=1) a col-1 PROCEDURE/FUNCTION is a
                                                                                                                                ! legitimate PROTOTYPE, not a definition - do NOT break out of the block
        end
      end
      if ~blockDepth then fldPre = ''.                                                                                          ! resync fired (mis-levelled structure) - stop field capture
      if blockDepth > 0                                                                                                         ! still in a block: count levels and skip
        if fldPre and self.IsColOneLabel(x)                                                                                     ! field typing: a PRE(p) structure publishes
          t2 = x + 1                                                                                                            ! every field as the single token p:name - register it
          if ~self.TokIsEOL(t2)                                                                                                 ! as a typed symbol in the scope that owns the structure
            if self.TokLevel(t2) = '+'                                                                                          ! nested structure opener: its fields keep the OUTER
              t3 = t2 + 1                                                                                                       ! prefix (Clarion PRE spans the whole structure), but a
              loop while ~self.TokIsEOL(t3)                                                                                     ! nested PRE of its own means composition - bail for the
                if upper(self.TokText(t3)) = 'PRE' then fldPre = ''.                                                            ! rest of the block (conservative under-reach)
                t3 += 1
              end
            else
              w2.setValue(upper(self.TokText(t2)))
              do ExtractDeclType
              if typeU._DataEnd
                self.AddSym(clip(fldPre) & ':' & upper(clip(self.TokText(x))), fldScope, typeU.getValue(), isRef, isLike, x, 1) ! clip! fldPre is a padded STRING - unclipped it bakes the padding into the symbol name (round-1 bug: case 12 silently missed)
              end
            end
          end
        end
        lvl = self.TokLevel(x)
        if lvl = '+' then blockDepth += 1.
        if lvl = '-' then blockDepth -= 1.
        if ~blockDepth then fldPre = ''.                                                                                        ! structure closed
        cycle
      end
    end

    get(self.tk.tokens, x)
    if errorcode() then break.
    if ~self.tk.tokens.firstOnLine then cycle.                                                                                  ! classify each line by its first token only

    if self.IsColOneLabel(x) or self.ColOneMethodDot(x) ! ColOneMethodDot: a 'Class.Method' impl label is ONE token IsLabelTok rejects (the '.')
      ! ---- column-1 label line: procedure / method / routine / declaration ----
      t2 = x + 1
      if self.TokIsEOL(t2) then cycle.                                                                                          ! bare label
      w2.setValue(upper(self.TokText(t2)))

      if w2._DataEnd = 1 and w2.valuePtr[1] = '.'                                                                               ! Class.Method PROCEDURE
        t3 = t2 + 1
        t4 = t3 + 1
        if ~self.TokIsEOL(t4) and self.IsLabelTok(self.TokText(t3)) |
           and (upper(self.TokText(t4)) = 'PROCEDURE' or upper(self.TokText(t4)) = 'FUNCTION')
          curProc   = self.AddScope(vs:scMethod, modScope, x, upper(self.TokText(x)))
          curRout   = 0
          dataScope = curProc
          self.AddSym('SELF', curProc, upper(self.TokText(x)), 1, 0, x)
          t5 = t4 + 1
          if ~self.TokIsEOL(t5) and self.TokText(t5) = '('
            self.ParseParams(t5, curProc)
          end
        end
        cycle
      end

      if w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'PROCEDURE' or w2._DataEnd = 8 and w2.valuePtr[1 : 8] = 'FUNCTION'
        dotPos = instring('.', clip(self.TokText(x)), 1, 1) ! Class.Method as ONE column-1 label token (the '.' only splits in expression context)
        if dotPos > 1                                       ! method implementation: receiver class = text before the '.'
          curProc = self.AddScope(vs:scMethod, modScope, x, upper(sub(clip(self.TokText(x)), 1, dotPos - 1)))
          self.AddSym('SELF', curProc, upper(sub(clip(self.TokText(x)), 1, dotPos - 1)), 1, 0, x)
        else
          curProc = self.AddScope(vs:scProc, modScope, x, '')
        end
        curRout   = 0
        dataScope = curProc
        t3 = t2 + 1
        if ~self.TokIsEOL(t3) and self.TokText(t3) = '('
          self.ParseParams(t3, curProc)
        end
        cycle
      end

      if w2._DataEnd = 7 and w2.valuePtr[1 : 7] = 'ROUTINE'
        curRout   = self.AddScope(vs:scRoutine, curProc, x, '')
        dataScope = 0            ! routine code unless a DATA section follows
        cycle
      end

      if self.TokLevel(t2) = '+' ! labelled structure block (lbl QUEUE,TYPE / GROUP / CLASS ...)
        blockDepth = 1
        protoBlock = choose(w2._DataEnd = 5 and w2.valuePtr[1 : 5] = 'CLASS' or w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'INTERFACE' or | ! prototype-bearing? (see resync)
                            w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'MAP'   or w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'MODULE', 1, 0)
        fldPre = ''                              ! field typing: capture PRE(p) so the
        if ~protoBlock and dataScope             ! skip loop can publish p:name field symbols.
          t3 = t2 + 1                            ! A ,TYPE definition has no storage - skip it
          loop while ~self.TokIsEOL(t3)          ! (scan the whole attribute list: TYPE may
            w2.setValue(upper(self.TokText(t3))) ! follow PRE)
            if w2._DataEnd = 4 and w2.valuePtr[1 : 4] = 'TYPE'
              fldPre = ''
              break
            elsif w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'PRE'
              t4 = t3 + 1
              t5 = t4 + 1
              if ~self.TokIsEOL(t5) and self.TokText(t4) = '(' and self.IsLabelTok(self.TokText(t5))
                fldPre = upper(self.TokText(t5))
                fldScope = dataScope
              end
            end
            t3 += 1
          end
        end
        x = t2             ! t2's own '+' already counted
        cycle
      end

      if dataScope         ! ---- variable declaration ----
        do ExtractDeclType ! t2/w2 in -> isRef/isLike/typeU out
        if typeU._DataEnd
          self.AddSym(upper(self.TokText(x)), dataScope, typeU.getValue(), isRef, isLike, x)
        end
      end
      cycle
    end

    ! ---- indented line start: region keywords ----
    w2.setValue(upper(self.TokText(x)))
    if w2._DataEnd = 4 and w2.valuePtr[1 : 4] = 'CODE'
      dataScope = 0
    elsif w2._DataEnd = 4 and w2.valuePtr[1 : 4] = 'DATA'
      if curRout then dataScope = curRout.
    elsif self.TokLevel(x) = '+'
      if dataScope         ! unlabelled structure in a data region (MAP, WINDOW ...)
        blockDepth = 1
        protoBlock = choose(w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'MAP' or w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'MODULE' or | ! a local/module MAP holds col-1 proc
                            w2._DataEnd = 5 and w2.valuePtr[1 : 5] = 'CLASS' or w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'INTERFACE', 1, 0) ! prototypes (see resync above)
      end
    end
  end

  self.SetScopeEnds()
  ! The type registry, in its two modes.
  !  WITHOUT the expanded stream (expTk NULL): rebuild from the raw in-file stream on EVERY Build - decls can shift or be
  !                   edited by a rewrite (e.g. UnusedVars comments one out), so it must track them.
  !  WITH it (expTk set): BOTH streams are read. The .red-expanded superset defines the types and is
  !                   STABLE across the pass (rewriting a method body never changes a field's declared
  !                   type), so it is built ONCE per file - that is hdrBuilt, and it is what avoids
  !                   re-scanning ~90k expanded tokens per rewrite. hdrBuilt is reset per file by the
  !                   engine when it points expTk at the new expansion. The RAW stream is read again
  !                   on EVERY Build beside it, because it is the only stream whose positions the
  !                   scope table shares and a rewrite moves them. See the else branch below.
  !                   DOCUMENTED LIMIT (review option a): a rule set that
  !                   REWRITES DECLARATIONS IN AN INCLUDE - retypes a field, renames a class or a
  !                   prototype - works from that frozen picture for the rest of the file.
  !                   The supported shape is two runs: the declaration pass first, then everything
  !                   else against the updated files. Detect-and-refresh was considered and
  !                   deferred until a real rule set needs it; the README's thorough-mode section
  !                   states the same limit in user terms.
  self.regSorted = 0 ! FindTypeDef's dedupe runs DURING the registry build - use the linear path until re-sorted
  if self.expTk &= NULL
    free(self.types)
    free(self.fields)
    free(self.methods)                                            !
    self.BuildTypeRegistry(pTk, 1)                                                                                                          ! the RAW in-file stream - pTk is what SetScopeEnds
                                                                                                                                            !   above just measured, so a field's token position and a
                                                                                                                                            !   scope's startTok/endTok are indices into the SAME stream
                                                                                                                                            !   and the declaring scope can be recorded.
  else
    ! ---- INCLUDE EXPANSION IS ON, SO THE REGISTRY IS BUILT FROM TWO STREAMS ----
    ! The EXPANDED stream is the superset - the includes and this file - and it is the only
    ! place a type arriving through an include can come from. Its token positions index a
    ! stream the scope table was never measured on, so nothing read from it may carry a scope:
    ! every row records vs:scUnknown and declTok 0, and an unknown scope is never narrowed to.
    ! That is the RIGHT answer for the includes themselves, since a type arriving through one
    ! is module-level and not a procedure-local of this file.
    !
    ! It is the WRONG answer for THIS FILE's own procedure-locals, which are in the superset
    ! too. So the RAW stream is read as well and those rows carry real scopes - two procedures
    ! that each declare a local QUEUE called Line are then told apart under include expansion
    ! exactly as they are without it.
    !
    ! THE TWO PASSES ARE NOT REFRESHED ALIKE, AND THAT IS THE WHOLE REASON FOR fromRaw.
    ! The expanded pass carries no positions, so nothing in it can go stale and it is built
    ! ONCE per file - that is what hdrBuilt is for, and it is what keeps ~90k expanded tokens
    ! from being re-scanned on every rewrite. The raw pass carries token positions and a
    ! rewrite MOVES them: kept across a resymbol they would index a stream that no longer
    ! exists, and a scope answered from a stale position is a coincidence, which is the whole
    ! defect this mechanism exists to avoid. So the raw rows are dropped and re-read on every
    ! Build. That is a scan of this file alone, never of its includes.
    !
    ! The duplication is deliberate and it is inert: an in-file field appears twice, once with
    ! a scope and once without, and the two AGREE on the type - so they never make a run
    ! disagree that would have agreed. Only the scoped row can ever be narrowed to.
    if ~self.hdrBuilt
      free(self.types)
      free(self.fields)
      free(self.methods)                                          !
      self.BuildTypeRegistry(self.expTk, 0)                                                                                                 ! superset: contains the in-file structures too
      self.hdrBuilt = 1
    end
    do DropRawRows                                                                                                                          ! last Build's raw rows: their positions have moved
    self.BuildTypeRegistry(pTk, 1)                                                                                                          ! this file's own structures again, WITH their scopes
  end
  ! sort for keyed (binary) GETs - FindSym was a full linear scan of ALL symbols per
  ! lookup, up to 3x per typed candidate token = the dominant typed-matching cost.
  sort(self.syms, +self.syms.scopeId, +self.syms.nameU)
  sort(self.types, +self.types.typeU)
  sort(self.fields, +self.fields.ownerU, +self.fields.nameU)
  sort(self.methods, +self.methods.ownerU, +self.methods.nameU)   !
  self.regSorted = 1
  self.dirty = 0                                                                                                                            ! freshly built
  return records(self.syms)

! ---- drop every registry row read from the RAW stream, so the raw pass can be run again ----
!      Their declScope and declTok are positions in a stream the last rewrite moved, and a
!      scope answered from a stale position is a coincidence. The EXPANDED rows carry no
!      positions and are left where they are - re-reading them is the ~90k-token scan hdrBuilt
!      exists to avoid. BACKWARDS, because deleting a queue row shifts every row above it.
DropRawRows routine
  data
drI long,auto
  code
  loop drI = records(self.fields) to 1 by -1
    get(self.fields, drI)
    if errorcode() then cycle.
    if self.fields.fromRaw then delete(self.fields).
  end
  loop drI = records(self.methods) to 1 by -1
    get(self.methods, drI)
    if errorcode() then cycle.
    if self.methods.fromRaw then delete(self.methods).
  end
  loop drI = records(self.types) to 1 by -1 ! last, so records(self.types) is back to the
    get(self.types, drI)                    !   expanded count before the raw pass seeds
    if errorcode() then cycle.              !   synthSeq from it
    if self.types.fromRaw then delete(self.types).
  end

! ---- shared declaration-type extraction: t2 = token after the col-1 label, w2 = its
!      upper text; sets isRef/isLike/typeU (typeU empty = not a typed declaration) ----
ExtractDeclType routine
  isRef  = 0
  isLike = 0
  typeU.free()
  if self.TokText(t2) = '&'
    t3 = t2 + 1
    if ~self.TokIsEOL(t3) and self.IsLabelTok(self.TokText(t3))
      isRef = 1
      typeU.setValue(upper(self.TokText(t3)))
    end
  elsif w2._DataEnd = 4 and w2.valuePtr[1 : 4] = 'LIKE'
    t3 = t2 + 1
    t4 = t3 + 1
    if ~self.TokIsEOL(t4) and self.TokText(t3) = '(' and self.IsLabelTok(self.TokText(t4))
      isLike = 1
      typeU.setValue(upper(self.TokText(t4)))
    end
  elsif self.IsLabelTok(w2.getValue())
    typeU.setValue(w2) ! bare keyword: STRING(20) arrives as STRING + ( + 20 + )
  end

! ------------------------------------------------------------------------------------
! Mirrors GetData's backward pass: a routine ends where the next routine or
! procedure starts; a procedure/method ends where the next procedure starts
! (so its locals stay visible inside its routines); module spans the file.
! ------------------------------------------------------------------------------------
VitSymbols.SetScopeEnds Procedure()
s             long,auto
N             long,auto
nextProcStart long,auto
nextAnyStart  long,auto
  code
  N = self.tk.records()
  nextProcStart = N + 1
  nextAnyStart  = N + 1
  loop s = records(self.scopes) to 1 by -1
    get(self.scopes, s)
    case self.scopes.kind
    of vs:scRoutine
      self.scopes.endTok = nextAnyStart - 1
      nextAnyStart = self.scopes.startTok
    of vs:scProc    orof vs:scMethod
      self.scopes.endTok = nextProcStart - 1
      nextProcStart = self.scopes.startTok
      nextAnyStart  = self.scopes.startTok
    else
      self.scopes.endTok = N
    end
    put(self.scopes)
  end

! ------------------------------------------------------------------------------------
! ====================================================================================
! Design B - type registry (C1/C2) + member-chain resolver (LookupChain).
! BuildTypeRegistry scans structure DEFINITIONS (named TYPE / CLASS / labelled instance)
! and records each type and its data members, so a dotted receiver can be walked field by
! field to a terminal type. Structure nesting is tracked by the tokenizer's '+'/'-' level
! marks (same source of truth GetData/Build use); an owner stack maps the current field
! owner. Method PROTOTYPES inside a CLASS are skipped (only data members type a receiver).
! In-file structures first; --thorough calls this again over the .red-expanded includes.
! ====================================================================================
VitSymbols.BuildTypeRegistry Procedure(VitTokenize pTk, BYTE pScoped)
x        long,AUTO
dclScope long,auto                                            ! the scope of the declaration about to be recorded (vs:scUnknown when ~pScoped)
dclTok   long,auto                                            !   ... and its token (0 when ~pScoped) - both set by DeclScopeAt
N        long,auto
t2       long,auto
t3       long,auto
t4       long,auto
depth    long,AUTO                                            ! structure nesting level (mirrors '+'/'-')
kindB    byte,auto
parentU  string(vs:maxName),auto
fldTypeU string(vs:maxName),auto
isRefB   byte,auto
isLikeB  byte,auto
synthSeq long,AUTO
lvl      string(1),auto
curOwner string(vs:maxName),auto
tta      byte,auto                                            ! this opener line carries a top-level ,TYPE attribute
tdep     long,auto                                            ! paren depth while scanning the attribute list
ttx      long,auto                                            ! attr-scan cursor
mdx      long,auto                                            ! prototype return-type scan cursor
mdepth   long,auto                                            ! paren depth over the prototype's parameter list
retU     string(vs:maxName)                                   ! return class from the attribute after the closing paren
retRefB  byte,auto                                            ! return carries * or &
virtB    byte,auto                                            ! the prototype's attribute list carries VIRTUAL
vdx      long,auto                                            ! VIRTUAL-scan cursor
aMin     long,auto                                            ! parameters the call MUST supply
aMax     long,auto                                            !   and the total declared (-1/-1 = unreadable, matches anything)
p1U      string(vs:maxName),auto                              ! first parameter's type token
pTx      string(vs:maxName)                                   ! the current parameter's type, marker stripped - the slot spelling
slotsU   string(vs:maxSlots),auto                             ! every parameter's type token, '|'-terminated
slotsOk  byte,auto                                            !   cleared if they will not fit - then we record NONE
pSeen    byte,auto                                            ! the current parameter has started
pOpt     byte,auto                                            !   ... and is defaulted ('=') or omittable ('<>')
pAng     byte,auto                                            !   ... and we are inside its angle brackets
vdep     long,auto                                            ! paren depth over that scan (NAME('x'),VIRTUAL)
saveTk   &VitTokenize                                         ! BuildTypeRegistry may run on the include-EXPANDED tokenizer; restore self.tk (Lookup needs the raw stream) after
OwnerStackQ QUEUE,PRE(osq)
ownerU     STRING(vs:maxName)
atDepth    LONG
kind       BYTE                                               ! vs:tk* of the owner - the EQUATE-in-class resync needs it
             END
  code
  saveTk &= self.tk
  self.tk &= pTk
  N = pTk.records()
  if self.traceReg                                            ! fresh trace per scan
    self.regTrace.free()
    self.regTrace.append('--- registry trace: ' & N & ' token(s) ---<13,10>')
  end
  self.regEofDepth = 0
  self.regEofStack = 0
  free(OwnerStackQ)
  depth    = 0
  self.regRaw = pScoped                                       ! stamped onto every row the three Add methods add on this pass
  ! SEEDED FROM THE ROWS ALREADY THERE, not from 0, and that is load-bearing whenever this runs
  ! a SECOND time over a registry that was not freed - the raw pass under include expansion.
  ! '$ANON' & n is an OWNER NAME and AddTypeDef dedupes by name, so a second pass restarting at
  ! 1 would find the first pass's $ANON1 already present, skip its own, and hang this pass's
  ! anonymous fields on a structure from the other one. Starting above the existing count cannot
  ! collide: '$' is not legal in a Clarion label, so no name from the source can be in the way.
  synthSeq = records(self.types)
  x = 0
  loop
    x += 1
    if x > N then break.
    if self.TokIsEOL(x) then cycle.
    get(self.tk.tokens, x)
    if errorcode() then break.
    if self.tk.tokens.firstOnLine and self.ColOneMethodDot(x) ! a col-1 DOTTED label (Class.Method impl)
      if depth or records(OwnerStackQ)                        !   can never sit inside a structure - resync,
        if self.traceReg                                      !   exactly like col-1 CLASS / ,TYPE. This closes
          self.regTrace.append('RESYNC tok ' & x & ' ' & clip(self.TokText(x)) & ' IMPL: depth was ' & depth & ' stack was ' & records(OwnerStackQ) & '<13,10>')
        end                                                   !   the swallow window between a phantom-'+'-broken
        depth = 0                                             !   class END and the main-file body (the
        free(OwnerStackQ)                                     !   MODULE-attribute phantom). Bare PROCEDURE labels
      end                                                     !   are NOT safe (b0b: col-1 prototypes) - dotted only.
    end
    if self.tk.tokens.firstOnLine and self.IsColOneLabel(x)
      t2 = x + 1
      if ~self.TokIsEOL(t2)
        kindB = 0
        if self.TokLevel(t2) = '+'                            ! label + keyword opening a '+' block
          kindB = self.StructKind(upper(self.TokText(t2)))
          if ~kindB then kindB = vs:tkOther.                  ! unknown block type - still push, to keep the stack aligned
        end
        if kindB                                              ! ---- structure opener ----
          tta = 0                                             ! does the opener line carry a top-level ,TYPE attribute?
          if kindB <> vs:tkClass                              !   (CLASS already resyncs unconditionally below)
            tdep = 0
            ttx  = t2 + 1
            loop while ~self.TokIsEOL(ttx)
              case upper(self.TokText(ttx))
              of '('
                tdep += 1
              of ')'
                tdep -= 1
              of 'TYPE'
                if ~tdep then tta = 1; break.
              end
              ttx += 1
            end
          end
          if kindB = vs:tkClass or tta                                                              ! A column-1 CLASS is ALWAYS
            if self.traceReg and (depth or records(OwnerStackQ))                                    !
              self.regTrace.append('RESYNC tok ' & x & ' ' & clip(self.TokText(x)) & choose(tta = 1, ' ,TYPE', ' CLASS') & ': depth was ' & depth & ' stack was ' & records(OwnerStackQ) & '<13,10>')
            end
            depth = 0                                                                               ! top-level in Clarion, and so is any structure carrying the
            free(OwnerStackQ)                                                                       ! TYPE attribute (TYPE is illegal on a nested structure) - so
          end                                                                                       ! force a resync: recover from mis-levelling in a prior big
                                                                                                    ! class/structure (phantom '+' marks on keyword-texted tokens
                                                                                                    ! in prototypes - diagnosis) that left depth/OwnerStackQ
                                                                                                    ! stale, which would otherwise swallow this definition as a
                                                                                                    ! NESTED FIELD and lose its fields (TokenQType/RulePartQType/
                                                                                                    ! ScopeQType... were all lost this way in virgin-tokenizer runs).
          if records(OwnerStackQ)
            get(OwnerStackQ, records(OwnerStackQ))
            curOwner = osq:ownerU
          else
            curOwner = ''
          end
          parentU = ''                                                                              ! CLASS(parent) / GROUP(base) instance-of
          t3 = t2 + 1
          if ~self.TokIsEOL(t3) and self.TokText(t3) = '('
            t4 = t3 + 1
            if ~self.TokIsEOL(t4) and self.IsLabelTok(self.TokText(t4))
              parentU = upper(self.TokText(t4))
            end
          end
          if ~curOwner                                                                              ! top level: a named type / class / instance variable
            self.AddTypeDef(upper(self.TokText(x)), kindB, parentU)
            if self.traceReg                                                                        !
              self.regTrace.append('TYPE tok ' & x & ' ' & clip(self.TokText(x)) & ' kind ' & kindB & ' depth ' & depth & '<13,10>')
            end
            clear(OwnerStackQ)
            osq:ownerU = upper(self.TokText(x))
          else                                                                                      ! nested: a field whose type is a structure
            if parentU
              fldTypeU = parentU                                                                    ! field GROUP(NamedType) - type is the named type
            else
              synthSeq += 1
              fldTypeU = '$ANON' & synthSeq ! anonymous inline structure - synthetic owner name - inline extra fields on a GROUP(Named) are dropped
              self.AddTypeDef(fldTypeU, kindB, '')
            end
            if self.traceReg                                                                        ! a NAMED structure landing here = the desync signature
              self.regTrace.append('NEST tok ' & x & ' ' & clip(self.TokText(x)) & ' -> ' & clip(fldTypeU) & ' under ' & clip(curOwner) & ' depth ' & depth & '<13,10>')
            end
            do DeclScopeAt
            self.AddTypeField(curOwner, upper(self.TokText(x)), fldTypeU, 0, 0, dclScope, dclTok)
            clear(OwnerStackQ)
            osq:ownerU = fldTypeU
          end
          osq:atDepth = depth
          osq:kind    = kindB                                                                       !
          add(OwnerStackQ)
        elsif records(OwnerStackQ)                                                                  ! ---- a simple field inside a structure ----
          if self.TokLevel(x) <> '+' and self.TokLevel(x) <> '-'                                    ! a real field label carries no level mark (skips unlabelled RECORD/END openers)
            get(OwnerStackQ, records(OwnerStackQ))
            curOwner = osq:ownerU
            if osq:kind = vs:tkClass and upper(self.TokText(t2)) = 'EQUATE'                         ! an EQUATE can never be a CLASS member -
              if self.traceReg                                                                      !   this "field" proves the class END was missed
                self.regTrace.append('RESYNC tok ' & x & ' ' & clip(self.TokText(x)) & ' EQUATE-in-class: depth was ' & depth & ' stack was ' & records(OwnerStackQ) & '<13,10>')
              end                                                                                   !   (phantom '+' marks) - resync instead of adding
              depth = 0                                                                             !   the fake field. ITEMIZE interiors are kind
              free(OwnerStackQ)                                                                     !   tkOther, so their equates keep current handling.
            elsif upper(self.TokText(t2)) = 'PROCEDURE' or upper(self.TokText(t2)) = 'FUNCTION'     ! method prototype - record its
              retU = '' ; retRefB = 0                                                               !   return class (was: skipped whole).
              aMin = -1 ; aMax = -1 ; p1U = '' ; slotsU = '' ; slotsOk = 1                          ! arity UNKNOWN unless we read a '(' list
              mdx = t2 + 1                                                                          ! Return class = the attribute directly
              if ~self.TokIsEOL(mdx) and self.TokText(mdx) = '('                                    ! after the closing paren; a known
                mdepth = 1                                                                          ! prototype ATTRIBUTE there (VIRTUAL,
                aMax = 0 ; aMin = 0                                                                 ! empty '()' is a real, known arity of 0
                pSeen = 0 ; pOpt = 0 ; pAng = 0                                                     !   pSeen: this parameter has begun
                loop                                                                                ! PROC, ...) means no return type.
                  mdx += 1
                  if self.TokIsEOL(mdx) then mdepth = -1 ; break.                                   ! EOS before ')' - malformed, no return
                  case self.TokText(mdx)
                  of '('
                    mdepth += 1
                  of ')'
                    mdepth -= 1
                    if ~mdepth then break.
                  end
                  if mdepth = 1                                                                     ! count only at the TOP level of the list -
                    case self.TokText(mdx)                                                          !   a nested '(' is a dimension or a default expression
                    of ','
                      if pSeen and ~pOpt then aMin += 1.                                            ! a parameter ENDS here: required unless <> or '='
                      pSeen = 0 ; pOpt = 0 ; pAng = 0
                    of '<'
                      pAng = 1 ; pOpt = 1                                                           ! <STRING pFormat> - omittable
                    of '>'
                      pAng = 0
                    of '='
                      pOpt = 1                                                                      ! LONG pStart=1 - defaulted
                    else
                      if ~pSeen and (self.TokText(mdx) = '*' or self.TokText(mdx) = '&')
                        ! a SEPARATE by-ref marker token ('&' never merges; a spaced '* STRING'
                        ! keeps its own '*') - the parameter's TYPE is the NEXT token, so the
                        ! parameter does not open here. Recording the marker itself both
                        ! mis-filed the slot AND consumed pSeen, so the real type was thrown
                        ! away: no caller-side spelling could ever equal a bare '&', and
                        ! ArgAdmits POSITIVELY excluded the row - the fail-closed inversion of
                        ! its own admit-only-on-positive contract.
                      elsif ~pSeen                                                                  ! '<' and '>' have their own arms above, so the
                        pSeen = 1                                                                   !   FIRST non-marker token to reach here is the
                        aMax += 1                                                                   !   parameter's TYPE, inside angle brackets or not
                        pTx = upper(self.TokText(mdx))
                        if pTx[1] = '*'                                                             ! MERGED '*STRING' token (the tokenizer combines
                          pTx = sub(pTx, 2, vs:maxName - 1)                                         !   * with the next token after ( , <) - record
                        end                                                                         !   the BARE type: the spelling a call site's
                                                                                                    !   CallArgTypes can actually produce. The return
                                                                                                    !   class below has always done this same strip.
                        if aMax = 1 then p1U = pTx.
                        ! record EVERY slot's type, not just the first. This loop already
                        ! had them and threw all but slot 1 away. '|'-terminated, in order, so
                        ! ArgAdmits can line argument N up with parameter N.
                        if slotsOk
                          if len(clip(slotsU)) + len(clip(pTx)) + 1 > size(slotsU)
                            slotsOk = 0                                                             ! too many/too long to hold - see below
                            slotsU  = ''
                          else
                            slotsU = clip(slotsU) & clip(pTx) & '|'
                          end
                        end
                      end
                    end
                  end
                end
                if pSeen and ~pOpt then aMin += 1.                                                  ! the last parameter has no ',' to close it
                if mdepth < 0 then aMin = -1 ; aMax = -1 ; slotsU = ''.                             ! malformed list - claim NOTHING about arity or slots
                if ~mdepth then mdx += 1 else mdx = 0.
              end                                                                                   ! (no '(' at all: Foo PROCEDURE,STRING -
              if mdx                                                                                !   mdx still sits right after PROCEDURE)
                if ~self.TokIsEOL(mdx) and self.TokText(mdx) = ','
                  mdx += 1
                  if ~self.TokIsEOL(mdx) and (self.TokText(mdx) = '*' or self.TokText(mdx) = '&')   ! separate ref-marker token ('&' never merges)
                    retRefB = 1
                    mdx += 1
                  end
                  if ~self.TokIsEOL(mdx)
                    retU = upper(self.TokText(mdx))
                    if retU[1] = '*'                                                                ! MERGED '*STRING' token - the tokenizer's
                      retRefB = 1                                                                   !   'reference prototypes' pass combines * with
                      retU = sub(retU, 2, vs:maxName - 1)                                           !   the next token after ( , < (vitTokenize ~307)
                    end
                    if ~self.IsLabelTok(clip(retU)) or instring(' ' & clip(retU) & ' ', vs:protoAttrs, 1, 1)
                      retU = ''                                                                     ! attribute keyword / not label-shaped = no return
                    end
                  end
                end
              end
              virtB = 0                                                                             ! RECORD the VIRTUAL that only
              if mdx                                                                                !   stepped past. A virtual prototype may be
                vdep = 0                                                                            !   overridden in a derived class, so nothing
                vdx  = mdx                                                                          !   learned from the body in THIS file may be
                loop while ~self.TokIsEOL(vdx)                                                      !   assumed at a call site (summaries).
                  case upper(self.TokText(vdx))                                                     ! Whole attribute list, not just the first
                  of '('                                                                            !   attribute: ,STRING,NAME('x'),VIRTUAL is
                    vdep += 1                                                                       !   as legal as ,VIRTUAL. Paren-depth guarded
                  of ')'                                                                            !   so a NAME('VIRTUAL') interior cannot count
                    vdep -= 1                                                                       !   (a quoted token carries its quotes anyway).
                  of 'VIRTUAL'
                    if ~vdep then virtB = 1 ; break.
                  end
                  vdx += 1
                end
              else
                virtB = 1                                                                           ! mdx 0 = the parameter list never closed, so the
              end                                                                                   !   attribute list was never reached. Record the
                                                                                                    !   REFUSAL, not a "not virtual" we did not see.
              self.AddTypeMethod(curOwner, upper(self.TokText(x)), retU, retRefB, virtB, aMin, aMax, p1U, slotsU)
              if self.traceReg
                self.regTrace.append('METH tok ' & x & ' ' & clip(curOwner) & '.' & clip(self.TokText(x)) & ' -> '                                     |
                                     & choose(retU = '', '(none)', clip(retU)) & choose(retRefB = 1, ' ref', '') & choose(virtB = 1, ' virtual', '') & |
                                     ' args ' & aMin & '..' & aMax & choose(p1U = '', '', ' p1=' & clip(p1U))                                        & |
                                     choose(slotsU = '', '', ' slots=' & clip(slotsU)) & '<13,10>') ! arity is what tells overloads apart, so it has to be visible. the report shows the slots too
              end
            else                                                                                    ! ---- plain data field ----
              isRefB = 0 ; isLikeB = 0 ; fldTypeU = ''
              if self.TokText(t2) = '&'
                t3 = t2 + 1
                if ~self.TokIsEOL(t3) and self.IsLabelTok(self.TokText(t3))
                  isRefB = 1 ; fldTypeU = upper(self.TokText(t3))
                end
              elsif upper(self.TokText(t2)) = 'LIKE'
                t3 = t2 + 1 ; t4 = t3 + 1
                if ~self.TokIsEOL(t4) and self.TokText(t3) = '(' and self.IsLabelTok(self.TokText(t4))
                  isLikeB = 1 ; fldTypeU = upper(self.TokText(t4))
                end
              elsif self.IsLabelTok(self.TokText(t2))
                fldTypeU = upper(self.TokText(t2))
              end
              if fldTypeU
                do DeclScopeAt
                self.AddTypeField(curOwner, upper(self.TokText(x)), fldTypeU, isRefB, isLikeB, dclScope, dclTok)
              end
            end
          end
        end
      end
    end
    lvl = self.TokLevel(x)                                                                          ! level accounting over EVERY token (END/'.' carry '-')
    if lvl = '+' then depth += 1.
    if lvl = '-'
      depth -= 1
      loop while records(OwnerStackQ)
        get(OwnerStackQ, records(OwnerStackQ))
        if osq:atDepth >= depth
          if self.traceReg                                                                          !
            self.regTrace.append('POP tok ' & x & ' ' & clip(osq:ownerU) & ' atDepth ' & osq:atDepth & ' depth now ' & depth & '<13,10>')
          end
          delete(OwnerStackQ)
        else
          break
        end
      end
    end
  end
  self.regEofDepth = depth                                                                          ! non-zero depth / stack at EOF = mis-levelled scan
  self.regEofStack = records(OwnerStackQ)
  if self.traceReg
    self.regTrace.append('EOF depth ' & depth & ' stack ' & records(OwnerStackQ))
    loop while records(OwnerStackQ)                                                                 ! list stuck owners (top first)
      get(OwnerStackQ, records(OwnerStackQ))
      self.regTrace.append(' [' & clip(osq:ownerU) & '@' & osq:atDepth & ']')
      delete(OwnerStackQ)
    end
    self.regTrace.append('<13,10>')
  end
  self.tk &= saveTk                                                                                 ! restore the raw stream for subsequent Lookup/scope resolution

! WHICH SCOPE DECLARES the field sitting at token x, at the finest granularity the
! scope table has - the ROUTINE if it is inside one, else the PROCEDURE or METHOD, else 0
! for module level.
!
! ROUTINE GRANULARITY IS NOT A REFINEMENT, IT IS REQUIRED. A routine's DATA section is
! invisible to the procedure's own code, so recording a routine-local declaration as the
! PROCEDURE's would offer it to a use site that cannot see it - and then a module-level
! `zq` whose `z` is a LONG, beside a routine-local `zq` whose `z` is a STRING, leaves the
! routine's row as the only survivor at a use site in the procedure's code and converts
! `if clip(zq.z)` on a numeric - which is the wrong-output direction this whole mechanism
! exists to prevent, so the coarser answer would have re-created it inside the fix for it.
!
! 0 is a REAL ANSWER and means module level, not a failure, which is why "could not tell"
! needed a spelling of its own. Asked only on the RAW pass: on the include-expanded stream
! x indexes a different stream from the one the scope table was measured on, so any answer
! from it would be a coincidence - and answering from a coincidence is the whole defect here.
DeclScopeAt routine
  if ~pScoped
    dclScope = vs:scUnknown
    dclTok   = 0                           ! x indexes the EXPANDED stream: not a position anything else can read
  else
    dclScope = self.ScopeContaining(x, vs:scRoutine, vs:scRoutine)
    if ~dclScope then dclScope = self.ScopeContaining(x, vs:scProc, vs:scMethod).
    dclTok   = x                           ! the field's own label token, which is where a LIKE target resolves from
  end

! ------------------------------------------------------------------------------------
VitSymbols.AddTypeDef Procedure(STRING pTypeU, BYTE pKind, STRING pParentU)
  code
  if self.FindTypeDef(pTypeU) then return. ! first definition wins (dedupe across units)
  clear(self.types)
  self.types.typeU = upper(pTypeU)
  self.types.kind    = pKind
  self.types.parentU = upper(pParentU)
  self.types.fromRaw = self.regRaw
  add(self.types)

! ------------------------------------------------------------------------------------
VitSymbols.AddTypeField Procedure(STRING pOwnerU, STRING pNameU, STRING pTypeU, BYTE pIsRef, BYTE pIsLike, LONG pDeclScope, LONG pDeclTok)
  code
  clear(self.fields)
  self.fields.ownerU = upper(pOwnerU)
  self.fields.nameU = upper(pNameU)
  self.fields.fieldTypeU = upper(pTypeU)
  self.fields.isRef      = pIsRef
  self.fields.isLike     = pIsLike
  self.fields.declScope  = pDeclScope ! NO dedupe, deliberately - two procedures' same-named
                                      !   locals stay TWO rows, and the scope on each is what lets
                                      !   ResolveMember tell them apart rather than merge them here.
  self.fields.declTok    = pDeclTok   !   the token beside the scope, so a LIKE target can be looked
                                      !   up from where the field was declared.
  self.fields.fromRaw    = self.regRaw
  add(self.fields)

! ------------------------------------------------------------------------------------
! record a method prototype's return class. NO dedupe - overloads add one row each
! (a keyed GET lands on an arbitrary row of the run; fine while overloads agree on the
! return class, which they must in Clarion anyway).
! ------------------------------------------------------------------------------------
VitSymbols.AddTypeMethod Procedure(STRING pOwnerU, STRING pNameU, STRING pRetClassU, BYTE pRetRef, BYTE pIsVirtual, LONG pArgMin, LONG pArgMax, STRING pP1TypeU, STRING pSlotsU)
  code
  clear(self.methods)
  self.methods.ownerU    = upper(pOwnerU)
  self.methods.nameU     = upper(pNameU)
  self.methods.retClassU = upper(pRetClassU)
  self.methods.retRef    = pRetRef
  self.methods.isVirtual = pIsVirtual                !
  self.methods.argMin    = pArgMin                           ! still no dedupe - overloads are SUPPOSED to add a row
  self.methods.argMax    = pArgMax                           !   each, and arity is what tells them apart
  self.methods.p1TypeU   = upper(pP1TypeU)
  self.methods.pSlotsU   = upper(pSlotsU)                    !
  self.methods.fromRaw   = self.regRaw
  add(self.methods)

! ------------------------------------------------------------------------------------
! is method pNameU on class pOwnerU VIRTUAL?
!   -1  no prototype is visible at all (no CLASS body for it in this file, and no
!       --thorough include closure) - we know NOTHING about it;
!    0  a prototype is visible and no VIRTUAL appears for this name in the parentU chain;
!    1  VIRTUAL appears somewhere in that chain.
! The chain is walked WHOLE, and any virtual row wins: a derived class may re-declare an
! inherited virtual without repeating the word, and dispatch is still virtual. The only
! answer a caller may build on is 0 - both -1 and 1 mean "assume nothing".
! Overloads add one row each (AddTypeMethod does not dedupe), so the scan is linear here
! rather than a keyed GET: a keyed GET lands on an ARBITRARY row of the (owner,name) run,
! and one virtual overload has to be able to veto the whole name.
! ------------------------------------------------------------------------------------
VitSymbols.MethodIsVirtual Procedure(STRING pOwnerU, STRING pNameU)
m     long,auto
td    long,auto
seen  long,auto
curO  string(vs:maxName),AUTO
nU    string(vs:maxName),AUTO
hops  long,AUTO
  code
  self.EnsureFresh()         ! consumer gate
  if self.methods &= NULL then return -1.
  seen = 0
  curO = upper(pOwnerU)
  nU   = upper(pNameU)
  if ~curO or ~nU then return -1.
  hops = 0
  loop
    hops += 1
    if hops > 32 then break. ! inheritance cycle cap (ResolveMember's)
    loop m = 1 to records(self.methods)
      get(self.methods, m)
      if errorcode() then break.
      if self.methods.ownerU <> curO or |
         self.methods.nameU <> nU
        cycle
      end
      seen = 1
      if self.methods.isVirtual then return 1.
    end
    td = self.FindTypeDef(curO) ! not declared here - try the parent
    if ~td then break.
    get(self.types, td)
    if errorcode() then break.
    if ~self.types.parentU then break.
    curO = self.types.parentU
  end
  if ~seen then return -1.
  return 0

! ------------------------------------------------------------------------------------
VitSymbols.FindTypeDef Procedure(STRING pTypeU)
s   long,auto
nU  string(vs:maxName),AUTO
  code
  if self.regSorted then self.EnsureFresh(). ! consumer gate (skip while BuildTypeRegistry itself is running - regSorted 0)
  nU = upper(pTypeU)
  if self.regSorted                          ! keyed GET once the registry is sorted
    self.types.typeU = nU
    get(self.types, self.types.typeU)
    if errorcode() then return 0.
    return pointer(self.types)
  end
  loop s = 1 to records(self.types)          ! during BuildTypeRegistry (dedupe) - linear
    get(self.types, s)
    if self.types.typeU = nU then return s.
  end
  return 0

! ------------------------------------------------------------------------------------
! One hop: the declared type of field pNameU on type pOwnerU, walking the parentU
! (inheritance / GROUP-base) chain. '' if the owner or field is unknown.
!
! *** A LIKE FIELD'S STORED TEXT IS A NAME, NOT A TYPE. *** AddTypeField records
! `f LIKE(t)` with fieldTypeU = 't' and isLike = 1. Handing that name straight back as
! though it were a declared type is right for one of the two things that wear the
! spelling and wrong for the other:
!
!   f LIKE(SomeGroupType)   t names a TYPE. The registry knows it, and the answer
!                           really is that name.
!   f LIKE(someVariable)    t names a VARIABLE, and its type is whatever that name
!                           means WHERE THE FIELD WAS DECLARED - a scoped question.
!                           The row carries the declaration's own TOKEN, so LikeVar
!                           can ask LookupIn from there. Asking at the USE site
!                           instead would let an inner-scope shadow of the target win.
!
! Both are answered now, and the second still REFUSES wherever it cannot be answered
! honestly: declTok 0, which is the include-EXPANDED pass saying its positions mean
! nothing here; rows that do not share one declaration; a target that resolves to
! nothing. That is the same choice the disagreeing-run rule below makes and for the
! same reason - refusing costs a resolution, guessing costs the user's code. isLike
! has to AGREE across the run as well, because a run holding both spellings has no
! single answer either.
!
! pUseTok is WHERE THE QUESTION IS BEING ASKED FROM, and it is consulted on exactly one
! path: a run that disagrees. See ScopeNarrow at the foot of this procedure.
! ------------------------------------------------------------------------------------
VitSymbols.ResolveMember Procedure(STRING pOwnerU, STRING pNameU, LONG pUseTok)
f      long,auto
td     long,auto
curO   string(vs:maxName),AUTO
nU     string(vs:maxName),AUTO
hops   long,AUTO
fp     long,auto                    ! first row of the (owner, name) run
fq     long,auto
fSeen  byte,auto
fTy    string(vs:maxName)
fLk    byte,auto                    ! the run's isLike, and it must agree like the type does
clash  byte,auto                    ! this hop's run disagrees, so the run ALONE has no answer -
                                    !   the narrowing below is the only thing that can still produce one
usRt   long,auto                    ! the use site's ROUTINE scope, 0 = not inside one
usPr   long,auto                    !   ... and its proc/method scope (0 = module level - a real answer)
usOk   byte,auto                    !   ... and whether the caller told us where it was asking from
usGot  byte,auto                    ! asked already: ONE pair of lookups per call, and only on a hop that is refusing
nLevel long,auto                    ! the scope being filtered on right now - one rung of the ladder
nSeen  byte,auto                    ! narrowing: a row survived the filter
nTy    string(vs:maxName)           !   ... its type
nLk    byte,auto                    !   ... and its isLike
nClash byte,auto                    ! two survivors disagreed - then that rung has no single answer either
fDt    long,auto                    ! the run's declaration TOKEN, for resolving a LIKE(someVariable) target
fDtC   byte,auto                    !   ... and 1 when two rows that BOTH know where they were declared name
                                    !   different places, so there is no single place to ask from and the
                                    !   LIKE target is refused. A row with declTok 0 has no opinion either way
nDt    long,auto                    ! the narrowed row's declaration token, and its own agreement flag
nDtC   byte,auto
lvTy   string(vs:maxName)           ! LIKE(someVariable): what the TARGET variable is declared as
lvRef  byte,auto                    !   ... its by-reference flag, which nothing here reads
lvOk   byte,auto                    !   ... and whether the target resolved at all
  code
  curO = upper(pOwnerU)
  nU = upper(pNameU)
  hops = 0
  usGot = 0
  usRt  = 0
  usPr  = 0
  usOk  = 0
  loop
    hops += 1
    if hops > 32 then break.        ! inheritance cycle cap
    ! *** A RUN OF ROWS MAY DISAGREE, AND THEN THERE IS NO ANSWER. *** AddTypeField does not
    ! dedupe and the registry is scope-blind, so two procedures that each declare a local QUEUE
    ! of the same name contribute their fields to ONE (owner, name) run. Answering from whichever
    ! row a keyed GET happened to land on gave one procedure the other's type - measured, with the
    ! shipped rules: `if clip(lq.s)` where s is a LONG came back as `if lq.s`, which is exactly
    ! what the clip-truthiness rule exists to forbid.
    !
    ! MethodReturnClass has answered this since it was written: walk the whole run and refuse if
    ! it does not agree. Refusing costs a resolution; guessing costs the user's code.
    !
    ! a disagreeing run sets `clash` rather than ending the search, and the narrowing at the
    ! foot of this procedure asks which of its rows the USE SITE could actually see. Refusing is
    ! still where it lands unless exactly one type survives that.
    fSeen = 0
    fTy   = ''
    fLk   = 0
    fDt   = 0
    fDtC  = 0
    clash = 0
    if self.regSorted               ! keyed GET per hop instead of scanning every field
      self.fields.ownerU = curO
      self.fields.nameU  = nU
      get(self.fields, self.fields.ownerU, self.fields.nameU)
      if ~errorcode()
        fp = pointer(self.fields)
        loop fq = fp - 1 to 1 by -1 ! back to the start of the run
          get(self.fields, fq)
          if errorcode() then break.
          if self.fields.ownerU <> curO or self.fields.nameU <> nU then break.
          fp = fq
        end
        loop fq = fp to records(self.fields)
          get(self.fields, fq)
          if errorcode() then break.
          if self.fields.ownerU <> curO or self.fields.nameU <> nU then break.
          if ~fSeen
            fSeen = 1
            fTy = self.fields.fieldTypeU
            fLk = self.fields.isLike
            fDt = self.fields.declTok
          elsif self.fields.fieldTypeU <> fTy or self.fields.isLike <> fLk
            clash = 1                        ! the run disagrees - do not guess from it. one further question is asked below
            break
          elsif self.fields.declTok          ! a row that KNOWS where it was declared. A row that
            if ~fDt                          !   does not - declTok 0, the include-EXPANDED pass -
              fDt = self.fields.declTok      !   has no opinion and neither answers nor objects,
            elsif self.fields.declTok <> fDt !   which is what lets the two passes share a run.
              fDtC = 1                       ! two declarations wearing one LIKE target: the TYPE
            end                              !   agrees so this is no clash, but there is no single
          end                                !   scope to resolve that target from
        end
      end
    else
      loop f = 1 to records(self.fields)
        get(self.fields, f)
        if self.fields.ownerU <> curO then cycle.
        if self.fields.nameU <> nU then cycle.
        if ~fSeen
          fSeen = 1
          fTy = self.fields.fieldTypeU
          fLk = self.fields.isLike
          fDt = self.fields.declTok
        elsif self.fields.fieldTypeU <> fTy or self.fields.isLike <> fLk
          clash = 1               ! same rule, and the same second question, on the unsorted path
          break
        elsif self.fields.declTok ! and the same LIKE-target rule, on the unsorted path
          if ~fDt
            fDt = self.fields.declTok
          elsif self.fields.declTok <> fDt
            fDtC = 1
          end
        end
      end
    end
    if clash
      do ScopeNarrow
      if nClash or ~nSeen
        self.runClash += 1                      ! the use site cannot tell them apart either - refuse
        return ''
      end
      self.runScoped += 1                       ! narrowed to one type the use site can actually see
      fSeen = 1
      fTy   = nTy
      fLk   = nLk
      fDt   = nDt
      fDtC  = nDtC
    end
    if fSeen
      if ~fLk then return fTy.
      if self.FindTypeDef(fTy) then return fTy. ! LIKE(SomeType) - the name IS a type
      do LikeVar                                ! LIKE(someVariable) - ask what THAT was declared as
      if lvOk then return lvTy.
      return ''
    end
    td = self.FindTypeDef(curO)                 ! not a direct member - try the parent
    if ~td then break.
    get(self.types, td)
    if ~self.types.parentU then break.
    curO = self.types.parentU
  end
  return ''

! WHAT TO DO WITH A RUN THAT DISAGREES.
!
! A run only ever disagrees because the registry is SCOPE-BLIND about owners. Two
! procedures that each declare a local QUEUE called Line - an entirely ordinary thing to
! write - contribute their fields to one (owner,name) run. Answering from whichever row a
! keyed GET lands on gives one procedure the OTHER's type, and the output that produces is
! `if clip(lq.s)` becoming `if lq.s` where s is a LONG - the exact conversion the clip-truthiness rule
! exists to forbid. Refusing the whole run is the correct answer to a question with no
! single answer, and it costs the procedure whose field really IS a STRING the conversion
! it earns on its own merits.
!
! So ask the question the run cannot: WHICH OF THESE ROWS IS DECLARED WHERE THE USE SITE
! CAN SEE IT. Answer only when exactly one TYPE survives - one type, not one row, because
! two surviving rows that agree are not an ambiguity - and refuse otherwise.
!
! THE SAFETY PROPERTY, and it is what keeps this small: it runs ONLY where the code above
! has already decided to refuse, so it can turn a refusal into an answer and can never
! turn one answer into a different one. The dangerous direction is attributing a scope
! WRONGLY and converting with the wrong type, which is the defect above again - and the exactly-one rule
! is the guard on it.
!
! IT ASKS INNERMOST-OUT, WHICH IS HOW CLARION ITSELF RESOLVES A NAME. The ROUTINE the use
! site sits in first; the PROCEDURE only when the routine declared nothing in this run,
! because a routine sees its procedure's locals but a procedure cannot see its routines'
! DATA; then MODULE level, which every scope in the file can see. LookupIn's own ladder.
!
! THE MODULE RUNG ASSUMES THE SOURCE WOULD COMPILE. The head that reached here was
! resolved by the scope-BLIND FindTypeDef, so "nothing nearer declares this name, so it
! is the module-level one" holds only of a legal program. It is admitted because it can
! only make this procedure ANSWER where it would otherwise refuse, never answer
! DIFFERENTLY - on a fragment the rung finds nothing and the refusal stands.
!
! Three ways for nothing to survive, all landing on the refusal above:
!   - the caller passed no use site (pUseTok 0), so it never said where it was asking from;
!   - no rung of the ladder holds a row of this run;
!   - every row carries vs:scUnknown, which is a run made up entirely of rows that arrived
!     through an INCLUDE. scUnknown is NEGATIVE and a scope id never is, so those rows fail
!     the test below without needing a case of their own - and a run that also holds a row
!     read from THIS file is narrowed on that row alone, which is the point.
ScopeNarrow routine
  if ~usGot                             ! one pair of lookups per CALL, not per hop, and only ever
    usGot = 1                            !   on a hop that has already decided to refuse
    if pUseTok > 0
      usRt = self.ScopeContaining(pUseTok, vs:scRoutine, vs:scRoutine)
      usPr = self.ScopeContaining(pUseTok, vs:scProc, vs:scMethod)
      usOk = 1                           ! 0 back from the second is MODULE LEVEL, which is an answer
    end
  end
  nSeen  = 0
  nTy    = ''
  nLk    = 0
  nClash = 0
  nDt    = 0
  nDtC   = 0
  if usOk
    if usRt                              ! rung 1: this routine's own DATA
      nLevel = usRt
      do NarrowRun
    end
    if ~nSeen                            ! rung 2, only when rung 1 held nothing at all: the
      nLevel = usPr                      !   procedure's locals, which its routines can see too
      do NarrowRun
    end
    if ~nSeen and usPr                   ! rung 3: MODULE level, which every scope in the file can
      nLevel = 0                         !   see. usPr 0 already IS module level, so rung 2 asked
      do NarrowRun                       !   it in that case and this rung adds nothing
    end
  end

NarrowRun routine
  data
sx  long,auto
  code
  if self.regSorted
    loop sx = fp to records(self.fields) ! fp is the run's first row - set by the keyed branch above
      get(self.fields, sx)
      if errorcode() then break.
      if self.fields.ownerU <> curO or self.fields.nameU <> nU then break.
      do NarrowRow
    end
  else
    loop sx = 1 to records(self.fields)
      get(self.fields, sx)
      if errorcode() then break.
      if self.fields.ownerU <> curO or self.fields.nameU <> nU then cycle.
      do NarrowRow
    end
  end

NarrowRow routine
  if self.fields.declScope = nLevel
    if ~nSeen
      nSeen = 1
      nTy   = self.fields.fieldTypeU
      nLk   = self.fields.isLike
      nDt   = self.fields.declTok
    elsif self.fields.fieldTypeU <> nTy or self.fields.isLike <> nLk
      nClash = 1 ! two declarations at this rung, disagreeing: no answer here either
    elsif self.fields.declTok
      if ~nDt
        nDt = self.fields.declTok
      elsif self.fields.declTok <> nDt
        nDtC = 1 ! agreeing rows from two declarations: fine for the TYPE, no good for a LIKE target
      end
    end
  end

! LIKE(someVariable): the field's recorded text is the TARGET'S NAME, and its type is
! whatever that name means WHERE THE FIELD WAS DECLARED. Asking at the use site instead
! would let an inner-scope shadow of the target win and hand the field a type its own
! declaration never had - the same trap LookupIn's own LIKE arm avoids.
!
! It refuses on two inputs and both are deliberate: declTok 0, which is the include-EXPANDED
! pass saying its positions mean nothing here; and a run whose rows do not share one
! declaration, where the type agreed but there is no single scope to resolve the target in.
! A target that resolves to nothing leaves lvOk 0 and the caller refuses exactly as before.
LikeVar routine
  lvOk  = 0
  lvTy  = ''
  lvRef = 0
  if fDtC or ~fDt then exit.
  lvOk = self.LookupIn(clip(fTy), fDt, lvTy, lvRef, 1)
  if lvOk and ~lvTy then lvOk = 0.

! ------------------------------------------------------------------------------------
! could a call carrying pArgCount arguments BE this prototype?
! Refusing to answer is spelled -1 in both directions and always means YES here: an
! unreadable parameter list, or a caller that does not know its own argument count,
! must not silently exclude a row - that would turn "I cannot tell" into "not this one".
! ------------------------------------------------------------------------------------
VitSymbols.ArityAdmits Procedure(LONG pArgMin, LONG pArgMax, LONG pArgCount)
  code
  if pArgCount < 0 or |   ! caller does not know - every row stays in play
     pArgMin < 0 or pArgMax < 0 ! prototype unreadable - same
    return 1
  end
  if pArgCount < pArgMin or |
     pArgCount > pArgMax
    return 0
  end
  return 1

! ------------------------------------------------------------------------------------
! the tie ARITY cannot break. JoinToks is declared
!     (LONG pStart=1, LONG pEnd=0, <STRING pFormat>),STRING       -> 0..3 args
!     (StringTheory st, LONG pStart=1, LONG pEnd=0, <STRING>)     -> 1..4 args
! and those overlap at 1, 2 and 3, so arity alone had to refuse. What separates them is the
! FIRST PARAMETER'S TYPE - StringTheory against LONG - so this admits a row only when
! the call's first argument could actually BE that parameter.
!
! It narrows ONLY on a positive determination. An EMPTY slot means the caller could not
! type the argument, and then every row stays in play and the run refuses just as arity alone would
! did. That direction matters: an identifier we merely FAILED to resolve might well be the
! class instance, and excluding the class-typed row on that basis would pick the
! STRING-returning overload and license a rewrite on a call that never returns a string.
! ------------------------------------------------------------------------------------
! could THIS CALL be this prototype?  Was P1Admits, which asked the same question of
! ARGUMENT ONE ONLY. Both sides now carry every position: pSlotsU is the prototype's parameter
! types and pArgTypesU is what the caller could work out about its arguments, each '|'-terminated
! and in order.
!
! WHY THIS ONLY EVER RESOLVES MORE, NEVER LESS. Each position is tested independently and an
! unknown NEVER narrows - an empty argument slot, an empty parameter slot, or a slot list we
! could not record all of, all return "admits". So a call that resolved on argument one still
! resolves; a call that was ambiguous may now be settled by a later argument; a call where
! nothing is typeable is refused exactly as before. There is no input on which this admits
! fewer prototypes than P1Admits did.
!
! The principle is export-style decoration: identify a prototype by its parameter TYPES,
! because names and defaults drift between a declaration and its definition and types do
! not. What is deliberately NOT taken from decoration is the whole signature as an
! all-or-nothing KEY. That form fits matching a DEFINITION to its DECLARATION, where both
! sides carry full types. A call site has expressions, not types, so an all-or-nothing key
! would match nothing; per-position narrowing is the form that works here.
VitSymbols.ArgAdmits Procedure(STRING pSlotsU, LONG pArgCount, STRING pArgTypesU)
n     long,auto               ! position under test, 1-based
aPos  long,auto               ! scan cursor into pArgTypesU
sPos  long,auto               !   ... and into pSlotsU
aTok  string(vs:maxName),auto ! the caller's type for this position
sTok  string(vs:maxName),auto ! the prototype's type for this position
  code
  if pArgCount < 1 or |   ! nothing to test
     ~pArgTypesU   or |   ! caller could type NOTHING - do not narrow
     ~pSlotsU                 ! prototype's parameter types unreadable - same
    return 1
  end
  aPos = 1 ; sPos = 1
  loop n = 1 to pArgCount
    do NextArg                ! aPos -> aTok
    do NextSlot               ! sPos -> sTok
    if ~aTok       or |   ! this argument could not be typed - no opinion
       ~sTok                                   ! ran off the end of the slot list - ditto
      cycle
    end
    if aTok = vs:scalarArg                     ! a numeric or quoted LITERAL: definitely a value,
      if self.FindTypeDef(sTok) then return 0. !   so a parameter wanting a class instance is out
      cycle
    end
    if aTok <> sTok then return 0.
  end
  return 1

NextArg routine
  aTok = ''
  loop while aPos <= size(pArgTypesU)
    if pArgTypesU[aPos] = '|' then aPos += 1 ; break.
    if pArgTypesU[aPos] = ' ' and ~aTok then aPos += 1 ; cycle.
    aTok = clip(aTok) & pArgTypesU[aPos]
    aPos += 1
  end

NextSlot routine
  sTok = ''
  loop while sPos <= size(pSlotsU)
    if pSlotsU[sPos] = '|' then sPos += 1 ; break.
    if pSlotsU[sPos] = ' ' and ~sTok then sPos += 1 ; cycle.
    sTok = clip(sTok) & pSlotsU[sPos]
    sPos += 1
  end

! ------------------------------------------------------------------------------------
! the return class of method pNameU on class pOwnerU, walking the parentU chain
! (a row found on a derived class shadows the parent, matching Clarion dispatch).
! '' = method unknown OR known with no return type; pIsRef reports a * / & return.
! ------------------------------------------------------------------------------------
VitSymbols.MethodReturnClass Procedure(STRING pOwnerU, STRING pNameU, *BYTE pIsRef, LONG pArgCount, STRING pArgTypesU)
m     long,auto
td    long,auto
curO  string(vs:maxName),AUTO
nU    string(vs:maxName),AUTO
hops  long,AUTO
p     long,auto                   ! overload run: the row the keyed GET landed on
rc    string(vs:maxName)          !   its return class, and AUTO unsafe: read before write
rr    byte                        !   its ref flag - both must hold across the WHOLE run AUTO unsafe: read before write
seenA byte,auto                   ! linear branch: first matching row found
  code
  self.EnsureFresh()              ! consumer gate
  pIsRef = 0
  curO = upper(pOwnerU)
  nU = upper(pNameU)
  hops = 0
  loop
    hops += 1
    if hops > 32 then break.      ! inheritance cycle cap
    if self.regSorted             ! keyed GET per hop, like ResolveMember
      self.methods.ownerU = curO
      self.methods.nameU  = nU
      get(self.methods, self.methods.ownerU, self.methods.nameU)
      if ~errorcode()             ! this lands on ONE row of an OVERLOAD RUN, and AddTypeMethod
        p = pointer(self.methods) !   deliberately does not dedupe - overloads are correct Clarion
        loop m = p - 1 to 1 by -1 !   and the return class belongs to the OVERLOAD, not the name.
          get(self.methods, m)    !   Walk to the start of the run; owner+name alone bound it.
          if errorcode() then break.
          if self.methods.ownerU <> curO then break.
          if self.methods.nameU <> nU then break.
          p = m
        end
        seenA = 0
        loop m = p to records(self.methods)
          get(self.methods, m)
          if errorcode() then break.
          if self.methods.ownerU <> curO then break.
          if self.methods.nameU <> nU then break.
          if ~self.ArityAdmits(self.methods.argMin, self.methods.argMax, pArgCount) then cycle.
          if ~self.ArgAdmits(self.methods.pSlotsU, pArgCount, pArgTypesU) then cycle. ! every position, not just the first
          if ~seenA
            seenA = 1
            rc = self.methods.retClassU
            rr = self.methods.retRef
          elsif self.methods.retClassU <> rc or self.methods.retRef <> rr
            pIsRef = 0                                                                ! two overloads BOTH admit this call and disagree - e.g. JoinToks,
            return ''                                                                 !   whose two forms overlap at 1..3 args once defaults and <> are
          end                                                                         !   counted. Refuse rather than guess; the first parameter's TYPE
        end                                                                           !   is what separates those, and that is the next step.
        if seenA
          pIsRef = rr
          return rc
        end
      end
    else
      seenA = 0
      loop m = 1 to records(self.methods)                                             ! same rule on the pre-sort linear path
        get(self.methods, m)
        if errorcode() then break.
        if self.methods.ownerU <> curO then cycle.
        if self.methods.nameU <> nU then cycle.
        if ~self.ArityAdmits(self.methods.argMin, self.methods.argMax, pArgCount) then cycle.
        if ~self.ArgAdmits(self.methods.pSlotsU, pArgCount, pArgTypesU) then cycle.   ! this branch had the
                                                                                      !   arity test but NOT the type
                                                                                      !   one - the two paths have to
                                                                                      !   answer the same question.
        if ~seenA
          seenA = 1
          rc = self.methods.retClassU
          rr = self.methods.retRef
        elsif self.methods.retClassU <> rc or self.methods.retRef <> rr
          pIsRef = 0
          return ''
        end
      end
      if seenA
        pIsRef = rr
        return rc
      end
    end
    td = self.FindTypeDef(curO) ! not declared here - try the parent
    if ~td then break.
    get(self.types, td)
    if ~self.types.parentU then break.
    curO = self.types.parentU
  end
  return ''

! ------------------------------------------------------------------------------------
! Walk a '|'-delimited member chain from a head type to its terminal type.
! e.g. LookupChain('DRIVERFILECLASS','REQUESTDATA|DATASTRINGTHEORY') -> 'STRINGTHEORY'.
! '' if any hop is unresolvable (caller then leaves the receiver un-converted).
! pUseTok is the token the caller is asking ABOUT, passed down to EVERY hop: the
! narrowing is not a property of the first hop, it is a property of where the question was
! asked, and a disagreeing run can turn up at any depth of the chain.
! ------------------------------------------------------------------------------------
VitSymbols.LookupChain Procedure(STRING pHeadTypeU, STRING pSegsBar, LONG pUseTok)
cur   string(vs:maxName),AUTO
seg   StringTheory
i     long,auto
  code
  self.EnsureFresh()                      ! consumer gate
  cur = upper(pHeadTypeU)
  if ~cur then return ''.
  seg.setValue(pSegsBar,st:clip)
  if ~seg._DataEnd then return clip(cur). ! no segments - head is already the type
  seg.split('|',,,,st:clip)
  loop i = 1 to seg.records()
    seg.setValueFromLine(i)
    if ~seg._DataEnd then cycle.
    cur = self.ResolveMember(cur, seg.getValue(), pUseTok)
    if ~cur then return ''.
  end
  return clip(cur)

! ------------------------------------------------------------------------------------
! ------------------------------------------------------------------------------------
! A method-implementation label 'Class.Method' is a SINGLE column-1 token (the '.' only
! splits in expression context), and IsLabelTok rejects it (no '.' in a label). Recognise
! it so Build can create the method scope + SELF. Returns the first '.' position, or 0.
! ------------------------------------------------------------------------------------
VitSymbols.IsDottedLabel Procedure(STRING pTok)
p     long,auto
tLen  long,auto
  code
  tLen = len(clip(pTok))
  p = instring('.', clip(pTok), 1, 1)
  if p < 2 or p >= tLen then return 0.                                 ! no '.', or leading/trailing '.'
  if ~self.IsLabelTok(sub(clip(pTok), 1, p - 1)) then return 0.        ! receiver-class part
  if ~self.IsLabelTok(sub(clip(pTok), p + 1, tLen - p)) then return 0. ! method part (single '.'; nested dots not treated as method labels)
  return p

! ------------------------------------------------------------------------------------
VitSymbols.ColOneMethodDot Procedure(LONG pIx)
  code
  get(self.tk.tokens, pIx)
  if errorcode() then return 0.
  if ~self.tk.tokens.firstOnLine then return 0.
  if not self.tk.tokens.strBefore &= NULL then return 0.               ! any leading trivia = not column 1
  if self.tk.tokens.tok &= NULL then return 0.
  return self.IsDottedLabel(clip(self.tk.tokens.tok))

! ------------------------------------------------------------------------------------
VitSymbols.StructKind Procedure(STRING pKwU)
  code
  case upper(pKwU)
  of 'GROUP'  ; return vs:tkGroup
  of 'QUEUE'  ; return vs:tkQueue
  of 'CLASS'  ; return vs:tkClass
  of 'RECORD' ; return vs:tkRecord
  end
  return 0

! ------------------------------------------------------------------------------------
VitSymbols._ListTypes Procedure(StringTheory pOut)
s   long,auto
f   long,auto
  code
  pOut.append('--- type registry: ' & records(self.types) & ' type(s), ' & records(self.fields) & ' field(s), ' & records(self.methods) & ' method(s) ---<13,10>')
  loop s = 1 to records(self.types)
    get(self.types, s)
    pOut.append('TYPE ' & clip(self.types.typeU) & ' (kind ' & self.types.kind & ')')
    if self.types.parentU then pOut.append(' : ' & clip(self.types.parentU)).
    pOut.append('<13,10>')
    loop f = 1 to records(self.fields)
      get(self.fields, f)
      if self.fields.ownerU <> self.types.typeU then cycle.
      pOut.append('    .' & clip(self.fields.nameU) & ' ' & choose(self.fields.isRef=1,'&','')                    & |
                  choose(self.fields.isLike=1,'LIKE ','') & clip(self.fields.fieldTypeU)                          & |
                  ' [scope ' & choose(self.fields.declScope = vs:scUnknown, 'unknown',                              |
                                      choose(self.fields.declScope = 0, 'module', 'id ' & self.fields.declScope)) & |
                  ']<13,10>') ! a duplicate (owner,name) run is only readable in a dump if the rows say where they came from
    end
    loop f = 1 to records(self.methods)                                                                     !
      get(self.methods, f)
      if self.methods.ownerU <> self.types.typeU then cycle.
      ! show the ARITY and the SLOTS. This line printed a bare '()' for every method,
      ! which says nothing about how two overloads differ - and it had me reading
      ! `.PICKIT() -> STRING` / `.PICKIT() -> LONG` as evidence the parameter list had not been
      ! parsed, when the registry trace showed it had. A dump that cannot distinguish the rows
      ! it is dumping is worse than no dump.
      pOut.append('    .' & clip(self.methods.nameU)                                                               & |
                  '(' & choose(self.methods.argMin < 0, '?', clip(self.methods.pSlotsU)) & ')'                     & |
                  choose(self.methods.argMin < 0, '', ' args ' & self.methods.argMin & '..' & self.methods.argMax) & |
                  ' -> ' & choose(self.methods.retRef=1,'ref ','')                                                 & |
                  choose(self.methods.retClassU = '', '(none)', clip(self.methods.retClassU)) & '<13,10>')
    end
  end

! ------------------------------------------------------------------------------------
VitSymbols.EnsureFresh Procedure()
  code
  if ~self.dirty then return.      ! byte test on the hot path; rebuild only when an edit intervened
  self.dirty = 0                   ! before Build (which also clears) - belt and braces against re-entry
  if not self.tk &= NULL then self.Build(self.tk).

! ------------------------------------------------------------------------------------
VitSymbols.Lookup Procedure(STRING pName, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef)
  code
  self.EnsureFresh()               ! every matcher path funnels through here / LookupChain / FindTypeDef
  return self.LookupIn(upper(clip(pName)), pTokPos, pTypeU, pIsRef, 0)

! ------------------------------------------------------------------------------------
VitSymbols.LookupIn Procedure(STRING pNameU, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef, LONG pDepth)
sc   long,auto
sym  long,auto
tgt  STRING(vs:maxName)
  code
  if pDepth > 8 then return false. ! LIKE cycle cap
  ! innermost-out: routine -> procedure/method -> module
  sc = self.ScopeContaining(pTokPos, vs:scRoutine, vs:scRoutine)
  if sc
    sym = self.FindSym(pNameU, sc)
    if sym then do Resolve.
  end
  sc = self.ScopeContaining(pTokPos, vs:scProc, vs:scMethod)
  if sc
    sym = self.FindSym(pNameU, sc)
    if sym then do Resolve.
  end
  sc = self.ScopeContaining(pTokPos, vs:scModule, vs:scModule)
  if sc
    sym = self.FindSym(pNameU, sc)
    if sym then do Resolve.
  end
  return false

Resolve routine
  data
dTok long,auto
  code
  get(self.syms, sym)
  if self.syms.isLike
    tgt  = self.syms.typeU
    dTok = self.syms.declTok ! resolve the LIKE target at the DECLARATION site: resolving at the USE site lets an inner-scope shadow of the target win, which is a wrong type and then a wrong typed rewrite
    return self.LookupIn(clip(tgt), dTok, pTypeU, pIsRef, pDepth + 1)
  end
  pTypeU = self.syms.typeU
  pIsRef = self.syms.isRef
  return true

! ------------------------------------------------------------------------------------
VitSymbols.ScopeContaining Procedure(LONG pTokPos, BYTE pKind1, BYTE pKind2)
s  long,auto
  code
  ! scopes of one kind never overlap, so the first hit is the scope
  loop s = 1 to records(self.scopes)
    get(self.scopes, s)
    if self.scopes.kind <> pKind1 and self.scopes.kind <> pKind2 then cycle.
    if pTokPos >= self.scopes.startTok and pTokPos <= self.scopes.endTok
      return self.scopes.scopeId
    end
  end
  return 0

! ------------------------------------------------------------------------------------
VitSymbols.FindSym Procedure(STRING pNameU, LONG pScopeId)
  code
  ! syms is sorted (scopeId,nameU) at Build end and FindSym only runs post-Build
  ! (LookupIn) - the keyed GET binary-searches instead of scanning every symbol.
  self.syms.scopeId = pScopeId
  self.syms.nameU   = pNameU
  get(self.syms, self.syms.scopeId, self.syms.nameU)
  if errorcode() then return 0.
  return pointer(self.syms)

! ------------------------------------------------------------------------------------
VitSymbols.AddScope Procedure(BYTE pKind, LONG pParent, LONG pStartTok, STRING pSelfClass)
  code
  clear(self.scopes)
  self.scopes.scopeId   = records(self.scopes) + 1
  self.scopes.kind      = pKind
  self.scopes.parentId  = pParent
  self.scopes.startTok  = pStartTok
  self.scopes.endTok    = 0
  self.scopes.selfClass = pSelfClass
  add(self.scopes)
  return self.scopes.scopeId

! ------------------------------------------------------------------------------------
VitSymbols.AddSym Procedure(STRING pNameU, LONG pScope, STRING pTypeU, BYTE pIsRef, BYTE pIsLike, LONG pDeclTok, BYTE pIsField=0)
  code
  clear(self.syms)
  self.syms.nameU   = pNameU
  self.syms.scopeId = pScope
  self.syms.typeU   = pTypeU
  self.syms.isRef   = pIsRef
  self.syms.isLike  = pIsLike
  self.syms.declTok = pDeclTok
  self.syms.isField = pIsField
  add(self.syms)

! ------------------------------------------------------------------------------------
! Parameter list: (TYPE name, *TYPE name, <TYPE name>, &TYPE name ...)
! type-first then name; '*' '<' '>' '&' markers skipped; unnamed prototype
! parameters add nothing. STRING(20)-style sizes handled by depth tracking.
! ------------------------------------------------------------------------------------
VitSymbols.ParseParams Procedure(LONG pOpenTok, LONG pScope)
x       long,auto
depth   long,auto
typeU   STRING(vs:maxName)
nameU   STRING(vs:maxName)
t       StringTheory
  code
  depth = 1
  x = pOpenTok
  loop
    x += 1
    if x > self.tk.records() then break.
    if self.TokIsEOL(x) then break.
    t.setValue(self.TokText(x))
    case val(t.getValue())
    of 40                         ! '('
      depth += 1
    of 41                         ! ')'
      depth -= 1
      if ~depth
        do FlushParam
        break
      end
    of 44                         ! <comma>
      if depth = 1
        do FlushParam
        typeU = ''
        nameU = ''
      end
    of 42 orof 60 orof 62 orof 38 ! '*' orof '<<' orof '>' orof '&'
      ! by-ref / omittable / reference markers. The tokenizer MERGES '*'+TYPE into ONE
      ! token ('*CSTRING') whenever it follows '(' ',' or '<' with no space - the
      ! universal spelling on definition lines - and val() dispatches on the FIRST
      ! byte, so the merged token lands in this arm WHOLE. Skipping it whole made
      ! every by-ref parameter invisible: the NAME then filled typeU, nameU stayed
      ! blank, and FlushParam added nothing - so a body reference to the parameter
      ! fell through to module scope, where a same-named global of a DIFFERENT type
      ! could resolve instead. Strip the one-byte marker and keep the type.
      if depth = 1 and t._DataEnd > 1 and ~typeU
        if self.IsLabelTok(t.valuePtr[2 : t._DataEnd])
          typeU = upper(t.valuePtr[2 : t._DataEnd])
        end
      end
    else
      if depth = 1 and self.IsLabelTok(t.getValue())
        if ~typeU
          typeU = upper(t.getValue())
        elsif ~nameU
          nameU = upper(t.getValue())
        end
      end
    end
  end

FlushParam routine
  if typeU and nameU
    self.AddSym(nameU, pScope, typeU, 0, 0, x)
  end

! ------------------------------------------------------------------------------------
VitSymbols._List Procedure(StringTheory pOut)
s  long,auto
  code
  pOut.free()
  pOut.append('Scopes: ' & records(self.scopes) & '<13,10>')
  loop s = 1 to records(self.scopes)
    get(self.scopes, s)
    pOut.append('  ' & self.scopes.scopeId & ' kind=' & self.scopes.kind & ' parent=' & self.scopes.parentId     & |
                ' toks ' & self.scopes.startTok & '..' & self.scopes.endTok                                      & |
                choose(self.scopes.selfClass <> '', ' self=' & clip(self.scopes.selfClass), '') & '<13,10>')
  end
  pOut.append('Symbols: ' & records(self.syms) & '<13,10>')
  loop s = 1 to records(self.syms)
    get(self.syms, s)
    pOut.append('  ' & clip(self.syms.nameU) & '  scope ' & self.syms.scopeId & '  '                             & |
                choose(self.syms.isRef, '&', '') & choose(self.syms.isLike, 'LIKE ', '') & clip(self.syms.typeU) & |
                '  @tok ' & self.syms.declTok & '<13,10>')
  end

! ------------------------------------------------------------------------------------
VitSymbols.TokText Procedure(LONG pIx)
  code
  if pIx < 1 or pIx > self.tk.records() then return ''.
  get(self.tk.tokens, pIx)
  if errorcode() then return ''.
  if self.tk.tokens.tok &= NULL then return ''.
  return clip(self.tk.tokens.tok)

! ------------------------------------------------------------------------------------
VitSymbols.TokIsEOL Procedure(LONG pIx)
  code
  if pIx < 1 or pIx > self.tk.records() then return true.
  get(self.tk.tokens, pIx)
  if errorcode() then return true.
  if self.tk.tokens.tok &= NULL then return true.
  if self.tk.tokens.tok = '<10>' then return true.
  return false

! ------------------------------------------------------------------------------------
VitSymbols.TokLevel Procedure(LONG pIx)
  code
  if pIx < 1 or pIx > self.tk.records() then return ''.
  get(self.tk.tokens, pIx)
  if errorcode() then return ''.
  return self.tk.tokens.level

! ------------------------------------------------------------------------------------
VitSymbols.IsColOneLabel Procedure(LONG pIx)
  code
  get(self.tk.tokens, pIx)
  if errorcode() then return false.
  if ~self.tk.tokens.firstOnLine then return false.
  if not self.tk.tokens.strBefore &= NULL then return false. ! any leading trivia = not column 1
  if self.tk.tokens.tok &= NULL then return false.
  return self.IsLabelTok(clip(self.tk.tokens.tok))

! ------------------------------------------------------------------------------------
VitSymbols.IsLabelTok Procedure(STRING pTok)
x    long,auto
c    long,auto
  code
  if ~pTok then return false.
  loop x = 1 to len(clip(pTok))
    c = val(pTok[x])
    case c
    of   65 to 90  ! A-Z
    orof 97 to 122 ! a-z
    orof 95        ! _
    of   48 to 57  ! 0-9
    orof 58        ! :
      if x = 1 then return false.
    else
      return false
    end
  end
  return true
