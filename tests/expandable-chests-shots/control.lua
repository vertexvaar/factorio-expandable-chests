-- Builds a scene, opens a linked chest for the player and takes screenshots (tests/shots.py runs it in a window).
local CHEST = defines.inventory.chest

script.on_init(function()
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
end)

local function at(surface, x, y)
  return surface.find_entities_filtered({
    area = { { x + 0.4, y + 0.4 }, { x + 0.6, y + 0.6 } },
    type = { "container", "logistic-container", "proxy-container" },
    limit = 1,
  })[1]
end

local function report(...)
  local parts = {}
  for i, v in ipairs({ ... }) do
    parts[i] = tostring(v)
  end
  helpers.write_file("ec-shots/report.txt", table.concat(parts, " ") .. "\n", true)
end

local function shot(player, name, gui, alt)
  game.take_screenshot({
    player = player,
    position = { 3, 2 },
    resolution = { 1920, 1080 },
    zoom = 1.6,
    path = "ec-shots/" .. name .. ".png",
    show_gui = gui,
    show_entity_info = alt,
    force_render = true,
    daytime = 0,
  })
end

local scene_tick
script.on_event(defines.events.on_tick, function(event)
  local player = game.get_player(1)
  if not player then
    return
  end
  local surface = player.surface
  if not scene_tick then
    scene_tick = event.tick
    surface.always_day = true
    local area = { { -20, -20 }, { 30, 30 } }
    for _, e in pairs(surface.find_entities_filtered({ area = area })) do
      if e.type ~= "character" then
        e.destroy()
      end
    end
    local tiles = {}
    for x = -20, 29 do
      for y = -20, 29 do
        tiles[#tiles + 1] = { name = "refined-concrete", position = { x, y } }
      end
    end
    surface.set_tiles(tiles)
    player.character.teleport({ 3, 6 })
    player.force.technologies["expandable-chests"].researched = true

    local function chest(name, x, y)
      return surface.create_entity({ name = name, position = { x + 0.5, y + 0.5 }, force = player.force, raise_built = true })
    end
    -- Row 0: O - O - O of steel chests, linked; then an unlinked steel chest.
    for x = 0, 4 do
      chest("steel-chest", x, 0)
    end
    remote.call("expandable-chests", "set_link", at(surface, 0, 0), 2, true)
    remote.call("expandable-chests", "set_link", at(surface, 1, 0), 2, true)
    remote.call("expandable-chests", "set_link", at(surface, 2, 0), 3, true)
    chest("steel-chest", 2, 1)
    remote.call("expandable-chests", "set_link", at(surface, 2, 0), 3, true)
    local pole = surface.create_entity({ name = "medium-electric-pole", position = { 1.5, -1.5 }, force = player.force })
    for x = 0, 1 do
      at(surface, x, 0).get_wire_connector(defines.wire_connector_id.circuit_red, true)
        .connect_to(pole.get_wire_connector(defines.wire_connector_id.circuit_red, true))
    end
    at(surface, 0, 0).insert({ name = "iron-plate", count = 5000 })
    at(surface, 0, 0).insert({ name = "copper-plate", count = 3000 })
    -- Row 3: requester chests and iron chests.
    for x = 0, 2 do
      chest("requester-chest", x, 3)
      chest("iron-chest", x + 4, 3)
    end
    remote.call("expandable-chests", "set_link", at(surface, 0, 3), 2, true)
    remote.call("expandable-chests", "set_link", at(surface, 4, 3), 2, true)
    remote.call("expandable-chests", "set_link", at(surface, 5, 3), 2, true)
    at(surface, 4, 3).insert({ name = "coal", count = 1000 })
  elseif event.tick == scene_tick + 30 then
    local proxy = at(surface, 1, 0)
    report("opening", proxy.name, "size via proxy", #proxy.get_inventory(CHEST))
    player.opened = proxy
    report("opened", tostring(player.opened and player.opened.name), "gui_type", player.opened_gui_type)
    report("panel", tostring(player.gui.relative["expandable-chests"] ~= nil))
  elseif event.tick == scene_tick + 40 then
    shot(player, "1-proxy-window", true, false)
  elseif event.tick == scene_tick + 50 then
    -- Unlink the east side of the middle chest from the GUI.
    report("click east", remote.call("expandable-chests", "click_side", player.index, 2))
    report("after click opened", tostring(player.opened and player.opened.name), "panel",
      tostring(player.gui.relative["expandable-chests"] ~= nil))
  elseif event.tick == scene_tick + 60 then
    shot(player, "2-after-unlink", true, false)
  elseif event.tick == scene_tick + 70 then
    player.opened = at(surface, 3, 0)
    report("opened real", tostring(player.opened and player.opened.name), "panel",
      tostring(player.gui.relative["expandable-chests"] ~= nil))
  elseif event.tick == scene_tick + 80 then
    shot(player, "3-real-window", true, false)
  elseif event.tick == scene_tick + 90 then
    report("requester clicked", at(surface, 1, 3).name)
    player.opened = at(surface, 1, 3)
    report("requester window", tostring(player.opened and player.opened.name), "panel",
      tostring(player.gui.relative["expandable-chests"] ~= nil))
  elseif event.tick == scene_tick + 100 then
    shot(player, "4-requester-window", true, false)
  elseif event.tick == scene_tick + 110 then
    player.opened = nil
    shot(player, "5-alt-mode", false, true)
  elseif event.tick == scene_tick + 120 then
    report("done")
  end
end)
