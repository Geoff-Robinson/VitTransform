-- Redirection for the issue #6 harness: adds the repo root (..\..) so
-- vitTokenize.inc/.clw resolve. A local red is only used when it is
-- named like the version default in C:\Clarion\<<ver>>\bin - for
-- Clarion 12 that is CLARION120.RED, hence this file's name.
{INCLUDE %REDDIR%\Clarion120.red}
[Common]
*.inc = .;..\..
*.clw = .;..\..
*.equ = .;..\..
