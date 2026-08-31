! VitEngine - Phase 5 of VitTransform
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! See VitEngine.inc header. File loop, wildcards and CLI parsing live in the
! driver program (vitTransform.clw), mirroring vtxaDiff's Transformations
! structure; this class handles one file end to end.
!
!
  MEMBER

  Include('StringTheory.inc'),ONCE
  Include('VitTokenize.inc'),ONCE
  Include('VitRules.inc'),ONCE
  Include('VitSymbols.inc'),ONCE
  Include('VitMatch.inc'),ONCE
  Include('VitRewrite.inc'),ONCE
  Include('VitTimer.inc'),ONCE
  Include('VitEngine.inc'),ONCE

  MAP
  END

! ====================================================================================
VitEngine.Construct Procedure()
  code
  self.tk   &= new VitTokenize
  self.syms &= new VitSymbols
  self.rw   &= new VitRewrite
  self.tmr  &= new VitTimer
  self.rl   &= NULL
  self.maxPasses  = 20
  self.progressFn = 'VitTransform.progress.txt' ! real (stamped) name is built in Init - the driver cannot set self.stamp before the global's CONSTRUCT runs
  self.pp        &= NULL                        ! allocated only if SetupIncludes is called
  self.exptk     &= NULL
  self.ppLineMap &= NULL
  self.ppSrc     &= NULL
  self.useIncludes = 0
  self.recvMode = rm:check                      ! DEFAULT: see --receiver=
  self.stMeth &= new StringTheory
  self.dgPure &= new StringTheory
  self.KnownRangePureList(self.dgPure)          ! THE BASE LIST ONLY.
                                                !   A rule file's PURE(...)
                                                !   additions are not here, so
                                                !   this refuses slightly more
                                                !   than KnownRanges does - the
                                                !   safe direction for a walk
                                                !   that DELETES a guard.
  ! EVERY ENTRY IS DELIMITED AT BOTH ENDS, and the extraction is CASE-BLIND. The lookup
  ! is instring(' NAME ', table), so the LAST entry needs a trailing space or it can never
  ! match - _SWITCHENDIAN was unmatchable and read as foreign. And StringTheory.inc spells
  ! two prototypes `procedure` and `PROCEDURE` rather than `Procedure`, so a case-sensitive
  ! extraction missed FormatHTML and IsTime. Each of those three made --receiver=check
  ! REFUSE a call it should have converted, which is the one thing check is supposed never
  ! to do.
  self.stMeth.append(' ABBREVIATE ADDBOM ADDLINE ADJUSTLENGTH AFTER AFTERLAST AFTERNTH ALL ANSITOUTF16 ')
  self.stMeth.append(' ANSITOUTF8 APIANSITOUTF8 APIUTF8TOANSI APPEND APPENDA APPENDBINARY ASNDECODE ASNENCODE ')
  self.stMeth.append(' ASNENCODENUMBER ASSIGN BASE32DECODE BASE32ENCODE BASE64DECODE BASE64ENCODE BASE85DECODE ')
  self.stMeth.append(' BASE85ENCODE BASETODEC BEFORE BEFORELAST BEFORENTH BETWEEN BIGENDIAN BYTETOHEX CAPACITY ')
  self.stMeth.append(' CAPITALIZE CAT CATADDR CHANGEBASE CHARS CHARTODECENTITY CLARIONTOUNIXDATE CLEANFILENAME ')
  self.stMeth.append(' CLIP CLIPLEN CLIPLENGTH COLORFROMHEX COLORTOHEX COLORTOLONG CONSTRUCT CONTAINSA ')
  self.stMeth.append(' CONTAINSADIGIT CONTAINSBYTE CONTAINSCHAR CONVERTANSITOOEM CONVERTOEMTOANSI CONVERTTABS ')
  self.stMeth.append(' COUNT COUNTBYTE COUNTWORDS CREATEDATEPICTURE CREATEHEXPICTURE CREATEKEYINPICTURE ')
  self.stMeth.append(' CREATENUMERICPICTURE CREATEPATTERNPICTURE CREATEPICTURE CREATESCIENTIFICPICTURE ')
  self.stMeth.append(' CREATESTRINGPICTURE CREATETIMEHOURSPICTURE CREATETIMEPICTURE CREATEUNIXTIMESTAMPPICTURE ')
  self.stMeth.append(' CROP CSVDECODE CSVENCODE DATEFROMWEEK DECENTITYTOCHAR DECODEHEXINLINE DECTOBASE ')
  self.stMeth.append(' DEFORMATDATE DEFORMATDATEDATE DEFORMATDATETEXT DEFORMATDATEWORKER DEFORMATHEX ')
  self.stMeth.append(' DEFORMATNUMBER DEFORMATPATTERN DEFORMATSCIENTIFIC DEFORMATTIME DEFORMATTIMEHOURS ')
  self.stMeth.append(' DEFORMATUNIXTIMESTAMP DEFORMATVALUE DELETELINE DESTRUCT ENCLOSE ENCODEDWORDDECODE ')
  self.stMeth.append(' ENCODEDWORDENCODE ENDSWITH EQUALS ERRORTRAP EXTENSIONONLY FILENAMEONLY FILESIZE FILTER ')
  self.stMeth.append(' FINDBETWEEN FINDBETWEENPOSITION FINDBYTE FINDCHAR FINDCHARS FINDCHARSADDR ')
  self.stMeth.append(' FINDENDOFSTRING FINDLAST FINDMATCH FINDMATCHPOSITION FINDNTH FINDWORD ')
  self.stMeth.append(' FLEXPOLYLINEDECODE FLUSH FLUSHANDKEEP FORMATDATE FORMATDATEWORKER FORMATHEX FORMATHTML ')
  self.stMeth.append(' FORMATMESSAGE FORMATNUMBER FORMATPATTERN FORMATTIME FORMATTIMEHOURS FORMATUNIXTIMESTAMP ')
  self.stMeth.append(' FORMATVALUE FREE FREELINES FROMBLOB FROMBYTES FROMHEX GETADDRESS GETBUFFERLENGTH ')
  self.stMeth.append(' GETBYTES GETCODEPAGEFROMCHARSET GETELAPSEDTIMEUTC GETLINE GETLINES GETVAL GETVALUE ')
  self.stMeth.append(' GETVALUEPTR GETWORD GUIDDECODE GUIDENCODE GUNZIP GZIP HEXTOBYTE HEXTOSTRING ')
  self.stMeth.append(' HTMLENTITYTODEC INLINE INSERT INSERTEVERY INSTRING INTERPRETDATEPICTURE ')
  self.stMeth.append(' INTERPRETHEXPICTURE INTERPRETKEYINPICTURE INTERPRETNUMERICPICTURE ')
  self.stMeth.append(' INTERPRETPATTERNPICTURE INTERPRETPICTURE INTERPRETSCIENTIFICPICTURE ')
  self.stMeth.append(' INTERPRETSTRINGPICTURE INTERPRETTIMEHOURSPICTURE INTERPRETTIMEPICTURE ')
  self.stMeth.append(' INTERPRETUNIXTIMESTAMPPICTURE ISALL ISALLDIGITS ISALLLOWER ISALLUPPER ISASCII ISDIGIT ')
  self.stMeth.append(' ISEMPTY ISLOWER ISTIME ISUPPER ISVALIDUTF8 JOIN JSONDECODE JSONENCODE KEEPCHARRANGES ')
  self.stMeth.append(' KEEPCHARS LEFT LEN LENGTH LENGTHA LINEENDINGS LITTLEENDIAN LOADFILE LOADLIBS ')
  self.stMeth.append(' LOADNORMALIZE LONGDIVISION LONGTOHEX LOWER MAKEGUID MAKEGUID4 MAKEGUID7 MATCH ')
  self.stMeth.append(' MATCHBRACKETS MD5 MERGEXML NORMALIZE NOSTREAM PARSEDATEPICTURE PARSEHEXPICTURE ')
  self.stMeth.append(' PARSEKEYINPICTURE PARSENUMERICPICTURE PARSEPATTERNPICTURE PARSEPICTURE ')
  self.stMeth.append(' PARSESCIENTIFICPICTURE PARSESTRINGPICTURE PARSETIMEHOURSPICTURE PARSETIMEPICTURE ')
  self.stMeth.append(' PARSEUNIXTIMESTAMPPICTURE PATHONLY PEEKRAM PREPEND QUOTE QUOTEDPRINTABLEDECODE ')
  self.stMeth.append(' QUOTEDPRINTABLEENCODE RANDOM RECORDS RELEASESPARECAPACITY REMOVE REMOVEATTRIBUTES ')
  self.stMeth.append(' REMOVEBYTE REMOVEBYTERANGE REMOVECHARRANGES REMOVECHARS REMOVEFROMPOSITION REMOVEHTML ')
  self.stMeth.append(' REMOVELEADING REMOVELINES REMOVEXMLPREFIXES REPLACE REPLACEBETWEEN REPLACEBYTE ')
  self.stMeth.append(' REPLACEEXCEPTBETWEEN REPLACELAST REPLACENTH REPLACESINGLECHARS REPLACESLICE ')
  self.stMeth.append(' RESERVECAPACITY REVERSE REVERSEBYTEORDER RIGHT SAVEFILE SAVEFILEA SEEDRANDOM ')
  self.stMeth.append(' SERIALIZEGROUP SERIALIZEQUEUE SETAFTER SETAFTERLAST SETAFTERNTH SETALL SETBEFORE ')
  self.stMeth.append(' SETBEFORELAST SETBEFORENTH SETBETWEEN SETBYTES SETDEFORMATVALUE SETENCODINGFROMBOM ')
  self.stMeth.append(' SETFORMATVALUE SETLEFT SETLENGTH SETLINE SETLINEFROMVALUE SETRANDOM SETRIGHT SETSLICE ')
  self.stMeth.append(' SETVALUE SETVALUEBYADDRESS SETVALUEBYCSTRINGADDRESS SETVALUEFROMLINE SLICE SORT ')
  self.stMeth.append(' SPARECAPACITY SPLIT SPLITBETWEEN SPLITBYMATCH SPLITEVERY SPLITINTOWORDS SQUEEZE START ')
  self.stMeth.append(' STARTSWITH STR STRCPY STREAM STRINGTOHEX SUB SWAP SWITCHENDIAN TAIL TOANSI TOBLOB ')
  self.stMeth.append(' TOBYTES TOCSTRING TOHEX TOP TOUNICODE TRACE TRACEHEX TRANSLATE TRIM UNIXTOCLARIONDATE ')
  self.stMeth.append(' UNIXTOCLARIONTIME UNQUOTE UPPER URLDECODE URLENCODE URLFILEONLY URLHOSTONLY ')
  self.stMeth.append(' URLPARAMETER URLPARAMETERSONLY URLPATHONLY URLPORTONLY URLPROTOCOLONLY UTCDATE UTCNOW ')
  self.stMeth.append(' UTCTIME UTF16TO8 UTF16TOANSI UTF16TOUTF8CHAR UTF8TO16 UTF8TOANSI WEEK WORDEND WORDSTART ')
  self.stMeth.append(' WRAPTEXT XMLDECODE XMLENCODE ZEROXDECODE ZEROXENCODE _BLOCK _BLOCKBOUND _COLORFROMCSL ')
  self.stMeth.append(' _COLORFROMHEX _COLORTOHEX _EQUALSUNICODE _GETNEXTBUFFERSIZE _IANANAMETONUMBER _MALLOC ')
  self.stMeth.append(' _MEMCHRS _MEMICHR _MEMICHRS _PROCESSCHARRANGES _REMOVEMATCHINGCHARS ')
  self.stMeth.append(' _REPLACEMATCHINGCHARS _SETVALUEPOINTER _STEALVALUE _SWITCHENDIAN ')
  self.acRoutQ   &= new RoutSpanQType                                            !
  self.tsProven  &= new TsProvenQType                                            !
  self.acDotQ    &= new DotRootQType                                             !
  self.sums      &= new SumQType                                                  ! procedure summaries
  self.acScopeId  = 0

! ------------------------------------------------------------------------------------
VitEngine.Destruct Procedure()
  code
  if not self.pp        &= NULL then dispose(self.pp).                            ! include expansion (only ever non-NULL after SetupIncludes)
  if not self.exptk     &= NULL then dispose(self.exptk).
  if not self.ppLineMap &= NULL then dispose(self.ppLineMap).
  if not self.ppSrc     &= NULL then dispose(self.ppSrc).
  if not self.stMeth    &= NULL then dispose(self.stMeth).
  if not self.dgPure    &= NULL then dispose(self.dgPure).
  if not self.acRoutQ &= NULL then free(self.acRoutQ) ; dispose(self.acRoutQ).   !
  if not self.acDotQ &= NULL then free(self.acDotQ) ; dispose(self.acDotQ).      !
  if not self.sums &= NULL then free(self.sums) ; dispose(self.sums).            !
  if not self.tsProven &= NULL then free(self.tsProven) ; dispose(self.tsProven). !
  dispose(self.tmr)
  dispose(self.rw)
  dispose(self.syms)
  dispose(self.tk)

! ------------------------------------------------------------------------------------
VitEngine.Init Procedure(VitRules pRl)
  code
  self.progressFn = 'VitTransform' & clip(self.stamp) & '.progress.txt'           ! stamped heartbeat (driver sets stamp before Init) - the Construct-time build always got a blank stamp
  self.rl &= pRl
  self.totalChanges = 0
  self.filesChanged = 0
  self.filesDone    = 0
  self.saveErrors   = 0
  self.loadErrors   = 0

! ------------------------------------------------------------------------------------
! enable cross-file type resolution. The Preprocessor splices every INCLUDE
! (resolved through the .red table) into an expanded source; we tokenize that and
! feed it to VitSymbols.BuildTypeRegistry so self.* receivers resolve against real
! headers (DriverClass.Inc etc.). Opt-in: callers that never invoke this keep the
! original in-file-only behaviour with no preprocessor overhead.
! PERF: the expanded source is the full ABC/StringTheory/NetTalk include tree;
! per-file tokenisation of it is the dominant cost, and that is accepted here. If a large run
! is slow, the optimisation to reach for is header-registry caching keyed off the line map.
VitEngine.SetupIncludes Procedure(STRING pRedPath, STRING pRootDir, STRING pConfig)
  code
  self.redPath = pRedPath
  self.rootDir = pRootDir
  self.config  = choose(pConfig = '', 'Release', pConfig)
  if self.pp &= NULL
    self.pp        &= new Preprocessor
    self.exptk     &= new VitTokenize
    self.ppLineMap &= new LineMapQueue
    self.ppSrc     &= new StringTheory
  end
  self.useIncludes = 1
  return 1

! ------------------------------------------------------------------------------------
VitEngine.TransformFile Procedure(STRING pFn, StringTheory pLog)
src          StringTheory
fileChanges  long,AUTO
passChanges  long,auto
pass         long,auto
dbg          StringTheory ! scratch for _List (which free()s its target)
txaFn        StringTheory ! scratch for the extension test below
unSt         StringTheory ! builds the "declaration not visible" name list,
unMsg        StringTheory !   and the line it goes on
  code
  self.tmr.Start()
  if not src.LoadFile(pFn)
    ! A source that was ASKED FOR and not transformed is a failed run, so it is counted and the
    ! caller's ERRORLEVEL says so: the commonest cause is an unquoted path with a space,
    ! where COMMAND() hands us the first fragment as the whole name - and reporting success for
    ! that is how a watched sweep transforms nothing and nobody notices. A name with no '.' in
    ! its last element is exactly that shape, so it gets told.
    self.loadErrors += 1
    pLog.append('ERROR could not load ' & clip(pFn) & ' : ' & src.LastError & '<13,10>')
    if ~instring('.', clip(pFn), 1, 1)
      pLog.append('      (no extension - if the path contains a SPACE, quote it: "My Source\a.clw")<13,10>')
    end
    return 0
  end
  if ~src._DataEnd
    pLog.append(clip(pFn) & ': empty file, skipped<13,10>')
    return 0
  end
  self.filesDone += 1
  ! self.crlfStyle and the two `if ~self.crlfStyle then replace('<13,10>','<10>')`
  ! branches are GONE. They existed to hand an LF-only source back as LF-only,
  ! but LF-only is not valid Clarion - it is always CRLF - so the branch could only ever fire
  ! on input the compiler would reject anyway. JoinToks emits CRLF and that is now simply what
  ! is written. If an LF-only file ever does arrive, it comes back normalised to CRLF, which is
  ! the more useful answer than faithfully preserving something invalid.
  ! ---- .txa: wrap it so the tokenizer sees Clarion. TxaPreProcess says what and why.
  !      The extension is the whole test - a template export is not source, and telling it
  !      apart by content would cost a scan to learn what the filename already says.
  self.isTxa   = choose(upper(txaFn.ExtensionOnly(clip(pFn))) = 'TXA')
  self.txaSaid = 0
  if self.isTxa
    self.TxaPreProcess(src)
    pLog.append(clip(pFn) & ': TXA - pre-processed for parsing. UnusedVars, UnusedAssignments and'     & |
                ' AutoCheck are RESTRICTED on a template export to procedures and routines contained'  & |
                ' WHOLLY inside one embed: the code the template generates is not in the file, so for' & |
                ' anything spanning embed points neither "never used" nor "always set before read"'    & |
                ' can be decided from what is here. UnusedRoutines annotates rather than commenting'   & |
                ' out, and UnreachableCode never walks past an embed boundary, for the same reason.<13,10>')
  end
  self.WidthPolicy(src)                                 ! width limit; it was made a method so the preview shares it
  self.curFile   = pFn
  self.sawAlign  = 0
  free(self.tsProven)                                   ! proofs are per FILE, never carried between files

  pLog.append('=== ' & clip(pFn) & ' ===<13,10>')
  self.Progress('parsing')
  self.tk.ParseText(src)
  self.rulesDirty = 0                                   ! fresh parse - the previous FILE's pending hazard is not this file's debt
  ! expand includes ONCE per file, tokenise the .red-expanded superset, and point the symbol
  ! table at it. VitSymbols.Build then sources the type registry from this stream on EVERY (re)build -
  ! including the resymbol that follows each rewrite - so cross-file header types survive the whole pass.
  ! (The earlier once-only append was wiped by the first post-rewrite resymbol: only one typed rule fired.)
  if self.useIncludes and not self.pp &= NULL
    self.Progress('expanding includes')
    self.pp.Init(pFn, clip(self.redPath), clip(self.rootDir), clip(self.config))
    self.ppSrc.free()
    if self.pp.Process(src, self.ppSrc, self.ppLineMap) ! PROC: non-zero = preprocessor errors (still expands what it can)
      pLog.append(clip(pFn) & ': preprocessor warnings:<13,10>' & self.pp.GetErrors() & '<13,10>')
    end
    self.Progress('tokenising expanded (' & self.ppSrc.Length() & ' bytes)')
    self.exptk.ParseText(self.ppSrc)
    self.syms.expTk    &= self.exptk                    ! persistent: Build reads it on resymbol
    self.syms.hdrBuilt  = 0                             ! new file's expansion -> rebuild the registry once
    pLog.append(clip(pFn) & ': +includes -> ' & self.ppSrc.Length() & ' expanded byte(s), ' & |
                self.exptk.records() & ' token(s)<13,10>')
    do ExpLevelFingerprint                              ! '+'/'-' census of the expanded stream (context-drift detector)
    if self.verbose                                     ! full EXPANDED-stream dump (level+type+text per token) -
      dbg.free()                                        !   diffing two contexts' dumps names the exact tokens whose
      self.exptk._List(dbg, 1)                          !   stamps drift (NB _List free()s its target first)
      pLog.append('--- exptk tokens ---<13,10>' & dbg.getValue() & '<13,10>')
    end
  else
    self.syms.expTk    &= NULL                          ! B0 path: in-file registry only
    self.syms.hdrBuilt  = 0
  end
  self.Progress('building symbols (' & self.tk.records() & ' tokens)')
  self.syms.traceReg = self.verbose                     ! registry decision trace under --verbose
  self.syms.Build(self.tk)                              ! scopes/symbols from raw self.tk; registry from expTk when set
  if self.syms.regEofDepth or self.syms.regEofStack     ! ALWAYS-ON health line - the registry desync signature
    pLog.append('WARNING type-registry scan ended unbalanced: depth ' & self.syms.regEofDepth & ', owner stack ' |
       & self.syms.regEofStack & ' (registry may be polluted - run --verbose for the trace)<13,10>')
  end
  if self.verbose and self.syms.traceReg and self.syms.regTrace._DataEnd
    pLog.append(self.syms.regTrace)
  end
  ! The version line, and nothing else - the one thing a report needs to say about itself
  ! is which VitTransform wrote it. Keep it to that: a report is read by a user deciding
  ! whether to accept a diff, and anything else here is noise to them.
  !
  ! THE BUILD NUMBER EARNS ITS PLACE, though, small and in brackets. A FAILED Clarion build
  ! leaves the PREVIOUS exe on disk and the gate then runs it and passes - the report is the
  ! only thing that says which engine actually produced these numbers. Bump vr:buildNo every
  ! gated round; `grep -o "VitTransform [0-9.]* (build [0-9]*)"` over the newest report is how
  ! you tell. It went missing for four rounds when this line was tidied down to the version.
  pLog.append('VitTransform ' & vr:version & ' (build ' & vr:buildNo & ')<13,10>')
  pLog.append(clip(pFn) & ': symtab ' & records(self.syms.scopes) & ' scope(s), '                         & |
              records(self.syms.syms) & ' symbol(s), ' & records(self.syms.types) & ' type(s), '          & |
              records(self.syms.fields) & ' field(s), ' & records(self.syms.methods) & ' method(s) over ' & |
              self.tk.records() & ' token(s)<13,10>') ! diagnostic: a declaration-dense file reporting few scopes/symbols has a VitSymbols.Build desync (typed rules silently no-op); type/field counts are the Design-B registry (0 types on a class-defining file = registry miss; 0 methods on a class-including --root run = prototype scan miss)
  if self.verbose
    self.tk._List(dbg, 1)                             ! RAW TOKENS (text + type) - to see whether member chains like self.Direct are recombined into one token
    pLog.append('--- tokens ---<13,10>' & dbg.getValue() & '<13,10>')
    self.syms._List(dbg)                              ! scopes + symbols (SELF / locals) - _List free()s dbg, so dump to a scratch then append
    pLog.append(dbg)
    self.syms._ListTypes(pLog)                        ! Design B: full type registry
  end
  self.rw.Init(self.rl, self.tk)
  self.rw.SetSymbols(self.syms)
  self.rw.m.loose   = self.loose
  self.rw.m.verbose = self.verbose
  if self.verbose
    self.rw.m.vlog &= pLog
  else
    self.rw.m.vlog &= NULL
  end

  fileChanges = 0
  loop pass = 1 to self.maxPasses
    self.curPass = pass
    passChanges = self.RunPass(pLog)
    fileChanges += passChanges
    if ~passChanges then break.
    if pass = self.maxPasses
      pLog.append('WARNING ' & clip(pFn) & ' did not converge after ' & self.maxPasses & ' passes<13,10>')
    end
  end

  ! ---- the DEFERRED pass. A FINAL group's rules were inert for every pass
  !      above; now they get exactly one, on the converged text. This is for a transform whose
  !      OUTPUT the analyses cannot read - the choose return form holds valuePtr, which
  !      SpaceKeepUse refuses by design, and is neither of the two spellings SmProveSpaceless
  !      accepts. Run during convergence it destroyed the summary parser.MaskSigBase depends
  !      on, and the result silently went backwards. Deferring is better than teaching each
  !      recogniser the new shape: nothing runs afterwards, so nothing has to understand it.
  !      ONE pass, not a fixpoint - deferred rules do not cascade into each other. If that is
  !      ever wanted it should be an explicit second fixpoint, not an accident.
  !      BEFORE AlignComments, so comment columns settle on the genuinely final text.
  ! DO NOT gate this on `if fileChanges and ~self.dryRun`, the shape used by the
  ! AlignComments gate eight lines below. That is correct there, because that pass is
  ! COSMETIC; it is wrong for a SEMANTIC one. It would leave a file whose only applicable
  ! transform is a FINAL rule untouched entirely, and make --dry-run under-report.
  ! Both matter on a plain no-switch run: DEFAULTSTYLE selects st-getvalue-slice, which is
  ! declared FINAL. The pass is a no-op when no FINAL group is selected, so it is safe to
  ! run unconditionally; dry-run still writes nothing, it just counts honestly.
  self.rl.deferPhase = 1
  self.Progress('deferred (FINAL) rules')
  passChanges = self.RunPass(pLog)
  self.rl.deferPhase = 0
  fileChanges += passChanges

  ! ---- THE COSMETIC STAGES MUST NOT NEED A RULE CHANGE FIRST.
  !      Gate them on `fileChanges` and, on a file the rules have nothing to say about -
  !      already-transformed source, or a run whose whole point is layout - the splitter,
  !      both aligners and the trailing-whitespace clip can never run at all: the tool
  !      reports `0 change(s)` and writes nothing. Seen on a 13,415-line file, every rule
  !      evaluated in 4 seconds and nothing done.
  !      A file whose only defect is trailing whitespace IS rewritten - deliberate, and the
  !      intent of a layout-only run.
  !      Each stage returns what it did and that counts as a change, so the report is honest and
  !      WriteOutput below still only fires when something actually happened. They run under
  !      --dry-run too, so a dry run's count matches what a real run would do.
  if self.splitWidth > 0
    self.Progress('split wide lines')
    if self.tk.SplitWideLines(self.splitWidth)                         ! flattened-wide lines, broken at a sensible point
      self.tk.SetLineNumbers()                                         !   new line breaks -> restamp before anything reads lineNo
      fileChanges += 1
    end
  end
  if self.sawAlign
    self.Progress('align comments')
    if self.acDiag                                                     ! --acdiag needs the tokenizer's own
      self.tk.acDiag = 1                                               !   log file switched on, because TraceIt is
      self.tk.logIt  = 1                                               !   the only channel AlignComments has.
    end
    if self.tk.AlignCaseLabels(self.splitWidth) then fileChanges += 1. ! CASE label columns. Both of these change
    if self.tk.AlignDeclTypes(self.splitWidth) then fileChanges += 1.  !   where code SITS, so they run BEFORE comment
                                                                       !   columns are measured. declaration types.
    if self.tk.AlignComments(self.splitWidth) then fileChanges += 1.   ! '!' and '|' settle in one shared column
  end
  if self.tk.ClipLines() then fileChanges += 1.                        ! trailing spaces/tabs. LAST, so nothing re-introduces any.
  if fileChanges
    self.filesChanged += 1
    self.totalChanges += fileChanges
    if ~self.dryRun
      self.WriteOutput(pFn, pLog)
    end
  end
  self.Progress('done (' & fileChanges & ' changes)')
  self.tmr.Stop()
  if self.rw.m.rtFallbacks                                             ! header-derived table bypassed - measure how often the
    pLog.append(clip(pFn) & ': rettype fallback x ' & self.rw.m.rtFallbacks & |                        !   old six-name list still carries bindings (retirement data)
                ' (receiver class not in the type registry - header truth unavailable)<13,10>')
    self.rw.m.rtFallbacks = 0
  end
  ! What the registry's remaining scope blindness costs, as a number rather than an
  ! argument. Two procedures that each declare a local QUEUE of the same name contribute their
  ! fields to ONE (owner,name) run, and a run that disagrees has no answer from the run alone.
  ! ResolveMember asks a second question there - which of those rows is declared where the USE
  ! SITE can see it - and answers when exactly one type survives it. The two counters are each
  ! other's CONTROL: `runScoped` is the narrowing arriving, `runClash` is what it still could
  ! not settle, and a zero in either one means nothing without the other beside it.
  if not self.syms &= NULL
    if self.syms.runScoped
      pLog.append(clip(pFn) & ': registry narrowed by scope x ' & self.syms.runScoped  & |
                  ' (a disagreeing field run settled by the use site''s own scope)<13,10>')
      self.syms.runScoped = 0
    end
    if self.syms.runClash
      pLog.append(clip(pFn) & ': scope-blind registry refused x ' & self.syms.runClash & |
                  ' (same-named local types share one field run and the use site cannot tell them apart)<13,10>')
      self.syms.runClash = 0
    end
  end
  do UnresolvedNote ! say when typed rules refused because a
                    !   DECLARATION was not visible - see the routine
  pLog.append(clip(pFn) & ': ' & fileChanges & ' change(s), ' & (self.curPass) & ' pass(es), '   & |
              self.rw.skipCount & ' comment-skip(s), ' & self.rw.widthSkips & ' width-skip(s), ' & |
              clip(self.tmr.Duration())                                                          & |
              choose(self.dryRun and fileChanges, '  [dry-run: not written]', '') & '<13,10>')
  return fileChanges

! ---- SAY WHEN A TYPED RULE REFUSED BECAUSE A DECLARATION WAS NOT VISIBLE.
!      Until this line existed the run simply did less and said nothing, which is the
!      failure mode this project keeps paying for: a silent refusal reads exactly like
!      "the rule did not apply here". It surfaced on an instring() that would not
!      convert, because self.PPDefines is declared in Preprocessor.inc and nothing had
!      read that file.
!      ONLY UNRESOLVED THINGS ARE COUNTED, never wrongly-typed ones - a rule that wanted
!      a StringTheory and found a LONG behaved correctly and must stay quiet, or this
!      line drowns in noise on every file. The distinction is made in
!      VitMatch.NoteChainUnres, where the two cases are visible.
!      The names are the DISTINCT receivers, capped at six with a count of the rest; the
!      total is every refusal, not every name.
!      THE PHRASE "declaration not visible" IS GREPPED BY run-regression.bat. Reword it
!      there in the same round or the suite reports the diagnostic missing - which it did,
!      loudly and correctly, when this message said "whose declaration is not visible".
UnresolvedNote routine
  data
unN    long
unR    long,auto
unTot  long
unThor byte
  code
  unSt.free()
  if ~self.rw.m.chainUnres then exit.
  if not self.pp &= NULL then unThor = 1. ! pp is non-NULL only once SetupIncludes has run
  if not self.rw.m.chainMissQ &= NULL
    loop unR = 1 to records(self.rw.m.chainMissQ)
      get(self.rw.m.chainMissQ, unR)
      if errorcode() then break.
      if unN >= 6 then break.
      if unN then unSt.append(', ').
      unSt.append(clip(self.rw.m.chainMissQ.recvU))
      unN += 1
    end
    unTot = records(self.rw.m.chainMissQ)
    if unTot > unN
      unSt.append(' and ')
      unSt.append(unTot - unN)
      if unTot >= 40          ! 40 = the name cap in NoteChainUnres, so at the
        unSt.append('+ more') !   cap the real total is higher than we can say
      else
        unSt.append(' more')
      end
    end
  end
  ! ONE STEP PER LINE, deliberately. The first cut built this message as a single
  ! multi-line continued expression and it would not compile - the error landed on a '('
  ! INSIDE a string literal, which is the compiler telling you its quote tracking is
  ! already lost somewhere earlier in the continuation. Do not make this clever again.
  unMsg.free()
  unMsg.append(clip(pFn))
  unMsg.append(': ')
  unMsg.append(self.rw.m.chainUnres)
  unMsg.append(' typed match(es) refused on ')
  unMsg.append(unTot)
  if unTot >= 40 then unMsg.append('+').
  unMsg.append(' receiver(s) - declaration not visible: ')
  unMsg.append(unSt)
  if unThor
    unMsg.append(' (--thorough is ON, so these are not reachable from the .RED either)')
  else
    unMsg.append(' - if any of these are declared in an INCLUDE, try --thorough')
  end
  unMsg.append('<13,10>')
  pLog.append(unMsg)
  self.rw.m.chainUnres = 0
  if not self.rw.m.chainMissQ &= NULL then free(self.rw.m.chainMissQ).

ExpLevelFingerprint routine
  data
fx    long,auto
nPlus long
nMin  long
  code
  ! census of '+'/'-' level marks in the EXPANDED stream. Identical text must give an
  ! identical census - a drift between invocation contexts (virgin vs reused exptk) localises
  ! the registry nondeterminism to the tokenizer; an identical census localises it to the
  ! BuildTypeRegistry scan. Cheap (one pass over the queue), logged only when includes are on.
  loop fx = 1 to records(self.exptk.tokens)
    get(self.exptk.tokens, fx)
    if errorcode() then break.
    case self.exptk.tokens.level
    of '+'
      nPlus += 1
    of '-'
      nMin += 1
    end
  end
  pLog.append(clip(pFn) & ': exptk level census +' & nPlus & ' -' & nMin & choose(nPlus <> nMin, '  [UNBALANCED]', '') & '<13,10>')

! ------------------------------------------------------------------------------------
! S4 live preview (design v01 5b / v02 5d): transform an in-MEMORY text buffer through
! the SAME pipeline as TransformFile - parse -> (optional include expansion) -> symbols
! -> fixpoint over the SELECTED rules -> JoinToks. NEVER writes a file (implicit dry-run).
! pOut receives the transformed text; pLog the per-rule change log (rule N line L: ...)
! the caller mines for changed-line highlighting. Selection is whatever the shared
! resolver last set on self.rl.groups - the preview is the real pipeline with a different
! output pane and cannot diverge from a batch run under the same selection.
! ------------------------------------------------------------------------------------
! ---- the width limit, as a METHOD so both entry points get the same answer.
!      It must NOT be a ROUTINE inside TransformFile with TransformText hard-coding a fixed
!      preview width. That is harmless only while the width merely decides whether to REFUSE
!      a conversion. SplitWideLines uses it too, and then it stops being harmless: the preview
!      splits at the hard-coded width while a batch run splits at the file's own, so a
!      90-char-line file (limit 102) shows unsplit lines in VitStyle and split ones on disk -
!      exactly the preview/batch divergence this design exists to prevent.
VitEngine.WidthPolicy Procedure(StringTheory pSrc)
fx   long,auto
run  long
mxw  long
  code
  ! allowed width = the codebase's own prevailing width plus a few chars,
  ! capped at 200; a file already wider than 200 is respected as-is and never extended.
  ! mxw = longest physical line of the ORIGINAL source (CRs ignored).
  ! --width=N overrides the scan entirely. --width=0 arrives here as -1 and means
  ! NEVER SPLIT - SplitWideLines and the width check are both gated on maxWidth > 0, so a
  ! zero switches the whole width policy off rather than setting an impossible limit.
  ! TWO different questions, and one number cannot answer both.
  !   rw.maxWidth  - the question: "would FLATTENING push this file past its own prevailing
  !                  width?" Derived from the file, and a file already wider than 200 is
  !                  respected as-is, because that check was guarding against EXTENDING lines.
  !   splitWidth   - the splitter's question: "is this line too wide to READ?" That is absolute.
  ! Do NOT share rw.maxWidth with the splitter. It fails on exactly the files that need it most:
  ! a source with one 465-char line gets a limit of 465, so nothing is ever over-wide and
  ! nothing is split.
  self.splitWidth = 200
  if self.widthArg < 0
    self.rw.maxWidth = 0
    self.splitWidth  = 0 ! --width=0 = never split
    return
  end
  if self.widthArg > 0
    self.rw.maxWidth = self.widthArg
    self.splitWidth  = self.widthArg
    return
  end
  loop fx = 1 to pSrc._DataEnd
    case val(pSrc.valuePtr[fx])
    of 10
      if run > mxw then mxw = run.
      run = 0
    of 13
      ! ignore
    else
      run += 1
    end
  end
  if run > mxw then mxw = run.
  if mxw >= 200
    self.rw.maxWidth = mxw
  else
    self.rw.maxWidth = choose(mxw + 12 > 200, 200, mxw + 12)
  end

! ------------------------------------------------------------------------------------
! THE FIXPOINT. Source text in, transformed text out, plus the change log.
!
! It runs passes until a pass changes nothing, capped by maxPasses with a did-not-converge
! warning. Running to a fixpoint rather than once is what lets one rule expose work for
! another, which is also why every rule has to be able to see its own output without
! re-firing on it - a rule that rewrites its own result never converges.
!
! The cosmetic passes are deliberately OUTSIDE this loop, run once after it settles: they
! report zero changes so they cannot drive another pass, and alignment that fed back into the
! fixpoint could not stabilise.
!
! This is the entry point VitStyle's live preview calls, so it must work on a buffer with no
! file behind it. Anything that needs a filename belongs in TransformFile, not here.
! ------------------------------------------------------------------------------------
VitEngine.TransformText Procedure(StringTheory pSrc, StringTheory pOut, StringTheory pLog)
src          StringTheory
fileChanges  long,auto
passChanges  long,auto
pass         long,auto
  code
  pOut.free()
  if ~pSrc._DataEnd                                                                                    ! passed StringTheory is by-reference (never NULL); just test empty
    pLog.append('(empty source)<13,10>')
    return 0
  end
  src.setValue(pSrc)
  self.WidthPolicy(src)                                                                                ! the SAME limit a batch run would use - was hard-coded 200
  self.curFile   = '(preview)'
  self.isTxa     = 0                                                                                   ! .txa-ness is a property of a FILENAME, and a preview buffer has none.
  self.txaSaid   = 0                                                                                   ! TransformFile sets both per file, so without this reset an embedder that
  self.sawAlign  = 0                                                                                   ! calls both entry points carries the last FILE's answer into every preview.
  free(self.tsProven)                                                                                  !
  self.tk.ParseText(src)
  self.rulesDirty = 0                                                                                  ! fresh parse - a previous run's pending hazard is not this preview's debt
  self.rw.m.chainUnres = 0                                                                             ! same reasoning as the three resets above - the
  if not self.rw.m.chainMissQ &= NULL then free(self.rw.m.chainMissQ).                                 !   preview has no report to print this on, so clear it or it
                                                                                                       !   accumulates across previews and lands on the next FILE's line
  self.tk.MapInit()                                                                                    ! arm the line map (identity now; MapFold composes it at every renumber)
  if self.useIncludes and not self.pp &= NULL                                                          ! same header fidelity as a real --root run when configured
    self.pp.Init('(preview)', clip(self.redPath), clip(self.rootDir), clip(self.config))
    self.ppSrc.free()
    self.pp.Process(src, self.ppSrc, self.ppLineMap)
    self.exptk.ParseText(self.ppSrc)
    self.syms.expTk    &= self.exptk
    self.syms.hdrBuilt  = 0
  else
    self.syms.expTk    &= NULL
    self.syms.hdrBuilt  = 0
  end
  self.syms.traceReg = 0
  self.syms.Build(self.tk)
  self.rw.Init(self.rl, self.tk)
  self.rw.SetSymbols(self.syms)
  self.rw.m.loose   = self.loose
  self.rw.m.verbose = 0
  self.rw.m.vlog   &= NULL
  fileChanges = 0
  loop pass = 1 to self.maxPasses
    self.curPass = pass
    passChanges = self.RunPass(pLog)
    fileChanges += passChanges
    if ~passChanges then break.
    if pass = self.maxPasses
      pLog.append('WARNING preview did not converge after ' & self.maxPasses & ' passes<13,10>')
    end
  end
  ! ---- the stages below are the SAME stages TransformFile runs after its
  !      fixpoint, in the same order, and the two lists have to be kept in step by hand - there
  !      is no shared routine. If a stage is ever added to TransformFile after its fixpoint, add
  !      it here too, or the preview silently stops matching a batch run again.
  !      The preview's whole promise is that what VitStyle shows is what a batch run produces.
  !      This procedure must NOT stop at the fixpoint and skip the three stages that
  !      follow it in TransformFile, or the preview UNDER-REPORTS on an ordinary run:
  !        - the deferred FINAL pass. DEFAULTSTYLE selects st-getvalue-slice, which is declared
  !          FINAL, so this is not an edge case - it is every no-switch preview of any file
  !          containing `return st.getValue()`.
  !        - AlignComments and ClipLines, so the preview would show comment columns and
  !          trailing whitespace the written file will not have.
  !      The gating is the SAME in both: sawAlign, and nothing else. A preview has to show what
  !      a batch run would produce, so it cannot gate these differently.
  self.rl.deferPhase = 1
  passChanges = self.RunPass(pLog)
  self.rl.deferPhase = 0
  fileChanges += passChanges
  ! ---- mirrors TransformFile exactly - see the note there. The preview has to show
  !      what a batch run would produce, so it cannot gate these differently.
  if self.splitWidth > 0
    if self.tk.SplitWideLines(self.splitWidth)
      self.tk.SetLineNumbers()
      fileChanges += 1
    end
  end
  if self.sawAlign
    if self.tk.AlignCaseLabels(self.splitWidth) then fileChanges += 1.
    if self.tk.AlignDeclTypes(self.splitWidth) then fileChanges += 1.
    if self.tk.AlignComments(self.splitWidth) then fileChanges += 1.
  end
  if self.tk.ClipLines() then fileChanges += 1.
  if self.tk.mapOn       ! final compose - a builtin may have edited without a
    self.tk.MapFold()    ! renumber since; after this, lineMap = OUTPUT line -> source line
    self.tk.mapOn = 0    ! disarm: the map data stays for the caller, batch runs never fold
  end
  self.tk.JoinToks(pOut) ! transformed text, format-preserving
  pOut.clip('<32,9>')    ! matches WriteOutput - the last line has no EOL token to carry its tail
  return fileChanges

! ------------------------------------------------------------------------------------
VitEngine.RunPass Procedure(StringTheory pLog)
r           long,auto
sv          long,auto
passChanges long
  code
  loop r = 1 to records(self.rl.rules)
    get(self.rl.rules, r)
    if errorcode() then break.
    if ~self.rl.GroupActive(self.rl.rules.groupId) then cycle.                          ! unselected GROUP - rule/builtin inert this run
    if self.onlyId and self.rl.rules.ruleId <> self.onlyId then cycle.                  ! these two MUST precede the builtin
    if self.skipId and self.rl.rules.ruleId = self.skipId then cycle.                   !   branch below, which cycles on its own. They
                                                                                        !   Placed after it, --only=<id> still runs
                                                                                        !   every BUILTIN - CombineAdjacentLiterals,
                                                                                        !   CheckCat, UnusedVars, AutoCheck and the rest -
                                                                                        !   while the README says "run only one rule". This
                                                                                        !   is the switch you reach for to attribute a bad
                                                                                        !   diff, so it must not misattribute.
                                                                                        !   NOTE: a BUILTIN's ruleId is its SOURCE LINE
                                                                                        !   NUMBER (VitRules:506), so it shares a number
                                                                                        !   space with declared rule ids - --only=533 also
                                                                                        !   keeps a builtin that happens to sit on line 533.
    if self.rl.rules.kind = vr:kindBuiltin
      if self.rulesDirty                                                                ! (the PROPLABEL/RHSISNUM audit): a rule rewrite re-emits tokens WITHOUT
        self.RejoinReparse()                                                            ! level marks, and only a REPARSE restores them - AutoCheck's frame walk convicted
      end ! safe vars on the stale stream. Builtins are entitled to a parse-fresh stream.
          ! rulesDirty is set only by LEVEL-HAZARD replacements (RepHasLevelKeyword); level-neutral families (clip drops, renames) skip the reparse. Builtins that restructure set wantReparse themselves - that path is unchanged.
          ! It is a MEMBER (cleared inside RejoinReparse): as a RunPass local, a hazard rule firing AFTER the last builtin died with the pass and the next pass's builtins - and the deferred FINAL pass - ran on the damaged stream.
      self.Progress('pass ' & self.curPass & ' builtin ' & clip(self.rl.rules.builtinName))
      sv = self.DoBuiltin(r, pLog)
      passChanges += sv
      if self.wantReparse
        self.RejoinReparse()
        self.wantReparse = 0
      elsif sv
        self.rw.m.freqDirty = true                                                      ! builtin edited tokens - anchor counts stale
        self.syms.dirty = 1                                                             ! rebuild lazily at the next consumer (mirrors VitRewrite)
      end
      cycle
    end
    if self.rl.rules.skip then cycle.                                                   ! onlyId/skipId moved ABOVE the builtin branch
    self.Progress('pass ' & self.curPass & ' rule ' & self.rl.rules.ruleId & ' (changes so far: ' & passChanges & ')')
    sv = self.rw.changeCount
    self.rw.ApplyRule(r, pLog)
    passChanges += self.rw.changeCount - sv
    if self.rw.changeCount > sv and self.RepHasLevelKeyword() then self.rulesDirty = 1. ! only a replacement carrying a LEVEL-BEARING keyword can damage levels
  end
  return passChanges

! ------------------------------------------------------------------------------------
! does the CURRENT rule's replacement contain a level-bearing keyword? Only such
! a replacement can damage the token LEVEL stream (a re-emitted IF/END/... carries no
! mark until reparse). Called only when the rule FIRED; repQ is a handful of tokens.
! ------------------------------------------------------------------------------------
VitEngine.RepHasLevelKeyword Procedure()
t   long,auto
wU  string(12),auto
  code
  if self.rl.rules.repQ &= NULL then return 1. ! no replacement recorded - stay conservative
  loop t = 1 to records(self.rl.rules.repQ)
    get(self.rl.rules.repQ, t)
    if errorcode() then break.
    if self.rl.rules.repQ.tok &= NULL then cycle.
    wU = upper(self.rl.rules.repQ.tok)
    case wU
    of   'IF'   orof 'LOOP'  orof 'CASE' orof 'EXECUTE' orof 'BEGIN' |
       orof 'ELSE' orof 'ELSIF' orof 'OF'   orof 'OROF'    orof 'END'
      return 1
    end
  end
  ! THE PATTERN SIDE COUNTS TOO (#1, #17). A pattern that CONSUMED a level-bearing
  ! token - an END, an inline '.' terminator, or a structure keyword - removed marks
  ! the stream still needs, and no replacement scan can see that. Scanning only the
  ! replacement let 'y = 1 end ==> y = 2' delete a close with rulesDirty clear; the
  ! dead-code walk then commented LIVE code and the hoist pass moved a statement
  ! across the wrong branch. A '.' row here may be a member dot, which over-reparses
  ! (never under) - metavar rows are skipped, they bind rather than consume.
  if self.rl.rules.patQ &= NULL then return 1. ! no pattern recorded - stay conservative
  loop t = 1 to records(self.rl.rules.patQ)
    get(self.rl.rules.patQ, t)
    if errorcode() then break.
    if self.rl.rules.patQ.mvx then cycle.
    if self.rl.rules.patQ.tok &= NULL then cycle.
    wU = upper(self.rl.rules.patQ.tok)
    if wU = '.' then return 1.
    case wU
    of   'IF'   orof 'LOOP'  orof 'CASE' orof 'EXECUTE' orof 'BEGIN' |
       orof 'ELSE' orof 'ELSIF' orof 'OF'   orof 'OROF'    orof 'END'
      return 1
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! AlignComments is cosmetic - run on the converged state only, i.e. when the
! previous pass made no changes it is too late, so instead it runs every pass
! but reports zero changes and thus never drives the fixpoint.
! CombineAdjacentLiterals / RemoveDoubledBrackets / CheckCaseStatements (incl.
! checkVals) / CheckReplaces / CheckRemoves / CheckSplits / CheckInLine /
! CheckCat are ports of the
! vtxaDiff009 routines. The analyses are UnusedVars,
! UnusedRoutines, UnreachableCode, UnusedAssignments and AutoCheck, and the
! layout builtins are HoistCommonBranchCode, IfChainToCase, KnownRanges,
! TrailingSpaces, KeywordCase, SplitStatements, ExpandOneLiners, BlockEndStyle
! and Reindent. Twenty-one arms in all. THE CASE BELOW IS THE INVENTORY: trust
! it over any list written in a comment, this one included.
! ------------------------------------------------------------------------------------
VitEngine.DoBuiltin Procedure(LONG pRow, StringTheory pLog)
  code
  ! ---- the three whole-file analyses are RESTRICTED on a .txa (the embed rule, strict
  !      form), and SAY SO once. They do NOT refuse wholesale: each one
  !      runs, and the per-scope gate (ScopeFullyEmbedded, applied in AutoEligible for
  !      AutoCheck + UnusedAssignments and in RemoveUnusedPass for UnusedVars) admits
  !      only procedures/routines contained wholly inside one embed - in practice mostly
  !      ROUTINES, since a synthesised procedure header spans template data by
  !      construction. Logged once per file, not once per pass.
  if self.TxaAnalysisRefused(self.rl.rules.builtinName)
    if ~self.txaSaid
      self.txaSaid = 1
      pLog.append('BUILTIN ' & clip(self.rl.rules.builtinName) & ': RESTRICTED on a .txa to'        & |
                  ' procedures/routines wholly inside one embed - the template''s generated code'   & |
                  ' is not in this file, so anything spanning embed points cannot be decided here.' & |
                  ' Run on the generated .clw for full coverage.<13,10>')
    end
  end
  if not self.syms &= NULL then self.syms.EnsureFresh(). ! builtins access syms.syms DIRECTLY (UnusedVars/AutoCheck row loops) - gate at dispatch
  case upper(self.rl.rules.builtinName)
  of 'ALIGNCOMMENTS'
    self.sawAlign = 1                                    ! deferred: runs once after convergence (cosmetic)
    return 0
  of 'COMBINEADJACENTLITERALS'
    return self.BuiltinCombineLiterals(pLog)
  of 'REMOVEDOUBLEDBRACKETS'
    return self.BuiltinDoubledBrackets(pLog)
  of 'CHECKCASESTATEMENTS'
    return self.BuiltinCheckCase(pLog)
  of 'CHECKREPLACES'
    return self.BuiltinCheckReplaces(pLog)
  of 'CHECKREMOVES'
    return self.BuiltinCheckRemoves(pLog)
  of 'CHECKSPLITS'
    return self.BuiltinCheckSplits(pLog)
  of 'CHECKINLINE'
    return self.BuiltinCheckInLine(pLog)
  of 'CHECKCAT'
    return self.BuiltinCheckCat(pLog)
  of 'UNUSEDVARS'
    return self.BuiltinUnusedVars(pLog)
  of 'UNUSEDROUTINES'
    return self.BuiltinUnusedRoutines(pLog)
  of 'UNREACHABLECODE'
    return self.BuiltinUnreachableCode(pLog)
  of 'UNUSEDASSIGNMENTS'
    return self.BuiltinUnusedAssignments(pLog)
  of 'AUTOCHECK'
    return self.BuiltinAutoCheck(pLog)
  of 'HOISTCOMMONBRANCHCODE'
    return self.BuiltinHoistCommonBranchCode(pLog)
  of 'MERGEGUARDCHAIN'
    return self.BuiltinMergeGuardChain(pLog) ! consecutive single-line IFs setting the same thing
  of 'IFCHAINTOCASE'
    return self.BuiltinIfChainToCase(pLog)   ! `if E = a or E = b ... elsif E = c` -> `case E / of a orof b / of c`
  of 'DEADGUARD'
    return self.BuiltinDeadGuard(pLog)
  of 'DEADLEFT'
    return self.BuiltinDeadLeft(pLog)        ! left() on a receiver trimmed above, read from character 1
  of 'KNOWNRANGES'
    return self.BuiltinKnownRanges(pLog)     ! retire a guard / a choose() that provably cannot go the other way
  of 'TRAILINGSPACES'
    return self.BuiltinTrailingSpaces(pLog)  ! make "no trailing spaces" true, then retire the code that asks about them
  of 'KEYWORDCASE'
    return self.BuiltinKeywordCase(pLog)
  of 'SPLITSTATEMENTS'
    return self.BuiltinSplitStatements(pLog)
  of 'EXPANDONELINERS'
    return self.BuiltinExpandOneLiners(pLog)
  of 'BLOCKENDSTYLE'
    return self.BuiltinBlockEndStyle(pLog)
  of 'REINDENT'
    return self.BuiltinReindent(pLog)
  else
    if self.curPass = 1
      pLog.append('BUILTIN ' & clip(self.rl.rules.builtinName) & ' is not a builtin this engine knows - skipped<13,10>')
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! BUILTIN CombineAdjacentLiterals - port of the vtxaDiff009 routine (GCR 27Aug2021).
! Part 1: 'abc' & 'xyz' -> 'abcxyz', repeating along chains ('a' & 'b' & 'c').
!         Not combined when the & or the second literal starts a new line, so
!         continuations and comments are never lost. vtxaDiff checked only the
!         second literal and carried a TODO for the & token; both are checked
!         here. Deviation from vtxaDiff, veto if byte-parity preferred
! Part 2: inside one literal, '<13><10>' -> '<13,10>' when both bracket groups
!         are comma-separated integer lists 0-255 (vtxaDiff 15Oct2023 logic).
! Ported onto locals (vtxaDiff used globals stTmp/param/changes); the inner
! labelled loop is kept from vtxaDiff - labels and labelled
! CYCLE/BREAK are legal inside class methods (cf VitTokenize.FoldStr's L loop).
! Error stops became log lines that advance startTok (vtxaDiff's cycle without
! advancing would have spun forever after the stop).
! ------------------------------------------------------------------------------------
VitEngine.BuiltinCombineLiterals Procedure(StringTheory pLog)
startTok      long(1)
chk           long,auto ! general check variable
pos           long,auto
x             long,auto
oldLen        long,auto
lineNo        long,auto
changes       long
stTmp         StringTheory
param         StringTheory
stB           StringTheory
stT           StringTheory
  code
  loop
    startTok = self.tk.FindSeq('|^  %''| &| %''', startTok)                   ! literal & literal (%' = literal-type wildcard)
    if ~startTok then break.
    stTmp.setValue(self.tk.getTok(startTok))
    lineNo = self.tk.tokens.lineNo
    chk = stTmp._DataEnd
    stTmp.UnQuote('''','''')
    if chk = stTmp._DataEnd                                                   ! token typed literal but does not unquote - should not happen
      pLog.append('BUILTIN CombineAdjacentLiterals line ' & self.tk.MapLine(lineNo) & ': unexpected non-literal token, skipped<13,10>')
      startTok += 1
      cycle
    end
    stTmp.freeLines()
    stTmp.setLine(1, stTmp.getValuePtr())                                     ! store first literal's content
    stTmp.setValue(self.tk.getTok(startTok+2))                                ! the token after the &
    chk = stTmp._DataEnd
    stTmp.UnQuote('''','''')
    if chk = stTmp._DataEnd
      pLog.append('BUILTIN CombineAdjacentLiterals line ' & self.tk.MapLine(lineNo) & ': unexpected non-literal token, skipped<13,10>')
      startTok += 1
      cycle
    end
    stTmp.setLine(2, stTmp.getValuePtr())
    self.tk.GetTok(startTok+1, stB, stT)                                      ! the &
    if ~stB.containsByte(10)                                                  ! <line feed>
      self.tk.GetTok(startTok+2, stB, stT)                                    ! the second literal
    end
    if stB.containsByte(10)                                                   ! & or literal on a continuation line - do NOT combine <line feed>
      startTok += 1
      cycle
    end
    stTmp.join('')                                                            ! recombine the two stored lines
    stTmp.quote('''','''',true)                                               ! pQuoteEmpty=true: '' & '' -> '' (vtxaDiff sliced valuePtr[1:0] here)
    self.tk.SetTok(startTok, stTmp.valuePtr[1 : stTmp._DataEnd])
    self.tk.DeleteToks(startTok+1, startTok+2)                                ! the & and the second literal (both glue-checked: no trivia lost)
    pLog.append('BUILTIN CombineAdjacentLiterals line ' & self.tk.MapLine(lineNo) & ': ==> ' & stTmp.getValue() & '<13,10>')
    changes += 1
  end                                                                         ! loop

  ! within a single literal change <13><10> style runs to <13,10> - only when both
  ! sides of the >< are comma-separated integer lists with every value 0-255
  startTok = 0
  loop
    startTok = self.tk.FindSeq('|^  %''', startTok+1)                         ! any literal
    if ~startTok then break.
    stTmp.setValue(self.tk.getTok(startTok))
    lineNo = self.tk.tokens.lineNo
    oldLen = stTmp._DataEnd
    pos = 0
L   loop
      pos += 1
      pos = stTmp.findchars('><<', pos)
      if ~pos then break.
      if pos+2 <= stTmp._DataEnd and stTmp.valuePtr[pos+2] = '<<' then cycle. ! doubled << = literal < char (a sub(pos+2)='<' test here would be a rest-of-string compare AND an un-doubled literal; vtxaDiff 2683)
      ! check <xxx> on the left
      chk = stTmp.instring('<<',-1,1,pos-1)
      if ~chk or |
         chk > 1 and stTmp.valuePtr[chk-1] = '<<' ! doubled << = literal < char (same fix as above; vtxaDiff 2687)
        cycle
      end
      param.setvalue(stTmp.slice(chk+1,pos-1))    ! part between < and >
      if param._DataEnd < 1 then cycle.
      if not param.isAll('0123456789, ') then cycle.
      param.split(',',,,,st:clip,st:left)
      loop x = 1 to param.records()
        param.setValueFromLine(x)
        if not param.IsAllDigits() or param.getValue() > 255 then cycle L.
      end
      ! check <xxx> on the right
      chk = stTmp.findByte(62, pos+2)             ! '>'
      if ~chk then cycle.
      param.setvalue(stTmp.slice(pos+2,chk-1))    ! part between < and >
      if param._DataEnd < 1 then cycle.
      if not param.isAll('0123456789, ') then cycle.
      param.split(',',,,,st:clip,st:left)
      loop x = 1 to param.records()
        param.setValueFromLine(x)
        if not param.IsAllDigits() or param.getValue() > 255 then cycle L.
      end
      ! all ok - replace '><' with ','
      stTmp.removeFromPosition(pos,1)
      stTmp.valueptr[pos] = ','
    end                                           ! loop
    if stTmp._DataEnd <> oldLen                   ! were changes made? (>< to comma reduces size)
      self.tk.SetTok(startTok, stTmp.valuePtr[1 : stTmp._DataEnd])
      pLog.append('BUILTIN CombineAdjacentLiterals line ' & self.tk.MapLine(lineNo) & ': ==> ' & stTmp.getValue() & '<13,10>')
      changes += 1
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! BUILTIN CheckCaseStatements - port of TWO vtxaDiff009 routines under one name:
! checkCaseStatements (GCR 5Dec2023: case 'x' -> case val('x') when every
! of/orof/to operand at case level is a single char, at least one non-digit)
! and checkVals (GCR 20Sep2023: val(chr(x)) -> x, then val('x') -> integer
! everywhere, one generated end-of-line comment per line via a scratch
! tokenizer - '<tab> orof ''x''' style in case context, '120=''x''' otherwise).
! vtxaDiff runs them back-to-back; the rule file names only CheckCaseStatements
! so both live here. Level-mismatch stop()s became log lines (the case is then
! skipped via cycle P); the labelled P loop / 'cycle P' is kept from vtxaDiff;
! GetTok('') guards added (vtxaDiff sliced blind).
! ------------------------------------------------------------------------------------
VitEngine.BuiltinCheckCase Procedure(StringTheory pLog)
startTok       long
endTok         long,auto
endBracket     long,auto
x              long,auto
allSingle      long,auto
lev            long
lineNo         long,auto
changes        long
prevValLineNo  long
cmtStartTok    long,auto
hdrEol         long,auto                                     ! EOL token of the CASE header line
cmtLastTok     long,auto
cmtEB          long,auto                                     ! comment end bracket
cmtCaseFormat  byte,auto                                     ! case statement context -> name format, else int='x' format
selS           long,auto                                     ! selector span start/end (SelGuard)
selE           long,auto
selOk          byte                                          ! selector provably single-char
param          StringTheory
comment        StringTheory
cmtTk          VitTokenize                                   ! scratch tokenizer for building the comment
  code
  ! --- pass 1: case 'x' -> case val('x') (vtxaDiff checkCaseStatements) ---
P loop
    startTok = self.tk.FindSeq(',^  ^case', startTok+1)
    if ~startTok then break.
    if lower(self.tk.getTok(startTok+1)) = 'val' then cycle. ! already: case val('x')
    self.tk.GetTok(startTok)                                 ! reget case (positions the queue for MatchLevel)
    endTok = self.tk.MatchLevel()                            ! find matching 'end'
    if ~endTok then cycle.                                   ! no 'end' found for case statement

    ! between startTok and endTok every case-level of/orof/to operand must be a
    ! single char, and at least one must be a non-digit (a bare digit case could
    ! be a genuine numeric CASE on a long/byte)
    allSingle = false
    lev = 1
    loop x = startTok + 1 to endTok - 1
      get(self.tk.tokens, x)
      if errorcode() or self.tk.tokens.tok &= NULL then break.
      case val(self.tk.tokens.level)
      of 43                                                  ! '+'
        lev += 1
        cycle
      of 45                                                  ! '-'
        if ~lev
          pLog.append('BUILTIN CheckCaseStatements: mismatched level (end) at token ' & x & ' line ' & self.tk.MapLine(self.tk.tokens.lineNo) & ' - case skipped<13,10>')
          cycle P
        else
          lev -= 1
        end
        cycle
      end
      if lev > 1 then cycle.                                 ! skip nested case/if levels

      case lower(self.tk.tokens.tok)
      of 'of' orof 'orof' orof 'to'
        ! *** THE OPERAND HAS TO END HERE. *** This wraps ONE token in val(), so an operand
        ! that is an expression had only its first token wrapped: `of 'a' & pad` came back as
        ! `val('a') & pad`, then `97 & pad` - a different comparison, and one that still
        ! compiles. The operand ends at an EOL, a ';', or the next arm of the same CASE.
        if ~self.IsEolTok(x+2)                      |
           and self.tk.GetTok(x+2) <> ';'           |
           and lower(self.tk.GetTok(x+2)) <> 'orof' |
           and lower(self.tk.GetTok(x+2)) <> 'to'
          cycle P                                   ! the operand is an EXPRESSION - refuse the whole CASE (#3):
        end                                         !   the wrap loop below wraps every arm unconditionally, so
                                                    !   skipping just this arm converts of 'b' & pad toof 98 & pad$n        x += 1
        param.setValue(self.tk.GetTok(x))
        if ~self.IsSingleChar(param.getValue()) then cycle P.
        if param._DataEnd > 1
          allSingle = true                                  ! at least one quoted/escaped char (not a bare digit)
        end
      end
    end
    if ~allSingle then cycle.

    hdrEol = startTok + 1                                   ! a continued CASE header ('case foo |') would take the ')' into continuation trivia (invisible to the compiler) and desync endTok
    loop while hdrEol < endTok
      get(self.tk.tokens, hdrEol)
      if errorcode() then break.
      if not self.tk.tokens.tok &= NULL
        if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then break.
      end
      hdrEol += 1
    end
    if self.SpanHasNL(startTok + 1, hdrEol - 1) then cycle. ! EXCLUDE the EOL token itself - SpanHasNL counts it as a newline, so including it skipped EVERY multi-line CASE (a real continuation's LF lives in an EARLIER token's strBefore, still inside the span)

    ! SELECTOR guard: val() reads only the FIRST char, so the selector itself must be
    ! provably single-char - the operand test alone is not enough (vtxaDiff 982
    ! comment "do NOT use val() as token may be > 1 char"; and its 2321 "case param.getLine(1)"
    ! with quoted-digit operands would have treated crop(10) as crop(1) once converted).
    ! Provable forms: quoted literal passing IsSingleChar, single-index slice x[i] (a string
    ! char pick), or a variable declared STRING(1) via the symbol table. Anything
    ! else - function calls, bare vars of other/unknown type - is SKIPPED and logged.
    ! deliberate safe-direction deviation: vtxaDiff wraps these blind.
    selS = startTok + 1
    selE = hdrEol - 1
    do SelGuard
    if ~selOk
      if self.curPass = 1                                   ! the site re-refuses every pass - log once
        pLog.append('BUILTIN CheckCaseStatements: case skipped (selector not provably 1-char) line ' & self.LogLineOf(startTok) & '<13,10>')
      end
      cycle
    end

    ! all values single chars: wrap the case expression in val(...)
    self.tk.InsertStringAtEOL(startTok+1, ')', 3)           ! mode 3: real token, ';'/'THEN' count as EOL
    self.tk.addTok(startTok+2, self.tk.GetTok(startTok+1))  ! move expression start over (no strBefore)
    self.tk.SetTok(startTok+1, 'val')                       ! keeps the existing strBefore
    get(self.tk.tokens, startTok+1)                         ! a glued source "case(" has an EMPTY
    if ~errorcode() and self.tk.tokens.strBefore &= NULL    !   strBefore, so 'val' would emit as
      self.tk.SetStrBefore(startTok+1, ' ')                 !   "caseval(" - force one space
    end
    self.tk.addTok(startTok+2, '(')
    startTok += 2
    endTok += 3

    ! and wrap each of/orof/to operand in val() - pass 2 converts to integers
    lev = 1
    loop x = startTok + 1 to endTok - 1
      get(self.tk.tokens, x)
      if errorcode() or self.tk.tokens.tok &= NULL then break.
      case val(self.tk.tokens.level)
      of 43                                                 ! '+'
        lev += 1
        cycle
      of 45                                                 ! '-'
        if ~lev
          pLog.append('BUILTIN CheckCaseStatements: mismatched level (end) at token ' & x & ' line ' & self.tk.MapLine(self.tk.tokens.lineNo) & '<13,10>')
        else
          lev -= 1
        end
        cycle
      end
      if lev > 1 then cycle.

      case lower(self.tk.tokens.tok)
      of 'of' orof 'orof' orof 'to'
        self.tk.addTok(x+2, ')')
        if len(self.tk.GetTok(x+1)) = 1
          self.tk.addTok(x+2, '''' & self.tk.GetTok(x+1) & '''') ! quote a bare digit so pass 2 treats it as a char
        else
          self.tk.addTok(x+2, self.tk.GetTok(x+1))
        end
        self.tk.addTok(x+2, '(')
        self.tk.setTok(x+1, 'val')                               ! keeps spacing before
        endTok += 3
        x += 4
        changes += 1
      end
    end
  end

  ! --- pass 2a: val(chr(whatever)) -> whatever (vtxaDiff checkVals) ---
  startTok = 0
  loop
    startTok = self.tk.FindSeq(',^  ^val, (, ^chr, (', startTok+1)
    if ~startTok then break.
    endBracket = self.tk.MatchLeftBracket('(',')',startTok+1)
    if self.tk.getTok(endBracket-1) <> ')' then cycle.           ! expect )) as in val(chr(xxx))
    if endBracket <> startTok + 6 then cycle.                    ! ONE token inside chr(...) - the same arity guard pass 2b
                                                                 !   applies: dropping the parens from val(chr(i + 1)) * 2
                                                                 !   leaves i + 1 * 2, different arithmetic (#19)
    self.tk.DeleteToks(endBracket-1, endBracket)
    self.tk.setTok(startTok, self.tk.getTok(startTok+4))         ! keeps spacing before
    self.tk.DeleteToks(startTok+1, startTok+4)
    changes += 1
  end

  ! --- pass 2b: val('x') -> integer, with one generated comment per line ---
  startTok = 0
  loop
    startTok = self.tk.FindSeq(',^  ^val, (', startTok+1)
    if ~startTok then break.
    endBracket = self.tk.MatchLeftBracket('(',')',startTok+1)
    if endBracket <> startTok+3 then cycle.                      ! want exactly val(tok)
    param.setValue(self.tk.GetTok(startTok+2))
    if ~self.IsSingleChar(param.getValue()) then cycle.

    get(self.tk.tokens, startTok)                                ! the val token
    lineNo = self.tk.tokens.lineNo
    if lineNo <> prevValLineNo                                   ! first val() on this line: build the line's comment
      prevValLineNo = lineNo
      self.tk.joinToks(comment, startTok, -1)                    ! -1 = to end of current line, comments excluded
      comment.trim()
      if comment.instring(' orof ',,,,st:noCase) or comment.instring(' to ',,,,st:noCase) or |
         lower(self.tk.GetTok(startTok-1)) = 'of' or lower(self.tk.GetTok(startTok-1)) = 'orof'
        cmtCaseFormat = true
      else
        cmtCaseFormat = false
      end
      cmtTk.ParseText(comment)
      cmtStartTok = 0
      cmtLastTok = 0
      loop
        cmtStartTok = cmtTk.FindSeq(',^  ^val, (', cmtStartTok+1)
        if ~cmtStartTok then break.
        cmtEB = cmtTk.MatchLeftBracket('(',')',cmtStartTok+1)
        if cmtEB <> cmtStartTok+3 then cycle.
        comment.setValue(cmtTk.GetTok(cmtStartTok+2))
        if ~comment._DataEnd or |
           comment.valuePtr[1] <> '''' or comment.valuePtr[comment._DataEnd] <> ''''
          cycle
        end
        if comment._DataEnd = 3 and ~cmtCaseFormat                     ! plain context: 120='x'
          cmtTk.setTok(cmtStartTok, val(comment.valuePtr[2]) & '=' & comment.getValue())
        else                                                           ! case context / escape form: pretty name
          cmtTk.setTok(cmtStartTok, self.CharName(comment.getValue()))
        end
        cmtLastTok = cmtStartTok
        cmtTk.deleteToks(cmtStartTok+1, cmtStartTok+3)                 ! ('x')
      end
      if cmtLastTok
        cmtTk.joinToks(comment, 1, cmtLastTok)                         ! up to the last val() replacement
        self.tk.InsertStringAtEOL(endBracket+1, comment.getValue(), 2) ! mode 2: comment, prepended
      end
      cmtTk.FreeToks()
    end

    case param._DataEnd
    of 1                                                               ! bare digit
      self.tk.setTok(startTok, val(param.valuePtr[1]))
    of 3                                                               ! 'x'
      self.tk.setTok(startTok, val(param.valuePtr[2]))
    else                                                               ! '<13>' / '''' / doubled pairs
      self.tk.setTok(startTok, self.GetSingleCharVal(param.getValue()))
    end
    self.tk.DeleteToks(startTok+1, endBracket)
    changes += 1
  end
  if changes
    pLog.append('BUILTIN CheckCaseStatements: ' & changes & ' change(s)<13,10>')
  end
  return changes

SelGuard routine
  data
hx   long,auto
dep  long,auto
  code
  ! is the selector span [selS,selE] provably ONE character? (see banner at the call site)
  selOk = 0
  dep = 0
  loop hx = selS to selE    ! a one-liner "case x; of ..." puts the ';' tail in
    case self.tk.getTok(hx) !   the header span - the selector ends at the ';'
    of '(' orof '['
      dep += 1
    of ')' orof ']'
      dep -= 1
    of ';'
      if ~dep
        selE = hx - 1
        break
      end
    end
  end
  loop while selS < selE                              ! unwrap enclosing brackets: case(x) -> x
    if self.tk.getTok(selS) <> '(' then break.
    if self.tk.MatchLeftBracket('(', ')', selS) <> selE then break.
    selS += 1
    selE -= 1
  end
  if selS > selE then exit.
  if selS = selE                                      ! single token
    if self.IsSingleChar(self.tk.GetTok(selS))        ! quoted single-char literal: 'x' / '<13>' / ''''
      selOk = 1
    else
      hx = val(upper(self.tk.getTok(selS)))
      if (hx >= 65 and hx <= 90) or hx = 95           ! identifier-shaped: STRING(1) variable?
        do String1Chk
      end
    end
    exit
  end
  ! slice form: <variable token> [ <single index> ] - a single-index pick of a STRING is one
  ! character, so a CASE on it may be compared against single-char literals.
  !
  ! *** UNLESS THE HEAD IS DIM'd, IN WHICH CASE THE PICK IS AN ELEMENT. *** `x STRING(5),DIM(3)`
  ! makes `x[2]` a five-character element, and `x LONG,DIM(3)` makes it a LONG - neither is the
  ! one character this arm is about to assume. The bare-identifier arm below has always tested
  ! for DIM; this one argued from the corpus instead, which is not an argument about
  ! soundness.
  !
  ! The proof is NameSliceOk, and it answers only YES or DON'T KNOW. DON'T KNOW refuses,
  ! because "is it DIM'd" says NO when it cannot find the declaration - which let an array
  ! PARAMETER and a plain-GROUP member through. It reads the LOGICAL declaration, since a
  ! ,DIM(3) may sit past a '|', and it FOLLOWS a LIKE, since LIKE carries no DIM of its own
  ! but inherits the target's.
  if self.tk.getTok(selE) <> ']' then exit.
  if self.tk.getTok(selS+1) <> '[' then exit.
  if self.tk.MatchLeftBracket('[', ']', selS+1) <> selE then exit.
  hx = val(upper(self.tk.getTok(selS)))
  if ~((hx >= 65 and hx <= 90) or hx = 95) then exit. ! head must be a variable token (merged dotted receiver ok)
  dep = 0
  loop hx = selS + 2 to selE - 1                      ! reject a top-level ':' (range slice = substring)
    case self.tk.getTok(hx)                           !   or ',' (2-D element) inside the [ ]
    of '(' orof '['
      dep += 1
    of ')' orof ']'
      dep -= 1
    of ':' orof ','
      if ~dep then exit.
    end
  end
  if changes then self.syms.dirty = 1.                ! declTok may have shifted this run
  self.syms.EnsureFresh()
  if ~self.NameSliceOk(upper(self.tk.getTok(selS)), startTok) then exit.
  selOk = 1

String1Chk routine
  data
sy     long,auto
scr    long,auto
bestR  long,auto
bestSp long,auto
dTok   long,auto
tw     long,auto
nmU    string(vs:maxName),auto
  code
  ! bare-identifier selector - convert when it is declared STRING(1). The symtab
  ! canonical type drops the size (STRING(20) -> STRING), so find the INNERMOST enclosing
  ! symbol of that name (any type - shadowing must win), then read the size straight off the
  ! declaration tokens at declTok. Token positions may have shifted if this builtin already
  ! wrapped an earlier CASE this run - flag dirty so EnsureFresh re-Builds before we trust
  ! declTok (PrependStrBefore-only builtins never move a position, so they never need this).
  if changes
    self.syms.dirty = 1
  end
  self.syms.EnsureFresh()
  nmU = upper(self.tk.getTok(selS))
  bestR = 0
  bestSp = 0
  loop sy = 1 to records(self.syms.syms)
    get(self.syms.syms, sy)
    if errorcode() then break.
    if self.syms.syms.nameU <> nmU then cycle.
    scr = self.syms.syms.scopeId
    get(self.syms.scopes, scr)
    if errorcode() then cycle.
    if self.syms.scopes.startTok > startTok or self.syms.scopes.endTok < startTok then cycle. ! scope must contain this CASE
    if ~bestR or self.syms.scopes.endTok - self.syms.scopes.startTok < bestSp
      bestR  = sy
      bestSp = self.syms.scopes.endTok - self.syms.scopes.startTok
    end
  end
  if ~bestR then exit.
  get(self.syms.syms, bestR)
  if self.syms.syms.isRef or self.syms.syms.isLike or |   ! &STRING / LIKE: size not provable here
     self.syms.syms.typeU <> 'STRING'
    exit
  end
  dTok = self.syms.syms.declTok
  loop tw = dTok to dTok + 2                ! decl window: <label> STRING ( 1 ) - an unsized
    if upper(self.tk.getTok(tw)) = 'STRING' !   STRING param never matches ( after STRING -> refuse
      if self.tk.getTok(tw+1) = '(' and self.tk.getTok(tw+3) = ')'
        if self.tk.getTok(tw+2) = '1'                 |                                                        ! STRING(1)
        or (val(self.tk.getTok(tw+2)) = 39 and self.IsSingleChar(self.tk.getTok(tw+2))) ! STRING('a')/STRING('<161>') - size = literal length = 1. The quote
                                                                                        !   gate (first char = 39) keeps STRING(9) out: IsSingleChar accepts bare digits
          if ~(self.tk.getTok(tw+4) = ',' and upper(self.tk.getTok(tw+5)) = 'DIM')      ! STRING(1),DIM(n): the bare name is the ARRAY
            selOk = 1
          end
        end
      end
      break
    end
  end

! ------------------------------------------------------------------------------------
! BUILTIN CheckReplaces - port of the vtxaDiff009 routine (GCR 9Sep2021,
! byte forms 22Oct2023): drop trailing default args off st.replace(), map
! pNoCase 1 -> st:noCase, then single-char forms to removeByte ('x','') or
! replaceByte ('x','z') with a generated "replace all ..." comment.
! deviation: a call whose argument span crosses a line break is skipped
! (vtxaDiff rejoins the args and would flatten the continuation and lose any
! comment). Veto if byte-parity on multi-line calls preferred.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinCheckReplaces Procedure(StringTheory pLog)
startTok     long,auto
endBracket   long
lChanges     long,auto
charVal      long,auto                                           ! LONG not byte: invalid is -1
charVal2     long,auto
lineNo       long,auto
changes      long
param        StringTheory
  code
  loop
    startTok = self.tk.FindSeq(',^ .,^replace, (', endBracket+1) ! look for .replace(
    if ~startTok then break.
    startTok += 2                                                ! FindSeq returns the '.' - move up to '('
    endBracket = self.tk.MatchLeftBracket('(',')',startTok)
    if ~endBracket then endBracket = startTok; cycle.            ! shouldn't happen
    !
    ! *** AND ASK WHAT THE RECEIVER IS. *** This finds its work by METHOD NAME alone, while
    ! every textual rule in the rule file proves the receiver through a typed metavar. So a
    ! same-named method on another class was rewritten by StringTheory's prototype:
    ! `ob.replace('a','')` on a CStringClass came back as `ob.removeByte(97)`, which either
    ! does not compile or, worse, compiles and means something else.
    !
    ! Refuses only what it can PROVE is another class. A receiver the symbol table cannot
    ! resolve still converts, exactly as before - requiring positive proof would be sound but
    ! would decline every unresolved receiver, and that is a change to what the tool DOES,
    ! not just to what it refuses. Registered as a decision rather than taken here.
    !
    ! *** IT MUST SIT AFTER endBracket ADVANCES. *** Cycling before that leaves FindSeq
    ! searching from the same place, so a refused site is found again on the next turn and
    ! the loop never ends. It hung the transform on the first non-StringTheory receiver.
    if self.RecvIsOtherClass(startTok - 3) then cycle.
    if self.SpanHasNL(startTok+1, endBracket-1) then cycle.      ! keep comments/continuations intact
    get(self.tk.tokens, startTok)
    lineNo = self.tk.tokens.lineNo

    self.tk.JoinToks(param, startTok+1, endBracket-1)
    param.split(',','''-(','''-)',,,,'-',st:nested)              ! no clip/left: preserve original spacing
    if param.records() > 7 then cycle.                           ! currently 7 parms

    lChanges = 0
    ! NB. no CASE on param.records(): deleteLine changes the count between tests
    if param.records() = 7
      case lower(left(param.getLine(7)))                         ! bool pRecursive
      of '0' orof 'false' orof ''
        lChanges += 1
        param.deleteLine(7)
      end
    end
    if param.records() > 5
      case lower(left(param.getLine(6)))                         ! long pNoCase=0
      of '1' orof 'true'
        param.setLine(6,'st:noCase')
        lChanges += 1
      of '0' orof 'false' orof ''
        if param.records() = 6                                   ! last parm?
          lChanges += 1
          param.deleteLine(6)
        end
      end
    end
    if param.records() = 5                                       ! last parm?
      case lower(left(param.getLine(5)))                         ! long pEnd=0
      of '0' orof 'false' orof ''
        lChanges += 1
        param.deleteLine(5)
      end
    end
    if param.records() = 4                                       ! last parm?
      case lower(left(param.getLine(4)))                         ! long pStart=1
      of '1' orof 'true' orof ''
        lChanges += 1
        param.deleteLine(4)
      end
    end
    if param.records() = 3                                       ! last parm?
      case lower(left(param.getLine(3)))                         ! long pCount=0
      of '0' orof 'false' orof ''
        lChanges += 1
        param.deleteLine(3)
      end
    end

    if param.records() = 2                                       ! removeByte / replaceByte?
      charVal = self.GetSingleCharVal(param.getLine(1))
      if charVal <> -1
        if left(param.getLine(2)) = ''''''                       ! replacing with '' = remove
          self.tk.setTok(startTok - 1, 'removeByte')
          self.tk.setTok(startTok + 1, charVal)
          self.tk.InsertStringAtEOL(endBracket+1, 'remove all ' & self.CharName(param.getLine(1)))
          self.tk.DeleteToks(startTok+2, endBracket-1)
          lChanges += 1
          changes += lChanges
          pLog.append('BUILTIN CheckReplaces line ' & self.tk.MapLine(lineNo) & ': ==> removeByte(' & charVal & ')<13,10>')
          endBracket = startTok+2
          cycle
        end
        charVal2 = self.GetSingleCharVal(param.getLine(2))
        if charVal2 <> -1
          self.tk.setTok(startTok - 1, 'replaceByte')
          self.tk.setTok(startTok + 1, charVal)
          self.tk.setTok(startTok + 3, charVal2) ! +2 is the comma
          self.tk.InsertStringAtEOL(endBracket+1, 'replace all ' & self.CharName(param.getLine(1)) & ' with ' & self.CharName(param.getLine(2)))
          self.tk.DeleteToks(startTok+4, endBracket-1)
          lChanges += 1
          changes += lChanges
          pLog.append('BUILTIN CheckReplaces line ' & self.tk.MapLine(lineNo) & ': ==> replaceByte(' & charVal & ',' & charVal2 & ')<13,10>')
          endBracket = startTok+4
          cycle
        end
      end
    end

    if lChanges
      changes += lChanges
      param.join(',')
      self.tk.DeleteToks(startTok+1, endBracket-1)
      self.tk.InsertString(startTok+1, param)
      pLog.append('BUILTIN CheckReplaces line ' & self.tk.MapLine(lineNo) & ': args ==> (' & param.getValue() & ')<13,10>')
      endBracket = startTok+1
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! BUILTIN CheckRemoves - port of the vtxaDiff009 routine (GCR 13Sep2023,
! removeByte 21-22Oct2023). Same shape as CheckReplaces for st.remove():
! drop trailing defaults, pNoCase 1 -> st:noCase, single-char -> removeByte.
! Keeps vtxaDiff's RETURN SELF.remove() guard (ST-internal overloads).
! Same line-break skip deviation as CheckReplaces.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinCheckRemoves Procedure(StringTheory pLog)
startTok     long,auto
endBracket   long
lChanges     long,auto
charVal      long,auto
lineNo       long,auto
changes      long
param        StringTheory
  code
  loop
    startTok = self.tk.FindSeq(',^ .,^remove, (', endBracket+1) ! look for .remove(
    if ~startTok then break.
    startTok += 2
    endBracket = self.tk.MatchLeftBracket('(',')',startTok)
    if ~endBracket then endBracket = startTok; cycle.
    !
    ! *** AND ASK WHAT THE RECEIVER IS. *** This finds its work by METHOD NAME alone, while
    ! every textual rule in the rule file proves the receiver through a typed metavar. So a
    ! same-named method on another class was rewritten by StringTheory's prototype:
    ! `ob.replace('a','')` on a CStringClass came back as `ob.removeByte(97)`, which either
    ! does not compile or, worse, compiles and means something else.
    !
    ! Refuses only what it can PROVE is another class. A receiver the symbol table cannot
    ! resolve still converts, exactly as before - requiring positive proof would be sound but
    ! would decline every unresolved receiver, and that is a change to what the tool DOES,
    ! not just to what it refuses. Registered as a decision rather than taken here.
    !
    ! *** IT MUST SIT AFTER endBracket ADVANCES. *** Cycling before that leaves FindSeq
    ! searching from the same place, so a refused site is found again on the next turn and
    ! the loop never ends. It hung the transform on the first non-StringTheory receiver.
    if self.RecvIsOtherClass(startTok - 3) then cycle.
    if upper(self.tk.getTok(startTok-3)) = 'SELF' and upper(self.tk.getTok(startTok-4)) = 'RETURN' then cycle.
    if self.SpanHasNL(startTok+1, endBracket-1) then cycle.
    get(self.tk.tokens, startTok)
    lineNo = self.tk.tokens.lineNo

    self.tk.JoinToks(param, startTok+1, endBracket-1)
    param.split(',','''-(','''-)',,,,'-',st:nested)
    if param.records() > 5 then cycle.                          ! currently 5 parms

    lChanges = 0
    if param.records() = 5
      case lower(left(param.getLine(5)))                        ! bool pCount
      of '0' orof 'false' orof ''
        lChanges += 1
        param.deleteLine(5)
      end
    end
    if param.records() = 4
      case lower(left(param.getLine(4)))                        ! bool pContentsOnly
      of '0' orof 'false' orof ''
        lChanges += 1
        param.deleteLine(4)
      end
    end
    if param.records() > 2
      case lower(left(param.getLine(3)))                        ! long pNoCase=0
      of '1' orof 'true'
        param.setLine(3,'st:noCase')
        lChanges += 1
      of '0' orof 'false' orof ''
        if param.records() = 3
          lChanges += 1
          param.deleteLine(3)
        end
      end
    end
    if param.records() = 2 and ~param.getLine(2)                ! string pRight
      lChanges += 1
      param.deleteLine(2)
    end

    if param.records() = 1                                      ! removeByte? (single char only)
      charVal = self.GetSingleCharVal(param.getLine(1))
      if charVal <> -1
        self.tk.setTok(startTok - 1, 'removeByte')
        self.tk.setTok(startTok + 1, charVal)
        self.tk.InsertStringAtEOL(endBracket+1, 'remove all ' & self.CharName(param.getLine(1)))
        self.tk.DeleteToks(startTok+2, endBracket-1)
        lChanges += 1
        changes += lChanges
        pLog.append('BUILTIN CheckRemoves line ' & self.tk.MapLine(lineNo) & ': ==> removeByte(' & charVal & ')<13,10>')
        endBracket = startTok+2
        cycle
      end
    end

    if lChanges
      changes += lChanges
      param.join(',')
      self.tk.DeleteToks(startTok+1, endBracket-1)
      self.tk.InsertString(startTok+1, param)
      pLog.append('BUILTIN CheckRemoves line ' & self.tk.MapLine(lineNo) & ': args ==> (' & param.getValue() & ')<13,10>')
      endBracket = startTok+1
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! ------------------------------------------------------------------------------------
! BUILTIN CheckSplits - port of the vtxaDiff009 routine (GCR 7Sep2021). It never came
! over with the rest of the family, and was found by auditing that file against this one
! st.split()'s 5th and 6th parameters are booleans in the prototype but
! they have NAMES, and a trailing default is noise:
!     st.split(',', '''', '''', true, true, true)
!  -> st.split(',', '''', '''', true, st:clip, st:left)
!
! Split(pSplitStr, pQuoteStart, pQuoteEnd, pRemoveQuotes, pClip, pLeft, pSeparator, pNested)
!
! THE 4th PARAMETER IS LEFT ALONE ON PURPOSE. vtxaDiff names it st:removeQuotes (GCR
! 5May2025) but that equate exists ONLY IN A PRIVATE StringTheory and never reached the
! CapeSoft release - which this file's own StringTheory.inc confirms: it
! has st:clip, st:left, st:nested and st:noClip, and no st:removeQuotes. Emitting it would
! produce source that does not compile for anyone else. The code is below, commented out,
! ready for the day it ships.
!
! Two refinements kept from the original: a trailing DEFAULT is deleted rather than named,
! and when the split is on a SPACE with no quote arguments, clip and left are redundant -
! the split already discards the run - so they come off again.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinCheckSplits Procedure(StringTheory pLog)
startTok     long,auto
endBracket   long
lChanges     long,auto
lineNo       long,auto
changes      long
param        StringTheory
  code
  loop
    startTok = self.tk.FindSeq(',^ .,^split, (', endBracket+1) ! look for .split(
    if ~startTok then break.
    startTok += 2                                              ! FindSeq returns the '.' - move up to '('
    endBracket = self.tk.MatchLeftBracket('(',')',startTok)
    if ~endBracket then endBracket = startTok; cycle.          ! shouldn't happen
    !
    ! *** AND ASK WHAT THE RECEIVER IS. *** This finds its work by METHOD NAME alone, while
    ! every textual rule in the rule file proves the receiver through a typed metavar. So a
    ! same-named method on another class was rewritten by StringTheory's prototype:
    ! `ob.replace('a','')` on a CStringClass came back as `ob.removeByte(97)`, which either
    ! does not compile or, worse, compiles and means something else.
    !
    ! Refuses only what it can PROVE is another class. A receiver the symbol table cannot
    ! resolve still converts, exactly as before - requiring positive proof would be sound but
    ! would decline every unresolved receiver, and that is a change to what the tool DOES,
    ! not just to what it refuses. Registered as a decision rather than taken here.
    !
    ! *** IT MUST SIT AFTER endBracket ADVANCES. *** Cycling before that leaves FindSeq
    ! searching from the same place, so a refused site is found again on the next turn and
    ! the loop never ends. It hung the transform on the first non-StringTheory receiver.
    if self.RecvIsOtherClass(startTok - 3) then cycle.
    if self.SpanHasNL(startTok+1, endBracket-1) then cycle.    ! keep comments/continuations intact
    get(self.tk.tokens, startTok)
    lineNo = self.tk.tokens.lineNo

    self.tk.JoinToks(param, startTok+1, endBracket-1)
    param.split(',','''-(','''-)',,,,'-',st:nested)            ! no clip/left: preserve original spacing
    if param.records() < 4 or param.records() > 8 then cycle.  ! currently 8 parms

    lChanges = 0
    ! NB. no CASE on param.records(): deleteLine changes the count between tests
    if param.records() = 8
      case lower(left(param.getLine(8)))                       ! Long pNested=false
      of '0' orof 'false' orof ''
        lChanges += 1
        param.deleteLine(8)
      end
    end
    if param.records() = 7
      case lower(left(param.getLine(7)))                       ! <string pSeparator>
      of '' orof ''''''
        lChanges += 1
        param.deleteLine(7)
      end
    end
    if param.records() > 5
      case lower(left(param.getLine(6)))                       ! bool pLeft=false
      of '1' orof 'true'
        param.setLine(6,'st:left')
        lChanges += 1
      of '0' orof 'false' orof ''
        if param.records() = 6                                 ! last parm?
          lChanges += 1
          param.deleteLine(6)
        end
      end
    end
    ! splitting on a SPACE with no quote args: left is redundant (GCR 2May2025)
    if param.records() > 5 and (param.getLine(1) = ''' ''' or param.getLine(1) = '''<32>''') and ~param.getLine(2)
      if lower(left(param.getLine(6))) = 'st:left'
        if param.records() = 6
          param.deleteLine(6)
        else
          param.setLine(6,'')
        end
        lChanges += 1
      end
    end
    if param.records() > 4
      case lower(left(param.getLine(5))) ! bool pClip=false
      of '1' orof 'true'
        param.setLine(5,'st:clip')
        lChanges += 1
      of '0' orof 'false'
        if param.records() = 5           ! last parm?
          param.deleteLine(5)
        else
          param.setLine(5,'st:noClip')
        end
        lChanges += 1
      of '' orof 'st:noclip'
        if param.records() = 5           ! last parm?
          param.deleteLine(5)
          lChanges += 1
        end
      end
    end
    ! splitting on a SPACE with no quote args: clip is redundant too (GCR 2May2025)
    if param.records() > 4 and (param.getLine(1) = ''' ''' or param.getLine(1) = '''<32>''') and ~param.getLine(2)
      if lower(left(param.getLine(5))) = 'st:clip'
        if param.records() = 5
          param.deleteLine(5)
        else
          param.setLine(5,'st:noClip')
        end
        lChanges += 1
      end
    end
    if param.records() > 3
      case lower(left(param.getLine(4)))         ! bool pRemoveQuotes=false
!     of '1' orof 'true'                                           ! st:removeQuotes is PRIVATE-ST ONLY - see the header.
!       param.setLine(4,'st:removeQuotes')                         !   Restore these two lines when it ships publicly.
!       lChanges += 1
      of '0' orof 'false' orof ''
        if param.records() = 4                   ! last parm?
          lChanges += 1
          param.deleteLine(4)
        end
      end
    end
    if param.records() = 3 and ~param.getLine(3) ! blank last parm?
      lChanges += 1
      param.deleteLine(3)
    end
    if param.records() = 2 and ~param.getLine(2) ! blank last parm?
      lChanges += 1
      param.deleteLine(2)
    end

    if lChanges
      changes += lChanges
      param.join(',')
      self.tk.DeleteToks(startTok+1, endBracket-1)
      self.tk.InsertString(startTok+1, param)
      pLog.append('BUILTIN CheckSplits line ' & self.tk.MapLine(lineNo) & ': args ==> (' & param.getValue() & ')<13,10>')
      endBracket = startTok+1
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! BUILTIN CheckInLine - port of the vtxaDiff009 routine (GCR 30Oct2023), the twin of
! CheckSplits and missing for the same reason. st.inline()'s 5th to 8th parameters are
! numbers with names:
!     st.inline(x, 1, 0, 0, true, true, 1, true)
!  -> st.inline(x, 1, 0, 0, st:noCase, st:wholeLine, st:begins, st:clip)
!
! pWhere is a THREE-valued parameter, not a boolean: 0 st:anywhere, 1 st:begins,
! 2 st:ends. All nine equates this can emit were checked against the shipped
! StringTheory.inc before the port - unlike st:removeQuotes, they are all public.
!
! No default-deletion here: the original does not do it for inline, and a trailing 0 on
! pWhere means st:anywhere, which is worth SAYING rather than dropping.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinCheckInLine Procedure(StringTheory pLog)
startTok     long,auto
endBracket   long
lChanges     long,auto
lineNo       long,auto
changes      long
param        StringTheory
  code
  loop
    startTok = self.tk.FindSeq(',^ .,^inline, (', endBracket+1) ! look for .inline(
    if ~startTok then break.
    startTok += 2                                               ! FindSeq returns the '.' - move up to '('
    endBracket = self.tk.MatchLeftBracket('(',')',startTok)
    if ~endBracket then endBracket = startTok; cycle.           ! shouldn't happen
    !
    ! *** AND ASK WHAT THE RECEIVER IS. *** This finds its work by METHOD NAME alone, while
    ! every textual rule in the rule file proves the receiver through a typed metavar. So a
    ! same-named method on another class was rewritten by StringTheory's prototype:
    ! `ob.replace('a','')` on a CStringClass came back as `ob.removeByte(97)`, which either
    ! does not compile or, worse, compiles and means something else.
    !
    ! Refuses only what it can PROVE is another class. A receiver the symbol table cannot
    ! resolve still converts, exactly as before - requiring positive proof would be sound but
    ! would decline every unresolved receiver, and that is a change to what the tool DOES,
    ! not just to what it refuses. Registered as a decision rather than taken here.
    !
    ! *** IT MUST SIT AFTER endBracket ADVANCES. *** Cycling before that leaves FindSeq
    ! searching from the same place, so a refused site is found again on the next turn and
    ! the loop never ends. It hung the transform on the first non-StringTheory receiver.
    if self.RecvIsOtherClass(startTok - 3) then cycle.
    if self.SpanHasNL(startTok+1, endBracket-1) then cycle.     ! keep comments/continuations intact
    get(self.tk.tokens, startTok)
    lineNo = self.tk.tokens.lineNo

    self.tk.JoinToks(param, startTok+1, endBracket-1)
    param.split(',','''-(','''-)',,,,'-',st:nested)             ! no clip/left: preserve original spacing
    if param.records() > 8 then cycle.                          ! currently 8 parms

    lChanges = 0
    if param.records() = 8
      case lower(left(param.getLine(8)))                        ! long pClip
      of '1' orof 'true'
        param.setLine(8,'st:clip')
        lChanges += 1
      of '0' orof 'false'
        param.setLine(8,'st:noClip')
        lChanges += 1
      end
    end
    if param.records() > 6
      case lower(left(param.getLine(7)))                        ! long pWhere - THREE-valued
      of '0' orof 'false'
        param.setLine(7,'st:anywhere')
        lChanges += 1
      of '1' orof 'true'
        param.setLine(7,'st:begins')
        lChanges += 1
      of '2'
        param.setLine(7,'st:ends')
        lChanges += 1
      end
    end
    if param.records() > 5
      case lower(left(param.getLine(6))) ! long pWholeLine
      of '1' orof 'true'
        param.setLine(6,'st:wholeLine')
        lChanges += 1
      end
    end
    if param.records() > 4
      case lower(left(param.getLine(5))) ! long pNoCase
      of '1' orof 'true'
        param.setLine(5,'st:noCase')
        lChanges += 1
      end
    end

    if lChanges
      changes += lChanges
      param.join(',')
      self.tk.DeleteToks(startTok+1, endBracket-1)
      self.tk.InsertString(startTok+1, param)
      pLog.append('BUILTIN CheckInLine line ' & self.tk.MapLine(lineNo) & ': args ==> (' & param.getValue() & ')<13,10>')
      endBracket = startTok+1
    end
  end
  return changes

! BUILTIN CheckCat - port of the vtxaDiff009 routine (GCR ~2019, lengths
! Oct2021): st.cat(x) -> st.Append(x) when the argument is clearly a string
! expression (literal, &, slice, clip(, .getValue); st.cat('lit',n) ->
! st.Append('lit') with the literal truncated to n logical chars when n is
! shorter (escape-aware: '' << {{ <13,10> {n}).
! deviations: a non-numeric length argument is skipped (vtxaDiff read it
! as 0 and would truncate the literal to nothing); line-break skip as above.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinCheckCat Procedure(StringTheory pLog)
startTok     long,auto
endBracket   long
litLen       long,auto
wantLen      long,auto
lineNo       long,auto
changes      long
param        StringTheory
raw          StringTheory
  code
  loop
    startTok = self.tk.FindSeq(',^ .,^Cat, (', endBracket+1) ! look for .cat(
    if ~startTok then break.
    startTok += 2
    endBracket = self.tk.MatchLeftBracket('(',')',startTok)
    if ~endBracket then endBracket = startTok; cycle.
    !
    ! *** AND ASK WHAT THE RECEIVER IS. *** This finds its work by METHOD NAME alone, while
    ! every textual rule in the rule file proves the receiver through a typed metavar. So a
    ! same-named method on another class was rewritten by StringTheory's prototype:
    ! `ob.replace('a','')` on a CStringClass came back as `ob.removeByte(97)`, which either
    ! does not compile or, worse, compiles and means something else.
    !
    ! Refuses only what it can PROVE is another class. A receiver the symbol table cannot
    ! resolve still converts, exactly as before - requiring positive proof would be sound but
    ! would decline every unresolved receiver, and that is a change to what the tool DOES,
    ! not just to what it refuses. Registered as a decision rather than taken here.
    !
    ! *** IT MUST SIT AFTER endBracket ADVANCES. *** Cycling before that leaves FindSeq
    ! searching from the same place, so a refused site is found again on the next turn and
    ! the loop never ends. It hung the transform on the first non-StringTheory receiver.
    if self.RecvIsOtherClass(startTok - 3) then cycle.
    if self.SpanHasNL(startTok+1, endBracket-1) then cycle.
    get(self.tk.tokens, startTok)
    lineNo = self.tk.tokens.lineNo

    self.tk.JoinToks(param, startTok+1, endBracket-1)
    param.split(',','''-(','''-)',,st:clip,st:left,'-',st:nested)
    case param.records()
    of 1
      if param.containsByte(39) or param.containsByte(38) or param.containsByte(91) or | ! <single quote> '&' '['
         param.instring('clip(',,,,st:noCase)                                       or |
         param.instring('.getValue',,,,st:noCase)
        self.tk.SetTok(startTok-1, 'Append')
        pLog.append('BUILTIN CheckCat line ' & self.tk.MapLine(lineNo) & ': cat ==> Append<13,10>')
        changes += 1
      end
    of 2
      raw.setValue(param.getLine(1))
      litLen = self.rw.m.LitLength(raw.getValue())
      if litLen < 0 then cycle.         ! first arg not a quoted literal
      raw.setValue(param.getLine(2))
      if ~raw.IsAllDigits() then cycle. ! length arg not a plain integer - vtxaDiff would truncate to 0
      wantLen = raw.getValue()
      raw.setValue(param.getLine(1))
      changes += 1
      if wantLen < litLen
        self.LitTruncate(raw, wantLen)
        self.tk.SetTok(startTok+1, raw.valuePtr[1 : raw._DataEnd])
      end
      ! if wantLen >= litLen cat caps at the literal anyway: just drop the length
      self.tk.SetTok(startTok-1, 'Append')
      self.tk.DeleteToks(startTok+2, endBracket-1)
      pLog.append('BUILTIN CheckCat line ' & self.tk.MapLine(lineNo) & ': cat ==> Append(' & raw.getValue() & ')<13,10>')
      endBracket -= 2
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! BUILTIN UnusedVars - comment out declarations that are never referenced.
! Port of vtxaDiff009 CheckForUnusedVars + RemoveUnused, rebuilt on VitSymbols
! instead of GetData/vitWordStore (which are not in the workspace).
!
! One removal scan per invocation; if it commented anything it requests a
! rejoin/reparse (wantReparse) so the commented-out declarations - whole lines
! that are now '!' comments - disappear from the token stream. The engine
! fixpoint then re-invokes this builtin next pass, which is what drives the
! OVER-cascade (removing var A frees an OVER'd var B): B is only exposed as
! unused after A's line is gone. Running every pass (rather than once) also
! catches vars whose last use a later transform pass removes - matching
! vtxaDiff's final state, since it runs UnusedVars after its transforms settle.
!
! What is NOT removed (matching vtxaDiff): parameters and SELF (declTok is not
! a column-1 label), LIKE declarations (may use .property), structure blocks
! (GROUP/CLASS/QUEUE/... - VitSymbols never records these as symbols), and any
! name on the EXCLUDE list (procname/pn debugging vars by default).
! Multi-line (continuation) declarations: only the first physical line is
! commented, same limitation as vtxaDiff (its own TODO). Rare for simple vars.
! Perf: usage search is O(symbols x scope span) with early-exit on first use, as
! in vtxaDiff; the per-pass reparse shrinks the stream as decls are removed.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinUnusedVars Procedure(StringTheory pLog)
prefix  StringTheory
exclU   StringTheory ! ' NAME1 NAME2 ' upper, space-delimited
raw     StringTheory
s       long,auto
changes long,AUTO
hasCode byte,auto
  code
  if self.syms &= NULL then return 0.

  ! an INCLUDE fragment - a file with NO CODE statement anywhere,
  ! e.g. an equates file INCLUDEd into other programs - can reference nothing, so
  ! EVERY declaration looks unused. The whole-file premise fails exactly as it did
  ! for module data in AutoCheck: the real references live in the INCLUDING
  ! programs, invisible here. No CODE statement in the stream -> skip the builtin.
  ! A real CODE statement: the single word CODE (caseless)
  ! starting in COLUMN > 1, followed by EOL or a trailing comment. A column-1
  ! CODE is a LABEL (a declaration named code) and must NOT count; col-1 test
  ! mirrors VitSymbols.IsColOneLabel (firstOnLine + NULL strBefore = column 1).
  ! A trailing '! comment' rides the EOL token's strBefore, so next-token-EOL
  ! covers both allowed followers. Anything unrecognised = treat as code present
  ! (under-skip = current behaviour, the safe direction).
  hasCode = 0
  loop s = 1 to self.tk.records()
    get(self.tk.tokens, s)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL          or |
       upper(self.tk.tokens.tok) <> 'CODE' or |
       ~self.tk.tokens.firstOnLine         or |   ! mid-line word - not the statement
       self.tk.tokens.strBefore &= NULL       ! column 1 = a label/declaration named code
      cycle
    end
    get(self.tk.tokens, s + 1)
    if errorcode()
      hasCode = 1                             ! CODE as the last token of the file
      break
    end
    if self.tk.tokens.tok &= NULL
      hasCode = 1                             ! trailing strBefore-only token = EOF after CODE
      break
    end
    if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10
      hasCode = 1                             ! genuine EOL - single-word CODE statement
      break
    end
  end
  if ~hasCode
    pLog.append('BUILTIN UnusedVars: no CODE statement in file (include fragment) - skipped<13,10>')
    return 0
  end

  prefix.setValue('! #Removed as not used: ') ! defaults (vtxaDiff hardcodes these)
  exclU.setValue(' PROCNAME PN ')
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      case upper(self.rl.rules.bparmQ.name)
      of 'PREFIX'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)
          raw.unquote('''','''')
          prefix.setValue(raw)
        end
      of 'EXCLUDE'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)
          raw.upper()
          exclU.setValue(' ' & clip(raw.getValue()) & ' ')
        end
      end
    end
  end

  changes = self.RemoveUnusedPass(prefix, exclU, pLog)
  if changes
    self.wantReparse = true ! commented decls must vanish before the next scan; fixpoint drives the OVER cascade
    pLog.append('BUILTIN UnusedVars: ' & changes & ' commented this pass<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! One scan of the symbol table: comment out each unreferenced removable
! declaration. PrependStrBefore on the column-1 label turns the whole line into
! a comment (the preceding <10> ends the previous line; the label's strBefore is
! empty for a column-1 label, so the prefix lands at line start). Token
! positions are unchanged by PrependStrBefore, so declTok stays valid across the
! whole scan.
! ------------------------------------------------------------------------------------
VitEngine.RemoveUnusedPass Procedure(StringTheory pPrefix, StringTheory pExclU, StringTheory pLog)
uvScopeS long      ! the scope this answer belongs to
uvScopeE long
uvScopeC long      ! and the answer: OMIT/COMPILE present
s        long,auto
sc       long,auto
declTok  long,auto
declLine long,auto
startT   long,auto
endT     long,auto
nameU    STRING(vs:maxName)
changes  long
used     byte      ! UsedChk verdict
ux       long,auto
dotP     long,auto ! first '.' inside a merged dotted token
colP     long,auto ! ... and the first ':', which means the same thing
isMember byte,auto ! this file's module statement is MEMBER (module data is module-PRIVATE)
scKind   byte,auto ! kind of the candidate's scope, captured at the scopes GET
extVis   byte      ! ExtVisChk verdict - decl carries an externally-visible attribute
modKept  long      ! module-scope decls withheld because they are not module-private
extKept  long      ! module-scope decls withheld for EXPORT/EXTERNAL/DLL
txaKept  long      ! decls withheld: owning scope spans .txa embed points (strict embed rule)
condKept long      ! decls withheld: the owning scope holds an OMIT or COMPILE block
UseQ     QUEUE,PRE(uu) ! one token sweep -> keyed usage lookups (SymUsed rescanned the whole scope span PER SYMBOL)
nameU      string(vs:maxName)
pos        long
lineNo     long
         END
  code
  ! A field run once commented GlobalRequest / GlobalResponse / VCRRequest /
  ! SilentRunning out of a PROGRAM module. A whole-file usage scan is only
  ! sound for declarations that are PRIVATE to this file. Module-scope data is private
  ! ONLY in a MEMBER module - a PROGRAM's global section is visible to every MEMBER
  ! module of the program, and those references are invisible here. Same premise
  ! failure as with ,AUTO on static data and the include fragment; VitSymbols has a
  ! single vs:scModule kind covering BOTH sections, so the file's module statement is
  ! what decides. Detector mirrors the CODE spec: the single word MEMBER or PROGRAM
  ! (caseless) at COLUMN > 1 (firstOnLine + non-NULL strBefore; a column-1 word is a
  ! LABEL, i.e. a declaration named member/program). First one found wins - the module
  ! statement is the first statement of the file. Neither present (an include fragment
  ! that does have code) -> NOT member -> module scope withheld, the safe direction.
  ! Procedure/method/routine locals are unaffected in every file.
  isMember = 0
  loop ux = 1 to records(self.tk.tokens)
    get(self.tk.tokens, ux)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL       or |
       ~self.tk.tokens.firstOnLine      or |
       self.tk.tokens.strBefore &= NULL or |   ! column 1 = a label, not the module statement
       self.tk.tokens.type <> vt:reservedWord ! MEMBER/PROGRAM ARE reserved words ('r'), never 'b'=laBel; and TokenIsReservedWord already returns FALSE in column 1, so a label named member/program cannot reach here
      cycle
    end
    case upper(self.tk.tokens.tok)            ! no CLIP: tok is a &STRING sized to the token, and = ignores trailing blanks anyway (our own rule 533)
    of 'MEMBER'                               ! bare MEMBER and MEMBER('prog') both = module-private data
      isMember = 1
      break
    of 'PROGRAM'
      break                                   ! global section - externally visible, isMember stays 0
    end
  end

  free(UseQ)
  loop ux = 1 to records(self.tk.tokens)      ! collect every content token once
    get(self.tk.tokens, ux)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL or |
       size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10
      cycle
    end
    uu:nameU = upper(self.tk.tokens.tok)
    uu:pos    = ux
    uu:lineNo = self.tk.tokens.lineNo
    add(UseQ)
    ! the ParseText label-merge folds PROPERTY/FIELD references into ONE token
    ! (`st._DataEnd = 1` -> token 'st._DataEnd'; only a following '(' suppresses the
    ! merge - the 13Oct2021 NetMaps guard - so METHOD calls stay split). A var whose
    ! only references are property/field reads therefore had NO bare-name token and
    ! scanned as unused: UnusedVars commented `st  StringTheory` out of the demo while
    ! `st._DataEnd`/`st.valuePtr[1]` (rule 332's rewrite) still referenced it. Credit
    ! the merged token's ROOT segment as a usage of the base variable.
    ! *** AND THE COLON SPELLING EARNS THE SAME CREDIT. *** A ':' may replace a '.', so a
    ! variable whose ONLY reference is `ga:x = 1` had no bare-name token and no dotted one
    ! either - it scanned as unused and its declaration was commented out. That output does
    ! not compile. False credit merely keeps a declaration, so it is the safe direction.
    dotP = instring('.', uu:nameU, 1, 1)
    colP = instring(':', uu:nameU, 1, 1)
    if colP and (~dotP or colP < dotP) then dotP = colP.
    if dotP > 1
      uu:nameU = sub(uu:nameU, 1, dotP - 1)
      add(UseQ) ! ('123.45' adds '123' - harmless, no symbol is named that)
    end
  end
  sort(UseQ, +uu:nameU, +uu:pos)
  loop s = 1 to records(self.syms.syms)
    get(self.syms.syms, s)
    if errorcode() then break.
    if self.syms.syms.isLike or |   ! LIKE may reference .property - do not remove
       self.syms.syms.isField                                                                                ! PRE:name structure field - its decl line is layout, never removable
      cycle
    end
    nameU   = self.syms.syms.nameU
    declTok = self.syms.syms.declTok
    if nameU = 'SELF' then cycle.                                                                            ! synthetic receiver
    if ~self.syms.IsColOneLabel(declTok) then cycle.                                                         ! parameter / non-declaration - never remove
    if pExclU.findChars(' ' & clip(nameU) & ' ') then cycle.                                                 ! EXCLUDE list

    sc = self.syms.syms.scopeId
    get(self.syms.scopes, sc)
    if errorcode() then cycle.
    scKind = self.syms.scopes.kind                                                                           ! capture now - the scopes buffer is shared
    startT = self.syms.scopes.startTok
    endT   = self.syms.scopes.endTok
    if endT < startT then cycle.
    ! ONE ANSWER PER SCOPE, NOT PER SYMBOL. This loop walks SYMBOLS and a scope holds many of
    ! them, so asking here rescanned the same token range once for every variable declared in
    ! it - quadratic in a big file, and measurably so. The answer cannot differ between two
    ! symbols of one scope, so it is computed only when the scope changes.
    if startT <> uvScopeS or endT <> uvScopeE
      uvScopeS = startT
      uvScopeE = endT
      uvScopeC = self.ScopeIsConditional(startT, endT)
    end
    declLine = self.LineOfTok(declTok)

    do UsedChk                                                                                               ! keyed lookup replaces the per-symbol span scan
    if ~used
      ! unused IN THIS FILE is only a verdict for a declaration this file owns
      ! privately. Module scope qualifies only in a MEMBER module, and never when the
      ! declaration is part of a cross-module contract. Checked here (not before
      ! UsedChk) so the reported counts mean 'would have been commented', and so the
      ! decl-line walk runs only for the handful of candidates. Scope-kind based: a
      ! procedure local in a PROGRAM file is still removable.
      !
      ! THE CONDITIONAL-SCOPE REFUSAL IS ASKED HERE FOR THE SAME REASON, AND IT IS
      ! COUNTED. Asked above the usage check instead, as a bare `cycle`, it would withhold
      ! declarations and say nothing at all - the one withheld reason with no counter
      ! beside the three below, in a routine whose own comment says a silent skip reads
      ! exactly like 'nothing was unused'. It withholds TWELVE declarations in
      ! TestData\r108all.clw, and that is the whole difference between the 3 that fixture
      ! reports and the 15 a count taken ahead of the usage check would give. Asking after
      ! UsedChk costs one keyed lookup per candidate and makes the count mean what the
      ! other three mean.
      if uvScopeC
        condKept += 1
        cycle
      end
      if self.isTxa
        ! The .txa embed rule, STRICT: decidable only when the owning
        ! procedure/routine is contained wholly inside ONE embed - generated code
        ! between embed points can reference a declaration this scan cannot see.
        if ~self.ScopeFullyEmbedded(startT, endT)
          txaKept += 1
          cycle
        end
      end
      if scKind = vs:scModule
        if ~isMember
          modKept += 1
          cycle                                                                                              ! PROGRAM global / include fragment - other modules see it
        end
        do ExtVisChk
        if extVis
          extKept += 1
          cycle                                                                                              ! EXPORT/EXTERNAL/DLL - linked from other modules
        end
      end
      ! *** COMMENT THE WHOLE DECLARATION, NOT ITS FIRST PHYSICAL LINE. *** Prepending to the
      ! label alone left everything past a '|' uncommented, so a declaration continued onto a
      ! second line came back as a comment followed by an orphaned `DIM(3)` - output that does
      ! not compile. CommentOutSpan gives every line of the span its own marker, and it works
      ! by PrependStrBefore too, so token positions are unchanged and declTok stays valid.
      self.CommentOutSpan(declTok, self.DeclLastTok(declTok), pPrefix.getValue())
      changes += 1
      if changes <= 500
        pLog.append('BUILTIN UnusedVars line ' & self.tk.MapLine(declLine) & ': ' & clip(nameU) & '<13,10>') ! log in SOURCE coords; declLine itself stays in stream coords for UsedChk
      end
    end
  end
  ! say what was withheld - a silent skip reads exactly like 'nothing was unused'.
  if modKept
    pLog.append('BUILTIN UnusedVars: ' & modKept & ' module-scope declaration(s) kept - not a MEMBER module, other modules can see them<13,10>')
  end
  if extKept
    pLog.append('BUILTIN UnusedVars: ' & extKept & ' module-scope declaration(s) kept - EXPORT/EXTERNAL/DLL, linked from other modules<13,10>')
  end
  if txaKept
    pLog.append('BUILTIN UnusedVars: ' & txaKept & ' declaration(s) kept - their procedure/routine spans .txa embed points, and generated code between embeds is not visible here<13,10>')
  end
  if condKept
    pLog.append('BUILTIN UnusedVars: ' & condKept & ' declaration(s) kept - their scope holds an OMIT or COMPILE block, and a reference from inside one is invisible to this scan<13,10>')
  end
  return changes

! is this declaration externally visible from OTHER modules? Module data carrying
! EXPORT (published from this module) or EXTERNAL/DLL (defined elsewhere, referenced
! here) is part of a cross-module contract - the whole-file scan cannot see the other
! side, so it is never removable. Walks the LOGICAL declaration statement: a '|'
! continuation produces NO <10> token (the CRLF rides in the next token's strBefore -
! vitTokenize), so the walk must run to the EOL token, not to the next lineNo, or an
! attribute parked on line 2 is missed. Bare tokens only (type 'b'), so EXPORT inside
! NAME('..EXPORT..') is a quoted literal and does not count.
ExtVisChk routine
  data
ex long,auto
  code
  extVis = 0
  ex = declTok
  loop
    ex += 1
    get(self.tk.tokens, ex)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then break. ! end of the logical declaration
    if self.tk.tokens.type <> 'b' then cycle.
    case upper(self.tk.tokens.tok)                                               ! no CLIP: tok is a &STRING sized to the token, and = ignores trailing blanks anyway (our own rule 533)
    of 'EXPORT' orof 'EXTERNAL' orof 'DLL'
      extVis = 1
      break
    end
  end

UsedChk routine
  data
qx long,auto
  code
  ! same verdict as SymUsed: a token equal to nameU inside [startT,endT] on a line AFTER declLine.
  ! POSITION(queue) with a CLEARed buffer + the name set lower-bounds on the active
  ! (nameU,pos) sort order - first entry of the name's run, no walk-back needed.
  used = 0
  clear(UseQ)
  uu:nameU = upper(nameU)
  loop qx = position(UseQ) to records(UseQ)
    get(UseQ, qx)
    if uu:nameU <> upper(nameU) then break.
    if uu:pos < startT or uu:pos > endT or |
       uu:lineNo <= declLine
      cycle
    end
    used = 1
    exit
  end

! ------------------------------------------------------------------------------------
! Is pNameU referenced (as a whole token, caseless) anywhere in the scope span
! after its declaration line? Mirrors vtxaDiff findTokInLines(name, declLine+1,
! endLine): comments/string literals are trivia or distinct tokens, so a name
! that only appears in a comment or inside a literal counts as unused.
! ------------------------------------------------------------------------------------
VitEngine.SymUsed Procedure(STRING pNameU, LONG pStart, LONG pEnd, LONG pDeclLine)
i  long,auto
  code
  loop i = pStart to pEnd
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.lineNo <= pDeclLine or |   ! only usages after the declaration line
       self.tk.tokens.tok &= NULL
      cycle
    end
    if upper(self.tk.tokens.tok) = pNameU then return true.
  end
  return false

! ====================================================================================
! BUILTIN UnusedRoutines - comment out ROUTINEs never invoked.
! Sibling of UnusedVars.  A Clarion ROUTINE is LOCAL to its procedure and reachable
! only by `DO <name>` from within that procedure (incl. its sibling routines), so a
! routine with no `DO <name>` anywhere in its owning proc's token span is dead.  Comment
! out its whole span (label line through last body line) and request a rejoin/reparse:
! the `DO` calls inside a removed routine then vanish, so a routine reachable ONLY from a
! now-removed routine becomes unused next pass - the same fixpoint cascade UnusedVars
! uses for OVER'd vars.
! Conservative (under-reach): KEEP a routine if `DO <name>` appears ANYWHERE in the proc
! span, including its own body (self-recursion) - a pure-recursive routine never called
! externally is a rare edge and keeping it is always safe.  Also keeps EXCLUDE names.
! v1 = ROUTINEs only (vs:scRoutine).  Local-MAP procedures/methods are a different
!     scope kind + reference shape (open Q-F) - not handled here.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinUnusedRoutines Procedure(StringTheory pLog)
prefix  StringTheory
exclU   StringTheory
raw     StringTheory
s       long,auto
changes long,AUTO
  code
  if self.syms &= NULL then return 0.

  prefix.setValue('! #Removed unused routine: ')
  exclU.setValue(' ')
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      case upper(self.rl.rules.bparmQ.name)
      of 'PREFIX'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)
          raw.unquote('''','''')
          prefix.setValue(raw)
        end
      of 'EXCLUDE'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)
          raw.upper()
          exclU.setValue(' ' & clip(raw.getValue()) & ' ')
        end
      end
    end
  end

  changes = self.RemoveUnusedRoutinesPass(prefix, exclU, pLog)
  if changes
    self.wantReparse = true ! commented routines must vanish before the next scan; fixpoint drives the DO-cascade
    pLog.append('BUILTIN UnusedRoutines: ' & changes & ' routine(s) commented this pass<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! One scan of the scope table: comment out each unreferenced ROUTINE scope.  Position
! indices (startTok/endTok) are unchanged by PrependStrBefore, so every scope row stays
! valid across the whole scan even as earlier routines are commented.
! ------------------------------------------------------------------------------------
VitEngine.RemoveUnusedRoutinesPass Procedure(StringTheory pPrefix, StringTheory pExclU, StringTheory pLog)
r         long,auto
parentId  long,auto
startT    long,auto
endT      long,auto
pStart    long,auto
pEnd      long,auto
nameU     STRING(vs:maxName),AUTO
annot     byte,auto ! .txa: the routine already carries the note
j         long,auto
changes   long
  code
  loop r = 1 to records(self.syms.scopes)
    get(self.syms.scopes, r)
    if errorcode() then break.
    if self.syms.scopes.kind <> vs:scRoutine then cycle.
    startT   = self.syms.scopes.startTok
    endT     = self.syms.scopes.endTok
    parentId = self.syms.scopes.parentId
    if endT < startT then cycle.
    nameU = upper(self.tk.GetTok(startT)) ! routine label = scope startTok
    if ~nameU or |
       pExclU.findChars(' ' & clip(nameU) & ' ')
      cycle
    end

    if parentId
      get(self.syms.scopes, parentId)     ! owning proc/method span
      if errorcode() then cycle.
      pStart = self.syms.scopes.startTok
      pEnd   = self.syms.scopes.endTok
      if pEnd < pStart then cycle.
    else
      ! no recorded parent - a ROUTINE under a .txa's SYNTHESISED procedure header can
      ! arrive unparented, and cycling here silently exempted every such routine from
      ! the analysis. ROUTINEs are DO-only and a DO cannot cross a procedure, so the
      ! WHOLE stream is a safe SUPERSET range: it can only over-credit a reference
      ! (routine kept / not annotated), never convict one wrongly.
      pStart = 1
      pEnd   = self.tk.records()
    end

    if ~self.RoutineReferenced(nameU, pStart, pEnd)
      if self.isTxa
        ! The .txa embed rule: on a.txa NEVER comment a routine out - a
        ! template can DO a routine from generated code this file does not contain, so
        ! "no DO found" is not "unused" here. Annotate the header for the user to check
        ! instead. IDEMPOTENCE walks BACK over the EOL tokens above the label: the pass
        ! sets wantReparse, and after the reparse a full-line comment's text lives in
        ! the strBefore of ITS OWN <10> token, not the label's - testing only the label
        ! re-added the note every pass to maxPasses (the physical-line-start trap in its
        ! annotation flavour, and this fixture caught it at 20 notes deep).
        annot = 0
        j = startT + 1
        loop
          j -= 1
          if j < 1 then break.
          get(self.tk.tokens, j)
          if errorcode() then break.
          if not self.tk.tokens.strBefore &= NULL
            if instring('possibly not used', self.tk.tokens.strBefore, 1, 1) then annot = 1 ; break.
          end
          if j = startT                 or |   ! the label itself - keep walking up
             self.tk.tokens.tok &= NULL or |   ! trailing-trivia row
             size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 ! a blank/comment line's EOL
            cycle
          end
          break                                                            ! previous CONTENT token - the note cannot be above it
        end
        if ~annot
          self.tk.PrependStrBefore(startT, '! possibly not used - no DO in the embedded source, but template-generated code is not visible here. Check, then delete this line or the routine.<13,10>')
          changes += 1
          pLog.append('BUILTIN UnusedRoutines line ' & self.LogLineOf(startT) & ': ' & clip(nameU) & ' - possibly not used (annotated; a .txa never has the whole picture)<13,10>')
        end
      elsif self.CommentOutSpan(startT, endT, pPrefix.getValue())
        changes += 1
        pLog.append('BUILTIN UnusedRoutines line ' & self.LogLineOf(startT) & ': ' & clip(nameU) & '<13,10>')
      end
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! `DO <pNameU>` present anywhere in [pProcStart, pProcEnd]?  (whole-token DO immediately
! followed by the routine name, caseless; <10> EOL tokens skipped so `DO`/name split
! across a line still matches).  ROUTINEs are DO-only, so this is a complete usage test.
! ------------------------------------------------------------------------------------
VitEngine.RoutineReferenced Procedure(STRING pNameU, LONG pProcStart, LONG pProcEnd)
i      long,auto
prevU  string(vs:maxName),AUTO
tU     string(vs:maxName),auto
  code
  prevU = ''
  loop i = pProcStart to pProcEnd
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL or |
       size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 ! EOL trivia
      cycle
    end
    tU = upper(self.tk.tokens.tok)
    if tU = pNameU and prevU = 'DO' then return true.
    prevU = tU
  end
  return false

! ------------------------------------------------------------------------------------
! Comment out a whole token span by '!'-prefixing the first-on-line token of every line
! it covers.  Each content line's first token carries only that line's indent in its
! strBefore (physical newlines are separate <10> tokens), so the '!' lands at line start.
! Blank / comment-only lines have no first-on-line CONTENT token (their sole token is the
! <10>), so are left as-is (already inert).  pHeader replaces '!' on the first line.
! PrependStrBefore leaves token positions unchanged -> caller indices stay valid.
! Returns lines commented (>=1 for a real routine).
! ABSORBED trivia lines: a token's strBefore can hold WHOLE PHYSICAL LINES with no
! tokens of their own (an OMIT block's prose, swallowed text), which the per-line '!'
! can therefore never reach - CommentTriviaLines gives each of those its own '!'
! skipping blank and already-comment lines. CommentLineStart's
! after-the-last-<10> insert covers the token's own line, so between them every
! physical line of the span comes back inert and visibly commented.
! ------------------------------------------------------------------------------------
VitEngine.CommentOutSpan Procedure(LONG pStartTok, LONG pEndTok, STRING pHeader)
i      long,auto
lines  long
  code
  loop i = pStartTok to pEndTok
    get(self.tk.tokens, i)
    if errorcode() then break.
    if i > pStartTok then self.CommentTriviaLines(i). ! pStartTok's strBefore is the gap ABOVE the span - not ours
    if ~self.tk.tokens.firstOnLine or |
       self.tk.tokens.tok &= NULL  or |
       size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 ! EOL token - not real content
      cycle
    end
    if i = pStartTok
      self.CommentLineStart(i, pHeader)                              ! physical-line-start insert (continuation/OMIT text lives in strBefore)
    else
      self.CommentLineStart(i, '!')
    end
    lines += 1
  end
  return lines

! ------------------------------------------------------------------------------------
! Give every COMPLETE physical line inside pTok's strBefore its own '!' - the lines
! that exist only as absorbed trivia and so can never be reached by per-token
! commenting. A segment is a complete line when a <10> inside this strBefore
! TERMINATES it; the FINAL segment (after the last <10>) is the token's own line
! start and belongs to CommentLineStart. The FIRST segment (before any <10>) is
! banged only when the PREVIOUS token is an EOL token - then it genuinely starts a
! physical line (the absorbed-OMIT shape: the directive line itself heads the blob,
! and banging it dissolves the region so every line inside is a plain comment on the
! next parse). When the previous token is mid-line content, the first segment is the
! TAIL of the line above and a '!' there kills live code. Blank segments and segments
! already leading with '!' are skipped: comments stay single-banged, blanks blank.
! ------------------------------------------------------------------------------------
VitEngine.CommentTriviaLines Procedure(LONG pTok)
sb      StringTheory
out     StringTheory
k       long,auto
j       long,auto
lastN   long,auto
need    byte,auto
prevEol byte
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return.
  if self.tk.tokens.strBefore &= NULL then return.
  sb.setValue(self.tk.tokens.strBefore)
  lastN = 0
  loop k = 1 to sb._DataEnd
    if val(sb.valuePtr[k]) = 10 then lastN = k.
  end
  if ~lastN then return.                    ! no line-break: nothing complete lives inside
  if pTok > 1
    get(self.tk.tokens, pTok - 1)
    if ~errorcode() and not self.tk.tokens.tok &= NULL
      if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then prevEol = 1.
    end
  end
  out.free()
  k = 1
  do SegNeed                                ! the first segment [1..first <10>)
  if prevEol and need then out.append('!'). !   is a line start only after an EOL token
  loop while k <= sb._DataEnd
    if val(sb.valuePtr[k]) <> 10
      out.append(sb.valuePtr[k])
      k += 1
      cycle
    end
    out.append(sb.valuePtr[k])              ! the <10> itself
    k += 1
    if k > lastN then break.                ! final segment - the token's own line start
    do SegNeed
    if need then out.append('!').
  end
  if k <= sb._DataEnd then out.append(sb.valuePtr[k : sb._DataEnd]).
  self.tk.SetStrBefore(pTok, out.getValue())

SegNeed routine                             ! does the segment starting at k earn a '!'?
  need = 0                                  ! blank or already-comment: no
  loop j = k to sb._DataEnd
    case val(sb.valuePtr[j])
    of 10                                   ! the segment ends
      break
    of 32 orof 9 orof 13                    ! space, tab, the CR of a CRLF - not content
      cycle
    end
    need = choose(sb.valuePtr[j] <> '!')
    break
  end

! ====================================================================================
! BUILTIN UnreachableCode - comment out code that can never execute:
! statements after an UNCONDITIONAL transfer of control (RETURN/EXIT/BREAK/CYCLE/GOTO)
! up to the next control-flow rejoin point.  Uses the same tokenizer level-mark walk as
! AutoCheck.  Comment-out (never delete), wantReparse so the commented dead lines vanish
! and a re-scan converges.
!
! Model - walk each proc/method main code + each routine body, tracking block-nesting
! DEPTH via level marks and a `dead` flag with the depth `deadDepth` at which the transfer
! occurred.  A whole-line transfer keyword sets dead for SUBSEQUENT lines.  `dead` clears
! (control can re-enter) at: a col-1 label (GOTO/jump target); a sibling branch of the
! transfer's own block (ELSE/ELSIF/OF/OROF, or a '/' level, at depth = deadDepth); the
! close of the transfer's enclosing block ('-' dropping depth below deadDepth).  A
! top-level transfer (deadDepth 0) kills everything until a label or the scope end.
!
! Safety (a wrong comment = deleting LIVE code): heavily under-reach.  `if x then return`
! is CONDITIONAL - not detected (stmtKw is IF, not RETURN).  A level underflow bails the
! scope (tracking lost -> stop).  Any rejoin clears dead.  We only ever comment lines that
! strictly follow a whole-line transfer within its own branch.
! Edges: a MID-LINE transfer is never detected (stmtKw is the
!     line's first word, so `case n ; of 1 ; x = 1 ; return ; ...` starts no deadness -
!     under-reach, safe), and a DEAD line whose tail holds a rejoin - `x = 1 ; of 2 ;
!     x = 2`, or `y = 1 ; end` closing the enclosing block - is REFUSED whole rather
!     than commented, because '!' comments to end of line and would take the live arm
!     or the structure with it (TailRejoinChk; pinned in the fixture).
! ------------------------------------------------------------------------------------
VitEngine.BuiltinUnreachableCode Procedure(StringTheory pLog)
prefix  StringTheory
raw     StringTheory
s       long,auto
changes long,AUTO
  code
  if self.syms &= NULL then return 0.

  prefix.setValue('! #Unreachable: ')
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      if upper(self.rl.rules.bparmQ.name) = 'PREFIX' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.unquote('''','''')
        prefix.setValue(raw)
      end
    end
  end

  changes = self.RemoveUnreachablePass(prefix, pLog)
  if changes
    self.wantReparse = true ! commented dead lines must vanish before the next scan
    pLog.append('BUILTIN UnreachableCode: ' & changes & ' line(s) commented this pass<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! Determine each executable range and walk it.  Proc/method: [CODE+1 .. before-first-
! child-routine].  Routine: [CODE+1 .. end] or, if no CODE keyword, [first line after the
! ROUTINE header .. end].  strBefore-only edits leave scope indices valid across the scan.
! ------------------------------------------------------------------------------------
VitEngine.RemoveUnreachablePass Procedure(StringTheory pPrefix, StringTheory pLog)
r        long,auto
rr       long,auto
kind     long,auto
scId     long,auto
startT   long,auto
endT     long,auto
mainEnd  long,auto
codeT    long,auto
exStart  long,auto
condKept long                                  ! scopes not examined - they hold an OMIT or COMPILE block
changes  long
  code
  loop r = 1 to records(self.syms.scopes)
    get(self.syms.scopes, r)
    if errorcode() then break.
    kind   = self.syms.scopes.kind
    scId   = self.syms.scopes.scopeId
    startT = self.syms.scopes.startTok
    endT   = self.syms.scopes.endTok
    if endT < startT then cycle.
    if self.ScopeIsConditional(startT, endT)   ! OMIT/COMPILE - see the banner on it
      condKept += 1                            !   and SAY SO at the end, like its two siblings
      cycle
    end

    if kind = vs:scProc or kind = vs:scMethod
      mainEnd = endT
      loop rr = 1 to records(self.syms.scopes) ! stop main code before the first child routine
        get(self.syms.scopes, rr)
        if self.syms.scopes.kind = vs:scRoutine and self.syms.scopes.parentId = scId
          if self.syms.scopes.startTok > startT and self.syms.scopes.startTok - 1 < mainEnd
            mainEnd = self.syms.scopes.startTok - 1
          end
        end
      end
      codeT = self.CodeTokOfScope(startT, mainEnd)
      if codeT
        if self.LevelSpanBalanced(codeT + 1, mainEnd)
          changes += self.WalkUnreachable(codeT + 1, mainEnd, pPrefix, pLog)
        else
          pLog.append('BUILTIN UnreachableCode: scope at line ' & self.LogLineOf(startT) & ' is level-unbalanced - NOT examined (refusal over restructuring, #1)<13,10>')
        end
      end
    elsif kind = vs:scRoutine
      codeT = self.CodeTokOfScope(startT, endT)
      if codeT
        exStart = codeT + 1
      else
        exStart = self.FirstTokAfterLine(startT) ! simple routine (no DATA/CODE) - body starts next line
      end
      if exStart
        if self.LevelSpanBalanced(exStart, endT)
          changes += self.WalkUnreachable(exStart, endT, pPrefix, pLog)
        else
          pLog.append('BUILTIN UnreachableCode: routine at line ' & self.LogLineOf(startT) & ' is level-unbalanced - NOT examined (refusal over restructuring, #1)<13,10>')
        end
      end
    end
  end
  ! SAY WHAT WAS NOT EXAMINED - this walks SCOPES, so the unit is scopes, not declarations.
  ! Third of the three passes that refused a conditional scope and said nothing about it.
  if condKept
    pLog.append('BUILTIN UnreachableCode: ' & condKept |
       & ' scope(s) NOT examined - each holds an OMIT or COMPILE block, so a line reached only from a compiled-out branch would read as unreachable<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! Net level balance of a token span: +1 per '+', -1 per '-' OR an unmarked vt:end
! (the inline-dot idiom). Returns 0 when opens outlive the span - the corruption
! case: a walk over it inflates its depth and never rejoins (#1, #17). Underflow is
! NOT a refusal: a range often ends inside its enclosing block, and every walk
! already bails safely on depth < 0.
! ------------------------------------------------------------------------------------
VitEngine.LevelSpanBalanced Procedure(LONG pS, LONG pE)
d  long
i  long,auto
  code
  loop i = pS to pE
    get(self.tk.tokens, i)
    if errorcode() then break.
    case val(self.tk.tokens.level)
    of 43
      d += 1
    of 45
      d -= 1
    else
      if self.tk.tokens.type = vt:end and self.tk.tokens.level <> '/' then d -= 1.
    end
  end
  return choose(d <= 0)

! ------------------------------------------------------------------------------------
! The dead-state walk over one contiguous code range.  Returns lines commented.
! ------------------------------------------------------------------------------------
VitEngine.WalkUnreachable Procedure(LONG pExecStart, LONG pExecEnd, StringTheory pPrefix, StringTheory pLog)
i         long,auto
fol       byte,auto
lvl       string(1),auto
tty       string(1),auto    ! token TYPE, captured with lvl: the unmarked-vt:end belt reads it (#1)
isEol     byte,auto
txt       string(vs:maxName),auto
tU        string(vs:maxName)
stmtKw    string(vs:maxName)
depth     long
dead      byte
deadDepth long
pendHead  byte
contLine  byte,auto    ! this token opens a '|' CONTINUATION of the line above
prevCmt   byte         !   ... and that line was commented out, so this one must be too
tailRj    byte         ! TailRejoinChk verdict: the dead line's tail holds a rejoin
lines     long
execStk   BYTE,DIM(64) ! execStk[depth]=1 when the opener at that depth is EXECUTE
  code
  if pExecStart < 1 or pExecEnd < pExecStart then return 0.
  loop i = pExecStart to pExecEnd
    get(self.tk.tokens, i)
    if errorcode() then break.
    fol = self.tk.tokens.firstOnLine
    lvl = self.tk.tokens.level
    tty = self.tk.tokens.type
    ! A '|' CONTINUATION LINE IS NOT A LINE OF ITS OWN, and reading it as one
    ! produced source that DOES NOT COMPILE. The tokenizer marks every continuation token
    ! firstOnLine=1 with the bar and the CRLF in its strBefore (the same trap the hoist
    ! builtin guards at TryEndHoist), so a RETURN whose expression runs over four physical
    ! lines looked like a transfer followed by three dead lines - and this pass commented
    ! the other three out, truncating the expression mid-air:
    !     Return( clip(choose(~L:Days, '', ...) & |
    !   ! #Unreachable:      choose(~L:Hours,'', ...) & |
    ! Clarion rejects that, and the tool had no way to know: VitTimer.clw and three sites
    ! in VitEngine.clw, found by BUILDING extreme-transformed source (bootstrap.bat) -
    ! which is why that check exists and why no text-level gate could have caught it.
    ! A continuation belongs to the statement above it, so it inherits that line's fate:
    ! commented only if the line it continues was commented, and never able to START a
    ! dead region or be read as a transfer keyword of its own.
    contLine = 0
    if fol and not self.tk.tokens.strBefore &= NULL
      if self.TriviaHasContinuation(self.tk.tokens.strBefore) then contLine = 1.
    end
    if self.tk.tokens.tok &= NULL
      txt   = '' ; isEol = 0
    else
      txt = self.tk.tokens.tok
      isEol = choose(size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10)
    end
    tU = upper(txt)
    if fol and txt and ~isEol then stmtKw = tU.

    ! ---- a.txa EMBED BOUNDARY clears the dead region (the embed rule:
    !      a transfer's deadness must not span embed points - the template-generated
    !      code between them is invisible here and can rejoin flow). The template lines
    !      between embeds survive the wrap as !<250>-marked comments, whose text lands
    !      in the TRIVIA of the tokens that follow them - including the EOL tokens - so
    !      the test runs on every token while dead, not only first-on-line ones. The
    !      byte is 250 SPECIFICALLY: 251 is the shift marker trailing every embedded
    !      code line and must not count. A mid-block PRIORITY group is 250-marked too,
    !      and that is correct - a different priority is a different injection point. ----
    if dead and self.isTxa
      if not self.tk.tokens.strBefore &= NULL
        if instring('<250>', self.tk.tokens.strBefore, 1, 1) then dead = 0.
      end
    end

    ! ---- control-flow REJOIN clears the dead region (before commenting this line) ----
    if fol and dead
      if self.syms.IsColOneLabel(i)                 ! GOTO/jump target
        dead = 0
      elsif depth = deadDepth and (stmtKw = 'OF' or stmtKw = 'OROF' or stmtKw = 'ELSE' or stmtKw = 'ELSIF')
        dead = 0                                    ! sibling branch of the transfer's own block
      end
    end

    ! ---- block nesting ----
    case val(lvl)
    of 43                                           ! '+'
      depth += 1
      if depth >= 1 and depth <= 64
        execStk[depth] = choose(stmtKw = 'EXECUTE') ! is the opener at this depth an EXECUTE?
      end
    of 47                                           ! '/'
      if dead and depth = deadDepth then dead = 0.  ! else/elsif/of separator (level-marked)
    of 45                                           ! '-'
      depth -= 1
      if depth < 0
        dead = 0 ; break                            ! level underflow - tracking lost, bail (safe)
      end
      if dead and depth < deadDepth then dead = 0.  ! transfer's enclosing block closed
    end
    if tty = vt:end and lvl <> '-' and lvl <> '+' and lvl <> '/'
      depth -= 1                                    ! the inline-dot idiom: a '.' terminator retyped vt:end but
      if depth < 0                                  !   carrying NO '-' mark. Every sibling walk wears this belt
        dead = 0 ; break                            !   (TailRejoinChk here, SmDepthWalk, KrClose...) - this one
      end                                           !   lacked it, so depth stayed inflated and the rejoin at the
      if dead and depth < deadDepth then dead = 0.  !   enclosing ELSE/END never fired: LIVE code was commented (#1)
    end

    ! ---- comment a dead content line - unless its TAIL holds a rejoin. The
    !      counterexample: '!' comments to END OF LINE, so a dead line
    !      spelled `x = 1 ; of 2 ; x = 2` would take the LIVE `of 2` arm with it, and
    !      `y = 1 ; end` would take the enclosing block's END. The comment decision
    !      happens HERE, before the loop reaches the tail's '/' and '-' tokens, so the
    !      tail is pre-scanned with a line-local depth (seeded 1 when this line's own
    !      first token opens a block, so a fully-dead `if p then p = 9.` still
    !      comments): an arm separator beyond the line's own opens, or a close that
    !      drops below them - inline dots included, they are retyped vt:end and may
    !      carry no '-' - REFUSES the line whole and deadness ends there. Refusal over
    !      restructuring, as everywhere else: the alternative is inserting a line
    !      break, and this tool does not reshape a line to make its own edit fit. ----
    if fol and dead and txt and ~isEol and contLine
      ! a continuation of the line above: it is not a statement, so it is not a candidate
      ! and not a rejoin. Comment it ONLY if the line it continues was commented, or half
      ! a dead statement is left live.
      if prevCmt
        self.CommentLineStart(i, '!')
        lines += 1
      end
    elsif fol and dead and txt and ~isEol
      do TailRejoinChk
      if tailRj
        dead = 0
        prevCmt = 0
      elsif pendHead
        prevCmt = 1
        self.CommentLineStart(i, pPrefix.getValue())              ! at the PHYSICAL line start - a plain prepend lands after a continuation '|' (prev line) leaving this line LIVE
        pendHead = 0
        lines += 1
      else
        prevCmt = 1
        self.CommentLineStart(i, '!')
        lines += 1
      end
    elsif fol and txt and ~isEol and ~contLine
      prevCmt = 0                                                 ! a live statement line - its continuations stay live
    end

    ! ---- a whole-line unconditional transfer makes SUBSEQUENT lines dead ----
    if fol and ~isEol and ~contLine and self.IsTransferKw(stmtKw) ! ~contLine: a continuation is not a statement of its own
      if depth >= 1 and depth <= 64 and execStk[depth] = 1        ! a transfer ARM of an EXECUTE - the following arms are LIVE alternatives, not dead code
        ! (skip)
      else
        dead = 1 ; deadDepth = depth ; pendHead = 1
      end
    end
  end
  return lines

! ---- does the CURRENT line's tail (tokens after i, to its EOL) rejoin control flow
!      beyond the line's own opens? See the refusal comment at the call site. ----
TailRejoinChk routine
  data
tt   long,auto
ttd  long,auto
tlv  string(1),auto
tty  string(1),auto
ttU  string(vs:maxName),auto
  code
  tailRj = 0
  ttd = choose(lvl = '+')                                                        ! this line's OWN opener - its close in the tail is line-local
  tt = i
  loop
    tt += 1
    get(self.tk.tokens, tt)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then break. ! the line ends
    tlv = self.tk.tokens.level
    tty = self.tk.tokens.type
    ttU = upper(self.tk.tokens.tok)
    if tlv = '+'
      ttd += 1
    elsif tlv = '/'
      if ~ttd then tailRj = 1 ; break.                                           ! arm separator beyond the line's own opens
    elsif tlv = '-' or (tty = vt:end and tlv <> '+')                             ! inline '.' terminators are retyped vt:end, often with no '-'
      ttd -= 1
      if ttd < 0 then tailRj = 1 ; break.                                        ! closes the ENCLOSING block
    elsif ~ttd and (ttU = 'OF' or ttU = 'OROF' or ttU = 'ELSE' or ttU = 'ELSIF')
      tailRj = 1 ; break                                                         ! belt: an arm word the level pass left unmarked
    end
  end

! ------------------------------------------------------------------------------------
VitEngine.IsTransferKw Procedure(STRING pKwU)
  code
  case pKwU
  of 'RETURN' orof 'EXIT' orof 'BREAK' orof 'CYCLE' orof 'GOTO'
    return 1
  end
  return 0

! ------------------------------------------------------------------------------------
VitEngine.FirstTokAfterLine Procedure(LONG pTok)
i   long,auto
ln  long,auto
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return 0.
  ln = self.tk.tokens.lineNo
  i  = pTok
  loop
    i += 1
    get(self.tk.tokens, i)
    if errorcode() then return 0.
    if self.tk.tokens.lineNo > ln then return i.
  end

! ====================================================================================
! BUILTIN UnusedAssignments - "unnecessary code": a variable set up
! then never subsequently used.  v1 = WRITE-ONLY locals: a simple scalar local that is
! ASSIGNED (>=1 whole-var write) but READ nowhere in its scope -> every such assignment is
! a dead store.  Comment each, wantReparse; the var then has no references so UnusedVars
! (if also enabled) removes the declaration next - a clean two-builtin cascade.
!
! Safety (a wrong comment could drop a side effect): heavily under-reach.
!   * eligibility reuses AutoEligible (simple scalar local, not param/ref/like/over/dim,
!     NOT touched in any routine) - so scanning the scope code is a complete usage test.
!   * ANY non-assignment occurrence (RHS, condition, arg, x.field, x[i], even a same-named
!     member of another object) counts as a READ -> the var is kept.  0 reads is required.
!   * only STRICT single-token, no-'(' , line-ending RHS is commented (RhsSingleSafe): `a = 5`,
!     `c = ''`, `x = y` - never a call `d = f()` (side effect) nor a compound/continued RHS.
!   * v1 is variable-level (write-only), NOT per-store liveness (`x=1; ...read x...; x=2` -
!     the x=1 dead store is NOT caught here; that is the flow-sensitive follow-on).
! ------------------------------------------------------------------------------------
VitEngine.BuiltinUnusedAssignments Procedure(StringTheory pLog)
prefix  StringTheory
raw     StringTheory
s       long,auto
changes long,AUTO
  code
  if self.syms &= NULL then return 0.
  prefix.setValue('! #Unused assignment (never read): ')
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      if upper(self.rl.rules.bparmQ.name) = 'PREFIX' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.unquote('''','''')
        prefix.setValue(raw)
      end
    end
  end
  changes = self.RemoveDeadStoresPass(prefix, pLog)
  if changes
    self.wantReparse = true
    pLog.append('BUILTIN UnusedAssignments: ' & changes & ' assignment(s) commented this pass<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! Per eligible local: classify every occurrence in the scope code as a whole-var WRITE
! (fol + next '=') or a READ (anything else).  0 reads + >=1 write -> comment the writes.
! ------------------------------------------------------------------------------------
VitEngine.RemoveDeadStoresPass Procedure(StringTheory pPrefix, StringTheory pLog)
uvScopeS long ! the scope this answer belongs to
uvScopeE long
uvScopeC long ! and the answer: OMIT/COMPILE present
condKept long ! symbols not examined because that answer was yes
s        long,auto
sc       long,auto
startT   long,auto
endT     long,auto
codeT    long,auto
declTok  long,auto
allowEnd byte,auto
i        long,auto
w        long,auto
nameU    string(vs:maxName),auto
nmU      string(vs:maxName),auto
prevU    string(vs:maxName),auto
nextU    string(vs:maxName),auto
fol      byte,auto
contLn   byte,auto
reads    long,auto
changes  long
WriteQ QUEUE,PRE(wr)
wtok      long
       END
  code
  loop s = 1 to records(self.syms.syms)
    get(self.syms.syms, s)
    if errorcode() then break.
    ! A PERSISTENT LOCAL CAN BE UNUSED LIKE ANY OTHER. AutoEligible is shared with AutoCheck,
    ! where refusing STATIC and THREAD is right - ,AUTO is uninitialised stack memory. This
    ! builtin asks whether anything READS the variable, and a procedure-local is visible only
    ! inside that procedure whatever its storage, so the scope scan answers it completely. The 1
    ! says which question is being asked. It also makes the STATIC/THREAD arm below reachable:
    ! `allowEnd` has always known that a persistent local's LAST store may be read on the next
    ! call, and nothing persistent ever got this far to find out.
    if ~self.AutoEligible(s, 1) then cycle.
    nameU   = self.syms.syms.nameU
    declTok = self.syms.syms.declTok
    sc      = self.syms.syms.scopeId
    get(self.syms.scopes, sc)
    if errorcode() then cycle.
    startT = self.syms.scopes.startTok
    endT   = self.syms.scopes.endTok
    codeT  = self.CodeTokOfScope(startT, endT)
    if ~codeT then cycle.
    ! ONE ANSWER PER SCOPE, NOT PER SYMBOL. This loop walks SYMBOLS and a scope holds many of
    ! them, so asking here rescanned the same token range once for every variable declared in
    ! it - quadratic in a big file, and measurably so. The answer cannot differ between two
    ! symbols of one scope, so it is computed only when the scope changes.
    if startT <> uvScopeS or endT <> uvScopeE
      uvScopeS = startT
      uvScopeE = endT
      uvScopeC = self.ScopeIsConditional(startT, endT)
    end
    if uvScopeC
      condKept += 1
      cycle
    end

    free(WriteQ)
    reads = 0
    loop i = codeT + 1 to endT
      get(self.tk.tokens, i)
      if errorcode() then break.
      if self.tk.tokens.type <> 'b' or |
         self.tk.tokens.tok &= NULL
        cycle
      end
      nmU = upper(self.tk.tokens.tok)
      if nmU <> nameU then cycle.
      fol = self.tk.tokens.firstOnLine                          ! capture before prev/next gets clobber the buffer
      contLn = 0                                                ! the same continuation guard AutoVerdict carries.
      if not self.tk.tokens.strBefore &= NULL                   !   firstOnLine is ALSO 1 on a '|' continuation line (the CRLF
        if self.TriviaHasContinuation(self.tk.tokens.strBefore) !   lives in strBefore), so `IF a = 1 AND |` / `x = 5` reads as
          contLn = 1                                            !   a write and the REAL store gets commented out. Wrong output.
        end
      end
      prevU = '' ; nextU = ''
      if i > codeT + 1
        get(self.tk.tokens, i - 1)
        if not self.tk.tokens.tok &= NULL then prevU = upper(self.tk.tokens.tok).
      end
      get(self.tk.tokens, i + 1)
      if ~errorcode() and not self.tk.tokens.tok &= NULL then nextU = upper(self.tk.tokens.tok).
      if fol and ~contLn and nextU = '=' and prevU <> '.'
        clear(WriteQ) ; wr:wtok = i ; add(WriteQ)               ! whole-var assignment target = write
      else
        reads += 1                                              ! any other occurrence = a use (conservative)
      end
    end

    if ~reads
      if records(WriteQ) > 0                                    ! v1: write-only var - every store is dead
        loop w = 1 to records(WriteQ)
          get(WriteQ, w)
          if self.RhsSingleSafe(wr:wtok)
            self.CommentLineStart(wr:wtok, pPrefix.getValue())  ! at the PHYSICAL line start. A raw
                                                                !   prepend goes in front of ALL the trivia, so a
                                                                !   preceding full-line comment (or a continuation)
                                                                !   puts the '!' on the PREVIOUS line and leaves this
                                                                !   one live - counted as a change, nothing commented,
                                                                !   and the next pass prepends another to maxPasses.
            changes += 1
            if changes <= 500
              pLog.append('BUILTIN UnusedAssignments line ' & self.LogLineOf(wr:wtok) & ': ' & clip(nameU) & '<13,10>')
            end
          end
        end
      end
    else                                                        ! v2: var IS read somewhere - hunt per-store dead stores
      ! scope-end deadness assumes the local dies on return; a STATIC/THREAD local persists,
      ! so its FINAL store may be read on a later call -> disallow the scope-end case for those
      ! (the overwrite-before-read case stays valid: the value is clobbered within this call).
      allowEnd = choose(~(self.DeclHasAttr(declTok, 'STATIC') or self.DeclHasAttr(declTok, 'THREAD')))
      changes += self.PerStoreDeadStores(codeT, endT, nameU, allowEnd, pPrefix, pLog)
    end
  end
  ! SAY WHAT WAS NOT EXAMINED. The sibling reason in UnusedVars is worded 'kept', because
  ! there the refusal is asked AFTER the usage check and so means 'would have been
  ! commented'. Here it is asked BEFORE the write/read scan - deliberately, that scan is the
  ! expensive part - so all this can honestly claim is that the symbol was never looked at.
  ! Both say so, because a silent skip reads exactly like 'nothing was dead'.
  if condKept
    pLog.append('BUILTIN UnusedAssignments: ' & condKept & ' declaration(s) NOT examined - their scope holds an OMIT or COMPILE block, so a read from inside one is invisible to this scan<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! v2 per-store liveness (overwritten-before-read).  For a var that IS read somewhere
! (so v1's write-only test skipped it), an INDIVIDUAL store `x = <safe>` is still dead if
! its value is never read before x is overwritten or the scope ends.  Flow-sensitive but
! deliberately straight-line only: ANY control structure (level +/'/'/'- mark) or jump
! label between a store and its overwrite/scope-end clears the pending store (we cannot
! prove deadness across branches) -> under-reach, never a wrong comment.
!
! Statement walk (mirrors WalkUnreachable's firstOnLine segmentation):
!   pendW = token of a pending commentable store to x whose value has not yet been read.
!   per statement, in order:
!     * has a control-flow level mark OR is a jump label  -> pendW := 0 (bail across flow)
!     * whole-var write `x = RHS`, RHS does NOT read x     -> the PREVIOUS pendW is dead
!         (overwritten before read) => comment it; pendW := this store (iff RhsSingleSafe)
!     * whole-var write whose RHS reads x (`x = x + 1`)    -> old value used => pendW := 0
!     * any other read of x                                -> pendW := 0 (value is live)
!     * statement doesn't mention x                        -> pendW unchanged
!   at scope end a surviving pendW is a store never read before end -> comment it.
! A store is only ever set into pendW when RhsSingleSafe, so every commented store is the
! same single-token side-effect-free form v1 touches (never a call / compound / continuation).
! Continuation lines (fol set, logically one statement) can only over-split -> add a spurious
! read/bail, never suppress one -> safe.
! ------------------------------------------------------------------------------------
VitEngine.PerStoreDeadStores Procedure(LONG pCodeT, LONG pEndT, STRING pNameU, BYTE pAllowEnd, StringTheory pPrefix, StringTheory pLog)
i        long,auto
fol      byte,auto
contLn   byte,auto
lvl      string(1)
isEol    byte,auto
ty       string(1)
txt      string(vs:maxName)
tU       string(vs:maxName)
prevU    string(vs:maxName),auto
nextU    string(vs:maxName),auto
isWrite  byte,auto
pendW    long
stActive byte
stHasCF  byte
stWriteT long
stReadsX byte
changes  long
  code
  if pCodeT < 1 or pEndT < pCodeT then return 0.
  loop i = pCodeT to pEndT                                 ! ANY GOTO defeats straight-line liveness (a forward jump skips the overwrite; a backward jump re-enters) - the same bail AutoVerdict takes
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if upper(self.tk.tokens.tok) = 'GOTO' then return 0.
  end
  loop i = pCodeT + 1 to pEndT + 1                         ! +1 sentinel forces the final statement's finalize
    if i > pEndT
      fol = 1 ; isEol = 0 ; contLn = 0                     ! sentinel: force finalize, then break
    else
      get(self.tk.tokens, i)
      if errorcode() then break.
      fol = self.tk.tokens.firstOnLine
      contLn = 0                                           ! see RemoveDeadStoresPass - fol=1 on a '|' continuation
      if not self.tk.tokens.strBefore &= NULL              !   line too, and the token after it is a COMPARISON operand
        if self.TriviaHasContinuation(self.tk.tokens.strBefore)
          contLn = 1
        end
      end
      lvl = self.tk.tokens.level
      ty  = self.tk.tokens.type                            ! capture now: finalize's PrependStrBefore clobbers the buffer
      if self.tk.tokens.tok &= NULL
        txt = '' ; isEol = 0
      else
        txt = self.tk.tokens.tok
        isEol = choose(size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10)
      end
      tU = upper(txt)
    end

    ! ---- finalize the previous statement at a new-statement boundary (or the sentinel) ----
    ! ~contLn: fol=1 on a '|' continuation line too, and finalizing there treats the
    ! fragment before the bar (`k = j +`) as a COMPLETE statement - a write with zero
    ! reads - convicting the pending store above as overwritten-before-read while the
    ! real statement reads it on the next physical line. The write classifier below
    ! has carried this guard all along; the boundary needs it for the same reason.
    if (fol and ~isEol and ~contLn and stActive) or i > pEndT
      if stHasCF
        pendW = 0                                          ! bail: cannot track deadness across control flow
      elsif stWriteT and ~stReadsX
        if pendW                                           ! previous store overwritten before any read -> dead
          self.CommentLineStart(pendW, pPrefix.getValue()) ! physical-line-start insert - see RemoveDeadStoresPass
          changes += 1
          if changes <= 500
            pLog.append('BUILTIN UnusedAssignments line ' & self.LogLineOf(pendW) & ': ' & clip(pNameU) & ' (overwritten before read)<13,10>')
          end
        end
        pendW = choose(self.RhsSingleSafe(stWriteT), stWriteT, 0)
      elsif stWriteT and stReadsX
        pendW = 0                                          ! `x = ...x...` reads the old value -> live
      elsif stReadsX
        pendW = 0                                          ! plain read -> value is live
      end
      stHasCF = 0 ; stWriteT = 0 ; stReadsX = 0
    end

    if i > pEndT                                           ! scope end: a store still pending was never read
      if pendW and pAllowEnd
        self.CommentLineStart(pendW, pPrefix.getValue())   ! physical-line-start insert - see RemoveDeadStoresPass
        changes += 1
        if changes <= 500
          pLog.append('BUILTIN UnusedAssignments line ' & self.LogLineOf(pendW) & ': ' & clip(pNameU) & ' (last store, never read)<13,10>')
        end
      end
      break
    end

    if fol and ~isEol then stActive = 1.

    if lvl = '+' or lvl = '/' or lvl = '-' then stHasCF = 1.
    if fol and ~isEol
      if self.syms.IsColOneLabel(i) then stHasCF = 1. ! jump target -> flow join, bail
    end

    if ~isEol and ty = 'b' and txt and tU = upper(pNameU)
      isWrite = 0
      if fol and ~contLn                              ! whole-var write target is first on its line (never a continuation)
        prevU = '' ; nextU = ''
        if i > pCodeT + 1
          get(self.tk.tokens, i - 1)
          if not self.tk.tokens.tok &= NULL then prevU = upper(self.tk.tokens.tok).
        end
        get(self.tk.tokens, i + 1)
        if ~errorcode() and not self.tk.tokens.tok &= NULL then nextU = upper(self.tk.tokens.tok).
        if nextU = '=' and prevU <> '.' then isWrite = 1.
      end
      if isWrite
        stWriteT = i
      else
        stReadsX = 1
      end
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! 1 = the RHS of the `<var> = <RHS>` at pAssignTok is a SINGLE token that is not '(' and
! the statement ends right after it (the next token is the <10> EOL on the same line).
! This proves side-effect-free (a lone literal/identifier read) with no call, no compound
! expression, and no line continuation.  Anything else -> 0 (keep the assignment).
! ------------------------------------------------------------------------------------
VitEngine.RhsSingleSafe Procedure(LONG pAssignTok)
ln long,auto
  code
  get(self.tk.tokens, pAssignTok)
  if errorcode() then return 0.
  ln = self.tk.tokens.lineNo
  get(self.tk.tokens, pAssignTok + 1) ! must be a plain '='
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.tok <> '=' then return 0.
  get(self.tk.tokens, pAssignTok + 2) ! the single RHS token
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.tok = '(' then return 0.
  get(self.tk.tokens, pAssignTok + 3) ! must be the EOL on the same line = RHS was one token
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.lineNo <> ln then return 0.
  if ~(size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10) then return 0.
  return 1

! ====================================================================================
! BUILTIN HoistCommonBranchCode - common statement(s) at the END of both
! branches of a clean IF/ELSE/END are moved to AFTER the END (item 8, unconditionally
! safe: trailing common code runs after whichever branch, and after the IF either way).
!
! Strategy: BATCHED - ONE walk hoists from every clean IF it finds, rather than one
! statement per pass. Each splice still moves a single physical line, which keeps the token
! surgery small and reviewable, and order is preserved: each hoisted line is inserted
! immediately after the END, so the second peel lands before the first.
! BOTH directions are implemented. END-hoist is tried first because it is the safe one;
! START-hoist (item 7) is tried second and is gated. The walk below is the exact order -
! read it there rather than trusting this summary.
!
! Heavy under-reach - a wrong MOVE silently corrupts code, so every uncertainty skips:
!   * only a clean IF / ELSE / END (exactly one depth-1 separator, and it is ELSE - never
!     ELSIF/OF; MatchLevel gives the matching END; no-ELSE and one-liner IFs are skipped).
!   * the two trailing statements must each be a SINGLE physical line at branch level (no
!     block marks on the line), carry NO interior or trailing comment (a hoist would move or
!     lose it), sit immediately before ELSE / END, and be token-for-token identical.
!   * comment-out is impossible for a motion; instead we relocate the exact tokens (MoveToks
!     preserves tok+strBefore refs - lossless) and re-indent the moved line to the IF's level.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinHoistCommonBranchCode Procedure(StringTheory pLog)
changes long,AUTO
  code
  if ~self.LevelSpanBalanced(1, records(self.tk.tokens))
    pLog.append('BUILTIN HoistCommonBranchCode: token stream level-unbalanced - pass refused (a mispaired IF/END hoists a statement across the wrong branch, #17)<13,10>')
    return 0
  end
  changes = self.HoistOnePass(pLog)
  if changes
    self.wantReparse = true
    pLog.append('BUILTIN HoistCommonBranchCode: ' & changes & ' hoist(s) this pass<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! Find every clean IF/ELSE/END with an identical trailing (END-hoist) or leading
! (START-hoist) statement in both branches and hoist it.  END-hoist is tried first
! (unconditionally safe); START-hoist second (gated).  BATCHED - after a
! successful hoist the scan resumes AT THE SAME IF (multi-peel in one invocation; the
! walk is token-structural, so stale lineNos are harmless) instead of returning for a
! full engine reparse per hoist.  Returns the number of hoists.
! ------------------------------------------------------------------------------------
VitEngine.HoistOnePass Procedure(StringTheory pLog)
i       long,auto
ifTok   long,auto
endTok  long,auto
elseTok long,auto
changes long
  code
  i = 0
  loop
    i += 1
    if i > records(self.tk.tokens) then break. ! live bound: counts shift after each hoist
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.type <> 'r'        or |
       ~self.tk.tokens.firstOnLine       or |
       self.tk.tokens.tok &= NULL        or |
       upper(self.tk.tokens.tok) <> 'IF' or |
       self.tk.tokens.level <> '+'
      cycle
    end
    ifTok = i
    get(self.tk.tokens, ifTok)    ! position the queue for MatchLevel
    endTok = self.tk.MatchLevel() ! matching '-' (END / '.')
    if endTok <= ifTok then cycle.
    elseTok = self.HoistFindElse(ifTok, endTok)
    if ~elseTok then cycle.
    if self.TryEndHoist(ifTok, elseTok, endTok, pLog)
      changes += 1
      i = ifTok - 1               ! re-scan this IF: another statement pair may now be peelable
      cycle
    end
    if self.TryStartHoist(ifTok, elseTok, endTok, pLog)
      changes += 1
      i = ifTok - 1               ! (after a START-hoist the IF sits further on - the forward walk re-finds it)
      cycle
    end
  end
  return changes

! ------------------------------------------------------------------------------------
! For the IF block [pIfTok..pEndTok], return the single depth-1 ELSE token, or 0 if the
! block is not a clean two-branch IF (no separator, an ELSIF, more than one separator,
! or an OF - i.e. anything we cannot hoist across safely).
! ------------------------------------------------------------------------------------
VitEngine.HoistFindElse Procedure(LONG pIfTok, LONG pEndTok)
i     long,auto
depth long,AUTO
cnt   long
sep   long
lvl   string(1),auto
  code
  depth = 1
  loop i = pIfTok + 1 to pEndTok - 1
    get(self.tk.tokens, i)
    if errorcode() then return 0.
    lvl = self.tk.tokens.level
    case val(lvl)
    of 43 ! '+'
      depth += 1
    of 45 ! '-'
      depth -= 1
      if depth < 1 then return 0.
    of 47 ! '/'
      if depth = 1
        cnt += 1
        if cnt > 1                    or |   ! ELSIF chain / multiple separators
           self.tk.tokens.tok &= NULL or |
           upper(self.tk.tokens.tok) <> 'ELSE' ! ELSIF/OF/OROF
          return 0
        end
        sep = i
      end
    end
  end
  if cnt <> 1 then return 0.
  return sep

! ------------------------------------------------------------------------------------
! Attempt the END-hoist for one clean IF/ELSE/END.  Returns 1 if performed, 0 if skipped.
! ------------------------------------------------------------------------------------
VitEngine.TryEndHoist Procedure(LONG pIfTok, LONG pElseTok, LONG pEndTok, StringTheory pLog)
tEol      long,auto
tFirst    long,auto
tCEnd     long,auto
sEol      long,auto
sFirst    long,auto
sCEnd     long,auto
sLine     long,auto
firstTxt  string(vs:maxName),AUTO
hoCmtA    StringTheory                                     ! the two lines' comment TEXT - identical is allowed, different is not
hoCmtB    StringTheory
endIndent StringTheory
  code
  ! ELSE and END must each begin their own physical line
  if ~self.IsFirstOnLine(pElseTok) then return 0.
  if ~self.IsFirstOnLine(pEndTok)  then return 0.
  ! the token just before ELSE / END is that line's EOL
  tEol = pElseTok - 1
  sEol = pEndTok  - 1
  if ~self.IsEolTok(tEol) then return 0.
  if ~self.IsEolTok(sEol) then return 0.
  ! END must own its line and have room after it to receive the hoisted line
  if ~self.IsEolTok(pEndTok + 1) then return 0.
  if pEndTok + 2 > records(self.tk.tokens) then return 0.
  ! each trailing statement's first-on-line token
  tFirst = self.LineStartOf(tEol)
  sFirst = self.LineStartOf(sEol)
  if ~tFirst or ~sFirst then return 0.
  tCEnd = tEol - 1
  sCEnd = sEol - 1
  if tCEnd < tFirst or sCEnd < sFirst then return 0.       ! blank line - no statement
  ! a '|'-continued trailing statement: every continuation token carries firstOnLine=1
  ! with the bar+CRLF in its strBefore, so LineStartOf stopped at the LAST physical
  ! line and tFirst/sFirst name only the TAIL. Hoisting that relocates half a
  ! statement, SetStrBefore destroys the bar, and BOTH branches are left truncated
  ! mid-statement - one continuing straight into ELSE. LineHasComment cannot see it
  ! ('!' only), so test the tail's own leading trivia. A '|' inside an absorbed
  ! comment refuses too - under-reach, the safe direction (KrTriviaClean's rule).
  get(self.tk.tokens, tFirst)
  if ~errorcode() and not self.tk.tokens.strBefore &= NULL
    if instring('|', self.tk.tokens.strBefore, 1, 1) then return 0.
  end
  get(self.tk.tokens, sFirst)
  if ~errorcode() and not self.tk.tokens.strBefore &= NULL
    if instring('|', self.tk.tokens.strBefore, 1, 1) then return 0.
  end
  ! single simple statement each (no block marks), no interior/trailing comment, identical
  if self.LineHasLevelMark(tFirst, tEol) then return 0.
  if self.LineHasLevelMark(sFirst, sEol) then return 0.
  ! IDENTICAL COMMENTS DO NOT BLOCK A HOIST. The refusal was blanket -
  ! any comment on either line - and its stated reason was that a hoist would MOVE or LOSE
  ! one. That is an information-loss argument, so it only bites when the two DIFFER: when
  ! they say the same thing the copy that goes is redundant and nothing is lost, which is
  ! the same reasoning that already requires the statements to be token-for-token identical.
  ! Compared as TEXT, so the column may differ - in real code it always does. A line with a
  ! comment and one without still refuse, because '' <> the other's text.
  self.LineCommentText(tFirst, tEol, hoCmtA)
  self.LineCommentText(sFirst, sEol, hoCmtB)
  if choose(hoCmtA._DataEnd < 1, '', hoCmtA.valuePtr[1 : hoCmtA._DataEnd]) <> hoCmtB.getValue() then return 0.
  if ~self.SpanTokEqual(tFirst, tCEnd, sFirst, sCEnd) then return 0.

  ! ---- capture what we need BEFORE the edits clobber the token buffer ----
  get(self.tk.tokens, pEndTok)
  if self.tk.tokens.strBefore &= NULL
    endIndent.free()
  else
    endIndent.setValue(self.tk.tokens.strBefore)           ! indent of the END line = the IF's level
  end
  get(self.tk.tokens, sFirst)
  if self.tk.tokens.tok &= NULL
    firstTxt = ''
  else
    firstTxt = self.tk.tokens.tok
  end
  sLine = self.LogLineOf(sFirst)                           ! log-only var - source coords in preview

  ! ---- the splice: relocate the false-branch line after END, drop the true-branch copy ----
  self.tk.SetStrBefore(sFirst, endIndent.getValue())       ! re-indent moved line to the IF's level
  self.tk.MoveToks(sFirst, pEndTok + 2, sEol - sFirst + 1) ! move [sFirst..sEol] to just after the END line
  self.tk.DeleteToks(tFirst, tEol)                         ! remove the now-redundant true-branch copy

  pLog.append('BUILTIN HoistCommonBranchCode END-hoist line ' & sLine & ': ' & clip(firstTxt) & ' ...<13,10>')
  return 1

! ------------------------------------------------------------------------------------
! Attempt the START-hoist (item 7): a statement common to the START of both branches is
! moved to BEFORE the IF.  This flips execution order from [eval C -> run S] to [run S ->
! eval C], so it is GATED - only when reordering cannot change behaviour:
!   (1) S is a plain assignment `lhs = ...` with no call (its only effect is writing lhs);
!   (2) the condition C contains no call (a pure read - so nothing in C feeds S either);
!   (3) S's lhs is not read by C (so running S first cannot change C's value).
! Returns 1 if performed, 0 if skipped.  The false copy is dropped and the true copy moved
! (a backward per-token relocation via StartMove) to just before the IF, re-indented.
! ------------------------------------------------------------------------------------
VitEngine.TryStartHoist Procedure(LONG pIfTok, LONG pElseTok, LONG pEndTok, StringTheory pLog)
ifEol    long,auto
elseEol  long,auto
tFirst   long,auto
tEol     long,auto
tCEnd    long,auto
fFirst   long,auto
fEol     long,auto
fCEnd    long,auto
lhsU     string(vs:maxName),AUTO
hoCmtA   StringTheory ! as TryEndHoist
hoCmtB   StringTheory
tLine    long,auto
hx       long,auto    ! scan index over the IF header line
ifIndent StringTheory
  code
  ! the IF line and the ELSE line each end at their own EOL (single physical line)
  ifEol   = self.FirstEolAfter(pIfTok)
  elseEol = self.FirstEolAfter(pElseTok)
  if ~ifEol or ~elseEol or |
     ifEol >= pElseTok  or |
     elseEol >= pEndTok or |
     elseEol <> pElseTok + 1                                       ! 'else <stmt>' inline - the line after is NOT the branch's first statement; hoisting reorders around the uninspected inline one
    return 0
  end
  loop hx = pIfTok + 1 to ifEol - 1                                ! 'if c then <stmt>' inline - same trap on the true side (THEN must be the last token of the IF line)
    get(self.tk.tokens, hx)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if upper(self.tk.tokens.tok) = 'THEN' and hx < ifEol - 1 then return 0.
  end
  ! first statement of each branch = the line immediately after the IF / ELSE line
  tFirst = ifEol + 1
  fFirst = elseEol + 1
  if ~self.IsFirstOnLine(tFirst) or ~self.IsFirstOnLine(fFirst) then return 0.
  if self.IsEolTok(tFirst) or self.IsEolTok(fFirst) then return 0. ! blank first line
  if tFirst >= pElseTok or fFirst >= pEndTok then return 0.        ! empty branch
  tEol = self.FirstEolAfter(tFirst)
  fEol = self.FirstEolAfter(fFirst)
  if ~tEol or ~fEol or |
     tEol >= pElseTok or fEol >= pEndTok                           ! first stmt must lie within its branch
    return 0
  end
  tCEnd = tEol - 1
  fCEnd = fEol - 1
  if tCEnd < tFirst or fCEnd < fFirst then return 0.
  ! single simple statement each, no marks/comments, identical
  if self.LineHasLevelMark(tFirst, tEol) then return 0.
  if self.LineHasLevelMark(fFirst, fEol) then return 0.
  ! IDENTICAL COMMENTS DO NOT BLOCK A HOIST. The refusal was blanket -
  ! any comment on either line - and its stated reason was that a hoist would MOVE or LOSE
  ! one. That is an information-loss argument, so it only bites when the two DIFFER: when
  ! they say the same thing the copy that goes is redundant and nothing is lost, which is
  ! the same reasoning that already requires the statements to be token-for-token identical.
  ! Compared as TEXT, so the column may differ - in real code it always does. A line with a
  ! comment and one without still refuse, because '' <> the other's text.
  self.LineCommentText(tFirst, tEol, hoCmtA)
  self.LineCommentText(fFirst, fEol, hoCmtB)
  if choose(hoCmtA._DataEnd < 1, '', hoCmtA.valuePtr[1 : hoCmtA._DataEnd]) <> hoCmtB.getValue() then return 0.
  if ~self.SpanTokEqual(tFirst, tCEnd, fFirst, fCEnd) then return 0.
  ! ---- the gate ----
  if ~self.StmtIsPlainAssign(tFirst, tCEnd) then return 0.         ! (1) plain no-call assignment
  if self.SpanHasParen(pIfTok + 1, ifEol - 1) then return 0.       ! (2) condition has no call
  get(self.tk.tokens, tFirst)
  if self.tk.tokens.tok &= NULL then return 0.
  lhsU = upper(self.tk.tokens.tok)
  if self.SpanHasName(lhsU, pIfTok + 1, ifEol - 1) then return 0.  ! (3) lhs not read by C
  if self.HoistAliasRisk(tFirst, lhsU) then return 0.              ! (3b) ...nor read through an ALIAS of it - see below

  ! ---- capture, then splice ----
  get(self.tk.tokens, pIfTok)
  if self.tk.tokens.strBefore &= NULL
    ifIndent.free()
  else
    ifIndent.setValue(self.tk.tokens.strBefore)
  end
  tLine = self.LogLineOf(tFirst)                                   ! log-only var - source coords in preview

  self.tk.DeleteToks(fFirst, fEol)                                 ! drop the false-branch copy (higher indices - IF/true unaffected)
  self.tk.SetStrBefore(tFirst, ifIndent.getValue())                ! re-indent the moved line to the IF's level
  self.StartMove(tFirst, pIfTok, tEol - tFirst + 1)                ! relocate [tFirst..tEol] to just before the IF

  pLog.append('BUILTIN HoistCommonBranchCode START-hoist line ' & tLine & ': ' & clip(lhsU) & ' ...<13,10>')
  return 1

! Backward block relocation: move the pNum tokens [pSrc..pSrc+pNum-1] to just before pDst
! (pDst < pSrc).  MoveTok(pSrc+k, pDst+k) is net-neutral on tokens above the source, so the
! block's own indices stay put as each token peels off in order.  (MoveToks does not advance
! its source for backward moves, so it cannot be used here.)
VitEngine.StartMove Procedure(LONG pSrc, LONG pDst, LONG pNum)
k long,auto
  code
  if pNum < 1 then return.
  loop k = 0 to pNum - 1
    self.tk.MoveTok(pSrc + k, pDst + k)
  end

! First <10> (EOL) token at an index greater than pTok, or 0.
VitEngine.FirstEolAfter Procedure(LONG pTok)
i long,auto
  code
  i = pTok + 1
  loop while i <= records(self.tk.tokens)
    if self.IsEolTok(i) then return i.
    i += 1
  end
  return 0

! 1 = a '(' token appears anywhere in [pS..pE] (a call or grouping - conservatively a skip).
VitEngine.SpanHasParen Procedure(LONG pS, LONG pE)
i long,auto
  code
  if pE < pS then return 0.
  loop i = pS to pE
    get(self.tk.tokens, i)
    if errorcode() then return 1.
    if not self.tk.tokens.tok &= NULL
      if self.tk.tokens.tok = '(' then return 1.
    end
  end
  return 0

! 1 = a label token (type 'b') in [pS..pE] names the same STORAGE as pNameU.
!
! *** COMPARED BY ROOT, NOT BY SPELLING. *** The tokenizer merges a dotted name into ONE token,
! so a whole-token compare for `GRP` never matches the token `GRP.X` - and the caller is asking
! whether a statement it wants to move writes something the condition reads. A GROUP appears in
! an expression as a string over its members, so `grp` and `grp.x` ARE the same bytes; and a
! colon is a second spelling of the same qualification, so `pq:a` and `pq.a` are one field.
! Comparing the text saw none of that, and HoistCommonBranchCode moved `grp = 1` above
! `if grp.x = 2` - the condition then read what the hoist had just written, and the other arm
! ran.
!
! So both sides are cut at the first '.' or ':' and the roots compared. That over-refuses two
! genuinely-independent members of one structure (`pq:a` against `pq:b`), which is the same cut
! MgQualClash takes for the same reason: a refusal costs one hoist, and the alternative is
! teaching this the storage model.
VitEngine.SpanHasName Procedure(STRING pNameU, LONG pS, LONG pE)
i    long,auto
  code
  if pE < pS then return 0.
  loop i = pS to pE
    get(self.tk.tokens, i)
    if errorcode() then return 1.
    if self.tk.tokens.type <> 'b' or |
       self.tk.tokens.tok &= NULL
      cycle
    end
    if self.NameRoot(self.tk.tokens.tok) = self.NameRoot(pNameU) then return 1.
  end
  return 0

! The part of a name before any qualification - `grp.x` and `pq:a` both have the root that
! names the storage. Upper-cased, because Clarion labels are not case sensitive.
VitEngine.NameRoot Procedure(STRING pName)
p  long,auto
q  long,auto
t  StringTheory
  code
  t.setValue(pName)
  t.trim()
  t.upper()
  if ~t._DataEnd then return ''.
  ! *** WHICHEVER COMES FIRST, not the dot in preference to the colon. *** The two are
  ! interchangeable (LRM: a ':' may replace a '.' for any structure except CLASS), so a
  ! name may be spelt `grp:x.m` - and looking for the dot first roots that at GRP:X, which
  ! is not the storage. Measured: `grp = 1` hoisted above `if grp:x.m = 2`, the same wrong
  ! branch this routine was written to stop.
  p = t.findByte(46)                                 ! '.'
  q = t.findByte(58)                                 ! ':'
  if q and (~p or q < p) then p = q.
  if p > 1 then t.setLength(p - 1).
  return choose(t._DataEnd < 1, '', t.valuePtr[1 : t._DataEnd])

! 1 = the statement [pFirst..pCEnd] is a plain `label = ...` assignment with no call: first
! token is a label, second is '=', and no '(' anywhere.  So its only effect is writing lhs.
VitEngine.StmtIsPlainAssign Procedure(LONG pFirst, LONG pCEnd)
  code
  if pCEnd < pFirst + 1 then return 0.               ! need at least `lhs = rhs`
  get(self.tk.tokens, pFirst)
  if errorcode() or self.tk.tokens.type <> 'b' then return 0.
  get(self.tk.tokens, pFirst + 1)
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.tok <> '=' then return 0.
  if self.SpanHasParen(pFirst, pCEnd) then return 0. ! a call anywhere -> not a pure assignment
  return 1

! ------------------------------------------------------------------------------------
! Small token-geometry helpers used by the hoist builtins.
! ------------------------------------------------------------------------------------
VitEngine.IsFirstOnLine Procedure(LONG pTok)
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return 0.
  if self.tk.tokens.firstOnLine then return 1.
  return 0

! ------------------------------------------------------------------------------------
! Is token pTok the end-of-line token - a single byte 10.
!
! A line ending is its OWN token in this model rather than trivia, which is what makes "the
! end of this line" a position that can be found rather than inferred. Answers 0 rather than
! raising on a bad index.
! ------------------------------------------------------------------------------------
VitEngine.IsEolTok Procedure(LONG pTok)
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then return 1.
  return 0

! Walk back from an EOL token to the first-on-line token of that same line.  Returns 0 if
! the line is blank (another EOL is hit first) or on any error.
VitEngine.LineStartOf Procedure(LONG pEolTok)
i  long,auto
  code
  i = pEolTok - 1
  loop while i >= 1
    get(self.tk.tokens, i)
    if errorcode() then return 0.
    if self.tk.tokens.firstOnLine then return i.
    if not self.tk.tokens.tok &= NULL
      if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then return 0.
    end
    i -= 1
  end
  return 0

! ------------------------------------------------------------------------------------
! Does any token between pFirst and pEol carry a block mark - '+', '-' or '/'.
!
! Used to leave structural lines alone: a line that opens or closes a block is not a plain
! statement, and several transforms are only safe on plain statements.
!
! IT ANSWERS 1 ON ERROR, ON PURPOSE. "I could not tell" has to mean "assume it is structural",
! because the failure that matters is treating a block line as ordinary and splicing it.
! ------------------------------------------------------------------------------------
VitEngine.LineHasLevelMark Procedure(LONG pFirst, LONG pEol)
i   long,auto
lvl string(1),auto
  code
  loop i = pFirst to pEol
    get(self.tk.tokens, i)
    if errorcode() then return 1. ! treat trouble as "has mark" -> skip (safe)
    lvl = self.tk.tokens.level
    if lvl = '+' or lvl = '/' or lvl = '-' then return 1.
  end
  return 0

! A comment ('!') anywhere in the line's trivia - leading (before pFirst's token), interior,
! or trailing (in the EOL's strBefore).  Under-reach: a hoist could move or drop it.
VitEngine.LineHasComment Procedure(LONG pFirst, LONG pEol)
i   long,auto
  code
  loop i = pFirst to pEol
    get(self.tk.tokens, i)
    if errorcode() then return 1.
    if not self.tk.tokens.strBefore &= NULL
      if instring('!', self.tk.tokens.strBefore, 1, 1) then return 1.
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! The COMMENT TEXT carried by a line, all of it, normalised and concatenated - everything
! AFTER the '!', from every token's trivia across [pFirst..pEol]. '' when the line carries none.
! It is the TEXT, deliberately, not the trivia bytes, and the normalising is deliberately
! generous: the '!' itself, the column it sits in, tabs, and runs of spaces all drop out, so
! two lines that SAY the same thing compare equal however they are laid out. Layout is exactly
! what differs between two branches of an IF in real code - one arm is indented further, or the
! comments were aligned to different columns - and refusing those would make the flexibility
! worthless. Only the words are compared.
! ------------------------------------------------------------------------------------
VitEngine.LineCommentText Procedure(LONG pFirst, LONG pEol, StringTheory pOut)
i   long,auto
bp  long,auto
sb  StringTheory
  code
  pOut.free()
  loop i = pFirst to pEol
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.strBefore &= NULL then cycle.
    sb.setValue(self.tk.tokens.strBefore)
    bp = sb.findByte(33)          ! '!'
    if ~bp then cycle.
    sb.RemoveFromPosition(1,bp)   ! everything AFTER the '!'
    sb.replaceByte(9, 32)         ! a tab is white space like any other here replace all <tab> with <space>
    loop while sb.findChars('  ') ! runs of spaces collapse: only the WORDS are the text
      sb.replace('  ', ' ')
    end
    sb.trim()
    if pOut._DataEnd then pOut.append(' ').
    pOut.append(sb)
  end

! Caseless token-for-token equality of two spans [pAF..pAE] and [pBF..pBE].
VitEngine.SpanTokEqual Procedure(LONG pAF, LONG pAE, LONG pBF, LONG pBE)
k   long,auto
o   long,auto
ta  StringTheory                  ! holds token A while token B is fetched - no fixed width to overflow
  code
  if pAE - pAF <> pBE - pBF then return 0.
  o = pBF - pAF
  loop k = pAF to pAE
    get(self.tk.tokens, k)
    if errorcode() then return 0. ! BOTH gets are checked. A failed fetch leaves the queue
    ! buffer on the PREVIOUS record, so an unchecked get compares a token with itself and
    ! answers 1 - the spans are the same length, so nothing else catches it. `ta` HOLDS the
    ! first token's text while the second is fetched, because the get below overwrites the
    ! queue buffer. It is a StringTheory rather than a fixed STRING so that a long token
    ! cannot be held as its PREFIX: two different long tokens sharing one would compare
    ! EQUAL, and this answer feeds the hoists, which MOVE code on the strength of it. A
    ! StringTheory has no length to guess and nothing to truncate, so the comparison is
    ! simply always right and no over-long token has to be refused.
    if self.tk.tokens.tok &= NULL
      ta.free()
    else
      ta.setValue(self.tk.tokens.tok)
      ta.upper()
    end
    get(self.tk.tokens, k + o)    !   buffer on the PREVIOUS record, so the routine compared a
    if errorcode() then return 0. !   token with itself and answered 1 - the spans are the same.
    if self.tk.tokens.tok &= NULL
      if ta._DataEnd then return 0.
    else
      if choose(ta._DataEnd < 1, '', ta.valuePtr[1 : ta._DataEnd]) <> upper(self.tk.tokens.tok) then return 0.
    end
  end
  return 1

! ====================================================================================
! BUILTIN IfChainToCase (idiom cleanup - OPT-IN) - collapse a chain of
! equality tests on ONE repeated expression into a CASE, so the expression is evaluated
! ONCE instead of once per arm:
!
!     if lower(w.getValue()) = 'fold' or lower(w.getValue()) = 'trimr'    case lower(w.getValue())
!       <body A>                                                         of 'fold' orof 'trimr'
!     elsif lower(w.getValue()) = 'chr'                          ==>        <body A>
!       <body B>                                                         of 'chr'
!     else                                                                  <body B>
!       <body C>                                                         else
!     end                                                                   <body C>
!                                                                        end
!
! The model that keeps this small: THE BODIES ARE NEVER TOUCHED, and the block's ELSE and
! its terminator (END or '.') already mean to a CASE exactly what they meant to the IF.
! Only the IF head and each ELSIF head are rewritten, by four token edits:
!   * the IF keyword      -> `case`  (SetTok, trivia KEPT - the CASE lands on the IF's line
!                                     at the IF's indent, and the expression that followed
!                                     the IF stays put and becomes the CASE selector)
!   * the first arm's '=' -> `of`    (SetTok with '<13,10>' & indent, so `of` starts a new
!                                     line level with the CASE; the literal after it keeps
!                                     its own leading space)
!   * each later `or`     -> `orof`  (SetTok, trivia kept) plus DeleteToks over THAT arm's
!                                     repeated expression and its '='
!   * an ELSIF keyword    -> `of`    (SetTok, trivia kept - it already owns its line) plus
!                                     DeleteToks over its repeated expression and its '='
! SetTok re-runs TokenType, so the new `case` immediately carries level '+' and every new
! `of`/`orof` carries '/' - the level marks stay consistent for the rest of the pass.
! Edits are collected first and applied HIGHEST POSITION FIRST (the established pattern):
! a DeleteToks shifts every position above it, so a right-to-left apply is the only order
! in which the staged positions stay valid.
!
! A '|' continuation needs no special handling: the tokenizer parks the bar AND the CRLF in
! the strBefore of the token that FOLLOWS the bar, so deleting an arm's repeated expression
! also removes the line break in front of it (the arms simply close up onto one line), and a
! bar sitting in front of an `or` survives into the `orof`. Either way the result is legal.
!
! SAFETY. Collapsing evaluates the repeated expression ONCE where the IF evaluated it up to
! N times, so it is sound only when that expression is PURE. Purity is PROVEN, not assumed:
! every token of the expression must be a name, a member dot, a constant inside an argument
! list, or a CALL whose name is on a known-pure list (Clarion reader builtins plus the
! StringTheory reader methods; extend it per rule file with the PURE(name name) parameter).
! A call that is not on the list refuses the WHOLE IF - `if NextWord() = 'a' or NextWord() =
! 'b'` consumes two words and must go on doing so. A token followed by '(' is the call being
! made, so that is the token whose name is tested; the tokenizer does not merge a dotted name
! when a '(' follows it, so a method call arrives as [obj] [.] [method] ['('] and the name
! tested is the METHOD. A merged dotted token with no parentheses (st._DataEnd) is a property
! READ and is allowed.
!
! WHAT IT REFUSES (all under-reach - a refusal leaves working code exactly as it was):
!   * anything but a top-level OR chain of `EXPR = <literal|integer>`: AND / XOR / NOT / '~',
!     any comparison other than '=', a right-hand side that is not a single constant token,
!     parentheses that are not a call, and any operator or bracket inside the expression;
!   * an expression that is not TEXTUALLY IDENTICAL (caseless, whitespace-blind, via
!     SpanTokEqual) in every arm of every head - a CASE has exactly one selector;
!   * a comment anywhere in a head line - the DeleteToks would swallow it;
!   * a one-liner head (`then` or ';' before the line ends) - that is ExpandOneLiners' job,
!     and it runs first if the rule file wants both;
!   * an ELSIF at this IF's own depth whose condition does NOT qualify. A PARTIAL conversion
!     is IMPOSSIBLE - `case ... of ... elsif ...` is not legal Clarion - so a non-qualifying
!     ELSIF refuses the WHOLE IF rather than converting the arms in front of it;
!   * fewer than TWO resulting OF values across the whole IF - one `of` is no clearer than
!     the IF was, and with one arm the expression was only ever evaluated once anyway.
!
! HIGH-RISK: this is the only builtin that changes an expression's evaluation COUNT.
!     The purity list IS the safety argument - a side-effecting name wrongly added to it (or
!     via PURE(...)) is a real bug. OPT-IN: vitrules.txt declares it inside `GROUP
!     analysis, OFF`, so a plain run never reaches it and --group=analysis turns it on.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinIfChainToCase Procedure(StringTheory pLog)
n          long,auto
i          long,auto
s          long,auto
raw        StringTheory
pureU      StringTheory                          ! ' NAME NAME ... ' - space delimited, UPPER, leading AND trailing space
ifIndentSt StringTheory                          ! the IF line's indent (trailing whitespace run of its strBefore)
ofSb       StringTheory                          ! '<13,10>' & indent - the strBefore handed to the first `of`
ifTok      long                                  ! the IF keyword being considered
endTok     long                                  ! its matching terminator (END or '.') from MatchLevel
ifEol      long                                  ! EOL of the IF's LOGICAL line (a '|' continuation emits no EOL token)
scanFirst  long                                  ! condition span handed to IcScanArms
scanLast   long
refExpS    long                                  ! the reference expression = arm 1 of the IF head
refExpE    long
headTok    long                                  ! the head currently being staged (the IF, or an ELSIF)
headIsIf   byte
armOk      byte                                  ! IcScanArms verdict for the current head
armTotal   long                                  ! OF values across the whole IF
bail       byte                                  ! any refusal raised after the IF head scan
converted  byte                                  ! this IF was collapsed
dep2       long                                  ! block depth while walking for our OWN ELSIF/ELSE
logLn      long                                  ! log-facing line of the IF, captured before the edits
changes    long
nxPos      long                                  ! IcPush staging (a routine takes no parameters)
nxPos2     long
nxKind     byte
nxTxt      string(8)
nxSb       byte
ArmQ  QUEUE,PRE(aq)
armOr     long                                   ! the `or` that introduces this arm (0 = first arm of its head)
armEq     long                                   ! this arm's top-level '='
armExpS   long                                   ! first token of this arm's repeated expression
armExpE   long                                   ! last token of it (always armEq - 1)
      END
EdQ   QUEUE,PRE(ed)
pos       long                                   ! SetTok target, or the FIRST token of a delete range
pos2      long                                   ! last token of a delete range (kind 2 only)
kind      byte                                   ! 1 = SetTok, 2 = DeleteToks
txt       string(8)                              ! 'case' / 'of' / 'orof' (kind 1 only)
useSb     byte                                   ! 1 = pass ofSb as the new strBefore (the first `of` only)
      END
  code
  free(ArmQ)                                     ! local QUEUEs persist between calls - start every pass empty
  free(EdQ)
  self.IfCasePureList(pureU)                     ! the base list; PURE(...) only ever APPENDS to it
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      if upper(self.rl.rules.bparmQ.name) = 'PURE' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value) ! parsed exactly like UnusedVars' EXCLUDE(a b c)
        raw.upper()
        pureU.append(clip(raw.getValue()) & ' ') ! the list already ends in a space
      end
    end
  end

  n = records(self.tk.tokens)
  if n < 1 then return 0.
  i = 0
  loop
    i += 1
    if i > records(self.tk.tokens) then break.   ! LIVE bound: the stream shrinks as chains collapse
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.type <> vt:reservedWord or |   ! IF is a reserved word ('r'); a variable named if is 'b'
       ~self.tk.tokens.firstOnLine            or |
       self.tk.tokens.tok &= NULL             or |
       upper(self.tk.tokens.tok) <> 'IF'      or |
       self.tk.tokens.level <> '+'               ! block opener (vitTokenize ~1077); ELSE/ELSIF are '/', END/'.' are '-'
      cycle
    end
    ifTok = i
    do IcTryOne
    if ~converted then cycle.
    changes += 1
    if changes = 501
      pLog.append('BUILTIN IfChainToCase: further detail lines suppressed (500 shown)<13,10>')
    end
    if changes <= 500
      pLog.append('BUILTIN IfChainToCase line ' & logLn & ': ' & armTotal & ' arm(s) -> CASE<13,10>')
    end
    i = ifTok               ! resume just after the new `case` - it can never re-match `if`
  end
  if changes
    self.wantReparse = true ! structure changed; later builtins must see the CASE, not the IF
    pLog.append('BUILTIN IfChainToCase: ' & changes & ' chain(s) collapsed this pass<13,10>')
  end
  free(ArmQ)
  free(EdQ)
  return changes

! ---- try to collapse the IF at ifTok; sets converted / armTotal / logLn ----
IcTryOne routine
  data
z  long,auto
  code
  converted = 0
  bail      = 0
  armTotal  = 0
  refExpS   = 0
  refExpE   = 0
  free(EdQ)
  get(self.tk.tokens, ifTok)                      ! position the queue for MatchLevel
  if errorcode() then exit.
  endTok = self.tk.MatchLevel()                   ! the matching '-' (END or '.')
  if endTok <= ifTok then exit.
  ifEol = self.FirstEolAfter(ifTok)               ! a '|' continuation carries no EOL token, so this IS the logical line end
  if ~ifEol then exit.
  if ifEol >= endTok then exit.                   ! no body between the head and the terminator
  if self.LineHasComment(ifTok, ifEol) then exit. ! a comment in the head would be deleted with an arm
  loop z = ifTok + 1 to ifEol - 1                 ! one-liner (`if C then S.` / `if C; S.`) - ExpandOneLiners' job
    get(self.tk.tokens, z)
    if errorcode() then exit.
    if self.tk.tokens.tok &= NULL then cycle.
    if upper(self.tk.tokens.tok) = 'THEN' or |
       self.tk.tokens.tok = ';'
      exit
    end
  end
  scanFirst = ifTok + 1
  scanLast  = ifEol - 1
  do IcScanArms
  if ~armOk then exit.
  get(ArmQ, 1)
  if errorcode() then exit.
  refExpS = aq:armExpS ! arm 1 of the IF head DEFINES the CASE selector
  refExpE = aq:armExpE
  do IcCheckSame
  if bail then exit.
  headTok  = ifTok
  headIsIf = 1
  do IcEmitHead
  if bail then exit.
  do IcHeads           ! the ELSIF chain at this IF's own depth
  if bail or |
     armTotal < 2               ! a single OF is no clearer than the IF
    exit
  end
  do IcCaptureIndent
  logLn = self.LogLineOf(ifTok) ! captured BEFORE the edits - log coordinates only, never logic
  do IcApply
  converted = 1

! ---- every arm of the head just scanned must repeat the SAME expression ----
IcCheckSame routine
  data
c  long,auto
  code
  loop c = 1 to records(ArmQ)
    get(ArmQ, c)
    if errorcode() then bail = 1 ; exit.
    if ~self.SpanTokEqual(refExpS, refExpE, aq:armExpS, aq:armExpE) then bail = 1 ; exit.
  end

! ---- stage (do NOT apply) the token edits for one qualified head ----
IcEmitHead routine
  data
a  long,auto
  code
  get(ArmQ, 1)
  if errorcode() then bail = 1 ; exit.
  if headIsIf
    nxPos = headTok  ; nxPos2 = 0 ; nxKind = 1 ; nxTxt = 'case' ; nxSb = 0         ! `if` -> `case`, indent kept
    do IcPush
    nxPos = aq:armEq ; nxPos2 = 0 ; nxKind = 1 ; nxTxt = 'of'   ; nxSb = 1         ! first '=' -> `of` on a NEW line; the expression in front of it stays put as the selector
    do IcPush
  else
    nxPos = headTok     ; nxPos2 = 0        ; nxKind = 1 ; nxTxt = 'of' ; nxSb = 0 ! `elsif` -> `of`; it already owns its line, so keep its trivia
    do IcPush
    nxPos = headTok + 1 ; nxPos2 = aq:armEq ; nxKind = 2 ; nxTxt = ''   ; nxSb = 0 ! drop the repeated expression and its '='
    do IcPush
  end
  loop a = 2 to records(ArmQ)
    get(ArmQ, a)
    if errorcode() then bail = 1 ; exit.
    nxPos = aq:armOr     ; nxPos2 = 0        ; nxKind = 1 ; nxTxt = 'orof' ; nxSb = 0
    do IcPush
    nxPos = aq:armOr + 1 ; nxPos2 = aq:armEq ; nxKind = 2 ; nxTxt = ''     ; nxSb = 0
    do IcPush
  end
  armTotal += records(ArmQ)

! ---- append one staged edit (dataless routine -> no CODE section) ----
IcPush routine
  clear(EdQ)
  ed:pos   = nxPos
  ed:pos2  = nxPos2
  ed:kind  = nxKind
  ed:txt   = nxTxt
  ed:useSb = nxSb
  add(EdQ)

! ---- walk this IF's OWN depth for ELSIF/ELSE; nested blocks are stepped over ----
IcHeads routine
  data
w      long,auto
zz     long,auto
esEol  long,auto
lv     string(1),auto
tyv    string(1),auto                                  ! fix: token TYPE, needed for the inline-dot close
wU     string(vs:maxName),auto
  code
  dep2 = 0
  w    = ifTok                                         ! the IF's own '+' is not counted: depth 0 IS this IF's body
  loop
    w += 1
    if w >= endTok then break.
    get(self.tk.tokens, w)
    if errorcode() then bail = 1 ; break.
    lv  = self.tk.tokens.level
    tyv = self.tk.tokens.type
    if lv = '+'
      dep2 += 1
    elsif lv = '-' or (tyv = vt:end and lv <> '+' and lv <> '/')
      dep2 -= 1                                        ! fix (the idiom): an INLINE '.' terminator is retyped
      if dep2 < 0 then bail = 1 ; break.               !   vt:end but carries NO '-' level - the level pass skips
                                                       !   inline dots. Counting only '-' let a one-liner IF in the
                                                       !   body inflate the depth for ever, so a REAL ELSIF below it
                                                       !   read as nested and was stepped over - and this IF's head
                                                       !   had already been staged as a CASE. The output would then
                                                       !   have carried an ELSIF inside a CASE - not Clarion.
    elsif lv = '/'
      if dep2 > 0 then cycle.                          ! an ELSE/ELSIF/OF belonging to a NESTED block
      if self.tk.tokens.tok &= NULL then bail = 1 ; break.
      wU = upper(self.tk.tokens.tok)
      if wU = 'ELSE' then break.                       ! a trailing ELSE means the same to a CASE - left alone
      if wU <> 'ELSIF' then bail = 1 ; break.          ! an OF/OROF at our own depth - not a shape we model
      if ~self.IsFirstOnLine(w) then bail = 1 ; break. ! an ELSIF sharing a line with something else
      esEol = self.FirstEolAfter(w)
      if ~esEol then bail = 1 ; break.
      if esEol >= endTok then bail = 1 ; break.
      if self.LineHasComment(w, esEol) then bail = 1 ; break.
      loop zz = w + 1 to esEol - 1                     ! a one-liner ELSIF is not ours
        get(self.tk.tokens, zz)
        if errorcode() then bail = 1 ; break.
        if self.tk.tokens.tok &= NULL then cycle.
        if upper(self.tk.tokens.tok) = 'THEN' or |
           self.tk.tokens.tok = ';'
          bail = 1 ; break
        end
      end
      if bail then break.
      scanFirst = w + 1
      scanLast  = esEol - 1
      do IcScanArms
      if ~armOk then bail = 1 ; break.                          ! a non-qualifying ELSIF refuses the WHOLE IF: `case ... of ... elsif` is not Clarion
      do IcCheckSame
      if bail then break.
      headTok  = w
      headIsIf = 0
      do IcEmitHead
      if bail then break.
      w = esEol                                                 ! nothing on a qualified head line can carry a level mark
    end
  end
  ! belt: the walk must come back to the depth it started at. If it does not,
  ! some opener in the body was never closed by a mark we recognise - which means
  ! every ELSIF below it was mis-read as nested and silently stepped over. Refusing
  ! the whole IF is the only safe answer: the alternative is a CASE with an ELSIF
  ! left inside it. Costs nothing on well-formed code, where dep2 is always 0 here.
  if ~bail and dep2 then bail = 1.

! ---- parse the condition span [scanFirst..scanLast] as `EXPR = lit [or EXPR = lit]...` ----
! Fills ArmQ and sets armOk. Any refusal EXITs with armOk = 0 - the caller then abandons the
! whole IF. Nothing here edits tokens.
IcScanArms routine
  data
p      long,auto                                                ! start of the arm being parsed
q      long,auto                                                ! cursor inside the arm's expression
dep    long,auto                                                ! parenthesis depth (a call's own brackets)
eqP    long,auto                                                ! this arm's top-level '='
expS   long,auto
litP   long,auto
curOr  long,auto                                                ! the `or` that introduced this arm
d      long,auto
dotAt  long,auto
nLen   long,auto
tU     string(vs:maxName),auto
nmU    string(vs:maxName)
callU  string(vs:maxName),auto
tTy    string(1),auto
  code
  free(ArmQ)
  armOk = 0
  if scanLast < scanFirst then exit.                            ! empty condition
  p     = scanFirst
  curOr = 0
  loop                                                          ! one iteration per `EXPR = literal` arm
    expS = p
    get(self.tk.tokens, expS)
    if errorcode() then exit.
    if self.tk.tokens.tok &= NULL then exit.
    if self.tk.tokens.type <> vt:label then exit.               ! an arm must START with a name (a variable, or the callee of a call)
    dep = 0
    eqP = 0
    q   = p
    loop while q <= scanLast
      get(self.tk.tokens, q)
      if errorcode() then exit.
      if self.tk.tokens.tok &= NULL then exit.
      tU  = upper(self.tk.tokens.tok)
      tTy = self.tk.tokens.type
      if tU = '('
        get(self.tk.tokens, q - 1)                              ! a '(' is only ever allowed as a CALL's opening bracket
        if errorcode() then exit.
        if self.tk.tokens.tok &= NULL then exit.
        if self.tk.tokens.type <> vt:label then exit.           ! grouping brackets - refused (we do not model precedence)
        nmU  = upper(self.tk.tokens.tok)
        nLen = len(clip(nmU))
        dotAt = 0
        loop d = 1 to nLen                                      ! defensive: the tokenizer does NOT merge a dotted name in front of '(',
          if nmU[d] = '.' then dotAt = d.                       ! so this should already be the bare method name - take the tail anyway
        end
        if dotAt >= nLen then exit.
        if dotAt
          callU = nmU[dotAt + 1 : nLen]
        else
          callU = nmU
        end
        if ~pureU.findChars(' ' & clip(callU) & ' ') then exit. ! NOT provably pure -> refuse the whole IF
        dep += 1
        q += 1
        cycle
      end
      if tU = ')'
        dep -= 1
        if dep < 0 then exit.
        q += 1
        cycle
      end
      if ~dep and tU = '=' then eqP = q ; break.                ! the arm's comparison - the expression is [expS..q-1]
      ! AND/OR/XOR/NOT are reserved words in keyword position only, so they are matched by
      ! TEXT, not by type - a continued line can present them with firstOnLine set.
      if tU = 'AND' or tU = 'OR' or tU = 'XOR' or tU = 'NOT' or |
         tU = 'THEN' or tU = '~' or tU = ';' or tU = '='
        exit
      end
      ! Whitelist. Every other operator ('+', '-', '*', '/', '&', the comparison family) and
      ! every other bracket ('[', '{') falls through to the else and refuses the IF - the
      ! comparison operators are deliberately caught by the whitelist rather than named,
      ! so no '<' has to be written (and doubled) in a literal here.
      if tTy <> vt:label                           ! a label IS allowed: a variable read, a merged dotted
        if self.tk.tokens.tok = '.'                ! property read (a.b.c is one label token), or a callee
          if self.tk.tokens.level = '-' then exit. ! a block terminator '.', not a member dot
        elsif self.tk.tokens.tok = ','
          if dep < 1 then exit.                    ! a comma outside an argument list
        elsif tTy = vt:Literal or tTy = vt:Integer or tTy = vt:NumericWithDecPt
          if dep < 1 then exit.                    ! a constant outside an argument list
        else
          exit
        end
      end
      q += 1
    end
    if ~eqP or |   ! no top-level '=' in this arm
       eqP - 1 < expS                              ! empty expression
      exit
    end
    litP = eqP + 1                                 ! the right-hand side: exactly ONE constant token
    if litP > scanLast then exit.
    get(self.tk.tokens, litP)
    if errorcode() then exit.
    if self.tk.tokens.tok &= NULL then exit.
    if self.tk.tokens.type <> vt:Literal and self.tk.tokens.type <> vt:Integer then exit.
    clear(ArmQ)
    aq:armOr   = curOr
    aq:armEq   = eqP
    aq:armExpS = expS
    aq:armExpE = eqP - 1
    add(ArmQ)
    if errorcode() then exit.
    if litP = scanLast then break. ! the chain ends here
    p = litP + 1
    get(self.tk.tokens, p)         ! only a top-level `or` may join the next arm
    if errorcode() then exit.
    if self.tk.tokens.tok &= NULL then exit.
    if upper(self.tk.tokens.tok) <> 'OR' then exit.
    curOr = p
    p += 1
    if p > scanLast then exit.     ! a trailing `or` with nothing after it
  end
  if ~records(ArmQ) then exit.
  armOk = 1

! ---- capture the IF line's indent, exactly as BuiltinExpandOneLiners' CaptureIndentE does:
!      the trailing whitespace run of the line-start token's strBefore ----
IcCaptureIndent routine
  data
k2     long,auto
sbLen2 long,auto
ch2    string(1),auto
  code
  ifIndentSt.free()
  ofSb.setValue('<13,10>')                       ! set FIRST: every exit below must still leave ofSb usable
  get(self.tk.tokens, ifTok)
  if errorcode() then exit.
  if self.tk.tokens.strBefore &= NULL then exit. ! column-1 IF (cannot happen: it would not be type 'r')
  sbLen2 = size(self.tk.tokens.strBefore)
  k2 = sbLen2
  loop while k2 >= 1
    ch2 = self.tk.tokens.strBefore[k2]
    if ch2 = ' ' or val(ch2) = 9
      k2 -= 1
    else
      break
    end
  end
  if k2 < sbLen2
    ifIndentSt.setValue(sub(self.tk.tokens.strBefore, k2 + 1, sbLen2 - k2))
    ofSb.append(ifIndentSt)
  end

! ---- apply the staged edits HIGHEST POSITION FIRST; a delete shifts everything above it ----
IcApply routine
  data
e  long,auto
  code
  sort(EdQ, -ed:pos)
  loop e = 1 to records(EdQ)
    get(EdQ, e)
    if errorcode() then break.
    if ed:kind = 1
      if ed:useSb
        self.tk.SetTok(ed:pos, clip(ed:txt), ofSb.getValue()) ! new text AND a new line break + indent in front
      else
        self.tk.SetTok(ed:pos, clip(ed:txt))                  ! strBefore OMITTED = keep the existing leading trivia
      end
    else
      self.tk.DeleteToks(ed:pos, ed:pos2)
    end
  end

! ------------------------------------------------------------------------------------
! The provably-pure call names IfChainToCase will accept inside the repeated expression.
! Space delimited, UPPER, with a leading AND a trailing space so instring(' NAME ', list)
! cannot match a substring of a longer name.
! Two families, both READ-ONLY by definition:
!   * Clarion reader builtins - they compute a value from their arguments and touch nothing;
!   * StringTheory reader methods - they inspect self.value and do
!     not modify it, so calling one once instead of three times is unobservable.
! Anything absent is refused, which is the safe direction. A rule file adds its own with
! BUILTIN IfChainToCase, PURE(myFn myOtherFn).
! NOTE the list is built with several appends on purpose: a single quoted literal beyond
! roughly 680 characters stops the Clarion parser dead.
! CHOOSE is listed but CANNOT currently be reached: `CHOOSE` is in vitTokenize's
!     reservedWords, so its token is typed 'r' and IfChainToCase's callee test (which
!     demands type 'b' = label) refuses it first. That is under-reach, not a hazard - a
!     `choose(...)` in the repeated expression simply leaves the IF alone. Left on the
!     list so the intent is recorded; revisit if the callee test is ever widened.
! ------------------------------------------------------------------------------------
VitEngine.IfCasePureList Procedure(StringTheory pOut)
  code
  pOut.setValue(' UPPER LOWER CLIP LEFT RIGHT CENTER SUB LEN VAL CHR NUMERIC INSTRING ')
  pOut.append('FORMAT DEFORMAT ABS INT ROUND BAND BOR BXOR BSHIFT CHOOSE ADDRESS SIZE ')
  pOut.append('GETVALUE GETVALUEPTR LENGTH LENGTHA CLIPLENGTH SLICE RECORDS GETLINE ')
  pOut.append('FINDCHAR FINDCHARS FINDBYTE CONTAINSCHAR CONTAINSBYTE ')

! ====================================================================================
! PROCEDURE SUMMARIES - one pre-pass that answers, for every PROCEDURE and
! METHOD body in THIS file, the single question "what does it RETURN?", so that the
! analysis builtins can use a fact established in one procedure while transforming
! another.
!
!     parser.StripRefSig    st.removeByte(32) ... return st.getValuePtr()   -> sm:spaceless
!     parser.MaskSigBase    st.SetValue(self.StripRefSig(pParams))          -> st is spaceless
!                           ... return clip(st.getValue())                  -> the clip is dead
!
! THE FACTS. sm:spaceless is deliberately STRONGER than "no trailing spaces": setLength
! truncates INTO the string, so only "no spaces anywhere" rules out a cut EXPOSING an
! interior space as a new trailing one - which is exactly why the earlier design refused MaskSigBase.
! sm:nonNeg / sm:posBound feed KnownRanges' seed table at a call site. sm:none is the
! default and ANY doubt collapses to it.
!
! WHAT IT REFUSES, and every one of these is pinned by a case in TestData\summary.clw:
!   * a body that is NOT in this file. A MAP prototype describes a SIGNATURE, never a
!     behaviour, so there is simply no row and the answer is sm:none;
!   * a VIRTUAL method - a derived class may override it with something that does not
!     strip spaces at all - and a method whose prototype is not VISIBLE (no CLASS body
!     here and no --thorough include closure), which is the same "assume nothing" answer.
!     VitSymbols.MethodIsVirtual returns -1 / 1 for those two, and only 0 is usable;
!   * recursion, direct or mutual: no fixpoint iteration in v1. NB a v1 summary is a pure
!     BODY-SHAPE analysis - it never consults another summary - so recursion cannot
!     actually corrupt one. The refusal is implemented anyway, blunt (ANY mention of the
!     body's own name in its own code), so that the guard is already in place the day
!     summaries become compositional;
!   * a scope with GOTO / COMPILE / OMIT or no CODE (the AutoScopePrep bail), and any
!     scope owning a ROUTINE - a RETURN inside a routine returns from the PROCEDURE, and
!     routine bodies are outside acMainEnd, so we would be summarising a body we had not
!     read all of;
!   * a scope whose level-mark walk does not return to the depth it started at. An INLINE
!     '.' terminator is retyped vt:end but carries NO '-' mark, so the close test is the same one
!     idiom; an unbalanced walk makes "depth 0" a lie and depth 0 is the whole argument
!     that the spaceless point is unconditionally executed;
!   * no explicit RETURN at all, a bare RETURN, or return paths that DISAGREE.
!
! A SUMMARY IS ABOUT THE RETURN VALUE, AND NOTHING ELSE. It says nothing whatsoever about
! what the body did to a *STRING argument, and no consumer may read it as if it did: the
! only thing either consumer does with a summary is credit the RECEIVER OF AN ASSIGNMENT
! (KnownRanges) or the buffer a setValue STORED INTO (TrailingSpaces). RefStrip in the
! fixture pins that.
!
! DELIBERATE DEVIATION from the design, and it is load-bearing. The design (and the earlier attempt's
!     DEVIATION 1 before it) both describe setLength as a TRUNCATION. Read against the
!     shipped class it is not only that: StringTheory.SetLength PADS WITH BYTE 32 when
!     NewLength is greater than _DataEnd (stMemSet(..., 32, ...) on both the buffer and the
!     non-buffer path). So a GROWING setLength puts trailing spaces INTO a spaceless buffer
!     and would invalidate the very simplification this round exists to license. setLength
!     is therefore sk:trunc, not sk:keep: SpaceKeepUse refuses it outright, and the ONLY
!     place it is accepted is BuiltinTrailingSpaces' TsTruncGuard, which requires the
!     author's own same-line proof that it shrinks - `if E < recv._DataEnd then
!     recv.setLength(E).` with the two E spans token-for-token equal. GrowLength in the
!     fixture pins the refusal of the unguarded form.
! ------------------------------------------------------------------------------------
VitEngine.BuildSummaries Procedure()
scRow      long,auto
scKind     byte
sc         long,auto
scSelf     string(vs:maxName) ! the method's receiver class, captured BEFORE AutoScopePrep clobbers the buffer
startT     long,auto
codeT      long,auto
mainEnd    long,auto
ownerU     string(vs:maxName) ! '' for a plain procedure
nameU      string(vs:maxName)
nmOk       byte
fact       byte               ! sm:* being built for this scope
vres       long,auto
lblTxt     string(vs:maxName)
lblLen     long,auto
dotP       long,auto
smRecur    byte
smBad      byte
smAny      byte               ! at least one RETURN seen
depth      long
prevEol    byte
rFact      byte               ! ONE return path's fact
rRecv      string(vs:maxName) ! ONE return path's receiver (spaceless only)
smRecvU    string(vs:maxName) ! the agreed receiver of every return path
reS        long
reE        long
reTmp      long,auto
smMakeP    long               ! the recv.removeByte(32) that makes the buffer spaceless
smMakeE    long               ! its closing ')'
mth        string(vs:maxName)
! ---- token peek (SmGet)
gPos       long,auto
gOk        byte
gNull      byte
gTxt       string(vs:maxName)
gTU        string(vs:maxName)
gTy        string(1)
gLv        string(1)
! ---- name splitting (SmSplitRoot)
spIn       string(vs:maxName)
spRoot     string(vs:maxName)
spSuf      string(vs:maxName)
! ---- paren matching (SmMatchParen)
mpOpen     long
mpClose    long
! ---- depth-0 line starts
lsPos      long
lsOk       byte
indOk      byte
! ---- symbol eligibility (SmRecvOk)
okName     string(vs:maxName)
okRes      byte
okDecl     long
SmLineQ  QUEUE,PRE(sml)                                           ! every DEPTH-0 line start of the scope's main code, ascending
smlPos    long
         END
  code
  if self.sums &= NULL then return.
  free(self.sums)
  if self.syms &= NULL then return.
  self.syms.EnsureFresh() ! consumer gate - the token stream may have moved
  self.acScopeId = 0      ! ... which also retires the AutoScopePrep cache
  if self.syms.scopes &= NULL then return.
  loop scRow = 1 to records(self.syms.scopes)
    get(self.syms.scopes, scRow)
    if errorcode() then break.
    scKind = self.syms.scopes.kind
    sc     = self.syms.scopes.scopeId
    scSelf = self.syms.scopes.selfClass
    startT = self.syms.scopes.startTok
    if scKind <> vs:scProc and scKind <> vs:scMethod then cycle.
    fact = sm:none
    do SmScopeName
    if ~nmOk then cycle. ! we could not even name it - record nothing
    do SmClassify
    do SmRecord
  end
  self.acScopeId = 0
  free(SmLineQ)

! ---- the owner/name this body is filed under ----
SmScopeName routine
  nmOk   = 0
  ownerU = ''
  nameU  = ''
  gPos = startT
  do SmGet
  if ~gOk or |
     gNull
    exit
  end
  lblTxt = gTxt
  lblLen = len(clip(lblTxt))
  if ~lblLen then exit.
  dotP = instring('.', clip(lblTxt), 1, 1)
  if scKind = vs:scMethod
    ownerU = upper(scSelf)
    if ~ownerU then exit.
    if dotP > 1 and dotP < lblLen
      nameU = upper(lblTxt[dotP + 1 : lblLen]) ! 'Class.Method' arrives as ONE column-1 token
    elsif ~dotP
      gPos = startT + 2                        ! ... or as Class . Method, three tokens
      do SmGet
      if ~gOk then exit.
      nameU = gTU
    else
      exit                                     ! a leading or trailing dot - not a name we model
    end
  else
    if dotP then exit.
    nameU = upper(lblTxt)
  end
  if ~nameU then exit.
  nmOk = 1

! ---- everything that has to hold before a body may be summarised at all ----
SmClassify routine
  if scKind = vs:scMethod
    vres = self.syms.MethodIsVirtual(ownerU, nameU)
    if vres then exit.                                            ! -1 = no prototype visible, 1 = VIRTUAL: assume nothing
  end
  self.AutoScopePrep(sc) ! NB clobbers the scopes buffer - sc/scKind/scSelf/startT are captured above
  if self.acBail or |   ! missing scope / no CODE / GOTO / COMPILE / OMIT present
     records(self.acRoutQ) ! a RETURN inside a ROUTINE returns from the PROCEDURE, and routines are outside acMainEnd
    exit
  end
  codeT   = self.acCodeT
  mainEnd = self.acMainEnd
  if mainEnd <= codeT then exit.
  do SmSelfCall
  if smRecur then exit.
  do SmDepthWalk
  if smBad then exit.
  do SmReturns
  if fact = sm:spaceless then do SmProveSpaceless.

! ---- file the answer; a name that turns up twice (an overload) collapses to sm:none ----
SmRecord routine
  data
zz  long,auto
  code
  loop zz = 1 to records(self.sums)
    get(self.sums, zz)
    if errorcode() then break.
    if self.sums.smOwnerU <> ownerU or |
       self.sums.smNameU  <> nameU
      cycle
    end
    if self.sums.smFact <> fact  ! two bodies, one name: a keyed read would land on
      self.sums.smFact = sm:none !   an arbitrary one of them, so neither is usable
      put(self.sums)
    end
    exit
  end
  clear(self.sums)
  self.sums.smOwnerU = ownerU
  self.sums.smNameU  = nameU
  self.sums.smFact   = fact
  add(self.sums)

! ---- does this body mention its OWN name?  Deliberately blunt - see the header ----
SmSelfCall routine
  data
zz  long,auto
  code
  smRecur = 0
  loop zz = codeT + 1 to mainEnd
    gPos = zz
    do SmGet
    if ~gOk or |
       gTy <> vt:label
      cycle
    end
    if gTU = nameU then smRecur = 1 ; break.
  end

! ---- every DEPTH-0 line start of the main code, plus the balance check ----
SmDepthWalk routine
  data
lz  long,auto
  code
  free(SmLineQ)
  depth   = 0
  prevEol = 0
  smBad   = 0
  loop lz = codeT + 1 to mainEnd
    if self.IsEolTok(lz)
      prevEol = 1
      cycle
    end
    gPos = lz
    do SmGet
    if ~gOk then smBad = 1 ; break.
    if gNull then cycle.
    if prevEol and ~depth
      do SmIndentOk                   ! gPos is already lz
      if indOk
        clear(SmLineQ)
        sml:smlPos = lz
        add(SmLineQ)
      end
    end
    prevEol = 0
    if gLv = '+'
      depth += 1
    elsif gLv = '-' or (gTy = vt:end and gLv <> '+' and gLv <> '/')
      depth -= 1                      ! the inline-dot idiom: an INLINE '.' is retyped vt:end but may carry NO '-'
      if depth < 0 then smBad = 1 ; break.
    end
  end
  if ~smBad and depth then smBad = 1. ! the belt: an unbalanced walk makes "depth 0" a lie

! ---- every RETURN in the main code must agree, or there is no fact ----
SmReturns routine
  data
rz  long,auto
  code
  fact    = sm:none
  smAny   = 0
  smRecvU = ''
  rz = codeT
  loop
    rz += 1
    if rz > mainEnd then break.
    gPos = rz
    do SmGet
    if ~gOk                   or |
       gTy <> vt:reservedWord or |
       gTU <> 'RETURN'
      cycle
    end
    reS   = rz + 1
    reTmp = self.FirstEolAfter(rz)
    if reTmp > rz and reTmp - 1 <= mainEnd
      reE = reTmp - 1            ! a '|' continuation emits NO EOL token, so this is the LOGICAL line
    else
      reE = mainEnd
    end
    loop while reE >= reS        ! trim the terminator of `if C then return X.`
      gPos = reE
      do SmGet
      if ~gOk then break.
      if gTy = vt:end or gTxt = ';'
        reE -= 1
      else
        break
      end
    end
    if reE < reS
      fact  = sm:none            ! a bare RETURN returns no value
      smAny = 1
      break
    end
    do SmRetFact
    if ~smAny
      fact    = rFact
      smRecvU = rRecv
      smAny   = 1
    elsif rFact <> fact or rRecv <> smRecvU
      fact = sm:none             ! the return paths disagree
      break
    end
    if fact = sm:none then break.
    rz = reE
  end
  if ~smAny then fact = sm:none. ! no explicit RETURN at all

! ---- ONE return expression -> rFact / rRecv ----
SmRetFact routine
  rFact = sm:none
  rRecv = ''
  do SmRetSpaceless
  if rFact <> sm:none then exit.
  do SmRetNumeric

! ---- (a) `return recv.getValue()` / `.getValuePtr()` - the WHOLE buffer, so its own fact.
!      Both return value[1 : _DataEnd] (checked against StringTheory), never the
!      physical slack behind it, so "the buffer is spaceless" IS "the result is spaceless". ----
SmRetSpaceless routine
  if reE <> reS + 4 then exit.
  gPos = reS
  do SmGet
  if ~gOk or |
     gTy <> vt:label
    exit
  end
  spIn = gTU
  do SmSplitRoot
  if spSuf then exit.                                             ! self.st.getValue() - not a simple local receiver
  okName = spRoot
  gPos = reS + 1
  do SmGet
  if ~gOk or |
     gTxt <> '.'
    exit
  end
  gPos = reS + 2
  do SmGet
  if ~gOk or |
     gTU <> 'GETVALUE' and gTU <> 'GETVALUEPTR'
    exit
  end
  gPos = reS + 3
  do SmGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  gPos = reS + 4
  do SmGet
  if ~gOk or |
     gTxt <> ')' ! getValue(start,len) is a slice, not the whole value
    exit
  end
  do SmRecvOk
  if ~okRes then exit.
  rFact = sm:spaceless
  rRecv = okName

! ---- (b) a literal, (c) a StringTheory counting read, (d) a bare Clarion reader ----
SmRetNumeric routine
  if reE = reS
    gPos = reS
    do SmGet
    if ~gOk or |
       gTy <> vt:Integer ! a NEGATIVE literal is '-' then the digits - two tokens, no fact
      exit
    end
    if gTxt = '0'
      rFact = sm:nonNeg
    else
      rFact = sm:posBound
    end
    exit
  end
  if reE >= reS + 4
    gPos = reS + 1
    do SmGet
    if gOk and gTxt = '.'
      gPos = reS
      do SmGet
      if ~gOk or |
         gTy <> vt:label
        exit
      end
      spIn = gTU
      do SmSplitRoot
      if spSuf then exit.
      okName = spRoot
      do SmRecvOk
      if ~okRes then exit.                                        ! only a StringTheory of THIS scope; another class's len() is its own business
      gPos = reS + 2
      do SmGet
      if ~gOk then exit.
      mth = gTU
      gPos = reS + 3
      do SmGet
      if ~gOk or |
         gTxt <> '('
        exit
      end
      mpOpen = reS + 3
      do SmMatchParen
      if mpClose <> reE then exit.
      case mth
      of   'LEN'      orof 'LENGTH'    orof 'LENGTHA'  orof 'CLIPLENGTH' orof 'LINES' |
         orof 'FINDCHAR' orof 'FINDCHARS' orof 'FINDBYTE' orof 'INSTRING'
        rFact = sm:nonNeg ! a length or a position: 0 = none, never negative
      end
      exit
    end
  end
  if reE < reS + 2 then exit.
  gPos = reS
  do SmGet
  if ~gOk then exit.
  mth = gTU
  if self.IsUserProc(mth) then exit. ! the user's own `Len` is not Clarion's
  gPos = reS + 1
  do SmGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  mpOpen = reS + 1
  do SmMatchParen
  if mpClose <> reE then exit.
  case mth
  of 'LEN' orof 'RECORDS' orof 'SIZE' orof 'INSTRING'
    rFact = sm:nonNeg
  end

! ---- the sm:spaceless CANDIDATE has to be PROVED: find the removeByte(32) that makes the
!      buffer spaceless and confirm nothing between it and the RETURN can undo it ----
SmProveSpaceless routine
  data
zz  long,auto
  code
  smMakeP = 0
  smMakeE = 0
  loop zz = codeT + 1 to mainEnd
    gPos = zz
    do SmGet
    if ~gOk or |
       gTy <> vt:label
      cycle
    end
    spIn = gTU
    do SmSplitRoot
    if spSuf then cycle.
    if spRoot <> smRecvU then cycle.
    if ~self.SpaceMakeUse(zz) then cycle.
    lsPos = zz
    do SmIsLineStart
    if ~lsOk then cycle.                       ! it must be UNCONDITIONAL: a depth-0 line of its own
    mpOpen = zz + 3
    do SmMatchParen
    if ~mpClose then cycle.
    if ~self.IsEolTok(mpClose + 1) then cycle. ! ... and nothing else may share that line
    smMakeP = zz                               ! keep looking: the LAST one wins
    smMakeE = mpClose
  end
  if ~smMakeP
    fact = sm:none                             ! nothing in this body ever removes the spaces
    exit
  end
  loop zz = codeT + 1 to mainEnd
    gPos = zz
    do SmGet
    if ~gOk then cycle.
    if gTy = vt:reservedWord and gTU = 'RETURN' and zz < smMakeP
      fact = sm:none                           ! a return path that never reaches the removeByte
      exit
    end
    if gTy = vt:reservedWord and gTU = 'DO' and zz > smMakeE
      fact = sm:none                           ! a routine can do anything to any buffer
      exit
    end
    if gTy <> vt:label then cycle.
    spIn = gTU
    do SmSplitRoot
    if spRoot <> smRecvU then cycle.
    if zz <= smMakeE
      if spSuf                                 ! a merged property token ABOVE the removeByte: only the length
        if spSuf <> '_DATAEND'                 !   is harmless - valuePtr hands out a writable &STRING, and a
          fact = sm:none                       !   reference taken here can be written through LATER, below the
          exit                                 !   point where we start claiming the buffer is spaceless
        end
        cycle
      end
      gPos = zz + 1
      do SmGet
      if ~gOk or gTxt <> '.'
        fact = sm:none                         ! a BARE mention anywhere - foo(st), st &= other - may alias
        exit                                   !   the buffer to something that mutates it without naming it
      end
      cycle
    end
    if ~self.SpaceKeepUse(zz)
      fact = sm:none                           ! something below the removeByte can put a space back
      exit
    end
  end

! ---- is okName a simple LOCAL StringTheory of scope sc?  (KrRecvOk's test) ----
SmRecvOk routine
  data
rz  long,auto
  code
  okRes = 0
  if ~okName then exit.
  rz = self.syms.FindSym(okName, sc)             ! module-level receivers are out: a call this walk cannot see
  if ~rz then exit.                              !   could move their contents without naming them here
  get(self.syms.syms, rz)
  if errorcode() then exit.
  if self.syms.syms.isRef then exit.             ! `st &= other` re-points a reference and carries no call
  if self.syms.syms.isLike then exit.
  if self.syms.syms.isField then exit.
  if self.syms.syms.typeU <> 'STRINGTHEORY' then exit.
  okDecl = self.syms.syms.declTok
  if ~self.syms.IsColOneLabel(okDecl) then exit. ! a PARAMETER is not a column-1 declaration
  if band(self.DeclAttrBits(okDecl), ab:over + ab:dim) then exit.
  okRes = 1

! ---- is lsPos one of this scope's depth-0 line starts? ----
SmIsLineStart routine
  data
sz  long,auto
  code
  lsOk = 0
  loop sz = 1 to records(SmLineQ)
    get(SmLineQ, sz)
    if errorcode() then break.
    if sml:smlPos = lsPos then lsOk = 1 ; break.
    if sml:smlPos > lsPos then break.
  end

! ---- the token at gPos starts its line with pure indent (column 1 is a LABEL position) ----
SmIndentOk routine
  data
iz  long,auto
ic  string(1),auto
  code
  indOk = 0
  get(self.tk.tokens, gPos)
  if errorcode() then exit.
  if self.tk.tokens.strBefore &= NULL then exit.
  if ~size(self.tk.tokens.strBefore) then exit.
  loop iz = 1 to size(self.tk.tokens.strBefore)
    ic = self.tk.tokens.strBefore[iz]
    case val(ic)
    of 32 orof 9
      ! plain indent
    else
      exit ! a comment, a bar, or the CRLF of a continuation
    end
  end
  indOk = 1

! ---- matching ')' for the '(' at mpOpen (0 = none) ----
SmMatchParen routine
  data
mz  long,auto
md  long,auto
  code
  mpClose = 0
  md      = 0
  loop mz = mpOpen to mainEnd
    gPos = mz
    do SmGet
    if ~gOk then exit.
    if gTy = vt:literal then cycle. ! a bracket INSIDE a quoted literal is text, not structure
    case gTxt
    of '('
      md += 1
    of ')'
      md -= 1
      if ~md then mpClose = mz ; exit.
      if md < 0 then exit.
    end
  end

! ---- split spIn at its FIRST '.' -> spRoot / spSuf (a bare name gives spSuf = '') ----
SmSplitRoot routine
  data
dz  long,auto
nz  long,auto
  code
  spRoot = spIn
  spSuf  = ''
  nz = len(clip(spIn))
  if ~nz then spRoot = '' ; exit.
  dz = instring('.', spIn, 1, 1)
  if dz > 1 and dz < nz
    spRoot = spIn[1 : dz - 1]
    spSuf  = spIn[dz + 1 : nz]
  elsif dz
    spRoot = '' ! a leading or trailing dot - not a name we model
  end

! ---- one token into gTxt / gTU / gTy / gLv / gNull ----
SmGet routine
  gOk   = 0
  gNull = 0
  gTxt  = ''
  gTU   = ''
  gTy   = ' '
  gLv   = ' '
  if gPos < 1 then exit.
  get(self.tk.tokens, gPos)
  if errorcode() then exit.
  gTy = self.tk.tokens.type
  gLv = self.tk.tokens.level
  if not self.tk.tokens.tok &= NULL
    if size(self.tk.tokens.tok) > size(gTxt) then exit.            ! the token does NOT FIT.
                                                                   !   gTxt is a fixed STRING, so a longer token arrives
                                                                   !   TRUNCATED, and the whitespace guards downstream
                                                                   !   (TsLitOk, TsLitSpaceless, SkReplOk) then scan the
                                                                   !   short copy and answer 'provably space-free' for a
                                                                   !   literal whose first space sits past the cut - which
                                                                   !   licenses removing a clip() that was doing real work.
                                                                   !   gOk stays 0, so every caller reads this as 'cannot
                                                                   !   see it' and refuses, which is the house answer.
    gTxt = self.tk.tokens.tok
    gTU  = upper(self.tk.tokens.tok)
  else
    gNull = 1
  end
  gOk = 1

! ------------------------------------------------------------------------------------
! the sm:* fact for ONE body. Linear - the table holds one row per proc/method in
! the file, and a name that appeared twice was already collapsed to sm:none by SmRecord.
! No parent-class walk: a summary is filed under the class whose body we READ, and an
! inherited body is deliberately not credited to the derived class (under-reach).
! ------------------------------------------------------------------------------------
VitEngine.SummaryOf Procedure(STRING pOwnerU, STRING pNameU)
z    long,auto
oU   string(vs:maxName),auto
nU   string(vs:maxName),auto
  code
  if self.sums &= NULL then return sm:none.
  oU = upper(pOwnerU)
  nU = upper(pNameU)
  if ~nU then return sm:none.
  loop z = 1 to records(self.sums)
    get(self.sums, z)
    if errorcode() then break.
    if self.sums.smOwnerU <> oU or |
       self.sums.smNameU  <> nU
      cycle
    end
    return self.sums.smFact
  end
  return sm:none ! no row = another file, or a body we refused

! ------------------------------------------------------------------------------------
! the sm:* fact of the call occupying EXACTLY [pFirst..pLast] - nothing before it,
! nothing after it, so the value the caller sees IS the value the body returned.
! Two shapes only:
!     self.Method(...)   keyed on pSelfClassU, and only when the prototype is visible AND
!                        not VIRTUAL (MethodIsVirtual must answer exactly 0);
!     MyProc(...)        keyed on '' - a plain procedure DEFINED in this file.
! A call on any other receiver (other.Method(), self.member.Method()) is sm:none: knowing
! which body would run means knowing the receiver's class, which this is not the place for.
! pNameOut carries the callee's SOURCE-case name back, for the log line that has to name
! the evidence.
! ------------------------------------------------------------------------------------
VitEngine.SummaryOfCallAt Procedure(LONG pFirst, LONG pLast, STRING pSelfClassU, *STRING pNameOut)
mOpen   long
mClose  long
nmTxt   string(vs:maxName),auto
nmU     string(vs:maxName),auto
oU      string(vs:maxName),auto
tTxt    string(vs:maxName),auto
  code
  pNameOut = ''
  if pLast <= pFirst then return sm:none.
  get(self.tk.tokens, pFirst)
  if errorcode() then return sm:none.
  if self.tk.tokens.tok &= NULL then return sm:none.
  if self.tk.tokens.type <> vt:label then return sm:none.
  nmTxt = self.tk.tokens.tok
  if instring('.', clip(nmTxt), 1, 1) then return sm:none. ! a MERGED dotted name is never a call - the tokenizer splits before a '('
  get(self.tk.tokens, pFirst + 1)
  if errorcode() then return sm:none.
  if self.tk.tokens.tok &= NULL then return sm:none.
  tTxt = self.tk.tokens.tok
  if tTxt = '('                                            ! ---- MyProc(...)
    mOpen = pFirst + 1
    do MatchParen
    if mClose <> pLast then return sm:none.
    pNameOut = nmTxt
    return self.SummaryOf('', upper(nmTxt))
  end
  if tTxt <> '.' or |
     upper(nmTxt) <> 'SELF'                                ! only SELF names a class we can key on
    return sm:none
  end
  oU = upper(pSelfClassU)
  if ~oU         or |
     pLast < pFirst + 4
    return sm:none
  end
  get(self.tk.tokens, pFirst + 2)
  if errorcode() then return sm:none.
  if self.tk.tokens.tok &= NULL then return sm:none.
  if self.tk.tokens.type <> vt:label then return sm:none.
  nmTxt = self.tk.tokens.tok
  nmU   = upper(nmTxt)
  get(self.tk.tokens, pFirst + 3)
  if errorcode() then return sm:none.
  if self.tk.tokens.tok &= NULL then return sm:none.
  tTxt = self.tk.tokens.tok
  if tTxt <> '(' then return sm:none.
  mOpen = pFirst + 3
  do MatchParen
  if mClose <> pLast then return sm:none.
  if self.syms.MethodIsVirtual(oU, nmU) <> 0 then return sm:none. ! -1 = no prototype visible, 1 = VIRTUAL
  pNameOut = nmTxt
  return self.SummaryOf(oU, nmU)

MatchParen routine
  data
d   long,auto
z   long,auto
tx  string(vs:maxName),auto
  code
  mClose = 0
  d      = 0
  loop z = mOpen to pLast
    get(self.tk.tokens, z)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL or |
       self.tk.tokens.type = vt:literal
      cycle
    end
    tx = self.tk.tokens.tok
    case tx
    of '('
      d += 1
    of ')'
      d -= 1
      if ~d then mClose = z ; break.
      if d < 0 then break.
    end
  end

! ------------------------------------------------------------------------------------
! what a StringTheory method name COULD do to the SPACES in its buffer, on its
! NAME alone - the one place this whitelist lives. The caller still has to validate the
! ARGUMENTS: removeByte(38) keeps a spaceless buffer spaceless but only removeByte(32)
! MAKES one, and replace(a, b) keeps it only while b cannot contain a space.
! This is NOT the ts:* ladder. That one asks about TRAILING spaces and about blindness,
! for a pass that INSERTS a clip; this one asks the single question "can this use put a
! space INTO the buffer", which is what a summary has to survive.
! Anything absent is sk:bad, which is the safe direction.
! ------------------------------------------------------------------------------------
VitEngine.SmMethodKind Procedure(STRING pMethodU)
  code
  case upper(pMethodU)
  of   'GETVALUE' orof 'GETVALUEPTR' orof 'CLIPLENGTH' orof 'LEN' orof 'LENGTH' orof 'LENGTHA' |
     orof 'FINDCHAR' orof 'FINDCHARS' orof 'FINDBYTE' orof 'CONTAINSCHAR' orof 'CONTAINSBYTE'  |
     orof 'SUB' orof 'SLICE' orof 'GETLINE' orof 'LINES' orof 'INSTRING' orof 'BETWEEN'        |
     orof 'EQUALS' orof 'COMPARE' orof 'STARTSWITH' orof 'ENDSWITH'
    return sk:read          ! reads self.value and writes nothing
  of   'CLIP' orof 'TRIM'
    return sk:keep          ! only ever REMOVES from the ends
  of   'REMOVEBYTE'
    return sk:strip
  of   'REMOVEFROMPOSITION' ! deletes a span and nothing else, so a
    return sk:keep          !   spaceless buffer stays spaceless. WITHOUT this it
                            !   is sk:bad and TrailingSpaces refuses everything
                            !   below it.
  of   'SETVALUE'
    return sk:store
  of   'REPLACE'
    return sk:repl
  of   'SETLENGTH'
    return sk:trunc         ! GROWS by padding with byte 32 - see the DEVIATION on BuildSummaries
  end
  return sk:bad

! ------------------------------------------------------------------------------------
! can the use of a StringTheory receiver whose ROOT token is at pTok put a SPACE
! into the buffer?  1 = provably not.  Every bail returns 0, which is the safe direction.
! sk:store returns 0 here on purpose: a setValue is only ever a keeper when its argument
! is itself a spaceless call, and reading a summary to answer a question ASKED BY the
! summary pass is the compositional v2 this round does not do.
! ------------------------------------------------------------------------------------
VitEngine.SpaceKeepUse Procedure(LONG pTok)
tTxt   string(vs:maxName)
tU     string(vs:maxName)
mthU   string(vs:maxName),auto
knd    byte
mOpen  long
mClose long
lastC  long
argS   long
d      long
z      long,auto
dp     long,auto
nz     long,auto
lz     long,auto
lc     string(1)
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  tTxt = self.tk.tokens.tok
  tU   = upper(tTxt)
  nz   = len(clip(tU))
  dp   = instring('.', clip(tU), 1, 1)
  if dp > 1 and dp < nz                                     ! ---- a MERGED property token: recv._DataEnd, recv.valuePtr, ...
    if tU[dp + 1 : nz] <> '_DATAEND' then return 0.         ! ONLY the length. recv.valuePtr hands out a &STRING that can be
    get(self.tk.tokens, pTok + 1)                           !   written through, and any other property is one we have not read
    if errorcode() then return 0.
    if self.tk.tokens.tok &= NULL then return 0.
    tTxt = self.tk.tokens.tok
    if tTxt = '=' then return 0.                            ! recv._DataEnd = n WRITES, and growing it exposes the slack behind
    if len(clip(tTxt)) = 2 and tTxt[2] = '='
      case val(tTxt[1])
      of 43 orof 45 orof 42 orof 47 orof 37 orof 94 orof 38 ! '+' orof '-' orof '*' orof '/' orof '%' orof '^' orof '&'
        return 0                                            ! a compound assignment writes it too
      end
    end
    if pTok > 1                                             ! ... and it must not be an ARGUMENT: a *LONG parameter is a write
      get(self.tk.tokens, pTok - 1)
      if ~errorcode()
        if not self.tk.tokens.tok &= NULL
          tTxt = self.tk.tokens.tok
          if tTxt = '(' or tTxt = ',' then return 0.
        end
      end
    end
    return 1
  end
  if dp then return 0.                                      ! a leading or trailing dot - not a name we model
  get(self.tk.tokens, pTok + 1)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  tTxt = self.tk.tokens.tok
  if tTxt <> '.' then return 0.                             ! a BARE mention - foo(st), st &= other - may alias the buffer
  get(self.tk.tokens, pTok + 2)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.type <> vt:label then return 0.
  mthU = upper(self.tk.tokens.tok)
  get(self.tk.tokens, pTok + 3)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  tTxt = self.tk.tokens.tok
  if tTxt <> '(' then return 0.                             ! the tokenizer only leaves recv . name unmerged before a '('
  mOpen = pTok + 3
  do SkMatch
  if ~mClose then return 0.
  knd = self.SmMethodKind(mthU)
  case knd
  of sk:read orof sk:keep orof sk:strip
    return 1                                                ! reads, and the two removal families: a space can only leave
  of sk:repl
    do SkReplOk
    return knd                                              ! SkReplOk overwrites knd with 1 or 0
  end
  return 0

! ---- replace(old, new): the REPLACEMENT decides. Exactly two arguments, the last one a
!      single quoted literal with no space, no tab and no '<' escape in it. ----
SkReplOk routine
  knd   = 0
  lastC = 0
  d     = 0
  loop z = mOpen + 1 to mClose - 1
    get(self.tk.tokens, z)
    if errorcode() then exit.
    if self.tk.tokens.tok &= NULL or |
       self.tk.tokens.type = vt:literal
      cycle
    end
    tTxt = self.tk.tokens.tok
    if tTxt = '('
      d += 1
    elsif tTxt = ')'
      d -= 1
    elsif ~d and tTxt = ','
      if lastC then exit.                                         ! three or more arguments - not the form we model
      lastC = z
    end
  end
  if ~lastC then exit.
  argS = lastC + 1
  if argS <> mClose - 1 then exit.                                ! the replacement must be ONE token
  get(self.tk.tokens, argS)
  if errorcode() then exit.
  if self.tk.tokens.tok &= NULL then exit.
  if self.tk.tokens.type <> vt:literal then exit.                 ! a computed replacement - we cannot see what is in it
  tTxt = self.tk.tokens.tok
  nz = len(clip(tTxt))
  if nz < 2 then exit.
  loop lz = 2 to nz - 1
    lc = tTxt[lz]
    case val(lc)
    of 32 orof 9
      exit ! the replacement IS whitespace
    of 60
      exit ! a '<' escape - it may BE a space under another name
    end
  end
  knd = 1

! ---- matching ')' for the '(' at mOpen ----
SkMatch routine
  data
sz  long,auto
sd  long,auto
sx  string(vs:maxName),auto
  code
  mClose = 0
  sd     = 0
  loop sz = mOpen to records(self.tk.tokens)
    get(self.tk.tokens, sz)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL or |
       self.tk.tokens.type = vt:literal
      cycle
    end
    sx = self.tk.tokens.tok
    case sx
    of '('
      sd += 1
    of ')'
      sd -= 1
      if ~sd then mClose = sz ; break.
      if sd < 0 then break.
    end
  end

! ------------------------------------------------------------------------------------
! is the use whose root token is at pTok exactly `recv.removeByte(32)`?  That is
! the ONE operation this round accepts as MAKING a buffer spaceless - it removes every
! occurrence of the byte from the whole value (StringTheory.RemoveByte, checked).
! ------------------------------------------------------------------------------------
VitEngine.SpaceMakeUse Procedure(LONG pTok)
tTxt   string(vs:maxName),auto
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  if instring('.', clip(upper(self.tk.tokens.tok)), 1, 1) then return 0.
  get(self.tk.tokens, pTok + 1)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  tTxt = self.tk.tokens.tok
  if tTxt <> '.' then return 0.
  get(self.tk.tokens, pTok + 2)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  if upper(self.tk.tokens.tok) <> 'REMOVEBYTE' then return 0.
  get(self.tk.tokens, pTok + 3)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  tTxt = self.tk.tokens.tok
  if tTxt <> '(' then return 0.
  get(self.tk.tokens, pTok + 4)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.type <> vt:Integer then return 0.
  tTxt = self.tk.tokens.tok
  if tTxt <> '32' then return 0. ! only removing the SPACE byte makes the buffer spaceless
  get(self.tk.tokens, pTok + 5)
  if errorcode() then return 0.
  if self.tk.tokens.tok &= NULL then return 0.
  tTxt = self.tk.tokens.tok
  if tTxt <> ')' then return 0.  ! removeByte(32, from) is a RANGE - it does not clear the whole value
  return 1

! ====================================================================================
! ------------------------------------------------------------------------------------
! BUILTIN DeadGuard - a guard THIS TOOL emitted, deleted when an earlier guard in the
! same procedure proves it can never fire.
!
! st-getvalue-slice rewrites st.getValue() into
!     choose(st._DataEnd < 1, '', st.valuePtr[1 : st._DataEnd])
! and the choose() is load-bearing in general: valuePtr is UNBOUND on an empty
! StringTheory, so the raw slice would fault. But in code like
! preprocessor.EvalPPCondition it cannot fire:
!
!     if c._dataEnd < 1 then return true.          <- proves it, for the rest of the proc
!     p = c.findByte(61)
!     if p > 1
!       ...
!     else
!       nm = left(choose(c._DataEnd < 1, '', c.valuePtr[1 : c._DataEnd]))
!
! so the guard is noise the tool put there itself. It becomes
!     nm = left(c.valuePtr[1 : c._DataEnd])
!
! WHY THIS DIRECTION IS SAFE AND THE OPPOSITE ONE IS NOT. Asked to prove bounds so a
! slice could REPLACE a clamp, the answer was no: a proof that is wrong by one turns a
! clamp into a GPF in somebody's shipped program. Here the proof only lets a test that
! cannot fire be deleted - if it is wrong, the guard was doing nothing anyway, and the
! cost of being wrong is a missed simplification rather than a crash. Same machinery,
! opposite risk.
!
! WHAT IT DEMANDS BEFORE EDITING - all of it, or it leaves the line alone:
!   * the EXACT shape above, on ONE receiver: the same name in all three places;
!   * a dominating guard `if <recv>._DataEnd < 1 then return` earlier in the same
!     procedure. DOMINATING is checked by walking back with the tokenizer's level marks
!     and only accepting a guard reached at nesting zero - a guard inside a branch we
!     are not in proves nothing;
!   * NOTHING BETWEEN THEM THAT COULD CHANGE THE RECEIVER. Any call on it that is not on
!     the const list below kills the fact. The list is deliberately short and additive:
!     an unknown method is assumed to MUTATE, so a new ST method cannot silently make
!     this unsound.
!   * the scope must pass AutoScopePrep - no GOTO / COMPILE / OMIT, which is what makes
!     "earlier in the token stream" mean "earlier in execution".
! ------------------------------------------------------------------------------------
VitEngine.BuiltinDeadGuard Procedure(StringTheory pLog)
s        long,auto
scKind   byte,auto
i        long,auto
e        long                                                    ! AUTO unsafe: read before write
keep     long                                                    ! AUTO unsafe: read before write
mainEnd  long,auto
recvU    string(vs:maxName)                                      ! AUTO unsafe: read before write
lineNo   long,auto
fol      byte,auto
changes  long
sb       StringTheory                                            ! strBefore is a &STRING of any length - a fixed
                                                                 !   STRING would pad it back with the spaces we
                                                                 !   are trying to remove
  code
  if self.syms &= NULL then return 0.
  loop s = records(self.syms.scopes) to 1 by -1                  ! BACKWARDS. Deleting tokens moves every scope
    get(self.syms.scopes, s)                                     !   AFTER this one, and the startTok/endTok in
    if errorcode() then break.                                   !   the rows were recorded before we started, so
    scKind = self.syms.scopes.kind                               !   visit the later ones FIRST while those
    if scKind <> vs:scProc and scKind <> vs:scMethod then cycle. ! numbers are still true - the reparse
    self.acScopeId = 0                                           !   that fixes them up does not happen until
    self.AutoScopePrep(s)                                        !   this builtin returns
    if self.acBail then cycle.                                   ! GOTO / COMPILE / OMIT / no CODE - order not provable
    mainEnd = self.acMainEnd
    i = self.acCodeT + 1
    loop while i <= mainEnd
      if ~self.DgShapeAt(i, recvU, e, keep)                      ! the emitted choose(), on one receiver
        i += 1
        cycle
      end
      if ~self.DgProvenNonEmpty(recvU, i, dg:wantGuard)          ! is there a dominating guard, unspoilt?
        i += 1
        cycle
      end
      get(self.tk.tokens, i)
      lineNo = self.tk.tokens.lineNo
      fol = self.tk.tokens.firstOnLine                           ! choose( held the line's start and indent: the
      if self.tk.tokens.strBefore &= NULL                        !   survivor must inherit BOTH. A NULL strBefore
        sb.Free()                                                !   is just a zero-length one - it is what
      else                                                       !   SetStrBefore stores for '' - so it is the
        sb.SetValue(self.tk.tokens.strBefore)                    !   ordinary "(choose" case, not a refusal
      end
      self.tk.DeleteToks(e, e)                                   ! the closing ')' FIRST - deleting forwards would
      self.tk.DeleteToks(i, keep - 1)                            !   shift the index we just computed. Everything
      self.tk.SetStrBefore(i, sb.GetValue())                     ! else valuePtr keeps the space from ", " - "left( c."
      if fol
        get(self.tk.tokens, i)
        if ~errorcode()
          self.tk.tokens.firstOnLine = true
          put(self.tk.tokens)
        end
      end
      self.wantReparse = true                                    ! tokens gone; later builtins must see the new stream
      changes += 1
      pLog.append('BUILTIN DeadGuard line ' & self.tk.MapLine(lineNo) & ': choose(' & clip(recvU) & |
                  '._DataEnd << 1, ...) cannot fire - an earlier guard already returned on empty<13,10>')
      mainEnd -= (keep - i) + 1                                  !   up to R.valuePtr goes, and so does the ')'.
                                                                 ! Do NOT advance i: the
                                                                 !   survivor sits at i now, and a scope may hold
                                                                 !   more than one - the deferred pass runs ONCE,
                                                                 !   so a break here would leave the rest forever
    end
  end
  if changes then pLog.append('BUILTIN DeadGuard: ' & changes & ' guard(s) removed this pass<13,10>').
  return changes

! ------------------------------------------------------------------------------------
! Is the emitted shape at pIx? Returns the receiver, the index of the closing ')', and
! the index of the one token that must SURVIVE - everything from pIx up to the token
! before it goes, and so does the ')'.
!
!   choose ( R._DataEnd < 1 , '' , R.valuePtr [ 1 : R._DataEnd ] )
!                                  ^ pKeep                        ^ pEnd
!
! The receiver must be the SAME name in both places - a choose() written over two
! different objects is not ours and is not decidable here. It is read through DgRecvAt,
! so `self.buf` is as good a receiver as `c`.
! ------------------------------------------------------------------------------------
VitEngine.DgShapeAt Procedure(LONG pIx, *STRING pRecvU, *LONG pEnd, *LONG pKeep)
memU     string(vs:maxName)                          ! AUTO unsafe: read before write
r2       string(vs:maxName)                          ! AUTO unsafe: read before write
m2       string(vs:maxName)                          ! AUTO unsafe: read before write
nx       long                                        ! AUTO unsafe: read before write
nx2      long                                        ! AUTO unsafe: read before write
  code
  pRecvU = '' ; pEnd = 0 ; pKeep = 0
  if upper(self.tk.GetTok(pIx)) <> 'CHOOSE' then return 0.
  if self.tk.GetTok(pIx + 1) <> '(' then return 0.
  if ~self.DgRecvAt(pIx + 2, pRecvU, memU, nx) then return 0.
  if memU <> '._DATAEND' then return 0.
  if self.tk.GetTok(nx)     <> '<' then return 0.
  if self.tk.GetTok(nx + 1) <> '1' then return 0.
  if self.tk.GetTok(nx + 2) <> ',' then return 0.
  if self.tk.GetTok(nx + 3) <> '''''' then return 0. ! the empty literal
  if self.tk.GetTok(nx + 4) <> ',' then return 0.
  if ~self.DgRecvAt(nx + 5, r2, m2, nx2) then return 0.
  if r2 <> pRecvU then return 0.
  if m2 <> '.VALUEPTR' then return 0.
  pKeep = nx + 5
  pEnd  = self.tk.MatchLeftBracket('(', ')', pIx + 1)
  if ~pEnd then return 0.
  return 1

!===============================================================================================
! Is this receiver member the TARGET of an assignment rather than a read?
!
! Walks forward past any subscript - `c.valuePtr[1] = ' '` has to skip the [1] - and answers 1
! when the next thing at that level is a plain '='. A compound `+=` counts too: it writes.
! A '==' would be a comparison, but Clarion has no such operator, so a bare '=' after a member
! at statement level is a store.
!===============================================================================================
VitEngine.DgMemberIsTarget Procedure(LONG pTok)
z    long,auto
z0   long,auto
dep  long,auto
t2   string(2),auto
  code
  ! A STORE HAPPENS AT STATEMENT START. `c._DataEnd = 0` is one; the '=' inside
  ! `if c._DataEnd = 0` is a COMPARISON, and reading that as a store refused a
  ! simplification that was perfectly safe.
  get(self.tk.tokens, pTok)
  if errorcode() then return 0.
  if ~self.tk.tokens.firstOnLine
    if pTok < 2 then return 0.
    get(self.tk.tokens, pTok - 1)
    if errorcode() or self.tk.tokens.tok &= NULL then return 0.
    ! AND THEN / ELSE OPEN A STATEMENT TOO. `if f then c._DataEnd = 0.` puts a store in an
    ! inline THEN clause, where it is neither first on its line nor after a ';' - so it read as
    ! harmless and three guards went where one should have. My own spec for this said
    ! EOL / ';' / THEN / ELSE, and those four are what is tested here.
    ! THE FIFTH POSITION IS NOT A POSITION IN THE LANGUAGE, AND IS STILL WORTH ACCEPTING.
    ! A statement after a TERMINATOR dot on the same line - `if f then g = f. c._DataEnd = 0` -
    ! had an arm added for it, the probe still lost the guard, and rather than argue the point
    ! the compiler was asked: that line is refused with "Expected: <LINEBREAK> ;" AT THE
    ! SECOND STATEMENT'S FIRST CHARACTER, while the same pair joined by a ';' compiles
    ! (TestData\r233leg.clw case 2, against controls 1 and 3). Only a line break or a ';' may
    ! follow a terminator dot - both of which this test already accepts - so on code that
    ! COMPILES the vt:end arm below is unreachable, and the defect the probe was really seeing
    ! is the SPLIT MEMBER handled further down.
    ! It stays anyway, and deliberately. A general-use tool is pointed at whatever a user has,
    ! and some of it will not compile. Without this arm a member here reads as mid-expression,
    ! which means a READ, which DELETES a guard - the aggressive direction on input we cannot
    ! parse into a legal program. Accepting the position costs nothing that compiles and makes
    ! the answer on input that does not the conservative one. vt:end rather than a text test on
    ! '.', because the word END lands in the same position and deserves the same answer.
    ! Pinned by dgtermdot-test.txt / TestData\dgtermdot.clw.
    if self.tk.tokens.tok <> ';'               |
       and upper(self.tk.tokens.tok) <> 'THEN' |
       and upper(self.tk.tokens.tok) <> 'ELSE' |
       and self.tk.tokens.type <> vt:end
      return 0                                        ! mid-expression: a read
    end
  end
  ! A MEMBER MAY BE THREE TOKENS, AND THIS WALK COUNTED ON ONE. DgMemberAt reads both
  ! spellings (:5645-5647) and DgOpenAfter adds the two extra tokens for the split one
  ! (:5688) - this walk started one token past the RECEIVER either way. On `c ._DataEnd = 0`
  ! it therefore met the qualifying dot as a size-1 token, and the single-character block
  ! below answers `read` to anything it does not recognise: it said READ two tokens before
  ! the '=' it was looking for, the store walked through the proof as harmless, and the
  ! guard was deleted - leaving a slice whose end precedes its start.
  ! THE SPELLING IS ORDINARY, NOT EXOTIC. The label merge wants NO whitespace in front of the
  ! dot (vitTokenize.clw:466-515), and one space there is enough to leave the member as three
  ! tokens. Clarion 11 accepts that space - asked, not argued: `grp .n = 0` compiles, while
  ! `grp . n = 0` and `grp. n = 0` are refused, so it is a space AFTER the dot that turns it
  ! into a terminator, which is the rule the tokenizer already implements. So this arrives on
  ! code that COMPILES, with no terminator dot anywhere near it.
  ! Pinned by splitmember-test.txt / TestData\splitmember.clw.
  ! An `if tok = '.' then cycle` at the END of this loop would look like the answer to this
  ! case and could never fire: a '.' token is ONE character, so the single-character block
  ! above always answers first.
  z0 = pTok
  if self.DgIsMemberDot(pTok + 1) then z0 = pTok + 2. ! split: <receiver> . <member>
  dep = 0
  loop z = z0 + 1 to z0 + 40
    get(self.tk.tokens, z)
    if errorcode() then return 0.
    if self.tk.tokens.tok &= NULL then cycle.
    if size(self.tk.tokens.tok) = 1
      case self.tk.tokens.tok
      of '[' orof '('
        dep += 1
        cycle
      of ']' orof ')'
        dep -= 1
        cycle
      end
      if dep then cycle.
      if val(self.tk.tokens.tok) = 10 then return 0. ! end of statement, no '=' seen
      if self.tk.tokens.tok = ';' then return 0.
      if self.tk.tokens.tok = '=' then return 1.     ! a store into the member
      return 0                                       ! anything else - it was a read
    end
    if dep then cycle.
    ! A COMPOUND ASSIGN IS ONE TWO-CHARACTER TOKEN, so it never reached the
    ! single-character test above and fell through as a read. `c._DataEnd -= 1`
    ! shortens the buffer as surely as a plain store does.
    t2 = self.tk.tokens.tok
    if t2[2] = '='
      if t2[1] = '+' or t2[1] = '-' or t2[1] = '*' or t2[1] = '/' or t2[1] = '&' or t2[1] = '%' or t2[1] = '^'
        return 1
      end
    end
    return 0
  end
  return 0

!===============================================================================================
! Is the statement at pTok nothing but a bare name - i.e. a call with its brackets left off?
!
! True when the token is first on its line and the next thing is the end of the statement. That
! is the one call spelling with no bracket and no keyword to recognise it by.
!===============================================================================================
VitEngine.DgStmtIsBareName Procedure(LONG pTok)
  code
  get(self.tk.tokens, pTok + 1)
  if errorcode() then return 1.                    ! end of file - treat as a statement
  if self.tk.tokens.tok &= NULL then return 1.
  if size(self.tk.tokens.tok) = 1
    if val(self.tk.tokens.tok) = 10 then return 1. ! EOL
    if self.tk.tokens.tok = ';' then return 1.
    if self.tk.tokens.tok = '.'
      ! A TRAILING DOT IS NOT A QUALIFIER. `if f then Wipe9.` ends with Clarion's
      ! statement terminator, and reading it as the '.' of a dotted name let that call
      ! walk straight through. A qualifying dot has a NAME after it; a terminator does not.
      get(self.tk.tokens, pTok + 2)
      if errorcode() then return 1.
      if self.tk.tokens.tok &= NULL then return 1.
      if self.tk.tokens.type = 'b' then return 0.  ! a name follows: it qualifies
      return 1                                     ! nothing follows: a terminator
    end
  end
  return 0

!===============================================================================================
! Is this receiver a simple LOCAL of the procedure we are inside?
!
! A PROCEDURE reached without parentheses is invisible to the opaque-call arm, and a ROUTINE is
! handled by the DO arm - but neither can touch another procedure's locals. Module-level and
! global data they can. A dotted receiver answers 0 too: `gs.buf` names storage inside something
! this cannot see the lifetime of.
!===============================================================================================
VitEngine.DgRecvIsLocal Procedure(STRING pRecvU, LONG pAtTok)
sy    long,auto
rootU string(vs:maxName),auto
scr   long,auto
  code
  if ~pRecvU then return 0.
  ! *** THE ROOT IS WHAT HAS TO BE LOCAL, NOT THE WHOLE NAME. *** `gs.buf` is reachable by a
  ! parenless call exactly when `gs` is - so refusing every dotted receiver refused a shape
  ! that is perfectly safe and is pinned by dotrecv-test.
  rootU = self.NameRoot(pRecvU)
  if ~rootU then return 0.
  if self.syms &= NULL then return 0.
  loop sy = 1 to records(self.syms.syms)
    get(self.syms.syms, sy)
    if errorcode() then break.
    if self.syms.syms.nameU <> rootU then cycle.
    scr = self.syms.syms.scopeId
    get(self.syms.scopes, scr)
    if errorcode() then cycle.
    if self.syms.scopes.startTok > pAtTok or self.syms.scopes.endTok < pAtTok then cycle.
    if self.syms.scopes.kind <> vs:scProc and self.syms.scopes.kind <> vs:scMethod then cycle.
    ! *** AND A TRUE LOCAL, WHICH A PARAMETER IS NOT. *** A CLASS parameter is BY REFERENCE
    ! and SELF is the caller's object, so both name storage a parenless call CAN reach. The
    ! sibling gates all demand a column-1 declaration and refuse isRef; this one did not.
    if self.syms.syms.isRef then cycle.
    if ~self.syms.IsColOneLabel(self.syms.syms.declTok) then cycle.
    return 1
  end
  return 0

! ------------------------------------------------------------------------------------
! ONE backward walk, two facts. Does something earlier in this procedure prove pWant
! about pRecvU at pIx, with nothing in between that could have unproved it? Walks BACK
! to the CODE statement.
!
!   dg:wantGuard   pRecvU is NOT EMPTY, from   if R._DataEnd < 1 then return.
!   dg:wantTrim    pRecvU has NO LEADING SPACE, from   R.Trim()   or   R.setLeft()
!
! Two separate questions are asked of every token on the way back, and they are NOT
! asked at the same nesting:
!
!   * COULD THIS HAVE CHANGED THE RECEIVER? Asked at EVERY nesting. A mutation inside a
!     branch we did not come through cannot be ruled out cheaply, and a wrong answer here
!     is unsound, so any use of the receiver that is not on the const list below kills the
!     fact wherever it appears. An unknown method is assumed to MUTATE, so a new
!     StringTheory method cannot silently make this unsound.
!   * DOES THIS PROVE IT? Asked only where the statement DOMINATES us, which is tracked
!     with the tokenizer's level marks. Going backwards a '-' means a block closed above
!     us (nest+1) and a '+' means one opened (nest-1), so a guard is read at the '+' when
!     nest returns to zero - i.e. from a block that opened AND closed as a SIBLING
!     statement before us, which is exactly the shape of
!         if c._DataEnd < 1 then return.
!     Reaching our line at all means that IF did not fire. A guard nested one deeper
!     (case 4 in the fixture) never brings nest back to zero, so it is never believed.
!
!     An ELSE is the other way to be somewhere we did not come through, and it needs its
!     own mark: walking back out of an else arm, everything until the owning IF is code
!     that did NOT run. inArm says so. It is set on a '/' seen at OUR level and cleared
!     by the '+' that owns it, so an elsif chain of any length clears in one go. Without
!     it a Trim() in the THEN arm would be believed while we sit in the ELSE arm.
!
! Only the one-line THEN RETURN form of the guard is recognised. The block form
!     if c._DataEnd < 1 ; return ; end
! is a miss, not a wrong answer: it simply leaves the choose() in place. Likewise only
! the NO-ARGUMENT Trim() proves anything - Trim('*') strips a different alphabet, and
! spaces would survive it. setLeft() is decided by its What argument instead, which can
! be a SUM - see DgSetLeftProves.
!
! The receiver is written two ways by the tokenizer and both are read here: a property
! merges into one token (c._DataEnd, c.valuePtr) but a CALL splits into three (c . Free).
! Reading only the merged form would silently see no mutations at all.
! ------------------------------------------------------------------------------------
VitEngine.DgProvenNonEmpty Procedure(STRING pRecvU, LONG pIx, STRING pWant)
j        long,auto
nest     long
inArm    byte
lv       string(1),auto
mU       string(vs:maxName),auto
  code
  loop j = pIx - 1 to self.acCodeT + 1 by -1
    get(self.tk.tokens, j)
    if errorcode() then break.
    lv = self.tk.tokens.level
    ! *** A ROUTINE CAN EMPTY ANY BUFFER, AND `do` DOES NOT MENTION THE RECEIVER. *** This
    ! walk looks for mutations THROUGH the receiver, so a bare `do Wipe` - where Wipe does
    ! c.free() - was invisible, the guard read as dead and was deleted, and what was left was
    ! `nm = left(c.valuePtr[1 : c._DataEnd])` on an empty buffer. A slice whose end precedes
    ! its start, with no bounds checking behind it: the GPF this builtin's own banner promises
    ! away. Every sibling analysis already kills on DO - KnownRanges at lnDo, TrailingSpaces
    ! in two places - and this one walker was the odd one out.
    if self.tk.tokens.type = vt:reservedWord
      if upper(self.tk.tokens.tok) = 'DO' then return 0. ! cannot prove across a DO
      ! AND A CALL IS THE OTHER SPELLING OF THE SAME THING. A ROUTINE reached by DO and a
      ! PROCEDURE reached by CALL are both opaque here: either can empty any buffer this walk
      ! can see, and neither mentions the receiver. The DO half was closed first and this one
      ! left open, so `Wipe()` between a guard and its use still had the guard deleted.
      if upper(self.tk.tokens.tok) = 'CALL' then return 0.
    end
    ! AND A PLAIN `Wipe()` IS A CALL WITH NO KEYWORD IN FRONT OF IT. CALL is only
    ! Clarion's DYNAMIC call, so covering DO and CALL still left the ordinary spelling -
    ! the one the probe used - walking straight through. Any call that is not on the pure
    ! list can empty any buffer, so it ends the proof, exactly as KnownRanges treats one.
    if self.tk.tokens.tok = '(' and j > 2
      get(self.tk.tokens, j - 2)                         ! A BARE CALL ONLY.
      if ~errorcode() and not self.tk.tokens.tok &= NULL !   `c.trim()` is a METHOD
        if self.tk.tokens.tok = '.'                      !   call, and the member
          get(self.tk.tokens, j)                         !   logic below is what
          cycle                                          !   decides about those.
        end                                              !   Treating them as opaque
      end                                                !   killed DeadLeft dead:
                                                         !   its whole PROOF is a
                                                         !   Trim() or setLeft() call
                                                         !   on the receiver, and the
                                                         !   walk met the proof's own
                                                         !   '(' before it could read
                                                         !   it. 0 of 5 conversions.
      get(self.tk.tokens, j - 1)
      if ~errorcode() and not self.tk.tokens.tok &= NULL
        if self.tk.tokens.type = 'b'
          if ~self.dgPure.findChars(' ' & clip(upper(self.tk.tokens.tok)) & ' ') then return 0.
        end
      end
      get(self.tk.tokens, j)                             ! restore the walk's buffer
    end
    ! A PARENLESS CALL IS A BARE NAME STANDING AS A WHOLE STATEMENT. Clarion lets a call
    ! omit its brackets, so `Wipe9` on a line of its own is a call with nothing to recognise it
    ! by. It cannot reach another procedure's TRUE locals - but a PARAMETER is the caller's
    ! variable by reference, and SELF is the caller's object, so it can reach both of those.
    ! Only refuse when the receiver is actually within its reach: with nothing between the guard
    ! and the use there is no call to be exposed to, and a parameter receiver simplifies as it
    ! always did.
    ! AND IT NEED NOT BE FIRST ON ITS LINE. `x = f ; Wipe9` puts one after a semicolon,
    ! `if f then Wipe9.` puts one after THEN, and `oth.Wipe` is a parenless method call on
    ! something else entirely - which can still reach a global. Keying on firstOnLine saw
    ! none of them, and with the pre-filter gone a global receiver lost its guard to all
    ! three. Any bare name that ENDS a statement is a call we cannot see into.
    ! THE RESTORE HAS TO HAPPEN WHETHER THE TEST PASSED OR NOT. DgStmtIsBareName PEEKS
    ! at j+1 (and sometimes j+2) and returns without putting the buffer back, so when it answers
    ! NO - which is every mid-statement token, the common case - the walk's buffer was left on the
    ! NEIGHBOUR. The same-root arm immediately below reads `self.tk.tokens` expecting token j, and
    ! was reading that neighbour instead: for `k = gs2.wipe + 1` walked backwards it tested '+',
    ! which has no dot, so the arm never fired and a parenless method call on the receiver's own
    ! root walked through the proof. The guard was deleted and what was left was
    ! `left(gs2.buf.valuePtr[1 : gs2.buf._DataEnd])` on a buffer that call may have emptied - the
    ! GPF this builtin's banner promises away, and in the ONE arm written to prevent it.
    ! It hid because the pinned case put the call on a line of its OWN: there the test answers
    ! YES, the restore ran, and the arm saw what it was supposed to. MEASURED: the same call
    ! mid-statement lost its guard while its split-spelling twin kept one.
    ! The restore is inside the type test, so it costs a GET only where a peek actually happened.
    if self.tk.tokens.type = 'b'
      if self.DgStmtIsBareName(j)
        if ~self.DgRecvIsLocal(pRecvU, pIx) then return 0.
      end
      get(self.tk.tokens, j)                             ! restore the walk's buffer
    end
    ! SOMETHING ELSE ON THE SAME ROOT IS A MUTATION WE CANNOT SEE INTO. `gs2.wipe` is a
    ! parenless METHOD call: it merges to one token, so it carries no '(' for the opaque-call
    ! arm, and it is not a member of `gs2.buf`, so the member walk below skips it entirely. But
    ! it names the same ROOT as the receiver, and whatever it does it can do to gs2.buf.
    if self.tk.tokens.type = 'b' and not self.tk.tokens.tok &= NULL
      if instring('.', self.tk.tokens.tok, 1, 1)        |
         and upper(self.tk.tokens.tok) <> upper(pRecvU) |
         and self.NameRoot(self.tk.tokens.tok) = self.NameRoot(pRecvU)
        if ~self.DgMemberAt(j, pRecvU) then return 0.
      end
    end
    mU = self.DgMemberAt(j, pRecvU)                                   ! '' when this is not our receiver
    if mU
      if pWant = dg:wantTrim and ~nest and ~inArm                     ! both of these leave character 1 non-blank,
        case mU                                                       !   which is the whole claim - see the header
        of '.TRIM'                                                    ! Trim() strips ' ', left()'s own alphabet.
          if ~self.DgArgCountAt(self.DgOpenAfter(j)) then return 1.   ! Trim('*') strips something else
        of '.SETLEFT'                                                 ! setLeft() / setLeft(n): pWhat defaults to
          if self.DgSetLeftProves(self.DgOpenAfter(j)) then return 1. ! st:spaces, and a What that SUMS
        end                                                           !   st:spaces in still qualifies
      end
      case mU
      of   '._DATAEND' orof '.VALUEPTR'     orof '.GETVALUE'      orof '.GETVALUEPTR'   |
         orof '.LEN'      orof '.LENGTH'       orof '.LENGTHA'       orof '.CLIPLENGTH' |
         orof '.SUB'      orof '.SLICE'        orof '.BETWEEN'       orof '.BEFORE'     |
         orof '.AFTER'    orof '.FINDCHAR'     orof '.FINDCHARS'     orof '.FINDBYTE'   |
         orof '.INSTRING' orof '.CONTAINSCHAR' orof '.CONTAINSCHARS'                    |
         orof '.RECORDS'  orof '.GETLINE'      orof '.LINES'
        ! CONST ONLY WHILE IT IS BEING READ. `c._DataEnd` reads the length; `c._DataEnd = 0`
        ! SETS it, and `c.valuePtr[1] = ' '` writes a byte - both through names on this list,
        ! which blessed them as harmless. A member that is the TARGET of an assignment is a
        ! mutation whatever its name is, so look for the '=' that follows it.
        if self.DgMemberIsTarget(j) then return 0.
      else
        return 0                          ! anything else MIGHT mutate it: unknown = unsafe
      end
    end
    if lv = '-' then nest += 1.
    if lv = '/' and ~nest then inArm = 1. ! an ELSE/ELSIF at OUR level: everything from here
    if lv = '+'                           !   back to its IF is an arm we did not run
      if nest > 0
        nest -= 1                         ! the opener of a block that closed above us
      else
        inArm = 0                         ! the IF that owns the arm(s) we just walked over
      end
      if ~nest and ~inArm and pWant = dg:wantGuard and self.DgGuardAt(j, pRecvU) then return 1.
    end
  end
  return 0                                ! reached the CODE statement without a proof

! ------------------------------------------------------------------------------------
! Is the token at pIx a use of pRecvU's member, and which member? Returns '.NAME' upper
! cased, or '' if this token is not our receiver at all. Handles both spellings:
!     c._DataEnd          one token
!     c . Free            three tokens
! A bare receiver that is NOT followed by a dot - passed to something, say - answers
! '.?', which is on no const list and so is read as a possible mutation.
! ------------------------------------------------------------------------------------
VitEngine.DgMemberAt Procedure(LONG pIx, STRING pRecvU)
t        string(vs:maxName),auto
dotP     long,auto
  code
  t = self.tk.GetTok(pIx)
  if ~t then return ''.
  if self.DgIsMemberDot(pIx + 1)         ! split: <receiver> . <method>
    if upper(t) <> pRecvU then return ''.
    return '.' & upper(self.tk.GetTok(pIx + 2))
  end
  if upper(t) = pRecvU then return '.?'. ! the receiver BARE - passed to something,
  dotP = self.DgLastDot(t)               !   &= assigned. Assume the worst
  if dotP < 2 or |
     upper(sub(t, 1, dotP - 1)) <> pRecvU
    return ''
  end
  return upper(sub(t, dotP, len(clip(t)) - dotP + 1))

! ------------------------------------------------------------------------------------
! Is the whole one-line guard at pIx?   if R._DataEnd < 1 then return
! ------------------------------------------------------------------------------------
VitEngine.DgGuardAt Procedure(LONG pIx, STRING pRecvU)
  code
  if upper(self.tk.GetTok(pIx)) <> 'IF' then return 0.
  if self.DgMemberAt(pIx + 1, pRecvU) <> '._DATAEND' then return 0.
  if self.tk.GetTok(pIx + 2) <> '<' then return 0.
  if self.tk.GetTok(pIx + 3) <> '1' then return 0.
  if upper(self.tk.GetTok(pIx + 4)) <> 'THEN' then return 0.
  if upper(self.tk.GetTok(pIx + 5)) <> 'RETURN' then return 0.
  return 1

! ------------------------------------------------------------------------------------
! Where is the '(' of the call whose member name sits at pIx? The tokenizer writes a
! member two ways - see DgMemberAt - and the same test decides both.
! ------------------------------------------------------------------------------------
VitEngine.DgOpenAfter Procedure(LONG pIx)
  code
  if self.DgIsMemberDot(pIx + 1) then return pIx + 3. ! split    c . Trim (
  return pIx + 1                                      ! merged   c.Trim (

! ------------------------------------------------------------------------------------
! How many arguments does the call bracket at pOpenIx have? 0 for '()', otherwise one
! more than the commas at depth 1 - so a comma inside a nested call or subscript is not
! counted. Answers 99 when pOpenIx is not a '(' at all, which passes none of the tests
! the callers make and so reads as a refusal rather than as "no arguments".
! ------------------------------------------------------------------------------------
VitEngine.DgArgCountAt Procedure(LONG pOpenIx)
j        long,auto
depth    long,auto
n        long,auto
t        string(vs:maxName),auto
  code
  if self.tk.GetTok(pOpenIx) <> '(' then return 99.
  if self.tk.GetTok(pOpenIx + 1) = ')' then return 0.
  n     = 1
  depth = 1
  loop j = pOpenIx + 1 to records(self.tk.tokens)
    t = self.tk.GetTok(j)
    case t
    of '(' orof '['
      depth += 1
    of ')' orof ']'
      depth -= 1
      if ~depth then break.
    of ','
      if depth = 1 then n += 1.
    end
  end
  return n

! ------------------------------------------------------------------------------------
! Does the setLeft() whose bracket opens at pOpenIx provably strip leading SPACES?
!
!   st.setLeft()                        yes - What is omitted and defaults to st:spaces
!   st.setLeft(20)                      yes - the Length pads the RIGHT; it strips nothing
!   st.setLeft( ,st:spaces + st:tabs)   yes - a sum that INCLUDES st:spaces (the usual form,
!                                             and the one the CapeSoft help gives as its
!                                             own example)
!   st.setLeft( ,st:tabs)               NO  - leading spaces survive it untouched
!   st.setLeft( ,flags)                 NO  - a variable. This walk does not evaluate one,
!                                             and a wrong guess here is unsound
!
! The third parameter, Pad, cannot matter: padding is added on the RIGHT, and a string
! made entirely of pad characters has no leading space to strip either way.
! ------------------------------------------------------------------------------------
VitEngine.DgSetLeftProves Procedure(LONG pOpenIx)
n        long,auto
j        long,auto
j0       long
depth    long,auto
t        string(vs:maxName),auto
sawSp    byte
sawAny   byte
  code
  n = self.DgArgCountAt(pOpenIx)
  if n = 99 then return 0. ! not a call bracket at all
  if n < 2 then return 1.  ! What omitted - it defaults to st:spaces
  depth = 1
  loop j = pOpenIx + 1 to records(self.tk.tokens)
    t = self.tk.GetTok(j)
    case t
    of '(' orof '['
      depth += 1
    of ')' orof ']'
      depth -= 1
      if ~depth then break.
    of ','
      if depth = 1
        if ~j0
          j0 = j + 1                                   ! What starts after the FIRST comma
        else
          break                                        ! and ends at the second - Pad is not our business
        end
      end
    end
    if j0 and j >= j0                                  ! inside What: a sum of st:* constants, nothing else
      sawAny = true
      case upper(t)
      of 'ST:SPACES'
        sawSp = true
      of '+'
        ! a term separator - keep reading
      else
        if upper(sub(t, 1, 3)) <> 'ST:' then return 0. ! a variable or an expression: not read here
      end
    end
  end
  if ~sawAny then return 1.                            ! `setLeft(20, )` - What is empty, so it defaulted
  return choose(sawSp = true)

! ------------------------------------------------------------------------------------
! BUILTIN DeadLeft (OPT-IN) - drop a left() that provably has nothing to strip.
!
!     c.Trim()
!     ...
!     nm = left(c.sub(1, p - 1))        ->   nm = c.sub(1, p - 1)
!     nm = left(c.valuePtr[1 : n])      ->   nm = c.valuePtr[1 : n]
!
! from preprocessor.EvalPPCondition, the same procedure DeadGuard came
! from: the receiver is trimmed at the top and every read of it below starts at
! character 1, so left() cannot find a leading space to remove.
!
! WHY THE SLICE MUST START AT 1. Trim() proves nothing about character 7. left(c.sub(2,n))
! may well have a space to strip, so only a literal 1 as the first argument qualifies -
! not a variable that happens to hold 1, which would need the value walk.
!
! WHY IT DOES NOT MATTER WHAT FOLLOWS. left() strips the LEADING spaces of its whole
! argument, and those can only come from whatever the expression starts with. Once the
! first operand is proven clean, left(A & B & C) is a no-op whatever B and C are - so
! the argument is not required to be the slice and nothing else.
!
! WHY Trim() AND NOT trim(alphabet). The no-argument Trim() strips ' ' - the same
! alphabet left() strips - so one exactly covers the other. Trim('*') does not, and
! answers no.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinDeadLeft Procedure(StringTheory pLog)
s        long,auto
scKind   byte,auto
i        long,auto
e        long                                                    ! AUTO unsafe: read before write
mainEnd  long,auto
fol      byte,auto
recvU    string(vs:maxName)                                      ! AUTO unsafe: read before write
lineNo   long,auto
changes  long
sb       StringTheory                                            ! see BuiltinDeadGuard - a fixed STRING would pad
  code
  if self.syms &= NULL then return 0.
  loop s = records(self.syms.scopes) to 1 by -1                  ! BACKWARDS, and for the reason written out at
    get(self.syms.scopes, s)                                     !   BuiltinDeadGuard: the recorded token ranges
    if errorcode() then break.                                   !   of every LATER scope go stale the moment we
    scKind = self.syms.scopes.kind                               !   delete anything, and nothing repairs them
    if scKind <> vs:scProc and scKind <> vs:scMethod then cycle. ! until this builtin returns
    self.acScopeId = 0
    self.AutoScopePrep(s)                                        ! the ROW - AutoScopePrep gets positionally
    if self.acBail then cycle.                                   ! GOTO / COMPILE / OMIT / no CODE - order not provable
    mainEnd = self.acMainEnd
    i = self.acCodeT + 1
    loop while i <= mainEnd
      if ~self.DlShapeAt(i, recvU, e)                            ! left( <receiver read starting at 1> ...
        i += 1
        cycle
      end
      if ~self.DgProvenNonEmpty(recvU, i, dg:wantTrim)           ! a dominating Trim(), unspoilt?
        i += 1
        cycle
      end
      get(self.tk.tokens, i)
      lineNo = self.tk.tokens.lineNo
      fol    = self.tk.tokens.firstOnLine                        ! left( held the line's start and indent
      if self.tk.tokens.strBefore &= NULL
        sb.Free()
      else
        sb.SetValue(self.tk.tokens.strBefore)
      end
      self.tk.DeleteToks(e, e)                                   ! the closing ')' FIRST - deleting forwards would
      self.tk.DeleteToks(i, i + 1)                               !   shift the index we just computed
      self.tk.SetStrBefore(i, sb.GetValue())
      if fol
        get(self.tk.tokens, i)
        if ~errorcode()
          self.tk.tokens.firstOnLine = true
          put(self.tk.tokens)
        end
      end
      self.wantReparse = true
      changes += 1
      pLog.append('BUILTIN DeadLeft line ' & self.tk.MapLine(lineNo) & ': left() on ' & clip(recvU) & |
                  ' from character 1 has nothing to strip - it was trimmed above<13,10>')
      mainEnd -= 3 ! left, its '(' and its ')'. Do NOT advance i -
                   !   the survivor sits at i, and case 1 of the
                   !   fixture has TWO in one procedure
    end
  end
  if changes then pLog.append('BUILTIN DeadLeft: ' & changes & ' left() removed this pass<13,10>').
  return changes

! ------------------------------------------------------------------------------------
! Is the no-op shape at pIx? Returns the receiver and the index of left()'s closing ')'.
!     left ( R.valuePtr [ 1 : ...        left ( R . sub ( 1 , ...
! Both spellings of a member reference are read - see DgRecvAt.
! ------------------------------------------------------------------------------------
VitEngine.DlShapeAt Procedure(LONG pIx, *STRING pRecvU, *LONG pEnd)
memU     string(vs:maxName)                       ! AUTO unsafe: read before write
nx       long                                     ! AUTO unsafe: read before write
  code
  pRecvU = '' ; pEnd = 0
  if upper(self.tk.GetTok(pIx)) <> 'LEFT' then return 0.
  if self.tk.GetTok(pIx + 1) <> '(' then return 0.
  if ~self.DgRecvAt(pIx + 2, pRecvU, memU, nx) then return 0.
  case memU
  of '.VALUEPTR'                                  ! R.valuePtr[1 : ...
    if self.tk.GetTok(nx) <> '[' then return 0.
  of '.SUB'      orof '.SLICE'                    ! R.sub(1, ...   R.slice(1, ...
    if self.tk.GetTok(nx) <> '(' then return 0.
  else
    return 0
  end
  if self.tk.GetTok(nx + 1) <> '1' then return 0. ! a LITERAL 1 - a variable holding 1 is not read here
  case self.tk.GetTok(nx + 2)                     ! ... and the operand must END there: '1 + p' is not a read
  of ',' orof ':' orof ')' orof ']'               !     from character 1, and the left() it wears does real work (#23)
  else
    return 0
  end
  pEnd = self.tk.MatchLeftBracket('(', ')', pIx + 1)
  if ~pEnd then return 0.
  return 1

! ------------------------------------------------------------------------------------
! Read a member reference at pIx whatever its spelling, WITHOUT knowing the receiver
! first: DgMemberAt answers about a receiver already in hand, this one names it.
!   merged   c.valuePtr            -> recv c, member .VALUEPTR, next = pIx + 1
!   split    c . sub               -> recv c, member .SUB,      next = pIx + 3
! Answers 0 when the token is not a member reference at all.
! ------------------------------------------------------------------------------------
VitEngine.DgRecvAt Procedure(LONG pIx, *STRING pRecvU, *STRING pMemU, *LONG pNext)
t        string(vs:maxName),auto
dotP     long,auto
  code
  pRecvU = '' ; pMemU = '' ; pNext = 0
  t = self.tk.GetTok(pIx)
  if ~t then return 0.
  if self.DgIsMemberDot(pIx + 1) ! split: <receiver> . <method>
    if ~self.tk.GetTok(pIx + 2) then return 0.
    pRecvU = upper(t)
    pMemU  = '.' & upper(self.tk.GetTok(pIx + 2))
    pNext  = pIx + 3
    return 1
  end
  dotP = self.DgLastDot(t)       ! merged, and split on the LAST dot: the
  if dotP < 2 then return 0.     !   receiver of self.buf._DataEnd is self.buf
  pRecvU = upper(sub(t, 1, dotP - 1))
  pMemU  = upper(sub(t, dotP, len(clip(t)) - dotP + 1))
  pNext  = pIx + 1
  return 1

! ------------------------------------------------------------------------------------
! Where is the LAST dot in a token? A receiver may be dotted itself - self.buf.valuePtr
! is one token whose receiver is self.buf - so the member is what follows the last dot,
! never the first. Answers 0 when there is none.
! ------------------------------------------------------------------------------------
VitEngine.DgLastDot Procedure(STRING pTok)
x        long,auto
  code
  loop x = len(clip(pTok)) to 1 by -1
    if pTok[x] = '.' then return x.
  end
  return 0

! ------------------------------------------------------------------------------------
! Is the token at pIx the '.' that joins a receiver to a member, rather than the '.'
! that CLOSES a block? Clarion spells both the same and only the token type tells them
! apart. Without this, `if x then n = c.` reads as a call on c, and the token after the
! END dot - the next line's first word - gets taken for a method name.
! ------------------------------------------------------------------------------------
VitEngine.DgIsMemberDot Procedure(LONG pIx)
  code
  if self.tk.GetTok(pIx) <> '.' then return 0.
  get(self.tk.tokens, pIx)
  if errorcode() then return 0.
  return choose(self.tk.tokens.type = vt:dot)

! BUILTIN KnownRanges (S3, OPT-IN) - retire a guard, or a choose(),
! that provably cannot go the other way, and collapse a computed sub() length into the
! slice() that says the same thing, by tracking WHERE a scalar local got its value.
!
!     p = st.findChar('=')                          p is 0 .. st._DataEnd
!     if ~p then break.                             below it, p is 1 .. st._DataEnd
!     if p - 1 < st._DataEnd then st.setLength(p - 1).      -> st.setLength(p - 1)
!     ... st.sub(choose(q < 0, st._DataEnd + q + 1, q), q)  -> st.sub(q, q)
!     ... st.sub(p, q - p + 1)                              -> st.slice(p, q)
!
! BOTH of those lines are code VitTransform ITSELF emitted (the truncate rule and
! the v13c sub-position dispatch). A pattern rule cannot know where a value came from,
! so it guards; this pass can, so it cleans up after them.
!
! THE MODEL. This is AutoCheck's walk (AutoVerdict) carrying RANGE FACTS instead of
! assigned/not-assigned: the same per-scope AutoScopePrep bail, the same level-mark
! frames, the same inline-dot idiom. One linear forward pass over each proc/method
! MAIN code (routines are excluded by acMainEnd, exactly as AutoCheck excludes them).
!
!   lattice   rk:none / rk:zeroBound (0..recv._DataEnd) / rk:posBound (1..recv._DataEnd)
!             / rk:nonNeg (>= 0).  Each bounded fact records the RECEIVER it is bounded
!             by, so a fact about `st` says nothing about `other._DataEnd`.
!   seeds     x = recv.findChar/findChars/findByte/instring(...)  -> zeroBound on recv
!             x = recv.len/length/lengthA/clipLength(...)          -> nonNeg
!             x = recv._DataEnd                                    -> nonNeg
!             x = len/records/size/instring(...)                   -> nonNeg
!             x = self.Method(...) / x = MyProc(...)               -> that body's
!               SUMMARY, when the body is in THIS file and (for a method) its prototype is
!               visible and NOT virtual. sm:nonNeg -> nonNeg, sm:posBound -> posBound with
!               NO receiver, so a summary can only ever decide `x < 0` and `x >= 0` and
!               their mirrors - never S3, which demands a bound on the receiver it is
!               written on. The fact carries the CALLEE's name and every log line it
!               decides says so, because the evidence is in another procedure.
!             anything else -> the fact is DROPPED (rk:none).
!   narrowing `if ~x then break|return|cycle|exit.` - below it x is non-zero, so
!             zeroBound becomes posBound;  `if ~x` ... `else` - inside the ELSE x is
!             non-zero.  The ELSE form is restored from a snapshot taken AT THE IF, so a
!             kill inside the THEN branch (which never ran on this path) cannot suppress
!             it. Facts carry the depth they were made at and die when that block closes.
!   invalidation
!             * a write to x (`x =`, `x +=`, ... at a statement start / after THEN /
!               ELSE / ';') drops every fact for x, then the seed above may re-make it;
!             * ANY impure call on the line drops every fact whose variable OR receiver
!               is NAMED anywhere on that line - it may be a *LONG output parameter, or a
!               method that moves the receiver's _DataEnd, and there is no prototype here;
!             * any `DO <routine>` clears EVERY fact - a routine can change anything;
!             * a non-IF block opener
!               clears every fact: LOOP and ACCEPT REPEAT, so a fact made above the opener
!               is not valid at the top of the body on the second iteration, and this walk
!               only ever sees the body once. Under-reach for CASE/EXECUTE, deliberately.
!             * GOTO / COMPILE / OMIT anywhere in the scope refuses the scope outright
!               (the existing AutoScopePrep bail).
!
! THE SIMPLIFICATIONS.
!   S1  `if C then S.` with C provably TRUE -> `if C then` and the terminating '.' are
!       deleted, leaving S, which inherits the IF token's leading trivia (its indent, and
!       any comment lines parked in front of it). SINGLE-LINE FORM ONLY - collapsing a
!       block IF would mean re-indenting its body, which is a different job.
!   S2  `choose(C, A, B)` with C provably FALSE -> the span becomes B; TRUE -> A. The
!       kept value inherits the CHOOSE token's trivia. EXACTLY two top-level commas: the
!       four-or-more argument form of CHOOSE is the INDEXED form and means something else.
!   S3  `recv.sub(q, x - q + 1)` -> `recv.slice(q, x)`. The same span, said once
!       and without the arithmetic. The `sub` token is retyped to `slice` and `- q + 1` is
!       deleted; nothing else on the line moves.
!       THE GUARD IS THE WHOLE POINT. The two ST methods agree ONLY while q >= 1 AND
!       x >= 1, so BOTH must carry rk:posBound. rk:nonNeg is NOT enough - zero is
!       precisely the broken case, and it is why this cannot be a rule: a rule could only
!       guard with isConst, and isConst proves >= 0. Re-read against StringTheory.Sub and
!       StringTheory.Slice while building this, there are three divergences, and
!       every one of them returns a WRONG ANSWER rather than failing:
!         x = 0  sub yields '' (its length works out <= 0), but Slice reads pEnd = 0 as
!                "to the end" and hands back the WHOLE REST of the string;
!         x < 0  sub yields '', but Slice measures from the end (pEnd = _DataEnd + pEnd);
!         q = 0  sub returns Value[1 : x + 1], because it clamps pStart up to 1 AFTER the
!                CALLER computed the length; slice returns Value[1 : x]. Off by one.
!       Everything else matches, including an over-long end - Sub clamps the length, Slice
!       clamps pEnd, and both land on _DataEnd. So the design's guard stands as ratified.
!       THE SHAPE, and nothing wider: q and the leading term x are each ONE token naming a
!       local that holds rk:posBound; the length argument has exactly ONE top-level '-'
!       and exactly ONE top-level '+'; the middle term is token-for-token equal to q
!       (SpanTokEqual); the trailing term is the literal 1; the sub has exactly one
!       top-level comma. Anything else is refused - under-reach is the correct answer here.
!       NB both facts are also required to be bounded by the receiver the call is made on.
!       That is STRICTER than soundness needs: only `>= 1` is load-bearing, and the
!       _DataEnd half of posBound is never used, because Sub and Slice clamp an over-long
!       end identically. Deliberate - a fact about `st` is the only one this walk is
!       willing to defend for a call written on `st`.
!       This is NOT the rest-of-string RULE (`st.sub(w, st._DataEnd - w + 1)` ->
!       `st.slice(w)`, in draft-rules-v15.txt - a working draft, NOT SHIPPED). That one matches the literal text
!       `_DataEnd` and runs in an earlier pass; S3 handles any expression whose RANGE is
!       known. Where both could apply the rule fires first and leaves no `sub` behind, so
!       the two need no coordination.
!
! DECIDABLE COMPARISONS - and NOTHING else. x holds a fact, recv is its bounding receiver:
!       x < 0          FALSE for zeroBound / posBound / nonNeg
!       x <= -1        FALSE  "
!       x >= 0         TRUE   "
!       x > -1         TRUE   "
!       x - 1 < recv._DataEnd   TRUE for posBound on THAT SAME receiver
! Anything else is UNDECIDED and is left alone. That is the entire safety argument: every
! bail above lands in UNDECIDED, and UNDECIDED never edits anything.
!
! DELIBERATE DEVIATION from the design table, flagged for review. The design also
!     lists `x < recv._DataEnd` as TRUE for posBound. It is NOT: posBound means
!     1 <= x <= _DataEnd, so x may EQUAL _DataEnd and the comparison is then FALSE.
!     Implementing it would delete a guard that really can fire, which is a behaviour
!     change - so it is refused here and fixture case BareLessDataEnd pins the refusal.
!     `x - 1 < _DataEnd` (the row above) IS sound: x >= 1 makes x - 1 <= _DataEnd - 1.
!     NB `x - 1 < recv._DataEnd` is also true for zeroBound (x - 1 >= -1), but the design
!     restricts that row to posBound and the fixture (NoZeroTest) expects the refusal, so
!     posBound it is - pure under-reach.
!
! WHAT IT REFUSES (all under-reach - a refusal leaves working code exactly as it was):
!   * a scope with GOTO / COMPILE / OMIT, and every ROUTINE body;
!   * any variable that is not a simple scalar INTEGER local of this scope - a parameter
!     (not a column-1 declaration), a reference, a field, LIKE, OVER, DIM, STATIC, THREAD;
!   * any receiver that is not a simple local StringTheory of this scope - a module-level
!     one could be moved by a call this walk cannot see, and a reference could be re-pointed
!     by `st &= other`, which carries no call for the invalidation scan to catch;
!   * any line carrying a ';' - two statements on one line make the order of effects matter,
!     and `if C then A ; B.` puts BOTH statements in the THEN branch;
!   * an impure call that RAN TO COMPLETION before a choose on the same line, or one that
!     sits inside the choose as a sibling argument - argument evaluation order is not
!     specified, so the fact may already be stale. A call that ENCLOSES the choose is fine:
!     its own effect happens after its arguments are computed. S3 applies the same test,
!     for the same reason, to the sub() it is about to rewrite (KrSubCallsOk);
!   * for a sub() with anything but exactly two arguments, a start or a leading term
!     that is not ONE token, a length whose top-level '-'/'+' count is not exactly one
!     each, a middle term that is not token-for-token the start, a trailing term that is
!     not the literal 1, or either operand holding anything but rk:posBound on the
!     receiver the call is made on;
!   * a comment or a '|' continuation anywhere in the text being deleted or re-trivia-ed;
!   * an inline ELSE, a nested opener, or a second THEN inside a candidate one-liner;
!   * a scope whose level-mark walk does not return to the depth it started at. An INLINE
!     '.' terminator is retyped vt:end but may carry NO '-' level mark (the level pass skips
!     inline dots), so the close test is the idiom; if the walk still ends unbalanced the
!     WHOLE scope is rolled back rather than half-transformed.
!
! HIGH-RISK: this builtin DELETES code. The purity list and the decidable table ARE
!     the safety argument - a side-effecting name wrongly added to the list (or via
!     PURE(...)) is a real bug. OPT-IN: vitrules.txt DECLARES it, inside `GROUP analysis,
!     OFF`, so a plain run never reaches it and --group=analysis is what turns it on.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinKnownRanges Procedure(StringTheory pLog)
s           long,auto
raw         StringTheory
pureU       StringTheory       ! ' NAME NAME ... ' - space delimited, UPPER, leading AND trailing space
noteSt      StringTheory       ! NOTE('...') - LOG text only; it never injects a comment into the source
sbSt        StringTheory       ! donor trivia while applying a kind-2 edit
wsST        StringTheory       ! a VEHICLE for IsAll in KrTriviaClean - its own value is never consulted
changes     long
scRow       long,auto          ! row in syms.scopes
scKind      byte,auto
sc          long,auto          ! scopeId of the proc/method being walked
scSelf      string(vs:maxName) ! the method's receiver class, captured BEFORE AutoScopePrep clobbers the buffer
codeT       long,auto
mainEnd     long,auto
depth       long               ! open block frames
edMark      long,auto          ! records(KrEdQ) when this scope started - refusal rollback point
chgMark     long,auto          ! `changes` at the same instant - see the rollback
logMark     long,auto          ! pLog length at the same instant - ditto
scBad       byte               ! this scope refused: roll its staged edits back
i           long,auto
lineFirst   long,auto          ! first token of the LOGICAL line being processed
lineLast    long,auto          ! last token of it ('|' continuations included - they emit no EOL token)
lineEol     long,auto
logLn       long,auto
edLine      long,auto          ! records(KrEdQ) before S2 ran on this line - see KrLine
viaTxt      string(260)        ! the log's EVIDENCE clause - a summary-driven decision cannot be audited from the changed line alone
! ---- comparison operator texts. chr() sidesteps the doubling rule for '<' entirely.
opLT        string(4)
opLE        string(4)
opGT        string(4)
opGE        string(4)
! ---- token peek (KrGet)
gPos        long,auto
gOk         byte
gTxt        string(vs:maxName)
gTU         string(vs:maxName)
gTy         string(1)
gLv         string(1)
! ---- fact helpers
fName       string(vs:maxName)                 ! KrFind in
fKind       byte                               ! KrFind out
fRecv       string(vs:maxName)                 ! KrFind out
fVia        string(vs:maxName)                 ! KrFind out - the callee whose SUMMARY made this fact ('' = an ordinary seed)
fGeVar      string(vs:maxName)                 ! KrFind out - the local this one is >= ('' = no relational bound)
purgeD      long                               ! KrPurge in
killNm      string(vs:maxName)                 ! KrKillName / KrKillRecv in
addNm       string(vs:maxName)                 ! KrAddFact in
addKd       byte
addRc       string(vs:maxName)
addVia      string(vs:maxName)                 !
addGe       string(vs:maxName)                 !
! ---- per-line classification (KrLineScan)
lnSemi      byte
lnLevel     byte
lnDo        byte
lnImpure    byte
! ---- narrowing
narName     string(vs:maxName)                 ! '' = this line narrows nothing
narBlock    byte                               ! 1 = `if ~x` block form (handed to the frame), 0 = one-liner transfer
pendNm      string(vs:maxName)                 ! snapshot handed to KrOpen
pendKd      byte
pendRc      string(vs:maxName)
pendVia     string(vs:maxName)                 !
pendGe      string(vs:maxName)                 !
frmSeq      long                               ! frame counter - tags each snapshot in KrSnapQ
lineSnapLo  long                               ! first frmSeq minted ON the current line: kills on the line reach those snapshots (the condition ran on every path)
lineKillSeq long                               ! the frame snapshot a '/' line re-exposed (ELSIF condition, OF selector): its kills reach that one too
snSeq       long                               ! the frame whose snapshot is being read
snNm        string(vs:maxName)                 ! one snapshot row, copied out before KrFind clobbers the buffer
snKd        byte
snRc        string(vs:maxName)
snDp        long
snVi        string(vs:maxName)
snGe        string(vs:maxName)
! ---- seed (KrDetectSeed)
seedOk      byte
seedNm      string(vs:maxName)
seedKd      byte
seedRc      string(vs:maxName)
seedVia     string(vs:maxName)                 ! the callee whose summary produced this seed ('' = one of the built-in shapes)
seedGe      string(vs:maxName)                 ! the START argument of a forward search - a lower bound on the seed
gaS         long                               ! KrArg2 out - the second argument's span (0 = none)
gaE         long
a2S         long                               ! KrArg2 in - the whole argument list to scan
a2E         long
mth         string(vs:maxName)                 ! was KrDetectSeed's ROUTINE-local; KrSeedGeArg needs it too
s4Uz        long                               ! S4 - shared by KrTryS4 and KrS4Shape, so PROCEDURE level.
sOpn        long                               !   A ROUTINE's DATA is private to that routine, so these belong
sCls        long                               !   HERE - declared inside KrTryS4 they are invisible to KrS4Shape.
sSub        long
sSlc        long
sAmp        long
sW          long
sB          long
sRcv        string(vs:maxName)
wNm         string(vs:maxName)
bNm         string(vs:maxName)
bVia        string(vs:maxName)
wSrc        string(vs:maxName)                 ! the two operands AS THE AUTHOR SPELLED THEM. wNm/bNm are
bSrc        string(vs:maxName)                 !   upper-cased for matching; emitting those would rewrite p as P.
smNm        string(vs:maxName)                 ! SummaryOfCallAt out - the callee's source-case name
smF         byte                               ! SummaryOfCallAt out - the sm:* fact
! ---- condition evaluation (KrEvalCond)
evS         long,auto
evE         long,auto
evRes       byte                               ! 0 = undecided, 1 = TRUE, 2 = FALSE
krHdrSkip   byte                               ! S2-S4 refused on LOOP/ELSIF/OF header lines (#18)
evOp        string(4)
! ---- S1
s1Then      long
s1Dot       long
! ---- S2
c2Tok       long                               ! the CHOOSE token
c2Open      long
c2Close     long
c2C1        long                               ! first top-level comma
c2C2        long                               ! second top-level comma
c2KeepS     long
c2KeepE     long
c2Done      byte
c2CallsOk   byte
c2Res       byte
! ---- S3. Its own vars, not S2's: KrTryS3 runs AFTER KrTryS2 on the same line and
!      must not disturb a decision S2 has already staged.
s3Tok       long                               ! the `sub` method token - retyped to `slice`
s3Open      long                               ! its '('
s3Close     long                               ! its matching ')'
s3Com       long                               ! the ONE top-level comma inside it
s3Recv      string(vs:maxName)                 ! the receiver, already through KrRecvOk
s3Q         long                               ! the ONE token of argument 1 (the start)
s3X         long                               ! the ONE token of the leading term of argument 2
s3Min       long                               ! the ONE top-level '-' in argument 2
s3Plus      long                               ! the ONE top-level '+' in it
s3Done      byte
s4Ok        byte                               ! S4 matched and staged this line
s4Why       string(200)                        ! why S4 refused a line whose SHAPE matched
s4Refs      long                               ! refusal lines emitted (capped)
s4Two       long                               ! a second top-level '&' was seen
s4DotR      long                               ! this setValue has a dotted receiver
s4DotT      string(vs:maxName)                 ! ... spelled thus
s4TlSub     long                               ! the trailing term is sub(b, _DataEnd - b + 1), not slice(b)
s3CallsOk   byte
ccLo        long                               ! the span KrSubCallsOk is protecting: S3 sets it from s3Tok/s3Close,
ccHi        long                               !   S4 from sOpn/sCls. The check is the SAME check; only the span differs.
! ---- call classification (KrCallAt)
caPos       long                               ! the '(' token
caIsCall    byte
caPure      byte
caDot       byte                               ! the callee is a METHOD - a '.' before it
caName      string(vs:maxName)
caTmp       string(vs:maxName)
! ---- paren matching (KrMatchParen)
mpOpen      long
mpClose     long
! ---- trivia scan (KrTriviaClean)
tcS         long
tcE         long
tcOk        byte
! ---- symbol eligibility (KrLocalOk / KrRecvOk)
okName      string(vs:maxName)
okRes       byte
okDecl      long
! ---- name splitting (KrSplitRoot)
spIn        string(vs:maxName)
spRoot      string(vs:maxName)
spSuf       string(vs:maxName)
! ---- edit staging
nxPos       long
nxPos2      long
nxKind      byte
nxTxt       string(3 * vs:maxName + 8)        ! kind 3 only; KrApply ignores it for kinds 1 and 2.
                                              ! THE WIDTH IS THE POINT. The widest thing built here is
                                              !   '(' & w & ', ' & b & ' - ' & w  =  6 + 2*len(w) + len(b) characters,
                                              !   so one name's worth of width cut the TRAILING OPERAND NAME as soon as
                                              !   the total passed it. Clipping an operand cannot substitute: clip()
                                              !   removes padding that sits AFTER the name, so the cut falls in the same
                                              !   place either way. Size it for the worst case, as here.
KrFactQ  QUEUE,PRE(kv)
kvName   string(vs:maxName)
kvKind   byte                                 ! rk:*
kvRecv   string(vs:maxName)                   ! '' for rk:nonNeg
kvDepth  long                                 ! block depth the fact was made at; dies when that block closes
kvVia    string(vs:maxName)                   ! the callee whose SUMMARY established it - the log line must name it
kvGeVar  string(vs:maxName)                   ! a RELATIONAL lower bound - this local is >= the local NAMED here.
                                              !   '' = none. Seeded by `x = recv.findByte(ch, v)` with a non-zero guard,
                                              !   because FindByte(ch, pStart) searches from address+pStart-1 and so
                                              !   returns 0 or a position AT OR AFTER pStart. Every other fact in this
                                              !   queue bounds a value against a CONSTANT or against the receiver; this
                                              !   is the first to bound one against another VARIABLE, which is exactly
                                              !   what the span-removal rewrite needs and could not be said before.
       END
KrKillQ  QUEUE,PRE(kk)                        ! names destroyed INSIDE a block, so KrClose can keep them destroyed.
kkFrame  long                                 !   the frame it happened in; handed up to the parent when that frame closes
kkName   string(vs:maxName)                   !   so an outer ELSE cannot resurrect it either
         END
KrFrameQ QUEUE,PRE(kf)
kfDepth  long
kfNar    string(vs:maxName)                   ! '' = this frame narrows nothing at its ELSE
kfKind   byte                                 ! the snapshot taken AT the IF
kfRecv   string(vs:maxName)
kfVia    string(vs:maxName)                   !
kfSeq    long                                 ! which snapshot in KrSnapQ belongs to this frame
kfGeVar  string(vs:maxName)                   ! the RELATIONAL bound must survive the ELSE narrowing too.
                                              !   Without it, `if ~q ... else` - which is how parser.MaskSigBase is
                                              !   written - restores q as posBound but FORGETS q >= p, and S4 refuses.
                                              !   The one-liner `if ~q then break.` narrowing carried it from the start;
                                              !   the BLOCK form is a different path and was missed.
       END
! the fact set AS IT STOOD AT EACH OPEN 'IF'. The ELSE branch did not run the
! THEN branch, so it must not inherit the THEN branch's KILLS either - and a kill deletes a
! row outright, at any depth, so the depth purge cannot undo one. Without this,
!     if ~q
!       st.setLength(p - 1)        <- impure: kills every fact keyed on st, including p's
!     else
!       ... p and q used here       <- p has no fact, though setLength never ran on this path
!     end
! which is exactly how parser.MaskSigBase is written. The comment on the ELSE narrowing has
! always said a kill in the THEN branch 'cannot suppress it' - that was true of the one
! narrowed variable and of nothing else.
KrSnapQ  QUEUE,PRE(sn)
snFrame  long
snName   string(vs:maxName)
snKind   byte
snRecv   string(vs:maxName)
snDepth  long
snVia    string(vs:maxName)
snGeVar  string(vs:maxName)
       END
KrEdQ    QUEUE,PRE(kr)
pos      long                                                          ! kind 1: first token of the delete range.  kind 2/3: the token being changed
pos2     long                                                          ! kind 1: last token of the delete range.   kind 2: the DONOR token (always BELOW pos)
kind     byte                                                          ! 1 = DeleteToks, 2 = SetStrBefore copied from pos2, 3 = SetTok text
txt      string(3 * vs:maxName + 8)                                    ! kind 3 only: the replacement token text. Blank for kinds 1 and 2.
                                                                       ! SAME SIZE AS nxTxt, AND FOR THE SAME REASON. nxTxt was widened to
                                                                       !   the worst case its own comment works out - 6 + 2*len(w) + len(b) -
                                                                       !   after a narrow buffer cut a trailing operand name into emitted
                                                                       !   source. KrPush then copied it straight into THIS field, which was
                                                                       !   left at one name's width, so the truncation the widening existed to
                                                                       !   stop happened one assignment later and in the same place.
                                                                       !   TrailingSpaces got this right on BOTH sides at once - nxTxt and
                                                                       !   tseTxt are the same width there. A one-sided fix to a two-sided
                                                                       !   problem is worth recognising as a shape: whenever a built string is
                                                                       !   handed on, the receiving field is part of the fix.
       END
  code
  if self.syms &= NULL then return 0.
  self.acScopeId = 0                                                   ! the token stream may have moved since the last pass
  free(KrFactQ)                                                        ! local QUEUEs persist between calls - start every pass empty
  free(KrSnapQ)                                                        !
  frmSeq = 0
  s4Refs = 0                                                           !
  free(KrFrameQ)
  free(KrKillQ)
  free(KrEdQ)
  opLT = chr(60)
  opLE = chr(60) & '='
  opGT = chr(62)
  opGE = chr(62) & '='
  self.KnownRangePureList(pureU)                                       ! the base list; PURE(...) only ever APPENDS to it
  noteSt.free()
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      case upper(self.rl.rules.bparmQ.name)
      of 'PURE'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)                     ! parsed exactly like UnusedVars' EXCLUDE(a b c)
          raw.upper()
          pureU.append(clip(raw.getValue()) & ' ')                     ! the list already ends in a space
        end
      of 'NOTE'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)
          raw.unquote('''','''')
          noteSt.setValue(raw)                                         ! reported once in the log; NEVER written into the source
        end
      end
    end
  end

  self.BuildSummaries()                                                ! what every proc/method in this file RETURNS - seeds a call site below
  if self.syms.scopes &= NULL then return 0.
  loop scRow = 1 to records(self.syms.scopes)
    get(self.syms.scopes, scRow)
    if errorcode() then break.
    scKind = self.syms.scopes.kind
    sc     = self.syms.scopes.scopeId
    scSelf = self.syms.scopes.selfClass                                ! which class a `self.` call in this scope names
    if scKind <> vs:scProc and scKind <> vs:scMethod then cycle.       ! module data has no code; a ROUTINE is covered by the DO bail
    self.AutoScopePrep(sc)                                             ! NB clobbers the scopes buffer - sc/scKind/scSelf are captured above
    if self.acBail then cycle.                                         ! missing scope / no CODE / GOTO / COMPILE / OMIT present
    codeT   = self.acCodeT
    mainEnd = self.acMainEnd
    if mainEnd <= codeT then cycle.
    do KrScopeWalk
  end

  if records(KrEdQ)
    do KrApply
    self.wantReparse = true                                            ! tokens deleted; later builtins must see the new stream
    if noteSt._DataEnd
      pLog.append('BUILTIN KnownRanges: ' & clip(noteSt.getValue()) & '<13,10>')
    end
    pLog.append('BUILTIN KnownRanges: ' & changes & ' simplification(s) this pass<13,10>')
  end
  free(KrFactQ)
  free(KrSnapQ)                                                        !
  free(KrFrameQ)
  free(KrKillQ)
  free(KrEdQ)
  return changes

! ---- walk ONE proc/method main code, staging its edits; roll them back on any refusal ----
KrScopeWalk routine
  free(KrFactQ)
  free(KrSnapQ)                                                        !
  free(KrFrameQ)
  free(KrKillQ)
  depth  = 0
  scBad  = 0
  edMark  = records(KrEdQ)
  chgMark = changes                                                    ! see the rollback below
  logMark = pLog._DataEnd
  i = codeT + 1
  loop
    if i > mainEnd or |
       scBad
      break
    end
    get(self.tk.tokens, i)
    if errorcode() then scBad = 1 ; break.
    if self.tk.tokens.tok &= NULL                                      ! trivia-only tail record
      i += 1
      cycle
    end
    if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10   ! a physical newline
      i += 1
      cycle
    end
    lineFirst = i
    lineEol   = self.FirstEolAfter(lineFirst) ! a '|' continuation emits NO EOL token, so this is the LOGICAL line
    if lineEol > lineFirst and lineEol <= mainEnd + 1
      lineLast = lineEol - 1
    else
      lineLast = mainEnd
    end
    do KrLine
    i = lineLast + 1
  end
  ! belt (the lesson): the walk must come back to the depth it started at. If it does
  ! not, some opener was never closed by a mark we recognise - so every frame boundary below
  ! it was mis-read and the facts we acted on are not the facts that hold. Roll the scope back
  ! rather than half-transform it. Costs nothing on well-formed code, where depth is 0 here.
  if ~scBad and depth then scBad = 1.
  if scBad
    loop while records(KrEdQ) > edMark
      get(KrEdQ, records(KrEdQ))
      if errorcode() then break.
      delete(KrEdQ)
    end
    ! the edits go, so the COUNT and the LOG must go with them. Without this the
    ! report claims simplifications that never happened, and worse: `changes` is this
    ! builtin's return value, so a non-zero count sets wantReparse and the fixpoint
    ! walks the same scope, rolls it back and counts it again on every pass to the cap.
    ! A leaked level mark is enough to reach it (TokenType early-returns for + - * / % ^
    ! and quoted literals without resetting `level`), so this is not a corner.
    changes = chgMark
    if pLog._DataEnd > logMark then pLog.setLength(logMark).
  end

! ---- one LOGICAL line: decide with the facts as they stand, THEN move the facts on ----
KrLine routine
  lineSnapLo  = frmSeq + 1                    ! snapshots minted on THIS line get this line's kills - the
  lineKillSeq = 0                             !   opener's condition runs on every path, so what it kills
                                              !   must die in the ELSE snapshot too (set by KrSnapRestore
                                              !   for the '/'-line twin: an ELSIF condition's kills)
  do KrLineScan                               ! ';' / level marks / DO / an impure call anywhere
  do KrDetectNarrow                           ! `if ~x then break.` (N1) or `if ~x` (N2)
  if ~lnSemi                                  ! two statements on one line: the order of effects matters
    do KrTryS1
    edLine = records(KrEdQ)
    krHdrSkip = 0
    case upper(self.tk.GetTok(lineFirst))
    of 'LOOP' orof 'ELSIF' orof 'OF' orof 'OROF' orof 'UNTIL' orof 'WHILE'
      krHdrSkip = 1                           ! S2-S4 REFUSED on these headers (#18): a LOOP WHILE/UNTIL condition
    end                                       !   re-evaluates every iteration and an ELSIF/OF operand runs under the
                                              !   PREVIOUS branch's facts - but the opener fact-clear (KrLevelWalk)
                                              !   lands only AFTER this line has already staged its edits, one line
                                              !   too late for the header itself: loop while choose(x >= 0, 1, 0)
                                              !   became loop while 1, an infinite loop
    if ~krHdrSkip
      do KrTryS2
    end
    ! S3 runs only when S2 changed NOTHING on this line. A choose() can ENCLOSE a
    ! sub(), and a decided choose deletes the losing value WHOLE - so S2's delete span
    ! could contain S3's, and two overlapping deletes in one KrApply sweep is corruption,
    ! not under-reach. S1 cannot collide the same way: the only conditions KrEvalCond
    ! decides are five tokens long at most, so a call can never be inside one.
    if ~krHdrSkip and records(KrEdQ) = edLine
      do KrTryS3
    end
    if ~krHdrSkip and records(KrEdQ) = edLine                ! S4 for the same reason S3 waits - one
      do KrTryS4                              !   delete span per line, or KrApply corrupts
    end
  end
  do KrLevelWalk                              ! frames, depth, the ELSE narrowing, the depth purge
  do KrLineEffects                            ! writes, impure kills, the seed, the N1 narrowing

! ---- level marks of this line, in token order ----
KrLevelWalk routine
  data
lw  long,auto
  code
  lw = lineFirst - 1
  loop
    lw += 1
    if lw > lineLast or |
       scBad
      break
    end
    gPos = lw
    do KrGet
    if ~gOk then scBad = 1 ; break.
    if gLv = '+'
      do KrOpen
    elsif gLv = '/'
      do KrElseMark
    elsif gLv = '-' or (gTy = vt:end and gLv <> '+' and gLv <> '/')
      do KrClose                                                  ! the inline-dot idiom: an INLINE '.' is retyped vt:end but may carry NO '-'
    end
  end

! ---- a block opens ----
KrOpen routine
  do KrSnapTake                                                   ! the fact set as it stands NOW, before the branch runs
  depth += 1
  clear(KrFrameQ)
  kf:kfDepth = depth
  kf:kfSeq   = frmSeq                                             !
  kf:kfNar   = ''
  kf:kfKind  = rk:none
  kf:kfRecv  = ''
  kf:kfVia   = ''
  kf:kfGeVar = ''
  if gTU = 'IF'
    if pendNm                                                     ! `if ~x` - snapshot taken BEFORE the frame opened
      kf:kfNar  = pendNm
      kf:kfKind = pendKd
      kf:kfRecv = pendRc
      kf:kfVia  = pendVia                                         ! the evidence travels with the fact
      kf:kfGeVar = pendGe                                         ! and so does the relational bound
    end
  else
    free(KrFactQ)                                                 ! LOOP and ACCEPT REPEAT: a fact made above the opener is not
  end                                                             !   valid at the top of the body on iteration 2, and this walk
  add(KrFrameQ)                                                   !   sees the body once. CASE/EXECUTE lose their facts too - under-reach.
  pendNm = ''

! ---- ELSE / ELSIF / OF / OROF: the branch just walked is not on this path ----
KrElseMark routine
  purgeD = depth
  do KrPurge                                                      ! everything the previous branch established
  do KrSnapRestore                                                ! ... and everything it KILLED comes back
  if ~records(KrFrameQ) then exit.
  get(KrFrameQ, records(KrFrameQ))
  if errorcode() then exit.
  if kf:kfDepth <> depth then exit.
  if ~kf:kfNar then exit.
  if kf:kfKind <> rk:zeroBound then exit.
  ! `if ~x` ... ELSE (or ELSIF - reached only when ~x was false too): x is non-zero here.
  ! Restored from the AT-THE-IF snapshot, so a kill inside the THEN branch - which never ran
  ! on this path - cannot suppress it.
  addNm  = kf:kfNar
  addKd  = rk:posBound
  addRc  = kf:kfRecv
  addVia = kf:kfVia                                               !
  addGe  = kf:kfGeVar                                             !
  do KrAddFact

! ---- END / '.' ----
KrClose routine
  purgeD = depth
  do KrPurge
  do KrKillsOut                                                   ! what ANY branch destroyed stays destroyed - see below
  do KrSnapDrop                                                   ! this frame's snapshot dies with the frame
  if ~records(KrFrameQ) then scBad = 1 ; exit.                    ! level underflow - do not trust the walk
  get(KrFrameQ, records(KrFrameQ))
  if errorcode() then scBad = 1 ; exit.
  delete(KrFrameQ)
  depth -= 1
  if depth < 0 then scBad = 1.

! ---- A FACT DESTROYED BY *ANY* BRANCH MUST NOT WALK OUT OF THE BLOCK. ----
!      The ELSE restore is right and stays: the else branch never ran the then branch, so
!      inside the else the old fact really does still hold, and KrSnapKill's header says
!      deliberately that a kill deep in a branch must not reach the snapshot.
!
!      WHAT WAS WRONG IS WHAT HAPPENED AFTER THE END. KrSnapRestore puts each row back
!      carrying its ORIGINAL depth, so a fact learned before the IF comes back at a depth
!      shallower than the block - and KrPurge, which only deletes depth >= this one, cannot
!      touch it. The fact walked out of the END into code that runs on EITHER path.
!      MEASURED: `p` seeded and narrowed, killed by `p = -9` in a then branch, restored at
!      the else, and `if p >= 0 then y = 2.` below the END came back as a bare `y = 2` -
!      the guard deleted while p was -9 on one of the two paths.
!
!      After an IF you only know what was true on EVERY path, so every name killed anywhere
!      inside the block is dropped here regardless of the depth it was learned at.
!
!      THE RE-TAG IS THE PART THAT IS EASY TO MISS. A kill inside a NESTED block has to go
!      on mattering to the blocks around it: the inner END drops it, but an outer ELSE
!      restores from an outer snapshot the kill never reached, so the outer END has to drop
!      it again. Handing the rows up to the parent frame does that at every level; at the
!      outermost frame there is no parent and they are simply discarded.
KrKillsOut routine
  data
oz   long,auto
oy   long,auto
oSeq long,auto
oPar long,auto
  code
  if ~records(KrKillQ) then exit.
  oSeq = 0
  oPar = 0
  if records(KrFrameQ)
    get(KrFrameQ, records(KrFrameQ))
    if ~errorcode() then oSeq = kf:kfSeq.
    if records(KrFrameQ) > 1
      get(KrFrameQ, records(KrFrameQ) - 1)
      if ~errorcode() then oPar = kf:kfSeq.
    end
  end
  if ~oSeq then exit.
  loop oz = records(KrKillQ) to 1 by -1
    get(KrKillQ, oz)
    if errorcode() then cycle.
    if kk:kkFrame <> oSeq then cycle.
    loop oy = records(KrFactQ) to 1 by -1
      get(KrFactQ, oy)
      if errorcode() then cycle.
      if kv:kvName = kk:kkName or kv:kvRecv = kk:kkName then delete(KrFactQ).
    end
    get(KrKillQ, oz)
    if errorcode() then cycle.
    if oPar
      kk:kkFrame = oPar ! hand it up - an outer ELSE can resurrect it too
      put(KrKillQ)
    else
      delete(KrKillQ)   ! outermost frame: nothing left to protect
    end
  end

! ---- S4 matched the SHAPE but a guard said no. Say so - a silent refusal is
!      indistinguishable from the pattern never matching, and that is exactly what cost two
!      wrong diagnoses. Capped like every other detail line. ----
! ---- the SHAPE did not match, on a setValue whose argument IS a concatenation.
!      Only logged once we know there is a top-level '&' - otherwise every plain setValue in
!      the file would report. Unconditional silence covers three different things: a correct
!      refusal, a missing arm, and never having looked. Only the first should be silent. ----
KrS4Miss routine
  do KrS4Refuse

KrS4Refuse routine
  s4Refs += 1
  if s4Refs > 20 then exit.
  pLog.append('BUILTIN KnownRanges line ' & self.LogLineOf(s4Uz) & ': span-removal REFUSED on ' & |
              clip(sRcv) & '.setValue(...) - ' & clip(s4Why) & '<13,10>')

! ---- copy the live fact set aside, tagged with a fresh frame number ----
KrSnapTake routine
  data
tz1  long,auto
  code
  frmSeq += 1
  loop tz1 = 1 to records(KrFactQ)
    get(KrFactQ, tz1)
    if errorcode() then cycle.
    clear(KrSnapQ)
    sn:snFrame = frmSeq
    sn:snName  = kv:kvName
    sn:snKind  = kv:kvKind
    sn:snRecv  = kv:kvRecv
    sn:snDepth = kv:kvDepth
    sn:snVia   = kv:kvVia
    sn:snGeVar = kv:kvGeVar
    add(KrSnapQ)
  end

! ---- at the ELSE, put back anything the THEN branch KILLED. The purge just above
!      has already dropped what that branch CREATED, so a snapshot row with no live fact of
!      the same name is one the branch deleted - and it never ran on this path. A row that
!      IS still live is left alone rather than duplicated. ----
KrSnapRestore routine
  data
tz2  long,auto
  code
  if ~records(KrFrameQ) then exit.
  get(KrFrameQ, records(KrFrameQ))
  if errorcode() then exit.
  if kf:kfDepth <> depth then exit.
  snSeq = kf:kfSeq
  lineKillSeq = snSeq ! this '/' line's own effects (an ELSIF condition's impure
                      !   call, an OF selector) run on every LATER path too, so
                      !   KrLineEffects' kills must reach this frame's snapshot
  ! rebuild the fact set WHOLESALE from the snapshot. Restoring only
  ! rows whose name has no live fact is wrong whenever a name carries MORE THAN ONE
  ! row - and the interesting ones always do:
  !     p = st.findByte(61)      seeds p as zeroBound
  !     if ~p then break.        appends p as posBound
  ! KrFind scans backwards so posBound wins while both are live. After a kill removed both,
  ! the by-name restore put back the zeroBound seed, then found p 'live' and skipped the
  ! posBound - restoring the WEAKEST fact and dropping the one that mattered. The refusal
  ! line said 'P holds zeroBound' and that is exactly what it was seeing.
  free(KrFactQ)
  loop tz2 = 1 to records(KrSnapQ)
    get(KrSnapQ, tz2)
    if errorcode() then cycle.
    if sn:snFrame <> snSeq then cycle.
    snNm = sn:snName
    snKd = sn:snKind
    snRc = sn:snRecv
    snDp = sn:snDepth
    snVi = sn:snVia
    snGe = sn:snGeVar
    clear(KrFactQ)
    kv:kvName  = snNm
    kv:kvKind  = snKd
    kv:kvRecv  = snRc
    kv:kvDepth = snDp
    kv:kvVia   = snVi
    kv:kvGeVar = snGe
    add(KrFactQ)
  end

! ---- the frame is closing, so its snapshot is dead ----
KrSnapDrop routine
  data
tz3  long,auto
  code
  if ~records(KrFrameQ) then exit.
  get(KrFrameQ, records(KrFrameQ))
  if errorcode() then exit.
  snSeq = kf:kfSeq
  loop tz3 = records(KrSnapQ) to 1 by -1
    get(KrSnapQ, tz3)
    if errorcode() then cycle.
    if sn:snFrame = snSeq then delete(KrSnapQ).
  end

! ---- drop every fact made at purgeD or deeper ----
KrPurge routine
  data
pz  long,auto
  code
  loop pz = records(KrFactQ) to 1 by -1
    get(KrFactQ, pz)
    if errorcode() then cycle.
    if kv:kvDepth >= purgeD then delete(KrFactQ).
  end

! ---- drop every fact ABOUT killNm - and the RELATIONAL half of any fact that NAMES it.
!      q's `>= P` is meaningless once P is rewritten, but q's own lower bound still
!      holds, so the geVar is blanked rather than the row deleted. S4 is the only
!      geVar consumer and a blank geVar refuses there ("it is >= nothing"). Without
!      this sweep the stale `ge P` survived P's reassignment and S4 rewrote to a
!      RemoveFromPosition that is a DIFFERENT PROGRAM once the new P is past q
!      (the S4 header's own proof: duplicate-vs-clamp). ----
KrKillName routine
  data
kz  long,auto
  code
  if ~killNm then exit.
  loop kz = records(KrFactQ) to 1 by -1
    get(KrFactQ, kz)
    if errorcode() then cycle.
    if kv:kvName = killNm
      delete(KrFactQ)
    elsif kv:kvGeVar = killNm
      kv:kvGeVar = ''
      put(KrFactQ)
    end
  end
  do KrSnapKill
  do KrKillRecord                       ! and the block this happened in must remember it

! ---- remember, for the enclosing block, that this name was destroyed inside it ----
!      KrKillsOut at the END is what uses these. Recorded here rather than at the write site
!      because this is the ONE place a fact dies by name, and a rule with two homes is how
!      two of them drift apart.
KrKillRecord routine
  data
kr  long,auto
  code
  if ~records(KrFrameQ) then exit.      ! not inside a block - nothing can resurrect it
  get(KrFrameQ, records(KrFrameQ))
  if errorcode() then exit.
  loop kr = records(KrKillQ) to 1 by -1 ! already recorded for this frame? nothing to add
    get(KrKillQ, kr)
    if errorcode() then cycle.
    if kk:kkFrame = kf:kfSeq and kk:kkName = killNm then exit.
  end
  get(KrFrameQ, records(KrFrameQ))
  if errorcode() then exit.
  clear(KrKillQ)
  kk:kkFrame = kf:kfSeq
  kk:kkName  = killNm
  add(KrKillQ)

! ---- THE KILL AND THE SEED HAVE TO AGREE ABOUT WHAT A DOTTED NAME IS. ----
!      KrDetectSeed records the WHOLE token - `SELF.BUF` - as the fact's name or receiver.
!      Every kill above splits the token first and offers only the ROOT, `SELF`, so on a
!      dotted receiver the two spellings never met and a mutation of `self.buf` left every
!      fact it should have invalidated standing. Measured: with `self.buf.Replace(...)`
!      between the seeds and the use, the dotted probe still converted while its bare twin
!      correctly refused. The root kill STAYS - a write through `self.buf` may well stale a
!      fact about `self` - and the whole token is offered as well, to both kills. More
!      killing means fewer facts, which means fewer conversions: the safe direction, and
!      the only one available while the two halves disagree.
!      Nothing to do when the token has no suffix: root and whole token are then the same
!      string and KrKillName/KrKillRecv have already been asked it.
KrKillWhole routine
  if ~spSuf then exit.
  killNm = spIn
  do KrKillName
  do KrKillRecv

! ---- drop every fact BOUNDED BY killNm ----
KrKillRecv routine
  data
rz  long,auto
  code
  if ~killNm then exit.
  loop rz = records(KrFactQ) to 1 by -1
    get(KrFactQ, rz)
    if errorcode() then cycle.
    if kv:kvRecv = killNm then delete(KrFactQ).
  end
  do KrSnapKillRecv

! ---- a kill on the line that MINTED a snapshot (a '+' opener's own condition) or on
!      a '/' line that re-exposed one (ELSIF condition, OF selector) must reach that
!      snapshot too: the killed effect ran on EVERY path, so the ELSE restore must not
!      resurrect it. Kills from lines deeper in a branch leave snapshots alone - those
!      effects belong to one branch only, and restoring them at ELSE is the point of
!      the snapshot. Both routines are called ONLY from KrLineEffects, so lineSnapLo /
!      lineKillSeq are always current. ----
KrSnapKill routine
  data
sz  long,auto
  code
  if ~records(KrSnapQ) then exit.
  loop sz = records(KrSnapQ) to 1 by -1
    get(KrSnapQ, sz)
    if errorcode() then cycle.
    if sn:snFrame < lineSnapLo and (~lineKillSeq or sn:snFrame <> lineKillSeq) then cycle.
    if sn:snName = killNm
      delete(KrSnapQ)
    elsif sn:snGeVar = killNm
      sn:snGeVar = ''
      put(KrSnapQ)
    end
  end

KrSnapKillRecv routine
  data
sr  long,auto
  code
  if ~records(KrSnapQ) then exit.
  loop sr = records(KrSnapQ) to 1 by -1
    get(KrSnapQ, sr)
    if errorcode() then cycle.
    if sn:snFrame < lineSnapLo and (~lineKillSeq or sn:snFrame <> lineKillSeq) then cycle.
    if sn:snRecv = killNm then delete(KrSnapQ).
  end

! ---- innermost live fact for fName (rows are appended, so scan BACKWARDS) ----
KrFind routine
  data
fz  long,auto
  code
  fKind = rk:none
  fRecv = ''
  fVia  = ''
  fGeVar = ''                                                     !
  if ~fName then exit.
  loop fz = records(KrFactQ) to 1 by -1
    get(KrFactQ, fz)
    if errorcode() then cycle.
    if kv:kvName = fName
      fKind = kv:kvKind
      fRecv = kv:kvRecv
      fVia  = kv:kvVia                                            !
      fGeVar = kv:kvGeVar                                         !
      break
    end
  end

! ---- record a fact at the CURRENT depth (dataless routine -> no CODE section) ----
KrAddFact routine
  clear(KrFactQ)
  kv:kvName  = addNm
  kv:kvKind  = addKd
  kv:kvRecv  = addRc
  kv:kvDepth = depth
  kv:kvVia   = addVia                                             !
  kv:kvGeVar = addGe                                              !
  add(KrFactQ)

! ---- one token into gTxt / gTU / gTy / gLv ----
KrGet routine
  gOk  = 0
  gTxt = ''
  gTU  = ''
  gTy  = ' '
  gLv  = ' '
  if gPos < 1 then exit.
  get(self.tk.tokens, gPos)
  if errorcode() then exit.
  gTy = self.tk.tokens.type
  gLv = self.tk.tokens.level
  if not self.tk.tokens.tok &= NULL
    if size(self.tk.tokens.tok) > size(gTxt) then exit.            ! the token does NOT FIT.
                                                                   !   gTxt is a fixed STRING, so a longer token arrives
                                                                   !   TRUNCATED, and the whitespace guards downstream
                                                                   !   (TsLitOk, TsLitSpaceless, SkReplOk) then scan the
                                                                   !   short copy and answer 'provably space-free' for a
                                                                   !   literal whose first space sits past the cut - which
                                                                   !   licenses removing a clip() that was doing real work.
                                                                   !   gOk stays 0, so every caller reads this as 'cannot
                                                                   !   see it' and refuses, which is the house answer.
    gTxt = self.tk.tokens.tok
    gTU  = upper(self.tk.tokens.tok)
  end
  gOk = 1

! ---- split spIn at its FIRST '.' -> spRoot / spSuf (a bare name gives spSuf = '') ----
KrSplitRoot routine
  data
dz  long,auto
nz  long,auto
  code
  spRoot = spIn
  spSuf  = ''
  nz = len(clip(spIn))
  if ~nz then spRoot = '' ; exit.
  dz = instring('.', spIn, 1, 1)
  if dz > 1 and dz < nz
    spRoot = spIn[1 : dz - 1]
    spSuf  = spIn[dz + 1 : nz]
  elsif dz
    spRoot = '' ! a leading or trailing dot - not a name we model
  end

! ---- is the '(' at caPos a CALL, and is that call on the pure list? ----
KrCallAt routine
  data
cz  long,auto
cn  long,auto
cd  long,auto
  code
  caIsCall = 0
  caPure   = 0
  caName   = ''
  if caPos < 2 then exit.
  get(self.tk.tokens, caPos - 1)
  if errorcode() then exit.
  if self.tk.tokens.tok &= NULL then exit.
  if self.tk.tokens.type <> vt:label and self.tk.tokens.type <> vt:reservedWord then exit. ! '(' after an operator/comma/'(' = grouping
  caName = upper(self.tk.tokens.tok)
  if self.tk.tokens.type = vt:reservedWord and caName <> 'CHOOSE' then exit.               ! `not(`, `if(` ... not calls
  ! defensive: the tokenizer does NOT merge a dotted name in front of a '(', so this is
  ! already the bare method name - take the tail after the last dot anyway.
  cn = len(clip(caName))
  cd = 0
  loop cz = 1 to cn
    if caName[cz] = '.' then cd = cz.
  end
  if cd >= cn then exit.
  if cd
    caTmp  = caName[cd + 1 : cn]
    caName = caTmp
  end
  caIsCall = 1
  ! A NAME IS NOT PURE ON ITS OWN - IT DEPENDS WHOSE IT IS. Clarion's CLIP(x) returns a
  ! trimmed copy and touches nothing. StringTheory's c.Clip() SHRINKS THE BUFFER. This looks
  ! up the tail after the last dot, so both arrive here as CLIP and the method read as pure -
  ! and KnownRanges then kept a fact about a receiver that had just been shortened.
  ! THE DOT IS A SEPARATE TOKEN. The comment above says so - the tokenizer does NOT merge a
  ! dotted name in front of a '(' - so `cd` is always 0 and keying on it made this arm dead code
  ! that never once ran. The dot is at caPos - 2, which is the test the DeadGuard arm already uses.
  caDot = 0
  if caPos > 2
    get(self.tk.tokens, caPos - 2)
    if ~errorcode() and not self.tk.tokens.tok &= NULL
      if self.tk.tokens.tok = '.' then caDot = 1.
    end
    get(self.tk.tokens, caPos - 1) ! restore the callee row
  end
  if caDot and caName = 'CLIP'
    caPure = 0                     ! a dotted CLIP is the mutating one
  elsif pureU.findChars(' ' & clip(caName) & ' ')
    caPure = 1
  end

! ---- matching ')' for the '(' at mpOpen, within this logical line (0 = none) ----
KrMatchParen routine
  data
mz  long,auto
md  long,auto
  code
  mpClose = 0
  md      = 0
  loop mz = mpOpen to lineLast
    gPos = mz
    do KrGet
    if ~gOk then exit.
    case gTxt
    of '('
      md += 1
    of ')'
      md -= 1
      if ~md then mpClose = mz ; exit.
      if md < 0 then exit.
    end
  end

! ---- every strBefore in [tcS..tcE] is plain whitespace (no comment, no bar, no line break) ----
KrTriviaClean routine
  data
qz  long,auto
  code
  tcOk = 0
  loop qz = tcS to tcE
    get(self.tk.tokens, qz)
    if errorcode() then exit.
    if self.tk.tokens.strBefore &= NULL then cycle.
    if ~wsST.IsAll('<32,9>', self.tk.tokens.strBefore, false) then exit. ! '!' comment, '|' continuation or a CR/LF
    ! ISALL SAYS THIS IN ONE LINE, and the hand-rolled character walk that was here said it in
    !   twelve. The two are the same test; the library one is harder to get subtly wrong.
    !   THE THIRD ARGUMENT IS pClip, NOT A CASE FLAG, and false is load-bearing: it measures the
    !   alphabet with size() rather than clipLen(). It changes nothing for '<32,9>', whose last
    !   byte is a tab - but write the alphabet '<9,32>' and the default would clip the space
    !   straight out of it, and no plain-space gap would ever pass again. The same argument is
    !   written out at the label-merge site in vitTokenize, which is where this spelling comes
    !   from.
    !   IsAll reads a ZERO-LENGTH pTestString as "not supplied" and answers from the RECEIVER's
    !   own value instead. It cannot be reached with one here: a NULL strBefore is cycled above,
    !   and a non-NULL one was allocated with a size of at least 1. wsST is a vehicle for the
    !   method and its own value is never consulted.
  end
  tcOk = 1

! ---- classify the line before anything is decided on it ----
KrLineScan routine
  data
zz  long,auto
  code
  lnSemi   = 0
  lnLevel  = 0
  lnDo     = 0
  lnImpure = 0
  loop zz = lineFirst to lineLast
    gPos = zz
    do KrGet
    if ~gOk then cycle.
    if gLv = '+' or gLv = '/' or gLv = '-' or |
       gTy = vt:end
      lnLevel = 1
    end
    if gTxt = ';' then lnSemi = 1.
    if gTy = vt:reservedWord and gTU = 'DO' then lnDo = 1.
    if gTxt = '('
      caPos = zz
      do KrCallAt
      if caIsCall and ~caPure then lnImpure = 1.
    end
  end

! ---- `if ~x then break.` (N1) or `if ~x` (N2); sets narName / narBlock / pend* ----
KrDetectNarrow routine
  narName  = ''
  narBlock = 0
  pendNm   = ''
  pendKd   = rk:none
  pendRc   = ''
  pendVia  = ''
  pendGe   = ''
  gPos = lineFirst
  do KrGet
  if ~gOk or |
     gTy <> vt:reservedWord or |
     gTU <> 'IF'            or |
     gLv <> '+'             or |
     lineLast < lineFirst + 2
    exit
  end
  gPos = lineFirst + 1
  do KrGet
  if ~gOk                   or |
     gTxt <> '~' ! only the bare `~x` test removes the zero
    exit
  end
  gPos = lineFirst + 2
  do KrGet
  if ~gOk or |
     gTy <> vt:label
    exit
  end
  fName = gTU
  do KrFind
  if fKind <> rk:zeroBound then exit.                                                       ! nothing to narrow (rk:nonNeg has no upper bound to keep)
  if lineFirst + 2 = lineLast
    narName  = fName                                                                        ! N2: block form - the ELSE branch knows x is non-zero
    narBlock = 1
    pendNm   = fName
    pendKd   = fKind
    pendRc   = fRecv
    pendVia  = fVia                                                                         !
    pendGe   = fGeVar                                                                       !
    exit
  end
  if lineFirst + 5 <> lineLast then exit.                                                   ! N1 is exactly  if ~ x then KEYWORD .
  gPos = lineFirst + 3
  do KrGet
  if ~gOk or |
     gTU <> 'THEN'
    exit
  end
  gPos = lineFirst + 4
  do KrGet
  if ~gOk or |
     gTy <> vt:reservedWord or |
     gTU <> 'BREAK' and gTU <> 'RETURN' and gTU <> 'CYCLE' and gTU <> 'EXIT' ! an UNCONDITIONAL transfer, so falling through means x is non-zero
    exit
  end
  gPos = lineFirst + 5
  do KrGet
  if ~gOk or |
     gTy <> vt:end
    exit
  end
  narName = fName

! ---- does this line SEED a fact?  Plain `V = <one reader call>` lines only ----
KrDetectSeed routine
  data
rs   long,auto
re   long,auto
  code
  seedOk  = 0
  seedNm  = ''
  seedKd  = rk:none
  seedRc  = ''
  seedVia = ''
  seedGe  = ''                                                    !
  if lnLevel or lnSemi or |   ! a conditional write cannot credit the code below the block
     lineLast < lineFirst + 2
    exit
  end
  gPos = lineFirst
  do KrGet
  if ~gOk              or |
     gTy <> vt:label
    exit
  end
  spIn = gTU
  do KrSplitRoot
  if spSuf then exit. ! a.b = ... is a member write, not our local
  seedNm = spRoot
  gPos = lineFirst + 1
  do KrGet
  if ~gOk              or |
     gTxt <> '='
    exit
  end
  okName = seedNm
  do KrLocalOk
  if ~okRes then exit.
  rs = lineFirst + 2
  re = lineLast
  ! ---- (a) a bare property read:  n = st._DataEnd
  if rs = re
    gPos = rs
    do KrGet
    if ~gOk or |
       gTy <> vt:label
      exit
    end
    spIn = gTU
    do KrSplitRoot
    if spSuf <> '_DATAEND' then exit.
    okName = spRoot
    do KrRecvOk
    if ~okRes then exit.
    seedOk = 1
    seedKd = rk:nonNeg ! _DataEnd is >= 0; it is not bounded BY anything
    exit
  end
  gPos = re
  do KrGet
  if ~gOk or |
     gTxt <> ')'       ! the RHS must be exactly ONE call, closing on the last token
    exit
  end
  ! ---- (b) a method call:  x = <recv>.<method>( ... )
  gPos = rs
  do KrGet
  if ~gOk then exit.
  if gTy = vt:label and re >= rs + 3
    gPos = rs + 1
    do KrGet
    if gOk and gTxt = '.'
      gPos = rs
      do KrGet
      spIn = gTU
      do KrSplitRoot
      ! a DOTTED receiver seeds a fact like any other. that round taught the span-removal
      ! MATCHER to accept self.buf; it still refused, because the SEEDER stopped here and so
      ! p never had a fact to match against. Widening a pattern buys nothing while the
      ! analysis that feeds it stays narrow - which is the whole distinction the boundary
      ! work was about.
      ! `self.Method(...)` is a DIFFERENT shape and still goes to the summary path: there the
      ! merge yields the bare token `self`, so spSuf is blank. `self.buf.findByte(...)` yields
      ! `self.buf` with spSuf 'BUF', and is a receiver, not a call on self.
      if spRoot = 'SELF' and ~spSuf                       ! ---- x = self.<Method>(...) - a body IN THIS FILE
        smNm = ''
        smF  = self.SummaryOfCallAt(rs, re, scSelf, smNm) ! sm:none unless the prototype is visible AND not VIRTUAL
        do KrSeedFromSummary
        exit
      end
      if spSuf
        seedRc = spIn                                     ! the WHOLE token is the receiver's identity
      else
        okName = spRoot                                   ! KrRecvOk only knows how to check a bare local is an ST;
        do KrRecvOk                                       !   a dotted one stands on the token matching in every
        if ~okRes then exit.                              !   place, exactly as the matcher requires
        seedRc = okName
      end
      gPos = rs + 2
      do KrGet
      if ~gOk or |
         gTy <> vt:label
        exit
      end
      mth = gTU
      gPos = rs + 3
      do KrGet
      if ~gOk or |
         gTxt <> '('
        exit
      end
      mpOpen = rs + 3
      do KrMatchParen
      if mpClose <> re then exit.
      case mth
      of 'FINDCHAR' orof 'FINDCHARS' orof 'FINDBYTE' orof 'INSTRING'
        seedOk = 1         ! 0 = not found, else 1 .. recv._DataEnd
        seedKd = rk:zeroBound
        do KrSeedGeArg     ! and, if it was given a START, x >= that start
      of 'LEN'      orof 'LENGTH'    orof 'LENGTHA'  orof 'CLIPLENGTH'
        seedOk = 1         ! >= 0 only. clipLength IGNORES trailing spaces, so it is
        seedKd = rk:nonNeg !   NOT _DataEnd and must never be treated as that bound
        seedRc = ''
      end
      exit
    end
  end
  ! ---- (c) a bare Clarion reader:  x = len(...) / records(...) / size(...) / instring(...)
  if re < rs + 2 then exit.
  gPos = rs
  do KrGet
  if ~gOk then exit.
  mth = gTU
  gPos = rs + 1
  do KrGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  mpOpen = rs + 1
  do KrMatchParen
  if mpClose <> re then exit.
  case mth
  of 'LEN' orof 'RECORDS' orof 'SIZE' orof 'INSTRING'
    seedOk = 1
    seedKd = rk:nonNeg
  else
    smNm = '' ! x = MyProc(...) - a plain procedure DEFINED in this file
    smF  = self.SummaryOfCallAt(rs, re, '', smNm)
    do KrSeedFromSummary
  end

! ---- turn a summary into a seed. rk:posBound is recorded with NO receiver, which is
!      correct and deliberately weak: the S3 rewrite and the `x - 1 < recv._DataEnd` row
!      both demand a fact bounded by the receiver the call is written on, and a blank one
!      can never match, so a summary can only ever decide `x < 0` / `x >= 0` and their
!      mirrors. Widening that would mean claiming a bound on a buffer we never looked at. ----
! ---- the START argument of a forward search is a LOWER BOUND on the result.
!      StringTheory.FindByte(ch, pStart) searches from address+pStart-1, so it returns 0 or a
!      position AT OR AFTER pStart - same for FindChar, FindChars and Instring. The seed is
!      recorded here; it is only USABLE once the value is also known non-zero, which is what
!      the `if ~x` narrowing at step 5 provides. Together they give `x >= v`.
!      SECOND ARGUMENT ONLY, and only when it is a bare local: an expression could be
!      anything, and Instring's second argument is a step rather than a start - which is why
!      INSTRING is deliberately absent from the case below even though it seeds a range. ----
KrSeedGeArg routine
  seedGe = ''
  case mth
  of 'FINDCHAR' orof 'FINDCHARS' orof 'FINDBYTE'
  else
    exit
  end
  a2S = mpOpen + 1
  a2E = mpClose - 1
  if a2E < a2S then exit.
  do KrArg2 ! gaS..gaE = the SECOND argument, or 0
  if ~gaS or |
     gaS <> gaE ! one token only - an expression proves nothing
    exit
  end
  gPos = gaS
  do KrGet
  if ~gOk or |
     gTy <> vt:label
    exit
  end
  spIn = gTU
  do KrSplitRoot
  if spSuf then exit.                                             ! a.b - not a plain local
  okName = spRoot
  do KrLocalOk
  if ~okRes then exit.
  seedGe = spRoot

! ---- gaS..gaE = the second top-level argument of the call spanning a2S..a2E ----
KrArg2 routine
  data
k2  long,auto
d2  long
c2  long,auto
  code
  gaS = 0
  gaE = 0
  c2  = 0
  loop k2 = a2S to a2E
    gPos = k2
    do KrGet
    if ~gOk then cycle.
    if gTxt = '(' then d2 += 1.
    if gTxt = ')' then d2 -= 1.
    if d2 or gTxt <> ',' then cycle.
    c2 += 1
    if c2 = 1
      gaS = k2 + 1
    else
      gaE = k2 - 1
      exit
    end
  end
  if gaS and ~gaE then gaE = a2E.
  if gaS > gaE then gaS = 0.

KrSeedFromSummary routine
  case smF
  of sm:nonNeg
    seedOk  = 1
    seedKd  = rk:nonNeg
    seedRc  = ''
    seedVia = smNm
  of sm:posBound
    seedOk  = 1
    seedKd  = rk:posBound
    seedRc  = ''
    seedVia = smNm
  end

! ---- move the facts on, at the POST-line depth ----
KrLineEffects routine
  data
ez  long,auto
  code
  do KrDetectSeed ! reads token SHAPES only - applied at step 4, after the kills
  ! ---- 1. a routine can change any variable and any receiver
  if lnDo then free(KrFactQ).
  ! ---- 2. every write target on the line loses its fact
  loop ez = lineFirst to lineLast - 1
    gPos = ez
    do KrGet
    if ~gOk or |
       gTy <> vt:label
      cycle
    end
    if ez > lineFirst ! a write target starts a statement (9b's rule)
      gPos = ez - 1
      do KrGet
      if ~gOk or |
         gTU <> 'THEN' and gTU <> 'ELSE' and gTxt <> ';'
        cycle
      end
    end
    gPos = ez + 1
    do KrGet
    if ~gOk then cycle.
    if gTxt <> '=' ! '=' or a compound assignment: both WRITE the label
      if len(clip(gTxt)) <> 2 or |
         gTxt[2] <> '='
        cycle
      end
      case val(gTxt[1])
      of 43 orof 45 orof 42 orof 47 orof 37 orof 94 orof 38 ! '+' orof '-' orof '*' orof '/' orof '%' orof '^' orof '&'
        ! a compound assignment
      else
        cycle
      end
    end
    gPos = ez
    do KrGet
    spIn = gTU
    do KrSplitRoot
    killNm = spRoot
    do KrKillName
    do KrKillRecv
    do KrKillWhole
  end
  ! ---- 3. an impure call may write through an argument (a *LONG we have no prototype for)
  !         or move a receiver's _DataEnd. Everything it could reach, it names on this line.
  if lnImpure
    loop ez = lineFirst to lineLast
      gPos = ez
      do KrGet
      if ~gOk or |
         gTy <> vt:label
        cycle
      end
      spIn = gTU
      do KrSplitRoot
      killNm = spRoot
      do KrKillName
      do KrKillRecv
      do KrKillWhole
    end
  end
  ! ---- 4. the seed (AFTER the kills: the call that produced the value ran last)
  if seedOk
    addNm  = seedNm
    addKd  = seedKd
    addRc  = seedRc
    addVia = seedVia                                              !
    addGe  = seedGe                                               ! the relational lower bound, if any
    do KrAddFact
  end
  ! ---- 5. `if ~x then break.` - below it x is non-zero
  if narName and ~narBlock
    fName = narName
    do KrFind
    if fKind = rk:zeroBound
      addNm  = narName
      addKd  = rk:posBound
      addRc  = fRecv
      addVia = fVia                                               ! the evidence survives the narrowing
      addGe  = fGeVar                                             ! and so does the relational bound - the
      do KrAddFact                                                !   narrowing is what MAKES it usable (x <> 0)
    end
  end

! ---- decide the condition span [evS..evE]: evRes 0 = undecided, 1 = TRUE, 2 = FALSE ----
KrEvalCond routine
  evRes = 0
  if evE < evS + 2 then exit.                                     ! the shortest decidable form is three tokens
  gPos = evS
  do KrGet
  if ~gOk or |
     gTy <> vt:label
    exit
  end
  spIn = gTU
  do KrSplitRoot
  if spSuf then exit.                                             ! a member read carries no fact
  fName = spRoot
  do KrFind
  if fKind = rk:none then exit.
  ! ---- shape 1:  x < 0   /   x >= 0
  if evE = evS + 2
    gPos = evS + 1
    do KrGet
    if ~gOk then exit.
    evOp = gTxt
    gPos = evS + 2
    do KrGet
    if ~gOk or |
       gTxt <> '0'
      exit
    end
    if evOp = opLT then evRes = 2 ; exit.                         ! every fact we hold says x >= 0
    if evOp = opGE then evRes = 1 ; exit.
    exit
  end
  ! ---- shape 2:  x <= -1   /   x > -1
  if evE = evS + 3
    gPos = evS + 1
    do KrGet
    if ~gOk then exit.
    evOp = gTxt
    gPos = evS + 2
    do KrGet
    if ~gOk or |
       gTxt <> '-'
      exit
    end
    gPos = evS + 3
    do KrGet
    if ~gOk or |
       gTxt <> '1'
      exit
    end
    if evOp = opLE then evRes = 2 ; exit.
    if evOp = opGT then evRes = 1 ; exit.
    exit
  end
  ! ---- shape 3:  x - 1 < <recv>._DataEnd   - TRUE only for posBound on THAT receiver.
  !      1 <= x <= _DataEnd  =>  x - 1 <= _DataEnd - 1  <  _DataEnd.  See the note in
  !      the header for why `x < recv._DataEnd` is NOT in this table.
  if evE <> evS + 4 or |
     fKind <> rk:posBound
    exit
  end
  gPos = evS + 1
  do KrGet
  if ~gOk or |
     gTxt <> '-'
    exit
  end
  gPos = evS + 2
  do KrGet
  if ~gOk or |
     gTxt <> '1'
    exit
  end
  gPos = evS + 3
  do KrGet
  if ~gOk or |
     gTxt <> opLT
    exit
  end
  gPos = evS + 4
  do KrGet
  if ~gOk or |
     gTy <> vt:label
    exit
  end
  spIn = gTU
  do KrSplitRoot
  if spSuf <> '_DATAEND' or |
     spRoot <> fRecv ! a bound on `st` says nothing about `other._DataEnd`
    exit
  end
  evRes = 1

! ---- `if C then S.` with C provably TRUE -> S ----
KrTryS1 routine
  data
tz   long,auto
dep  long,auto
  code
  s1Then = 0
  s1Dot  = 0
  gPos = lineFirst
  do KrGet
  if ~gOk                   or |
     gTy <> vt:reservedWord or |
     gTU <> 'IF'            or |
     gLv <> '+'
    exit
  end
  ! the surviving statement inherits the IF's leading trivia; at column 1 it would read as
  ! a LABEL, so a bare-column-1 IF (which the tokenizer would not type 'r' anyway) is out.
  get(self.tk.tokens, lineFirst)
  if errorcode() then exit.
  if self.tk.tokens.strBefore &= NULL then exit.
  if ~size(self.tk.tokens.strBefore) then exit.
  gPos = lineLast
  do KrGet
  if ~gOk          or |
     gTy <> vt:end or |
     gTxt <> '.' ! a whole-word END on this line is not the one-liner form
    exit
  end
  s1Dot = lineLast
  dep = 0
  loop tz = lineFirst + 1 to s1Dot - 1
    gPos = tz
    do KrGet
    if ~gOk        or |
       gLv = '+'   or |   ! a nested opener inside the one-liner
       gLv = '/'   or |   ! an inline ELSE - `if C then A else B.`
       gTy = vt:end        ! a nested inline terminator
      exit
    end
    if gTxt = '('
      dep += 1
    elsif gTxt = ')'
      dep -= 1
      if dep < 0 then exit.
    elsif ~dep and gTy = vt:reservedWord and gTU = 'THEN'
      if s1Then then exit. ! two top-level THENs - not a shape we model
      s1Then = tz
    end
  end
  if dep                        or |
     ~s1Then                    or |
     s1Then - 1 < lineFirst + 1 or |   ! empty condition
     s1Then + 1 > s1Dot - 1 ! empty body
    exit
  end
  ! nothing we DELETE, and nothing whose trivia we REPLACE, may carry a comment or a bar
  tcS = lineFirst + 1
  tcE = s1Then + 1
  do KrTriviaClean
  if ~tcOk then exit.
  tcS = s1Dot
  tcE = s1Dot
  do KrTriviaClean
  if ~tcOk then exit.
  evS = lineFirst + 1
  evE = s1Then - 1
  do KrEvalCond
  if evRes <> 1 then exit.
  logLn = self.LogLineOf(lineFirst) ! captured BEFORE the edits - log coordinates only, never logic
  nxPos  = s1Dot
  nxPos2 = s1Dot
  nxKind = 1
  do KrPush                         ! drop the terminating '.'
  nxPos  = s1Then + 1
  nxPos2 = lineFirst
  nxKind = 2
  do KrPush                         ! the statement inherits the IF's indent
  nxPos  = lineFirst
  nxPos2 = s1Then
  nxKind = 1
  do KrPush                         ! drop `if <condition> then`
  changes += 1
  if changes = 501
    pLog.append('BUILTIN KnownRanges: further detail lines suppressed (500 shown)<13,10>')
  end
  do KrViaTxt
  if changes <= 500
    pLog.append('BUILTIN KnownRanges line ' & logLn & ': guard on ' & clip(fName) & ' cannot fail - if/then removed' & clip(viaTxt) & '<13,10>')
  end

! ---- the EVIDENCE clause. A fact seeded from a procedure summary was established in
!      ANOTHER procedure, so a reader looking at the changed line alone cannot check it -
!      the log line has to say where it came from. Blank for every ordinary seed. ----
KrViaTxt routine
  if fVia
    viaTxt = ' - ' & clip(fName) & ' holds what ' & clip(fVia) & '() returns'
  else
    viaTxt = ''
  end

! ---- every choose() on this line ----
KrTryS2 routine
  data
sz  long,auto
  code
  sz = lineFirst - 1
  loop
    sz += 1
    if sz >= lineLast then break.
    gPos = sz
    do KrGet
    if ~gOk or |
       gTU <> 'CHOOSE'
      cycle
    end
    gPos = sz + 1
    do KrGet
    if ~gOk or |
       gTxt <> '('
      cycle
    end
    c2Tok  = sz
    c2Open = sz + 1
    mpOpen = c2Open
    do KrMatchParen
    if ~mpClose then cycle.
    c2Close = mpClose
    do KrChooseOne
    if c2Done then sz = c2Close. ! never descend into a span we are already rewriting
  end

! ---- one choose(): decide it and stage the collapse ----
KrChooseOne routine
  data
oz  long,auto
od  long,auto
nc  long,auto
  code
  c2Done = 0
  ! EXACTLY two top-level commas. choose(n, v1, v2, v3 ...) is the INDEXED form and means
  ! something else entirely, so anything else is refused outright.
  c2C1 = 0
  c2C2 = 0
  nc   = 0
  od   = 0
  loop oz = c2Open + 1 to c2Close - 1
    gPos = oz
    do KrGet
    if ~gOk then exit.
    if gTxt = '('
      od += 1
    elsif gTxt = ')'
      od -= 1
      if od < 0 then exit.
    elsif ~od and gTxt = ','
      nc += 1
      if nc = 1 then c2C1 = oz.
      if nc = 2 then c2C2 = oz.
    end
  end
  if nc <> 2            or |
     c2C1 <= c2Open + 1 or |   ! empty condition
     c2C2 <= c2C1 + 1   or |   ! empty TRUE value
     c2Close <= c2C2 + 1 ! empty FALSE value
    exit
  end
  tcS = c2Tok + 1
  tcE = c2Close
  do KrTriviaClean
  if ~tcOk then exit.    ! a comment or a '|' inside would be deleted with the span
  do KrChooseCallsOk
  if ~c2CallsOk then exit.
  evS = c2Open + 1
  evE = c2C1 - 1
  do KrEvalCond
  if ~evRes then exit.
  c2Res = evRes
  if c2Res = 1
    c2KeepS = c2C1 + 1   ! TRUE  -> the first value
    c2KeepE = c2C2 - 1
  else
    c2KeepS = c2C2 + 1   ! FALSE -> the last value
    c2KeepE = c2Close - 1
  end
  logLn = self.LogLineOf(c2Tok)
  nxPos  = c2KeepE + 1
  nxPos2 = c2Close
  nxKind = 1
  do KrPush              ! everything after the kept value, up to and incl. the ')'
  nxPos  = c2KeepS
  nxPos2 = c2Tok
  nxKind = 2
  do KrPush              ! the kept value inherits CHOOSE's trivia
  nxPos  = c2Tok
  nxPos2 = c2KeepS - 1
  nxKind = 1
  do KrPush              ! `choose(` + the condition + the discarded value
  c2Done = 1
  changes += 1
  if changes = 501
    pLog.append('BUILTIN KnownRanges: further detail lines suppressed (500 shown)<13,10>')
  end
  do KrViaTxt
  if changes <= 500
    if c2Res = 1
      pLog.append('BUILTIN KnownRanges line ' & logLn & ': choose() condition on ' & clip(fName) & ' is always true - collapsed to the first value' & clip(viaTxt) & '<13,10>')
    else
      pLog.append('BUILTIN KnownRanges line ' & logLn & ': choose() condition on ' & clip(fName) & ' is always false - collapsed to the last value' & clip(viaTxt) & '<13,10>')
    end
  end

! ---- may this choose be decided from facts taken at the START of the line? ----
KrChooseCallsOk routine
  data
qz  long,auto
  code
  c2CallsOk = 0
  loop qz = lineFirst to lineLast
    gPos = qz
    do KrGet
    if ~gOk      or |
       gTxt <> '('
      cycle
    end
    caPos = qz
    do KrCallAt
    if ~caIsCall or |
       caPure
      cycle
    end
    mpOpen = qz
    do KrMatchParen
    if ~mpClose then exit. ! unbalanced - refuse
    ! ONLY an ENCLOSING impure call is allowed: the choose is one of its arguments, so it is
    ! computed BEFORE that call has any effect. Anything else - a call that completes before
    ! the choose, a sibling argument of the same call, a call later in the expression - leaves
    ! the order of evaluation up to the compiler, and the fact may already be stale.
    if qz >= c2Tok or |
       mpClose <= c2Close
      exit
    end
  end
  c2CallsOk = 1

! ---- every recv.sub(...) on this line ----
!      The receiver/'.'/method/'(' shape is KrDetectSeed's shape (b), for the same reason:
!      vitTokenize merges a dotted name into ONE token EXCEPT in front of a '(', so a call
!      always arrives as four tokens and `st._DataEnd` always arrives as one.
KrTryS3 routine
  data
uz  long,auto
  code
  uz = lineFirst + 1 ! the first token that can have a recv AND a '.' below it
  loop
    uz += 1
    if uz >= lineLast then break.
    gPos = uz
    do KrGet
    if ~gOk            or |
       gTy <> vt:label or |   ! SUB is not in vitTokenize's reservedWords, so it types as a label
       gTU <> 'SUB'
      cycle
    end
    gPos = uz + 1
    do KrGet
    if ~gOk            or |
       gTxt <> '('
      cycle
    end
    gPos = uz - 1
    do KrGet
    if ~gOk            or |
       gTxt <> '.' ! this dot is vt:dot, not vt:end - a label follows it with no space
      cycle
    end
    gPos = uz - 2
    do KrGet
    if ~gOk            or |
       gTy <> vt:label
      cycle
    end
    spIn = gTU
    do KrSplitRoot
    if spSuf then cycle. ! self.st.sub(...) - not a simple local receiver
    okName = spRoot
    do KrRecvOk
    if ~okRes then cycle.
    s3Recv = okName
    s3Tok  = uz
    s3Open = uz + 1
    mpOpen = s3Open
    do KrMatchParen
    if ~mpClose then cycle.
    s3Close = mpClose
    do KrSubOne
    if s3Done then uz = s3Close. ! never descend into a span we are already rewriting
  end

! ---- one recv.sub(q, x - q + 1): prove the shape and both facts, then stage the collapse.
!      Sound ONLY while q >= 1 and x >= 1 - see the three divergences in the header. ----
KrSubOne routine
  data
oz    long,auto
od    long,auto
onc   long,auto                  ! top-level commas
onm   long,auto                  ! top-level '-'
onp   long,auto                  ! top-level '+'
qKind byte,auto                  ! the fact held by the START operand
qRecv string(vs:maxName),auto
qNm   string(vs:maxName),auto    ! both names, for the log line
xNm   string(vs:maxName),auto
qVia  string(vs:maxName),auto    ! the summary, if any, behind each of them
xVia  string(vs:maxName),auto
  code
  s3Done = 0
  ! ---- 1. EXACTLY one top-level comma. sub(x) and sub(x, y, z) are not the form we model.
  onc  = 0
  od   = 0
  s3Com = 0
  loop oz = s3Open + 1 to s3Close - 1
    gPos = oz
    do KrGet
    if ~gOk then exit.
    if gTxt = '('
      od += 1
    elsif gTxt = ')'
      od -= 1
      if od < 0 then exit.
    elsif ~od and gTxt = ','
      onc += 1
      s3Com = oz
    end
  end
  if onc <> 1            or |
     s3Com <= s3Open + 1 or |   ! empty start
     s3Close <= s3Com + 1 ! empty length
    exit
  end
  ! ---- 2. the length argument: exactly one top-level '-' and one top-level '+', in that order
  onm = 0
  onp = 0
  od  = 0
  loop oz = s3Com + 1 to s3Close - 1
    gPos = oz
    do KrGet
    if ~gOk then exit.
    if gTxt = '('
      od += 1
    elsif gTxt = ')'
      od -= 1
      if od < 0 then exit.
    elsif ~od
      case gTxt
      of '-'
        onm += 1
        s3Min = oz
      of '+'
        onp += 1
        s3Plus = oz
      end
    end
  end
  if onm <> 1 or onp <> 1 or |   ! anything ambiguous is refused outright
     s3Min >= s3Plus
    exit
  end
  ! ---- 3. the three terms of  x - q + 1
  s3X = s3Com + 1
  if s3X <> s3Min - 1     or |   ! the leading term must be ONE token
     s3Plus + 1 <> s3Close - 1 ! the trailing term must be ONE token
    exit
  end
  gPos = s3Plus + 1
  do KrGet
  if ~gOk                 or |
     gTxt <> '1'          or |   ! ... and it must be the literal 1
     s3Min + 1 > s3Plus - 1                                         ! empty middle term
    exit
  end
  s3Q = s3Open + 1
  if s3Q <> s3Com - 1 then exit.                                    ! the start must be ONE token
  if ~self.SpanTokEqual(s3Min + 1, s3Plus - 1, s3Q, s3Q) then exit. ! the middle term must BE the start
  ! ---- 4. both operands are locals holding rk:posBound on THIS receiver.
  !         posBound is what makes the two methods agree; nonNeg is not enough, because a
  !         zero start is off by one and a zero end reads as "to the end of the string".
  gPos = s3Q
  do KrGet
  if ~gOk or |
     gTy <> vt:label
    exit
  end
  spIn = gTU
  do KrSplitRoot
  if spSuf then exit.                                                ! a member read carries no fact
  fName = spRoot
  do KrFind
  qKind = fKind
  qRecv = fRecv
  qNm   = fName
  qVia  = fVia                                                       !
  if qKind <> rk:posBound or |
     qRecv <> s3Recv
    exit
  end
  gPos = s3X
  do KrGet
  if ~gOk                 or |
     gTy <> vt:label
    exit
  end
  spIn = gTU
  do KrSplitRoot
  if spSuf then exit.
  fName = spRoot
  do KrFind
  xNm  = fName
  xVia = fVia                                                     !
  if fKind <> rk:posBound or |
     fRecv <> s3Recv
    exit
  end
  ! ---- 5. nothing in the argument list may carry a comment or a '|', and no impure call
  !         may have run before the sub - the facts were taken at the START of the line.
  tcS = s3Open
  tcE = s3Close
  do KrTriviaClean
  if ~tcOk then exit.
  ccLo = s3Tok
  ccHi = s3Close
  do KrSubCallsOk
  if ~s3CallsOk then exit.
  ! ---- 6. stage it. The delete sits ABOVE the retype, and KrApply works downwards, so the
  !         `sub` token has not moved by the time its text is replaced.
  logLn  = self.LogLineOf(s3Tok)
  nxPos  = s3Min
  nxPos2 = s3Close - 1
  nxKind = 1
  nxTxt  = ''
  do KrPush   ! drop  - q + 1
  nxPos  = s3Tok
  nxPos2 = s3Tok
  nxKind = 3
  nxTxt  = 'slice'
  do KrPush   ! sub -> slice
  s3Done = 1
  changes += 1
  if changes = 501
    pLog.append('BUILTIN KnownRanges: further detail lines suppressed (500 shown)<13,10>')
  end
  viaTxt = '' ! name whichever operand a SUMMARY vouched for
  if qVia and xVia
    viaTxt = ' - ' & clip(qNm) & ' holds what ' & clip(qVia) & '() returns, ' & clip(xNm) & ' what ' & clip(xVia) & '() returns'
  elsif qVia
    viaTxt = ' - ' & clip(qNm) & ' holds what ' & clip(qVia) & '() returns'
  elsif xVia
    viaTxt = ' - ' & clip(xNm) & ' holds what ' & clip(xVia) & '() returns'
  end
  if changes <= 500
    pLog.append('BUILTIN KnownRanges line ' & logLn & ': ' & clip(s3Recv) & '.sub(' & clip(qNm) & |
                ', ' & clip(xNm) & ' - ' & clip(qNm) & ' + 1) is the same span as .slice('      & |
                clip(qNm) & ', ' & clip(xNm) & ') - both are 1 or more' & clip(viaTxt) & '<13,10>')
  end

! ------------------------------------------------------------------------------------
! A SPAN COPIED AROUND IS A SPAN REMOVED.
!
!     st.SetValue(st.sub(1, p - 1) & st.slice(q))   ->   st.RemoveFromPosition(p, q - p)
!
! sub(1, p-1) keeps 1..p-1, slice(q) keeps q.._DataEnd, so what the concatenation drops is
! p..q-1 - exactly q-p characters starting at p. The rewrite is one memmove where the
! original allocates for the sub, again for the slice, again for the concatenation, and
! copies once more in the setValue.
!
! THE GENERAL SHAPE IS NOT PROVABLE, and general is what is wanted. The honest form is
!     `sub(1, A) & slice(B)` -> `RemoveFromPosition(A + 1, B - A - 1)`, which needs
!     B >= A + 1. At B = A + 1 the length is 0 and both spellings leave the string alone;
!     below that the ORIGINAL DUPLICATES characters A+1..B-1 while RemoveFromPosition
!     clamps a negative length to zero and does nothing. They are different programs, so
!     the guard is not optional.
!     The only derivable instance is A = w - 1 with B >= w, because that is precisely what
!     a forward search yields: `q = st.findByte(ch, p)` guarded non-zero gives q >= p.
!     An arbitrary A would need a relational fact between B and A that nothing produces.
!     So S4 matches the `w - 1` form ONLY. That is not a simplification for tidiness - a
!     wider match would have no way to earn its guard. If a real file shows another shape,
!     the fact it needs is the thing to add, not the pattern.
! ------------------------------------------------------------------------------------
KrTryS4 routine
  s4Uz = lineFirst + 1
  loop
    s4Uz += 1
    if s4Uz >= lineLast then break.
    gPos = s4Uz
    do KrGet
    if ~gOk or |
       gTy <> vt:label or |
       gTU <> 'SETVALUE'
      cycle
    end
    gPos = s4Uz - 1
    do KrGet
    if ~gOk            or |
       gTxt <> '.'
      cycle
    end
    gPos = s4Uz - 2
    do KrGet
    if ~gOk            or |
       gTy <> vt:label
      cycle
    end
    spIn = gTU
    do KrSplitRoot
    ! a DOTTED receiver - self.buf.setValue(...). Note it and carry on; the report
    ! must wait until KrS4Shape has confirmed the argument IS a concatenation, or every
    ! ordinary self.x.setValue() in the file would produce a line. Nothing in the reasoning
    ! needs a bare local - the guard is about p and q and the receiver only has to be the
    ! SAME one in all three places - so this is incidental, and it is on the list.
    ! the receiver is now compared WHOLE, so a dotted one works. The tokenizer
    ! splits a dotted name before a bracket, so self.buf.sub(...) arrives as one token
    ! self.buf, then a dot, then sub - exactly the shape a bare st has - and merges it when
    ! there is no bracket, so self.buf.valuePtr arrives whole. Comparing the full token
    ! covers both without a second code path.
    ! KrRecvOk only knows how to check that a BARE local is a StringTheory. For a dotted
    ! receiver we rely instead on the token being IDENTICAL in all three places, which the
    ! matcher already demands, and on the method names being ST's own - a member without
    ! sub/slice/valuePtr on it would not compile as this shape in the first place.
    s4DotR = 0
    sRcv   = gTU
    if spSuf
      s4DotR = 1
      s4DotT = gTxt
    else
      okName = sRcv
      do KrRecvOk
      if ~okRes then cycle.
    end
    gPos = s4Uz + 1
    do KrGet
    if ~gOk or |
       gTxt <> '('
      cycle
    end
    sOpn   = s4Uz + 1
    mpOpen = sOpn
    do KrMatchParen
    if ~mpClose then cycle.
    sCls = mpClose
    do KrS4Shape
    if s4Ok then break.
  end

! ---- the inner shape: <recv>.sub(1, <w> - 1) & <recv>.slice(<b>) ----
KrS4Shape routine
  data
kz  long,auto
dz  long
  code
  s4Ok  = 0
  s4Why = ''
  s4Two = 0
  sAmp  = 0
  loop kz = sOpn + 1 to sCls - 1                                ! the top-level '&' that joins the two terms
    gPos = kz
    do KrGet
    if ~gOk then cycle.
    if gTxt = '(' then dz += 1.
    if gTxt = ')' then dz -= 1.
    if dz then cycle.
    if gTxt = '&'
      if sAmp
        s4Two = 1                                               ! BREAK leaves the LOOP; EXIT would leave the
        break                                                   !   ROUTINE and skip the report below it entirely
      end
      sAmp = kz
    end
  end
  if s4Two
    s4Why = 'more than one top-level & - this is not a two-term concatenation'
    do KrS4Miss
    exit
  end
  if ~sAmp then exit.                                           ! not a concatenation at all - SILENT, or every
  ! ---- left term: THREE SPELLINGS, ONE SPAN. The head keeps 1..w-1 however it is written:
  !       st.sub(1, w - 1)         a LENGTH from 1, so 1..w-1
  !       st.slice(1, w - 1)       an END, and from a start of 1 that is the same
  !       st.valuePtr[1 : w - 1]   the buffer sliced directly
  !      The last matters more than it looks: this tool EMITS it. The fastcompare family and
  !      the getvalue-form both produce valuePtr[1 : _DataEnd], so a matcher that knows
  !      only sub and slice increasingly fails to recognise its own output.
  !      The tokenizer merges a dotted name NOT followed by '(' into one token, so
  !      st.valuePtr arrives whole and spSuf is how it is told apart.
  if sAmp - 1 < sOpn + 7 then exit.
  gPos = sOpn + 1
  do KrGet
  if ~gOk then exit.
  spIn = gTU
  do KrSplitRoot
  if gTU <> sRcv and gTU <> clip(sRcv) & '.VALUEPTR' then exit. ! whole-token compare
  if gTU = clip(sRcv) & '.VALUEPTR'                             ! works for st and self.buf alike
    if sAmp <> sOpn + 9 then exit.                              ! [ 1 : w - 1 ] is eight tokens
    gPos = sOpn + 2
    do KrGet
    if gTxt <> '[' then exit.
    gPos = sOpn + 3
    do KrGet
    if gTxt <> '1'
      s4Why = 'the leading valuePtr slice does not start at 1'
      do KrS4Miss
      exit
    end
    gPos = sOpn + 4
    do KrGet
    if gTxt <> ':' then exit.
    gPos = sOpn + 5
    do KrGet
    if gTy <> vt:label then exit.
    spIn = gTU
    do KrSplitRoot
    if spSuf then exit.
    wNm  = spRoot
    wSrc = gTxt
    sW   = sOpn + 5
    gPos = sOpn + 6
    do KrGet
    if gTxt <> '-' then exit.
    gPos = sOpn + 7
    do KrGet
    if gTxt <> '1'
      s4Why = 'the leading valuePtr end is not <<var> - 1, and that is the only form whose guard can be earned'
      do KrS4Miss
      exit
    end
    gPos = sOpn + 8
    do KrGet
    if gTxt <> ']' then exit.
  else
  gPos = sOpn + 2
  do KrGet
  if gTxt <> '.' then exit.
  gPos = sOpn + 3
  do KrGet
  ! slice(1, w - 1) is the SAME SPAN as sub(1, w - 1): sub takes a LENGTH and slice an END,
  ! and from a start of 1 those coincide - which the matcher guarantees, because it demands
  ! the literal 1 below. So BOTH spellings are admitted here, and anything else is a leading
  ! term this rewrite cannot reason about.
  if gTU <> 'SUB' and gTU <> 'SLICE'
    s4Why = 'the leading term is ' & clip(gTxt) & '(), not sub() or slice()'
    do KrS4Miss
    exit
  end
  sSub = sOpn + 3
  gPos = sSub + 1
  do KrGet
  if gTxt <> '(' then exit.
  mpOpen = sSub + 1
  do KrMatchParen
  if mpClose <> sAmp - 1 then exit. ! the sub must END where the '&' begins
  gPos = sSub + 2
  do KrGet
  if gTxt <> '1'
    s4Why = 'the leading term does not start at 1'
    do KrS4Miss
    exit
  end
  gPos = sSub + 3
  do KrGet
  if gTxt <> ',' then exit.
  if mpClose - 1 <> sSub + 6
    s4Why = 'the leading length is not <<var> - 1, and that is the only form whose guard can be earned'
    do KrS4Miss
    exit
  end
  gPos = sSub + 4
  do KrGet
  if gTy <> vt:label then exit.
  spIn = gTU
  do KrSplitRoot
  if spSuf then exit.
  wNm = spRoot
  wSrc = gTxt                                                   ! the SOURCE spelling - the replacement must not
  sW  = sSub + 4                                                !   upper-case a name the author wrote in lower case
  gPos = sSub + 5
  do KrGet
  if gTxt <> '-' then exit.
  gPos = sSub + 6
  do KrGet
  if gTxt <> '1' then exit.                                     ! ... and it must be `w - 1`
  end                                                           ! end of the call-form head
  ! ---- right term: recv . slice ( b )
  ! ---- right term: the same three spellings, and it must reach the END of the buffer:
  !       st.slice(b)                  omitted end = _DataEnd
  !       st.sub(b, _DataEnd - b + 1)  handled by S3 on an earlier pass, arrives as slice
  !       st.valuePtr[b : st._DataEnd] the end must be _DataEnd EXPLICITLY - anything else
  !                                    stops short and the gap is not what it looks
  gPos = sAmp + 1
  do KrGet
  if ~gOk then exit.
  spIn = gTU
  do KrSplitRoot
  if gTU <> sRcv and gTU <> clip(sRcv) & '.VALUEPTR' then exit. ! whole-token compare
  if gTU = clip(sRcv) & '.VALUEPTR'                             ! works for st and self.buf alike
    if sCls - 1 <> sAmp + 6 then exit.                          ! [ b : recv._DataEnd ] is six tokens
    gPos = sAmp + 2
    do KrGet
    if gTxt <> '[' then exit.
    gPos = sAmp + 3
    do KrGet
    if gTy <> vt:label then exit.
    spIn = gTU
    do KrSplitRoot
    if spSuf then exit.
    bNm  = spRoot
    bSrc = gTxt
    sB   = sAmp + 3
    gPos = sAmp + 4
    do KrGet
    if gTxt <> ':' then exit.
    gPos = sAmp + 5
    do KrGet
    if gTy <> vt:label then exit.
    spIn = gTU
    do KrSplitRoot
    if gTU <> clip(sRcv) & '._DATAEND'
      s4Why = 'the trailing valuePtr slice does not end at ' & clip(sRcv) & '._DataEnd, so it does not reach the end'
      do KrS4Miss
      exit
    end
    gPos = sAmp + 6
    do KrGet
    if gTxt <> ']' then exit.
  else
  gPos = sAmp + 2
  do KrGet
  if gTxt <> '.' then exit.
  gPos = sAmp + 3
  do KrGet
  ! sub(b, recv._DataEnd - b + 1) is the SAME span as slice(b) - both are
  ! b..end. A rule in draft-rules-v15.txt (a working draft, NOT shipped - the shipped rule
  ! file is vitrules.txt) converts one to the other, but this fixture does
  ! not load that file, so relying on it meant the case worked in real use and never in the
  ! gate. S4 reads it directly now and depends on no other pass.
  if gTU <> 'SLICE' and gTU <> 'SUB'
    s4Why = 'the trailing term is ' & clip(gTxt) & '(), not slice(), sub() or valuePtr[]'
    do KrS4Miss
    exit
  end
  s4TlSub = choose(gTU = 'SUB')
  sSlc = sAmp + 3
  gPos = sSlc + 1
  do KrGet
  if gTxt <> '(' then exit.
  mpOpen = sSlc + 1
  do KrMatchParen
  if mpClose <> sCls - 1 then exit.       ! the term must END where the setValue closes
  if s4TlSub
    if mpClose - 1 <> sSlc + 8 then exit. ! b , recv._DataEnd - b + 1
    gPos = sSlc + 3
    do KrGet
    if gTxt <> ',' then exit.
    gPos = sSlc + 4
    do KrGet
    spIn = gTU
    do KrSplitRoot
    if spRoot <> sRcv or spSuf <> '_DATAEND'
      s4Why = 'the trailing sub() length is not ' & clip(sRcv) & '._DataEnd - <<var> + 1, so it does not reach the end'
      do KrS4Miss
      exit
    end
    gPos = sSlc + 5
    do KrGet
    if gTxt <> '-' then exit.
    gPos = sSlc + 7
    do KrGet
    if gTxt <> '+' then exit.
    gPos = sSlc + 8
    do KrGet
    if gTxt <> '1' then exit.
    if ~self.SpanTokEqual(sSlc + 2, sSlc + 2, sSlc + 6, sSlc + 6) then exit.   ! the two b spans must MATCH
  else
    if mpClose - 1 <> sSlc + 2 then exit.                                      ! slice(b) - ONE token
  end
  gPos = sSlc + 2
  do KrGet
  if gTy <> vt:label then exit.
  spIn = gTU
  do KrSplitRoot
  if spSuf then exit.
  bNm = spRoot
  bSrc = gTxt                                                                  !
  sB  = sSlc + 2
  end                                                                          ! end of the call-form tail
  ! ---- the guard: w >= 1 on THIS receiver, and b >= w.
  !      from HERE the shape is confirmed, so a refusal is worth SAYING - reasoning
  !      about why it did not fire is easy to get wrong, and a line in the
  !      report naming the failed test turns that into evidence.
  s4Why = ''
  fName = wNm
  do KrFind
  if fKind <> rk:posBound
    s4Why = clip(wNm) & ' is not known to be 1 or more here - it holds '                      & |
            choose(fKind = rk:none, 'NO fact at all (killed, or never established)',            |
            choose(fKind = rk:zeroBound, 'zeroBound - 0.._DataEnd, never narrowed to non-zero', |
            choose(fKind = rk:nonNeg, 'nonNeg - 0 or more, not bounded by a receiver', 'some other kind')))
    do KrS4Refuse
    exit
  end
  if fRecv <> sRcv
    s4Why = clip(wNm) & ' is bounded by ' & choose(fRecv = '', '(nothing)', clip(fRecv)) & ', not ' & sRcv
    do KrS4Refuse
    exit
  end
  fName = bNm
  do KrFind
  if fKind <> rk:posBound
    s4Why = clip(bNm) & ' is not known to be 1 or more here - it holds '                      & |
            choose(fKind = rk:none, 'NO fact at all (killed, or never established)',            |
            choose(fKind = rk:zeroBound, 'zeroBound - 0.._DataEnd, never narrowed to non-zero', |
            choose(fKind = rk:nonNeg, 'nonNeg - 0 or more, not bounded by a receiver', 'some other kind')))
    do KrS4Refuse
    exit
  end
  if fRecv <> sRcv
    s4Why = clip(bNm) & ' is bounded by ' & choose(fRecv = '', '(nothing)', clip(fRecv)) & ', not ' & sRcv
    do KrS4Refuse
    exit
  end
  if fGeVar <> wNm
    s4Why = 'nothing says ' & clip(bNm) & ' >= ' & clip(wNm) & ' (it is >= '                  & |
            choose(fGeVar = '', 'nothing', clip(fGeVar)) & ')'
    do KrS4Refuse
    exit
  end
  bVia = fVia
  ! ---- trivia and evaluation order, exactly as S3 ----
  ! IT SAID "EXACTLY AS S3" AND ONLY DID THE TRIVIA HALF. S2 has KrChooseCallsOk and S3 has
  !     KrSubCallsOk, both refusing an impure call that RUNS BEFORE the span being rewritten -
  !     the facts were taken at the START of the line, so a call that can write an operand
  !     between then and here invalidates them. S4 had neither, while its comment said it did,
  !     which is worse than no comment: the next reader trusts it. The shape it lets through is
  !     an inline-IF condition carrying an impure call that names an operand and writes it
  !     through a *LONG before the argument evaluates - and S4's own header argues at length
  !     that duplicate-vs-clamp are different programs, which is precisely the harm.
  !     THE SPAN IS THE EXPRESSION BEING REWRITTEN, NOT THE CALL THAT WRAPS IT. KrSubCallsOk
  !     tolerates exactly ONE impure call - the one that ENCLOSES the span, starting before
  !     ccLo and closing after ccHi - because that call is the setter the rewrite is being
  !     handed to, and it runs AFTER the expression it is given. Everything else on the line
  !     ran BEFORE, and the facts were taken at the start of the line.
  !     S3 gets this right by construction: its span is [s3Tok, s3Close], the `sub` call, which
  !     sits INSIDE the setter's parens - so the setter's own '(' is below ccLo and is allowed.
  !     THE FIRST ATTEMPT PASSED sOpn/sCls AND THAT IS THE SETTER'S OWN PARENS. The setter's
  !     '(' is then AT ccLo, `wz >= ccLo` is true for it, and the one call that is supposed to
  !     be tolerated became the one that refused - on every line that had one. Measured:
  !     `rangefix` fell 16 -> 3 and `krdotted` 1 -> 0.
  !     sOpn + 1 / sCls - 1 is the concatenation itself, which is the S3 shape one level in.
  tcS = sOpn
  tcE = sCls
  do KrTriviaClean
  if ~tcOk then exit.
  ccLo = sOpn + 1
  ccHi = sCls - 1
  do KrSubCallsOk
  if ~s3CallsOk then exit.
  ! ---- stage it, highest position first: KrApply works downwards ----
  logLn  = self.LogLineOf(s4Uz)
  nxPos  = sOpn + 1
  nxPos2 = sCls - 1
  nxKind = 1
  nxTxt  = ''
  do KrPush                                                   ! drop the whole concatenation
  nxPos  = sOpn
  nxPos2 = sOpn
  nxKind = 3
  nxTxt = '(' & clip(wSrc) & ', ' & clip(bSrc) & ' - ' & wSrc ! source spelling. The LAST operand needs no clip: its
                                                              !   padding lands at the END of the result and the
                                                              !   assignment truncates it away, so a clip there would
                                                              !   change nothing. clip() removes TRAILING padding, which
                                                              !   sits after the name - if the meaningful text is longer
                                                              !   than nxTxt it is cut at the same character either way.
                                                              !   Against that truncation the remedy is the WIDTH of
                                                              !   nxTxt, which is sized for the worst case; see its
                                                              !   declaration.
  do KrPush                                                   ! '(' becomes '(p, q - p'
  nxPos  = s4Uz
  nxPos2 = s4Uz
  nxKind = 3
  nxTxt  = 'RemoveFromPosition'
  do KrPush                                                   ! setValue -> RemoveFromPosition
  s4Ok    = 1
  changes += 1
  if changes = 501
    pLog.append('BUILTIN KnownRanges: further detail lines suppressed (500 shown)<13,10>')
  end
  if changes <= 500
    pLog.append('BUILTIN KnownRanges line ' & logLn & ': ' & clip(sRcv) & '.setValue(' & clip(sRcv)   & |
                '.sub(1, ' & clip(wNm) & ' - 1) & ' & clip(sRcv) & '.slice(' & clip(bNm)              & |
                ')) copies the string around a gap - it is .RemoveFromPosition(' & clip(wNm) & ', '   & |
                clip(bNm) & ' - ' & clip(wNm) & '), one move instead of four copies'                  & |
                choose(bVia = '', '', ' - ' & clip(bNm) & ' holds what ' & clip(bVia) & '() returns') & |
                '<13,10>')
  end

! ---- may this sub() be rewritten from facts taken at the START of the line? ----
!      The same test, and the same reason, as KrChooseCallsOk: ONLY a call that ENCLOSES
!      the sub is safe, because then the sub is computed before that call has any effect.
!      A sibling argument, or a call that completed first, leaves evaluation order to the
!      compiler and q or x may already have been written through a *LONG we cannot see.
!      Deliberately a SEPARATE routine: the S2 is pinned by the fixture and is not
!      disturbed by this round.
KrSubCallsOk routine
  data
wz  long,auto
  code
  s3CallsOk = 0
  loop wz = lineFirst to lineLast
    gPos = wz
    do KrGet
    if ~gOk      or |
       gTxt <> '('
      cycle
    end
    caPos = wz
    do KrCallAt
    if ~caIsCall or |
       caPure ! SUB and SLICE are both on the pure list, so the sub itself lands here
      cycle
    end
    mpOpen = wz
    do KrMatchParen
    if ~mpClose   or |    ! unbalanced - refuse
       wz >= ccLo or |
       mpClose <= ccHi
      exit
    end
  end
  s3CallsOk = 1

! ---- is okName a simple scalar INTEGER local of scope sc? ----
KrLocalOk routine
  data
lz  long,auto
  code
  okRes = 0
  if ~okName then exit.
  lz = self.syms.FindSym(okName, sc)             ! scope sc only - a module-level or outer name is not ours
  if ~lz then exit.
  get(self.syms.syms, lz)
  if errorcode() then exit.
  if self.syms.syms.isRef then exit.
  if self.syms.syms.isLike then exit.
  if self.syms.syms.isField then exit.
  case self.syms.syms.typeU
  of 'LONG' orof 'ULONG' orof 'SHORT' orof 'USHORT' orof 'BYTE' orof 'SIGNED' orof 'UNSIGNED'
    ! an integer position variable - ok
  else
    exit                                         ! REAL/DECIMAL/STRING/... are not what these seeds produce
  end
  okDecl = self.syms.syms.declTok
  if ~self.syms.IsColOneLabel(okDecl) then exit. ! a PARAMETER is not a column-1 declaration
  if band(self.DeclAttrBits(okDecl), ab:over + ab:dim + ab:static + ab:thread) then exit.
  ! *** AND A SIBLING DECLARED OVER(V) IS THE FIFTH SPELLING OF V'S STORAGE. *** The line above
  ! asks whether THIS variable is an alias; it does not ask whether something else aliases it.
  ! With `p LONG` and `sh SHORT,OVER(p)`, writing sh writes p - so a fact about p can be true
  ! when it is recorded and false by the time it is used, and the guard it justified deleting
  ! was load-bearing. Measured: `p = st.findByte(61) ; sh = -5 ; if p >= 0 then f = 1.` lost its
  ! guard while p was -5. AutoCheck asks this same question of its own candidates.
  if self.HasSiblingOver(lz, okName) then exit.
  okRes = 1

! ---- is okName a simple LOCAL StringTheory of scope sc? ----
KrRecvOk routine
  data
rz  long,auto
  code
  okRes = 0
  if ~okName then exit.
  rz = self.syms.FindSym(okName, sc)             ! module-level receivers are out: a call this walk cannot see
  if ~rz then exit.                              !   could move their _DataEnd without naming them here
  get(self.syms.syms, rz)
  if errorcode() then exit.
  if self.syms.syms.isRef then exit.             ! `st &= other` re-points a reference and carries no call
  if self.syms.syms.isLike then exit.
  if self.syms.syms.isField then exit.
  if self.syms.syms.typeU <> 'STRINGTHEORY' then exit.
  okDecl = self.syms.syms.declTok
  if ~self.syms.IsColOneLabel(okDecl) then exit.
  if band(self.DeclAttrBits(okDecl), ab:over + ab:dim) then exit.
  okRes = 1

! ---- append one staged edit (dataless routine -> no CODE section) ----
KrPush routine
  clear(KrEdQ)
  kr:pos  = nxPos
  kr:pos2 = nxPos2
  kr:kind = nxKind
  kr:txt  = nxTxt ! kind 3 only; KrApply never reads it for kinds 1 and 2
  add(KrEdQ)

! ---- apply the staged edits HIGHEST POSITION FIRST; a delete shifts everything above it.
!      A kind-2 donor is ALWAYS below its target, so by the time the sweep reaches the
!      target every remaining delete is below the donor too and the donor has not moved.
!      A kind-3 retype is the same story from the other side: its token is BELOW the
!      delete staged with it, so the delete lands first and the token has not moved. ----
KrApply routine
  data
az  long,auto
  code
  sort(KrEdQ, -kr:pos)
  loop az = 1 to records(KrEdQ)
    get(KrEdQ, az)
    if errorcode() then break.
    case kr:kind
    of 1
      self.tk.DeleteToks(kr:pos, kr:pos2)
    of 3
      self.tk.SetTok(kr:pos, clip(kr:txt)) ! strBefore OMITTED on purpose - SetTok then leaves the indent alone
    else
      get(self.tk.tokens, kr:pos2)
      if errorcode() then cycle.
      sbSt.free()
      if not self.tk.tokens.strBefore &= NULL
        sbSt.setValue(self.tk.tokens.strBefore)
      end
      if sbSt._DataEnd
        self.tk.SetStrBefore(kr:pos, sbSt.valuePtr[1 : sbSt._DataEnd])
      else
        self.tk.SetStrBefore(kr:pos, '')
      end
    end
  end

! ------------------------------------------------------------------------------------
! The calls KnownRanges accepts as unable to move a tracked value or a bound. Space
! delimited, UPPER, with a leading AND a trailing space so instring(' NAME ', list) cannot
! match a substring of a longer name. Two families, both READ-ONLY by definition:
!   * Clarion reader builtins - they compute a value from their arguments and touch nothing;
!   * StringTheory reader methods - they inspect self.value and do not modify it.
! Anything absent is treated as IMPURE, which is the safe direction: an impure call drops
! every fact whose variable or receiver is named on that line. A rule file adds its own with
! BUILTIN KnownRanges, PURE(myFn myOtherFn).
! NOTE the list is built with several appends on purpose: a single quoted literal beyond
! roughly 680 characters stops the Clarion parser dead.
! ------------------------------------------------------------------------------------
VitEngine.KnownRangePureList Procedure(StringTheory pOut)
  code
  pOut.setValue(' UPPER LOWER CLIP LEFT RIGHT CENTER SUB LEN VAL CHR NUMERIC INSTRING ')
  pOut.append('FORMAT DEFORMAT ABS INT ROUND BAND BOR BXOR BSHIFT CHOOSE ADDRESS SIZE ')
  pOut.append('RECORDS POINTER ')
  pOut.append('GETVALUE GETVALUEPTR LENGTH LENGTHA CLIPLENGTH SLICE GETLINE ')
  pOut.append('FINDCHAR FINDCHARS FINDBYTE CONTAINSCHAR CONTAINSBYTE STARTSWITH ENDSWITH ')
  pOut.append('EQUALS BETWEEN ') ! COMPARE and LINES were in this list and
                                 !   are neither StringTheory methods nor
                                 !   Clarion functions. A name wrongly IN a
                                 !   purity list is a WRONG transform, not a
                                 !   missed one - the unsafe direction.

! ====================================================================================
! BUILTIN TrailingSpaces (OPT-IN) - do not PROVE the buffer has no trailing
! spaces, MAKE it true, then retire the code that keeps asking about them.
! The shape this comes from:
!
!     st.Replace('<9>', ' ')                  the tail may now be padded
!     st.clip()                               <- INSERTED once, at a top-level point
!     pLen = st.clipLength()             ->   pLen = st._DataEnd
!     p    = st.findChar('=', 1)
!     return clip(st.getValue())         ->   return st.getValue()
!
! THE MODEL. Per proc/method MAIN code (routines excluded by acMainEnd, exactly as
! AutoCheck and KnownRanges exclude them), per LOCAL StringTheory receiver. Every
! textual occurrence of the receiver is classified into ONE of the ts:* kinds - see
! TsMethodKind, which is the only place the whitelist lives. Two properties matter and
! they are NOT the same property:
!
!   BLIND        the use cannot tell whether the buffer ends in spaces - it gives the
!                same answer either way. Needed so that INSERTING a clip is invisible.
!   CLEAN-KEEP   the use cannot CREATE a trailing space. Needed so that "the buffer is
!                clean" survives from the clip down to the uses that rely on it.
!
! ts:read / ts:clipLen / ts:anchor are both. ts:cleanSet is both AND makes the buffer
! clean. ts:bad is neither, and any doubt collapses to ts:bad.
!
!   REGION       let lastBad be the LAST occurrence in the scope that is ts:bad (a `DO`
!                counts - a routine can touch any buffer). P is the first DEPTH-0 line
!                start below lastBad. Then every occurrence in [P .. mainEnd] is BLIND
!                and CLEAN-KEEP, by construction.
!   ANCHOR       the region must contain a `clip(recv.getValue())`. That is the author
!                saying the trailing spaces of the result are dead. Without it the pass
!                does nothing (a region with no anchor is left completely alone).
!
! WHY DEPTH 0 IS LOAD-BEARING. The region is a TEXTUAL suffix. It is also the set of
! uses reachable after control passes P only because P sits at depth 0 of the scope: no
! enclosing block can jump control back ABOVE P, and GOTO is refused outright by the
! existing AutoScopePrep bail. So a loop inside the region needs no fixpoint iteration -
! every operation it can perform is already in the region, and no operation in the region
! can dirty the buffer. That single observation is what removes the loop analysis the
! design would otherwise have needed.
!
! THE TWO HALVES.
!   HALF A (simplify), applied to every qualifying use BELOW the clean point:
!     A1  recv.clipLength()      -> recv._DataEnd      (the receiver token is retyped and
!         the `. clipLength ( )` tokens are dropped, so it stays ONE token, which is what
!         the tokenizer produces for a dotted name that is not followed by a paren. The
!         existing rest-of-string RULE then collapses recv.sub(w, recv._DataEnd - w + 1)
!         to recv.slice(w) on a later pass - that part is not done here.)
!     A2  clip(recv.getValue())  -> recv.getValue()    (`clip` and its '(' are dropped, the
!         receiver token inherits clip's leading trivia, and the extra ')' goes.)
!   HALF B (insert): if the receiver is NOT already provably clean at the top of the
!     region, insert `recv.clip()` on its own line immediately before P, which makes it
!     clean, which is what licences A1 and A2. Half B is never done alone: it requires at
!     least one A1 to be waiting below it, because an insertion that only retires the
!     anchor clip moves the same clip from one line to another and is a wash.
!
! THE SAFETY ARGUMENT, in one line each.
!   * inserting the clip is invisible because every use below it is BLIND;
!   * the buffer STAYS clean all the way down because every use below it is CLEAN-KEEP;
!   * A1 is then an identity (clipLength() and _DataEnd agree on a clean buffer);
!   * A2 is then an identity (clip(x) is x when x has no trailing spaces);
!   * everything not on the whitelist is ts:bad, and ts:bad only ever moves P DOWN, i.e.
!     shrinks what the pass is allowed to touch. Every bail lands there.
!
! THE FIXPOINT ARGUMENT - this is the FIRST transform that inserts a statement, so it has
! to be proved, not asserted. Two independent guarantees, either one sufficient:
!   1. An insertion happens only when the receiver is NOT already clean at the top of the
!      region, and "already clean" means the first occurrence at or below P is a ts:cleanSet
!      that is ALONE on its own depth-0 line. What we insert is exactly that: `recv.clip()`
!      alone on its own depth-0 line, placed between lastBad and the old P. Nothing above P
!      is edited, so lastBad cannot move up; therefore on the next pass the first depth-0
!      line start below lastBad IS our inserted line, its statement IS a ts:cleanSet, and
!      the guard fires. At most one insertion per receiver per scope, ever.
!   2. Independently: an insertion requires at least one ts:clipLen use below it, and the
!      same pass rewrites EVERY ts:clipLen use in the region into _DataEnd. A rewritten one
!      is a merged `recv._DataEnd` token, which classifies ts:bad. So after one pass there
!      is no ts:clipLen left to justify a second insertion, and lastBad has moved DOWN past
!      the rewrite, shrinking the region further.
!   Convergence in practice: pass 1 inserts and simplifies; pass 2 finds `recv._DataEnd`
!   (ts:bad) and a now-unclipped `return recv.getValue()` (ts:bad) and stages nothing.
!
! THE LINE MAP - which neighbour wins, and why. An inserted line has no source line, so
! SetLineNumbers/MapFold must fold it onto a neighbour. Left alone MapFold would give it
! the PREDECESSOR (a wholly-inserted line finds no survivor token carrying a real lineNo
! and falls back to the carry). The design wants the SUCCESSOR - the construct the clip
! enables - so that a click on it in VitStyle's After pane lands somewhere meaningful.
! TsApplyInsert therefore stamps the construct's own lineNo onto every inserted token
! before returning. MapFold then reads a real, monotone line off the first token of the
! new line and maps it to the construct's source line; the construct's own line maps
! there too, so this is the ordinary 1 -> N case that the map and the survivor
! lookahead already handle (ExpandOneLiners makes 1 -> 3 the same way).
!
! WHAT IT REFUSES (all under-reach - a refusal leaves working code exactly as it was):
!   * a scope with GOTO / COMPILE / OMIT, and every ROUTINE body (AutoScopePrep);
!   * a scope whose depth walk does not return to the depth it started at. An INLINE '.'
!     terminator is retyped vt:end but may carry NO '-' level mark, so the close test is
!     the inline-dot idiom; if the walk still ends unbalanced the WHOLE scope is skipped, because
!     "depth 0" would then be a lie and depth 0 is the whole reachability argument;
!   * any receiver that is not a simple LOCAL StringTheory of this scope - a module-level
!     one could be moved by a call this walk cannot see, and &-reference / LIKE / OVER /
!     DIM / STATIC / THREAD / parameter forms are all out;
!   * a receiver named BARE anywhere in the scope (`foo(st)`, `st &= other`, `address(st)`).
!     A bare mention can alias the buffer to something that later mutates it WITHOUT
!     naming it, which no textual walk can see. This is the only refusal that is scope-wide
!     rather than region-wide, and it is deliberately so;
!   * `DO` anywhere in the region;
!   * `recv._DataEnd`, `recv.len()`, `recv.length()` - they COUNT the spaces;
!   * `recv.append(...)`, `recv.prepend(...)` - THE TRAP. If the buffer ends in spaces and
!     something appends, those spaces become INTERNAL: 'abc  ' & 'x' is not 'abc' & 'x';
!   * `recv.getValue()` that is NOT immediately wrapped in `clip(...)` - the trailing
!     spaces escape to the caller, so they are not dead;
!   * a needle that is, or might be, a space: findChar(' '), findByte(32), any needle that
!     is not a single quoted literal / integer, and any literal containing a '<' escape;
!   * clipLength(pStr), clip(alphabet), trim(alphabet), getValue(start,len) - same name,
!     different method;
!   * an insertion point whose previous token is not an EOL, or whose leading trivia is
!     not pure indent (a comment or a '|' continuation carrier lives there);
!   * a comment or a '|' inside anything being deleted or re-trivia-ed;
!   * lastBad = 0, i.e. nothing above P has touched the buffer at all. The design is
!     explicit that the clip must not go at the top of a procedure, where the buffer may
!     not be populated yet.
!
! DELIBERATE DEVIATION 1 - the design's table is used for BLIND only, never for
!     CLEAN-KEEP, and `setLength(n)` / bare `setValue(x)` are therefore REFUSED here even
!     though the table lists setLength as insensitive. The design's Half B says "mark the
!     receiver clean from there", which silently assumes insensitive implies clean. It does
!     not. setLength TRUNCATES (StringTheory.SetLength: _DataEnd = NewLength), so a clean
!     buffer can come out of it dirty, and setValue stores an arbitrary string.
!     This is not a corner: it retires the motivating example itself. Take
!         st = 'LONG pA, STRING pB = 5'          (no trailing spaces anywhere)
!         p = st.findChar('=')  -> 20 ; q = st.findChar(',', 20) -> 0
!         st.setLength(p - 1)   -> 'LONG pA, STRING pB '         <- a space is CREATED
!         return clip(st.getValue())  -> 'LONG pA, STRING pB'
!     Drop that clip and the procedure returns the trailing space instead. The clip is
!     doing real work on the most ordinary input, and no clip inserted before the loop can
!     help, because the space is made after it. MaskSigBase in TestData\trailspace.clw
!     pins this refusal and carries the counterexample.
!
! DELIBERATE DEVIATION 2 - `sub` / `slice` / `crop` are refused OUTRIGHT, not only
!     when they reach the end. The design splits them on "reaching the end of the buffer",
!     which is a property of the ARGUMENTS at run time - st.sub(1, p - 1) reaches the end
!     exactly when p - 1 is at least the clipped length, and nothing in this walk knows p.
!     Guessing here would be a silent behaviour change, so the whole family is ts:bad.
!
! ---- THE SPACELESS MODE - the second way in, and the one that lifts MaskSigBase --
! Everything above is the CLEAN mode: it knows only "no TRAILING spaces", it has to MAKE
! that true by inserting a clip, and DEVIATION 1 therefore refuses setLength. the summary pass adds a
! second, independent mode that runs FIRST (TsSpacelessTry) and inserts nothing at all:
!
!     st.SetValue(self.StripRefSig(pParams))   StripRefSig is sm:spaceless (summary),
!                                              so from here st contains NO SPACES AT ALL
!     st.Replace(',omitmask', '')              a space-free replacement cannot add one
!     if p - 1 < st._DataEnd then st.setLength(p - 1).  a GUARDED shrink - see TsTruncGuard
!     pLen = st.clipLength()             ->    pLen = st._DataEnd
!     return clip(st.getValue())         ->    return st.getValue()
!
! The region is (the setValue .. mainEnd] and it needs no ANCHOR, because with no spaces in
! the buffer both A1 and A2 are IDENTITIES rather than transformations licensed by an
! author's intent. What it does need, for every use below the store:
!   * VitEngine.SpaceKeepUse says the use cannot put a space INTO the buffer (reads, clip,
!     trim, removeByte, and replace() with a space-free literal replacement), or
!   * TsTruncGuard says it is `if E < recv._DataEnd then recv.setLength(E).`, the author's
!     own same-line proof that the setLength shrinks;
!   * no `DO` below the store, and no BARE mention of the receiver anywhere in the scope
!     (TsScanUses' existing scope-wide refusal).
! The store itself must be UNCONDITIONAL: a depth-0 line start with nothing else on its line.
! Every log line the mode produces NAMES the callee, because the evidence for it is in
! another procedure and the changed line cannot be audited on its own.
!
! WHY setLength IS NOT SIMPLY ALLOWED HERE, which is a DEVIATION from the design.
!     The design (and the DEVIATION 1) both describe setLength as a truncation, in which
!     case spacelessness would survive it unconditionally. StringTheory.SetLength also
!     GROWS - and it pads the new bytes with byte 32 (stMemSet(..., 32, ...), both the
!     buffer and the non-buffer path). An unguarded setLength can therefore put trailing
!     spaces INTO a spaceless buffer and retire a clip that was doing real work. Hence the
!     guard, and hence GrowLength in TestData\summary.clw, which pins the refusal.
!
! ---- A SPACELESS setValue MAY BE A CONCATENATION -----------------------------
! The summary pass took a setValue only when its argument was EXACTLY ONE call with an sm:spaceless
! summary, which is why it never reached the line the whole exercise started from:
!
!     st.SetValue(st.sub(1, p - 1) & st.sub(choose(q < 0, st._DataEnd + q + 1, q),
!                                           st.clipLength() - q + 1))
!
! splits the argument on TOP-LEVEL '&' (depth 0, so an '&' inside a nested call's
! arguments does not split) and requires EVERY term to be spaceless-yielding - TsConcatOk
! and TsTermOk. A term qualifies three ways and no other:
!   1. a call whose summary is sm:spaceless        (the case, now applied per term);
!   2. a SELF-SLICE - recv.sub / recv.slice / recv.getValue on the SAME receiver - a substring of
!      a string with no spaces has no spaces;
!   3. a quoted literal with no space, tab or '<' escape in it.
! A BARE VARIABLE is refused, and that is not fussiness: '&' on a fixed STRING(n) operand
! concatenates WITH the padding. It is safe for 1 and 2 because a Clarion PROCEDURE
! returning STRING returns exactly its own length, not a padded field.
!
! DEVIATION - TERM 2 IS ADMISSIBLE ON THE KEEP WALK ONLY, and the design does not
!     say so. The design puts the whole rule in TsSpaceSetAt, the walk that CHOOSES the
!     store, and there it is circular: at the store nothing is yet known about the buffer,
!     so `st.setValue(st.sub(1, 5))` would "prove" spaceless from a slice of anything.
!         st.setValue(pParams)          arbitrary, spaces and all
!         st.setValue(st.sub(1, 5))     <- would establish spaceless. It does not.
!     Hence cnSelf: 0 on the ESTABLISH walk (terms 1 and 3 only), 1 on the KEEP walk, where
!     the forward walk already has the fact and a slice of it is sound. ConcatSlices in
!     TestData\summary.clw is written the second way, exactly as parser.MaskSigBase is.
!
! DEVIATION - the KEEP walk had to learn about setValue at all. SpaceKeepUse answers 0
!     for sk:store and must keep doing so: it also runs inside BuildSummaries and may not
!     read summaries that pre-pass is in the middle of building. In parser.MaskSigBase the
!     concatenation is INSIDE the loop, so it is never the store - it is a use BELOW the
!     store - and the design's placement alone would not have moved that line. So
!     TsSpaceKeepAt now tries TsSpaceSetAt itself, after SpaceKeepUse and TsTruncGuard.
!
! DEVIATION - TsDataEndRead, for the same line. See its own header.
!
! This builtin INSERTS and DELETES code. OPT-IN: vitrules.txt declares it inside
!     `GROUP analysis, OFF`, so a plain run never reaches it and --group=analysis turns it on.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinTrailingSpaces Procedure(StringTheory pLog)
s          long,auto
raw        StringTheory
noteSt     StringTheory       ! NOTE('...') - LOG text only; it never injects a comment into the source
sbSt       StringTheory       ! donor trivia while applying a kind-2 edit
insSt      StringTheory       ! the text handed to InsertString
indSt      StringTheory       ! captured indent of the insertion point
wsST       StringTheory       ! a VEHICLE for IsAll in TsTriviaClean - its own value is never consulted
inserts    long
simps      long
changes    long,auto
scRow      long,auto          ! row in syms.scopes
scKind     byte,auto
sc         long,auto          ! scopeId of the proc/method being walked
scSelf     string(vs:maxName) ! the method's receiver class, captured BEFORE AutoScopePrep clobbers the buffer
scNameU    string(vs:maxName) ! that scope's declaration label, UPPER - the proof bank's scope-STABLE key
codeT      long,auto
mainEnd    long,auto
scBad      byte               ! the depth walk of this scope did not balance - skip it whole
rcIx       long,auto
opLT       string(4)          ! chr() sidesteps the doubling rule for '<' entirely
opLE       string(4)
! ---- token peek (TsGet)
gPos       long,auto
gOk        byte
gNull      byte               ! the record carries no token (trivia-only tail record)
gTxt       string(vs:maxName)
gTU        string(vs:maxName)
gTy        string(1)
gLv        string(1)
! ---- cross-pass proof of a guarded setLength
tpArgU     string(vs:maxName) ! the setLength argument, tokens joined and upper-cased
tpArg      stringTheory       ! the accumulator TsArgText builds tpArgU in
tpAS       long,auto
tpAE       long,auto
tpHit      byte
! ---- name splitting (TsSplitRoot)
spIn       string(vs:maxName)
spRoot     string(vs:maxName)
spSuf      string(vs:maxName)
! ---- paren matching (TsMatchParen)
mpOpen     long
mpClose    long
! ---- argument spans of the call at mpOpen (TsArgs)
agN        long ! top-level argument count (0 = empty parens)
agS        long ! FIRST argument: first token
agE        long ! FIRST argument: last token
agLS       long ! LAST  argument: first token
agLE       long ! LAST  argument: last token
! ---- classification (TsClassify)
tcPos      long
tcKind     byte
tcEnd      long ! last token of the whole use (for an anchor: clip's ')')
mth        string(vs:maxName)
kndName    long
ltOk       byte ! TsLitOk: the needle is a literal that cannot be a space
! ---- trivia scan (TsTriviaClean)
tcS        long
tcE        long
tcOk       byte
! ---- indent / insertion-point checks
indOk      byte
insOk      byte
lsPos      long
lsOk       byte
! ---- scope line walk
depth      long
prevEol    byte
! ---- per receiver
rcU        string(vs:maxName)                                    ! UPPER name, for matching token roots
rcTxt      string(vs:maxName)                                    ! SOURCE case, for the code we write
recvBad    byte                                                  ! a BARE mention - this receiver is out for the whole scope
lastBad    long                                                  ! last occurrence that refuses the region (0 = none)
pTok       long                                                  ! the insertion point / start of the region
firstIx    long
cleanFrom  long                                                  ! uses at or below this token are NOT yet known clean
alreadyCl  byte
nAnchor    long
nClip      long
nSimp      long
uPos       long
uEnd       long
uKind      byte
edOk       byte
logLn      long,auto
! ---- SPACELESS mode: the receiver was STORED from a call whose summary is sm:spaceless
slOk       byte                                                  ! the whole mode validated for this receiver
slPos      long                                                  ! the setValue that makes it spaceless
slEnd      long                                                  ! ... and its closing ')'
slIx       long                                                  ! its row in TsUseQ
slName     string(vs:maxName)                                    ! the callee - the EVIDENCE every log line has to name
ssOk       byte                                                  ! TsSpaceSetAt out
ssEnd      long
ssName     string(vs:maxName)
skOk       byte                                                  ! TsSpaceKeepAt out
smNm       string(vs:maxName)                                    ! SummaryOfCallAt out
smF        byte
! ---- CONCATENATION: the setValue argument split on TOP-LEVEL '&'
cnSelf     byte                                                  ! may a term be a SELF-SLICE?  ONLY where the buffer is already known spaceless
cnOk       byte                                                  ! TsConcatOk out - every term is spaceless-yielding
cnNm       string(vs:maxName)                                    ! the first SUMMARISED callee among the terms - the evidence a log line has to name
tmS        long                                                  ! ONE term: first token
tmE        long                                                  ! ONE term: last token
tmOk       byte                                                  ! TsTermOk / TsLitSpaceless out
! ---- edit staging
nxPos      long
nxPos2     long
nxKind     byte
nxTxt      string(vs:maxName + 16)                               ! was string(140), a LITERAL sized by hand against
                                                                 !   vs:maxName when it was 100 (100 + '.clip()' = 107, fits).
                                                                 !   raised vs:maxName to 255 and this did not follow, so a
                                                                 !   long receiver name truncated INTO EMITTED SOURCE. Sized off
                                                                 !   the equate now, so it cannot fall behind again. The longest
                                                                 !   suffix assigned here is '._DataEnd' - 9 chars (TsStageClipLen;
                                                                 !   '.clip()' is 7) - and +8 was ONE BYTE SHORT for a maxName-length
                                                                 !   receiver: `name._DataEn` into emitted source. +16 leaves slack
                                                                 !   for the next suffix too.
TsRecvQ  QUEUE,PRE(tsv)
tsvNameU  string(vs:maxName)
tsvText   string(vs:maxName)
         END
TsLineQ  QUEUE,PRE(tsl)                                          ! every DEPTH-0 line start of this scope's main code, ascending
tslPos    long
         END
TsUseQ   QUEUE,PRE(tsu)                                          ! every occurrence of ONE receiver in this scope, ascending
tsuPos    long                                                   ! the receiver token
tsuEnd    long                                                   ! last token of the use
tsuKind   byte                                                   ! ts:*
         END
TsEdQ    QUEUE,PRE(tse)
tsePos    long                                                   ! kind 1: first token to delete.  2/3/4: the token acted on
tsePos2   long                                                   ! kind 1: last token to delete.   2: the DONOR token (always BELOW pos)
tseKind   byte                                                   ! 1 DeleteToks / 2 SetStrBefore from pos2 / 3 SetTok to txt / 4 insert txt as a new line before pos
tseTxt    string(vs:maxName + 16)                                ! nxTxt is assigned straight into this - same size, same reason
         END
  code
  if self.syms &= NULL then return 0.
  self.acScopeId = 0                                             ! the token stream may have moved since the last pass
  free(TsRecvQ)                                                  ! local QUEUEs persist between calls - start every pass empty
  free(TsLineQ)
  free(TsUseQ)
  free(TsEdQ)
  opLT = chr(60)                                                 !
  opLE = chr(60) & '='
  noteSt.free()
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      case upper(self.rl.rules.bparmQ.name)
      of 'NOTE'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)
          raw.unquote('''','''')
          noteSt.setValue(raw)                                   ! reported once in the log; NEVER written into the source
        end
      end
    end
  end

  self.BuildSummaries()                                          ! what every proc/method in this file RETURNS - the spaceless mode below reads it
  if self.syms.scopes &= NULL then return 0.
  loop scRow = 1 to records(self.syms.scopes)
    get(self.syms.scopes, scRow)
    if errorcode() then break.
    scKind = self.syms.scopes.kind
    sc     = self.syms.scopes.scopeId
    scSelf = self.syms.scopes.selfClass                          ! which class a `self.` call in this scope names
    scNameU = upper(self.tk.GetTok(self.syms.scopes.startTok))   ! the DECLARATION LABEL - what the proof bank is keyed on.
                                                                 !   For a method that is `Class.Method`, so it is unique in the file
                                                                 !   on its own; blank means we could not name the scope, and TsProvenAdd
                                                                 !   then banks nothing rather than banking under a key that is not one.
    if scKind <> vs:scProc and scKind <> vs:scMethod then cycle. ! module data has no code; a ROUTINE is covered by the DO bail
    self.AutoScopePrep(sc)                                       ! NB clobbers the scopes buffer - sc/scKind/scSelf are captured above
    if self.acBail then cycle.                                   ! missing scope / no CODE / GOTO / COMPILE / OMIT present
    codeT   = self.acCodeT
    mainEnd = self.acMainEnd
    if mainEnd <= codeT then cycle.
    do TsScopeLines
    if scBad then cycle.
    do TsCollect
    loop rcIx = 1 to records(TsRecvQ)
      get(TsRecvQ, rcIx)
      if errorcode() then break.
      rcU   = tsv:tsvNameU
      rcTxt = tsv:tsvText
      do TsReceiver
    end
  end

  changes = inserts + simps
  if changes
    do TsApply
    self.wantReparse = true ! tokens inserted AND deleted; later builtins must see the new stream
    if noteSt._DataEnd
      pLog.append('BUILTIN TrailingSpaces: ' & clip(noteSt.getValue()) & '<13,10>')
    end
    pLog.append('BUILTIN TrailingSpaces: ' & inserts & ' insertion(s), ' & simps & ' simplification(s) this pass<13,10>')
  end
  free(TsRecvQ)
  free(TsLineQ)
  free(TsUseQ)
  free(TsEdQ)
  return changes

! ---- one token into gTxt / gTU / gTy / gLv / gNull ----
TsGet routine
  gOk   = 0
  gNull = 0
  gTxt  = ''
  gTU   = ''
  gTy   = ' '
  gLv   = ' '
  if gPos < 1 then exit.
  get(self.tk.tokens, gPos)
  if errorcode() then exit.
  gTy = self.tk.tokens.type
  gLv = self.tk.tokens.level
  if not self.tk.tokens.tok &= NULL
    if size(self.tk.tokens.tok) > size(gTxt) then exit.            ! the token does NOT FIT.
                                                                   !   gTxt is a fixed STRING, so a longer token arrives
                                                                   !   TRUNCATED, and the whitespace guards downstream
                                                                   !   (TsLitOk, TsLitSpaceless, SkReplOk) then scan the
                                                                   !   short copy and answer 'provably space-free' for a
                                                                   !   literal whose first space sits past the cut - which
                                                                   !   licenses removing a clip() that was doing real work.
                                                                   !   gOk stays 0, so every caller reads this as 'cannot
                                                                   !   see it' and refuses, which is the house answer.
    gTxt = self.tk.tokens.tok
    gTU  = upper(self.tk.tokens.tok)
  else
    gNull = 1
  end
  gOk = 1

! ---- split spIn at its FIRST '.' -> spRoot / spSuf (a bare name gives spSuf = '') ----
TsSplitRoot routine
  data
dz  long,auto
nz  long,auto
  code
  spRoot = spIn
  spSuf  = ''
  nz = len(clip(spIn))
  if ~nz then spRoot = '' ; exit.
  dz = instring('.', spIn, 1, 1)
  if dz > 1 and dz < nz
    spRoot = spIn[1 : dz - 1]
    spSuf  = spIn[dz + 1 : nz]
  elsif dz
    spRoot = '' ! a leading or trailing dot - not a name we model
  end

! ---- matching ')' for the '(' at mpOpen, searching forward from it (0 = none) ----
TsMatchParen routine
  data
mz  long,auto
md  long,auto
  code
  mpClose = 0
  md      = 0
  loop mz = mpOpen to mainEnd
    gPos = mz
    do TsGet
    if ~gOk then exit.
    if gTy = vt:literal then cycle. ! a bracket INSIDE a quoted literal is text, not structure
    case gTxt
    of '('
      md += 1
    of ')'
      md -= 1
      if ~md then mpClose = mz ; exit.
      if md < 0 then exit.
    end
  end

! ---- top-level argument spans of the call whose parens are mpOpen .. mpClose ----
TsArgs routine
  data
az2 long,auto
ad  long,auto
  code
  agN  = 0
  agS  = 0
  agE  = 0
  agLS = 0
  agLE = 0
  if mpClose <= mpOpen + 1 then exit. ! () - no arguments at all
  agN  = 1
  agS  = mpOpen + 1
  agLS = mpOpen + 1
  agLE = mpClose - 1
  ad   = 0
  loop az2 = mpOpen + 1 to mpClose - 1
    gPos = az2
    do TsGet
    if ~gOk then exit.
    if gTy = vt:literal then cycle.
    if gTxt = '('
      ad += 1
    elsif gTxt = ')'
      ad -= 1
    elsif ~ad and gTxt = ','
      agN += 1
      if agN = 2 then agE = az2 - 1.
      agLS = az2 + 1
    end
  end
  if agN = 1 then agE = mpClose - 1.

! ---- the FIRST argument is a single quoted literal that cannot possibly be a space ----
TsLitOk routine
  data
lz  long,auto
ln2 long,auto
lc  string(1),auto
  code
  ltOk = 0
  gPos = agS
  do TsGet
  if ~gOk or |
     gTy <> vt:literal  ! a computed needle - we cannot see what it is
    exit
  end
  ln2 = len(clip(gTxt))
  if ln2 < 3 then exit. ! the empty literal
  loop lz = 2 to ln2 - 1
    lc = gTxt[lz]
    case val(lc)
    of 32 orof 9
      exit              ! the needle IS whitespace: clipping moves the answer
    of 60
      exit              ! a '<' escape - the needle may BE a space under another name
    end
  end
  ltOk = 1

! ---- every strBefore in [tcS..tcE] is plain whitespace (no comment, no bar, no line break) ----
TsTriviaClean routine
  data
qz  long,auto
  code
  tcOk = 0
  loop qz = tcS to tcE
    get(self.tk.tokens, qz)
    if errorcode() then exit.
    if self.tk.tokens.strBefore &= NULL then cycle.
    if ~wsST.IsAll('<32,9>', self.tk.tokens.strBefore, false) then exit. ! '!' comment, '|' continuation or a CR/LF
    ! ISALL SAYS THIS IN ONE LINE, and the hand-rolled character walk that was here said it in
    !   twelve. The two are the same test; the library one is harder to get subtly wrong.
    !   THE THIRD ARGUMENT IS pClip, NOT A CASE FLAG, and false is load-bearing: it measures the
    !   alphabet with size() rather than clipLen(). It changes nothing for '<32,9>', whose last
    !   byte is a tab - but write the alphabet '<9,32>' and the default would clip the space
    !   straight out of it, and no plain-space gap would ever pass again. The same argument is
    !   written out at the label-merge site in vitTokenize, which is where this spelling comes
    !   from.
    !   IsAll reads a ZERO-LENGTH pTestString as "not supplied" and answers from the RECEIVER's
    !   own value instead. It cannot be reached with one here: a NULL strBefore is cycled above,
    !   and a non-NULL one was allocated with a size of at least 1. wsST is a vehicle for the
    !   method and its own value is never consulted.
  end
  tcOk = 1

! ---- the token at gPos starts its line with pure indent (and indSt receives that indent) ----
TsIndentOk routine
  data
iz  long,auto
ic  string(1),auto
  code
  indOk = 0
  indSt.free()
  get(self.tk.tokens, gPos)
  if errorcode() then exit.
  if self.tk.tokens.strBefore &= NULL then exit. ! column 1 = a LABEL position, never a statement we may precede
  if ~size(self.tk.tokens.strBefore) then exit.
  loop iz = 1 to size(self.tk.tokens.strBefore)
    ic = self.tk.tokens.strBefore[iz]
    case val(ic)
    of 32 orof 9
      ! plain indent
    else
      exit                                       ! a comment, a bar, or the CRLF of a continuation
    end
  end
  indSt.setValue(self.tk.tokens.strBefore)
  indOk = 1

! ---- classify ONE occurrence of the receiver at tcPos -> tcKind / tcEnd ----
TsClassify routine
  tcKind = ts:bad
  tcEnd  = tcPos
  gPos = tcPos
  do TsGet
  if ~gOk then exit.
  spIn = gTU
  do TsSplitRoot
  if spSuf then exit.                                             ! recv._DataEnd and every other merged property read - SENSITIVE
  gPos = tcPos + 1
  do TsGet
  if ~gOk or |
     gTxt <> '.' ! foo(st) / st &= other - may alias the buffer
    tcKind = ts:bare ; exit
  end
  gPos = tcPos + 2
  do TsGet
  if ~gOk or |
     gTy <> vt:label
    exit
  end
  mth = gTU
  gPos = tcPos + 3
  do TsGet
  if ~gOk or |
     gTxt <> '(' ! the tokenizer only leaves recv . name unmerged before a '('
    exit
  end
  mpOpen = tcPos + 3
  do TsMatchParen
  if ~mpClose then exit.
  tcEnd = mpClose
  do TsArgs
  kndName = self.TsMethodKind(mth)
  case kndName
  of ts:cleanSet
    do TsCleanSetArgs
  of ts:clipLen
    if agN then exit.                                             ! clipLength(pStr) measures SOMEONE ELSE's string
    tcKind = ts:clipLen
  of ts:read
    do TsNeedleArgs
  of ts:anchor
    do TsAnchorArgs
  end

! ---- clip / trim / removeByte / setValue: is THIS call one that leaves the buffer clean? ----
TsCleanSetArgs routine
  case mth
  of 'CLIP' orof 'TRIM'
    if agN then exit.                                             ! clip(alphabet) / trim(alphabet) - a different method
    tcKind = ts:cleanSet
    exit
  end
  if mth = 'REMOVEBYTE'
    if agN <> 1 or |
       agS <> agE
      exit
    end
    gPos = agS
    do TsGet
    if ~gOk or |
       gTy <> vt:Integer or |
       gTxt <> '32' ! only removing the SPACE byte proves the tail is clean
      exit
    end
    tcKind = ts:cleanSet
    exit
  end
  ! setValue(x, st:clip) - StringTheory clips as it stores, so the buffer lands clean.
  ! A bare setValue(x) stores an arbitrary string and is NOT clean-keep: see DEVIATION 1.
  if agN < 2 or |
     agLS <> agLE
    exit
  end
  gPos = agLS
  do TsGet
  if ~gOk or |
     gTU <> 'ST:CLIP' ! the tokenizer merges a:b into one token, so this is one compare
    exit
  end
  tcKind = ts:cleanSet

! ---- findChar / findChars / findByte / containsChar / containsByte: the needle decides ----
TsNeedleArgs routine
  if agN < 1 or |
     agS <> agE       ! a computed needle - we cannot see what it is
    exit
  end
  case mth
  of 'FINDBYTE' orof 'CONTAINSBYTE'
    gPos = agS
    do TsGet
    if ~gOk or |
       gTy <> vt:Integer or |
       gTxt = '32'    ! byte 32 IS the space
      exit
    end
    tcKind = ts:read
    exit
  end
  do TsLitOk
  if ~ltOk then exit.
  tcKind = ts:read

! ---- getValue(): only an IMMEDIATELY enclosing clip() makes the trailing spaces dead ----
TsAnchorArgs routine
  if agN or |   ! getValue(start,len) is a slice, not the whole value
     tcPos < 3
    exit
  end
  gPos = tcPos - 1
  do TsGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  gPos = tcPos - 2
  do TsGet
  if ~gOk or |
     gTy <> vt:label or |
     gTU <> 'CLIP'
    exit
  end
  gPos = mpClose + 1
  do TsGet
  if ~gOk            or |
     gTxt <> ')' ! clip(recv.getValue() & x) - the clip covers more than the value
    exit
  end
  tcEnd  = mpClose + 1
  tcKind = ts:anchor

! ---- every DEPTH-0 line start of this scope's main code, plus the balance check ----
TsScopeLines routine
  data
lz  long,auto
  code
  free(TsLineQ)
  depth   = 0
  prevEol = 0
  scBad   = 0
  loop lz = codeT + 1 to mainEnd
    if self.IsEolTok(lz)
      prevEol = 1                     ! a physical newline: the NEXT real token starts a line
      cycle
    end
    gPos = lz
    do TsGet
    if ~gOk then scBad = 1 ; break.
    if gNull then cycle.              ! trivia-only tail record - does not start a line either
    if prevEol and ~depth
      do TsIndentOk                   ! gPos is already lz; gTy/gLv are already copied out
      if indOk
        clear(TsLineQ)
        tsl:tslPos = lz
        add(TsLineQ)
      end
    end
    prevEol = 0
    if gLv = '+'
      depth += 1
    elsif gLv = '-' or (gTy = vt:end and gLv <> '+' and gLv <> '/')
      depth -= 1                      ! the inline-dot idiom: an INLINE '.' is retyped vt:end but may carry NO '-'
      if depth < 0 then scBad = 1 ; break.
    end
  end
  if ~scBad and depth then scBad = 1. ! the belt: an unbalanced walk makes "depth 0" a lie

! ---- the simple local StringTheorys of this scope ----
TsCollect routine
  data
cz   long,auto
cNm  string(vs:maxName)
cDcl long,auto
  code
  free(TsRecvQ)
  if self.syms.syms &= NULL then exit.
  ! POSITIONAL sweep - deliberately NOT syms.FindSym. FindSym is a KEYED get, and a keyed
  ! read switches the queue's active order, after which a positional loop reads different
  ! rows than it started with. Everything needed is copied out here, in one pass, first.
  loop cz = 1 to records(self.syms.syms)
    get(self.syms.syms, cz)
    if errorcode() then break.
    if self.syms.syms.scopeId <> sc           or |
       self.syms.syms.typeU <> 'STRINGTHEORY' or |
       self.syms.syms.isRef                   or |   ! `st &= other` re-points it and carries no call to notice
       self.syms.syms.isLike                  or |
       self.syms.syms.isField
      cycle
    end
    cNm  = self.syms.syms.nameU
    cDcl = self.syms.syms.declTok
    if ~self.syms.IsColOneLabel(cDcl) then cycle. ! a PARAMETER is not a column-1 declaration
    if band(self.DeclAttrBits(cDcl), ab:over + ab:dim + ab:static + ab:thread) then cycle.
    clear(TsRecvQ)
    tsv:tsvNameU = cNm
    gPos = cDcl
    do TsGet
    tsv:tsvText = gTxt                            ! SOURCE case, so the inserted line reads like the file
    if ~tsv:tsvText then tsv:tsvText = cNm.
    add(TsRecvQ)
  end

! ---- classify every occurrence of rcU in this scope's main code ----
TsScanUses routine
  data
uz  long,auto
  code
  free(TsUseQ)
  recvBad = 0
  lastBad = 0
  loop uz = codeT + 1 to mainEnd
    gPos = uz
    do TsGet
    if ~gOk then recvBad = 1 ; break.
    if gNull then cycle.
    if gTy = vt:reservedWord and gTU = 'DO'
      lastBad = uz ! a routine can touch any buffer - the region must start below it
      cycle
    end
    if gTy <> vt:label then cycle.
    spIn = gTU
    do TsSplitRoot
    if spRoot <> rcU then cycle.
    tcPos = uz
    do TsClassify
    if tcKind = ts:bare then recvBad = 1 ; break.
    clear(TsUseQ)
    tsu:tsuPos  = uz
    tsu:tsuEnd  = tcEnd
    tsu:tsuKind = tcKind
    add(TsUseQ)
    if tcKind = ts:bad then lastBad = uz.
  end

! ---- is lsPos one of this scope's depth-0 line starts? ----
TsIsLineStart routine
  data
sz  long,auto
  code
  lsOk = 0
  loop sz = 1 to records(TsLineQ)
    get(TsLineQ, sz)
    if errorcode() then break.
    if tsl:tslPos = lsPos then lsOk = 1 ; break.
    if tsl:tslPos > lsPos then break.
  end

! ---- may the use in uPos/uEnd/uKind actually be edited? (trivia only - the classification is done) ----
TsUseEditable routine
  edOk = 0
  if uKind = ts:clipLen
    tcS = uPos
    tcE = uEnd
  elsif uKind = ts:anchor
    if uPos < 3 then exit.
    tcS = uPos - 2
    tcE = uEnd
  else
    exit
  end
  do TsTriviaClean
  if tcOk then edOk = 1.

! ---- may we put a new statement line immediately before pTok? ----
TsInsertOk routine
  insOk = 0
  if pTok < 2 then exit.
  if ~self.IsEolTok(pTok - 1) then exit.                          ! the line above must really END there - never split a continuation
  gPos = pTok
  do TsIndentOk
  if ~indOk then exit.
  insOk = 1

! ---- one receiver: find the region, decide, stage ----
TsReceiver routine
  data
rz  long,auto
  code
  do TsScanUses
  if recvBad or |
     ~records(TsUseQ)
    exit
  end
  ! ---- SPACELESS MODE first. It is strictly more permissive than the region below
  !      (it starts AT the setValue rather than below the last ts:bad use) and it inserts
  !      nothing, so when it validates there is nothing the clean-mode path could add.
  !      When it does not, everything below is exactly as it was.
  do TsSpacelessTry
  if slOk
    cleanFrom = slEnd
    do TsCountBelow
    if ~nAnchor and ~nClip then exit. ! nothing to simplify
    do TsHalfA
    exit
  end
  ! ---- P: the first DEPTH-0 line start below the last use that refuses the region
  pTok = 0
  loop rz = 1 to records(TsLineQ)
    get(TsLineQ, rz)
    if errorcode() then break.
    if tsl:tslPos > lastBad then pTok = tsl:tslPos ; break.
  end
  if ~pTok then exit.
  ! ---- is the receiver ALREADY provably clean at the top of the region?
  alreadyCl = 0
  cleanFrom = pTok - 1
  firstIx   = 0
  loop rz = 1 to records(TsUseQ)
    get(TsUseQ, rz)
    if errorcode() then break.
    if tsu:tsuPos >= pTok then firstIx = rz ; break.
  end
  if firstIx
    get(TsUseQ, firstIx)
    if ~errorcode() and tsu:tsuKind = ts:cleanSet
      uPos  = tsu:tsuPos
      uEnd  = tsu:tsuEnd
      lsPos = uPos
      do TsIsLineStart
      if lsOk and self.IsEolTok(uEnd + 1)
        alreadyCl = 1    ! an UNCONDITIONAL clean-setter, alone on its own depth-0 line
        cleanFrom = uEnd
      end
    end
  end
  ! ---- what is waiting to be simplified below the clean point?
  do TsCountBelow
  if ~nAnchor then exit. ! no anchor: nothing says the trailing spaces are dead
  if ~alreadyCl
    if ~nClip or |   ! an insertion that only retires the anchor clip is a wash
       ~lastBad                   ! nothing above P has touched the buffer - do not clip at the top of a procedure
      exit
    end
    do TsInsertOk
    if ~insOk then exit.
    logLn  = self.LogLineOf(pTok) ! captured BEFORE the edits - log coordinates only, never logic
    nSimp  = nAnchor + nClip
    nxPos  = pTok
    nxPos2 = pTok
    nxKind = 4
    nxTxt  = clip(rcTxt) & '.clip()'
    do TsPush
    inserts += 1
    if inserts + simps = 501
      pLog.append('BUILTIN TrailingSpaces: further detail lines suppressed (500 shown)<13,10>')
    end
    if inserts + simps <= 500
      pLog.append('BUILTIN TrailingSpaces line ' & logLn & ': inserted ' & clip(rcTxt) & '.clip() - ' & nSimp & ' later use(s) simplified<13,10>')
    end
  end
  do TsHalfA

! ---- count what is waiting to be simplified strictly below cleanFrom ----
TsCountBelow routine
  data
cz  long,auto
  code
  nAnchor = 0
  nClip   = 0
  loop cz = 1 to records(TsUseQ)
    get(TsUseQ, cz)
    if errorcode() then break.
    if tsu:tsuPos <= cleanFrom then cycle.
    uPos  = tsu:tsuPos
    uEnd  = tsu:tsuEnd
    uKind = tsu:tsuKind
    do TsUseEditable
    if ~edOk then cycle.
    if uKind = ts:anchor
      nAnchor += 1
    elsif uKind = ts:clipLen
      nClip += 1
    end
  end

! ---- HALF A: every qualifying use below the clean point ----
TsHalfA routine
  data
hz  long,auto
  code
  loop hz = 1 to records(TsUseQ)
    get(TsUseQ, hz)
    if errorcode() then break.
    if tsu:tsuPos <= cleanFrom then cycle.
    uPos  = tsu:tsuPos
    uEnd  = tsu:tsuEnd
    uKind = tsu:tsuKind
    do TsUseEditable
    if ~edOk then cycle.
    if uKind = ts:clipLen
      do TsStageClipLen
    elsif uKind = ts:anchor
      do TsStageAnchor
    end
  end

! ---- is this receiver STORED FROM a call whose summary is sm:spaceless, and does it
!      stay spaceless from there to the end of the scope?  If so every use below that store
!      is provably free of TRAILING spaces too, which is what licenses A1 and A2 without
!      inserting anything - and it is what lifts the MaskSigBase refusal, because a
!      setLength cannot EXPOSE a space in a string that has none. ----
TsSpacelessTry routine
  data
zz  long,auto
  code
  slOk   = 0
  slPos  = 0
  slEnd  = 0
  slIx   = 0
  slName = ''
  loop zz = records(TsUseQ) to 1 by -1       ! the LAST such store wins - everything above it is irrelevant
    get(TsUseQ, zz)
    if errorcode() then cycle.
    uPos   = tsu:tsuPos
    cnSelf = 0                               ! NOTHING is known about the buffer yet, so a self-slice term
    do TsSpaceSetAt                          !      here would be circular - `st.setValue(st.sub(1,5))` proves nothing
    if ~ssOk then cycle.
    lsPos = uPos
    do TsIsLineStart
    if ~lsOk then cycle.                     ! it must be UNCONDITIONAL: a depth-0 line start of its own
    if ~self.IsEolTok(ssEnd + 1) then cycle. ! ... and nothing else may share that line
    slPos  = uPos
    slEnd  = ssEnd
    slName = ssName
    slIx   = zz
    break
  end
  if ~slPos then exit.
  loop zz = slIx + 1 to records(TsUseQ)      ! nothing below it may put a space back
    get(TsUseQ, zz)
    if errorcode() then break.
    uPos = tsu:tsuPos
    do TsSpaceKeepAt
    if ~skOk
      do TsWhySetLen                         ! diag: name the refusal when it is an UNGUARDED setLength
      exit
    end
  end
  loop zz = slEnd + 1 to mainEnd             ! and a routine can do anything to any buffer
    gPos = zz
    do TsGet
    if ~gOk then cycle.
    if gTy = vt:reservedWord and gTU = 'DO' then exit.
  end
  slOk = 1

! ---- recv.setValue(<every top-level '&' term spaceless-yielding>) -> ssOk / ssEnd / ssName.
!      cnSelf must be set by the caller FIRST: 0 on the ESTABLISH walk, 1 on the KEEP walk. ----
TsSpaceSetAt routine
  ssOk   = 0
  ssEnd  = 0
  ssName = ''
  gPos = uPos
  do TsGet
  if ~gOk then exit.
  spIn = gTU
  do TsSplitRoot
  if spSuf then exit.
  gPos = uPos + 1
  do TsGet
  if ~gOk or |
     gTxt <> '.'
    exit
  end
  gPos = uPos + 2
  do TsGet
  if ~gOk or |
     gTU <> 'SETVALUE'
    exit
  end
  gPos = uPos + 3
  do TsGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  mpOpen = uPos + 3
  do TsMatchParen
  if ~mpClose then exit.
  do TsArgs
  if agN <> 1 then exit.                                          ! setValue(x, st:clip) is the clean-setter, not this
  ssEnd = mpClose ! captured BEFORE TsConcatOk, which re-uses mpOpen/mpClose
  do TsConcatOk   ! the argument may be a CONCATENATION
  if ~cnOk
    ssEnd = 0
    exit
  end
  ssName = cnNm
  ssOk   = 1

! ---- the setValue argument [agS..agE] split on TOP-LEVEL '&' - depth 0 only, so an
!      '&' inside a nested call's argument list does NOT split - with EVERY term required to
!      be spaceless-yielding. One term and no '&' is the original case, unchanged. ----
TsConcatOk routine
  data
kz  long,auto
kd  long,auto
ktS long,auto
  code
  cnOk = 0
  cnNm = ''
  ktS  = agS
  kd   = 0
  loop kz = agS to agE
    gPos = kz
    do TsGet
    if ~gOk then exit.
    if gTy = vt:literal then cycle. ! an '&' INSIDE a quoted literal is text, not structure
    if gTxt = '('
      kd += 1
    elsif gTxt = ')'
      kd -= 1
      if kd < 0 then exit.
    elsif ~kd and gTxt = '&'
      tmS = ktS
      tmE = kz - 1
      do TsTermOk
      if ~tmOk then exit.
      ktS = kz + 1
    end
  end
  if kd then exit.                                    ! unbalanced - "depth 0" was a lie
  tmS = ktS
  tmE = agE
  do TsTermOk                                         ! the last term (and the ONLY one when there is no '&')
  if ~tmOk then exit.
  if ~cnNm then cnNm = 'a space-free literal'.        ! nothing named a callee - say so rather than log an empty name
  cnOk = 1

! ---- ONE term of the '&' chain. Three ways to qualify and nothing else; in particular
!      a BARE VARIABLE is refused, because a fixed STRING(n) concatenates WITH its padding and
!      would inject spaces. Confirmed: a Clarion PROCEDURE returning STRING
!      returns exactly its own length, not a padded field, which is what makes 1 and 2 safe. ----
TsTermOk routine
  tmOk = 0
  if tmE < tmS then exit.                             ! `a & & b` - an empty term
  smNm = ''
  smF  = self.SummaryOfCallAt(tmS, tmE, scSelf, smNm) ! 1. a call whose body we summarised as sm:spaceless
  if smF = sm:spaceless
    if ~cnNm then cnNm = smNm.
    tmOk = 1
    exit
  end
  if tmS = tmE                                        ! 3. a quoted literal with no space in it
    gPos = tmS
    do TsGet
    if ~gOk or |
       gTy <> vt:literal ! a BARE VARIABLE lands here and is REFUSED
      exit
    end
    do TsLitSpaceless
    exit
  end
  if ~cnSelf then exit.  ! 2. a SELF-SLICE - admissible ONLY on the KEEP walk, see below
  gPos = tmS
  do TsGet
  if ~gOk then exit.
  spIn = gTU
  do TsSplitRoot
  if spRoot <> rcU or |   ! a DIFFERENT buffer, and we know nothing about it
     spSuf
    exit
  end
  gPos = tmS + 1
  do TsGet
  if ~gOk or |
     gTxt <> '.'
    exit
  end
  gPos = tmS + 2
  do TsGet
  if ~gOk or |
     gTy <> vt:label or |
     gTU <> 'SUB' and gTU <> 'SLICE' and gTU <> 'GETVALUE'
    exit
  end
  gPos = tmS + 3 ! ... a SLICING READER: a substring of a spaceless string has no spaces
  do TsGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  mpOpen = tmS + 3
  do TsMatchParen
  if mpClose <> tmE then exit.                                    ! the term must be EXACTLY the call - `st.sub(1,2) - f()` is not
  tmOk = 1

! ---- gTxt is a quoted literal token - is there a space, a tab or a '<' escape in it?
!      The '<' is refused because <32> IS a space under another name, which is the same call
!      TsLitOk makes about a needle and SkReplOk about a replacement. ----
TsLitSpaceless routine
  data
vz  long,auto
vn  long,auto
vc  string(1),auto
  code
  tmOk = 0
  vn = len(clip(gTxt))
  if vn < 2 then exit. ! not a quoted token at all
  loop vz = 2 to vn - 1
    vc = gTxt[vz]
    case val(vc)
    of 32 orof 9
      exit             ! ONE space in ONE literal poisons the whole result
    of 60
      exit
    end
  end
  tmOk = 1

! ---- can the use at uPos put a space back into the buffer? ----
TsSpaceKeepAt routine
  skOk = self.SpaceKeepUse(uPos)
  if skOk then exit.
  do TsTruncGuard      ! the ONE setLength form this round accepts
  if skOk then exit.
  do TsProvenGuard     ! ... or one an EARLIER PASS accepted, before KnownRanges retired the guard
  if skOk then exit.
  do TsDataEndRead     ! a _DataEnd READ inside an argument EXPRESSION
  if skOk then exit.
  cnSelf = 1           ! HERE the buffer is already known spaceless, so a self-slice term is sound
  do TsSpaceSetAt      ! ... and a setValue of spaceless terms KEEPS it spaceless
  if ssOk then skOk = 1.

! ---- `if E <op> recv._DataEnd then recv.setLength(E).` - the author's own proof that
!      the setLength SHRINKS. It matters because StringTheory.SetLength PADS WITH BYTE 32
!      when it grows (see the DEVIATION on BuildSummaries), so an unguarded setLength can
!      put trailing spaces into a spaceless buffer. One-liner form only: a block IF would
!      need the frame walk, and under-reach is the right answer here. ----
TsTruncGuard routine
  data
tz  long,auto
lf  long,auto
aS  long,auto
aE  long,auto
vz  long,auto ! walks the argument span looking for a call - see the note at the SpanTokEqual test
  code
  skOk = 0
  if uPos < 6 then exit.
  gPos = uPos + 1
  do TsGet
  if ~gOk or |
     gTxt <> '.'
    exit
  end
  gPos = uPos + 2
  do TsGet
  if ~gOk or |
     gTU <> 'SETLENGTH'
    exit
  end
  gPos = uPos + 3
  do TsGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  mpOpen = uPos + 3
  do TsMatchParen
  if ~mpClose then exit.
  aS = mpOpen + 1
  aE = mpClose - 1
  if aE < aS then exit. ! setLength() with no argument is not a shape we model
  gPos = uPos - 1
  do TsGet
  if ~gOk          or |
     gTU <> 'THEN'
    exit
  end
  gPos = uPos - 2
  do TsGet
  if ~gOk then exit.
  spIn = gTU
  do TsSplitRoot
  if spRoot <> rcU or |   ! the bound must be THIS receiver's own length
     spSuf <> '_DATAEND'
    exit
  end
  gPos = uPos - 3
  do TsGet
  if ~gOk          or |
     gTxt <> opLT and gTxt <> opLE
    exit
  end
  lf = 0
  tz = uPos - 4
  loop while tz >= 1
    if self.IsEolTok(tz)
      lf = tz + 1
      break
    end
    tz -= 1
  end
  if ~lf or |
     lf > uPos - 4                                           ! nothing left for the condition
    exit
  end
  gPos = lf
  do TsGet
  if ~gOk then exit.
  if gTy <> vt:reservedWord then exit.
  if gTU <> 'IF' then exit.
  if gLv <> '+' then exit.
  if lf + 1 > uPos - 4 then exit.                            ! empty condition
  if ~self.SpanTokEqual(lf + 1, uPos - 4, aS, aE) then exit. ! the two E spans must be the SAME expression
  ! SAME TEXT IS NOT SAME VALUE. SpanTokEqual proves the two spellings of E match token for
  !   token; it cannot prove they EVALUATE alike, and E is evaluated twice - once in the
  !   condition and once in setLength(). If E carries a call that can answer differently the
  !   second time, the condition tests one length and setLength applies another, and a
  !   setLength that GROWS pads with byte 32 - poisoning the very spaceless region this guard
  !   was read as proving. The author's own guard is already racy in such code, but this pass
  !   BANKS the proof for later rewrites, so it must not adopt one it cannot stand behind.
  !   Any parenthesis in the span refuses. That also turns away pure calls, and deliberately:
  !   a length expression built from a call is rare, purity here would have to be proved rather
  !   than assumed, and this whole pass exists to under-reach rather than guess.
  vz = aS
  loop while vz <= aE
    gPos = vz
    do TsGet
    if gOk and gTxt = '(' then exit.
    vz += 1
  end
  gPos = mpClose + 1
  do TsGet
  if ~gOk or |
     gTy <> vt:end ! the inline terminator - block form is not modelled
    exit
  end
  skOk = 1
  tpAS = aS        ! the author's proof exists RIGHT NOW - bank it
  tpAE = aE
  do TsProvenAdd

! ---- THE PROOF OUTLIVES THE GUARD.
!      TsTruncGuard accepts `recv.setLength(E)` only while the author's own same-line proof
!          if E <  recv._DataEnd then recv.setLength(E).
!      is still there. BUILTIN KnownRanges deletes exactly that IF, because with E carrying
!      rk:posBound the condition provably cannot fail - a correct deletion of genuinely dead
!      code. So the guard is present on pass 1 and gone from pass 2 on, and TrailingSpaces
!      gives a DIFFERENT answer about the same line on different passes. Observed, not
!      supposed: trailerode3.clw (a working fixture, not shipped) -
!          pass 1  BUILTIN KnownRanges line 82: guard on P cannot fail - if/then removed
!          pass 2  BUILTIN TrailingSpaces line 82: pass 2 REFUSED st - unguarded setLength
!      Nothing was lost THERE only because TrailingSpaces reached the region first on pass 1.
!      A region first reachable on pass 2 - because a rule rewrote some other use below the
!      store during pass 1 - is refused on every pass and converts never, silently, since a
!      builtin reports what it DID and not what it declined.
!
!      newbuiltins.txt (a working rule file, NOT SHIPPED) puts TrailingSpaces BEFORE KnownRanges, which holds this
!      together, and it only holds WITHIN one pass. Correctness must not rest on a line order
!      in a file most users will never open - this is an MIT tool for other people's code.
!
!      THE FIX IS TO REMEMBER, NOT TO REORDER. When TsTruncGuard succeeds, bank
!      (scope NAME, receiver, argument text). Later passes accept a bare setLength matching a
!      bank row. The key is the scope's declaration LABEL, never its scopeId: ids are
!      positional, and a scope-removing builtin - UnusedRoutines commenting out a routine -
!      renumbers them at the reparse, so an id banked on one pass can belong to a DIFFERENT
!      procedure on the next. With `st` and `p - 1` for the other two thirds of the key, that
!      is a collision waiting to happen, and its failure mode is the bad direction: a proof
!      nobody made, spaces left in a buffer the region claims is spaceless. KnownRanges is untouched: the guard IS dead and deleting it IS right.
!      DELIBERATELY CONSERVATIVE - the identity is the argument's TOKEN TEXT, so if a rule
!      rewrites E between passes the row stops matching and we simply refuse as before.
!      Under-reach is the correct failure here; a stale proof would put spaces in a buffer
!      the whole region claims is spaceless.
!      Per FILE: TransformFile and TransformText both free self.tsProven before parsing.
TsProvenAdd routine
  do TsArgText ! tpAS..tpAE -> tpArgU
  if ~tpArgU or |
     ~scNameU                                                     ! no name = no stable key. Bank nothing rather than
    exit
  end
                                                                  !   bank under an id that a mid-run reparse can hand to someone else.
  do TsProvenFind
  if tpHit then exit.                                             ! already banked - one row per proof
  self.tsProven.tpNameU = scNameU
  self.tsProven.tpRecvU = rcU
  self.tsProven.tpArgU  = tpArgU
  add(self.tsProven)

! ---- is the use at uPos a bare `recv.setLength(E)` whose E an earlier pass already proved? ----
TsProvenGuard routine
  skOk = 0
  if records(self.tsProven) < 1 then exit.                        ! nothing banked - the common case, so test it first
  gPos = uPos + 1
  do TsGet
  if ~gOk or |
     gTxt <> '.'
    exit
  end
  gPos = uPos + 2
  do TsGet
  if ~gOk or |
     gTU <> 'SETLENGTH'
    exit
  end
  gPos = uPos + 3
  do TsGet
  if ~gOk or |
     gTxt <> '('
    exit
  end
  mpOpen = uPos + 3
  do TsMatchParen
  if ~mpClose then exit.
  tpAS = mpOpen + 1
  tpAE = mpClose - 1
  if tpAE < tpAS then exit.                                       ! setLength() with no argument is not a shape we model
  do TsArgText
  if ~tpArgU then exit.
  do TsProvenFind
  if tpHit
    skOk = 1
    ! A RECEIPT for the one decision here that rests on something not visible in this pass's
    ! text. Everything else TrailingSpaces does can be read off the line in front of it; this
    ! accepts a BARE setLength because an earlier pass saw a guard that KnownRanges has since
    ! deleted, and without a line in the report there is nothing to grep for when asking
    ! whether the bank fired at all. It also names the scope the proof was made in, which is
    ! the whole point of the key: if that name is ever not the procedure you expected,
    ! the bank has handed out somebody else's proof.
    pLog.append('BUILTIN TrailingSpaces line ' & self.LogLineOf(uPos) & |
                ': bare setLength accepted - proved on an earlier pass in ' & clip(scNameU) & '<13,10>')
  end

! ---- tpAS..tpAE joined, upper-cased, single-spaced. Long spans are refused rather than
!      truncated: a truncated key could collide with a DIFFERENT expression and hand out a
!      proof that was never made. ----
TsArgText routine
  data
tz  long,auto
  code
  ! built in a StringTheory, not by `tpArgU = clip(tpArgU) & ...`. That self-append
  ! form re-reads and re-clips the whole accumulator on EVERY term - quadratic - and it is the
  ! shape that silently truncates the moment the buffer is full. append() just writes at the end.
  ! The refusal below stays: an argument too long to hold is one we decline to key on at all,
  ! because a truncated key could collide with a DIFFERENT expression and hand out a proof
  ! nobody made. Under-reach is the safe direction here.
  tpArg._dataEnd = 0
  loop tz = tpAS to tpAE
    gPos = tz
    do TsGet
    if ~gOk or |
       ~gTU
      cycle
    end
    if tpArg._dataEnd then tpArg.append(' ').
    tpArg.append(clip(gTU))
  end
  if tpArg._dataEnd > size(tpArgU)
    tpArgU = ''          ! too long to key safely - refuse the whole proof
  else
    tpArgU = tpArg.getValue()
  end

! ---- scNameU + rcU + tpArgU -> tpHit ----
TsProvenFind routine
  data
tz  long,auto
  code
  tpHit = 0
  if ~scNameU then exit. ! an unnamed scope can neither bank nor claim a proof
  loop tz = 1 to records(self.tsProven)
    get(self.tsProven, tz)
    if errorcode() then break.
    if self.tsProven.tpNameU <> scNameU or |
       self.tsProven.tpRecvU <> rcU     or |
       self.tsProven.tpArgU <> tpArgU
      cycle
    end
    tpHit = 1
    break
  end

! ---- DIAGNOSTIC ONLY - transforms nothing. TsSpaceKeepAt has just refused the use at
!      uPos, which abandons the whole spaceless region below the store. If that use is a
!      `recv.setLength(...)`, SAY SO: the one thing that makes such a use acceptable is the
!      author's own same-line shrink proof (TsTruncGuard), and BUILTIN KnownRanges deletes
!      exactly that guard because it provably cannot fail. Silence here reads identically to
!      "nothing matched" and to "nobody looked" - the lesson.
!      HOW TO READ IT: a refusal that appears at pass 2 or later on a line that did NOT refuse
!      at pass 1 is KnownRanges having taken the evidence between the two passes. The ordering
!      rule in newbuiltins.txt (NOT SHIPPED - TrailingSpaces BEFORE KnownRanges) only holds WITHIN one pass;
!      the fixpoint runs the pair again. Same line refusing on every pass = an ordinary
!      unguarded setLength the author never proved, and correctly refused.
TsWhySetLen routine
  gPos = uPos + 1
  do TsGet
  if ~gOk or |
     gTxt <> '.'
    exit
  end
  gPos = uPos + 2
  do TsGet
  if ~gOk or |
     gTU <> 'SETLENGTH'
    exit
  end
  pLog.append('BUILTIN TrailingSpaces line ' & self.LogLineOf(uPos) & ': pass ' & self.curPass                                            & |
              ' REFUSED ' & clip(rcTxt) & ' - unguarded setLength, and no earlier pass proved it. SetLength GROWS and pads with byte 32,' & |
              ' so the only accepted form is `if E << ' & clip(rcTxt) & '._DataEnd then '                                                 & |
              clip(rcTxt) & '.setLength(E).` - if that guard was there on pass 1, KnownRanges removed it<13,10>')

! ---- a READ of `recv._DataEnd` that SpaceKeepUse refuses on POSITION alone. It refuses
!      every merged _DataEnd whose previous token is '(' or ',' because a bare argument can
!      bind to a *LONG parameter and be WRITTEN, and growing _DataEnd exposes the slack behind
!      it. An argument that is an EXPRESSION cannot: Clarion evaluates it into a temporary and
!      passes that by value. So the read is accepted only when the very NEXT token is a binary
!      operator, which is exactly what makes it an expression. `f(st._DataEnd)` and
!      `f(a, st._DataEnd, b)` stay refused, and every other verdict is left to SpaceKeepUse.
!      This is the call-site walk only - SpaceKeepUse itself is untouched, because it also runs
!      inside the summary pre-pass. Needed by parser.MaskSigBase:
!          st.sub(choose(q < 0, st._DataEnd + q + 1, q), ...)     - ',' before it, '+' after ----
TsDataEndRead routine
  skOk = 0
  if uPos < 2 then exit.
  gPos = uPos
  do TsGet
  if ~gOk then exit.
  spIn = gTU
  do TsSplitRoot
  if spRoot <> rcU or |
     spSuf <> '_DATAEND' ! recv.valuePtr hands out a &STRING that can be written THROUGH
    exit
  end
  gPos = uPos - 1
  do TsGet
  if ~gOk or |
     gTxt <> '(' and gTxt <> ',' ! the ONLY case SpaceKeepUse refuses on position alone
    exit
  end
  gPos = uPos + 1
  do TsGet
  if ~gOk then exit.
  case gTxt
  of '+' orof '-' orof '*' orof '/' orof '^' orof '&'
    skOk = 1                     ! `+=` and every other compound assignment is ONE two-character token
  end

! ---- A1: recv.clipLength() -> recv._DataEnd (ONE token, as the tokenizer would build it) ----
TsStageClipLen routine
  logLn  = self.LogLineOf(uPos)
  nxTxt  = ''
  nxPos  = uPos + 1
  nxPos2 = uEnd
  nxKind = 1
  do TsPush                      ! drop  . clipLength ( )
  nxPos  = uPos
  nxPos2 = uPos
  nxKind = 3
  nxTxt  = clip(rcTxt) & '._DataEnd'
  do TsPush                      ! the receiver token BECOMES the merged property read
  simps += 1
  if inserts + simps = 501
    pLog.append('BUILTIN TrailingSpaces: further detail lines suppressed (500 shown)<13,10>')
  end
  if inserts + simps <= 500
    if slOk                      ! the evidence is in ANOTHER procedure, so the log must name it
      pLog.append('BUILTIN TrailingSpaces line ' & logLn & ': ' & clip(rcTxt) & '.clipLength() is ' & clip(rcTxt) & '._DataEnd here - ' & clip(rcTxt) & ' is spaceless via ' & clip(slName) & '<13,10>')
    else
      pLog.append('BUILTIN TrailingSpaces line ' & logLn & ': ' & clip(rcTxt) & '.clipLength() is ' & clip(rcTxt) & '._DataEnd here - the buffer has no trailing spaces<13,10>')
    end
  end

! ---- A2: clip(recv.getValue()) -> recv.getValue() ----
TsStageAnchor routine
  logLn  = self.LogLineOf(uPos)
  nxTxt  = ''
  nxPos  = uEnd
  nxPos2 = uEnd
  nxKind = 1
  do TsPush ! clip's closing paren
  nxPos  = uPos
  nxPos2 = uPos - 2
  nxKind = 2
  do TsPush ! the receiver inherits clip's leading trivia
  nxPos  = uPos - 2
  nxPos2 = uPos - 1
  nxKind = 1
  do TsPush ! `clip` and its '('
  simps += 1
  if inserts + simps = 501
    pLog.append('BUILTIN TrailingSpaces: further detail lines suppressed (500 shown)<13,10>')
  end
  if inserts + simps <= 500
    if slOk ! name the procedure the fact came from
      pLog.append('BUILTIN TrailingSpaces line ' & logLn & ': clip() around ' & clip(rcTxt) & '.getValue() is redundant - ' & clip(rcTxt) & ' is spaceless via ' & clip(slName) & '<13,10>')
    else
      pLog.append('BUILTIN TrailingSpaces line ' & logLn & ': clip() around ' & clip(rcTxt) & '.getValue() is redundant - removed<13,10>')
    end
  end

! ---- append one staged edit (dataless routine -> no CODE section) ----
TsPush routine
  clear(TsEdQ)
  tse:tsePos  = nxPos
  tse:tsePos2 = nxPos2
  tse:tseKind = nxKind
  tse:tseTxt  = nxTxt
  add(TsEdQ)

! ---- apply the staged edits HIGHEST POSITION FIRST; a delete or an insert shifts everything
!      above it. Ties are broken by KIND ascending so that an INSERT at a position is applied
!      LAST, after any rewrite of the token already at that position. A kind-2 donor is ALWAYS
!      below its target, so by the time the sweep reaches the target the donor has not moved. ----
TsApply routine
  data
az  long,auto
  code
  sort(TsEdQ, -tse:tsePos, +tse:tseKind)
  loop az = 1 to records(TsEdQ)
    get(TsEdQ, az)
    if errorcode() then break.
    case tse:tseKind
    of 1
      self.tk.DeleteToks(tse:tsePos, tse:tsePos2)
    of 2
      get(self.tk.tokens, tse:tsePos2)
      if errorcode() then cycle.
      sbSt.free()
      if not self.tk.tokens.strBefore &= NULL
        sbSt.setValue(self.tk.tokens.strBefore)
      end
      if sbSt._DataEnd
        self.tk.SetStrBefore(tse:tsePos, sbSt.valuePtr[1 : sbSt._DataEnd])
      else
        self.tk.SetStrBefore(tse:tsePos, '')
      end
    of 3
      self.tk.SetTok(tse:tsePos, clip(tse:tseTxt)) ! strBefore OMITTED = keep the existing leading trivia
    of 4
      do TsApplyInsert
    end
  end

! ---- kind 4: put `recv.clip()` on its own line immediately before the token at tsePos ----
TsApplyInsert routine
  data
iz      long,auto
ik      long,auto
ic      string(1),auto
sbLen   long,auto
lnNo    long,auto
nBefore long,auto
nAdded  long,auto
  code
  get(self.tk.tokens, tse:tsePos)
  if errorcode() then exit.
  lnNo = self.tk.tokens.lineNo ! the construct's CURRENT line - stamped onto the new tokens below
  indSt.free()
  if not self.tk.tokens.strBefore &= NULL
    sbLen = size(self.tk.tokens.strBefore)
    ik = sbLen
    loop while ik >= 1         ! trailing whitespace run = the indent (CaptureIndentE's rule)
      ic = self.tk.tokens.strBefore[ik]
      if ic = ' ' or val(ic) = 9
        ik -= 1
      else
        break
      end
    end
    if ik < sbLen then indSt.setValue(sub(self.tk.tokens.strBefore, ik + 1, sbLen - ik)).
  end
  insSt.setValue(tse:tseTxt,st:clip)
  insSt.append('<13,10>')      ! our statement closes its OWN line; the construct keeps its own trivia
  nBefore = records(self.tk.tokens)
  self.tk.InsertString(tse:tsePos, insSt)
  nAdded = records(self.tk.tokens) - nBefore
  if nAdded < 1 then exit.
  if indSt._DataEnd
    self.tk.SetStrBefore(tse:tsePos, indSt.valuePtr[1 : indSt._DataEnd])
  end
  ! THE LINE MAP. InsertString leaves lineNo at zero, and MapFold gives a wholly-inserted
  ! line to its PREDECESSOR when no token on it carries a real line. The decision is
  ! that the SUCCESSOR wins - the construct this clip enables - so stamp its line here.
  loop iz = tse:tsePos to tse:tsePos + nAdded - 1
    get(self.tk.tokens, iz)
    if errorcode() then break.
    self.tk.tokens.lineNo = lnNo
    put(self.tk.tokens)
  end

! ------------------------------------------------------------------------------------
! The ONE place the TrailingSpaces whitelist lives: what a StringTheory method name COULD
! be, on its name alone. The caller (TsClassify) still has to validate the arguments -
! `clip()` is a clean-setter but `clip(alphabet)` is a different method, `clipLength()` is
! a blind read but `clipLength(pStr)` measures someone else's string, and a findChar whose
! needle is a space is not blind at all. Anything absent is ts:bad, which is the safe
! direction: ts:bad only ever shrinks the region the pass may touch.
! Deliberately NOT here, and see the DEVIATION notes on BuiltinTrailingSpaces for why:
!   setLength / setValue-without-st:clip  - blind, but they can CREATE a trailing space;
!   sub / slice / crop                    - "does it reach the end" is a run-time property;
!   append / prepend / len / length / _DataEnd - they observe or relocate the spaces.
! ------------------------------------------------------------------------------------
VitEngine.TsMethodKind Procedure(STRING pMethodU)
  code
  case upper(pMethodU)
  of 'CLIP'       orof 'TRIM'      orof 'REMOVEBYTE'   orof 'SETVALUE'
    return ts:cleanSet
  of 'CLIPLENGTH'
    return ts:clipLen
  of 'GETVALUE'
    return ts:anchor
  of 'FINDCHAR'   orof 'FINDCHARS' orof 'CONTAINSCHAR' orof 'FINDBYTE' orof 'CONTAINSBYTE'
    return ts:read
  end
  return ts:bad

! ====================================================================================
! BUILTIN KeywordCase (OPT-IN, cosmetic) - normalise reserved-word case.
!   BUILTIN KeywordCase, STYLE('lower'|'upper'|'title')   (default lower; bare `, UPPER` etc. also ok)
! Recases every reserved-word token (type='r') to the chosen style: lower `if`, UPPER `IF`,
! or Title `If`.  This is byte-safe by construction - the tokenizer flags a word 'r' ONLY in
! keyword position and NEVER in column 1, so identifiers (even ones spelled like a keyword)
! are type 'b'/label and are left untouched.  Clarion is case-insensitive, so recasing a
! keyword can never change meaning.  In-place SetTok (same length), no reparse needed.
! Scope: reserved words incl. structure keywords (PROCEDURE/CODE/GROUP/QUEUE/CLASS/...), and
! declaration/prototype ATTRIBUTES in attribute position - `,AUTO`, `,OVER`, `,STATIC` and the
! rest of IsClarionAttribute's list, which is why `Flag BYTE,AUTO` recases with everything else.
! An attribute is only safe there because of WHERE it sits: the test is `~col1 and prevComma`,
! so a variable legitimately named `Auto` or `Over` is a label and is never touched.
! SCALAR DATA TYPES are the ones still left alone. They are type 'b' - a var may legitimately be
! named `Date` - so they need declaration context that this pass does not have.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinKeywordCase Procedure(StringTheory pLog)
styleU    string(12),AUTO
nm        string(12),auto
raw       StringTheory
s         long,auto
i         long,auto
n         long,auto
oldTxt    string(vs:maxName),auto
newTxt    string(vs:maxName),auto
col1      byte,auto
isKw      long,auto
nextParen byte,auto
prevComma byte,auto
prevDot   byte,auto ! M2
firstOL   byte,auto ! M2
changes   long
  code
  styleU = 'LOWER'  ! default (matches the common Clarion house style)
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      nm = upper(self.rl.rules.bparmQ.name)
      if nm = 'STYLE' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.unquote('''','''')
        styleU = upper(raw.getValue())
      elsif nm = 'LOWER' or nm = 'UPPER' or nm = 'TITLE' or nm = 'CAMEL' or nm = 'PASCAL'
        styleU = nm ! bare form: BUILTIN KeywordCase, UPPER
      end
    end
  end

  n = records(self.tk.tokens)
  loop i = 1 to n
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL                                    or |
       size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 or |   ! EOL tokens can never recase - skip both peeks
       self.tk.tokens.type = ''''                                                    ! string literals likewise
      cycle
    end
    oldTxt = self.tk.tokens.tok
    col1   = choose(self.tk.tokens.firstOnLine and self.tk.tokens.strBefore &= null) ! a col-1 word can be a label
    firstOL = self.tk.tokens.firstOnLine                                             ! M2: capture now (the peeks below clobber the buffer)
    isKw   = self.tk.TokenIsReservedWord()                                           ! capture NOW: the peeks below clobber the buffer
    prevComma = 0 ; prevDot = 0
    if i > 1
      get(self.tk.tokens, i - 1)
      if ~errorcode() and not self.tk.tokens.tok &= NULL
        if self.tk.tokens.tok = ',' then prevComma = 1.
        if self.tk.tokens.tok = '.' then prevDot = 1.
      end
    end
    nextParen = 0
    get(self.tk.tokens, i + 1)
    if ~errorcode() and not self.tk.tokens.tok &= NULL
      if self.tk.tokens.tok = '(' then nextParen = 1.
    end
    ! Recase four identifier-safe classes.  (1) tokenizer keyword (IF/ELSE/PROCEDURE/END/MAP, col-1
    ! labels excluded).  (2) a SCALAR data type in non-col-1 position -
    ! genuinely reserved, never a label.  (3) a RUNTIME BUILTIN (ROUND/EOF/...) in CALL position
    ! (next '(') that is NOT a user proc - so a field `Status` (no '(') or a user proc `Round` is
    ! untouched.  (4) a declaration/prototype ATTRIBUTE (AUTO/OVER/STATIC/...) in attribute position
    ! (prev token ','); the dual-use attrs TYPE/NAME/C/RAW are excluded (they are real field names).
    if prevDot and ~firstOL then cycle. ! M2: a member/field access (Rec.Time) is an identifier - never recase
    if isKw
      ! keyword - recase
    elsif ~col1 and self.IsScalarType(upper(oldTxt))
      ! scalar type - recase
    elsif ~col1 and nextParen and self.IsRuntimeBuiltin(upper(oldTxt)) and ~self.IsUserProc(upper(oldTxt))
      ! runtime builtin call - recase
    elsif ~col1 and prevComma and self.IsClarionAttribute(upper(oldTxt))
      ! declaration / prototype attribute - recase
    else
      cycle
    end
    newTxt = self.RecaseWord(oldTxt, styleU)
    if newTxt <> oldTxt
      self.tk.SetTok(i, clip(newTxt))   ! same length -> in-place text swap, positions unchanged
      changes += 1
      if changes <= 500
        pLog.append('BUILTIN KeywordCase line ' & self.LogLineOf(i) & ': ' & clip(oldTxt) & ' -> ' & clip(newTxt) & '<13,10>')
      end
    end
  end
  if changes
    ! SetTok re-runs TokenType, which clears the level marks that END/'.' get in a later pass;
    ! reparse rebuilds every type/level from the recased text so block nesting stays intact.
    self.wantReparse = true
    pLog.append('BUILTIN KeywordCase (' & clip(styleU) & '): ' & changes & ' keyword(s) recased this pass<13,10>')
  end
  return changes

! ------------------------------------------------------------------------------------
! Recase one word to pStyleU: UPPER -> all caps, TITLE/CAMEL/PASCAL -> first cap rest lower,
! anything else (incl. LOWER) -> all lower.
! ------------------------------------------------------------------------------------
VitEngine.RecaseWord Procedure(STRING pText, STRING pStyleU)
l  long,auto
  code
  case pStyleU
  of 'UPPER'
    return upper(clip(pText))
  of 'TITLE' orof 'CAMEL' orof 'PASCAL'
    l = len(clip(pText))
    if l < 1 then return clip(pText).
    if l = 1 then return upper(pText).
    return upper(sub(pText, 1, 1)) & lower(sub(pText, 2, l - 1))
  else
    return lower(clip(pText))
  end

! ------------------------------------------------------------------------------------
! 1 = pUpperName is a Clarion SCALAR data type - one that is genuinely reserved and can
! NEVER be a label (so recasing a non-col-1 occurrence is always safe).  Reconciled from
! The tokenizer's `dataTypes` list + the transpiler's parser.IsPrimitiveTypeName, minus:
!   * structure types (WINDOW/FILE/QUEUE/VIEW/KEY/GROUP) - dual-use as method/label names;
!   * INT64/UINT64/BOOL - NOT real Clarion types (StringTheory declares INT64/UINT64 as
!     GROUP labels; the parser comments flag this exact trap).
! ------------------------------------------------------------------------------------
VitEngine.IsScalarType Procedure(STRING pUpperName)
  code
  return choose(instring(' ' & clip(pUpperName) & ' ',                                            |
    ' LONG ULONG SHORT USHORT BYTE SIGNED UNSIGNED REAL SREAL BFLOAT4 BFLOAT8 DECIMAL PDECIMAL' & |
    ' STRING CSTRING PSTRING ASTRING DATE TIME ANY ', 1, 1) > 0)

! ------------------------------------------------------------------------------------
! 1 = pUpperName is a Clarion runtime builtin FUNCTION (Clarion.h free function).  These are
! dual-use with user procedures, so KeywordCase only recases them in CALL position and only
! when IsUserProc is 0.
!
! "functions like clip sub etc are not going to lower-case".  They were
! not in the list.  The original was "harvested verbatim from the transpiler's
! parser.IsRuntimeBuiltinName" - but that list exists over there to mark the calls the EMITTER
! has to treat specially, and CLIP/LEN/SUB are handled by other means in the transpiler, so
! they were never in it.  Copying it wholesale imported a gap, not a policy: the list had
! ISALPHA and DELETEREG but not the half-dozen functions every Clarion program is full of.
!
! WHY THE PARENTHESIS TEST IS ENOUGH, which is what decides how far this list can safely go.
! A DIM'd field subscripted as Size(3) is NOT caught by mistake, and cannot be:
! Clarion subscripts with BRACKETS - Size[3] - as the LRM says twice ("Brackets enclose an
! array subscript list", and "the entire list is enclosed in brackets").
! So a bare name followed by '(' in non-column-1, non-member position IS a call, and with
! IsUserProc excluding the program's own procedures the remaining risk is a name this list
! claims that Clarion does not actually define.  Every name below was checked against
! LanguageReference.md as a real entry before it went in.
! ------------------------------------------------------------------------------------
VitEngine.IsRuntimeBuiltin Procedure(STRING pUpperName)
  code
  return choose(instring(',' & clip(pUpperName) & ',',                 |
    ',ISALPHA,ISUPPER,ISLOWER,ISSTRING,QUOTE,UNQUOTE,PEEK,POKE,'     & |
    'GETINI,PUTINI,GETREG,PUTREG,DELETEREG,COMMIT,ROLLBACK,LOGOUT,'  & |
    'HOLD,RELEASE,WATCH,REGET,RESET,STATUS,COPY,REMOVE,RENAME,'      & |
    'AGE,CHOICE,COMMAND,SETCLOCK,SETNULL,FILEERROR,CHANGES,'         & |
    'ROUND,INT,LOG10,EXISTS,FLUSH,ASSERT,MAXIMUM,'                   & |
    'EOF,BOF,EMPTY,BYTES,PACK,LOCK,UNLOCK,SEND,SQL,'                 & |
    'GETSTATE,RESTORESTATE,FREESTATE,INSTANCE,SHARE,'                & |
    'CLIP,LEN,SUB,UPPER,LOWER,LEFT,RIGHT,CENTER,ALL,'                & | ! string - the set L named
    'FORMAT,DEFORMAT,INSTRING,STRPOS,MATCH,NUMERIC,VAL,CHR,'         & | !   and the rest of that family
    'ABS,RANDOM,SQRT,LOGE,BAND,BOR,BXOR,BSHIFT,INRANGE,'             & | ! numeric
    'TODAY,CLOCK,DATE,TIME,DAY,MONTH,YEAR,'                          & | ! date and time
    'RECORDS,POINTER,POSITION,ADDRESS,SIZE,OMITTED,EVALUATE,'        & | ! these read like field names - see above
    'ERROR,ERRORCODE,ERRORFILE,FILEERRORCODE,INLIST,HOWMANY,WHO,WHAT,', 1, 1) > 0)

! ------------------------------------------------------------------------------------
! 1 = pUpperName is a Clarion declaration/prototype ATTRIBUTE that is safe to recase in
! attribute position (after a ',').  Union of the data-decl attrs ParseDataDecl consumes and
! parser.IsProcAttribute, MINUS the dual-use words (TYPE/NAME/C/RAW/COM) that are legitimately
! used as field/label names in real code - those need tighter context and are left alone.
! ------------------------------------------------------------------------------------
VitEngine.IsClarionAttribute Procedure(STRING pUpperName)
  code
  return choose(instring(',' & clip(pUpperName) & ',',                 |
    ',AUTO,OVER,STATIC,THREAD,EXTERNAL,CONST,DIM,PRE,'               & |
    'VIRTUAL,DERIVED,PRIVATE,PROTECTED,BINDABLE,IMPLEMENTS,PARTIAL,' & |
    'PROC,LATE,PROTO,REPLACE,DLL,PASCAL,CDECL,STDCALL,WINAPI,'       & |
    'NETCLASS,ONCE,LINK,', 1, 1) > 0)

! ------------------------------------------------------------------------------------
! 1 = pNameU (upper) is the name of a user-declared PROCEDURE or METHOD in this file - so a
! builtin-named call that is actually the user's own proc is left alone (parser.ResolveCallName
! gives the user registry priority over the builtin list; we mirror that).  Method scope labels
! are `Class.Method` (one col-1 token) - compare the part after the dot.
! ------------------------------------------------------------------------------------
VitEngine.IsUserProc Procedure(STRING pNameU)
sc   long,auto
lbl  string(vs:maxName),auto
dp   long,auto
  code
  if self.syms &= NULL then return 0.
  loop sc = 1 to records(self.syms.scopes)
    get(self.syms.scopes, sc)
    if errorcode() then break.
    if self.syms.scopes.kind = vs:scProc or self.syms.scopes.kind = vs:scMethod
      lbl = upper(self.tk.GetTok(self.syms.scopes.startTok))
      dp  = instring('.', lbl, 1, 1)
      if dp then lbl = sub(lbl, dp + 1, len(clip(lbl)) - dp).
      if lbl = pNameU then return 1.
    end
  end
  return 0

! ====================================================================================
! BUILTIN SplitStatements (OPT-IN, cosmetic) - one statement per line.
!   BUILTIN SplitStatements
! Splits a line like `a = 1 ; b = 2 ; c = 3` at each top-level ';' so every statement
! lands on its own line at the SAME indent as the original line.  Conservative by design:
!   * bail on any line carrying a level mark (+/-//): IF/LOOP/CASE openers, ELSE/OF, END and
!     block-'.', inline `if..then..` one-liners, compressed `if x; y; end` blocks, and every
!     structure declaration (GROUP/QUEUE/CLASS ... END).  Those are left for ExpandOneLiners
!     / Reindent, which understand nesting.  A pure statement line has no level mark.
!   * only ';' at paren/bracket depth 0 (never inside a call or subscript).
!   * a trailing ';' (next token is EOL) is REMOVED, not split: splitting it would make a blank
!     line, but the statement it separates this one from is empty, so the ';' can simply go.
!     Only when its own trivia is plain spacing - see TrailRemovable. A doubled ';;' is skipped
!     at the first ';'; the split at the second leaves a trailing one, which the next pass
!     removes, so it converges to the right answer without a rule of its own.
!   * a '|' continuation on either side of the ';' is CONVERTED, not refused: once each statement
!     has its own line the continuation has nothing left to continue, so the bar becomes the '!'
!     it already behaves like and the author's words stay on their own physical line (SplitAt).
!   * refuse only trivia holding a newline that is NOT a continuation (absorbed OMIT text): its
!     words are not comment text, so they cannot be re-lined. TriviaClassify says why; the
!     refusal is REPORTED but not counted, and it is per-CANDIDATE.
! What survives is exactly the safe case: sequences of plain statements (or plain scalar decls,
! whose labels stay in column 1).  The split keeps each new line at the original line's indent;
! if Reindent is also enabled it fixes nesting afterwards.  Lossless mechanics: the ';'
! token is retyped to a newline, CARRYING whatever the surrounding trivia said (a continuation's
! words, with the bar swapped for '!'; nothing at all in the ordinary case, where that trivia is
! just the space before the ';'), and the next statement's first token gets the line indent -
! byte-for-byte the same characters, just re-lined, and the same number of physical lines out as
! in.  wantReparse rebuilds firstOnLine / lineNo / levels from the re-lined text.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinSplitStatements Procedure(StringTheory pLog)
n         long,auto
i         long,auto
k         long,auto
lineStart long,auto
depth     long
hasMark   byte
sbLen     long,auto
ch        string(1)
lvl       string(1)
tv        string(4)
indentSt  StringTheory
changes   long
trivSt    StringTheory ! both sides' trivia around the ';', concatenated in source order
pTok      long         ! token the trivia routines read from (pTok and pTok+1)
tx        long,auto
lastNl    long
sawBar    byte
sbBad     byte         ! trivia holds a newline that is NOT a '|' continuation - cannot be re-lined
hasWords  byte
CandQ  QUEUE
pos      long
act      byte          ! 0 = split here, 1 = refused (reported, untouched), 2 = trailing ';' to remove
       END
DelQ   QUEUE           ! trailing ';' positions, applied AFTER the scan (see the loop)
pos      long
       END
  code
  n = records(self.tk.tokens)
  if n < 1 then return 0.
  lineStart = 1
  depth     = 0
  hasMark   = 0
  free(CandQ)
  free(DelQ)
  loop i = 1 to n
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.IsEolTok(i) or i = n
      ! -------- end of the current physical line: flush [lineStart .. this] --------
      if i = n and ~self.IsEolTok(i)
        do ScanTok          ! last token is real - fold it into the line first
      end
      if ~hasMark and records(CandQ)
        do CaptureIndent    ! read the line's leading indent once
        loop k = 1 to records(CandQ)
          get(CandQ, k)
          case CandQ.act
          of 1
            do KeepAt       ! report the refusal - a decision is worth a receipt
          of 2
            do RemoveAt     ! trailing ';' - queued, removed after the scan
          else
            do SplitAt
          end
        end
      end
      lineStart = i + 1     ! next line begins after this EOL
      depth     = 0
      hasMark   = 0
      free(CandQ)
    else
      do ScanTok
    end
  end
  ! Trailing ';' removals happen HERE, after the whole scan, and BACKWARDS. Deleting a token
  ! renumbers every token above it, which would invalidate i, n, lineStart and any candidate
  ! position not yet applied; taking the highest position first means the ones still to go
  ! cannot move. (The same reason VitRewrite applies its matches right-to-left.) Splits above
  ! only retype tokens, so they are unaffected either way.
  if records(DelQ)
    loop k = records(DelQ) to 1 by -1
      get(DelQ, k)
      self.tk.DeleteTok(DelQ.pos)
    end
  end
  if changes
    self.wantReparse = true ! re-line the token stream: rebuild firstOnLine/levels
    pLog.append('BUILTIN SplitStatements: ' & changes & ' statement split(s) this pass<13,10>')
  end
  return changes

! ---- accumulate one non-EOL token into the current line's state (buffer is on token i) ----
ScanTok routine
  data
n2 string(vs:maxName)
  code
  lvl = self.tk.tokens.level
  if lvl = '+' or lvl = '/' or lvl = '-' then hasMark = 1.
  if self.tk.tokens.tok &= NULL then exit.
  tv = self.tk.tokens.tok
  case val(tv)
  of 40 orof 91                   ! '(' orof '['
    depth += 1
  of 41 orof 93                   ! ')' orof ']'
    if depth > 0 then depth -= 1.
  of 59                           ! <semi-colon>
    if ~depth
      ! candidate - but not a trailing ';' (next is EOL) nor a doubled ';;'
      get(self.tk.tokens, i + 1)
      if ~errorcode() and not self.tk.tokens.tok &= NULL
        if self.IsEolTok(i + 1)
          ! TRAILING ';' - it separates this statement from nothing at all. Splitting it would
          ! make a blank line, which is why it was skipped; REMOVING it is exact,
          ! because the empty statement it introduces does nothing. Only when the ';' carries
          ! plain spacing: a bar or a newline in front of it means a continuation is involved,
          ! and dropping the ';' would leave that bar continuing into nothing.
          pTok = i
          do TrailRemovable
          if ~sbBad
            CandQ.pos = i
            CandQ.act = 2
            add(CandQ)
          end
        else
          n2 = self.tk.tokens.tok ! read BEFORE TriviaGather moves the buffer
          if n2 <> ';'
            pTok = i
            do TriviaGather       ! both sides' trivia, in source order
            do TriviaClassify     ! plain continuation, or something we cannot re-line?
            CandQ.pos = i
            CandQ.act = sbBad     ! 0 = split, 1 = refused
            add(CandQ)
          end
        end
      end
      get(self.tk.tokens, i)      ! restore buffer to token i for the caller
    end
  end

! ---- indent = trailing run of spaces/tabs in the line-start token's strBefore ----
!      (using only the trailing run skips any leading full-line comment kept in strBefore).
CaptureIndent routine
  indentSt.free()
  get(self.tk.tokens, lineStart)
  if errorcode() then exit.
  if self.tk.tokens.strBefore &= NULL then exit.
  sbLen = size(self.tk.tokens.strBefore)
  k = sbLen
  loop while k >= 1
    ch = self.tk.tokens.strBefore[k]
    if ch = ' ' or val(ch) = 9
      k -= 1
    else
      break
    end
  end
  if k < sbLen then indentSt.setValue(sub(self.tk.tokens.strBefore, k + 1, sbLen - k)).

! ---- collect the trivia on BOTH sides of the ';' at pTok, in source order ----
!      Continuations are NOT tokens: the '|', whatever the author wrote after it (that text is a
!      comment to end of line) and the CRLF all live in the strBefore of the token that FOLLOWS.
!      SplitAt rewrites both sides - the ';' token's own strBefore and the successor's - so both
!      have to be read together to know what is being re-lined. The ';' glyph itself sits between
!      them and is what becomes the line break, so concatenating the two IS the source order.
TriviaGather routine
  trivSt.free()
  get(self.tk.tokens, pTok)
  if ~errorcode() and not self.tk.tokens.strBefore &= NULL then trivSt.append(self.tk.tokens.strBefore).
  get(self.tk.tokens, pTok + 1)
  if ~errorcode() and not self.tk.tokens.strBefore &= NULL then trivSt.append(self.tk.tokens.strBefore).

! ---- is that trivia a plain '|' continuation, or something that cannot be re-lined? ----
!      Every newline in it must be the end of a continuation segment, i.e. have a '|' in front of
!      it. That is the only shape the tokenizer produces from a continued line, and it is exactly
!      the shape SplitAt can convert. Anything else with a newline in it - absorbed OMIT text is
!      the one that can get there - is left alone and reported, because its words are NOT comment
!      text and moving them would change what the file says. A '!' comment cannot reach here on
!      its own: '!' absorbs to end of line, so it always lands in the EOL token's trivia, and that
!      candidate is already refused as a trailing ';'.  (dataless routine -> no CODE statement)
TriviaClassify routine
  sbBad  = 0
  sawBar = 0
  loop tx = 1 to trivSt._DataEnd
    case val(trivSt.valuePtr[tx])
    of 124 ! '|' - a continuation segment opens
      sawBar = 1
    of 10  ! and this newline closes it
      if ~sawBar
        sbBad = 1
        break
      end
      sawBar = 0
    end
  end

! ---- turn the ';' at CandQ.pos into a line break and re-indent the following statement ----
!      a '|' either side of the ';' is not a reason to refuse - it is a
!      CONTINUATION, and once each statement has its own line there is nothing left for it to
!      continue. Turn it into the comment marker it already behaves like ('|' and '!' both run to
!      end of line) and the author's words survive, on the very physical line they were written
!      on: `p = 1 ; |  note` becomes `p = 1 !  note`, with `q = 2` still below it. Byte-for-byte
!      the same characters, one glyph swapped, and the physical line count is unchanged - only
!      the LAST newline in the trivia is dropped, because the ';' token, now a <10>, supplies it.
SplitAt routine
  pTok = CandQ.pos
  do TriviaGather
  trivSt.replaceByte(124, 33)                              ! '|' -> '!' : the continuation is gone, the words stay
  lastNl = 0
  loop tx = 1 to trivSt._DataEnd
    if val(trivSt.valuePtr[tx]) = 10 then lastNl = tx.
  end
  if lastNl                                                ! drop that last newline and the indent behind it
    trivSt.setLength(lastNl - 1)
    if trivSt._DataEnd and val(trivSt.valuePtr[trivSt._DataEnd]) = 13 then trivSt.setLength(trivSt._DataEnd - 1).
  end
  trivSt.clip('<32,9>')                                    ! no trailing whitespace on the line just ended
  hasWords = 0                                             ! a bare '|' carried no words: emit nothing, not a lone '!'
  loop tx = 1 to trivSt._DataEnd
    case val(trivSt.valuePtr[tx])
    of 32 orof 9 orof 33 orof 13 orof 10                   ! space, tab, '!', CR, LF
    else
      hasWords = 1
      break
    end
  end
  if ~hasWords then trivSt.free().
  self.tk.SetTok(CandQ.pos, '<10>', trivSt.getValue())     ! ';' -> newline, carrying the converted comment ahead of it
  if ~indentSt._DataEnd then indentSt.setValue(' ').       ! never column 1 - see below
  self.tk.SetStrBefore(CandQ.pos + 1, indentSt.getValue()) ! next statement starts at the line's indent
  ! AN EMPTY INDENT WOULD PUT THE SPLIT STATEMENT IN COLUMN 1, WHERE IT IS A LABEL, NOT A STATEMENT.
  !     A statement label is legal on any executable statement and must begin in column 1, so
  !     `Lab  x = 1 ; y = 2` starts its line with the LABEL token, whose strBefore carries no
  !     trailing whitespace at all - CaptureIndent reads an indent of nothing, correctly, because
  !     there is none. Writing `y = 2` at that indent makes `y` a second label and `= 2` something
  !     Clarion cannot parse, so the file stops compiling.
  !     The floor is applied HERE and not inside CaptureIndent because that routine has two early
  !     exits - a failed get, and a NULL strBefore - and both leave the indent empty as well. This
  !     is the one place the value is used, so it is the one place that covers every path to it.
  !     One space is the whole fix. A line that already has an indent cannot reach this arm, so
  !     nothing that was laid out on purpose is touched.
  changes += 1
  if changes <= 500
    pLog.append('BUILTIN SplitStatements line ' & self.LogLineOf(lineStart) & ': split at ";"' & |
                choose(~hasWords, '', ' (continuation kept as a comment)') & '<13,10>')
  end

! ---- may the trailing ';' at pTok simply be dropped? Only if its own trivia is plain ----
!      spacing on the same physical line. A '|' or a newline in front of it means it sits on a
!      continuation line, and removing it would leave the bar continuing into nothing.
!      (dataless routine -> no CODE statement)
TrailRemovable routine
  sbBad = 0
  get(self.tk.tokens, pTok)
  if errorcode()
    sbBad = 1
  elsif not self.tk.tokens.strBefore &= NULL
    if instring('|', self.tk.tokens.strBefore, 1, 1) or |
       instring('<10>', self.tk.tokens.strBefore, 1, 1)
      sbBad = 1
    end
  end

! ---- queue a trailing ';' for removal (the delete itself is after the scan, backwards) ----
!      DeleteTok disposes the token AND its strBefore, which is exactly right here: that
!      strBefore is the space in front of the ';', so `c = 5 ;` comes back as `c = 5` with no
!      trailing space to clean up afterwards. A comment on the line lives in the EOL token's
!      trivia and is untouched, so `c = 5 ; ! note` keeps its note.
RemoveAt routine
  DelQ.pos = CandQ.pos
  add(DelQ)
  changes += 1
  if changes <= 500
    pLog.append('BUILTIN SplitStatements line ' & self.LogLineOf(lineStart)                 & |
                ': trailing ";" removed (it separated the statement from nothing)<13,10>')
  end

! ---- a candidate the trivia classifier refused: left byte-identical, and said out loud ----
KeepAt routine
  pLog.append('BUILTIN SplitStatements line ' & self.LogLineOf(lineStart)                   & |
              ': ";" KEPT - a newline in the trivia here is not a "|" continuation, so its' & |
              ' text cannot be re-lined as a comment<13,10>')

! ====================================================================================
! BUILTIN ExpandOneLiners (OPT-IN, cosmetic) - inline IF -> block form.
!   BUILTIN ExpandOneLiners
! Rewrites a single-line  `if C then S. [else T.]`  - or the ';'-separator form
! `if C; S. [else T.]`, which Clarion accepts as the same statement -
! into the multi-line block form:
!       if C                       if C
!         S           or             S
!       end                        else
!                                    T
!                                  end
! v1 handles ONE flat IF per line only.  Bails (line left byte-identical) on:
!   * multi-statement clauses (a ';' beyond the single THEN-or-';' separator, e.g.
!     `if C then S; T.` or `if C; S; T.`) - NB SplitStatements ALSO bails on an IF
!     line (level mark), so multi-statement one-liners stay one-liners by design;
!   * ELSIF chains / nested IF / any second block (plusCnt<>1, thenCnt+semiCnt<>1, slashCnt>1,
!     or a '/' token that is not ELSE);
!   * a non-'.' terminator or a '.' that is not the final token (requires the block '.');
!   * a comment in the line interior or trailing (a LEADING full-line comment above the IF
!     is fine - it lives in the IF token's strBefore, which the comment check skips).
! Mechanics (NO token nulled - TokenType is not null-safe): `then` (or the separator
! ';') is RETYPED to a newline
! (the same proven move SplitStatements makes on ';'), so the word vanishes and becomes the
! break after `if C`; the `else`/`end` line breaks are a CRLF placed in the following token's
! strBefore; the terminating '.' is retyped to `end`.  Body indent = IF indent + 2 spaces
! (Reindent, if later enabled, normalises).  wantReparse re-lines the token stream.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinExpandOneLiners Procedure(StringTheory pLog)
n          long,auto
i          long,auto
k          long,auto
llStart    long
plusCnt    long
slashCnt   long
thenPos    long
thenCnt    long
elsePos    long
dotPos     long
lastPos    long
lastIsDot  byte
isIfLine   byte
elseIsElse byte
semiCnt    long
semiPos    long
flushEol   long
sbLen      long,auto
ch         string(1)
lvl        string(1)
ifIndentSt StringTheory
sBody      StringTheory
sIfNL      StringTheory
sBodyNL    StringTheory
changes    long
  code
  n = records(self.tk.tokens)
  if n < 1 then return 0.
  llStart = 1
  do ResetLine
  loop i = 1 to n
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.IsEolTok(i) or i = n
      if i = n and ~self.IsEolTok(i)
        do ScanE ! last token is real - fold it in first
      end
      flushEol = i
      do FlushLine
      llStart  = i + 1
      do ResetLine
    else
      do ScanE
    end
  end
  if changes
    self.wantReparse = true
    pLog.append('BUILTIN ExpandOneLiners: ' & changes & ' one-liner(s) expanded this pass<13,10>')
  end
  return changes

! ---- reset per-line accumulators (dataless routine -> no CODE) ----
ResetLine routine
  plusCnt = 0; slashCnt = 0
  thenPos = 0; thenCnt = 0; elsePos = 0; dotPos = 0; lastPos = 0; lastIsDot = 0
  isIfLine = 0; elseIsElse = 0; semiCnt = 0; semiPos = 0

! ---- accumulate one non-EOL token into the line state (buffer is on token i) ----
ScanE routine
  data
uvt string(vs:maxName),AUTO
  code
  ! '+' (block opener) and '/' (else/elsif/of) levels are set by TokenType from the KEYWORD, so
  ! they are reliable even for an inline one-liner.  The '-' (end/'.') level is set by a separate
  ! pass and may not mark an inline '.', so the terminator is detected by VALUE (last token = '.').
  lvl = self.tk.tokens.level
  if lvl = '+' then plusCnt += 1.
  if lvl = '/'
    slashCnt += 1
    elsePos = i
    if not self.tk.tokens.tok &= NULL
      if upper(self.tk.tokens.tok) = 'ELSE' then elseIsElse = 1.
    end
  end
  if self.tk.tokens.tok &= NULL then exit.
  uvt = upper(self.tk.tokens.tok)
  lastPos = i
  lastIsDot = choose(self.tk.tokens.tok = '.') ! updated each token -> reflects the final one at flush
  if i = llStart and uvt = 'IF' and lvl = '+' then isIfLine = 1.
  case uvt
  of 'THEN'
    thenCnt += 1
    thenPos = i
  of ';'
    semiCnt += 1
    semiPos = i
  end

! ---- qualify + transform the current line (dataless routine -> no CODE) ----
FlushLine routine
  if ~isIfLine or |
     plusCnt <> 1 or |   ! exactly one block opener (the IF)
     thenCnt + semiCnt <> 1 ! exactly ONE separator: THEN or the ';' form (both/extra ';' = multi-statement -> bail)
    exit
  end
  if semiCnt = 1 then thenPos = semiPos. ! `if C; S.` - the ';' plays THEN's role
  if slashCnt > 1 or |
     slashCnt = 1 and ~elseIsElse or |
     ~lastIsDot    ! terminator must be a final '.' token
    exit
  end
  dotPos = lastPos ! the terminating '.'
  if thenPos < llStart or dotPos < thenPos then exit. ! sanity
  if self.LineHasComment(llStart + 1, flushEol) then exit. ! interior/trailing comment -> skip (leading is ignored)
  if slashCnt = 1
    if thenPos + 1 >= elsePos or elsePos + 1 >= dotPos then exit. ! empty then/else clause
  else
    if thenPos + 1 >= dotPos then exit. ! empty then clause
  end
  do ExpandLine
  changes += 1
  if changes <= 500
    pLog.append('BUILTIN ExpandOneLiners line ' & self.LogLineOf(llStart) & ': inline IF -> block form<13,10>')
  end

! ---- capture the IF-line indent = trailing whitespace run of the line-start strBefore ----
CaptureIndentE routine
  ifIndentSt.free()
  get(self.tk.tokens, llStart)
  if errorcode() then exit.
  if self.tk.tokens.strBefore &= NULL then exit.
  sbLen = size(self.tk.tokens.strBefore)
  k = sbLen
  loop while k >= 1
    ch = self.tk.tokens.strBefore[k]
    if ch = ' ' or val(ch) = 9
      k -= 1
    else
      break
    end
  end
  if k < sbLen then ifIndentSt.setValue(sub(self.tk.tokens.strBefore, k + 1, sbLen - k)).

! ---- perform the block-form rewrite for the qualified line ----
ExpandLine routine
  do CaptureIndentE
  sBody.setValue(ifIndentSt.getValuePtr())
  sBody.append('  ')                                      ! body indent = if-indent + 2 (spaces only)
  sIfNL.setValue('<13,10>')
  sIfNL.append(ifIndentSt)                                ! newline + if-indent
  sBodyNL.setValue('<13,10>')
  sBodyNL.append(ifIndentSt)
  sBodyNL.append('  ')                                    ! newline + body indent
  self.tk.SetTok(thenPos, '<10>', '')                     ! 'then' -> the line break after `if C`
  self.tk.SetStrBefore(thenPos + 1, sBody.getValue())     ! then-clause first token at body indent
  if slashCnt = 1
    self.tk.SetStrBefore(elsePos, sIfNL.getValue())       ! 'else' onto its own line at if-indent
    self.tk.SetStrBefore(elsePos + 1, sBodyNL.getValue()) ! else-clause first token at body indent
  end
  self.tk.SetTok(dotPos, 'end', sIfNL.getValue())         ! '.' -> `end` on its own line at if-indent

! ====================================================================================
! BUILTIN BlockEndStyle (OPT-IN, cosmetic) - `.` <-> END terminators.
!   BUILTIN BlockEndStyle, STYLE('end'|'period')     (default 'end' = spell terminators out)
!   * STYLE('end')    : '.'  -> the word `end`
!   * STYLE('period') : `END` -> '.'
!
! TWO CASES, AND THEY ARE DECIDED DIFFERENTLY. That difference is the whole design:
!
!  1. WHOLE-LINE - the terminator is the only non-EOL token on its line. Its VALUE settles it:
!     a token alone on a line that reads '.' or END cannot be anything else. No type or level
!     information is consulted. strBefore (indent AND any comment) is preserved as-is.
!     The one exclusion is a COLUMN-1 `End`, which is a jump label (GOTO End), not a terminator.
!
!  2. INLINE - the terminator shares its line with code, as in `if x then y.`. Here the
!     value is NOT enough: `st.getValue()` also contains a lone '.' token. So this case keys on
!     the token TYPE, vt:end, which ParseText's promotion walk sets only for a '.' that is
!     really a terminator - a method dot stays vt:dot because the token after it is a name with
!     no gap in front. Additional conditions, all of them under-reach:
!       * the terminator must be the LAST token on the line;
!       * EXACTLY ONE terminator on the line. A stacked run (`. .`, closing several blocks at
!         once) is REFUSED - see below;
!       * the gap in front of it must be blank. A comment or continuation there is left alone.
!
! WHY STACKED RUNS ARE REFUSED. To expand `. .` into `END END` correctly the
! builtin would have to trust the tokenizer's level marks to know the run really closes two
! blocks. It does not count blocks anywhere else, and a wrong count would not fail loudly - it
! would silently reshape the block structure, which is the worst failure class here: one wrong
! level mark moves every block boundary after it. Identifying
! ONE token as a terminator is a local decision and safe; counting how many blocks a run closes
! is not. Under-reach is the correct direction here.
!
! SPACING. Going '.' -> end INSERTS a space, or `y.` would become `yend`. Going END -> '.'
! removes a single-space gap, so `y END` comes back as `y.` and the pair round trips. The space
! is written with SetStrBefore, which stores anything of non-zero size - a trivia writer that
! tested truthiness instead would read a lone ' ' as blank and drop it.
!
! wantReparse rebuilds levels; the converse spelling never re-fires (an `end` is not a '.').
! Inline expansion of a one-liner into block form is a DIFFERENT builtin, ExpandOneLiners -
! this one only restyles a terminator where it already stands.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinBlockEndStyle Procedure(StringTheory pLog)
styleU     string(12),auto
nm         string(12),auto
raw        StringTheory
s          long,auto
n          long,auto
i          long,auto
llStart    long,AUTO
tokCnt     long
onlyPos    long
onlyValDot byte
onlyIsEnd  byte
endCnt     long ! terminators on this line - inline converts only at 1
lastIsTerm byte ! is the LAST token scanned on the line a terminator
toEnd      byte ! 1 = STYLE(end) '.'->end ; 0 = STYLE(period) END->'.'
styleNm    string(8),auto
changes    long
  code
  toEnd = 1     ! default: spell terminators out as `end`
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      nm = upper(self.rl.rules.bparmQ.name)
      if nm = 'STYLE' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.unquote('''','''')
        styleU = upper(raw.getValue())
        if styleU = 'PERIOD' or styleU = 'DOT' then toEnd = 0.
        if styleU = 'END' then toEnd = 1.
      elsif nm = 'PERIOD' or nm = 'DOT'
        toEnd = 0 ! bare form: BUILTIN BlockEndStyle, PERIOD
      elsif nm = 'END'
        toEnd = 1
      end
    end
  end

  n = records(self.tk.tokens)
  if n < 1 then return 0.
  llStart = 1
  do ResetB
  loop i = 1 to n
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.IsEolTok(i) or i = n
      if i = n and ~self.IsEolTok(i)
        do ScanB
      end
      do FlushB
      llStart = i + 1
      do ResetB
    else
      do ScanB
    end
  end
  if changes
    self.wantReparse = true
    if toEnd then styleNm = 'end' else styleNm = 'period'.
    pLog.append('BUILTIN BlockEndStyle (' & clip(styleNm) & '): ' & changes & ' terminator(s) this pass<13,10>')
  end
  return changes

! ---- reset per-line state (dataless routine -> no CODE) ----
ResetB routine
  tokCnt = 0; onlyPos = 0; onlyValDot = 0; onlyIsEnd = 0; endCnt = 0; lastIsTerm = 0

! ---- accumulate one non-EOL token (buffer is on token i) ----
ScanB routine
  if self.tk.tokens.tok &= NULL then exit.
  tokCnt += 1
  onlyPos = i
  if self.tk.tokens.tok = '.' then onlyValDot = 1 else onlyValDot = 0.
  if upper(self.tk.tokens.tok) = 'END' then onlyIsEnd = 1 else onlyIsEnd = 0.
  ! TYPE, not value - this is the inline test. ParseText's promotion walk types a '.' as
  ! vt:end only when it is really a block terminator; a method dot in `st.getValue()` stays
  ! vt:dot because the token after it is a name with no gap in front. See the banner above.
  if self.tk.tokens.type = vt:end
    endCnt += 1
    lastIsTerm = 1
  else
    lastIsTerm = 0
  end

! ---- convert a whole-line terminator (dataless routine -> no CODE) ----
FlushB routine
  if tokCnt < 1 then exit.
  get(self.tk.tokens, onlyPos)
  if errorcode() then exit.                                  ! could not read it - never convert blind
  if tokCnt > 1
    ! ---- INLINE terminator: it shares its line with code, e.g. `if x then y.` ----
    if endCnt <> 1 or |   ! stacked run - REFUSED, see the banner
       ~lastIsTerm                       ! must be the LAST token on the line
      exit
    end
    if not self.tk.tokens.strBefore &= NULL
      if self.tk.tokens.strBefore then exit. ! a comment or continuation in the gap - leave alone
    end
    if toEnd
      if ~onlyValDot then exit.          ! already a word - nothing to do
      self.tk.SetTok(onlyPos, 'end')
      self.tk.SetStrBefore(onlyPos, ' ') ! `y.` -> `y end`, NEVER `yend`
    else
      if ~onlyIsEnd then exit.           ! already '.' - nothing to do
      self.tk.SetTok(onlyPos, '.')
      self.tk.SetStrBefore(onlyPos, '')  ! `y END` -> `y.` so the pair round trips
    end
    changes += 1
    if changes <= 500
      pLog.append('BUILTIN BlockEndStyle line ' & self.LogLineOf(onlyPos) & ': inline terminator restyled<13,10>')
    end
    exit
  end
  ! ---- WHOLE-LINE terminator: alone on its line, so the VALUE decides ----
  ! A COLUMN-1 'End' is a jump label (GOTO End), not a terminator - firstOnLine with NO
  ! trivia in front of it IS column 1, the same test TokenIsReservedWord uses.
  if self.tk.tokens.firstOnLine and self.tk.tokens.strBefore &= NULL then exit.
  ! A lone token on its own line that is '.' or END is unambiguously a block terminator, so we key
  ! on the VALUE (not the '-' level, which a separate pass sets and we don't want to depend on).
  if toEnd
    if ~onlyValDot then exit.            ! already a word - nothing to do
    self.tk.SetTok(onlyPos, 'end')       ! '.' -> end ; strBefore (indent/comment) preserved
  else
    if ~onlyIsEnd then exit.             ! already '.' - nothing to do
    self.tk.SetTok(onlyPos, '.')         ! END -> '.' ; strBefore preserved
  end
  changes += 1
  if changes <= 500
    pLog.append('BUILTIN BlockEndStyle line ' & self.LogLineOf(onlyPos) & ': terminator restyled<13,10>')
  end

! ====================================================================================
! BUILTIN Reindent (OPT-IN, cosmetic) - normalise block-body indentation.
!   BUILTIN Reindent, WIDTH(2), CASEOF('flush'|'indent')     (default WIDTH 2, CASEOF flush; TABS reserved for v2)
! Recomputes the leading indent of executable block bodies from nesting depth, using the
! tokenizer's reliable level marks: '+' opens (IF/LOOP/CASE/EXECUTE/...), '-' closes (END/'.'),
! '/' continues (ELSE/ELSIF/OF/OROF).  Model = a STACK of open-block indents:
!   * a block BODY line  -> opener-indent + WIDTH;
!   * an END/'.'/ELSE/OF -> aligned back to the opener's indent (flush CASEOF);
!   * WHEN NO BLOCK IS OPEN, a line's indent is LEFT AS-IS - this preserves each procedure's
!     baseline indent for free, so we never model proc/routine/data-section boundaries.
! Safety by construction (heavy under-reach):
!   * ANY column-1 label line is skipped whole (data decls, proc/routine/method headers,
!     GROUP/QUEUE/CLASS/WINDOW/REPORT/FILE structures - all have col-1 labels) - so data
!     sections and structure declarations are never re-indented and their labels stay put;
!   * only the FIRST-on-line token's leading indent is rewritten (its trailing whitespace run),
!     preserving any leading full-line comment in the same strBefore; continuation ('|') lines
!     and comment-only lines live inside other tokens' strBefore and are untouched;
!   * a col-1 proc/routine header also RESETS the stack (defensive against a mis-balanced block
!     leaking across procedures; well-formed code is already balanced so this is a no-op);
!   * a col-1 label line that OPENS a block still pushes a frame for it, marked layout-preserving,
!     so the structure it declares keeps its interior exactly as authored and the matching END
!     pops the right frame.
! CASEOF('flush'|'indent') (default flush): a CASE frame carries an isCase flag; its OF/OROF/ELSE
! lines either align with the CASE (flush) or indent one level under it (indent), and the branch
! bodies follow (opener+WIDTH flush, opener+2*WIDTH indent) via the frame's bodyLen.  IF-block
! ELSE/ELSIF always align with the IF regardless of CASEOF.
! CODECOL(n) (OPT-IN - absent = un-nested lines are left as-is, the safe default): the CODE statement
! sets the executable baseline (baseCol=n) and is moved to column n; every un-nested body line and
! top-level block opener then anchors to baseCol (nesting = baseCol + depth*WIDTH) instead of keeping
! its own indent.  baseActive persists across the proc's ROUTINEs so their bodies share the same
! baseline (routines are appended at body level, not nested), and is CLEARED at the next
! PROCEDURE/FUNCTION header - the baseline belongs to the procedure that declared it, so the next
! proc's data section is left as authored until its own CODE.  This gives an absolute proc-body reflow
! keyed off the one keyword that reliably marks it, with no proc/routine/method/DATA-section modelling.
! The CODE statement is an INDENTED reserved word (type 'r'); a data field named `Code` is a col-1
! label (type 'b') and is not mistaken for it.
! Idempotent (a second run finds 0 changes -> converges).  Indent-only edit (no token/level/
! symbol change), so NO wantReparse.  v2: TABS, absolute proc-baseline reflow.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinReindent Procedure(StringTheory pLog)
width          long
caseIndent     byte                 ! CASEOF: 0 = flush (default), 1 = indent OF/OROF one level under CASE
codeCol        long                 ! CODECOL(n): target column for CODE + the executable baseline
codeColSet     byte                 ! CODECOL was supplied (opt-in; absent = un-nested lines left as-is)
baseCol        long                 ! current executable baseline (set by each CODE line)
baseActive     byte                 ! a CODE has been seen -> anchor un-nested lines to baseCol
lineIsCode     byte                 ! this line is a CODE statement (indented reserved word)
s              long,auto
nmv            string(12),auto
raw            StringTheory
n              long,auto
i              long,auto
m              long,auto
j              long,auto
llStart        long
lvl            string(1)
firstStructLev string(1)
closerAtStart  byte                 ! was that first structural mark the line's FIRST token?
firstType      string(1)
firstFOL       byte
sawStruct      byte
isCol1Label    byte
hasProcKw      byte
hasProcHdr     byte                 ! PROCEDURE/FUNCTION only - a ROUTINE shares the proc's baseline and must NOT clear it
lineIsCase     byte                 ! this line's '+' opener is a CASE
lineIsStruct   byte                 ! M1: this line's '+' opener is a DATA STRUCTURE (WINDOW/GROUP/QUEUE/SHEET/...), not control flow
targetLen      long
topOpn         long                 ! stack top: opener indent
topBody        long                 ! stack top: body indent
tmpLen         long
tmpLeadLen     long
hadTab         byte
c              string(1)
sbCap          StringTheory
sbNew          StringTheory         ! C2: build the reindented strBefore with ST (no fixed 1024 buffer)
changes        long
StackQ QUEUE
opnLen   long                       ! the opener line's own indent (END/ELSE/OF align here)
bodyLen  long                       ! indent for this block's direct body lines (CASE-of adjusts it)
isCase   byte                       ! this frame is a CASE (so ELSE/OF get the CASEOF treatment)
isStruct byte                       ! M1: this frame is a data structure - leave its member/END layout untouched
       END
MarkQ QUEUE
mklev   string(1)
       END
  code
  width = 2                         ! default nesting width
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      nmv = upper(self.rl.rules.bparmQ.name)
      if nmv = 'WIDTH' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.unquote('''','''')
        width = raw.getValue()      ! WIDTH(n) - Clarion string->numeric on assign
      elsif nmv = 'CASEOF' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.unquote('''','''')
        if upper(choose(raw._DataEnd < 1, '', raw.valuePtr[1 : raw._DataEnd])) = 'INDENT' then caseIndent = 1.
        if upper(choose(raw._DataEnd < 1, '', raw.valuePtr[1 : raw._DataEnd])) = 'FLUSH'  then caseIndent = 0.
      elsif nmv = 'CODECOL' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.unquote('''','''')
        codeCol    = raw.getValue() ! CODECOL(n): opt-in absolute baseline anchored on CODE
        codeColSet = 1
      elsif nmv = 'TABS'
        if self.curPass = 1
          pLog.append('BUILTIN Reindent: TABS is a v2 option - v1 always uses spaces<13,10>')
        end
      end
    end
  end
  if width < 0 then width = 0.
  if width > 32 then width = 32.
  if codeCol < 1 then codeCol = 1.  ! CODECOL(0) would re-base lines to column 1 = they become LABELS
  if codeCol > 256 then codeCol = 256.

  n = records(self.tk.tokens)
  if n < 1 then return 0.
  free(StackQ)
  llStart = 1
  do ResetR
  loop i = 1 to n
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.IsEolTok(i) or i = n
      if i = n and ~self.IsEolTok(i)
        do ScanR
      end
      do FlushR
      llStart = i + 1
      do ResetR
    else
      do ScanR
    end
  end
  if changes
    pLog.append('BUILTIN Reindent (width ' & width & '): ' & changes & ' line(s) re-indented this pass<13,10>')
  end
  return changes

! ---- reset per-line accumulators (dataless routine -> no CODE) ----
ResetR routine
  firstStructLev = ' '; firstType = ' '; firstFOL = 0
  sawStruct = 0; closerAtStart = 0; isCol1Label = 0; hasProcKw = 0; hasProcHdr = 0; lineIsCase = 0; lineIsCode = 0; lineIsStruct = 0
  free(MarkQ)

! ---- accumulate one non-EOL token into the line state (buffer is on token i) ----
ScanR routine
  data
uw string(vs:maxName),AUTO
  code
  if i = llStart
    firstFOL  = self.tk.tokens.firstOnLine
    firstType = self.tk.tokens.type
  end
  lvl = self.tk.tokens.level
  case val(lvl)
  of 43 orof 45 orof 47                                                           ! '+' orof '-' orof '/'
    if ~sawStruct
      firstStructLev = lvl
      closerAtStart  = choose(i = llStart)                                        ! is the line the terminator, or does it merely END with one?
      sawStruct = 1
    end
    case val(lvl)
    of 43 orof 45                                                                 ! '+' orof '-'
      MarkQ.mklev = lvl                                                           ! record openers/closers in order for the stack
      add(MarkQ)
    end
  end
  if not self.tk.tokens.tok &= NULL
    uw = upper(self.tk.tokens.tok)
    if uw = 'PROCEDURE' or uw = 'FUNCTION' or uw = 'ROUTINE' then hasProcKw = 1.
    if uw = 'PROCEDURE' or uw = 'FUNCTION'                   then hasProcHdr = 1. ! ROUTINE deliberately excluded - see the baseActive note in FlushR
    if uw = 'CASE' and lvl = '+' then lineIsCase = 1.                             ! opener is a CASE -> its ELSE/OF get the CASEOF treatment
    if lvl = '+'                                                                  ! M1: classify this opener - control-flow vs data-structure
      case uw
      of 'IF' orof 'CASE' orof 'LOOP' orof 'EXECUTE' orof 'BEGIN' orof 'ACCEPT'
        ! control-flow opener - reindented normally
      else
        lineIsStruct = 1                                                          ! WINDOW/GROUP/QUEUE/RECORD/FILE/VIEW/REPORT/MENU/SHEET/TAB/... - a declaration block
      end
    end

    ! the CODE *statement* is an indented reserved word (a data field named Code is a col-1 label, type 'b')
    if i = llStart and uw = 'CODE' and self.tk.tokens.type = vt:reservedWord then lineIsCode = 1.
  end

! ---- decide + apply the line's indent, then update the block stack (dataless -> no CODE) ----
FlushR routine
  if ~firstFOL then exit.                                                         ! blank line (llStart is an EOL) or non-line-start -> skip
  do ScanIndentR                                                                  ! fills sbCap / tmpLen / tmpLeadLen / hadTab
  ! CODECOL (opt-in): a CODE statement sets the executable baseline and is moved to it.  Everything
  ! below (un-nested lines, top-level block openers) then anchors to baseCol instead of being left as-is.
  ! baseActive persists across the proc's routines (their bodies share the proc-body baseline).
  if lineIsCode and codeColSet
    baseCol    = codeCol
    baseActive = 1
    targetLen  = baseCol
    do SetIndentR                                                                 ! CODE has no level marks -> nothing to push/pop
    exit
  end
  ! A column-1 label line (data decl / proc / routine / structure) is never re-indented - but a
  ! block OPENED on one still has to push its frame, or everything inside it is loose: `MyQ QUEUE`
  ! is how almost every structure is written, and without the frame its members and END fall
  ! through to the un-nested arm below and are re-based to baseCol, destroying the authored
  ! layout the moment CODECOL is on. (An un-pushed opener also leaves the stack unbalanced: the
  ! structure's END then pops whatever block happens to enclose it.)
  ! The frame is always LAYOUT-PRESERVING (isStruct), whatever the opener is, because the
  ! opener's own indent is 0: aligning an END to column 1 would turn it into a LABEL. So a
  ! column-1-labelled control-flow block (a labelled LOOP) keeps its body as authored rather
  ! than being reflowed - the safe answer.
  isCol1Label = 0
  if firstFOL and firstType = vt:label and ~tmpLen then isCol1Label = 1.
  if isCol1Label
    if hasProcKw  then free(StackQ).                                              ! proc/routine boundary -> reset the stack
    if hasProcHdr then baseActive = 0.                                            ! ... and the baseline belongs to the procedure that declared it: a new
                                                                                  !     PROCEDURE has none until its OWN CODE, so its data section is left
                                                                                  !     as authored. A ROUTINE header does NOT clear it - routines are
                                                                                  !     appended at body level and share the proc baseline by design.
                                                                                  !     A MAP/CLASS prototype has the same shape and clears it too; that
                                                                                  !     is harmless - a prototype only ever precedes the CODE that sets a
                                                                                  !     baseline, and clearing it just leaves lines as authored.
    targetLen    = tmpLen                                                         ! 0 - recorded as the frame's opener indent, never applied to this line
    lineIsStruct = 1                                                              ! layout-preserving, per the note above
  elsif records(StackQ) = 0
    if baseActive
      targetLen = baseCol                                                         ! CODECOL: anchor un-nested executable lines to the CODE baseline
      do SetIndentR
    else
      targetLen = tmpLen                                                          ! default: not inside a block -> leave the indent as-is
    end
  else
    get(StackQ, records(StackQ))
    topOpn  = StackQ.opnLen
    topBody = StackQ.bodyLen
    case val(firstStructLev)
    of 45                                                                         ! '-'
      ! A LINE THAT *IS* THE TERMINATOR ALIGNS WITH ITS OPENER. A LINE THAT MERELY ENDS
      ! WITH ONE IS A BODY LINE. Clarion lets a full stop close a block, so `count = 1.` does
      ! two jobs at once: it finishes the statement AND it closes the IF. This arm read the
      ! FIRST structural mark found ANYWHERE on the line, so that line scored as a closer and
      ! the whole statement was dragged out to sit under the `if` - legal, unchanged in meaning,
      ! and not what anyone wrote. The stack still pops either way; only the COLUMN changes.
      if closerAtStart
        targetLen = topOpn                                                        ! the line IS the terminator: END, or a bare '.'
      else
        targetLen = topBody                                                       ! a statement that happens to carry one
      end
    of 47                                                                         ! '/'
      if StackQ.isCase                                                            ! CASE branch: OF/OROF/ELSE
        if caseIndent
          targetLen      = topOpn + width                                         ! OF indented one level under CASE
          StackQ.bodyLen = topOpn + width + width                                 ! its body a further level
        else
          targetLen      = topOpn                                                 ! OF flush with CASE (default)
          StackQ.bodyLen = topOpn + width
        end
        put(StackQ)                                                               ! persist the of-body indent for the following body lines
      else
        targetLen = topOpn                                                        ! IF-block ELSE/ELSIF always aligns with the IF
      end
    else
      targetLen = topBody                                                         ! plain body / nested-opener line
    end
    if StackQ.isStruct                                                            ! M1: inside a data structure - preserve the member/END layout as authored
      targetLen = tmpLen
    else
      do SetIndentR
    end
  end
  ! push each opener at this line's indent; pop on each closer (handles inline one-liners too)
  loop m = 1 to records(MarkQ)
    get(MarkQ, m)
    case MarkQ.mklev
    of '+'
      StackQ.opnLen  = targetLen                                                  ! this opener's own indent
      StackQ.bodyLen = targetLen + width                                          ! its body one level deeper (CASE-of may re-adjust)
      StackQ.isCase  = lineIsCase
      StackQ.isStruct = lineIsStruct
      add(StackQ)
    of '-'
      if records(StackQ) > 0
        get(StackQ, records(StackQ))
        delete(StackQ)
      end
    end
  end

! ---- capture llStart's strBefore + measure its trailing whitespace run (dataless -> no CODE) ----
ScanIndentR routine
  sbCap.free()
  tmpLen = 0; tmpLeadLen = 0; hadTab = 0
  get(self.tk.tokens, llStart)
  if errorcode() then exit.
  if self.tk.tokens.strBefore &= NULL then exit.
  sbCap.setValue(self.tk.tokens.strBefore)
  j = size(self.tk.tokens.strBefore)
  loop while j >= 1
    c = self.tk.tokens.strBefore[j]
    if c = ' '
      tmpLen += 1; j -= 1
    elsif val(c) = 9
      tmpLen += 1; hadTab = 1; j -= 1
    else
      break
    end
  end
  tmpLeadLen = j                                           ! chars before the trailing whitespace run

! ---- rewrite llStart's leading indent to targetLen spaces, preserving the leading part ----
SetIndentR routine
  data
plen long,auto
  code
  if targetLen < 0 then targetLen = 0.
  if targetLen > 256 then targetLen = 256.
  if tmpLen = targetLen and ~hadTab then exit.             ! already correct (all-space, right length)
  plen = tmpLeadLen
  if plen < 0 then plen = 0.
  sbNew.free()                                             ! C2: no fixed buffer - a leading comment of ANY length survives
  if plen > 0 then sbNew.setValue(sbCap.sub(1, plen)).     ! keep the whole leading comment/continuation part
  if targetLen > 0 then sbNew.append(all(' ', targetLen)). ! then the normalised indent
  self.tk.SetStrBefore(llStart, sbNew.getValue())          ! '' when both parts are empty - correct
  changes += 1
  if changes <= 500
    pLog.append('BUILTIN Reindent line ' & self.LogLineOf(llStart) & ': ' & tmpLen & ' -> ' & targetLen & ' space(s)<13,10>')
  end

! ====================================================================================
! BUILTIN AutoCheck - ,AUTO safety by definite-assignment analysis.
! Full design + correctness rationale: AutoCheck-spec.md - which is NOT SHIPPED, so
! everything a reader needs is written out here and at the walk below. Safety invariant:
!   * a wrong ADD injects a read-of-uninitialised-memory bug -> SAFE must be PROVEN.
!   * REMOVE / UNKNOWN errors are harmless: removing ,AUTO just restores zero-init
!     (always correct), and UNKNOWN touches nothing. So the analysis is biased to
!     under-reach: ANY uncertainty -> ac:unknown (no ADD) or ac:unsafe (harmless REMOVE).
! WHAT IT RESTS ON: the tokenizer's per-token `level` marks (+ = if/case/loop open,
!     - = end/'.', / = else/elsif). A tokenizer defect that mis-levels a structure
!     arrives here as a wrong verdict, so the level census is this builtin's early
!     warning as much as the tokenizer's. TestData\autoCheck*.clw is the acceptance gate.
!     It is neither untested nor held back any more: AutoCheck ships UNGROUPED and ON by
!     default, and a self-host run put 153 ,AUTO additions into the engine's OWN
!     sources, which is the sharpest test it has had - one wrong ADD would have left an
!     uninitialised variable inside the tool doing the transforming.
! ====================================================================================
VitEngine.BuiltinAutoCheck Procedure(StringTheory pLog)
doAdd    byte,AUTO
doRem    byte,AUTO
doSafe   byte,auto                                   ! SAFE param = remove-only (opt OUT of ADD)
doWhy    byte                                        ! WHY param = report why each candidate was NOT given ,AUTO
whyN     long                                        ! WHY lines emitted (capped)
whyTxt   string(200)                                 ! the reason for the current symbol
noteSt   StringTheory
raw      StringTheory
s        long,auto
verdict  long,auto
changes  long
ok       byte,auto
scpNm    string(vs:maxName),auto                     ! enclosing proc/method/routine name, for drift-proof audit logs
WorkQ  QUEUE,PRE(wq)
declT    long
act      byte                                        ! 1 = ADD, 2 = REMOVE
nm       string(vs:maxName)
scp      string(vs:maxName)                          ! owning scope name
why      long                                        ! diag: acWhyLine at verdict time
whyT     string(900)                                 ! diag: conviction state + ledger
       END
  code
  if self.syms &= NULL then return 0.
  self.acScopeId = 0                                 ! token stream/symbols may have changed since the last pass

  doSafe = 0
  noteSt.setValue('AutoCheck: read before write - ,AUTO removed')
  if not self.rl.rules.bparmQ &= NULL
    loop s = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, s)
      case upper(self.rl.rules.bparmQ.name)
      of 'SAFE' ; doSafe = 1
      of 'WHY'  ; doWhy = 1                          ! opt-in diagnostic - answer 'why did X NOT get ,AUTO'
      of 'NOTE'
        if not self.rl.rules.bparmQ.value &= NULL
          raw.setValue(self.rl.rules.bparmQ.value)
          raw.unquote('''','''')
          noteSt.setValue(raw)
        end
      end
    end
  end
  ! Only two modes: DEFAULT = ALL transformations (ADD + REMOVE); SAFE = remove-only
  ! (the zero-risk direction - a REMOVE only ever restores zero-init).
  doRem = 1
  doAdd = choose(~(doSafe = 1))

  ! ---- pass 1: classify every eligible local, collect the edits (no token edits yet) ----
  free(WorkQ)
  loop s = 1 to records(self.syms.syms)
    get(self.syms.syms, s)
    if errorcode() then break.
    if ~self.AutoEligible(s)
      if doWhy
        whyTxt = self.acWhyElig                      ! set at every refusal inside AutoEligible
        if whyTxt then do WhyLog.                    ! blank = the row-GET failed, nothing to report
      end
      cycle
    end
    verdict = self.AutoVerdict(s)
    scpNm = ''
    get(self.syms.scopes, self.syms.syms.scopeId)    ! capture the owning scope name for the log
    if ~errorcode()
      get(self.tk.tokens, self.syms.scopes.startTok) ! scope startTok = the proc/method/routine header label = its name
      if ~errorcode() and not self.tk.tokens.tok &= NULL then scpNm = self.tk.tokens.tok.
    end
    if verdict = ac:safe and doAdd
      if ~self.DeclHasAttr(self.syms.syms.declTok, 'AUTO')
        clear(WorkQ) ; wq:declT = self.syms.syms.declTok ; wq:act = 1 ; wq:nm = self.syms.syms.nameU ; wq:scp = scpNm ; add(WorkQ)
      elsif doWhy
        whyTxt = 'it already carries ,AUTO' ; do WhyLog
      end
    elsif verdict = ac:unsafe and doRem
      if self.DeclHasAttr(self.syms.syms.declTok, 'AUTO')
        clear(WorkQ) ; wq:declT = self.syms.syms.declTok ; wq:act = 2 ; wq:nm = self.syms.syms.nameU ; wq:scp = scpNm ; wq:why = self.acWhyLine ; wq:whyT = self.acWhyTxt ; add(WorkQ)
      elsif doWhy
        whyTxt = 'read before it is written (line ' & self.acWhyLine & ') - ,AUTO would be a bug here' ; do WhyLog
      end
    elsif doWhy ! WHY: eligible, walked, but not proven safe
      if verdict = ac:safe
        whyTxt = 'proven safe, but ADD is off (the SAFE parameter)'
      elsif self.acBail
        whyTxt = 'the walk bailed on this scope - GOTO, COMPILE or OMIT present, or no CODE'
      else
        whyTxt = 'the walk could not prove it either way (line ' & self.acWhyLine & ' ' & clip(self.acWhyTxt) & ')'
      end
      do WhyLog
    end
  end
  if ~records(WorkQ) then return 0.

  ! ---- pass 2: apply DESCENDING by declTok so a REMOVE's DeleteToks/insert never
  !      shifts a not-yet-applied lower declTok (ADD is position-stable, but sort anyway) ----
  sort(WorkQ, -wq:declT)
  loop s = 1 to records(WorkQ)
    get(WorkQ, s)
    if wq:act = 1
      ok = self.AddAutoAttr(wq:declT)
    else
      ok = self.RemoveAutoAttr(wq:declT, noteSt)
    end
    if ok
      changes += 1
      if wq:act = 1
        pLog.append('BUILTIN AutoCheck ADD ,AUTO: ' & clip(wq:scp) & '.' & clip(wq:nm) & ' line ' & self.LogLineOf(wq:declT) & '<13,10>') ! proc.var (drift-proof anchor; line# is post-transform)
      else
        pLog.append('BUILTIN AutoCheck REMOVE ,AUTO (read before write): ' & clip(wq:scp) & '.' & clip(wq:nm) |
           & ' line ' & self.LogLineOf(wq:declT) & ' (trigger line ' & wq:why & ' ' & clip(wq:whyT) & ')<13,10>')                         ! proc.var (drift-proof anchor); diag: trigger + state
      end
    end
  end
  if changes
    self.wantReparse = true ! decl attributes changed; re-tokenise + resymbol so later passes see them and merged tokens split
    pLog.append('BUILTIN AutoCheck: ' & changes & ' change(s) this pass<13,10>')
  end
  return changes

! one WHY line for a declaration that did NOT get ,AUTO. Opt-in via
! BUILTIN AutoCheck, WHY - silent otherwise, because this fires for every declaration
! the builtin looks at. The symbol row is re-fetched: an AutoEligible refusal can
! return with the syms buffer parked on a sibling row (the OVER scan).
WhyLog routine
  data
wsc  long,auto
wnm  string(vs:maxName),auto
wscp string(vs:maxName),auto
wdcl long,auto
  code
  whyN += 1
  if whyN = 501
    pLog.append('BUILTIN AutoCheck WHY: further lines suppressed (500 shown)<13,10>')
  end
  if whyN > 500 then exit.
  get(self.syms.syms, s)
  if errorcode() then exit.
  wnm  = self.syms.syms.nameU
  wdcl = self.syms.syms.declTok
  wsc  = self.syms.syms.scopeId
  wscp = ''
  get(self.syms.scopes, wsc)
  if ~errorcode()
    get(self.tk.tokens, self.syms.scopes.startTok) ! scope startTok = the proc/method/routine header label
    if ~errorcode() and not self.tk.tokens.tok &= NULL then wscp = self.tk.tokens.tok.
  end
  pLog.append('BUILTIN AutoCheck WHY no ,AUTO: ' & clip(wscp) & '.' & clip(wnm) & ' line ' & self.LogLineOf(wdcl) & ' - ' & clip(whyTxt) & '<13,10>')

! ------------------------------------------------------------------------------------
! Eligible = a simple scalar LOCAL worth analysing. Anything else -> not our business.
! ------------------------------------------------------------------------------------
VitEngine.AutoEligible Procedure(LONG pSymRow, LONG pPersistOk=0)
sc       long,auto
r        long,auto
declTok  long,auto
attMask  long,auto
nameU    string(vs:maxName),AUTO
  code
  self.acWhyElig = ''                           ! WHY: set at every refusal below
  get(self.syms.syms, pSymRow)
  if errorcode() then return 0.
  if self.syms.syms.isRef  then self.acWhyElig = 'reference (&) declaration - AUTO n/a' ; return 0.
  if self.syms.syms.isLike then self.acWhyElig = 'LIKE declaration - structure/aliased' ; return 0.
  if self.syms.syms.isField then self.acWhyElig = 'structure field - AUTO applies to locals only' ; return 0.
  ! (review-response Bug A): ,AUTO grants uninitialised STACK memory - module-level
  ! data (PROGRAM global / MEMBER module sections, scope kind vs:scModule) is STATIC
  ! storage read/written across procedures, so neither AutoCheck's definite-assignment
  ! walk nor DeadStores' liveness holds there (the walk cannot see the other procs).
  ! AutoEligible is the shared gate, so this one guard covers BOTH builtins. Locals only.
  get(self.syms.scopes, self.syms.syms.scopeId) ! positional: scopeId = row (AddScope appends)
  if errorcode() then self.acWhyElig = 'scope not found' ; return 0.
  if self.syms.scopes.kind = vs:scModule then self.acWhyElig = 'module-scope data - static storage, not a stack local' ; return 0.
  ! The .txa embed rule, STRICT: on a.txa only a scope contained wholly
  ! inside ONE embed is decidable - the template's generated code can read or write
  ! anything in a scope that spans embed points, so neither definite-assignment nor
  ! liveness holds there. AutoEligible is the shared gate, so this one test covers
  ! BOTH AutoCheck and UnusedAssignments; UnusedVars carries its own copy.
  if self.isTxa
    if ~self.ScopeFullyEmbedded(self.syms.scopes.startTok, self.syms.scopes.endTok)
      self.acWhyElig = 'on a .txa its procedure/routine spans embed points - generated code between them is not visible here'
      return 0
    end
  end
  nameU   = self.syms.syms.nameU
  declTok = self.syms.syms.declTok
  if nameU = 'SELF' then self.acWhyElig = 'the synthetic SELF receiver' ; return 0.
  if ~self.syms.IsColOneLabel(declTok) then self.acWhyElig = 'parameter or non-declaration - not a column-1 label' ; return 0.
  ! scalar keyword only (no GROUP/QUEUE/RECORD/FILE/VIEW/WINDOW/CLASS/named-type)
  case upper(self.syms.syms.typeU)
  of   'LONG' orof 'ULONG' orof 'SHORT'   orof 'USHORT'   orof 'BYTE'    orof 'SIGNED'  orof 'UNSIGNED' |
     orof 'REAL' orof 'SREAL' orof 'DECIMAL' orof 'PDECIMAL' orof 'BFLOAT4' orof 'BFLOAT8'              |
     orof 'DATE' orof 'TIME'  orof 'STRING'  orof 'CSTRING'  orof 'PSTRING'
    ! scalar - ok
  else
    self.acWhyElig = 'not a scalar type - it is ' & self.syms.syms.typeU
    return 0
  end
  ! OVER = shared storage; DIM = array; STATIC and THREAD persist across calls, so ',AUTO'
  ! is wrong on all four. ONE decl-line walk (DeclAttrBits) instead of four.
  ! *** PERSISTENT STORAGE IS ONLY WRONG FOR ,AUTO. *** This gate is shared and the two
  ! builtins ask different questions of it. ,AUTO grants uninitialised STACK memory, so
  ! anything with persistent storage is ruled out. "Is this variable ever READ?" does not care
  ! where the storage lives: a procedure-local is visible only inside that procedure, so a scan
  ! of the procedure is a COMPLETE usage test, and a variable nothing reads is unused whether
  ! or not its value survives the return.
  !
  ! THREAD IS INCLUDED WITH STATIC, AND FOR EXACTLY THE SAME REASON. The ruling on STATIC -
  ! "unused static locals can be commented out along with any other unused vars, they have
  ! limited scope so you can safely check if they are used" - extends to THREAD unaltered.
  ! `,STATIC,THREAD` is a common spelling and the argument does not change for it.
  ! THREAD alters WHERE the storage lives (one instance per thread), never WHO CAN SEE THE
  ! NAME, and visibility is the whole basis of the test. UnusedVars already comments an unused
  ! local carrying either attribute - it refuses only EXPORT/EXTERNAL/DLL and .txa embeds - so
  ! refusing them here left the two halves of the cascade disagreeing about one variable.
  !
  ! What does NOT follow, and is deliberately kept: the SCOPE-END dead-store case stays off for
  ! both, because a persistent local's LAST store may be read on the next call. That is
  ! `allowEnd` at the caller, and it always knew about THREAD - it simply could never be
  ! reached for one until now. The caller says which question it is asking.
  attMask = ab:over + ab:dim
  if ~pPersistOk then attMask += ab:static + ab:thread.
  if band(self.DeclAttrBits(declTok), attMask)
    self.acWhyElig = 'declared ' & choose(pPersistOk = 0, 'OVER, DIM, STATIC or THREAD', 'OVER or DIM')
    return 0
  end
  ! THIS IS A BACKSTOP, NOT A CONTINUATION REFUSAL, and the difference is worth stating
  ! because the two are easy to confuse and the second one is not what this arm is doing. A
  ! continuation refusal would be needed if the attribute helpers read ONE PHYSICAL LINE: a
  ! ',OVER(x)' parked past a '|' would be invisible and every continued declaration would have
  ! to be refused outright. DeclLastTok walks to the LOGICAL end of the statement, so they see
  ! the whole thing, and a continued declaration is handled correctly - measured both ways: a
  ! benign continuation earns ',AUTO' after the logical last token, a ',STATIC' past a '|' is
  ! refused on its own merits, and an existing ',AUTO' past a '|' is not doubled.
  ! So on a well-formed declaration this arm does not fire. IT STAYS ANYWAY. What follows
  ! DeclLastTok is an EOL or the end of file on any statement this tool can parse, and if it is
  ! something else then the walk did NOT find the end of the declaration - and the next thing
  ! that happens is AddAutoAttr merging ',AUTO' into text it has misread. Refusing is the
  ! conservative answer on input we have failed to understand. Unreachable on code that compiles
  ! is not the same as harmless: an arm was deleted on exactly that reasoning and had to be put
  ! back when the fixture it guarded went from 1 to 2.
  ! Pinned by autocont-test.txt / TestData\r224auto.clw.
  r = self.DeclLastTok(declTok) + 1
  get(self.tk.tokens, r)
  if ~errorcode()
    if self.tk.tokens.tok &= NULL
      ! trailing strBefore-only token = EOF after the decl - fine
    elsif size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10
      ! genuine EOL - fine
    else
      self.acWhyElig = 'declaration continued with a vertical bar - attributes may hide on line 2'
      return 0
    end
  end
  ! Another local declared OVER(V) aliases V's storage - a read through the alias sees
  ! garbage after an ADD. V's own decl was checked above; the SIBLING decls are HasSiblingOver's
  ! question, and it is asked here and by KnownRanges' KrLocalOk from the one place. It was a
  ! copy in two places for one round, which is how NameRoot and UnusedVars' credit drifted
  ! apart, so it is shared before it can happen again. The scope-bounded walk lives there:
  ! syms is sorted on (+scopeId, +nameU), so a scope's rows are CONTIGUOUS and it walks OUT
  ! from the candidate rather than scanning the file - the biggest corpus file has 3,411
  ! symbols, and BUILTIN AutoCheck is ungrouped, so it runs on every pass of every file.
  if self.HasSiblingOver(pSymRow, nameU) then self.acWhyElig = 'a sibling declaration OVERs this one - shared storage' ; return 0.
  get(self.syms.syms, pSymRow) ! restore the candidate's buffer
  ! routine-touched -> UNKNOWN: a routine can run before the main-code write, in any order
  sc = self.syms.syms.scopeId
  self.AutoScopePrep(sc)       ! the scope's routine list is cached
  loop r = 1 to records(self.acRoutQ)
    get(self.acRoutQ, r)
    if self.NameRefdInRange(nameU, self.acRoutQ.rStart, self.acRoutQ.rEnd) then self.acWhyElig = 'referenced inside a ROUTINE - a routine can run before the main-code write' ; return 0.
  end
  ! a MERGED dotted token rooted at this name anywhere in the scope hides a
  ! read/write from every whole-token scan (the UnusedVars disease). Neither
  ! AutoCheck's definite-assignment walk nor DeadStores' liveness can classify a
  ! hidden ref -> the symbol is simply NOT ELIGIBLE for AUTO/dead-store surgery.
  ! (AutoEligible is the shared gate: this one guard covers BOTH builtins.)
  ! On VALID code this is a no-op while eligibility is scalars-only, since a
  ! spaceless scalar.name never compiles - belt-and-braces for non-compiling input
  ! and pre-wired for any future GROUP-eligibility widening.
  ! keyed lookup in the per-scope roots cache (AutoScopePrep builds it once per
  ! scope; the per-symbol span sweep cost Part A +23% on the big class files).
  clear(self.acDotQ)
  self.acDotQ.rootU = nameU
  get(self.acDotQ, self.acDotQ.rootU)
  if ~errorcode() then self.acWhyElig = 'a merged dotted token is rooted at this name - hidden reference' ; return 0.
  return 1

! ------------------------------------------------------------------------------------
! The definite-assignment walk. Returns ac:safe / ac:unsafe / ac:unknown for the local
! in row pSymRow. SAFE = no path reads it before writing it, and it is written at least
! once (whole-variable, clean). Handles straight-line + IF/ELSIF/ELSE precisely; LOOP,
! CASE, EXECUTE and anything unrecognised bail to UNKNOWN the moment the var is touched
! inside them. AutoCheck-spec.md holds the state machine but is not shipped; the frame
! model is described at the CASE below, which is the part that has to be got right.
! ------------------------------------------------------------------------------------
VitEngine.AutoVerdict Procedure(LONG pSymRow)
sc        long,auto
mainEnd   long,auto
codeT     long,auto
i         long,auto
j         long,auto
nU        string(vs:maxName),AUTO
txt       string(vs:maxName),auto
tU        string(vs:maxName)
ty        string(1),auto
lvl       string(1),auto
fol       byte,auto
prevU     string(vs:maxName),auto
nextU     string(vs:maxName),auto
stmtKw    string(vs:maxName)              ! leading keyword of the current statement (robust block-kind detection)
curAsg    byte,auto                       ! V definitely assigned on the current straight-line path
sawWrite  byte,auto
lastWLn   long                            ! diag: line of the last write-credit for this symbol
lastPopLn long                            ! diag: line of the most recent frame POP
lastPopTx string(12)                      ! diag: token text that caused it
contLn    byte,auto                       ! current reference token starts a '|' continuation line
selfRead  byte,auto                       ! audit: RHS self-reference scan verdict for one name hit
ctlOurs   byte                            ! this LOOP's control variable IS the symbol being walked
lcJ       long,auto                       ! scan of the rest of a LOOP header
lcSeen    byte                            ! the counter is READ in its own header
danger    long,auto                       ! open CASE / EXECUTE / unrecognised frames (NOT LOOP); touch here while unassigned -> UNKNOWN
FrameQ QUEUE,PRE(fr)
kind     byte                             ! 1=IF, 2=LOOP, 3=bail-context
entryAsg byte
allBr    byte
hasElse  byte
dng      byte                             ! this frame incremented `danger`
       END
  code
  get(self.syms.syms, pSymRow)
  if errorcode() then return ac:unknown.
  nU = self.syms.syms.nameU
  sc = self.syms.syms.scopeId
  ! main-code bounds, CODE token, and the GOTO / COMPILE-OMIT pre-scan are
  ! per-SCOPE facts - AutoScopePrep computes them once per scope instead of once per symbol.
  self.AutoScopePrep(sc)
  if self.acBail then return ac:unknown.  ! missing scope / no CODE / GOTO / COMPILE / OMIT present
  codeT   = self.acCodeT
  mainEnd = self.acMainEnd

  free(FrameQ)
  curAsg = 0 ; sawWrite = 0 ; danger = 0
  self.acWhyLine = 0 ; self.acWhyTxt = '' ! diag
  loop i = codeT + 1 to mainEnd           ! start AFTER the CODE token
    get(self.tk.tokens, i)
    if errorcode() then break.
    lvl = self.tk.tokens.level
    fol = self.tk.tokens.firstOnLine
    ty  = self.tk.tokens.type
    if self.tk.tokens.tok &= NULL
      txt = ''
    else
      txt = self.tk.tokens.tok
    end
    tU = upper(txt)
    if fol and txt then stmtKw = tU. ! leading keyword of the line.  IF/LOOP/CASE/ELSE/END are RESERVED words (type 'r'=vt:reservedWord), NOT 'b'=vt:label - a gate on ty='b' does not capture them, so every IF falls through `case stmtKw` to the else/bail arm (kind3, danger++) and any var touched in/around an IF returns ac:unknown.  Capture the first token of ANY line (a block opener is always first-on-line; on a plain statement line stmtKw is set but never consulted).

    ! ---------- block structure via level marks ----------
    if lvl = '+'                                                                                       ! block opener (if/case/loop/execute/...)
      clear(FrameQ)
      fr:entryAsg = curAsg ; fr:allBr = 1 ; fr:hasElse = 0 ; fr:dng = 0
      case stmtKw                                                                                      ! classify by the statement keyword, not the +-marked token
      of 'IF'
        fr:kind = 1
      of 'LOOP'
        fr:kind = 2
        ! CREDIT THE LOOP COUNTER HERE, before the entered-unassigned test. The counted
        ! LOOP form assigns its control variable ON ENTRY - the counter is set to the
        ! start value before the first limit test, so it is written even when the body
        ! runs zero times, and it survives the loop holding limit+step. Without this
        ! credit the counter's own LOOP raises `danger`, the very next token - the
        ! counter itself - returns ac:unknown, and the commonest local in Clarion, the
        ! loop index, can never be ,AUTO.
        ! The credit needs the cursor ON the LOOP token, so it is gated on the OPENER
        ! TOKEN's own text, not on stmtKw: stmtKw is the LINE-leading keyword, and on a
        ! compressed line (`loop x = 1 to n ; if v = 1 then break..`) the '+' opener
        ! being classified here can be the mid-line IF while stmtKw still says LOOP.
        ! Ungated, LoopCtlChk then read `v` `=` after that IF as a counter write -
        ! crediting a READ as a definite write, the inversion that licenses a wrong
        ! ADD (,AUTO over a zero-init the comparison relied on). The symmetric miss
        ! (`if c then loop x = 1 to n.` - a LOOP opener on an IF-led line gets no
        ! credit) is under-reach in the safe direction. AutoR43m pins both halves.
        if tU = 'LOOP'
          do LoopCtlChk
          if ctlOurs
            sawWrite = 1 ; curAsg = 1 ; lastWLn = self.LineOfTok(i)
            fr:entryAsg = 1                                                                            ! and still assigned after the frame pops
          end
        end
        ! The shape to keep in mind is `loop` / `p = st.findChar(...)` / reads of p below
        ! it: a LOOP frame does NOT raise `danger`. Raising it would mean "V is
        ! unassigned at loop entry, so any touch inside is ambiguous" - which convicts
        ! the commonest shape in Clarion, a variable WRITTEN at the top of a loop body
        ! and read further down the same body. The frame model already handles the real
        ! risk without it: a loop body is straight-line code, so a write credits curAsg
        ! for the reads below it, a read ABOVE the write is still convicted on the first
        ! iteration, and the kind-2 pop restores curAsg = fr:entryAsg - so relying on a
        ! loop-body write AFTER the loop is convicted exactly as before (the loop may run
        ! zero times). CASE/EXECUTE keep their danger: their branches are alternatives,
        ! not straight-line code, so a write in one branch must never credit the others.
        ! NB this makes the LoopCtlChk credit above LOAD-BEARING: without it the counted
        ! header token `i` in `loop i = 1 to n` would now read as a read-before-write and
        ! REMOVE ,AUTO. The two halves ship together.
      of 'CASE' orof 'EXECUTE' orof 'BEGIN'
        fr:kind = 3 ; fr:dng = 1 ; danger += 1
      else
        fr:kind = 3 ; fr:dng = 1 ; danger += 1                                                         ! unrecognised opener -> bail-context
      end
      add(FrameQ)
      curAsg = fr:entryAsg                                                                             ! first branch body starts at entry state
    elsif lvl = '/'                                                                                    ! else / elsif  (IF branch separator)
      if records(FrameQ)
        get(FrameQ, records(FrameQ))
        if fr:kind = 1
          fr:allBr = choose(fr:allBr = 1 and curAsg = 1)                                               ! fold the just-finished branch
          if tU = 'ELSE' then fr:hasElse = 1 . ! full else (not elsif) - the no-branch path is covered. Use the '/'-token's OWN text: stmtKw is the LINE-leading keyword, still 'IF' on a one-liner, so an INLINE else never set hasElse and the join could not fire (AutoR41a caught it)
          put(FrameQ)
          curAsg = fr:entryAsg                                                                         ! new branch body starts at entry state
        end
      end
    elsif lvl = '-' or (ty = vt:end and lvl <> '+' and lvl <> '/') ! end / '.' - audit: an INLINE '.' terminator is retyped vt:end but may carry NO '-' level (the level pass skips inline dots); without this the one-liner if/then/else frame never closed, blocking the all-branches-wrote join
      lastPopLn = self.tk.tokens.lineNo ; lastPopTx = txt                                              ! diag
      if ~records(FrameQ) then return ac:unknown.                                                      ! level underflow -> don't trust the walk
      get(FrameQ, records(FrameQ))
      if fr:dng then danger -= 1.
      if fr:kind = 1
        fr:allBr = choose(fr:allBr = 1 and curAsg = 1)                                                 ! fold final branch
        if fr:entryAsg = 1 or (fr:hasElse = 1 and fr:allBr = 1)
          curAsg = 1                                                                                   ! every path through the IF assigns V
        else
          curAsg = fr:entryAsg
        end
      else
        curAsg = fr:entryAsg                                                                           ! LOOP may run 0 times; bail-context leaves state as entered
      end
      delete(FrameQ)
    end

    ! ---------- variable reference ----------
    if ty = 'b' and tU = nU
      prevU = '' ; nextU = ''
      if i > codeT
        get(self.tk.tokens, i - 1)
        if not self.tk.tokens.tok &= NULL then prevU = upper(self.tk.tokens.tok).
      end
      if i < mainEnd
        get(self.tk.tokens, i + 1)
        if not self.tk.tokens.tok &= NULL then nextU = upper(self.tk.tokens.tok).
      end
      get(self.tk.tokens, i)                                                                           ! restore buffer to the reference token
      contLn = 0 ! fol=1 is ALSO true on a '|' continuation line (CRLF lives in strBefore) - 'IF a = 1 AND |' / 'V = 2' is a COMPARISON, not a write
      if not self.tk.tokens.strBefore &= NULL
        if self.TriviaHasContinuation(self.tk.tokens.strBefore) then contLn = 1.
      end
      if prevU = '.'                                                                                   ! x.V -> V is a member of x, not our local; ignore
        ! (skip)
      elsif nextU = '.' or nextU = '[' or nextU = '{{'                                                 ! V.field / V[i] / V{prop} -> structure use -> can't classify
        return ac:unknown
      elsif danger > 0 and ~curAsg                                                                     ! touched inside a case / execute / unrecognised block WHILE still unassigned
        ! the bail is about reading storage that may never have been written on
        ! this path - so it only applies while the symbol is NOT yet definitely
        ! assigned. Once curAsg is 1 (assigned before the frame opened, or credited at
        ! a counted LOOP opener inside it), a read here is reading something written,
        ! and the frame pop still restores the entry state afterwards, so a read AFTER
        ! the block is convicted exactly as before. This is what lets an INNER counted
        ! loop's index earn ,AUTO under an outer loop. A WRITE while unassigned still
        ! bails: an EXECUTE/CASE branch write cannot be credited, its branch may not run.
        return ac:unknown
      elsif ((fol = 1 and ~contLn) or prevU = ';' or prevU = 'THEN' or prevU = 'ELSE') and nextU = '=' ! whole-variable assignment target: V = <expr> (also after ;/THEN/ELSE, and not on a continuation line)
        ! self-reference (V = ...V...) as the FIRST touch = read of uninitialised V -> UNSAFE.
        ! Scan the RHS (i+2 .. the true end of statement). Stop on a GENUINE statement
        ! boundary (a <10> EOL token or a ';' separator), NOT firstOnLine - a '|' continuation line
        ! also sets firstOnLine but carries no <10> token (CRLF is in strBefore), so the old
        ! firstOnLine break truncated a continued RHS and missed a self-read on it. This follows
        ! the logical statement to its end (same <10>/; boundary the matcher's TokIsEOL uses).
        if ~curAsg
          j = i + 2
          loop while j <= mainEnd
            get(self.tk.tokens, j)
            if errorcode() then break.
            if self.tk.tokens.tok &= NULL then break.                                                  ! NULL tok = statement boundary
            if self.tk.tokens.tok = '<10>' then break.                                                 ! genuine EOL (a '|' continuation has none)
            if self.tk.tokens.tok = ';' then break.                                                    ! explicit statement separator
            case upper(self.tk.tokens.tok)
            of 'THEN' orof 'ELSE'
              break                                                                                    ! audit: one-line if C then V = x else V = y. - the RHS of the
            end ! then-clause ENDS at ELSE; overrunning read the else-branch WRITE target as a self-read (12 StringPicture false REMOVEs)
            if self.tk.tokens.type = 'b' and upper(self.tk.tokens.tok) = nU
              selfRead = 1                                                                             ! audit: not every name hit is a READ of our local -
              get(self.tk.tokens, j - 1)
              if ~errorcode() and not self.tk.tokens.tok &= NULL
                if self.tk.tokens.tok = '.' then selfRead = 0.                                         ! x.V is a MEMBER (clipLen = self.clipLen(x) false REMOVEs)
              end
              get(self.tk.tokens, j + 1)
              if ~errorcode() and not self.tk.tokens.tok &= NULL
                if self.tk.tokens.tok = '(' then selfRead = 0.                                         ! V( is a CALL name (len = len(x) false REMOVEs)
              end
              if selfRead
                self.acWhyLine = self.LineOfTok(j)                                                     ! diag: the RHS token read as a self-reference
                self.acWhyTxt  = 'SCAN prev=' & clip(prevU) & ' next=' & clip(nextU) & ' fol=' & fol & ' cont=' & contLn & ' dng=' & danger & ' lastW=' & lastWLn & ' frm=' & records(FrameQ)
                return ac:unsafe
              end
            end
            j += 1
          end
        end
        sawWrite = 1 ; curAsg = 1 ; lastWLn = self.LineOfTok(i)                                        ! diag
      elsif self.AutoOutArgWrite(i, prevU)                                                             ! 9b: CLEAR(V..)/GETPOSITION(feq,V..) - a builtin writes V via an output arg
        sawWrite = 1 ; curAsg = 1 ; lastWLn = self.LineOfTok(i)                                        ! diag
      else                                                                                             ! any other occurrence = a READ
        if ~curAsg                                                                                     ! read before write on this path
          self.acWhyLine = self.LineOfTok(i)                                                           ! diag: the read that convicted it
          self.acWhyTxt = 'READ prev=' & clip(prevU) & ' next=' & clip(nextU) & ' fol=' & fol & ' cont=' & contLn |
             & ' dng=' & danger & ' lastW=' & lastWLn & ' frm=' & records(FrameQ) & ' pop=' & lastPopLn & ':' & lastPopTx
          return ac:unsafe
        end
      end
    end
  end

  if records(FrameQ) then return ac:unknown.                                                           ! unbalanced blocks -> don't trust
  if sawWrite then return ac:safe.
  return ac:unknown                                                                                    ! never written (and never read-before-write) -> not our business

! is this LOOP the counted form over the symbol being walked - LOOP <nU> = ... ?
! i is the walk cursor, parked on the LOOP token (the '+' level mark lives on LOOP
! itself - see VitTokenize.SkipWs), so the control variable is the next CONTENT token and its
! '=' the one after. Only that exact shape counts: LOOP alone, LOOP UNTIL/WHILE, and
! LOOP n TIMES assign nothing, and a non-matching name is somebody else's counter.
LoopCtlChk routine
  ctlOurs = 0
  get(self.tk.tokens, i + 1)
  if ~errorcode() and not self.tk.tokens.tok &= NULL
    if self.tk.tokens.type = 'b' and upper(self.tk.tokens.tok) = nU
      get(self.tk.tokens, i + 2)
      if ~errorcode() and not self.tk.tokens.tok &= NULL
        if self.tk.tokens.tok = '=' then ctlOurs = 1.
      end
    end
  end
  ! *** A COUNTER THAT READS ITSELF IN ITS OWN HEADER IS NOT WRITTEN FIRST. ***
  ! `loop v = v + 1 to 3` evaluates the START expression before it assigns v, so v is
  ! READ while still unassigned - and crediting the write here would let it earn ,AUTO
  ! over the zero-init that read depends on, which is a WRONG ADD in the one direction
  ! this routine must never go. `loop u = 1 to u` is the same question about the limit,
  ! and the order there is not something to rely on either way.
  !
  ! So the rest of the header is scanned for the name, and the credit is withdrawn if it
  ! is there. Withdrawing it does not convict anything by itself: it just lets the normal
  ! walk see the token, which is a read of an unassigned variable and is judged as one.
  !
  ! The scan runs to the EOL token or a ';', so a header continued with '|' is covered -
  ! the continuation makes the newline trivia rather than a token. Over-reaching would
  ! only ever REFUSE a credit, which is the safe direction, so the bound is generous.
  if ctlOurs
    lcSeen = 0
    loop lcJ = i + 3 to records(self.tk.tokens)
      get(self.tk.tokens, lcJ)
      if errorcode() then break.
      if self.tk.tokens.tok &= NULL then cycle.
      if size(self.tk.tokens.tok) = 1
        if val(self.tk.tokens.tok) = 10 or |   ! end of the statement
           self.tk.tokens.tok = ';' !   and of a compressed one
          break
        end
      end
      if self.tk.tokens.type = 'b' and upper(self.tk.tokens.tok) = nU
        lcSeen = 1
        break
      end
    end
    if lcSeen then ctlOurs = 0.
  end
  get(self.tk.tokens, i)            ! restore the buffer to the opener token

! ------------------------------------------------------------------------------------
! 9b: does the builtin call surrounding token pTok WRITE it via an output/by-ref
! argument?  Only genuine whole-variable writes are recognised, so this can never create
! a wrong ADD; it removes false REMOVEs (and catches a few more legit ADDs) where a var's
! first touch is such a call.  CLEAR(V ...) writes V (arg 1).  GETPOSITION(feq, x,y,w,h)
! writes args 2-5 (feq, arg 1, is input - reached via prevU='(' so never matched here).
! Extend the allow-list at the CASE below for further output-writing builtins.
! ------------------------------------------------------------------------------------
VitEngine.AutoOutArgWrite Procedure(LONG pTok, STRING pPrevU)
j     long,auto
depth long,auto
  code
  if pPrevU = '('                               ! V is the FIRST arg of the call
    get(self.tk.tokens, pTok - 2)
    if errorcode() then return 0.
    if self.tk.tokens.tok &= NULL then return 0.
    if upper(self.tk.tokens.tok) = 'CLEAR'
      get(self.tk.tokens, pTok - 3)             ! o.Clear(V) is a METHOD - it may READ its argument; only the builtin statement CLEAR writes
      if ~errorcode() and not self.tk.tokens.tok &= NULL
        if self.tk.tokens.tok = '.' then return 0.
      end
      return 1                                  ! CLEAR(V) / CLEAR(V,fill)
    end
    return 0
  end
  if pPrevU = ','                               ! V is at arg position 2+ : walk back to the call name
    depth = 0
    loop j = pTok - 1 to 1 by -1
      get(self.tk.tokens, j)
      if errorcode() then break.
      if self.tk.tokens.tok &= NULL then break. ! statement boundary
      case self.tk.tokens.tok
      of '<10>' orof ';'
        break                                   ! never cross a statement
      of '['    orof ']'
        return 0                                ! a subscript comma (arr[i, V]) is NOT an argument slot - bail
      of ')'
        depth += 1
      of '('
        if ~depth                               ! the enclosing arg-list open paren
          get(self.tk.tokens, j - 1)
          if errorcode() then return 0.
          if self.tk.tokens.tok &= NULL then return 0.
          case upper(self.tk.tokens.tok)
          of   'GETPOSITION'                    ! args 2-5 are OUTPUT (x,y,w,h)
          orof 'PEEK'                           ! audit: PEEK(address, V) writes its 2nd (only other) arg - 4 stMemCpy false REMOVEs
            get(self.tk.tokens, j - 2)          ! o.GetPosition(a,V) is a METHOD, not the builtin
            if ~errorcode() and not self.tk.tokens.tok &= NULL
              if self.tk.tokens.tok = '.' then return 0.
            end
            return 1
          end
          return 0
        end
        depth -= 1
      end
    end
  end
  return 0

! ------------------------------------------------------------------------------------
! A bare-label token (type 'b') equal to pNameU anywhere in [pStart,pEnd], excluding
! member (`.V`) and qualified uses. Used for the routine-touched eligibility test.
! ------------------------------------------------------------------------------------
VitEngine.NameRefdInRange Procedure(STRING pNameU, LONG pStart, LONG pEnd)
i     long,auto
nU    string(vs:maxName),AUTO
prevU string(vs:maxName),auto
  code
  nU = upper(pNameU)
  loop i = pStart to pEnd
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.type <> 'b' or |
       self.tk.tokens.tok &= NULL or |
       upper(self.tk.tokens.tok) <> nU
      cycle
    end
    prevU = ''
    if i > 1
      get(self.tk.tokens, i - 1)
      if not self.tk.tokens.tok &= NULL then prevU = self.tk.tokens.tok.
    end
    if prevU <> '.' then return true.
  end
  return false

! ------------------------------------------------------------------------------------
!===============================================================================================
! Is any of this token range CONDITIONALLY COMPILED?
!
! OMIT and COMPILE take a block of source in or out according to a flag the compiler resolves,
! so code inside one is not necessarily part of THIS build - and nothing here can see the other
! configuration at all. A pass that decides what is written, what is read or what is reachable
! is therefore reasoning from half the program: a store whose only read sits in an omitted block
! looks dead, and a line reached only from a compiled-out branch looks unreachable. Both would
! be commented out on the strength of a build the user did not ask about.
!
! The right answer is to leave the whole scope alone, which is what AutoCheck, DeadGuard and
! KnownRanges already do through acBail. This is the same question asked in one place, for the
! passes that ask it per scope rather than per walk.
!===============================================================================================
!===============================================================================================
! Does this token range hold an OMIT or COMPILE keyword? The four analyses refuse a scope that
! does, because whether such a block is built at all depends on a compile-time switch: a
! declaration read only from inside one would scan as unused and be commented out on the
! strength of a build the caller never asked for.
!
! ***  THIS READS TOKENS, AND THE TOKENIZER ABSORBS SOME OMIT BLOCKS INTO TRIVIA - keyword
! ***  and all. So this can only ever see the blocks that were NOT absorbed, and the two
! ***  boundaries have to coincide EXACTLY. They do, and it is load-bearing:
!
!   absorbed      = the UNCONDITIONAL one-argument OMIT('...') and nothing else. The machine in
!                   vitTokenize.clw fires on a 4-character OMIT token only - so never COMPILE -
!                   and its walk reverts unless the very next tokens are ( 'literal' ). The
!                   two-argument conditional form presents a comma there and reverts.
!                   That code is omitted from EVERY build, so a reference inside it genuinely
!                   does not count, and analysing the scope normally is correct.
!   not absorbed  = everything conditional. The keyword survives as a token, this finds it,
!                   and the scope is refused.
!
! Absorption therefore coincides with UNCONDITIONAL omission, which is what makes "refuse what
! is still visible, analyse what was absorbed" safe. Widen absorption to a conditional form and
! this goes blind without a word: the keyword would be gone, nothing would refuse, and a
! variable used only in the branch that is sometimes built would be silently commented out.
! TestData\uvomit.clw is the pin, and its case is a COMPILE precisely because that is never
! absorbed.
!===============================================================================================
VitEngine.ScopeIsConditional Procedure(LONG pFromTok, LONG pToTok)
i  long,auto
  code
  loop i = pFromTok to pToTok
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    case upper(self.tk.tokens.tok)
    of 'OMIT' orof 'COMPILE'
      return 1
    end
  end
  return 0

!===============================================================================================
! Is there a COMMENT riding the leading trivia of any token in this range?
!
! Trivia is whitespace, continuations and COMMENTS, and a comment there belongs to the author.
! Two places in MergeGuardChain would destroy trivia if they did not ask: MgOrForm overwrites the
! THEN token's, and MgCollapseRuns deletes the condition tokens' along with the tokens. Neither
! produces wrong CODE - a comment is not code - but both could silently drop something a person
! wrote, which is not ours to do. They ask this first and refuse the merge if the answer is yes.
!
! A '!' anywhere in trivia starts a comment: trivia holds no string literals, so there is no
! quoting to reason about. An OMIT/COMPILE body absorbed into trivia can contain one too, and
! that prose is just as much the author's - refusing there is right for the same reason.
!
! REFUSING, not carrying. Carrying the text is the better answer and it is what the per-condition
! comment bank already does for the comments it knows about; this is for the trivia nothing has
! claimed. Refusing costs a merge on a shape that has a comment in an unusual place. Dropping
! the comment costs the comment, and nobody would ever see it go.
!===============================================================================================
VitEngine.SpanTriviaHasComment Procedure(LONG pFromTok, LONG pToTok)
i  long,auto
  code
  loop i = pFromTok to pToTok
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.strBefore &= NULL then cycle.
    if instring('!', self.tk.tokens.strBefore, 1, 1) then return 1.
  end
  return 0

!===============================================================================================
! Does this leading trivia hold a CONTINUATION '|', as opposed to one inside a comment?
!
! `firstOnLine` is true on a continuation line too, so the passes that ask "is this token the
! start of a statement" have to tell the two apart, and the '|' lives in the token's trivia. A
! plain search for it also finds one written inside a FULL-LINE COMMENT sitting in that same
! trivia - and a comment may say anything at all. The token is then taken for a continuation,
! `fol and ~contLn` goes false, and a genuine whole-variable write becomes invisible: the
! variable reads as touched-before-written, which is how an author's own ,AUTO gets removed on
! a claim that is not true.
!
! Everything from a '!' to the end of that line is comment, so a '|' there is text. A '|'
! before any '!' is the real thing - and code after a continuation is ignored by the compiler,
! so `x = 1 | ! note` is a continuation carrying a comment, found correctly by reading left to
! right and stopping at the first unquoted marker.
!
! Only the contLine/contLn sites use this. The places that REFUSE on a '|' - the hoist tail
! test, the strBefore purity test - keep the blunt search on purpose: refusing on a comment's
! '|' is under-reach, which is their safe direction.
!===============================================================================================
VitEngine.TriviaHasContinuation Procedure(STRING pTrivia)
i    long,auto
n    long,auto
inC  byte,auto
  code
  n = size(pTrivia)
  inC = 0
  loop i = 1 to n
    if val(pTrivia[i]) = 10 ! a newline ends the comment, not the trivia
      inC = 0
    elsif pTrivia[i] = '!'
      inC = 1
    elsif pTrivia[i] = '|' and ~inC
      return 1
    end
  end
  return 0

!===============================================================================================
VitEngine.CodeTokOfScope Procedure(LONG pStart, LONG pEnd)
i  long,auto
  code
  loop i = pStart to pEnd
    get(self.tk.tokens, i)
    if errorcode() then break.
    if ~self.tk.tokens.firstOnLine or |
       self.tk.tokens.tok &= NULL
      cycle
    end
    if upper(self.tk.tokens.tok) = 'CODE'
      if self.tk.tokens.strBefore &= NULL then cycle.  ! a COLUMN-1 'code' is a LABEL (a local variable), not the
      return i                                         !   CODE statement - the exclusion BuiltinUnusedVars already applies (#10)
    end
  end
  return 0

!===============================================================================================
! Is any OTHER declaration in this symbol's scope declared OVER it?
!
! OVER is the fifth way one storage location gets two names, and the one a textual test cannot
! see at all: the alias does not resemble the name it aliases. `p LONG` / `sh SHORT,OVER(p)` are
! two labels on the same bytes, so a write through either is a write to both.
!
! VitSymbols sorts syms on (+scopeId, +nameU), so a scope's rows are CONTIGUOUS: walk OUT from
! the candidate and stop at the scope boundary rather than scanning the file. The biggest corpus
! file has 3,411 symbols, and the whole-file form was O(symbols^2) per invocation.
!===============================================================================================
!===============================================================================================
! Could the statement the hoist wants to lift be read through an ALIAS of its own left side?
!
! Gate (3) at TryStartHoist asks whether the CONDITION mentions the lhs by name, and that test is
! textual - SpanHasName compares name roots and consults nothing. OVER is the one aliasing spelling
! a textual test cannot see at all, because the alias does not resemble the name it aliases. With
! `x LONG` and `sh SHORT,OVER(x)`, two branches both starting `x = 1` look safe to hoist above
! `if sh = 2` - and the hoisted store writes the very bytes the condition reads, so the other arm
! runs. No GPF; just the wrong branch, quietly.
!
! THE QUESTION AND THE ANSWER BOTH ALREADY EXISTED HERE - only the wiring was missing.
! HasSiblingOver is asked by AutoCheck and by KnownRanges' KrLocalOk, and its own header records
! that a copy in two places is how NameRoot and UnusedVars' credit drifted apart. It wants a syms
! ROW; the hoist has a token and a name, so this composes the two lookups that bridge them and
! adds no third copy of the rule.
!
! IT REFUSES WHEN IT CANNOT TELL, which is the whole posture of this gate: no scope, no symbol row,
! or no symbol table at all means no proof, and an unproven hoist is one that does not happen.
!===============================================================================================
VitEngine.HoistAliasRisk Procedure(LONG pTokPos, STRING pNameU)
sc    long,auto
syRow long                            ! AUTO unsafe: read before write
  code
  if self.syms &= NULL then return 1. ! no table - cannot tell, so refuse
  if ~pNameU then return 1.
  ! INNERMOST-OUT, the same ladder LookupIn walks: a ROUTINE's DATA is private to that routine,
  !   so a name declared there is the one the statement means. Only when the routine declares
  !   nothing does the surrounding procedure answer.
  sc = self.syms.ScopeContaining(pTokPos, vs:scRoutine, vs:scRoutine)
  if sc then syRow = self.syms.FindSym(pNameU, sc).
  if ~syRow
    sc = self.syms.ScopeContaining(pTokPos, vs:scProc, vs:scMethod)
    if sc then syRow = self.syms.FindSym(pNameU, sc).
  end
  if ~syRow
    ! MODULE LEVEL IS ASKED TOO, and not asking it would have been the expensive mistake here.
    !   A global can be OVERed by another global just as a local can, and a hoist whose lhs is
    !   module-level is common. Stopping at the procedure would have refused every one of those
    !   for want of a lookup rather than for want of proof.
    sc = self.syms.ScopeContaining(pTokPos, vs:scModule, vs:scModule)
    if sc then syRow = self.syms.FindSym(pNameU, sc).
  end
  if ~syRow then return 1.            ! nowhere in the table - no proof, so refuse
  return self.HasSiblingOver(syRow, pNameU)

VitEngine.HasSiblingOver Procedure(LONG pSymRow, STRING pNameU)
r   long,auto
sc  long,auto
res long,auto
  code
  res = 0
  get(self.syms.syms, pSymRow)
  if errorcode() then return 0.
  sc = self.syms.syms.scopeId
  loop r = pSymRow - 1 to 1 by -1
    get(self.syms.syms, r)
    if errorcode() then break.
    if self.syms.syms.scopeId <> sc then break.
    if ~self.DeclHasAttr(self.syms.syms.declTok, 'OVER') then cycle.
    if self.DeclLineMentions(self.syms.syms.declTok, pNameU) then res = 1 ; break.
  end
  if ~res
    loop r = pSymRow + 1 to records(self.syms.syms)
      get(self.syms.syms, r)
      if errorcode() then break.
      if self.syms.syms.scopeId <> sc then break.
      if ~self.DeclHasAttr(self.syms.syms.declTok, 'OVER') then cycle.
      if self.DeclLineMentions(self.syms.syms.declTok, pNameU) then res = 1 ; break.
    end
  end
  get(self.syms.syms, pSymRow) ! restore the caller's buffer
  return res

! ------------------------------------------------------------------------------------
! Does the declaration line carry pAttrU (AUTO/OVER/DIM) as a real bare token?
! (An 'AUTO' inside NAME('..AUTO..') is a quoted literal token, not caught.)
! ------------------------------------------------------------------------------------
VitEngine.DeclHasAttr Procedure(LONG pDeclTok, STRING pAttrU)
i     long,auto
ln    long,auto
aU    string(vs:maxName),AUTO
  code
  aU = upper(pAttrU)
  get(self.tk.tokens, pDeclTok)
  if errorcode() then return 0.
  ln = self.tk.tokens.lineNo
  i = pDeclTok
  loop
    i += 1
    get(self.tk.tokens, i)
    if errorcode() then break.
    ! *** A DECLARATION IS A LOGICAL LINE, NOT A PHYSICAL ONE. *** Breaking at the first
    ! lineNo change stopped the walk at a '|', so everything past the continuation was
    ! invisible: `sh SHORT,|` / `OVER(p)` read as carrying no OVER, and the guard that
    ! depends on seeing it was deleted. Same for a ',DIM(3)' written past a '|'.
     if self.tk.tokens.lineNo <> ln
       if ~self.TriviaHasContinuation(self.tk.tokens.strBefore) then break.
       ln = self.tk.tokens.lineNo ! the declaration carries on here
     end
    if self.tk.tokens.type <> 'b' or |
       self.tk.tokens.tok &= NULL
      cycle
    end
    if upper(self.tk.tokens.tok) = aU then return true.
  end
  return false

! ------------------------------------------------------------------------------------
! Last non-trivia token of the declaration statement (same line as the label).
! ------------------------------------------------------------------------------------
VitEngine.DeclLastTok Procedure(LONG pDeclTok)
i    long,auto
ln   long,auto
last long,auto
  code
  get(self.tk.tokens, pDeclTok)
  if errorcode() then return pDeclTok.
  ln = self.tk.tokens.lineNo
  last = pDeclTok
  i = pDeclTok
  loop
    i += 1
    get(self.tk.tokens, i)
    if errorcode() then break.
    ! *** A DECLARATION IS A LOGICAL LINE, NOT A PHYSICAL ONE. *** Breaking at the first
    ! lineNo change stopped the walk at a '|', so everything past the continuation was
    ! invisible: `sh SHORT,|` / `OVER(p)` read as carrying no OVER, and the guard that
    ! depends on seeing it was deleted. Same for a ',DIM(3)' written past a '|'.
     if self.tk.tokens.lineNo <> ln
       if ~self.TriviaHasContinuation(self.tk.tokens.strBefore) then break.
       ln = self.tk.tokens.lineNo                                                ! the declaration carries on here
     end
    if self.tk.tokens.tok &= NULL then cycle.
    if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then break. ! CHR(10) EOL token carries lineNo=ln (vitTokenize SetLineNumbers): stop BEFORE it, else ',AUTO' merges onto the newline and renders at the next line's start
    last = i
  end
  return last

! ------------------------------------------------------------------------------------
! Append ',AUTO' to the declaration by merging it onto the last decl token (byte-safe
! on output; a later reparse re-splits on the comma). 1 = edited.
! ------------------------------------------------------------------------------------
VitEngine.AddAutoAttr Procedure(LONG pDeclTok)
last   long,auto
i      long,auto
ln     long,auto
k      long,auto
c      long,auto
hasUp  byte,auto
hasLo  byte,auto
cur    StringTheory
tyStr  string(vs:maxName)
autoTx string(4),auto
  code
  last = self.DeclLastTok(pDeclTok)
  cur.setValue(self.tk.getTok(last))
  if ~cur._DataEnd then return 0.
  ! match the ,AUTO case to the data-type keyword's case
  ! (string -> ,auto ; STRING -> ,AUTO ; String -> ,Auto).  Clarion '=' is caseless,
  ! so classify by byte value (val), not a string compare.
  get(self.tk.tokens, pDeclTok)
  if errorcode() then return 0.
  ln = self.tk.tokens.lineNo
  tyStr = ''
  i = pDeclTok
  loop
    i += 1
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.lineNo <> ln then break.
    if self.tk.tokens.tok &= NULL then cycle.
    tyStr = self.tk.tokens.tok              ! first token after the label = the data-type keyword
    break
  end
  hasUp = 0 ; hasLo = 0
  loop k = 1 to len(clip(tyStr))
    c = val(tyStr[k])
    if c >= 65 and c <= 90  then hasUp = 1. ! A-Z
    if c >= 97 and c <= 122 then hasLo = 1. ! a-z
  end
  if hasLo and ~hasUp
    autoTx = 'auto'
  elsif hasUp and hasLo
    autoTx = 'Auto'
  else
    autoTx = 'AUTO'                         ! all-caps or no letters -> AUTO
  end
  cur.append(',' & clip(autoTx))
  self.tk.SetTok(last, cur.valuePtr[1 : cur._DataEnd])
  return 1

! ------------------------------------------------------------------------------------
! Strip ',AUTO' (the AUTO token and its preceding comma) and append the NOTE as a
! trailing line comment. 1 = edited.
! ------------------------------------------------------------------------------------
VitEngine.RemoveAutoAttr Procedure(LONG pDeclTok, StringTheory pNote)
i      long,auto
ln     long,auto
autoT  long,auto
commaT long,auto ! the earlier AutoCheck missed the compound  autoT = 0 ; commaT = 0  write - restored
barT   long,auto ! a '|' token seen on the current physical line - the declaration continues (#24)
  code
  get(self.tk.tokens, pDeclTok)
  if errorcode() then return 0.
  ln = self.tk.tokens.lineNo
  autoT = 0 ; commaT = 0 ; barT = 0
  i = pDeclTok
  loop
    i += 1
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.lineNo <> ln
      if ~barT                                     ! not continued by a trailing '|' token - the bar can also live
        if self.tk.tokens.strBefore &= NULL then break.
        if ~self.TriviaHasContinuation(self.tk.tokens.strBefore) then break.  ! ...in the next token's trivia
      end
      ln = self.tk.tokens.lineNo                   ! an ,AUTO after a '|' is still THIS declaration - follow it (#24)
      barT = 0
    end
    if self.tk.tokens.tok &= NULL then cycle.
    if self.tk.tokens.tok = '|' then barT = 1.
    if self.tk.tokens.type = 'b' and upper(self.tk.tokens.tok) = 'AUTO'
      autoT = i
      break
    end
    if self.tk.tokens.tok = ',' then commaT = i. ! remember the most recent comma before AUTO
  end
  if ~autoT then return 0.
  if commaT and commaT < autoT
    self.tk.DeleteToks(commaT, autoT)            ! remove ',AUTO' (comma + keyword together)
  else
    self.tk.DeleteToks(autoT, autoT)             ! defensive: AUTO with no leading comma
  end
  ! Insert on a MID-LINE token (pDeclTok+1 = the type keyword), NOT the col-1 label:
  ! InsertStringAtEOL walks forward to the line's <10> EOL token, but a first-on-line
  ! label has an empty strBefore, so starting there trips its 'expecting continuation
  ! line' stop.  pDeclTok+1 sits before the just-deleted comma, so the DeleteToks above
  ! does not shift its index.  pComment=1 supplies the '!' itself (as VitRewrite's NOTE does).
  self.tk.InsertStringAtEOL(pDeclTok + 1, clip(pNote.getValue()), 1)
  return 1

! ------------------------------------------------------------------------------------
VitEngine.LineOfTok Procedure(LONG pTok)
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return 0.
  return self.tk.tokens.lineNo

! ------------------------------------------------------------------------------------
! LOG-facing line of a token. In the preview (tk.mapOn armed) the change log
! must carry SOURCE line numbers - the Changes list clicks land without any guesswork;
! in batch (mapOn 0) MapLine is identity so reports stay byte-identical. Use in pLog
! emission ONLY - logic must keep using LineOfTok (stream coordinates).
! ------------------------------------------------------------------------------------
VitEngine.LogLineOf Procedure(LONG pTok)
  code
  return self.tk.MapLine(self.LineOfTok(pTok))

! ------------------------------------------------------------------------------------
! Single-char helpers - reimplemented from the vtxaDiff usage (the originals
! live in VTXADIFF009.INC's module, not in the workspace). A "single char" is:
! a bare digit 0-9 (the digit character), or a quoted literal whose content is
! one char: 'x', a doubled pair ''/<<//{{, or one char-code group '<nnn>' with
! nnn 0-255. Multi-value groups like '<13,10>' are NOT single.
! ------------------------------------------------------------------------------------
VitEngine.GetSingleCharVal Procedure(STRING pStr)
s      StringTheory
inner  StringTheory
n      long,auto
  code
  s.setValue(pStr)
  s.trim()
  if s._DataEnd = 1
    if s.valuePtr[1] >= '0' and s.valuePtr[1] <= '9' then return val(s.valuePtr[1]).
    return -1
  end
  if s._DataEnd < 3 or |
     s.valuePtr[1] <> '''' or s.valuePtr[s._DataEnd] <> ''''
    return -1
  end
  inner.setValue(s.valuePtr[2 : s._DataEnd - 1])
  case inner._DataEnd
  of 1
    return val(inner.valuePtr[1])
  of 2
    if inner._DataEnd = 2 and inner.valuePtr[1 : 2] = '''''' then return 39.  ! <single quote>           ! '' -> the quote char
    if inner._DataEnd = 2 and inner.valuePtr[1 : 2] = '<<<<' then return 60.  ! '<<'           ! << -> <
    if inner._DataEnd = 2 and inner.valuePtr[1 : 2] = '{{{{' then return 123. ! '{{'           ! {{ -> {
    return -1
  else
    if inner.valuePtr[1] = '<<' and inner.valuePtr[inner._DataEnd] = '>'
      inner.setValue(inner.valuePtr[2 : inner._DataEnd - 1])
      if inner._DataEnd and inner.IsAllDigits()
        n = inner.getValue()
        if n >= 0 and n <= 255 then return n.
      end
    end
    return -1
  end

! ------------------------------------------------------------------------------------
VitEngine.IsSingleChar Procedure(STRING pStr)
  code
  if self.GetSingleCharVal(pStr) = -1 then return false.
  return true

! ------------------------------------------------------------------------------------
! Pretty names for generated comments - port of vtxaDiff DescribeChar (the
! program-level one, NOT VitTokenize.DescribeChar which is a hex debug aid).
! ------------------------------------------------------------------------------------
VitEngine.CharName Procedure(STRING pStr)
nm  string(24),auto
  code
  ! the table moved to VitTokenize so the rule-file NOTE charname() helper shares
  ! it - two copies of this list would drift the moment one gained an entry.
  nm = self.tk.CharNameOfByte(self.GetSingleCharVal(pStr))
  if nm then return clip(nm).
  return clip(left(pStr))

! ------------------------------------------------------------------------------------
! Truncate a RAW quoted literal (outer quotes present, escapes intact) to
! pWant logical characters. Escape-aware like VitMatch.LitLength: doubled
! pairs stay pairs, '<13,10>' groups keep only the values needed, 'A{5}'
! repeat counts are reduced. Result is re-quoted raw text. Companion to the
! CheckCat port (vtxaDiff setLiteralLength, reimplemented - see helper note).
! ------------------------------------------------------------------------------------
VitEngine.LitTruncate Procedure(StringTheory pInOut, LONG pWant)
t     StringTheory
out   StringTheory
grp   StringTheory
n     long
i     long,auto
j     long,auto
k     long,auto
rep   long,auto
take  long,auto
  code
  t.setValue(pInOut)
  if t._DataEnd < 2 or |
     t.valuePtr[1] <> '''' or t.valuePtr[t._DataEnd] <> ''''
    return
  end
  out.setValue('''')
  i = 2
  loop while i <= t._DataEnd - 1 and n < pWant
    if i < t._DataEnd - 1
      if t.valuePtr[i : i+1] = '''''' or t.valuePtr[i : i+1] = '<<<<' or t.valuePtr[i : i+1] = '{{{{'
        out.append(t.valuePtr[i : i+1])
        n += 1
        i += 2
        cycle
      end
    end
    if t.valuePtr[i] = '<<'                          ! char-code group
      j = i + 1
      loop while j <= t._DataEnd - 1 and t.valuePtr[j] <> '>'
        j += 1
      end
      if j > t._DataEnd - 1 or j = i + 1 then break. ! malformed: stop here
      grp.setValue(t.valuePtr[i+1 : j-1])
      grp.split(',')
      take = pWant - n
      if take > grp.records() then take = grp.records().
      out.append('<<')
      loop k = 1 to take
        if k > 1 then out.append(',').
        out.append(clip(left(grp.getLine(k))))
      end
      out.append('>')
      n += take
      i = j + 1
      cycle
    end
    if t.valuePtr[i] = '{{' ! repeat group: previous char counted once already
      j = i + 1
      loop while j <= t._DataEnd - 1 and t.valuePtr[j] <> '}'
        j += 1
      end
      if j > t._DataEnd - 1 or j = i + 1 or ~n then break.
      grp.setValue(t.valuePtr[i+1 : j-1])
      if ~grp.IsAllDigits() then break.
      rep = grp.getValue()
      take = pWant - n
      if take > rep - 1 then take = rep - 1.
      if take > 0
        out.append('{{' & (take + 1) & '}')
        n += take
      end
      i = j + 1
      cycle
    end
    out.append(t.valuePtr[i])
    n += 1
    i += 1
  end
  out.append('''')
  pInOut.setValue(out)

! ------------------------------------------------------------------------------------
! True when any strBefore in the token span carries a line break - i.e. the
! span crosses a continuation or holds a comment. Builtins that rejoin and
! reflow argument lists skip such spans so trivia is never lost.
! ------------------------------------------------------------------------------------
VitEngine.SpanHasNL Procedure(LONG pS, LONG pE)
x  long,auto
  code
  loop x = pS to pE
    get(self.tk.tokens, x)
    if errorcode() then return true. ! defensive: treat unknown as unsafe
    if self.tk.tokens.tok &= NULL then return true.
    if self.tk.tokens.tok = '<10>' then return true.
    if not self.tk.tokens.strBefore &= NULL
      if instring('<10>', self.tk.tokens.strBefore, 1, 1) then return true.
    end
  end
  return false

! ------------------------------------------------------------------------------------
! BUILTIN RemoveDoubledBrackets - port of the vtxaDiff009 routine (GCR 8Sep2021).
! foo((x)) -> foo(x): the FindSeq first token carries no ws flag, so the outer
! ( must be glued to the token before it (its strBefore is empty - deleting it
! loses nothing); the inner pair must bracket exactly the same extent.
! deviation from vtxaDiff (which deletes blind): the pair is skipped when
! the inner ( or the outer ) starts a new line, so a continuation or comment in
! their strBefore is never lost. Veto if byte-parity preferred.
! ------------------------------------------------------------------------------------
VitEngine.BuiltinDoubledBrackets Procedure(StringTheory pLog)
startTok     long
endBracket   long,auto
lineNo       long,auto
changes      long
stB          StringTheory
stT          StringTheory
  code
  loop
    startTok = self.tk.FindSeq(',^ (, (', startTok+1)                           ! look for ( (
    if ~startTok then break.
    endBracket = self.tk.MatchLeftBracket('(',')',startTok)
    if ~endBracket then cycle.                                                  ! shouldn't happen
    if self.tk.MatchLeftBracket('(',')',startTok+1) <> endBracket-1 then cycle. ! not matching doubled brackets
    self.tk.GetTok(startTok+1, stB, stT)                                        ! inner ( on a continuation line? skip the pair
    if stB.containsByte(10) then cycle.                                         ! <line feed>
    self.tk.GetTok(endBracket, stB, stT)                                        ! outer ) on a continuation line? skip the pair
    if stB.containsByte(10) then cycle.                                         ! <line feed>
    self.tk.getTok(startTok)
    lineNo = self.tk.tokens.lineNo
    self.tk.deleteTok(endBracket)                                               ! delete duplicated outer brackets - do end bracket first!
    self.tk.deleteTok(startTok)
    pLog.append('BUILTIN RemoveDoubledBrackets line ' & self.tk.MapLine(lineNo) & ': doubled brackets removed<13,10>')
    startTok -= 1                                                               ! restart from the same place - that bracket is gone
    changes += 1
  end
  return changes

! ------------------------------------------------------------------------------------
VitEngine.RejoinReparse Procedure()
whole  StringTheory
svMap  BYTE,AUTO
  code
  svMap = self.tk.mapOn
  if svMap
    self.tk.MapFold()        ! compose the preview line map BEFORE the re-lex frees the tokens
    self.tk.mapOn = 0        ! ParseText restamps a FRESH stream - it must not fold garbage coordinates
  end
  self.tk.JoinToks(whole)
  self.tk.FreeToks()
  self.tk.ParseText(whole)
  self.tk.mapOn = svMap
  self.rw.m.freqDirty = true ! token queue rebuilt - anchor counts stale
  self.rulesDirty = 0        ! whoever reparses, the stream is fresh - pending level-hazard debt is paid
  self.syms.Build(self.tk)

! ------------------------------------------------------------------------------------
! ------------------------------------------------------------------------------------
! TXA SUPPORT. A .txa is a template EXPORT, not Clarion source: the code you wrote lives
! inside [SOURCE] blocks scattered through template markup, and it starts in COLUMN 1 -
! which in Clarion is label position. Handed straight to the tokenizer, every one of those
! lines reads as a label and the whole analysis is wrong.
!
! So the file is wrapped: made to look like Clarion on the way in, and put back exactly on
! the way out. Ported from the vtxaDiff tool this engine grew out of, whose marker protocol
! is kept unchanged because it is reversible by construction - every edit leaves a mark
! saying how to undo it, and TxaPostProcess undoes them in the opposite order:
!
!   <253>        a line joined onto the one before it        -> becomes <10> again
!   !<255>       the lifted application header               -> the marker is removed
!   !<250>       a template-data line, commented out          -> the marker is removed
!   !<252,10>    a whole line this pass INSERTED             -> the line is removed
!   !<251,10>    a line shifted one column right             -> marker and the space removed
!
! Those FIVE marker bytes are chosen because they cannot occur in a .txa: it is plain text, and
! 251-255 are not produced by the template writer.
!
! WHAT IT DOES, in order:
!   1. Normalises to LF so every position test below is counting one byte per line end.
!   2. An [APPLICATION] export holds several applications; each is processed separately and
!      the results re-joined, because the header lift in step 3 is per application.
!   3. Everything before the program's first [DATA] is application and template metadata -
!      dictionary references, template registrations, the procedure list. None of it is
!      Clarion, so it is lifted out behind a !<255> marker rather than parsed.
!   4. A `WHEN` continuation (a line ending '|') is folded onto its own first line, so the
!      tokenizer sees one statement rather than a fragment per line.
!   5. Each [PROCEDURE] gets a synthesised `<name> PROCEDURE(<params>)` header inserted
!      ahead of it, marked !<252,10>. The TXA has the name and PARAMETERS as template
!      fields, not as a Clarion header, so without this there is no scope for a procedure's
!      declarations and code to belong to.
!   6. Inside a [SOURCE] block that belongs to a CODE embed, a line starting in column 1 is
!      shifted one space right and marked !<251,10>. Only code embeds: a DATA embed's
!      column-1 text really is a label and must stay where it is. The embed kind is found
!      by scanning BACK from the [SOURCE] line to the enclosing EMBED, which is why this
!      cannot be done a line at a time.
! ------------------------------------------------------------------------------------
VitEngine.TxaPreProcess Procedure(StringTheory pSrc)
apps   StringTheory
one    StringTheory
out    StringTheory
x      long,auto
  code
  pSrc.LineEndings(st:unix)
  x = pSrc.count('[APPLICATION]<10>')
  if x < 2
    self.TxaPreOne(pSrc)                           ! one application, or a procedure export
    return                                         ! RETURN, not EXIT - EXIT leaves a ROUTINE
  end
  apps.setValue(pSrc)                              ! several - each gets its own header lift
  apps.split('[APPLICATION]<10>')
  loop x = 1 to apps.records()
    if x = 1
      one.setValue(apps.getLine(x))                ! whatever stood BEFORE the first separator - see below
    else
      one.setValue('[APPLICATION]<10>' & apps.getLine(x))
    end
    if ~one._DataEnd then cycle.                   ! the empty first field a leading separator always makes
    self.TxaPreOne(one)
    out.append(one)
  end
  pSrc._StealValue(out)
  ! RECORD 1 IS NOT AN APPLICATION, IT IS WHATEVER PRECEDED THE FIRST ONE.
  !     Splitting a value that BEGINS with the separator always yields an EMPTY first field -
  !     splitNoQuotes starts at 1 and its AddLine sets the end to (separator position - 1), which is
  !     zero. Prefixing every record therefore turned N applications into N+1 and put a phantom empty
  !     application at the top of the file, which re-imports as one. Record 1 now goes through
  !     unprefixed and is skipped when empty, so a file starting with the separator loses nothing and
  !     a file carrying a preamble before its first application keeps it verbatim.

! ---- one application (or one procedure export). See the header above for the four steps. ----
VitEngine.TxaPreOne Procedure(StringTheory pSt)
hdr        StringTheory                            ! the lifted metadata, flattened to one line
tmp        StringTheory
proc       StringTheory
stPos      long,auto
endPos     long,auto
xx         long,auto
codeLine   long,auto
str8       string(8),auto
wln        StringTheory                            ! the whole line, so the word-boundary test can look past str8's eight characters
wx         long,auto
inSrc      long,auto                               ! inside a [SOURCE] block (step 7)
borrowedLf long,auto                               ! step 5 lent the text a leading line feed and owes it back
  code
  ! ---- 3. lift the application/template metadata ----
  if pSt.startsWith('[APPLICATION]')
    stPos = pSt.findChars('[PROGRAM]<10>')
    stPos = pSt.findChars('<10>[DATA]<10>', stPos) ! THE LEADING <10> IS PART OF THE MATCH AND IS LOAD-BEARING - see below
    if stPos > 1
      hdr.setValue('!<255>')
      hdr.append(pSt.valuePtr[1 : stPos - 1])      ! everything BEFORE that line feed
      pSt.removeFromPosition(1, stPos)             ! ...and the line feed with it, so the body starts at '[DATA]'
      hdr.replaceByte(10,253)                      ! the whole header is now ONE line replace all <line feed> with '<253>'
      pSt.prepend(hdr.getValue() & '<10>')         ! the line feed added here stands in EXACTLY for the one removed
    end
  end
  ! THE LIFT MUST REMOVE EXACTLY WHAT IT PUTS BACK.
  !     Searching for '[DATA]<10>' returns the position of the MATCH START - the '[' itself - so a
  !     slice on that alone lifts the '[' into the header while removeFromPosition takes it out of
  !     the body, leaving the body starting 'DATA]'. The prepend then adds a line feed that nothing
  !     ever removes, and the file comes back with a line holding just '[' and the next line
  !     starting 'DATA]', which breaks re-import. Searching for the line feed TOO makes stPos point
  !     at that line feed instead, so the header ends where the line ends and the added line feed
  !     replaces the removed one byte for byte.
  !     It also self-guards: a '[DATA]' not at the start of a line does not match at all, and the
  !     lift is skipped rather than eating a real character off the front of it.
  !     The shape comes from a DIFF tool, which wraps both sides the same way and never writes the
  !     text back - so exact reconstruction does not matter there, and it does here.
  ! ---- 4. fold a WHEN continuation onto its first line ----
  stPos = 0
L loop
    stPos = pSt.findChars('<10>WHEN ', stPos+1)
    if ~stPos then break.
    stPos += 5
    loop
      stPos = pSt.findByte(10, stPos+1)
      if ~stPos then break L.
      if pSt.valuePtr[stPos-1] <> '|' then break.
      pSt.valuePtr[stPos] = '<253>'
    end
  end
  ! ---- 5. give every [PROCEDURE] a real Clarion header to be a scope ----
  ! THE FIRST [PROCEDURE] IN THE FILE HAS NOTHING IN FRONT OF IT, AND THE SEARCH BELOW WANTS A
  !     LINE FEED THERE. A procedure export - which is what both of the shipped .txa fixtures
  !     are, and much the commonest kind - STARTS with '[PROCEDURE]' at position 1, so the scan
  !     stepped straight over its first procedure and every local in it stayed unscoped. The
  !     analyses then withheld that procedure, quietly: under-reach, never a wrong rewrite, which
  !     is exactly why a change COUNT could never have shown it.
  !     A borrowed line feed is the whole fix. It goes on before the scan and comes off after, so
  !     the first procedure looks like all the others to one body of code rather than needing a
  !     second copy of it, and the text this procedure returns is unchanged by the loan.
  borrowedLf = false
  if pSt.startsWith('[PROCEDURE]<10>NAME ')
    pSt.prepend('<10>')
    borrowedLf = true
  end
  stPos = 1
  loop
    endPos = 0
    tmp.setValue(pSt.FindBetween('<10>[PROCEDURE]<10>NAME ','<10>[', stPos, endPos))
    if ~stPos then break.
    stPos -= 17                                           ! back to the '[' of [PROCEDURE]
    tmp.split('<10>')
    proc.setValue(tmp.getLine(1) & ' PROCEDURE ')
    tmp.setValueFromLine(tmp.InLine('PARAMETERS ',,,,,,st:begins))
    if tmp._DataEnd
      tmp.SetAfter('PARAMETERS ')
      tmp.trim()
      tmp.unquote('''','''')
      proc.append(tmp)
    end
    proc.clip()
    proc.append(' !<252,10>')                             ! marked: this whole line is ours
    pSt.insert(stPos, proc)
    stPos = endPos + proc._DataEnd
  end
  if borrowedLf then pSt.removeFromPosition(1, 1).        ! give the line feed back - see the note above step 5
  ! ---- 6. shift column-1 CODE out of label position ----
  pSt.split('<10>')
  stPos = 0
  loop
    stPos = pSt.inline('[SOURCE]',,stPos+1,,,st:wholeLine)
    if ~stPos then break.
    codeLine = false
    loop xx = stPos to 1 by -1                            ! which embed does this block sit in?
      tmp.setValue(pSt.getLine(xx))
      if choose(tmp._DataEnd < 1, '', tmp.valuePtr[1 : tmp._DataEnd]) = 'WHEN ''Accepted''' then codeLine = true ; break.
      if choose(tmp._DataEnd < 1, '', tmp.valuePtr[1 : tmp._DataEnd]) = '[END]' then break.
      if not tmp.StartsWith('EMBED ') then cycle.
      if tmp.findChars('Code',7) or tmp.findChars('EventHandling',7)
        codeLine = true
        break
      end
      if tmp.findChars('Data',7) or tmp.findChars('Routines',7) or tmp.findChars('Procedures',7) then break.
    end
    if ~codeLine then cycle.                              ! a DATA embed's column 1 is a real label
    endPos = pSt.inline('[END]',,stPos+1,,,st:wholeLine)
    if ~endPos then break.
    loop xx = stPos+1 to endPos-1
      str8 = pSt.getLine(xx)
      case str8
      of 'PROPERTY' orof 'PRIORITY' orof 'LABEL'
        ! str8 holds only the first EIGHT characters, so `PRIORITYX = 1` truncates
        ! straight into this arm - and `PRIORITY 5000` matched only BECAUSE of that same
        ! truncation. A directive is a WORD: require what follows it to be blank or nothing.
        wln.setValue(pSt.getLine(xx))
        wx = len(clip(str8)) + 1
        if wx > wln._DataEnd or wln.valuePtr[wx] = ' ' or val(wln.valuePtr[wx]) = 9
          cycle                                           ! template directives, not code
        end
      end
      case val(str8[1])
      of 32 orof 33 orof 63 orof 124                      ! <space> orof '!' orof '?' orof '|'
        ! already clear of column 1, or a comment/continuation - leave it
      else
        pSt.setLine(xx, ' ' & pSt.getLine(xx) & '!<251>')
      end
    end
  end
  ! ---- 7. EVERYTHING OUTSIDE A [SOURCE] BLOCK IS TEMPLATE DATA. Comment it out.
  !      This step is NOT in the tool this was ported from, and it is needed because this
  !      engine has passes that one never had. Template markup is a column-1 word followed
  !      by a value:
  !          NAME DrawMakeHeading
  !          FROM ABC Source
  !          PRIORITY 5000
  !      which is exactly the shape of a Clarion declaration, so AlignDeclTypes lined their
  !      "type column" up with the real declarations below and rewrote the template's own
  !      data. Found by the round-trip gate on the first run.
  !      Commenting is used rather than shifting because a comment is inert to EVERYTHING -
  !      every rule, every builtin, every aligner - and this file has no business being
  !      changed outside the source the author embedded in it. The marker goes in column 1
  !      so the comment sits at position 1, which AlignComments skips (it ignores anything
  !      with Pos < 2), so these lines cannot become anchors for the real comments either.
  !      The synthesised PROCEDURE headers are NOT commented: they are what gives a
  !      procedure's declarations and code a scope to share.
  inSrc = 0
  loop xx = 1 to pSt.records()
    tmp.setValue(pSt.getLine(xx))
    if tmp.StartsWith('[SOURCE]') then inSrc = 1 ; cycle. ! the marker itself is data
    if tmp.StartsWith('[END]')    then inSrc = 0.         ! ... and so is this one
    if inSrc
      ! PROPERTY / PRIORITY / LABEL are template DIRECTIVES that live INSIDE a source
      ! block. They are not Clarion, and in column 1 they look exactly like a declaration
      ! label, so the aligners reformat them - `PRIORITY 5000` came back `PRIORITY   5000`,
      ! lined up with the equates under it. The shift loop above already skips them for the
      ! same reason; they need protecting from the aligners as well.
      str8 = tmp.getValue()
      case str8
      of 'PROPERTY' orof 'PRIORITY' orof 'LABEL'
        wx = len(clip(str8)) + 1                          ! the same word-boundary test as above
        if wx > tmp._DataEnd or tmp.valuePtr[wx] = ' ' or val(tmp.valuePtr[wx]) = 9
          pSt.setLine(xx, '!<250>' & tmp.getValue())
        end
      end
      cycle                                               ! everything else here is real source
    end
    if tmp.findChars('!<252>') or |   ! our own synthesised header - must stay live
       ~tmp._DataEnd                                      ! a blank line is already inert
      cycle
    end
    pSt.setLine(xx, '!<250>' & tmp.getValue())
  end
  ! ---- steps 6 and 7 both worked on the SPLIT line queue. Without this join none of those
  !      setLine writes reach the value the caller goes on to parse - the shift and the
  !      comment-out both silently do nothing, and the first sign of it is the template's own
  !      data coming back reformatted. The tool this was ported from joins here too; dropping
  !      that one line is what the round-trip gate caught on its first run.
  pSt.join('<10>')

! ---- undo TxaPreProcess, marker by marker, in the opposite order. Ported unchanged. ----
VitEngine.TxaPostProcess Procedure(StringTheory pOut)
x long,auto
y long,auto
  code
  pOut.LineEndings(st:unix)                               ! JoinToks emits CRLF; count one byte per end
  pOut.replaceByte(253,10)                                ! un-join the folded lines
  pOut.remove('!<255>')                                   ! the lifted header is itself again
  pOut.remove('!<250>')                                   ! template data is data again (step 7)
  y = 1
  loop                                                    ! drop the lines we inserted whole
    x = pOut.findChars('!<252,10>', y)
    if ~x then break.
    y = pOut.instring('<10>',-1,1,x)
    pOut.RemoveFromPosition(y+1, x+2-y)
  end
  y = 1
  loop                                                    ! put the shifted lines back in column 1
    x = pOut.findChars('!<251,10>', y)
    if ~x then break.
    y = pOut.instring('<10>',-1,1,x)
    pOut.RemoveFromPosition(x, 2)
    pOut.RemoveFromPosition(y+1, 1)
  end
  pOut.replace('<10>','<13,10>')

! ------------------------------------------------------------------------------------
! The three analyses that MUST NOT run on a .txa.
!
! A template export contains only the source YOU embedded. What the template generates
! around it is not in the file and does not exist until the app is built. All three of
! these decide by looking at every use in the text they can see:
!
!   UnusedVars         a variable used only by generated code looks unused, and the
!                      declaration would be commented out
!   UnusedAssignments  same premise, same failure
!   AutoCheck          adds ,AUTO once it can prove always-set-before-read. A read in
!                      generated code is invisible to that proof, so the proof is false
!                      and ,AUTO puts an uninitialised variable into a live procedure
!
! This is the same premise failure this engine has hit three times before - static module
! data, an include fragment with no CODE, and a PROGRAM's globals seen from one MEMBER -
! each time because a whole-file scan assumed it could see every reference. A .txa breaks
! it harder than any of those: the missing code is not in another file, it does not exist
! yet. There is no analysis that fixes this, so the answer is to refuse, out loud.
! ------------------------------------------------------------------------------------
VitEngine.TxaAnalysisRefused Procedure(STRING pBuiltin)
  code
  ! Under the .txa embed rule this names the RESTRICTED trio, not a refusal: the caller
  ! prints the once-per-file advisory and falls through, and the real restricting is
  ! ScopeFullyEmbedded at each analysis's own gate.
  if ~self.isTxa then return 0.
  case upper(pBuiltin)
  of 'UNUSEDVARS' orof 'UNUSEDASSIGNMENTS' orof 'AUTOCHECK'
    return 1
  end
  return 0

! ------------------------------------------------------------------------------------
! is the scope [pStartTok..pEndTok] contained WHOLLY inside one .txa embed? Always true
! on a plain .clw. The wrap marks every template line with byte 250 in the trivia of
! the tokens that follow it, so any 250 INSIDE the span means the scope crosses
! template data - and the template's generated code there can read or write anything,
! which is what makes a spanning scope undecidable (the embed rule, strict form).
! A synthesised procedure header spans template data by construction, so procedures
! rarely qualify; a ROUTINE wholly inside one [SOURCE] block is the working case.
! The span's LEADING trivia (pStartTok's own strBefore) is the world BEFORE the scope
! and must not disqualify a scope that starts right after a boundary; likewise the
! trailing gap after the last content token belongs to the NEXT scope's world.
! ------------------------------------------------------------------------------------
VitEngine.ScopeFullyEmbedded Procedure(LONG pStartTok, LONG pEndTok)
i     long,auto
lastC long
  code
  if ~self.isTxa then return 1.
  loop i = pEndTok to pStartTok by -1
    get(self.tk.tokens, i)
    if errorcode() then cycle.
    if self.tk.tokens.tok &= NULL then cycle.
    if size(self.tk.tokens.tok) = 1 and val(self.tk.tokens.tok) = 10 then cycle.
    lastC = i
    break
  end
  if ~lastC then return 1. ! nothing but trivia - vacuously inside
  loop i = pStartTok + 1 to lastC
    get(self.tk.tokens, i)
    if errorcode() then return 0.
    if not self.tk.tokens.strBefore &= NULL
      if instring('<250>', self.tk.tokens.strBefore, 1, 1) then return 0.
    end
  end
  return 1

! ------------------------------------------------------------------------------------
! Join the token stream and write the result, taking a backup first for an in-place run.
!
! ORDER MATTERS HERE and both steps below say why at the site: the final clip has to happen
! after the join, because the last line of a file with no trailing newline has no EOL token to
! carry its trailing whitespace; and the .txa unwrap has to happen after the clip, because its
! markers sit at line ends and a later clip would eat a space a shifted line is owed.
! ------------------------------------------------------------------------------------
VitEngine.WriteOutput Procedure(STRING pFn, StringTheory pLog)
out    StringTheory
outFn  StringTheory
bak    StringTheory ! in-place: the untouched original, saved as a .bak first
bakFn  string(500),AUTO
  code
  self.tk.JoinToks(out)
  ! the LAST line of a file that has no line ending after it carries its
  ! trailing whitespace in no EOL token's strBefore - there is no EOL token - so ClipLines cannot
  ! see it. One clip on the joined text is the whole fix. It cannot touch anything else: only
  ! spaces and tabs are named, and only at the very end of the file. A file that DOES end in a
  ! newline ends in byte 10, so this is a no-op there.
  out.clip('<32,9>')
  ! ---- .txa: undo the wrap. This is the LAST thing done to the text, after the clip
  !      above, because the markers it removes sit at line ends - a clip running after
  !      them could eat the space a shifted line is owed back. See TxaPostProcess.
  if self.isTxa then self.TxaPostProcess(out).
  outFn.setValue(self.OutName(pFn))
  ! outDir given: the output name must not BE the input - that path takes no .bak, so a
  ! same-name hit would destroy the original. The CLI refuses a same-directory outDir up
  ! front by filesystem probe (which settles '.', relative and absolute spellings); this
  ! equality test is the engine's own last line of defence for an embedder that passes
  ! the source's directory spelled the same way, and it can never false-positive.
  if self.outDir and upper(choose(outFn._DataEnd < 1, '', outFn.valuePtr[1 : outFn._DataEnd])) = upper(pFn)
    self.saveErrors += 1
    pLog.append('ERROR output file is the input file ' & clip(pFn) & |
                ' - ORIGINAL NOT OVERWRITTEN (use --in-place for a backed-up overwrite)<13,10>')
    return
  end
  ! in-place (no outDir): the original is about to be overwritten - preserve it as a
  ! timestamped .bak first, straight from disk (still untouched: we transform in memory).
  ! If the backup cannot be written we REFUSE to overwrite, so nothing is ever lost.
  if ~self.outDir
    bakFn = self.BackupName(pFn)
    if ~bak.LoadFile(clip(pFn))
      self.saveErrors += 1
      pLog.append('ERROR could not read original to back up ' & clip(pFn) & ' : ' & bak.LastError & |
                  '  - ORIGINAL NOT OVERWRITTEN<13,10>')
      return
    end
    if ~bak.SaveFile(clip(bakFn))
      self.saveErrors += 1
      pLog.append('ERROR could not write backup ' & clip(bakFn) & ' : ' & bak.LastError           & |
                  '  - ORIGINAL NOT OVERWRITTEN<13,10>')
      return
    end
    pLog.append('backup: ' & clip(bakFn) & '<13,10>')
  end
  if not out.SaveFile(outFn.getValue())
    self.saveErrors += 1
    pLog.append('ERROR could not save ' & outFn.getValue() & ' : ' & out.LastError                & |
                '  (does the output directory exist? SaveFile does not create it)<13,10>')
    return
  end
  pLog.append('written: ' & outFn.getValue() & '<13,10>')

! ------------------------------------------------------------------------------------
! One-line heartbeat, overwritten each step: watch the file to see where a
! long run is. clock() = hundredths of a second since midnight.
! ------------------------------------------------------------------------------------
VitEngine.Progress Procedure(STRING pMsg)
st  StringTheory
  code
  if ~self.progressFn then return.
  if clock() >= self.progLast and clock() - self.progLast < 25 then return. ! throttle to ~4 writes/sec (was one DISK WRITE per rule per pass per file); midnight wrap falls through
  self.progLast = clock()
  st.setValue(clock() & '  ' & clip(self.curFile) & '  ' & clip(pMsg) & '<13,10>')
  st.SaveFile(clip(self.progressFn))

! ------------------------------------------------------------------------------------
VitEngine.OutName Procedure(STRING pFn)
st    StringTheory
full  string(500),AUTO
dp    long,AUTO
  code
  ! 1. base target path: outDir\basename.ext, or the source path in-place
  if ~self.outDir
    full = pFn                                                              ! in-place (may still get a suffix below)
  else
    st.setValue(self.outDir,st:clip)
    if st.valuePtr[st._DataEnd] <> '\' then st.append('\').
    st.append(st.FileNameOnly(pFn, true))                                   ! StringTheory.inc:598 - FileNameOnly(<<fPath>, pIncludeExtension=true),
                                                                            !   so `true` here keeps the extension, which is what an output path needs
    full = st.getValue()
  end
  ! 2. insert the suffix (if any) just before the final '.' so the extension is preserved
  if self.outSuffix
    dp = instring('.', clip(full), -1, len(clip(full)))                     ! last '.' (step -1 = search backwards)
    if dp                                                                   ! a dot inside a DIRECTORY name (c:\src.v2\noext) is not an extension
      if dp < instring('\', clip(full), -1, len(clip(full))) or dp < instring('/', clip(full), -1, len(clip(full)))
        dp = 0
      end
    end
    if dp > 0
      full = sub(full, 1, dp - 1) & clip(self.outSuffix) & sub(full, dp, len(clip(full)) - dp + 1)
    else
      ! guarded. This is the same self-append shape as everywhere else, but what it
      ! builds is a FILENAME - a silent truncation here does not lose a diagnostic, it writes
      ! the output to a DIFFERENT PATH than the one reported. Refuse instead.
      if len(clip(full)) + len(clip(self.outSuffix)) > size(full)
        return ''                                                           ! WriteOutput's SaveFile then fails, logs, and counts a saveError
      end
      full = clip(full) & self.outSuffix                                    ! no extension - just append
    end
  end
  return clip(full)

! ------------------------------------------------------------------------------------
! In-place backup name: the source path with the run stamp inserted before the final
! '.', then '.bak' appended, e.g.  src\Foo.clw  ->  src\Foo on 20260714 at 14302547.clw.bak
VitEngine.BackupName Procedure(STRING pFn)
full  string(500),AUTO
dp    long,AUTO
  code
  full = pFn
  dp = instring('.', clip(full), -1, len(clip(full))) ! last '.' (step -1 = search backwards)
  if dp                                               ! dot inside a directory name is not an extension
    if dp < instring('\', clip(full), -1, len(clip(full))) or dp < instring('/', clip(full), -1, len(clip(full)))
      dp = 0
    end
  end
  if dp > 0
    full = sub(full, 1, dp - 1) & clip(self.stamp) & sub(full, dp, len(clip(full)) - dp + 1)
  else
    ! see OutName - a truncated BACKUP name is worse than a truncated message,
    ! because WriteOutput refuses to overwrite when the backup cannot be written, and a
    ! truncated name could silently collide with an existing backup instead.
    if len(clip(full)) + len(clip(self.stamp)) > size(full)
      return ''                                       ! caller treats '' as "no backup name" and refuses to overwrite
    end
    full = clip(full) & self.stamp                    ! no extension - just append the stamp
  end
  return clip(full) & '.bak'

! ------------------------------------------------------------------------------------
! Does the declaration LINE of pDeclTok mention pNameU as a whole token?
! Used to find sibling decls carrying OVER(V) for candidate V.
! ------------------------------------------------------------------------------------
VitEngine.DeclLineMentions Procedure(LONG pDeclTok, STRING pNameU)
i   long,auto
ln  long,auto
nU  string(vs:maxName),AUTO
  code
  nU = upper(pNameU)
  get(self.tk.tokens, pDeclTok)
  if errorcode() then return 0.
  ln = self.tk.tokens.lineNo
  i = pDeclTok
  loop
    i += 1
    get(self.tk.tokens, i)
    if errorcode() then break.
    ! *** A DECLARATION IS A LOGICAL LINE, NOT A PHYSICAL ONE. *** Breaking at the first
    ! lineNo change stopped the walk at a '|', so everything past the continuation was
    ! invisible: `sh SHORT,|` / `OVER(p)` read as carrying no OVER, and the guard that
    ! depends on seeing it was deleted. Same for a ',DIM(3)' written past a '|'.
     if self.tk.tokens.lineNo <> ln
       if ~self.TriviaHasContinuation(self.tk.tokens.strBefore) then break.
       ln = self.tk.tokens.lineNo ! the declaration carries on here
     end
    if self.tk.tokens.tok &= NULL then cycle.
    if upper(self.tk.tokens.tok) = nU then return 1.
  end
  return 0

! ------------------------------------------------------------------------------------
! Insert pHeader at the start of the PHYSICAL line the token begins - i.e.
! after the LAST line feed in its strBefore. A plain PrependStrBefore lands the '!'
! BEFORE any continuation text / swallowed OMIT block living in strBefore, which
! renders at the END of the PREVIOUS physical line and leaves this line live.
! ------------------------------------------------------------------------------------
VitEngine.CommentLineStart Procedure(LONG pTok, STRING pHeader)
sb   StringTheory
out  StringTheory
p    long,auto
k    long,auto
  code
  get(self.tk.tokens, pTok)
  if errorcode() then return.
  if self.tk.tokens.strBefore &= NULL
    self.tk.PrependStrBefore(pTok, pHeader)
    return
  end
  p = 0
  loop k = 1 to size(self.tk.tokens.strBefore)
    if val(self.tk.tokens.strBefore[k]) = 10 then p = k.
  end
  if ~p
    self.tk.PrependStrBefore(pTok, pHeader)
    return
  end
  sb.setValue(self.tk.tokens.strBefore)
  out.setValue(sb.sub(1, p))
  out.append(pHeader)
  if p < sb._DataEnd then out.append(sb.slice(p + 1)).
  self.tk.SetStrBefore(pTok, out.getValue())

! ------------------------------------------------------------------------------------
! fill the per-scope AutoCheck cache. Everything here is a function of the
! SCOPE, not the symbol, so it is computed ONCE rather than per candidate (which would be
! O(symbols x span)):
! main-code bounds (stop before the first routine), the CODE token, the routine list,
! and the GOTO / COMPILE / OMIT bail pre-scan. acBail=1 also encodes "missing
! scope" and "no CODE section" - AutoVerdict returns UNKNOWN for all of them.
! ------------------------------------------------------------------------------------
VitEngine.AutoScopePrep Procedure(LONG pScopeId)
r      long,auto
i      long,auto
dp     long,auto                                     ! first '.' inside a token
startT long,auto
endT   long,auto
  code
  if self.acScopeId = pScopeId then return.
  self.acScopeId = pScopeId
  self.acCodeT = 0 ; self.acMainEnd = 0 ; self.acBail = 1
  free(self.acRoutQ)
  free(self.acDotQ)                                  !
  get(self.syms.scopes, pScopeId)
  if errorcode() then return.
  startT = self.syms.scopes.startTok
  endT   = self.syms.scopes.endTok
  if endT <= startT then return.
  self.acMainEnd = endT
  loop r = 1 to records(self.syms.scopes)
    get(self.syms.scopes, r)
    if self.syms.scopes.kind = vs:scRoutine and self.syms.scopes.parentId = pScopeId
      self.acRoutQ.rStart = self.syms.scopes.startTok
      self.acRoutQ.rEnd   = self.syms.scopes.endTok
      add(self.acRoutQ)
      if self.syms.scopes.startTok > startT and self.syms.scopes.startTok - 1 < self.acMainEnd
        self.acMainEnd = self.syms.scopes.startTok - 1
      end
    end
  end
  self.acCodeT = self.CodeTokOfScope(startT, self.acMainEnd)
  ! collect the ROOTS of every merged dotted token in the WHOLE scope span, ONCE
  ! per scope (was an O(span) sweep per eligible symbol - Part A paid +23%).
  ! Dups are kept (hit/miss lookup only); sorted for the keyed GET in AutoEligible.
  loop i = startT to endT
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    dp = instring('.', self.tk.tokens.tok, 1, 1)
    if dp < 2 then cycle. ! no dot / leading dot: not a merged label
    self.acDotQ.rootU = upper(sub(self.tk.tokens.tok, 1, dp - 1))
    add(self.acDotQ)
  end
  sort(self.acDotQ, +self.acDotQ.rootU)
  if ~self.acCodeT then return.
  self.acBail = 0
  loop i = self.acCodeT + 1 to self.acMainEnd
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    case upper(self.tk.tokens.tok)
    of 'GOTO' orof 'COMPILE' orof 'OMIT'
      self.acBail = 1
      break
    end
  end

!===============================================================================================
! Should this receiver be refused? 1 = yes.
!
! The Check* builtins find their work by METHOD NAME - `.replace(`, `.cat(` and so on - so they
! can be pointed at any object that happens to have a same-named method. Measured on the corpus:
! of 10,128 such call sites, 573 had a receiver that PROVABLY names another class, and about
! 4,000 more had one the symbol table could not resolve at all.
!
! What happens to those 4,000 is --receiver=:
!
!   assume   rewrite it as a StringTheory, identified or not.
!   check    DEFAULT. Refuse if any use of it in scope is not a StringTheory method.
!   strict   Refuse unless it PROVABLY resolves to a StringTheory.
!
! `check` can only ADD refusals, so it cannot break output that works today, and on the corpus
! it catches about two thirds of the genuinely-wrong receivers. It is NOT sound: a class whose
! methods are all ALSO StringTheory methods passes it - our own CStringClass probe does, by
! construction. That residual is what `strict` is for, and `strict` wants --thorough to be
! useful, since that is what makes a receiver declared in an include resolvable.
!===============================================================================================
VitEngine.RecvIsOtherClass Procedure(LONG pRecvTok)
sy     long,auto
scr    long,auto
bestR  long,auto
bestSp long,auto
nm     string(vs:maxName),auto
  code
  get(self.tk.tokens, pRecvTok)
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.type <> 'b' then return 0.
  nm = upper(self.tk.tokens.tok)
  if ~nm then return 0.
  bestR  = 0
  bestSp = 0
  if nm <> 'SELF' and ~instring('.', nm, 1, 1) and ~instring(':', nm, 1, 1)
    loop sy = 1 to records(self.syms.syms)
      get(self.syms.syms, sy)
      if errorcode() then break.
      if self.syms.syms.nameU <> nm then cycle.
      scr = self.syms.syms.scopeId
      get(self.syms.scopes, scr)
      if errorcode() then cycle.
      if self.syms.scopes.startTok > pRecvTok or self.syms.scopes.endTok < pRecvTok then cycle.
      if ~bestR or self.syms.scopes.endTok - self.syms.scopes.startTok < bestSp
        bestR  = sy
        bestSp = self.syms.scopes.endTok - self.syms.scopes.startTok
      end
    end
  end
  if bestR
    get(self.syms.syms, bestR)
    if ~errorcode() and self.syms.syms.typeU and ~self.syms.syms.isLike
      return choose(self.syms.syms.typeU <> 'STRINGTHEORY') ! resolved: it is, or it is not
    end
  end
  ! ---- not resolvable: SELF, a qualified name, or a declaration this file cannot see --------
  case self.recvMode
  of rm:strict
    return 1                                                ! proof required, and there is none
  of rm:check
    return self.RecvForeignUse(pRecvTok)
  end
  return 0                                                  ! rm:assume - treat it as a StringTheory

!===============================================================================================
! Is this receiver used ANYWHERE in its scope in a way a StringTheory could not be?
!
! Every `<recv>.<method>(` in the enclosing scope is looked up in the StringTheory method table.
! One method that is not there is enough: SystemStringClass gives itself away with FromFile and
! CountLines, UltimateString with Get and Contains.
!
! The table going stale is safe. If CapeSoft adds a method and this list has not caught up, the
! new method reads as foreign and the site is REFUSED - a lost rewrite, not a wrong one. A class
! DERIVED from StringTheory that adds methods refuses for the same reason, which matches the
! typed rules: they do not match derived classes either.
!===============================================================================================
VitEngine.RecvForeignUse Procedure(LONG pRecvTok)
i     long,auto
sS    long,auto
sE    long,auto
sc    long,auto
recvU string(vs:maxName),auto
methU string(vs:maxName),auto
  code
  get(self.tk.tokens, pRecvTok)
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  recvU = upper(self.tk.tokens.tok)
  if ~recvU then return 0.
  ! the scope this use sits in - walk only that, not the file
  sS = 1
  sE = records(self.tk.tokens)
  loop sc = 1 to records(self.syms.scopes)
    get(self.syms.scopes, sc)
    if errorcode() then break.
    if self.syms.scopes.startTok > pRecvTok or self.syms.scopes.endTok < pRecvTok then cycle.
    if self.syms.scopes.endTok - self.syms.scopes.startTok < sE - sS
      sS = self.syms.scopes.startTok
      sE = self.syms.scopes.endTok
    end
  end
  loop i = sS to sE - 2
    get(self.tk.tokens, i)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if self.tk.tokens.type <> 'b' then cycle.
    if upper(self.tk.tokens.tok) <> recvU then cycle.
    get(self.tk.tokens, i + 1)
    if errorcode() or self.tk.tokens.tok &= NULL then cycle.
    if self.tk.tokens.tok <> '.' then cycle.
    get(self.tk.tokens, i + 2)
    if errorcode() or self.tk.tokens.tok &= NULL then cycle.
    if self.tk.tokens.type <> 'b' then cycle.
    methU = upper(self.tk.tokens.tok)
    if ~methU then cycle.
    if ~instring(' ' & clip(methU) & ' ', self.stMeth.getValue(), 1, 1)
      return 1 ! one foreign method is enough
    end
  end
  return 0

!===============================================================================================
! Is this declaration a STRING(1)?
!
! Asked of a DIM'd head: an element of a STRING(1) array is one character, so the DIM does not
! defeat a single-index pick. Anything else - a wider STRING, a LONG, an unsized or computed
! size - answers 0 and the pick is refused.
!===============================================================================================
VitEngine.DeclIsString1 Procedure(LONG pDeclTok)
tw  long,auto
  code
  loop tw = pDeclTok to pDeclTok + 2
    if upper(self.tk.getTok(tw)) = 'STRING'
      if self.tk.getTok(tw+1) = '(' and self.tk.getTok(tw+3) = ')'
        if self.tk.getTok(tw+2) = '1' then return 1.
      end
      break
    end
  end
  return 0

!===============================================================================================
! Is a single-index pick of pNameU provably ONE CHARACTER?
!
! `x[2]` is one byte of a STRING - but one ELEMENT of a DIM'd array, and an element can be any
! width or any type. So this answers only YES or DON'T KNOW, and DON'T KNOW refuses.
!
! *** ASKING "IS IT DIM'd?" WAS THE WRONG QUESTION. *** That answers NO when it cannot find the
! declaration at all, which let two shapes through: an array PARAMETER, where the DIM is on the
! caller's declaration and never on this one (`P1 PROCEDURE(*STRING[] pa)` - `pa[2]` is an
! element of the caller's array), and a DIM'd member of a plain GROUP, where the merged token
! `grp.arr` is not what the symbol table holds. The PRE-prefixed twin `qq:qarr` resolved and
! refused, which is what showed the hole was reach and not logic.
!
! Proof required: the name resolves to a declaration visible here, that declaration starts in
! column one (a PARAMETER does not), and it carries no DIM.
!===============================================================================================
VitEngine.NameSliceOk Procedure(STRING pNameU, LONG pAtTok)
sy     long,auto
scr    long,auto
bestR  long,auto
bestSp long,auto
dTok   long,auto
depth  long,auto
nm     string(vs:maxName),auto
atTok  long,auto                ! where THIS link is resolved from
  code
  nm    = pNameU
  depth = 0
  atTok = pAtTok
  loop
    depth += 1
    if depth > 8 then return 0. ! a LIKE cycle - do not chase it
    bestR  = 0
    bestSp = 0
    loop sy = 1 to records(self.syms.syms)
      get(self.syms.syms, sy)
      if errorcode() then break.
      if self.syms.syms.nameU <> nm then cycle.
      scr = self.syms.syms.scopeId
      get(self.syms.scopes, scr)
      if errorcode() then cycle.
      if self.syms.scopes.startTok > atTok or self.syms.scopes.endTok < atTok then cycle.
      if ~bestR or self.syms.scopes.endTok - self.syms.scopes.startTok < bestSp
        bestR  = sy
        bestSp = self.syms.scopes.endTok - self.syms.scopes.startTok
      end
    end
    if ~bestR then return 0.                         ! not resolvable - do not guess
    get(self.syms.syms, bestR)
    if errorcode() then return 0.
    dTok = self.syms.syms.declTok
    if ~self.syms.IsColOneLabel(dTok) then return 0. ! a PARAMETER: the DIM is the caller's
    ! *** DIM ONLY DEFEATS THE PROOF WHEN THE ELEMENT IS WIDER THAN ONE. *** `x STRING(5),DIM(3)`
    ! makes x[2] a five-character element, but `d1 STRING(1),DIM(3)` makes d1[2] exactly one
    ! character - which is what this arm is trying to establish. Refusing every DIM threw that
    ! away and cost a fixture two conversions.
    if band(self.DeclAttrBits(dTok), ab:dim) and ~self.DeclIsString1(dTok) then return 0.
    if ~self.syms.syms.isLike then break.            ! a real declaration, and no DIM on it
    ! *** LIKE INHERITS DIM, SO THE PROOF HAS TO FOLLOW IT. *** `lk LIKE(sdim)` carries no DIM of
    ! its own and never will - it takes the one on sdim. Refusing every LIKE would be sound but
    ! throws away `lp LIKE(pl)` of a plain STRING, which is one character and should convert. For
    ! a LIKE symbol the registry keeps the TARGET's name in typeU, so walk to it and ask again.
    ! *** AND THE NEXT LINK RESOLVES WHERE IT IS DECLARED, NOT WHERE IT IS USED. *** Clarion
    ! binds LIKE(target) at the DECLARATION, so a local at the use site that happens to share
    ! the target's name is a different variable entirely. Resolving each link from pAtTok let
    ! such a local stand in for the real target and flipped the proof.
    atTok = dTok
    nm    = self.syms.syms.typeU
    if ~nm then return 0.
  end
  return 1


! ------------------------------------------------------------------------------------
! one walk of the declaration line returning every attribute of interest as
! a bitmask (ab:*). Replaces four separate DeclHasAttr walks in AutoEligible.
! ------------------------------------------------------------------------------------
VitEngine.DeclAttrBits Procedure(LONG pDeclTok)
i    long,auto
ln   long,auto
b    long
  code
  get(self.tk.tokens, pDeclTok)
  if errorcode() then return 0.
  ln = self.tk.tokens.lineNo
  i = pDeclTok
  loop
    i += 1
    get(self.tk.tokens, i)
    if errorcode() then break.
    ! *** A DECLARATION IS A LOGICAL LINE, NOT A PHYSICAL ONE. *** Breaking at the first
    ! lineNo change stopped the walk at a '|', so everything past the continuation was
    ! invisible: `sh SHORT,|` / `OVER(p)` read as carrying no OVER, and the guard that
    ! depends on seeing it was deleted. Same for a ',DIM(3)' written past a '|'.
     if self.tk.tokens.lineNo <> ln
       if ~self.TriviaHasContinuation(self.tk.tokens.strBefore) then break.
       ln = self.tk.tokens.lineNo ! the declaration carries on here
     end
    if self.tk.tokens.type <> 'b' or |
       self.tk.tokens.tok &= NULL
      cycle
    end
    case upper(self.tk.tokens.tok)
    of 'AUTO'   ; b = bor(b, ab:auto)
    of 'OVER'   ; b = bor(b, ab:over)
    of 'DIM'    ; b = bor(b, ab:dim)
    of 'STATIC' ; b = bor(b, ab:static)
    of 'THREAD' ; b = bor(b, ab:thread)
    end
  end
  return b

!===============================================================================================
! MergeGuardChain: consecutive single-line IFs that set the SAME thing become ONE test.
!
!     if extraPos.containsByte(92) then pathish = 1.   ! '\'
!     if extraPos.containsByte(47) then pathish = 1.   ! '/'
!     if extraPos.containsByte(46) then pathish = 1.   ! <<dot>
!
! Three statements saying one thing. When every condition asks whether the SAME receiver holds
! ONE character, the whole chain is a single library call:
!
!     if extraPos.containsA('\/.') then pathish = 1.
!
! ContainsA takes an ALPHABET and answers whether any of it is present, which is the question
! the chain was asking a character at a time. Two rules come with it:
!   - pClip defaults to st:Clip and clips the ALPHABET, so a space written LAST is trimmed off
!     and silently stops being searched for. The order of an alphabet means nothing, so a space
!     is simply never put there.
!   - a quote is doubled, as in any Clarion literal.
!
! *** WHAT MAY BE MERGED, and this is the whole of the safety argument. ***
!   - the statements must be CONSECUTIVE, each a whole line of its own
!   - each must be the single-line form `if COND then ASSIGNMENT.`
!   - the ASSIGNMENT must be the same in every one of them
!   - every condition must be a one-character containment test on the same receiver
!
! The last two are what make it safe. N separate IFs evaluate N conditions; one merged test
! stops as soon as it has its answer. That only matters if a condition DOES something besides
! answer - and containsByte/containsChar only read. The assignment ran once in the chain (or not
! at all) and runs once here (or not at all), whatever the conditions did.
!
! THE COMMENTS. Those `! '\'` notes are generated by the rule that wrote the containsByte call,
! from NOTE(charname(lit)): either CharNameOfByte's name for the byte, or the source literal
! when it has no special name. Both are recognised EXACTLY and dropped, because the characters
! they document are now visible in the alphabet itself. Anything else is an author's own comment
! and is carried onto the merged line - a transformer does not get to discard those.
!===============================================================================================
VitEngine.BuiltinMergeGuardChain Procedure(StringTheory pLog)
i          long,auto
n          long,auto
changes    long
lnS        long          ! first token of the line being read
lnE        long          ! its EOL token
mgIf       long          ! the IF token, when the line is one of ours
mgThen     long          ! its THEN
mgDot      long          ! the terminating '.'
asgTxt     StringTheory  ! the assignment, normalised, for comparing
runAsg     StringTheory  !   and the one this run agreed on
recvTxt    StringTheory  ! the receiver of a one-character test
runRecv    StringTheory  !   and the one this run agreed on
rawTxt     StringTheory
condTxt    StringTheory  ! the condition being staged, as text
sb         StringTheory
alpha      StringTheory  ! the alphabet, before escaping
carried    StringTheory  ! comments that were NOT ours to drop
cmtRaw     StringTheory  ! one line's comment, unpacked from the bank
cmtBank    StringTheory  ! every staged comment end to end; cmtSt/cmtLn slice it
pureU      StringTheory  ! ' NAME NAME ' - calls that only READ
! #Removed as not used: indentSt   StringTheory                            ! the surviving line's own indent
allPure    byte          ! every condition is safe to short-circuit
mgAgain    byte          ! a merge moved the tokens - walk again
raw        StringTheory
t          long,auto
runCount   long
mgRuns     long,auto     ! conditions collapsed by MgCollapseRuns
allChar    byte          ! every condition so far is a one-character test
! #Removed as not used: q          long,auto
mgQ        QUEUE,PRE(mq)
ifTok        long
eolTok       long
condS        long
condE        long
cmtSt        long        ! this line's comment as a slice of cmtBank - start and
cmtLn        long        ! length. *** NEITHER A FIXED FIELD NOR A TOKEN INDEX. ***
                         ! A fixed field silently cut a 217-character comment to
                         ! 200. A token index has no size to get wrong, but it is
                         ! only valid until the first DeleteToks - and MgOrForm
                         ! reads its comments AFTER editing tokens, so every
                         ! carried comment came from the wrong place and was lost.
                         ! Text banked when the line is STAGED is immune to both.
                         ! in a fixed field silently cut a 217-character comment to 200 -
                         ! an author's words shortened by a tool asked to tidy layout. The
                         ! token has no length, so there is no size left to guess wrong.
ch           string(1)
hasCh        byte
condTx       string(400) ! the condition as written, for the OR form
             END
  code
  n = records(self.tk.tokens)
  if n < 2 then return 0.
  free(mgQ)
  ! The same list IfChainToCase uses, and extensible the same way: a rule file's PURE(...)
  ! adds to it. A call that only READS may be short-circuited; anything else may not.
  self.IfCasePureList(pureU)
  pureU.append('CONTAINSA ')
  if not self.rl.rules.bparmQ &= NULL
    loop t = 1 to records(self.rl.rules.bparmQ)
      get(self.rl.rules.bparmQ, t)
      if upper(self.rl.rules.bparmQ.name) = 'PURE' and not self.rl.rules.bparmQ.value &= NULL
        raw.setValue(self.rl.rules.bparmQ.value)
        raw.Upper()
        pureU.append(clip(raw.getValue()) & ' ')
      end
    end
  end
  ! *** A MERGE MOVES EVERY INDEX AFTER IT, SO THE WALK STARTS AGAIN. *** MgFlush deletes the
  ! lines it folded in; i and n were read before that, so carrying on with them reads the wrong
  ! tokens - some chains merged, others silently missed, and a SECOND run found more. A pass
  ! that depends on how much it has already done is not idempotent, and this one broke the
  ! 2 -> 4 -> 2 round trip. Restarting terminates: a merge always removes more than it adds.
  changes  = 0
  mgAgain  = 1
  loop while mgAgain
    mgAgain  = 0
    runCount = 0
    free(mgQ)
    n = records(self.tk.tokens)
    i = 1
    loop while i <= n
      do MgReadLine
      if mgIf and mgThen and mgDot
        self.MgSpanText(mgThen + 1, mgDot - 1, asgTxt)
        ! *** A MERGE RUNS THE BODY ONCE WHERE IT RAN ONCE PER TRUE CONDITION. *** That is only
        ! the same thing for a repeatable statement, so the shape is checked before the run is
        ! opened OR extended - it gates the OR-joined form as much as the containsA one.
        if self.MgStmtRepeatable(asgTxt) and |
           (~runCount or self.MgSameStmt(asgTxt, runAsg))
          if ~runCount
            runAsg.setValue(asgTxt)
            allChar = 1
            allPure = 1
            runRecv.free()
          end
          do MgStageLine
          i = lnE + 1
          cycle
        end
      end
      do MgFlush                 ! this line is not part of the open run
      if mgAgain then break.     !   and the indices below have moved
      ! IT MAY STILL START THE NEXT ONE. Skipping it after a flush lost the first line of any
      ! chain that began immediately after another one ended.
      if mgIf and mgThen and mgDot
        runAsg.setValue(asgTxt)
        allChar = 1
        allPure = 1
        runRecv.free()
        do MgStageLine
      end
      i = lnE + 1
    end
    if ~mgAgain then do MgFlush. ! a run still open at end of file
  end
  free(mgQ)
  ! ... and the same collapse INSIDE a condition the author already wrote as one line.
  ! Run after the chain merging, on settled text, for the reason the whole builtin is
  ! FINAL: the rules that make containsByte() live further down the rule file.
  mgRuns = self.MgCollapseRuns()
  if mgRuns
    changes += mgRuns
    pLog.append('BUILTIN MergeGuardChain: ' & mgRuns & ' condition(s) collapsed to containsA<13,10>')
  end
  if changes
    self.wantReparse = true
    pLog.append('BUILTIN MergeGuardChain: ' & changes & ' chain(s) merged this pass<13,10>')
  end
  return changes

! ---- the physical line starting at i --------------------------------------------------------
! mgIf/mgThen/mgDot are non-zero only when the line is exactly `if COND then ASSIGNMENT.`
! THEN is taken at bracket depth 0, so a `then` inside a call cannot be mistaken for the
! statement's own, and the dot must be the LAST token on the line: `if a then b. ; c` is two
! statements and not ours to touch.
MgReadLine routine
  data
mrD    long,auto
mrJ    long,auto
  code
  lnS = i ; lnE = 0 ; mgIf = 0 ; mgThen = 0 ; mgDot = 0
  loop mrJ = i to n
    if self.IsEolTok(mrJ) then lnE = mrJ ; break.
  end
  if ~lnE then lnE = n + 1.
  if lnE - lnS < 5 then exit. ! if C then A . - five tokens at the very least
  get(self.tk.tokens, lnS)
  if errorcode() then exit.
  if self.tk.tokens.tok &= NULL then exit.
  if upper(self.tk.tokens.tok) <> 'IF' then exit.
  mgIf = lnS
  mrD = 0
  loop mrJ = lnS + 1 to lnE - 1
    get(self.tk.tokens, mrJ)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if size(self.tk.tokens.tok) = 1
      if self.tk.tokens.tok = '(' then mrD += 1.
      if self.tk.tokens.tok = ')' then mrD -= 1.
    end
    if ~mrD and upper(self.tk.tokens.tok) = 'THEN' and ~mgThen then mgThen = mrJ.
  end
  if ~mgThen
    mgIf = 0
    exit
  end
  get(self.tk.tokens, lnE - 1)
  if errorcode() or self.tk.tokens.tok &= NULL
    mgIf = 0
    exit
  end
  if size(self.tk.tokens.tok) <> 1 or self.tk.tokens.tok <> '.'
    mgIf = 0
    exit
  end
  mgDot = lnE - 1
  if mgDot <= mgThen + 1 then mgIf = 0. ! `if x then.` - nothing assigned

! ---- stage this line into the run -----------------------------------------------------------
MgStageLine routine
  data
msP  long,auto
msB  long,auto
  code
  clear(mgQ)
  mq:ifTok  = mgIf
  mq:eolTok = lnE
  mq:condS  = mgIf + 1
  mq:condE  = mgThen - 1
  mq:cmtSt  = 0
  mq:cmtLn  = 0
  mq:hasCh  = 0
  mq:ch     = ''
  get(self.tk.tokens, lnE)                                  ! a trailing comment rides the EOL token's trivia
  if ~errorcode() and not self.tk.tokens.strBefore &= NULL
    msP = instring('!', self.tk.tokens.strBefore, 1, 1)
    if msP
      self.MgCmtText(lnE, cmtRaw)                           ! READ IT HERE, while the token index
      if cmtRaw._DataEnd                                    !   is still valid - a later DeleteToks
        mq:cmtSt = cmtBank._DataEnd + 1                     !   makes it point at something else
        mq:cmtLn = cmtRaw._DataEnd
        cmtBank.append(cmtRaw)
      end
    end
  end
  self.MgSpanRaw(mq:condS, mq:condE, condTxt)               ! as written: this text is re-emitted
  mq:condTx = condTxt.getValue()
  if condTxt._DataEnd > 400 then allChar = 0 ; allPure = 0. ! too wide to carry - leave it alone
  if ~self.MgCondIsPure(mq:condS, mq:condE, pureU) then allPure = 0.
  msB = self.MgOneCharTest(mq:condS, mq:condE, recvTxt)
  if msB > 0
    if ~runRecv._DataEnd then runRecv.setValue(recvTxt).
    if upper(choose(recvTxt._DataEnd < 1, '', recvTxt.valuePtr[1 : recvTxt._DataEnd])) = upper(runRecv.getValue())
      mq:hasCh = 1
      mq:ch    = chr(msB)
    end
  end
  if ~mq:hasCh then allChar = 0.
  add(mgQ)
  runCount += 1

! ---- close the run: merge it if it earned the right, then start over ------------------------
MgFlush routine
  data
mfQ      long,auto
mfFirst  long,auto
mfLast   long,auto
mfCondS  long,auto
mfCondE  long,auto
! #Removed as not used: mfSp     long,auto
mfName   string(64),auto
  code
  if runCount < 2 then do MgReset ; exit.
  if ~allChar
    if allPure then do MgOrForm.
    do MgReset
    exit
  end
  alpha.free() ; carried.free()
  loop mfQ = 1 to records(mgQ)
    get(mgQ, mfQ)
    if errorcode() then break.
    alpha.append(mq:ch)
    if mq:cmtLn                          ! ours to drop, or the author's to keep?
      mfName = self.tk.CharNameOfByte(val(mq:ch))
      cmtRaw.free()                      ! the comment WHOLE, straight from the
      if mq:cmtLn then cmtRaw.setValue(cmtBank.valuePtr[mq:cmtSt : mq:cmtSt + mq:cmtLn - 1]).
      rawTxt.setValue(cmtRaw)            !   token - nothing to overflow
      rawTxt.RemoveFromPosition(1,1)     ! past the '!'
      rawTxt.trim()
      if choose(rawTxt._DataEnd < 1, '', rawTxt.valuePtr[1 : rawTxt._DataEnd]) = mfName or choose(rawTxt._DataEnd < 1, '', rawTxt.valuePtr[1 : rawTxt._DataEnd]) = '''' & mq:ch & ''''
        ! generated from the character itself, which the alphabet now shows - drop it
      else
        if carried._DataEnd then carried.append(' ').
        carried.append(cmtRaw)           ! whole, however long it was
      end
    end
  end
  if ~self.MgAlphaFix(alpha)             ! an all-space alphabet clips to
    if allPure then do MgOrForm.         !   nothing, and would test for
    do MgReset                           !   nothing
    exit
  end
  sb.setValue(runRecv)
  sb.append('.containsA(''')
  self.MgLitAlphabet(alpha, sb)          ! quote, '<', '{' and the unprintables
  sb.append(''')')
  get(mgQ, 1)
  mfFirst = mq:eolTok ; mfCondS = mq:condS ; mfCondE = mq:condE
  get(mgQ, records(mgQ))
  mfLast = mq:eolTok
  ! BACK TO FRONT: dropping the later lines first leaves the earlier indices untouched.
  if mfLast > mfFirst then self.tk.DeleteToks(mfFirst + 1, mfLast).
  if mfCondE > mfCondS then self.tk.DeleteToks(mfCondS + 1, mfCondE).
  self.tk.SetTok(mfCondS, sb.getValue()) ! strBefore omitted: the space after IF stays
  ! THE TRAILING TRIVIA IS REWRITTEN EITHER WAY. The surviving line came into this with a
  ! comment of its own, and if that one was generated it has to GO - leaving it would name one
  ! character out of an alphabet that now lists them all. Anything an author wrote is in
  ! `carried`, whichever line it was on, so this puts back exactly what should be there and
  ! nothing else. The column is not this routine's business: AlignComments settles it after.
  if carried._DataEnd
    self.tk.SetStrBefore(mfFirst - (mfCondE - mfCondS), '   ' & carried.getValue())
  else
    self.tk.SetStrBefore(mfFirst - (mfCondE - mfCondS), '')
  end
  changes += 1
  mgAgain = 1                            ! the indices have moved - walk again
  do MgReset


! ---- SHAPE B: one OR-joined test, a condition to a line ------------------------------------
! Everything the containsA form cannot take still collapses, just not into a library call:
!
!     if firstCond or |                      ! the first author's comment
!        secondCond or |                     ! the second
!        thirdCond                           ! the third
!       target = value
!     end
!
! A condition to a line, so each keeps the comment written beside it. Text after a '|' is
! ignored by the compiler exactly as text after a '!' is, so a comment rides there safely.
!
! N separate IFs evaluate N conditions; this stops at the first true one. That is why every
! condition had to be provably READ-ONLY before we got here - see allPure.
!
! The tokens are written back to front, because every insertion moves the indices after it and
! nothing moves the ones before. Each condition becomes ONE coarse token: the pass sets
! wantReparse, so the file is tokenised again before anything reads these as tokens rather than
! as text, and what reaches the file is the text.
MgOrForm routine
  data
moQ     long,auto
moEol   long,auto
moLast  long,auto
moIf    long,auto
moThen  long,auto
moAsgS  long,auto
moAsgE  long,auto
moPos   long,auto
moNl    long,auto
moJ     long,auto
moIndSt StringTheory ! the indent, exact: a fixed string pads it
moSb    StringTheory
  code
  get(mgQ, 1)
  if errorcode() then exit.
  moIf   = mq:ifTok
  moEol  = mq:eolTok
  moThen = mq:condE + 1
  moAsgS = moThen + 1
  moAsgE = moEol - 2 ! the token before the statement's own dot
  if moAsgE < moAsgS then exit.
  ! The THEN token's trivia is about to be OVERWRITTEN with ' ' so THEN can become the
  ! first 'or'. When the first chain line breaks before THEN - `if <cond> | ! note` and then
  ! THEN on the next line - that trivia is where the author's '|' and anything written after
  ! it lives, and overwriting it drops the note without a word. Refuse the whole merge.
  ! Before any edit, deliberately: an early exit here leaves the chain exactly as written, and
  ! `changes` is not incremented until the bottom of this routine.
  if self.SpanTriviaHasComment(moThen, moThen) then exit.
  get(mgQ, records(mgQ))
  moLast = mq:eolTok
  ! the line's own indent, from the IF token's leading trivia
  moIndSt.free()
  get(self.tk.tokens, moIf)
  if ~errorcode() and not self.tk.tokens.strBefore &= NULL
    moNl = 0
    loop moJ = 1 to size(self.tk.tokens.strBefore)
      if val(self.tk.tokens.strBefore[moJ]) = 10 then moNl = moJ.
    end
    if moNl < size(self.tk.tokens.strBefore)
      moIndSt.setValue(self.tk.tokens.strBefore[moNl + 1 : size(self.tk.tokens.strBefore)])
    end
  end
  if moLast > moEol then self.tk.DeleteToks(moEol + 1, moLast). ! lines 2..k
  self.tk.DeleteToks(moEol - 1, moEol - 1)                      ! the dot: a block has none
  ! *** EVERY NEW LINE ENDS WITH A REAL EOL TOKEN. *** Writing the newline into the next
  ! token's trivia instead LOOKS identical in the file - the writer turns a lone <10> into
  ! CRLF either way - but it leaves a physical line that no line-walker can SEE, because
  ! they bracket lines by EOL tokens. This routine is itself such a walker: after the first
  ! merge in a file every later line was mis-bracketed, so chains further down were missed.
  ! That made the pass depend on how many merges had already happened - not idempotent, and
  ! it broke the 2 -> 4 -> 2 round trip on Parser.clw.
  self.tk.AddTok(moAsgE + 1, '<10>', '')                        ! ends the body's line
  self.tk.AddTok(moAsgE + 2, 'end', moIndSt.getValue())         ! ... and an END instead
  get(mgQ, records(mgQ))                                        ! the LAST condition's comment
  cmtRaw.free()                                                 !   sits on its own line
  if mq:cmtLn then cmtRaw.setValue(cmtBank.valuePtr[mq:cmtSt : mq:cmtSt + mq:cmtLn - 1]).
  moSb.setValue('   ')
  if cmtRaw._DataEnd then moSb.append(cmtRaw).                  ! the last condition's comment
  self.tk.AddTok(moAsgS, '<10>', moSb.getValue())               ! closes the condition line
  moSb.setValue(moIndSt.getValuePtr())
  moSb.append('  ')
  self.tk.SetStrBefore(moAsgS + 1, moSb.getValue())             ! the body, on its own line
  self.tk.SetStrBefore(moEol + 2, '')                           ! the old trailing comment has been
                                                                !   re-placed on its condition's line;
                                                                !   leaving it here trails the END
  self.tk.SetTok(moThen, 'or')                                  ! THEN becomes the first OR
  self.tk.SetStrBefore(moThen, ' ')
  moPos = moThen
  self.tk.AddTok(moPos + 1, '|', ' ')
  moPos += 1
  loop moQ = 2 to records(mgQ)
    get(mgQ, moQ)
    if errorcode() then break.
    moSb.setValue('   ')
    get(mgQ, moQ - 1)                                           ! the PREVIOUS line's comment
    cmtRaw.free()                                               !   closes the line before
    if mq:cmtLn then cmtRaw.setValue(cmtBank.valuePtr[mq:cmtSt : mq:cmtSt + mq:cmtLn - 1]).
    if cmtRaw._DataEnd then moSb.append(cmtRaw).                !   whole, however long this
    self.tk.AddTok(moPos + 1, '<10>', moSb.getValue())          ! a real end to that line
    moPos += 1
    get(mgQ, moQ)
    self.tk.AddTok(moPos + 1, clip(mq:condTx), moIndSt.getValue() & '   ')
    moPos += 1
    if moQ < records(mgQ)
      self.tk.AddTok(moPos + 1, 'or', ' ')
      moPos += 1
      self.tk.AddTok(moPos + 1, '|', ' ')
      moPos += 1
    end
  end
  changes += 1
  mgAgain = 1 ! the indices have moved - walk again

MgReset routine
  free(mgQ)
  runCount = 0
  allChar  = 0
  allPure  = 0
  runRecv.free()

!===============================================================================================
! The tokens pS..pE as text, normalised to ONE space between them. Used to ask whether two
! assignments are the same thing written twice: `f = 1` and `f  =  1` are, and comparing the
! source spacing would say otherwise.
!===============================================================================================
VitEngine.MgSpanText Procedure(LONG pS, LONG pE, StringTheory pOut)
j  long,auto
  code
  pOut.free()
  loop j = pS to pE
    get(self.tk.tokens, j)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if pOut._DataEnd then pOut.append(' ').
    pOut.append(self.tk.tokens.tok)
  end

!===============================================================================================
! Is pS..pE exactly `RECEIVER.containsByte(n)` or `RECEIVER.containsChar('c')` for ONE character?
! Returns the byte, 1..255, or 0 for anything else - and fills pRecv with the receiver as it was
! written, dotted names included.
!
! Read from the RIGHT, because that is where the fixed shape is: ')' , the value, '(' , the
! method name, '.' - and whatever is left in front of them is the receiver. A receiver may be
! `x`, `self.buf` or `a.b.c`, and none of those need special handling this way round.
!===============================================================================================
VitEngine.MgOneCharTest Procedure(LONG pS, LONG pE, StringTheory pRecv)
nmU   string(32),auto
valTx string(64)
b     long,auto
  code
  pRecv.free()
  if pE - pS < 4 then return 0. ! r . name ( v ) is five tokens at the least
  get(self.tk.tokens, pE)
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.tok <> ')' then return 0.
  get(self.tk.tokens, pE - 2)
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.tok <> '(' then return 0.
  get(self.tk.tokens, pE - 3)
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  nmU = upper(self.tk.tokens.tok)
  if nmU <> 'CONTAINSBYTE' and nmU <> 'CONTAINSCHAR' then return 0.
  get(self.tk.tokens, pE - 4)
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  if self.tk.tokens.tok <> '.' then return 0.
  get(self.tk.tokens, pE - 1) ! the value
  if errorcode() or self.tk.tokens.tok &= NULL then return 0.
  valTx = self.tk.tokens.tok
  if nmU = 'CONTAINSBYTE'
    if ~self.MgAllDigits(valTx) then return 0.
    b = valTx                 ! the digits, as a number
  else
    ! a literal of exactly one character. An escape like '<9>' is a single character too, but it
    ! is not one this decides - it is left to the containsByte form, which states its byte.
    if len(clip(valTx)) <> 3 or |
       valTx[1] <> '''' or valTx[3] <> ''''
      return 0
    end
    b = val(valTx[2])
  end
  if b < 1 or b > 255 then return 0.
  ! *** WHAT IS IN FRONT OF THE '.' HAS TO BE A NAME, AND ONLY A NAME. *** Taking the span on
  ! trust and stripping its spaces turned `ok and s.containsByte(92)` into the receiver
  ! `okands` - an identifier that does not exist - and `~s.containsByte(92)` into `~s`, which
  ! DOES compile and is wrong: the chain means `~A or ~B`, the merge means `~(A or B)`. A call
  ! left there, `foo(x).containsByte(92)`, would collapse N evaluations of foo into one.
  if ~self.MgPlainRecv(pS, pE - 5) then return 0.
  self.MgSpanText(pS, pE - 5, pRecv) ! everything before the '.method(' is the receiver
  pRecv.removeByte(32)               ! `a . b` and `a.b` are the same receiver remove all <space>
  if ~pRecv._DataEnd then return 0.
  return b


!===============================================================================================
! ONE condition that tests the same receiver for several single characters, collapsed to one
! containsA - the same saving MergeGuardChain makes across consecutive IFs, made inside a
! condition the author already wrote as one.
!
!     if s.containsByte(92) or s.containsByte(47)     ->   if s.containsA('\/')
!     if ~s.containsByte(92) and ~s.containsByte(47)  ->   if ~s.containsA('\/')
!
! BOTH DIRECTIONS ARE DE MORGAN, AND THE OPERATOR IS NOT INTERCHANGEABLE.
! containsA asks "does it hold ANY of these", so it is an OR of the tests:
!     A or B                 == containsA(ab)
!     ~A and ~B  == ~(A or B) == ~containsA(ab)
! The other two pairings are NOT equal to anything containsA can say - `A and B` is
! contains-ALL, which StringTheory has no method for, and `~A or ~B` is its negation. A run
! whose polarity and operator do not match the two lines above is left alone.
!
! *** THE RUN MUST BE THE WHOLE CONDITION. *** `if x and A or B` parses as `(x and A) or B`,
! so collapsing the A-or-B that the eye sees would move a term across an operator that binds
! tighter. Requiring the run to span the entire condition costs a few collapses and cannot
! make that mistake. Parenthesised sub-runs are a later question, not a silent assumption.
!===============================================================================================
VitEngine.MgCollapseRuns Procedure()
cS     long,auto      ! first token of the condition
cE     long,auto      ! last token of the condition
p      long,auto
j      long,auto
d      long,auto
tS     long,auto      ! this term's first token
tEnd   long,auto
opU    string(8),auto ! the operator joining the terms - all must match
neg    byte           ! this term is negated
runNeg byte,auto      ! ... and every term must agree
b      long,auto
terms  long,auto
ok     byte,auto
nTok   long,auto
tokU   string(16),auto
recv   StringTheory
first  StringTheory
alpha  StringTheory
sb     StringTheory
hits   long,auto
  code
  hits = 0
  nTok = records(self.tk.tokens)
  ! BACK TO FRONT: a collapse deletes tokens, so working backwards leaves every index we have
  ! yet to visit exactly where it was.
  loop p = nTok to 1 by -1
    get(self.tk.tokens, p)
    if errorcode() or self.tk.tokens.tok &= NULL then cycle.
    tokU = upper(self.tk.tokens.tok)
    if tokU <> 'IF' and tokU <> 'ELSIF' then cycle.
    cS = p + 1
    cE = 0
    d  = 0
    loop j = cS to nTok
      if self.IsEolTok(j) then cE = j - 1 ; break.
      get(self.tk.tokens, j)
      if errorcode() or self.tk.tokens.tok &= NULL then cycle.
      if size(self.tk.tokens.tok) = 1
        if self.tk.tokens.tok = '(' then d += 1.
        if self.tk.tokens.tok = ')' then d -= 1.
      end
      if ~d and upper(self.tk.tokens.tok) = 'THEN' then cE = j - 1 ; break.
    end
    if ~cE or cE < cS then cycle.
    ! ---- walk the condition as terms separated by ONE repeated operator -----------------
    opU   = ''
    terms = 0
    ok    = 1
    runNeg = 2 ! 2 = not yet known
    alpha.free()
    first.free()
    tS = cS
    d  = 0
    loop j = cS to cE + 1
      if j <= cE
        get(self.tk.tokens, j)
        if errorcode() or self.tk.tokens.tok &= NULL then cycle.
        if size(self.tk.tokens.tok) = 1
          if self.tk.tokens.tok = '(' then d += 1.
          if self.tk.tokens.tok = ')' then d -= 1.
        end
        if d then cycle.
        tokU = upper(self.tk.tokens.tok)
        if tokU <> 'OR' and tokU <> 'AND' then cycle.
        if opU and opU <> tokU then ok = 0 ; break. ! mixed operators - precedence, leave it
        opU = tokU
      end
      tEnd = j - 1                                  ! the term is everything up to the operator
      neg = 0
      get(self.tk.tokens, tS)
      if errorcode() or self.tk.tokens.tok &= NULL then ok = 0 ; break.
      tokU = upper(self.tk.tokens.tok)
      if tokU = '~' or tokU = 'NOT'
        neg = 1
        tS += 1
      end
      if runNeg = 2 then runNeg = neg.
      if neg <> runNeg then ok = 0 ; break.         ! mixed polarity says nothing containsA can
      b = self.MgOneCharTest(tS, tEnd, recv)
      if ~b then ok = 0 ; break.
      if ~terms
        first.setValue(recv)
      elsif upper(choose(first._DataEnd < 1, '', first.valuePtr[1 : first._DataEnd])) <> upper(recv.getValue())
        ok = 0                                      ! a different receiver each time
        break
      end
      alpha.append(chr(b))
      terms += 1
      tS = j + 1
    end
    if ~ok or terms < 2 then cycle.
    if ~self.MgAlphaFix(alpha) then cycle.          ! all-space, or a space left last
    if opU = 'OR'  and runNeg then cycle.           ! ~A or ~B  - contains-ALL, no method for it
    if opU = 'AND' and ~runNeg then cycle.          !  A and B  - the same, the other way up
    ! The condition tokens are about to be DELETED, and a token's trivia goes with it. A
    ! run spanning a '|' continuation collapses correctly - the continuation is trivia, so the
    ! condition is still one logical line - but a comment written after that '|' is trivia too
    ! and would go with the tokens. Refuse this run rather than drop it.
    if self.SpanTriviaHasComment(cS + 1, cE) then cycle.
    ! ---- emit ---------------------------------------------------------------------------
    sb.free()
    if runNeg then sb.append('~').
    sb.append(first)
    sb.append('.containsA(''')
    self.MgLitAlphabet(alpha, sb)
    sb.append(''')')
    self.tk.SetTok(cS, sb.getValue())
    if cE > cS then self.tk.DeleteToks(cS + 1, cE).
    hits += 1
    nTok = records(self.tk.tokens)
  end
  return hits

!===============================================================================================
! Is the span a bare name chain - `a`, `a.b`, `a.b.c` - and nothing else?
!
! The shape is strict on purpose: an identifier, then any number of '.'-separated identifiers,
! with no operator, no '~', no parenthesis and no keyword anywhere in it. Alternation alone
! rejects `ok and s` (three identifiers running together) and `not s`, and the token test
! rejects `~s` and `foo(x)`.
!===============================================================================================
VitEngine.MgPlainRecv Procedure(LONG pS, LONG pE)
j     long,auto
c     string(1),auto
wantN byte,auto               ! 1 = a NAME is due here, 0 = a '.' is due
  code
  if pE < pS then return 0.
  wantN = 1
  loop j = pS to pE
    get(self.tk.tokens, j)
    if errorcode() or self.tk.tokens.tok &= NULL then return 0.
    if self.tk.tokens.tok = '.'
      if wantN then return 0. ! '..' or a leading dot
      wantN = 1
      cycle
    end
    if ~wantN then return 0.  ! two names with nothing between them - `ok and s`
    c = self.tk.tokens.tok[1]
    if ~((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c = '_')
      return 0                ! `~`, a digit, a quote, a bracket - not a name
    end
    wantN = 0
  end
  return choose(wantN = 0)    ! must have ENDED on a name, not a trailing '.'

!===============================================================================================
! Would running this statement ONCE do what running it N times does?
!
! A merge folds N single-line IFs into one, so the body runs once where it used to run once per
! TRUE condition. For `f = 1` that is the same thing. For `n += 1`, `do Bump` or anything that
! calls out, it is not: two true conditions used to add 2 and would now add 1.
!
! Deliberately strict - a refusal only costs a merge, and a wrong merge costs correct code:
!   * a plain `=` assignment, and nothing else. Compound assignment is out by definition.
!   * no '(' anywhere, so no call can hide on either side.
!   * the target must not appear on the right, which is `x = x + 1` wearing a different hat.
!===============================================================================================
VitEngine.MgStmtRepeatable Procedure(StringTheory pStmt)
one    StringTheory
lhs    StringTheory
rhs    StringTheory
allLhs StringTheory ! every target in the statement, <1>-separated
allRhs StringTheory ! every source in the statement, <1>-separated
txt    StringTheory
j      long,auto
seg    long,auto
  code
  txt.setValue(pStmt)
  txt.trim()
  if ~txt._DataEnd then return 0.
  ! *** A SEMICOLON JOINS STATEMENTS, IT DOES NOT DISQUALIFY THEM. *** `f = 2 ; g = 3` is two
  ! plain stores and merging it is perfectly safe; `f = 2 ; n += 1` is not. So split, and
  ! require EVERY part to be repeatable - refusing the whole line on sight of a ';' threw the
  ! safe case away with the unsafe one.
  !
  ! Split does the quoting itself, which is the point of using it: a ';' inside a literal is
  ! DATA, so `f = ';'` is one statement and not two. RemoveLines then drops the empty part a
  ! stray or doubled ';' leaves behind - `f = 1 ;;` is still just a store, and hand-walking
  ! the string for the same result formed a [seg : seg-1] slice at either end to do it.
  allLhs.free()
  allRhs.free()
  txt.split(';', '''', '''')
  txt.removeLines()
  if ~txt.records() then return 0.
  loop j = 1 to txt.records()
    one.setValue(txt.getLine(j))
    if ~self.MgOneStore(one, lhs, rhs) then return 0.
    allLhs.append(lhs) ; allLhs.append('<1>')
    allRhs.append(rhs) ; allRhs.append('<1>')
  end
  ! *** THE PARTS ARE NOT INDEPENDENT OF EACH OTHER. *** Each one on its own can be perfectly
  ! repeatable while the PAIR is not: in `f = g ; g = 2` the second part writes what the
  ! first one reads, so the second time round the first part sees a different g. With g = 5
  ! and both characters present, the original chain ends f = 2 and the merged line ends f = 5.
  !
  ! So no target may appear among the sources ANYWHERE in the statement. This also refuses
  ! `g = 2 ; f = g`, which is in fact safe - but the cost of refusing is one merge, and the
  ! cost of allowing a wrong one is the user's code.
  seg = 1
  loop j = 1 to allLhs._DataEnd
    if allLhs.valuePtr[j] <> '<1>' then cycle.
    if j > seg
      one.setValue(allLhs.valuePtr[seg : j - 1])
      if instring(upper(one.getValue()), upper(allRhs.getValue()), 1, 1) then return 0.
    end
    seg = j + 1
  end
  ! *** A NAME IS TEXT HERE, BUT WHAT IS AT STAKE IS STORAGE. *** Two spellings can name the
  ! same bytes: a GROUP appears in an expression as a string over its members, so `grp` and
  ! `grp.x` overlap. And a colon is TWO different mechanisms wearing one spelling: `Prefix:Field`
  ! under PRE, and `Structure:Field`, which the LRM allows "instead of a period ... to reference
  ! member variables of any structure except CLASS and named reference variables" (Field
  ! Qualification, p28). So `q.g` and `q:g` can be one field written two ways.
  !
  ! Comparing the TEXT sees none of that, and `f = grp ;
  ! grp.x = 2` merged wrongly. Rather than teach this test the storage model, refuse the
  ! moment a qualified name is in play against anything but constants - the shape is rare and
  ! a refusal costs one merge.
  if self.MgQualClash(allLhs, allRhs) then return 0.
  return 1

!===============================================================================================
! Is a qualified name in play against anything that is not a constant?
!
! IT OVER-REFUSES, AND THE CASES ARE WORTH KNOWING so they do not read as defects later. A '.'
! is a qualifier here whether or not it qualifies anything, so a decimal constant refuses
! (`f = 1.5 * g`); and a ':' or '.' INSIDE a literal counts too (`u = 'a:b'`). Each costs one
! merge on a shape that is rare to begin with, and each errs toward leaving the code alone.
!
! 1 = yes, refuse. A '.' or a ':' anywhere on either side makes a name qualified, and the
! question is then only whether the other side names anything at all - `f = 8 ; pq:state = 9`
! stores constants and is perfectly safe, while `f = g ; grp.x = 2` is not.
!===============================================================================================
VitEngine.MgQualClash Procedure(StringTheory pLhs, StringTheory pRhs)
j    long,auto
c    string(1),auto
qual byte,auto
  code
  qual = 0
  loop j = 1 to pLhs._DataEnd
    c = pLhs.valuePtr[j]
    if c = '.' or c = ':' then qual = 1 ; break.
  end
  if ~qual
    loop j = 1 to pRhs._DataEnd
      c = pRhs.valuePtr[j]
      if c = '.' or c = ':' then qual = 1 ; break.
    end
  end
  if ~qual then return 0.
  ! *** A CLARION LABEL NEED NOT CONTAIN A LETTER. *** "The first character must be a letter or
  ! the underscore character" (LanguageReference.md, valid labels), so `_1` and `__2` are names
  ! and a letters-only test cannot see them: `f = _1 ; _1.x = 2` merged wrongly. A letterless
  ! name has to START with the underscore, and no numeric constant carries one, so admitting it
  ! here costs nothing. MgPlainRecv already spells this class correctly.
  loop j = 1 to pRhs._DataEnd ! does the other side name anything?
    c = pRhs.valuePtr[j]
    if (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c = '_' then return 1.
  end
  return 0

!===============================================================================================
! Are these two statements the same statement?
!
! Clarion identifiers are case-blind, so `F = 1` and `f = 1` ARE the same statement and should
! merge - which is why this compared upper() to upper(). A LITERAL is not case-blind: `f = 'a'`
! and `f = 'A'` store different bytes, and the upper() compare called them equal and merged
! them. With only the second character present the original stored 'A' and the merged line
! stored 'a'.
!
! *** THE CASE RULE CHANGES AT THE QUOTE, NOT AT THE STATEMENT. *** Comparing the whole thing
! as written the moment a quote appears anywhere would stop `F = 'a'` matching `f = 'a'`, which
! IS the same statement - a refusal, and an arbitrary one. So this walks the two together and
! switches rule at each quote: case-blind in the code, byte-for-byte inside the literal.
!
! The two run in step, so a quote in one and not the other fails at that character anyway -
! one side is a quote and the other is not, and nothing upper() does makes those equal.
!===============================================================================================
VitEngine.MgSameStmt Procedure(StringTheory pA, StringTheory pB)
a     StringTheory
b     StringTheory
j     long,auto
ca    string(1),auto
cb    string(1),auto
inLit byte
  code
  a.setValue(pA)
  a.trim()
  b.setValue(pB)
  b.trim()
  if a._DataEnd <> b._DataEnd then return 0.
  inLit = 0
  loop j = 1 to a._DataEnd
    ca = a.valuePtr[j]
    cb = b.valuePtr[j]
    if inLit
      if ca <> cb then return 0.               ! inside a literal, bytes are bytes
    else
      if upper(ca) <> upper(cb) then return 0. ! outside it, Clarion is case-blind
    end
    if ca = '''' then inLit = 1 - inLit.
  end
  return 1

!===============================================================================================
! ONE statement, and whether running it twice is the same as running it once. The target and
! the source come back in pOut/pRhs so the caller can check the parts against EACH OTHER.
!
! Deliberately strict - a refusal costs a merge, a wrong merge costs correct code:
!   * a plain `=` store, and nothing else. Compound assignment is out by definition: `n += 1`
!     run once where it ran twice is a different number.
!   * no '(' anywhere, so no call can hide on either side and be made to happen fewer times.
!   * the target must not appear on its own right, which is `x = x + 1` wearing another hat.
!===============================================================================================
VitEngine.MgOneStore Procedure(StringTheory pOne, StringTheory pLhs, StringTheory pRhs)
txt   StringTheory
lhs   StringTheory
rhs   StringTheory
eqP   long,auto
j     long,auto
c     string(1),auto
  code
  txt.setValue(pOne)
  txt.trim()
  if ~txt._DataEnd then return 0.                        ! an empty part - `f = 1 ;;` say
  if txt.findByte(40) then return 0.                     ! '(' - a call may hide either side
  eqP = txt.findByte(61)                                 ! '='
  if eqP < 2 then return 0.                              ! no '=', or nothing to assign to
  c = txt.valuePtr[eqP - 1]
  if c = '+' or c = '-' or c = '*' or c = '/' or c = '&' ! += -= *= /= &= are not repeatable
    return 0
  end
  if eqP < txt._DataEnd
    if txt.valuePtr[eqP + 1] = '=' then return 0.        ! '==' is a comparison, not a store
  end
  lhs.setValue(txt.valuePtr[1 : eqP - 1])
  lhs.trim()
  rhs.setValue(txt.valuePtr[eqP + 1 : txt._DataEnd])
  rhs.trim()
  if ~lhs._DataEnd or ~rhs._DataEnd then return 0.
  ! the target has to be a plain name - `f`, `grp.fld`, `pq:state`
  loop j = 1 to lhs._DataEnd
    c = lhs.valuePtr[j]
    if ~((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or |
         (c >= '0' and c <= '9') or c = '_' or c = '.' or c = ':')
      return 0
    end
  end
  ! `x = x + 1` reads its own target, so once is not the same as twice
  if instring(upper(lhs.getValue()), upper(rhs.getValue()), 1, 1) then return 0.
  pLhs.setValue(lhs) ! hand both back for the
  pRhs.setValue(rhs) !   cross-part check
  return 1

!===============================================================================================
! Make the alphabet fit to go inside containsA, or say it cannot.
!
! containsA CLIPS its argument, so a space at the END of the alphabet is simply not there at
! run time - the character would stop being tested and nothing would say so. Order carries no
! meaning in an alphabet, so a trailing space is moved to the FRONT rather than refusing a
! chain that is otherwise perfectly mergeable.
!
! An alphabet that is ALL spaces has nowhere to move it to. Clipped, it becomes the empty
! string, and `containsA('')` asks whether the receiver holds one of no characters. Returns 0
! (1 = usable, and pAlpha may have been reordered).
!===============================================================================================
VitEngine.MgAlphaFix Procedure(StringTheory pAlpha)
j   long,auto
sb  StringTheory
  code
  if ~pAlpha._DataEnd then return 0.
  loop j = 1 to pAlpha._DataEnd
    if pAlpha.valuePtr[j] <> ' ' then break.
  end
  if j > pAlpha._DataEnd then return 0. ! every byte is a space - nothing survives clip
  if pAlpha._DataEnd > 1 and pAlpha.valuePtr[pAlpha._DataEnd] = ' '
    sb.setValue(' ')
    sb.append(pAlpha.slice(1, pAlpha._DataEnd - 1))
    pAlpha.setValue(sb)
  end
  return 1

!===============================================================================================
! The alphabet, written as the body of a Clarion literal.
!
! Printable characters go in as themselves, with the quote, '<' and '{' doubled. A run of
! UNPRINTABLE bytes becomes ONE escape with the values comma-separated - <10,13>, not
! <10><13>. Both are legal and mean the same thing, but the comma form is the spelling the
! rest of this file already produces, and *** A FINAL BUILTIN HAS TO EMIT FINAL SPELLINGS. ***
! Running after the fixpoint, anything it writes that another rule would have tidied never
! gets tidied - so the file settled only on a SECOND run, and the round trip broke over
! nothing worse than a house-style difference.
!===============================================================================================
VitEngine.MgLitAlphabet Procedure(StringTheory pAlpha, StringTheory pOut)
j    long,auto
b    long,auto
opn  byte,auto               ! an escape group is open
  code
  opn = 0
  loop j = 1 to pAlpha._DataEnd
    b = val(pAlpha.valuePtr[j])
    if b < 32 or b > 126
      if opn
        pOut.append(',' & b) ! another value in the group already open
      else
        pOut.append('<' & b)
        opn = 1
      end
      cycle
    end
    if opn
      pOut.append('>')
      opn = 0
    end
    self.MgLitByte(b, pOut)
  end
  if opn then pOut.append('>').

!===============================================================================================
! One byte, written so a Clarion literal survives it.
!
! Three characters have to be doubled inside a literal - the quote, '<' (which opens the
! `<n>` escape) and '{' (which opens a repeat count) - and anything outside printable ASCII
! has to BE an escape, because writing the byte raw puts it in the source. A CR or an LF
! written raw physically splits the line in half, mid-literal, and the file will not compile.
!===============================================================================================
!===============================================================================================
! This line's trailing comment, whole, from '!' to the last thing on it.
!
! Read at flush time rather than copied into the queue when the line is staged. A queue row
! holding a fixed string would cut a longer comment to fit without a word about it, so the
! merged line would carry most of what the author wrote. A token index cannot overflow.
!===============================================================================================
VitEngine.MgCmtText Procedure(LONG pEolTok, StringTheory pOut)
p  long,auto
  code
  pOut.free()
  get(self.tk.tokens, pEolTok)
  if errorcode() or self.tk.tokens.strBefore &= NULL then return.
  p = instring('!', self.tk.tokens.strBefore, 1, 1)
  if ~p then return.
  pOut.setValue(self.tk.tokens.strBefore[p : size(self.tk.tokens.strBefore)])
  pOut.trim()            ! the field's trailing padding is not

!===============================================================================================
VitEngine.MgLitByte Procedure(LONG pB, StringTheory pOut)
c  string(1),auto
  code
  if pB < 32 or pB > 126 ! not printable - it must be an escape
    pOut.append('<' & pB & '>')
    return
  end
  c = chr(pB)
  case val(c)
  of 39                  ! <single quote>
    pOut.append('''''')  ! doubled, as in any Clarion literal
  of 60                  ! '<<'                                    ! THE ESCAPER NEEDS THE ESCAPING IT WRITES.
    pOut.append('<<<<')  !   '<<' in Clarion source IS one '<', so two
  of 123                 ! '{{'                                    !   of them take four here. A single '{' does
    pOut.append('{{{{')  !   not even compile - it opens a repeat count.
  else
    pOut.append(c)
  end

!===============================================================================================
VitEngine.MgAllDigits Procedure(STRING pTxt)
j  long,auto
n  long,auto
  code
  n = len(clip(pTxt))
  if ~n then return 0.
  loop j = 1 to n
    if pTxt[j] < '0' or pTxt[j] > '9' then return 0.
  end
  return 1

!===============================================================================================
! Is every call in pS..pE one that only READS?
!
! An OR-joined test short-circuits, so a condition that is not reached is not evaluated. That is
! only safe when evaluating it does nothing but answer. A '(' whose preceding token is a NAME is
! a call; one after an operator, a comma, or at the start of the span is grouping. The name has
! to be on the list, and the list is the one IfChainToCase uses, so a rule file's PURE(...)
! extends both at once.
!===============================================================================================
VitEngine.MgCondIsPure Procedure(LONG pS, LONG pE, StringTheory pPure)
j     long,auto
nmU   string(64)
c     string(1),auto
  code
  loop j = pS to pE
    get(self.tk.tokens, j)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL                                 or |
       size(self.tk.tokens.tok) <> 1 or self.tk.tokens.tok <> '(' or |
       j <= pS                        ! opens the span - grouping
      cycle
    end
    get(self.tk.tokens, j - 1)
    if errorcode() or self.tk.tokens.tok &= NULL then cycle.
    nmU = upper(self.tk.tokens.tok)
    if ~nmU then cycle.
    c = nmU[len(clip(nmU))]
    case val(c)                       ! a NAME immediately before '(' is a call
    of 65 to 90 orof 48 to 57 orof 95 ! 'A' to 'Z' orof '0' to '9' orof '_'
      if ~pPure.findChars(' ' & clip(nmU) & ' ') then return 0.
    end
  end
  return 1

!===============================================================================================
! The tokens pS..pE AS WRITTEN - each one's own leading trivia kept, except the first, whose
! trivia belongs to whatever came before it. MgSpanText normalises to one space, which is what
! you want for COMPARING two spans and not at all what you want for re-emitting one: it turns
! `p.findChar('z')` into `p . findChar ( 'z' )`.
!===============================================================================================
VitEngine.MgSpanRaw Procedure(LONG pS, LONG pE, StringTheory pOut)
j  long,auto
  code
  pOut.free()
  loop j = pS to pE
    get(self.tk.tokens, j)
    if errorcode() then break.
    if self.tk.tokens.tok &= NULL then cycle.
    if j > pS and not self.tk.tokens.strBefore &= NULL
      pOut.append(self.tk.tokens.strBefore)
    end
    pOut.append(self.tk.tokens.tok)
  end
