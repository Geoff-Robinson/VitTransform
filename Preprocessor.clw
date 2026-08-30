! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
! ===========================================================================
! Preprocessor.clw - INCLUDE / SECTION / ONCE expansion + .RED resolution
! SHARED by two projects - see the note in Preprocessor.inc. Written for the
! Clarion-to-C++ Transpiler; VitTransform links it for --thorough include
! expansion.
!
! Runs before the lexer. See Preprocessor.inc for the design summary. The whole
! algorithm was validated against a real Clarion .RED before being written here.
!
! Environment assumptions to confirm at first compile:
!   * EXISTS(path) is the standard Clarion file-existence built-in.
!   * Paths are native Windows backslash form (matching the .RED and the IDE).
!   * StringTheory.Split(',', '''', '''', true) is quote-aware with quote removal
!     (Clarion: '''' is one single-quote char; '"' would strip double quotes).
! ===========================================================================
  MEMBER         ! decoupled from the transpiler program for VitTransform (was MEMBER('Transpiler'))

  MAP
  end

  INCLUDE('Preprocessor.inc'), ONCE

! ---------------------------------------------------------------------------
preprocessor.Construct PROCEDURE()
dbg StringTheory ! trace-only local, not used for any real parsing
  code
  ! DELIBERATELY KEPT. This is the transpiler's build-provenance convention: it is how that
  ! project confirms which build of a module is actually running, and it has settled more
  ! than one wrong conclusion there. It goes to the DEBUG VIEWER, never to a file and never
  ! to the user - nothing is written to disk and nothing appears unless a viewer is attached.
  ! Do not delete it as a stray debug statement; this file is shared, and the transpiler
  ! relies on it. (Mind the length if you edit it - an over-long single-quoted Clarion
  ! literal stops the transpiler's emitter.)
  dbg.trace('[BUILDSIG] Preprocessor.clw - the OMIT/COMPILE terminator matches EXACTLY, as a string constant, ' & |
    'and a region left open at EOF is reported instead of silently swallowing the rest of the file')
  self.RedDirs         &= NEW RedDirQueue
  self.Seen            &= NEW StringTheory
  self.DepthErrReported &= NEW StringTheory
  self.ErrText         &= NEW StringTheory
  self.PPDefines       &= NEW StringTheory ! the equates OMIT/COMPILE conditions test

! ---------------------------------------------------------------------------
preprocessor.Destruct PROCEDURE()
  code
  if not self.RedDirs &= null
    free(self.RedDirs) ; DISPOSE(self.RedDirs)
  end
  if not self.Seen &= null then DISPOSE(self.Seen).
  if not self.DepthErrReported &= null then DISPOSE(self.DepthErrReported).
  if not self.ErrText &= null then DISPOSE(self.ErrText).
  if not self.PPDefines &= null then DISPOSE(self.PPDefines).

! ---------------------------------------------------------------------------
! Init - record the main file's directory (the '.' anchor), set macro values,
! and parse the .RED into the search table.
! ---------------------------------------------------------------------------
preprocessor.Init PROCEDURE(STRING pMainFilePath, string pRedFilePath, string pRootDir, string pConfig)
st StringTheory
  code
  self.MainFile = self.BaseName(pMainFilePath)
  self.ProjDir  = self.DirName(pMainFilePath)
  if ~self.ProjDir then self.ProjDir = '.'.
  self.RootDir  = pRootDir
  self.BinDir   = clip(pRootDir) & '\bin' ! %BIN% default = %ROOT%\bin
  self.Config   = choose(~pConfig, 'Debug', pConfig)
  free(self.RedDirs)
  st.setValue(pRedFilePath, st:clip)
  if st._dataEnd
    self.LoadRed(st, 0)
  end

! ---------------------------------------------------------------------------
! LoadRed - parse a .RED file into RedDirs (in priority order). Honours sections
! ([Common] and section-less lines are used for source includes; [Copy]/[Debug]/
! [Release] are skipped), '--' comments, %macros%, trailing '|' stop, quoted
! paths, and nested {include redfile} (priority: earlier lines win).
! ---------------------------------------------------------------------------
preprocessor.LoadRed PROCEDURE(StringTheory pRedPath, long pDepth)
red         StringTheory
ln          StringTheory
i           long,auto
j           long,auto
loc:section string(32)                                           !! cannot use section - reserved word
mask        string(64)
stop        byte,auto
eqPos       long,auto
p2          long,auto
  code
  if pDepth > PP:MaxDepth or ~pRedPath._dataEnd then return.
  if ~red.LoadFile(pRedPath.getValue()) then return.             ! missing .RED -> no entries
  red.lineEndings(st:Unix)                                       ! normalise CRLF/CR -> LF remove all <carriage return>
  red.Split('<10>',,,,st:clip,st:left)
  red.removeLines()                                              ! strip blank lines
!  loc:section = ''                                          ! pre-section region behaves like Common
  loop i = 1 to red.records()
    ln.SetValue(red.getLine(i))
    if ln.startsWith('--') then cycle.                           ! comment line
    if ln.valuePtr[1] = '['                                      ! [Section]
      loc:section = upper(ln.between('[',']'))
      cycle
    end
    if ln._dataEnd > 7 and upper(ln.valuePtr[1:8]) = '{{INCLUDE' ! nested red file
      p2 = ln.matchBrackets('{{','}')
      if p2
        ln.crop(9,p2-1)
        ln.trim()
        if ln._dataEnd
          self.NormalizeDir(ln)                                  ! resolve macros/relativity
          self.LoadRed(ln, pDepth + 1)
        end
      end
      cycle
    end
    if loc:section AND loc:section <> 'COMMON' then cycle.       ! [Copy]/[Debug]/[Release] not for source
    eqPos = ln.findByte(61)                                      ! '='
    if ~eqPos then cycle.
    if eqPos > 1
      mask = ln.valuePtr[1 : eqPos - 1]
      ln.removeFromPosition(1,eqPos)
      ln.trim()
    end
    ln.split(';','"','"',true,st:clip,st:left)
    loop j = 1 to ln.records()
      ln.setValueFromLine(j)
      ln.unquote('"','"')                                        ! drop quotes around spaced paths (if not already removed in split)
      ln.trim()
      if ~ln._dataEnd then cycle.
      if ln.endsWith('|')                                        ! trailing '|' -> stop marker
        stop = 1
        ln.adjustlength(-1)
        ln.clip()
      else
        stop = 0
      end
      self.NormalizeDir(ln)
      self.RedDirs.Seq  = records(self.RedDirs) + 1
      self.RedDirs.Mask = mask
      self.RedDirs.Dir  = ln.getValue()
      self.RedDirs.Stop = stop
      add(self.RedDirs)
    end
  end

! ---------------------------------------------------------------------------
! ExpandMacros - substitute the supported %MACRO% values (case-insensitive).
! Unknown macros are left intact (their directories simply won't exist).
! ---------------------------------------------------------------------------
preprocessor.ExpandMacros PROCEDURE(StringTheory s)
  code
  s.Replace('%ROOT%',          clip(self.RootDir), 0, 1, 0,st:nocase)
  s.Replace('%BIN%',           clip(self.BinDir),  0, 1, 0,st:nocase)
  s.Replace('%CONFIGURATION%', clip(self.Config),  0, 1, 0,st:nocase)
  s.trim() ! just in case

! ---------------------------------------------------------------------------
! NormalizeDir - expand macros, then resolve a RELATIVE directory against ProjDir.
!
! EVERY relative form resolves against the project, not against wherever the
! process happens to have been started. A leading '.' or '..' always did; a BARE
! relative name - `libsrc`, the commonest spelling in a real redirection file -
! fell through the early return untouched and was later resolved by the OS
! against the CWD. That is the same directory only when the tool is run from the
! project, which is how it survived: every gate here runs in the project
! directory. A user's build does not have to, and the failure is silent - the
! include is simply not found, or a DIFFERENT file of that name is.
!
! Absolute paths are left exactly as written, and so is an empty one.
! ---------------------------------------------------------------------------
preprocessor.NormalizeDir PROCEDURE(StringTheory pDir)
  code
  self.ExpandMacros(pDir)
  if ~pDir._dataEnd then return.
  if self.IsAbsolute(pDir.getValue()) then return.
  if pDir.valuePtr[1] <> '.'
    pDir.setValue(self.JoinPath(self.ProjDir, pDir.getValue()),st:Clip)
    return
  end

  if pDir._dataEnd = 1                               ! '.'
    pdir.setValue(self.ProjDir,st:Clip)
  elsif pDir._dataEnd = 2 and pdir.valuePtr[2] = '.' ! '..'
    pdir.setValue(self.DirName(self.ProjDir),st:Clip)
  else
    case val(pdir.valuePtr[2])
    of 92 orof 47                                    ! '\' orof '/'
      pdir.setValue(self.JoinPath(self.ProjDir, pDir.slice(3)),st:Clip)
    else
      case pDir.sub(2,2)
      of '.\' orof './'
        pdir.setValue(self.JoinPath(self.DirName(self.ProjDir), pDir.slice(4)),st:Clip)
      else
        pdir.setValue(self.JoinPath(self.ProjDir, pDir.getValue()),st:Clip)
      end
    end
  end
! A LEADING DOT DOES NOT MAKE A NAME RELATIVE-TO-HERE. `.private` and `..foo` are ordinary
!     directory names that happen to start with a dot, and every arm above is looking for the
!     NAVIGATION spellings - '.', '..', '.\x', './x', '..\x', '../x'. Without the ELSE above,
!     a name matching none of them left this procedure with pDir UNCHANGED and still relative,
!     and the OS then resolved it against the current directory instead of the project - so the
!     include was not found, or a DIFFERENT file of that name was, and nothing said a word.
!     The ELSE gives it the same treatment as any other relative name: joined to ProjDir, which
!     is exactly what the `pDir.valuePtr[1] <> '.'` arm at the top of this procedure does. The
!     dot was never the point; being relative was.

! ---------------------------------------------------------------------------
! ResolveFile - locate an INCLUDE'd file. Default extension .CLW. Absolute names
! are tried directly; everything else is tried alongside the INCLUDING file, then
! alongside the main source, then through the .RED search table in priority order.
! First existing file wins. Returns '' if not found.
! ---------------------------------------------------------------------------
preprocessor.ResolveFile PROCEDURE(STRING pName, <STRING pFromDir>)
nm    string(512),AUTO
base  string(256),AUTO
cand  string(512),AUTO
i     long,auto
  code
  nm = pName
  if ~self.HasExtension(nm) then nm = clip(nm) & '.CLW'.
  if self.IsAbsolute(nm)
    if EXISTS(clip(nm)) then return clip(nm).
    return ''
  end
  ! 1. Alongside the file that CONTAINS this INCLUDE. Real Clarion always checks
  !    here first, before consulting any redirection file, and this applies to a
  !    bare name ('ScopeManager.inc') exactly as much as a path-bearing one
  !    ('sub/ScopeManager.inc') - gate it on the name carrying a path separator
  !    and a plain sibling include is never found.
  !    pFromDir is the INCLUDING file's directory, passed down the ProcessText
  !    recursion. ProjDir alone was wrong for anything nested: it is set ONCE in Init
  !    from the MAIN source, so an include living in a subdirectory had ITS siblings
  !    looked for next to the main file, where they are not, and the run reported
  !    'INCLUDE not found' for a file sitting right beside the one asking for it.
  if ~omitted(pFromDir)
    cand = self.JoinPath(clip(pFromDir), nm)
    if EXISTS(clip(cand)) then return clip(cand).
  end
  ! 2. Alongside the MAIN source. For a top-level include this is the same lookup as
  !    (1) and costs one EXISTS; it stays because the main source's directory is a
  !    reasonable second guess for a file the including directory does not hold.
  cand = self.JoinPath(self.ProjDir, nm)
  if EXISTS(clip(cand)) then return clip(cand).
  ! 3. The .RED search table, by base name.
  ! fall through and try by base name through the search table (matches
  ! original behaviour for path-bearing names not found via ProjDir either)
  base = self.BaseName(nm)
  loop i = 1 to records(self.RedDirs)
    get(self.RedDirs, i)
    if ~self.MaskMatches(self.RedDirs.Mask, base) then cycle.
    cand = self.JoinPath(clip(self.RedDirs.Dir), base)
    if EXISTS(clip(cand)) then return clip(cand).
    if self.RedDirs.Stop then return ''. ! '|' stop: search no further
  end
  return ''

! ---------------------------------------------------------------------------
! MaskMatches - wildcard match of a .RED filemask ('*', '?') against a basename,
! case-insensitive.
! ---------------------------------------------------------------------------
preprocessor.MaskMatches PROCEDURE(STRING pMask, string pBase)
p     string(64)
t     string(256)
pi    long,AUTO
ti    long,auto
pn    long,AUTO
tn    long,AUTO
star  long,auto
mark  long,auto
  code
  p = upper(pMask)
  t = upper(pBase)
  pn = len(clip(p))
  tn = len(clip(t))
  pi = 1 ; ti = 1 ; star = 0 ; mark = 0
  loop while ti <= tn
    if pi <= pn AND (p[pi] = '?' OR p[pi] = t[ti])
      pi += 1 ; ti += 1
    elsif pi <= pn AND p[pi] = '*'
      star = pi ; mark = ti ; pi += 1
    elsif star
      pi = star + 1 ; mark += 1 ; ti = mark
    else
      return 0
    end
  end
  loop while pi <= pn AND p[pi] = '*'
    pi += 1
  end
  return choose(pi > pn)

! ---------------------------------------------------------------------------
! Process - expand pMainSource into pExpandedOut, filling pLineMap. Returns the
! number of preprocessor errors (missing include / nested-too-deep).
! ---------------------------------------------------------------------------
preprocessor.Process PROCEDURE(*StringTheory pMainSource, *StringTheory pExpandedOut, *LineMapQueue pLineMap)
  code
  self.Out      &= pExpandedOut
  self.LineMap  &= pLineMap
  self.Out._dataEnd = 0
  free(self.LineMap)
  self.Seen._dataEnd      = 0
  self.DepthErrReported._dataEnd = 0
  self.ErrText._dataEnd   = 0
  ! Compile-time-equate state must not survive a Process
  ! call: PPDefines carried one file's equates into every later file's
  ! OMIT/COMPILE conditions. (OMIT/COMPILE region state needs no reset here -
  ! it is a LOCAL stack in ProcessText, so it cannot outlive its file.)
  if not self.PPDefines &= null then self.PPDefines._dataEnd = 0.
  self.ProcessText(pMainSource, clip(self.MainFile), 0)
  return self.ErrText.Count('<13,10>')

! ---------------------------------------------------------------------------
! ProcessText - the recursive workhorse. Walks the source line by line, emits
! non-directive lines (with their origin), and splices resolved INCLUDEs.
! ---------------------------------------------------------------------------
preprocessor.ProcessText PROCEDURE(*StringTheory pSrc, string pFileLabel, long pDepth, LONG pLineOfs=0, <STRING pFileDir>)
work      StringTheory
body      StringTheory
chosen    StringTheory
tl        StringTheory
i         long,auto
nLines    long,AUTO
myDir     string(512)      ! the directory of the file whose text THIS call is walking -
incDir    string(512),auto !       a bare sibling INCLUDE in it resolves here first, as Clarion does
RegionQ   QUEUE,PRE(rgq)   ! OMIT/COMPILE regions, innermost last. A LOCAL, so each
Term        string(64)     !   file's regions die with its call frame - the call stack
Sup         byte           !   IS the region stack, and an unterminated region in an
          END              !   include cannot leak into the file that included it
rgTerm    string(64)       ! CheckOmitCompile out-params
rgSup     byte
fileName  string(512)
secName   string(256)
onceFlag  byte
resolved  string(512),auto
keyStr    string(800),auto
secOfs    long,auto        ! section start line in the included file
  code
  ! the top-level call is the main source, whose directory IS ProjDir; every recursive
  ! call is handed the directory of the file it is about to walk. Carried as a parameter, not a
  ! member, for the same reason RegionQ is a local: the call stack already models the nesting,
  ! and there is nothing to save or restore on the way back up.
  if omitted(pFileDir)
    myDir = self.ProjDir
  else
    myDir = pFileDir
  end
  if ~myDir then myDir = self.ProjDir.
  work.SetValue(pSrc)
  work.lineEndings(st:Unix)
  work.Split('<10>')
  nLines = work.records()
  loop i = 1 to nLines
    tl.SetValue(work.getLine(i))
    tl.Trim()
    ! Conditional compilation (LangRef pp.63-69).
    ! Inside an active region every line is checked for the INNERMOST region's
    ! terminator string (it commonly sits inside a comment, e.g. '!***' closing
    ! a COMPILE('***',UnitTests) block); the terminator line itself is always
    ! consumed. Suppressed-region lines are dropped, and a directive inside a
    ! SUPPRESSED region is inert - the LangRef allows nesting only "if parsing
    ! is continuing", so the first terminator ends a suppressed region.
    ! Pass-through-region lines flow on to normal processing, WHICH INCLUDES
    ! the directive check below: parsing is continuing there, so an inner
    ! OMIT/COMPILE opens a NESTED region (the LangRef's own worked example -
    ! the DEBUGGER::BUTTONLIST idiom in Clarion's libsrc - nests a COMPILE
    ! inside a COMPILE; treating the inner directive as text leaked both its
    ! line and its suppressed block into the expanded stream). EQUATE lines
    ! are tracked so guard-style conditions (the equate defined inside the
    ! guarded region) evaluate correctly.
    if records(RegionQ)
      get(RegionQ, records(RegionQ)) ! innermost region governs
      ! the terminator is matched EXACTLY. The LRM (p67/p3495) says the block "ends with
      ! the line that contains the same STRING CONSTANT as the terminator" - and a string
      ! constant's content is case-significant. A caseless compare ends the block EARLY on a
      ! line that merely differs in case, which leaks source the author omitted back into the
      ! stream as live code. Same failure direction as an OMIT that ends on its own directive
      ! line, and the same reason to be strict about it.
      if tl.findChars(clip(rgq:Term)) > 0
        delete(RegionQ)
        cycle
      end
      if rgq:Sup then cycle.
    end
    if self.CheckOmitCompile(tl, rgTerm, rgSup)
      clear(RegionQ)
      rgq:Term = rgTerm
      rgq:Sup  = rgSup
      add(RegionQ)
      cycle
    end
    self.TrackEquate(tl)
    !if ~t1._dataEnd or tl.valuePtr[1] = '!' or tl.valuePtr[1] = '|' then cycle. ! blank or comment or continuation
    if tl._dataEnd < 7 or upper(tl.valuePtr[1 : 7]) <> 'INCLUDE' or ~self.ParseDirective(tl, fileName, secName, onceFlag)
      self.EmitLine(work.getLine(i), pFileLabel, i + pLineOfs)
      cycle
    end
    ! ---- it is an INCLUDE directive ----
    resolved = self.ResolveFile(fileName, myDir)
    if ~resolved
      self.ErrText.Append('INCLUDE not found: ' & clip(fileName) & |
                          ' (' & clip(pFileLabel) & ' line ' & i & ')<13,10>')
      self.EmitLine('! #error INCLUDE not found: ' & clip(fileName), pFileLabel, i + pLineOfs)
      cycle
    end
    keyStr = self.SeenKey(resolved)
    ! ONCE is FILENAME-wide, exactly as the LangRef states: "ONCE is applied on
    ! the entire filename, so subsequent uses of INCLUDE(filename, section) will
    ! be ignored." So the key is the resolved path ALONE - a ,ONCE include is
    ! skipped when the file was already included in ANY form, sectioned or
    ! whole. (An earlier cut keyed sections separately, so a second section of
    ! an already-included file spliced again under ONCE - declarations the real
    ! compiler would never see twice reached the type registry twice.) ONCE
    ! stays an attribute of THIS directive: a plain re-INCLUDE splices again.
    if onceFlag AND self.Seen.FindChars(CLIP(keyStr))
      cycle
    end
    if pDepth + 1 > PP:MaxDepth
      ! Report this specific file's "nested too
      ! deep" error only once, not once per including file. Deliberately NOT
      ! folded into Seen/OnceGuard (which would also suppress the *include
      ! itself* on any later, possibly-shallower attempt from a different
      ! path) - this only silences repeat error TEXT for a file whose
      ! shallowest attempt has already failed; the cycle/skip behaviour below
      ! is completely unchanged either way.
      if not self.DepthErrReported.FindChars(CLIP(keyStr))
        self.ErrText.Append('INCLUDE nested too deep (>' & PP:MaxDepth & '): ' & |
                            clip(fileName) & '<13,10>')
        self.EmitLine('! #error INCLUDE nested too deep: ' & clip(fileName), pFileLabel, i + pLineOfs)
        self.DepthErrReported.Append(CLIP(keyStr))
      end
      cycle
    end
    if ~body.LoadFile(clip(resolved))
      self.ErrText.Append('INCLUDE unreadable: ' & clip(resolved) & '<13,10>')
      self.EmitLine('! #error INCLUDE unreadable: ' & clip(fileName), pFileLabel, i + pLineOfs)
      cycle
    end
    secOfs = 0
    if secName
      self.ExtractSection(body, secName, chosen, secOfs) ! named section only
      if ~secOfs                                         ! say so: a typo'd section otherwise includes NOTHING, silently
        self.ErrText.Append('SECTION not found: ' & clip(secName) & ' in ' & clip(resolved) & |
                            ' (' & clip(pFileLabel) & ' line ' & i + pLineOfs & ')<13,10>')
        self.EmitLine('! #error SECTION not found: ' & clip(secName), pFileLabel, i + pLineOfs)
        cycle
      end
    else
      self.StripSections(body, chosen)                   ! whole file, SECTION lines blanked (line count preserved for the map)
    end
    self.Seen.Append(CLIP(keyStr))
    ! OMIT/COMPILE region state is per FILE, not global:
    ! an INCLUDE spliced inside an active pass-through region must not run
    ! against the OUTER region's terminator. RegionQ is a LOCAL, so the
    ! recursion below gets its own empty stack and this file's regions are
    ! untouched when it returns - the call stack IS the region stack, with
    ! nothing to save or restore.
    incDir = self.DirName(resolved)                      ! what THAT file's own bare includes resolve against
    if ~incDir then incDir = myDir.                      !       (a name found with no path at all keeps this file's)
    self.ProcessText(chosen, self.BaseName(resolved), pDepth + 1, secOfs, incDir)
  end
  ! a region still open at end of file SUPPRESSED everything from its directive to EOF
  ! (or leaked a pass-through one), and said nothing at all. A missing terminator is a source
  ! defect and the reader needs to be told which one, in which file.
  loop while records(RegionQ)
    get(RegionQ, records(RegionQ))
    self.ErrText.Append('OMIT/COMPILE region never terminated: "' & clip(rgq:Term) & |
                        '" (' & clip(pFileLabel) & ') - '                          & |
                        choose(rgq:Sup = 1, 'everything to end of file was OMITTED', |
                                            'the region ran to end of file') & '<13,10>')
    delete(RegionQ)
  end

! ---------------------------------------------------------------------------
! CheckOmitCompile - OMIT('term'[,cond]) / COMPILE('term'[,cond]) region opener.
! OMIT suppresses its block when cond is true (or
! absent); COMPILE keeps its block when cond is true (or absent) and
! suppresses it otherwise. Undefined equates evaluate to 0. Returns TRUE when
! the line was a directive (the caller drops it either way) and fills the
! region's terminator + suppress flag; the CALLER pushes it onto its region
! stack, which is what lets regions nest where the LangRef allows.
! ---------------------------------------------------------------------------
preprocessor.CheckOmitCompile PROCEDURE(StringTheory pTrimmed, *STRING pTerm, *BYTE pSuppress)
s        string(512)
u        string(512)
term     string(64),AUTO
cond     string(128),AUTO
isOmit   byte
condVal  byte,AUTO
p        long
p1       long,AUTO
p2       long,AUTO
pc       long,AUTO
pr       long,AUTO
  code
  s = pTrimmed.getValue()
  u = upper(s)
  if u[1 : 5] = 'OMIT('  OR u[1 : 5] = 'OMIT '
    isOmit = true
    p = 5
  elsif u[1 : 8] = 'COMPILE(' OR u[1 : 8] = 'COMPILE '
    isOmit = false
    p = 8
  else
    return false
  end
  loop while p <= len(clip(u)) AND u[p] = ' '
    p += 1
  end
  if p > len(clip(u)) OR u[p] <> '(' then return false.
  p1 = instring('''', s, 1, p)
  if ~p1 then return false.
  p2 = instring('''', s, 1, p1 + 1)
  if p2 <= p1 + 1 then return false.
  term = s[p1+1 : p2-1]
  pc = instring(',', s, 1, p2 + 1)
  pr = instring(')', s, 1, p2 + 1)
  if pc > 0 AND (pr = 0 OR pc < pr) AND pr > pc + 1
    cond = s[pc+1 : pr-1]
    condVal = self.EvalPPCondition(cond)
  else
    condVal = true
  end
  pTerm     = term
  pSuppress = choose(isOmit = true, condVal, 1 - condVal)
  return true

! ---------------------------------------------------------------------------
! EvalPPCondition - 'NAME' -> defined and non-zero; 'NAME=value' -> equality
! against the tracked EQUATE registry; undefined names evaluate to 0.
! ---------------------------------------------------------------------------
preprocessor.EvalPPCondition PROCEDURE(STRING pCond)
c    StringTheory
nm   string(64),AUTO
vl   string(64),AUTO
defv string(64),AUTO
p    long,AUTO
q    long,AUTO
  code
  c.SetValue(upper(pCond))
  c.Trim()
  if c._dataEnd < 1 then return true.
  p = c.findByte(61) ! '='
  if p > 1
    nm = left(c.sub(1, p - 1))
    vl = left(c.slice(p + 1))
  else
    nm = left(c.getValue())
    vl = ''
  end
  p = instring('|' & clip(nm) & '=', upper(self.PPDefines.getValue()), 1, 1)
  if ~p
    defv = '0'
  else
    p += len(clip(nm)) + 2
    q = instring('|', self.PPDefines.getValue(), 1, p)
    if ~q then q = self.PPDefines._dataEnd + 1.
    defv = self.PPDefines.sub(p, q - p)
  end
  if vl
    return choose(left(defv) = left(vl))
  end
  return choose(left(defv) <> '0' AND defv)

! ---------------------------------------------------------------------------
! TrackEquate - record 'Label EQUATE(value)' lines so OMIT/COMPILE conditions
! can test them (include-guard idiom: the guard equate is defined INSIDE the
! guarded region of the first pass). First definition wins.
! ---------------------------------------------------------------------------
preprocessor.TrackEquate PROCEDURE(StringTheory pTrimmed)
u    StringTheory
nm   string(64),AUTO
vl   string(64),AUTO
p    long,AUTO
q    long,AUTO
r    long,AUTO
  code
  u.SetValue(upper(pTrimmed.getValue()))
  p = u.findChars(' EQUATE')
  if ~p then p = u.findChars('<9>EQUATE').
  if p < 2 then return.
  nm = left(u.sub(1, p - 1))
  if instring(' ', clip(nm), 1, 1) > 0 then return.
  ! Prefixed labels (ST:Debug) are LEGAL equates and pervasive in COMPILE/OMIT conditions, so
  ! rejecting a name for holding one drops whole COMPILE regions. Only a LEADING colon is invalid.
  if nm[1] = ':' then return.
  q = u.findByte(40, p)   ! '('
  if ~q
    vl = '1'
  else
    r = u.findByte(41, q) ! ')'
    if r <= q + 1 then return.
    vl = left(u.sub(q + 1, r - q - 1))
  end
  if instring('|' & clip(nm) & '=', upper(self.PPDefines.getValue()), 1, 1) > 0 then return.
  self.PPDefines.Append('|' & clip(nm) & '=' & clip(vl))

! ---------------------------------------------------------------------------
! ParseDirective - is pLine an INCLUDE directive? If so fill file/section/once.
! A directive must START the line (after trimming); INCLUDE text inside a string
! or after other code is not a directive. Quote-aware arg split handles both the
! 1-arg INCLUDE('f') and 2-arg INCLUDE('f','sect') forms.
! ---------------------------------------------------------------------------
preprocessor.ParseDirective PROCEDURE(StringTheory ln, *STRING pFile, *STRING pSection, *BYTE pOnce)
args    StringTheory
p1      long,AUTO
p2      long,AUTO
cpos    long,AUTO      ! position of a trailing '!', so ONCE is never read out of a comment
  code
  pFile = '' ; pSection = '' ; pOnce = 0
  p1 = ln.findByte(40) ! '('
  if ~p1 or |
     ln.Sub(8, p1 - 8) ! between INCLUDE and '(' must be blank
    return 0
  end
  ! the MATCHING ')', not the first one. The case that makes this a real
  ! bug rather than a tidy-up is the commonest path on Windows -
  !     INCLUDE('C:\Program Files (x86)\...\thing.inc')
  ! where FindChar returns the ')' of '(x86)': the filename came back truncated, the
  ! include silently did not resolve, and the ONCE scan below started INSIDE the path
  ! (so a directory containing the letters "once" would have set pOnce too).
  ! MatchBrackets counts depth, so a BALANCED pair inside the quotes cancels out and it
  ! lands on the real close. It is not quote-aware - `INCLUDE('a).inc')` still defeats
  ! it - but that needs a quote-aware scan and is a far rarer shape than a program-files
  ! path. Documented rather than fixed, deliberately.
  p2 = ln.MatchBrackets('(', ')', p1)
  if ~p2 or |
     p2 <= p1 + 1                                   ! `INCLUDE()` - nothing to parse
    return 0
  end
  ! ONE SCAN, ONE ANSWER. This used to be a second, independent ln.between('(',')'),
  ! which finds its right delimiter with a plain search (StringTheory.FindBetweenPosition)
  ! - so it had the identical defect and could disagree with p2. Slice between the
  ! brackets we already matched instead.
  args.SetValue(ln.Slice(p1 + 1, p2 - 1))           ! arg list inside the parens (L: Slice takes the two
                                                    !   positions we already hold, so no length arithmetic)
  args.Split(',', '''', '''', true,st:clip,st:left) ! quote-aware, strip quotes; clip+left so ' <39>Sect<39>' unquotes too
  if ~args.records() then return 0.
  pFile = args.getLine(1)
  if args.records() > 1 then pSection = args.getLine(2).
  ! CHOOSE(expr, val1, val2) treats a positive-integer expr as a 1-based INDEX into the
  ! value list, not a boolean (confirmed against Clarion's own docs). INSTRING()
  ! returns a POSITION, so `choose(instringResult, 1, 0)` returns 1 only when the match
  ! happens to land at position 1 - which is why onceFlag came out false almost always and
  ! ONCE deduplicated nothing. The single-argument CHOOSE(expr) is the real boolean-to-0/1
  ! converter: use it, or an explicit `expr <> 0`, whenever the condition is not already
  ! guaranteed to be exactly 0 or 1.
  cpos = ln.findByte(33, p2 + 1)                    ! bound the ONCE search at a trailing comment '!'
  if cpos
    pOnce = choose(ln.Instring('ONCE', 1, p2 + 1, cpos - 1, st:nocase))
  else
    pOnce = choose(ln.Instring('ONCE', 1, p2 + 1, 0, st:nocase))
  end
  return 1

! ---------------------------------------------------------------------------
! ExtractSection - return only the named SECTION's body (from SECTION('name') to
! the next SECTION or EOF). SECTION directive lines themselves are not emitted.
! ---------------------------------------------------------------------------
preprocessor.ExtractSection PROCEDURE(*StringTheory pBody, string pSection, *StringTheory pResult, *LONG pStartLine)
bw    StringTheory
tl    StringTheory
i     long
cap   byte
  code
  pStartLine = 0
  pResult._dataEnd = 0
  bw.SetValue(pBody)
  bw.lineEndings(st:Unix)
  bw.Split('<10>')
  loop i = 1 to bw.records()
    tl.SetValue(bw.getLine(i)) ; tl.Trim()
    if self.IsSectionLine(tl)                                                                          ! the word SECTION then a '(' - a label merely STARTING
      tl.SetBetween('(',')',,,,,true)                                                                  !   'Section' (SectionSize EQUATE(100)) is BODY, and the
      tl.unquote('''', '''')                                                                           !   7-char prefix test used to end the capture there,
      cap = choose(upper(choose(tl._DataEnd < 1, '', tl.valuePtr[1 : tl._DataEnd])) = upper(pSection)) ! silently truncating the section
      if cap and ~pStartLine then pStartLine = i.                                                      ! the section body starts at line i+1 of the included file
      cycle                                                                                            ! never emit the SECTION line
    end
    if cap
      pResult.Append(bw.getLine(i))                                                                    ! original line, untrimmed
      pResult.Append('<13,10>')
    end
  end

! ---------------------------------------------------------------------------
! StripSections - return the whole body with any SECTION directive lines removed
! (they delimit but produce no code when a file is included wholesale).
! ---------------------------------------------------------------------------
preprocessor.StripSections PROCEDURE(*StringTheory pBody, *StringTheory pResult)
bw    StringTheory
tl    StringTheory
i     long,auto
  code
  pResult._dataEnd = 0
  bw.SetValue(pBody)
  bw.lineEndings(st:Unix)
  bw.Split('<10>')
  loop i = 1 to bw.records()
    tl.SetValue(bw.getLine(i)) ; tl.Trim()
    if self.IsSectionLine(tl)   ! the containsChar('(') form still blanked a label
      pResult.Append('<13,10>') !   like SectionSize EQUATE(100). BLANK the marker
      cycle                     !   line (deleting it shifted every later line's map entry)
    end
    pResult.Append(bw.getLine(i))
    pResult.Append('<13,10>')
  end

! ---------------------------------------------------------------------------
! IsSectionLine - a real SECTION('name') directive: the word SECTION, optional
! spaces, then '('. Mirrors CheckOmitCompile's OMIT/COMPILE test. A column-1
! label that merely STARTS with the letters (SectionSize, SectionNo) is code.
! ---------------------------------------------------------------------------
preprocessor.IsSectionLine PROCEDURE(StringTheory pTrimmed)
u    string(512)
p    long,AUTO
  code
  u = upper(pTrimmed.getValue())
  if u[1 : 8] = 'SECTION(' then return 1.
  if u[1 : 8] <> 'SECTION ' then return 0.
  p = 9
  loop while p <= len(clip(u)) AND u[p] = ' '
    p += 1
  end
  return choose(p <= len(clip(u)) AND u[p] = '(')

! ---------------------------------------------------------------------------
! EmitLine - append one physical line to the expanded output and record its
! origin (file + original line) in the line map (1:1 with the output lines).
! ---------------------------------------------------------------------------
preprocessor.EmitLine PROCEDURE(STRING pLine, string pFileLabel, long pOrigLine)
  code
  self.Out.Append(pLine)
  self.Out.Append('<13,10>')
  self.LineMap.FileName = pFileLabel
  self.LineMap.OrigLine = pOrigLine
  add(self.LineMap)

! ---------------------------------------------------------------------------
preprocessor.SeenKey PROCEDURE(STRING pResolved)
  code
  return '|' & lower(clip(pResolved)) & '|'

! ---------------------------------------------------------------------------
preprocessor.HadErrors PROCEDURE()
  code
  return choose(self.ErrText._dataEnd > 0)

! ---------------------------------------------------------------------------
preprocessor.getErrors PROCEDURE()
  code
  ! GetValuePtr returns a NULL &string when empty.
  if self.ErrText._dataEnd < 1 then return ''.
  return self.ErrText.getValuePtr()

! ---------------------------------------------------------------------------
! Path helpers (native backslash; '/' tolerated on input).
! ---------------------------------------------------------------------------
preprocessor.DirName PROCEDURE(STRING pPath)
s     string(512)
i     long,auto
  code
  s = pPath
  loop i = len(clip(s)) to 1 by -1
    if s[i] = '\' OR s[i] = '/' then return sub(s, 1, i - 1).
  end
  return ''

preprocessor.BaseName PROCEDURE(STRING pPath)
s     string(512)
i     long,auto
  code
  s = pPath
  loop i = len(clip(s)) to 1 by -1
    if s[i] = '\' OR s[i] = '/' then return sub(s, i + 1, len(clip(s)) - i).
  end
  return clip(s)

preprocessor.HasExtension PROCEDURE(STRING pName)
b     string(256)
i     long,auto
  code
  b = self.BaseName(pName)
  loop i = len(clip(b)) to 1 by -1
    if b[i] = '.' then return 1.
  end
  return 0

preprocessor.IsAbsolute PROCEDURE(STRING pName)
s     string(512)
  code
  s = pName
  if len(clip(s)) >= 2 AND s[2] = ':' then return 1. ! drive letter
  if len(clip(s)) >= 1 AND (s[1] = '\' OR s[1] = '/') then return 1.
  return 0

preprocessor.JoinPath PROCEDURE(STRING pDir, string pName)
d     string(512)
  code
  d = pDir
  if ~d then return clip(pName).
  if d[len(clip(d))] = '\' OR d[len(clip(d))] = '/'
    return clip(d) & clip(pName)
  end
  return clip(d) & '\' & clip(pName)
