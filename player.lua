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

local res = require('resources')
local storage = require('storage')
local action_manager = require('action_manager')
local mount_roulette = require('libs/mountroulette/mountroulette')

local player = {}

player.name = ''
player.main_job = ''
player.main_job_level = ''
player.sub_job = ''
player.sub_job_level = ''
player.server = ''

player.vitals = {}
player.vitals.mp = 0
player.vitals.tp = 0

player.sch_jp_spent = 0

player.hotbar = {}

-- ordered list of file-level environments that merge into player.hotbar
-- indices 1=all-jobs, 2=job-default, 3=job-sub; ability overlays appended at 4+
player.hotbar_levels = {}

-- set of level indices modified by in-game edits since the last save; only these
-- levels are flushed to disk by save_hotbar
player.dirty_levels = {}

player.hotbar_settings = {}
player.hotbar_settings.max = 1
player.hotbar_settings.active_hotbar = 1
player.hotbar_settings.active_environment = 'Field'

player.auto_create_xml = true

-- initialize player
function player:initialize(windower_player, server, theme_options, enchanted_items)
    self.name = windower_player.name
    self.main_job = windower_player.main_job
    self.main_job_level = windower_player.main_job_level
    self.sub_job = windower_player.sub_job
    self.sub_job_level = windower_player.sub_job_level
    self.server = server
    self.id = windower_player.id
    self.enchanted_items = enchanted_items

    self.hotbar_settings.max = theme_options.hotbar_number

    self.vitals.mp = windower_player.vitals.mp
    self.vitals.tp = windower_player.vitals.tp

    self.sch_jp_spent = windower_player.job_points.sch.jp_spent

    self.auto_create_xml = theme_options.AutoCreateXML

    storage:setup(self)
end

local unescape = function(str)
    return str:gsub('&apos;', '\''):gsub('quote', '"')
end

-- update player jobs
function player:update_jobs(main, sub)
    self.main_job = main
    self.sub_job = sub

    storage:update_filename(main, sub)
end

function player:get_id()
    return self.id
end

-- Updates the set of spells the player can currently cast. Does not take
-- MP, recast timers, or special ability requirements into account. Only
-- whether or not FFXI's job data says the spell is there.
function player:update_current_spells()
    local mainJobSpellList = T()
    if windower.ffxi.get_player()['main_job_id'] == 16 then
        mainJobSpellList = T(windower.ffxi.get_mjob_data().spells)
        -- Returns all values but 512
        :filter(function(id) return id ~= 512 end)
        -- Transforms them from IDs to lowercase English names
        :map(function(id) return res.spells[id].english:lower() end)
    end

    local subJobSpellList = T()
    if windower.ffxi.get_player()['sub_job_id'] == 16 then
        subJobSpellList = T(windower.ffxi.get_sjob_data().spells)
        -- Returns all values but 512
        :filter(function(id) return id ~= 512 end)
        -- Transforms them from IDs to lowercase English names
        :map(function(id) return res.spells[id].english:lower() end)
    end

    self.current_spells = {}
    for _, spellName in ipairs(subJobSpellList) do
        self.current_spells[spellName] = true
    end
    for _, spellName in ipairs(mainJobSpellList) do
        self.current_spells[spellName] = true
    end
end

-- Returns true if the player has the spell and (if BLU) the spell is set.
function player:has_spell(spellName)
    return self.current_spells[spellName] == true
end

-- load hotbar for current player and job combination
function player:load_hotbar()
    self:update_current_spells()
    self:reset_hotbar()

    -- the storage.* handles are current for this job by now; attach them so each
    -- base level knows which file it flushes to
    self.hotbar_levels[1].file = storage.all_jobs_file
    self.hotbar_levels[2].file = storage.job_default_file
    self.hotbar_levels[3].file = storage.file

    -- if all jobs file exists, load it. If not, build a default version in memory
    if storage.all_jobs_file:exists() then
        windower.console.write('[XIVCrossbar] Load cross-job fallback crossbar set')
        self:load_level_from_file(1, storage.all_jobs_file)
    elseif self.auto_create_xml then
        self:create_all_jobs_default_hotbar()
    end

    -- if job default file exists, load it. If not, build a default version in memory
    if storage.job_default_file:exists() then
        windower.console.write('[XIVCrossbar] Load cross-subjob fallback crossbar set for ' .. player.main_job)
        self:load_level_from_file(2, storage.job_default_file)
    elseif self.auto_create_xml then
        self:create_job_default_hotbar()
    end

    -- if normal hotbar file exists, load it. If not, build a default hotbar in memory
    if storage.file:exists() then
        windower.console.write('[XIVCrossbar] Load crossbar sets for ' .. storage.filename)
        self:load_level_from_file(3, storage.file)
    elseif self.auto_create_xml then
        self:create_default_hotbar()
    end

    self:merge_levels()
end

-- read the three static XML files into hotbar_levels and rebuild player.hotbar
function player:load_ability_overlay(name)
    local overlay_file = storage:get_ability_file(name)
    if not overlay_file:exists() then
        return
    end

    -- parse and validate into a local table first; only append the overlay level
    -- on success so a malformed/missing-root file leaves no phantom empty level
    local contents = xml.read(overlay_file)
    if contents == nil or contents.name ~= 'hotbar' then
        return
    end

    local data = { hotbar = {} }
    self:parse_hotbar_into(data.hotbar, contents)

    local level = { name = name, file = overlay_file, data = data }
    self.hotbar_levels[#self.hotbar_levels + 1] = level
    self:merge_levels()
end

-- remove a single ability overlay level by name and rebuild player.hotbar
function player:unload_ability_overlay(name)
    for i = #self.hotbar_levels, 4, -1 do
        if self.hotbar_levels[i].name == name then
            table.remove(self.hotbar_levels, i)
        end
    end
    self:merge_levels()
end

-- remove every ability overlay level and rebuild player.hotbar
function player:unload_all_overlays()
    for i = #self.hotbar_levels, 4, -1 do
        table.remove(self.hotbar_levels, i)
    end
    self:merge_levels()
end

-- rebuild the merged player.hotbar view from all levels (low -> high priority)
function player:merge_levels()
    self.hotbar = {}

    for i = 1, #self.hotbar_levels, 1 do
        local level = self.hotbar_levels[i]
        for environment, hotbars in pairs(level.data.hotbar) do
            if self.hotbar[environment] == nil then
                self.hotbar[environment] = {}
            end

            for key, value in pairs(hotbars) do
                if key == 'name' then
                    self.hotbar[environment]['name'] = value
                else
                    -- key is a hotbar_N table of slots
                    if self.hotbar[environment][key] == nil then
                        self.hotbar[environment][key] = {}
                    end
                    for slot, action in pairs(value) do
                        if (action ~= nil and action.action ~= nil) then
                            self.hotbar[environment][key][slot] = action
                        elseif self.hotbar[environment][key][slot] == nil then
                            -- preserve placeholder slots (e.g. the slot_9 set-selector hack)
                            self.hotbar[environment][key][slot] = action
                        end
                    end
                end
            end
        end
    end
end

function kebab_casify(str)
    return str:lower():gsub(' ', '-'):gsub('\'', '')
end

-- true if a level's data defines a real action (not an empty/placeholder slot) at
-- the given environment key / hotbar number / slot number
local function level_defines_slot(level, env_key, hotbar, slot)
    local hotbars = level.data.hotbar[env_key]
    if hotbars == nil then return false end
    local slots = hotbars['hotbar_' .. hotbar]
    if slots == nil then return false end
    local action = slots['slot_' .. slot]
    return action ~= nil and action.action ~= nil
end

-- shallow copy of a flat action field table (built by action_manager:build), so a
-- copied/moved slot does not alias the source action across levels/files
local function shallow_copy_action(action)
    local copy = {}
    for key, value in pairs(action) do
        copy[key] = value
    end
    return copy
end

-- load a hotbar file into the given level's data table
function player:load_level_from_file(level_index, storage_file)
    local contents = xml.read(storage_file)

    if contents == nil or contents.name ~= 'hotbar' then
        windower.console.write('XIVCROSSBAR: invalid hotbar on ' .. storage.filename)
        return
    end

    local target_hotbar = self.hotbar_levels[level_index].data.hotbar
    self:parse_hotbar_into(target_hotbar, contents)
end

-- parse an xml hotbar DOM (root element) into the given target hotbar table
function player:parse_hotbar_into(target_hotbar, contents)
    for key, environment in ipairs(contents.children) do
        local environment_name = nil
        for key, hotbar in ipairs(environment.children) do     -- hotbar number
            if (hotbar.name == 'name') then
                for key, name in ipairs(hotbar.children) do
                    environment_name = name.value
                end
            end
        end
        if (environment_name == nil) then
            environment_name = key
        end
        for key, hotbar in ipairs(environment.children) do     -- hotbar number
            if (hotbar.name ~= 'name') then
                for key, slot in ipairs(hotbar.children) do       -- slot number
                    local new_action = {}

                    for key, tag in ipairs(slot.children) do   -- action
                        if tag.name == 'type' then
                            new_action.type = tag.children[1].value
                        elseif tag.name == 'action' then
                            new_action.action = unescape(tag.children[1].value)
                        elseif tag.name == 'target' then
                            if tag.children[1] == nil then
                                new_action.target = nil
                            else
                                new_action.target = tag.children[1].value
                            end

                        elseif tag.name == 'alias' then
                            new_action.alias = tag.children[1].value
                        elseif tag.name == 'icon' then
                            new_action.icon = tag.children[1].value
                        elseif tag.name == 'equip_slot' then
                            new_action.equip_slot = tag.children[1].value
                        elseif tag.name == 'warmup' then
                            new_action.warmup = tag.children[1].value
                        elseif tag.name == 'cooldown' then
                            new_action.cooldown = tag.children[1].value
                        elseif tag.name == 'usable' then
                            new_action.usable = tag.children[1].value
                        end
                    end

                    self:add_action_to(
                        target_hotbar,
                        action_manager:build(new_action.type, new_action.action, new_action.target, new_action.alias, new_action.icon, new_action.equip_slot, new_action.warmup, new_action.cooldown, new_action.usable),
                        environment_name,
                        hotbar.name:gsub('hotbar_', ''),
                        slot.name:gsub('slot_', '')
                    )
                end
            end
        end
    end
end

-- create a default hotbar in the job-sub level
function player:create_default_hotbar()
    windower.console.write('[XIVCrossbar] No hotbar found. Creating default for ' .. storage.filename)

    local target_hotbar = self.hotbar_levels[3].data.hotbar

    target_hotbar.default = {}
    target_hotbar.default['name'] = 'Default'
    self:setup_environment_hotbars(target_hotbar, 'default')

    target_hotbar.basic = {}
    target_hotbar.basic['name'] = 'Basic'
    self:setup_environment_hotbars(target_hotbar, 'basic')
end

-- create a fallback hotbar that applies to all subjobs of this job
function player:create_job_default_hotbar()
    windower.console.write('[XIVCrossbar] No cross-subjob fallback crossbar set found. Creating a default version')

    local target_hotbar = self.hotbar_levels[2].data.hotbar

    target_hotbar['job-default'] = {}
    target_hotbar['job-default']['name'] = 'Job Default'
    self:setup_environment_hotbars(target_hotbar, 'job-default')
end

-- create a fallback hotbar that applies to all jobs on this character
function player:create_all_jobs_default_hotbar()
    windower.console.write('[XIVCrossbar] No cross-job fallback crossbar set found. Creating a default version')

    local target_hotbar = self.hotbar_levels[1].data.hotbar

    target_hotbar['all-jobs-default'] = {}
    target_hotbar['all-jobs-default']['name'] = 'All Jobs Default'
    self:setup_environment_hotbars(target_hotbar, 'all-jobs-default')
end

-- reset player hotbar
function player:reset_hotbar()
    self.hotbar = {}
    self.dirty_levels = {}

    self.hotbar_levels = {
        { name = 'all-jobs', file = nil, data = { hotbar = {} } },
        { name = 'job-default', file = nil, data = { hotbar = {} } },
        { name = 'job-sub', file = nil, data = { hotbar = {} } }
    }

    self.hotbar_settings.active_hotbar = 1
end

function player:setup_environment_hotbars(target_hotbar, environment)
    for h=1,self.hotbar_settings.max,1 do
        target_hotbar[environment]['hotbar_' .. h] = {}

        -- This is a hack to make sure all newly-created crossbars show up in the crossbar set selector
        target_hotbar[environment]['hotbar_' .. h]['slot_9'] = {}
    end
end

-- set bar environment
function player:set_active_environment(environment)
    self.hotbar_settings.active_environment = kebab_casify(environment)
end

-- set bar environment
function player:is_valid_environment(environment)
    return self.hotbar[environment] ~= nil
end

function player:set_is_in_battle(in_battle)
    self.in_battle = in_battle
end

-- set bar environment to battle
function player:set_battle_environment(in_battle)
    local environment = 'Field'
    if in_battle then environment = 'Battle' end

    self.hotbar_settings.active_environment = environment
end

-- change active hotbar
function player:change_active_hotbar(new_hotbar)
    self.hotbar_settings.active_hotbar = new_hotbar

    if self.hotbar_settings.active_hotbar > self.hotbar_settings.max then
        self.hotbar_settings.active_hotbar = 1
    end
end

function player:get_crossbar_names()
    local names = L{}

    for name, hotbar in pairs(self.hotbar) do
        names:append(hotbar.name or name)
    end

    return names
end

-- resolve which level an add/modify edit should write to: the most-specific level
-- (job-sub or an active arts overlay) that already defines the slot, otherwise the
-- job-default floor (2). ALL-JOBS-DEFAULT (1) is never an in-game write target.
function player:resolve_edit_level(environment, hotbar, slot)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot == 10 then slot = 0 end
    local env_key = kebab_casify(environment)

    for i = #self.hotbar_levels, 3, -1 do
        if level_defines_slot(self.hotbar_levels[i], env_key, hotbar, slot) then
            return i
        end
    end
    return 2
end

-- resolve which level a delete should remove from: the most-specific writable level
-- (job-default up through active arts overlays) that defines the slot, or nil when
-- the slot only exists in the hand-edited ALL-JOBS-DEFAULT level (1).
function player:resolve_delete_level(environment, hotbar, slot)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot == 10 then slot = 0 end
    local env_key = kebab_casify(environment)

    for i = #self.hotbar_levels, 2, -1 do
        if level_defines_slot(self.hotbar_levels[i], env_key, hotbar, slot) then
            return i
        end
    end
    return nil
end

-- add given action to the most-specific defining level (job-default floor by
-- default), record that level as dirty, then refresh the merged view.
function player:add_action(action, environment, hotbar, slot)
    local idx = self:resolve_edit_level(environment, hotbar, slot)
    self:add_action_to(self.hotbar_levels[idx].data.hotbar, action, environment, hotbar, slot)
    self.dirty_levels[idx] = true
    self:merge_levels()
end

-- add given action to a specific hotbar table (a level's data.hotbar)
function player:add_action_to(target_hotbar, action, environment, hotbar, slot)
    if environment == nil or environment == '' then
        return
    end

    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot == 10 then slot = 0 end

    local env_key = kebab_casify(environment)
    if (env_key == nil) then
        return
    end

    if target_hotbar[env_key] == nil then
        target_hotbar[env_key] = {}
        target_hotbar[env_key]['name'] = environment
        self:setup_environment_hotbars(target_hotbar, env_key)
    end

    if target_hotbar[env_key]['hotbar_' .. hotbar] == nil then
        windower.console.write('XIVCROSSBAR: invalid hotbar (hotbar number)')
        return
    end

    if target_hotbar[env_key]['hotbar_' .. hotbar]['slot_' .. slot] == nil then
        target_hotbar[env_key]['hotbar_' .. hotbar]['slot_' .. slot] = {}
    end

    target_hotbar[env_key]['hotbar_' .. hotbar]['slot_' .. slot] = action
end

function create_send_command_coroutine(command)
    return function()
        windower.send_command(command)
    end
end

function player:create_use_item_coroutine(item_name)
    local enchanted_items = self.enchanted_items
    return function()
        enchanted_items:use(item_name)
    end
end

-- execute action from given slot
function player:execute_action(slot)
    local h = self.hotbar_settings.active_hotbar
    local env = self.hotbar_settings.active_environment

    local action = self.hotbar[env]['hotbar_' .. h]['slot_' .. slot]
    local is_missing = action == nil or action.action == nil

    if (is_missing and env ~= 'default' and env ~= 'job-default' and env ~= 'all-jobs-default' and self.hotbar['default'] and self.hotbar['default']['hotbar_' .. h] and
        self.hotbar['default']['hotbar_' .. h]['slot_' .. slot]) then
        action = self.hotbar['default']['hotbar_' .. h]['slot_' .. slot]
    elseif (is_missing and env ~= 'job-default' and env ~= 'all-jobs-default' and self.hotbar['job-default'] and self.hotbar['job-default']['hotbar_' .. h] and
        self.hotbar['job-default']['hotbar_' .. h]['slot_' .. slot]) then
        action = self.hotbar['job-default']['hotbar_' .. h]['slot_' .. slot]
    elseif (is_missing and env ~= 'all-jobs-default' and self.hotbar['all-jobs-default'] and self.hotbar['all-jobs-default']['hotbar_' .. h] and
        self.hotbar['all-jobs-default']['hotbar_' .. h]['slot_' .. slot]) then
        action = self.hotbar['all-jobs-default']['hotbar_' .. h]['slot_' .. slot]
    end

    local is_still_missing = action == nil or action.action == nil
    if (is_still_missing) then return end

    if action.type == 'ct' then
        local command = '/' .. action.action

        if  action.target ~= nil then
            command = command .. ' <' ..  action.target .. '>'
        end

        windower.send_command('input ' .. command)
        return
    end

    if action.type == 'ex' then
        windower.send_command(action.action)
        return
    end

    if action.type == 'enchanteditem' then
        local item = action.action
        local equip_slot = action.equip_slot
        local delay = 0.5
        if (action.warmup ~= nil) then
            delay = delay + action.warmup
        end
        local recast = action.cooldown

        if (equip_slot ~= nil) then
            windower.send_command('gs disable ' .. equip_slot)
            windower.send_command('input /equip '.. equip_slot .. ' "' .. item .. '"')
            self.enchanted_items:equip(item)
        end

        local use_item = create_send_command_coroutine('input /item "' .. item .. '" <' .. action.target .. '>')
        coroutine.schedule(use_item, delay)
        local mark_used_item = player:create_use_item_coroutine(item)
        coroutine.schedule(mark_used_item, delay)

        if (equip_slot ~= nil) then
            local reactivate_equip_slot = create_send_command_coroutine('gs enable ' .. equip_slot)
            coroutine.schedule(reactivate_equip_slot, delay + 2)
        end
        return
    end

    local target_string = ''
    if (action.target ~= nil) then
        target_string = '" <' .. action.target .. '>'
    end

    if action.type == 'mount' and action.action == 'Mount Roulette' then
        mount_roulette:ride_random_mount()
        return
    elseif (action.type == 'ta' and action.action == 'Switch Target' and action.alias == 'Switch Target') then
        if (self.in_battle) then
            windower.send_command('input /a ' .. target_string)
        else
            windower.send_command('input /ta ' .. target_string)
        end
        return
    end

    windower.send_command('input /' .. action.type .. ' "' .. action.action .. target_string)
end

-- remove the action from its most-specific writable level (job-default up through
-- active arts overlays); a lower-tier copy then shows through. A slot that only
-- exists in ALL-JOBS-DEFAULT is a no-op: that file is hand-edited.
function player:remove_action(environment, hotbar, slot)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot == 10 then slot = 0 end

    local idx = self:resolve_delete_level(environment, hotbar, slot)
    if idx == nil then
        windower.console.write('[XIVCrossbar] Action is only defined in ALL-JOBS-DEFAULT.xml; edit that file by hand to remove it.')
        return
    end

    local env_key = kebab_casify(environment)
    local target_hotbar = self.hotbar_levels[idx].data.hotbar
    if target_hotbar[env_key] == nil then return end
    if target_hotbar[env_key]['hotbar_' .. hotbar] == nil then return end

    target_hotbar[env_key]['hotbar_' .. hotbar]['slot_' .. slot] = nil
    self.dirty_levels[idx] = true
    self:merge_levels()
end

-- copy (or move) an action from one slot to another. The source is read from the
-- merged view; the destination lands in its most-specific defining level (job-default
-- floor by default). A move also clears the source's most-specific writable copy.
function player:copy_action(environment, hotbar, slot, to_environment, to_hotbar, to_slot, is_moving)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if to_environment == 'b' then to_environment = 'battle' elseif to_environment == 'f' then to_environment = 'field' end
    if slot == 10 then slot = 0 end
    if to_slot == 10 then to_slot = 0 end

    local src_env_key = kebab_casify(environment)
    local dest_env_key = kebab_casify(to_environment)

    if self.hotbar[src_env_key] == nil then return end
    if self.hotbar[src_env_key]['hotbar_' .. hotbar] == nil then return end
    local action = self.hotbar[src_env_key]['hotbar_' .. hotbar]['slot_' .. slot]
    if action == nil then return end

    local dest_idx = self:resolve_edit_level(to_environment, to_hotbar, to_slot)
    local target = self.hotbar_levels[dest_idx].data.hotbar
    if target[dest_env_key] == nil then
        target[dest_env_key] = {}
        target[dest_env_key]['name'] = to_environment
        self:setup_environment_hotbars(target, dest_env_key)
    end
    if target[dest_env_key]['hotbar_' .. to_hotbar] == nil then
        target[dest_env_key]['hotbar_' .. to_hotbar] = {}
    end
    target[dest_env_key]['hotbar_' .. to_hotbar]['slot_' .. to_slot] = shallow_copy_action(action)
    self.dirty_levels[dest_idx] = true

    if is_moving then
        local src_idx = self:resolve_delete_level(environment, hotbar, slot)
        if src_idx ~= nil then
            local source = self.hotbar_levels[src_idx].data.hotbar
            if source[src_env_key] ~= nil and source[src_env_key]['hotbar_' .. hotbar] ~= nil then
                source[src_env_key]['hotbar_' .. hotbar]['slot_' .. slot] = nil
                self.dirty_levels[src_idx] = true
            end
        end
    end

    self:merge_levels()
end

-- ensure the resolved edit level holds a real action for the slot before an in-place
-- field edit (alias/icon). When the action only lives in a lower level (e.g. it is
-- defined in ALL-JOBS-DEFAULT but the edit resolves to the job-default floor), copy
-- the merged action's fields down so the override carries the full action. Returns
-- the target slot table to mutate, or nil when there is no action to edit.
function player:prepare_field_edit(idx, env_key, hotbar, slot)
    local merged = self.hotbar[env_key]
    if merged == nil or merged['hotbar_' .. hotbar] == nil then return nil end
    local action = merged['hotbar_' .. hotbar]['slot_' .. slot]
    if action == nil or action.action == nil then return nil end

    local target = self.hotbar_levels[idx].data.hotbar
    if target[env_key] == nil then
        target[env_key] = {}
        target[env_key]['name'] = merged['name'] or env_key
        self:setup_environment_hotbars(target, env_key)
    end
    if target[env_key]['hotbar_' .. hotbar] == nil then
        target[env_key]['hotbar_' .. hotbar] = {}
    end

    local existing = target[env_key]['hotbar_' .. hotbar]['slot_' .. slot]
    if existing == nil or existing.action == nil then
        target[env_key]['hotbar_' .. hotbar]['slot_' .. slot] = shallow_copy_action(action)
    end

    return target[env_key]['hotbar_' .. hotbar]['slot_' .. slot]
end

-- update action alias
function player:set_action_alias(environment, hotbar, slot, alias)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot == 10 then slot = 0 end

    local env_key = kebab_casify(environment)
    local idx = self:resolve_edit_level(environment, hotbar, slot)
    local target_slot = self:prepare_field_edit(idx, env_key, hotbar, slot)
    if target_slot == nil then return end

    target_slot.alias = alias
    self.dirty_levels[idx] = true
    self:merge_levels()
end

-- update action icon
function player:set_action_icon(environment, hotbar, slot, icon)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot == 10 then slot = 0 end

    local env_key = kebab_casify(environment)
    local idx = self:resolve_edit_level(environment, hotbar, slot)
    local target_slot = self:prepare_field_edit(idx, env_key, hotbar, slot)
    if target_slot == nil then return end

    target_slot.icon = icon
    self.dirty_levels[idx] = true
    self:merge_levels()
end

-- create a new environment in the job-default level (the in-game edit floor)
function player:create_new_environment(name)
    if (name ~= nil) then
        local new_environment = {}
        for h=1,self.hotbar_settings.max,1 do
            new_environment['name'] = name
            new_environment['hotbar_' .. h] = {}
            for i=1,8,1 do
                new_environment['hotbar_' .. h]['slot_' .. i] = {}
            end
        end

        self.hotbar_levels[2].data.hotbar[kebab_casify(name)] = new_environment
        self.dirty_levels[2] = true
        self:merge_levels()
    else
        print('XIVCROSSBAR: Attempted to create crossbar set with no name. Unable to create.')
    end
end

-- save current hotbar. Only the levels touched by in-game edits since the last save
-- are flushed to disk; untouched files (including the hand-edited ALL-JOBS-DEFAULT)
-- are left alone.
function player:save_hotbar()
    for idx in pairs(self.dirty_levels) do
        local level = self.hotbar_levels[idx]
        if level and level.file then
            storage:save_level(level.data, level.file)
        end
    end
    self.dirty_levels = {}
end

return player