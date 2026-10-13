# Manual QA Checklist (run in Godot 4.7.2 / Android)

This checklist is a plan for verification, not a record of tests already passed. Check and date each result only after observing it in the target engine/device.

## Startup/import

- [ ] Import project without script/scene/shader errors in Godot 4.7.2 stable.
- [ ] Confirm engine version in F3 overlay and main scene startup.
- [ ] Wait for 1,245 GLBs and 720 map images to finish importing; inspect import errors.
- [ ] Confirm grass, dirt, bedrock and sample placed models show supplied base-colour maps and normal/ORM detail in sunlight.
- [ ] Toggle optional WebP maps and confirm albedo/normal/roughness/displacement change as expected.

## Movement and interaction

- [ ] WASD, mouse look, Space jump, double-tap jump/F flight, Shift descend, and 1–9 hotbar selection.
- [ ] Mobile joystick and camera drag work simultaneously without cross-input.
- [ ] Break and place target the correct adjacent cells on all six faces.
- [ ] Test cell conversion around negative coordinates and chunk boundaries.
- [ ] Placing inside the player is rejected; breaking does not fire while clicking inventory controls.
- [ ] Digging grass/dirt updates exposed faces and terrain collision; bedrock stays locked by default.
- [ ] Test full cube, axis log, top/bottom/double slab, top/bottom stair and inner/outer corners, each door half/open state, trapdoor/gate, fence/wall/pane connections, bed/tall plant pairs, wall/floor sign, container, hopper transfer, rail shape, button/lever/pressure plate, wire/repeater/comparator/lamp, piston push/pull, TNT, fluid source/flow/reaction and falling block. Compare each result with intended Bedrock behavior.

## Inventory

- [ ] Every category opens; search is case-insensitive and matches IDs, display names, tags, material family and aliases.
- [ ] All 1,245 entries are reachable through search/pages and 3D previews show the intended imported geometry.
- [ ] Selecting an item fills the current hotbar slot and creative placement does not consume it.
- [ ] Preview paging releases old viewports and remains responsive on a mobile-class device.

## Save/load

- [ ] Build at positive, negative and distant coordinates; save, restart, reload, and compare exact positions, family states, pair relationships, container IDs and day-cycle/player state.
- [ ] Confirm player view, flight state, hotbar, slot and settings round-trip.
- [ ] Corrupt the temporary/latest save and confirm a useful diagnostic rather than a crash/data-loss loop.
- [ ] Confirm autosave behavior after repeated edits and across app suspend/resume.

## Android performance/export

- [ ] Check safe areas and touch target sizes across portrait/landscape/aspect ratios.
- [ ] Record startup import/load time, FPS/frame time, memory and chunk count on target phone.
- [ ] Compare Mobile renderer and Compatibility renderer if the device requires it.
- [ ] Configure Android export templates/SDK, build an APK, install it, and verify offline startup/save behavior.

## Family-state acceptance tests

Use `reports/mechanic_coverage.md` as the contract for what is intended and what remains approximate. The checked-in `tests/runtime_smoke.gd` exercises a subset of the actual project in a Godot process; it must pass before marking these boxes complete. Passing Python consistency tests alone is not evidence of runtime behavior.