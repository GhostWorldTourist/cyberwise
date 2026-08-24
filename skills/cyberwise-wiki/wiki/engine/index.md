# Engine and runtime

How the game and its script layers actually behave, independent of any mod. Mods
appear here only as examples.

- [A .reds file on disk is not code the game is running](/engine/compiled-script-bundle) - the compiled bundle, what is in it, and the three false absences
- [An archived redscript log is named for the run that replaced it](/engine/redscript-log-names-the-wrong-run) - the rotation trap, and how a compile test destroys the record of the last launch
- [Reading live game objects from CET Lua without losing the row that mattered](/engine/cet-lua-runtime) - LuaJIT limits, per-field `pcall`, and the out-param return slot that moves between builds
- [There are two load-order systems, and a conflict scan only sees one of them](/engine/two-load-order-domains) - loose archives and REDmod are ordered by different lists, and nothing ranks across them
- [The game's own option registry outranks any mod's account of an engine setting](/engine/option-registry-is-the-authority) - what `UserSettings.json` settles that no mod file can
