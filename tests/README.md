# Issue repro tests

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
