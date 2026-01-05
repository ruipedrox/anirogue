Character Template
==================

This folder is a starter template for creating new character variants.

Files to fill in when creating a new character folder:

- `Stats.lua` — metadata and passive stats. Follow the structure in `Goku_4/Stats.lua`.
- `Cards.lua` — card definitions. Copy, rename and edit the entries to create the new character's cards.
- Add any Prefabs/VFX/Models required by cards here or in a canonical `Shared/FX` folder.

Steps to create a new character:

1. Duplicate this `Character_Template` folder and rename (for example `MyChar_4`).
2. Update `Stats.lua` metadata (name, stars, icon) and `Passives` values.
3. Populate `Cards.lua` with real card definitions; set `module` to the name of shared behaviour modules if needed.
4. If your card modules require visual prefabs, add them either in this folder or in `ReplicatedStorage/Shared/FX` and reference them from cards.

Notes:
- Keep shared FX in a centralized location if multiple characters reuse them.
- Use consistent naming for assets so card modules can find them reliably.
