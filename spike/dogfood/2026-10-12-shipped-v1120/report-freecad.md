<!-- Filed 2026-10-12 as FreeCAD/FreeCAD#33493. FreeCAD's AI_POLICY.md asks that comments and
descriptions be the contributor's own: the owner wrote the text in Japanese from a draft of the
facts, and it was translated and disclosed as such. Template: 1-FUNCTIONAL_PROBLEM_REPORT.yml, its
required fields read one by one. This comment excluded, the text filed: -->

### Problem description

If the process is killed while FreeCAD is saving, `part.FCStd` can be left missing. No data is lost (the `.FCBak` and the new contents both remain in the same folder), but it is hard to notice.

`Document::saveToFile` (`src/App/Document.cpp`, main) writes the new contents to `part.FCStd.<UUID>` and then renames twice:
1. `part.FCStd` → `part.<date>.FCBak`
2. `part.FCStd.<UUID>` → `part.FCStd`

If it is killed between the two, there is no `part.FCStd`, and opening it gives `File '…/part.FCStd' does not exist!`. Renaming either file back to `part.FCStd` recovers it.

A possible fix: rename the new file directly over the original name, and make the backup beforehand as a copy or hard link. Not fixing it is also fine; in that case, please close this.

Disclosure: found with Sideeye (https://github.com/yottayoshida/sideeye, a personal open-source project). I used AI (Claude) for the investigation and to translate this from my Japanese original (Assisted-by: Claude). I checked the content myself.

### Workbench affected?

Core (App, Gui,...)

### Steps to reproduce

Open a document with `freecadcmd`, change a box's length and `save()`. Kill the process at each of the 26 points between file operations during the save; it happens at this one point (measured with Sideeye, reproduced twice).

### Expected behavior

Wherever it is killed, `part.FCStd` exists with either the old or the new contents.

### Actual behavior

Between the two renames, `part.FCStd` does not exist.

### Development version About Info (in Safe Mode)

FreeCAD 26.3.0 Revision: 20261008 (the 26.3rc1 aarch64 AppImage), run headless with `freecadcmd`, Debian 13, aarch64. Also reproduced on 1.1.4.
