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
-- All values are in tiles relative to the chest centre and were measured on the 2.1 sprites:
--   inner  inner edges of the lid frame; side pieces span from the right edge to the left edge of the chest to the
--          east, front pieces from the bottom edge to the top edge of the chest to the south
--   side   columns copied at full height over a side seam, clear of locks, doors and bolts
--   lid    rows of the lid that are stretched over a front seam
--   fill   columns of those rows repeated across the inside of the lid (defaults to side)
local default_layout = {
  inner = { left = -0.33, top = -0.51, right = 0.31, bottom = -0.17 },
  side = { 0.19, 0.31 },
  lid = { -0.51, -0.17 },
}
local logistic_layout = {
  inner = { left = -0.39, top = -0.6, right = 0.36, bottom = -0.2 },
  side = { 0.22, 0.36 },
  lid = { -0.53, -0.33 },
  fill = { 0.235, 0.28 },
}
local layouts = {
  ["wooden-chest"] = {
    inner = { left = -0.33, top = -0.49, right = 0.38, bottom = -0.1 },
    side = { 0, 0.29 },
    lid = { -0.485, -0.1 },
    fill = { -0.33, 0.38 },
  },
  ["iron-chest"] = default_layout,
  ["steel-chest"] = {
    inner = { left = -0.4, top = -0.48, right = 0.34, bottom = -0.09 },
    side = { 0.1, 0.33 },
    lid = { -0.47, -0.1 },
    fill = { -0.4, 0.34 },
  },
  ["passive-provider-chest"] = logistic_layout,
  ["active-provider-chest"] = logistic_layout,
  ["storage-chest"] = logistic_layout,
  ["buffer-chest"] = logistic_layout,
  ["requester-chest"] = logistic_layout,
}

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
    local inner = layout.inner
    local scale = layer.scale or 1
    local px = 32 / scale -- source pixels per tile
    local sx, sy = to_xy(layer.shift)
    local x0, y0 = to_xy({ layer.x, layer.y })
    local left, top = sx - width / px / 2, sy - height / px / 2

    -- Converts a span in tiles into whole source pixels inside the frame: first pixel, pixel count, centre in tiles.
    local function span(from, to, origin, size)
      local a = math.max(0, math.floor((from - origin) * px + 0.5))
      local b = math.min(size, math.floor((to - origin) * px + 0.5))
      return a, b - a, origin + (a + b) / 2 / px
    end
    local function part(cx, cw, cy, ch, shift)
      return {
        filename = layer.filename,
        x = x0 + cx,
        y = y0 + cy,
        width = cw,
        height = ch,
        scale = scale,
        shift = shift,
        priority = "medium",
      }
    end

    local bx, bw = span(layout.side[1], layout.side[2], left, width)
    local by, bh, body_y = span(top, 0.5, top, height) -- not below the own tile, where an unlinked chest may stand
    local ly, lh = span(layout.lid[1], layout.lid[2], top, height)
    local fill = layout.fill or layout.side
    local fx, fw = span(fill[1], fill[2], left, width)
    if bw > 0 and bh > 0 and lh > 0 and fw > 0 then
      local side = part(bx, bw, by, bh)
      side.type, side.name = "sprite", "expandable-chests-seam-side-" .. base
      table.insert(seam_sprites, side)

      -- Front: the lid rows with the lid frame on both sides and the fill repeated in between. Where the chest to the
      -- west or east has a front piece too, that side has no frame and the fill runs up to the seam instead.
      local el, ew, ec = span(left, inner.left, left, width)
      local er, erw, erc = span(inner.right, left + width / px, left, width)
      local fronts = {}
      for _, open in pairs({ "", "w", "e", "we" }) do
        local layers = {}
        local from = open:find("w") and math.floor((-0.5 - left) * px + 0.5) or el + ew
        local to = open:find("e") and math.floor((0.5 - left) * px + 0.5) or er
        local x = from
        while x < to do
          local at = math.min(x, to - fw)
          layers[#layers + 1] = part(fx, fw, ly, lh, { left + (at + fw / 2) / px, 0 })
          x = x + fw
        end
        if not open:find("w") then
          layers[#layers + 1] = part(el, ew, ly, lh, { ec, 0 })
        end
        if not open:find("e") then
          layers[#layers + 1] = part(er, erw, ly, lh, { erc, 0 })
        end
        local name = "expandable-chests-seam-front-" .. (open == "" and "" or open .. "-") .. base
        table.insert(seam_sprites, { type = "sprite", name = name, layers = layers })
        fronts[open] = name
      end

      -- Offsets from the northern or western chest.
      seams[base] = {
        side = {
          sprite = side.name,
          offset = { (inner.right + 1 + inner.left) / 2, body_y },
          x_scale = (1 + inner.left - inner.right) / (bw / px),
        },
        front = {
          sprites = fronts,
          offset = { 0, (inner.bottom + 1 + inner.top) / 2 },
          y_scale = (1 + inner.top - inner.bottom) / (lh / px),
        },
      }
    end
  end
end
if #seam_sprites > 0 then
  data:extend(seam_sprites)
end
data:extend({ { type = "mod-data", name = shared.seams, data = seams } })
