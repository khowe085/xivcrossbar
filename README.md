Forked off of AliekberFFXI's xivcrossbar!

Fixes:

    Corrected pet abilites not showing up in the Add Ability GUI

    Fixed Ninja Tools not showing a count if using master tools


Additions:

    Added Scholar Strategem Count to abilities that use them

    Added option in settings (AutoHideExtraBars) that will hide extra bars 5&6 until you double-tap LT or RT

	Added options in settings to adjust offsets of hotbars relative to hotbar 1 when not in the Alternative layout

    Added Alternate Layout (UseAltLayout) that mimics FFXIV's alt layout, where the left side will always be dpad and right side will be face buttons. Note: This makes editing the hotbar data files a litte more confusing, as it alternates what is shows. For example, from left to right on your screen you will now see hotbar_1 slots 1-4, then hotbar_2 slots 1-4, then hotbar_1 slots 5-8 and finally hotbar_2 slots 5-8. Keep that in mind if manually editing the data files.

Hotbar File Layout & Light/Dark Arts Overlays:

    Your hotbars are built by merging several layers together, lowest priority to highest. They are stored as Lua data files under data/hotbar/{Server}/{Character}/:

        General.lua    - the all-jobs layer; applies to every job
        {MAINJOB}.lua  - e.g. RDM.lua; holds every job-specific layer for that main job

    {MAINJOB}.lua is a single file containing named sections - one per layer - keyed by a combo string:

        {MAINJOB}-DEFAULT        - applies to that main job on any subjob
        {MAINJOB}-{SUBJOB}       - e.g. RDM-SCH, the specific job/subjob combo
        {MAINJOB}-{SUBJOB}-LA    - Light Arts overlay (optional)
        {MAINJOB}-{SUBJOB}-DA    - Dark Arts overlay (optional)
        {MAINJOB}-{SUBJOB}-LA-AW - Addendum: White overlay (optional)
        {MAINJOB}-{SUBJOB}-DA-AB - Addendum: Black overlay (optional)

    The merge happens slot-by-slot, in priority order (lowest first): General.lua -> {MAINJOB}-DEFAULT -> {MAINJOB}-{SUBJOB} -> arts overlay -> addendum overlay. When the same set name shows up in more than one layer, a higher-priority layer fills only the slots it actually defines, and any slot it leaves empty falls through to the lower-priority layer. So you can define your common actions once in a broad layer (like General.lua) and let the job/subjob layers fill in just the slots that differ - no need to redefine a whole set for every combo. A set that only exists in one layer just appears on its own.

    Light Arts / Dark Arts and Addendum overlays:

        The arts overlay sections ({MAINJOB}-{SUBJOB}-LA / -DA) layer on top of your current sets when you activate Light Arts or Dark Arts in-game - by any means, gamepad, hotbar, or the /ja command - and merge slot-by-slot just like the others. Switching arts swaps the overlay; changing job or subjob clears it. If the section doesn't exist, nothing happens - overlays are entirely optional and safe to omit.

        Scholar can stack a second overlay on top of the active arts: the {MAINJOB}-{SUBJOB}-LA-AW section layers on when you use Addendum: White (over Light Arts), and {MAINJOB}-{SUBJOB}-DA-AB layers on when you use Addendum: Black (over Dark Arts). These sit above the arts overlay in priority; switching arts clears the addendum overlay along with it.

    Defaults on a fresh character:

        With no data files present, General.lua is auto-created with a Field environment (shared across all jobs), and the {MAINJOB}-DEFAULT section of {MAINJOB}.lua is auto-created with a General environment. The job/subjob section starts empty and only appears once you edit it. Nothing is written to disk just from loading the addon or logging in - files are written on your first save.

    In-game editing and the edit target:

        By default, every edit you make through the in-game editor (adding, moving, deleting, re-aliasing, or re-iconing a slot) is written to the {MAINJOB}-DEFAULT section of {MAINJOB}.lua - the job-default layer.

        You can change where edits land with the "Select Edit Target" option in the action binder menu (the same menu you use to assign actions). It lets you point your edits at any layer: All Jobs Default (General.lua), Job Default, Job + Sub Default, the Light/Dark Arts overlays, or the Addendum: White/Black overlays. The selected target resets back to Job Default on reload and on every job change.

        General.lua and {MAINJOB}.lua are plain Lua tables and can still be made or edited by hand in a text editor. The in-game editor writes them too, but a job/subjob or overlay section is only written once you point the edit target at that layer and edit it. When a section is missing, a default set is still built in memory so it shows up in the editor; it just isn't written to disk until you edit it with that layer selected.

        One thing to keep in mind: because in-game edits land in the job-default layer by default - which sits below the job/subjob layer and the arts overlays in priority - if you hand-define the same slot in the {MAINJOB}-{SUBJOB} section or in an arts/addendum section, that higher-priority layer wins in the merged view and your in-game edit to that slot won't show. Either edit it in the layer that defines it, or switch the edit target to that layer. Likewise, deleting a slot only clears the copy in the currently selected target; a copy defined in a higher-priority layer reappears on the next merge.

Controller changes:

    The controller AHK will now auto-select FFXI window if FFXI is not the active window when pushing one of the 4 facebuttons!


Steps to get XIVCrossbar working:

1) Install Autohotkey (https://www.autohotkey.com/)

OR (for Steam Deck users)

1b) Add the following line to your init.txt Windower script, changing the path as appropriate to point to your FFXI_Input.sh:

    run C:/Windows/System32/cmd.exe /c start /unix /home/deck/Games/final-fantasy-xi-online/FFXI_Input.sh

OR (for 2026 Steam Controller users)

1c) Apply steam input profile steam://controllerconfig/230330/3750616172
	- Note: If you don't it to open the AHK script on load, you can disable it in the settings!
	
2) Enable the "Run" plugin in Windower

3) Run FFXI Configuration tool and set up your gamepad to match ConfigureYourGamepadLikeThis.jpg. Green box = required to have set, Red box = required to leave blank, Yellow box = configure it the way you usually do.

4) There are two options to automatically load xivcrossbar. Either editing your gearswap, or adding the load command to windower.

    a) If you want to only use xivcrossbar for specific jobs then add the following to your Gearswap LUA for any jobs where you want to use the crossbar. If you already have these functions defined, simply add the "windower.send_command" line in each of them to the existing function.

    function user_setup()
        windower.send_command('lua load xivcrossbar')
    end

    function user_unload()
        windower.send_command('lua unload xivcrossbar')
    end

    function job_setup()
        windower.send_command('lua reload xivcrossbar')
    end

   OR
   
   b) In Windower's init.txt, add the line "lua load xivcrossbar". This will load xivcrossbar for all jobs. Windower executes each line, from top to bottom, of the file so keep in mind the order of loading addons. This should not conflict with any other.
   
6) Follow the instructions in the setup dialog shown in-game.

    a) If you're using an XInput controller, everything should Just Work.

    b) If you're using a DirectInput controller that is a Wired Fight Pad Pro for Nintendo Switch, everything should Just Work.

    c) If you're using a DirectInput controller that is something else, you may need to modify the button numbers in ffxi_directinput.ahk. You can use the AHK script at https://www.autohotkey.com/docs_1.0/scripts/JoystickTest.htm to determine what your button numbers are. In ffxi_directinput.ahk you shouldn't need to change ANY lines other than changing lines like `Joy10::` to `Joy4::`, and any corresponding lines like `if GetKeyState("Joy10")` to `if GetKeyState("Joy4")`, and so forth. Everything else can be configured through the addon in-game.

7) Minus button (Nintendo), Share button (PS4) or Back button (XBox) brings up the gamepad binding utility, and can also exit out of it.

8) Plus button (Nintendo), Options button (PS4) or Start button (XBox) brings up binding set selector as long as it is held down, and you can switch between different binding sets by using your dpad.

9) Once you're used to the button placement, I recommend updating your settings xml to use the compact layout, just to reclaim some screen real estate.

10) If you want a 4th crossbar in each set, you can set the crossbar number to 4 in settings, which will make the 3rd and 4th crossbars dependent on which trigger you press first. L -> R is Crossbar 4, and R -> L is Crossbar 3.

11) If you want to have 6 crossbars in each set, you can set the crossbar number to 6 in settings, do the same as above but also add Crossbar 5 (activated when you double-press L) and Crossbar 6 (activated when you double-press R).

12) Enjoy!

NOTE: The crossbar unbinds any existing bindings for Ctrl+F1 through Ctrl+F12 because it uses those buttons as proxies for the gamepad. Any Alt, Shift, or neutral bindings to F1-F12 will be unaffected. Ctrl is used for the bindings rather than Alt because Alt has a tendency to get "stuck" when Alt-Tabbing in and out, and can lead to accidental ability use. However, while Ctrl+F9 through Ctrl+F12 are completely locked down by this addon, you can re-add your Ctrl+F1 through Ctrl+F8 bindings by editing function_key_bindings.lua.

NOTE: in order to capture dpad inputs without affecting the underlying game, you will need to hold down at least one of the triggers for XIVCrossbar to be able to use its input. This should really only be noticeable when navigating the gamepad binding utility.
