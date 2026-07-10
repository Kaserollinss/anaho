return {
  {
    "folke/tokyonight.nvim",
    opts = {
      -- Don't paint a background; let kitty's background_opacity show through.
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },
}
