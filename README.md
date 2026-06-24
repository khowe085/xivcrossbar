Forked off of AliekberFFXI's xivcrossbar!

Fixes:

    Corrected pet abilites not showing up in the Add Ability GUI

    Fixed Ninja Tools not showing a count if using master tools


Additions:

    Added Scholar Strategem Count to abilities that use them

    Added option in settings (AutoHideExtraBars) that will hide extra bars 5&6 until you double-tap LT or RT

	Added options in settings to adjust offsets of hotbars relative to hotbar 1 when not in the Alternative layout

    Added Alternate Layout (UseAltLayout) that mimics FFXIV's alt layout, where the left side will always be dpad and right side will be face buttons. Note: This makes editing the xmls a litte more confusing, as it alternates what is shows. For example, from left to right on your screen you will now see hotbar_1 slots 1-4, then hotbar_2 slots 1-4, then hotbar_1 slots 5-8 and finally hotbar_2 slots 5-8. Keep that in mind if manually editing the xmls.

Hotbar File Hierarchy & Light/Dark Arts Overlays:

    Your hotbars are no longer one single active environment file. Instead they are built by merging several XML files together, lowest priority to highest. All of these live under data/hotbar/{Server}/{Character}/:

        ALL-JOBS-DEFAULT.xml          - applies to every job
        {MAINJOB}-DEFAULT.xml         - e.g. RDM-DEFAULT.xml, applies to that main job on any subjob
        {MAINJOB}-{SUBJOB}.xml        - e.g. RDM-SCH.xml, the specific job/subjob combo

    The merge happens slot-by-slot. When the same set name shows up in more than one file, a higher-priority file fills only the slots it actually defines, and any slot it leaves empty falls through to the lower-priority file. So you can define your common actions once in a broad file (like ALL-JOBS-DEFAULT.xml) and let the job/subjob files fill in just the slots that differ - no need to redefine a whole set for every combo. A set that only exists in one file just appears on its own.

    Light Arts / Dark Arts overlays:

        You can also make optional overlay files named {MAINJOB}-{SUBJOB}-lightarts.xml and {MAINJOB}-{SUBJOB}-darkarts.xml (e.g. RDM-SCH-lightarts.xml). When you activate Light Arts or Dark Arts in-game - by any means, gamepad, hotbar, or the /ja command - the matching overlay file gets layered on top of your current sets and merges slot-by-slot just like the others. Switching arts swaps the overlay; changing job or subjob clears it. If the overlay file doesn't exist, nothing happens - it's entirely optional and safe to omit. Only Light Arts and Dark Arts are supported as overlays.

    In-game editing lands in the most-specific file that defines the slot:

        Loading is strictly read-only: switching characters, logging in, or changing job never writes any hotbar files. When a file is missing, an empty default set is still built in memory so it shows up in the editor - it just isn't written to disk until you actually edit it.

        Any edit you make through the in-game editor (adding, moving, deleting, re-aliasing, or re-iconing a slot) is routed to the most-specific file that already defines that slot, and only the file it actually touches gets written. The default target is {MAINJOB}-DEFAULT.xml: a fresh edit, or an edit to a slot that nothing else defines, lands there. If the slot is already defined in {MAINJOB}-{SUBJOB}.xml or in an active Light/Dark Arts overlay file, the edit lands in that file instead, so it takes effect right where you see it. ALL-JOBS-DEFAULT.xml is never written from in-game; a slot that exists only there gets a job-level override written into {MAINJOB}-DEFAULT.xml. Deleting removes the most-specific copy of the slot, so any lower-tier copy simply reappears on the next merge - a slot that exists only in ALL-JOBS-DEFAULT.xml can't be deleted in-game and must be removed by hand. Those broader files, and the Light/Dark Arts overlays, can still be hand-edited in a text editor whenever you like.

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
