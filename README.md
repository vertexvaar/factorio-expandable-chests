# Expandable Chests

Factorio 2.0 mod (Space Age optional). Neighbouring chests of the same type can be linked into one shared inventory,
like the cargo bays of a space platform hub. Each side is switched on or off in a small panel next to the chest window.

- Works for wooden, iron and steel chests, all logistic chests and 1x1 chests from other mods.
- Only chests of the same type and quality link. Capacity is the sum of all linked chests.
- Unlocked by the technology "Expandable chests" (same tier and cost as fluid handling).
- Links are kept in blueprints. Removing a chest takes its share of the items with it.
- Upgrading or fast-replacing chests keeps their links: an upgraded group splits into single chests with their share
  of the items and links up again as soon as the neighbours have the new type too.

## How it works

Each group has one real chest whose inventory size is overridden to the group's total. The other chests are swapped
for look-alike proxy containers that forward inserters, robots and the player to that chest. Nothing runs per tick.

## Expandable Chests and Merging Chests

[Merging Chests](https://mods.factorio.com/mod/WideChests) by Atria (with its add-on WideChestsLogistic for logistic chests) is a great mod with a similar goal. Both mods let several chests share one inventory, and they take different approaches, so you can pick what suits your factory:

**Merging Chests may suit you if you like**
- one large chest, warehouse or trash dump with its own matching graphics
- merging and splitting many chests at once with a selection tool
- fine control through mod settings: maximum sizes, inventory multipliers and which chest types can merge

**Expandable Chests may suit you if you like**
- chests that keep their place and look while sharing their inventory
- groups of any shape, for example an L or a ring around a machine
- linking each side directly in a panel next to the chest window
- a setup that works right away for all vanilla chests, logistic chests and 1x1 chests from other mods

The two mods have not been tested together yet.

## Tests

    python tests/run.py                 # headless, with Space Age
    python tests/run.py --no-space-age
    python tests/ingame.py              # opens a game window: blueprints, mining, fast replace, robots, upgrades
    python tests/shots.py               # opens a game window briefly, writes previews/shots/*.png
