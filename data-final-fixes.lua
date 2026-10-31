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

-- Overlays --------------------------------------------------------------------------------------------------------
-- Every linked chest gets an overlay (control.lua) that redraws its sprite so that a group looks like one big chest:
-- towards a linked neighbour the frame is cut off and the lid or the front runs on up to the tile edge, built from
-- quiet strips of the same sprite that are repeated rather than stretched. There is one overlay per combination of
-- linked sides. Values are pixels of the sprite frame and were measured on the 2.1 sprites:
--   top, bottom  rows where the lid starts and ends; above is the back edge, below the front
--   x            columns where the left and right frame end; front_x for the front if it differs
--   back, lid,   columns repeated where the back edge, the lid or the front runs on sideways; without lid the
--   front        patch is used
--   rows         rows repeated where the chest runs on to the north or south: the side frames and, unless
--                patch_middle is set, the lid between them
--   patch        a quiet piece of the lid { x, y, width, height }, repeated wherever only lid is left
--   keep         optional box { x1, y1, x2, y2 } of the lock or door; the lid around it is rebuilt as well
-- Repeats are anchored at the tile edges, so neighbouring chests continue each other without a seam.
local logistic_layout = {
  top = 5, bottom = 28, x = { 9, 56 }, front_x = { 14, 54 }, back = { 26, 30 }, front = { 26, 30 },
  rows = { 20, 28 }, patch = { 44, 2, 4, 4 }, patch_middle = true, keep = { 18, 4, 49, 28 },
}
local layouts = {
  ["wooden-chest"] = {
    top = 9, bottom = 34, x = { 9, 55 }, back = { 20, 28 }, lid = { 36, 40 }, front = { 20, 28 }, rows = { 10, 18 },
    patch = { 36, 10, 4, 8 },
  },
  ["iron-chest"] = {
    top = 8, bottom = 29, x = { 13, 54 }, back = { 15, 23 }, lid = { 16, 20 }, front = { 15, 23 }, rows = { 7, 15 },
    patch = { 16, 7, 4, 8 }, patch_middle = true, keep = { 23, 17, 46, 30 },
  },
  ["steel-chest"] = {
    top = 9, bottom = 33, x = { 9, 56 }, back = { 12, 20 }, lid = { 19, 28 }, front = { 12, 20 }, rows = { 17, 21 },
    patch = { 19, 17, 9, 4 },
  },
  ["passive-provider-chest"] = logistic_layout,
  ["active-provider-chest"] = logistic_layout,
  ["storage-chest"] = logistic_layout,
  ["buffer-chest"] = logistic_layout,
  ["requester-chest"] = logistic_layout,
}
-- Chests of other mods get the iron chest layout scaled to their sprite.
local default_layout, default_size = layouts["iron-chest"], { 66, 76 }

local function scaled_layout(width, height)
  local function sx(v) return math.floor(v * width / default_size[1] + 0.5) end
  local function sy(v) return math.floor(v * height / default_size[2] + 0.5) end
  local d = default_layout
  return {
    top = sy(d.top), bottom = sy(d.bottom), x = { sx(d.x[1]), sx(d.x[2]) },
    back = { sx(d.back[1]), sx(d.back[2]) }, lid = { sx(d.lid[1]), sx(d.lid[2]) },
    front = { sx(d.front[1]), sx(d.front[2]) },
    rows = { sy(d.rows[1]), sy(d.rows[2]) }, patch = { sx(d.patch[1]), sy(d.patch[2]), d.patch[3], d.patch[4] },
  }
end

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

local overlay_sprites = {}
local overlays = {}
for _, proxy in pairs(proxies) do
  local base = proxy.name:sub(#shared.proxy_prefix + 1)
  local layer = main_layer(proxy.picture)
  local width, height = layer and (layer.width or layer.size), layer and (layer.height or layer.size)
  if type(width) == "table" then
    width, height = width[1], width[2]
  end
  if layer and width and height then
    local layout = layouts[base] or scaled_layout(width, height)
    local scale = layer.scale or 1
    local px = 32 / scale -- source pixels per tile
    local sx, sy = to_xy(layer.shift)
    local x0, y0 = to_xy({ layer.x, layer.y })
    -- Tile edges in frame pixels, rounded outwards so that neighbours overlap rather than leave a gap.
    local tl = math.floor(width / 2 - (0.5 + sx) * px)
    local tt = math.floor(height / 2 - (0.5 + sy) * px)
    local tr, tb = math.ceil(width / 2 + (0.5 - sx) * px), math.ceil(height / 2 + (0.5 - sy) * px)

    -- Copies the source rectangle (frame pixels) to the given place in the frame.
    local function part(layers, x, y, w, h, to_x, to_y)
      layers[#layers + 1] = {
        filename = layer.filename,
        x = x0 + x,
        y = y0 + y,
        width = w,
        height = h,
        scale = scale,
        shift = { sx + (to_x + w / 2 - width / 2) / px, sy + (to_y + h / 2 - height / 2) / px },
        priority = "medium",
      }
    end
    -- Fills the area x1..x2, y1..y2 with copies of the source rectangle, laid out on a grid that starts at ax, ay.
    local function repeat_part(layers, src, x1, y1, x2, y2, ax, ay)
      local w, h = src[3], src[4]
      local y = ay + math.floor((y1 - ay) / h) * h
      while y < y2 do
        local top, bottom = math.max(y, y1), math.min(y + h, y2)
        local x = ax + math.floor((x1 - ax) / w) * w
        while x < x2 do
          local left, right = math.max(x, x1), math.min(x + w, x2)
          if right > left and bottom > top then
            part(layers, src[1] + left - x, src[2] + top - y, right - left, bottom - top, left, top)
          end
          x = x + w
        end
        y = y + h
      end
    end

    -- Builds the overlay for the given linked sides. Without `door` the middle of the lid is left out where nothing
    -- needs covering, so the animated robot door of a logistic chest shows through.
    local function build(n, e, s, w, door)
      local layers = {}
      local rows = {}
      if not n then
        rows[#rows + 1] = { 0, layout.top, "back" }
      elseif layout.top > tt then
        rows[#rows + 1] = { tt, layout.top, "fill" }
      end
      rows[#rows + 1] = { layout.top, layout.bottom, "lid" }
      if s then
        rows[#rows + 1] = { layout.bottom, tb, "fill" }
      else
        rows[#rows + 1] = { layout.bottom, height, "front" }
      end
      local patch = layout.patch
      for _, row in pairs(rows) do
        local y1, y2, kind = row[1], row[2], row[3]
        local split = kind == "front" and layout.front_x or layout.x
        local segments = {
          { w and tl or 0, split[1], w },
          { split[1], split[2], false, true },
          { split[2], e and tr or width, e },
        }
        for _, seg in pairs(segments) do
          local x1, x2, linked, middle = seg[1], seg[2], seg[3], seg[4]
          if x2 > x1 and y2 > y1 then
            if kind == "fill" then
              if linked or (middle and layout.patch_middle) then
                repeat_part(layers, patch, x1, y1, x2, y2, tl, tt)
              else
                repeat_part(layers, { x1, layout.rows[1], x2 - x1, layout.rows[2] - layout.rows[1] }, x1, y1, x2, y2, x1, tt)
              end
            elseif linked then
              if kind == "lid" and not layout.lid then
                repeat_part(layers, patch, x1, y1, x2, y2, tl, tt)
              else
                local cols = layout[kind]
                repeat_part(layers, { cols[1], y1, cols[2] - cols[1], y2 - y1 }, x1, y1, x2, y2, tl, y1)
              end
            elseif kind == "lid" and middle and layout.keep then
              -- Only the lock or door is kept, the lid around it is rebuilt so that it matches the filled parts.
              local k = layout.keep
              local ky1, ky2 = math.max(k[2], y1), math.min(k[4], y2)
              for _, r in pairs({
                { x1, y1, x2, ky1 }, { x1, ky2, x2, y2 }, { x1, ky1, k[1], ky2 }, { k[3], ky1, x2, ky2 },
              }) do
                if r[3] > r[1] and r[4] > r[2] then
                  if layout.lid then
                    repeat_part(layers, { layout.lid[1], r[2], layout.lid[2] - layout.lid[1], r[4] - r[2] }, r[1], r[2], r[3], r[4], tl, r[2])
                  else
                    repeat_part(layers, patch, r[1], r[2], r[3], r[4], tl, tt)
                  end
                end
              end
              if n or door then
                part(layers, k[1], ky1, k[3] - k[1], ky2 - ky1, k[1], ky1)
              end
            elseif not (kind == "lid" and middle and not n and not door) then
              part(layers, x1, y1, x2 - x1, y2 - y1, x1, y1)
            end
          end
        end
      end
      return layers
    end

    local with_door = data.raw["logistic-container"][base] ~= nil
    for mask = 1, 15 do
      local n, e, s, w = mask % 2 == 1, math.floor(mask / 2) % 2 == 1, math.floor(mask / 4) % 2 == 1, mask >= 8
      local name = "expandable-chests-overlay-" .. base .. "-" .. mask
      table.insert(overlay_sprites, { type = "sprite", name = name, layers = build(n, e, s, w, true) })
      if with_door and not n then
        table.insert(overlay_sprites, { type = "sprite", name = name .. "-door", layers = build(n, e, s, w, false) })
      end
    end
    overlays[base] = { door = with_door }
  end
end
if #overlay_sprites > 0 then
  data:extend(overlay_sprites)
end
data:extend({ { type = "mod-data", name = shared.seams, data = overlays } })
