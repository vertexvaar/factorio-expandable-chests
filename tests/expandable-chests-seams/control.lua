-- Builds linked and unlinked chest shapes of every chest type and screenshots them (tests/seams.py runs it in a window).
script.on_init(function()
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
end)

local TYPES = {
  "wooden-chest", "iron-chest", "steel-chest", "passive-provider-chest", "active-provider-chest", "storage-chest",
  "buffer-chest", "requester-chest",
}
-- Shapes as lists of cells; every cell is linked to its neighbours in the shape.
local SHAPES = {
  { x = 0, cells = { { 0, 0 }, { 1, 0 } } },
  { x = 3, cells = { { 0, 0 }, { 0, 1 } } },
  { x = 5, cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } },
  { x = 8, cells = { { 0, 0 }, { 0, 1 }, { 1, 1 } } },
  { x = 11, cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } } },
}
local BAND = 9

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
  helpers.write_file("ec-seams/report.txt", table.concat(parts, " ") .. "\n", true)
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
    local area = { { -10, -10 }, { 30, #TYPES * BAND + 10 } }
    for _, e in pairs(surface.find_entities_filtered({ area = area })) do
      if e.type ~= "character" then
        e.destroy()
      end
    end
    local tiles = {}
    for x = -10, 29 do
      for y = -10, #TYPES * BAND + 9 do
        tiles[#tiles + 1] = { name = "refined-concrete", position = { x, y } }
      end
    end
    surface.set_tiles(tiles)
    surface.destroy_decoratives({ area = area })
    player.character.teleport({ -8, -8 })
    player.force.technologies["expandable-chests"].researched = true
    for i, name in pairs(TYPES) do
      local y0 = (i - 1) * BAND
      for row, linked in pairs({ true, false }) do
        local oy = y0 + (row - 1) * 4
        for _, shape in pairs(SHAPES) do
          local set = {}
          for _, c in pairs(shape.cells) do
            surface.create_entity({ name = name, position = { shape.x + c[1] + 0.5, oy + c[2] + 0.5 }, force = player.force, raise_built = true })
            set[c[1] .. "," .. c[2]] = true
          end
          if linked then
            for _, c in pairs(shape.cells) do
              if set[(c[1] + 1) .. "," .. c[2]] then
                remote.call("expandable-chests", "set_link", at(surface, shape.x + c[1], oy + c[2]), 2, true)
              end
              if set[c[1] .. "," .. (c[2] + 1)] then
                remote.call("expandable-chests", "set_link", at(surface, shape.x + c[1], oy + c[2]), 3, true)
              end
            end
          end
        end
        -- Working inserters beside the 3x3 block: one fills it from the L shape, one empties it to the ground.
        if linked then
          at(surface, 8, oy + 1).insert({ name = "coal", count = 50 })
          at(surface, 11, oy).insert({ name = "iron-plate", count = 100 })
          for _, spec in pairs({ { 10.5, oy + 1.5, defines.direction.west }, { 12.5, oy + 3.5, defines.direction.north } }) do
            local inserter = surface.create_entity({ name = "burner-inserter", position = { spec[1], spec[2] }, direction = spec[3], force = player.force })
            inserter.get_fuel_inventory().insert({ name = "coal", count = 5 })
          end
        end
      end
    end
  elseif event.tick == scene_tick + 30 then
    for i, name in pairs(TYPES) do
      local y0 = (i - 1) * BAND
      game.take_screenshot({
        player = player,
        position = { 7, y0 + 3.5 },
        resolution = { 1088, 576 },
        zoom = 2,
        path = "ec-seams/" .. name .. ".png",
        show_entity_info = false,
        force_render = true,
        daytime = 0,
      })
      -- Close-ups of the 2x2 and L shapes and the 3x3 block at twice the sprite resolution.
      for _, close in pairs({ { "2x2", 6, 1 }, { "l", 9, 1 }, { "3x3", 12.5, 1.5 } }) do
        game.take_screenshot({
          player = player,
          position = { close[2], y0 + close[3] },
          resolution = close[1] == "3x3" and { 896, 896 } or { 640, 640 },
          zoom = 4,
          path = "ec-seams/close/" .. name .. "-" .. close[1] .. ".png",
          show_entity_info = false,
          force_render = true,
          daytime = 0,
        })
      end
    end
  elseif event.tick > scene_tick + 30 and event.tick <= scene_tick + 150 and event.tick % 8 == 0 then
    for _, name in pairs({ "iron-chest", "requester-chest" }) do
      local y0 = (#TYPES - 1) * BAND
      for i, n in pairs(TYPES) do
        if n == name then
          y0 = (i - 1) * BAND
        end
      end
      game.take_screenshot({
        player = player,
        position = { 11.5, y0 + 2 },
        resolution = { 384, 320 },
        zoom = 2,
        path = "ec-seams/inserter/" .. name .. "-" .. (event.tick - scene_tick) .. ".png",
        force_render = true,
        daytime = 0,
      })
    end
  elseif event.tick == scene_tick + 160 then
    report("DONE")
  end
end)
