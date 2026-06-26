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

-- in-game edit target: selector ID 1-7. 1-3 = static levels (all-jobs, job-default,
-- job-sub); 4-7 = ability overlays resolved by edit_target_overlay_name
player.edit_target_level        = 2
player.edit_target_overlay_name = nil

player.hotbar_settings = {}
player.hotbar_settings.max = 1
player.hotbar_settings.active_hotbar = 1
player.hotbar_settings.active_environment = 'Field'

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

    self:reset_edit_target()

    storage:setup(self)
end

-- update player jobs
function player:update_jobs(main, sub)
    self.main_job = main
    self.sub_job = sub

    storage:update_filename(main, sub)

    self:reset_edit_target()
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

    -- attach the storage handles + section keys so each base level knows where it
    -- reads from and (for the job levels) which {JOB}.lua section it anchors into
    self.hotbar_levels[1].file = storage.all_jobs_file
    self.hotbar_levels[2].file = storage.job_file
    self.hotbar_levels[2].combo = storage.job_default_key
    self.hotbar_levels[3].file = storage.job_file
    self.hotbar_levels[3].combo = storage.filename

    -- Level 1 (all-jobs): General.lua, loaded fresh from disk each time. If absent,
    -- build a default Field environment in memory.
    local all_jobs = storage:load_all_jobs()
    if all_jobs ~= nil then
        self.hotbar_levels[1].data = all_jobs
    else
        self:create_all_jobs_default_hotbar()
    end

    -- Level 2 (job-default): the {JOB}-DEFAULT section of the cached {JOB}.lua. If
    -- absent, build a default Battle environment and register it in job_data eagerly.
    local job_default = storage:get_job_section(storage.job_default_key)
    if job_default ~= nil then
        self.hotbar_levels[2].data = job_default
    else
        self:create_job_default_hotbar()
    end

    -- Level 3 (job-sub): the {JOB}-{SUB} section. Absent (empty + transient) until
    -- the user edits it, at which point the first save anchors it into job_data.
    local job_sub = storage:get_job_section(storage.filename)
    if job_sub ~= nil then
        self.hotbar_levels[3].data = job_sub
    else
        self:create_default_hotbar()
    end

    self:merge_levels()
end

-- load an ability overlay level (LA / DA / LA-AW / DA-AB) from the cached {JOB}.lua.
-- A saved section is loaded by reference so in-game edits mutate job_data directly;
-- an absent section gets a transient empty level that is not registered in job_data
-- until the first edit anchors it (see save_hotbar / anchor_job_section).
function player:load_ability_overlay(name)
    local combo_key = storage.filename .. '-' .. name
    local section = storage:get_job_section(combo_key)
    local data = section or { sets = {} }

    local level = { name = name, file = storage.job_file, combo = combo_key, data = data }
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
        for environment, hotbars in pairs(level.data.sets) do
            if self.hotbar[environment] == nil then
                self.hotbar[environment] = {}
            end

            for key, value in pairs(hotbars) do
                if key == 'name' or key == 'order' then
                    self.hotbar[environment][key] = value
                elseif type(value) == 'table' then
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

-- shallow copy of a flat action field table (built by action_manager:build), so a
-- copied/moved slot does not alias the source action across levels/files
local function shallow_copy_action(action)
    local copy = {}
    for key, value in pairs(action) do
        copy[key] = value
    end
    return copy
end

-- create an empty job-sub level. JOB-SUB starts empty and the table stays transient
-- (out of job_data) until the first edit anchors it on save -- the {JOB}-{SUB} section
-- must not appear in {JOB}.lua until the user actually edits it.
function player:create_default_hotbar()
    self.hotbar_levels[3].data = { sets = {} }
end

-- create the fallback hotbar that applies to all subjobs of this job (the
-- {JOB}-DEFAULT section). Auto-creates a General environment and registers the level
-- in job_data eagerly so its content is persisted whenever {JOB}.lua is next written.
function player:create_job_default_hotbar()
    local data = self.hotbar_levels[2].data
    data.sets['general'] = {}
    data.sets['general']['name'] = 'General'
    self:setup_environment_hotbars(data.sets, 'general')

    storage.job_data[storage.job_default_key] = data
end

-- create the fallback hotbar that applies to all jobs on this character (General.lua).
-- Auto-creates a Field environment shared across every job via the merge.
function player:create_all_jobs_default_hotbar()
    local sets = self.hotbar_levels[1].data.sets

    sets['field'] = {}
    sets['field']['name'] = 'Field'
    self:setup_environment_hotbars(sets, 'field')
end

-- reset player hotbar
function player:reset_hotbar()
    self.hotbar = {}
    self.dirty_levels = {}

    self.hotbar_levels = {
        { name = 'all-jobs', file = nil, data = { sets = {} } },
        { name = 'job-default', file = nil, data = { sets = {} } },
        { name = 'job-sub', file = nil, data = { sets = {} } }
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

-- map a selector ID (1-7) to the in-game edit target. 1-3 are static levels; 4-7 are
-- ability overlays, stored by name so resolve_* can find/create them at edit time.
function player:set_edit_target(id)
    local names = { [4] = 'LA', [5] = 'DA', [6] = 'LA-AW', [7] = 'DA-AB' }
    self.edit_target_level        = id
    self.edit_target_overlay_name = names[id]
end

-- return the current edit target selector ID (1-7)
function player:get_edit_target()
    return self.edit_target_level
end

-- reset the in-game edit target to Job Default (level 2). Done on load/login and on job
-- change -- NOT on the reloads that follow an edit, so the selection persists across edits.
function player:reset_edit_target()
    self.edit_target_level        = 2
    self.edit_target_overlay_name = nil
end

-- label of the file/section the current edit target writes to (for display)
function player:get_edit_target_filename()
    local id = self.edit_target_level
    if id == 1 then
        return 'General.lua'
    elseif id == 2 then
        return self.main_job .. '.lua (' .. storage.job_default_key .. ')'
    elseif id == 3 then
        return self.main_job .. '.lua (' .. storage.filename .. ')'
    else
        return self.main_job .. '.lua (' .. storage.filename .. '-' .. self.edit_target_overlay_name .. ')'
    end
end

function player:get_edit_target_label()
    local id = self.edit_target_level
    if id == 1 then
        return 'General.lua'
    elseif id == 2 then
        return '(' .. storage.job_default_key .. ')'
    elseif id == 3 then
        return '(' .. storage.filename .. ')'
    else
        return '(' .. storage.filename .. '-' .. self.edit_target_overlay_name .. ')'
    end
end

-- find an ability overlay level by name, loading it if not already in hotbar_levels.
-- load_ability_overlay always appends a level (a saved {JOB}.lua section by reference,
-- or a transient empty one), so the section is registered in job_data only later, on
-- the first edit's save. Returns the overlay's index in hotbar_levels.
function player:ensure_ability_overlay(name)
    for i = 4, #self.hotbar_levels do
        if self.hotbar_levels[i].name == name then
            return i
        end
    end

    self:load_ability_overlay(name)
    for i = 4, #self.hotbar_levels do
        if self.hotbar_levels[i].name == name then
            return i
        end
    end

    return #self.hotbar_levels
end

-- resolve which level an add/modify edit should write to. Static targets (1-3) map
-- directly; overlay targets (4-7) find or create the overlay by name.
function player:resolve_edit_level(environment, hotbar, slot)
    if self.edit_target_level <= 3 then
        return self.edit_target_level
    end
    return self:ensure_ability_overlay(self.edit_target_overlay_name)
end

-- resolve which level a delete should remove from. Static targets (1-3) map directly;
-- overlay targets (4-7) find or create the overlay by name.
function player:resolve_delete_level(environment, hotbar, slot)
    if self.edit_target_level <= 3 then
        return self.edit_target_level
    end
    return self:ensure_ability_overlay(self.edit_target_overlay_name)
end

-- add given action to the job-default level (2), record that level as dirty,
-- then refresh the merged view.
function player:add_action(action, environment, hotbar, slot)
    local idx = self:resolve_edit_level(environment, hotbar, slot)
    self:add_action_to(self.hotbar_levels[idx].data.sets, action, environment, hotbar, slot)
    self.dirty_levels[idx] = true
    self:merge_levels()
end

-- add given action to a specific hotbar table (a level's data.sets)
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

-- remove the action from the job-default level (2); a lower-tier (ALL-JOBS-DEFAULT)
-- copy then shows through, and higher hand-made levels (job-sub / arts overlays)
-- still shadow it in the merged view.
function player:remove_action(environment, hotbar, slot)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot == 10 then slot = 0 end

    local idx = self:resolve_delete_level(environment, hotbar, slot)

    local env_key = kebab_casify(environment)
    local target_hotbar = self.hotbar_levels[idx].data.sets
    if target_hotbar[env_key] == nil then return end
    if target_hotbar[env_key]['hotbar_' .. hotbar] == nil then return end

    target_hotbar[env_key]['hotbar_' .. hotbar]['slot_' .. slot] = nil
    self.dirty_levels[idx] = true
    self:merge_levels()
end

-- copy (or move) an action from one slot to another. The source is read from the
-- merged view; the destination lands in the job-default level (2). A move also clears
-- the job-default copy of the source.
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
    local target = self.hotbar_levels[dest_idx].data.sets
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
        local source = self.hotbar_levels[src_idx].data.sets
        if source[src_env_key] ~= nil and source[src_env_key]['hotbar_' .. hotbar] ~= nil then
            source[src_env_key]['hotbar_' .. hotbar]['slot_' .. slot] = nil
            self.dirty_levels[src_idx] = true
        end
    end

    self:merge_levels()
end

-- swap two actions within the same environment. Both source and target land in the
-- level returned by resolve_edit_level for slot_a.
function player:swap_action(environment, hotbar_a, slot_a, hotbar_b, slot_b)
    if environment == 'b' then environment = 'battle' elseif environment == 'f' then environment = 'field' end
    if slot_a == 10 then slot_a = 0 end
    if slot_b == 10 then slot_b = 0 end

    local env_key = kebab_casify(environment)
    if self.hotbar[env_key] == nil then return end

    local action_a = self.hotbar[env_key]['hotbar_' .. hotbar_a] and
                     self.hotbar[env_key]['hotbar_' .. hotbar_a]['slot_' .. slot_a]
    local action_b = self.hotbar[env_key]['hotbar_' .. hotbar_b] and
                     self.hotbar[env_key]['hotbar_' .. hotbar_b]['slot_' .. slot_b]

    local has_a = action_a ~= nil and action_a.action ~= nil
    local has_b = action_b ~= nil and action_b.action ~= nil
    if not has_a and not has_b then return end

    local idx = self:resolve_edit_level(environment, hotbar_a, slot_a)
    local target = self.hotbar_levels[idx].data.sets

    if target[env_key] == nil then
        target[env_key] = {}
        target[env_key]['name'] = self.hotbar[env_key]['name'] or environment
        self:setup_environment_hotbars(target, env_key)
    end
    target[env_key]['hotbar_' .. hotbar_a] = target[env_key]['hotbar_' .. hotbar_a] or {}
    target[env_key]['hotbar_' .. hotbar_b] = target[env_key]['hotbar_' .. hotbar_b] or {}

    target[env_key]['hotbar_' .. hotbar_a]['slot_' .. slot_a] = has_b and shallow_copy_action(action_b) or nil
    target[env_key]['hotbar_' .. hotbar_b]['slot_' .. slot_b] = has_a and shallow_copy_action(action_a) or nil

    self.dirty_levels[idx] = true
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

    local target = self.hotbar_levels[idx].data.sets
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

-- create a new environment in the currently selected edit target level
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

        local max_order = 0
        for _, env in pairs(self.hotbar) do
            if (env.order or 0) > max_order then
                max_order = env.order or 0
            end
        end
        new_environment['order'] = max_order + 1

        local idx = self:resolve_edit_level(nil, nil, nil)
        self.hotbar_levels[idx].data.sets[kebab_casify(name)] = new_environment
        self.dirty_levels[idx] = true
        self:merge_levels()
    else
        print('XIVCROSSBAR: Attempted to create crossbar set with no name. Unable to create.')
    end
end

-- save current hotbar. Only the levels touched by in-game edits since the last save
-- are flushed to disk. Level 1 (all-jobs) writes General.lua; any dirty job level
-- (2+) is first anchored into job_data, then the whole {JOB}.lua is rewritten once.
-- Untouched files (including a hand-edited General.lua) are left alone.
function player:save_hotbar()
    local save_job = false

    for idx in pairs(self.dirty_levels) do
        if idx == 1 then
            storage:save_all_jobs(self.hotbar_levels[1].data)
        else
            local level = self.hotbar_levels[idx]
            if level and level.combo then
                storage:anchor_job_section(level.combo, level.data)
                save_job = true
            end
        end
    end

    if save_job then
        storage:save_job_file()
    end

    self.dirty_levels = {}
end

return player