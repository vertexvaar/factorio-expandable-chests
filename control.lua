-- Expandable chests: neighbouring chests of the same type share one inventory.
--
-- Every linked group has exactly one real chest, the master. Its inventory size is overridden to the sum of the
-- sizes of all chests in the group. All other chests of the group are swapped for proxy-container look-alikes that
-- forward every access to the master. Single chests are always the real vanilla entity.
--
-- Links are stored per tile as a bit mask of sides. A side is linked when both chests have the bit for it.

local shared = require("shared")

local PREFIX = shared.proxy_prefix
local CHEST = defines.inventory.chest
local GUI_NAME = "expandable-chests"
local MAX_SLOTS = 65535

local DIRS = {
  { bit = 1, dx = 0, dy = -1, opposite = 4, name = "north" },
  { bit = 2, dx = 1, dy = 0, opposite = 8, name = "east" },
  { bit = 4, dx = 0, dy = 1, opposite = 1, name = "south" },
  { bit = 8, dx = -1, dy = 0, opposite = 2, name = "west" },
}

local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

local function init_storage()
  storage.masks = storage.masks or {} -- [surface index][tile key] = side mask
  storage.detached = storage.detached or {} -- [surface index][tile key] = mask before marked for deconstruction
  storage.pending = storage.pending or {} -- [unit number] = inventory with items for the mining buffer
  storage.renders = storage.renders or {} -- [surface index][tile key] = render objects
  storage.upgrading = storage.upgrading or {} -- [surface index][tile key] = mask before marked for upgrade
  storage.opened = storage.opened or {} -- [player index] = {entity = chest of the panel, window = entity of the window}
  storage.redirect = storage.redirect or {} -- [player index] = logistic proxy whose master window is being opened
end

-- Entity helpers -----------------------------------------------------------------------------------------------------

local function is_proxy(entity)
  return entity.name:sub(1, #PREFIX) == PREFIX
end

-- The vanilla chest name of a chest or proxy, or nil when the entity can't be linked.
local function base_name(entity)
  if not (entity and entity.valid) then
    return nil
  end
  if entity.type == "entity-ghost" then
    return nil
  end
  if is_proxy(entity) then
    return entity.name:sub(#PREFIX + 1)
  end
  if prototypes.entity[PREFIX .. entity.name] then
    return entity.name
  end
end

local function tile(position)
  return math.floor(position.x), math.floor(position.y)
end

local function tile_key(position)
  local x, y = tile(position)
  return x .. "," .. y
end

local function surface_table(root, surface_index)
  local t = root[surface_index]
  if not t then
    t = {}
    root[surface_index] = t
  end
  return t
end

local function get_mask(entity)
  local t = storage.masks[entity.surface.index]
  return t and t[tile_key(entity.position)] or 0
end

local function set_mask(entity, mask)
  local t = surface_table(storage.masks, entity.surface.index)
  t[tile_key(entity.position)] = mask ~= 0 and mask or nil
end

local function base_size(entity)
  return prototypes.entity[base_name(entity)].get_inventory_size(CHEST, entity.quality) or 0
end

-- The chest of the same type and force on the given side, if any.
local function neighbour(entity, dir)
  local base = base_name(entity)
  local x, y = tile(entity.position)
  x, y = x + dir.dx, y + dir.dy
  local found = entity.surface.find_entities_filtered({
    area = { { x + 0.4, y + 0.4 }, { x + 0.6, y + 0.6 } },
    name = { base, PREFIX .. base },
    force = entity.force,
    limit = 1,
  })
  local other = found[1]
  if other and other.quality.name == entity.quality.name then
    return other
  end
end

local function is_linked(entity, dir, other)
  return band(get_mask(entity), dir.bit) ~= 0 and band(get_mask(other), dir.opposite) ~= 0
end

-- All chests linked to the given one, the given one included.
local function component(entity, seen)
  seen = seen or {}
  local result = {}
  local queue = { entity }
  seen[entity.unit_number] = true
  local i = 1
  while queue[i] do
    local current = queue[i]
    i = i + 1
    result[#result + 1] = current
    for _, dir in pairs(DIRS) do
      local other = neighbour(current, dir)
      if other and not seen[other.unit_number] and is_linked(current, dir, other) then
        seen[other.unit_number] = true
        queue[#queue + 1] = other
      end
    end
  end
  return result
end

-- Moves every stack of one inventory into another as far as it fits.
local function move_all(from, to)
  if not (from and to) then
    return
  end
  for i = 1, #from do
    local stack = from[i]
    if stack.valid_for_read then
      local empty = to.find_empty_stack()
      if empty then
        empty.transfer_stack(stack)
      end
      if stack.valid_for_read then
        local inserted = to.insert(stack)
        if inserted > 0 then
          stack.count = stack.count - inserted
        end
      end
    end
  end
end

local function spill(inventory, surface, position, force)
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then
      surface.spill_item_stack({ position = position, stack = stack, enable_looted = true, force = force, allow_belts = false })
      stack.clear()
    end
  end
end

-- Replaces a chest by its real or proxy variant, keeping wires, health, last user and orders.
local function swap(entity, name)
  local surface, position, force = entity.surface, entity.position, entity.force
  local quality, health, last_user = entity.quality, entity.health, entity.last_user
  local marked = entity.to_be_deconstructed()
  local upgrade_target, upgrade_quality = entity.get_upgrade_target()
  local behavior = entity.get_control_behavior()
  local read_contents = behavior and behavior.read_contents
  local wires = {}
  for _, id in pairs({ defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }) do
    local connector = entity.get_wire_connector(id, false)
    if connector then
      for _, connection in pairs(connector.real_connections) do
        wires[#wires + 1] = { id = id, target = connection.target, origin = connection.origin }
      end
    end
  end
  local key = tile_key(position)
  local renders = storage.renders[surface.index]
  if renders then
    renders[key] = nil
  end
  entity.destroy({ raise_destroy = false })
  local new = surface.create_entity({
    name = name,
    position = position,
    force = force,
    quality = quality,
    create_build_effect_smoke = false,
    raise_built = false,
  })
  if not new then
    return nil
  end
  new.health = health
  if last_user then
    new.last_user = last_user
  end
  for _, wire in pairs(wires) do
    if wire.target.valid then
      new.get_wire_connector(wire.id, true).connect_to(wire.target, false, wire.origin)
    end
  end
  if read_contents == false then
    local new_behavior = new.get_or_create_control_behavior()
    if new_behavior and new_behavior.read_contents ~= nil then
      new_behavior.read_contents = false
    end
  end
  if marked then
    new.order_deconstruction(force)
  end
  if upgrade_target and not is_proxy(new) then
    new.order_upgrade({ target = { name = upgrade_target.name, quality = upgrade_quality and upgrade_quality.name }, force = force })
  end
  return new
end

-- Rendering ------------------------------------------------------------------------------------------------------------

local function clear_renders(surface_index, key)
  local t = storage.renders[surface_index]
  local objects = t and t[key]
  if objects then
    for _, object in pairs(objects) do
      if object.valid then
        object.destroy()
      end
    end
    t[key] = nil
  end
end

-- Draws the links to the east and south, so that every link is drawn once.
local function draw_links(entity)
  local key = tile_key(entity.position)
  clear_renders(entity.surface.index, key)
  local objects = {}
  for _, dir in pairs({ DIRS[2], DIRS[3] }) do
    local other = neighbour(entity, dir)
    if other and is_linked(entity, dir, other) then
      objects[#objects + 1] = rendering.draw_line({
        surface = entity.surface,
        from = { entity = entity, offset = { dir.dx * 0.3, dir.dy * 0.3 } },
        to = { entity = other, offset = { -dir.dx * 0.3, -dir.dy * 0.3 } },
        color = { 0.9, 0.6, 0.1, 0.9 },
        width = 6,
        only_in_alt_mode = true,
      })
    end
  end
  if #objects > 0 then
    surface_table(storage.renders, entity.surface.index)[key] = objects
  end
end

-- Group maintenance --------------------------------------------------------------------------------------------------

-- Restores the invariant (one real master per group with the summed size, proxies pointing at it) for all groups
-- that contain one of the seeds. Items from `extra` are added to the groups. Items that no longer fit go to `sink`,
-- or are spilled when there is no sink or it is full.
local function normalize(seeds, extra, sink)
  local seen = {}
  local groups = {}
  local capacity = 0
  for _, seed in pairs(seeds) do
    if seed.valid and base_name(seed) and not seen[seed.unit_number] then
      local members = component(seed, seen)
      groups[#groups + 1] = members
      for _, member in pairs(members) do
        if not is_proxy(member) then
          capacity = capacity + #member.get_inventory(CHEST)
        end
      end
    end
  end
  if #groups == 0 then
    if extra and sink then
      move_all(extra, sink)
    end
    return
  end

  local pool = game.create_inventory(math.max(1, math.min(MAX_SLOTS, capacity)))
  local masters = {}
  for g, members in pairs(groups) do
    local total = 0
    local master
    for _, member in pairs(members) do
      total = total + base_size(member)
      if not is_proxy(member) then
        if not master or #member.get_inventory(CHEST) > #master.get_inventory(CHEST) then
          master = member
        end
      end
    end
    total = math.min(total, MAX_SLOTS)

    -- Every other real chest hands its items to the pool and becomes a proxy.
    for i, member in pairs(members) do
      if member ~= master and not is_proxy(member) then
        local inventory = member.get_inventory(CHEST)
        move_all(inventory, pool)
        if not inventory.is_empty() then
          -- The pool is sized to hold everything, so this only happens with exotic items.
          spill(inventory, member.surface, member.position, member.force)
        end
        members[i] = swap(member, PREFIX .. base_name(member))
      end
    end
    if not master then
      local index = 1
      master = swap(members[index], base_name(members[index]))
      members[index] = master
    end

    local inventory = master.get_inventory(CHEST)
    if #members == 1 then
      master.set_inventory_size_override(CHEST, nil, pool)
    elseif #inventory ~= total then
      master.set_inventory_size_override(CHEST, total, pool)
    end
    masters[g] = master

    for _, member in pairs(members) do
      if member and member.valid and member ~= master then
        member.proxy_target_entity = master
        member.proxy_target_inventory = CHEST
      end
    end
  end

  for _, master in pairs(masters) do
    move_all(extra, master.get_inventory(CHEST))
  end
  for _, master in pairs(masters) do
    move_all(pool, master.get_inventory(CHEST))
  end
  local first = masters[1]
  for _, leftovers in pairs({ pool, extra }) do
    if leftovers and not leftovers.is_empty() then
      if sink then
        move_all(leftovers, sink)
      end
      if not leftovers.is_empty() then
        spill(leftovers, first.surface, first.position, first.force)
      end
    end
  end
  pool.destroy()

  for _, members in pairs(groups) do
    for _, member in pairs(members) do
      if member and member.valid then
        draw_links(member)
      end
    end
  end
end

local function find_chest_at(surface, position, base)
  return surface.find_entities_filtered({ position = position, name = { base, PREFIX .. base }, limit = 1 })[1]
end

-- Links or unlinks a side of a chest. Returns the chest at the same position afterwards, which may be a new entity.
local function set_link(entity, dir, linked)
  local other = neighbour(entity, dir)
  if not other then
    return entity
  end
  local surface, position, base = entity.surface, entity.position, base_name(entity)
  local seeds = component(entity)
  for _, member in pairs(component(other)) do
    seeds[#seeds + 1] = member
  end
  if linked then
    set_mask(entity, bor(get_mask(entity), dir.bit))
    set_mask(other, bor(get_mask(other), dir.opposite))
  else
    set_mask(entity, band(get_mask(entity), bnot(dir.bit)))
    set_mask(other, band(get_mask(other), bnot(dir.opposite)))
  end
  normalize(seeds)
  return find_chest_at(surface, position, base)
end

-- Takes a chest out of its group before it is removed. The group keeps its items as far as they fit; the rest goes
-- into `sink`. A real chest keeps those items itself, so they come out when it is mined.
-- The neighbours keep their side bits, so a chest that replaces this one (upgrade, fast replace) can link again.
local function detach(entity, sink)
  local members = component(entity)
  local surface_index, key = entity.surface.index, tile_key(entity.position)
  local mask = get_mask(entity)
  set_mask(entity, 0)
  clear_renders(surface_index, key)
  if #members == 1 then
    return mask
  end

  local seeds = {}
  for _, member in pairs(members) do
    if member ~= entity then
      seeds[#seeds + 1] = member
    end
  end
  if is_proxy(entity) then
    entity.proxy_target_entity = nil
    normalize(seeds, nil, sink)
  else
    local inventory = entity.get_inventory(CHEST)
    local carry = game.create_inventory(math.max(1, #inventory))
    move_all(inventory, carry)
    entity.set_inventory_size_override(CHEST, nil, carry)
    normalize(seeds, carry, inventory)
    if sink and sink ~= inventory then
      move_all(inventory, sink)
    end
    carry.destroy()
  end
  return mask
end

-- Chests removed in this tick, so that a chest built on the same tile (upgrade, fast replace) takes over their links
-- and, for proxies replaced by robots, their share of the items.
local function recent_entries()
  local recent = storage.recent
  if not recent or recent.tick ~= game.tick then
    if recent then
      for _, entry in pairs(recent.entries) do
        -- Detached for a fast replace that did not happen: link the chest again.
        if entry.entity and entry.entity.valid then
          set_mask(entry.entity, entry.mask)
          local items = entry.items
          entry.items = nil
          normalize({ entry.entity }, items)
          if items and items.valid then
            items.destroy()
          end
        end
        if entry.items and entry.items.valid then
          if entry.surface.valid then
            spill(entry.items, entry.surface, entry.position, entry.force)
          end
          entry.items.destroy()
        end
      end
    end
    recent = { tick = game.tick, entries = {} }
    storage.recent = recent
  end
  return recent.entries
end

-- `waiting` is set when the chest is detached ahead of a fast replace that may still fail.
local function remember_removed(entity, mask, items, waiting)
  local entries = recent_entries()
  local key = entity.surface.index .. ":" .. tile_key(entity.position)
  local entry = entries[key]
  if entry then
    -- Already detached before the replace; now it is really going away.
    entry.entity = nil
    if items and items.valid then
      if entry.items and entry.items.valid then
        move_all(items, entry.items)
      end
      if not items.is_empty() then
        spill(items, entity.surface, entity.position)
      end
      items.destroy()
    end
    return
  end
  entries[key] = {
    mask = mask,
    items = items,
    entity = waiting and entity or nil,
    surface = entity.surface,
    position = entity.position,
    force = entity.force,
  }
end

local function take_removed(entity)
  local entries = recent_entries()
  local key = entity.surface.index .. ":" .. tile_key(entity.position)
  local entry = entries[key]
  entries[key] = nil
  return entry
end

-- Events -------------------------------------------------------------------------------------------------------------

local function on_built(event)
  local entity = event.entity
  local base = base_name(entity)
  if not base then
    return
  end
  local mask = event.tags and event.tags.expandable_chests_mask
  local upgrading = storage.upgrading[entity.surface.index]
  local key = tile_key(entity.position)
  if upgrading and upgrading[key] then
    mask = mask or upgrading[key]
    upgrading[key] = nil
  end
  local replaced = take_removed(entity)
  if replaced then
    mask = mask or replaced.mask
    if replaced.items and replaced.items.valid then
      if not is_proxy(entity) then
        move_all(replaced.items, entity.get_inventory(CHEST))
      end
      if not replaced.items.is_empty() then
        spill(replaced.items, entity.surface, entity.position, entity.force)
      end
      replaced.items.destroy()
    end
  end
  mask = mask or 0
  set_mask(entity, mask)
  if mask == 0 and not is_proxy(entity) and not replaced then
    return
  end
  local seeds = { entity }
  for _, dir in pairs(DIRS) do
    local other = neighbour(entity, dir)
    if other then
      seeds[#seeds + 1] = other
    end
  end
  normalize(seeds)
end

local function on_pre_mined(event)
  local entity = event.entity
  if not base_name(entity) then
    return
  end
  if is_proxy(entity) then
    local pending = game.create_inventory(math.max(1, base_size(entity)))
    local mask = detach(entity, pending)
    if pending.is_empty() then
      pending.destroy()
    else
      storage.pending[entity.unit_number] = pending
    end
    remember_removed(entity, mask)
  else
    remember_removed(entity, detach(entity, entity.get_inventory(CHEST)))
  end
end

local function on_mined(event)
  local entity = event.entity
  -- Robot upgrades skip the pre-mined event; the items have already gone to the replacement here.
  if entity.valid and base_name(entity) and get_mask(entity) ~= 0 and #component(entity) > 1 then
    remember_removed(entity, detach(entity))
  end
  local detached = storage.detached[entity.surface.index]
  if detached then
    detached[tile_key(entity.position)] = nil
  end
  local pending = storage.pending[entity.unit_number]
  if not pending then
    return
  end
  storage.pending[entity.unit_number] = nil
  if pending.valid then
    move_all(pending, event.buffer)
    local player = event.player_index and game.get_player(event.player_index)
    if player then
      move_all(pending, player.get_main_inventory())
    end
    if not pending.is_empty() then
      spill(pending, entity.surface, entity.position, not player and entity.force or nil)
    end
    pending.destroy()
  end
end

local function on_destroyed(event)
  local entity = event.entity
  if not base_name(entity) then
    return
  end
  if is_proxy(entity) then
    detach(entity)
  else
    detach(entity, entity.get_inventory(CHEST))
  end
end

local function on_marked_for_deconstruction(event)
  local entity = event.entity
  local base = base_name(entity)
  if not base or #component(entity) == 1 then
    return
  end
  local surface, position, key = entity.surface, entity.position, tile_key(entity.position)
  if is_proxy(entity) then
    local pending = game.create_inventory(math.max(1, base_size(entity)))
    local mask = detach(entity, pending)
    surface_table(storage.detached, surface.index)[key] = mask
    local chest = swap(entity, base)
    if chest then
      move_all(pending, chest.get_inventory(CHEST))
    end
    if not pending.is_empty() then
      spill(pending, surface, position, entity.force)
    end
    pending.destroy()
  else
    local mask = detach(entity, entity.get_inventory(CHEST))
    surface_table(storage.detached, surface.index)[key] = mask
  end
end

-- Links a chest again with the sides it had before it was marked, where the neighbour isn't marked as well.
local function restore(entity, saved)
  if not base_name(entity) then
    return
  end
  local t = saved[entity.surface.index]
  local key = tile_key(entity.position)
  local mask = t and t[key]
  if not mask then
    return
  end
  t[key] = nil
  local seeds = { entity }
  local restored = 0
  for _, dir in pairs(DIRS) do
    local other = band(mask, dir.bit) ~= 0 and neighbour(entity, dir)
    if other and not other.to_be_deconstructed() and not other.to_be_upgraded() then
      restored = bor(restored, dir.bit)
      set_mask(other, bor(get_mask(other), dir.opposite))
      seeds[#seeds + 1] = other
    end
  end
  set_mask(entity, restored)
  normalize(seeds)
end

local function on_cancelled_deconstruction(event)
  restore(event.entity, storage.detached)
end

-- A player fast-replaces a chest by building over it. The game takes the items out of the old chest before any
-- mining event, which would hand the whole group's items to the new chest, so the old chest leaves its group first.
local function on_pre_build(event)
  local player = game.get_player(event.player_index)
  local stack = player and player.cursor_stack
  local item = stack and stack.valid_for_read and stack.prototype
  local result = item and item.place_result
  if not (result and (result.type == "container" or result.type == "logistic-container")) then
    return
  end
  local entity = player.surface.find_entities_filtered({
    position = event.position,
    type = { "container", "logistic-container", "proxy-container" },
    limit = 1,
  })[1]
  if not base_name(entity) or #component(entity) == 1 then
    return
  end
  if result.name == base_name(entity) and stack.quality.name == entity.quality.name then
    return
  end
  if is_proxy(entity) then
    local pending = game.create_inventory(math.max(1, base_size(entity)))
    remember_removed(entity, detach(entity, pending), pending, true)
  else
    remember_removed(entity, detach(entity, entity.get_inventory(CHEST)), nil, true)
  end
end

-- An upgrade replaces chests one by one with another type, which can't stay in the group anyway. The group is split
-- into single chests with their share of the items, all marked for the upgrade. Each upgraded chest gets its old
-- sides back when it is built, so the group links up again once its neighbours are upgraded too.
local function on_marked_for_upgrade(event)
  local entity = event.entity
  local base = base_name(entity)
  if not base or not event.target then
    return
  end
  local members = component(entity)
  if #members == 1 then
    return
  end
  local target = { name = event.target.name, quality = event.quality and event.quality.name }
  local surface = entity.surface
  local saved = surface_table(storage.upgrading, surface.index)
  local master, capacity = nil, 0
  for _, member in pairs(members) do
    saved[tile_key(member.position)] = get_mask(member)
    set_mask(member, 0)
    clear_renders(surface.index, tile_key(member.position))
    if not is_proxy(member) then
      master = member
      capacity = capacity + #member.get_inventory(CHEST)
    end
  end
  local pool = game.create_inventory(math.max(1, math.min(MAX_SLOTS, capacity)))
  if master then
    move_all(master.get_inventory(CHEST), pool)
    master.set_inventory_size_override(CHEST, nil, pool)
  end
  local chests = {}
  for _, member in pairs(members) do
    local chest = is_proxy(member) and swap(member, base) or member
    if chest then
      chests[#chests + 1] = chest
      move_all(pool, chest.get_inventory(CHEST))
    end
  end
  if not pool.is_empty() and chests[1] then
    spill(pool, surface, chests[1].position, chests[1].force)
  end
  pool.destroy()
  for _, chest in pairs(chests) do
    if not chest.to_be_upgraded() then
      chest.order_upgrade({ target = target, force = chest.force, player = event.player_index })
    end
  end
end

local function on_cancelled_upgrade(event)
  restore(event.entity, storage.upgrading)
end

local function on_setup_blueprint(event)
  local blueprint = event.stack
  if not (blueprint and blueprint.valid_for_read and blueprint.is_blueprint) then
    blueprint = event.record
  end
  if not (blueprint and blueprint.valid) then
    return
  end
  local mapping = event.mapping.get()
  local entities = blueprint.get_blueprint_entities()
  if not entities then
    return
  end
  local changed = false
  for index, entry in pairs(entities) do
    local entity = mapping[index]
    if entity and entity.valid and base_name(entity) then
      if is_proxy(entity) then
        entry.name = base_name(entity)
        changed = true
      end
      local mask = get_mask(entity)
      if mask ~= 0 then
        entry.tags = entry.tags or {}
        entry.tags.expandable_chests_mask = mask
        changed = true
      end
    end
  end
  if changed then
    blueprint.set_blueprint_entities(entities)
  end
end

-- GUI ----------------------------------------------------------------------------------------------------------------

local function researched(force)
  local technology = force.technologies[shared.technology]
  return technology and technology.researched
end

local function destroy_panel(player)
  local panel = player.gui.relative[GUI_NAME]
  if panel then
    panel.destroy()
  end
end

-- Logistic proxies can't show the request settings, so their window is the master's window instead.
local function window_of(entity)
  local target = is_proxy(entity) and entity.proxy_target_entity
  if target and target.valid and target.type == "logistic-container" then
    return target
  end
  return entity
end

-- Circuit reading ----------------------------------------------------------------------------------------------------

local WIRES = { defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }

local function reads_contents(entity)
  local behavior = entity.get_control_behavior()
  return not behavior or behavior.read_contents ~= false
end

local function network_ids(entity)
  local ids = {}
  for _, id in pairs(WIRES) do
    local network = entity.get_circuit_network(id)
    if network then
      ids[network.network_id] = true
    end
  end
  return ids
end

-- Other chests of the group that report the group's contents to a circuit network this chest is on as well.
-- Only checked when a chest window opens, so it costs nothing while the game runs.
local function duplicate_readers(entity)
  local ids = network_ids(entity)
  if next(ids) == nil then
    return {}
  end
  local result = {}
  for _, member in pairs(component(entity)) do
    if member ~= entity and reads_contents(member) then
      for id in pairs(network_ids(member)) do
        if ids[id] then
          result[#result + 1] = member
          break
        end
      end
    end
  end
  return result
end

-- Lets only this chest report the group to the networks it shares with other chests of the group.
local function make_sole_reader(entity)
  for _, member in pairs(duplicate_readers(entity)) do
    member.get_or_create_control_behavior().read_contents = false
  end
  entity.get_or_create_control_behavior().read_contents = true
end

-- Shows the side switches of `entity` next to the open window of `window`.
local function build_panel(player, entity, window)
  destroy_panel(player)
  storage.opened[player.index] = { entity = entity, window = window }
  local gui_type = is_proxy(window) and defines.relative_gui_type.proxy_container_gui
    or defines.relative_gui_type.container_gui
  local frame = player.gui.relative.add({
    type = "frame",
    name = GUI_NAME,
    caption = { "expandable-chests.title" },
    direction = "vertical",
    anchor = { gui = gui_type, position = defines.relative_gui_position.right },
  })
  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local grid = inner.add({ type = "table", column_count = 3 })
  grid.style.horizontal_spacing = 4
  grid.style.vertical_spacing = 4
  local layout = { false, 1, false, 4, "center", 2, false, 3, false }
  for _, cell in ipairs(layout) do
    if cell == false then
      grid.add({ type = "empty-widget" })
    elseif cell == "center" then
      local sprite = grid.add({ type = "sprite", sprite = "entity/" .. base_name(entity) })
      sprite.style.size = 40
      sprite.style.stretch_image_to_widget_size = true
    else
      local dir = DIRS[cell]
      local other = neighbour(entity, dir)
      local linked = other and is_linked(entity, dir, other)
      -- Chests waiting for robots to remove or upgrade them stay out of groups.
      local busy = other and (entity.to_be_deconstructed() or entity.to_be_upgraded() or other.to_be_deconstructed()
        or other.to_be_upgraded())
      local button = grid.add({
        type = "button",
        caption = { "expandable-chests.side-" .. dir.name },
        tooltip = { other and (linked and "expandable-chests.tooltip-linked" or "expandable-chests.tooltip-unlinked")
          or "expandable-chests.tooltip-none" },
        style = linked and "green_button" or "button",
        enabled = other ~= nil and not busy,
        tags = { expandable_chests_side = cell },
      })
      button.style.width = 72
    end
  end
  local members = component(entity)
  local slots = 0
  for _, member in pairs(members) do
    slots = slots + base_size(member)
  end
  inner.add({ type = "label", caption = { "expandable-chests.group-size", #members, math.min(slots, MAX_SLOTS) } })
  local duplicates = reads_contents(entity) and #duplicate_readers(entity) or 0
  if duplicates > 0 then
    local warning = inner.add({ type = "label", caption = { "expandable-chests.double-count", duplicates + 1 } })
    warning.style.single_line = false
    warning.style.maximal_width = 220
    warning.style.font_color = { 1, 0.75, 0.2 }
    inner.add({
      type = "button",
      caption = { "expandable-chests.sole-reader" },
      tooltip = { "expandable-chests.sole-reader-tooltip" },
      tags = { expandable_chests_sole_reader = true },
    })
  end
end

-- Opens the window for a chest, or just rebuilds the panel when that window is already open.
local function show(player, entity)
  local window = window_of(entity)
  if player.opened == window then
    build_panel(player, entity, window)
  else
    storage.redirect[player.index] = window ~= entity and entity or nil
    player.opened = window
  end
end

local function on_gui_opened(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local entity = event.entity
  local redirected = storage.redirect[player.index]
  storage.redirect[player.index] = nil
  if not (base_name(entity) and researched(player.force)) then
    destroy_panel(player)
    return
  end
  if redirected and redirected.valid and window_of(redirected) == entity then
    build_panel(player, redirected, entity)
  elseif window_of(entity) ~= entity then
    show(player, entity)
  else
    build_panel(player, entity, entity)
  end
end

local function on_gui_closed(event)
  local player = game.get_player(event.player_index)
  local opened = player and storage.opened[player.index]
  if opened and event.entity and (opened.window == event.entity or opened.entity == event.entity) then
    storage.opened[player.index] = nil
    destroy_panel(player)
  end
end

local function on_gui_click(event)
  local element = event.element
  local tags = element.valid and element.tags
  local side = tags and tags.expandable_chests_side
  if not (side or (tags and tags.expandable_chests_sole_reader)) then
    return
  end
  local player = game.get_player(event.player_index)
  local opened = storage.opened[player.index]
  local entity = opened and opened.entity
  if not (entity and entity.valid) then
    destroy_panel(player)
    return
  end
  if not side then
    make_sole_reader(entity)
    build_panel(player, entity, opened.window)
    return
  end
  local dir = DIRS[side]
  local other = neighbour(entity, dir)
  local chest = set_link(entity, dir, not (other and is_linked(entity, dir, other)))
  if chest and chest.valid then
    show(player, chest)
  else
    destroy_panel(player)
  end
end

-- Registration -------------------------------------------------------------------------------------------------------

script.on_init(init_storage)
script.on_configuration_changed(init_storage)

local built = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}
local filters = {
  { filter = "type", type = "container" },
  { filter = "type", type = "logistic-container" },
  { filter = "type", type = "proxy-container" },
}
for _, id in pairs(built) do
  script.on_event(id, on_built, filters)
end
for _, id in pairs({ defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_space_platform_pre_mined }) do
  script.on_event(id, on_pre_mined, filters)
end
for _, id in pairs({ defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity, defines.events.on_space_platform_mined_entity }) do
  script.on_event(id, on_mined, filters)
end
script.on_event(defines.events.on_entity_died, on_destroyed, filters)
script.on_event(defines.events.script_raised_destroy, on_destroyed, filters)
script.on_event(defines.events.on_marked_for_deconstruction, on_marked_for_deconstruction, filters)
script.on_event(defines.events.on_cancelled_deconstruction, on_cancelled_deconstruction, filters)
script.on_event(defines.events.on_pre_build, on_pre_build)
script.on_event(defines.events.on_marked_for_upgrade, on_marked_for_upgrade, filters)
script.on_event(defines.events.on_cancelled_upgrade, on_cancelled_upgrade, filters)
script.on_event(defines.events.on_player_setup_blueprint, on_setup_blueprint)
script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_gui_closed, on_gui_closed)
script.on_event(defines.events.on_gui_click, on_gui_click)

-- Used by the tests and by other mods.
remote.add_interface("expandable-chests", {
  -- side: 1 north, 2 east, 3 south, 4 west
  set_link = function(entity, side, linked)
    return set_link(entity, DIRS[side], linked)
  end,
  group = function(entity)
    return component(entity)
  end,
  remove = function(entity, sink)
    return detach(entity, sink)
  end,
  build = function(entity, mask)
    on_built({ entity = entity, tags = { expandable_chests_mask = mask } })
  end,
  -- Runs the blueprint fix-up on a blueprint made by create_blueprint, for tests.
  setup_blueprint = function(stack, mapping)
    on_setup_blueprint({ stack = stack, mapping = { get = function() return mapping end } })
  end,
  duplicate_readers = function(entity)
    return duplicate_readers(entity)
  end,
  make_sole_reader = function(entity)
    make_sole_reader(entity)
  end,
  -- Presses a side button in the open panel of a player, for tests.
  click_side = function(player_index, side)
    local panel = game.get_player(player_index).gui.relative[GUI_NAME]
    local button
    local function find(element)
      for _, child in pairs(element.children) do
        if child.tags and child.tags.expandable_chests_side == side then
          button = child
        end
        find(child)
      end
    end
    if panel then
      find(panel)
    end
    if button and button.enabled then
      on_gui_click({ element = button, player_index = player_index })
      return true
    end
    return false
  end,
})
