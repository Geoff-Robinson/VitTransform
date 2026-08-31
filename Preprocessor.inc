! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
! ===========================================================================
! Preprocessor.inc - INCLUDE / SECTION / ONCE directive expansion
! SHARED by two projects: it was written for the Clarion-to-C++ Transpiler, and
! VitTransform links it too (VitEngine.inc includes this file) to expand
! includes for the cross-file type registry that --thorough needs. Change it
! with both callers in mind.
!
! Clarion INCLUDE is textual: the named file (or one SECTION of it) is compiled
! "as if it appeared in sequence". This preprocessor runs BEFORE the lexer: it
! takes the main source, splices every INCLUDE in place (resolving via the .RED
! redirection file), honours ONCE the way the LangRef specifies - FILENAME-wide,
! so a ,ONCE include of a file that was already included (any section of it) is
! ignored - caps nesting at PP:MaxDepth, and is immune to INCLUDE text inside
! comments or string literals (a directive must be the first token on its line).
!
! It also emits a LineMapQueue so diagnostics can report the ORIGINAL file and
! line: expanded physical line N maps to record N of the LineMapQueue.
! ===========================================================================
  OMIT('__EndPreprocessorInc__', _PreprocessorIncPresent_)
_PreprocessorIncPresent_ EQUATE(1)

  INCLUDE('StringTheory.inc'), ONCE ! Transpiler.inc only re-exported StringTheory + unused TK:/ST: equates (decoupled for VitTransform)

! Maximum INCLUDE nesting depth - a safety net against runaway/circular includes.
! it is the ONLY thing catching a cycle.
! ONCE is an attribute of a DIRECTIVE, not of a file: `INCLUDE('a.inc'),ONCE` is skipped
! when a.inc has been included before, but a PLAIN `INCLUDE('a.inc')` splices it again
! however many times it appears. So A-includes-B-includes-A without ONCE on the way round
! is a genuine cycle, and what stops it is this cap - after which it reports "nested too
! deep" and carries on. It will have spliced the loop PP:MaxDepth times by then.
! WHY IT IS GENEROUS: a real multi-module project has many .inc files all pulling in one
! shared common .inc, so depth adds up fast even when every individual chain is reasonable -
! measured hitting a limit of 3 on an ordinary file. Raising the cap only relaxes the safety
! net and cannot break anything that worked before, so it is set well clear of real code.
PP:MaxDepth       EQUATE(100)

! ---------------------------------------------------------------------------
! Line map - one record per physical line of the fully-expanded source.
! Record N corresponds to expanded line N (1-based); the lexer's token.LineNo
! indexes straight into this to recover the real file + line.
! ---------------------------------------------------------------------------
LineMapQueue      QUEUE, TYPE
FileName            STRING(256)
OrigLine            LONG
                  END

! ---------------------------------------------------------------------------
! Redirection entries - one record per (filemask, directory) pair, in .RED
! priority order (earlier lines first). Resolution walks this in Seq order.
! ---------------------------------------------------------------------------
RedDirQueue       QUEUE, TYPE
Seq                 LONG          ! global priority order
Mask                STRING(64)    ! e.g. '*.clw', '*.*'
Dir                 STRING(256)   ! macro-expanded directory (native backslash form)
Stop                BYTE          ! trailing '|' in the .RED -> stop searching if not found here
                  END

! ---------------------------------------------------------------------------
! Preprocessor
! ---------------------------------------------------------------------------
Preprocessor      CLASS, TYPE, MODULE('Preprocessor.clw'), LINK('Preprocessor.clw')
RedDirs             &RedDirQueue  ! parsed .RED search table (owned)
LineMap             &LineMapQueue ! bound to the caller's queue during Process
Out                 &StringTheory ! bound to the caller's expanded output during Process
Seen                &StringTheory ! |-delimited lowercased resolved paths already included (owned).
                                  ! FILENAME keys only: ONCE is filename-wide per the LangRef, so a
                                  ! sectioned include records the same key as a whole-file one.
DepthErrReported    &StringTheory ! |-delimited paths already given a "nested too deep" error (owned) -
                                  ! tracks error *reporting* only, separate
                                  ! from Seen (which governs actual include-skip behaviour) - see the
                                  ! note at the check site in Preprocessor.clw for why these can't just
                                  ! share one field.
ErrText             &StringTheory ! accumulated preprocessor diagnostics (owned)
MainFile            STRING(256)   ! base name of the main source (line-map label for top level)
ProjDir             STRING(256)   ! directory of the main source; '.' in the .RED resolves here
RootDir             STRING(256)   ! %ROOT% macro value
BinDir              STRING(256)   ! %BIN%  macro value
Config              STRING(32)    ! %CONFIGURATION% macro value (Debug / Release)
                                  ! (OMIT/COMPILE region state is a LOCAL stack in ProcessText - one per
                                  ! file, so the call stack is the region stack and nested regions in a
                                  ! pass-through block are honoured, as the LangRef allows)
PPDefines           &StringTheory ! '|NAME=VALUE' compile-time equate registry (owned) -
                                  ! fed by TrackEquate, read by EvalPPCondition

Construct           PROCEDURE()
Destruct            PROCEDURE()
! pRootDir = Clarion install root (%ROOT%); pConfig = 'Debug'/'Release' (optional)
Init                PROCEDURE(STRING pMainFilePath, STRING pRedFilePath, STRING pRootDir, STRING pConfig)
! Expand pMainSource into pExpandedOut and fill pLineMap. Returns the number of
! preprocessor errors encountered (0 = clean).
Process             PROCEDURE(*StringTheory pMainSource, *StringTheory pExpandedOut, *LineMapQueue pLineMap), LONG, PROC
HadErrors           PROCEDURE(), BYTE
GetErrors           PROCEDURE(), STRING

! ---- internals ----
LoadRed             PROCEDURE(stringTheory pRedPath, LONG pDepth), PRIVATE
ExpandMacros        PROCEDURE(stringTheory s), PRIVATE
ResolveFile         PROCEDURE(STRING pName, <STRING pFromDir>), STRING, PRIVATE    ! pFromDir = the INCLUDING file's directory, tried before ProjDir
MaskMatches         PROCEDURE(STRING pMask, STRING pBase), BYTE, PRIVATE
! These three prototypes said 'StringTheory' BY VALUE
! while every definition in Preprocessor.clw takes '*StringTheory' - native
! Clarion tolerated the mismatch, C++ treats decl and definition as different
! functions. Aligned to the definitions (also avoids copying a heap-owning
! class by value).
ProcessText         PROCEDURE(*StringTheory pSrc, STRING pFileLabel, LONG pDepth, LONG pLineOfs=0, <STRING pFileDir>), PRIVATE  ! section includes carry their true start line
ParseDirective      PROCEDURE(StringTheory pLine, *STRING pFile, *STRING pSection, *BYTE pOnce), BYTE, PRIVATE
ExtractSection      PROCEDURE(*StringTheory pBody, STRING pSection, *StringTheory pResult, *LONG pStartLine), PRIVATE  ! pStartLine = SECTION line index (0 = section not found)
StripSections       PROCEDURE(*StringTheory pBody, *StringTheory pResult), PRIVATE
CheckOmitCompile    PROCEDURE(StringTheory pTrimmed, *STRING pTerm, *BYTE pSuppress), BYTE, PRIVATE
                                    ! OMIT('t'[,cond]) / COMPILE('t'[,cond]) region opener. Fills the
                                    ! region's terminator + suppress flag; the CALLER stacks it (regions
                                    ! nest when parsing is continuing)
IsSectionLine       PROCEDURE(StringTheory pTrimmed), BYTE, PRIVATE
                                    ! a real SECTION('name') directive - the word THEN a '('. A label
                                    ! merely STARTING 'Section' (SectionSize EQUATE(100)) is body text,
                                    ! not a boundary
EvalPPCondition     PROCEDURE(STRING pCond), BYTE, PRIVATE
TrackEquate         PROCEDURE(StringTheory pTrimmed), PRIVATE
EmitLine            PROCEDURE(STRING pLine, STRING pFileLabel, LONG pOrigLine), PRIVATE
SeenKey             PROCEDURE(STRING pResolved), STRING, PRIVATE  ! '|key|' lowercase lookup token
DirName             PROCEDURE(STRING pPath), STRING, PRIVATE
BaseName            PROCEDURE(STRING pPath), STRING, PRIVATE
HasExtension        PROCEDURE(STRING pName), BYTE, PRIVATE
IsAbsolute          PROCEDURE(STRING pName), BYTE, PRIVATE
JoinPath            PROCEDURE(STRING pDir, STRING pName), STRING, PRIVATE
NormalizeDir        PROCEDURE(stringTheory pDir), PRIVATE  ! expand macros + resolve '.'/'..' (mutates pDir)
                  END

  __EndPreprocessorInc__
