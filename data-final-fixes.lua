local shared = require("shared")

-- Same tier, cost and prerequisites as fluid handling, including changes other mods made to it.
local fluid_handling = data.raw.technology["fluid-handling"]
local technology = data.raw.technology[shared.technology]
if fluid_handling then
  technology.prerequisites = table.deepcopy(fluid_handling.prerequisites)
  technology.unit = table.deepcopy(fluid_handling.unit)
  technology.research_trigger = table.deepcopy(fluid_handling.research_trigger)
  if technology.research_trigger then
    technology.unit = nil
  end
end

-- Finds the item that builds the given entity.
local function placing_item(entity)
  if entity.placeable_by then
    local by = entity.placeable_by
    return by.item or (by[1] and by[1].item)
  end
  for _, type in pairs({ "item", "item-with-entity-data" }) do
    for name, item in pairs(data.raw[type] or {}) do
      if item.place_result == entity.name then
        return name
      end
    end
  end
end

local function is_one_tile(entity)
  local box = entity.collision_box
  if not box then
    return false
  end
  local lt, rb = box[1] or box.left_top, box[2] or box.right_bottom
  local x1, y1 = lt[1] or lt.x, lt[2] or lt.y
  local x2, y2 = rb[1] or rb.x, rb[2] or rb.y
  return x2 - x1 < 1 and y2 - y1 < 1
end

-- Turns the first frame of an animation into a sprite.
local function to_sprite(animation)
  if not animation then
    return nil
  end
  local function layer(src)
    local sprite = table.deepcopy(src)
    sprite.frame_count, sprite.line_length, sprite.animation_speed = nil, nil, nil
    sprite.run_mode, sprite.repeat_count, sprite.frame_sequence = nil, nil, nil
    sprite.stripes, sprite.lines_per_file, sprite.slice = nil, nil, nil
    sprite.filenames = nil
    if src.filenames then
      sprite.filename = src.filenames[1]
    end
    return sprite
  end
  if animation.layers then
    local layers = {}
    for _, l in pairs(animation.layers) do
      table.insert(layers, layer(l))
    end
    return { layers = layers }
  end
  return layer(animation)
end

local copied_keys = {
  "icon", "icons", "icon_size", "max_health", "corpse", "dying_explosion", "collision_box", "selection_box",
  "collision_mask", "drawing_box_vertical_extension", "damaged_trigger_effect", "resistances", "circuit_connector",
  "circuit_wire_max_distance", "draw_circuit_wires", "draw_copper_wires", "open_sound", "close_sound",
  "impact_category", "surface_conditions", "heating_energy", "icon_draw_specification", "alert_icon_shift",
  "integration_patch", "integration_patch_render_layer", "quality_indicator_scale", "hit_visualization_box",
  "working_sound", "water_reflection", "map_color", "friendly_map_color", "enemy_map_color", "localised_description", "subgroup", "order",
}

local proxies = {}
for _, type in pairs({ "container", "logistic-container" }) do
  for name, entity in pairs(data.raw[type]) do
    local item = placing_item(entity)
    if item and is_one_tile(entity) and not entity.hidden and name:sub(1, #shared.proxy_prefix) ~= shared.proxy_prefix then
      local proxy = {
        type = "proxy-container",
        name = shared.proxy_prefix .. name,
        localised_name = entity.localised_name or { "entity-name." .. name },
        flags = table.deepcopy(entity.flags),
        hidden = true,
        hidden_in_factoriopedia = true,
        factoriopedia_alternative = name,
        placeable_by = { item = item, count = 1 },
        minable = entity.minable and { mining_time = entity.minable.mining_time, result = item, count = 1 },
        picture = table.deepcopy(entity.picture) or to_sprite(entity.robot_door and entity.robot_door.animation or entity.animation),
        draw_inventory_content = true,
        fast_replaceable_group = entity.fast_replaceable_group,
      }
      for _, key in pairs(copied_keys) do
        if proxy[key] == nil and entity[key] ~= nil then
          proxy[key] = table.deepcopy(entity[key])
        end
      end
      table.insert(proxies, proxy)
    end
  end
end
if #proxies > 0 then
  data:extend(proxies)
end
