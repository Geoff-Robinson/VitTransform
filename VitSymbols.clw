! VitSymbols - the symbol table and type registry of VitTransform
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
  self.mapProtos &= new MapProtoQType
  self.syms   &= new SymQType
  self.hidden &= new HideQType
  self.incDecl &= new IncDeclQType
  self.incProtos &= new IncProtoQType
  self.types  &= new TypeDefQType
  self.fields &= new TypeFieldQType
  self.methods &= new TypeMethodQType !
  self.pmQ &= new ProtoMemoQType
  self.regTrace &= new StringTheory   ! registry decision trace
  self.tk     &= NULL
  self.expTk  &= NULL                 ! not owned; engine points this at its expanded stream
  self.stMeth &= NULL                 ! not owned; the engine's list of StringTheory's methods
  self.hdrBuilt = 0

! ------------------------------------------------------------------------------------
VitSymbols.Destruct Procedure()
  code
  if not self.pmQ &= NULL
    free(self.pmQ)
    dispose(self.pmQ)
  end
  if not self.scopes &= NULL
    free(self.scopes)
    dispose(self.scopes)
    free(self.mapProtos)
    dispose(self.mapProtos)
  end
  if not self.syms &= NULL
    free(self.syms)
    dispose(self.syms)
  end
  if not self.hidden &= NULL
    free(self.hidden)
    dispose(self.hidden)
  end
  if not self.incDecl &= NULL
    free(self.incDecl)
    dispose(self.incDecl)
  end
  if not self.incProtos &= NULL
    free(self.incProtos)
    dispose(self.incProtos)
  end
  if not self.types &= NULL
    free(self.types)
    dispose(self.types)
  end
  if not self.fields &= NULL
    free(self.fields)
    dispose(self.fields)
  end
  if not self.methods &= NULL  !
    free(self.methods)
    dispose(self.methods)
  end
  if not self.regTrace &= NULL
    dispose(self.regTrace)     !
  end

! ------------------------------------------------------------------------------------
VitSymbols.Build Procedure(VitTokenize pTk)
N          long,auto
x          long,AUTO
t2         long,auto
t3         long,auto
t4         long,auto
bdT0       long,auto          ! --timing
t5         long,auto
selfForm   byte,auto
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
mapBlock   byte               ! ... and it is a MAP or a MODULE: every prototype line in it (MapProtoAt) is counted
                              ! by name for the overload test (VitEngine.SummaryOfCallAt)
modScope   long,auto
fldPre     string(vs:maxName) ! field typing: PRE prefix of the structure being skipped ('' = none)
fldScope   long               ! scope receiving its PRE:name field symbols
lvl        string(1),auto
dotPos     long,auto          ! '.' position inside a Class.Method label token
fldBare    byte               ! a PRE() structure: its fields are named bare, with no prefix
fldDimAt   long               ! field capture: the block depth from which fields sit in a DIM'd structure
fldOff     long               ! field capture: the block depth from which fields carry a nested PRE of their own
fldExt     byte               ! field capture: the structure is declared EXTERNAL, DLL or EXPORT
declLnk    byte               ! the declaration just read carries EXTERNAL, DLL or EXPORT (LinkedDecl)
lastProc   long               ! the latest procedure scope - a local class's methods follow it
  code
  bdT0 = clock()
  self.tk &= pTk
  free(self.scopes)
  free(self.mapProtos)
  self.mapIncl = 0
  free(self.syms)
  free(self.hidden)
  N = pTk.records()
  modScope  = self.AddScope(vs:scModule, 0, 1, '')
  dataScope = modScope
  self.isMember = 1
  loop x = 1 to N                                                    ! the module statement: the first MEMBER or PROGRAM in the file
    if self.TokIsEOL(x) or self.IsColOneLabel(x) then cycle.         !   a word in column 1 is a label, not the statement
    case upper(self.TokText(x))
    of 'MEMBER'
      break
    of 'PROGRAM'
      self.isMember = 0
      break
    end
  end
  x = 0
  loop
    x += 1
    if x > N then break.
    if self.TokIsEOL(x) then cycle.

    if blockDepth > 0                                                ! inside GROUP/QUEUE/CLASS/MAP/... - skip whole block
      if self.IsColOneLabel(x) or self.ColOneMethodDot(x)            ! resync: a procedure/method/routine is never inside a data
        t2 = x + 1                                                   ! structure, so if we see one at column 1 the block's END was
        if ~self.TokIsEOL(t2)                                        ! mis-levelled (e.g. a single-line 'g GROUP(t),AUTO.' whose
          w2.setValue(upper(self.TokText(t2)))                       ! inline '.' terminator carries no '-' level) - recover here
          if (w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'PROCEDURE' or w2._DataEnd = 8 and w2.valuePtr[1 : 8] = 'FUNCTION') and (~protoBlock or self.ColOneMethodDot(x))
            blockDepth = 0                                           ! a proc inside a DATA structure => the block's END was mis-levelled.
                                                                     ! A DOTTED label (Class.Method) is never a prototype, so it resyncs
                                                                     ! even inside a MAP/CLASS - as BuildTypeRegistry already does
          elsif w2._DataEnd = 7 and w2.valuePtr[1 : 7] = 'ROUTINE' or w2._DataEnd = 1 and w2.valuePtr[1] = '.'
            blockDepth = 0                                           ! rather than blanking symbol resolution to the next stray '-'
          end                                                        ! NB. inside a MAP/CLASS (protoBlock=1) a col-1 PROCEDURE/FUNCTION is a
                                                                     ! legitimate PROTOTYPE, not a definition - do NOT break out of the block
        end
      end
      if ~blockDepth then fldPre = ''.                               ! resync fired (mis-levelled structure) - stop field capture
      if ~blockDepth then fldBare = 0 ; fldDimAt = 0 ; fldOff = 0.
      if blockDepth > 0                                              ! still in a block: count levels and skip
        if mapBlock and self.MapProtoAt(x) then self.AddMapProto(upper(self.TokText(x)), self.MapProtoRetAt(x), x).
        if mapBlock and upper(self.TokText(x)) = 'INCLUDE'
          self.mapIncl = 1
        end
        if fldPre and self.IsColOneLabel(x)                          ! field typing: a PRE(p) structure publishes
          t2 = x + 1                                                 ! every field as the single token p:name - register it
          if ~self.TokIsEOL(t2)                                      ! as a typed symbol in the scope that owns the structure
            if self.TokLevel(t2) = '+'                               ! nested structure opener: its fields keep the OUTER
              t3 = t2 + 1                                            ! prefix (Clarion PRE spans the whole structure), but a
              loop while ~self.TokIsEOL(t3)                          ! nested PRE of its own means composition - bail for the
                if upper(self.TokText(t3)) = 'PRE' then fldPre = ''. ! rest of the block (conservative under-reach)
                t3 += 1
              end
            else
              w2.setValue(upper(self.TokText(t2)))
              do ExtractDeclType
              if typeU._DataEnd
                self.AddSym(clip(fldPre) & ':' & upper(clip(self.TokText(x))), fldScope, typeU.getValue(), isRef, isLike, x, 1, fldExt) ! clip! fldPre is a padded STRING - unclipped it bakes the
                                                                                                                                        !   padding into the symbol name and every lookup of it misses
                if fldDimAt then do DimHeld.                         ! a field of a DIM'd structure is an array
              end
            end
          end
        end
        if fldBare and self.IsColOneLabel(x) then do BareField.      ! PRE(): fields named bare
        if (fldPre or fldBare) and ~fldDimAt then do NestDim.        ! a nested DIM
        lvl = self.TokLevel(x)
        if lvl = '+' then blockDepth += 1.
        if lvl = '-' then blockDepth -= 1.
        if lvl = '-' and fldDimAt > blockDepth then fldDimAt = 0.    ! that DIM closed
        if ~blockDepth then fldPre = ''.                             ! structure closed
        if ~blockDepth then mapBlock = 0.
        if ~blockDepth then fldBare = 0 ; fldDimAt = 0.
        if lvl = '-' and fldOff > blockDepth then fldOff = 0.
        cycle
      end
    end

    get(self.tk.tokens, x)
    if errorcode() then break.
    if ~self.tk.tokens.firstOnLine then cycle.                       ! classify each line by its first token only

    if self.IsColOneLabel(x) or self.ColOneMethodDot(x)              ! ColOneMethodDot: a 'Class.Method' impl label is ONE token IsLabelTok rejects (the '.')
      ! ---- column-1 label line: procedure / method / routine / declaration ----
      t2 = x + 1
      if self.TokIsEOL(t2) then cycle.                               ! bare label
      w2.setValue(upper(self.TokText(t2)))

      if w2._DataEnd = 1 and w2.valuePtr[1] = '.'                    ! Class.Method PROCEDURE
        t3 = t2 + 1
        t4 = t3 + 1
        if ~self.TokIsEOL(t4) and self.IsLabelTok(self.TokText(t3))  |
           and (upper(self.TokText(t4)) = 'PROCEDURE' or upper(self.TokText(t4)) = 'FUNCTION')
          curProc   = self.AddScope(vs:scMethod, modScope, x, upper(self.TokText(x)))
          curRout   = 0
          dataScope = curProc
          self.AddSym('SELF', curProc, upper(self.TokText(x)), 1, 0, x)
          do MethodHost
          t5 = t4 + 1
          if ~self.TokIsEOL(t5) and self.TokText(t5) = '('
            self.ParseParams(t5, curProc)
          end
        end
        cycle
      end

      if w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'PROCEDURE' or w2._DataEnd = 8 and w2.valuePtr[1 : 8] = 'FUNCTION'
        dotPos = instring('.', self.TokText(x), 1, 1)                ! Class.Method as ONE column-1 label token (the '.' only splits in expression context)
        if dotPos > 1                                                ! method implementation: receiver class = text before the '.'
          curProc = self.AddScope(vs:scMethod, modScope, x, upper(sub(clip(self.TokText(x)), 1, dotPos - 1)))
          self.AddSym('SELF', curProc, upper(sub(clip(self.TokText(x)), 1, dotPos - 1)), 1, 0, x)
        else
          ! the older method form, `Name PROCEDURE(Class SELF, ...)`: the class is the FIRST
          ! parameter and it is named SELF. Filed as that class's method, as the dotted label
          ! is, so a call through self finds it and its VIRTUAL is seen; ParseParams leaves the
          ! SELF parameter to the SELF symbol added here. (No continuation bar and no trailing
          ! comment on these lines: either would lift this run's column.)
          t3 = t2 + 1
          t4 = t3 + 1
          selfForm = 0
          if ~self.TokIsEOL(t3) and self.TokText(t3) = '('
            if ~self.TokIsEOL(t4 + 1)
              if upper(self.TokText(t4 + 1)) = 'SELF'
                selfForm = self.IsLabelTok(self.TokText(t4))
              end
            end
          end
          if selfForm
            curProc = self.AddScope(vs:scMethod, modScope, x, upper(self.TokText(t4)))
            self.AddSym('SELF', curProc, upper(self.TokText(t4)), 1, 0, x)
          else
            curProc = self.AddScope(vs:scProc, modScope, x, '')
          end
        end
        do MethodHost
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
        dataScope = 0                                                ! routine code unless a DATA section follows
        cycle
      end

      if self.TokLevel(t2) = '+'                                     ! labelled structure block (lbl QUEUE,TYPE / GROUP / CLASS ...)
        blockDepth = 1
        protoBlock = choose(w2._DataEnd = 5 and w2.valuePtr[1 : 5] = 'CLASS' or w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'INTERFACE' or | ! prototype-bearing? (see resync)
                            w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'MAP'   or w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'MODULE')
        mapBlock   = choose(w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'MAP' or w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'MODULE')
        fldPre = ''                                                  ! field typing: capture PRE(p) so the
        fldBare = 0 ; fldDimAt = 0 ; fldExt = 0
        if ~protoBlock and dataScope                                 ! skip loop can publish p:name field symbols.
          t3 = t2 + 1                                                ! A ,TYPE definition has no storage - skip it
          loop while ~self.TokIsEOL(t3)                              ! (scan the whole attribute list: TYPE may
            w2.setValue(upper(self.TokText(t3)))                     ! follow PRE)
            if w2._DataEnd = 4 and w2.valuePtr[1 : 4] = 'TYPE'
              fldPre = ''
              fldBare = 0 ; fldDimAt = 0
              break
            elsif w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'PRE'
              t4 = t3 + 1
              t5 = t4 + 1
              if ~self.TokIsEOL(t5) and self.TokText(t4) = '(' and self.IsLabelTok(self.TokText(t5))
                fldPre = upper(self.TokText(t5))
                fldScope = dataScope
              elsif self.TokText(t5) = ')'
                if self.TokText(t4) = '(' then fldBare = 1.
                fldScope = dataScope
              end
            elsif w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'DIM'
              fldDimAt = 1
            elsif w2._DataEnd = 8 and w2.valuePtr[1 : 8] = 'EXTERNAL' or w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'DLL' or |
                  w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'EXPORT'
              fldExt = 1
            end
            t3 += 1
          end
        end
        if dataScope then do HideLabel.
        x = t2                                                       ! t2's own '+' already counted
        cycle
      end

      if dataScope                                                   ! ---- variable declaration ----
        do ExtractDeclType                                           ! t2/w2 in -> isRef/isLike/typeU out
        if typeU._DataEnd
          do LinkedDecl
          self.AddSym(upper(self.TokText(x)), dataScope, typeU.getValue(), isRef, isLike, x, 0, declLnk)
        else
          do HideUnread                                              ! declared, type not read
        end
      end
      cycle
    end

    ! ---- indented line start: region keywords ----
    w2.setValue(upper(self.TokText(x)))
    if w2._DataEnd = 4 and w2.valuePtr[1 : 4] = 'CODE'
      dataScope = 0
      if ~curProc                                                    ! a PROGRAM's own CODE: a scope of its own,
        curProc = self.AddScope(vs:scMain, modScope, x, '')          !   and its routines are its routines
      end
    elsif w2._DataEnd = 4 and w2.valuePtr[1 : 4] = 'DATA'
      if curRout then dataScope = curRout.
    elsif w2._DataEnd = 7 and w2.valuePtr[1 : 7] = 'INCLUDE'
      if dataScope and dataScope <> modScope then do MarkUnseen.
    elsif self.TokLevel(x) = '+'
      if dataScope                                                   ! unlabelled structure in a data region (MAP, WINDOW ...)
        blockDepth = 1
        protoBlock = choose(w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'MAP' or w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'MODULE' or | ! a local/module MAP holds col-1 proc
                            w2._DataEnd = 5 and w2.valuePtr[1 : 5] = 'CLASS' or w2._DataEnd = 9 and w2.valuePtr[1 : 9] = 'INTERFACE') ! prototypes (see resync above)
        mapBlock   = choose(w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'MAP' or w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'MODULE')
      end
    end
  end

  self.SetScopeEnds()
  self.MarkBlocks()
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
  !                   DOCUMENTED LIMIT: a rule set that
  !                   REWRITES DECLARATIONS IN AN INCLUDE - retypes a field, renames a class or a
  !                   prototype - works from that frozen picture for the rest of the file.
  !                   The supported shape is two runs: the declaration pass first, then everything
  !                   else against the updated files. Such a change is not detected and the
  !                   picture is not refreshed; the README's thorough-mode section
  !                   states the same limit in user terms.
  self.regSorted = 0                                                 ! FindTypeDef's dedupe runs DURING the registry build - use the linear path until re-sorted
  if self.expTk &= NULL
    free(self.incDecl)
    free(self.incProtos)
    self.incRead = 0
    free(self.types)
    free(self.fields)
    free(self.methods)                                               !
    self.BuildTypeRegistry(pTk, 1)                                   ! the RAW in-file stream - pTk is what SetScopeEnds above just measured, so a field's token position and
                                                                     !   a scope's startTok/endTok are indices into the SAME stream and the declaring scope can be recorded.
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
    !
    ! The MAP prototypes are read from the expanded stream here as well (ReadIncProtos), once per
    ! file, so a prototype in a file that a MAP INCLUDEs counts as one written in the MAP does.
    if ~self.hdrBuilt
      free(self.incDecl)
      free(self.types)
      free(self.fields)
      free(self.methods)                                             !
      self.BuildTypeRegistry(self.expTk, 0)                          ! superset: contains the in-file structures too
      sort(self.incDecl, +self.incDecl.nameU)
      self.ReadIncProtos()
      self.hdrBuilt = 1
    end
    do DropRawRows                                                   ! last Build's raw rows: their positions have moved
    self.BuildTypeRegistry(pTk, 1)                                   ! this file's own structures again, WITH their scopes
  end
  ! sort for keyed (binary) GETs: unsorted, FindSym would scan ALL symbols per
  ! lookup, up to 3x per typed candidate token - the dominant typed-matching cost.
  sort(self.syms, +self.syms.scopeId, +self.syms.nameU)
  sort(self.hidden, +self.hidden.scopeId, +self.hidden.nameU)
  sort(self.types, +self.types.typeU)
  sort(self.fields, +self.fields.ownerU, +self.fields.nameU)
  sort(self.methods, +self.methods.ownerU, +self.methods.nameU)      !
  self.regSorted = 1
  self.dirty = 0                                                     ! freshly built - cleared BEFORE the retype, whose FindTypeDef would otherwise build it again
  do StKinRetype
  do HiddenKinRetype
  bdT0 = clock() - bdT0 ; if bdT0 < 0 then bdT0 += 8640000.          ! --timing, across midnight
  self.nBuild += 1 ; self.tBuild += bdT0
  return records(self.syms)

! ---- an object of a class derived from StringTheory that overrides none of its methods - one
!      that only adds methods of its own - is a StringTheory to every question asked of its type
!      (ruled 30 Oct 2026), and a reference to one or a parameter of that class is a reference to a
!      StringTheory or a StringTheory parameter. The rows are sorted by scope and name, not by type,
!      so retyping one keeps the order.
StKinRetype routine
  if self.stMeth &= NULL then exit.
  loop x = 1 to records(self.syms)
    get(self.syms, x)
    if errorcode() then break.
    if self.syms.isLike then cycle.                                  ! the name of what it is LIKE, not a type
    if ~self.syms.typeU or self.syms.typeU = 'STRINGTHEORY' then cycle.
    if ~self.FindTypeDef(self.syms.typeU) then cycle.                ! a LONG or a STRING: no class to look at
    if ~self.PureStKin(self.syms.typeU) then cycle.
    self.syms.typeU = 'STRINGTHEORY'
    put(self.syms)
  end

! ---- the same for an object written as a block, `stObj CLASS(StringTheory)` with methods of its
!      own and none of StringTheory's: its hidden row is typed as its own label, the type registry's
!      name for the class, and it is a StringTheory as an object declared with a type is. A TYPE
!      label is filed the same way but is no object, so only an instance (OpenerInst) is retyped ----
HiddenKinRetype routine
  if self.stMeth &= NULL then exit.
  loop x = 1 to records(self.hidden)
    get(self.hidden, x)
    if errorcode() then break.
    if self.hidden.typeU <> self.hidden.nameU then cycle.
    t2 = self.FindTypeDef(self.hidden.typeU)
    if ~t2 then cycle.
    get(self.types, t2)
    if errorcode() or ~self.types.isInst then cycle.
    if ~self.PureStKin(self.hidden.typeU) then cycle.
    get(self.hidden, x)
    self.hidden.typeU = 'STRINGTHEORY'
    put(self.hidden)
  end

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
  loop drI = records(self.types) to 1 by -1 ! the types themselves. The three loops are
    get(self.types, drI)                    !   independent, each deleting only its own
    if errorcode() then cycle.              !   queue, so the order among them does not matter
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
      if self.TokText(t4 + 1) <> ')' then isLike = 0 ; typeU.free().
    end
  elsif self.IsLabelTok(w2.getValue())
    typeU.setValue(w2) ! bare keyword: STRING(20) arrives as STRING + ( + 20 + )
  end

! ---- the label of a structure written as a block (a QUEUE, GROUP, CLASS ...) names it in this
!      scope, so it hides an outer declaration of the name. Filed apart from syms, where no pass
!      looks for candidates, and typed as the label itself: the type registry knows the
!      structure by that name ----
HideLabel routine
  self.AddHidden(upper(self.TokText(x)), dataScope, upper(self.TokText(x)), x)

! ---- a column-1 label in a data section whose type could not be read still DECLARES the name,
!      so it is filed as declared with no known type. INCLUDE in column 1 is the directive ----
HideUnread routine
  if upper(self.TokText(x)) = 'INCLUDE'
    if dataScope <> modScope then do MarkUnseen.
  else
    self.AddHidden(upper(self.TokText(x)), dataScope, vs:unknownType, x)
  end

! ---- the data section INCLUDEs a file, which may declare any name this table never sees ----
MarkUnseen routine
  get(self.scopes, dataScope)
  if errorcode() then exit.
  self.scopes.unseen = 1
  put(self.scopes)

! ---- A LOCAL DERIVED METHOD shares the data of the procedure whose data section declares its
!      class, so a name the method does not declare itself is that procedure's before it is the
!      module's. Its body follows that procedure, before the next one, so the latest procedure
!      is the one asked. hostId 0: the class is the module's, or nothing in this file declares
!      it. -1: another scope declares it, or the latest procedure's data INCLUDEs a file that
!      may - a name that gets past the method then has no answer ----
MethodHost routine
  data
mhR    long,auto
mhLast byte
mhMod  byte
mhElse byte
mhCls  string(vs:maxName),auto
  code
  get(self.scopes, curProc)
  if errorcode() then exit.
  if self.scopes.kind = vs:scProc then lastProc = curProc.
  if self.scopes.kind <> vs:scMethod then exit.
  mhCls = self.scopes.selfClass
  loop mhR = 1 to records(self.hidden)
    get(self.hidden, mhR)
    if errorcode() then break.
    if self.hidden.nameU <> mhCls then cycle.
    if upper(self.TokText(self.hidden.declTok + 1)) <> 'CLASS' then cycle.
    if lastProc and self.hidden.scopeId = lastProc
      mhLast = 1
    elsif self.hidden.scopeId = modScope
      mhMod = 1
    else
      mhElse = 1
    end
  end
  if mhLast
    mhR = lastProc
  elsif mhMod
    mhR = 0
  elsif mhElse
    mhR = -1
  else
    mhR = 0
    if lastProc
      get(self.scopes, lastProc)
      if ~errorcode() and self.scopes.unseen then mhR = -1.
    end
  end
  get(self.scopes, curProc)
  if errorcode() then exit.
  self.scopes.hostId = mhR
  put(self.scopes)

! ---- a declaration that carries EXTERNAL, DLL or EXPORT is held or reached by another module.
!      Its attributes are read to the end of the logical line, past a '|' continuation ----
LinkedDecl routine
  declLnk = 0
  t3 = t2 + 1
  loop while ~self.TokIsEOL(t3)
    w2.setValue(upper(self.TokText(t3)))
    if w2._DataEnd = 8 and w2.valuePtr[1 : 8] = 'EXTERNAL' or w2._DataEnd = 3 and w2.valuePtr[1 : 3] = 'DLL' or |
       w2._DataEnd = 6 and w2.valuePtr[1 : 6] = 'EXPORT'
      declLnk = 1
      exit
    end
    t3 += 1
  end

! ---- a field of a PRE() structure is named bare, with no prefix, so it is filed under its own
!      label: a field all the same, which no pass offers as a candidate. Every bare label is
!      filed, because each one hides a name of the same spelling declared further out: a field
!      whose type is not read is filed as declared with no known type, and the label of a
!      nested structure is filed as that structure, as HideLabel files one at the top. A nested
!      structure with a PRE of its own names the fields inside it with that prefix, so none of
!      them is filed bare; after its END the outer structure's fields are bare again. A nested
!      PRE() keeps its fields bare. INCLUDE in column 1 is the directive ----
BareField routine
  t2 = x + 1
  if self.TokIsEOL(t2) then exit.
  if fldOff and blockDepth >= fldOff then exit.
  if self.TokLevel(t2) = '+'
    self.AddHidden(upper(self.TokText(x)), fldScope, upper(self.TokText(x)), x)
    t3 = t2 + 1
    loop while ~self.TokIsEOL(t3)
      if upper(self.TokText(t3)) = 'PRE'
        if self.TokText(t3 + 1) <> '(' or self.TokText(t3 + 2) <> ')' then fldOff = blockDepth + 1.
      end
      t3 += 1
    end
    exit
  end
  w2.setValue(upper(self.TokText(t2)))
  do ExtractDeclType
  if ~typeU._DataEnd
    if upper(self.TokText(x)) <> 'INCLUDE' then self.AddHidden(upper(self.TokText(x)), fldScope, vs:unknownType, x).
    exit
  end
  self.AddSym(upper(self.TokText(x)), fldScope, typeU.getValue(), isRef, isLike, x, 1, fldExt)
  if fldDimAt then do DimHeld.

! ---- a structure inside one whose fields are being filed may carry DIM of its own (LRM DIM:
!      each level of nesting adds subscripts). Every field inside it is then an array, until it
!      closes. x is the token that opens it, labelled or not ----
NestDim routine
  if self.TokLevel(x) <> '+' then exit.
  if self.DimOnLine(x) then fldDimAt = blockDepth + 1.

! ---- the symbol just added is an array whose DIM is not on its own line ----
DimHeld routine
  self.syms.dimHeld = 1
  put(self.syms)

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
    of vs:scProc    orof vs:scMethod orof vs:scMain
      self.scopes.endTok = nextProcStart - 1
      nextProcStart = self.scopes.startTok
      nextAnyStart  = self.scopes.startTok
    else
      self.scopes.endTok = N
    end
    put(self.scopes)
  end

! ------------------------------------------------------------------------------------
! WHICH DECLARATIONS ARE INSIDE A COMPILE OR CONDITIONAL OMIT BLOCK - code some builds leave out.
! A variable declared only there does not exist in a build without the block, and a use of its
! name outside the block is then another variable of that name, or nothing. So each syms and
! hidden row declared in a block is given the token of the block's keyword and the first token
! after the block, and Visible answers "unknown" for it at a use the block does not hold.
!
! The blocks are found once per Build, in one walk of the file from its first token, by the
! rules VitEngine.CondBlockAt reads them by, so the two agree on where a block ends: the
! keyword and a quoted terminator survive as tokens (a plain OMIT is trivia, no build has its
! code); each physical line is read whole, code and trivia alike, while a block is open; a line
! holding a block's terminator anywhere - in a comment, after a '|', in front of a comment -
! ends that block and every block opened inside it, and the line itself is in the block. On the
! directive's own line only the text after its closing ')' is searched. A block with no
! terminator runs to the end of the file. Blocks nest, so a token is in a block, or in one
! inside it, exactly when it lies between the keyword and the first token after the block.
! ------------------------------------------------------------------------------------
VitSymbols.MarkBlocks Procedure()
i     long,auto
j     long,auto
k     long,auto
p     long,auto
e     long,auto
f     long,auto
N     long,auto
r     long,auto
open  StringTheory ! the terminators of the blocks open so far, the innermost last
kw    StringTheory ! the blkQ row of each one, line for line with open
fr    StringTheory ! where on the line being read each one's search starts, 0 = not on this line
ar    StringTheory ! the token of each one's closing ')' when it is on the directive's own line, else 0
sb    StringTheory
ln    StringTheory ! the physical line read so far, trivia and code alike, while a block is open
lt    StringTheory
blkQ  QUEUE,PRE(mbk)
kwTok   long
endTok  long
      END
  code
  if self.tk &= NULL then return.
  N = self.tk.records()
  loop i = 1 to N
    get(self.tk.tokens, i)
    if errorcode() then break.
    if open.records() and not self.tk.tokens.strBefore &= NULL
      sb.setValue(self.tk.tokens.strBefore)
      p = 1
      loop
        e = sb.findByte(10, p)
        if ~e then break.
        if e > p then ln.append(sb.slice(p, e - 1)).
        do LineEnds
        p = e + 1
        if ~open.records() then break.
      end
      if open.records() and p <= sb._DataEnd then ln.append(sb.slice(p, sb._DataEnd)).
      get(self.tk.tokens, i)
      if errorcode() then break.
    end
    if open.records() and not self.tk.tokens.tok &= NULL
      if self.tk.tokens.tok = '<10>' then do LineEnds.
    end
    if self.tk.tokens.tok &= NULL then cycle.
    if open.records() and self.tk.tokens.tok <> '<10>'
      ln.append(self.tk.tokens.tok)
      loop k = 1 to ar.records()
        if ar.getLine(k) = i then fr.setLine(k, ln._DataEnd + 1).
      end
    end
    if size(self.tk.tokens.tok) <> 4 and size(self.tk.tokens.tok) <> 7 then cycle.
    case upper(self.tk.tokens.tok)
    of 'OMIT' orof 'COMPILE'
      if i > 1 and self.tk.GetTok(i - 1) = '.' then cycle. ! a method of that name
      if self.tk.GetTok(i + 1) <> '(' then cycle.
      lt.setValue(self.tk.GetTok(i + 2))
      if lt._DataEnd < 3 or lt.valuePtr[1] <> '''' or lt.valuePtr[lt._DataEnd] <> '''' then cycle.
      lt.setValue(lt.valuePtr[2 : lt._DataEnd - 1])
      lt.replace('''''', '''')
      if ~lt._DataEnd then cycle.
      do CloseAt
      if ~open.records() then ln.free().
      clear(blkQ)
      blkQ.kwTok  = i
      blkQ.endTok = N + 1
      add(blkQ)
      open.addLine(lt.getValue()) ; kw.addLine(records(blkQ)) ; fr.addLine(0) ; ar.addLine(e)
    end
  end
  if ~records(blkQ) then return.
  loop j = 1 to records(self.syms)
    get(self.syms, j)
    if errorcode() then break.
    p = self.syms.declTok
    do Inner
    if f
      self.syms.blkTok = f
      self.syms.blkEnd = e
      put(self.syms)
    end
  end
  if self.hidden &= NULL then return.
  loop j = 1 to records(self.hidden)
    get(self.hidden, j)
    if errorcode() then break.
    p = self.hidden.declTok
    do Inner
    if f
      self.hidden.blkTok = f
      self.hidden.blkEnd = e
      put(self.hidden)
    end
  end

! ---- the ')' that closes the directive at i when it is on the directive's own line, else 0 ----
CloseAt routine
  e = 0
  j = 0
  loop k = i + 1 to N
    get(self.tk.tokens, k)
    if errorcode() then break.
    if not self.tk.tokens.strBefore &= NULL
      if sb.findByte(10, 1,, self.tk.tokens.strBefore) then break.
    end
    if self.tk.tokens.tok &= NULL then cycle.
    case self.tk.tokens.tok
    of '<10>'
      break
    of '('
      j += 1
    of ')'
      j -= 1
      if ~j then e = k ; break.
    end
  end
  get(self.tk.tokens, i)

! ---- a physical line has been read: a terminator on it closes that block and every one inside
!      it, and token i is the first token after them ----
LineEnds routine
  loop k = open.records() to 1 by -1
    f = fr.getLine(k)
    if f and ln.findChars(open.getLine(k), f)
      loop while open.records() >= k
        r = kw.getLine(kw.records())
        get(blkQ, r)
        if ~errorcode()
          blkQ.endTok = i
          put(blkQ)
        end
        open.deleteLine(open.records())
        kw.deleteLine(kw.records())
        fr.deleteLine(fr.records())
        ar.deleteLine(ar.records())
      end
      break
    end
  end
  loop k = 1 to fr.records()
    fr.setLine(k, 1)
  end
  ln.free()

! ---- the innermost block that holds token p: f its keyword, e the first token after it; f = 0
!      for none. A block opened inside another closes no later, so the last one opened wins ----
Inner routine
  f = 0
  loop k = records(blkQ) to 1 by -1
    get(blkQ, k)
    if errorcode() then break.
    if blkQ.kwTok < p and p < blkQ.endTok
      f = blkQ.kwTok
      e = blkQ.endTok
      break
    end
  end

! ------------------------------------------------------------------------------------
! ====================================================================================
! Design B - type registry (C1/C2) + member-chain resolver (LookupChain).
! BuildTypeRegistry scans structure DEFINITIONS (named TYPE / CLASS / labelled instance)
! and records each type and its data members, so a dotted receiver can be walked field by
! field to a terminal type. Structure nesting is tracked by the tokenizer's '+'/'-' level
! marks (same source of truth GetData/Build use); an owner stack maps the current field
! owner. Method PROTOTYPES inside a CLASS are recorded too, in the methods table (return
! class, arity, argument types, VIRTUAL and the prototype's position); only data members
! type a receiver.
! In-file structures first; --thorough calls this again over the .red-expanded includes.
! ====================================================================================
VitSymbols.BuildTypeRegistry Procedure(VitTokenize pTk, BYTE pScoped)
x        long,AUTO
dclScope long,auto                ! the scope of the declaration about to be recorded (vs:scUnknown when ~pScoped)
dclTok   long,auto                !   ... and its token (0 when ~pScoped) - both set by DeclScopeAt
N        long,auto
t2       long,auto
t3       long,auto
t4       long,auto
depth    long,AUTO                ! structure nesting level (mirrors '+'/'-')
kindB    byte,auto
parentU  string(vs:maxName),auto
fldTypeU string(vs:maxName),auto
isRefB   byte,auto
isLikeB  byte,auto
lvl      string(1),auto
curOwner string(vs:maxName),auto
tta      byte,auto                ! this opener line carries a top-level ,TYPE attribute
tdep     long,auto                ! paren depth while scanning the attribute list
ttx      long,auto                ! attr-scan cursor
mdx      long,auto                ! prototype return-type scan cursor
mdepth   long,auto                ! paren depth over the prototype's parameter list
retU     string(vs:maxName)       ! return class from the attribute after the closing paren
retRefB  byte,auto                ! return carries * or &
virtB    byte,auto                ! the prototype's attribute list carries VIRTUAL
vdx      long,auto                ! VIRTUAL-scan cursor
aMin     long,auto                ! parameters the call MUST supply
aMax     long,auto                !   and the total declared (-1/-1 = unreadable, matches anything)
p1U      string(vs:maxName),auto  ! first parameter's type token
pTx      string(vs:maxName)       ! the current parameter's type, marker stripped - the slot spelling
slotsU   string(vs:maxSlots),auto ! every parameter's type token, '|'-terminated
slotsOk  byte,auto                !   cleared if they will not fit - then we record NONE
pSeen    byte,auto                ! the current parameter has started
pOpt     byte,auto                !   ... and is defaulted ('=') or omittable ('<>')
pAng     byte,auto                !   ... and we are inside its angle brackets
vdep     long,auto                ! paren depth over that scan (NAME('x'),VIRTUAL)
dimB     byte,auto                ! this structure is an array: DIM on its opener, or on one it sits in
saveTk   &VitTokenize             ! BuildTypeRegistry may run on the include-EXPANDED tokenizer; restore self.tk (Lookup needs the raw stream) after
OwnerStackQ QUEUE,PRE(osq)
ownerU     STRING(vs:maxName)
atDepth    LONG
kind       BYTE                   ! vs:tk* of the owner - the EQUATE-in-class resync needs it
dimmed     BYTE                   ! the owner, or a structure it sits in, carries DIM
             END
  code
  saveTk &= self.tk
  self.tk &= pTk
  N = pTk.records()
  if self.traceReg                                                                 ! fresh trace per scan
    self.regTrace.free()
    self.regTrace.append('--- registry trace: ' & N & ' token(s) ---<13,10>')
  end
  self.regEofDepth = 0
  self.regEofStack = 0
  free(OwnerStackQ)
  depth    = 0
  self.regRaw = pScoped                                                            ! stamped onto every row the three Add methods add on this pass
  ! An anonymous inline structure is named from its OWNER and FIELD ('$ANON:owner:field'), never
  ! from a counter: under include expansion the same declaration is read twice, by the expanded
  ! pass and the raw pass, and the two rows for one field must AGREE on the type or every dotted
  ! receiver through it reads as a clash. A counter seeded above the first pass's rows gave the
  ! second pass a different name for the same structure. AddTypeDef dedupes by name, so the raw
  ! pass finds the expanded pass's row and adds nothing; '$' is not legal in a Clarion label, so
  ! no name from the source can be in the way.
  x = 0
  loop
    x += 1
    if x > N then break.
    if self.TokIsEOL(x) then cycle.
    get(self.tk.tokens, x)
    if errorcode() then break.
    if self.tk.tokens.firstOnLine and self.ColOneMethodDot(x)                      ! a col-1 DOTTED label (Class.Method impl)
      if depth or records(OwnerStackQ)                                             !   can never sit inside a structure - resync,
        if self.traceReg                                                           !   exactly like col-1 CLASS / ,TYPE. This closes
          self.regTrace.append('RESYNC tok ' & x & ' ' & clip(self.TokText(x)) & ' IMPL: depth was ' & depth & ' stack was ' & records(OwnerStackQ) & '<13,10>')
        end                                                                        !   the swallow window between a phantom-'+'-broken
        depth = 0                                                                  !   class END and the main-file body (the
        free(OwnerStackQ)                                                          !   MODULE-attribute phantom). Bare PROCEDURE labels
      end                                                                          !   are NOT safe (b0b: col-1 prototypes) - dotted only.
    end
    if self.tk.tokens.firstOnLine and self.IsColOneLabel(x)
      t2 = x + 1
      if ~self.TokIsEOL(t2)
        kindB = 0
        if self.TokLevel(t2) = '+'                                                 ! label + keyword opening a '+' block
          kindB = self.StructKind(upper(self.TokText(t2)))
          if ~kindB then kindB = vs:tkOther.                                       ! unknown block type - still push, to keep the stack aligned
        end
        if kindB                                                                   ! ---- structure opener ----
          tta = 0                                                                  ! does the opener line carry a top-level ,TYPE attribute?
          if kindB <> vs:tkClass                                                   !   (CLASS already resyncs unconditionally below)
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
          if kindB = vs:tkClass or tta                                             ! A column-1 CLASS is ALWAYS
            if self.traceReg and (depth or records(OwnerStackQ))                   !
              self.regTrace.append('RESYNC tok ' & x & ' ' & clip(self.TokText(x)) & choose(tta = 1, ' ,TYPE', ' CLASS') & ': depth was ' & depth & ' stack was ' & records(OwnerStackQ) & '<13,10>')
            end
            depth = 0                                                              ! top-level in Clarion, and so is any structure carrying the
            free(OwnerStackQ)                                                      ! TYPE attribute (TYPE is illegal on a nested structure) - so
          end                                                                      ! force a resync: recover from mis-levelling in a prior big
                                                                                   ! class/structure (phantom '+' marks on keyword-texted tokens
                                                                                   ! in prototypes, for one) that left depth/OwnerStackQ
                                                                                   ! stale, which would otherwise swallow this definition as a
                                                                                   ! NESTED FIELD and lose its fields - a QUEUE or GROUP TYPE
                                                                                   ! after the mis-levelled one would be left with no fields.
          dimB = 0
          if records(OwnerStackQ)
            get(OwnerStackQ, records(OwnerStackQ))
            curOwner = osq:ownerU
            dimB = osq:dimmed
          else
            curOwner = ''
          end
          parentU = ''                                                             ! CLASS(parent) / GROUP(base) instance-of
          t3 = t2 + 1
          if ~self.TokIsEOL(t3) and self.TokText(t3) = '('
            t4 = t3 + 1
            if ~self.TokIsEOL(t4) and self.IsLabelTok(self.TokText(t4))
              parentU = upper(self.TokText(t4))
            end
          end
          if self.DimOnLine(x) then dimB = 1.
          if ~curOwner                                                             ! top level: a named type / class / instance variable
            self.AddTypeDef(upper(self.TokText(x)), kindB, parentU)
            do OpenerInst
            if self.traceReg                                                       !
              self.regTrace.append('TYPE tok ' & x & ' ' & clip(self.TokText(x)) & ' kind ' & kindB & ' depth ' & depth & '<13,10>')
            end
            clear(OwnerStackQ)
            osq:ownerU = upper(self.TokText(x))
          else                                                                     ! nested: a field whose type is a structure
            ! a nested structure is a type of its OWN, named from owner and field so both passes
            ! agree, whether it is anonymous or `GROUP(NamedType)`: a named base becomes the new
            ! type's PARENT, so its fields resolve through the parent walk and any fields written
            ! inline land on THIS type - not on the shared base, where two GROUP(BaseG) instances
            ! with different inline fields would make the base's run disagree
            fldTypeU = '$ANON:' & curOwner
            fldTypeU = clip(fldTypeU) & ':' & upper(self.TokText(x))
            self.AddTypeDef(fldTypeU, kindB, parentU)
            if self.traceReg                                                       ! a NAMED structure landing here = the desync signature
              self.regTrace.append('NEST tok ' & x & ' ' & clip(self.TokText(x)) & ' -> ' & clip(fldTypeU) & ' under ' & clip(curOwner) & ' depth ' & depth & '<13,10>')
            end
            do DeclScopeAt
            self.AddTypeField(curOwner, upper(self.TokText(x)), fldTypeU, 0, 0, dclScope, dclTok)
            clear(OwnerStackQ)
            osq:ownerU = fldTypeU
          end
          osq:dimmed = dimB
          if dimB then do TypeDimmed.
          if pScoped then do ParentRow.                                            ! this declaration's parent, with its scope
          osq:atDepth = depth
          osq:kind    = kindB                                                      !
          add(OwnerStackQ)
        elsif records(OwnerStackQ)                                                 ! ---- a simple field inside a structure ----
          if self.TokLevel(x) <> '+' and self.TokLevel(x) <> '-'                   ! a real field label carries no level mark (skips unlabelled RECORD/END openers)
            get(OwnerStackQ, records(OwnerStackQ))
            curOwner = osq:ownerU
            if osq:kind = vs:tkClass and upper(self.TokText(t2)) = 'EQUATE'        ! an EQUATE can never be a CLASS member -
              if self.traceReg                                                     !   this "field" proves the class END was missed
                self.regTrace.append('RESYNC tok ' & x & ' ' & clip(self.TokText(x)) & ' EQUATE-in-class: depth was ' & depth & ' stack was ' & records(OwnerStackQ) & '<13,10>')
              end                                                                  !   (phantom '+' marks) - resync instead of adding
              depth = 0                                                            !   the fake field. ITEMIZE interiors are kind
              free(OwnerStackQ)                                                    !   tkOther, so their equates keep current handling.
            elsif upper(self.TokText(t2)) = 'PROCEDURE' or upper(self.TokText(t2)) = 'FUNCTION' ! method prototype - record its
              retU = '' ; retRefB = 0                                              !   return class.
              aMin = -1 ; aMax = -1 ; p1U = '' ; slotsU = '' ; slotsOk = 1         ! arity UNKNOWN unless we read a '(' list
              mdx = t2 + 1                                                         ! Return class = the attribute directly
              if ~self.TokIsEOL(mdx) and self.TokText(mdx) = '('                   ! after the closing paren; a known
                mdepth = 1                                                         ! prototype ATTRIBUTE there (VIRTUAL,
                aMax = 0 ; aMin = 0                                                ! empty '()' is a real, known arity of 0
                pSeen = 0 ; pOpt = 0 ; pAng = 0                                    !   pSeen: this parameter has begun
                loop                                                               ! PROC, ...) means no return type.
                  mdx += 1
                  if self.TokIsEOL(mdx) then mdepth = -1 ; break.                  ! EOS before ')' - malformed, no return
                  case self.TokText(mdx)
                  of '('
                    mdepth += 1
                  of ')'
                    mdepth -= 1
                    if ~mdepth then break.
                  end
                  if mdepth = 1                                                    ! count only at the TOP level of the list -
                    case self.TokText(mdx)                                         !   a nested '(' is a dimension or a default expression
                    of ','
                      if pSeen and ~pOpt then aMin += 1.                           ! a parameter ENDS here: required unless <> or '='
                      pSeen = 0 ; pOpt = 0 ; pAng = 0
                    of '<<'
                      pAng = 1 ; pOpt = 1                                          ! <STRING pFormat> - omittable
                    of '>'
                      pAng = 0
                    of '='
                      pOpt = 1                                                     ! LONG pStart=1 - defaulted
                    else
                      if ~pSeen and (self.TokText(mdx) = '*' or self.TokText(mdx) = '&' or upper(self.TokText(mdx)) = 'CONST')
                        ! a SEPARATE by-ref marker token ('&' never merges; a spaced '* STRING'
                        ! keeps its own '*') - the parameter's TYPE is the NEXT token, so the
                        ! parameter does not open here. Recording the marker itself would
                        ! mis-file the slot AND consume pSeen, throwing the real type away:
                        ! no caller-side spelling can ever equal a bare '&', so ArgAdmits
                        ! would POSITIVELY exclude the row - the fail-closed inversion of
                        ! its own admit-only-on-positive contract. CONST, the qualifier of a
                        ! variable parameter - (CONST *CSTRING p) - is stepped past the same way:
                        ! it is not the type, and the '*' after it is a separate token too.
                      elsif ~pSeen                                                 ! '<' and '>' have their own arms above, so the
                        pSeen = 1                                                  !   FIRST non-marker token to reach here is the
                        aMax += 1                                                  !   parameter's TYPE, inside angle brackets or not
                        pTx = upper(self.TokText(mdx))
                        if pTx[1] = '*'                                            ! MERGED '*STRING' token (the tokenizer combines
                          pTx = sub(pTx, 2, vs:maxName - 1)                        !   * with the next token after ( , <) - record
                        end                                                        !   the BARE type: the spelling a call site's CallArgTypes can actually produce. The return class below makes the same strip.
                        if aMax = 1 then p1U = pTx.
                        ! record EVERY slot's type, not just the first: '|'-terminated, in
                        ! order, so ArgAdmits can line argument N up with parameter N.
                        if slotsOk
                          if len(clip(slotsU)) + len(clip(pTx)) + 1 > size(slotsU)
                            slotsOk = 0                                            ! too many/too long to hold - see below
                            slotsU  = ''
                          else
                            slotsU = clip(slotsU) & clip(pTx) & '|'
                          end
                        end
                      end
                    end
                  end
                end
                if pSeen and ~pOpt then aMin += 1.                                 ! the last parameter has no ',' to close it
                if mdepth < 0 then aMin = -1 ; aMax = -1 ; slotsU = ''.            ! malformed list - claim NOTHING about arity or slots
                if ~mdepth then mdx += 1 else mdx = 0.
              end                                                                  ! (no '(' at all: Foo PROCEDURE,STRING -
              if mdx                                                               !   mdx still sits right after PROCEDURE)
                if ~self.TokIsEOL(mdx) and self.TokText(mdx) = ','
                  mdx += 1
                  if ~self.TokIsEOL(mdx) and (self.TokText(mdx) = '*' or self.TokText(mdx) = '&') ! separate ref-marker token ('&' never merges)
                    retRefB = 1
                    mdx += 1
                  end
                  if ~self.TokIsEOL(mdx)
                    retU = upper(self.TokText(mdx))
                    if retU[1] = '*'                                               ! MERGED '*STRING' token - the tokenizer's
                      retRefB = 1                                                  !   'reference prototypes' pass combines * with
                      retU = sub(retU, 2, vs:maxName - 1)                          !   the next token after ( , < (the tokenizer's reference-prototype merge)
                    end
                    if ~self.IsLabelTok(clip(retU)) or instring(' ' & clip(retU) & ' ', vs:protoAttrs, 1, 1)
                      retU = ''                                                    ! attribute keyword / not label-shaped = no return
                    end
                  end
                end
              end
              virtB = 0                                                            ! RECORD the VIRTUAL that only
              if mdx                                                               !   stepped past. A virtual prototype may be
                vdep = 0                                                           !   overridden in a derived class, so nothing
                vdx  = mdx                                                         !   learned from the body in THIS file may be
                loop while ~self.TokIsEOL(vdx)                                     !   assumed at a call site (summaries).
                  case upper(self.TokText(vdx))                                    ! Whole attribute list, not just the first
                  of '('                                                           !   attribute: ,STRING,NAME('x'),VIRTUAL is
                    vdep += 1                                                      !   as legal as ,VIRTUAL. Paren-depth guarded
                  of ')'                                                           !   so a NAME('VIRTUAL') interior cannot count
                    vdep -= 1                                                      !   (a quoted token carries its quotes anyway).
                  of 'VIRTUAL'
                    if ~vdep then virtB = 1 ; break.
                  end
                  vdx += 1
                end
              else
                virtB = 1                                                          ! mdx 0 = the parameter list never closed, so the
              end                                                                  !   attribute list was never reached. Record the REFUSAL, not a "not virtual" we did not see.
              self.AddTypeMethod(curOwner, upper(self.TokText(x)), retU, retRefB, virtB, aMin, aMax, p1U, slotsU, x)
              if self.traceReg
                self.regTrace.append('METH tok ' & x & ' ' & clip(curOwner) & '.' & clip(self.TokText(x)) & ' -> '                                     |
                                     & choose(retU = '', '(none)', clip(retU)) & choose(retRefB = 1, ' ref', '') & choose(virtB = 1, ' virtual', '') & |
                                     ' args ' & aMin & '..' & aMax & choose(p1U = '', '', ' p1=' & clip(p1U))                                        & |
                                     choose(slotsU = '', '', ' slots=' & clip(slotsU)) & '<13,10>')                                                    ! arity is what tells overloads apart, so it has
                                                                                                                                                       !   to be visible. the report shows the slots too
              end
            else                                                                   ! ---- plain data field ----
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
                self.fields.noDim = choose(~isLikeB and self.DimOnLine(x) = 0)
                if osq:dimmed then self.fields.noDim = 0.
                put(self.fields)
              end
            end
          end
        elsif ~pScoped                                                             ! ---- a declaration outside any structure ----
          do IncDeclRow
        end
      end
    end
    lvl = self.TokLevel(x)                                                         ! level accounting over EVERY token (END/'.' carry '-')
    if lvl = '+' then depth += 1.
    if lvl = '-'
      depth -= 1
      loop while records(OwnerStackQ)
        get(OwnerStackQ, records(OwnerStackQ))
        if osq:atDepth >= depth
          if self.traceReg                                                         !
            self.regTrace.append('POP tok ' & x & ' ' & clip(osq:ownerU) & ' atDepth ' & osq:atDepth & ' depth now ' & depth & '<13,10>')
          end
          delete(OwnerStackQ)
        else
          break
        end
      end
    end
  end
  self.regEofDepth = depth                                                         ! non-zero depth / stack at EOF = mis-levelled scan
  self.regEofStack = records(OwnerStackQ)
  if self.traceReg
    self.regTrace.append('EOF depth ' & depth & ' stack ' & records(OwnerStackQ))
    loop while records(OwnerStackQ)                                                ! list stuck owners (top first)
      get(OwnerStackQ, records(OwnerStackQ))
      self.regTrace.append(' [' & clip(osq:ownerU) & '@' & osq:atDepth & ']')
      delete(OwnerStackQ)
    end
    self.regTrace.append('<13,10>')
  end
  self.tk &= saveTk                                                                ! restore the raw stream for subsequent Lookup/scope resolution

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
    dclTok   = 0 ! x indexes the EXPANDED stream: not a position anything else can read
  else
    dclScope = self.ScopeContaining(x, vs:scRoutine, vs:scRoutine)
    if ~dclScope then dclScope = self.ScopeContaining(x, vs:scProc, vs:scMethod).
    dclTok   = x ! the field's own label token, which is where a LIKE target resolves from
  end

! ---- this structure is an array, by DIM on its own opener or on one it sits in, so owner.field[i]
!      through it is a whole element. Any declaration of the name that is one marks the type ----
TypeDimmed routine
  data
tdR long,auto
  code
  tdR = self.FindTypeDef(osq:ownerU)
  if ~tdR then exit.
  get(self.types, tdR)
  if errorcode() then exit.
  self.types.dimmed = 1
  put(self.types)

! ---- the parent THIS declaration names, with the scope it is declared in. When two declarations
!      of one name name different parents the type's own row cannot say which, and ResolveMember
!      picks the one the use site sees from these, as it does for a field. Only the RAW pass:
!      a row with no scope is never narrowed to, so the expanded pass would add rows for nothing ----
ParentRow routine
  do DeclScopeAt
  self.AddTypeField(osq:ownerU, '$PARENT', parentU, 0, 0, dclScope, dclTok)

! ---- a name declared outside every structure, read from the include-expanded stream, filed with
!      the type it is declared with: an ASSUME line never answers for a name the run has read a
!      declaration of (VitMatch.AssumeOf). A procedure or routine label declares no data, and an
!      EQUATE names a constant, never an object - the bulk of a large header, so it is left out ----
IncDeclRow routine
  fldTypeU = ''
  case upper(self.TokText(t2))
  of 'PROCEDURE' orof 'FUNCTION' orof 'ROUTINE' orof 'EQUATE'
    exit
  of '&'
    t3 = t2 + 1
    if ~self.TokIsEOL(t3) and self.IsLabelTok(self.TokText(t3)) then fldTypeU = upper(self.TokText(t3)).
  of 'LIKE'
    fldTypeU = vs:unknownType
  else
    if self.IsLabelTok(self.TokText(t2)) then fldTypeU = upper(self.TokText(t2)).
  end
  if ~fldTypeU then fldTypeU = vs:unknownType.
  clear(self.incDecl)
  self.incDecl.nameU = upper(self.TokText(x))
  self.incDecl.typeU = fldTypeU
  add(self.incDecl)

! ---- a top-level structure with no TYPE attribute declares an INSTANCE, whose type is its own
!      label: marked, so an argument that is one is not taken for an instance of a named type ----
OpenerInst routine
  data
oiX  long,auto
oiD  long
oiR  long,auto
  code
  oiX = t2 + 1
  loop while ~self.TokIsEOL(oiX)
    case upper(self.TokText(oiX))
    of '('
      oiD += 1
    of ')'
      oiD -= 1
    of 'TYPE'
      if ~oiD then exit.
    end
    oiX += 1
  end
  oiR = self.FindTypeDef(upper(self.TokText(x)))
  if ~oiR then exit.
  get(self.types, oiR)
  if errorcode() then exit.
  self.types.isInst = 1
  put(self.types)

! ------------------------------------------------------------------------------------
! The first definition of a name is kept, across units too. A second one that names ANOTHER
! parent - two procedures that each declare `g GROUP(Base)` from a different base - leaves no
! single parent to walk to: the row's parent becomes vs:unknownType, and each declaration's own
! is in its '$PARENT' row (BuildTypeRegistry), from which only a walk that knows its use site
! can pick one.
! ------------------------------------------------------------------------------------
VitSymbols.AddTypeDef Procedure(STRING pTypeU, BYTE pKind, STRING pParentU)
td  long,auto
  code
  td = self.FindTypeDef(pTypeU)
  if td
    get(self.types, td)
    if errorcode() then return.
    if self.types.parentU <> upper(pParentU)
      self.types.parentU = vs:unknownType
      put(self.types)
    end
    return
  end
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
  self.fields.declScope  = pDeclScope  ! NO dedupe, deliberately - two procedures' same-named locals stay TWO rows, and the scope on each is what lets ResolveMember tell them apart rather than merge them here.
  self.fields.declTok    = pDeclTok    !   the token beside the scope, so a LIKE target can be looked up from where the field was declared.
  self.fields.fromRaw    = self.regRaw
  add(self.fields)

! ------------------------------------------------------------------------------------
! The ONE prototype of this method, as a token, so a caller can read its PARAMETER LIST
! from the source. Zero when the class has no visible prototype for the name, or when there
! is more than one (an overload: which body a call binds is not knowable from the name).
! A VIRTUAL method IS answered, and that is a deliberate asymmetry. Plain VIRTUAL does not
! force a derived prototype to match - DERIVED is what does that - so a derived class could in
! principle overload the slot by value. But the only caller of this asks whether a slot may be
! WRITTEN, and the two wrong answers do not cost the same: answering when we should not leaves
! an author's declaration alone, which is harmless, while refusing lets a wrong REMOVE through,
! which is the defect this exists to stop. A visible prototype is evidence; an absent one is
! not, which is why silence still answers nothing.
! ------------------------------------------------------------------------------------
VitSymbols.MethodProtoTok Procedure(STRING pOwnerU, STRING pNameU)
  code
  self.EnsureFresh()
  if self.pmQ &= NULL then return self.MethodProtoTokWork(pOwnerU, pNameU).
  self.PmCheck()
  self.pmQ.key = 'C ' & clip(upper(pOwnerU)) & '.' & upper(pNameU)
  get(self.pmQ, self.pmQ.key)
  if ~errorcode() then return self.pmQ.tok.
  self.pmQ.key = 'C ' & clip(upper(pOwnerU)) & '.' & upper(pNameU)
  self.pmQ.tok = self.MethodProtoTokWork(pOwnerU, pNameU)
  add(self.pmQ, self.pmQ.key)
  return self.pmQ.tok

VitSymbols.MethodProtoTokWork Procedure(STRING pOwnerU, STRING pNameU)
z     long,auto
hit   long,auto
tk    long,auto
expOn byte,auto
  code
  self.EnsureFresh()
  if self.methods &= NULL then return 0.
  expOn = choose(not self.expTk &= NULL)
  hit = 0 ; tk = 0
  loop z = 1 to records(self.methods)
    get(self.methods, z)
    if errorcode() then break.
    if expOn and self.methods.fromRaw then cycle. ! under include expansion the class is recorded
    if self.methods.ownerU <> upper(pOwnerU) or self.methods.nameU <> upper(pNameU) then cycle.
    hit += 1
    if hit > 1 then return 0.
    tk = self.methods.tok
  end
  if hit <> 1 then return 0.
  return tk

! ------------------------------------------------------------------------------------
! record a method prototype's return class. NO dedupe - overloads add one row each
! (a keyed GET lands on an arbitrary row of the run; fine while overloads agree on the
! return class, which they must in Clarion anyway).
! ------------------------------------------------------------------------------------
VitSymbols.AddTypeMethod Procedure(STRING pOwnerU, STRING pNameU, STRING pRetClassU, BYTE pRetRef, BYTE pIsVirtual, LONG pArgMin, LONG pArgMax, STRING pP1TypeU, STRING pSlotsU, LONG pTok)
  code
  clear(self.methods)
  self.methods.ownerU    = upper(pOwnerU)
  self.methods.nameU     = upper(pNameU)
  self.methods.retClassU = upper(pRetClassU)
  self.methods.retRef    = pRetRef
  self.methods.isVirtual = pIsVirtual      !
  self.methods.argMin    = pArgMin         ! still no dedupe - overloads are SUPPOSED to add a row
  self.methods.argMax    = pArgMax         !   each, and arity is what tells them apart
  self.methods.p1TypeU   = upper(pP1TypeU)
  self.methods.pSlotsU   = upper(pSlotsU)  !
  self.methods.tok       = pTok            ! its own declaration, for reading parameters from source
  self.methods.fromRaw   = self.regRaw
  add(self.methods)

! ------------------------------------------------------------------------------------
! Is the first token of this line, inside a MAP or MODULE block, a PROTOTYPE? Any label-shaped
! word that is not one of the block's own keywords counts - in column 1 or indented, with or
! without the PROCEDURE keyword: `Say(STRING pMsg)`, `Mark  procedure(long pX), long`, a bare
! `Foo`. Most MAPs are written indented and keyword-less, and a count of column-1 labels
! only would miss every one of those. The next token settles the rest.
! ------------------------------------------------------------------------------------
VitSymbols.MapProtoAt Procedure(LONG pIx)
tU  string(vs:maxName),auto
! #Removed as not used: nU  string(vs:maxName),auto
  code
  get(self.tk.tokens, pIx)
  if errorcode() then return 0.
  if ~self.tk.tokens.firstOnLine then return 0.
  tU = upper(self.TokText(pIx))
  if ~tU or ~self.IsLabelTok(tU) then return 0.
  if instring(' ' & clip(tU) & ' ', ' MODULE END INCLUDE OMIT COMPILE SECTION PRAGMA ', 1, 1) then return 0.
  if self.TokIsEOL(pIx + 1) then return 1.
  case upper(self.TokText(pIx + 1))
  of '(' orof ',' orof 'PROCEDURE' orof 'FUNCTION'
    return 1
  end
  return 0

! ------------------------------------------------------------------------------------
! The ONE prototype of this name, as a token, so a caller can read its PARAMETER LIST on
! demand rather than the registry carrying a copy of it. Zero when the name has no
! prototype, or more than one: with overloads, which body a call binds is not knowable
! from the name, and answering anyway would be a guess wearing a fact's clothes.
! A MAP or MODULE that INCLUDEs a file may prototype the name there again. With the includes
! read, the include-expanded stream says how many prototypes the compiler sees (ReadIncProtos):
! the answer is this file's token only when that is ONE, and it is this file's own line - the
! same words (ProtoSig). Zero when an include in such a block could not be read, and zero
! whenever the includes were not read and a MAP or MODULE of this file INCLUDEs a file: one
! prototype seen here does not then make it the only one.
! ------------------------------------------------------------------------------------
VitSymbols.MapProtoTok Procedure(STRING pNameU)
  code
  if self.pmQ &= NULL then return self.MapProtoTokWork(pNameU).
  self.PmCheck()
  self.pmQ.key = 'M ' & upper(pNameU)
  get(self.pmQ, self.pmQ.key)
  if ~errorcode() then return self.pmQ.tok.
  self.pmQ.key = 'M ' & upper(pNameU)
  self.pmQ.tok = self.MapProtoTokWork(pNameU)
  add(self.pmQ, self.pmQ.key)
  return self.pmQ.tok

!===============================================================================================
! MapProtoTok and MethodProtoTok remember their answers in pmQ, by name. The answer depends only
! on the prototype tables and the include state, so the memo is dropped when any of them changes:
! a symbol rebuild, a row added to either table, the include flags, the expanded stream switched
! on or off, or the token count.
!===============================================================================================
VitSymbols.PmCheck Procedure()
st  string(80),auto
  code
  st = self.nBuild & ' ' & choose(self.mapProtos &= NULL, 0, records(self.mapProtos)) & ' '                            & |
       choose(self.methods &= NULL, 0, records(self.methods)) & ' ' & self.incRead & self.incMiss & self.mapIncl & ' ' & |
       choose(self.expTk &= NULL, 'R', 'E') & ' ' & choose(self.tk &= NULL, 0, self.tk.records())
  if st <> self.pmStamp
    free(self.pmQ)
    self.pmStamp = st
  end

VitSymbols.MapProtoTokWork Procedure(STRING pNameU)
z  long,auto
  code
  if self.mapProtos &= NULL then return 0.
  loop z = 1 to records(self.mapProtos)
    get(self.mapProtos, z)
    if errorcode() then break.
    if self.mapProtos.nameU = upper(pNameU)
      if self.mapProtos.n <> 1 then return 0.
      if ~self.incRead
        if self.mapIncl then return 0.
        return self.mapProtos.tok
      end
      if self.incMiss then return 0.
      z = self.mapProtos.tok
      if self.IncProtoCount(pNameU) <> 1 then return 0.
      if self.incProtos.sig <> sub(self.ProtoSig(z), 1, size(self.incProtos.sig)) then return 0.
      return z
    end
  end
  return 0

VitSymbols.AddMapProto Procedure(STRING pNameU, STRING pRetU, LONG pTok)
z  long,auto
  code
  if self.mapProtos &= NULL then return.
  loop z = 1 to records(self.mapProtos)
    get(self.mapProtos, z)
    if errorcode() then break.
    if self.mapProtos.nameU = upper(pNameU)
      self.mapProtos.n += 1
      self.mapProtos.tok = 0                                                ! a second prototype of the name: which one a call binds is not knowable here
      if self.mapProtos.retU <> upper(pRetU) then self.mapProtos.retU = ''. ! two prototypes that disagree: no return type is claimed
      put(self.mapProtos)
      return
    end
  end
  clear(self.mapProtos)
  self.mapProtos.nameU = upper(pNameU)
  self.mapProtos.n     = 1
  self.mapProtos.tok   = pTok
  self.mapProtos.retU  = upper(pRetU)
  add(self.mapProtos)

! ------------------------------------------------------------------------------------
! The plain return type of the prototype whose first token is pIx: the keyword after the
! closing ')' - `Foo(STRING p),LONG` gives LONG. '' when there is none, when it is a reference
! or pointer (`,*STRING`, `,&Class`), or when the name is bare. An attribute that is not a
! type (`,PROC`) comes back as it is; a consumer that maps keywords to classes ignores it.
! ------------------------------------------------------------------------------------
VitSymbols.MapProtoRetAt Procedure(LONG pIx)
rf  byte
t   string(vs:maxName),auto
  code
  t = self.ProtoRetAt(pIx, rf)
  if rf then return ''.
  return clip(t)

! ------------------------------------------------------------------------------------
! The return type of the prototype whose first token is pIx, with pIsRef 1 when it is a
! `*` return: `Foo(STRING p),*STRING` gives STRING and 1, `Foo(),LONG` gives LONG and 0.
! '' when there is none or the name is bare. An attribute that is not a type (`,PROC`)
! comes back as it is.
! ------------------------------------------------------------------------------------
VitSymbols.ProtoRetAt Procedure(LONG pIx, *BYTE pIsRef)
p   long,auto
t   string(vs:maxName),auto
  code
  pIsRef = 0
  p = pIx + 1
  t = upper(self.TokText(p))
  case t
  of 'PROCEDURE' orof 'FUNCTION'
    p += 1
    t = upper(self.TokText(p))
  end
  if t = '('
    p = self.tk.MatchLeftBracket('(', ')', p)
    if p < 1 then return ''.
    p += 1
    t = upper(self.TokText(p))
  end
  if t <> ',' then return ''.
  t = upper(self.TokText(p + 1))
  if t = '*'                                                                ! a separate `*` token
    pIsRef = 1
    t = upper(self.TokText(p + 2))
  elsif t[1] = '*'                                                          ! `*STRING` merged into one token
    pIsRef = 1
    t = sub(t, 2, vs:maxName - 1)
  end
  if ~t or ~self.IsLabelTok(clip(t)) then pIsRef = 0 ; return ''.
  return clip(t)

! ------------------------------------------------------------------------------------
! What the procedure or method that pTokPos sits in is prototyped to RETURN: the type,
! with pIsRef 1 for a `*` return (`,*STRING`). '' and 0 when it returns nothing, or when
! no single prototype can be found for it - a MAP in another file, overloads that differ, a
! MAP that INCLUDEs a file holding another prototype of it, or one the run did not read
! (MapProtoTok), the program's own CODE. A RETURN inside a ROUTINE
! returns from its procedure, so the routine is looked through.
! ------------------------------------------------------------------------------------
VitSymbols.ProcReturnAt Procedure(LONG pTokPos, *BYTE pIsRef)
known byte
  code
  return self.ProcReturnRead(pTokPos, pIsRef, known)

! ------------------------------------------------------------------------------------
! ProcReturnAt, with one more answer: pKnown 1 when a prototype was found and read - the one
! MAP prototype of this file, the class's own prototypes of the method, or the program's own
! CODE, which returns nothing - and 0 when '' only means that none could be found. A caller
! that must not take "not found" for "returns a value" asks this one.
! ------------------------------------------------------------------------------------
VitSymbols.ProcReturnRead Procedure(LONG pTokPos, *BYTE pIsRef, *BYTE pKnown)
sid   long,auto
s     long,auto
x     long,auto
dp    long,auto
z     long,auto
hit   long,auto
nmU   string(vs:maxName),auto
retU  string(vs:maxName)
expOn byte,auto
  code
  pIsRef = 0
  pKnown = 0
  self.EnsureFresh()
  sid = self.ScopeContaining(pTokPos, vs:scProc, vs:scMethod)
  if ~sid then return ''.
  loop s = 1 to records(self.scopes)
    get(self.scopes, s)
    if self.scopes.scopeId = sid then break.
  end
  if self.scopes.scopeId <> sid then return ''.
  x = self.scopes.startTok
  if self.scopes.kind = vs:scProc
    z = self.MapProtoTok(upper(self.TokText(x)))                            ! a MAP prototype of this file, and only one
    if ~z then return ''.
    pKnown = 1
    return self.ProtoRetAt(z, pIsRef)
  end
  if self.scopes.kind = vs:scMain then pKnown = 1.
  if self.scopes.kind <> vs:scMethod then return ''.                        ! the program's own CODE returns nothing
  dp = self.IsDottedLabel(self.TokText(x))
  if dp                                                                     ! Class.Method as one token
    nmU = upper(sub(self.TokText(x), dp + 1, vs:maxName))
  elsif self.TokText(x + 1) = '.'                                           ! Class . Method as three
    nmU = upper(self.TokText(x + 2))
  else                                                                      ! the older form, Name PROCEDURE(Class SELF)
    nmU = upper(self.TokText(x))
  end
  if self.methods &= NULL then return ''.
  expOn = choose(not self.expTk &= NULL)
  hit = 0
  loop z = 1 to records(self.methods)
    get(self.methods, z)
    if errorcode() then break.
    if expOn and self.methods.fromRaw then cycle.                           ! under include expansion the class is recorded twice
    if self.methods.ownerU <> self.scopes.selfClass or self.methods.nameU <> nmU then cycle.
    if hit and (self.methods.retClassU <> retU or self.methods.retRef <> pIsRef)
      pIsRef = 0                                                            ! overloads that disagree: which one this
      return ''                                                             !   body is cannot be told from its name
    end
    hit += 1
    retU = self.methods.retClassU
    pIsRef = self.methods.retRef
  end
  if ~hit then return ''.
  pKnown = 1
  return clip(retU)

! ------------------------------------------------------------------------------------
! The return type of the ONE MAP prototype of the name, when MapProtoTok finds it: '' when there
! is none, more than one, or a file a MAP or MODULE INCLUDEs may hold another (MapProtoTok).
! ------------------------------------------------------------------------------------
VitSymbols.MapProtoReturn Procedure(STRING pNameU)
z  long,auto
  code
  if self.mapProtos &= NULL then return ''.
  if ~self.MapProtoTok(pNameU) then return ''.
  loop z = 1 to records(self.mapProtos)
    get(self.mapProtos, z)
    if errorcode() then break.
    if self.mapProtos.nameU = upper(pNameU) then return self.mapProtos.retU.
  end
  return ''

! ------------------------------------------------------------------------------------
! The type the include-expanded stream declares pNameU with, outside every structure: '' when
! it declares no such name, vs:unknownType when a declaration of it cannot be read or two of
! them disagree. A class built on StringTheory that overrides none of its methods answers
! STRINGTHEORY, as an object of it declared in this file does (StKinRetype).
! ------------------------------------------------------------------------------------
VitSymbols.IncDeclType Procedure(STRING pNameU)
k   long,auto
r   long,auto
nU  string(vs:maxName),auto
tU  string(vs:maxName),auto
  code
  if self.incDecl &= NULL then return ''.
  nU = upper(pNameU)
  self.incDecl.nameU = nU
  get(self.incDecl, self.incDecl.nameU)
  if errorcode() then return ''.
  r  = pointer(self.incDecl)
  tU = self.incDecl.typeU
  loop k = r - 1 to 1 by -1
    get(self.incDecl, k)
    if errorcode() or self.incDecl.nameU <> nU then break.
    if self.incDecl.typeU <> tU then return vs:unknownType.
  end
  loop k = r + 1 to records(self.incDecl)
    get(self.incDecl, k)
    if errorcode() or self.incDecl.nameU <> nU then break.
    if self.incDecl.typeU <> tU then return vs:unknownType.
  end
  if tU = vs:unknownType then return vs:unknownType.
  if self.PureStKin(tU) then return 'STRINGTHEORY'.
  return clip(tU)

! ------------------------------------------------------------------------------------
! The MAP prototypes of this file, by name, counted. Every prototype line inside a MAP or
! MODULE block counts (MapProtoAt: any column, with or without PROCEDURE), and a name with
! two of them is an OVERLOAD: a call binds by signature, and the other body may be in
! another file, so a summary of the body that IS here says nothing about that call.
! With the includes read, the count is the include-expanded stream's (ReadIncProtos), which
! holds every file a MAP or MODULE INCLUDEs: a prototype there counts as one here does, and so
! does a name prototyped only there. The larger of the two counts is taken, so a prototype
! this file's stream holds is never lost. When an include in such a block could not be read,
! or the includes were not read and a MAP or MODULE of this file INCLUDEs a file, a name may
! be prototyped again where the run cannot see: a name with a prototype counts one more than
! those seen, and reads as an overload. So does a name this file prototypes that the expanded
! stream does not hold, when a MAP or MODULE of this file INCLUDEs a file: that stream was not
! read as this file is, so it cannot vouch for the include. A name with no prototype the run
! has seen counts 0.
! ------------------------------------------------------------------------------------
VitSymbols.MapProtoCount Procedure(STRING pNameU)
z  long,auto
n  long
  code
  if self.mapProtos &= NULL then return 0.
  loop z = 1 to records(self.mapProtos)
    get(self.mapProtos, z)
    if errorcode() then break.
    if self.mapProtos.nameU = upper(pNameU)
      n = self.mapProtos.n
      break
    end
  end
  if ~self.incRead
    if n then n += self.mapIncl.
    return n
  end
  z = self.IncProtoCount(pNameU)
  if n and ~z and self.mapIncl then n += 1.
  if z > n then n = z.
  if n then n += self.incMiss.
  return n

! ------------------------------------------------------------------------------------
! THE MAP PROTOTYPES OF THE INCLUDE-EXPANDED STREAM, read once per file with the expanded
! registry. That stream is this file with each include it could read written in where its
! INCLUDE stood, so a MAP there holds the prototypes of every file it INCLUDEs as well as this
! file's own, and a MAP an included file holds is there too. The blocks are found as Build
! finds them in this file: a MAP or MODULE opener, its level marks, and the same resync. Each
! prototype line files one row, its name and its words (ProtoSig), and the rows are sorted by
! name. incMiss is set when such a block still holds an include that was not read - the line
! the expansion writes for one it could not find or read, which begins '! #error', or an
! INCLUDE left as text because it would not parse - since that file may prototype a name again.
! ------------------------------------------------------------------------------------
VitSymbols.ReadIncProtos Procedure()
saveTk  &VitTokenize
N       long,auto
x       long,auto
t2      long,auto
depth   long
w2      StringTheory
  code
  free(self.incProtos)
  self.incRead = 0
  self.incMiss = 0
  if self.expTk &= NULL or self.incProtos &= NULL then return.
  saveTk &= self.tk
  self.tk &= self.expTk
  N = self.tk.records()
  loop x = 1 to N
    get(self.tk.tokens, x)
    if errorcode() then break.
    if depth
      do InBlock
      cycle
    end
    if self.tk.tokens.level <> '+' or ~self.tk.tokens.firstOnLine then cycle.
    case upper(self.TokText(x))
    of 'MAP' orof 'MODULE'
      depth = 1
    end
  end
  self.tk &= saveTk
  sort(self.incProtos, +self.incProtos.nameU)
  self.incRead = 1

! ---- one token inside a MAP or MODULE block. The '! #error' line is trivia, so it is in the
!      text in front of a token, and is looked for before anything else moves the buffer ----
InBlock routine
  if not self.tk.tokens.strBefore &= NULL
    if instring('! #error ', self.tk.tokens.strBefore, 1, 1) then self.incMiss = 1.
  end
  if self.TokIsEOL(x) then exit.
  if self.IsColOneLabel(x) or self.ColOneMethodDot(x)
    t2 = x + 1
    if ~self.TokIsEOL(t2)
      w2.setValue(upper(self.TokText(t2)))
      if self.ColOneMethodDot(x) and inlist(w2.getValue(), 'PROCEDURE', 'FUNCTION')
        depth = 0
        exit
      end
      if inlist(w2.getValue(), 'ROUTINE', '.')
        depth = 0
        exit
      end
    end
  end
  if self.MapProtoAt(x)
    clear(self.incProtos)
    self.incProtos.nameU = upper(self.TokText(x))
    self.incProtos.sig = self.ProtoSig(x)
    add(self.incProtos)
  end
  if upper(self.TokText(x)) = 'INCLUDE' then self.incMiss = 1.
  case self.TokLevel(x)
  of '+'
    depth += 1
  of '-'
    depth -= 1
  end

! ------------------------------------------------------------------------------------
! How many prototypes of the name the include-expanded stream holds (ReadIncProtos), 0 when
! none. When there is one, its row is left in the buffer, so its words can be read.
! ------------------------------------------------------------------------------------
VitSymbols.IncProtoCount Procedure(STRING pNameU)
k   long,auto
r   long,auto
n   long,auto
nU  string(vs:maxName),auto
  code
  if self.incProtos &= NULL then return 0.
  if ~records(self.incProtos) then return 0.
  nU = upper(pNameU)
  self.incProtos.nameU = nU
  get(self.incProtos, self.incProtos.nameU)
  if errorcode() then return 0.
  r = pointer(self.incProtos)
  n = 1
  loop k = r - 1 to 1 by -1
    get(self.incProtos, k)
    if errorcode() or self.incProtos.nameU <> nU then break.
    n += 1
  end
  loop k = r + 1 to records(self.incProtos)
    get(self.incProtos, k)
    if errorcode() or self.incProtos.nameU <> nU then break.
    n += 1
  end
  get(self.incProtos, r)
  return n

! ------------------------------------------------------------------------------------
! The words of the prototype line that starts at pIx, upper-cased and one space apart, with
! no continuation bar: one line reads the same in this file's own stream and in the
! include-expanded one, however it is spaced, split or commented.
! ------------------------------------------------------------------------------------
VitSymbols.ProtoSig Procedure(LONG pIx)
p   long,auto
sg  StringTheory
  code
  p = pIx
  loop while ~self.TokIsEOL(p)
    if self.TokText(p) <> '|' then sg.append(upper(self.TokText(p)) & ' ').
    p += 1
  end
  return sg.getValue()

! ------------------------------------------------------------------------------------
! How many prototypes of method pNameU does class pOwnerU see - its own rows and every
! parent's, walked as MethodIsVirtual walks them, since an inherited overload binds too.
! More than one = an overload, and the summary of the one body here must not be trusted.
! A parent that cannot be told - the name declared again with another one - counts as an
! overload, so the body here is not trusted.
! ------------------------------------------------------------------------------------
VitSymbols.MethodProtoCount Procedure(STRING pOwnerU, STRING pNameU)
m     long,auto
td    long,auto
n     long
curO  string(vs:maxName),AUTO
nU    string(vs:maxName),auto
hops  long,AUTO
expOn byte,auto
  code
  self.EnsureFresh()
  if self.methods &= NULL then return 0.
  expOn = choose(not self.expTk &= NULL)
  curO = upper(pOwnerU)
  nU   = upper(pNameU)
  if ~curO or ~nU then return 0.
  hops = 0
  loop
    hops += 1
    if hops > 32 then break.
    loop m = 1 to records(self.methods)
      get(self.methods, m)
      if errorcode() then break.
      if expOn and self.methods.fromRaw then cycle.                          ! under include expansion every class is in the EXPANDED rows once; the raw
      if self.methods.ownerU = curO and self.methods.nameU = nU then n += 1. !   pass adds this file's again, and a count must not see both
    end
    td = self.FindTypeDef(curO)
    if ~td then break.
    get(self.types, td)
    if errorcode() then break.
    if ~self.types.parentU then break.
    if self.types.parentU = vs:unknownType
      if n < 2 then n = 2.
      break
    end
    curO = self.types.parentU
  end
  return n

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
! A parent that cannot be told - the name declared again with another one - is -1 as well.
! ------------------------------------------------------------------------------------
VitSymbols.MethodIsVirtual Procedure(STRING pOwnerU, STRING pNameU)
m     long,auto
td    long,auto
seen  long,auto
curO  string(vs:maxName),AUTO
nU    string(vs:maxName),AUTO
hops  long,AUTO
  code
  self.EnsureFresh()                      ! consumer gate
  if self.methods &= NULL then return -1.
  seen = 0
  curO = upper(pOwnerU)
  nU   = upper(pNameU)
  if ~curO or ~nU then return -1.
  hops = 0
  loop
    hops += 1
    if hops > 32 then break.              ! inheritance cycle cap (ResolveMember's)
    loop m = 1 to records(self.methods)
      get(self.methods, m)
      if errorcode() then break.
      if self.methods.ownerU <> curO or   |
         self.methods.nameU <> nU
        cycle
      end
      seen = 1
      if self.methods.isVirtual then return 1.
    end
    td = self.FindTypeDef(curO)           ! not declared here - try the parent
    if ~td then break.
    get(self.types, td)
    if errorcode() then break.
    if ~self.types.parentU then break.
    if self.types.parentU = vs:unknownType then return -1.
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
! Both are answered, and the second REFUSES wherever it cannot be answered
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
fp     long,auto          ! first row of the (owner, name) run
fq     long,auto
fSeen  byte,auto
fTy    string(vs:maxName)
fLk    byte,auto          ! the run's isLike, and it must agree like the type does
clash  byte,auto          ! this hop's run disagrees, so the run ALONE has no answer - the narrowing below is the only thing that can still produce one
usRt   long,auto          ! the use site's ROUTINE scope, 0 = not inside one
usPr   long,auto          !   ... and its proc/method scope (0 = module level - a real answer)
usOk   byte,auto          !   ... and whether the caller told us where it was asking from
usGot  byte,auto          ! asked already: ONE pair of lookups per call, and only on a hop that is refusing
usHost long               ! the procedure a method's class belongs to: a rung of its own
usWall byte               ! the first rung the narrowing may not climb past - see UseSiteWalls
tClash byte               ! this hop's type is declared twice with two parents: its own run is narrowed too
nLevel long,auto          ! the scope being filtered on right now - one rung of the ladder
nSeen  byte,auto          ! narrowing: a row survived the filter
nTy    string(vs:maxName) !   ... its type
nLk    byte,auto          !   ... and its isLike
nClash byte,auto          ! two survivors disagreed - then that rung has no single answer either
fDt    long,auto          ! the run's declaration TOKEN, for resolving a LIKE(someVariable) target
fDtC   byte,auto          !   ... and 1 when two rows that BOTH know where they were declared name different places, so there is no single
                          !   place to ask from and the LIKE target is refused. A row with declTok 0 has no opinion either way
nDt    long,auto          ! the narrowed row's declaration token, and its own agreement flag
nDtC   byte,auto
lvTy   string(vs:maxName) ! LIKE(someVariable): what the TARGET variable is declared as
lvRef  byte,auto          !   ... its by-reference flag, which nothing here reads
lvOk   byte,auto          !   ... and whether the target resolved at all
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
    if hops > 32 then break.                    ! inheritance cycle cap
    ! *** A RUN OF ROWS MAY DISAGREE, AND THEN THERE IS NO ANSWER. *** AddTypeField does not
    ! dedupe and the registry is scope-blind, so two procedures that each declare a local QUEUE
    ! of the same name contribute their fields to ONE (owner, name) run. Answering from whichever
    ! row a keyed GET happens to land on would give one procedure the other's type - with the
    ! shipped rules, `if clip(lq.s)` where s is a LONG would become `if lq.s`, which is exactly
    ! what the clip-truthiness rule exists to forbid.
    !
    ! So, as MethodReturnClass does: walk the whole run and refuse if
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
    tClash = 0
    td = self.FindTypeDef(curO)
    if td then do TypeClash.
    if self.regSorted                           ! keyed GET per hop instead of scanning every field
      self.fields.ownerU = curO
      self.fields.nameU  = nU
      get(self.fields, self.fields.ownerU, self.fields.nameU)
      if ~errorcode()
        fp = pointer(self.fields)
        loop fq = fp - 1 to 1 by -1             ! back to the start of the run
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
            clash = 1                           ! the run disagrees - do not guess from it. one further question is asked below
            break
          elsif self.fields.declTok             ! a row that KNOWS where it was declared. A row that
            if ~fDt                             !   does not - declTok 0, the include-EXPANDED pass -
              fDt = self.fields.declTok         !   has no opinion and neither answers nor objects,
            elsif self.fields.declTok <> fDt    !   which is what lets the two passes share a run.
              fDtC = 1                          ! two declarations wearing one LIKE target: the TYPE
            end                                 !   agrees so this is no clash, but there is no single
          end                                   !   scope to resolve that target from
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
          clash = 1                             ! same rule, and the same second question, on the unsorted path
          break
        elsif self.fields.declTok               ! and the same LIKE-target rule, on the unsorted path
          if ~fDt
            fDt = self.fields.declTok
          elsif self.fields.declTok <> fDt
            fDtC = 1
          end
        end
      end
    end
    if tClash and ~clash
      if fSeen then do OwnNarrow.
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
    if self.types.parentU = vs:unknownType
      do ParentNarrow
      if ~curO then break.
      cycle
    end
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
!
! A METHOD OF A CLASS A PROCEDURE DECLARES shares that procedure's data, so the procedure is a
! rung of its own between the method and the module. And the ladder stops at a scope whose data
! INCLUDEs a file (UseSiteWalls): a row further out may be hidden by one this table never read.
ScopeNarrow routine
  ! one pair of lookups per CALL, not per hop, and only ever on a hop that has already
  ! decided to refuse. 0 back from the second is MODULE LEVEL, which is an answer
  if ~usGot
    usGot = 1
    if pUseTok > 0
      usRt = self.ScopeContaining(pUseTok, vs:scRoutine, vs:scRoutine)
      usPr = self.ScopeContaining(pUseTok, vs:scProc, vs:scMethod)
      usOk = 1
      do UseSiteWalls
    end
  end
  nSeen  = 0
  nTy    = ''
  nLk    = 0
  nClash = 0
  nDt    = 0
  nDtC   = 0
  if ~usOk then exit.
  ! rung 1: this routine's own DATA
  if usRt
    nLevel = usRt
    do NarrowRun
    if nSeen or usWall = 1 then exit.
  end
  ! rung 2, only when rung 1 held nothing at all: the procedure's locals, which its routines
  ! can see too
  nLevel = usPr
  do NarrowRun
  if nSeen or usWall = 2 then exit.
  ! rung 3, for a method of a class a procedure declares: that procedure's locals
  if usHost > 0
    nLevel = usHost
    do NarrowRun
    if nSeen or usWall = 3 then exit.
  end
  ! rung 4: MODULE level, which every scope in the file can see. usPr 0 already IS module
  ! level, so rung 2 asked it in that case and this rung adds nothing
  if usPr
    nLevel = 0
    do NarrowRun
  end

! WHERE THE LADDER MUST STOP. A scope whose data INCLUDEs a file may declare the name itself,
! where this table cannot see it, so a row found further out may be the wrong one; so may a
! module row for a method whose class belongs to a procedure that cannot be told. usWall is
! the last rung that may be asked: 1 the routine, 2 the procedure or method, 3 the procedure
! a local class belongs to; 0 = no wall.
UseSiteWalls routine
  usWall = 0
  usHost = 0
  if usRt
    get(self.scopes, usRt)
    if ~errorcode() and self.scopes.unseen then usWall = 1 ; exit.
  end
  if ~usPr then exit.
  get(self.scopes, usPr)
  if errorcode() then exit.
  if self.scopes.unseen or self.scopes.hostId < 0 then usWall = 2 ; exit.
  usHost = self.scopes.hostId
  if usHost < 1 then exit.
  get(self.scopes, usHost)
  if ~errorcode() and self.scopes.unseen then usWall = 3.

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

! the type at this hop is declared twice, naming two different parents
TypeClash routine
  get(self.types, td)
  if errorcode() then exit.
  if self.types.parentU = vs:unknownType then tClash = 1.

! A TYPE NAME DECLARED TWICE WITH TWO PARENTS - two procedures' `g GROUP(Base)` from different
! bases - makes even an AGREEING run of its own fields unsafe: its one row may be the other
! declaration's, where this one takes the field from its parent. So the run is narrowed to the
! use site as a disagreeing one is. No row there means the field is not this declaration's own,
! and the walk goes on to the parent the use site sees.
OwnNarrow routine
  do ScopeNarrow
  if nClash
    self.runClash += 1
    return ''
  end
  fSeen = nSeen
  fTy   = nTy
  fLk   = nLk
  fDt   = nDt
  fDtC  = nDtC

! THE PARENT OF A TYPE DECLARED TWICE WITH TWO PARENTS: each declaration filed its own as a
! '$PARENT' row with the scope it was declared in, and the same narrowing picks the one the use
! site can see. None, or two that disagree, ends the walk with no answer. '$' is not legal in a
! Clarion label, so no field of the source can be in the way.
ParentNarrow routine
  data
pnU  string(vs:maxName),auto
  code
  pnU = nU
  nU = '$PARENT'
  fp = 0
  if self.regSorted
    self.fields.ownerU = curO
    self.fields.nameU  = nU
    get(self.fields, self.fields.ownerU, self.fields.nameU)
    if ~errorcode()
      fp = pointer(self.fields)
      loop fq = fp - 1 to 1 by -1
        get(self.fields, fq)
        if errorcode() then break.
        if self.fields.ownerU <> curO or self.fields.nameU <> nU then break.
        fp = fq
      end
    end
  end
  nSeen  = 0
  nClash = 0
  if fp or ~self.regSorted then do ScopeNarrow.
  nU = pnU
  if nSeen and ~nClash and nTy
    curO = nTy
  else
    curO = ''
  end

! ------------------------------------------------------------------------------------
! could a call carrying pArgCount arguments BE this prototype?
! Refusing to answer is spelled -1 in both directions and always means YES here: an
! unreadable parameter list, or a caller that does not know its own argument count,
! must not silently exclude a row - that would turn "I cannot tell" into "not this one".
! ------------------------------------------------------------------------------------
VitSymbols.ArityAdmits Procedure(LONG pArgMin, LONG pArgMax, LONG pArgCount)
  code
  if pArgCount < 0 or           |   ! caller does not know - every row stays in play
     pArgMin < 0 or pArgMax < 0 ! prototype unreadable - same
    return 1
  end
  if pArgCount < pArgMin or     |
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
! type the argument, and then every row stays in play and the run refuses just as arity alone
! would. That direction matters: an identifier we merely FAILED to resolve might well be the
! class instance, and excluding the class-typed row on that basis would pick the
! STRING-returning overload and license a rewrite on a call that never returns a string.
! ------------------------------------------------------------------------------------
! could THIS CALL be this prototype? Both sides carry every position: pSlotsU is the
! prototype's parameter types and pArgTypesU is what the caller could work out about its
! arguments, each '|'-terminated and in order.
!
! WHY AN UNKNOWN NEVER NARROWS. Each position is tested independently, and an empty
! argument slot, an empty parameter slot, or a slot list we could not record all of, all
! return "admits". So a call is settled by whichever of its arguments can be typed, and a
! call where nothing is typeable is refused - a name we merely FAILED to resolve must never
! exclude the row it might belong to.
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
aInst byte,auto               ! this argument is a structure instance, passed whole
aTd   long,auto               !   ... and the registry row that says so
  code
  if pArgCount < 1 or                          |   ! nothing to test
     ~pArgTypesU   or                          |   ! caller could type NOTHING - do not narrow
     ~pSlotsU                                  ! prototype's parameter types unreadable - same
    return 1
  end
  aPos = 1 ; sPos = 1
  loop n = 1 to pArgCount
    do NextArg                                 ! aPos -> aTok
    do NextSlot                                ! sPos -> sTok
    if ~aTok or                                |   ! this argument could not be typed - no opinion
       ~sTok                                   ! ran off the end of the slot list - ditto
      cycle
    end
    if aTok = vs:unknownType then cycle.
    if aTok = vs:scalarArg                     ! a numeric or quoted LITERAL: definitely a value,
      if self.FindTypeDef(sTok) then return 0. !   so a parameter wanting a class instance is out
      cycle
    end
    if aTok <> sTok
      ! two SCALAR types that differ are not a positive mismatch: a value parameter takes an
      ! argument of any scalar type - the compiler converts it on the call, and its overloading
      ! rules count every value parameter as one type - so a BYTE argument binds a LONG slot
      ! exactly as a LONG one does, and excluding the row here sent the lookup to the PARENT
      ! class, whose same-named method is the one the call does NOT reach. A class or structure
      ! type on either side against a different type is the mismatch this test is for.
      if instring(' ' & clip(aTok) & ' ', vs:scalarTypes, 1, 1) and instring(' ' & clip(sTok) & ' ', vs:scalarTypes, 1, 1) then cycle.
      do InstArg
      if aInst then cycle.
      return 0
    end
  end
  return 1

! AN ARGUMENT THAT IS A STRUCTURE'S OWN LABEL - an instance passed whole - binds by more than
! its type's name: a CLASS by derivation, a GROUP as a STRING, a QUEUE to any QUEUE parameter.
! None of that is read here, so such an argument has no opinion, as when its label is not
! known at all.
InstArg routine
  aInst = 0
  aTd = self.FindTypeDef(aTok)
  if ~aTd then exit.
  get(self.types, aTd)
  if ~errorcode() and self.types.isInst then aInst = 1.

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
p     long,auto          ! overload run: the row the keyed GET landed on
rc    string(vs:maxName) !   its return class, and
rr    byte               !   its ref flag - both must hold across the WHOLE run
seenA byte,auto          ! linear branch: first matching row found
  code
  self.EnsureFresh()                                                                  ! consumer gate
  pIsRef = 0
  curO = upper(pOwnerU)
  nU = upper(pNameU)
  hops = 0
  loop
    hops += 1
    if hops > 32 then break.                                                          ! inheritance cycle cap
    if self.regSorted                                                                 ! keyed GET per hop, like ResolveMember
      self.methods.ownerU = curO
      self.methods.nameU  = nU
      get(self.methods, self.methods.ownerU, self.methods.nameU)
      if ~errorcode()                                                                 ! this lands on ONE row of an OVERLOAD RUN, and AddTypeMethod
        p = pointer(self.methods)                                                     !   deliberately does not dedupe - overloads are correct Clarion
        loop m = p - 1 to 1 by -1                                                     !   and the return class belongs to the OVERLOAD, not the name.
          get(self.methods, m)                                                        !   Walk to the start of the run; owner+name alone bound it.
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
          end                                                                         !   counted. Refuse rather than guess: the argument TYPES, asked by
        end                                                                           !   ArgAdmits above, are what separate those.
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
        if ~self.ArgAdmits(self.methods.pSlotsU, pArgCount, pArgTypesU) then cycle.   ! both paths ask the same two questions: arity, then argument types.
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
    td = self.FindTypeDef(curO)                                                       ! not declared here - try the parent
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
! A method-implementation label 'Class.Method' is a SINGLE column-1 token (the '.' only
! splits in expression context), and IsLabelTok rejects it (no '.' in a label). Recognise
! it so Build can create the method scope + SELF. Returns the first '.' position, or 0.
! The implementation of an INTERFACE method has one more part, `Class.Interface.Method`
! (LRM IMPLEMENTS), and is the same kind of header: its receiver is the class.
! ------------------------------------------------------------------------------------
VitSymbols.IsDottedLabel Procedure(STRING pTok)
p     long,auto
q     long,auto
tLen  long,auto
  code
  tLen = len(clip(pTok))
  p = instring('.', pTok, 1, 1)
  if p < 2 or p >= tLen then return 0.                                 ! no '.', or leading/trailing '.'
  if ~self.IsLabelTok(sub(clip(pTok), 1, p - 1)) then return 0.        ! receiver-class part
  q = instring('.', pTok, 1, p + 1)                                    ! a second '.': Class.Interface.Method
  if q then do TwoDot.
  if ~self.IsLabelTok(sub(clip(pTok), p + 1, tLen - p)) then return 0. ! method part (one '.'; a second one is TwoDot's)
  return p

! Class.Interface.Method: the interface and the method are labels too, and a third '.' is not
! part of a label
TwoDot routine
  if q >= tLen then return 0.
  if ~self.IsLabelTok(sub(clip(pTok), p + 1, q - p - 1)) then return 0.
  if ~self.IsLabelTok(sub(clip(pTok), q + 1, tLen - q)) then return 0.
  return p

! ------------------------------------------------------------------------------------
! The same column-1 test as IsColOneLabel, for the one label shape IsLabelTok rejects: a
! method implementation header, `Class.Method`, which the tokenizer leaves as a single
! dotted token. Returns the position of the dot. A continued line does not open a line
! here either - the reason is written out under IsColOneLabel - and the last read puts
! the shared token buffer back on pIx, where the caller expects it.
! ------------------------------------------------------------------------------------
VitSymbols.ColOneMethodDot Procedure(LONG pIx)
dp   long,auto
  code
  get(self.tk.tokens, pIx)
  if errorcode() then return 0.
  if ~self.tk.tokens.firstOnLine then return 0.
  if ~self.tk.BufColOne() then return 0. ! trivia in front that does not end at a line feed = not column 1
  if self.tk.tokens.tok &= NULL then return 0.
  dp = self.IsDottedLabel(clip(self.tk.tokens.tok))
  if ~dp then return 0.
  if ~self.TokIsEOL(pIx - 1) then return 0.
  get(self.tk.tokens, pIx)
  return dp

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
                  ']<13,10>')                                                                                       ! a duplicate (owner,name) run is only readable in a dump if the rows say where they came from
    end
    loop f = 1 to records(self.methods)                                                !
      get(self.methods, f)
      if self.methods.ownerU <> self.types.typeU then cycle.
      ! show the ARITY and the SLOTS: a bare '()' for every method says nothing about how
      ! two overloads differ, and a dump that cannot distinguish the rows it is dumping is
      ! worse than no dump.
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
  if ~self.dirty then return. ! byte test on the hot path; rebuild only when an edit intervened
  self.dirty = 0              ! before Build (which also clears) - belt and braces against re-entry
  if not self.tk &= NULL then self.Build(self.tk).

! ------------------------------------------------------------------------------------
VitSymbols.Lookup Procedure(STRING pName, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef)
  code
  self.EnsureFresh() ! every matcher path funnels through here / LookupChain / FindTypeDef
  return self.LookupIn(upper(clip(pName)), pTokPos, pTypeU, pIsRef, 0)

! ------------------------------------------------------------------------------------
VitSymbols.LookupIn Procedure(STRING pNameU, LONG pTokPos, *STRING pTypeU, *BYTE pIsRef, LONG pDepth)
sym  long
tgt  STRING(vs:maxName)
  code
  if pDepth > 8 then return false. ! LIKE cycle cap
  ! Visible walks the ladder and says what the name binds to. A structure written as a block
  ! answers its own label, the name the type registry knows it by. A name declared where this
  ! table cannot read it, or that a declaration it cannot see may hide, answers vs:unknownType
  ! as a reference: no typed rule accepts it, and no pass trusts it as plain storage.
  self.visMode = 1
  case self.Visible(pNameU, pTokPos, sym)
  of vs:visSym
    do Resolve
  of vs:visHidden
    get(self.hidden, sym)
    if errorcode() then return false.
    pTypeU = self.hidden.typeU
    pIsRef = 0
    if self.hidden.typeU = vs:unknownType then pIsRef = 1.
    return true
  of vs:visUnknown
    pTypeU = vs:unknownType
    pIsRef = 1
    return true
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
! the declared length of a plain STRING(n) variable, read from its declaration: the
! symbol row keeps the type keyword only (STRING(20) is filed as STRING), and the WHERE
! guard isOneChar needs the number. Resolves the name the way LookupIn does - routine,
! then procedure or method, then module - and reads the tokens after the label:
! `x STRING(1)` is label, STRING, (, 1, ). 0 for anything else: a reference, a LIKE, a
! structure field (the registry files fields by type keyword too), an unknown name, a
! STRING with no length, or a declaration carrying DIM.
!
! DIM IS NOT A LENGTH, and it is the whole reason the number is asked for. `x STRING(1),DIM(5)`
! is five one-character elements and the whole variable is five characters, so a caller told
! "one" compares all five where it meant to compare one and the program takes the other
! branch. DeclaredHasDim answers that question and is asked it here, and its -1 - the
! declaration could not be read at all - refuses the same way a DIM does.
!
! A name declared twice in one scope - the two arms of an OMIT and a COMPILE - answers 0 as
! well: which declaration compiles is not known here.
! ------------------------------------------------------------------------------------
VitSymbols.DeclaredStrLen Procedure(STRING pName, LONG pTokPos)
sym  long
t    long,auto
nm   STRING(vs:maxName),AUTO
num  StringTheory
  code
  self.EnsureFresh()
  nm = upper(pName)
  if self.Visible(nm, pTokPos, sym) <> vs:visSym then return 0.
  if self.SymRunLen(sym) > 1 then return 0.
  get(self.syms, sym)
  if errorcode() then return 0.
  if self.syms.typeU <> 'STRING' or self.syms.isRef or self.syms.isLike or self.syms.isField then return 0.
  t = self.syms.declTok
  if upper(self.TokText(t + 1)) <> 'STRING' then return 0.
  if self.TokText(t + 2) <> '(' or self.TokText(t + 4) <> ')' then return 0.
  num.setValue(self.TokText(t + 3))
  if ~num._DataEnd or ~num.IsAllDigits() then return 0.
  if self.DeclaredHasDim(pName, pTokPos) then return 0.
  return num.getValue()

! ------------------------------------------------------------------------------------
! Does pName's declaration carry DIM? THREE answers, because two of them are not the
! same: 1 = it does, 0 = it provably does not, -1 = CANNOT TELL.
!
! It matters because `x[i]` is one character only for a plain string. With DIM it selects
! a whole ELEMENT - LRM p124, `Contact[1]` of a `STRING(15),DIM(4)` is fifteen characters
! and the one-character form needs the second subscript - so a caller that reads `x[i]` as
! one character would compare the whole element where val() read a single byte, and the
! program takes the other branch.
!
! -1 is returned rather than 0 for anything not actually read: a name that does not
! resolve, a LIKE whose target is not followed, a reference, and a declaration CONTINUED
! with a bar, where the attribute could be on the next line. A caller wanting safety
! treats -1 the way it treats 1.
!
! An array parameter (`*STRING[] p`) and a field of a DIM'd structure carry their DIM away from
! their own line, and answer 1 from the symbol row. A structure's own label is read from its
! opener line; a name declared twice in one scope, or whose declaration cannot be read, is -1.
! ------------------------------------------------------------------------------------
VitSymbols.DeclaredHasDim Procedure(STRING pName, LONG pTokPos)
sym   long
nm    STRING(vs:maxName),AUTO
  code
  self.EnsureFresh()
  nm = upper(pName)
  case self.Visible(nm, pTokPos, sym)
  of vs:visSym
    if self.SymRunLen(sym) > 1 then return -1.
    get(self.syms, sym)
    if errorcode() then return -1.
    if self.syms.dimHeld then return 1.
    if self.syms.isLike or self.syms.isRef then return -1.
    return self.DimOnLine(self.syms.declTok)
  of vs:visHidden
    get(self.hidden, sym)
    if errorcode() then return -1.
    if self.hidden.typeU = vs:unknownType then return -1.
    return self.DimOnLine(self.hidden.declTok)
  end
  return -1

! ------------------------------------------------------------------------------------
! The DIM question for one declaration, by the token of its label: 1 = it carries DIM, 0 = its
! line was read to the end without one, -1 = cannot tell (the line runs on with a bar, or past
! what is read). Asked by DeclaredHasDim for a variable, and by the type registry for a field
! as it records it - from the stream the field was read in, which may be the included one.
! ------------------------------------------------------------------------------------
VitSymbols.DimOnLine Procedure(LONG pDeclTok)
k     long,auto
j     long,auto
nlp   long,auto
atEnd long ! the walk reached the end of the declaration's line
  code
  ! walk the declaration's own line. The label is firstOnLine, so the scan starts after it
  ! and stops at the token that opens the NEXT line - unless a bar says the declaration is
  ! not finished, and then the honest answer is that it was not read.
  loop k = pDeclTok + 1 to pDeclTok + 120
    if self.TokIsEOL(k) then atEnd = 1 ; break.
    get(self.tk.tokens, k)
    if errorcode() then break.
    if self.tk.tokens.firstOnLine
      if not self.tk.tokens.strBefore &= NULL
        nlp = 0
        loop j = 1 to size(self.tk.tokens.strBefore)
          if self.tk.tokens.strBefore[j] = '<10>'
            nlp = j
            break
          end
        end
        if nlp
          loop j = 1 to nlp
            if self.tk.tokens.strBefore[j] = '|' then return -1.
          end
        end
      end
      atEnd = 1
      break
    end
    if self.tk.tokens.tok &= NULL then cycle.
    if upper(self.tk.tokens.tok) = 'DIM' then return 1.
  end
  if ~atEnd then return -1. ! the walk ran out before the line did: a declaration this long was not read to its end, and nothing is proved about it
  return 0

! ------------------------------------------------------------------------------------
! Is owner.name[i] ONE character? Only when every row recorded for the field - its owner first,
! then the classes and groups it inherits from - is a STRING, CSTRING or PSTRING, or a reference
! to one, read without DIM. A reference is fine here: name[i] reads the string it points at, one
! character of it, and the code dereferences it whichever spelling it is written in. 0 for a
! field with no rows, rows that disagree, a LIKE, or a declaration not read to its end.
! A structure that is itself an array, by its own DIM or one it sits in, makes every field
! through it a whole element: 0. So does a name declared again with another parent.
! ------------------------------------------------------------------------------------
VitSymbols.FieldOneChar Procedure(STRING pOwnerU, STRING pNameU)
z     long,auto
td    long,auto
hops  long,auto
hit   long,auto
curO  string(vs:maxName),auto
  code
  self.EnsureFresh()
  if self.fields &= NULL then return 0.
  curO = upper(pOwnerU)
  loop hops = 1 to 32           ! inheritance cycle cap, as ResolveMember
    td = self.FindTypeDef(curO)
    if td
      get(self.types, td)
      if errorcode() then return 0.
      if self.types.dimmed then return 0.
      if self.types.parentU = vs:unknownType then return 0.
    end
    hit = 0
    loop z = 1 to records(self.fields)
      get(self.fields, z)
      if errorcode() then break.
      if self.fields.ownerU <> curO or self.fields.nameU <> upper(pNameU) then cycle.
      hit += 1
      if ~self.fields.noDim then return 0.
      case self.fields.fieldTypeU
      of 'STRING' orof 'CSTRING' orof 'PSTRING'
      else
        return 0
      end
    end
    if hit then return 1.
    td = self.FindTypeDef(curO) ! not declared here: the parent it inherits from
    if ~td then return 0.
    get(self.types, td)
    if errorcode() or ~self.types.parentU then return 0.
    curO = self.types.parentU
  end
  return 0

! ------------------------------------------------------------------------------------
! Is x[i] ONE character, for a plain variable x? The variable's twin of FieldOneChar: 1 when the
! declaration was read and carries no DIM, and it is not a LIKE - and when it is a reference, it
! refers to a STRING, CSTRING or PSTRING. A reference is fine here for the same reason it is for
! a field: x[i] reads the string it points at, one character of it. 0 for a name that does not
! resolve, a LIKE, a reference to anything else, a DIM, or a declaration not read to its end.
! 0 too for an array whose DIM is not on its own line, a structure's label, and a name declared
! twice in one scope or where this table cannot read it.
! ------------------------------------------------------------------------------------
VitSymbols.VarOneChar Procedure(STRING pName, LONG pTokPos)
sym   long
nm    STRING(vs:maxName),AUTO
  code
  self.EnsureFresh()
  nm = upper(pName)
  if self.Visible(nm, pTokPos, sym) <> vs:visSym then return 0.
  if self.SymRunLen(sym) > 1 then return 0.
  get(self.syms, sym)
  if errorcode() then return 0.
  if self.syms.isLike or self.syms.dimHeld then return 0.
  if self.syms.isRef
    case self.syms.typeU
    of 'STRING' orof 'CSTRING' orof 'PSTRING'
    else
      return 0
    end
  end
  return choose(self.DimOnLine(self.syms.declTok) = 0)

! ------------------------------------------------------------------------------------
! the first plain instance of a type visible from a token: a local of the routine, then
! of the procedure or method, then a module-level declaration - the innermost wins, and
! within a scope the first declared. A reference (&Type) is never offered: it can be
! NULL at the call, and a method on a NULL reference is a crash. Returns the declaration
! token, so the caller can spell the name the way the author did (the row holds it upper).
! For a method of a class a procedure declares, that procedure is asked before the module. The
! name of what is found has to mean that declaration where it is used, or nothing is offered.
! ------------------------------------------------------------------------------------
VitSymbols.FirstInstanceOf Procedure(STRING pTypeU, LONG pTokPos)
sc       long,auto
best     long
bestDecl long
k        long,auto
bestName STRING(vs:maxName)
  code
  self.EnsureFresh()
  sc = self.ScopeContaining(pTokPos, vs:scRoutine, vs:scRoutine)
  if sc then do Scan.
  if ~best
    sc = self.ScopeContaining(pTokPos, vs:scProc, vs:scMethod)
    if sc then do Scan.
    if ~best and sc then do HostScan.
  end
  if ~best
    sc = self.ScopeContaining(pTokPos, vs:scModule, vs:scModule)
    if sc then do Scan.
  end
  if best then do Binds.
  return best

Scan routine
  loop k = 1 to records(self.syms)
    get(self.syms, k)
    if errorcode() then break.
    if self.syms.scopeId <> sc or self.syms.isRef or self.syms.isLike or self.syms.isField then cycle.
    if self.syms.typeU <> upper(pTypeU) then cycle.
    if ~best or self.syms.declTok < best then best = self.syms.declTok ; bestName = self.syms.nameU.
  end
  bestDecl = best
  if best then do NameTok.

! the row keeps the name in upper case and declTok is where the DECLARATION was read, which for a
! parameter is the token after the name. The caller spells the name as the author did, so find
! the token near declTok whose text IS the name.
NameTok routine
  data
nt  long,auto
  code
  loop nt = best - 2 to best + 2
    if nt < 1 then cycle.
    if upper(self.TokText(nt)) = bestName
      best = nt
      exit
    end
  end
  best = 0

! the procedure a method's class belongs to, whose locals the method shares
HostScan routine
  get(self.scopes, sc)
  if errorcode() or self.scopes.hostId < 1 then exit.
  sc = self.scopes.hostId
  do Scan

! the instance found must be what its NAME means at pTokPos: a declaration nearer the use
! site, or one this table cannot see, may hide it, and then the name is something else
Binds routine
  data
bRow long
  code
  self.visMode = 2
  if self.Visible(bestName, pTokPos, bRow) <> vs:visSym
    best = 0
    exit
  end
  get(self.syms, bRow)
  if errorcode() or self.syms.declTok <> bestDecl then best = 0.

! ------------------------------------------------------------------------------------
! the innermost scope of kind pKind1 or pKind2 that holds pTokPos; 0 = none. Scopes of
! one kind never overlap, so the first hit is the answer.
! ------------------------------------------------------------------------------------
VitSymbols.ScopeContaining Procedure(LONG pTokPos, BYTE pKind1, BYTE pKind2)
s  long,auto
  code
  ! scopes of one kind never overlap, so the first hit is the scope
  loop s = 1 to records(self.scopes)
    get(self.scopes, s)
    if self.scopes.kind <> pKind1 and self.scopes.kind <> pKind2
      if self.scopes.kind <> vs:scMain then cycle.
      if pKind1 <> vs:scProc and pKind2 <> vs:scProc then cycle. ! the main CODE is a procedure scope to a pass that asks for one (ruled 13 Sep 2026)
    end
    if pTokPos >= self.scopes.startTok and pTokPos <= self.scopes.endTok
      return self.scopes.scopeId
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! Is pTypeU a class derived from StringTheory - through classes whose headers this table holds -
! none of which declares a method StringTheory has? A prototype of the same name is an override,
! an overload included. A class whose parent's header is not held is not one: that parent could
! be any class (ruled 1 Nov 2026). 1 = it only adds methods of its own.
! ------------------------------------------------------------------------------------
VitSymbols.PureStKin Procedure(STRING pTypeU)
c   STRING(vs:maxName),AUTO
td  long,auto
d   long,auto
m   long,auto
kin StringTheory
  code
  if self.stMeth &= NULL then return 0.
  c = upper(pTypeU)
  kin.setValue(' ')
  loop d = 1 to 16                                         ! first the parents, by key: almost every class
    if c = 'STRINGTHEORY' then break.                      !   asked about is not derived from StringTheory
    td = self.FindTypeDef(c)
    if ~td then return 0.
    get(self.types, td)
    if errorcode() or self.types.kind <> vs:tkClass then return 0.
    kin.append(clip(c) & ' ')
    c = self.types.parentU
    if ~c then return 0.
  end
  if c <> 'STRINGTHEORY' or d = 1 then return 0.
  loop m = 1 to records(self.methods)                      ! then the prototypes of the classes on the way
    get(self.methods, m)
    if errorcode() then return 0.
    if kin.findChars(' ' & clip(self.methods.ownerU) & ' ') and self.stMeth.findChars(' ' & clip(self.methods.nameU) & ' ') then return 0.
  end
  return 1

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
! FindSym, and one more answer: for the main CODE of a PROGRAM (a vs:scMain scope), a name
! declared at program level is the main code's own when no procedure, method or routine
! outside the main code so much as mentions it - a routine of the main code is part of it.
! Ruled 13 Sep 2026: the line and value passes treat the main CODE as a procedure, and a
! program-level object they would drop, rename or trim must be checked across every
! procedure first, because it lives for the whole program.
! Ruled 29 Oct 2026: the program's other source files can read program-level data too, and
! this table reads only this file. So no name is the main code's own when the file INCLUDEs
! anything or has a MODULE - a MAP section, or a CLASS whose methods are in another file -
! nor one declared EXTERNAL, DLL or EXPORT, or a field of a structure that is.
! ------------------------------------------------------------------------------------
VitSymbols.FindOwn Procedure(STRING pNameU, LONG pScopeId)
sym   long,auto
main  long,auto
s     long,auto
t     long,auto
nmU   string(vs:maxName),auto
wantU string(vs:maxName),auto
h     long,auto
d     long,auto
  code
  sym = self.FindSym(pNameU, pScopeId)
  if sym then return sym.
  get(self.scopes, pScopeId)
  if errorcode() then return 0.
  if self.scopes.kind <> vs:scMain then return 0.
  main = pScopeId
  sym = self.FindSym(pNameU, self.scopes.parentId) ! the module scope: a program-level declaration
  if ~sym then return 0.
  if self.syms.linked then return 0.               ! EXTERNAL, DLL or EXPORT: another module holds it or reaches it
  loop t = 1 to self.tk.records()                  ! an INCLUDE anywhere, or a MODULE - a section of the MAP, or a CLASS
    get(self.tk.tokens, t)                         !   whose methods are in another source file: code this file does
    if errorcode() then return 0.                  !   not hold may name program data
    if self.tk.tokens.tok &= NULL then cycle.
    if inlist(upper(self.tk.tokens.tok), 'INCLUDE', 'MODULE') and self.tk.GetTok(t + 1) = '(' then return 0.
  end
  wantU = upper(pNameU)
  loop s = 1 to records(self.scopes)
    get(self.scopes, s)
    if errorcode() then return 0.
    if self.scopes.kind = vs:scModule or self.scopes.kind = vs:scMain then cycle.
    if self.scopes.kind = vs:scRoutine and self.scopes.parentId = main then cycle.
    loop t = self.scopes.startTok to self.scopes.endTok
      get(self.tk.tokens, t)
      if errorcode() then return 0.
      if self.tk.tokens.tok &= NULL then cycle.
      if self.tk.tokens.type <> vt:label then cycle.
      nmU = upper(self.tk.tokens.tok)
      h = len(clip(nmU))
      loop d = 1 to h
        if nmU[d] = '.' then h = d - 1 ; break.
      end
      if h < 1 then cycle.
      if nmU[1 : h] = wantU then return 0.         ! mentioned elsewhere: not the main code's own
    end
  end
  return sym

! ------------------------------------------------------------------------------------
! WHAT A NAME AT pTok BINDS TO, asked the way the compiler resolves it: the ROUTINE's DATA,
! then the PROCEDURE or METHOD, then - for a method of a class a procedure declares in its
! data - THAT PROCEDURE, whose locals the method shares, then the MODULE.
!
! The first scope that declares the name answers. Two things make the answer unknown rather
! than wrong. A scope that declares the name twice, the two disagreeing - the arms of an OMIT
! and a COMPILE - or as both a symbol and a hidden name, has no single declaration. And once
! the ladder has passed a scope whose data INCLUDEs a file, or a method whose procedure cannot
! be told, a declaration found further out may be hidden by one this table never read: the
! name is declared, so it is not nothing, but what it is cannot be told.
! The same holds for a declaration inside a COMPILE or conditional OMIT block that does not hold
! the use: a build without the block has no such declaration, and the name is then whatever is
! declared further out. A row in no block, or in a block that holds the use, answers as before,
! and so does a name declared alike in both arms of a COMPILE and an OMIT. Two modes, set in
! visMode for one call: 1, a question of TYPE alone (LookupIn), answers the block's row when the
! declaration a build without the block reads has the same type - every build sees that type;
! 2 (FirstInstanceOf) reads past the blocks, for a caller that asks its own block question.
!
! vs:visSym with pRow a syms row, vs:visHidden with pRow a hidden row, vs:visUnknown, or
! vs:visNone when nothing on the ladder declares it - an undeclared name.
! ------------------------------------------------------------------------------------
VitSymbols.Visible Procedure(STRING pNameU, LONG pTok, *LONG pRow)
sc    long,auto
nmU   string(vs:maxName),auto
wall  byte
ans   long
mode  byte,auto
pend  long
pRs   long
  code
  mode = self.visMode
  self.visMode = 0
  pRow = 0
  nmU = upper(pNameU)
  sc = self.ScopeContaining(pTok, vs:scRoutine, vs:scRoutine)
  if sc
    do Rung
    if ans then return ans.
  end
  sc = self.ScopeContaining(pTok, vs:scProc, vs:scMethod)
  if sc
    do Rung
    if ans then return ans.
    get(self.scopes, sc)
    if ~errorcode()
      if self.scopes.hostId < 0 then wall = 1.
      if self.scopes.hostId > 0
        sc = self.scopes.hostId
        do Rung
        if ans then return ans.
      end
    end
  end
  sc = self.ScopeContaining(pTok, vs:scModule, vs:scModule)
  if sc
    do Rung
    if ans then return ans.
  end
  if pend then return vs:visUnknown.
  return vs:visNone

! one rung: what scope sc itself declares under the name
Rung routine
  data
rs  long,auto
rh  long,auto
rc  long,auto
bs  byte,auto
bh  byte,auto
  code
  bs = 0
  bh = 0
  rs = self.FindSym(nmU, sc)
  if rs and self.syms.blkTok
    if pTok <= self.syms.blkTok or pTok >= self.syms.blkEnd then bs = 1.
  end
  rh = self.FindHidden(nmU, sc)
  if rh and self.hidden.blkTok
    if pTok <= self.hidden.blkTok or pTok >= self.hidden.blkEnd then bh = 1.
  end
  if ~rs and ~rh
    get(self.scopes, sc)
    if ~errorcode() and self.scopes.unseen then wall = 1.
    exit
  end
  ans = vs:visUnknown
  if wall then exit.
  if rs and rh then exit.
  if rs
    if ~self.SymRunAgrees(rs) then exit.
    if bs
      rc = self.SymRunCovers(rs, pTok)
      if rc > 0
        rs = rc
      elsif ~rc and mode = 1
        if pend then exit.
        pend = rs
        ans = 0
        exit
      elsif ~rc and mode <> 2
        exit
      end
    end
    if pend
      pRs = rs
      do PendSame
      exit
    end
    pRow = rs
    ans = vs:visSym
  else
    if pend then exit.
    if ~self.HiddenRunAgrees(rh) then exit.
    if bh
      rc = self.HiddenRunCovers(rh, pTok)
      if rc > 0
        rh = rc
      elsif ~rc and mode <> 2
        exit
      end
    end
    pRow = rh
    ans = vs:visHidden
  end

! a type question (mode 1): the block's row pend answers when the declaration a build without
! the block reads, syms row rs, has the same type and reference flag, and neither is a LIKE
PendSame routine
  data
tU  string(vs:maxName),auto
iR  byte,auto
iL  byte,auto
  code
  get(self.syms, pRs)
  if errorcode() then exit.
  tU = self.syms.typeU
  iR = self.syms.isRef
  iL = self.syms.isLike
  get(self.syms, pend)
  if errorcode() then exit.
  if iL or self.syms.isLike then exit.
  if self.syms.typeU <> tU or self.syms.isRef <> iR then exit.
  pRow = pend
  ans = vs:visSym

! ------------------------------------------------------------------------------------
VitSymbols.FindHidden Procedure(STRING pNameU, LONG pScopeId)
  code
  if self.hidden &= NULL then return 0.
  if ~records(self.hidden) then return 0.
  self.hidden.scopeId = pScopeId
  self.hidden.nameU   = pNameU
  get(self.hidden, self.hidden.scopeId, self.hidden.nameU)
  if errorcode() then return 0.
  return pointer(self.hidden)

! ------------------------------------------------------------------------------------
! How many rows share the scope and name of syms row pRow. syms is sorted on (scope, name), so
! they are neighbours. Two or more is a name declared twice in one scope, which only the arms
! of an OMIT and a COMPILE can do in source that compiles: which one the compiler keeps is not
! known here, so a question about the declaration's length or DIM has no answer.
! ------------------------------------------------------------------------------------
VitSymbols.SymRunLen Procedure(LONG pRow)
k    long,auto
n    long,auto
sc   long,auto
nmU  string(vs:maxName),auto
  code
  get(self.syms, pRow)
  if errorcode() then return 0.
  sc  = self.syms.scopeId
  nmU = self.syms.nameU
  n = 1
  loop k = pRow - 1 to 1 by -1
    get(self.syms, k)
    if errorcode() then break.
    if self.syms.scopeId <> sc or self.syms.nameU <> nmU then break.
    n += 1
  end
  loop k = pRow + 1 to records(self.syms)
    get(self.syms, k)
    if errorcode() then break.
    if self.syms.scopeId <> sc or self.syms.nameU <> nmU then break.
    n += 1
  end
  get(self.syms, pRow)
  return n

! ------------------------------------------------------------------------------------
! Do all the rows sharing syms row pRow's scope and name say the same TYPE - the type, its
! reference flag and its LIKE flag? One row always does. Two that differ leave the name with
! no single type in that scope. The rows are neighbours, as SymRunLen walks them.
! ------------------------------------------------------------------------------------
VitSymbols.SymRunAgrees Procedure(LONG pRow)
k    long,auto
sc   long,auto
nmU  string(vs:maxName),auto
tU   string(vs:maxName),auto
iR   byte,auto
iL   byte,auto
  code
  get(self.syms, pRow)
  if errorcode() then return 0.
  sc  = self.syms.scopeId
  nmU = self.syms.nameU
  tU  = self.syms.typeU
  iR  = self.syms.isRef
  iL  = self.syms.isLike
  loop k = pRow - 1 to 1 by -1
    get(self.syms, k)
    if errorcode() then break.
    if self.syms.scopeId <> sc or self.syms.nameU <> nmU then break.
    if self.syms.typeU <> tU or self.syms.isRef <> iR or self.syms.isLike <> iL then return 0.
  end
  loop k = pRow + 1 to records(self.syms)
    get(self.syms, k)
    if errorcode() then break.
    if self.syms.scopeId <> sc or self.syms.nameU <> nmU then break.
    if self.syms.typeU <> tU or self.syms.isRef <> iR or self.syms.isLike <> iL then return 0.
  end
  return 1

! ------------------------------------------------------------------------------------
! The same question of a hidden row: two hidden declarations of one name in one scope must
! say the same type.
! ------------------------------------------------------------------------------------
VitSymbols.HiddenRunAgrees Procedure(LONG pRow)
k    long,auto
sc   long,auto
nmU  string(vs:maxName),auto
tU   string(vs:maxName),auto
  code
  get(self.hidden, pRow)
  if errorcode() then return 0.
  sc  = self.hidden.scopeId
  nmU = self.hidden.nameU
  tU  = self.hidden.typeU
  loop k = pRow - 1 to 1 by -1
    get(self.hidden, k)
    if errorcode() then break.
    if self.hidden.scopeId <> sc or self.hidden.nameU <> nmU then break.
    if self.hidden.typeU <> tU then return 0.
  end
  loop k = pRow + 1 to records(self.hidden)
    get(self.hidden, k)
    if errorcode() then break.
    if self.hidden.scopeId <> sc or self.hidden.nameU <> nmU then break.
    if self.hidden.typeU <> tU then return 0.
  end
  return 1

! ------------------------------------------------------------------------------------
! Which row of syms row pRow's run - its scope and name - is the declaration in every build that
! has the use at pTok? A row in no COMPILE or OMIT block is: a build that also kept a block's
! row of that name would declare it twice and not compile. So is a row whose block holds pTok,
! since the use is in a build only with that block. The answer is that row, so what is read from
! it - its DIM, STATIC or THREAD - is the declaration's own. When every row is in a block pTok is
! not in: -1 for two or more rows - the arms of a COMPILE and an OMIT, which Visible answers as
! their agreed type - and 0 for one, whose block a build may leave out.
! ------------------------------------------------------------------------------------
VitSymbols.SymRunCovers Procedure(LONG pRow, LONG pTok)
k    long,auto
sc   long,auto
nmU  string(vs:maxName),auto
  code
  get(self.syms, pRow)
  if errorcode() then return 0.
  sc  = self.syms.scopeId
  nmU = self.syms.nameU
  loop k = pRow to 1 by -1
    get(self.syms, k)
    if errorcode() then break.
    if self.syms.scopeId <> sc or self.syms.nameU <> nmU then break.
    if ~self.syms.blkTok then return k.
    if pTok > self.syms.blkTok and pTok < self.syms.blkEnd then return k.
  end
  loop k = pRow + 1 to records(self.syms)
    get(self.syms, k)
    if errorcode() then break.
    if self.syms.scopeId <> sc or self.syms.nameU <> nmU then break.
    if ~self.syms.blkTok then return k.
    if pTok > self.syms.blkTok and pTok < self.syms.blkEnd then return k.
  end
  if k > pRow + 1 then return -1.
  get(self.syms, pRow - 1)
  if ~errorcode() and self.syms.scopeId = sc and self.syms.nameU = nmU then return -1.
  return 0

! ------------------------------------------------------------------------------------
! The same question of a hidden row's run.
! ------------------------------------------------------------------------------------
VitSymbols.HiddenRunCovers Procedure(LONG pRow, LONG pTok)
k    long,auto
sc   long,auto
nmU  string(vs:maxName),auto
  code
  get(self.hidden, pRow)
  if errorcode() then return 0.
  sc  = self.hidden.scopeId
  nmU = self.hidden.nameU
  loop k = pRow to 1 by -1
    get(self.hidden, k)
    if errorcode() then break.
    if self.hidden.scopeId <> sc or self.hidden.nameU <> nmU then break.
    if ~self.hidden.blkTok then return k.
    if pTok > self.hidden.blkTok and pTok < self.hidden.blkEnd then return k.
  end
  loop k = pRow + 1 to records(self.hidden)
    get(self.hidden, k)
    if errorcode() then break.
    if self.hidden.scopeId <> sc or self.hidden.nameU <> nmU then break.
    if ~self.hidden.blkTok then return k.
    if pTok > self.hidden.blkTok and pTok < self.hidden.blkEnd then return k.
  end
  if k > pRow + 1 then return -1.
  get(self.hidden, pRow - 1)
  if ~errorcode() and self.hidden.scopeId = sc and self.hidden.nameU = nmU then return -1.
  return 0

! ------------------------------------------------------------------------------------
VitSymbols.AddHidden Procedure(STRING pNm, LONG pSc, STRING pTy, LONG pTok)
  code
  if self.hidden &= NULL then return.
  clear(self.hidden)
  self.hidden.nameU   = upper(pNm)
  self.hidden.scopeId = pSc
  self.hidden.typeU   = upper(pTy)
  self.hidden.declTok = pTok
  add(self.hidden)

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
VitSymbols.AddSym Procedure(STRING pNameU, LONG pScope, STRING pTypeU, BYTE pIsRef, BYTE pIsLike, LONG pDeclTok, BYTE pIsField=0, BYTE pLinked=0)
  code
  clear(self.syms)
  self.syms.nameU   = pNameU
  self.syms.scopeId = pScope
  self.syms.typeU   = pTypeU
  self.syms.isRef   = pIsRef
  self.syms.isLike  = pIsLike
  self.syms.declTok = pDeclTok
  self.syms.isField = pIsField
  self.syms.linked  = pLinked
  add(self.syms)

! ------------------------------------------------------------------------------------
! Parameter list: (TYPE name, *TYPE name, <TYPE name>, &TYPE name ...)
! type-first then name; '*' '<' '>' '&' markers skipped; unnamed prototype
! parameters add nothing. STRING(20)-style sizes handled by depth tracking.
! A parameter written with no type word is filed as declared with no known type, and an array
! parameter (`*STRING[] p`) as an array whose DIM is not on its own line.
! ------------------------------------------------------------------------------------
VitSymbols.ParseParams Procedure(LONG pOpenTok, LONG pScope)
x       long,auto
depth   long,auto
typeU   STRING(vs:maxName)
nameU   STRING(vs:maxName)
isRefP  BYTE ! defensive only: '&' is not a legal parameter spelling (*TYPE is). A reference LOCAL is flagged by ExtractDeclType
t       StringTheory
isArr   BYTE
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
        isRefP = 0
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
      ! '&' NEVER MERGES - and a PARAMETER is never spelled with one. A by-address
      ! parameter is *TYPE, and the prototype parameter lists have no &TYPE form at all.
      ! The marker is still read here, defensively: source that spells one anyway files
      ! the parameter as a reference, which only ever makes this tool MORE careful. The
      ! flag that carries the real weight is set on a DECLARATION, by ExtractDeclType -
      ! a reference LOCAL is legal and common, and that flag is what keeps a rewrite off
      ! a reference which can be NULL: a method on one is a crash the tool would cause.
      if depth = 1 and ~typeU
        if t.valuePtr[1] = '&' then isRefP = 1.
        if t._DataEnd > 1 and self.IsLabelTok(t.valuePtr[2 : t._DataEnd])
          typeU = upper(t.valuePtr[2 : t._DataEnd])
        end
        if t._DataEnd = 2 and t.valuePtr[2] = '?' then typeU = vs:unknownType.
      end
    of 91                         ! '['
      do OpenBracket
    of 93                         ! ']'
      depth -= 1
    of 63                         ! '?' - a parameter of unspecified type
      if depth = 1 and ~typeU then typeU = vs:unknownType.
    else
      if depth = 1 and self.IsLabelTok(t.getValue())
        if ~typeU
          ! CONST is the qualifier of a variable parameter - (CONST *CSTRING Value) - and not
          ! its type. The '*' after it does not merge with the type (it merges only after '('
          ! ',' or '<'), so the tokens here are CONST, '*', CSTRING, Value: the word is stepped
          ! past, the marker is read by the arm above, and CSTRING is the type.
          if upper(t.getValue()) = 'CONST' then cycle.
          typeU = upper(t.getValue())
        elsif ~nameU
          nameU = upper(t.getValue())
        end
      end
    end
  end

! ---- a parameter named SELF is the class instance of the older method form, and Build has
!      already added it as SELF
FlushParam routine
  if typeU and ~nameU then nameU = typeU ; typeU = vs:unknownType.
  if typeU = vs:unknownType then do FlushUnknown.
  if typeU and nameU and nameU <> 'SELF'
    self.AddSym(nameU, pScope, typeU, isRefP, 0, x)
    if isArr then self.syms.dimHeld = 1 ; put(self.syms).
  end
  isRefP = 0
  isArr = 0

! ---- a parameter with no type word - `? pVal`, or `pNum` whose type is left to the prototype
!      (LRM PROCEDURE: the type is optional, the label is not) - is still a parameter, and it
!      hides any outer name it shares. Filed as declared, with no known type ----
FlushUnknown routine
  if nameU <> 'SELF' and nameU <> vs:unknownType then self.AddHidden(nameU, pScope, vs:unknownType, x).
  typeU = ''

! ---- an array parameter, `*STRING[] pArr`: the brackets after the type say so, and a comma
!      inside them, `[,]`, separates dimensions, not parameters ----
OpenBracket routine
  if depth = 1 and typeU then isArr = 1.
  if t._DataEnd = 1 then depth += 1.

! ------------------------------------------------------------------------------------
VitSymbols._List Procedure(StringTheory pOut)
s  long,auto
  code
  pOut.free()
  pOut.append('Scopes: ' & records(self.scopes) & '<13,10>')
  loop s = 1 to records(self.scopes)
    get(self.scopes, s)
    pOut.append('  ' & self.scopes.scopeId & ' kind=' & self.scopes.kind & ' parent=' & self.scopes.parentId & |
                ' toks ' & self.scopes.startTok & '..' & self.scopes.endTok                                  & |
                choose(self.scopes.selfClass <> '', ' self=' & clip(self.scopes.selfClass), '') & '<13,10>')
    if self.scopes.hostId or self.scopes.unseen
      pOut.append('    host=' & self.scopes.hostId & ' unseen=' & self.scopes.unseen & '<13,10>')
    end
  end
  pOut.append('Symbols: ' & records(self.syms) & '<13,10>')
  loop s = 1 to records(self.syms)
    get(self.syms, s)
    pOut.append('  ' & clip(self.syms.nameU) & '  scope ' & self.syms.scopeId & '  '                             & |
                choose(self.syms.isRef=1,'&','') & choose(self.syms.isLike=1,'LIKE ','') & clip(self.syms.typeU) & |
                '  @tok ' & self.syms.declTok & '<13,10>')
    if self.syms.dimHeld then pOut.append('    dimHeld<13,10>').
  end
  pOut.append('Hidden names: ' & records(self.hidden) & '<13,10>')
  loop s = 1 to records(self.hidden)
    get(self.hidden, s)
    pOut.append('  ' & clip(self.hidden.nameU) & '  scope ' & self.hidden.scopeId & '  ' & clip(self.hidden.typeU) & |
                '  @tok ' & self.hidden.declTok & '<13,10>')
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
! The token opens a line, stands in column 1, and is shaped like a name - the position a
! Clarion LABEL is written in, which is how a declaration, a procedure header and a jump
! target are told from the code around them.
!
! A CONTINUED LINE DOES NOT OPEN ONE. The line feed that ends a continued line is carried
! in the leading text of the NEXT token instead of arriving as a line-break token of its
! own, so the first token after a continuation bar counts as first on its line, and
! written hard against the left margin it stands in column 1 as well. It still holds no
! label: in a parameter list split over two lines, the type word beginning the second
! line belongs to the list, not to a new statement. What really opens a line is the
! line-break token in front of it, so that is what is asked for. Text folded away by
! OMIT carries line feeds in the same place and still has that token in front of it, so
! a label after an omitted block is read as the column-1 label it is.
!
! The last read puts the shared token buffer back on pIx, where the caller expects it.
! ------------------------------------------------------------------------------------
VitSymbols.IsColOneLabel Procedure(LONG pIx)
  code
  get(self.tk.tokens, pIx)
  if errorcode() then return false.
  if ~self.tk.tokens.firstOnLine then return false.
  if ~self.tk.BufColOne() then return false. ! trivia in front that does not end at a line feed = not column 1
  if self.tk.tokens.tok &= NULL then return false.
  if ~self.IsLabelTok(clip(self.tk.tokens.tok)) then return false.
  if ~self.TokIsEOL(pIx - 1) then return false.
  get(self.tk.tokens, pIx)
  return true

! ------------------------------------------------------------------------------------
VitSymbols.IsLabelTok Procedure(STRING pTok)
x    long,auto
  code
  if ~pTok then return false.
  loop x = 1 to len(clip(pTok))
    case val(pTok[x])
    of   65 to 90     ! A-Z
    orof 97 to 122    ! a-z
    orof 95           ! _
    of   48 to 57     ! 0-9
    orof 58           ! :
      if x = 1 then return false.
    else
      return false
    end
  end
  return true
