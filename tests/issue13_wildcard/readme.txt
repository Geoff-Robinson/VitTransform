Repro for issue #13 (partial).
https://github.com/msarson/VitTransform/issues/13

(a) subfolders counted as load errors: NOT REPRODUCIBLE on build 253 -
    DIRECTORY(..., ff_:NORMAL) did not return the subfolder here, so
    src\* with a subfolder present processed cleanly (exit 0, 1 file).
    May be Clarion-version/platform dependent; the code still has no
    ff_:DIRECTORY attribute filter unlike its two siblings (:999, :1100).
(b) zero-match wildcard exits 0: CONFIRMED. src\*.xyz matches nothing,
    the report says "no files matched", and the run exits 0 - despite
    the file's own contract ("A watched sweep that transforms nothing
    must not report success", vitTransform.clw ~:657).

run.bat replays both runs and prints the exit codes.
