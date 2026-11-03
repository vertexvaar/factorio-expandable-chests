local shared = require("shared")

data:extend({
  {
    type = "technology",
    name = shared.technology,
    icons = {
      { icon = "__base__/graphics/technology/steel-processing.png", icon_size = 256, tint = { 0, 0, 0, 0 } },
      { icon = "__base__/graphics/icons/steel-chest.png", icon_size = 64, scale = 1.2, shift = { -36, 0 } },
      { icon = "__base__/graphics/icons/steel-chest.png", icon_size = 64, scale = 1.2, shift = { 36, 0 } },
    },
    effects = {
      { type = "nothing", effect_description = { "modifier-description.expandable-chests" }, icon = "__base__/graphics/icons/steel-chest.png", icon_size = 64 },
    },
    -- Prerequisites and cost are copied from fluid handling in data-final-fixes.
    prerequisites = { "automation-2", "engine" },
    unit = { count = 50, ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } }, time = 15 },
  },
})

-- Quick link tool: drag over chests to link all neighbours of the same type, shift-drag to cut them off. The shortcut
-- and the (unbound) control both put it in the cursor.
local tool_icon = "__base__/graphics/icons/steel-chest.png"
local chest_types = { "container", "logistic-container", "proxy-container" }
data:extend({
  {
    type = "selection-tool",
    name = shared.tool,
    icon = tool_icon,
    icon_size = 64,
    subgroup = "tool",
    order = "c[automated-construction]-z[expandable-chests]",
    stack_size = 1,
    flags = { "only-in-cursor", "spawnable", "not-stackable" },
    hidden_in_factoriopedia = true,
    draw_label_for_cursor_render = true,
    select = {
      border_color = { 0.2, 0.9, 0.3 },
      cursor_box_type = "entity",
      mode = { "any-entity", "same-force" },
      entity_type_filters = chest_types,
    },
    alt_select = {
      border_color = { 0.9, 0.3, 0.2 },
      cursor_box_type = "not-allowed",
      mode = { "any-entity", "same-force" },
      entity_type_filters = chest_types,
    },
  },
  {
    type = "custom-input",
    name = shared.tool_input,
    key_sequence = "",
    action = "spawn-item",
    item_to_spawn = shared.tool,
    consuming = "game-only",
  },
  {
    type = "shortcut",
    name = shared.tool,
    order = "b[blueprints]-z[expandable-chests]",
    action = "spawn-item",
    item_to_spawn = shared.tool,
    associated_control_input = shared.tool_input,
    technology_to_unlock = shared.technology,
    unavailable_until_unlocked = true,
    icon = tool_icon,
    icon_size = 64,
    small_icon = tool_icon,
    small_icon_size = 64,
  },
})
