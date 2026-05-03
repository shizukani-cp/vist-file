---@alias Vist.Adapters.File.Action.Kind "create" | "delete" | "rename"

local M = { protocol = "vist-file://", cache = {}, pending_path = nil }

local devicons = require("nvim-web-devicons")

local function dirname_from_bufname(bufnr)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname:find(M.protocol, 1, true) == 1 then
        return bufname:sub(#M.protocol + 1)
    end
    return nil
end

local function get_cwd()
    if M.pending_path then
        return M.pending_path
    end
    local from_bufname = dirname_from_bufname(0)
    if from_bufname then
        return from_bufname
    end
    local bufname = vim.api.nvim_buf_get_name(0)
    local buftype = vim.bo.buftype
    if buftype == "" and bufname ~= "" then
        return vim.fn.fnamemodify(bufname, ":p:h")
    end
    return vim.fn.getcwd()
end

function M.bufname()
    return M.protocol .. get_cwd()
end

function M.filetype()
    return "vist-file"
end

function M.list()
    local cwd = get_cwd()
    if not cwd then
        return
    end
    local files = vim.fn.readdir(cwd)
    table.sort(files)
    local items = { directory = {}, file = {}, all = {} }
    M.cache = {}

    for _, name in ipairs(files) do
        local ext = name:match("%.([^%.]+)$")
        local full_path = vim.fs.joinpath(cwd, name)
        local real_path = vim.uv.fs_realpath(full_path) or full_path
        local stat = vim.uv.fs_stat(real_path)
        ---@type any
        local id = stat and stat.ino or nil
        if not id then
            vim.notify("Failed to stat", vim.log.levels.ERROR)
            id = full_path
        end
        local icon, hl = devicons.get_icon(name, ext, { default = true })
        local display_name = name
        local item = { id = tostring(id), display = display_name, icon = icon, icon_hl = hl }
        if vim.fn.isdirectory(real_path) == 1 then
            item.display = name .. "/"
            item.icon = ""
            item.icon_hl = "Directory"
            table.insert(items.directory, item)
        else
            table.insert(items.file, item)
        end
        M.cache[id] = name
    end
    vim.list_extend(items.all, items.directory)
    vim.list_extend(items.all, items.file)
    return items.all
end

function M.parse(state)
    ---@type Vist.Action<Vist.Adapters.File.Action.Kind>
    local actions = {}
    local current_ids = {}
    local seen_ids = {}

    for _, item in ipairs(state) do
        if item.id then
            local id = tonumber(item.id)
            if not id then
                vim.notify("Invaild ID: " .. item.id, vim.log.levels.ERROR)
                return
            end
            current_ids[id] = true
            local current_text = item.text:gsub("/$", "")
            local old_name = M.cache[id]
            if not seen_ids[id] then
                if old_name and old_name ~= current_text then
                    table.insert(actions, {
                        kind = "rename",
                        data = { old = old_name, new = current_text },
                    })
                end
                seen_ids[id] = true
                current_ids[id] = true
            else
                table.insert(actions, {
                    kind = "copy",
                    data = { src = old_name, dest = current_text },
                })
            end
        else
            if item.text ~= "" then
                table.insert(actions, { kind = "create", data = { name = item.text } })
            end
        end
    end

    for id, name in pairs(M.cache) do
        if not current_ids[id] then
            table.insert(actions, { kind = "delete", data = { name = name } })
        end
    end

    table.sort(actions, function(a, b)
        local priority = { copy = 1, create = 2, rename = 3, delete = 4 }
        return priority[a.kind] < priority[b.kind]
    end)

    return actions
end

local function smart_delete(path)
    local uv = vim.uv
    local stat = uv.fs_stat(path)
    if not stat then
        return
    end

    local ok, err
    if stat.type == "directory" then
        ok, err = pcall(function()
            vim.fn.delete(path, "rf")
        end)
    else
        ok, err = uv.fs_unlink(path)
    end

    if not ok or (type(ok) == "number" and ok ~= 0) then
        vim.notify((err or "Unknown Error"), vim.log.levels.ERROR)
    end
end

local function smart_rename(old_p, new_p)
    local uv = vim.uv
    local ok, err, err_name = uv.fs_rename(old_p, new_p)

    if not ok then
        vim.notify(err .. " " .. err_name, vim.log.levels.ERROR)
    end
    return ok
end

local function smart_copy(src_p, dest_p)
    local uv = vim.uv
    local ok, err, err_name = uv.fs_copyfile(src_p, dest_p)

    if not ok then
        vim.notify(err .. " " .. err_name, vim.log.levels.ERROR)
    end
    return ok
end

function M.do_action(action)
    local cwd = get_cwd()
    if action.kind == "rename" then
        local old_path = vim.fs.joinpath(cwd, action.data.old)
        local new_path = vim.fn.fnamemodify(vim.fs.joinpath(cwd, action.data.new), ":p")
        new_path = new_path:gsub("/$", "")

        local new_parent = vim.fn.fnamemodify(new_path, ":h")
        if vim.fn.isdirectory(new_parent) == 0 then
            vim.fn.mkdir(new_parent, "p")
        end
        smart_rename(old_path, new_path)
    elseif action.kind == "delete" then
        local path = vim.fs.joinpath(cwd, action.data.name)
        smart_delete(path)
    elseif action.kind == "create" then
        local path = vim.fs.joinpath(cwd, action.data.name)
        local parent = vim.fn.fnamemodify(path, ":h")
        if vim.fn.isdirectory(parent) == 0 then
            vim.fn.mkdir(parent, "p")
        end

        if action.data.name:sub(-1) == "/" then
            vim.fn.mkdir(path, "p")
        else
            local f, err = io.open(path, "w")
            if f then
                f:close()
            else
                vim.notify(err or "", vim.log.levels.ERROR)
            end
        end
    elseif action.kind == "copy" then
        local src_path = vim.fs.joinpath(cwd, action.data.src)
        local dest_path = vim.fn.fnamemodify(vim.fs.joinpath(cwd, action.data.dest), ":p")
        dest_path = dest_path:gsub("/$", "")

        local new_parent = vim.fn.fnamemodify(dest_path, ":h")
        if vim.fn.isdirectory(new_parent) == 0 then
            vim.fn.mkdir(new_parent, "p")
        end
        smart_copy(src_path, dest_path)
    end
end

function M.open_item(_, text)
    local clean_name = text:gsub("/$", "")
    local new_path = vim.fs.joinpath(dirname_from_bufname(0), clean_name)

    if vim.fn.isdirectory(new_path) == 1 then
        M.pending_path = new_path
        require("vist.core").open(M)
        M.pending_path = nil
    else
        vim.cmd("edit " .. vim.fn.fnameescape(new_path))
    end
end

function M.on_open(bufnr)
    vim.keymap.set("n", "-", function()
        local current = dirname_from_bufname(bufnr):gsub("/$", "")
        local parent = vim.fn.fnamemodify(current, ":p:h:h")

        if current == parent or current == "/" then
            return
        end

        M.pending_path = parent
        require("vist.core").open(M)
        M.pending_path = nil
    end, { buffer = bufnr, silent = true, noremap = true })
end

function M.confirm(actions)
    if #actions == 0 then
        return
    end

    local lines = {}
    for _, a in ipairs(actions) do
        if a.kind == "create" then
            table.insert(lines, "  [+] " .. a.data.name)
        elseif a.kind == "delete" then
            table.insert(lines, "  [-] " .. a.data.name)
        elseif a.kind == "rename" then
            table.insert(lines, "  [R] " .. a.data.old .. " -> " .. a.data.new)
        elseif a.kind == "copy" then
            table.insert(lines, "  [C] " .. a.data.src .. " -> " .. a.data.dest)
        end
    end

    local choice = vim.fn.confirm(table.concat(lines, "\n"), "&Yes\n&No", 1)
    if choice ~= 1 then
        return false
    end
    return true
end

return M --[[@as Vist.Adapter]]
