-- ~/.config/nvim/lua/plugins/dashboard.lua
-- Custom LazyVim dashboard: colored img2art portrait (left), shortcuts (right),
-- git branch + plugin count in the footer.

return {
  {
    "nvimdev/dashboard-nvim",
    opts = function(_, opts)
      local api = vim.api
      local art = require("dashboard_art")

      local art_ns = api.nvim_create_namespace("dashboard_art")
      local ui_ns = api.nvim_create_namespace("dashboard_shortcuts")

      local GAP = 6 -- columns between the portrait and the shortcut list

      local function put(buf, ns, lnum, scol, ecol, group)
        pcall(api.nvim_buf_set_extmark, buf, ns, lnum, scol, {
          end_col = ecol,
          hl_group = group,
          priority = 5000, -- outrank DashboardHeader's default 4096
        })
      end

      -------------------------------------------------------------------
      -- Portrait highlight groups
      -------------------------------------------------------------------
      -- dashboard_art.lua defines its I2A* groups via nvim_set_hl when required.
      -- `:colorscheme` runs `hi clear`, which wipes them, so re-execute it then.
      local function define_art_hl()
        package.loaded["dashboard_art"] = nil
        require("dashboard_art")
      end

      local function define_ui_hl()
        api.nvim_set_hl(0, "AnahoTitle", { link = "DashboardHeader" })
        api.nvim_set_hl(0, "AnahoFlower1", { fg = "#f38ba8", bold = true })
        api.nvim_set_hl(0, "AnahoFlower2", { fg = "#f9e2af", bold = true })
        api.nvim_set_hl(0, "AnahoVine", { fg = "#a6e3a1" })
      end
      define_ui_hl()

      -- `hi clear` wipes both the I2A* groups and the ones above
      api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          define_art_hl()
          define_ui_hl()
        end,
      })

      -------------------------------------------------------------------
      -- Title: "anaho" with a lei draped over the letters
      -------------------------------------------------------------------
      -- 20 cells wide, and the blossoms sit above the letter centers
      local TITLE = {
        "~❀~·~✿~·~~❀~·~✿~·~❀~",
        "▄▀█ █▄ █ ▄▀█ █ █ █▀█",
        "█▀█ █ ▀█ █▀█ █▀█ █▄█",
      }
      local TITLE_HL = {
        ["▄"] = "AnahoTitle",
        ["▀"] = "AnahoTitle",
        ["█"] = "AnahoTitle",
        ["❀"] = "AnahoFlower1",
        ["✿"] = "AnahoFlower2",
        ["~"] = "AnahoVine",
        ["·"] = "AnahoVine",
      }

      -- byte-offset spans, merging adjacent characters that share a group
      local function segments(text)
        local segs, run, i = {}, nil, 1
        while i <= #text do
          local b = text:byte(i)
          local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
          local group = TITLE_HL[text:sub(i, i + len - 1)]
          if run and group == run[1] and run[3] == i - 1 then
            run[3] = i + len - 1
          else
            if run then
              segs[#segs + 1] = run
            end
            run = group and { group, i - 1, i + len - 1 } or nil
          end
          i = i + len
        end
        if run then
          segs[#segs + 1] = run
        end
        return segs
      end

      -------------------------------------------------------------------
      -- Shortcut column, taken over from dashboard-nvim's `center`
      -------------------------------------------------------------------
      -- dashboard-nvim can only stack `center` *below* the header, so compose
      -- both columns into the header ourselves and render nothing in `center`.
      local items = vim.deepcopy(opts.config.center or {})
      opts.config.center = {}

      local entries, widest = {}, 0
      for _, item in ipairs(items) do
        -- the project.nvim extra right-pads its desc to 43 chars for the stacked
        -- layout; that padding would blow this column open, so drop it
        local icon = item.icon or ""
        local desc = (item.desc:gsub("%s+$", ""))
        local text = icon .. desc
        widest = math.max(widest, api.nvim_strwidth(text))
        table.insert(entries, { item = item, icon = icon, desc = desc, text = text })
      end

      -- title, blank line, then one shortcut per line with a blank spacer
      -- between; the whole block is vertically centered against the art
      local right = {}
      for _, line in ipairs(TITLE) do
        right[#right + 1] = { text = line, title = true, segs = segments(line) }
      end
      right[#right + 1] = false
      right[#right + 1] = false
      for i, e in ipairs(entries) do
        local pad = widest - api.nvim_strwidth(e.text) + 3
        e.text = e.text .. (" "):rep(pad) .. e.item.key
        right[#right + 1] = e
        if i < #entries then
          right[#right + 1] = false -- spacer
        end
      end

      local art_w = 0
      for _, v in ipairs(art.val) do
        art_w = math.max(art_w, api.nvim_strwidth(v))
      end
      local label_w = 0
      for _, r in ipairs(right) do
        if r then
          label_w = math.max(label_w, api.nvim_strwidth(r.text))
        end
      end
      local total_w = art_w + GAP + label_w
      local top = math.floor((#art.val - #right) / 2)

      local shortcuts = {} -- art row index -> right entry
      local header = { "", "" }
      for i = 1, #art.val do
        local line = art.val[i] .. (" "):rep(GAP)
        local r = right[i - top]
        if r then
          line = line .. r.text
          shortcuts[i] = r
        end
        -- center_align() pads each line independently by its own width, so
        -- ragged widths would stagger the portrait's left edge.
        line = line .. (" "):rep(total_w - api.nvim_strwidth(line))
        header[#header + 1] = line
      end
      header[#header + 1] = ""
      opts.config.header = header

      -------------------------------------------------------------------
      -- Painting
      -------------------------------------------------------------------
      -- A blank art row is a run of spaces and would match at column 0 of any
      -- line, so anchor the search on the first row that has visible content.
      local anchor = 1
      for i, v in ipairs(art.val) do
        if v:find("%S") then
          anchor = i
          break
        end
      end

      -- Returns a map of 1-based cursor line -> { item, col }.
      local function paint(buf)
        local total = api.nvim_buf_line_count(buf)
        local start, col0
        for row = 0, total - 1 do
          local l = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
          local s = l and l:find(art.val[anchor], 1, true)
          if s then
            start, col0 = row - (anchor - 1), s - 1
            break
          end
        end
        -- every header line is padded to one width, so center_align() indents
        -- them all equally: the anchor's column is the column of every row
        if not start or start < 0 then
          return nil
        end

        api.nvim_buf_clear_namespace(buf, art_ns, 0, -1)
        api.nvim_buf_clear_namespace(buf, ui_ns, 0, -1)

        local rows = {}
        for i = 1, #art.val do
          local lnum = start + i - 1
          local l = api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1]
          if not l then
            break
          end
          for _, seg in ipairs(art.opts.hl[i]) do
            put(buf, art_ns, lnum, col0 + seg[2], col0 + seg[3], seg[1])
          end

          local r = shortcuts[i]
          if r then
            local base = col0 + #art.val[i] + GAP
            if r.title then
              for _, seg in ipairs(r.segs) do
                put(buf, ui_ns, lnum, base + seg[2], base + seg[3], seg[1])
              end
            else
              local icon, key = r.icon, r.item.key
              local desc_end = base + #icon + #r.desc
              local key_start = base + #r.text - #key
              put(buf, ui_ns, lnum, base, base + #icon, "DashboardIcon")
              put(buf, ui_ns, lnum, base + #icon, desc_end, "DashboardDesc")
              put(buf, ui_ns, lnum, key_start, key_start + #key, "DashboardKey")
              rows[lnum + 1] = { item = r.item, col = base }
            end
          end
        end
        return rows
      end

      -------------------------------------------------------------------
      -- Actions, keys and cursor
      -------------------------------------------------------------------
      local function run(action)
        if type(action) == "string" then
          local fn = loadstring(action)
          if fn then
            fn()
          else
            vim.cmd(action)
          end
        elseif type(action) == "function" then
          action()
        end
      end

      api.nvim_create_autocmd("User", {
        pattern = "DashboardLoaded",
        callback = function()
          local buf = api.nvim_get_current_buf()
          local rows = paint(buf)
          if not rows then
            return
          end

          local order = vim.tbl_keys(rows)
          table.sort(order)

          local idx = 1
          local function place(i)
            idx = math.max(1, math.min(#order, i))
            local lnum = order[idx]
            pcall(api.nvim_win_set_cursor, 0, { lnum, rows[lnum].col })
          end

          local map = function(lhs, fn)
            vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
          end

          -- `center` is empty, so dashboard-nvim never bound these itself
          for _, item in ipairs(items) do
            if item.key then
              vim.keymap.set("n", item.key, function()
                run(item.action)
              end, {
                buffer = buf,
                nowait = true,
                silent = true,
                desc = "Dashboard: " .. vim.trim(item.desc),
              })
            end
          end

          map("<CR>", function()
            local row = rows[api.nvim_win_get_cursor(0)[1]]
            if row then
              run(row.item.action)
            end
          end)
          for _, lhs in ipairs({ "j", "<Down>" }) do
            map(lhs, function()
              place(idx % #order + 1)
            end)
          end
          for _, lhs in ipairs({ "k", "<Up>" }) do
            map(lhs, function()
              place((idx - 2) % #order + 1)
            end)
          end

          vim.defer_fn(function()
            if not api.nvim_buf_is_valid(buf) then
              return
            end
            -- doom's own CursorMoved handler pins the cursor to the band where
            -- `center` used to be, which is now the footer. Take it out.
            pcall(api.nvim_del_augroup_by_name, "DashboardDoomCursor")
            if api.nvim_get_current_buf() == buf then
              place(1)
            end
          end, 30)
        end,
      })

      -------------------------------------------------------------------
      -- Footer: git branch + plugin count
      -------------------------------------------------------------------
      local function git_branch()
        local out = vim.fn.systemlist({ "git", "rev-parse", "--abbrev-ref", "HEAD" })
        if vim.v.shell_error ~= 0 then
          return nil
        end
        local branch = vim.trim(out[1] or "")
        return branch ~= "" and branch or nil
      end

      -- deferred so lazy.stats() has real numbers by the time it runs
      opts.config.footer = function()
        local ok, result = pcall(function()
          local loaded, lazy = pcall(require, "lazy")
          local stats = loaded and lazy.stats() or { loaded = 0, count = 0, startuptime = 0 }
          local ms = math.floor(stats.startuptime * 100 + 0.5) / 100
          local parts = {}
          local branch = git_branch()
          if branch then
            table.insert(parts, " " .. branch)
          end
          table.insert(
            parts,
            ("󰒲 loaded %d/%d plugins in %sms"):format(stats.loaded, stats.count, ms)
          )
          return table.concat(parts, "   ")
        end)
        return { ok and result or ("dashboard error: " .. tostring(result)) }
      end
    end,
  },
}
