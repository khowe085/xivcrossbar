local env_chooser = {}

local text_setup = {
    flags = {
        draggable = false
    }
}

require('lists')

local ADD_NEW_SET = '+ Add New Set'

-- env_chooser metrics
env_chooser.hotbar_width = 0
env_chooser.hotbar_spacing = 0
env_chooser.slot_spacing = 0
env_chooser.pos_x = 0
env_chooser.pos_y = 0

-- env_chooser variables
env_chooser.feedback_icon = nil
env_chooser.hotbars = {}

-- env_chooser theme options
env_chooser.theme = {}

-- env_chooser control
env_chooser.feedback = {}
env_chooser.feedback.is_active = false
env_chooser.feedback.current_opacity = 0
env_chooser.feedback.max_opacity = 0
env_chooser.feedback.speed = 0

env_chooser.disabled_slots = {}
env_chooser.disabled_slots.actions = {}
env_chooser.disabled_slots.no_vitals = {}
env_chooser.disabled_slots.on_cooldown = {}
env_chooser.disabled_slots.on_warmup = {}

env_chooser.is_setup = false

env_chooser.is_shown = false
-----------------------------
-- Helpers
-----------------------------

-- setup text
function setup_text(text, theme_options)
    text:bg_alpha(0)
    text:bg_visible(false)
    text:font(theme_options.font)
    text:size(theme_options.font_size)
    text:color(theme_options.font_color_red, theme_options.font_color_green, theme_options.font_color_blue)
    text:stroke_transparency(theme_options.font_stroke_alpha)
    text:stroke_color(theme_options.font_stroke_color_red, theme_options.font_stroke_color_green, theme_options.font_stroke_color_blue)
    text:stroke_width(theme_options.font_stroke_width)
    text:show()
end

-- get x position for a given environment index
function env_chooser:get_name_x(i)
    local base = self.pos_x + 160
    return base
end

-- get y position for a given environment index
function env_chooser:get_name_y(i)
    local base = self.pos_y - (2.5 * self.hotbar_spacing)
    return base - (i * 15)
end

-----------------------------
-- Setup env_chooser
-----------------------------

-- setup env_chooser
function env_chooser:setup(theme_options)
    self.theme.slot_opacity = theme_options.slot_opacity
    self.theme.disabled_slot_opacity = theme_options.disabled_slot_opacity
    self.theme.button_layout = theme_options.button_layout

    self:setup_metrics(theme_options)
    self:load(theme_options)

    self.is_setup = true
end

-- load the ui
function env_chooser:load(theme_options)
    windower.prim.create('menu_background')
    windower.prim.set_color('menu_background', 150, 0, 0, 0)
    windower.prim.set_position('menu_background', self:get_name_x(1) - 10, self:get_name_y(4) - 10)
    windower.prim.set_size('menu_background', 290, 180)
    windower.prim.set_visibility('menu_background', false)

    windower.prim.create('menu_highlight')
    windower.prim.set_color('menu_highlight', 150, 171, 252, 252)
    windower.prim.set_position('menu_highlight', self:get_name_x(1) - 10, self:get_name_y(4) - 10)
    windower.prim.set_size('menu_highlight', 290, 15)
    windower.prim.set_visibility('menu_highlight', false)

    self.environments = {}
    for i=1,30,1 do
        self.environments[i] = {}
        self.environments[i].name_text = texts.new(text_setup)
        setup_text(self.environments[i].name_text, theme_options)
        self.environments[i].name_text:hide()
    end
end

-- setup positions and dimensions for env_chooser
function env_chooser:setup_metrics(theme_options)
    self.hotbar_width = (400 + theme_options.slot_spacing * 9)
    self.pos_x = (windower.get_windower_settings().ui_x_res / 2) - (self.hotbar_width / 2) + theme_options.offset_x
    self.pos_y = (windower.get_windower_settings().ui_y_res - 120) + theme_options.offset_y

    self.slot_spacing = theme_options.slot_spacing

    if theme_options.hide_action_names == true then
        theme_options.hotbar_spacing = theme_options.hotbar_spacing - 10
        self.pos_y = self.pos_y + 10
    end

    self.hotbar_spacing = theme_options.hotbar_spacing
end

function env_chooser:get_default_active_environment(player_hotbar)
    local names = L{}
    for environment_name, environment in pairs(player_hotbar) do
        names:append(environment_name)
    end
    names:sort()
    for i, name in ipairs(names) do
        return name
    end
end

function env_chooser:get_player_environments(player_hotbar)
    local environments = L{}

    for environment_name, environment in pairs(player_hotbar) do
        if (environment.name == nil) then
            environment.name = environment_name
        end
        environments:append(environment)
    end

    environments:sort(sortByName)

    environments:append({['name'] = ADD_NEW_SET})

    return environments
end

local HIDDEN_SPACE = "​" -- Invisible character for color formatting
local HAIRLINE = " "

function env_chooser:show_player_environments(player_hotbar, current_environment)
    self.current_environment = current_environment
    self.is_shown = true
    self.should_close_at = os.time()

    local environments = self:get_player_environments(player_hotbar)

    for i, environment in ipairs(environments) do
        local index = (#environments - i) + 1 -- put first environment at the top instead of bottom
        if (environment.name == ADD_NEW_SET) then
            self.environments[index].name_text:text(HAIRLINE .. '\\cs(0,255,128)' .. HIDDEN_SPACE .. environment.name)
            self.indexof_add_new_set = index
        else
            self.environments[index].name_text:text(HAIRLINE .. '\\cs(255,255,255)' .. HIDDEN_SPACE .. environment.name)
        end
        self.environments[index].name_text:pos(self:get_name_x(index), self:get_name_y(index))
        self.environments[index].name_text:show()
        if (kebab_casify(environment.name) == current_environment) then
            windower.prim.set_position('menu_highlight', self:get_name_x(index) - 10, self:get_name_y(index) - 2)
        end
    end

    local count = #environments
    windower.prim.set_position('menu_background', self:get_name_x(1) - 10, self:get_name_y(count) - 10)
    windower.prim.set_size('menu_background', 170, 15 + self:get_name_y(0) - self:get_name_y(count))
    windower.prim.set_visibility('menu_background', true)

    windower.prim.set_size('menu_highlight', 170, 16)
    windower.prim.set_visibility('menu_highlight', true)
end

function env_chooser:hide_player_environments()
    coroutine.schedule(maybe_hide_me, 0.25)
    coroutine.schedule(maybe_hide_me, 0.5)
    coroutine.schedule(maybe_hide_me, 0.75)
    coroutine.schedule(maybe_hide_me, 1)
end

function env_chooser:accept_text_entry()
    self.capturing = true
    local index = self.indexof_add_new_set
    local label = HAIRLINE .. '\\cs(0,255,128)' .. HIDDEN_SPACE .. ADD_NEW_SET
    local text_prompt = HAIRLINE .. '\\cs(0,255,128)' .. HIDDEN_SPACE .. '<Enter Set Name>'
    if (self.environments[index].name_text:text() == label) then
        self.new_set_name = ''
        self.environments[index].name_text:text(text_prompt)
    end
end

function env_chooser:send_key(char)
    if (self.capturing) then
        self.new_set_name = self.new_set_name .. char

        local index = self.indexof_add_new_set
        local text_prompt = HAIRLINE .. '\\cs(0,255,128)' .. HIDDEN_SPACE .. self.new_set_name
        self.environments[index].name_text:text(text_prompt)
    end
end

function env_chooser:send_backspace()
    if (self.capturing) then
        self.new_set_name = self.new_set_name:sub(1, -2)

        local text_prompt = ''
        if (self.new_set_name == '') then
            text_prompt = HAIRLINE .. '\\cs(0,255,128)' .. HIDDEN_SPACE .. '<Enter Set Name>'
        else
            text_prompt = HAIRLINE .. '\\cs(0,255,128)' .. HIDDEN_SPACE .. self.new_set_name
        end

        local index = self.indexof_add_new_set
        self.environments[index].name_text:text(text_prompt)
    end
end

function env_chooser:send_escape()
    if (self.capturing) then
        self:clear()
    end
end

function env_chooser:validate_new_set_name()
    local new_name = kebab_casify(self.new_set_name)
    for i, environment in pairs(env_chooser.environments) do
        if (new_name == kebab_casify(environment.name)) then
            return false
        end
    end

    return true
end

function env_chooser:get_new_set_name()
    return self.new_set_name
end


function env_chooser:clear()
    if (self.capturing) then
        self.new_set_name = nil
        hide_me()
    end
end

function maybe_hide_me()
    if (env_chooser.should_close_at < os.time()) then
        if (env_chooser.current_environment == kebab_casify(ADD_NEW_SET)) then
            env_chooser:accept_text_entry()
        else
            hide_me()
        end
    end
end

function hide_me()
    env_chooser.capturing = false
    env_chooser.is_shown = false

    for i, environment in pairs(env_chooser.environments) do
        env_chooser.environments[i].name_text:hide()
    end

    windower.prim.set_visibility('menu_background', false)
    windower.prim.set_visibility('menu_highlight', false)
end

function env_chooser:is_showing()
    return self.is_shown
end

function env_chooser:get_prev_environment(player_hotbar, current_environment)
    local last_was_current = false

    local environments = self:get_player_environments(player_hotbar)
    for i, environment in ipairs(environments) do
        if (last_was_current) then
            return kebab_casify(environment.name)
        end
        if (kebab_casify(environment.name) == current_environment) then
            last_was_current = true
        end
    end

    -- if we're here, the current environment is the last in the list so return the first
    return kebab_casify(environments[1].name)
end

function env_chooser:get_next_environment(player_hotbar, current_environment)
    local prev_name = nil
    local current_is_first = false
    local last_name = nil

    local environments = self:get_player_environments(player_hotbar)
    for i, environment in ipairs(environments) do
        if (kebab_casify(environment.name) == current_environment) then
            if (prev_name ~= nil) then
                return prev_name
            else
                current_is_first = true
            end
        else
            prev_name = kebab_casify(environment.name)
        end

        last_name = kebab_casify(environment.name)
    end

    -- if we're here, the current environment is the first in the last so return the last
    return last_name
end

-- HELPER FUNCTIONS
function sortByName(a, b)
    return a.name < b.name
end

function kebab_casify(str)
    if (str ~= nil) then
        if (type(str) == 'number') then
            return nil
        elseif (str.lower) then
            return str:lower():gsub(' ', '-'):gsub('\'', '')
        else
            return str
        end
    else
        return nil
    end
end

return env_chooser