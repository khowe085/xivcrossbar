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
storage.file = nil

-- normalize the subjob token: no subjob (nil / '' / 'NON') -> 'NOSUB'
local function normalize_sub(sub)
    if sub == nil or sub == '' or sub == 'NON' then
        return 'NOSUB'
    end
    return sub
end

-- setup storage for current player
function storage:setup(player)
    self.directory = player.server .. '/' .. player.name
    self:update_filename(player.main_job, player.sub_job)
end

-- get a handle to an ability overlay file: e.g. SCH-NOSUB-lightarts.xml
function storage:get_ability_file(name)
    return file.new('data/hotbar/' .. self.directory .. '/' .. self.filename .. '-' .. name .. '.xml')
end

-- write a single level's environments to its file, creating the file/dir if needed
function storage:save_level(level_data, target_file)
    if not target_file:exists() then
        target_file:create()
    end
    target_file:write(table.to_xml(level_data))
end

-- create a level's file only if it does not already exist; never overwrites
function storage:create_level_if_missing(level_data, target_file)
    if target_file:exists() then
        return
    end
    target_file:create()
    target_file:write(table.to_xml(level_data))
end

-- update filename according to jobs
function storage:update_filename(main, sub)
    self.filename = main .. '-' .. normalize_sub(sub)
    self.file = file.new('data/hotbar/' .. self.directory .. '/' .. self.filename .. '.xml')
    self.job_default_file = file.new('data/hotbar/' .. self.directory .. '/' .. main .. '-DEFAULT.xml')
    self.all_jobs_file = file.new('data/hotbar/' .. self.directory .. '/ALL-JOBS-DEFAULT.xml')
end

return storage