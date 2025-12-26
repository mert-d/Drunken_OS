---
description: How to fix a bug in Drunken OS
---

1.  **Analysis**:

    - Read the user report carefully.
    - Locate the relevant file(s). Use `grep_search` if the error location is unknown.
    - Create a reproduction hypothesis: "If I do X, Y should happen, but Z happens."

2.  **Planning**:

    - Enter PLANNING mode via `task_boundary`.
    - Update `task.md` with:
      - [ ] Locate bug
      - [ ] Fix bug
      - [ ] Verify fix

3.  **Fixing**:

    - Apply the fix using `replace_file_content` (for small fixes) or `multi_replace_file_content`.
    - **Crucial**: Check if this fix affects other components (especially in `lib/` or shared server code).

4.  **Verification**:

    - Explain _why_ the fix works.
    - If possible, run a dry-run or verify the logic mentally.

5.  **Cleanup**:
    - Remove any debug print statements you added.
