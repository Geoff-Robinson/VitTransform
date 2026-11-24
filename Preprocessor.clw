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
! algorithm follows the way Clarion itself reads a real .RED.
!
! Facts this file relies on:
!   * EXISTS(path) is the standard Clarion file-existence built-in.
!   * Paths are native Windows backslash form (matching the .RED and the IDE).
!   * StringTheory.Split(',', '''', '''', true) is quote-aware with quote removal
!     (Clarion: '''' is one single-quote char; '"' would strip double quotes).
! ===========================================================================
  MEMBER ! a MEMBER of no program: VitTransform and the Clarion-to-C++ transpiler both link this file

  MAP
  end

  INCLUDE('Preprocessor.inc'), ONCE

! ---------------------------------------------------------------------------
preprocessor.Construct PROCEDURE()
dbg StringTheory ! trace-only local, not used for any real parsing
  code
  ! DELIBERATELY KEPT. This is the transpiler's build-provenance convention: it is how that
  ! project confirms which build of a module is actually running, so a stale build shows
  ! up at once. It goes to the DEBUG VIEWER, never to a file and never
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
  self.SeedDefines     &= NEW StringTheory ! the project flags PPDefines is reset to per file

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
  if not self.SeedDefines &= null then DISPOSE(self.SeedDefines).

! ---------------------------------------------------------------------------
! Init - record the main file's directory (the '.' anchor), set macro values,
! and parse the .RED into the search table.
! ---------------------------------------------------------------------------
preprocessor.Init PROCEDURE(STRING pMainFilePath, string pRedFilePath, string pRootDir, string pConfig, <STRING pDefines>)
st StringTheory
  code
  self.MainFile = self.BaseName(pMainFilePath)
  self.ProjDir  = self.DirName(pMainFilePath)
  if ~self.ProjDir then self.ProjDir = '.'.
  self.RootDir  = pRootDir
  self.BinDir   = clip(pRootDir) & '\bin'              ! %BIN% default = %ROOT%\bin
  self.Config   = choose(~pConfig, 'Release', pConfig) ! Release, as everything else documents; the CLI already passes it
  free(self.RedDirs)
  self.ErrText._dataEnd = 0                            ! the diagnostics start HERE, not at Process: what LoadRed
  self.RedVer = 0                                      !   has to say about a redirection file is the reason every
  st.setValue(pRedFilePath, st:clip)                   !   include after it comes back "not found"
  if st._dataEnd
    self.LoadRed(st, 0)
  end
  self.ErrBase = self.ErrText._dataEnd                 ! Process rewinds to here rather than to zero, so they survive
  if omitted(pDefines)
    self.SeedProjectFlags(clip(pRedFilePath), '')
  else
    self.SeedProjectFlags(clip(pRedFilePath), clip(pDefines))
  end


! ---------------------------------------------------------------------------
! SeedProjectFlags - build SeedDefines: the Clarion version flags the .red file
! name implies (Clarion110.red -> version 110), CUMULATIVE - a _Cnn_ flag is 1
! exactly when the compiler version is at least that, so every release token up
! to and including the .red's version is set to 1 and every later one is left 0
! (_C111_ stays 0 on an 11.0 build) - plus each flag named on --define=. Both
! the _Cnn_ and the legacy _VER_Cnn spellings are seeded, and the short major
! _Cn_ (e.g. _C11_). PPDefines is reset to SeedDefines before every file, so
! these answer OMIT/COMPILE conditions the way the compiler's own built-ins do.
! A PROJECT redirection file carries no version in its own name and chains to the
! release file; when the name it was given says nothing, the version comes from the
! highest any file in that chain implies, so the flags still answer correctly.
! _WIDTH32_ is 1 from Clarion 6 on, which builds 32-bit only. The other config-dependent flags
! (_Unicode_, _ABCDllMode_ ...) are not version-ordered and are not inferred; name them on
! --define= when a build sets them. A name given on --define= answers before any flag seeded
! here, so --define=_WIDTH32_=0 turns that one off.
! ---------------------------------------------------------------------------
preprocessor.SeedProjectFlags PROCEDURE(STRING pRedFilePath, STRING pDefines)
tok    STRING(12),AUTO
nm     STRING(160),AUTO
ver    LONG,AUTO
maj    LONG,AUTO
i      LONG,AUTO
relSt  StringTheory
dc     StringTheory
  code
  self.SeedDefines._dataEnd = 0
  ! --- the --define= names FIRST, each NAME (=> 1) or NAME=value. A flag is looked up by its first
  !     entry, so a name given here answers before any flag seeded below: --define=_WIDTH32_=0
  !     turns the seeded one off ---
  if pDefines
    dc.setValue(pDefines)
    dc.split(',')
    loop i = 1 to dc.records()
      nm = upper(left(dc.getLine(i)))
      if ~nm then cycle.
      if relSt.findByte(61, 1,, nm)            ! '='
        self.SeedDefines.append('|' & clip(nm))
      else
        self.SeedDefines.append('|' & clip(nm) & '=1')
      end
    end
  end
  ! --- version from the .red basename: the digit run just before '.RED' ---
  ver = self.RedVersion(pRedFilePath)          ! a PROJECT redirection file carries no version in its own name, and
  if ~ver then ver = self.RedVer.              !   chaining to the release file is the shape the shipped ones use -
                                               !   take the version from the chain rather than seed nothing at all,
                                               !   which leaves every version-guarded region answering the wrong way
  maj = ver / 10                               ! 110 -> 11, 60 -> 6, 55 -> 5 (a REAL stored in a LONG truncates)
  ! --- the release build-numbers, cumulative: a token <= ver gets its flag ---
  relSt.setValue('50 55 60 61 62 63 70 71 72 73 80 90 91 100 110 111 120 130')
  relSt.split(' ')
  loop i = 1 to relSt.records()
    tok = relSt.getLine(i)
    if ~tok then cycle.
    if tok > ver then cycle.
    self.SeedDefines.append('|_C' & clip(tok) & '_=1')
    self.SeedDefines.append('|_VER_C' & clip(tok) & '=1')
  end
  loop i = 5 to maj                             ! the short major spelling, _C11_ and the like
    self.SeedDefines.append('|_C' & i & '_=1')
  end
  ! Clarion 6 on builds 32-bit only
  if ver >= 60 then self.SeedDefines.append('|_WIDTH32_=1').
! ---------------------------------------------------------------------------
! LoadedEmpty - did LoadFile fail only because the file holds nothing? An empty include or
! redirection file is empty, not unreadable (ruled 30 Oct 2026). StringTheory 3.90 sets
! winErrorCode to 0 for a file of zero bytes and to the Windows error when it cannot open one -
! but to 0 as well when the name is blank or the file is not there, so EXISTS tells those apart.
! 1 = it is there and empty, and pSt is left empty too.
! ---------------------------------------------------------------------------
preprocessor.LoadedEmpty PROCEDURE(StringTheory pSt, STRING pPath)
  code
  if pSt.winErrorCode or ~exists(clip(pPath)) then return 0.
  pSt.free()
  return 1

! ---------------------------------------------------------------------------
! RedVersion - the Clarion version a redirection file NAME implies: the run of
! digits immediately before '.RED' in its base name. 'Clarion110.red' gives 110
! and 'MyApp.red' gives 0, because there is nothing in that name to read.
! A SINGLE digit is a whole version, as it is in a Clarion folder's name:
! 'Clarion9.red' is Clarion 9, so it gives 90, the number the release flags are
! counted in. Read as 9 it would be below every release, and set no flag at all.
! ---------------------------------------------------------------------------
preprocessor.RedVersion PROCEDURE(STRING pRedFilePath)
base   STRING(260),AUTO
ver    LONG,AUTO
p1     LONG,AUTO
p2     LONG,AUTO
relSt  StringTheory
  code
  base = upper(self.BaseName(pRedFilePath))
  p2 = relSt.findChars('.RED', 1,, base)
  if ~p2 then p2 = len(clip(base)) + 1.
  p2 -= 1                                      ! last char before '.RED'
  p1 = p2
  loop while p1 >= 1 and base[p1] >= '0' and base[p1] <= '9'
    p1 -= 1
  end
  p1 += 1
  ver = 0
  if p1 <= p2 then ver = base[p1 : p2].        ! 'CLARION110' -> 110
  if p1 = p2 then ver *= 10.
  return ver

! ---------------------------------------------------------------------------
! LoadRed - parse a .RED file into RedDirs (in priority order). Honours sections
! ([Common], section-less lines and the section for the configuration being
! built are used for source includes; the others are skipped), '--' comments,
! %macros%, trailing '|' stop, quoted paths, and nested {include redfile}
! (priority: earlier lines win).
! ---------------------------------------------------------------------------
preprocessor.LoadRed PROCEDURE(StringTheory pRedPath, long pDepth)
red         StringTheory
ln          StringTheory
i           long,auto
j           long,auto
loc:section string(32) !! cannot use section - reserved word
mask        string(64),auto
stop        byte,auto
eqPos       long,auto
p2          long,auto
vNow        long,auto
rawRed      string(512),auto
cfg         string(32),auto
  code
  if pDepth > PP:MaxDepth or ~pRedPath._dataEnd then return.
  if ~red.LoadFile(pRedPath.getValue()) and ~self.LoadedEmpty(red, pRedPath.getValue()) ! missing .RED -> no entries, and SAID: a chained file that never
    self.ErrText.Append('RED not found: ' & clip(pRedPath.getValue()) & '<13,10>')
    return                                                                              !   loaded is why every include after it is "not found"
  end
  vNow = self.RedVersion(pRedPath.getValue())                                           ! the version THIS name implies - a project .red has
  if vNow > self.RedVer then self.RedVer = vNow.                                        !   none, and the file it chains to is where it is
  do SetRedDir                                                                          ! %REDDIR% is THIS file's directory
  red.lineEndings(st:Unix)                                                              ! normalise CRLF/CR -> LF  ! remove all <carriage return>
  red.Split('<10>',,,,st:clip,st:left)
  red.removeLines()                                                                     ! strip blank lines
  cfg = upper(left(self.Config))                                                        ! the one configuration section THIS build owns
!  loc:section = ''                                          ! pre-section region behaves like Common
  loop i = 1 to red.records()
    ln.SetValue(red.getLine(i))
    if ln.startsWith('--') then cycle.                                                  ! comment line
    if ln.valuePtr[1] = '['                                                             ! [Section]
      loc:section = upper(left(ln.between('[',']')))                                    ! left(): a section written [ Common ] is the same
                                                                                        !   one, and a compare ignores TRAILING spaces only
      cycle
    end
    if ln._dataEnd > 7 and upper(ln.valuePtr[1:8]) = '{{INCLUDE'                        ! nested red file
      p2 = ln.matchBrackets('{{','}')
      if p2
        ln.crop(9,p2-1)
        ln.trim()
        if ln._dataEnd
          self.ExpandMacros(ln)                                                         ! macros first: the fallback below reads the path
          rawRed = ln.getValue()                                                        ! the name as the .RED WROTE it
          self.NormalizeDir(ln)                                                         ! resolve macros/relativity
          if rawRed and ~self.IsAbsolute(rawRed)                                        ! a nested .RED names a file beside the .RED that
            if ~EXISTS(clip(ln.getValue()))                                             !   names it, not beside the project. The project
              ln.setValue(self.JoinPath(clip(self.RedDir), clip(rawRed)),st:Clip)       ! reading is tried FIRST, so
            end                                                                         !   nothing that resolves today moves anywhere
          end                                                                           !   - this is only where it found nothing
          self.LoadRed(ln, pDepth + 1)
          do SetRedDir                                                                  ! back to THIS file's directory for its remaining lines
        end
      end
      cycle
    end
    if loc:section AND loc:section <> 'COMMON' AND loc:section <> cfg then cycle.       ! [Copy] is not for source, and
                                                                                        !   neither is the configuration that is NOT being
                                                                                        !   built - but the one that IS carries that build's
                                                                                        !   own directories, which is what it is there for
    eqPos = ln.findByte(61)                                                             ! '='
    if eqPos < 2 then cycle.                                                            ! no '=', or nothing in front of it: a line with no mask of its own
                                                                                        !   names no file pattern, so its directories go under none
    mask = ln.valuePtr[1 : eqPos - 1]
    ln.removeFromPosition(1,eqPos)
    ln.trim()
    ln.split(';','"','"',true,st:clip,st:left)
    loop j = 1 to ln.records()
      ln.setValueFromLine(j)
      ln.unquote('"','"')                                                               ! drop quotes around spaced paths (if not already removed in split)
      ln.trim()
      if ~ln._dataEnd then cycle.
      if ln.endsWith('|')                                                               ! trailing '|' -> stop marker
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

! ---- %REDDIR% is the directory of the .RED being read - set on entry, and set again after a nested
!      include has been read. Made ABSOLUTE: NormalizeDir joins a relative directory to ProjDir, and
!      this one is relative to where the tool was started, not to the project.
SetRedDir routine
  self.RedDir = self.DirName(pRedPath.getValue())
  if ~self.RedDir then self.RedDir = '.'.
  if ~self.IsAbsolute(self.RedDir) then self.RedDir = self.JoinPath(path(), self.RedDir).

! ---------------------------------------------------------------------------
! ExpandMacros - substitute the supported %MACRO% values (case-insensitive). %REDDIR% is
! the directory of the .RED being read; LoadRed sets it per file.
! Unknown macros are left intact (their directories simply won't exist).
! ---------------------------------------------------------------------------
preprocessor.ExpandMacros PROCEDURE(StringTheory s)
  code
  s.Replace('%ROOT%',          clip(self.RootDir), 0, 1, 0,st:nocase)
  s.Replace('%BIN%',           clip(self.BinDir),  0, 1, 0,st:nocase)
  s.Replace('%CONFIGURATION%', clip(self.Config),  0, 1, 0,st:nocase)
  s.Replace('%REDDIR%',        clip(self.RedDir),  0, 1, 0,st:nocase)
  s.trim() ! just in case

! ---------------------------------------------------------------------------
! NormalizeDir - expand macros, then resolve a RELATIVE directory against ProjDir.
!
! EVERY relative form resolves against the project, not against wherever the
! process happens to have been started. A BARE relative name - `libsrc`, the
! commonest spelling in a real redirection file - is joined to ProjDir here,
! as '.' and '..' are. Left alone it would be resolved later by the OS
! against the CWD, which is the same directory only when the tool is run
! from the project. A user's build does not have to be, and the
! failure is silent - the include is simply not found, or a DIFFERENT
! file of that name is.
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

  if pDir._dataEnd = 1                                  ! '.'
    pdir.setValue(self.ProjDir,st:Clip)
  elsif pDir._dataEnd = 2 and pdir.valuePtr[2] = '.'    ! '..'
    pdir.setValue(self.ParentDir(self.ProjDir),st:Clip)
  else
    case val(pdir.valuePtr[2])
    of 92 orof 47                                       ! '\' orof '/'
      pdir.setValue(self.JoinPath(self.ProjDir, pDir.slice(3)),st:Clip)
    else
      case pDir.sub(2,2)
      of '.\' orof './'
        pdir.setValue(self.JoinPath(self.ParentDir(self.ProjDir), pDir.slice(4)),st:Clip)
      else
        pdir.setValue(self.JoinPath(self.ProjDir, pDir.getValue()),st:Clip)
      end
    end
  end
! A LEADING DOT DOES NOT MAKE A NAME RELATIVE-TO-HERE. `.private` and `..foo` are ordinary
!     directory names that happen to start with a dot, and every arm above is looking for the
!     NAVIGATION spellings - '.', '..', '.\x', './x', '..\x', '../x'. A name matching none of
!     them reaches the ELSE above. Left unchanged and still relative, it would be resolved by
!     the OS against the current directory instead of the project, so the include would not be
!     found, or a DIFFERENT file of that name would be, and nothing would say a word.
!     The ELSE gives it the same treatment as any other relative name: joined to ProjDir, which
!     is exactly what the `pDir.valuePtr[1] <> '.'` arm at the top of this procedure does. The
!     dot is not the point; being relative is.

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
  !    recursion. ProjDir alone is wrong for anything nested: it is set ONCE in Init
  !    from the MAIN source, so an include in a subdirectory would have ITS siblings
  !    looked for beside the main file, where they are not, and the run would report
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
  ! a name with a path, not found in (1) or (2), is looked up here too, by
  ! its base name alone.
  base = self.BaseName(nm)
  loop i = 1 to records(self.RedDirs)
    get(self.RedDirs, i)
    if ~self.MaskMatches(self.RedDirs.Mask, base) then cycle.
    ! A BLANK DIRECTORY IS NOT "HERE". An entry that was nothing but the stop bar, or
    ! whose only content was a macro with no value, reaches this table with no directory
    ! at all. JoinPath then hands back the BARE name and EXISTS resolves it against the
    ! directory the tool was STARTED in - so a file of that name sitting there is spliced
    ! instead of the right one, silently, which is the failure NormalizeDir exists to
    ! prevent. Skip the lookup; the entry's stop flag still means what it says.
    if self.RedDirs.Dir
      cand = self.JoinPath(clip(self.RedDirs.Dir), base)
      if EXISTS(clip(cand)) then return clip(cand).
    end
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
  self.ErrText._dataEnd   = self.ErrBase
  ! Rewind to what Init recorded rather than to nothing. A redirection file that
  ! would not load is the reason every include after it comes back "not found",
  ! and wiping the line that says so left the user the symptom and not the cause -
  ! or, on a source with no unresolvable include at all, nothing whatever.
  ! Compile-time-equate state must not survive a Process
  ! call: PPDefines carried one file's equates into every later file's
  ! OMIT/COMPILE conditions. (OMIT/COMPILE region state needs no reset here -
  ! it is a LOCAL stack in ProcessText, so it cannot outlive its file.)
  if not self.PPDefines &= null then self.PPDefines.setValue(self.SeedDefines). ! seeded project flags (_Cnn_ + --define=), rebuilt each file
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
! #Removed as not used: raw       StringTheory
i         long,auto
nLines    long,AUTO
myDir     string(512),auto ! the directory of the file whose text THIS call is walking -
incDir    string(512),auto !       a bare sibling INCLUDE in it resolves here first, as Clarion does
RegionQ   QUEUE,PRE(rgq)   ! OMIT/COMPILE regions, innermost last. A LOCAL, so each
Term        &string        !   file's regions die with its call frame - the call stack
Sup         byte           !   IS the region stack, and an unterminated region in an
          END              !   include cannot leak into the file that included it
rgTerm    StringTheory     ! CheckOmitCompile out-params
rgSup     byte
rgAft     long
rgEnd     byte
fileName  string(512)
secName   string(256)
onceFlag  byte
incOk     byte,auto        ! ParseDirective: 1 = a directive, 2 = one that will not parse, 0 = not one
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
    tl.Trim(' <9>')                                                                  ! spaces AND tabs: a tab-indented INCLUDE, OMIT,
                                                                                     !   COMPILE or SECTION is still that directive, and
                                                                                     !   every test below is fed from this one line
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
      get(RegionQ, records(RegionQ))                                                 ! innermost region governs
      ! the terminator is matched EXACTLY. The LRM (p67/p3495) says the block "ends with
      ! the line that contains the same STRING CONSTANT as the terminator" - and a string
      ! constant's content is case-significant. A caseless compare ends the block EARLY on a
      ! line that merely differs in case, which leaks source the author omitted back into the
      ! stream as live code. Same failure direction as an OMIT that ends on its own directive
      ! line, and the same reason to be strict about it.
      ! And it is looked for in the line AS WRITTEN, not in the trimmed copy the directive tests
      ! read: a terminator that ends or starts with a blank ('** ', ' END') is in the line only
      ! before the trim, and searched for after it the block would never close.
      work.setValueFromLine(i)
      if work.findChars(rgq:Term) > 0
        dispose(rgq:Term)
        delete(RegionQ)
        cycle
      end
      if rgq:Sup then cycle.
    end
    do SemiDirective
    if self.CheckOmitCompile(tl, rgTerm, rgSup, rgAft)
      do OwnLineEnd
      if rgEnd then cycle.
      clear(RegionQ)
      rgq:Term &= new string(rgTerm._DataEnd)
      rgq:Term = rgTerm.getValue()
      rgq:Sup  = rgSup
      add(RegionQ)
      cycle
    end
    self.TrackEquate(tl)
    !if ~t1._dataEnd or tl.valuePtr[1] = '!' or tl.valuePtr[1] = '|' then cycle. ! blank or comment or continuation
    if tl._dataEnd < 7 or upper(tl.valuePtr[1 : 7]) <> 'INCLUDE'
      self.EmitLine(work.getLine(i), pFileLabel, i + pLineOfs)
      cycle
    end
    incOk = self.ParseDirective(tl, fileName, secName, onceFlag)
    if incOk <> 1
      ! A LINE THAT OPENS WITH THE KEYWORD AND ITS '(' AND STILL WILL NOT PARSE IS A
      ! MALFORMED INCLUDE. Emitting it as ordinary source text and saying nothing leaves a
      ! hole in the expanded stream with the error count reading zero - the type registry is
      ! short a whole header and the run reports itself clean. ParseDirective answers 2 for
      ! exactly that shape and 0 for a line that was never the directive (a label beginning
      ! with the same letters), so nothing is said about ordinary code.
      if incOk = 2
        self.ErrText.Append('INCLUDE not understood: ' & clip(work.getLine(i)) &     |
                            ' (' & clip(pFileLabel) & ' line ' & (i + pLineOfs) & ')<13,10>')
      end
      self.EmitLine(work.getLine(i), pFileLabel, i + pLineOfs)
      cycle
    end
    ! ---- it is an INCLUDE directive ----
    resolved = self.ResolveFile(fileName, myDir)
    if ~resolved
      self.ErrText.Append('INCLUDE not found: ' & clip(fileName) &                   |
                          ' (' & clip(pFileLabel) & ' line ' & (i + pLineOfs) & ')<13,10>') ! + pLineOfs: i is section-relative, the neighbours include it
      self.EmitLine('! #error INCLUDE not found: ' & clip(fileName), pFileLabel, i + pLineOfs)
      cycle
    end
    keyStr = self.SeenKey(resolved)
    ! ONCE is FILENAME-wide, exactly as the LangRef states: "ONCE is applied on
    ! the entire filename, so subsequent uses of INCLUDE(filename, section) will
    ! be ignored." So the key is the resolved path ALONE - a ,ONCE include is
    ! skipped when the file was already included in ANY form, sectioned or
    ! whole. Keyed per section, a second section of an already-included file
    ! would splice again under ONCE, and declarations the real compiler never
    ! sees twice would reach the type registry twice. ONCE stays an attribute
    ! of THIS directive: a plain re-INCLUDE splices again.
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
        self.ErrText.Append('INCLUDE nested too deep (>' & PP:MaxDepth & '): ' &     |
                            clip(fileName) & '<13,10>')
        self.EmitLine('! #error INCLUDE nested too deep: ' & clip(fileName), pFileLabel, i + pLineOfs)
        self.DepthErrReported.Append(CLIP(keyStr))
      end
      cycle
    end
    if ~body.LoadFile(clip(resolved)) and ~self.LoadedEmpty(body, resolved)
      self.ErrText.Append('INCLUDE unreadable: ' & clip(resolved) & '<13,10>')
      self.EmitLine('! #error INCLUDE unreadable: ' & clip(fileName), pFileLabel, i + pLineOfs)
      cycle
    end
    secOfs = 0
    if secName
      self.ExtractSection(body, secName, chosen, secOfs)                             ! named section only
      if ~secOfs                                                                     ! say so: a typo'd section otherwise includes NOTHING, silently
        self.ErrText.Append('SECTION not found: ' & clip(secName) & ' in ' & clip(resolved) & |
                            ' (' & clip(pFileLabel) & ' line ' & i + pLineOfs & ')<13,10>')
        self.EmitLine('! #error SECTION not found: ' & clip(secName), pFileLabel, i + pLineOfs)
        cycle
      end
    else
      self.StripSections(body, chosen)                                               ! whole file, SECTION lines blanked (line count preserved for the map)
    end
    self.Seen.Append(CLIP(keyStr))
    ! OMIT/COMPILE region state is per FILE, not global:
    ! an INCLUDE spliced inside an active pass-through region must not run
    ! against the OUTER region's terminator. RegionQ is a LOCAL, so the
    ! recursion below gets its own empty stack and this file's regions are
    ! untouched when it returns - the call stack IS the region stack, with
    ! nothing to save or restore.
    incDir = self.DirName(resolved)                                                  ! what THAT file's own bare includes resolve against
    if ~incDir then incDir = myDir.                                                  !       (a name found with no path at all keeps this file's)
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
    dispose(rgq:Term)
    delete(RegionQ)
  end

! ---- THE DIRECTIVE'S OWN LINE CAN END ITS BLOCK. The search for the terminator starts on the
!      rest of that line, after the directive's closing ')': measured, a terminator in the line's
!      comment ends the block on that line, and the block is empty - nothing is omitted and no
!      region is opened. The condition in front of the ')' is not searched: measured, the
!      compiler does not end the block on a terminator spelled inside it. The line is searched
!      as written, so a terminator that ends in a blank is found as it is on the lines below. A
!      directive whose ')' is not on its line is not searched ----
OwnLineEnd routine
  data
olRaw  StringTheory
olRest StringTheory
olK    long,auto
  code
  rgEnd = 0
  if ~rgAft then exit.
  if rgAft <= tl._DataEnd then olRest.SetValue(tl.valuePtr[rgAft : tl._DataEnd]).
  olRaw.SetValue(work.getLine(i))
  olK = olRaw._DataEnd
  loop while olK > 0 and (olRaw.valuePtr[olK] = ' ' or olRaw.valuePtr[olK] = '<9>')
    olK -= 1
  end
  if olK < olRaw._DataEnd then olRest.Append(olRaw.valuePtr[olK + 1 : olRaw._DataEnd]).
  if olRest.findChars(rgTerm.getValue()) then rgEnd = 1.

! ---- A DIRECTIVE AFTER A ';'. The compiler takes INCLUDE, OMIT and COMPILE after a line break
!      or after a ';' and white space (LRM, compiler messages: "INCLUDE has to follow a
!      line-break, or a semi-colon"), so in  n = 1 ; INCLUDE('x.inc')  the INCLUDE is a
!      directive. When tl does not open with one, the line is searched for a ';' outside a
!      string literal and in front of any comment that a directive follows. The text before
!      that ';' is a statement and goes out as a line of its own, in its own columns; tl
!      becomes the directive, and the tests after this read it as they read one that starts
!      its line, and an EQUATE in front of the ';' is still tracked. Only a directive that
!      parses is split off - anything else leaves the line exactly as it was. ----
SemiDirective routine
  data
sdK    long,auto
sdQ    byte
sdRaw  StringTheory
sdRem  StringTheory
sdTerm StringTheory
sdSup  byte
sdFile string(512)
sdSec  string(256)
sdOnce byte
  code
  if self.CheckOmitCompile(tl, sdTerm, sdSup) then exit.
  if tl._dataEnd >= 7 and upper(tl.valuePtr[1 : 7]) = 'INCLUDE' then exit.
  sdRaw.SetValue(work.getLine(i))
  ! 39 is a quote - a doubled one toggles twice - 33 a '!', which outside a literal starts the
  ! comment, and 59 the ';'
  loop sdK = 1 to sdRaw._dataEnd
    case val(sdRaw.valuePtr[sdK])
    of 39
      sdQ = 1 - sdQ
    of 33
      if ~sdQ then break.
    of 59
      if sdQ or sdK = sdRaw._dataEnd then cycle.
      sdRem.SetValue(sdRaw.valuePtr[sdK + 1 : sdRaw._dataEnd])
      sdRem.Trim(' <9>')
      if sdRem._dataEnd < 4 then cycle.
      if ~self.CheckOmitCompile(sdRem, sdTerm, sdSup)
        if sdRem._dataEnd < 7 or upper(sdRem.valuePtr[1 : 7]) <> 'INCLUDE' then cycle.
        if self.ParseDirective(sdRem, sdFile, sdSec, sdOnce) <> 1 then cycle.
      end
      self.TrackEquate(tl)
      if sdK > 1 then self.EmitLine(sdRaw.valuePtr[1 : sdK - 1], pFileLabel, i + pLineOfs).
      tl.SetValue(sdRem)
      break
    end
  end

! ---------------------------------------------------------------------------
! CheckOmitCompile - OMIT('term'[,cond]) / COMPILE('term'[,cond]) region opener.
! OMIT suppresses its block when cond is true (or
! absent); COMPILE keeps its block when cond is true (or absent) and
! suppresses it otherwise. Undefined equates evaluate to 0. Returns TRUE when
! the line was a directive (the caller drops it either way) and fills the
! region's terminator + suppress flag; the CALLER pushes it onto its region
! stack, which is what lets regions nest where the LangRef allows.
! pAfter, when it is passed, says where the text after the directive's closing
! ')' starts in pTrimmed: the brackets are counted, and a bracket inside a
! literal is not one. 0 when the ')' is not on the line - a '|' or a '!'
! outside a literal comes first.
! ---------------------------------------------------------------------------
preprocessor.CheckOmitCompile PROCEDURE(StringTheory pTrimmed, StringTheory pTerm, *BYTE pSuppress, <*LONG pAfter>)
u        StringTheory ! the directive upper-cased, for the keyword test only: the terminator and the condition are sliced from pTrimmed in source case
isOmit   byte,auto
condVal  byte,AUTO
p        long,auto
p1       long,AUTO
p2       long,AUTO
pc       long,AUTO
pr       long,AUTO
k        long,auto
dep      long
q        byte
  code
  u.setValue(pTrimmed)
  u.upper()
  ! A TAB SEPARATES THE KEYWORD FROM ITS '(' EXACTLY AS A SPACE DOES, and a compare
  ! ignores TRAILING spaces only, so 'OMIT' + tab never equals 'OMIT '. Untested, a tab
  ! would leave the region unopened - the omitted block AND its terminator line go into
  ! the expanded stream as live code, with nothing reported.
  if u.startsWith('OMIT(') or u.startsWith('OMIT ', true, st:NoClip) or u.startsWith('OMIT<9>', true, st:NoClip)
    isOmit = true
    p = 5
  elsif u.startsWith('COMPILE(') or u.startsWith('COMPILE ', true, st:NoClip) or u.startsWith('COMPILE<9>', true, st:NoClip)
    isOmit = false
    p = 8
  else
    return false
  end
  loop while p <= u._DataEnd and (u.valuePtr[p] = ' ' or u.valuePtr[p] = '<9>')
    p += 1
  end
  if p > u._DataEnd or u.valuePtr[p] <> '(' then return false.
  p1 = pTrimmed.findByte(39, p)                      ! the opening quote of the terminator
  if ~p1 then return false.
  p2 = pTrimmed.findByte(39, p1 + 1)                 ! its closing quote
  if p2 <= p1 + 1 then return false.
  pTerm.setValue(pTrimmed.valuePtr[p1 + 1 : p2 - 1]) ! the terminator, whole - however long its author made it
  pc = pTrimmed.findByte(44, p2 + 1)                 ! ','
  pr = pTrimmed.findByte(41, p2 + 1)                 ! ')'
  if pc > 0 and (pr = 0 or pc < pr) and pr > pc + 1
    condVal = self.EvalPPCondition(pTrimmed.valuePtr[pc + 1 : pr - 1])
  else
    condVal = true
  end
  pSuppress = choose(isOmit = true, condVal, 1 - condVal)
  if ~omitted(pAfter)
    pAfter = 0
    loop k = p to pTrimmed._DataEnd
      case val(pTrimmed.valuePtr[k])
      of 39
        q = 1 - q
      of 40
        if ~q then dep += 1.
      of 41
        if ~q then dep -= 1.
        if ~dep then pAfter = k + 1 ; break.
      of 33 orof 124
        if ~q then break.
      end
    end
  end
  return true

! ---------------------------------------------------------------------------
! EvalPPCondition - 'NAME' -> defined and non-zero; 'NAME=value' -> equality
! against the tracked EQUATE registry; undefined names evaluate to 0.
! An equate's value can itself be a NAME - UseText EQUATE(False), MyDebug
! EQUATE(_DEBUG_) - and the compiler reads that name's value, so the chain is
! followed to a value that is not a name. A name with no definition reads 0, as
! an undefined equate does. TRUE and FALSE are declared in EQUATES.CLW, which
! every program sees, so they read 1 and 0 when no file the reader has seen
! defines them. A tab in the condition - after the comma, beside the '=' - is
! white space, as a space is.
! ---------------------------------------------------------------------------
preprocessor.EvalPPCondition PROCEDURE(STRING pCond)
c    StringTheory
nm   string(64),AUTO
vl   string(64),AUTO
defv string(64),AUTO
p    long,AUTO
q    long,AUTO
hop  long,AUTO
isNm byte,AUTO
  code
  c.SetValue(upper(pCond))
  c.Trim(' <9>')
  if c._dataEnd < 1 then return true.
  p = c.findByte(61)                    ! '='
  if p > 1
    nm = left(c.sub(1, p - 1))
    vl = left(c.slice(p + 1))
  else
    nm = left(c.getValue())
    vl = ''
  end
  loop q = 1 to size(nm)
    if nm[q] = '<9>' then nm[q] = ' '.
    if vl[q] = '<9>' then vl[q] = ' '.
  end
  nm = left(nm)
  vl = left(vl)
  p = instring('|' & clip(nm) & '=', upper(self.PPDefines.getValue()), 1, 1)
  if ~p
    defv = '0'
  else
    p += len(clip(nm)) + 2
    q = self.PPDefines.findByte(124, p) ! '|'
    if ~q then q = self.PPDefines._dataEnd + 1.
    defv = self.PPDefines.sub(p, q - p)
  end
  if ~p and nm = 'TRUE' then defv = '1'.
  loop hop = 1 to 32
    do IsName
    if ~isNm then break.
    nm = defv
    defv = '0'
    p = instring('|' & clip(nm) & '=', upper(self.PPDefines.getValue()), 1, 1)
    if p
      p += len(clip(nm)) + 2
      q = self.PPDefines.findByte(124, p)
      if ~q then q = self.PPDefines._dataEnd + 1.
      defv = self.PPDefines.sub(p, q - p)
    elsif nm = 'TRUE'
      defv = '1'
    end
  end
  do IsName
  if isNm then defv = '0'.
  if vl
    return choose(left(defv) = left(vl))
  end
  return choose(left(defv) <> '0' AND defv)

! ---- is defv a NAME - a letter or '_' first, then letters, digits, '_' and ':'? A
!      value that is not (a number, a quoted string, an expression) is the value itself.
!      Still a name after thirty-two steps, the chain is a loop of names, and reads 0.
IsName routine
  isNm = 0
  defv = left(defv)
  if ~defv then exit.
  q = val(defv[1])
  if (q < 65 or q > 90) and q <> 95 then exit.
  loop q = 2 to len(clip(defv))
    case val(defv[q])
    of 48 to 57 orof 65 to 90 orof 95 orof 58
    else
      exit
    end
  end
  isNm = 1

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
! #Removed as not used: r    long,AUTO
  code
  u.SetValue(upper(pTrimmed.getValue()))
  p = u.findChars(' EQUATE')
  if ~p then p = u.findChars('<9>EQUATE').
  if p < 2 then return.
  nm = left(u.sub(1, p - 1))
  ! `Label<9><9>EQUATE(1)`: a search can match at the SECOND tab and leave the first in the name,
  ! where clip() does not reach it - a tab after the label is a separator, so it becomes a space
  loop q = 1 to len(clip(nm))
    if nm[q] = '<9>' then nm[q] = ' '.
  end
  nm = left(nm)
  if instring(' ', clip(nm), 1, 1) > 0 then return.
  ! Prefixed labels (ST:Debug) are LEGAL equates and pervasive in COMPILE/OMIT conditions, so
  ! rejecting a name for holding one drops whole COMPILE regions. Only a LEADING colon is invalid.
  if nm[1] = ':' then return.
  q = u.findByte(40, p) ! '('
  if ~q
    vl = '1'
  else
    ! ')'
    if u.findByte(41, q) <= q + 1 then return.
    vl = left(u.sub(q + 1, u.findByte(41, q) - q - 1))
  end
  if instring('|' & clip(nm) & '=', upper(self.PPDefines.getValue()), 1, 1) > 0 then return.
  self.PPDefines.Append('|' & clip(nm) & '=' & clip(vl))

! ---------------------------------------------------------------------------
! ParseDirective - is pLine an INCLUDE directive? If so fill file/section/once.
! A directive must START the line (after trimming); INCLUDE text inside a string
! or after other code is not a directive. Quote-aware arg split handles both the
! 1-arg INCLUDE('f') and 2-arg INCLUDE('f','sect') forms.
!
! THREE ANSWERS, not two. 1 = a directive, parsed. 0 = never a directive, so the
! caller emits the line and says nothing: a label that merely begins with the same
! letters (INCLUDEFILE EQUATE(1)) is ordinary code. 2 = it opened with the keyword
! and its '(' and would not parse - a malformed directive, which the caller reports
! rather than leaving a silent hole in the expanded stream.
! ---------------------------------------------------------------------------
preprocessor.ParseDirective PROCEDURE(StringTheory ln, *STRING pFile, *STRING pSection, *BYTE pOnce)
args    StringTheory
gap     StringTheory
p1      long,AUTO
p2      long,AUTO
p3      long,AUTO
pq      long,AUTO
! #Removed as not used: cpos    long,AUTO ! position of a trailing '!', so ONCE is never read out of a comment
  code
  pFile = '' ; pSection = '' ; pOnce = 0
  p1 = ln.findByte(40)                                   ! '(' - and the opening quote: WHICHEVER COMES FIRST
  pq = ln.findByte(39)                                   !   picks the arm. A '(' can sit in a trailing comment
  if ~p1 or (pq and pq < p1)                             !   or in the name itself, and a whole-line search for
    p1 = pq                                              !   one would send such a line down the bracketed arm
    if ~p1 then return 0.                                !   to fail and go out as text in silence. NO
    gap.SetValue(ln.Sub(8, p1 - 8))                      !   BRACKETS is a spelling real sources use, so it is
    gap.Trim(' <9>')                                     !   read. Whitespace must still separate the keyword
    if gap._DataEnd then return 0.                       !   from the quote: that keeps INCLUDEFILE out of here
    p2 = ln.findByte(33, p1)                             ! a trailing comment ends the arguments
    if p2
      args.SetValue(ln.Slice(p1, p2 - 1))
    else
      args.SetValue(ln.Slice(p1, ln._DataEnd))
    end
    args.Trim(' <9>')
    ! ONLY THE ONE-ARGUMENT FORM IS READ HERE. A comma means a section name or an option,
    ! and what those look like without brackets is not something to guess at: answering 0
    ! leaves such a line exactly as it is handled today, which is the safe answer.
    if args.findByte(44) then return 0.                  ! <39>,<39>
    args.Split(',', '''', '''', true,st:clip,st:left)    ! quote-aware, strip quotes - as the bracketed arm does
    if ~args.records() then return 0.
    pFile = args.getLine(1)
    if ~pFile then return 0.
    p3 = ln.findByte(39, 1,, pFile)                      ! the same ampersand rule the bracketed arm applies
    if p3 > 1 and instring('&', clip(pFile), 1, p3) then pFile = sub(pFile, 1, p3 - 1).
    return 1
  end
  gap.SetValue(ln.Sub(8, p1 - 8))                        ! between INCLUDE and '(' must be WHITESPACE. A TAB
  gap.Trim(' <9>')                                       !   separates exactly as a space does, and a bare-string
  if gap._DataEnd then return 0.                         !   test calls one NON-blank, so the line would go out
                                                         !   as ordinary text, the include never expanded
  ! the MATCHING ')', not the first one. The case that needs it is the
  ! commonest path on Windows -
  !     INCLUDE('C:\Program Files (x86)\...\thing.inc')
  ! where the first ')' is the one of '(x86)': stopping there would truncate the name, the
  ! include would not resolve, and the ONCE scan below would start INSIDE the path
  ! (so a directory containing the letters "once" would set pOnce too).
  ! MatchBrackets counts depth, so a BALANCED pair inside the quotes cancels out and it
  ! lands on the real close. It is not quote-aware - `INCLUDE('a).inc')` still defeats
  ! it - but that needs a quote-aware scan and is a far rarer shape than a program-files
  ! path, so it is left as a known limit.
  p2 = ln.MatchBrackets('(', ')', p1)
  if ~p2 or                                              |
     p2 <= p1 + 1                                        ! `INCLUDE()` - nothing to parse; or a '(' inside the
    return 2                                             !   name that never closes, which leaves MatchBrackets
  end                                                    !   at 0. Either way it was MEANT to be a directive
  ! ONE SCAN, ONE ANSWER. A second, independent ln.between('(',')') here would find its
  ! right delimiter with a plain search (StringTheory.FindBetweenPosition) - the identical
  ! defect to the one above, and it could disagree with p2. Slice between the brackets
  ! already matched instead.
  args.SetValue(ln.Slice(p1 + 1, p2 - 1))                ! arg list inside the parens (Slice takes the two positions we already hold, so no length arithmetic)
  args.Split(',', '''', '''', true,st:clip,st:left)      ! quote-aware, strip quotes; clip+left so ' <39>Sect<39>' unquotes too
  if ~args.records() then return 2.
  pFile = args.getLine(1)
  if args.records() > 1 then pSection = args.getLine(2).
  ! THE PRE-PROCESSOR IGNORES '&' CONCATENATION: INCLUDE('EQUA' & 'TES.CLW') opens EQUA.CLW,
  ! and so must this. Split strips only the OUTER quotes, so a surviving quote with an '&'
  ! after it is where the first literal ended - cut there and the answer matches the
  ! compiler. Without the '&' test a quote is left alone: a doubled '' is one quote INSIDE
  ! the name, and that is a different question from this one.
  p3 = ln.findByte(39, 1,, pFile)                        ! <single quote>
  if p3 > 1 and instring('&', clip(pFile), 1, p3) then pFile = sub(pFile, 1, p3 - 1).
  ! CHOOSE(expr, val1, val2) treats a positive-integer expr as a 1-based INDEX into the
  ! value list, not a boolean (as Clarion's own docs say). INSTRING()
  ! returns a POSITION, so `choose(instringResult, 1, 0)` returns 1 only when the match
  ! happens to land at position 1, so onceFlag would be false almost always and ONCE
  ! would deduplicate nothing. The single-argument CHOOSE(expr) is the real boolean-to-0/1
  ! converter: use it, or an explicit `expr <> 0`, whenever the condition is not already
  ! guaranteed to be exactly 0 or 1.
  ! bound the ONCE search at a trailing comment '!'
  if ln.findByte(33, p2 + 1)
    pOnce = choose(ln.Instring('ONCE', 1, p2 + 1, ln.findByte(33, p2 + 1) - 1, st:nocase))
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
! #Removed as not used: tl    StringTheory
i     long,auto
cap   byte
  code
  pStartLine = 0
  pResult._dataEnd = 0
  bw.SetValue(pBody)
  bw.lineEndings(st:Unix)
  bw.Split('<10>')
  loop i = 1 to bw.records()
    bw.setValueFromLine(i) ; bw.Trim(' <9>')
    if self.IsSectionLine(bw)                     ! the word SECTION then a '(' - a label merely STARTING
      bw.SetBetween('(',')',,,,,true)             !   'Section' (SectionSize EQUATE(100)) is BODY, and the
      bw.unquote('''', '''')                      !   a 7-char prefix test would end the capture there,
      cap = choose(upper(choose(bw._DataEnd < 1, '', bw.valuePtr[1 : bw._DataEnd])) = upper(pSection)) ! silently truncating the section
      if cap and ~pStartLine then pStartLine = i. ! the section body starts at line i+1 of the included file
      cycle                                       ! never emit the SECTION line
    end
    if cap
      pResult.Append(bw.getLine(i))               ! original line, untrimmed
      pResult.Append('<13,10>')
    end
  end

! ---------------------------------------------------------------------------
! StripSections - return the whole body with any SECTION directive lines removed
! (they delimit but produce no code when a file is included wholesale).
! ---------------------------------------------------------------------------
preprocessor.StripSections PROCEDURE(*StringTheory pBody, *StringTheory pResult)
bw    StringTheory
! #Removed as not used: tl    StringTheory
i     long,auto
  code
  pResult._dataEnd = 0
  bw.SetValue(pBody)
  bw.lineEndings(st:Unix)
  bw.Split('<10>')
  loop i = 1 to bw.records()
    bw.setValueFromLine(i) ; bw.Trim(' <9>')
    if self.IsSectionLine(bw)   ! a section marker line and only that: a label
      pResult.Append('<13,10>') !   like SectionSize EQUATE(100) is not one. BLANK the
      cycle                     !   line: deleting it would shift every later line's map entry
    end
    pResult.Append(bw.getLine(i))
    pResult.Append('<13,10>')
  end

! ---------------------------------------------------------------------------
! IsSectionLine - a real SECTION('name') directive: the word SECTION, optional
! whitespace, then '('. Mirrors CheckOmitCompile's OMIT/COMPILE test. A column-1
! label that merely STARTS with the letters (SectionSize, SectionNo) is code:
! the separator test below refuses it, because its 8th character is a letter.
! The separator may be a TAB. A compare ignores TRAILING spaces only, so testing
! the 8 characters against 'SECTION ' missed a tab and the section boundary went
! unseen - the capture of the section before it ran straight on through this one.
! ---------------------------------------------------------------------------
preprocessor.IsSectionLine PROCEDURE(StringTheory pTrimmed)
u    string(512)
p    long,AUTO
  code
  u = upper(pTrimmed.getValue())
  if u[1 : 8] = 'SECTION(' then return 1.
  if u[1 : 7] <> 'SECTION' then return 0.
  p = 8
  loop while p <= len(clip(u)) AND (u[p] = ' ' or u[p] = '<9>')
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

! The directory ABOVE pDir. This is NOT DirName: DirName answers "the directory part of a
! path", and for a path that is only a navigation step there is no part to take. DirName('.')
! is '' - correct for what DirName means, and useless as a parent, because '' is read further
! down as "the current directory" and so the step up is silently lost. A redirection entry of
! `..\shared` would then resolve to `shared`, in the project directory, not its parent, and a
! file of that name living there would be spliced in instead of the right one.
!
! A trailing navigation step cannot be cancelled by removing it - the parent of `..` is
! `..\..`, not '' - so those spellings are extended rather than popped. A single plain name
! DOES pop, to '', which correctly means the directory the project sits in.
preprocessor.ParentDir PROCEDURE(STRING pDir)
d     string(512)
n     long,auto
  code
  d = pDir
  ! A TRAILING SEPARATOR FIRST. BaseName answers blank for `src\`, and a blank segment would
  ! send this down the pop arm and take one level too few. Nothing reaches here with one -
  ! ProjDir comes from DirName, which strips it - but the answer should not depend on that.
  loop
    n = len(clip(d))
    if ~n then break.
    if d[n] <> '\' and d[n] <> '/' then break.
    if n = 1                              ! nothing but a separator: blank it rather than
      d = ''                              !   hand BaseName a path it answers with a
      break                               !   zero-length SUB
    end
    d = sub(d, 1, n - 1)
  end
  if ~d then return '..'.                 ! blank means HERE, and above here is '..'
  case self.BaseName(d)                   ! the final segment, whatever separators were used
  of '.'
    if len(clip(d)) = 1 then return '..'. ! '.' on its own - say '..', not '.\..'
    return clip(d) & '\..'
  of '..'
    return clip(d) & '\..'                ! cannot be popped - go up from where it lands
  end
  return self.DirName(d)                  ! a real name pops; '' here means the project's own parent

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
  case val(d[len(clip(d))])
  of 92 orof 47 ! '\' orof '/'
    return clip(d) & clip(pName)
  end
  return clip(d) & '\' & clip(pName)
