! VitStyle - the rule-selection chooser (S3 of the selection arc; design v01
! section 5 + v02 sections 5c/5d).
! (c) 2019-2026 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
!
! usage:  VitStyle [rulefile]          (default vitrules.txt, and it says so on screen)
!
! Shows every GROUP/CHOICE of the rule file with its resolved state, lets the
! user pick a shipped STYLE or a saved profile, toggle groups, and save the
! result as a named PROFILE in VitStyle.profiles.txt NEXT TO THE EXE (decision
! 3). A profile is one STYLE line (names only, never line numbers;
! name members express deselection) + a LASTUSED marker so the chooser
! reopens where the user left off.
!
! THE HONESTY INVARIANT: this program decides NOTHING. The
! checkboxes merely edit an override list that is fed to VitRules.Resolve -
! the SAME resolver the VitTransform CLI uses - and every state shown is read
! back from the resolved groups queue; the effective-selection panel is the
! engine's own SelectionTable output. Preview-vs-real divergence is impossible
! by construction.
!
! Group descriptions are harvested from the comment block immediately
! preceding each GROUP line in the rule file (the files are already commented
! in exactly that shape - no new DOC syntax).
!
!
! the RULE WORKBENCH - write/lint/test/save USER rules into
! VitStyle.rules.txt next to the exe. The user file is
! auto-loaded NON-FATALLY at startup (validated on a scratch VitRules first;
! broken -> message + skipped, the workbench still opens). All draft work runs on
! the scratch wbRl/wbEng - the live set changes only through Save's full reload.
!
  PROGRAM

  INCLUDE('KEYCODES.CLW'),ONCE                                                 ! MouseLeft2 for the ALRT double-click (not in EQUATES.CLW;
                                                                               ! template apps include it for you, a hand-coded PROGRAM must ask)
  INCLUDE('StringTheory.inc'),ONCE
  INCLUDE('VitTokenize.inc'),ONCE
  INCLUDE('VitRules.inc'),ONCE
  INCLUDE('VitSymbols.inc'),ONCE                                               ! the live-preview engine (same classes VitTransform links)
  INCLUDE('VitMatch.inc'),ONCE
  INCLUDE('VitRewrite.inc'),ONCE
  INCLUDE('VitTimer.inc'),ONCE
  INCLUDE('VitEngine.inc'),ONCE

  MAP
    LoadEverything()
    RefreshProfiles()                                                          ! drop+reload profile styles from profFn
    HarvestDocs()                                                              ! comment block above each GROUP line -> docsQ
    BuildStyleList()
    BuildDisplay()                                                             ! groups queue -> DispQ + effective table + doc panel
    ApplyOverrides()                                                           ! ovrQ -> csv lists -> rl.Resolve -> BuildDisplay -> RefreshPreview
    ToggleCurrent()                                                            ! flip the highlighted group via the override list
    ShowDoc()                                                                  ! doc panel for the highlighted group
    SaveProfile()
    WriteProfileLine(STRING pName, STRING pMembers),BYTE,PROC                  ! read-modify-write profFn; 0 = save failed (box already shown)
    CurrentMembers(),STRING                                                    ! FULL-spelling member list of the resolved state
    ExeDir(),STRING
    RefreshPreview()                                                           ! run eng.TransformText on the source buffer under the current selection
    BuildPreviewLists(StringTheory pSrc, StringTheory pOut, StringTheory pLog) ! split + diff + change list
    ResizeControls()                                                           ! reflow the preview + lists to the current window size
    LoadSourceFile(<string pFn>)                                               ! open a .clw/.inc as the preview source (in-file fidelity)
    PasteSnippet()                                                             ! paste a snippet as the preview source (ASSUME fidelity)
    SetDemo()                                                                  ! built-in demo source
    GotoChange()                                                               ! scroll both panes to the highlighted change
    SyncPanes(BYTE pWhich)                                                     ! 1 = before selected -> scroll after; 2 = after selected -> scroll before
    SortChanges()                                                              ! (re)sort the change list by rule# or line# per sortMode
    OverrideLists(StringTheory pGrps, StringTheory pNogr)                      ! OvrQ -> csv pick/unpick lists (shared by ApplyOverrides + the workbench test)
    Workbench()                                                                ! the modal rule workbench
    WbBuildRuleList()                                                          ! existing user rules -> the workbench droplist
    WbLoadPick()                                                               ! droplist pick -> editor (edit-in-place) / (new rule)
    WbComposeUser(StringTheory pOut, *LONG pDraftLn)                           ! prospective VitStyle.rules.txt text = disk file + draft (replace or append)
    WbLint(BYTE pShowOk),LONG,PROC                                             ! lint the prospective COMBINED set on the scratch instances; fills the panel; returns SEV:Error count
    WbTest()                                                                   ! run the draft on the current preview source via the scratch engine
    WbSave(),LONG                                                              ! lint gate + write userFn; 1 = saved (refresh happens post-close)
    WbAfterSave()                                                              ! AFTER close(WbW): full reload + force group on + profile offer -
                                                                               !     main-window controls must never be touched while the modal child is open
    LoadUiPrefs()                                                              ! colour: read VitStyle.ui.txt (CHGCOLOR/CHGCOLOR2) or defaults
    SaveUiPrefs()                                                              ! colour: write it (best-effort)
    DarkenColor(LONG pC),LONG                                                  ! colour: selected-variant shade of the changed-line fill
    UiNum(StringTheory pSt, STRING pKey),LONG                                  ! colour: digit-walk the number after pKey in the UPPERED prefs text (0 = absent)
  END

rl        VitRules
eng       VitEngine                                                            ! owns tk/syms/rw/tmr for the in-process preview
wbRl      VitRules                                                             ! SCRATCH rules instance - startup user-file validation + workbench lint/test;
                                                                               !     the LIVE rl/eng are never touched by a draft
wbEng     VitEngine                                                            ! scratch engine over wbRl for the workbench test run
rulesFn   StringTheory
profFn    StringTheory
userFn    StringTheory                                                         ! VitStyle.rules.txt next to the exe
raw       StringTheory                                                         ! rule file raw text (doc harvesting)
scratch   StringTheory
selSt     StringTheory
srcBuf    StringTheory                                                         ! the current preview SOURCE (demo / opened file / pasted snippet)
outBuf    StringTheory                                                         ! transformed text
logBuf    StringTheory                                                         ! change log from TransformText
fidelity  STRING(96),AUTO                                                      ! 80 overflowed by 3 on the longest
                                                                               !   form - 'file: ' + 55 of the name +
                                                                               !   '  (in-file types only)' = 83 - and it
                                                                               !   is the DISCLAIMER at the end that was
                                                                               !   cut, which is the half that matters.
                                                                               ! badge - what the preview is running against
prevChg   LONG,AUTO                                                            ! change count of the last preview run
engReady  BYTE,AUTO                                                            ! eng.Init done
progBef   LONG                                                                 ! the Before row we last KNOW about (baseline). A NewSelection whose row = this is our own echo / a no-op - skip.
progAft   LONG                                                                 ! ditto for After
syncLock  BYTE                                                                 ! re-entrancy guard held across a sync (NB SyncPanes must NOT test it - the handler holds it while calling SyncPanes)
lastSync  LONG ! clock() (centiseconds) of the last sync - the DEBOUNCE: the echo of our select() lands within ~50ms and is skipped, breaking the ping-pong
syncRow   LONG                                                                 ! scratch row for the sync handlers (global 'r' clashed with local r's)
! syncOn SHIPS AS 1, i.e. pane sync is ON. If you are chasing a sync loop, read the
! value above and not a comment: this one said "0 = OFF" for a long time while the
! declaration said BYTE(1), which would send you looking anywhere but here. Set it to 0
! to turn pane sync off - the tool stays perfectly usable without it. The debounce is
! the guard repeated at every use: if ~syncOn or syncLock or (clock() >= lastSync and clock() - lastSync < 5).
! the `clock() >= lastSync` half is the MIDNIGHT guard. CLOCK() is centiseconds since
! midnight, so at the rollover it restarts at 0 and `clock() - lastSync` goes hugely NEGATIVE -
! which is < 5, so the debounce swallowed every sync for the rest of the session. Comparing
! first means a rolled-over clock reads as "the window has passed", and the next sync resets
! lastSync to the new day's value, so it recovers on the first click rather than never.
syncOn    BYTE(1)                                                              ! pane->pane click sync master switch. 1 = ON, and that is what ships - see the note above.
shortCap  BYTE                                                                 ! 1 = the change-list button row is in its
                                                                               !   NARROW form. Set by ResizeControls and
                                                                               !   read by SortChanges, which also writes
                                                                               !   ?SortBtn's caption - without this the two
                                                                               !   fight and the long text reappears on a
                                                                               !   narrow window at the next sort.
sortMode  BYTE                                                                 ! 0 = changes sorted by rule#, 1 = by line#

DocsQ     QUEUE,PRE(dq)
name        STRING(vr:maxName)
txt         STRING(2000)
          END

DispQ     QUEUE,PRE(pq)
state       STRING(6)
name        STRING(vr:maxName)
choice      STRING(vr:maxName)
info        STRING(20)
grpRow      LONG
          END

OvrQ      QUEUE,PRE(oq)                   ! per-group override, one row per touched group,
grpRow      LONG               ! row order = click order (latest wins in its list)
mode        BYTE               ! 1 = force-on, 2 = force-off
          END

StyQ      QUEUE,PRE(sq)        ! style droplist backing store
shown       STRING(70)
nm          STRING(vr:maxName) ! '' = file defaults
          END

PvBefQ    QUEUE,PRE(bq)        ! before pane, one row per source line (2 cols = ln + txt)
ln          LONG
txt         STRING(255)        ! '> ' prefix marks changed lines.
txtFg       LONG               ! colour: the * column tuple - text, fill, SELECTED text, SELECTED fill.
txtBg       LONG               !   ALL FOUR longs must sit right after txt - the colour failure fits
txtSFg      LONG               !   a 2-long fg/bg tuple exactly (the LIST read the sync field as the
txtSBg      LONG               !   selected pair). COLOR:None (-1) = no override, theme default.
aln         LONG               ! S4 sync: the aligned AFTER line (trailing data field, not displayed - like DispQ.grpRow)
          END

PvAftQ    QUEUE,PRE(aq)        ! after pane, one row per transformed line
ln          LONG
txt         STRING(255)
txtFg       LONG               ! colour tuple - see PvBefQ
txtBg       LONG
txtSFg      LONG
txtSBg      LONG
bln         LONG               ! S4 sync: the aligned BEFORE line
          END

ChgQ      QUEUE,PRE(cq)        ! change list (from the rule log) - cols: Line, Rule, Change
ln          LONG               ! source line
rule        LONG               ! rule id (SORT key for by-rule# vs by-line#)
desc        STRING(255)        ! the change text (before ==> after)
          END

curStyle   STRING(vr:maxName)  ! '' = file defaults
styPickTxt STRING(70)
rulesLbl   STRING(120),AUTO
docTxt     STRING(2000),AUTO
effTxt     STRING(2500),AUTO
profNm     STRING(vr:maxName)
x          LONG
nameOk     LONG

! ---- changed-line colour ----
chgColor   LONG                ! fill colour A for changed lines (user-choosable via COLORDIALOG;
                               !   persisted as CHGCOLOR in VitStyle.ui.txt; default pale yellow)
chgColor2  LONG                ! fill colour B: contiguous changed BLOCKS
                               !   alternate A/B on the Before side and each changed After row
                               !   INHERITS its source block's colour through the line map, so
                               !   corresponding lhs/rhs regions share a colour at a glance.
                               !   Persisted as CHGCOLOR2; default pale green.
uiFn       StringTheory        ! VitStyle.ui.txt next to the exe (UI prefs - NOT the profile file,
                               !   whose engine-side parser warns on unknown lines)

! ---- workbench state ----
userLoaded BYTE                ! VitStyle.rules.txt present + validated + appended to the live set
wbPickTxt  STRING(70)          ! workbench droplist display
draftVar   CSTRING(4096)       ! the draft rule text (TEXT control; one logical rule, | continuations ok)
wbGrp      STRING(vr:maxName)  ! target GROUP (default my-rules)
wbLintTxt  STRING(2500),AUTO   ! lint panel
wbEditId   LONG                ! ruleId being edited in place (0 = new rule)
wbDraftId  LONG                ! the draft's ruleId in the prospective file (userBase + line) - the fires filter
wbOut      StringTheory        ! scratch-engine output buffer
wbLog      StringTheory        ! scratch-engine change log

WbrQ      QUEUE,PRE(wr)        ! workbench droplist backing store
shown       STRING(70)
id          LONG               ! ruleId (vr:userBase-offset); 0 = (new rule)
grpNm       STRING(vr:maxName)
          END

WbBefQ    QUEUE,PRE(wb)        ! mini before pane
ln          LONG
txt         STRING(255)
txtFg       LONG               ! colour tuple - see PvBefQ
txtBg       LONG
txtSFg      LONG
txtSBg      LONG
          END

WbAftQ    QUEUE,PRE(wa)        ! mini after pane
ln          LONG
txt         STRING(255)
txtFg       LONG               ! colour tuple - see PvBefQ
txtBg       LONG
txtSFg      LONG
txtSBg      LONG
bln         LONG               ! source line (from the scratch engine line map; 0 = unmapped)
          END

WbChgQ    QUEUE,PRE(wc)        ! the DRAFT's fires only (wbDraftId range test)
ln          LONG               ! source line
desc        STRING(255)
aln         LONG               ! first after-pane row of that source line (click-to-jump)
          END

! debugIt - the workbench debug switch. 0 (the shipped value) and NOTHING is written to
! disk. Set it to 1 in the debugger, or add a line of code, to get logFile.txt (the raw
! engine change log) plus PvBefQ.csv and PvAftQ.csv (the two preview panes, for eyeballing
! how lines were paired up) dropped in the CURRENT WORKING DIRECTORY. Keep them behind this
! switch: unconditional, they land in whatever folder the user happened to run from on every
! single preview refresh, which is the sort of thing that is nobody's bug until it is.
debugIt long

! first WINDOW of the project: FORMAT picture widths, ALRT and the resize reflow are the risk spots
!    Left column = selection controls (fixed width); right column = live preview (grows on resize).
!    RESIZE + MAX + opens maximized (0{PROP:Maximize} after open); ResizeControls reflows the LISTs.
W WINDOW('VitStyle - rule selection & live preview'),AT(,,640,384),CENTER,GRAY,SYSTEM, |
      MAX,Iconize,FONT('Segoe UI',9),RESIZE,IMM ! IMM IS WHAT MAKES A RESIZE ARRIVE.
    PROMPT('Rules:'),AT(6,6),USE(?PROMPT1)
    STRING(@s120),AT(34,6,220,10),USE(rulesLbl)
    PROMPT('Style:'),AT(6,20),USE(?PROMPT2)
    LIST,AT(34,18,140,12),USE(styPickTxt),DROP(15),FROM(StyQ),FORMAT('156L(2)@s70@')
    BUTTON('&Apply'),AT(178,17,48,14),USE(?ApplyBtn)
    LIST,AT(6,36,250,150),USE(?GrpList),VSCROLL,FROM(DispQ),FORMAT('24L(2)~St~@s' & |
        '6@88L(2)~Group~@s50@66L(2)~Choice~@s50@42L(2)~Rules~@s20@'),ALRT(MouseLeft2)
    BUTTON('&Toggle'),AT(6,190,42,14),USE(?ToggleBtn)
    BUTTON('&Save profile...'),AT(52,190,64,14),USE(?SaveBtn)
    BUTTON('&Workbench...'),AT(120,190,64,14),USE(?WbBtn)
    BUTTON('&Close'),AT(210,190,46,14),USE(?CloseBtn)
    PROMPT('About the highlighted group:'),AT(6,210),USE(?PROMPT3)
    TEXT,AT(6,220,250,66),USE(docTxt),VSCROLL,READONLY
    PROMPT('Effective selection (the engine''s own table):'),AT(6,290),USE(?PROMPT4)
    TEXT,AT(6,300,250,78),USE(effTxt),VSCROLL,READONLY
    ! ---- right column: live preview ----
    BUTTON('&Open file...'),AT(262,4,56,14),USE(?OpenBtn)
    BUTTON('&Demo'),AT(320,4,40,14),USE(?DemoBtn)
    BUTTON('&Paste...'),AT(362,4,44,14),USE(?PasteBtn)
    STRING(@s96),AT(410,7,,10),FULL,USE(fidelity) ! @s96 = the buffer: @s80 clipped the 83-char longest form (#30)
    PROMPT('Before'),AT(262,22),USE(?PROMPT5)
    PROMPT('After (live)'),AT(450,22),USE(?AfterHdr)
    ! changed lines: '> ' prefix + cell colour (the * modifier + 4-LONG tuple per column)
    LIST,AT(262,32,184,252),USE(?BeforeList),VSCROLL,FROM(PvBefQ),FORMAT('36R(2)' & |
        '~Line~@n5@600L(2)*~Source~@s255@')
    LIST,AT(450,32,184,252),USE(?AfterList),VSCROLL,FROM(PvAftQ),FORMAT('36R(2)~' & |
        'Line~@n5@600L(2)*~Transformed~@s255@')
    PROMPT('Changes (click a row to jump both panes):'),AT(262,290),USE(?ChangesHdr)
    ! Widths here and the Xpos offsets in ResizeControls MUST be kept in step: the resize
    ! sets Xpos only, never Width, so a button widened here and not re-offset there overlaps
    ! its neighbour the moment the window is sized. Both lay the row out RIGHT-ANCHORED with
    ! 4-unit gaps, ending flush with ?ChangeList's right edge (rX + rW, 634 at design size).
    BUTTON('Chg colour...'),AT(396,288,72,12),USE(?ChgColorBtn)
    BUTTON('Sort: rule#'),AT(472,288,66,12),USE(?SortBtn)
    BUTTON('&<< Prev'),AT(542,288,44,12),USE(?PrevChg)
    BUTTON('&Next >'),AT(590,288,44,12),USE(?NextChg)
    LIST,AT(262,300,372,78),USE(?ChangeList),VSCROLL,FROM(ChgQ),FORMAT('40R(2)~L' & |
        'ine~@n5@50R(2)~Rule~@n6@340L(2)~Change~@s255@'),ALRT(MouseLeft2)
  END

NameW WINDOW('Save profile'),AT(,,210,52),CENTER,MODAL,SYSTEM,GRAY,FONT('Segoe UI',9)
    PROMPT('Name:'),AT(6,8)
    ENTRY(@s50),AT(34,6,168,12),USE(profNm)
    BUTTON('&OK'),AT(104,32,45,14),USE(?OkBtn),DEFAULT
    BUTTON('&Cancel'),AT(154,32,45,14),USE(?CancelBtn)
  END

! the rule workbench - second modal window with lists (a
!    flagged risk area). FIXED size (no RESIZE = no reflow risk). One rule per visit
!    (ratified). NameW/PasteW modal pattern: local accept loop, break on Save/Cancel.
WbW WINDOW('Rule workbench - user rules in VitStyle.rules.txt'),AT(,,480,326),CENTER,MODAL,SYSTEM,GRAY, |
      FONT('Segoe UI',9)
    PROMPT('Rule:'),AT(6,6),USE(?WbP1)
    LIST,AT(30,4,300,12),USE(wbPickTxt),DROP(15),FROM(WbrQ),FORMAT('300L(2)@s70@') ! pick-to-edit wired on EVENT:NewSelection of a DROP - if it never fires, add an Edit button
    PROMPT('Group:'),AT(340,6),USE(?WbP2)
    ENTRY(@s50),AT(366,4,108,12),USE(wbGrp)
    PROMPT('Rule text - pattern ==> replacement, then optional WHERE / NOTE(...) / SKIP / ONCE:'),AT(6,20),USE(?WbP3)
    TEXT,AT(6,30,468,44),USE(draftVar),VSCROLL
    BUTTON('&Lint'),AT(6,78,44,14),USE(?WbLintBtn)
    BUTTON('&Test'),AT(54,78,44,14),USE(?WbTestBtn)
    BUTTON('&Save'),AT(388,78,44,14),USE(?WbSaveBtn)
    BUTTON('Cancel'),AT(436,78,38,14),USE(?WbCancelBtn)
    PROMPT('Lint (combined shipped + user + draft; zero errors required to save):'),AT(6,96),USE(?WbP4)
    TEXT,AT(6,106,468,40),USE(wbLintTxt),VSCROLL,READONLY
    PROMPT('Draft fires on the current preview source:'),AT(6,150),USE(?WbChgHdr)
    LIST,AT(6,160,468,48),USE(?WbChgList),VSCROLL,FROM(WbChgQ),FORMAT('40R(2)~Lin' & |
        'e~@n5@420L(2)~Change~@s255@'),ALRT(MouseLeft2)
    PROMPT('Before'),AT(6,212),USE(?WbP5)
    PROMPT('After (draft applied on top of the current selection)'),AT(242,212),USE(?WbP6)
    LIST,AT(6,222,232,98),USE(?WbBefList),VSCROLL,FROM(WbBefQ),FORMAT('36R(2)~Lin' & |
        'e~@n5@600L(2)*~Source~@s255@')
    LIST,AT(242,222,232,98),USE(?WbAftList),VSCROLL,FROM(WbAftQ),FORMAT('36R(2)~L' & |
        'ine~@n5@600L(2)*~Transformed~@s255@')
  END

dbg StringTheory ! for trace

  CODE
  rulesFn.setValue(command('1'))
  rulesFn.trim()
  if ~rulesFn._DataEnd
    ! was a SILENT fallback to 'draft-rules-v12.txt'. It stayed at v12 while the rule file
    ! moved to v15, so a no-argument VitStyle previewed a two-version-old rule set without saying so -
    ! and the preview then honestly disagreed with a v15 batch run. Name the file, every time.
    rulesFn.setValue('vitrules.txt')
    if ~exists(rulesFn.getValue())
      Message('VitStyle: no rule file given, and the default ' & clip(rulesFn.getValue()) & |
              ' is not in this directory.||Run:  VitStyle <<rulefile>', 'VitStyle', ICON:Exclamation)
      halt(1) ! fatal path: a bare halt() exits 0 and scripts read SUCCESS (#14)
    end
    Message('No rule file given - using ' & clip(rulesFn.getValue()) & '.'                & |
            '||Run  VitStyle <<rulefile>  to choose a different one.', 'VitStyle', ICON:Asterisk)
  end
  profFn.setValue(ExeDir())
  profFn.append('VitStyle.profiles.txt')
  userFn.setValue(ExeDir())                                    ! the user rulefile lives next to the exe,
  userFn.append('VitStyle.rules.txt')                          !        like the profile file
  uiFn.setValue(ExeDir())                                      ! UI prefs (changed-line colour)
  uiFn.append('VitStyle.ui.txt')
  LoadUiPrefs()

  LoadEverything()
  eng.Init(rl)                                                 ! preview engine shares the loaded rules + resolver
  eng.progressFn = ''                                          ! no heartbeat file for the interactive preview
  engReady = 1
  SetDemo()                                                    ! start with the built-in demo source

  open(W)
  0{PROP:Text} = 'VitStyle ' & vr:version & ' - rule selection & live preview'
                                                               ! the version in the title, from the SAME
                                                               !   equate every report prints, so the two
                                                               !   cannot drift. Set here rather than in
                                                               !   the WINDOW literal for exactly that.
  0{PROP:MinWidth}  = 440                                      ! A FLOOR THE RESIZE CANNOT BE ASKED TO COPE WITH.
  0{PROP:MinHeight} = 260                                      !   The button row above the change list narrows as the
                                                               !   window does, but only to 85% - past that the captions
                                                               !   clip, which is what it was reported for. 580 is where
                                                               !   85% still fits beside the 'Changes (click a row...)'
                                                               !   prompt; 300 keeps the preview panes above their own
                                                               !   40-unit floor with the change list and the row below.
                                                               !   Set BEFORE the maximise so the first reflow already
                                                               !   has them.
  0{PROP:Maximize} = 1                                         ! open MAXIMIZED (PROP:Maximize on the window) - L request
  ResizeControls()                                             ! reflow the preview lists to the maximized client size
  post(EVENT:Sized)                                            ! one reflow from INSIDE the loop, so the
                                                               !   opening layout is settled whatever order
                                                               !   the maximise and the first paint happen
                                                               !   in. Cheap, and it makes startup
                                                               !   deterministic rather than order-dependent.
  syncLock = 0 ; lastSync = 0 ; progBef = 1 ; progAft = 1      ! S4 sync baselines
  BuildStyleList()
  BuildDisplay()                                               ! ends in RefreshPreview via ApplyOverrides? no - call preview explicitly:
  RefreshPreview()
  accept
    case accepted()
    of ?ApplyBtn
      x = choice(?styPickTxt)                                  ! DROP selection read - if 0 here, wire EVENT:NewSelection on the list instead
      if x
        get(StyQ, x)
        if ~errorcode()
          curStyle = sq:nm
          free(OvrQ)                                           ! picking a style resets individual overrides (design 5)
          ApplyOverrides()
        end
      end
    of ?ToggleBtn
      ToggleCurrent()
    of ?ChgColorBtn                                            ! pick fills A then B; persists in VitStyle.ui.txt
      if COLORDIALOG('Changed-line colour A', chgColor)
        if COLORDIALOG('Changed-line colour B (alternating blocks)', chgColor2) then.
        SaveUiPrefs()
        RefreshPreview()                                       ! re-mark with the new colours
      end
    of ?SortBtn
      sortMode = 1 - sortMode                                  ! toggle rule# <-> line#
      SortChanges()
    of ?PrevChg
      if ~records(ChgQ) then cycle.
      x = choice(?ChangeList)                                  ! 0 if the change list was never clicked
      if x > 1 then x -= 1 else x = 1.
      select(?ChangeList, x)
      GotoChange()
    of ?NextChg
      if ~records(ChgQ) then cycle.
      x = choice(?ChangeList)
      if x < records(ChgQ) then x += 1 else x = records(ChgQ). ! x=0 -> 1 (first)
      select(?ChangeList, x)
      GotoChange()
    of ?OpenBtn
      LoadSourceFile()
    of ?DemoBtn
      SetDemo()
      RefreshPreview()
    of ?PasteBtn
      PasteSnippet()
    of ?SaveBtn
      SaveProfile()
    of ?WbBtn
      Workbench() ! modal - returns after Save/Cancel; Save already refreshed everything
    of ?CloseBtn
      break
    end
    case event()
    of EVENT:AlertKey
      if field() = ?GrpList and keycode() = MouseLeft2
        ToggleCurrent()
      elsif field() = ?ChangeList and keycode() = MouseLeft2
        GotoChange()
      end
    of EVENT:NewSelection
      if field() = ?GrpList
        ShowDoc()
      elsif field() = ?ChangeList
        GotoChange()
      ! ---- pane->pane click sync (DEBOUNCE approach) ----
      ! The echo of our own programmatic select() lands within a few centiseconds, so a
      ! CLOCK() debounce skips it (and any burst), breaking the ping-pong that the earlier
      ! flag approaches could not. syncLock guards re-entrancy; SyncPanes must NOT test it.
      ! The progBef/progAft baseline stops a same-row no-op from re-syncing.
      elsif field() = ?BeforeList                                                              ! select a source line -> scroll After to its aligned line
        if ~syncOn or syncLock or (clock() >= lastSync and clock() - lastSync < 5) then cycle. ! syncOn=0 -> pane sync OFF (usable, no loop). Flip syncOn to debug.
        syncLock = 1
        syncRow = choice(?BeforeList)
        if syncRow and syncRow <> progBef
          progBef = syncRow
          SyncPanes(1)
          lastSync = clock()
        end
        syncLock = 0
      elsif field() = ?AfterList
        if ~syncOn or syncLock or (clock() >= lastSync and clock() - lastSync < 5) then cycle.
        syncLock = 1
        syncRow = choice(?AfterList)
        if syncRow and syncRow <> progAft
          progAft = syncRow
          SyncPanes(2)
          lastSync = clock()
        end
        syncLock = 0
      end
    of EVENT:Sized        orof EVENT:Maximized orof EVENT:Restored
      ! *** THESE ARE THREE SEPARATE EVENTS AND THE WINDOW SENDS THE RIGHT ONE. *** LRM: Sized
      ! is "the user has RESIZED the window", Maximized is "the user has MAXIMIZED" and Restored
      ! is "restored the window's previous size". Handle Sized alone and maximising or restoring
      ! reflows nothing, so a maximised window lays itself out for whatever size it happened to
      ! have at startup and leaves dead grey down the right and along the bottom. All three are
      ! caught here, on purpose.
      ResizeControls()
    of EVENT:CloseWindow
      break
    end
  end
  close(W)
  return

! ====================================================================================
LoadEverything PROCEDURE()
e  LONG,AUTO
i  LONG,AUTO
  code
  rl.LoadFile(rulesFn.getValue()) ! load errors surface via the issues list below

  ! ---- the user rulefile loads NON-FATALLY - validate the combined set on the
  !      SCRATCH instance first; only a clean set is appended to the live rl. A broken
  !      user file -> message + skipped for the session; the workbench still opens (its
  !      lint/test rebuild wbRl from disk, so the user can fix and re-save from there).
  userLoaded = 0
  if exists(userFn.getValue())
    wbRl.LoadFile(rulesFn.getValue())
    wbRl.LoadUserRules(userFn.getValue())
    wbRl.Lint()
    if wbRl.ErrorCount()
      scratch.setValue('VitStyle: ' & wbRl.ErrorCount() & ' error(s) with ' & clip(userFn.getValue()) & |
                       ' loaded - USER RULES SKIPPED this session.|Fix them in the Workbench or an editor.')
      loop i = 1 to records(wbRl.issues)
        get(wbRl.issues, i)
        if wbRl.issues.sev <> vr:sevError then cycle.
        if wbRl.issues.lineNo >= vr:userBase                    ! workbench display = U<n>
          scratch.append('|U' & (wbRl.issues.lineNo - vr:userBase) & ': ' & clip(wbRl.issues.msg))
        else
          scratch.append('|line ' & wbRl.issues.lineNo & ': ' & clip(wbRl.issues.msg))
        end
        if scratch._DataEnd > 700 then break.
      end
      message(scratch.getValue(), 'VitStyle', ICON:Exclamation) ! NON-fatal (the shipped-file halt below stays)
    else
      rl.LoadUserRules(userFn.getValue())                       ! clean -> append to the LIVE set (load order:
      userLoaded = 1                                            !   shipped, then user, then the profile styles)
    end
  end

  if exists(profFn.getValue())
    e = rl.ErrorCount()                                         ! parse errors so far belong to the rules (+user) load
    rl.LoadStyleFile(profFn.getValue())
    if rl.ErrorCount() > e
      ! profiles are machine-written convenience - a broken one must not brick
      ! startup. Without this, a broken profile - an over-long member list, say -
      ! fires the fatal halt below, whose message blames the RULE file: the user is
      ! sent to fix the wrong one, and VitStyle refuses to start until the profiles
      ! file is hand-edited. Report against the RIGHT file, then rebuild WITHOUT the
      ! profile layer - the same non-fatal treatment the user rulefile gets above.
      scratch.setValue('VitStyle: ' & rl.ErrorCount() - e & ' error(s) in ' & clip(profFn.getValue()) & |
                       ' (your saved profiles) - PROFILES SKIPPED this session.'                      & |
                       '|Fix or delete that file; until then the style list shows shipped styles only.')
      message(scratch.getValue(), 'VitStyle', ICON:Exclamation)
      rl.LoadFile(rulesFn.getValue()) ! full rebuild, no profile layer
      if userLoaded then rl.LoadUserRules(userFn.getValue()).
    end
  end
  rl.Lint()
  e = rl.ErrorCount()
  if e
    scratch.setValue('VitStyle: ' & e & ' error(s) in ' & clip(rulesFn.getValue()) & ' - fix the rule file first.')
    loop i = 1 to records(rl.issues)
      get(rl.issues, i)
      if rl.issues.sev <> vr:sevError then cycle.
      scratch.append('|line ' & rl.issues.lineNo & ': ' & clip(rl.issues.msg))
      if scratch._DataEnd > 700 then break.
    end
    message(scratch.getValue(), 'VitStyle', ICON:Exclamation)
    halt(1)                                    ! fatal path: a bare halt() exits 0 and scripts read SUCCESS (#14)
  end
  if rl.lastUsed and rl.FindStyle(rl.lastUsed) ! reopen where the user left off (5c)
    curStyle = rl.lastUsed
  end
  rl.Resolve(curStyle, '', '')
  HarvestDocs()
  rulesLbl = clip(rulesFn.getValue()) & '   (' & records(rl.groups) & ' groups, ' & records(rl.rules) & ' rules' & |
             choose(userLoaded = 1, ' incl user', '') & ')'

! ====================================================================================
RefreshProfiles PROCEDURE()
i  LONG,AUTO
  code
  loop i = records(rl.styles) to 1 by -1 ! drop old profile rows (plain STRING fields - nothing to dispose)
    get(rl.styles, i)
    if rl.styles.isProfile then delete(rl.styles).
  end
  if exists(profFn.getValue())
    rl.LoadStyleFile(profFn.getValue())
  end

! ====================================================================================
! Comment block immediately preceding each GROUP line -> DocsQ. Blank lines and
! rule lines reset the accumulator, so only the directly-attached block counts.
! ------------------------------------------------------------------------------------
HarvestDocs PROCEDURE()
i    LONG,AUTO
j    LONG,AUTO
p    LONG,AUTO
line StringTheory
body StringTheory ! the note text, indent intact
acc  StringTheory
up   StringTheory
nm   StringTheory
  code
  free(DocsQ)
  if not raw.LoadFile(rulesFn.getValue()) then return.
  raw.LineEndings(st:unix)
  raw.split('<10>')
  loop i = 1 to raw.records()
    line.setValue(raw.getLine(i))
    line.trim()
    if ~line._DataEnd
      acc.free()
      cycle
    end
    if line.valuePtr[1] = '!'
      line.setValue(line.valuePtr[2 : line._DataEnd])   ! strip the bang; keep the text
      body.setValue(line)                               ! KEEP THE INDENT OF AN EXAMPLE.
      if body._DataEnd and body.valuePtr[1] = ' '       !   The line arrives already trimmed at
        body.setValue(body.valuePtr[2 : body._DataEnd]) ! both ends, so only ONE leading space
      end                                               !   is dropped - the space that separates
                                                        !   the bang from the text. Whatever is
                                                        !   left was put there on purpose, and
                                                        !   for a note whose example is a BLOCK
                                                        !   the indent IS the example: trimming
                                                        !   it showed the user if x / y = 1 / end
                                                        !   flush left, which is the one thing
                                                        !   the note was drawing.
      line.trim()                                       ! the ruler test wants it flush
      if line._DataEnd and (line.valuePtr[1] = '-' or line.valuePtr[1] = '=')
        j = 1                                           ! A RULER IS ALL DASHES, not merely
        loop while j <= line._DataEnd                   !   STARTING with one. Testing the first
          if line.valuePtr[j] <> '-' and |              !   byte alone ate every example line in
             line.valuePtr[j] <> '=' then break.        !   the file - `--group=analysis` and the
          j += 1                                        !   like - so notes that introduced a
        end                                             !   switch showed the user a dangling
        if j > line._DataEnd then cycle.                !   colon and no switch.
      end
      if acc._DataEnd then acc.append('<13,10>').
      acc.append(body)
      if acc._DataEnd > 1900 then acc.setLength(1900).
      cycle
    end
    up.setValue(line)
    up.upper()
    if up._DataEnd > 6 and up.valuePtr[1 : 6] = 'GROUP '
      nm.setValue(line.valuePtr[7 : line._DataEnd])
      p = nm.findByte(44)                               ! <comma>
      if p then nm.setLength(p - 1).
      nm.trim()
      clear(DocsQ)
      dq:name = nm.getValue()
      dq:txt  = acc.getValue()
      add(DocsQ)
    end
    acc.free()
  end

! ====================================================================================
BuildStyleList PROCEDURE()
i  LONG,AUTO
  code
  free(StyQ)
  clear(StyQ)
  sq:shown = '(file defaults)'
  sq:nm    = ''
  add(StyQ)
  loop i = 1 to records(rl.styles) ! shipped first, then profiles (load order gives that)
    get(rl.styles, i)
    clear(StyQ)
    sq:shown = clip(rl.styles.name) & choose(rl.styles.isProfile = 1, '  (profile)', '')
    sq:nm    = rl.styles.name
    add(StyQ)
    if upper(rl.styles.name) = upper(curStyle)
      styPickTxt = sq:shown
    end
  end
  if ~curStyle then styPickTxt = '(file defaults)'.
  display()

! ====================================================================================
BuildDisplay PROCEDURE()
g    LONG,AUTO
n    LONG
sv   LONG,AUTO
  code
  sv = choice(?GrpList)
  free(DispQ)
  loop g = 1 to records(rl.groups)
    get(rl.groups, g)
    clear(DispQ)
    if rl.groups.choiceName
      pq:state  = choose(rl.groups.selected = 1, '  (o)', '  ( )')
    else
      pq:state  = choose(rl.groups.selected = 1, '  [X]', '  [ ]')
    end
    pq:name   = rl.groups.name
    pq:choice = rl.groups.choiceName
    pq:info   = '' & (rl.groups.handCount + rl.groups.autoCount)
    pq:grpRow = g
    add(DispQ)
  end
  loop g = 1 to records(rl.rules)
    get(rl.rules, g)
    if ~rl.rules.groupId then n += 1.
  end
  clear(DispQ)
  pq:state  = '   - '
  pq:name   = '(ungrouped rules)'
  pq:choice = 'always on'
  pq:info   = '' & n
  pq:grpRow = 0
  add(DispQ)
  selSt.free()
  rl.SelectionTable(selSt)
  effTxt = selSt.getValue()
  if sv then select(?GrpList, sv). ! keep the highlight through a rebuild
  display()
  ShowDoc()

! ====================================================================================
ApplyOverrides PROCEDURE()
grps  StringTheory
nogr  StringTheory
  code
  OverrideLists(grps, nogr)        ! shared with the workbench test (same selection = honesty)
  rl.Resolve(curStyle, grps.getValue(), nogr.getValue())
  BuildDisplay()
  RefreshPreview()                 ! selection changed -> re-run the live preview (same resolver, honesty invariant)

! ====================================================================================
! OvrQ -> comma lists for Resolve. Factored from ApplyOverrides so the workbench
! test resolves its SCRATCH set under the SAME style + overrides as the live preview
! (plus the draft group) - the honesty invariant extended to drafts.
! ------------------------------------------------------------------------------------
OverrideLists PROCEDURE(StringTheory pGrps, StringTheory pNogr)
i    LONG,AUTO
  code
  loop i = 1 to records(OvrQ)      ! row order = click order; Resolve applies picks then unpicks
    get(OvrQ, i)
    get(rl.groups, oq:grpRow)
    if errorcode() then cycle.
    if oq:mode = 1
      if pGrps._DataEnd then pGrps.append(',').
      pGrps.append(clip(rl.groups.name))
    else
      if pNogr._DataEnd then pNogr.append(',').
      pNogr.append(clip(rl.groups.name))
    end
  end

! ====================================================================================
ToggleCurrent PROCEDURE()
r    LONG,AUTO
g    LONG,AUTO
m    BYTE,AUTO
i    LONG,AUTO
  code
  r = choice(?GrpList)
  if ~r then return.
  get(DispQ, r)
  if errorcode() or ~pq:grpRow then return. ! the (ungrouped) footer row toggles nothing
  g = pq:grpRow
  get(rl.groups, g)
  m = choose(rl.groups.selected = 1, 2, 1)  ! flip the RESOLVED state
  loop i = 1 to records(OvrQ)               ! one row per group, re-added at the END so the
    get(OvrQ, i)                            ! latest click wins inside its list
    if oq:grpRow = g then delete(OvrQ) ; break.
  end
  clear(OvrQ)
  oq:grpRow = g
  oq:mode   = m
  add(OvrQ)
  ApplyOverrides()

! ====================================================================================
ShowDoc PROCEDURE()
r  LONG,AUTO
i  LONG,AUTO
  code
  r = choice(?GrpList)
  docTxt = ''
  if r
    get(DispQ, r)
    if ~errorcode() and pq:grpRow
      loop i = 1 to records(DocsQ)
        get(DocsQ, i)
        if upper(dq:name) = upper(pq:name)
          docTxt = dq:txt
          break
        end
      end
      if ~docTxt then docTxt = clip(pq:name) & ': no description block above its GROUP line.'.
    elsif ~errorcode()
      docTxt = 'Rules outside any GROUP - always active, not selectable.'
    end
  end
  display(?docTxt)

! ====================================================================================
! FULL-spelling member list of the CURRENT resolved state: every choice's winner
! by name (or -defaultMember when the choice sits at none), every standalone that
! diverges... plus ON standalones spelled explicitly. Full spelling survives
! future changes to the file defaults.
! ------------------------------------------------------------------------------------
CurrentMembers PROCEDURE()
g      LONG,AUTO
g2     LONG,AUTO
first  LONG,AUTO
chcU   STRING(vr:maxName),AUTO
win    STRING(vr:maxName),AUTO
def    STRING(vr:maxName),AUTO
nmG    STRING(vr:maxName),AUTO
selG   BYTE,AUTO
offG   BYTE,AUTO
mems   StringTheory
  code
  mems.free()
  loop g = 1 to records(rl.groups)
    get(rl.groups, g)
    if rl.groups.choiceName
      chcU = upper(rl.groups.choiceName)
      first = 1
      loop g2 = 1 to g - 1
        get(rl.groups, g2)
        if upper(rl.groups.choiceName) = chcU then first = 0 ; break.
      end
      if ~first then cycle.
      win = ''
      def = ''
      loop g2 = 1 to records(rl.groups)
        get(rl.groups, g2)
        if upper(rl.groups.choiceName) <> chcU then cycle.
        if rl.groups.selected then win = rl.groups.name.
        if rl.groups.isDefault then def = rl.groups.name.
      end
      if win
        if mems._DataEnd then mems.append(', ').
        mems.append(clip(win))
      elsif def
        if mems._DataEnd then mems.append(', ').
        mems.append('-' & clip(def))
      end
    else
      nmG  = rl.groups.name
      selG = rl.groups.selected
      offG = rl.groups.isOff
      if selG
        if mems._DataEnd then mems.append(', ').
        mems.append(clip(nmG))
      elsif ~offG ! off although the file default is on -> negate
        if mems._DataEnd then mems.append(', ').
        mems.append('-' & clip(nmG))
      end
    end
  end
  return choose(mems._DataEnd < 1, '', mems.valuePtr[1 : mems._DataEnd])

! ====================================================================================
SaveProfile PROCEDURE()
mems  StringTheory
  code
  profNm = ''
  nameOk = 0
  open(NameW)
  accept
    case accepted()
    of ?OkBtn
      if ~rl.IsGroupName(profNm)
        message('Profile names start with a letter and use letters/digits/_/:/- only.', 'VitStyle', ICON:Exclamation)
        select(?profNm)
        cycle
      end
      nameOk = 1
      break
    of ?CancelBtn
      break
    end
    if event() = EVENT:CloseWindow then break.
  end
  close(NameW)
  if ~nameOk then return.
  mems.setValue(CurrentMembers())
  if ~mems._DataEnd
    message('Nothing to save: the whole file is at its defaults with no groups.', 'VitStyle', ICON:Asterisk)
    return
  end
  if mems._DataEnd > size(rl.styles.members)
    ! a STYLE line longer than the engine's member buffer is a LOAD-time error,
    ! so writing it would poison the profiles file for the next launch. Refuse here,
    ! where the user can still do something about it.
    message('This selection spells out to ' & mems._DataEnd & ' characters of group names - more than' & |
            ' the ' & size(rl.styles.members) & ' a STYLE line can hold, so it cannot be saved as a'   & |
            ' profile.||Turn some groups off, or shorten group names in the rule file.',                 |
            'VitStyle', ICON:Exclamation)
    return
  end
  if ~WriteProfileLine(profNm, mems.getValue()) then return. ! the failure box has already shown -
                                                             !   do not reload, reselect and then claim success
  RefreshProfiles()
  rl.Lint()                                                  ! re-validate the new profile against the groups
  curStyle = profNm
  free(OvrQ)                                                 ! the profile now IS the selection
  ApplyOverrides()
  BuildStyleList()
  message('Saved profile ' & clip(profNm) & ' to|' & clip(profFn.getValue())                                        & |
          '||Batch use:|VitTransform <rules> <src> <out> --stylefile=VitStyle.profiles.txt --style=' & clip(profNm) & |
          choose(userLoaded = 1, ' --userrules=VitStyle.rules.txt', ''),                                              |
          'VitStyle', ICON:Asterisk)

! ====================================================================================
! Read-modify-write the profile file: replace this profile's STYLE line if it
! exists, keep everything else, refresh the LASTUSED marker at the end.
! (Hand-written continuation lines inside profFn are not reassembled - the file
! is normally machine-written, one STYLE per line.)
! ------------------------------------------------------------------------------------
WriteProfileLine PROCEDURE(STRING pName, STRING pMembers)
i     LONG,AUTO
line  StringTheory
up    StringTheory
outSt StringTheory
have  StringTheory
nmU   STRING(vr:maxName),AUTO
  code
  nmU = upper(pName)
  if exists(profFn.getValue()) and have.LoadFile(profFn.getValue())
    have.LineEndings(st:unix)
    have.split('<10>')
    loop i = 1 to have.records()
      line.setValue(have.getLine(i))
      up.setValue(line)
      up.trim()
      up.upper()
      if up._DataEnd > 9 and up.valuePtr[1 : 9] = 'LASTUSED ' then cycle. ! rewritten below
      if up._DataEnd > 6 and up.valuePtr[1 : 6] = 'STYLE '
        up.setValue(up.valuePtr[7 : up._DataEnd])
        up.trim()
        ! this profile already saved? whole-word match (a saved MINE must not
        ! swallow MINE2): the char after the name must be a space or '='
        if up._DataEnd > len(clip(nmU)) and up.valuePtr[1 : len(clip(nmU))] = nmU
          if up.valuePtr[len(clip(nmU)) + 1] = ' ' or up.valuePtr[len(clip(nmU)) + 1] = '='
            cycle                                                         ! replaced below
          end
        end
      end
      outSt.append(line.getValue() & '<13,10>')
    end
  else
    outSt.append('! VitStyle.profiles.txt - saved profiles (STYLE lines) + LASTUSED marker.<13,10>')
    outSt.append('! Written by VitStyle; safe to hand-edit. Names only, never line numbers.<13,10>')
  end
  outSt.append('STYLE ' & clip(pName) & ' = ' & clip(pMembers) & '<13,10>')
  outSt.append('LASTUSED ' & clip(pName) & '<13,10>')
  if not outSt.SaveFile(profFn.getValue())
    message('Could not save ' & clip(profFn.getValue()) & '||' & outSt.LastError, 'VitStyle', ICON:Exclamation)
    return 0 ! callers must not proceed as if saved
  end
  return 1

! ====================================================================================
ExeDir PROCEDURE()
p   StringTheory
i   LONG,AUTO
  code
  p.setValue(command('0'))
  loop i = p._DataEnd to 1 by -1
    if p.valuePtr[i] = '\' then return p.valuePtr[1 : i].
  end
  ! command('0') can come back as a BARE NAME - a launch that found the exe on the PATH
  ! rather than by path - and then there is no directory here to return. The empty string makes
  ! the three side files (profiles, user rules, UI prefs) CURRENT-DIRECTORY relative for that
  ! launch, so a VitStyle started from elsewhere writes a second set somewhere else and appears
  ! to have forgotten its profiles. That is the behaviour, said out loud rather than left to be
  ! inferred from an empty return; changing it needs the exe path from the OS, which is a
  ! Windows API call this file does not otherwise make.
  return '' ! = current directory

! ====================================================================================
! re-run the live preview on the current source buffer under the CURRENT resolved
! selection. TransformText is the SAME pipeline a batch run uses (honesty invariant),
! so the After pane is exactly what VitTransform would write under this selection.
! ------------------------------------------------------------------------------------
RefreshPreview PROCEDURE()
  code
  if ~engReady then return.
  if ~srcBuf._DataEnd
    free(PvBefQ) ; free(PvAftQ) ; free(ChgQ)
    ?BeforeList{PROP:Selected} = 0 ; ?AfterList{PROP:Selected} = 0
    progBef = 0 ; progAft = 0
    display(?BeforeList) ; display(?AfterList) ; display(?ChangeList)
    ?AfterHdr{PROP:Text} = 'After (live)'
    return
  end
  logBuf.free()      ! TransformText APPENDS to the log (like TransformFile) - reset per preview run
  prevChg = eng.TransformText(srcBuf, outBuf, logBuf)
  BuildPreviewLists(srcBuf, outBuf, logBuf)
  ?AfterHdr{PROP:Text} = 'After (live) - ' & prevChg & ' change(s)'
  display(?fidelity) ! fidelity variable was set by the caller (SetDemo/LoadSourceFile/PasteSnippet)

! ====================================================================================
! Split before/after into per-line queues; align the panes line-by-line (aln/bln);
! mark changed lines on BOTH panes by comparing each line with its ALIGNED counterpart.
! The change list is descriptive (rule + line + summary), from the rule log.
! ------------------------------------------------------------------------------------
BuildPreviewLists PROCEDURE(StringTheory pSrc, StringTheory pOut, StringTheory pLog)
befS    StringTheory
aftS    StringTheory
logS    StringTheory
line    StringTheory
line2   StringTheory
i       LONG,AUTO
j       LONG,AUTO
lnNo    LONG,AUTO
ruleNo  LONG,AUTO
chgRow  LONG,AUTO                                             ! 1 = this log line describes a CHANGE, 0 = a note about one
hdrW    LONG,AUTO                                             ! how many words the header actually used - only those are stripped
dw      LONG,AUTO                                             ! header-strip loop
mi      LONG,AUTO                                             ! alignment: before index
mj      LONG,AUTO                                             ! alignment: after index
mk      LONG,AUTO
found   LONG,AUTO
nB      LONG,AUTO
nA      LONG,AUTO
tot     LONG,AUTO                                             ! anchor search: total distance di+dj
di      LONG,AUTO
dj      LONG,AUTO
adi     LONG,AUTO                                             ! chosen anchor offsets
adj     LONG,AUTO
mk2     LONG,AUTO                                             ! block map: candidate offset in the opposite block
pk      LONG,AUTO                                             ! block map: previous pick (monotone floor)
pt      LONG,AUTO                                             ! block map: proportional slot
b2      LONG,AUTO                                             ! block map: best candidate so far
bl2     LONG,AUTO                                             ! block map: best common-prefix length so far
bd      LONG,AUTO                                             ! block map: best distance-to-slot so far
cp      LONG,AUTO                                             ! block map: this candidate's common-prefix length
d2      LONG,AUTO                                             ! block map: this candidate's distance to the slot
lp      LONG,AUTO                                             ! block map: char loop
minL    LONG,AUTO                                             ! block map: shorter of the two stripped lines
tot2    LONG,AUTO                                             ! anchor search: adaptive range for this divergence
farOff  LONG,AUTO                                             ! anchor search: 1 = full-range scan missed, stop paying for far scans until an anchor resets it
mapOk   LONG,AUTO                                             ! engine map: 1 = aln/bln came from eng.tk.lineMap (walk skipped)
s2      LONG,AUTO                                             ! engine map: source line for the After row in hand
lastA2  LONG,AUTO                                             ! engine map: carry for combined-away source lines
ind     LONG,AUTO                                             ! unit scan: leading-space count of the raw line
baseI   LONG,AUTO                                             ! unit scan: block base indent (first non-blank line)
isCont  LONG,AUTO                                             ! unit scan: 1 = this line continues the open unit
ub      LONG,AUTO                                             ! unit map: current unit index while assigning
zeb     LONG,AUTO                                             ! zebra: 0 = colour A block, 1 = colour B block
lastChg LONG,AUTO                                             ! zebra: last changed row seen (contiguity test)
col     LONG,AUTO                                             ! zebra: this After row's inherited colour
pcol    LONG,AUTO                                             ! zebra: previous changed After row's colour (insert carry)
UBQ    QUEUE                                                  ! unit starts, BEFORE side of the current block (0-based offsets)
ofs      LONG
       END
UAQ    QUEUE                                                  ! unit starts, AFTER side
ofs      LONG
       END
  code
  free(PvBefQ) ; free(PvAftQ) ; free(ChgQ)
  befS.setValue(pSrc) ; befS.LineEndings(st:unix) ; befS.split('<10>')
  aftS.setValue(pOut) ; aftS.LineEndings(st:unix) ; aftS.split('<10>')

  ! change list + changed-line set from the log ('rule N line L: before ==> after')
  logS.setValue(pLog)
  if debugIt then logS.SaveFile('logFile.txt').               ! debug dump of the raw engine log - see debugIt
  logS.LineEndings(st:unix)
  logS.split('<10>',,,,st:clip,st:left)
  loop i = 1 to logS.records()
    line.setValue(logS.getLine(i))
    line.split(' ')
    line.RemoveLines()
    ! A LINE WITH NO WORDS IS NOT A CHANGE. Every engine log line ends with <13,10>, so
    ! splitting the whole log on <10> always yields one FINAL, EMPTY record - StringTheory.Split
    ! adds empty pieces deliberately (AddLine banks a one-space entry with Lines.Empty set), and
    ! pClip does not drop them. Before that record fell out because a row whose first word
    ! was not 'rule' was dropped; now that such rows are KEPT - AutoCheck's ADD lines and the
    ! hoist formats are real changes and were being hidden - the empty record became a row with
    ! no line, no rule and no text, and `sort(ChgQ, +cq:ln, ...)` floated it to the TOP of the
    ! list. Guard on the WORD COUNT, not on the first word: that drops blank lines only and
    ! leaves every worded line, whatever it says, which is the point of guarding on the count.
    if ~line.records() then cycle.

    ! A CHANGE, OR ONLY A NOTE ABOUT ONE. The engine writes both into this one log with
    ! nothing marking which is which, so the shape is all there is to go on. A change is
    ! `rule <n> line <m>: ...`, `BUILTIN <Name> line <m>: ...`, one of AutoCheck's two
    ! attribute lines, or a hoist line. A NOTE is the per-pass summary, a `kept`/`skipped`
    ! count, a WARNING, an ERROR or the file header - and listing those as changes is what
    ! put two `Line 0  Rule 0` rows ABOVE the real one on a pasted snippet, which has no
    ! CODE statement and so makes UnusedVars log a skip on every pass.
    ! THE TEST IS THE SECOND WORD, and it fails SAFE - anything it cannot place is KEPT:
    !   every note spells its builtin `<Name>:` with the colon attached, because the text
    !   after it is prose about the file; every CHANGE spells it `<Name> line <m>:`, with
    !   the colon on the NUMBER. No change form ends its second word with a colon, and a
    !   `rule` line is never tested at all.
    chgRow = 1
    if lower(line.getline(1)) <> 'rule'
      ruleNo = 0
      if lower(line.getLine(1)) <> 'builtin' then chgRow = 0. ! header, WARNING, ERROR, file summary
      line.SetValueFromLine(2)
      if line.EndsWith(':')                  then chgRow = 0. ! BUILTIN <Name>: <prose about the file>
      line.SetValueFromLine(3)
      if line.StartsWith('(')                then chgRow = 0. ! BUILTIN <Name> (<style>): <summary>
      if upper(line.getValue()) = 'WHY'      then chgRow = 0. ! BUILTIN AutoCheck WHY...  - a diagnostic
    else
      ruleNo = line.getLine(2)
    end

    hdrW = 0
    if line.getLine(3) = 'line'
      line.setValueFromLine(4)
      if line.EndsWith('#') then line.AdjustLength(-1).
      lnNo = line.getValue()
      hdrW = 4                                                ! `rule n line m:` / `BUILTIN Name line m:`
    else
      lnNo = 0
    end

    if ~chgRow then cycle.

    ! a row whose third word is not 'line' - AutoCheck's ADD lines, the END-hoist
    ! formats - must NOT be dropped here: the list would show fewer changes than the header
    ! counted, and the ones it hid would be real. They are kept with no line number instead;
    ! the click handler already returns on ~cq:ln, so such a row simply does not navigate.
    clear(ChgQ)
    cq:ln   = lnNo
    cq:rule = ruleNo
    ! STRIP ONLY THE WORDS THE HEADER ACTUALLY USED. This deleted four unconditionally,
    ! which is right for `rule n line m:` and wrong for everything else - on a line that
    ! does not carry that header it ate four words of real text, which is why such a row
    ! read as a sentence starting in the middle. hdrW is 0 when no header was recognised,
    ! and the whole line is then kept as its own description.
    loop dw = hdrW to 1 by -1
      line.deleteLine(dw)
    end
    line.join(' ')
    cq:desc = line.getValue()                                 ! text after the ':', or the whole line
    add(ChgQ)
  end

  loop i = 1 to befS.records()
    clear(PvBefQ)
    bq:ln = i
    bq:txt = '  ' & befS.getLine(i)
    bq:txtFg = COLOR:None ; bq:txtBg = COLOR:None             ! clear() leaves 0 = BLACK - the tuple must be
    bq:txtSFg = COLOR:None ; bq:txtSBg = COLOR:None           !      explicitly no-override on every unchanged row
    add(PvBefQ)
  end
  loop i = 1 to aftS.records()
    clear(PvAftQ)
    aq:ln = i
    aq:txt = '  ' & aftS.getLine(i)
    aq:txtFg = COLOR:None ; aq:txtBg = COLOR:None
    aq:txtSFg = COLOR:None ; aq:txtSBg = COLOR:None
    add(PvAftQ)
  end

  ! ---- offset-aware before<->after LINE ALIGNMENT (for the click-to-sync) ----
  ! Anchor-region walk: identical lines are anchors (the vast majority - most rules
  ! rewrite in place). At a divergence, find the NEAREST next anchor (smallest di+dj)
  ! over an ADAPTIVE range (up to the remaining lines, capped at 400 - a fixed small
  ! window broke expand-oneliners: 4 expansions in a row put the next anchor 18 away,
  ! and the whole region degraded to a 1:1 walk). Far anchors (di+dj > 12) must be
  ! SOLID (>= 4 stripped chars). Then map the two divergent blocks onto each other
  ! line-by-line:
  !  - EQUAL-size blocks pair k<->k positionally (in-place rewrites; content matching
  !    is deliberately NOT used here - a weak shared prefix like 'st.' must not lure a
  !    line off its slot when the rewrite renames the method).
  !  - UNEQUAL blocks: STRUCTURAL UNIT PAIRING first - group each side into indent-
  !    delimited units (base-indent line starts one; deeper lines, blanks and the
  !    closers end/else/'.' continue it); same unit count both sides -> unit k <-> k,
  !    no content matching at all (expand-oneliners is exactly this shape, and rules
  !    rewrite the conditions so content CANNOT be trusted there). Only when unit
  !    counts differ: each line snaps to the opposite line with the longest space-
  !    stripped case-folded common PREFIX (>= 4 chars); ties and no-signal fall to
  !    the nearest PROPORTIONAL slot; monotone via a previous-pick floor. So a
  !    combine's source lines all land on the combined line, a split's fragments all
  !    land on their one source line, and an adjacent rewrite in the same block (the
  !    st4-combine + st5-rewrite case) does not bleed into its neighbour.
  ! BOTH maps are built here from the same walk, so pane->pane sync agrees in both
  ! directions by construction. Stored in the trailing aln/bln fields (not displayed).
  ! Blocks are bounded by the 400 range cap; the scans are trivial at preview scale.
  nB = records(PvBefQ) ; nA = records(PvAftQ)

  ! ---- ENGINE LINE MAP first (the honesty invariant applied to alignment) ----
  ! TransformText maintained an exact output-line -> source-line map through every
  ! rewrite (VitTokenize.lineMap, folded at each renumber INSIDE the engine), so when
  ! its size matches the After pane we use it verbatim: bln straight from the map,
  ! aln = FIRST output line of each source line (so a split's source line lands on its
  ! opener), carry for combined-away/deleted lines (they land on the line their content
  ! merged into). The text-walk below survives only as the FALLBACK (empty map = engine
  ! ran unarmed; size mismatch = bug guard) - it should not run in normal preview use.
  mapOk = 0
  if nA > 0 and nB > 0 and records(eng.tk.lineMap) = nA
    j = 1                                                            ! monotone floor while filling bln
    loop i = 1 to nA
      get(eng.tk.lineMap, i)
      s2 = eng.tk.lineMap.srcLn
      if s2 < j then s2 = j.
      if s2 > nB then s2 = nB.
      j = s2
      get(PvAftQ, i) ; aq:bln = s2 ; put(PvAftQ)
    end
    j = 1 ; lastA2 = 1                                               ! invert: aln = first After row of each source line
    loop i = 1 to nB
      loop while j <= nA
        get(PvAftQ, j)
        if aq:bln >= i then break.
        j += 1
      end
      if j <= nA and aq:bln = i then lastA2 = j.                     ! else: combined/deleted source line - keep the carry
      get(PvBefQ, i) ; bq:aln = lastA2 ; put(PvBefQ)
    end
    mapOk = 1
  end

  if ~mapOk                                                          ! FALLBACK: the text walk (anchors + units + snap)
  mi = 1 ; mj = 1 ; farOff = 0
  loop while mi <= nB or mj <= nA
    if mi <= nB and mj <= nA and befS.getLine(mi) = aftS.getLine(mj) ! anchor
      get(PvBefQ, mi) ; bq:aln = mj ; put(PvBefQ)
      get(PvAftQ, mj) ; aq:bln = mi ; put(PvAftQ)
      mi += 1 ; mj += 1 ; farOff = 0
      cycle
    end
    if mi > nB                                                       ! only after-lines remain
      get(PvAftQ, mj) ; aq:bln = nB ; put(PvAftQ)
      mj += 1 ; cycle
    end
    if mj > nA                                                       ! only before-lines remain
      get(PvBefQ, mi) ; bq:aln = nA ; put(PvBefQ)
      mi += 1 ; cycle
    end
    found = 0 ; adi = 0 ; adj = 0                                    ! find the nearest next anchor (di,dj)
    tot2 = (nB - mi) + (nA - mj)                                     ! ADAPTIVE range - expand-oneliners pushes the true
    if tot2 > 400 then tot2 = 400.                                   ! anchor far past any small fixed window (the demo's
    if farOff and tot2 > 12 then tot2 = 12.                          ! 4 expansions + a choose rewrite = di+dj of 18)
    loop tot = 1 to tot2
      loop di = 0 to tot
        dj = tot - di
        if mi + di <= nB and mj + dj <= nA and befS.getLine(mi + di) = aftS.getLine(mj + dj)
          if tot > 12                                                ! far anchors must be SOLID - a blank or a lone
            line.setValue(befS.getLine(mi + di))                     ! 'end' far ahead would pair unrelated regions
            line.removeByte(32)
            if line._DataEnd < 4 then cycle.
          end
          adi = di ; adj = dj ; found = 1 ; break
        end
      end
      if found then break.
    end
    if found
      farOff = 0
    elsif tot2 = (nB - mi) + (nA - mj)                               ! scanned the WHOLE remainder: no anchor exists at all
      adi = nB - mi + 1 ; adj = nA - mj + 1                          ! -> ONE final block (short pasted snippets, fully-rewritten tails)
    else
      if tot2 > 12 then farOff = 1.                                  ! full-range miss: degrade to the near window until an anchor is seen again (perf guard for fully-rewritten regions)
      adi = 1 ; adj = 1                                              ! capped miss: 1:1 the pair
    end
    if adi = adj                                                     ! equal-size block: pair k<->k
      loop mk = 0 to adi - 1
        get(PvBefQ, mi + mk) ; bq:aln = mj + mk ; put(PvBefQ)
        get(PvAftQ, mj + mk) ; aq:bln = mi + mk ; put(PvAftQ)
      end
    else                                                             ! unequal block: try STRUCTURAL unit pairing first
      ! Group each side into indent-delimited UNITS: a line at the block's base indent
      ! starts a unit; deeper lines (bodies), blanks, and closers (end / else / a
      ! leading '.') continue it. An expanded one-liner is exactly one unit, so when
      ! both sides have the SAME unit count we pair unit k <-> unit k positionally -
      ! NO content matching, immune to condition rewrites (the 'if s = <39,39>' vs
      ! 'if s = <39>ab<39>' prefix trap that content snapping fell into).
      free(UBQ) ; baseI = -1                                         ! -- unit starts, before side --
      loop mk = 0 to adi - 1
        line.setValue(befS.getLine(mi + mk))
        ind = 0
        loop lp = 1 to line._DataEnd                                 ! leading-space count of the raw line
          if line.valuePtr[lp] <> ' ' then break.
          ind = lp
        end
        line.removeByte(32) ; line.lower()
        isCont = 0
        if ~line._DataEnd
          isCont = choose(records(UBQ) > 0)                          ! blank attaches to the open unit
        else
          if baseI < 0 then baseI = ind.
          if ind > baseI
            isCont = 1                                               ! deeper than the block base = a body line
          elsif line._DataEnd >= 3 and line.valuePtr[1 : line._DataEnd] = 'end' or line._DataEnd >= 4 and line.valuePtr[1 : line._DataEnd] = 'else' or line.valuePtr[1] = '.'
            isCont = 1                                               ! closers continue their unit
          elsif line._DataEnd > 3 and (line.valuePtr[1 : 4] = 'end!' or line.valuePtr[1 : 4] = 'end;')
            isCont = 1                                               ! 'end' + trailing comment/separator
          elsif line._DataEnd > 4 and line.valuePtr[1 : 5] = 'else!'
            isCont = 1
          end
        end
        if ~isCont or ~records(UBQ)
          UBQ.ofs = mk ; add(UBQ)
        end
      end
      free(UAQ) ; baseI = -1                                         ! -- unit starts, after side (same rule) --
      loop mk = 0 to adj - 1
        line.setValue(aftS.getLine(mj + mk))
        ind = 0
        loop lp = 1 to line._DataEnd
          if line.valuePtr[lp] <> ' ' then break.
          ind = lp
        end
        line.removeByte(32) ; line.lower()
        isCont = 0
        if ~line._DataEnd
          isCont = choose(records(UAQ) > 0)
        else
          if baseI < 0 then baseI = ind.
          if ind > baseI
            isCont = 1
          elsif line._DataEnd >= 3 and line.valuePtr[1 : line._DataEnd] = 'end' or line._DataEnd >= 4 and line.valuePtr[1 : line._DataEnd] = 'else' or line.valuePtr[1] = '.'
            isCont = 1
          elsif line._DataEnd > 3 and (line.valuePtr[1 : 4] = 'end!' or line.valuePtr[1 : 4] = 'end;')
            isCont = 1
          elsif line._DataEnd > 4 and line.valuePtr[1 : 5] = 'else!'
            isCont = 1
          end
        end
        if ~isCont or ~records(UAQ)
          UAQ.ofs = mk ; add(UAQ)
        end
      end
      if records(UBQ) and records(UBQ) = records(UAQ)         ! same unit count -> pair unit k<->k
        ub = 1
        loop mk = 0 to adi - 1                                ! every before line -> FIRST line of its paired after unit
          loop while ub < records(UBQ)                        ! advance to the unit containing offset mk
            get(UBQ, ub + 1)
            if UBQ.ofs > mk then break.
            ub += 1
          end
          get(UAQ, ub)
          get(PvBefQ, mi + mk) ; bq:aln = mj + UAQ.ofs ; put(PvBefQ)
        end
        ub = 1
        loop mk = 0 to adj - 1                                ! every after line -> FIRST line of its paired before unit
          loop while ub < records(UAQ)
            get(UAQ, ub + 1)
            if UAQ.ofs > mk then break.
            ub += 1
          end
          get(UBQ, ub)
          get(PvAftQ, mj + mk) ; aq:bln = mi + UBQ.ofs ; put(PvAftQ)
        end
        mi += adi ; mj += adj
        cycle                                                 ! block done - next region
      end
      ! unit counts differ -> fall back to prefix-snap with proportional tie-break
      pk = 0                                                  ! -- before block -> after block --
      loop mk = 0 to adi - 1
        line.setValue(befS.getLine(mi + mk))
        line.removeByte(32) ; line.lower()                    ! space-stripped, case-folded
        pt = int(mk * adj / adi)                              ! INT is load-bearing: Clarion ROUNDS on LONG assignment,
        if pt < pk then pt = pk.                              ! and rounding up would push a combine's 2nd source line
        b2 = pk ; bl2 = -1 ; bd = 99999                       ! past the combined line (adi > 0 here, divide is safe)
        loop mk2 = pk to adj - 1
          line2.setValue(aftS.getLine(mj + mk2))
          line2.removeByte(32) ; line2.lower()
          minL = choose(line._DataEnd < line2._DataEnd, line._DataEnd, line2._DataEnd)
          cp = 0
          loop lp = 1 to minL                                 ! common-prefix length of the stripped lines
            if line.valuePtr[lp] <> line2.valuePtr[lp] then break.
            cp = lp
          end
          if cp < 4 then cp = 0.                              ! a prefix under 4 stripped chars ('if', 's=', 'st.') is
          d2 = abs(mk2 - pt)                                  ! NOISE - it must not beat the proportional slot
          if cp > bl2 or (cp = bl2 and d2 < bd)               ! longest prefix wins; ties -> nearest the slot
            b2 = mk2 ; bl2 = cp ; bd = d2
          end
        end
        get(PvBefQ, mi + mk) ; bq:aln = mj + b2 ; put(PvBefQ) ! adj = 0 (pure delete): scan is empty, b2 = 0 -> mj
        pk = b2
      end
      pk = 0                                                  ! -- after block -> before block (same rule) --
      loop mk = 0 to adj - 1
        line.setValue(aftS.getLine(mj + mk))
        line.removeByte(32) ; line.lower()
        pt = int(mk * adi / adj)                              ! adj > 0 whenever this loop body runs
        if pt < pk then pt = pk.
        b2 = pk ; bl2 = -1 ; bd = 99999
        loop mk2 = pk to adi - 1
          line2.setValue(befS.getLine(mi + mk2))
          line2.removeByte(32) ; line2.lower()
          minL = choose(line._DataEnd < line2._DataEnd, line._DataEnd, line2._DataEnd)
          cp = 0
          loop lp = 1 to minL
            if line.valuePtr[lp] <> line2.valuePtr[lp] then break.
            cp = lp
          end
          if cp < 4 then cp = 0.                              ! same noise floor as the before->after pass
          d2 = abs(mk2 - pt)
          if cp > bl2 or (cp = bl2 and d2 < bd)
            b2 = mk2 ; bl2 = cp ; bd = d2
          end
        end
        get(PvAftQ, mj + mk) ; aq:bln = mi + b2 ; put(PvAftQ) ! adi = 0 (pure insert): b2 = 0 -> mi = next anchor's line
        pk = b2
      end
    end
    mi += adi ; mj += adj
  end
  end                                                         ! if ~mapOk (fallback walk)

! mark changed lines on BOTH panes: a line is changed if it differs from its ALIGNED
! counterpart. Compare the pristine split lines (befS/aftS), not the queue txt - a
! queue row may already carry a '>' from an earlier iteration (order-dependent false
! positives). The second pass catches after-lines no before-line maps to (the extra
! fragments of a split).
  loop i = 1 to records(PvBefQ)
    get(PvBefQ, i)
    if bq:aln < 1 or bq:aln > nA then cycle.
    if befS.getLine(i) <> aftS.getLine(bq:aln)
      bq:txt[1] = '>'
      put(PvBefQ)
      get(PvAftQ, bq:aln)
      aq:txt[1] = '>'
      put(PvAftQ)
    end
  end
  loop i = 1 to records(PvAftQ)
    get(PvAftQ, i)
    if aq:txt[1] = '>' or aq:bln < 1 or aq:bln > nB then cycle.
    if aftS.getLine(i) <> befS.getLine(aq:bln)
      aq:txt[1] = '>'
      put(PvAftQ)
    end
  end

! ZEBRA colour pass: one colour per TRANSFORMATION -
! groups are keyed by the CORRESPONDENCE POINTER, not by contiguity. Before side:
! adjacent changed rows pointing at the SAME After line (bq:aln - a combine) share a
! colour; a different pointer alternates A/B. After side: each changed row INHERITS
! its source row's colour through the map (aq:bln) - a split (many rows, one bln)
! is one colour, and a changed lhs line and its rhs line(s) match by construction;
! carry/insert rows whose bln points at an UNCHANGED row group by that pointer too
! (same bln as the previous changed row = same colour, else alternate from it).
! Selected variants = DarkenColor of the fill (changed-under-cursor stays distinct).
  lastChg = -1                               ! the previous changed row's aln POINTER (not its row no)
  zeb = 1                                    ! first pointer toggles to 0 = colour A
  loop i = 1 to records(PvBefQ)
    get(PvBefQ, i)
    if bq:txt[1] <> '>' then cycle.
    if bq:aln <> lastChg then zeb = 1 - zeb. ! same target line = same transformation = same colour
    lastChg = bq:aln
    bq:txtBg  = choose(zeb = 0, chgColor, chgColor2)
    bq:txtSBg = DarkenColor(bq:txtBg)
    put(PvBefQ)
  end
  pcol = 0
  lastChg = -1                               ! the previous changed After row's bln POINTER
  loop i = 1 to records(PvAftQ)
    get(PvAftQ, i)
    if aq:txt[1] <> '>' then cycle.
    col = 0
    if aq:bln >= 1 and aq:bln <= records(PvBefQ)
      get(PvBefQ, aq:bln)                    ! separate queue buffer - aq: fields keep row i
      if bq:txt[1] = '>' then col = bq:txtBg.
    end
    if ~col                                  ! carry/insert rows: group purely by the source pointer
      if aq:bln = lastChg and pcol
        col = pcol
      elsif pcol
        col = choose(pcol = chgColor, chgColor2, chgColor)
      else
        col = chgColor
      end
    end
    aq:txtBg  = col
    aq:txtSBg = DarkenColor(col)
    put(PvAftQ)
    pcol = col
    lastChg = aq:bln
  end

  if debugIt                   ! the two panes as CSV, for eyeballing the pairing
    dbg.SerializeQueue(PvBefQ) ! see debugIt at the top of this file
    dbg.SaveFile('PvBefQ.csv')
    dbg.SerializeQueue(PvAftQ)
    dbg.SaveFile('PvAftQ.csv')
  end


! NO line-number remapping needed any more. The engine now emits every change-
! log line number in SOURCE coordinates (VitRewrite/builtins log via tk.MapLine /
! LogLineOf against the live line map), so cq:ln arrived correct when the log was
! parsed above. The old remap ('BUILTIN rows = After-pane index' + text-match +
! butterfly search) guessed from fire-time coordinates and put RemoveDoubledBrackets
! rows on the wrong line - deleted with the guessing.

  SortChanges()      ! honour the current sort mode
  if records(PvBefQ) ! give each pane a valid selection + baseline after a rebuild
    ?BeforeList{PROP:Selected} = 1 ; progBef = 1
  end
  if records(PvAftQ)
    ?AfterList{PROP:Selected} = 1 ; progAft = 1
  end
  display(?BeforeList) ; display(?AfterList) ; display(?ChangeList)


! ====================================================================================
! sort the change list by rule# (default) or line#, and label the toggle button.
! ------------------------------------------------------------------------------------
SortChanges PROCEDURE()
  code
  ! shortCap is ResizeControls' answer to how much room this row has. Reading it here is what
  ! stops the long caption reappearing on a narrow window the next time the sort is toggled -
  ! two places write this one caption, so both have to ask the same question.
  if sortMode = 1
    sort(ChgQ, +cq:ln, +cq:rule)
    ?SortBtn{PROP:Text} = choose(shortCap = 1, 'line#', 'Sort: line#')
  else
    sort(ChgQ, +cq:rule, +cq:ln)
    ?SortBtn{PROP:Text} = choose(shortCap = 1, 'rule#', 'Sort: rule#')
  end
  display(?ChangeList)

! ====================================================================================
! Reflow to the CURRENT window size - on open, and on every resize, maximise and restore.
!
! *** IT IS `IMM` ON THE WINDOW THAT MAKES A RESIZE ARRIVE HERE, not RESIZE. *** RESIZE lets
! the user drag the frame; IMM is what makes the program hear about it (LRM p418: IMM "specifies
! immediate event generation whenever the user moves or resizes the window", and lists
! EVENT:Sized among what it then generates). Without it this ran ONCE, at open, and the window
! kept that layout no matter what the user did to it - a maximised window laid out for its
! startup size, with dead grey down the right and along the bottom.
!
! Both columns grow. The left keeps its WIDTH - it is a column of controls - but its height
! follows the window; the two preview LISTs split the right column; the change list spans the
! bottom. All in dialog units via PROP:Width/Height/Xpos/Ypos.
! ------------------------------------------------------------------------------------
ResizeControls PROCEDURE()
winW    LONG,AUTO
winH    LONG,AUTO
rX      LONG,AUTO
rW      LONG,AUTO
topY    LONG(32)
chH     LONG(78)
chY     LONG,AUTO
listH   LONG,AUTO
halfW   LONG,AUTO
lcExtra LONG,AUTO                          ! height the left column gained
lcY     LONG,AUTO                          ! running Y down that column
bw1     LONG,AUTO                          ! button widths, scaled
bw2     LONG,AUTO
bw3     LONG,AUTO
bw4     LONG,AUTO
grpH    LONG,AUTO
effH    LONG,AUTO
  code
  winW = 0{PROP:Width}
  winH = 0{PROP:Height}
  if winW < 300 or winH < 200 then return. ! too small to reflow sensibly
  rX = 262
  rW = winW - rX - 6
  if rW < 120 then return.
  chY   = winH - chH - 6
  ! THE GAP MUST CLEAR THE BUTTON ROW THAT SITS IN IT. The button/prompt row lives between the
  ! preview panes and the change list, and the buttons are 12 units tall - so a gap of 8, which
  ! is what this was, put them 4 units INSIDE the bottom of the panes. The design-time AT() did
  ! not show it: there the panes end at 284 and the buttons start at 288. This formula makes the
  ! panes 8 units taller than the designer does, and the window opens MAXIMIZED, so the reflow
  ! always runs and the overlap was always there. 20 = 3 above the buttons + 12 for them + 5 below.
  listH = chY - 20 - topY
  if listH < 40 then listH = 40.
  halfW = (rW - 6) / 2
  ! before pane
  ?BeforeList{PROP:Xpos} = rX ; ?BeforeList{PROP:Ypos} = topY
  ?BeforeList{PROP:Width} = halfW ; ?BeforeList{PROP:Height} = listH
  ! after pane
  ?AfterList{PROP:Xpos} = rX + halfW + 6 ; ?AfterList{PROP:Ypos} = topY
  ?AfterList{PROP:Width} = halfW ; ?AfterList{PROP:Height} = listH
  ?AfterHdr{PROP:Xpos} = rX + halfW + 6
  ! change list
  ?ChangesHdr{PROP:Ypos} = chY - 15
  ! THESE OFFSETS ARE THE BUTTON WIDTHS IN THE WINDOW STRUCTURE, ACCUMULATED FROM THE RIGHT.
  ! Widths are set ONCE, in the structure - the resize moves Xpos only - so the two have to be
  ! changed together or the row overlaps as soon as the window is sized. Right-anchored with
  ! 4-unit gaps: Next 44, Prev 44, Sort 66, Chg colour 72, ending flush with the change list.
  ! THE BUTTON ROW NARROWS IN TWO STEPS AS THE WINDOW DOES, rather than running into the prompt
  ! on its left. Squeezing the widths alone does not work - the captions clip, which is what
  ! this row was reported for in the first place - so the SHORT step changes the captions too.
  ! The prompt gives way FIRST, being the widest thing on the row and the least useful.
  !     rW >= 341   full prompt,    full buttons     72 + 66 + 44 + 44 = 226, gaps 12
  !     rW >= 274   'Changes:',     full buttons
  !     below       'Changes:',     short buttons    40 + 36 + 22 + 22 = 120, gaps 12
  ! PROP:MinWidth 440 keeps rW at 166 or more, which the short row fits inside.
  ! Xpos is DERIVED from the widths, right to left, so there is nothing to keep in step by hand.
  if rW >= 274
    ?ChangesHdr{PROP:Text} = choose(rW >= 341, 'Changes (click a row to jump both panes):', 'Changes:')
    bw1 = 72 ; bw2 = 66 ; bw3 = 44 ; bw4 = 44
    shortCap = 0
    ?ChgColorBtn{PROP:Text} = 'Chg colour...'
    ?PrevChg{PROP:Text}     = '&<< Prev'
    ?NextChg{PROP:Text}     = '&Next >'
  else
    ?ChangesHdr{PROP:Text} = 'Changes:'
    bw1 = 40 ; bw2 = 36 ; bw3 = 22 ; bw4 = 22
    shortCap = 1
    ?ChgColorBtn{PROP:Text} = 'Colour'
    ?PrevChg{PROP:Text}     = '&<<'
    ?NextChg{PROP:Text}     = '&>'
  end
  ! ?SortBtn's caption belongs to sortMode, so pick the form matching BOTH it and the tier.
  ! SortChanges writes this same caption when you toggle the sort, and reads shortCap for the
  ! same reason - without that the long text reappears on a narrow window at the next sort.
  if sortMode = 1
    ?SortBtn{PROP:Text} = choose(shortCap = 1, 'line#', 'Sort: line#')
  else
    ?SortBtn{PROP:Text} = choose(shortCap = 1, 'rule#', 'Sort: rule#')
  end
  ?NextChg{PROP:Ypos}     = chY - 17 ; ?NextChg{PROP:Width}     = bw4
  ?NextChg{PROP:Xpos}     = rX + rW - bw4
  ?PrevChg{PROP:Ypos}     = chY - 17 ; ?PrevChg{PROP:Width}     = bw3
  ?PrevChg{PROP:Xpos}     = rX + rW - bw4 - 4 - bw3
  ?SortBtn{PROP:Ypos}     = chY - 17 ; ?SortBtn{PROP:Width}     = bw2
  ?SortBtn{PROP:Xpos}     = rX + rW - bw4 - 4 - bw3 - 4 - bw2
  ?ChgColorBtn{PROP:Ypos} = chY - 17 ; ?ChgColorBtn{PROP:Width} = bw1
  ?ChgColorBtn{PROP:Xpos} = rX + rW - bw4 - 4 - bw3 - 4 - bw2 - 4 - bw1
  ?ChangeList{PROP:Xpos} = rX ; ?ChangeList{PROP:Ypos} = chY
  ?ChangeList{PROP:Width} = rW ; ?ChangeList{PROP:Height} = chH

  ! ---- THE LEFT COLUMN GROWS AS WELL ----------------------------------------------------
  ! Left entirely alone, a maximised window puts the group list, the doc box and the selection
  ! table all in the top 384 units with dead grey under them. Its WIDTH is still fixed - that
  ! is deliberate, it is a column of controls - but its height should follow the window like
  ! everything else.
  !
  ! The extra height is SPLIT between the group list and the effective-selection table, the
  ! two that can run long; the doc box keeps its 66. At the design height this computes the
  ! designed layout exactly, so nothing moves until the window does.
  lcExtra = (winH - 156) - 228
  if lcExtra < 0 then lcExtra = 0.
  grpH = 150 + lcExtra / 2
  effH = 78 + lcExtra - lcExtra / 2
  ?GrpList{PROP:Height} = grpH
  lcY = 36 + grpH + 4
  ?ToggleBtn{PROP:Ypos} = lcY ; ?SaveBtn{PROP:Ypos} = lcY
  ?WbBtn{PROP:Ypos}     = lcY ; ?CloseBtn{PROP:Ypos} = lcY
  lcY += 20
  ?PROMPT3{PROP:Ypos} = lcY
  lcY += 10
  ?docTxt{PROP:Ypos} = lcY
  lcY += 66 + 4
  ?PROMPT4{PROP:Ypos} = lcY
  lcY += 10
  ?effTxt{PROP:Ypos} = lcY ; ?effTxt{PROP:Height} = effH
  ! left column stays FIXED (its buttons + doc/effective panels sit below the group
  ! list at fixed offsets; growing the group list would overlap them).

! ====================================================================================
LoadSourceFile PROCEDURE(<string pFn>)
fn   CSTRING(261)
st   StringTheory
  code
  if omitted(pFn) or ~pFn
    if ~FILEDIALOG('Open a Clarion source for preview', fn, |
         'Clarion source|*.clw;*.inc|All files|*.*', FILE:KeepDir + FILE:LongName)
      return                                                            ! cancelled
    end
  else
    fn = pFn
  end

  if ~st.LoadFile(fn)
    message('Could not open ' & clip(fn) & '||' & st.LastError, 'VitStyle', ICON:Exclamation)
    return
  end
  srcBuf._StealValue(st)
  fidelity = 'file: ' & clip(sub(fn, 1, 55)) & '  (in-file types only)' ! full-header fidelity (--root) is a follow-up
  RefreshPreview()

! ====================================================================================
! paste a snippet as the preview source. A bare snippet has no declarations, so the
! rule file's ASSUME lines (st* -> StringTheory, ...) supply receiver types - the badge
! says so. Local window so the paste box is self-contained.
! ------------------------------------------------------------------------------------
PasteSnippet PROCEDURE()
pasteVar CSTRING(16384),AUTO
okHit    BYTE,AUTO
PasteW WINDOW('Paste a snippet'),AT(,,300,220),CENTER,MODAL,SYSTEM,GRAY,RESIZE,FONT('Segoe UI',9)
    PROMPT('Paste Clarion code; the preview runs it under the current selection.'),AT(6,4,288,10)
    TEXT,AT(6,18,288,170),USE(pasteVar),VSCROLL,HSCROLL
    BUTTON('&Preview'),AT(192,194,50,14),USE(?PvOk),DEFAULT
    BUTTON('&Cancel'),AT(246,194,48,14),USE(?PvCancel)
  END
  code
  pasteVar = ''
  okHit = 0
  open(PasteW)
  accept
    case accepted()
    of ?PvOk
      okHit = 1 ; break
    of ?PvCancel
      break
    end
    if event() = EVENT:CloseWindow then break.
  end
  close(PasteW)
  if ~okHit or ~pasteVar then return.
  srcBuf.setValue(pasteVar)
  fidelity = 'snippet  (undeclared receivers typed by ASSUME)'
  RefreshPreview()

! ====================================================================================
SetDemo PROCEDURE()
  code
  srcBuf.setValue('Demo PROCEDURE()<13,10>'         & |
    'st   StringTheory<13,10>'                      & |
    's    STRING(20)<13,10>'                        & |
    'n    LONG<13,10>'                              & |
    '  CODE<13,10>'                                 & |
    '  if s = '''' then n = 1.<13,10>'              & |
    '  if n <> 0 then s = ''x''.<13,10>'            & |
    '  if clip(s) = ''ab'' then n = 2.<13,10>'      & |
    '  s = choose(n = 1, true, false)<13,10>'       & |
    '  if st.getValue() = ''y'' then n = 3.<13,10>' & |
    '  return<13,10>')
  fidelity = 'built-in demo  (in-file types)'

! ====================================================================================
! Change-list click: cq:ln is a SOURCE line. Select it in the Before pane, then use the
! alignment map to scroll the After pane to its corresponding (offset-aware) line.
! ------------------------------------------------------------------------------------
GotoChange PROCEDURE()
r  LONG,AUTO
a  LONG,AUTO
  code
  r = choice(?ChangeList)
  if ~r then return.
  get(ChgQ, r)
  if errorcode() or ~cq:ln then return.
  a = 0
  if cq:ln <= records(PvBefQ)
    progBef = cq:ln            ! programmatic selects - record baselines so the echoes are recognised
    select(?BeforeList, cq:ln) ! line number = row index (1 row per source line)
    get(PvBefQ, cq:ln)
    if ~errorcode() then a = bq:aln.
  end
  if ~a then a = cq:ln.        ! fall back to same number if unmapped
  if a <= records(PvAftQ)
    progAft = a
    select(?AfterList, a)
  end

! ====================================================================================
! Click a line in one pane -> scroll the other pane to its aligned line (offset-aware
! via aln/bln). progBef/progAft hold the row we last set each pane to; a NewSelection
! whose row equals that baseline is our own echo (or a no-op) and is NOT re-synced, so
! the panes never ping-pong - and it is robust even when select() posts no echo.
! ------------------------------------------------------------------------------------
SyncPanes PROCEDURE(BYTE pWhich)
r  LONG,AUTO
  code

  if pWhich = 1          ! before -> after
    r = choice(?BeforeList)
    if r
      get(PvBefQ, r)
      if ~errorcode() and bq:aln and bq:aln <= records(PvAftQ)
        progAft = bq:aln ! record what we set After to, so its echo is recognised
        ?AfterList{prop:selected} = bq:aln
      end
    end
  else                   ! after -> before
    r = choice(?AfterList)
    if r
      get(PvAftQ, r)
      if ~errorcode() and aq:bln and aq:bln <= records(PvBefQ)
        progBef = aq:bln
        ?BeforeList{prop:selected} = aq:bln
      end
    end
  end

! ====================================================================================
! the rule workbench - one rule per visit.
! Everything runs on the SCRATCH wbRl/wbEng - the live rl/eng change only via
! WbSave's full reload. Lint = the save gate = lint of the PROSPECTIVE file (disk +
! draft composed exactly as save would write it), so what you lint IS what you save.
! ------------------------------------------------------------------------------------
Workbench PROCEDURE()
r      LONG,AUTO
saved  BYTE
  code
  WbBuildRuleList()
  if ~wbGrp then wbGrp = 'my-rules'. ! default target group; sticky across visits
  wbEditId  = 0
  wbPickTxt = '(new rule)'
  wbLintTxt = ''
  free(WbBefQ) ; free(WbAftQ) ; free(WbChgQ)
  open(WbW)
  accept
    case accepted()
    of ?WbLintBtn
      WbLint(1)
    of ?WbTestBtn
      WbTest()
    of ?WbSaveBtn
      if WbSave() then saved = 1 ; break. ! stays open on a failed gate / declined confirm
    of ?WbCancelBtn
      break
    end
    case event()
    of EVENT:NewSelection
      if field() = ?wbPickTxt
        WbLoadPick()                      ! DROP NewSelection - if it never fires, add an Edit button next to the drop
      elsif field() = ?WbChgList          ! fire row -> jump both mini panes
        r = choice(?WbChgList)
        if r
          get(WbChgQ, r)
          if ~errorcode()
            if wc:ln and wc:ln <= records(WbBefQ) then select(?WbBefList, wc:ln).
            if wc:aln and wc:aln <= records(WbAftQ) then select(?WbAftList, wc:aln).
          end
        end
      end
    of EVENT:CloseWindow
      break
    end
  end
  close(WbW)
  if saved then WbAfterSave(). ! refresh the MAIN window only after the modal child
                               !   is gone (field equates resolve per current window)

! ====================================================================================
! existing user rules -> the droplist. Filter: real rules only (no builtins, no
! REVERSE copies), ruleId in the user band [userBase, userBase + revBase).
! ------------------------------------------------------------------------------------
WbBuildRuleList PROCEDURE()
i  LONG,AUTO
g  LONG,AUTO
  code
  free(WbrQ)
  clear(WbrQ)
  wr:shown = '(new rule)'
  wr:id    = 0
  add(WbrQ)
  loop i = 1 to records(rl.rules)
    get(rl.rules, i)
    if rl.rules.kind <> vr:kindRule or |
       rl.rules.revOf               or |
       rl.rules.ruleId < vr:userBase or rl.rules.ruleId >= vr:revBase + vr:userBase
      cycle
    end
    clear(WbrQ)
    wr:id = rl.rules.ruleId
    g = rl.rules.groupId
    if g
      get(rl.groups, g)
      if ~errorcode() then wr:grpNm = rl.groups.name.
    end
    if not (rl.rules.srcText &= NULL)
      wr:shown = 'U' & (rl.rules.ruleId - vr:userBase) & '  [' & clip(wr:grpNm) & ']  ' & sub(rl.rules.srcText, 1, 40)
    else
      wr:shown = 'U' & (rl.rules.ruleId - vr:userBase) & '  [' & clip(wr:grpNm) & ']'
    end
    add(WbrQ)
  end

! ====================================================================================
! droplist pick. (new rule) keeps the current text (copy-as-new comes free);
! an existing rule loads its CLEANED logical text (comments/continuations folded -
! the v01 edit granularity) + its group, and save REPLACES it in place.
! ------------------------------------------------------------------------------------
WbLoadPick PROCEDURE()
r  LONG,AUTO
i  LONG,AUTO
  code
  r = choice(?wbPickTxt)
  if ~r then return.
  get(WbrQ, r)
  if errorcode() then return.
  if ~wr:id
    wbEditId = 0
    display()
    return
  end
  loop i = 1 to records(rl.rules)
    get(rl.rules, i)
    if rl.rules.ruleId = wr:id and rl.rules.kind = vr:kindRule and ~rl.rules.revOf
      wbEditId = wr:id
      wbGrp    = wr:grpNm
      if not (rl.rules.srcText &= NULL)
        if len(clip(rl.rules.srcText)) > size(draftVar) - 1
          ! the editor buffer is finite and the assignment below TRUNCATES
          ! silently - and Save then writes the truncation BACK over the whole rule.
          ! A truncation at a clean token boundary even lints clean, so part of the
          ! user's rule is destroyed with no complaint. Refuse to load it instead.
          message('This rule is ' & len(clip(rl.rules.srcText)) & ' characters - longer than the'  & |
                  ' workbench editor holds (' & size(draftVar) - 1 & '). Edit it in the rule file' & |
                  ' directly: loading it here would truncate it, and Save would write the'         & |
                  ' truncation back.', 'VitStyle', ICON:Exclamation)
          wbEditId = 0
          draftVar = ''
          break
        end
        draftVar = clip(rl.rules.srcText)
      else
        draftVar = ''
      end
      break
    end
  end
  display()

! ====================================================================================
! build the PROSPECTIVE VitStyle.rules.txt text: the disk file with the draft
! REPLACED in place (editing - the old rule's whole logical span incl | continuation
! lines is consumed) or APPENDED inside its GROUP block (before the block's end),
! creating the block (and the file header) when absent. pDraftLn returns the 1-based
! OUTPUT line of the draft's first content line - the rule's ruleId in the prospective
! file is vr:userBase + pDraftLn (the fires filter and the U-number shown in the panel).
! ------------------------------------------------------------------------------------
WbComposeUser PROCEDURE(StringTheory pOut, *LONG pDraftLn)
have    StringTheory
line    StringTheory
up      StringTheory
draft   StringTheory
dl      StringTheory                                       ! EmitDraft scratch (routines share procedure scope)
i       LONG,AUTO
pos     LONG,AUTO
dx      LONG,AUTO                                          ! EmitDraft scratch
dp      LONG,AUTO                                          ! EmitDraft scratch
outLn   LONG
tgtLn   LONG
spanEnd LONG,AUTO
grpLn   LONG
endLn   LONG,AUTO
grpU    STRING(vr:maxName),AUTO
  code
  pOut.free()
  pDraftLn = 0
  draft.setValue(draftVar)
  draft.replace('<13,10>', '<10>')                         ! the TEXT control stores CRLF between lines
  draft.split('<10>')
  if exists(userFn.getValue()) and have.LoadFile(userFn.getValue())
    have.LineEndings(st:unix)
    have.split('<10>')
  end

  if wbEditId                                              ! ---- replace-in-place path ----
    tgtLn = wbEditId - vr:userBase
    if tgtLn < 1 or tgtLn > have.records() then tgtLn = 0. ! disk changed underneath - fall through to append
  end
  if tgtLn
    spanEnd = tgtLn                                        ! whole logical span: follow | continuations
    loop while spanEnd < have.records()
      line.setValue(have.getLine(spanEnd))
      pos = rl.PosOutsideQuotes(line, '!')
      if pos then line.setLength(pos - 1).
      line.trim()
      if line._DataEnd and line.valuePtr[line._DataEnd] = '|'
        spanEnd += 1
      else
        break
      end
    end
    loop i = 1 to have.records()
      if i = tgtLn then do EmitDraft.
      if i >= tgtLn and i <= spanEnd then cycle. ! the old spelling goes
      outLn += 1
      pOut.append(have.getLine(i) & '<13,10>')
    end
    return
  end

  ! ---- append path: find the target GROUP block ----
  grpU = upper(wbGrp)
  loop i = 1 to have.records()
    line.setValue(have.getLine(i))
    pos = rl.PosOutsideQuotes(line, '!')
    if pos then line.setLength(pos - 1).
    line.trim()
    up.setValue(line)
    up.upper()
    if up._DataEnd > 6 and up.valuePtr[1 : 6] = 'GROUP '
      up.setValue(up.valuePtr[7 : up._DataEnd])
      pos = up.findByte(44)                      ! name ends at the first attribute comma <comma>
      if pos then up.setLength(pos - 1).
      up.trim()
      if choose(up._DataEnd < 1, '', up.valuePtr[1 : up._DataEnd]) = grpU
        grpLn = i
        break
      end
    end
  end
  if grpLn
    endLn = 0                                    ! block ends at ENDGROUP / next GROUP / STYLE / EOF
    loop i = grpLn + 1 to have.records()
      line.setValue(have.getLine(i))
      pos = rl.PosOutsideQuotes(line, '!')
      if pos then line.setLength(pos - 1).
      line.trim()
      up.setValue(line)
      up.upper()
      if up._DataEnd = 8 and up.valuePtr[1 : 8] = 'ENDGROUP'
        endLn = i ; break
      elsif up._DataEnd > 6 and (up.valuePtr[1 : 6] = 'GROUP ' or up.valuePtr[1 : 6] = 'STYLE ')
        endLn = i ; break
      end
    end
    if ~endLn then endLn = have.records() + 1.
    loop i = 1 to have.records()
      if i = endLn then do EmitDraft.
      outLn += 1
      pOut.append(have.getLine(i) & '<13,10>')
    end
    if endLn > have.records() then do EmitDraft. ! block ran to EOF
    return
  end
  ! group absent: keep the whole file (or seed the header), append a new block
  if have.records()
    loop i = 1 to have.records()
      outLn += 1
      pOut.append(have.getLine(i) & '<13,10>')
    end
  else
    outLn += 1
    pOut.append('! VitStyle.rules.txt - user rules (plain DSL, GROUP blocks). Written by the VitStyle<13,10>')
    outLn += 1
    pOut.append('! workbench; safe to hand-edit. Loaded after the shipped rule file - CLI reproduction:<13,10>')
    outLn += 1
    pOut.append('!   VitTransform <<rules> <<src> <<out> --userrules=VitStyle.rules.txt --group=<<group><13,10>')
  end
  outLn += 1
  pOut.append('<13,10>') ! one blank line before the new block
  outLn += 1
  pOut.append('GROUP ' & clip(wbGrp) & '<13,10>')
  do EmitDraft
  outLn += 1
  pOut.append('ENDGROUP<13,10>')
  return

! ---- emit the draft lines; pDraftLn = output line of the first CONTENT line ----
EmitDraft routine
  loop dx = 1 to draft.records()
    outLn += 1
    pOut.append(draft.getLine(dx) & '<13,10>')
    if ~pDraftLn
      dl.setValue(draft.getLine(dx))
      dp = rl.PosOutsideQuotes(dl, '!')
      if dp then dl.setLength(dp - 1).
      dl.trim()
      if dl._DataEnd then pDraftLn = outLn.
    end
  end

! ====================================================================================
! lint the prospective combined set (shipped + prospective user file + profile
! styles) on the SCRATCH wbRl. Fills the panel with U-numbers, sets wbDraftId,
! clears stale test results. Returns the SEV:Error count, which is the save gate.
! ------------------------------------------------------------------------------------
WbLint PROCEDURE(BYTE pShowOk)
prosp  StringTheory
d      StringTheory
up     StringTheory
i      LONG,AUTO
e      LONG,AUTO
ln     LONG
  code
  wbLintTxt = ''
  free(WbChgQ) ; free(WbBefQ) ; free(WbAftQ) ! stale test panes would show an older draft
  display(?WbChgList) ; display(?WbBefList) ; display(?WbAftList)
  wbDraftId = 0
  d.setValue(draftVar)
  d.trim()
  if ~d._DataEnd
    wbLintTxt = 'nothing to lint - the rule text is empty.'
    display(?wbLintTxt)
    return 1
  end
  up.setValue(d)
  up.upper()
  if (up._DataEnd > 6 and up.valuePtr[1 : 6] = 'GROUP ')    or (up._DataEnd >= 8 and up.valuePtr[1 : 8] = 'ENDGROUP')  |
  or (up._DataEnd > 6 and up.valuePtr[1 : 6] = 'STYLE ')    or (up._DataEnd > 9  and up.valuePtr[1 : 9] = 'LASTUSED ') |
  or (up._DataEnd > 8 and up.valuePtr[1 : 8] = 'BUILTIN ')
    wbLintTxt = 'enter only the RULE text - the workbench writes the GROUP block for you (and STYLE/LASTUSED/BUILTIN lines do not belong in a user rulefile).'
    display(?wbLintTxt)
    return 1
  end
  if ~wbGrp or ~rl.IsGroupName(wbGrp)
    wbLintTxt = 'the Group name must start with a letter and use letters/digits/_/:/- only.'
    display(?wbLintTxt)
    return 1
  end
  WbComposeUser(prosp, ln)
  wbDraftId = vr:userBase + ln
  wbRl.LoadFile(rulesFn.getValue())
  wbRl.LoadUserText(prosp)
  if exists(profFn.getValue())
    wbRl.LoadStyleFile(profFn.getValue()) ! so Resolve(curStyle) works in WbTest
  end
  wbRl.Lint()
  e = wbRl.ErrorCount()
  scratch.free()
  if ~records(wbRl.issues)
    scratch.setValue('lint clean - no errors, no warnings.')
  else
    if ~e and pShowOk
      scratch.setValue('no errors; ' & wbRl.WarnCount() & ' warning(s):<13,10>')
    end
    loop i = 1 to records(wbRl.issues)
      get(wbRl.issues, i)
      scratch.append(choose(wbRl.issues.sev = vr:sevError, 'ERROR ', 'warn  '))
      if wbRl.issues.lineNo >= vr:userBase ! the workbench shows U<n>
        scratch.append('U' & (wbRl.issues.lineNo - vr:userBase))
      else
        scratch.append('line ' & wbRl.issues.lineNo)
      end
      scratch.append(': ' & clip(wbRl.issues.msg) & '<13,10>')
      if scratch._DataEnd > 2300 then break.
    end
  end
  wbLintTxt = scratch.getValue()
  display(?wbLintTxt)
  return e

! ====================================================================================
! run the draft against the CURRENT preview source through the scratch engine.
! Selection = the LIVE selection (same style + overrides via OverrideLists) PLUS the
! draft's group (user groups are opt-in - the test must see the draft fire). The
! fires list keeps ONLY wbDraftId rows; both mini panes mark its lines with '>'.
! ------------------------------------------------------------------------------------
WbTest PROCEDURE()
grps    StringTheory
nogr    StringTheory
befS    StringTheory
aftS    StringTheory
logS    StringTheory
line    StringTheory
i       LONG,AUTO
j       LONG,AUTO
chg     LONG,AUTO
ruleNo  LONG,AUTO
nA      LONG,AUTO
zeb     LONG,AUTO ! zebra (see BuildPreviewLists)
lastChg LONG,AUTO
col     LONG,AUTO
pcol    LONG,AUTO
  code
  if WbLint(0)
    ?WbChgHdr{PROP:Text} = 'Draft fires: lint errors - fix first (see the panel above).'
    return
  end
  if ~srcBuf._DataEnd
    message('No preview source - open a file, load the demo or paste a snippet first.', 'VitStyle', ICON:Asterisk)
    return
  end
  OverrideLists(grps, nogr)
  if grps._DataEnd then grps.append(',').
  grps.append(clip(wbGrp))
  wbRl.Resolve(curStyle, grps.getValue(), nogr.getValue())
  if wbRl.ErrorCount()
    ?WbChgHdr{PROP:Text} = 'Draft fires: selection resolve failed - re-run Lint for the issue list.'
    return
  end
  wbEng.Init(wbRl)
  wbEng.progressFn = ''
  wbLog.free()
  chg = wbEng.TransformText(srcBuf, wbOut, wbLog)
  free(WbBefQ) ; free(WbAftQ) ; free(WbChgQ)
  befS.setValue(srcBuf) ; befS.LineEndings(st:unix) ; befS.split('<10>')
  aftS.setValue(wbOut)  ; aftS.LineEndings(st:unix) ; aftS.split('<10>')
  loop i = 1 to befS.records()
    clear(WbBefQ)
    wb:ln  = i
    wb:txt = '  ' & befS.getLine(i)
    wb:txtFg = COLOR:None ; wb:txtBg = COLOR:None ! colour tuple - see BuildPreviewLists
    wb:txtSFg = COLOR:None ; wb:txtSBg = COLOR:None
    add(WbBefQ)
  end
  nA = aftS.records()
  loop i = 1 to nA
    clear(WbAftQ)
    wa:ln  = i
    wa:txt = '  ' & aftS.getLine(i)
    wa:txtFg = COLOR:None ; wa:txtBg = COLOR:None
    wa:txtSFg = COLOR:None ; wa:txtSBg = COLOR:None
    add(WbAftQ)
  end
  if records(wbEng.tk.lineMap) = nA  ! the engine line map: after row -> source line
    j = 1
    loop i = 1 to nA
      get(wbEng.tk.lineMap, i)
      get(WbAftQ, i)
      wa:bln = wbEng.tk.lineMap.srcLn
      if wa:bln < j then wa:bln = j. ! monotone clamp, as the main pane does
      if wa:bln > records(WbBefQ) then wa:bln = records(WbBefQ).
      j = wa:bln
      put(WbAftQ)
    end
  end
  logS.setValue(wbLog)               ! 'rule N line L: before ==> after' - SOURCE coords
  logS.LineEndings(st:unix)
  logS.split('<10>',,,,st:clip,st:left)
  loop i = 1 to logS.records()
    line.setValue(logS.getLine(i))
    line.split(' ')
    line.RemoveLines()
    if lower(line.getLine(1)) <> 'rule' then cycle.
    ruleNo = line.getLine(2)
    if ruleNo <> wbDraftId or |   ! the draft's fires ONLY (one rule per visit = one id)
       line.getLine(3) <> 'line'
      cycle
    end
    line.setValueFromLine(4)
    if line.EndsWith('#') then line.AdjustLength(-1).
    clear(WbChgQ)
    wc:ln = line.getValue()
    if ~wc:ln then cycle.
    line.deleteLine(4)
    line.deleteLine(3)
    line.deleteLine(2)
    line.deleteLine(1)
    line.join(' ')
    wc:desc = line.getValue()
    wc:aln = 0 ! first after row of that source line (click-to-jump)
    loop j = 1 to records(WbAftQ)
      get(WbAftQ, j)
      if wa:bln = wc:ln then wc:aln = j ; break.
      if wa:bln > wc:ln then break.
    end
    if ~wc:aln then wc:aln = choose(wc:ln <= records(WbAftQ), wc:ln, records(WbAftQ)).
    add(WbChgQ)
    get(WbBefQ, wc:ln)
    if ~errorcode()
      wb:txt[1] = '>'
      put(WbBefQ)
    end
  end
  loop i = 1 to records(WbAftQ) ! mark after rows born from a fired source line
    get(WbAftQ, i)
    if ~wa:bln then cycle.
    loop j = 1 to records(WbChgQ)
      get(WbChgQ, j)
      if wc:ln = wa:bln
        wa:txt[1] = '>'
        put(WbAftQ)
        break
      end
    end
  end
  lastChg = -1                            ! zebra pass, pointer-keyed like BuildPreviewLists:
  zeb = 1                                 ! Before rows group by their fire's target row (wc:aln),
  loop i = 1 to records(WbBefQ)           ! After inherits via bln
    get(WbBefQ, i)
    if wb:txt[1] <> '>' then cycle.
    col = 0                               ! this row's target pointer = its fire's aln
    loop j = 1 to records(WbChgQ)
      get(WbChgQ, j)
      if wc:ln = i then col = wc:aln ; break.
    end
    if col <> lastChg then zeb = 1 - zeb. ! pointer change = new transformation = alternate
    lastChg = col
    wb:txtBg  = choose(zeb = 0, chgColor, chgColor2)
    wb:txtSBg = DarkenColor(wb:txtBg)
    put(WbBefQ)
  end
  pcol = 0
  lastChg = -1
  loop i = 1 to records(WbAftQ)
    get(WbAftQ, i)
    if wa:txt[1] <> '>' then cycle.
    col = 0
    if wa:bln >= 1 and wa:bln <= records(WbBefQ)
      get(WbBefQ, wa:bln)
      if wb:txt[1] = '>' then col = wb:txtBg.
    end
    if ~col ! carry/insert rows: group purely by the source pointer
      if wa:bln = lastChg and pcol
        col = pcol
      elsif pcol
        col = choose(pcol = chgColor, chgColor2, chgColor)
      else
        col = chgColor
      end
    end
    wa:txtBg  = col
    wa:txtSBg = DarkenColor(col)
    put(WbAftQ)
    pcol = col
    lastChg = wa:bln
  end
  ?WbChgHdr{PROP:Text} = 'Draft fires on the current preview source: ' & records(WbChgQ) & |
                         '  (all rules under this selection: ' & chg & ' change(s))'
  display(?WbChgList) ; display(?WbBefList) ; display(?WbAftList)

! ====================================================================================
! the save GATE + write only. zero SEV:Error on the prospective combined set;
! warnings -> confirm. NO main-window refresh here - WbW is still open and Clarion
! field equates resolve against the CURRENT window; the refresh is WbAfterSave, run
! by Workbench() after close(WbW).
! ------------------------------------------------------------------------------------
WbSave PROCEDURE()
prosp  StringTheory
e      LONG,AUTO
nWarn  LONG,AUTO ! NB not 'w' - labels are caseless and W is the main WINDOW label (the global-r lesson, mirrored)
ln     LONG
  code
  e = WbLint(1)
  if e
    message('The combined set has ' & e & ' lint error(s) - a rule only saves clean (see the panel).', 'VitStyle', ICON:Exclamation)
    return 0
  end
  nWarn = wbRl.WarnCount()
  if nWarn
    if message('Lint shows ' & nWarn & ' warning(s) - see the panel.|Save anyway?', 'VitStyle', ICON:Question, BUTTON:Yes + BUTTON:No, BUTTON:Yes) = BUTTON:No
      return 0
    end
  end
  WbComposeUser(prosp, ln) ! recompose - WbLint's copy was consumed by the load
  if not prosp.SaveFile(userFn.getValue())
    message('Could not save ' & clip(userFn.getValue()) & '||' & prosp.LastError, 'VitStyle', ICON:Exclamation)
    return 0
  end
  return 1

! ====================================================================================
! post-save refresh - runs AFTER close(WbW), main window is current again. The
! FULL normal reload (no incremental patching of live queues), force the saved
! group ON for the session, the profile offer, then the standard refresh chain.
! ------------------------------------------------------------------------------------
WbAfterSave PROCEDURE()
mem   StringTheory
g     LONG,AUTO
i     LONG,AUTO
s     LONG,AUTO
svSty STRING(vr:maxName),AUTO
  code
  svSty = curStyle                                                              ! LoadEverything re-applies the FILE's LASTUSED marker
  LoadEverything()                                                              !   (right at startup, wrong here) - saving a workbench rule
  if svSty and rl.FindStyle(svSty)                                              !   silently reverted the SESSION's style choice, and the
    curStyle = svSty                                                            !   retained overrides were then re-applied on the wrong base.
  end                                                                           !   ApplyOverrides below re-resolves with the restored style.
  g = rl.FindGroup(wbGrp)                                                       ! force the saved group ON for this session (the group is
  if g                                                                          !   opt-in, but the author wants to SEE the rule live)
    loop i = 1 to records(OvrQ)
      get(OvrQ, i)
      if oq:grpRow = g then delete(OvrQ) ; break.
    end
    clear(OvrQ)
    oq:grpRow = g
    oq:mode   = 1
    add(OvrQ)
  end
  if curStyle                                                                   ! offer the group to the ACTIVE profile's STYLE line
    s = rl.FindStyle(curStyle)
    if s
      get(rl.styles, s)
      mem.setValue(' ' & upper(clip(rl.styles.members)) & ' ')                  ! whole-word membership test - the old
      mem.replaceByte(44, 32)                                                   !   substring instring() found group `st` inside replace all <comma> with <space>
      if rl.styles.isProfile and ~mem.findChars(' ' & upper(clip(wbGrp)) & ' ') ! member `strings` and silently
                                                                                ! suppressed the offer
        if message('Add group ' & clip(wbGrp) & ' to the active profile ' & clip(curStyle) & '?', 'VitStyle', ICON:Question, BUTTON:Yes + BUTTON:No, BUTTON:Yes) = BUTTON:Yes
          mem.setValue(clip(rl.styles.members) & ', ' & clip(wbGrp))
          if WriteProfileLine(rl.styles.name, mem.getValue())                   ! a failed write must not refresh-and-relint
            RefreshProfiles()                                                   !   as if it happened
            rl.Lint()
          end
        end
      end
    end
  end
  ApplyOverrides()                                                              ! Resolve + BuildDisplay + RefreshPreview
  BuildStyleList()
  message('Saved to ' & clip(userFn.getValue())                                                      & |
          '||Batch reproduction:|VitTransform <<rules> <<src> <<out> --userrules=VitStyle.rules.txt' & |
          choose(curStyle <> '', ' --stylefile=VitStyle.profiles.txt --style=' & clip(curStyle), '') & |
          ' --group=' & clip(wbGrp), 'VitStyle', ICON:Asterisk)

! ====================================================================================
! colour: UI prefs live in their OWN file (VitStyle.ui.txt) - the profile file's
! engine-side parser (VitRules.LoadStyleFile) warns on unknown lines, so CHGCOLOR
! cannot ride there without an engine change. Format: one 'CHGCOLOR <n>' line.
! ------------------------------------------------------------------------------------
LoadUiPrefs PROCEDURE()
st  StringTheory
v   LONG,AUTO
  code
  chgColor  = 0C0FFFFh        ! defaults: A = pale yellow, B = pale green (BGR)
  chgColor2 = 0C0FFC0h
  if not st.LoadFile(uiFn.getValue()) then return.
  st.upper()
  v = UiNum(st, 'CHGCOLOR ')
  if v > 0 then chgColor = v. ! 0 = absent or BLACK fill = unusable; keep default
  v = UiNum(st, 'CHGCOLOR2 ')
  if v > 0 then chgColor2 = v.

! ------------------------------------------------------------------------------------
SaveUiPrefs PROCEDURE()
st  StringTheory
  code
  st.setValue('! VitStyle.ui.txt - UI preferences (machine-written by VitStyle).<13,10>' & |
              'CHGCOLOR ' & chgColor & '<13,10>'                                         & |
              'CHGCOLOR2 ' & chgColor2 & '<13,10>')
  st.SaveFile(uiFn.getValue()) ! best-effort: a failure only loses persistence

! ------------------------------------------------------------------------------------
! colour: digit-walk the number after pKey in the (already UPPERED) prefs text.
! Explicit walk - the line ends in CR/LF and whole-string numeric coercion of
! trailing junk is not to be trusted. 0 = key absent / no digits.
! NB 'CHGCOLOR ' cannot false-match 'CHGCOLOR2 ' (the trailing space differs).
! ------------------------------------------------------------------------------------
UiNum PROCEDURE(StringTheory pSt, STRING pKeyx)
p   LONG,AUTO
v   LONG
c   STRING(1),AUTO
  code
  p = pSt.findChars(pKeyx)
  if ~p then return 0.
  p += len(pKeyx)
  loop while p <= pSt._DataEnd
    c = pSt.valuePtr[p]
    if c < '0' or c > '9' then break.
    v = v * 10 + val(c) - 48
    p += 1
  end
  return v

! ====================================================================================
! colour: the SELECTED-row variant of the changed-line fill - each RGB component
! scaled to 4/5 so a changed line stays visibly tinted under the cursor while the
! un-starred Line column still shows the normal selection bar (= the selection cue).
! ------------------------------------------------------------------------------------
DarkenColor PROCEDURE(LONG pC)
cr  LONG,AUTO
cg  LONG,AUTO
cb  LONG,AUTO
  code
  if pC < 0 then return pC. ! COLOR:None and friends pass through
  cr = band(pC, 0FFh) * 4 / 5
  cg = band(bshift(pC, -8), 0FFh) * 4 / 5
  cb = band(bshift(pC, -16), 0FFh) * 4 / 5
  return cr + bshift(cg, 8) + bshift(cb, 16)
