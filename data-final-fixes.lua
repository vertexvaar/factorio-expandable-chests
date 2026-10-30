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

-- Seam pieces -----------------------------------------------------------------------------------------------------
-- Linked chests get pieces of their own sprite drawn over the seams (control.lua), so a group looks like one big chest.
-- Areas are in tiles relative to the chest centre and were measured on the 2.1 chests. Each chest may override them.
local default_layout = {
  body = { -0.31, -0.06 },     -- columns of the body copied over a side seam (left of the lock)
  lid = { -0.41, -0.16 },      -- rows of the lid that are stretched over a front seam
  front = -0.05,               -- where the front face starts
  rim = 0.47,                  -- lower edge of the rim of the chest to the south, relative to the northern chest
}
local layouts = {}

local function to_xy(v)
  if not v then
    return 0, 0
  end
  return v[1] or v.x or 0, v[2] or v.y or 0
end

-- The first layer that is drawn as the chest itself.
local function main_layer(sprite)
  if not sprite then
    return nil
  end
  if sprite.layers then
    for _, layer in pairs(sprite.layers) do
      local found = main_layer(layer)
      if found then
        return found
      end
    end
    return nil
  end
  if sprite.draw_as_shadow or sprite.draw_as_glow or sprite.draw_as_light or not sprite.filename then
    return nil
  end
  return sprite
end

local seam_sprites = {}
local seams = {}
for _, proxy in pairs(proxies) do
  local base = proxy.name:sub(#shared.proxy_prefix + 1)
  local layer = main_layer(proxy.picture)
  local width, height = layer and (layer.width or layer.size), layer and (layer.height or layer.size)
  if type(width) == "table" then
    width, height = width[1], width[2]
  end
  if layer and width and height then
    local layout = layouts[base] or default_layout
    local scale = layer.scale or 1
    local px = 32 / scale -- source pixels per tile
    local sx, sy = to_xy(layer.shift)
    local x0, y0 = to_xy({ layer.x, layer.y })
    local left, top = sx - width / px / 2, sy - height / px / 2

    -- Converts a span in tiles into whole source pixels inside the frame and back.
    local function span(from, to, origin, size)
      local a = math.max(0, math.floor((from - origin) * px + 0.5))
      local b = math.min(size, math.floor((to - origin) * px + 0.5))
      return a, b - a, origin + (a + b) / 2 / px, (b - a) / px
    end
    local function piece(name, cx, cw, cy, ch)
      seam_sprites[#seam_sprites + 1] = {
        type = "sprite",
        name = name,
        filename = layer.filename,
        x = x0 + cx,
        y = y0 + cy,
        width = cw,
        height = ch,
        scale = scale,
        priority = "medium",
      }
    end

    local bx, bw = span(layout.body[1], layout.body[2], left, width)
    local ly, lh, _, lid = span(layout.lid[1], layout.lid[2], top, height)
    if bw > 0 and lh > 0 then
      local stretch = (layout.rim - layout.front) / lid
      local seam_y = (layout.front + layout.rim) / 2
      local names = {
        side = "expandable-chests-seam-side-" .. base,
        front = "expandable-chests-seam-front-" .. base,
        middle = "expandable-chests-seam-middle-" .. base,
      }
      piece(names.side, bx, bw, 0, height)
      piece(names.front, 0, width, ly, lh)
      piece(names.middle, bx, bw, ly, lh)
      -- Offsets from the northern or western chest, so that the piece sits centred on the seam.
      seams[base] = {
        side = { sprite = names.side, offset = { 0.5, sy } },
        front = { sprite = names.front, offset = { sx, seam_y }, y_scale = stretch },
        middle = { sprite = names.middle, offset = { 0.5, seam_y }, y_scale = stretch },
      }
    end
  end
end
if #seam_sprites > 0 then
  data:extend(seam_sprites)
end
data:extend({ { type = "mod-data", name = shared.seams, data = seams } })
