# Issue repro tests
> **Status: FIXED.** Every issue below is fixed on the `fixes` branch -
> the repros now demonstrate the corrected behavior (26/26 checks pass:
> harnesses exit 0, rule-driven runs show refusals/correct rewrites).
> The Status column records the ORIGINAL finding for history. Note the
> `out\` folders and `result.txt` files hold post-fix output.


One folder per GitHub issue on this fork. Two kinds of repro:

**Rule-driven** (run against the shipped VitTransform.exe): `in.clw` +
`rules.txt` + `run.bat`, output written to `out\`.

**Harness** (for library bugs the exes never reach): a small compilable
program + `.cwproj`/`.sln`, with a local `CLARION120.RED` adding the repo
root to the include path (a local red must be named like the version
default in C:\Clarion\<<ver>>\bin). Build it, then `run.bat` executes it;
the harness writes `result.txt` and exits 1 while the bug is present.

All sources are ANSI, CRLF, no BOM. Each `in.clw`/harness header comment
carries the full story: defect, mechanism, expected vs actual.

| Folder | Issue | Kind | Status |
|---|---|---|---|
| `issue01_walkunreachable` | [#1](https://github.com/msarson/VitTransform/issues/1) WalkUnreachable comments out live code | rule-driven | Reproduced |
| `issue02_movetoks` | [#2](https://github.com/msarson/VitTransform/issues/2) MoveToks corrupts backward multi-token moves | harness | Reproduced (exit 1, result.txt) |
| `issue03_checkcase` | [#3](https://github.com/msarson/VitTransform/issues/3) BuiltinCheckCase rewrites unvalidated CASE arms | rule-driven | Reproduced |
| `issue04_optiononly` | [#4](https://github.com/msarson/VitTransform/issues/4) Loader crash on option-only replacement | rule-driven | Reproduced (Debug traps; Release correct by accident) |
| `issue05_commaoption` | [#5](https://github.com/msarson/VitTransform/issues/5) DELETE, ONCE loads as text replacement | rule-driven | Reproduced |
| `issue06_staleanchors` | [#6](https://github.com/msarson/VitTransform/issues/6) Appended rule matches nothing (dead postings rescue) | harness | Reproduced (exit 1, result.txt) |
| `issue08_aligndecl` | [#8](https://github.com/msarson/VitTransform/issues/8) AlignDeclTypes width guard measures fictional widths | rule-driven | Reproduced (44 cols under --width=40) |
| `issue09_omitrevert` | [#9](https://github.com/msarson/VitTransform/issues/9) Stale inContinuation after OMIT revert drops tokens | rule-driven | Reproduced (token dump shows the hole) |
| `issue10_codelabel` | [#10](https://github.com/msarson/VitTransform/issues/10) Column-1 'code' label breaks AutoCheck | rule-driven | Reproduced (valid AUTO stripped) |
| `issue11_argcount` | [#11](https://github.com/msarson/VitTransform/issues/11) Arg counters treat [i,j] commas as separators | harness | Reproduced (counts 2 for 1 arg) |
| `issue12_batchmodal` | [#12](https://github.com/msarson/VitTransform/issues/12) --batch --summary opens a modal box | rule-driven | Reproduced (hangs; watchdog-killed) |
| `issue13_wildcard` | [#13](https://github.com/msarson/VitTransform/issues/13) Wildcard exit-code contract | rule-driven | Partial: zero-match exit 0 confirmed; subfolder case not reproducible on build 253 |
| `issue14_haltzero` | [#14](https://github.com/msarson/VitTransform/issues/14) Bare halt() exits 0 on fatal paths | harness | Reproduced (exit 0) |
| `issue15_implicitvar` | [#15](https://github.com/msarson/VitTransform/issues/15) Leading ANYVAR metavar never matches implicit vars | rule-driven | Reproduced |
| `issue16_timer` | [#16](https://github.com/msarson/VitTransform/issues/16) vitTimer rounding | harness | REFUTED - output correct on Clarion 12; kept as regression test |
| `issue17_hoistpairing` | [#17](https://github.com/msarson/VitTransform/issues/17) Hoist pairs inner IF with outer ELSE/END | rule-driven | Reproduced (x = 5 leaves the else path) |
| `issue18_knownranges` | [#18](https://github.com/msarson/VitTransform/issues/18) KnownRanges folds loop header with stale facts | rule-driven | Reproduced (loop while 1) |
| `issue19_valchr` | [#19](https://github.com/msarson/VitTransform/issues/19) val(chr(EXPR)) drops parentheses | rule-driven | Reproduced (i + 1 * 2) |
| `issue20_cosmeticdrift` | [#20](https://github.com/msarson/VitTransform/issues/20) cosmetic.txt header vs DEFAULTSTYLE tidy | rule-driven | Reproduced (whole-file re-layout on a plain run) |
| `issue21_applyonewidth` | [#21](https://github.com/msarson/VitTransform/issues/21) ApplyOne width check omits indent | rule-driven | Reproduced (94-col line, 0 width-skips) |
| `issue22_deadguard` | [#22](https://github.com/msarson/VitTransform/issues/22) DeadGuard misses %= and ^= writes | rule-driven | Reproduced (guard deleted; -= control kept) |
| `issue23_deadleft` | [#23](https://github.com/msarson/VitTransform/issues/23) DeadLeft false "starts at 1" | rule-driven | Reproduced (left() deleted on 1 + p) |
| `issue24_autocontinuation` | [#24](https://github.com/msarson/VitTransform/issues/24) AUTO on continuation line never removed | rule-driven | Reproduced (unsafe AUTO left silently) |
| `issue25_literalscan` | [#25](https://github.com/msarson/VitTransform/issues/25) Literal-scan state inversion after rejected match | harness | Reproduced (needle "found" inside a comment); latent - no in-tree callers |
| `issue26_optionbracket` | [#26](https://github.com/msarson/VitTransform/issues/26) FindOptionStart splits inside [ ] | rule-driven | Reproduced (SKIP armed, replacement truncated; lint stops the run but misdiagnoses) |
| `issue27_includeline` | [#27](https://github.com/msarson/VitTransform/issues/27) INCLUDE-not-found line number omits section offset | rule-driven | Reproduced (line 2 for line 15) |
| `issue28_configdefault` | [#28](https://github.com/msarson/VitTransform/issues/28) Blank config defaults to Debug | harness | Reproduced (pp.Config = Debug) |
| `issue29_notequiv` | [#29](https://github.com/msarson/VitTransform/issues/29) Leading <> never matches NOT = | rule-driven | Reproduced |
| (no folder) | [#30](https://github.com/msarson/VitTransform/issues/30) VitStyle fidelity @s80 vs STRING(96) | source-cited | Confirmed in source (GUI display only) |

## Compile checks

Every rule-driven `in.clw` (and issue13's `src\a.clw`) carries a
`CompileCheck.cwproj` proving the input is valid Clarion 12 -
`compile-all.bat` builds the lot. Two deliberate exceptions:

- `issue09_omitrevert` - the tokenizer trigger (`Omit(` followed by a
  glued `|`) is REJECTED by the compiler in every spelling we tried
  ("OMIT misplaced" / "Invalid OMIT/EMBED expression"), so the input
  cannot compile BY NATURE. The defect remains reachable through
  non-compiling input paths (VitStyle's paste-a-snippet preview, mid-
  edit sources) - see the issue for the re-scoped verdict.
- `issue27_includeline` - `main.clw` deliberately includes a missing
  file; that is the bug being demonstrated.

Compile-check byproducts worth keeping: issue10's premise is compiler-
verified (a local really can be named `code`), and issue21/22/23 inputs
gained the definitions/includes needed to link.
