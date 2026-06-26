-- Standalone round-trip test for storage.lua's Lua serializer / loader.
-- Runs under plain Lua 5.1 -- no Windower, no game client, no shell-out.
--
--   lua tests/storage/run_tests.lua
--
-- Every field, nested table and string (apostrophes, backslashes, embedded
-- double quotes, empty slots) must survive save -> reload byte-for-byte.

-- make require('storage') resolve relative to this script, not the CWD
local script_dir = (arg[0] or ''):match('^(.*[/\\])') or './'
package.path = script_dir .. '../../?.lua;' .. package.path

-----------------------------------------------------------------------------
-- stubs (defined before requiring storage)
-----------------------------------------------------------------------------

windower = { console = { write = print } }

-- file stub: every path is flattened into /tmp (which always exists) by turning
-- separators into underscores, so no directory ever needs to be created
local ROOT = '/tmp/xivtest_'
local function abs_path(rel)
    return ROOT .. rel:gsub('/', '_')
end

file = {}
file.new = function(rel)
    local abs = abs_path(rel)
    return {
        exists = function(self)
            local f = io.open(abs, 'r')
            if f then f:close() return true end
            return false
        end,
        create = function(self) end,   -- nothing to create: /tmp already exists
        read = function(self)
            local f = assert(io.open(abs, 'r'))
            local s = f:read('*all'); f:close(); return s
        end,
        write = function(self, s)
            local f = assert(io.open(abs, 'w'))
            f:write(s); f:close()
        end,
    }
end

-- start from a clean slate so a previous run cannot mask a regression
os.remove(abs_path('data/hotbar/Asura/Tester/General.lua'))
os.remove(abs_path('data/hotbar/Asura/Tester/RDM.lua'))

-----------------------------------------------------------------------------
-- helpers
-----------------------------------------------------------------------------

local function deep_copy(t)
    if type(t) ~= 'table' then return t end
    local c = {}
    for k, v in pairs(t) do
        c[k] = deep_copy(v)
    end
    return c
end

-- recursive comparison; on the first mismatch print the key path and both
-- values, then error() so the process exits non-zero
local function deep_equal(a, b, label, path)
    path = path or label
    if type(a) ~= type(b) then
        print('MISMATCH at ' .. path .. ': type ' .. type(a) .. ' (' .. tostring(a) ..
              ') vs ' .. type(b) .. ' (' .. tostring(b) .. ')')
        error(label .. ' failed', 0)
    end
    if type(a) ~= 'table' then
        if a ~= b then
            print('MISMATCH at ' .. path .. ': ' .. tostring(a) .. ' vs ' .. tostring(b))
            error(label .. ' failed', 0)
        end
        return
    end
    for k, v in pairs(a) do
        deep_equal(v, b[k], label, path .. '.' .. tostring(k))
    end
    for k, v in pairs(b) do
        if a[k] == nil then
            print('MISMATCH at ' .. path .. '.' .. tostring(k) ..
                  ': missing in expected, present in actual (' .. tostring(v) .. ')')
            error(label .. ' failed', 0)
        end
    end
end

-----------------------------------------------------------------------------
-- fixtures
-----------------------------------------------------------------------------

-- Fixture A: General.lua data -- a Field environment spanning 3 hotbars whose
-- slots exercise every action field and every string-escaping edge case.
local gen_input = {
    sets = {
        ['field'] = {
            name = 'Field',
            hotbar_1 = {
                slot_1 = { type = 'ma', action = 'Cure', target = 'stpc' },
                slot_2 = { type = 'ja', action = "Monk's Focus", alias = "Mon'k" },          -- apostrophes
                slot_3 = { type = 'ws', action = "Stone's Throw", icon = 'icons\\ws\\stone.png' }, -- backslashes + apostrophe
            },
            hotbar_2 = {
                slot_4 = { type = 'item', action = 'Hi-Potion', target = 'me', warmup = '0.5', cooldown = '30' },
                slot_5 = { type = 'ct', action = 'gs c activate Idle' },
                slot_6 = { type = 'enchanteditem', action = 'Reraise Earring', equip_slot = 'ear1', usable = 'true' },
            },
            hotbar_3 = {
                slot_7 = {},                                                                 -- empty slot
                slot_8 = { type = 'ex', action = 'input /equip main "Excalibur"' },          -- embedded double quotes
            },
        },
    },
}

-- Fixture B: RDM.lua data -- top-level keys are section/combo names, each value
-- is a level.data-shaped { sets = ... } table.
local job_input = {
    ['RDM-DEFAULT'] = {
        sets = {
            ['battle'] = {
                name = 'Battle',
                hotbar_1 = {
                    slot_1 = { type = 'ja', action = 'Composure' },
                    slot_2 = { type = 'ma', action = 'Refresh', target = 'me' },
                    slot_3 = { type = 'ws', action = 'Savage Blade', target = 't' },
                },
            },
        },
    },
    ['RDM-SCH'] = {
        sets = {
            ['scholar'] = {
                name = 'Scholar',
                hotbar_1 = {
                    slot_1 = { type = 'ma', action = 'Stone' },
                    slot_2 = { type = 'ma', action = 'Aero' },
                    slot_3 = { type = 'ma', action = 'Cure' },
                },
                hotbar_2 = {
                    slot_1 = { type = 'ja', action = 'Light Arts' },
                    slot_2 = { type = 'ja', action = 'Dark Arts' },
                },
            },
        },
    },
    ['RDM-SCH-LA'] = {
        sets = {
            ['scholar'] = {
                name = 'Scholar',
                hotbar_1 = {
                    slot_1 = { type = 'ma', action = 'Regen' },
                    slot_2 = { type = 'ma', action = 'Protect' },
                },
            },
        },
    },
    ['RDM-SCH-LA-AW'] = {
        sets = {
            ['scholar'] = {
                name = 'Scholar',
                hotbar_1 = {
                    slot_1 = { type = 'ma', action = 'Sublimation' },
                    slot_2 = { type = 'ma', action = 'Reraise' },
                },
            },
        },
    },
    ['RDM-SCH-DA'] = {
        sets = {
            ['scholar'] = {
                name = 'Scholar',
                hotbar_1 = {
                    slot_1 = { type = 'ma', action = 'Bio' },
                    slot_2 = { type = 'ma', action = 'Poison' },
                },
            },
        },
    },
    ['RDM-SCH-DA-AB'] = {
        sets = {
            ['scholar'] = {
                name = 'Scholar',
                hotbar_1 = {
                    slot_1 = { type = 'ma', action = 'Dispel' },
                    slot_2 = { type = 'ma', action = 'Sleep' },
                },
            },
        },
    },
    ['RDM-WAR'] = {
        sets = {
            ['warrior'] = {
                name = 'Warrior',
                hotbar_1 = {
                    slot_1 = { type = 'ja', action = 'Provoke', target = 't' },
                    slot_2 = { type = 'ja', action = 'Berserk' },
                },
            },
        },
    },
    ['RDM-NOSUB'] = {
        sets = {
            ['field'] = {
                name = 'Field',
                hotbar_1 = {
                    slot_1 = { type = 'ma', action = 'Teleport-Holla' },
                    slot_2 = { type = 'ct', action = 'heal' },
                },
            },
        },
    },
}

-----------------------------------------------------------------------------
-- test
-----------------------------------------------------------------------------

local storage = require('storage')
storage:setup({ server = 'Asura', name = 'Tester', main_job = 'RDM', sub_job = 'SCH' })

-- SAVE
storage:save_all_jobs(gen_input)            -- serialize gen_input -> General.lua
storage.job_data = deep_copy(job_input)
storage:save_job_file()                     -- serialize job_input -> RDM.lua

-- RELOAD (simulate a fresh session: drop all in-memory state)
storage.job_data = nil
storage:update_filename('RDM', 'SCH')       -- reloads RDM.lua into storage.job_data
local gen_out = storage:load_all_jobs()     -- reads General.lua
local job_out = deep_copy(storage.job_data)

-- ASSERT full round-trip
deep_equal(gen_input, gen_out, 'General.lua round-trip')
deep_equal(job_input, job_out, 'RDM.lua round-trip')

-- spot checks on the trickiest values / behaviours
assert(gen_out.sets['field'].hotbar_1.slot_2.action == "Monk's Focus", 'apostrophe value lost')
assert(gen_out.sets['field'].hotbar_1.slot_3.icon == 'icons\\ws\\stone.png', 'backslash value lost')
assert(gen_out.sets['field'].hotbar_3.slot_8.action == 'input /equip main "Excalibur"', 'embedded quote value lost')
assert(type(gen_out.sets['field'].hotbar_3.slot_7) == 'table', 'empty slot dropped')
assert(next(gen_out.sets['field'].hotbar_3.slot_7) == nil, 'empty slot not empty after round-trip')
assert(gen_out.sets['field'].hotbar_2.slot_6.usable == 'true', 'string "true" must not become a boolean')
assert(job_out['RDM-WAR'] ~= nil, 'unrelated subjob section did not survive save/reload')

-- section lookups used by player.lua at load time
assert(storage:get_job_section('RDM-DEFAULT') ~= nil, 'job-default section lookup failed')
assert(storage:get_job_section('RDM-SCH') ~= nil, 'job-sub section lookup failed')
assert(storage:get_job_section('RDM-XXX') == nil, 'missing section must be nil')

print('ALL TESTS PASSED')
