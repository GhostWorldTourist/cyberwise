# Installs and mod managers

How a modded install is assembled, and what each assembly method makes untrue
about the files on disk. This is manager behaviour rather than game behaviour, so
it drifts with manager releases rather than with game patches.

- [What the game directory shows you depends on how the mods got there](/install/how-the-install-is-assembled) - detecting the mode, and what manual, Vortex, MO2 and Wabbajack each change
- [The deployment manifest is the inventory, and it records where each file really went](/install/the-deployment-manifest) - real target paths, phantom missing files, and why "disabled" is not "removed"
- [A staging folder name is a record of the download, not of what is installed](/install/staging-folder-names) - the version lies, and two id-derivation bugs that resolve to somebody else's mod
- [A missing-requirement report is wrong in both directions](/install/auditing-dependencies) - id matching, framework aliasing, compatibility prose, and the orphaned optional file
- [A purge is not a vanilla game](/install/what-survives-a-purge) - what a purge leaves behind, and the long first launch that looks like a hang
- [Parking a directory selects an axis the mod list does not have](/install/selecting-mods-by-layer) - layer boundaries are directories; a manager selects mods
- [Fixing a bug in someone else's mod](/install/overriding-another-authors-mod) - override or patch, and why the override's danger is silence rather than breakage
- [Two downloads from one mod page may not be alternatives](/install/two-builds-of-one-filename) - and byte size is the only thing that identifies which build is deployed
- [Never write into a mod manager's staging folder](/install/never-write-into-a-managers-staging-folder) - what a file added there breaks, and the zip that delivers the same change as its own mod
