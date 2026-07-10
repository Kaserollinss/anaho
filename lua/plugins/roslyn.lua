-- C# / Razor via the Roslyn language server.
--
-- Not LazyVim's `lang.dotnet` extra: that one configures omnisharp, which is in
-- maintenance mode and has no Razor support. roslyn.nvim also supersedes the
-- discontinued rzls.nvim, handling Razor itself via co-hosting.
--
-- Requires the server binary. Either:
--   :MasonInstall roslyn                       (uses the extra registry below)
--   dotnet tool install -g roslyn-language-server --prerelease \
--     --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
-- The dotnet tool currently targets net10.0, so it needs a .NET 10 SDK; the
-- mason build targets net8.0 with rollForward, so it runs on .NET 9.

return {
  -- roslyn is not in the default mason registry
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.registries = opts.registries or { "github:mason-org/mason-registry" }
      if not vim.tbl_contains(opts.registries, "github:Crashdummyy/mason-registry") then
        table.insert(opts.registries, "github:Crashdummyy/mason-registry")
      end
    end,
  },

  {
    "seblyng/roslyn.nvim",
    ft = { "cs", "razor" },
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {},
    init = function()
      -- The server targets net10.0, but /usr/local/share/dotnet only has 6/7/9
      -- and is root-owned. .NET 10 lives in ~/.dotnet; point just this process
      -- at it so the system `dotnet` keeps resolving to /usr/local.
      local root = vim.fn.expand("~/.dotnet")
      if vim.fn.isdirectory(root .. "/shared/Microsoft.NETCore.App") == 1 then
        vim.lsp.config("roslyn", { cmd_env = { DOTNET_ROOT = root } })
      end
    end,
  },

  -- LazyVim marks ensure_installed as opts_extend, so this appends
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "c_sharp", "razor" } },
  },
}
