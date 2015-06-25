local module    = {
--- === hs._asm.hotkey ===
---
--- Create and manage global keyboard shortcuts
---
}

local keycodes  = require("hs.keycodes")
local fnutils   = require("hs.fnutils")
local et        = require("hs.eventtap")
local et_events = require("hs.eventtap.event")
local timer     = require("hs.timer")

-- since we pass through to the actual utf8 library if it exists, this works for lua 5.2 and lua 5.3
local utf8      = require("hs.utf8")

local definedHotkeys = {}

local modKeys = {
    -- sort order intuited from System Preferences Keyboard Shortcuts screen..
    -- no special for 'fn' that I could find, so using ƒ since it's 'f' like, but "different"
    ["fn"]    = {utf8.codepointToUTF8("U+0192"), 1},
    ["ctrl"]  = {utf8.registeredKeys.ctrl      , 2},
    ["alt"]   = {utf8.registeredKeys.alt       , 3},
    ["shift"] = {utf8.registeredKeys.shift     , 4},
    ["cmd"]   = {utf8.registeredKeys.cmd       , 5},
}

-- Problem keys... these set the fn=true mod whenever they are pressed.
local problemKeys = {
    [125] = "down",
    [123] = "left",
    [124] = "right",
    [126] = "up",
    [122] = "f1",
    [120] = "f2",
    [99]  = "f3",
    [118] = "f4",
    [96]  = "f5",
    [97]  = "f6",
    [98]  = "f7",
    [100] = "f8",
    [101] = "f9",
    [109] = "f10",
    [103] = "f11",
    [111] = "f12",
    [105] = "f13",
    [107] = "f14",
    [113] = "f15",
    [119] = "end",
    [117] = "forwarddelete",
    [121] = "pagedown",
    [116] = "pageup",
    [114] = "help",
    [115] = "home",

-- assumed because I don't have them on my keyboard
    [106] = "f16",
    [64]  = "f17",
    [79]  = "f18",
    [80]  = "f19",
    [90]  = "f20",
    [71]  = "padclear",  -- on my keyboard, this corresponds to NumLock, which does have FN set

--    [81] = "pad=",      -- assumed not, but I also don't have it on my keyboard
}

-- defined out here because they are used in multiple places...
local keyEnable = function(self)
    self.active = true
    self.fired = false

    local testKey = module.duplicatedKey(self)
    if testKey then
        print("-- warning: duplicate keybinding: "..tostring(testKey))
    end
    return self
end
local keyDisable = function(self)
    self.active = false
    self.fired = false
    return self
end

local _hotKey_metatable = {
    __index     = {
--- hs._asm.hotkey:enable() -> hotkeyObject
--- Method
--- Enables a hotkey object
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `hs.hotkey object`
        enable  = keyEnable,
--- hs._asm.hotkey:disable() -> hotkeyObject
--- Method
--- Disables a hotkey object
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `hs.hotkey object`
        disable = keyDisable,
        desc    = function(self, x)
                      if type(x) ~= nil then
                          self.label = tostring(x)
                      end
                      return self
                  end,
        getDesc = function(self) return self.label end,
        label   = nil,
        owner   = nil,
        fired   = false,
    },
    __tostring  = function(self)
                      local o = (self.active and "active" or "inactive").." "..
                                (self.owner  and "modal"  or "global").." hotkey '"
                      local m = ""
                      for k,v in fnutils.sortByKeys(self.mods,
                          function(m,n) return modKeys[m][2] < modKeys[n][2] end) do
                              m = m..modKeys[k][1]
                      end
                      o = o..(m ~= "" and m.." " or "")..keycodes.map[self.keyCode].."'"
                      if self.label then o = o..": "..self.label end
                      return o
                  end,
    __gc        = function(self) self:disable() end,
}

local function wrap(fn)
    return function()
        if fn then
            local ok, err = xpcall(fn, debug.traceback)
            if not ok then hs.showError(err) end
        end
    end
end

module.keys    = definedHotkeys -- remove after testing

module.sameKey = function(k1, k2) -- compares active, mods, and keyCode hash tags only
    if k1.active  ~= k2.active  then return false end
    if k1.keyCode ~= k2.keyCode then return false end
    for i in pairs(k1.mods) do if k1.mods[i] ~= k2.mods[i] then return false end end
    for i in pairs(k2.mods) do if k1.mods[i] ~= k2.mods[i] then return false end end
    return true
end
module.duplicatedKey = function(k1)
    for _,k2 in ipairs(definedHotkeys) do
        if k1 ~= k2 and module.sameKey(k1, k2) then return k2 end
    end
    return false
end

--- hs._asm.hotkey.new(mods, key, pressedfn[, releasedfn, repeatfn]) -> hotkeyObject or nil
--- Constructor
--- Creates a new hotkey
---
--- Parameters:
---  * mods - A table containing the keyboard modifiers required, which should be zero or more of the following strings:
---   * cmd
---   * alt
---   * shift
---   * ctrl
---   * fn
---  * key - A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---  * pressedfn - A function that will be called when the hotkey has been pressed
---  * releasedfn - An optional function that will be called when the hotkey has been released
---  * repeatfn - An optional function that will be called when a pressed hotkey is repeating
---
--- Returns:
---  * An `hs._asm.hotkey` object, or nil if an error occurred

module.new = function(mods, key, pressedfn, releasedfn, repeatfn)
    local keycode

    if (key:sub(1, 1) == '#') then
        keycode = tonumber(key:sub(2))
    else
        keycode = keycodes.map[tostring(key):lower()]
    end

    if not keycode then
        print("Error: Invalid key: "..key)
        return nil
    end

    local _pressedfn  = pressedfn  and wrap(pressedfn)
    local _releasedfn = releasedfn and wrap(releasedfn)
    local _repeatfn   = repeatfn   and wrap(repeatfn)

    local modsAsHash = {}
    for _,m in ipairs(mods) do
        for i,v in pairs(modKeys) do
            if tostring(m):lower() == i or tostring(m):lower() == v[1] then
                modsAsHash[i] = true
            end
        end
    end

    -- keys which always return with 'fn' set
    if problemKeys[keycode] then modsAsHash["fn"] = true end

    local k = setmetatable({
                              mods      = modsAsHash,
                              keyCode   = keycode,
                              keyDown   = _pressedfn,
                              keyUp     = _releasedfn,
                              keyRepeat = _repeatfn,
                              active    = false,
                          }, _hotKey_metatable)

    table.insert(definedHotkeys, k)

    return k
end

--- hs._asm.hotkey.bind(mods, key, pressedfn, releasedfn, repeatfn) -> hotkeyObject or nil
--- Constructor
--- Creates a hotkey and enables it immediately
---
--- Parameters:
---  * mods - A table containing the keyboard modifiers required, which should be zero or more of the following strings:
---   * cmd
---   * alt
---   * shift
---   * ctrl
---   * fn
---  * key - A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---  * pressedfn - A function that will be called when the hotkey has been pressed
---  * releasedfn - An optional function that will be called when the hotkey has been released
---  * repeatfn - An optional function that will be called when a pressed hotkey is repeating
---
--- Returns:
---  * An `hs._asm.hotkey` object or nil if an error occurred
---
--- Notes:
---  * This function is a simple wrapper that performs: `hs._asm.hotkey.new(mods, key, pressedfn, releasedfn, repeatfn):enable()`
module.bind = function(...)
    local key = module.new(...)
    if key then
        return key:enable()
    else
        return nil
    end
end

--- === hs._asm.hotkey.modal ===
---
--- Create/manage modal keyboard shortcut environments
---
--- This would be a simple example usage:
---
---     k = hs._asm.hotkey.modal.new({"cmd", "shift"}, "d")
---
---     function k:entered() hs.alert.show('Entered mode') end
---     function k:exited()  hs.alert.show('Exited mode')  end
---
---     k:bind({}, 'escape', function() k:exit() end)
---     k:bind({}, 'J', function() hs.alert.show("Pressed J") end)

local _modal_metatable = {
    __index = {
--- hs._asm.hotkey.modal:entered()
--- Method
--- Optional callback for when a modal is entered; default implementation does nothing.
        entered = function(self)
        end,

--- hs._asm.hotkey.modal:exited()
--- Method
--- Optional callback for when a modal is exited; default implementation does nothing.
        exited = function(self)
        end,

--- hs._asm.hotkey.modal:bind(mods, key, pressedfn, releasedfn, repeatfn)
--- Method
---
--- Parameters:
---  * mods - A table containing the keyboard modifiers required, which should be zero or more of the following strings:
---   * cmd
---   * alt
---   * shift
---   * ctrl
---  * key - A string containing the name of a keyboard key (as found in [hs.keycodes.map](hs.keycodes.html#map) ), or if the string begins with a `#` symbol, the remainder of the string will be treated as a raw keycode number
---  * pressedfn - A function that will be called when the hotkey has been pressed
---  * releasedfn - An optional function that will be called when the hotkey has been released
---  * repeatfn - An optional function that will be called when a pressed hotkey is repeating
---
--- Returns:
---  * An `hs._asm.hotkey.modal` object or nil if an error occurred
---
        bind = function(self, mods, key, pressedfn, releasedfn, repeatfn)
            local k = module.new(mods, key, pressedfn, releasedfn, repeatfn)
            k.owner = self
            table.insert(self.keys, k)
            return self
        end,

--- hs._asm.hotkey.modal:enter()
--- Method
--- Enables all hotkeys created via `modal:bind` and disables the modal itself.
--- Called automatically when the modal's hotkey is pressed.
        enter = function(self)
            if (self.k) then
                self.k:disable()
            end
            fnutils.each(self.keys, keyEnable)
            self.entered()
            return self
        end,

--- hs._asm.hotkey.modal:exit()
--- Method
--- Disables all hotkeys created via `modal:bind` and re-enables the modal itself.
        exit = function(self)
            fnutils.each(self.keys, keyDisable)
            if (self.k) then
                self.k:enable()
            end
            self.exited()
            return self
        end,
        desc    = function(self, x)
                      if type(x) ~= nil then
                          self.label = tostring(x)
                      end
                      return self
                  end,
        getDesc = function(self) return self.label end,
        label   = nil,
    },
    __tostring  = function(self)
                  local o = "modal hotkey set"
                  if self.label then o = o..": "..self.label end
                  return o
              end,
}

module.modal = {}

--- hs._asm.hotkey.modal.new(mods, key) -> modal
--- Constructor
--- Creates a new modal hotkey and enables it.
--- When mods and key are pressed, all keys bound via `modal:bind` will be enabled.
--- They are disabled when the "mode" is exited via `modal:exit()`
--- If mods and key are both nil, the modal state will be created with no top-level hotkey to enter the modal state. This is useful where you want a modal state to exist, but be entered programatically.
module.modal.new = function(mods, key)
    if ((mods and not key) or (not mods and key)) then
        hs.showError("Incorrect use of hs._asm.hotkey.modal.new(). Both parameters must either be valid, or nil. You cannot mix valid and nil parameters")
        return nil
    end
    local m = setmetatable({keys = {}}, _modal_metatable)
    if (mods and key) then
        m.k = module.bind(mods, key, function() m:enter() end)
    end
    return m
end

local buildEventWatcher = function()
    return et.new({
            et_events.types.keyDown,
            et_events.types.keyUp,

    -- apparently OS X disables eventtaps if it thinks they are slow or odd or just because the moon
    -- is wrong in some way... but at least it's nice enough to tell us.

            et_events.tapDisabledByTimeout,
            et_events.tapDisabledByUserInput,

        }, function(theEvent)

            -- long pauses make OS X event tap notifier sad...
            -- let's see if this helps by stopping it until
            -- we're done.

            module.eventWatcher:stop()

            local weAteTheEvent   = nil
            local whyWeWereCalled = theEvent:getType()

            if (whyWeWereCalled == et_events.types.tapDisabledByTimeout) or
               (whyWeWereCalled == et_events.types.tapDisabledByUserInput) then
                    print("-- "..os.date("%c",os.time())..": hotkey event tap restarted")
                    weAteTheEvent = true
            else
                local eventKey = {
                    keyCode = theEvent:getKeyCode(),
                    mods    = theEvent:getFlags(),
                    active  = true
                }

                local matchedKey = module.duplicatedKey(eventKey)

                if matchedKey then
                    if whyWeWereCalled == et_events.types.keyDown then
                        if not matchedKey.fired then
                            matchedKey.fired = true
                            if matchedKey.keyDown then matchedKey.keyDown() end
                        else
                            if matchedKey.keyRepeat then matchedKey.keyRepeat() end
                        end
                    else
                        matchedKey.fired = false
                        if matchedKey.keyUp then matchedKey.keyUp() end
                    end
                    weAteTheEvent = true
                else
                    weAteTheEvent = false
                end
            end

            if type(weAteTheEvent) == "nil" then
                weAteTheEvent = false
                print("-- "..os.date("%c",os.time())..": hotkey check result nil? Should not happen; check code...")
            end

            -- Now turn event watcher back on and return

            module.eventWatcher:start()
            return weAteTheEvent
        end
    ):start()
end

module.eventWatcher = hs.timer.new(1, function()
        if hs.accessibilityState() then
            module.eventWatcher:stop()
            print("-- Starting hs.hotkey eventtap")
            module.eventWatcher = buildEventWatcher()
        end
    end):start()

module = setmetatable(module, {
        __gc = function(self) if type(self.eventWatcher) == "userdata" then self.eventWatcher:stop() end end,
})

return module

