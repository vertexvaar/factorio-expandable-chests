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
