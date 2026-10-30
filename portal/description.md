Link neighbouring chests into one big shared inventory, just like cargo bays extend the hub of a space platform.

![Linked chests in alt mode](https://raw.githubusercontent.com/vertexvaar/factorio-expandable-chests/main/previews/portal/6-overview.png)

## How it works

Open any chest and a **Linked chests** panel appears next to its window. Click **North**, **East**, **South** or **West** to link the chest with its neighbour on that side. Linked chests share one inventory whose size is the sum of all chests in the group: three steel chests in a row give you 144 slots that every chest of the group can access.

- Inserters, robots and you can use any chest of a group. It always shows the whole shared inventory.
- Only chests of the **same type and quality** link: wooden with wooden, steel with steel, requester with requester.
- Works with wooden, iron and steel chests, all five logistic chests and 1x1 chests from other mods.
- A logistic group acts as one big chest: its requests and settings apply to the whole group, no matter which chest you open.
- Alt mode shows the links as orange bars.

## Building and removing

- **Blueprints** keep the links. Robots build linked groups straight from a blueprint.
- **Removing** a chest takes its share of the items with it; the rest stays in the group.
- **Fast replace and upgrade planners** keep the links: an upgraded group links up again as soon as its neighbours have the new type too.
- Chests waiting for robots to remove or upgrade them can't be linked until the job is done or cancelled.

## Circuit network

Every chest of a group reports the contents of the whole group. If several chests of the same group are wired to one network, the panel warns that the contents are counted more than once and offers **Only this chest reports** with a single click.

## Performance

The mod does nothing while the game runs. It only works when chests are built, removed or switched, and when a chest window opens. Inventory access goes straight through the engine.

## Unlocking

Research **Expandable chests**. It has the same tier, cost and prerequisites as Fluid handling.

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

## Under the hood

Each group has one real chest whose inventory is enlarged to the group size. The other chests become look-alike proxy containers that forward all access to it.

Languages: English, German. Source and issues: [GitHub](https://github.com/vertexvaar/factorio-expandable-chests).
