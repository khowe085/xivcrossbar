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

local lua_serializer = require('libs/lua_serializer')

local storage = {}

storage.directory     = ''
storage.main_job      = ''
storage.job_file      = nil
storage.all_jobs_file = nil

function storage:setup(player)
  self.main_job      = player.main_job
  self.directory     = player.server .. '/' .. player.name
  self.job_file      = file.new('data/hotbar/' .. self.directory .. '/' .. self.main_job .. '.lua')
  self.all_jobs_file = file.new('data/hotbar/' .. self.directory .. '/General.lua')
end

-- Call when the player's main or sub job changes.
-- Updates the job file handle only when main job changes.
-- Returns true if the main job changed (file handle was updated).
function storage:update_main_job(main, sub)
  if self.main_job == main then return false end
  self.main_job = main
  self.job_file = file.new('data/hotbar/' .. self.directory .. '/' .. main .. '.lua')
  return true
end

-- Safely load a Lua-format hotbar file using loadstring (no require cache).
-- Returns the table the file returns, or nil if the file is absent or malformed.
function storage:_load_lua_file(f)
  if not f:exists() then return nil end
  local content = f:read()
  if content == nil or content == '' then return nil end
  local chunk, err = loadstring(content)
  if chunk == nil then
    windower.console.write('[XIVCrossbar] Failed to parse Lua hotbar: ' .. tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    windower.console.write('[XIVCrossbar] Failed to execute Lua hotbar: ' .. tostring(result))
    return nil
  end
  return result
end

-- Load hotbar data from disk.
-- Returns job_data (table or nil), all_jobs_data (table or nil).
-- nil means the file does not exist yet — hotbar will be empty until the user saves.
function storage:read_hotbar()
  return self:_load_lua_file(self.job_file), self:_load_lua_file(self.all_jobs_file)
end

local function split_hotbar(hotbar_table)
  local job_envs, all_jobs_envs = {}, {}
  for env_key, env_data in pairs(hotbar_table) do
    if string.sub(env_key, 1, 4) == 'all-' then
      all_jobs_envs[env_key] = env_data
    else
      job_envs[env_key] = env_data
    end
  end
  return job_envs, all_jobs_envs
end

-- Write the full in-memory hotbar to disk.
-- Environments with the 'all-' prefix go to General.lua; everything else to <JOB>.lua.
function storage:write_hotbar(hotbar_table)
  local job_envs, all_jobs_envs = split_hotbar(hotbar_table)
  self.job_file:create()
  self.job_file:write(lua_serializer.to_lua(job_envs))
  self.all_jobs_file:create()
  self.all_jobs_file:write(lua_serializer.to_lua(all_jobs_envs))
end

return storage
