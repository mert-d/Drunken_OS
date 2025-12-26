---
description: How to implement a new feature in Drunken OS
---

1.  **Check Roadmap**:

    - Read `ROADMAP.md` (if it exists) to see if this feature is already planned or conflicts with existing goals.

2.  **Planning**:

    - Use the `task_boundary` tool to enter PLANNING mode.
    - Create or update `task.md` with a breakdown of the feature work.
    - If the feature is complex (spanning multiple files), create `implementation_plan.md` in the artifacts directory.

3.  **Implementation**:

    - Start simple. If adding a new app, check `apps/` directory for examples (e.g., `apps/system.lua`).
    - If modifying core OS (`clients/Drunken_OS_Client.lua`), ensure backward compatibility.
    - Follow the style guide:
      - Use `local function` where possible.
      - Document parameters with JSDoc-style comments (e.g., `--- @param`).
      - Use `context` object for passing state in modular apps.

4.  **Verification**:

    - Update `task_boundary` to VERIFICATION mode.
    - Verify the feature works as intended (compile check, logical flow check).
    - If visual, describe the UI changes in `walkthrough.md`.

5.  **Documentation**:
    - Update `DOCUMENTATION.md` if user-facing changes were made.
    - Add comments to the new code.
