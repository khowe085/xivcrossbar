--[[
        Copyright © 2017, SirEdeonX
        All rights reserved.

        Redistribution and use in source and binary forms, with or without
        modification, are permitted provided that the following conditions are met:

            * Redistributions of source code must retain the above copyright
              notice, this list of conditions and the following disclaimer.
            * Redistributions in binary form must reproduce the above copyright
              notice, this list of conditions and the following disclaimer in the
              documentation and/or other materials provided with the distribution.
            * Neither the name of xivhotbar nor the
              names of its contributors may be used to endorse or promote products
              derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
        WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL SirEdeonX BE LIABLE FOR ANY
        DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
        (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
        LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
        ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
        (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

local storage = {}

storage.filename = ''
storage.directory = ''

-- the {JOB}-DEFAULT section key for the current main job (e.g. 'RDM-DEFAULT')
storage.job_default_key = ''

-- in-memory cache of the whole {JOB}.lua table: section key -> level.data table.
-- Reloaded from disk by update_filename whenever the job changes.
storage.job_data = {}

-- normalize the subjob token: no subjob (nil / '' / 'NON') -> 'NOSUB'
local function normalize_sub(sub)
    if sub == nil or sub == '' or sub == 'NON' then
        return 'NOSUB'
    end
    return sub
end

-- serialize a string value into a single-quoted Lua literal, escaping the
-- characters that would otherwise break the literal or span lines
local function quote_string(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub("'", "\\'")
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    return "'" .. s .. "'"
end

-- collect a table's keys in a deterministic order (numeric ascending, then
-- string alphabetical) so serialized files are stable across saves
local function sorted_keys(t)
    local nums, strs = {}, {}
    for k in pairs(t) do
        if type(k) == 'number' then
            nums[#nums + 1] = k
        else
            strs[#strs + 1] = k
        end
    end
    table.sort(nums)
    table.sort(strs)
    return nums, strs
end

-- true when every value in t is a scalar (string/number/boolean) — no nested tables,
-- no numeric keys. Used to decide whether to serialize a table inline.
local function is_flat(t)
    for _, v in pairs(t) do
        if type(v) == 'table' then return false end
    end
    return true
end

-- recursively serialize a Lua value into source text.
-- * Empty tables render as {}.
-- * Tables whose values are all scalars (slot action tables) render on one line.
-- * Tables that have a 'name' key (environment tables) emit 'name' then 'order' first.
-- * All other tables use sorted keys (numeric ascending, then string alphabetical).
local function serialize_value(v, indent)
    local tv = type(v)
    if tv == 'string' then
        return quote_string(v)
    elseif tv == 'number' or tv == 'boolean' then
        return tostring(v)
    elseif tv == 'table' then
        local nums, strs = sorted_keys(v)
        if #nums == 0 and #strs == 0 then
            return '{}'
        end
        -- Inline flat tables (slot action tables: scalar values only, no numeric keys)
        if #nums == 0 and is_flat(v) then
            local parts = {}
            for _, k in ipairs(strs) do
                local key = k:match('^[%a_][%w_]*$') and k or ('[' .. quote_string(k) .. ']')
                parts[#parts + 1] = key .. ' = ' .. serialize_value(v[k], '')
            end
            return '{ ' .. table.concat(parts, ', ') .. ' }'
        end
        local child = indent .. '  '
        local parts = {}
        -- Environment tables (has 'name' key): emit name first, then order if present
        local ordered_strs
        if v['name'] ~= nil then
            ordered_strs = { 'name' }
            if v['order'] ~= nil then
                ordered_strs[#ordered_strs + 1] = 'order'
            end
            for _, k in ipairs(strs) do
                if k ~= 'name' and k ~= 'order' then
                    ordered_strs[#ordered_strs + 1] = k
                end
            end
        else
            ordered_strs = strs
        end
        for _, k in ipairs(nums) do
            parts[#parts + 1] = child .. '[' .. k .. '] = ' .. serialize_value(v[k], child)
        end
        for _, k in ipairs(ordered_strs) do
            local key = k:match('^[%a_][%w_]*$') and k or ('[' .. quote_string(k) .. ']')
            parts[#parts + 1] = child .. key .. ' = ' .. serialize_value(v[k], child)
        end
        return '{\n' .. table.concat(parts, ',\n') .. ',\n' .. indent .. '}'
    end
    -- nil / function / userdata are not expected in hotbar data; emit nil so the
    -- file still loads rather than producing malformed source
    return 'nil'
end

-- serialize a table to a complete Lua data file body ('return { ... }')
local function table_to_lua(t)
    return 'return ' .. serialize_value(t, '') .. '\n'
end

-- read a Lua data file and return the table it returns, or nil on any error
local function load_lua_file(f)
    if f == nil or not f:exists() then
        return nil
    end
    local contents = f:read()
    if contents == nil or contents == '' then
        return nil
    end
    local chunk, err = loadstring(contents)
    if chunk == nil then
        windower.console.write('XIVCROSSBAR: failed to parse lua data file: ' .. tostring(err))
        return nil
    end
    local ok, result = pcall(chunk)
    if not ok or type(result) ~= 'table' then
        windower.console.write('XIVCROSSBAR: failed to load lua data file: ' .. tostring(result))
        return nil
    end
    return result
end

-- setup storage for current player
function storage:setup(player)
    self.directory = player.server .. '/' .. player.name
    self:update_filename(player.main_job, player.sub_job)
end

-- update filenames + handles for the given jobs and reload the cached {JOB}.lua.
-- job_data is the source of truth for every {JOB}.lua section while this job is active.
function storage:update_filename(main, sub)
    self.filename = main .. '-' .. normalize_sub(sub)
    self.job_default_key = main .. '-DEFAULT'
    self.all_jobs_file = file.new('data/hotbar/' .. self.directory .. '/General.lua')
    self.job_file = file.new('data/hotbar/' .. self.directory .. '/' .. main .. '.lua')
    self.job_data = load_lua_file(self.job_file) or {}
end

-- return the all-jobs (General.lua) data table, or nil if absent/invalid
function storage:load_all_jobs()
    return load_lua_file(self.all_jobs_file)
end

-- return the cached {JOB}.lua section for a combo key (may be nil)
function storage:get_job_section(combo)
    return self.job_data[combo]
end

-- register a transient section table into job_data on its first edit; noop if the
-- section is already present so the live in-memory reference is preserved
function storage:anchor_job_section(combo, data)
    if self.job_data[combo] == nil then
        self.job_data[combo] = data
    end
end

-- write the all-jobs (General.lua) data, creating the file/dir if needed
function storage:save_all_jobs(data)
    if not self.all_jobs_file:exists() then
        self.all_jobs_file:create()
    end
    self.all_jobs_file:write(table_to_lua(data))
end

-- write the entire {JOB}.lua table (all cached sections), creating the file/dir if needed
function storage:save_job_file()
    if not self.job_file:exists() then
        self.job_file:create()
    end
    self.job_file:write(table_to_lua(self.job_data))
end

return storage
