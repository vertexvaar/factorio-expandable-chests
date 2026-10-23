-- In-game tests with a real player and construction robots (tests/ingame.py runs it in a game window).
-- Writes ECTEST lines to script-output/ec-ingame/report.txt.
local PREFIX = "expandable-chests-proxy-"
local CHEST = defines.inventory.chest
local failures = 0

script.on_init(function()
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
end)

local function report(...)
  local parts = {}
  for i, v in ipairs({ ... }) do
    parts[i] = tostring(v)
  end
  helpers.write_file("ec-ingame/report.txt", "ECTEST " .. table.concat(parts, " ") .. "\n", true)
end

local function check(name, condition, detail)
  if not condition then
    failures = failures + 1
  end
  report(condition and "PASS" or "FAIL", name, detail ~= nil and tostring(detail) or "")
end

local function call(fn, ...)
  return remote.call("expandable-chests", fn, ...)
end

local surface, force, player

local function at(x, y)
  return surface.find_entities_filtered({
    area = { { x + 0.4, y + 0.4 }, { x + 0.6, y + 0.6 } },
    type = { "container", "logistic-container", "proxy-container" },
    limit = 1,
  })[1]
end

local function chest(name, x, y)
  return surface.create_entity({ name = name, position = { x + 0.5, y + 0.5 }, force = force, raise_built = true })
end

local function row(name, y, n)
  for x = 0, n - 1 do
    chest(name, x, y)
  end
  for x = 0, n - 2 do
    call("set_link", at(x, y), 2, true)
  end
end

local function is_proxy(e)
  return e.type == "proxy-container"
end

local function first_proxy(y)
  for x = 0, 6 do
    local e = at(x, y)
    if e and is_proxy(e) then
      return e
    end
  end
end

local function master(y)
  for x = 0, 6 do
    local e = at(x, y)
    if e and not is_proxy(e) and #call("group", e) > 1 then
      return e
    end
  end
end

-- Item count over all real chests of a row.
local function row_count(y, item)
  local n = 0
  for x = 0, 6 do
    local e = at(x, y)
    if e and not is_proxy(e) then
      n = n + e.get_inventory(CHEST).get_item_count(item)
    end
  end
  return n
end

local function storage_count(item)
  local n = 0
  for _, e in pairs(surface.find_entities_filtered({ name = "storage-chest", area = { { 15, -20 }, { 25, -5 } } })) do
    n = n + e.get_item_count(item)
  end
  for _, e in pairs(surface.find_entities_filtered({ type = "construction-robot" })) do
    n = n + e.get_inventory(defines.inventory.robot_cargo).get_item_count(item)
  end
  return n
end

local function ground(item)
  local n = 0
  for _, e in pairs(surface.find_entities_filtered({ type = "item-entity" })) do
    if e.stack.name == item then
      n = n + e.stack.count
    end
  end
  return n
end

local function names(y, n)
  local list = {}
  for x = 0, n - 1 do
    local e = at(x, y)
    list[#list + 1] = e and e.name:gsub(PREFIX, "P:") or "-"
  end
  return table.concat(list, ",")
end

local steps = {}
local function step(delay, fn)
  steps[#steps + 1] = { delay = delay, fn = fn }
end

-- Setup: concrete, power, roboport with robots, storage with chests.
step(1, function()
  surface.always_day = true
  local area = { { -20, -25 }, { 30, 30 } }
  for _, e in pairs(surface.find_entities_filtered({ area = area })) do
    if e.type ~= "character" then
      e.destroy()
    end
  end
  local tiles = {}
  for x = -20, 29 do
    for y = -25, 29 do
      tiles[#tiles + 1] = { name = "refined-concrete", position = { x, y } }
    end
  end
  surface.set_tiles(tiles)
  player.character.teleport({ 3, 4.5 })
  force.technologies["expandable-chests"].researched = true
  local eei = surface.create_entity({ name = "electric-energy-interface", position = { 12, -8 }, force = force })
  eei.power_production = 1e9
  eei.electric_buffer_size = 1e9
  surface.create_entity({ name = "substation", position = { 15, -10 }, force = force })
  local roboport = surface.create_entity({ name = "roboport", position = { 18, -14 }, force = force })
  roboport.get_inventory(defines.inventory.roboport_robot).insert({ name = "construction-robot", count = 40 })
  local storage = surface.create_entity({ name = "storage-chest", position = { 21.5, -10.5 }, force = force })
  storage.insert({ name = "steel-chest", count = 50 })
  storage.insert({ name = "iron-chest", count = 50 })
  for x = 15, 19 do
    surface.create_entity({ name = "storage-chest", position = { x + 0.5, -18.5 }, force = force })
  end
end)

-- A: blueprint of O-O-O, fixed up like on_player_setup_blueprint, built by the player as ghosts, robots revive them.
step(5, function()
  row("steel-chest", 0, 3)
  local inv = game.create_inventory(1)
  inv.insert({ name = "blueprint" })
  local bp = inv[1]
  local mapping = bp.create_blueprint({ surface = surface, force = force, area = { { 0, 0 }, { 3, 1 } } })
  call("setup_blueprint", bp, mapping)
  local entities = bp.get_blueprint_entities() or {}
  local summary = {}
  for _, e in pairs(entities) do
    summary[#summary + 1] = e.name .. "=" .. tostring(e.tags and e.tags.expandable_chests_mask)
  end
  table.sort(summary)
  check("A blueprint entries", #entities == 3, table.concat(summary, " "))
  local all_base = true
  for _, e in pairs(entities) do
    all_base = all_base and e.name == "steel-chest" and e.tags and e.tags.expandable_chests_mask ~= nil
  end
  check("A blueprint uses base chest with masks", all_base)
  player.cursor_stack.set_stack(bp)
  player.build_from_cursor({ position = { 1.5, -3.5 } })
  player.clear_cursor()
  inv.destroy()
  local ghosts = surface.find_entities_filtered({ type = "entity-ghost", area = { { -1, -5 }, { 4, -2 } } })
  check("A ghosts placed", #ghosts == 3, #ghosts)
end)

-- B: hand-mining a proxy of a full group gives the player its share.
step(1, function()
  row("steel-chest", 6, 3)
  master(6).insert({ name = "copper-plate", count = 144 * 100 })
  player.get_main_inventory().clear()
  local proxy = first_proxy(6)
  local ok = player.mine_entity(proxy, true)
  local got = player.get_main_inventory().get_item_count("copper-plate")
  check("B player mined proxy", ok)
  check("B player got share", got == 4800, got)
  check("B group keeps rest", row_count(6, "copper-plate") == 9600, row_count(6, "copper-plate"))
  player.get_main_inventory().clear()
end)

-- C: hand fast-replace of the master (wooden -> iron) keeps all items and relinks when possible.
step(1, function()
  row("wooden-chest", 9, 3)
  master(9).insert({ name = "coal", count = 48 * 50 })
  player.get_main_inventory().clear()
  local m = master(9)
  local mx = math.floor(m.position.x)
  player.cursor_stack.set_stack({ name = "iron-chest", count = 10 })
  player.build_from_cursor({ position = m.position })
  player.clear_cursor()
  local total = row_count(9, "coal") + player.get_main_inventory().get_item_count("coal") + ground("coal")
  report("INFO C after replace", names(9, 3), "ground", ground("coal"), "player", player.get_main_inventory().get_item_count("coal"), "row", row_count(9, "coal"))
  check("C replaced master is iron", at(mx, 9).name == "iron-chest", at(mx, 9).name)
  check("C coal conserved", total == 2400, total)
  -- Replace a proxy as well.
  local p = first_proxy(9)
  if p then
    local px = math.floor(p.position.x)
    player.cursor_stack.set_stack({ name = "iron-chest", count = 10 })
    player.build_from_cursor({ position = p.position })
    player.clear_cursor()
    report("INFO C after proxy replace", names(9, 3), "ground", ground("coal"), "player", player.get_main_inventory().get_item_count("coal"), "row", row_count(9, "coal"))
    check("C replaced proxy is iron", at(px, 9).name == "iron-chest" or at(px, 9).name == PREFIX .. "iron-chest", at(px, 9).name)
    total = row_count(9, "coal") + player.get_main_inventory().get_item_count("coal") + ground("coal")
    check("C coal conserved after proxy", total == 2400, total)
  end
  player.get_main_inventory().clear()
end)

-- D: robots deconstruct a proxy of a group.
step(1, function()
  row("steel-chest", 12, 3)
  master(12).insert({ name = "iron-ore", count = 144 * 20 })
  -- Take an end of the row, so the other two stay a group.
  local p = is_proxy(at(2, 12)) and at(2, 12) or (is_proxy(at(0, 12)) and at(0, 12)) or first_proxy(12)
  storage.d_x = math.floor(p.position.x)
  surface.deconstruct_area({ area = { { storage.d_x + 0.2, 12.2 }, { storage.d_x + 0.8, 12.8 } }, force = force, player = player })
  local marked = at(storage.d_x, 12)
  report("INFO D after mark", names(12, 3), "x", storage.d_x, "marked", marked.to_be_deconstructed(), "items", marked.get_item_count("iron-ore"))
end)

-- E: upgrade planner wooden -> iron over a linked row.
step(1, function()
  row("wooden-chest", 15, 3)
  master(15).insert({ name = "stone", count = 40 * 50 })
  local inv = game.create_inventory(1)
  inv.insert({ name = "upgrade-planner" })
  local planner = inv[1]
  planner.set_mapper(1, "from", { type = "entity", name = "wooden-chest" })
  planner.set_mapper(1, "to", { type = "entity", name = "iron-chest" })
  surface.upgrade_area({ area = { { -0.5, 14.5 }, { 3.5, 15.5 } }, force = force, player = player, item = planner })
  local marked = {}
  for x = 0, 2 do
    marked[#marked + 1] = tostring(at(x, 15).to_be_upgraded())
  end
  report("INFO E marked", names(15, 3), table.concat(marked, ","))
  inv.destroy()
end)

-- Let the robots work.
for _ = 1, 5 do
  step(300, function()
    local nets = surface.find_logistic_networks_by_construction_area({ 5.5, 12.5 }, force)
    local d = at(storage.d_x, 12)
    report("INFO t", game.tick, "D", tostring(d and d.name), 
      "robots out", #surface.find_entities_filtered({ type = "construction-robot" }), "avail", nets[1] and nets[1].available_construction_robots,
      "E", names(15, 3), "ghosts", #surface.find_entities_filtered({ type = "entity-ghost" }))
  end)
end
step(1, function()
  report("INFO A built", names(-4, 3))
  local group = at(0, -4) and call("group", at(0, -4)) or {}
  check("A robots built linked group", #group == 3, #group)

  local d = at(storage.d_x, 12)
  report("INFO D after robots", names(12, 3), d and d.to_be_deconstructed(), d and d.get_item_count("iron-ore"))
  check("D chest removed", at(storage.d_x, 12) == nil, names(12, 3))
  local total = row_count(12, "iron-ore") + storage_count("iron-ore") + ground("iron-ore")
  check("D ore conserved", total == 144 * 20, total)
  local rest = at(1, 12)
  local expected = storage.d_x == 1 and 1 or 2
  check("D group shrank", rest and #call("group", rest) == expected, rest and #call("group", rest))

  report("INFO E after robots", names(15, 3))
  local all_iron = true
  for x = 0, 2 do
    local e = at(x, 15)
    all_iron = all_iron and e and (e.name == "iron-chest" or e.name == PREFIX .. "iron-chest")
  end
  check("E all upgraded", all_iron, names(15, 3))
  local egroup = at(0, 15) and #call("group", at(0, 15)) or 0
  check("E still linked", egroup == 3, egroup)
  local stone = row_count(15, "stone") + storage_count("stone") + ground("stone")
  check("E stone conserved", stone == 2000, stone .. " (chests " .. row_count(15, "stone") .. ")")
end)

step(1, function()
  report("DONE", failures == 0 and "all passed" or (failures .. " failures"))
end)

local current, wait = 0, 0
script.on_event(defines.events.on_tick, function()
  player = game.get_player(1)
  if not player or not player.character then
    return
  end
  surface, force = player.surface, player.force
  if wait > 0 then
    wait = wait - 1
    return
  end
  current = current + 1
  local s = steps[current]
  if not s then
    return
  end
  local ok, err = pcall(s.fn)
  if not ok then
    failures = failures + 1
    report("FAIL step " .. current .. " crashed: " .. tostring(err))
  end
  wait = steps[current + 1] and steps[current + 1].delay or 0
end)
