---
description: How to refactor code in Drunken OS
---

1.  **Preparation**:

    - Ensure you understand the _current_ behavior. Refactoring should improve structure without changing external behavior.
    - If available, check for existing tests or create a small reproduction script to verify current behavior.

2.  **Planning**:

    - Enter PLANNING mode via `task_boundary`.
    - Identify the "Smell": Duplicated code, long functions, magic numbers, etc.
    - Propose the connection: "I will extract X into new file Y."
    - **Dependency Check**: Use `grep_search` to find all usages of the code you are about to move.

3.  **Execution steps**:

    - **Extract**: Move the code to the new location (e.g., `lib/new_util.lua`).
    - **Export**: Ensure the new file returns a table or function.
    - **Integrate**: Modify the _original_ file to `require` the new library.
    - **Verify**: Check that the original file still works.

4.  **Safety Rules**:

    - Do not mix Refactoring with Feature work. Do one, then the other.
    - Keep redundant backups if you are unsure (e.g., comment out old code instead of deleting immediately, then delete in a cleanup pass).

5.  **Documentation**:
    - Add JSDoc comments to the new functions.
