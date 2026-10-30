-- Headless test harness. Logs ECTEST lines that tests/run.py collects.
local PREFIX = "expandable-chests-proxy-"
local CHEST = defines.inventory.chest
local failures = 0

local function log_line(...)
  local parts = {}
  for i, v in ipairs({ ... }) do
    parts[i] = tostring(v)
  end
  log("ECTEST " .. table.concat(parts, " "))
end

local function check(name, condition, detail)
  if condition then
    log_line("PASS", name)
  else
    failures = failures + 1
    log_line("FAIL", name, tostring(detail))
  end
end

local function call(fn, ...)
  return remote.call("expandable-chests", fn, ...)
end

local surface, force
local function chest(name, x, y, quality)
  return surface.create_entity({ name = name, position = { x + 0.5, y + 0.5 }, force = force, quality = quality, raise_built = true })
end

local function at(x, y)
  return surface.find_entities_filtered({
    area = { { x + 0.4, y + 0.4 }, { x + 0.6, y + 0.6 } },
    type = { "container", "logistic-container", "proxy-container" },
    limit = 1,
  })[1]
end

local function size(e)
  return #e.get_inventory(CHEST)
end

local function count(e, item)
  return e.get_inventory(CHEST).get_item_count(item)
end

local function fill(e, item, amount)
  return e.get_inventory(CHEST).insert({ name = item, count = amount })
end

local function is_proxy(e)
  return e.type == "proxy-container"
end

-- Sum of an item over the real chests in a row.
local function real_total(y, item)
  local total = 0
  for x = 0, 6 do
    local e = at(x, y)
    if e and not is_proxy(e) then
      total = total + count(e, item)
    end
  end
  return total
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

local function clear_ground()
  for _, e in pairs(surface.find_entities_filtered({ type = "item-entity" })) do
    e.destroy()
  end
end

local function master_of(group)
  for _, e in pairs(group) do
    if not is_proxy(e) then
      return e
    end
  end
end

local tests = {}

tests[#tests + 1] = function()
  for _, name in pairs({ "wooden-chest", "iron-chest", "steel-chest", "passive-provider-chest", "active-provider-chest",
    "storage-chest", "requester-chest", "buffer-chest" }) do
    check("proxy prototype " .. name, prototypes.entity[PREFIX .. name] ~= nil)
  end
  local tech, fluid = prototypes.technology["expandable-chests"], prototypes.technology["fluid-handling"]
  local same = tech.research_unit_count == fluid.research_unit_count and tech.research_unit_energy == fluid.research_unit_energy
  for name in pairs(fluid.prerequisites) do
    same = same and tech.prerequisites[name] ~= nil
  end
  check("technology matches fluid handling", same)
end

-- O - O - O in a row: one master with 3x48 slots, two proxies.
tests[#tests + 1] = function()
  chest("steel-chest", 0, 0); chest("steel-chest", 1, 0); chest("steel-chest", 2, 0)
  fill(at(1, 0), "iron-plate", 1000)
  call("set_link", at(0, 0), 2, true)
  call("set_link", at(1, 0), 2, true)
  local group = call("group", at(0, 0))
  check("row group size", #group == 3, #group)
  local proxies = 0
  for _, e in pairs(group) do
    if e.name == PREFIX .. "steel-chest" then
      proxies = proxies + 1
    end
  end
  local master = master_of(group)
  check("row one master two proxies", proxies == 2, proxies)
  check("row master size", size(master) == 144, size(master))
  for _, e in pairs(group) do
    if e ~= master then
      check("row proxy target", e.proxy_target_entity == master)
      check("row proxy sees items", count(e, "iron-plate") == 1000, count(e, "iron-plate"))
    end
  end
  local proxy = is_proxy(group[1]) and group[1] or group[2]
  fill(proxy, "iron-plate", 144 * 100)
  check("row full capacity", count(master, "iron-plate") == 144 * 100, count(master, "iron-plate"))

  -- Split the last chest off: 96 + 48 slots, nothing lost.
  call("set_link", at(1, 0), 2, false)
  local left, right = call("group", at(0, 0)), call("group", at(2, 0))
  check("split sizes", #left == 2 and #right == 1, #left .. "/" .. #right)
  check("split keeps items", real_total(0, "iron-plate") == 14400, real_total(0, "iron-plate"))
  check("split single is real chest", at(2, 0).name == "steel-chest" and size(at(2, 0)) == 48, at(2, 0).name)
  check("split pair size", size(master_of(left)) == 96, size(master_of(left)))
end

-- Different chest types never link.
tests[#tests + 1] = function()
  chest("steel-chest", 0, 3); chest("iron-chest", 1, 3)
  call("set_link", at(0, 3), 2, true)
  check("mixed types stay apart", #call("group", at(0, 3)) == 1 and size(at(0, 3)) == 48)
end

-- O O - : linking only where switched on.
tests[#tests + 1] = function()
  chest("wooden-chest", 0, 5); chest("wooden-chest", 1, 5); chest("wooden-chest", 2, 5)
  call("set_link", at(1, 5), 2, true)
  check("partial row", #call("group", at(0, 5)) == 1 and #call("group", at(1, 5)) == 2)
end

-- Removing a proxy hands back its share of the items.
tests[#tests + 1] = function()
  for x = 0, 2 do
    chest("steel-chest", x, 7)
  end
  call("set_link", at(0, 7), 2, true)
  call("set_link", at(1, 7), 2, true)
  fill(at(0, 7), "copper-plate", 144 * 100)
  local proxy
  for x = 0, 2 do
    if is_proxy(at(x, 7)) then
      proxy = at(x, 7)
      break
    end
  end
  local px = math.floor(proxy.position.x)
  local sink = game.create_inventory(48)
  call("remove", proxy, sink)
  proxy.destroy()
  check("remove proxy sink", sink.get_item_count("copper-plate") == 4800, sink.get_item_count("copper-plate"))
  check("remove proxy keeps rest", real_total(7, "copper-plate") == 9600, real_total(7, "copper-plate"))
  local left = px == 0 and 0 or #call("group", at(0, 7))
  check("remove proxy regroups", px ~= 1 or (left == 1 and #call("group", at(2, 7)) == 1), "removed at " .. px)
  sink.destroy()
end

-- Removing the master: another chest takes over, the removed chest keeps its share.
tests[#tests + 1] = function()
  for x = 0, 2 do
    chest("iron-chest", x, 9)
  end
  call("set_link", at(0, 9), 2, true)
  call("set_link", at(1, 9), 2, true)
  fill(at(1, 9), "stone", 96 * 50)
  local master = master_of(call("group", at(0, 9)))
  call("remove", master, master.get_inventory(CHEST))
  check("remove master keeps own share", count(master, "stone") == 32 * 50 and size(master) == 32,
    count(master, "stone") .. " in " .. size(master))
  master.destroy()
  check("remove master moves rest", real_total(9, "stone") == 64 * 50, real_total(9, "stone"))
end

-- A destroyed proxy spills its share.
tests[#tests + 1] = function()
  clear_ground()
  chest("steel-chest", 0, 11); chest("steel-chest", 1, 11)
  call("set_link", at(0, 11), 2, true)
  fill(at(0, 11), "coal", 96 * 50)
  local proxy = is_proxy(at(0, 11)) and at(0, 11) or at(1, 11)
  proxy.die()
  check("died proxy spills share", ground("coal") == 48 * 50 and real_total(11, "coal") == 48 * 50,
    ground("coal") .. " / " .. real_total(11, "coal"))
  clear_ground()
end

-- Logistic chests link with their own type only.
tests[#tests + 1] = function()
  chest("requester-chest", 0, 13); chest("requester-chest", 1, 13); chest("storage-chest", 2, 13)
  call("set_link", at(0, 13), 2, true)
  call("set_link", at(1, 13), 2, true)
  local group = call("group", at(0, 13))
  check("requester pair", #group == 2 and size(master_of(group)) == 96, #group)
  check("storage stays alone", #call("group", at(2, 13)) == 1)
end

-- Circuit wires survive the swap.
tests[#tests + 1] = function()
  local a, b = chest("steel-chest", 0, 15), chest("steel-chest", 1, 15)
  local cc = surface.create_entity({ name = "constant-combinator", position = { 1.5, 16.5 }, force = force })
  for _, e in pairs({ a, b }) do
    e.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
      cc.get_wire_connector(defines.wire_connector_id.circuit_red, true))
  end
  call("set_link", a, 2, true)
  local ok = true
  for x = 0, 1 do
    local c = at(x, 15).get_wire_connector(defines.wire_connector_id.circuit_red, false)
    ok = ok and c ~= nil and c.connection_count == 1
  end
  check("wires kept", ok)
end

-- Built with a mask from a blueprint links to neighbours that also have it.
tests[#tests + 1] = function()
  local a = surface.create_entity({ name = "steel-chest", position = { 0.5, 18.5 }, force = force })
  call("build", a, 2)
  local b = surface.create_entity({ name = "steel-chest", position = { 1.5, 18.5 }, force = force })
  call("build", b, 8)
  check("blueprint tags link", #call("group", at(0, 18)) == 2)
  local p = surface.create_entity({ name = PREFIX .. "steel-chest", position = { 5.5, 18.5 }, force = force })
  call("build", p, 0)
  check("lonely proxy turns real", at(5, 18).name == "steel-chest")
end

-- Marking for deconstruction takes the chest out of the group; cancelling puts it back.
tests[#tests + 1] = function()
  chest("steel-chest", 0, 20); chest("steel-chest", 1, 20); chest("steel-chest", 2, 20)
  call("set_link", at(0, 20), 2, true)
  call("set_link", at(1, 20), 2, true)
  fill(at(0, 20), "iron-ore", 144 * 50)
  local proxy
  for x = 0, 2 do
    if is_proxy(at(x, 20)) then
      proxy = at(x, 20)
      break
    end
  end
  local x = math.floor(proxy.position.x)
  proxy.order_deconstruction(force)
  local marked = at(x, 20)
  check("marked chest is real and alone", marked.type == "container" and #call("group", marked) == 1
    and count(marked, "iron-ore") == 48 * 50 and marked.to_be_deconstructed(), marked.type .. " " .. count(marked, "iron-ore"))
  marked.cancel_deconstruction(force)
  check("cancel relinks", #call("group", at(0, 20)) == 3, #call("group", at(0, 20)))
  check("cancel keeps items", real_total(20, "iron-ore") == 144 * 50, real_total(20, "iron-ore"))
end

-- Inserters work through a proxy (checked after some ticks).
tests[#tests + 1] = function()
  chest("steel-chest", 0, 24); chest("steel-chest", 1, 24)
  call("set_link", at(0, 24), 2, true)
  local proxy = is_proxy(at(0, 24)) and at(0, 24) or at(1, 24)
  local x = math.floor(proxy.position.x)
  fill(proxy, "iron-gear-wheel", 100)
  local inserter = surface.create_entity({ name = "burner-inserter", position = { x + 0.5, 25.5 }, direction = defines.direction.north, force = force })
  inserter.get_fuel_inventory().insert({ name = "coal", count = 5 })
  surface.create_entity({ name = "wooden-chest", position = { x + 0.5, 26.5 }, force = force })
end

-- Circuit network: each chest of a group on its own red network; a pair sharing one network (checked after some ticks).
local RED = defines.wire_connector_id.circuit_red
local function wire(a, b)
  a.get_wire_connector(RED, true).connect_to(b.get_wire_connector(RED, true))
end

tests[#tests + 1] = function()
  for x = 0, 2 do
    chest("steel-chest", x, 28)
  end
  call("set_link", at(0, 28), 2, true)
  call("set_link", at(1, 28), 2, true)
  fill(at(0, 28), "iron-plate", 500)
  for x = 0, 2 do
    local pole = surface.create_entity({ name = "small-electric-pole", position = { x + 0.5, 30.5 }, force = force })
    wire(at(x, 28), pole)
  end
  chest("steel-chest", 0, 33); chest("steel-chest", 1, 33)
  call("set_link", at(0, 33), 2, true)
  fill(at(0, 33), "copper-plate", 300)
  local shared = surface.create_entity({ name = "small-electric-pole", position = { 0.5, 35.5 }, force = force })
  wire(at(0, 33), shared)
  wire(at(1, 33), shared)
  -- A wire added after linking, to a chest that is a proxy at that time.
  chest("steel-chest", 4, 28); chest("steel-chest", 5, 28)
  call("set_link", at(4, 28), 2, true)
  fill(at(4, 28), "coal", 200)
  -- Switching reading off survives the chest becoming a proxy and a real chest again.
  chest("steel-chest", 8, 28); chest("steel-chest", 9, 28)
  local quiet = surface.create_entity({ name = "small-electric-pole", position = { 8.5, 30.5 }, force = force })
  wire(at(8, 28), quiet)
  at(8, 28).get_or_create_control_behavior().read_contents = false
  call("set_link", at(9, 28), 4, true)
  local swapped = is_proxy(at(8, 28))
  call("set_link", at(8, 28), 2, false)
  check("read contents off kept", swapped and at(8, 28).get_control_behavior().read_contents == false, "was proxy: " .. tostring(swapped))
  local late = surface.create_entity({ name = "small-electric-pole", position = { 4.5, 30.5 }, force = force })
  local proxy = is_proxy(at(4, 28)) and at(4, 28) or at(5, 28)
  wire(proxy, late)
  storage.late_pole = late
end

local function signal(entity, item)
  local network = entity.get_circuit_network(RED)
  return network and network.get_signal({ type = "item", name = item }) or "no network"
end

local function check_circuits()
  for x = 0, 2 do
    local e = at(x, 28)
    check("circuit " .. (is_proxy(e) and "proxy" or "master") .. " at " .. x .. " reads group", signal(e, "iron-plate") == 500,
      signal(e, "iron-plate"))
  end
  check("double count is 2x", signal(at(0, 33), "copper-plate") == 600, signal(at(0, 33), "copper-plate"))
  check("duplicate readers found", #call("duplicate_readers", at(1, 33)) == 1)
  call("make_sole_reader", at(1, 33))
  check("sole reader", #call("duplicate_readers", at(1, 33)) == 0 and at(0, 33).get_control_behavior().read_contents == false)
  check("no duplicates on separate networks", #call("duplicate_readers", at(1, 28)) == 0)
  storage.sole_checked = true
  local late = storage.late_pole
  local n = late.get_circuit_network(RED)
  check("circuit wire added to proxy later", n and n.get_signal({ type = "item", name = "coal" }) == 200,
    n and n.get_signal({ type = "item", name = "coal" }))
end

-- Quality chests only link with the same quality and count their bigger size.
tests[#tests + 1] = function()
  if not script.active_mods["quality"] then
    log_line("SKIP quality")
    return
  end
  chest("steel-chest", 0, 22, "uncommon"); chest("steel-chest", 1, 22, "uncommon"); chest("steel-chest", 2, 22)
  call("set_link", at(0, 22), 2, true)
  call("set_link", at(1, 22), 2, true)
  local expected = 2 * prototypes.entity["steel-chest"].get_inventory_size(CHEST, "uncommon")
  local group = call("group", at(0, 22))
  check("quality group", #group == 2 and size(master_of(group)) == expected, #group .. " " .. size(master_of(group)) .. "/" .. expected)
end

-- Seam pieces: a linked 2x2 block gets two side, two front and one middle piece; unlinking one side drops the
-- middle piece and that side piece.
local function seam_pieces()
  local found = { side = 0, front = 0, middle = 0 }
  for _, object in pairs(rendering.get_all_objects("expandable-chests")) do
    if object.type == "sprite" then
      local kind = tostring(object.sprite):match("^expandable%-chests%-seam%-(%a+)%-")
      if kind then
        found[kind] = found[kind] + 1
      end
    end
  end
  return found
end

tests[#tests + 1] = function()
  for _, name in pairs({ "wooden-chest", "iron-chest", "steel-chest", "passive-provider-chest", "requester-chest" }) do
    for _, kind in pairs({ "side", "front", "middle" }) do
      check("seam sprite " .. kind .. " " .. name, helpers.is_valid_sprite_path("expandable-chests-seam-" .. kind .. "-" .. name))
    end
  end
  local before = seam_pieces()
  chest("iron-chest", 0, 36); chest("iron-chest", 1, 36); chest("iron-chest", 0, 37); chest("iron-chest", 1, 37)
  call("set_link", at(0, 36), 2, true)
  call("set_link", at(0, 37), 2, true)
  call("set_link", at(0, 36), 4, true)
  call("set_link", at(1, 36), 4, true)
  local after = seam_pieces()
  local diff = (after.side - before.side) .. "/" .. (after.front - before.front) .. "/" .. (after.middle - before.middle)
  check("seam pieces 2x2", diff == "2/2/1", diff)
  call("set_link", at(0, 37), 2, false)
  local split = seam_pieces()
  diff = (split.side - before.side) .. "/" .. (split.front - before.front) .. "/" .. (split.middle - before.middle)
  check("seam pieces after unlink", diff == "1/2/0", diff)
end

script.on_event(defines.events.on_tick, function(event)
  if event.tick == 5 then
    surface, force = game.surfaces[1], game.forces.player
    surface.request_to_generate_chunks({ 0, 0 }, 3)
    surface.force_generate_chunk_requests()
    for _, e in pairs(surface.find_entities_filtered({ area = { { -10, -10 }, { 40, 40 } } })) do
      if e.type ~= "character" then
        e.destroy()
      end
    end
    local tiles = {}
    for x = -10, 40 do
      for y = -10, 40 do
        tiles[#tiles + 1] = { name = "concrete", position = { x, y } }
      end
    end
    surface.set_tiles(tiles)
    for i, test in ipairs(tests) do
      local ok, err = pcall(test)
      if not ok then
        failures = failures + 1
        log_line("FAIL", "test " .. i .. " crashed:", err)
      end
    end
  elseif event.tick == 400 then
    local out = surface.find_entities_filtered({ name = "wooden-chest", area = { { 0, 26 }, { 2, 27 } } })[1]
    check("inserter takes from proxy", out and out.get_item_count("iron-gear-wheel") > 0, out and out.get_item_count("iron-gear-wheel"))
    check_circuits()
  elseif event.tick == 420 then
    check("sole reader counts once", signal(at(1, 33), "copper-plate") == 300, signal(at(1, 33), "copper-plate"))
    log_line("DONE", failures == 0 and "all passed" or (failures .. " failures"))
  end
end)
