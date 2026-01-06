---
description: Start a new development version or troubleshooting session in an isolated subfolder.
---

This workflow creates a safe, isolated copy of the current stable codebase in `DevVersions/`. Use this before starting any risky changes, new features, or troubleshooting.

1.  **Define the version name**:
    *   Format: `v[Version]_[FeatureName]` (e.g., `v1.2_Refactor`, `v1.1_DebugLogs`).
    
2.  **Create the directory**:
    ```bash
    mkdir -p DevVersions/[VersionName]
    ```

3.  **Copy the stable codebase**:
    *   *Note: We exclude build artifacts, git metadata, backups, and other dev versions.*
    ```bash
    rsync -av --progress . DevVersions/[VersionName]/ --exclude '.git' --exclude '.build' --exclude 'dist' --exclude 'Backups' --exclude 'DevVersions' --exclude '*.dmg' --exclude '*.zip'
    ```

4.  **Switch Context**:
    *   From now on, **only edit files** inside `DevVersions/[VersionName]/`.
    *   Run builds from that directory.

5.  **Finalization (Manual)**:
    *   Once the dev version is stable and approved, you can copy the changes back to the root or release from the dev folder.
