// Possibly of interest to some --
//
// All of this has been done successfully in Lua using hs.eventtap as the only component
// written in Objective-C.  However, such a solution means that the embedded Lua interpreter
// is invoked for the keyUp and keyDown event of *every single key stroke* typed on the
// computer once it is running.  The overhead was causing periods of slow keyboard response
// and even occasional dropouts when the OS decided Hammerspoon was taking too long to
// determine if a key matched a callback or not.
//
// This code does replicate hs.eventtap to some degree, but is written specifically so that the
// event watching and callback function only involve the Lua interpreter when a specific key press
// matches a registered hotkey -- if it doesn't, the event is immediately passed on, reducing
// overhead to almost nothing when Hammerspoon isn't the intended target of the keypress.
//
// Don't get me wrong -- Lua's fast.  This is faster.

#import <Cocoa/Cocoa.h>
// #import <lua/lauxlib.h>
// #include "../hammerspoon.h"
#import <lauxlib.h>
#define CLS_NSLOG NSLog
void showError(lua_State *L, char *message) {
    lua_getglobal(L, "hs");
    lua_getfield(L, -1, "showError");
    lua_remove(L, -2);
    lua_pushstring(L, message);
    lua_pcall(L, 1, 0, 0);
}

// From CGEventTypes.h and IOLLEvent.h -- this is what the Flag Mask will be made of.
//
//   kCGEventFlagMaskShift =               NX_SHIFTMASK,
//   kCGEventFlagMaskControl =             NX_CONTROLMASK,
//   kCGEventFlagMaskAlternate =           NX_ALTERNATEMASK,
//   kCGEventFlagMaskCommand =             NX_COMMANDMASK,
//   kCGEventFlagMaskSecondaryFn =         NX_SECONDARYFNMASK,
//
//   #define    NX_SHIFTMASK        0x00020000
//   #define    NX_CONTROLMASK      0x00040000
//   #define    NX_ALTERNATEMASK    0x00080000
//   #define    NX_COMMANDMASK      0x00100000
//   #define    NX_SECONDARYFNMASK  0x00800000

#define FLAGS_WE_WANT ( kCGEventFlagMaskShift       | \
                        kCGEventFlagMaskControl     | \
                        kCGEventFlagMaskAlternate   | \
                        kCGEventFlagMaskCommand     | \
                        kCGEventFlagMaskSecondaryFn )

static NSMutableArray*  keysToWatchFor;

static CFMachPortRef      hotkeyTap ;
static CFRunLoopSourceRef hotkeyRunLoopSrc ;
static int                luaCallbackPart ;

// hs._asm.hotkey.registerKeyToWatch(keycode, flagcode) -> bool
// Function
// Add the specified keycode and flags (modifier keys) to the watch list for the hotkey eventtap.
//
// Parameters:
//  * keycode  -- the numeric keycode for the key to watch for as described in `hs.keycodes.map`
//  * flagcode -- the numeric mask representing the flags (modifier keys) which accompany the key to watch for.
//
// Returns:
//  * True if the hotkey was added to the watch list or false if it was not (because it already exists in the watch list).
//
// Notes:
//  * This function is used internally by hs._asm.hotkey and should not be invoked directly unless (a) you really really really know what you're doing, or (b) you like screwing things up.  This function has been stored without public reference in the metatable for this reason.
static int registerKey(lua_State* L) {
    NSInteger keycode = luaL_checkinteger(L, 1) ;
    NSInteger flags   = luaL_checkinteger(L, 2) ;
    NSArray *myKey    = @[[NSNumber numberWithInteger:keycode], [NSNumber numberWithInteger:flags]] ;

    if ([keysToWatchFor containsObject:myKey]) {
        lua_pushboolean(L, false) ;
    } else {
        [keysToWatchFor addObject:myKey] ;
        lua_pushboolean(L, true) ;
    }
    return 1 ;
}

// hs._asm.hotkey.unregisterKeyToWatch(keycode, flagcode) -> bool
// Function
// Remove the specified keycode and flags (modifier keys) from the watch list for the hotkey eventtap.
//
// Parameters:
//  * keycode  -- the numeric keycode for the key to watch for as described in `hs.keycodes.map`
//  * flagcode -- the numeric mask representing the flags (modifier keys) which accompany the key to watch for.
//
// Returns:
//  * True if the hotkey was removed from the watch list or false if it was not (because it doesn't exist in the watch list).
//
// Notes:
//  * This function is used internally by hs._asm.hotkey and should not be invoked directly unless (a) you really really really know what you're doing, or (b) you like screwing things up.  This function has been stored without public reference in the metatable for this reason.
static int unregisterKey(lua_State* L) {
    NSInteger keycode = luaL_checkinteger(L, 1) ;
    NSInteger flags   = luaL_checkinteger(L, 2) ;
    NSArray *myKey    = @[[NSNumber numberWithInteger:keycode], [NSNumber numberWithInteger:flags]] ;

    if ([keysToWatchFor containsObject:myKey]) {
        [keysToWatchFor removeObject:myKey] ;
        lua_pushboolean(L, true) ;
    } else {
        lua_pushboolean(L, false) ;
    }
    return 1 ;
}

static int enableKeyTap(lua_State* L);
static int disableKeyTap(lua_State* L);
CGEventRef hotkeyCallback(CGEventTapProxy __unused proxy, CGEventType type, CGEventRef event, void *refcon) {
    lua_State* L             = refcon ;
    BOOL       weAteTheEvent = NO ;

//  apparently OS X disables eventtaps if it thinks they are slow or odd or just because the moon
//  is wrong in some way... but at least it's nice enough to tell us.

    if ((type == kCGEventTapDisabledByTimeout) || (type == kCGEventTapDisabledByUserInput)) {
//         NSDateFormatter *format = [[NSDateFormatter alloc] init];
//         [format setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
//         NSDate *now = [NSDate date];
//         NSString *nsstr = [format stringFromDate:now];
//
//         lua_getglobal(L, "print");
//         lua_pushstring(L, [[NSString stringWithFormat:@"-- %@: (%d) hotkey event tap restarted", nsstr, type] UTF8String]) ;
//         lua_call(L, 1, 0) ;

        CLS_NSLOG(@"hotkey eventtap restarted: (%d)", type) ;
        CGEventTapEnable(hotkeyTap, true);
    } else {
        NSInteger flags   = CGEventGetFlags(event) & FLAGS_WE_WANT ;
        NSInteger keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) ;
        NSArray *myKey    = @[[NSNumber numberWithInteger:keycode], [NSNumber numberWithInteger:flags]] ;

        if ((luaCallbackPart != LUA_NOREF) && [keysToWatchFor containsObject:myKey]) {

// long pauses make OS X eventtap sender sad...  let's see if we can keep it happy
// by stopping it until we're done with the "slow" part.

            disableKeyTap(L) ; lua_pop(L, 1) ;

            lua_getglobal(L, "debug"); lua_getfield(L, -1, "traceback"); lua_remove(L, -2);
            lua_rawgeti(L, LUA_REGISTRYINDEX, luaCallbackPart);
            lua_pushinteger(L, keycode) ;
            lua_pushinteger(L, flags) ;
            lua_pushboolean(L, (type == kCGEventKeyDown)) ;
            if (lua_pcall(L, 3, 0, -5) != LUA_OK) {
                CLS_NSLOG(@"%s", lua_tostring(L, -1));
                lua_getglobal(L, "hs"); lua_getfield(L, -1, "showError"); lua_remove(L, -2);
                lua_pushvalue(L, -2);
                lua_pcall(L, 1, 0, 0);
            }
            weAteTheEvent = YES ;

// We're done.

            enableKeyTap(L) ; lua_pop(L, 1) ;

        } else {
            weAteTheEvent = NO ;  // just to be extra special carefull not to swallow the event
        }
    }

    return weAteTheEvent ? NULL : event ;
}


// hs._asm.hotkey.registerLuaCallbackPart(fn) -> nil
// Function
// Registers the Lua portion of the callback code.
//
// Parameters:
//  * fn -- a function which takes 3 arguments (keycode, flagcode, and isKeyDown) and uses these to lookup and call the registered callback function for the defined hotkey.
//
// Returns:
//  * None
//
// Notes:
//  * This function is used internally by hs._asm.hotkey and should not be invoked directly unless (a) you really really really know what you're doing, or (b) you like screwing things up.  This function has been stored without public reference in the metatable for this reason.
static int registerLuaCallbackPart(lua_State *L) {
    luaL_checktype(L, 1, LUA_TFUNCTION) ;
    luaCallbackPart = luaL_ref(L, LUA_REGISTRYINDEX) ;
    return 0 ;
}

/// hs._asm.hotkey.isHotkeyEventtapEnabled() -> bool
/// Function
/// Determine whether or not the hotkey eventtap is enabled.
///
/// Parameters:
///  * None
///
/// Returns:
///  * True if the hotkey eventtap is enabled or false if it is not.
static int isEnabled(lua_State* L) {
    lua_pushboolean(L, (hotkeyTap && CGEventTapIsEnabled(hotkeyTap))) ;
    return 1;
}

/// hs._asm.hotkey.enableHotkeyEventtap() -> bool
/// Function
/// Enable the hotkey eventtap.
///
/// Parameters:
///  * None
///
/// Returns:
///  * True if the hotkey eventtap is enabled or false if it is not.
///
/// Notes:
///  * This function is called by the modules initialization code, so it is unlikely you will ever need to call it directly unless you have programmatically disabled all hotkeys and are now re-enabling them.
///  * The most likely cause of failure is if Accessibility is not enabled (check Hammerspoon preferences).
///  * If the failure was caused by Accessibility being disabled, you may have to restart Hammerspoon after enabling it before this function will succeed.
///    * The initialization process checks for this and delays calling this function until Accessibility is enabled, so unless you are calling this function directly from elsewhere, the restart will usually not be necessary.
static int enableKeyTap(lua_State* L) {

//  apparently OS X disables eventtaps if it thinks they are slow or odd or just because the moon
//  is wrong in some way... but at least it's nice enough to tell us.

    CGEventMask hotkeyMask = CGEventMaskBit(kCGEventKeyDown) |
                             CGEventMaskBit(kCGEventKeyUp) ;

    if (!(hotkeyTap && CGEventTapIsEnabled(hotkeyTap))) {
        // Just in case; don't want dangling ports and loops and such lying around.
        if (hotkeyTap && !CGEventTapIsEnabled(hotkeyTap)) {
            CFMachPortInvalidate(hotkeyTap);
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hotkeyRunLoopSrc, kCFRunLoopCommonModes);
            CFRelease(hotkeyRunLoopSrc);
            CFRelease(hotkeyTap);
        }
        hotkeyTap = CGEventTapCreate(kCGSessionEventTap,
                                     kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault,
                                     hotkeyMask,
                                     hotkeyCallback,
                                     L);

        if (hotkeyTap) {
            CGEventTapEnable(hotkeyTap, true);
            hotkeyRunLoopSrc = CFMachPortCreateRunLoopSource(NULL, hotkeyTap, 0);
            CFRunLoopAddSource(CFRunLoopGetMain(), hotkeyRunLoopSrc, kCFRunLoopCommonModes);
        } else {
            showError(L, "Unable to create hotkey eventtap.  Is Accessibility enabled?");
        }
    }
    return isEnabled(L) ;
}

/// hs._asm.hotkey.disableHotkeyEventtap() -> bool
/// Function
/// Disable the hotkey eventtap.
///
/// Parameters:
///  * None
///
/// Returns:
///  * True if the hotkey eventtap is not enabled (we succeeded in disabling it or it was already disabled) or false if we were unable to disable it for some reason.
///
/// Notes:
///  * This function is called by the modules garbage collection code, so it is unlikely you will ever need to call it directly unless you are programmatically disabling all hotkeys for some reason.
///  * This function does not affect hotkey definitions or what hotkeys are currently enabled or disabled -- you could re-enable hotkeys via `hs._asm.hotkey.enableHotkeyEventtap()` and return to the exact set of registered hotkeys as were previously in place.
///  * This function also does not affect the binding of new hotkeys -- they just won't do anything until the Hotkey eventtap is restarted.
static int disableKeyTap(lua_State* L) {
    if (hotkeyTap) {
        if (CGEventTapIsEnabled(hotkeyTap)) CGEventTapEnable(hotkeyTap, false);
        CFMachPortInvalidate(hotkeyTap);
        CFRunLoopRemoveSource(CFRunLoopGetMain(), hotkeyRunLoopSrc, kCFRunLoopCommonModes);
        CFRelease(hotkeyRunLoopSrc);
        CFRelease(hotkeyTap);
        hotkeyRunLoopSrc = NULL ;
        hotkeyTap = NULL ;
    }
    isEnabled(L) ; lua_pushboolean(L, !lua_toboolean(L, -1)) ; // Invert isEnabled's result
    return 1 ;
}

static int meta_gc(lua_State* L) {
    disableKeyTap(L) ;
    [keysToWatchFor removeAllObjects];
    keysToWatchFor = NULL;
    return 0;
}

// Functions for returned object when module loads
static luaL_Reg hotkeyLib[] = {
    {"registerLuaCallbackPart", registerLuaCallbackPart},
    {"registerKeyToWatch",      registerKey},
    {"unregisterKeyToWatch",    unregisterKey},
    {"enableHotkeyEventtap",    enableKeyTap},
    {"disableHotkeyEventtap",   disableKeyTap},
    {"isHotkeyEventtapEnabled", isEnabled},
    {NULL,      NULL}
};

// Metatable for returned object when module loads
static const luaL_Reg meta_gcLib[] = {
    {"__gc",    meta_gc},
    {NULL,      NULL}
};

int luaopen_hs__asm_hotkey_internal(lua_State* L) {
    keysToWatchFor  = [NSMutableArray array] ;
    luaCallbackPart = LUA_NOREF ;

    // Just being explicit...
    hotkeyRunLoopSrc = NULL ;
    hotkeyTap = NULL ;

    luaL_newlib(L, hotkeyLib);
        luaL_newlib(L, meta_gcLib);
        lua_setmetatable(L, -2);

    return 1;
}
