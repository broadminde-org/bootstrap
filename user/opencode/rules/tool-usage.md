# Tool Usage

## Scope
Every task. How to use the available tools correctly.

## Rules
- FILE_TOOLS: Read files with Read tool. Write files with Write tool. Edit files with Edit tool. Search with Glob/Grep tools. NEVER `cat`, `echo >`, `sed`, `find`, or `grep` in bash for file operations.
- READ_HYGIENE: Use offset/limit for large files. For shell/Python, read the specific function or section, not the whole file. Never re-read a file in the same session unless an edit failed.
- EDIT_VERIFY: After editing, the Edit tool reports success/failure. On failure (oldString not found), re-read the file before attempting a corrected edit.
- SESSION_DISCIPLINE: If the session context is too long to recall file contents accurately, prefer starting a fresh session rather than re-reading many files. Re-read only when the edit context requires it.
