# VitTransform - 1.0.3

**A safe, format-preserving code transformer for [Clarion](https://www.softvelocity.com/) source code.**

You give VitTransform a list of rules (or switch on one of its built-in transforms), point it at your
`.clw`/`.inc` files, and it rewrites them - fixing patterns, flagging dead code, or tidying layout -
**without disturbing anything you didn't ask it to change.** Your comments, blank lines and indentation
are kept as you wrote them.

Its guiding rule is *when in doubt, do nothing*: if it can't prove a change is safe, it leaves the code
alone. It never deletes code it merely suspects of being dead - it comments it out, with a note saying
why.

Two programs ship together:

- **VitTransform.exe** - the command-line tool: transforms files, writes reports.
- **VitStyle.exe** - a visual companion: tick the transforms you want, watch a live
  before|after preview, and save your choices as a named profile the command line can replay.

Two rule files ship with it. **`vitrules.txt`** is the main one and does everything, layout included.
**`cosmetic.txt`** is a cut-down alternative that does layout *only* - see [The shipped rule files](#the-shipped-rule-files)
for which to use.

## Contents

**Getting started**
- [A note from the author](#a-note-from-the-author) - seven years of it, and why
- [Install](#install)
- [Quick start](#quick-start) - running in one minute
- [FAQ](#appendix-f-faq) - the impatient reader's section. It lives at the back as Appendix F,
  but start there if you would rather have answers than an explanation
- [A few terms, in plain English](#a-few-terms-in-plain-english)

**Using it**
- [What it can do](#what-it-can-do)
- [Template exports (.txa)](#template-exports-txa---what-runs-and-what-is-refused)
- [`.clw` and `.inc` - what differs](#clw-and-inc---what-differs)
- [Choosing what runs: groups, choices, styles](#choosing-what-runs-groups-choices-styles)
- [`THOROUGH` - when the rules themselves need include expansion](#thorough---when-the-rules-themselves-need-include-expansion)
- [The shipped rule files](#the-shipped-rule-files)
- [VitStyle - the visual chooser and live preview](#vitstyle---the-visual-chooser-and-live-preview)

**Writing your own rules**
- [Writing rules](#writing-rules)
- [Your own rules, step by step](#your-own-rules-step-by-step) - where the file goes and how to switch it on

**Appendices - the reference material**
- [Appendix A: Command line](#appendix-a-command-line)
- [Appendix B: Every switch](#appendix-b-every-switch)
- [Appendix C: Built-in transforms](#appendix-c-built-in-transforms)
- [Appendix D: Rule file reference](#appendix-d-rule-file-reference)
- [Appendix E: Reading the comments in the source](#appendix-e-reading-the-comments-in-the-source) - only if you are changing VitTransform itself
- [Appendix F: FAQ](#appendix-f-faq) - the same FAQ linked above, kept here so the appendices are complete

[License](#license)

---
## A note from the author

It's probably not too often that a product takes seven years of work before its first
release - but this is the case with VitTransform.

In fact its genesis can be traced many years earlier. I recall - probably around the turn of
the century - working on an app that had lots of instances of `left(clip(myString))` when
of course the coder actually meant `clip(left(myString))`. I started searching the generated
code and then going into the IDE to fix them, but it was laborious. So, I ended up exporting
the app to TXA and then writing a simple search and replace before importing the TXA into a
new version of the app.

Sometime later, I would look at code and then manually make changes - and the same changes
came up frequently. I thought "Wouldn't it be better to automate this?" and so started writing
code to make existing Clarion code more efficient. Some changes were almost trivial while
others were harder. I could look with my eyes at a variable and the code that used it and know
almost straight away if it should have AUTO on it - but getting code to examine all branches to
guarantee a variable is always written before it is read turns out to be harder than you might
think!

I had started transforming Clarion code directly on the `.clw` until in 2019 I decided that
splitting the code into tokens would make transformations easier, hence, VitTokenize was born.
This is the basis on which VitTransform works: things are split into tokens, these are
transformed, and then they are all put back together again at the end.

I worked on VitTransform off and on in my spare time - sometimes there would be a concentrated
burst for a few months and then a break while other things in life took precedence.

Initially when using VitTokenize, all my transformations were "hard coded" in Clarion code - so
I wondered "Wouldn't it be better if the rules, the transformations, were all just data in a
simple ASCII file". And so an "engine" was needed to parse the rules and implement them against
the selected code. This, of course, meant you could implement new rules without writing Clarion
code - you just needed to write the new rule. And this opened up the product so that *anybody*
could implement their own transformations - things I had not thought about.

That, in a nutshell, is how VitTransform came about. In the last few months I have used AI to
add new features and search for and fix bugs etc. I started with Gemini but ended up deciding
Claude was the better choice (for me at least - YMMV). Using AI can certainly make one more
productive - at the cost of the code often being sprinkled with AI artifacts and code that is
"not the way I would have done it!". But life is full of compromises.

VitTransform ships with standard rules that you can either use "as is", adapt, or write your
own. This README should give you all the details you need no matter how deeply you wish to use
it.

I should add that not all transformations alter the code structure; some are purely cosmetic.
Everyone has their own preferences on how many characters you should indent - or whether
keywords should be UPPER or lower or Title cased. Or whether you prefer END or dot/period. And
should you have one-liners? And so on - VitTransform allows you to easily reformat code to make
it feel comfortable and look better to *your* eyes. At the other end of the spectrum, many
transformations are about making the code more efficient, with a particular emphasis on
StringTheory use.

Finally, a separate exe VitStyle allows you to experiment with rule selection (or writing your
own rules) and applying them to a selected `.clw` file (or an `.inc`, or a snippet you paste)
with a before/after display so you can instantly see what changes are made.

The product is released under the permissive MIT License. You can use the binary exes provided
or compile the Clarion source yourself - the code uses CapeSoft's StringTheory extensively so
you need to have a licence for ST if you want to build it yourself (but hopefully you already
have that!)

Anyway, as I said, this product has been the result of years of work - I hope you find it
useful.

cheers

**Geoff Robinson**<br>
vitessegr AT gmail DOT com<br>
August 2026

---


## Install

**If you just want to use VitTransform, you do not have to build anything.** Two ready-made
programs come with it - `VitTransform.exe` and `VitStyle.exe`. If you wish to use those then
skip the rest of this section and go directly to the [Quick start](#quick-start) below.

The rest of this section is for building the tools from the provided source, which requires StringTheory.

There are **two solutions**, one per program. Build both in **Clarion** (I happen to use Clarion
11.13505 but any recent release should be fine), Release configuration:

| | |
|---|---|
| `VitTransform.sln` | the command-line tool, `VitTransform.exe` |
| `VitStyle.sln` | the visual chooser, `VitStyle.exe` |

Both projects set `<Model>Lib</Model>`, which links the Clarion runtime INTO each exe. That
is deliberate: the two exes are then **self-contained**, with no `ClaRUN.dll` to ship beside
them. It costs about 700 KB per exe.

As mentioned, **building either exe needs a recent version of [StringTheory](https://www.capesoft.com/accessories/StringTheorySP.htm)**, from CapeSoft.
VitTransform uses it extensively throughout its own code - it is a great tool and I
wouldn't code without it - so it is required to compile. I am probably biased, having contributed
to ST, but I think it is well worth buying if you don't already have it.

---

## Quick start

> **Keep a backup, and test what comes out before you ship it.** This is ordinary good practice
> rather than a warning about VitTransform - the same thing you would do before any bulk edit. The
> tool is built to leave your code alone when it isn't sure, it writes to a separate output
> directory unless you explicitly tell it not to, and `--dry-run` shows you everything first. None
> of that is a substitute for your own source control and your own testing. Read the report, diff
> the output, build it, run your tests.

Three commands. Only the first writes no files at all - and none of the three touches your
originals.

```
VitTransform vitrules.txt src\*.clw --dry-run
```
**See what would change.** Writes no files at all - just a report. It is often a good idea to start here
on a codebase you haven't run it over before.

```
VitTransform vitrules.txt src\*.clw out
```
**Do it for real, into `out\`.** Your originals are untouched; the transformed copies go in `out\`.
Diff them before you trust anything.

```
VitTransform cosmetic.txt src\*.clw out
```
**Layout only** - it never changes what your code *does*. But "layout" is more than spacing, and
this command does all of it, because `cosmetic.txt`'s default style is `tidy`: it lines up trailing
comments and `CASE` labels, breaks over-long lines at a sensible point, strips trailing whitespace,
**and also upper-cases keywords, re-indents to two spaces, and splits `a = 1 ; b = 2` onto separate
lines.** That is a bigger diff than you may be expecting on a first run. `--style=` picks a
different set, and `--nogroup=` turns any single one off - see [The shipped rule files](#the-shipped-rule-files).

Every run writes a report next to the rule file. Every change is logged as
`rule <id> line <n>: <before> ==> <after>`, and the header records exactly which groups and styles
were active - so any run can be reproduced later.

Prefer buttons to switches? Run `VitStyle vitrules.txt`. It opens with sample code already in the
preview, so you can tick a transform and watch what it does straight away - see
[the first five minutes](#the-first-five-minutes). Nothing there touches your files.

> **Overwriting your originals.** With no output directory VitTransform would overwrite the files in
> place, so it refuses unless you pass `--in-place` - and even then it writes a timestamped `.bak`
> first, and will not overwrite anything if that backup cannot be written. An output directory that
> is really the source directory is refused for the same reason.

---

## A few terms, in plain English

VitTransform's docs use some standard compiler words. Here's what they mean here:

- **Rule file / DSL** - a plain-text file where you write your find-and-replace rules. "DSL" (domain-specific
  language) just means it's a tiny, purpose-built format for *this one job* - not a general programming
  language. One rule per line: `pattern ==> replacement`.
- **Token / tokenize** - before doing anything, VitTransform splits your source into its smallest pieces
  (words, symbols, punctuation, and the whitespace/comments between them). Working on tokens instead of raw
  text is how it understands structure while leaving the formatting around them alone.
- **Pass / fixpoint** - VitTransform applies your rules to the whole file, top to bottom - that's one *pass*.
  Because one change can expose another, it repeats passes until a full pass changes nothing. That
  "nothing-left-to-do" state is called a **fixpoint**. (It stops there, and there's a safety cap on the
  number of passes.)
- **Receiver** - the thing before the dot in `object.method()`. In `myString.trim()`, the receiver is
  `myString`.
- **Type-safe / symbol table** - VitTransform reads your variable declarations to build a *symbol table*
  (a map of "which name is what type"). A rule tagged for `StringTheory` then fires **only** on a
  StringTheory receiver and is refused on, say, a `CSTRING`. That's what "type-safe" means: the tool checks
  the type before rewriting.
- **Group / choice / style / profile** - the selection system (its own section below). A **group** is a
  named bundle of rules you can switch on or off. A **choice** is a set of groups where only one can be on
  at a time (like radio buttons). A **style** is a named combination of groups shipped in the rule file.
  A **profile** is your own saved combination (VitStyle writes these for you).
- **Format-preserving** - your layout survives a run. Indentation, blank lines and the text of your
  comments are never touched. There are five deliberate exceptions, all small and all listed under
  *Tidy up layout* below: trailing whitespace goes, over-long lines are split, and trailing comments,
  `CASE` labels and declaration types are lined up. Those five run on their own, and they run whether or
  not a rule changed the file - which is what makes a layout-only run worth doing. Each can be turned
  off (`--width=0`, `--nogroup=cosmetic-aligncomments`). The larger reformatting transforms - re-indenting,
  keyword case, block terminators - are all opt-in, and even then only the specific thing you asked for
  changes.

---

## What it can do

### 1. Rewrite patterns you describe (rule files)

Write rules like `myString.setValue(myString.getValue() & x) ==> myString.append(x)` and VitTransform
applies them everywhere they safely match. Rules can be **typed** (only fire on a given receiver type),
**guarded** (`WHERE` conditions), **one-shot** (`ONCE`), and more. See *Writing rules* below.

### 2. Find problems and flag them (analysis - it comments out, never deletes)

These add a `!` in front of the suspect lines and log why, so nothing is lost and you stay in control:

- **UnusedVars** - variable declarations that are never used.
- **UnusedRoutines** - `ROUTINE`s that nothing ever `DO`es.
- **UnreachableCode** - statements that can never run (e.g. code after an unconditional `RETURN`).
- **UnusedAssignments** - values written to a variable that are never read before being overwritten
  ("dead stores").
- **AutoCheck** - checks whether a local variable's `,AUTO` attribute is safe, and adds or removes it
  accordingly. **Expect your loop counters to gain it:** a counted `LOOP i = 1 TO n` assigns `i` on
  entry, before the first limit test and even when the body never runs, so the commonest local in
  Clarion is provably safe and gets `,AUTO`. A variable assigned only *inside* that body does not -
  the body may run zero times.
  It is biased to caution: it only *adds* `,AUTO` when it can prove the variable is always set
  before it's read.

### 3. Restructure code (motion)

- **HoistCommonBranchCode** - if both branches of an `IF`/`ELSE` end (or begin) with the same statement,
  it moves that shared statement out of the branches. Moves are done by relocating the exact tokens, so the
  code is preserved, not re-typed.

### 4. Clean up common Clarion idioms

Ports of well-tested cleanups: combine adjacent string literals, remove doubled brackets, tidy `CASE`
statements, normalise `replace()`/`remove()`/concatenation calls, and align trailing comments.

### 5. Tidy up layout (opt-in cosmetic formatting)

Each of these is **opt-in** - if you don't ask for it, your formatting is untouched. Turn one on by adding a
`BUILTIN <name>` line to your rule file.

> Five layout tidy-ups are **not** in this list, because they are not opt-in: removing trailing spaces
> and tabs from line ends, splitting over-long lines, aligning trailing comments and continuations,
> aligning `CASE` labels, and aligning the type column of a run of declarations. They run on their own,
> on the settled text, and they run **whether or not any rule changed the file** - so a
> layout-only run does useful work on code the rules have nothing to say about.
> Trailing-whitespace removal is unconditional and line splitting answers to `--width=`. The other three
> are one group between them: `--nogroup=cosmetic-aligncomments` turns off comment/continuation
> alignment, `CASE` label alignment and declaration-type alignment together.

- **KeywordCase** - make keyword capitalisation consistent: `STYLE('lower')`, `'upper'`, or `'title'`
  (`'camel'` and `'pascal'` are accepted as aliases of `'title'`). An attribute form,
  `BUILTIN KeywordCase, UPPER`, works too if you prefer it to `STYLE(...)`.
  It changes four things: keywords, data types, calls to Clarion's own functions, and declaration
  attributes. It never touches your own names.

  ```
  ! before                                      ! after  (STYLE('lower'))
  MyProc  PROCEDURE()                           MyProc  procedure()
  Total     LONG,AUTO                           Total     long,auto
    CODE                                          code
    IF NOT Total AND OrCount = 2                  if not Total and OrCount = 2
      Total = LEN(CLIP(MyText))                     Total = len(clip(MyText))
    END                                           end
  ```

  Note what stayed as you wrote it: `MyProc`, `Total`, `OrCount`, `MyText`. Clarion doesn't care about
  the case of a name, but you do, so the tool leaves names alone.

  The function list covers what people actually write - `CLIP LEN SUB UPPER LOWER LEFT RIGHT FORMAT
  DEFORMAT INSTRING VAL CHR ABS TODAY CLOCK RECORDS POINTER SIZE OMITTED` and about eighty more. A name
  only counts as a function call when a `(` follows it, so a variable of your own called `Size` is
  untouched - and if you have written your own procedure named `Clip`, that is yours and is left alone
  too.
- **SplitStatements** - put `a = 1 ; b = 2 ; c = 3` onto three separate lines. A `;` with nothing
  after it is simply **removed** - it separates the statement from an empty one - and a `|`
  continuation next to a split becomes the `!` comment it already behaves like, so anything you
  wrote after the bar stays where you wrote it. Lines carrying block structure are left alone.
- **ExpandOneLiners** - turn an inline `if C then S. else T.` into a normal multi-line block:

  ```
  ! before                                ! after
  if Name = '' then Name = 'unknown'.     if Name = ''
                                            Name = 'unknown'
                                          end
  ```

- **BlockEndStyle** - convert block terminators between `.` and the word `END`
  (`STYLE('end')` or `'period'`; `'dot'` is accepted as an alias of `'period'`).
  Works on a terminator standing on its own line *and* on one
  sharing a line with code, so `if x then y.` and `if x then y END` convert both ways.

  It will not touch a line carrying **two or more** terminators - a stacked `. .` closing
  several blocks at once is left exactly as written. Expanding one correctly would mean
  counting how many blocks the run closes, and a wrong count reshapes your block structure
  without failing loudly, so the tool declines rather than guesses. Method dots, decimal
  points and a column-1 `End` label are never candidates.
- **Reindent** - re-indent executable code consistently. Options:
  - `WIDTH(n)` - spaces per nesting level (default 2).
  - `CASEOF('flush'|'indent')` - whether `OF`/`OROF`/`ELSE` inside a `CASE` line up with the `CASE`
    (flush, the default) or sit one level under it (indent).
  - `CODECOL(n)` - *(optional)* also re-base the whole procedure body to column `n`, anchored on the
    `CODE` statement. Without it, Reindent fixes nesting but leaves each procedure's existing base indent
    as-is. The baseline belongs to the procedure that declared it: a `ROUTINE` shares its procedure's
    baseline, and the next `PROCEDURE` starts again from its own `CODE`, so a data section is left
    exactly as you wrote it. Declared structures - `QUEUE`, `GROUP`, `WINDOW`, `REPORT` and the rest -
    keep their interior layout untouched wherever they appear.

  Reindent never moves a column-1 label, so declarations and data structures are always left alone.

Example - Reindent with `WIDTH(2)`:

```
! before                            ! after
  if Err                             if Err
        Msg = 'save failed'            Msg = 'save failed'
   if Retries < MaxRetries             if Retries < MaxRetries
  Retries += 1                           Retries += 1
      end                              end
  end                                end
```

---

## Template exports (`.txa`) - what runs, and what is refused

VitTransform will transform a `.txa` (a Clarion template export) as well as a `.clw`. It is
recognised by the extension; you do not have to say anything.

```
VitTransform vitrules.txt MyApp.txa out
```

**Only the source you embedded is touched.** A `.txa` is mostly template data - the procedure
list, prompts, window definitions, the `NAME` / `FROM` / `PRIORITY` lines. None of that is
Clarion, so none of it is transformed, and the file comes back with its structure byte-for-byte
as it was. Your code lives in the `[SOURCE]` blocks, and that is the only place anything changes.

### What the analyses do differently on a `.txa`

**A template export does not contain the code the template generates**, so any analysis
that reasons from "every use I can see" is working from half the story: a variable used
only by generated code looks unused, a routine `DO`ne only from generated code looks
orphaned, and a read in generated code is invisible to `,AUTO`'s always-set-before-read
proof. Rather than refusing wholesale, each analysis does the most it can honestly do:

| | on a `.txa` |
|---|---|
| `UnusedVars`, `UnusedAssignments`, `AutoCheck` | **Restricted** to a procedure or routine contained **wholly inside one embed**, where every possible reference really is visible. In practice that mostly means routines - a template procedure's code is spread across embeds with generated code between them. Anything spanning embed points is left alone, and the report counts what was withheld and why. |
| `UnusedRoutines` | **Annotates, never removes.** "No `DO` found" is not proof here, so an apparently-unused routine gets a `! possibly not used - ...` comment above its header for you to check - added once, not per pass. |
| `UnreachableCode` | **Stops at embed boundaries.** A `RETURN` kills what follows it *in its own embed only* - generated code between embed points can rejoin flow invisibly, so the dead-walk never crosses one. |

The report says so rather than quietly finding less:

```
BUILTIN UnusedVars: RESTRICTED on a .txa to procedures/routines wholly inside one
embed - the template's generated code is not in this file, so anything spanning
embed points cannot be decided here. Run on the generated .clw for full coverage.
```

**For full coverage, run the analyses on the generated `.clw`**, where the whole
procedure is visible. Everything else - the rule files, the idiom cleanups, the layout
tidy-ups - runs normally.

### Why it needs pre-processing at all

Embedded source starts in **column 1**, and column 1 in Clarion is label position. Handed
straight to the parser, every line of your code would read as a label. So a `.txa` is wrapped
before parsing and unwrapped afterwards: code inside CODE embeds is shifted one column right, a
real `PROCEDURE` header is synthesised for each procedure so its declarations and code share a
scope, `WHEN` continuations are folded onto one line, and everything that is template data is
held aside. Every one of those edits leaves a marker recording how to undo it, and the unwrap
undoes them in the opposite order - so a run that changes nothing gives you your file back
unchanged, byte for byte.

### The rest of the limits, in one place

- **Only `[SOURCE]` blocks are treated as Clarion.** Rules can only fire there. Everything
  outside one - the procedure list, prompts, window definitions, `NAME` / `FROM` / `PRIORITY`,
  and all the application and template metadata ahead of the first `[DATA]` - is held aside
  during the run and put back byte-for-byte.
- **The analyses are restricted or softened**, as above - full coverage needs the
  generated `.clw`.
- **Column-1 shifting happens in CODE embeds only.** In a DATA embed, column-1 text really is a
  label and is left exactly where it is.
- **The wrap assumes bytes 250-255 do not appear in your `.txa`.** They are used as the markers
  that record how to undo each step, and they are safe because a template export is plain text
  and the template writer does not emit them. This is **not checked**, so a `.txa` that
  contained one would be pre-processed wrongly. Nothing normal produces such a file.
- A `.txa` is recognised **by its extension alone**. Rename a template export to `.clw` and it
  will be parsed as Clarion source, which it is not.

---

## `.clw` and `.inc` - what differs

Name either and it is transformed; there is nothing to switch on. But two things behave
differently on an `.inc`, and both come from the same fact: **an include file is only half a
compilation unit.**

**A declaration-only `.inc` disables `UnusedVars`, and the report says so.** An equates file, or
any `.inc` with no `CODE` statement anywhere, cannot reference the things it declares - the real
references are in the programs that include it, and they are invisible from here. Scanned on its
own, *every* declaration in it looks unused, so the builtin would comment out the entire file.
It detects that and skips itself instead:

```
BUILTIN UnusedVars: no CODE statement in file (include fragment) - skipped
```

This is the same premise failure as the `.txa` case above: a whole-file scan assuming it can see
every reference. `UnusedRoutines`, `UnreachableCode`, the rules and the layout builtins are all
unaffected and run normally.

**Typed rules need the declaration to be visible.** A rule written on `st.method(...)` where `st`
is a `StringTheory` fires only when the tool can *prove* the receiver's type. The common miss: a
receiver reached **through a class field declared in a `.inc`** - `myObj.buffer.trim()` where
`buffer &StringTheory` lives in the class's header file. Transforming the `.clw` on its own
leaves that type unknown, and the rule refuses rather than guessing - so the transform quietly
does not happen. Three ways round it, in order of preference:

| | |
|---|---|
| `--thorough` | expands the `INCLUDE`s and resolves the type properly. The right answer. |
| `--root=<dir>` | the same, when you would rather name the Clarion install than have it found |
| `ASSUME st* StringTheory` | a rule-file line saying "identifiers named like this are that type". Useful when the declaration is somewhere the tool cannot reach at all |

`--loose` also widens matching, but it downgrades typed metavars rather than resolving them, so
it is the blunt option - it will match things the type gate was there to exclude.

---

## Choosing what runs: groups, choices, styles

A rule file can offer *alternatives* - for example, some teams want blank tests spelled
`if ~s` (compact) and others want `if s = ''` (explicit). The selection system lets one
rule file serve both, and lets you pick per run.

### In the rule file

```
! -- an on/off group: these rules run only when the group is selected --
GROUP deadcode, OFF                     ! OFF = opt-in, unselected by default
if st.instring('a') = 0   ==>  if st.containsChar('a') = false
ENDGROUP

! -- a CHOICE: two groups on one axis, only one can be on --
GROUP blank-collapse, CHOICE(blank-test), DEFAULT
if s = ''   ==>  if ~s
ENDGROUP
GROUP blank-explicit, CHOICE(blank-test), REVERSE(blank-collapse)
ENDGROUP

! -- styles: named combinations, shipped with the file --
STYLE optimised = blank-collapse
STYLE readable  = blank-explicit
```

Reading that:

- `GROUP name ... ENDGROUP` wraps rules into a switchable bundle. Rules outside any
  group are always on.
- `OFF` makes a group opt-in (unselected unless you ask for it).
- `CHOICE(axis)` puts groups on a shared axis - selecting one deselects the others,
  like radio buttons. `DEFAULT` marks the file's default pick for that axis.
- `REVERSE(other-group)` is the clever one: it **auto-derives the inverse rules** of
  another group. `blank-explicit` above contains the reversed rules of
  `blank-collapse` (`if ~s ==> if s = ''`) without anyone writing them by hand - so
  the two spellings can never drift apart.
- `FINAL` **defers** a group. Its rules are inert for every pass of the fixpoint and get
  exactly one pass afterwards, on the settled text, just before comment alignment. For a
  transform whose *output* the analysis passes cannot read - see below.
- `STYLE name = group, group, ...` ships a named combination. Members are always
  **names, never line numbers**, and a `-name` member means "explicitly off".

**Why `FINAL` exists.** It looks like a scheduling detail and it is really a correctness one.

**A `FINAL` rule runs once, after everything else has settled, and nothing runs after it.**
That is the whole of it. Some rewrites produce a *finished* spelling - compact output that no
later rule was written to read. If such a rule ran during the normal fixpoint, a rule further
down could read its output, fail to recognise the new shape, and undo work that was already
correct. Deferring it is simpler and safer than teaching every other rule about every compact
form.

Deferred rules get **one pass, not a fixpoint**, so they do not cascade into each other. That is
deliberate: if cascading is ever wanted it should be asked for explicitly, not arrive as an
accident of ordering.

### On the command line

| Switch | Effect |
|---|---|
| `--style=<name>` | Apply a shipped STYLE (or a loaded profile) by name. Overrides the rule file's `DEFAULTSTYLE`, if it has one. |
| `--stylefile=<file>` | Load a profile file (STYLE + LASTUSED lines) - e.g. the one VitStyle saves. |
| `--group=<name>` | Select a group (on top of the style/defaults). **Repeat the switch for several groups.** |
| `--nogroup=<name>` | Deselect a group. Repeatable, same as above. |
| `--batch` | **Unattended.** Never open a modal box; anything that would have been one is appended to `vt-batch.log` instead - not suppressed, since each is something you must see (a rule file refused to load, output that is not on disk). Also makes `--thorough` take the newest Clarion rather than asking. Required by unattended build scripts, which have nobody to click OK |
| `--dumptokens` | Write the include-expanded token stream to `<file>.tokens.txt` - named after the **transformed file** (with a wildcard source, the last file transformed: that is the stream the dump describes) - with the level mark in column 1, and report three things: every level-opening token sitting **inside parentheses** (where nothing can open a structure), every unmatched **open**, and every **close that closes nothing**. Needs `--thorough`. For chasing an unbalanced level census |
| `--acdiag` | **Diagnostic.** Explains why comment alignment left each comment where it is. After the columns have settled, every comment that ends up in a different column from the one above it is reported with the numbers behind the decision and the reason it could not be moved - `FROZEN` (an anchored comment sets the column), `OUT-OF-WINDOW` (more than ten lines from the comment above it) or `CAPPED` (moving it would push the line past the width limit). Writes to a `Log on <date> at <time>.txt` in the current directory, and switches the tokenizer's own file logging on to do it. Use it when a comment sits where you did not expect - a line reporting a non-zero adjustment that the output does not show has been *decided* but not *applied*, which is a different bug from one that was never decided at all |

> **Comma lists work.** `--group=a,b` and `--group=a --group=b` are equivalent, and comma
> lists are equally fine inside STYLE lines and profile files.
>
> **A path containing a space must be QUOTED** - `VitTransform vitrules.txt "C:\My Source\a.clw" out`.
> The command line splits on spaces, so an unquoted path arrives as two arguments. Quoted
> positionals work everywhere a path is accepted.

No switches = the file's defaults. Every report header prints the **resolved selection
table** - which groups ended up on and why - so a report is always a repeatable
experiment.

```
VitTransform vitrules.txt src\*.clw out --style=readable
VitTransform vitrules.txt src\*.clw out --style=optimised --group=deadcode
VitTransform vitrules.txt src\*.clw out --stylefile=VitStyle.profiles.txt --style=mystyle
```

### What the StringTheory rule file offers

> The groups, axes and styles below all live in `vitrules.txt`.

**A run with no `--style=` gets `plain`.** The rule file carries a file-level line

```
DEFAULTSTYLE plain
```

which names the style a run with no `--style=` gets. The report header says where it came
from, so two runs of the same command line can never differ in silence:

```
[selection] style: plain (file default - DEFAULTSTYLE)
```

It is a **default, not a base layer**: it applies only when you give no `--style=`. An
explicit `--style=` **replaces** it outright - the style you ask for is the style you get,
and anything the default style would have switched on that your style does not mention
stays at its file state rather than leaking through. Axes your style does not name still
fall back to their per-axis `DEFAULT` members, and `--group=`/`--nogroup=` still layer on
top of whichever style applied. Take the line out and every axis falls back to its per-axis
`DEFAULT` member instead, with the header reading `style: (file defaults)` - which is exactly how
a rule file that carries no `DEFAULTSTYLE` line behaves.

`DEFAULTSTYLE` is refused in a `--userrules=` file, like `STYLE` and `LASTUSED`. A user
file is *appended* to the shipped one, so a `DEFAULTSTYLE` there could silently re-select
every axis in a rule file it does not own.


## `THOROUGH` - when the rules themselves need include expansion

A shipped rule file may carry a bare directive on its own line:

```
THOROUGH
```

It asks for include expansion - the same thing `--thorough` does - **on the rule file's
behalf**. That is where the need usually lives: a rule set full of typed StringTheory
receivers cannot resolve them when the classes are declared in `.inc` files, so it cannot do
its job without expansion, and that is a property of the *rules* rather than of the style you
picked to run them. One visible line in a file you already read beats a switch everyone has to
remember to type.

**It asks; the command line decides.** In order:

| | |
|---|---|
| `--nothorough` | the explicit **no**, and it beats everything - including an explicit `--root=`. An implicit switch you cannot turn off is worse than no switch |
| `--thorough` / `--root=<dir>` | the command line was always the loudest voice |
| `THOROUGH` in the rule file | travels with the rules that need it |
| *(nothing)* | off |

The report says which of those applied, so a run is never ambiguous about it:

```
[THOROUGH: requested by the rule file, line 17 - --nothorough turns it off]
[--nothorough: include expansion OFF for this run - the rule file asked for it at line 17]
```

**It fails loudly.** If the directive is set and no Clarion installation can be found, the run
stops and says so - naming the *directive and its line*, not `--thorough`, which you never
typed and would go looking for. Running with less knowledge than the rule file says it needs
is precisely the silent under-transformation the *declaration not visible* report line exists
to expose.

`THOROUGH` is refused in a `--userrules=` file, like `DEFAULTSTYLE`, `STYLE` and `LASTUSED`:
a user file is *appended* to the shipped one, and it must not reach out and change how the
whole run reads your source tree.

Worth knowing what this actually turns on. `plain` is not "do nothing" - it takes the
shorter, tidier form everywhere that only removes something redundant you wrote. What it
holds back are the three changes that buy speed at the cost of a longer, less obvious line.
`--style=optimised` adds those:
`fastcompare`, which compares a StringTheory in place instead of copying its buffer out;
`st-findbyte`, which turns `st.findChar('=')` into `st.findByte(61) ! '='`; and
`st-getvalue-slice`, which turns a procedure's `return st.getValuePtr()` into the direct
slice. `--style=readable` is the one that actively changes direction.

**Choice axes** - exactly one member of each is ever active:

| Axis | Members (default first) | Effect of the non-default member |
|---|---|---|
| `choose-test` | `choose-collapse` / `choose-explicit` | `choose(a = b, true, false)` -> `choose(a = b)`, or restore the long form |
| `fastcompare` | `fastcompare-on` / `fastcompare-off` | compare an ST's bytes directly instead of calling `getValue()`, or leave the call alone. ONE shape covers the family: `st.getValue() = w` becomes `choose(st._DataEnd < 1, '', st.valuePtr[1 : st._DataEnd]) = w`. The comparee can be a literal, a variable, an expression or another ST; `<>` and `~=` keep your spelling; `upper()` and `lower()` folds carry through; and a bare `~` needs no parentheses, because the replacement is a single comparison |
| `blank-test` | `blank-collapse` / `blank-explicit` | `if s = ''` -> `if ~s`, or restore |
| `zero-test` | `zero-collapse` / `zero-explicit` | `if n = 0` -> `if ~n`, or restore |
| `delete-mode` | `delete-remove` / `delete-comment` | a `DELETE` rule removes the statement, or comments it out with the reason beside it |
| `reindent` | *(none)* / `cosmetic-reindent-2` / `-3` / `-4` | selects `BUILTIN Reindent` and its indent width. No default - reindenting is off unless you pick one |
| `findchar-form` | `st-findchar-keep` / `st-findbyte` / `st-findchar` | which spelling a single-character search uses. The default member is **empty** - neither spelling is touched. `st-findbyte` (in `optimised`) converts to the byte methods, `st.findChar('=')` -> `st.findByte(61) ! '='`; `st-findchar` (in `readable`) converts back |
| `getvalue-form` | `st-getvalue-asis` / `st-getvalue-keep` / `st-getvalue-slice` / `st-getvalue-slice-all` | how a procedure returns a StringTheory's value. `st-getvalue-asis` (in `plain`) leaves it exactly as written - it is the only member that rewrites nothing. `st-getvalue-keep` (the per-axis default, and in `readable`) gives `return st.getValuePtr()`. `st-getvalue-slice` (in `optimised`) gives `return choose(st._DataEnd < 1, '', st.valuePtr[1 : st._DataEnd])` - the same slice with no virtual call, and `''` rather than an unbound `&string` when the buffer is empty. Declared **`FINAL`**, so it runs after the fixpoint (see below). `st-getvalue-slice-all` is the same rewrite **everywhere, not only in a return** - assignments, arguments, concatenations, comparisons. Also `FINAL`, and **off by default**: outside a comparison it saves the virtual call but not the copy, and it is roughly ten times the changes on a StringTheory-heavy file. Ask for it with `--group=st-getvalue-slice-all`. No reverse member on this axis: the inverse pattern's only occurrences of the metavar are dotted, and a dotted metavar cannot be the first binding of its head |

**Standalone groups** - independent on/off switches:

| Group | Default | What it does |
|---|---|---|
| `lenclip-collapse` | **ON** | `if len(clip(s)) > 0` -> `if s` (and the `= 0` / `<> 0` spellings, in `if`/`elsif`/`and`/`or`/`while`/`until`) |
| `clip-absorb` | **ON** | absorb a redundant `clip()` into the call's own flag - `st.setValue(clip(s))` -> `st.setValue(s, st:clip)`, letting the method do the trimming. **One-way: no style puts it back**, because `st.setValue(s, st:clip)` reads as plainly as the `clip()` did and saves the call. Type-gated - only a declared `STRING`, `CSTRING` or `PSTRING` converts |
| `merge-guards` | **ON** | enables `BUILTIN MergeGuardChain`: consecutive single-line `IF`s that set the *same* thing are merged into one. Three `if p.containsByte(...) then f = 1.` lines against one receiver become a single `if p.containsA('\/.') then f = 1.`; anything less uniform becomes one OR-joined `IF` written a condition to a line, so each keeps its own comment. **A `FINAL` group**: it runs in the deferred pass after everything else has settled, because it has to read the finished chain |
| `cosmetic-aligncomments` | **ON** | enables `BUILTIN AlignComments`, and with it `CASE` label and declaration type alignment - `--nogroup=` it to leave all three alone and keep your columns exactly as written |
| `cosmetic-splitstatements` | off | enables `BUILTIN SplitStatements` |
| `cosmetic-expandoneliners` | off | enables `BUILTIN ExpandOneLiners` |
| `deadchoose` | off | enables `BUILTIN DeadGuard` and `BUILTIN DeadLeft` - they clean up after `st-getvalue-slice`, so they only earn their keep when that is on. **A `FINAL` group**: it runs in the one deferred pass after everything else has settled, because what it reads is what the other `FINAL` rewrites wrote. `--style=extreme` selects it |

**Cosmetic axes** - pick at most one from each; none is selected unless you ask:

| Axis | Members |
|---|---|
| `keywordcase` | `cosmetic-keywordcase-lower`, `cosmetic-keywordcase-upper`, `cosmetic-keywordcase-title` |
| `reindent` | `cosmetic-reindent-2`, `cosmetic-reindent-3`, `cosmetic-reindent-4` |
| `blockend` | `cosmetic-blockend-end`, `cosmetic-blockend-dot` |

`cosmetic.txt` offers exactly the same three axes, so a choice you make in one file names the same
group in the other.

**Shipped styles:**

Five ship. The first four are `vitrules.txt`'s and `plain` is what a plain run of it
gets; `tidy` belongs to `cosmetic.txt` and is what a plain run of *that* gets.

| Style | In | Selects |
|---|---|---|
| `plain` | `vitrules.txt` | **The default.** `blank-collapse`, `zero-collapse`, `choose-collapse`, `lenclip-collapse`, `fastcompare-off`, `st-findchar-keep`, `st-getvalue-asis` - the cleanups that remove redundancy from what you wrote, and none of the three axes that rewrite working code just to make it run faster |
| `optimised` | `vitrules.txt` | `blank-collapse`, `zero-collapse`, `fastcompare-on`, `choose-collapse`, `lenclip-collapse`, `st-findbyte`, `st-getvalue-slice` |
| `readable` | `vitrules.txt` | `blank-explicit`, `zero-explicit`, `fastcompare-off`, `choose-explicit`, `lenclip-collapse`, `st-findchar`, `st-getvalue-keep` |
| `extreme` | `vitrules.txt` | **Everything that changes what the code does**, and nothing that changes its layout. `optimised`'s list, plus `st-getvalue-slice-all`, `analysis`, `deadchoose`, `deadcode` and `general-compound-assign`. **It comments code out** - unused routines, unreachable statements, dead stores - and its hoist drops a duplicated statement outright. Much the biggest diff the tool produces: `--dry-run` and read it first. Spelled out below the table. |
| `tidy` | `cosmetic.txt` | `cosmetic-aligncomments`, `cosmetic-keywordcase-upper`, `cosmetic-reindent-2`, `cosmetic-splitstatements` - this is why a plain `cosmetic.txt` run upper-cases keywords and re-indents |

**`extreme`, spelled out.** It is `optimised`'s list with four additions and one substitution:
`st-getvalue-slice-all` in place of `st-getvalue-slice`, so *every* `getValue()` becomes the direct
slice rather than only the ones in a return or a comparison; `analysis`, which is `IfChainToCase`,
`TrailingSpaces` and `KnownRanges` - the three that read furthest into your code; `deadchoose`
(`DeadGuard` and `DeadLeft`), which clears up after the slice rewrite this style turns on; and
`deadcode` plus `general-compound-assign`.

**`deadcode` mostly comments code out** - unused routines, unreachable statements, dead stores - so
this style does more than make code faster. Those three leave the text where it is with a note
saying why, and the report lists them all. The fourth is different, and worth knowing before you
switch it on: when both halves of an IF start or finish with the same statement, the hoist moves
that statement outside the IF and removes the second copy, so that one line goes rather than being
marked. The cosmetic axes deliberately stay out, because they are
*choices*: including one would pick your keyword case and indent width for you.

Expect far more changes, and wider lines. On one 15,000-line file the slice-everywhere rule alone
was 106 changes against 11, so `--dry-run` and a diff really are not optional here.

A note on the byte conversion, because it is easy to get wrong by hand: a **boolean**
test keeps a boolean method. `if s.findChar('<10>')` becomes
`if s.containsByte(10)`, never `findByte` - only a genuine **position** use becomes
`findByte`. The two are not interchangeable: `containsByte` returns true/false,
`findByte` returns a position.

Neither style touches the cosmetic groups or reindenting - layout stays your business
unless you ask for it.

---

## The shipped rule files

Two files ship, and they are **not** two separate sets of rules - the second is a narrower view of
the same ones.

| | |
|---|---|
| **`vitrules.txt`** | The main rule file. Everything: the StringTheory and general rewrites, the analyses, **and all the layout builtins**. |
| **`cosmetic.txt`** | Layout only. **No rewrite rules at all** - it cannot change what your code does. |

**The layout builtins are in both files.** The difference is what is switched on and what choices you
are offered:

| | in `vitrules.txt` | in `cosmetic.txt` |
|---|---|---|
| `AlignComments` | on | on |
| `KeywordCase` | off, lower/upper/title | **on (upper)**, lower/upper/title |
| `Reindent` | off, widths 2/3/4 | **on (2)**, widths 2/3/4 |
| `SplitStatements` | off | **on** |
| `ExpandOneLiners` | off | off |
| `BlockEndStyle` | off, `end`/`dot` | off, `end`/`dot` |

So `cosmetic.txt` is for when you want your layout tidied and nothing else touched - it is safe to
run on code you are not ready to have rewritten. Use `vitrules.txt` for everything else; if you want
its layout builtins on as well, switch them on with `--group=`.

> **Five layout tidy-ups run whichever of the two you use**: trailing whitespace removal, over-long
> line splitting, comment/continuation alignment, `CASE` label alignment and declaration-type
> alignment. The first two are engine-side; the other three ride the `BUILTIN AlignComments` line
> that both shipped files carry. See [Appendix C.3](#c3-layout).

### What `vitrules.txt` gives you

| Turn it on with | What you get |
|---|---|
| *(nothing)* | The default style, `plain`: safe general cleanups plus StringTheory call-pattern modernisation - `setValue(sub(...))` -> `Crop`, prepend+append -> `Enclose`, absorbing a redundant `clip()` into the call's own flag, redundant `clip()` dropped from comparisons and - on a variable provably declared STRING, CSTRING or PSTRING - from bare condition tests (`if clip(s)` -> `if s`; a bare string in a condition is already the non-blank test, and the type gate matters because on a numeric the two spellings genuinely differ), `instring`/`findChars` -> `findChar`/`containsChar`, `cat` -> `Append`, adjacent-literal combining, doubled-bracket removal, single-char `CASE` -> `val()`, **UnusedVars** and **AutoCheck**. It also runs **`MergeGuardChain`** (the `merge-guards` group, on by default): consecutive single-line `IF`s that set the same thing become one guard - a structural change, so it is called out here rather than left to the group table. Type-gated: StringTheory rules only touch receivers it can prove are StringTheory (`--thorough` widens that proof across includes). |
| `--style=optimised` | Everything `plain` does, plus the three changes that buy speed: `fastcompare`, `st-findbyte`, `st-getvalue-slice`. Faster code, at the cost of longer and less obvious lines. |
| `--style=readable` | The conservative alternative - the longer, more explicit form rather than the compact one. |
| `--style=extreme` | Every group that changes what the code does, layout excepted: `optimised` plus the slice everywhere (`st-getvalue-slice-all`), plus `analysis`, `deadchoose`, `deadcode` and `general-compound-assign`. **It comments dead code out as well as rewriting** - that is `deadcode`'s job and it is included on purpose; its hoist also removes a duplicated statement outright. Much the biggest diff the tool produces; `--dry-run` and read it. |
| `--group=analysis` | The three deeper analyses: `IfChainToCase`, `TrailingSpaces`, `KnownRanges`. Off by default because they read further into your code than anything else here. |
| `--group=deadcode` | `UnusedRoutines`, `UnreachableCode`, `UnusedAssignments`, `HoistCommonBranchCode` - these **comment out** code, never delete it. |
| `--group=general-compound-assign` | `tot = tot + 1` -> `tot += 1`. Off by default: it is a house-style choice, not a correctness fix. |
| `--group=st-getvalue-slice-all` | Every `st.getValue()` becomes the direct slice, not just the ones in a `return` or a comparison. Off by default, and `FINAL` - it runs once, after everything else has settled. Expect a lot of changes and wider lines; outside a comparison it saves the call, not the copy. |
| `--nogroup=cosmetic-aligncomments` | Leave trailing comments where you put them. |

It is plain text - open it, read the comments, delete or `SKIP` any rule you don't want. First run
on a new codebase: use an `<outdir>` (or `--dry-run`) and diff before trusting.

> **A note on rule ids.** A rule's id - the number in reports, and what `--only=` and
> `--skip=` take - is its **line number in the rule file**. Add a comment or a blank line
> and every id below it moves. Quote the rule file's version along with the id when
> reporting anything. VitTransform refuses a `--only=`/`--skip=` id that matches no rule,
> rather than silently doing nothing.

---

## VitStyle - the visual chooser and live preview

### The first five minutes

Start it from the folder holding your rule file:

```
VitStyle vitrules.txt
```

**It opens ready to use** - a small piece of sample code is already loaded, so the *Before* pane
shows it and *After (live)* shows what the current selection does to it. You can start clicking
straight away and watch the right-hand side change.

A good order for a first look:

1. **Pick a style** from the `Style:` droplist at the top left and press **`Apply`**. The *After*
   pane redraws. This is the quickest way to see the difference between `plain`, `optimised`,
   `readable` and `extreme`.
2. **Turn individual transforms on and off** in the left-hand list - double-click a row, or select it
   and press **`Toggle`**. The preview redraws on every click, so you can see exactly what each one
   does to real code before you commit to it.
3. **Read what a transform does** in the *About the highlighted group* panel below the list - the
   description comes from the rule file itself, so it always matches the rules you actually have.
4. **Find the changes.** Every changed line is marked `>`. The *Changes* list at the bottom right
   names each rule that fired; click a row and both panes jump to that line. `<< Prev` and `Next >`
   step through them, and `Chg colour...` changes the highlight if it is hard to read.
5. **Try it on your own code.** `Open file...` (top right) loads one of your `.clw` or `.inc` files
   into the preview; `Paste...` takes a snippet you type or paste in. Everything above works the
   same way on it.
6. **Keep the combination** with **`Save profile...`**. It writes a name of your choosing into
   `VitStyle.profiles.txt` beside the exe, and *shows you the command line that reproduces it* so you
   can use the same selection in a batch run.

**Nothing you do in this window changes your source.** The preview transforms a copy for display
only. The only files VitStyle writes are its own three, all beside the exe: `VitStyle.profiles.txt`
when you save a profile, `VitStyle.rules.txt` when you save from the Workbench, and
`VitStyle.ui.txt` remembering your changed-line colour.

### The window itself

`VitStyle [rulefile]` opens a window with two halves:

**Left - the chooser.** Every group and choice in the rule file, with its current state, a
description harvested from the comments above each GROUP line, and the engine's own
resolved-selection table. Double-click (or Toggle) to flip a group; pick a shipped style from the
droplist.

**The shape of the bracket tells you what a click will do**, and the two are not interchangeable:

| marker | meaning | what clicking it does |
|---|---|---|
| `[X]` / `[ ]` | an **independent** group - a check box | turns just that group on or off |
| `(o)` / `( )` | one member of a **CHOICE axis** - a radio button | turns that one on **and its siblings off** |

A choice axis is a decision the rule file says can only be made one way at a time: how a blank
test is spelt, whether `getValue()` becomes a slice, and so on. Turning one member on necessarily
turns the others off, so a `( )` click changes something you did not click. An `[ ]` never does.

The ten axes are `blank-test`, `blockend`, `choose-test`, `delete-mode`,
`fastcompare`, `findchar-form`, `getvalue-form`, `keywordcase`, `reindent` and `zero-test`.
Everything else is independent: `analysis`, `deadcode`, `deadchoose`, `merge-guards`,
`lenclip-collapse`, `clip-absorb`, `general-compound-assign` and the `cosmetic-*` groups.

VitStyle decides nothing itself - every click goes through the same resolver the
command line uses, and the display is read back from the engine, so what you see is
exactly what a batch run would do.

**Right - the live preview.** A before|after view of real code (a built-in demo, any
`.clw`/`.inc` you open, or a pasted snippet), re-transformed on every click through
the same engine pipeline. Changed lines are marked `>`; clicking a line in either
pane scrolls the other pane to its counterpart (the engine reports exactly which
source line became which output line, so this stays right through splits, merges and
expansions). A Changes list at the bottom names every rule that fired with its
source line - click one and both panes jump there.

**Save profile...** writes your current selection as a named STYLE line to
`VitStyle.profiles.txt` (next to the exe), plus a LASTUSED marker so VitStyle reopens
where you left off. The save dialog shows the exact command line to replay it in
batch:

```
VitTransform <rules> <src> <out> --stylefile=VitStyle.profiles.txt --style=<yourname>
```

The profile file is plain text and safe to hand-edit.

**Workbench...** opens a modal editor for **your own rules**, kept in `VitStyle.rules.txt`
next to the exe. VitStyle loads that file at startup if it is there, and does so
*non-fatally*: a file with a mistake in it warns and is skipped, the workbench still opens,
and you can fix it in place rather than being locked out by your own typo.

Pick one of your rules from the droplist to edit it, or type a new one. A rule is
`pattern ==> replacement` followed by the optional `WHERE` / `NOTE(...)` / `SKIP` / `ONCE`
parts described under [Writing rules](#writing-rules).

| Button | |
|---|---|
| **Lint** | Checks the file you are about to write - shipped rules, your existing ones and the draft, all together. **Zero errors is the condition for saving**, so a rule file that would not load cannot be written in the first place. |
| **Test** | Runs the draft against whatever is in the live preview and shows exactly which lines it fires on, before and after, on top of your current selection. You see what a rule does before you keep it. |
| **Save** | Writes `VitStyle.rules.txt` and refreshes the main window. |

**A GROUP you declare in your own file arrives switched OFF**, so wrapping your rules in one
means they can never quietly change a run - you turn it on in the chooser, or with `--group=`,
exactly like a shipped group. (A rule *not* inside a group is ungrouped, and ungrouped rules
always run. See [Your own rules, step by step](#your-own-rules-step-by-step).) Groups from your
file are marked `(user)` in the resolved-selection table, so a report always says where a rule
came from.

For batch runs the same file goes in with `--userrules=<file>`, appended after the shipped
rule file. It is **off unless you ask for it**, so a run without it is byte-identical to one
from a machine that has no user rules at all. Your rule ids are offset by 500000 - rule
`500096` in a report is line 96 of your file - so they can never collide with shipped ids in
a log.

---

## Writing rules

Rules live in a plain-text file, **one rule per line**, as `pattern ==> replacement`. A rule's id is its
line number. A `METAVARS` header at the top declares your placeholders; any word that *isn't* a declared
placeholder is a literal the source must contain. Bare words match **case-insensitively** (`getvalue`
matches `GetValue`); a **quoted** literal (`'abc'`) must match case-exactly. The replacement is written
with the rule's own spelling - matched metavar spans are copied from the source verbatim.

**Operators with more than one spelling match each other.** Clarion documents `<=` and `=<` (and `~>`)
as the same operator, likewise `>=`, `=>` and `~<`, and `<>` with `~=`. A rule written one way matches
source written any of them, so you do not have to write the rule three times. The two-word forms
(`NOT =`, `NOT <`, `NOT >`) are two tokens and are *not* equated.

A **metavar** (metavariable) is a named wildcard: it matches any code of a given kind, and if you use the
same name twice it must match the *same* code both times - compared the way that kind of token is
compared, so `foo(?L, ?L)` accepts `foo(Name, NAME)` (identifiers are caseless in Clarion) but **not**
`foo('Yes','YES')`, because a quoted literal is content.

### A first rule, end to end

```
METAVARS
st              StringTheory    ! typed: only fires when the receiver is a StringTheory
w               EXPR            ! any single balanced expression

st.setValue(st.getValue() & w)  ==>  st.append(w)
```

What it does to your code:

```
! before                                      ! after
buf.setValue(buf.getValue() & name)           buf.append(name)
log.setValue(log.getValue() & ' at ' & tm)    log.append(' at ' & tm)
line.setValue(other.getValue() & x)           (no change - receivers differ: line vs other)
cs.setValue(cs.getValue() & x)                (no change if cs is a CSTRING - wrong type)
```

Note the last two: `st` used twice means *the same variable* both times, and the
type gate refuses anything that isn't provably a StringTheory.

### Your own rules, step by step

The section above shows how to *write* a rule. This is where you put it and how you run it.

**1. Put it in a file.** Any name will do. A complete, working one is this short:

```
GROUP my-rename-rule
st.oldLog(w)  ==>  st.newLog(w)
ENDGROUP
```

That is the whole file. **No `METAVARS` block** - and that is not laziness, it is required:

> ### The first thing that goes wrong
> Your file is **added to** `vitrules.txt`, not loaded instead of it, so the shipped
> metavars are **already declared** and you must not declare them again. `vitrules.txt`
> already gives you `st st2` (StringTheory), `w w1 w2 w3 w4 w5` (EXPR), `lit`, `nm`, `a`, `c`, `v`
> and more - see its `METAVARS` block, or run `VitTransform vitrules.txt` on its own: it writes an `.ir.txt` beside the rule file that lists every one. (`--summary` prints the run box, which gives the metavar COUNT, not the names.)
>
> Re-declaring one is a hard error and the run stops before it changes anything:
>
> ```
> line 500003 ERROR duplicate metavar declaration: st
> ```
>
> Only add a `METAVARS` block for a **new** name of your own. Everything already declared is
> yours to use for free.

**2. Decide whether it should run immediately.**

- **Inside a `GROUP`, it arrives switched OFF.** Nothing happens until you ask for it by name.
  This is the safer habit and the one to use for anything you mean to keep.
- **On its own, with no `GROUP`, it runs straight away** - an ungrouped rule is always active.
  Fine for a one-off; surprising if you were not expecting it.

**3. Run it.** Your file is loaded *after* the shipped rule file, so it adds to `vitrules.txt`
rather than replacing it:

```
VitTransform vitrules.txt src\*.clw out --userrules=myrules.txt --group=my-rename-rule
```

Drop the `--group=` if you did not wrap it in one. Add `--dry-run` first if you want to see the
report before anything is written.

Leave `--userrules=` off and the run is byte-for-byte what it would be on a machine that has no
rules of yours at all - so a shared build never behaves differently because of a file sitting on
your disk.

**4. Or let VitStyle do it.** Name the file `VitStyle.rules.txt` and put it next to the exe;
VitStyle loads it at startup and the **Workbench...** button edits it, lints it and shows you
what it fires on before you save. See
[VitStyle](#vitstyle---the-visual-chooser-and-live-preview).

**5. Find it in the report.** Your rule ids are offset by **500000**, so the id is 500000 plus
the line number in *your* file. The rule above sits on line 2, and the report reads:

```
rule 500002 line 7: buf . oldLog ( name ) ==> buf.newLog(name)
```

`line 7` is the line in the **source file** it changed. Shipped rules keep their own numbers, so
yours can never be confused with them.

**What a user rule file may not contain:** `STYLE`, `DEFAULTSTYLE`, `THOROUGH` and `LASTUSED` are refused -
those decide what a *plain* run does, and that is the shipped rule file's job, not an add-on's.
Everything else in [Appendix D](#appendix-d-rule-file-reference) is available to you.

### More worked examples

```
METAVARS
st st2          StringTheory
w w1            EXPR
lit             LITERAL         ! a quoted string literal
n               NUM             ! any numeric type - see TYPESET below

! 1. A guard: only fire when the matched literal is not blank once trailing spaces go
st.append(clip(lit))  ==>  st.append(trimr(lit))  WHERE lit <> ''

!    before:  st.append(clip('abc  '))        after:  st.append('abc')
!    before:  st.append(clip('   '))          after:  (unchanged - guard refused)

! 2. Two statements collapsed into one (the ; matches a statement boundary)
st.prepend(w) ; st.append(w1)  ==>  st.Enclose(w,w1)

!    before:  s.prepend('<<')                 after:  s.Enclose('<<','>')
!             s.append('>')

! 3. Delete a do-nothing statement outright (indent + trailing comment survive)
st.crop()  ==>  DELETE

! 4. Leave a breadcrumb in the code where you changed it
n = n + 1  ==>  n += 1   NOTE('modernised by rules')

!    before:  tot = tot + 1                   after:  tot += 1  ! modernised by rules
```

---

# Appendix A: Command line

```
VitTransform <rulefile>
      Check the rule file for mistakes and write out its parsed form
      -> <rulefile> on <yyyymmdd> at <hhmmssth>.ir.txt

VitTransform <rulefile> <source> [outdir] [switches]
      Transform mode. <source> may use wildcards (e.g. src\*.clw).
      Give an <outdir> to write transformed copies there.
      With no <outdir> VitTransform would overwrite the originals, so it
      refuses unless you pass --in-place (see below). --dry-run is exempt:
      it writes nothing, so it needs no <outdir> and no --in-place.
      A run report is written to <rulefile> on <yyyymmdd> at <hhmmssth>.report.txt

      Every output filename carries the run's date-time stamp (th = hundredths),
      computed once per run - so repeated runs keep separate reports, results
      and IR dumps instead of overwriting each other. Open the NEWEST one.

      Only three arguments are positional - <rulefile> <source> [outdir].
      A fourth is refused rather than ignored, because it is a PATH WITH A
      SPACE in it that was not quoted. QUOTE any path containing a space:

          VitTransform vitrules.txt "C:\My Source\a.clw" out

      Quoted positionals work (verified). Unquoted, C:\My Source\a.clw
      arrives as two arguments and the run is refused - which is the good
      case; give one fewer argument and it would instead try to read
      "C:\My" and write into "Source\a.clw".
      A switch VitTransform does not recognise also stops the run before
      anything is read or written. A near miss such as --dry-runn would
      otherwise make a DIFFERENT run from the one asked for.

      --batch is read BEFORE any of this, in a pass of its own, so a refusal
      raised while the command line is still being parsed is written to
      vt-batch.log rather than opening a modal box on an unattended run.
      Write it anywhere on the line; last is fine.

      EXITS 1 if a source you asked for could not be read. The summary line
      of the report says NOT LOADED: n. A watched sweep that transforms
      nothing must not report success.
```

> **Safety:** VitTransform never overwrites your originals by accident. If you
> omit `<outdir>` it stops and reminds you to either give an output directory or
> pass `--in-place`. An `<outdir>` that is really the **source directory itself** -
> spelled `.`, relative, or absolute - is refused the same way: writing there would
> overwrite the originals, and the `<outdir>` path keeps no `.bak`. Only files that
> actually change are ever written.

> **Exit code:** a clean run exits **0**. Anything a calling script must see exits
> **1** - a refused switch or rule file, rule-file errors, a save that failed, a wildcard
> that matched no files, or a header that could not be found while expanding includes
> (the type registry is incomplete when that happens, so the typed rules only saw part
> of your program) - so a batch file can test `ERRORLEVEL` instead of parsing the report.

> **Line endings:** output is always **CRLF**. A file VitTransform does not change is not
> rewritten at all, so it keeps whatever it had; a file it *does* change comes back CRLF even
> if it arrived LF-only. That is not a lossy step - LF-only is not valid Clarion source, so
> normalising it is the more useful answer than faithfully reproducing something the compiler
> would reject.

Example - apply rules from `myrules.txt` to every `.clw` in `src\`, writing results to `out\`:

```
VitTransform myrules.txt src\*.clw out
```

---

# Appendix B: Every switch

| Switch | Effect |
|---|---|
| `--summary` | Show the end-of-run message box. **Off by default**, so a batch of runs goes straight through without anyone clicking OK - every number in that box is in the report file anyway. A failure to SAVE still shows regardless. |
| `--dry-run` | Analyse and report, but write nothing. |
| `--in-place` | Overwrite the source files (only needed when you give no `<outdir>`). Before overwriting a changed file, its original is saved alongside as a timestamped `.bak` (e.g. `Foo on 20260714 at 14302547.clw.bak`), so nothing is ever lost. If the backup can't be written, that file is left untouched. |
| `--verbose` | Detailed per-rule, per-file logging. |
| `--loose` | Ignore the symbol table - apply typed rules to any receiver (for comparison/diagnosis). |
| `--only=<id>` | Run only one rule. A rule's id is its **line number in the rule file**, so open the file at that line to see which rule you are naming. Built-in transforms are suppressed too, so what you see is that rule alone. A `BUILTIN` line's id is also its line number, so `--only=<its line>` runs just that builtin - that is how you try one analysis on its own. |
| `--skip=<id>` | Skip one rule. Same id rule as above. |
| `--passes=<n>` | Cap the number of passes (see *fixpoint* above). |
| `--receiver=<mode>` | What to do when a built-in cannot identify a receiver: `assume` rewrites it as a StringTheory, `check` refuses it when a nearby use is not a StringTheory method (**default**), `strict` refuses it unless it provably resolves. See D.4. |
| `--width=<n>` | The longest line to allow before VitTransform splits it. **Default 200.** Use `--width=120` to set your own, or **`--width=0` to switch line splitting off completely**. Minimum 40. |
| `--userrules=<file>` | Load your own extra rule file on top of `vitrules.txt`. Its **groups** arrive **off** - select them with `--group=` - so loading a file can never change a run on its own. An **ungrouped** line in that file (a plain rule, or a `BUILTIN`) is active immediately. Your file **inherits** the shipped file's metavars and typesets, so do not redeclare them - a `METAVARS` block naming `st` again is an error, not an override. Ids in a user file are offset by 500000, so `--only=` on one of your own rules takes `500000 + <its line number>`. |
| `--style=` `--stylefile=` `--group=` `--nogroup=` | Selection - see *Choosing what runs* above. |
| `--batch` | **Unattended mode.** No modal boxes - anything that would have been one is appended to `vt-batch.log` instead - and `--thorough` takes the newest Clarion rather than asking. Full description in the table under *Choosing what runs* above. |
| `--dumptokens` | **Diagnostic.** Write the include-expanded token stream to `<file>.tokens.txt` and report unbalanced level marks. Needs `--thorough`. Full description under *Choosing what runs* above. |
| `--acdiag` | **Diagnostic.** Explain why comment alignment left each comment where it is. Full description under *Choosing what runs* above. |

## B.1 Naming the output files

By default the output keeps the source's name (`src\Foo.clw` -> `out\Foo.clw`). To keep several runs side by
side, insert a suffix before the extension:

| Switch | Effect |
|---|---|
| `--outsuffix=<text>` | Insert `<text>` before the extension, e.g. `--outsuffix=Width2` -> `FooWidth2.clw`. |
| `--outstamp` | Append ` on yyyymmdd at hhmmssth` (date + time to hundredths), e.g. `Foo on 20260714 at 14302547.clw`. |

They combine, and the timestamp is computed once per run so every file in a batch shares it.

## B.2 Overloaded methods

Clarion lets a class declare the same method name more than once, and the forms often
differ in what they return - one builds and returns a value, another fills something you
pass in:

```clarion
GetTok   Procedure(LONG pTokNumber),STRING,proc,virtual
GetTok   Procedure(LONG pTokNumber, StringTheory pStrBefore, StringTheory pTok),virtual
```

The return type belongs to the **overload**, not to the name, so VitTransform picks the
overload by the **number of arguments at the call site**. `GetTok(n)` is one
argument and only the first form can take it, so its result binds as a `STRING`;
`GetTok(n, a, b)` is three and binds as nothing. Defaults and `<omittable>` parameters are
counted properly - a form declared `(LONG pStart=1, LONG pEnd=0, <STRING pFormat>)` accepts
anywhere from **zero to three** arguments.

Where the count alone cannot decide - two forms that both accept it and disagree about the
return type - the **argument types** break the tie. Every prototype's parameter types are
recorded position by position, and each argument the caller can type is tested against its
own slot:

```clarion
JoinToks Procedure(LONG pStart=1, LONG pEnd=0, <STRING pFormat>),STRING     ! 0 to 3 args
JoinToks Procedure(StringTheory st, LONG pStart=1, LONG pEnd=0, <STRING>)   ! 1 to 4 args
```

Both accept three arguments, so `JoinToks(st, 1, 0)` is settled by `st` being a
StringTheory - it selects the second form, which returns nothing. `JoinToks(1, 5)` selects
the first, which returns a `STRING`. The test is not limited to the first position: a call
that is ambiguous at argument one can be settled by any later argument the tool can type.

> **Why not export-style decoration?** Clarion's export decoration identifies a prototype
> by its parameter *types* alone - names and defaults never appear, so nothing can drift -
> and matching a **definition** to its **declaration** that way is exact, because both
> sides carry full types. VitTransform borrows exactly that idea, per position. What it
> deliberately does not borrow is the whole decorated signature as an all-or-nothing key:
> a **call site** has expressions, not types, and any argument the tool cannot type would
> make a decorated key match nothing at all. Testing each position independently keeps
> decoration's virtue - types, never names - while a position the tool cannot type simply
> has no opinion.

VitTransform narrows **only on a positive determination**: an argument whose type it
resolved, or a literal, which is certainly not a class instance. An argument it could not
type - an unresolved identifier, or an expression like `a + b` - narrows nothing, and the
call goes back to being refused. That asymmetry is deliberate: an identifier that merely
failed to resolve might be the class instance, and excluding that overload on a guess would
pick the string-returning form and rewrite a call that never returns a string.

When nothing settles it, VitTransform **refuses to type the call** and typed rules do not
fire on it. A missed rewrite is a cost; a wrong one changes your code.

## B.3 Thorough mode (cross-file type resolution)

By default, VitTransform works out receiver types from the declarations **in the file it's transforming** -
fast, and no setup. If a receiver's type is declared in an **included header** (e.g. `self.buffer`, where
`buffer &StringTheory` lives in a `.inc`), turn on include expansion so those types can be resolved too:

| Switch | Effect |
|---|---|
| `--thorough` | Turn on thorough mode and **find your Clarion install automatically** - first from the Windows uninstall registry, then by probing `<drive>:\Clarion*` (covers installs copied over from a backup, which never registered). One install found: used silently. Several: you pick from a dialog (so unattended batch runs should use `--root` instead). |
| `--nothorough` | The explicit **no**. Turns include expansion off for this run, and beats both a `THOROUGH` directive in the rule file and an explicit `--root=` - it is the escape hatch, so nothing outranks it. |
| `--root=<dir>` | Your Clarion install directory (e.g. `c:\Clarion11`). Providing this also turns on thorough mode, and always overrides `--thorough` discovery. |
| `--red=<file>` | The `.red` redirection file. Default: `Clarion110.red` in the working directory if present, otherwise the newest `Clarion*.red` in `<root>\bin` (its normal home). |
| `--config=<name>` | Build configuration macro (default `Release`). |

```
VitTransform myrules.txt src\MyClass.clw out --thorough
VitTransform myrules.txt src\MyClass.clw out --root=c:\Clarion11
```

**It buys more than receiver types.** Expanding the includes also fills the *type registry* - the list
of which names are classes - and two things lean on that beyond resolving a receiver:

- **Picking between overloads.** Where several methods share a name, VitTransform chooses by argument
  count and then by the type of each argument it can work out. One of those tests is *a numeric or
  quoted literal cannot be a class instance*, which needs to know whether a parameter's declared type
  **is** a class. Without include expansion the registry holds only the classes declared in the file
  itself, so that test cannot exclude anything and an otherwise-decidable overload is refused.
- **Return types.** A method's declared return class comes from the same registry, so a rule that
  needs "this call returns a STRING" is more often satisfied.

The practical effect is that `--thorough` doesn't only resolve *more receivers* - it also lets rules
fire on calls that would otherwise be left alone. If a rule you expected to fire didn't, running with
`--thorough` is the first thing to try.

> **One limit worth knowing:** thorough mode reads your **included** declarations once, at the
> start of each file, and typed decisions for the rest of that file use that picture. A rule set
> that *rewrites declarations in an include* - retypes a field, renames a class or a prototype -
> therefore doesn't mix with `--thorough` in a single run: later rules would still see the old
> types. The supported shape is two runs - the declaration pass first, then everything else
> against the updated files.

---

# Appendix C: Built-in transforms

Some jobs can't be expressed as a pattern - "is this variable read before it is written?"
needs an analysis, not a rewrite. Those ship as **builtins**, switched on by naming them in
the rule file. Parameters follow the name, comma-separated. A builtin can live inside a
`GROUP` like any rule, which is how the cosmetic suite is kept opt-in.

```
BUILTIN UnusedVars, PREFIX('! #Removed as not used: '), EXCLUDE(procname pn)
BUILTIN AutoCheck, NOTE('AUTO unsafe: read before write')
BUILTIN Reindent, WIDTH(4), CASEOF('indent')
```

## C.1 Analysis - the deep reads, and what each is allowed to remove

**Your code is only ever commented out, never deleted** - that is the rule for the four that
judge whether something is used at all (`UnusedVars`, `UnusedRoutines`, `UnreachableCode`,
`UnusedAssignments`), and every line they touch keeps its text behind a marker you can grep
back. The rest of the table is the other kind: they retire code that is **provably redundant**
- a guard that cannot fire, a `clip()` that cannot strip, a `left()` with nothing to its left -
and those go for real. Each carries its proof into the report, which is the thing to read
before you accept one.

| Builtin | What it does | Parameters |
|---|---|---|
| `UnusedVars` | Comments out declarations nothing references. | `PREFIX('text')` - the comment marker written in front of the line. `EXCLUDE(a b c)` - names never to touch. |
| `UnusedRoutines` | Comments out `ROUTINE`s that no `DO` ever reaches, whole body included. Cascades: a routine only reachable from a removed routine goes next pass. | `PREFIX`, `EXCLUDE` as above. |
| `UnreachableCode` | Comments out statements that can never run - anything after an unconditional `RETURN`/`EXIT`/`BREAK`/`CYCLE`/`GOTO`, up to the next rejoin point. | `PREFIX('text')` - the comment marker written in front of the line. |
| `UnusedAssignments` | Comments out dead stores: assignments to a local that is written but never read. Feeds `UnusedVars` - once the writes are gone the declaration is unused too. A name reached over a `\|` line continuation is a *comparison*, not a store (`IF a = 1 AND \|` / `x = 5`), and is never counted as a write. | `PREFIX('text')` - the comment marker written in front of the line. |
| `AutoCheck` | Adds `,AUTO` to locals it can **prove** are written before every read, and removes it from ones that are read first. `,AUTO` skips zero-initialisation, so a wrong add is a real bug - the analysis refuses whenever it cannot prove safety. | `SAFE` - removals only, never add (the zero-risk direction). `NOTE('text')` - the comment left on a removal. `WHY` - explain every declaration that did *not* get `,AUTO`, one line each. |
| `KnownRanges` | Retires a guard or a `choose()` that provably cannot go the other way, by tracking where a local's value came from. `p = st.findChar('=')` followed by `if ~p then break.` means `p` is 1..`_DataEnd`, so `if p - 1 < st._DataEnd then ...` can never fail and the guard goes. Also turns `sub(q, x - q + 1)` into `slice(q, x)` when both are provably >= 1, and removes a **span copied around a gap** - see below. | `PURE(a b c)` - extra call names to treat as side-effect free. |
| `DeadGuard` | Retires the guard **this tool emitted** when an earlier one proves it cannot fire. `st-getvalue-slice` writes `choose(st._DataEnd < 1, '', st.valuePtr[1 : st._DataEnd])`, which is load-bearing in general - `valuePtr` is unbound on an empty StringTheory - but not in a procedure that has already returned on empty: `if st._DataEnd < 1 then return.` four lines above makes the test decidable, so what is left is the slice. The proof is a backward walk that gives up on any call which could mutate the receiver, and a receiver passed **bare** to anything at all counts as a mutation. In group `deadchoose` (off, `FINAL`) | - |
| `DeadLeft` | Drops a `left()` that provably has nothing to strip: the receiver was cleaned above it - `Trim()`, or a `setLeft()` whose flags can be **read** as including `st:spaces` - and the read starts at a literal `1`, so there can be no leading space to remove. `left(st.sub(1, p - 1))` -> `st.sub(1, p - 1)`. `Trim('*')` strips something else and proves nothing; a read starting at `2` proves nothing about character 2. Runs after `DeadGuard` in the same group, and takes the `left()` that `DeadGuard`'s work uncovers | - |
| `TrailingSpaces` | Where nothing below a point can observe **or create** a trailing space, inserts one `clip()` and then retires the code that asked about them - `clipLength()` becomes `_DataEnd`, a redundant `clip()` around `getValue()` goes. The only transform that INSERTS a statement; it logs insertions separately from rewrites. It can also read a fact proved in **another procedure in the same file** (see procedure summaries below), and names that procedure in the log line. | - |

**Where the analyses deliberately stand back.** Each of these judges a file on what that
file can see, so they withdraw wherever that premise fails: a file with no `CODE`
statement is an include fragment whose references live in the *including* programs, so
`UnusedVars` skips it entirely; module-scope data is only private in a `MEMBER` module,
so in a `PROGRAM` (where globals are visible to every module) it is left alone, as is
anything declared `EXPORT`/`EXTERNAL`/`DLL`; and `,AUTO` is never added to module-level
data, which is static storage rather than stack. The report says how many declarations
were withheld and why.

#### Removing a span

Rebuilding a string around a gap is four allocations and four copies:

```clarion
st.SetValue(st.sub(1, p - 1) & st.slice(q))       ! keep 1..p-1, keep q..end
st.RemoveFromPosition(p, q - p)                  ! the same thing, one memmove
```

Either piece may be written `sub(...)`, `slice(...)` or `valuePtr[a : b]`, on a plain
receiver or a dotted one - all nine combinations are recognised.

The guard is `q >= p`, and it comes from the search itself: `FindByte(ch, pStart)` scans
from `pStart`, so a non-zero result is at or after it. Without that fact the rewrite is a
**different program** - below `q = p` the original duplicates characters while
`RemoveFromPosition` clamps to a no-op - so a line whose shape matches but whose guard
cannot be earned is refused, and the report says which test failed:

```
BUILTIN KnownRanges line NN: span-removal REFUSED on st.setValue(...) - nothing says Q >= P
```

The only head length it accepts is `w - 1`. That is not a simplification for tidiness: it
is the sole form whose guard anything can derive.

#### Procedure summaries

`KnownRanges` and `TrailingSpaces` judge one procedure at a time, so a fact
established in a helper would be lost at the call. To keep it, the engine makes one pass over
the file first, and records for each procedure body a single fact about what it returns -
"never negative", "at least 1 and within the receiver", or "the buffer it hands back has
no trailing spaces". A call site can then use it.

The summaries are deliberately hard to earn, because a wrong one is a silent bug in the
caller. A summary is only recorded when every `RETURN` in the body agrees; a name that
appears twice in the file (an overload) collapses to "unknown", since a call site cannot
tell which body it reached; a method is only usable through `SELF.Method()` where the
prototype is visible and **not** `VIRTUAL` - a virtual call may land in a derived class
this file never sees; and any `DO` of a routine, or any bare mention of the buffer that
could take a reference to it, withdraws the fact.

#### The one thing to know about `setLength`

StringTheory's `SetLength` **grows as well as truncates, padding the new space with byte
32** - so `st.setLength(n)` where `n` exceeds the current length puts trailing spaces
*into* the buffer. `TrailingSpaces` therefore refuses to see through any `setLength`
except the one form where the author's own guard proves it can only shrink:

```clarion
if p - 1 < st._DataEnd then st.setLength(p - 1).
```

That guard is exactly the kind of provably-true guard `KnownRanges` deletes, which would
leave `TrailingSpaces` without the evidence it needs and make it refuse the same line from
the second pass onward. `TrailingSpaces` therefore remembers each guard it has accepted
(per file, per procedure, per receiver, per argument) and honours that proof on later
passes, so the two are independent and the order you list them in does not
change the result.

Both live in the `analysis` group in `vitrules.txt` - `--group=analysis` switches all three
on together.

## C.2 Idiom cleanups

| Builtin | What it does |
|---|---|
| `CombineAdjacentLiterals` | `'abc' & '123'` -> `'abc123'` |
| `RemoveDoubledBrackets` | `((expr))` -> `(expr)` |
| `CheckCaseStatements` | Single-character `CASE` values -> `val()` integers |
| `CheckCat` | StringTheory `cat` -> `Append`, including literal-length truncation |
| `CheckReplaces` | `replace`/`replaceByte` argument cleanup |
| `CheckRemoves` | `remove`/`removeByte` argument cleanup |
| `CheckSplits` | `st.split()`'s positional booleans become names - `st:clip` (5th) and `st:left` (6th) - and a trailing DEFAULT is deleted rather than named. Also takes clip/left off again when the split is on a SPACE with no quote arguments, where they are redundant |
| `CheckInLine` | the same for `st.inline()`: `st:noCase` (5th), `st:wholeLine` (6th), `st:anywhere`/`st:begins`/`st:ends` (7th - it is three-valued, not a boolean) and `st:clip`/`st:noClip` (8th) |
| `HoistCommonBranchCode` | Statements common to the **end** of both `IF` branches move out after the `END`, and statements common to the **start** move out before the `IF` - one per pass, so a run of them peels off in order. Comments on the two lines must **match** (compared as words, so the column may differ); a comment on one side only refuses |
| `MergeGuardChain` | Consecutive single-line `IF`s that set the **same thing** become one test. When every condition asks whether the same receiver holds **one character**, they collapse into a single `st.containsA('\/.')`; otherwise they become one `OR`-joined test with a condition to a line, so each keeps the comment written beside it. Merging is refused unless the assignment is identical in all of them and every condition is safe to **short-circuit** - N separate `IF`s evaluate N conditions and one merged test stops at the first true one, so a condition that does anything besides answer would be a different program. Purity is the list `IfChainToCase` uses, which `PURE(...)` extends |
| `IfChainToCase` | An `IF`/`ELSIF` chain of equality tests on **one repeated expression** becomes a `CASE`, so the expression is evaluated once instead of once per arm: `if lower(w.getValue()) = 'fold' or ... = 'trimr'` -> `case lower(w.getValue())` / `of 'fold' orof 'trimr'`. Bodies, a trailing `ELSE` and the terminator are untouched - only the heads are rewritten. The expression must be **provably pure**, since it now runs once where it ran N times; an arm that does not qualify refuses the whole `IF`. Parameter: `PURE(a b c)` |

## C.3 Layout

The five builtins in the table below are opt-in - add a `BUILTIN <name>` line to switch one on.
`AlignComments` is the exception: it is on by default.

**These five run after everything else has settled, including on a file no rule changed** - which is
why a layout-only run (`cosmetic.txt`) does useful work even on code the rules have nothing to say
about. Two of them are not builtins at all: trailing whitespace removal, which is unconditional, and
line splitting, which answers to `--width=`. The other three ride the `BUILTIN AlignComments` line
that both shipped rule files carry inside `GROUP cosmetic-aligncomments` - so they are on by default,
`--nogroup=cosmetic-aligncomments` turns all three off together, and a rule file of your own that
omits that line does not get them:

| | What it does |
|---|---|
| **Trailing whitespace** | Spaces and tabs removed from the end of every line. |
| **Line splitting** | A line longer than the limit (default 200, see `--width=`) is broken at a sensible point: after a comma at the outermost call depth, before a top-level `&`, `AND` or `OR`, or after the opening bracket. Long string literals are split too - `'first half ' & \|` then `'second half'` - including an escape group such as `'<0,1,2,3>'`, which splits at one of its commas into `'<0,1>'` and `'<2,3>'`. Where there is nowhere sensible to break, the line is left long rather than guessed at. When the line being broken already has continuations of its own, the new piece lands on **their** column rather than opening one of its own, so a statement you had lined up by hand stays lined up. |
| **Comment and continuation alignment** | Trailing `!` comments and trailing `\|` continuations of the same kind that are adjacent within a ten-line window form a group, and the group is put at the narrowest column that clears every member - one space past the widest code in it. **The column is computed from the code, never stepped towards**, which is what makes a second run change nothing and a reindent-and-back return to where it started. A full-line comment cannot move, so a group containing one settles no further left than that - **unless it is the rest of the comment above it**, which is the common case: a whole-line comment sitting in the comment field directly under a trailing comment is treated as that comment continued onto another line, and lands in the same column it does, so a wrapped comment stays in one piece instead of being split across two columns. A comment written at the **left margin** is not one of these and never moves. **A line that opens a structure sets no column** - a `CLASS` or `QUEUE` header, or a procedure prototype, never drags the fields under it out to match, because its width is an accident of the declaration rather than anything about the block. It may still **join** the column its block settles on, when that column clears its own code. A row whose comment is too long to sit at the shared column is placed one space past its own code instead. A `\|` written after a trailing `&`, `AND` or `OR` moves with that operator, and the gap between the two is normalised to one space, so lining up the `\|` lines up the operator as well. Never padded past the width limit. |
| **CASE label alignment** | `OF` and `OROF` labels close together line up in columns, one space after the longest entry in each. **A column is delimited by the arm keyword** (`OF`, `OROF`, `ELSE`, `;`), so an arm holding an expression - `of self.Match(TK:Operator, ':')` - lines up as one unit and keeps its own spelling; only whole arms move. If lining a block up would widen it by more than 20 characters, or push a block that currently fits past the width limit, it is left exactly as you wrote it. A run with no `OROF` in it is never touched. |
| **Declaration type alignment** | Straightens a run of column-1 declarations whose types **don't** line up, putting the type one space past the longest label. **A run that already lines up is left exactly as you wrote it**, whatever column you chose - see below. Only declarations count: a `PROCEDURE`, `CLASS` or `QUEUE` line ends the run. |

None of these ever change the text of a comment - only where the line ends and where the marker sits.

**"Already lined up" means left alone.** Declaration alignment only straightens a run that is actually
crooked. If your types already start in the same column, that was a decision and the tool has nothing to
say about it:

```
! ragged - so it is straightened          ! already level - so nothing happens
count LONG                                count   LONG
totalValue LONG                           total   LONG
n LONG                                    n       LONG

! becomes:                                ! stays exactly as it was, wider
count      LONG                           ! gutter and all
totalValue LONG
n          LONG
```

The second block is untouched even though the gutter is wider than the tool would have chosen. The
alignment only ever closes a run that is RAGGED; it does not impose a column of its own on one that is
already level. Picking a column and imposing it would turn `i long` / `n long` into `i  long` / `n  long`
- a file changed for no gain, which is the one thing a format-preserving rewriter must not do.

Between them, comment/continuation alignment, `CASE` label alignment and declaration type alignment are
the single group `cosmetic-aligncomments`: `--nogroup=cosmetic-aligncomments` turns off all three.

| Builtin | What it does | Parameters |
|---|---|---|
| `Reindent` | Re-indents block structure. | `WIDTH(n)` - spaces per level (default 2). `CASEOF('flush'\|'indent')` - whether `OF` sits level with its `CASE` or one step in (default flush). `CODECOL(n)` - also re-base each procedure body to column `n`, anchored on `CODE`; without it the existing base indent is kept (see *Tidy up layout* above). |
| `KeywordCase` | Normalises keyword casing. | `STYLE('lower'\|'upper'\|'title')`, default lower. |
| `BlockEndStyle` | Normalises block terminators, whether they stand on their own line or share one with code - `if x then y.` and `if x then y END` convert both ways. A line with two or more terminators (a stacked `. .`) is left alone; see the note above. | `STYLE('end'\|'period')` - spell `END` out, or use `.` (default `end`; `'dot'` is an alias of `'period'`). |
| `SplitStatements` | One statement per line - splits `;`-joined statements. A trailing `;` is removed rather than split; a `\|` continuation beside a split becomes a `!` comment, keeping its text. | - |
| `ExpandOneLiners` | `if c then s.` -> the three-line block form. | - |
| `AlignComments` | Aligns trailing comments into a column. Runs once at the end, on the settled text. **Unlike the rest of this table it is ON by default** - it belongs to the group `cosmetic-aligncomments`, so `--nogroup=cosmetic-aligncomments` turns it off. | - |

> Unknown parameter words are accepted and ignored, so an old rule file never fails to
> load on that account. The shipped `BUILTIN AutoCheck, ADD, REMOVE` line is an example -
> add and remove are simply the default behaviour, spelled out for the reader.

---

# Appendix D: Rule file reference

## D.1 Metavar types

A METAVARS line is **space-separated**: one or more names, then the type as the last word (no commas or
colons). Types are `EXPR` (any single balanced expression), `ARGS` (the contents of an argument list -
zero or more comma-separated arguments), `LITERAL` (a quoted string literal), `CONST` (an integer
literal or something that folds to one), `ANYVAR` (any single identifier, no type check), a Clarion
scalar type (`STRING`, `LONG`, ...), a class name like `StringTheory`, or a **TYPESET** name (below).

**Type sets** - declare a named class of types with `TYPESET`, then use the set name as a metavar type
so one rule covers the whole class:

```
TYPESET INT = BYTE + LONG + ULONG + SHORT + USHORT + INT64 + UINT64
TYPESET NUM = INT + DECIMAL + PDECIMAL + REAL + SREAL + BFLOAT4 + BFLOAT8 + SIGNED + UNSIGNED
TYPESET STR = STRING + CSTRING + PSTRING

METAVARS
n    NUM                        ! matches one identifier declared as ANY numeric type

n = 0  ==>  clear(n)
```

A member may be a scalar type keyword or an **earlier set** (`NUM` includes everything in `INT`) - sets
are flattened when parsed, and must be declared before use. A set only ever matches a *resolved*
identifier: an undeclared name still refuses, exactly like any other typed metavar. Unknown member
words are kept but warned about (typo guard), so future Clarion types can be added freely.

Two ordering and length rules, both **errors** rather than silent surprises: a metavar
(or ASSUME) name or type longer than **50 characters** is refused, never truncated; and a
metavar must be declared **above** the first rule that uses it - names resolve in file
order, so a use above its `METAVARS` line would load as a literal, and the loader says so
instead of letting the rule quietly never match.

## D.2 Rule options

Options trail the replacement, in any order:

| Option | Meaning |
|---|---|
| `WHERE <cond>` | The rule fires only if the condition holds (guards below). Several conditions can be ANDed: `WHERE len(lit) = 1 and lit <> ''`. |
| `NOTE('text')` | Appends `! text` as a trailing comment **on the rewritten source line** - an in-code annotation, not just a log entry. The text may name a metavar, so `NOTE(lit)` writes out whatever `lit` matched, and segments join with `&`: `NOTE('was ' & lit)`. Wrap a metavar in `charname()` to print an unprintable character by name - `NOTE(charname(lit))` writes `! <line feed>` rather than `! '<10>'`, and a character with no special name still prints itself. If the rewritten line ends in a `|` continuation the note goes after the bar, where Clarion already ignores it. |
| `EXPREND` | Refuse the match unless it **ends its operand** - i.e. the next token is not `& + - * / ^ %`. Use it on any rule whose pattern could match a prefix of a longer expression: without it, `... = UPPER(clip(w)) & '_X'` would match the `UPPER(clip(w))` part and drop a `clip()` that was doing real work on the concatenation. |
| `INPARENS` | Refuse the match unless it **starts inside an unclosed bracket** of its own statement. What that proves: an `=` at bracket depth > 0 is a COMPARISON, never an assignment - an assignment target closes every bracket it opens before its `=`, so anything deeper is a call argument, a subscript expression or a parenthesised condition, and Clarion has no assignment expression to put there. It is what lets `w1 = clip(w)` be dropped inside `choose(...)` while the same text as a whole statement is left alone. Pairs naturally with `EXPREND`. |
| `ONCE` | Fire at most once **per file**. |
| `SKIP` | Disable the rule but keep it in the file. |

Two **replacement keywords** stand in place of the whole replacement:

| Keyword | Meaning |
|---|---|
| `DELETE` | Delete the matched statement. The leading indent and any trailing comment survive. |
| `COMMENT` | Comment the statement out instead of deleting it, keeping the original text and appending the reason: `! st.crop()  ! crop() with no arguments is a no-op - removed`. Pair it with `NOTE('...')` to give that reason; without one you get `removed by rule <id>`. |

A file-level `NEEDBUILD <n>` line declares the minimum engine build a rule file needs
(e.g. `NEEDBUILD 85`). Older engines do not know the word, so they refuse to load the
file rather than misinterpret a newer feature. Put it above the rules that need it.

A file-level `DEFAULTSTYLE <name>` line names the style a run with no `--style=` gets -
see *What the StringTheory rule file offers* above. Shipped rule files only; not valid in
a `--userrules=` file.

**A rule pattern cannot begin with a dotted metavar.** `st._DataEnd` and `st.valuePtr`
merge into single tokens, so a pattern whose only occurrences of `st` are dotted has
nothing to bind the head to, and the loader refuses it:

```
ERROR dotted metavar st._DataEnd needs st bound earlier in the pattern
```

`return st.getValue()` is fine because the tokenizer splits before a `(`, which binds `st`
plainly. This is why the `getvalue-form` axis has no reverse member - the inverse rule is
not expressible, not merely unwritten.

**A replacement cannot end with one of the option words.** `WHERE`, `NOTE`, `ONCE`, `SKIP`,
`EXPREND` and `INPARENS` are ordinary identifiers, and they are read as options wherever they appear at
bracket depth 0 - so a replacement whose tail is one of them, such as `x = skip`, would have
the `skip` taken as the SKIP option and the replacement would truncate to `x =`. An operator
in front of the word proves it was meant as a value, and the loader refuses it instead:

```
ERROR rule option SKIP sits where an OPERAND belongs - the replacement would silently
truncate to "x =". The option words are read as options wherever they appear at bracket
depth 0, so rename the identifier: ...
```

Rename the variable, and the rule says what it looks like it says.

A `|` continues a long rule onto the next line.
`ASSUME <name-pattern> <Type>` gives a fallback type for names your declarations don't cover - handy for
naming conventions, e.g. `ASSUME st* StringTheory` treats any name starting with `st` as a StringTheory
when nothing else says otherwise.

**Replacement helpers** (evaluated when the rule fires):

| Helper | Meaning |
|---|---|
| `trimr(lit)` | The matched literal with its trailing spaces removed: if `lit` matched `'abc  '`, `trimr(lit)` writes `'abc'`. **Replacement only** - it edits the literal's real bytes, which matter at runtime. In a `WHERE` you never need it: the guard compare already ignores trailing spaces. |
| `fold(expr)` | Constant-fold arithmetic: if `w` matched `5`, `fold(w-1)` writes `4`; if it can't fully fold, the expression is written as-is. |
| `len(lit)` | The literal's character count, written as a number: `'ab'` -> `2`. Escape-aware, so `'<13>'` is 1. |
| `val(lit)` | The byte value of a **one-character** literal: `'='` -> `61`, `'<9>'` -> `9`, `''''` -> `39`. Anything longer keeps the `val(...)` spelling, which is valid Clarion meaning the same thing. |
| `chr(nn)` | The inverse: the literal **source text** for a byte value, `61` -> `'='`, `9` -> `'<9>'`. Note this writes a literal into your source; it does not emit a runtime `chr()` call. |

**WHERE guards:**

| Guard | Meaning |
|---|---|
| `WHERE <mv> = 'x'` / `<> 'x'` | Compare the matched text (case-insensitive unless quoted as a literal). The compare is Clarion's own, so **trailing spaces are ignored** - `= 'x'` also matches `'x  '`, and an all-space literal equals `''` (which is exactly what makes `WHERE lit <> ''` a blank guard). Use `len()` when exactness matters. `fold()` works here too. |
| `WHERE len(lit) = 1` | Logical character count of a matched **literal** - `'<13>'` counts as 1, `''''` as 1, `'<13,10>'` as 2. **`len()` only knows the length of a literal.** Against a binding that is not one - a variable, or any expression - there is no length to measure, so `len(x) = 1` cannot pass and `len(x) <> 1` passes for everything. Guard on a LITERAL metavar if you mean to test a length. |
| `WHERE isConst(w)` / `isLiteral(w)` / `isVar(w)` | The match folds to an integer / is a single quoted literal / is one identifier that resolves in the symbol table. `isConst` refuses a written negative, so it doubles as "a provably non-negative constant". |
| `WHERE isPure(w)` | The match contains no `(` and no `{` **anywhere**. Read that literally: it refuses `y + (3 * z)`, which calls nothing, purely because of the grouping brackets. If what you need is "safe to evaluate twice", `isCallFree` is the test you want; `isPure` is the blunter one |
| `WHERE isCallFree(w)` | The match **calls nothing**, so a replacement may evaluate it a different number of times than the pattern did. Grouping brackets are fine - `y + (3 * z)` passes, `f(x)` and `self.M(x)` do not. A `(` counts as a call when the token before it ends in a name character; one after an operator, after a comma, or opening the match is grouping. `{` is refused as well, because a property expression may itself be a method call on an OLE or OCX control and nothing in the syntax says which it is |
| `WHERE isSimple(w)` | The match has no top-level logical operator (`AND`/`OR`/`XOR`/`NOT`/`~`), so its comparator is the root of the condition - the guard that makes it safe to flip a test around. |
| `WHERE isBoolExpr(w)` | The exact opposite of `isSimple`: the match **does** have a top-level `AND`/`OR`/`XOR`/`NOT`/`~`, so the match is a *logical* expression and its value is already 1 or 0. Those four operators are the only ones of lower precedence than a comparator, so a top-level one is the root. Use it where a rewrite is only sound on a condition - `choose(a or b, 1, 0)` -> `choose(a or b)` is safe, while the same collapse on a bare or arithmetic operand would hit `CHOOSE`'s *other* form, which indexes the value list. |
| `WHERE isCaseNeutral(w)` | `upper(match) = lower(match)` - true only when the match holds no letter, so neither case fold can change it. Used to hoist a repeated fold out of a concatenation: `upper(a) & '::' & upper(b)` -> `upper(a & '::' & b)` is safe because `'::'` cannot change when it comes inside the `upper()`. |

**Multi-statement patterns:** a `;` *inside a pattern* matches a statement boundary (so
`st.prepend(w) ; st.append(w1) ==> st.Enclose(w,w1)` collapses a two-statement pair), and a *trailing* `;`
asserts "end of statement" without consuming it. In a replacement, `;` just separates the statements it
writes out.

## D.3 A few things worth knowing

- **`&StringTheory` counts as `StringTheory`.** Derived classes aren't matched. `CSTRING` is not `STRING`.
- **A BARE `SELF` receiver is excluded from typed rules.** A rule on `st.method(...)` will not fire
  on `self.method(...)` - deliberate caution, since what `SELF` is depends on context the matcher
  can't always prove. If a rule seems to "miss" those call sites, that's why.
- **A receiver reached THROUGH `SELF` is a different case, and it can fire.** `self.buffer.method(...)`
  is not a bare `SELF`: the tool works out what `buffer` was declared as and, if that resolves to
  the metavar's type, the rule fires normally. Only the head of the chain is `SELF`, and resolving
  it is what the class the rule sits in is for. When the declaration lives in an include, `--thorough`
  is what makes it resolvable - see [B.3](#b3-thorough-mode-cross-file-type-resolution). If it resolves to nothing, the match
  is skipped, exactly as the next bullet describes.
- **An unresolvable receiver refuses, it doesn't guess - IN A RULE.** If a typed rule's receiver
  can't be found in the symbol table, the match is skipped (use `ASSUME`, `--thorough`, or
  `--loose` to widen).
- **Two procedures may declare the same local, and the tool works out which one you mean.** If
  `PA` and `PB` each declare their own `Line` queue - one holding text, the other numbers - a rule
  on `Line.value` is answered separately in each, from what the code *at that spot* can see: the
  routine first, then the procedure around it, then the file's own module-level declarations. If
  none of those declares the name, there is no single answer and your code is left alone.
- **That last step is the one place VitTransform assumes your source would compile.** Reaching for
  a module-level declaration because nothing nearer declares the name is only sound in a legal
  program. It is allowed because it can only make the tool *resolve* something it would otherwise
  have left alone - never resolve it differently - so on a fragment, a half-written file or a file
  mid-edit the step finds nothing and the refusal stands. Nothing else it decides is assumed: the
  rest is read straight off the source in front of it.
- **The BUILT-IN transforms find their work by METHOD NAME**, not through a typed metavar.
  `CheckReplaces`, `CheckRemoves`, `CheckSplits`, `CheckInLine` and `CheckCat` look for
  `.replace(`, `.remove(`, `.cat(` and so on. If your own class has a method of the same name,
  they can point at it. **`--receiver=` decides what happens then** - see below.
- **Comments inside a match are protected** - rather than risk dropping a comment, VitTransform skips that
  match and logs it (the report's `comment-skip` count).
- **A `width-skip` is not a skipped rewrite.** Despite the name, the conversion *did* happen. It counts a
  rewrite whose result would not fit the width limit with the original line continuations carried into it,
  so the replacement was built **flat** and the line left long - `SplitWideLines` breaks it up afterwards.
  Taking the wide line is the better trade: a long line that gets tidied afterwards beats a conversion that
  never happened. So a report reading `4 width-skip(s)` means four
  rewrites were applied the flat way, not four that were declined.
- **If a file will not settle, the report says so.** VitTransform re-runs the rules until a pass changes
  nothing. If it hits the `--passes=` cap first it writes
  `WARNING <file> did not converge after <n> passes` and gives you the state it had reached. That almost
  always means two rules are undoing each other - the log shows which lines keep moving.
- **Your capitalisation survives a rewrite.** A word a rule spells out, which your source also spells, is
  written back the way *you* wrote it: a rule that removes a `clip()` from `UPPER(CLIP(x))` gives you back
  `UPPER(x)`, not `upper(x)`. A word the rule *introduces* - a renamed method, an equate - is not in your
  source, so it appears as the rule spells it, which is how a rename to a canonical spelling still works.
  Restyling keywords is `KeywordCase`'s job, and it is opt-in.
- **Built-in transforms** (the analyses and the formatting tools above) are switched on with a
  `BUILTIN <Name>` line in the rule file, e.g. `BUILTIN Reindent, WIDTH(2), CASEOF('indent')`.

## D.4 `--receiver=` - when the tool cannot tell what an object is

**Short version: leave it alone.** The default is the safe-and-useful setting. This section is
here for the day it refuses something you expected it to convert.

Five built-in transforms rewrite StringTheory calls by looking for the **method name**:

```clarion
st.replace('a','')      ->   st.removeByte(97)      ! remove all 'a'
st.cat('xyz')           ->   st.Append('xyz')
```

To do that safely they need to know that `st` really is a StringTheory. Usually they can: it is
declared in the file, and the answer is yes or no. Sometimes they cannot - the object is
`self.something`, or it is declared in an include that was not expanded. On a large real-world
corpus that is about **40% of such call sites**.

`--receiver=` is what happens in that case:

| mode | an object the tool cannot identify is... |
|---|---|
| `assume` | **rewritten as a StringTheory.** Fastest, most rewrites, and wrong if it was not one. |
| `check` | **checked before rewriting.** DEFAULT. |
| `strict` | **left alone** unless the tool can prove what it is. |

**What `check` does.** It looks at every other use of that same object nearby. If it sees a
method StringTheory does not have, it concludes the object is something else and leaves it
alone:

```clarion
ssc.FromFile('x.txt')    ! StringTheory has no FromFile - so ssc is not one
ssc.replace('a','')      ! ... and this is left alone
```

On the corpus that catches about two in three of the objects that are not StringTheorys. It
cannot catch them all: a class whose methods are *all* also StringTheory methods looks exactly
like one from the outside.

**`check` only leaves an object alone when it has actually seen a method StringTheory does not
have.** The list it checks against is StringTheory's own, so a method it does not recognise -
including one from a newer StringTheory than the list knows, or one your own class adds on top
of StringTheory - reads as a reason to leave that object alone. If a conversion you expected did
not happen, that is the first thing to look at.

**When to use `strict`.** If you have your own string-like classes and you want certainty rather
than a good guess. Pair it with `--thorough`, which expands includes so that most objects become
identifiable - `strict` on its own will refuse a great deal, because it refuses everything it
cannot prove.

```
VitTransform vitrules.txt src\*.clw out --receiver=strict --thorough
```

**When to use `assume`.** If you know no other object type in the run has method names that clash
with StringTheory's. That is the condition that actually matters, because these transforms match
on the METHOD NAME: a class of your own with its own `replace` or `cat` is what `assume` will
rewrite by StringTheory's prototype. It skips the identification question entirely, so it is the
fastest setting and the one that converts the most.

---

# Appendix E: Reading the comments in the source

You only need this appendix if you are reading or changing VitTransform's own code.

## The five phases, which is what the source headers mean

Each class header names a phase - `VitEngine - Phase 5 of VitTransform`. That is the pipeline,
in the order a file passes through it:

| | | |
|---|---|---|
| **Phase 1** | `VitRules` | reads the rule file: metavars, rules, groups, choices, styles, and the resolver that decides what is switched on |
| **Phase 2** | `VitMatch` | finds where a rule matches, binds its metavars and evaluates `WHERE` guards |
| **Phase 3** | `VitRewrite` | splices the replacement into the token stream |
| **Phase 4** | `VitSymbols` | the symbol and type registry the typed rules ask about |
| **Phase 5** | `VitEngine` | drives it: parse, build symbols, run rules and builtins to a fixpoint, write output |

`vitTransform.clw` is the command-line program over the top of all five, and `VitStyle.clw` is
the visual one. Three more classes sit underneath without a phase number: `vitTokenize` (the
tokenizer and the token-stream primitives everything splices through), `Preprocessor`
(`INCLUDE` expansion for `--thorough`), and `vitTimer` (elapsed-time measurement - the
`seconds` figure in every report line).

Those five are the only phase numbers anywhere in the source, and there is no sixth class.

The comments in the source are the design record. They are unusually long in places, and
that is deliberate: they carry **why** a thing is the way it is, which is the part that
cannot be recovered by reading the code. Where a comment explains a decision at length,
that length is the point - please don't compress it.

One label appears in the comments and is worth knowing:

| Label | What it marks |
|---|---|
| `S1` - `S4` in `VitEngine.clw` | the four passes of the `KnownRanges` value walk, named after the routines that run them (`KrTryS1` .. `KrTryS4`). A comment saying "S3 runs only when S2 changed nothing" is naming those routines, not a document |

Every transform report opens with the version and build number of the program that wrote it -
`VitTransform 1.0.3 (build 255)` is the shape of it - and nothing else. That tells you which copy of
VitTransform produced the report in front of you, which is worth knowing if you have more than one
to hand.

Three conventions worth knowing before you edit anything:

- **An apostrophe inside a Clarion literal terminates it.** Double it. This has broken the
  build three separate times, and the failure is confusing because the compile error lands
  nowhere near the apostrophe.
- **Source is CRLF and ASCII only.** A scripted comment edit that eats line terminators
  welds a comment onto the code line below it. Comparing the line count before and after is
  the cheapest way to catch that, and it has caught it.
- **One storage location has several spellings.** This one has produced five separate bugs
  in five different places, in code written by people who knew about it. It has a section
  of its own, below.

## One storage, several spellings

**If you are adding a builtin, read this before you compare a name to anything.**

A transform that moves, merges or removes a statement has to answer one question: *does this
statement touch the same storage as that one?* The tempting way to answer it is to compare the
names. In Clarion that is wrong, because the same bytes can be written several ways:

| written | also written | why |
|---|---|---|
| `grp` | `grp.x` | a GROUP appears in an expression as a string over its members, so writing the group writes the member |
| `q.g` | `q:g` | a colon may replace a period for any structure except CLASS and named reference variables (LRM, *Field Qualification*) |
| `pq:field` | `pq.field` | the `PRE` attribute - a *different* mechanism from the one above, sharing the same character |
| `grp:x.m` | `grp.x.m` | the two separators mix freely in one name |
| a name | its `OVER` alias | two labels, one address - and see below, because this one is different |

The tokenizer merges a qualified name into a **single token**, so `grp` and `grp.x` are not
"one token that contains another" - they are two unequal strings. A whole-token compare for
`grp` therefore never matches `grp.x`, and a guard written to stop a dangerous rewrite silently
lets it through.

**What it looks like when it goes wrong.** Every instance so far has been silent, and the
symptom is always that a write ends up on the wrong side of a read:

```clarion
if grp.x = 2                 grp = 1          ! hoisted ABOVE the condition
  grp = 1        becomes     if grp.x = 2
  f = 1                        f = 1
else                         else
  grp = 1                      f = 2
  f = 2                      end
end
```

With `grp.x = 2` on entry the original takes the THEN arm and the rewritten code takes the ELSE
arm. Nothing warns; the file still compiles.

**The fix, every time, is to compare ROOTS.** `VitEngine.NameRoot` does it: upper-case the name
and cut it at whichever of `.` or `:` comes **first**. Cutting at the dot in preference to the
colon is not good enough - `grp:x.m` roots at `GRP:X`, which is not the storage, and that was a
bug of its own.

Comparing roots over-refuses: two genuinely independent members of one structure (`pq:a` against
`pq:b`) will read as a clash and the rewrite will be declined. **That is the correct direction to
be wrong in.** A refusal costs one transformation; a wrong merge costs the user's code.

**`OVER` is the one you cannot see coming.** Every other spelling above resembles the name it
shares storage with, so a root cut finds it. An `OVER` alias does not:

```clarion
p    LONG
sh   SHORT,OVER(p)      ! two labels, one address - `sh` and `p` share no letters
```

Writing `sh` writes `p`. No amount of comparing the two names will tell you that, because the
relationship is in a third place - the declaration. The only way to answer it is to ask the
symbol table, which is what `VitEngine.HasSiblingOver` does: walk the other declarations in the
same scope and see whether any is `OVER` this one. Checking whether the variable is ITSELF an
alias is not the same question and does not answer it - that was the fifth bug.

**Not every name compare is a storage question.** The engine deliberately has two different
cuts, and they are not interchangeable:

- Over an **arbitrary** name - a hoist guard, a usage credit - the cut must take whichever of
  `.` or `:` comes first, because any spelling can turn up.
- Over a **receiver already proved** to be a bare local StringTheory or a bare scalar, a
  dot-only cut is correct: no colon spelling of that storage exists, so the wider cut would
  only add refusals. `KrSplitRoot`, `TsSplitRoot`, `SmSplitRoot` and `DgLastDot` are all in
  this second family, on purpose.

So the question to ask is not "does this compare names" but "what has this already proved
about the thing it is comparing".

**If you are auditing for this**, the tells are `instring('.'`, `findByte(46)`, `findByte(58)`,
any `upper()` compare of two token strings, and any check that reads a declaration's own
attributes without looking at its neighbours. Ask of each one whether it is deciding a
*spelling* question or a *storage* question. If it is storage, it wants `NameRoot` on both
sides - and, if a write is at stake, `HasSiblingOver` as well.

---

# Appendix F: FAQ

Quick answers, each with a pointer to the section that tells the whole story. It sits at the
back with the other reference material, but it is linked from the top of the Contents as well,
because for most people it is the fastest way in - real questions, answered in the order they
tend to come up.

**I like my keywords - IF THEN ELSE END LOOP - in uppercase, but this code has them
lowercase. How do I fix that?**

```
VitTransform cosmetic.txt src\*.clw out
```

`cosmetic.txt`'s default style (`tidy`) upper-cases keywords - and also re-indents to
2 spaces and puts `;`-joined statements on their own lines, because that is its idea of
tidy. If you want the keywords fixed and *nothing* else:

```
VitTransform cosmetic.txt src\*.clw out --nogroup=cosmetic-reindent-2 --nogroup=cosmetic-splitstatements
```

Your own names - `MyProc`, `Total` - are never touched; only keywords, data types,
Clarion's functions and declaration attributes change case. (The same groups exist in
`vitrules.txt`, so `--group=cosmetic-keywordcase-upper` fixes keywords in the same run
that modernises the code.) See *Tidy up layout*.

**And if I want lowercase, or Title case?**

Pick that member of the axis instead:

```
--group=cosmetic-keywordcase-lower       if x then y.
--group=cosmetic-keywordcase-title       If x Then y.
```

The three are a *choice* - selecting one deselects the others, so two can never fight.

**This code has 2-character indents and I want 4. What do I run?**

```
VitTransform cosmetic.txt src\*.clw out --group=cosmetic-reindent-4
```

Selecting `-4` automatically deselects the default `-2` (same choice axis). Reindent
never moves a column-1 label, so declarations and data structures stay exactly where
they are - only executable nesting changes.

**And 3 characters? Or something else?**

`--group=cosmetic-reindent-3`. The shipped widths are 2, 3 and 4; for any other, edit
the rule file's `BUILTIN Reindent, WIDTH(2)` line to the width you want - it is plain
text. `CODECOL(n)` on the same line also re-bases each procedure body to column `n`.

**What are my options for lining up / indenting CASE statements?**

Two separate things:

- **Where `OF` sits.** The default is *flush* - `OF` level with its `CASE`. For one
  step in, add `CASEOF('indent')` to the `BUILTIN Reindent` line:
  `BUILTIN Reindent, WIDTH(2), CASEOF('indent')`.
- **Label columns.** `OF`/`OROF` labels near each other are lined up in columns
  automatically (it is part of comment alignment, on by default). It only touches runs
  that contain an `OROF`, never widens a block by more than 20 characters, and
  `--nogroup=cosmetic-aligncomments` switches it off.

**I use StringTheory a lot - what gives me the fastest code?**

Ask for it. A plain run deliberately does **not** make the three changes that buy speed;
`--style=optimised` is the one that does: byte-wise searches (`st.findChar('=')` ->
`st.findByte(61)`), direct buffer compares, and the slice return form. A plain run already
gives you the cleanups that cost nothing in readability, including absorbing a redundant
`clip()` into the call's own flag. Three steps further:

```
VitTransform vitrules.txt src\*.clw out --style=optimised   ! the three changes that buy speed, and nothing that comments code out
VitTransform vitrules.txt src\*.clw out --style=extreme     ! everything below in one word, plus the slice everywhere
VitTransform vitrules.txt src\*.clw out --group=analysis    ! deeper: redundant-clip retirement, provably-dead guard removal
VitTransform vitrules.txt src\*.clw out --thorough          ! resolve types across INCLUDEs, so more typed rules fire
```

`--style=extreme` is every group that changes what your code does: `optimised`, plus
`st-getvalue-slice-all` (**every** `st.getValue()` becomes the direct slice, not only the ones
in a `return` or a comparison), plus `analysis`, `deadchoose` - the pair that tidies up after
that very rewrite, retiring the emitted `choose()` guard where an earlier guard already made it
decidable, and the `left()` left with nothing to strip - plus `deadcode` and
`general-compound-assign`. Two
things to know before you reach for it. It **comments dead code out** as well as rewriting -
that is `deadcode`, and it is in there on purpose - and it is much the biggest diff the tool
produces, so `--dry-run` and actually reading it is not optional here. It leaves layout alone,
whichever style you pick, and `--thorough` combines with any of them.

**Some of that optimised ST code looks cryptic to me. How do I get more readable code,
even if it runs a little slower?**

If you did not ask for it, you will not get it! Life is full of compromises and often if you want faster,
optimised code, you might end up sacrificing some clarity.  The default style is `plain`, and it never
rewrites working code just to make it run faster. **The transformations that would are simply
switched off** - so on a normal run there is no "lessening of clarity". These optimisations run
only when you ask for them with `--style=optimised` or `--style=extreme`, and they are the ones
that turn a `getValue()` comparison into `choose(st._DataEnd < 1, ...)`, or `findChar('=')`
into `findByte(61)`.

So the answer depends on where the code came from.

**You ran `--style=optimised` and want it back:** drop the switch and re-run over the
**original** source. A plain run leaves that code as it stands rather than putting it back, so
re-running over the *output* will not undo anything.

**You want the longer, plainer form, further than the default goes:**

```
VitTransform vitrules.txt src\*.clw out --style=readable
```

That is what `readable` is for: the longer, more explicit form - `if s = ''` rather than
`if ~s`, `findChar('=')` rather than `findByte(61)`. Run it over already-optimised code
and the ones that have an opposite convert back (they are derived from the same rules, so the
two directions cannot drift apart - that holds for the pairs built with REVERSE, though a hand-written opposite like `st-findchar` can still drift); a compact form with no safe inverse - the slice
return, the direct buffer compare - is left alone rather than guessed at.

**I ran `--style=optimised` and my `st.getValue()` comparisons came back as a `choose(...)`.
Can I keep the rest of `optimised` and drop just that one?**

Yes. That one is the **`fastcompare`** axis, and there are three answers in ascending
permanence:

```
VitTransform vitrules.txt src\*.clw out --style=optimised --nogroup=fastcompare-on   ! this run, that axis only
VitTransform vitrules.txt src\*.clw out --style=readable                             ! this run, the whole explicit side
```

- **Just this run, just that transformation:** `--style=optimised --nogroup=fastcompare-on`.
  Everything else `optimised` does - `findByte(61)`, the slice return - carries on as normal.
- **Just this run, the longer form everywhere:** `--style=readable`. Wider than you asked for:
  it also restores `findChar('=')`, and `if s = ''` over `if ~s`. Use it when the whole compact
  look is what you object to, not one rule.
- **Permanently, no switch:** edit the **one** `DEFAULTSTYLE` line near the end of
  `vitrules.txt` - it ships as `DEFAULTSTYLE plain`, and `DEFAULTSTYLE readable` makes every
  switch-free run readable from then on. To keep asking for `optimised` but drop **only**
  `fastcompare` from it, change the word `fastcompare-on` to `fastcompare-off` on the
  `STYLE optimised` line instead.

**One trap worth knowing, because it looks like it should work and does not:** moving the
`DEFAULT` marker between `GROUP fastcompare-on` and `GROUP fastcompare-off` changes nothing
while a `DEFAULTSTYLE` line names a style that pins that axis. A style is applied **over** the
per-axis `DEFAULT` markers, so the style wins and the marker is ignored. Change the style, not
the marker.

Whichever permanent edit you choose, put it in **your own copy** of the rule file and pass that
copy's name - see the next-but-one question. And if you would rather not edit anything, the
other durable answer is a one-line `.bat` holding the command with its switches, which is worth
having anyway so that everyone building the app transforms it the same way.

**I don't like one particular transformation (or a few of them) but want all the
others. How do I exclude some - for this run, or permanently?**

- **This run, one rule:** find its id in the report (a rule's id is its line number in
  the rule file) and pass `--skip=<id>`. One id per run.
- **This run, a whole group:** `--nogroup=<name>` - the report's selection table lists
  every group that was on.
- **Permanently:** the rule file is plain text. Add ` SKIP` to the end of the rule's
  line (it stays in the file, disabled), or delete the line. For a builtin, comment out
  its `BUILTIN` line. Keep your changes in a copy, or better in a `--userrules=` file,
  so a new release of the shipped file does not overwrite them.

**If I make a lot of changes to `vitrules.txt`, will the next release wipe them? Is there
anything better than keeping a backup and merging by hand?**

Yes - and the answer is mostly *don't edit the shipped file at all*. `vitrules.txt` is the
one file a new version is certain to replace, and there is a purpose-built place for each
kind of change you might want:

| What you want to keep | Where it belongs | What an upgrade does to it |
|---|---|---|
| Rules of your own | a `--userrules=<file>` file - loaded **on top of** `vitrules.txt`, not instead of it | nothing, it is your file |
| A saved on/off selection | a profile: **Save profile...** in VitStyle writes `VitStyle.profiles.txt`, replayed with `--stylefile=... --style=<yourname>` | nothing, it is your file |
| A switch you always pass | a `.bat` holding the whole command line | nothing, it is your file |
| Disabling a shipped rule for one run | `--skip=<id>` / `--nogroup=<name>` on the command line | nothing to lose |

Your user rules file **inherits** the shipped metavars and typesets, so you write rules the
same way you would in `vitrules.txt`. Groups you declare in it arrive **off** - select them
with `--group=` - so having the file on disk can never change a run on its own. `STYLE`,
`DEFAULTSTYLE`, `THOROUGH` and `LASTUSED` are refused there, deliberately: a user file is *appended* to the
shipped one, and a `DEFAULTSTYLE` in it could silently re-select every axis in a file it does
not own. That is the only thing you cannot move out, which is why the previous question tells
you to make that one edit in a **copy**.

Two things genuinely do need the shipped file edited: disabling a *shipped* rule permanently
(` SKIP` on its line), and changing `DEFAULTSTYLE`. If you are doing either, do this:

1. Work in a copy - `myrules.txt` - and pass that name. `<rulefile>` is just the first
   argument, so nothing requires the shipped name.
2. Keep the **pristine** shipped file you started from beside it, e.g. `vitrules-orig.txt`.
3. On upgrade, diff **orig against new** - not yours against theirs. That diff is small and is
   what the release notes describe, and you apply it to your copy. It is the difference between
   reading a handful of changed lines and re-reading the whole 1,977-line file.

One caution while you are in there: **a rule's id is its line number**, so inserting or
deleting lines renumbers every rule below the edit. Any `--skip=`/`--only=` id in your `.bat`
files, or written in your notes, is about the file it was read from - re-check them after an
edit, and prefer `--nogroup=<name>` where a group exists, because a name does not move.

**I saw something about Groups, Styles and Choices - explain them simply?**

- A **group** is a named bundle of rules with an on/off switch: `--group=x` on,
  `--nogroup=x` off.
- A **choice** is a set of groups where at most one can be on - radio buttons. Picking
  one un-picks the rest, which is why you never say "and turn the old width off".
- A **style** is a named combination of picks that ships in the rule file:
  `--style=readable`. A **profile** is the same thing saved by you - VitStyle writes
  it, and `--stylefile=` loads it.

The full story, including how the report proves what was on: *Choosing what runs*.

**Where do I look if I want to write my own rules?**

Start at [Writing rules](#writing-rules) - one worked rule, end to end - then
[Your own rules, step by step](#your-own-rules-step-by-step) for where your file goes
and how to switch it on. [Appendix D](#appendix-d-rule-file-reference) is the
reference. The easiest road is VitStyle's **Workbench** button: type the rule, **Lint**
checks it, **Test** shows exactly what it fires on - all before you save anything.

**How do I check for and comment out unused code - routines nothing `DO`es, unreachable
statements, dead assignments and the like?**

```
VitTransform vitrules.txt src\*.clw out --group=deadcode --dry-run
```

Read the report, then run it again without `--dry-run` when you are happy. The group turns on
four analyses, and **every one of them comments code out with a `!` rather than deleting it**,
so nothing is lost and a diff shows you exactly what it believes:

- **UnusedRoutines** - a `ROUTINE` that nothing ever `DO`es.
- **UnreachableCode** - statements that can never run, such as code after an unconditional
  `RETURN`.
- **UnusedAssignments** - a value written to a variable and then overwritten before anything
  reads it (a "dead store").
- **HoistCommonBranchCode** - not a dead-code check at all; see the next question.

Unused *variables* need no switch: `UnusedVars` is on by default and marks a declaration it
believes unused with `! #Removed as not used:`.

Two cautions. The group is **off by default** because these are the most opinionated things in
the file, so read the report rather than accepting the diff blind. And on a `.txa` template
export they are deliberately restricted, because the code the template generates is not in the
file you are looking at: `UnusedRoutines` only annotates, `UnreachableCode` stops at an embed
boundary, and the scope-based analyses run only where a procedure sits wholly inside one
embed. See *Find problems and flag them* and *Template exports (`.txa`)*.

**What is hoisting common branch code, and how do I turn it on?**

```
VitTransform vitrules.txt src\*.clw out --group=deadcode
```

It takes a statement that is identical at the end of **both** branches of an `IF ... ELSE ...
END` and moves it out to after the `END`, where it runs either way:

```
! before                            ! after
if Ok                               if Ok
  Total += 1                          Total += 1
  Close(File)                       else
else                                  Log('failed')
  Log('failed')                     end
  Close(File)                       Close(File)
end
```

It travels in the `deadcode` group because it is the same kind of opinionated tidy-up, but it
deletes nothing: it relocates the exact tokens and re-indents the moved line.

It refuses far more than it accepts, on purpose - a wrong *move* corrupts code silently, where
a wrong comment-out is merely visible. It wants a clean `IF / ELSE / END` (never an `ELSIF`,
never a one-liner), and the two statements must be a single physical line each,
token-for-token identical, and sitting immediately against the `ELSE` and the `END`. Comments
on the two lines must **match**: a hoist keeps one copy and drops the other, so two different
comments would lose one - but when both say the same thing the dropped copy is redundant, and
the survivor travels with the hoisted line. The match is on the words, not the layout, so the
column, tabs, and runs of spaces are all free to differ. A comment on one side only still
refuses. Both ends are handled: the trailing form shown above is tried first because it is
unconditionally safe, and the leading form (common code at the *start* of both branches) is
tried after it.

If you expected a hoist and did not get one, **check whether the comments on those two lines
differ**, and whether one side has one at all - it is much the commonest reason after `ELSIF`,
and the report says what it declined.

**Will it break my code?**

Its guiding rule is refusal: if it cannot prove a change is safe, it does nothing, and
the report says what it declined and why. The analyses comment code out - they never
delete it. Typed rules refuse a receiver they cannot resolve. And your originals are
untouched unless you explicitly pass `--in-place`, which writes a timestamped `.bak`
first. Even so: `--dry-run`, then an `<outdir>`, then diff, before you trust any tool
with your source - including this one.

**How do I see what it would do before it touches anything?**

`--dry-run`. Nothing is written; the report lists every change it *would* make as
`rule <id> line <n>: <before> ==> <after>`.

**I ran it and almost nothing changed. Why?**

Usually the type gate: rules on StringTheory receivers refuse when the declaration is
not visible in the file being transformed - declarations in `.inc` files are invisible
by default. Add `--thorough` and watch the number climb. If it is still quiet, check
the report's selection table: the group you expected may simply be off.

**You do not have to guess, either.** When a typed rule refuses because it could not
resolve what it was looking at, the report says so once per file, and names them:

```
MyThing.clw: 963 typed match(es) refused on 20 receiver(s) - declaration not visible:
SELF.PPDEFINES, SELF.PROJDIR, SELF.ERRTEXT and 17 more - if any of these are declared
in an INCLUDE, try --thorough
```

If that line is absent, `--thorough` has nothing to add on that file.

**How is `--thorough` different from `--style=extreme`? Can I use both, or do they conflict?**

They are different axes and combine freely - `--style=extreme --thorough` is a normal thing
to type.

* **`--style=` decides WHAT gets rewritten** - which groups of rules are switched on. It is a
  policy choice, and it is the same policy on any machine.
* **`--thorough` decides HOW MUCH THE TOOL KNOWS** - it expands your `INCLUDE`s so the type
  registry can see classes that are declared in `.inc` files. It changes no policy at all; it
  lets the rules you already chose apply in more places.

The practical difference: `extreme` makes the tool try more *kinds* of change, `--thorough`
makes the changes it already tries succeed on more *receivers*.

**Is there any reason not to use `--thorough` all the time?**

Mostly no - and on a typical application it is the single biggest lever you have. Measured on
one 16,000-line NetTalk source, where the classes all live in `.inc` files:

| | changes | time |
|---|---|---|
| without `--thorough` | 1346 | 59.2 s |
| with `--thorough` | **1489** | 61.7 s |

About 4% slower for 10% more transformations. On code that declares its own classes the gap
is much smaller - VitTransform's own sources gain 4 changes in 203 for the same 4% - so how
much it buys depends entirely on where your declarations live. The report line above tells
you which case you are in.

Three real reasons to leave it off:

1. **It needs your Clarion installation.** It reads the `.RED` to find `INCLUDE`s, so it looks
   for the install (registry first, then probing) or takes `--root=<dir>`. On a machine
   without Clarion, or in a build server, it has nothing to expand.
2. **Declarations are read ONCE, at the start of each file.** A rule set that *rewrites
   declarations* - retypes a field, renames a class - does not mix with `--thorough` in a
   single run, because later rules would still be looking at the old picture.
3. **A bigger diff is a bigger review.** That is the point of it, but if you are working
   through a codebase file by file you may want the smaller diff first.

**Can I default `--thorough` ON so I never have to type it?**

Yes - put a bare `THOROUGH` line in the rule file:

```
DEFAULTSTYLE plain
THOROUGH
```

That is the right place for it when the *rules* are what need expansion, which is the usual
case: a rule set full of typed StringTheory receivers cannot resolve them when the classes
live in `.inc` files. See *`THOROUGH` - when the rules themselves need include expansion* for
the precedence rules; the short version is that it asks and the command line decides, with
`--nothorough` as the explicit no.

If you would rather leave the rule file alone, `--root=<dir>` turns thorough mode on as a
side effect and also settles *which* Clarion is read - useful when more than one is installed.

There is deliberately no "extreme implies thorough" shortcut. `--style=` decides *what* gets
rewritten and is the same policy on any machine; `--thorough` decides *how much the tool
knows* and needs your Clarion installation to do it. An implicit switch with an external
dependency is the kind of thing that works on your machine and fails on someone else's -
which is why turning it on is a line you write, and turning it off is a switch you can always
type.

**Where did the report go?**

Next to the rule file, named `<rulefile> on <yyyymmdd> at <hhmmssth>.report.txt`.
Repeated runs keep separate reports, so open the newest.

**Can I keep my comment columns exactly as I wrote them?**

`--nogroup=cosmetic-aligncomments` turns off comment, `CASE`-label and declaration-type
alignment together, and `--width=0` turns off line splitting. Trailing-space removal
still happens - it can itself be the only change a run makes.

**Does it need Clarion installed to run?**

No, and there is no runtime DLL to keep beside them either: both exes link the Clarion
runtime IN (`<Model>Lib</Model>` in each project), so a single .exe on its own is enough -
copy it anywhere and run it. Only `--thorough` looks for an installation, to expand
`INCLUDE`s. (BUILDING the two exes needs Clarion and StringTheory - see *Install*.)

**Can I run it from a build script?**

Yes: add `--batch` so nothing ever opens a modal box (messages go to `vt-batch.log`),
and test `ERRORLEVEL` - 0 is a clean run, 1 is anything you need to look at.

---

## License

Released under the MIT License - free to use, modify and redistribute, including
commercially, provided the copyright notice is kept. See [LICENSE](LICENSE).

Copyright (c) 2019-2026 Geoffrey C. Robinson.

VitTransform needs [StringTheory](https://www.capesoft.com/accessories/StringTheorySP.htm) to build.
StringTheory is a separate CapeSoft product with its own licence and is not covered by this one.
(Hopefully you already have StringTheory but Geoff reckons it is a "no brainer" purchase from Capesoft if you are yet to buy it.)
