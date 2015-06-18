_asm.hotkey
-----------

This module is a replacement of `hs.hotkey` with one entirely handled via hs.eventtap.  It is an attempt to determine if this is a viable alternative which addresses some of the limitations of `hs.hotkey`.

** THIS CODE IS EXTREMELY EXPERIMENTAL **

If you have any question about using this code or about what it is doing, then for now, don't use it!  Much more testing is required before I will even consider proposing this as a potential update to the existing module.

### Local Install
~~~bash
$ git clone https://github.com/asmagill/hammerspoon_hotkey
$ cd hammerspoon_hotkey
$ [PREFIX=/usr/local/share/lua/5.2/] make install
~~~

To remove:
~~~bash
$ cd hammerspoon_hotkey
$ [PREFIX=/usr/local/share/lua/5.2/] make uninstall
~~~

Note that if you do not provide `PREFIX`, then it defaults to your Hammerspoon home directory (~/.hammerspoon).  To properly remove, the `PREFIX` supplied (or not-supplied) must match what you used when initially installing it.

### Usage

To use this code properly, you must override *Hammerspoons* default usage of its internal `hs.hotkey` module.  To do so, put the following at the **very top** of your `init.lua` file, before any other module is loaded or required:

~~~lua
local R, M = pcall(require,"hs._asm.hotkey")
if R then
    print()
    print("**** Replacing internal hs.hotkey with experimental module.")
    print()
    hs.hotkey = M
    package.loaded["hs.hotkey"] = M   -- make sure require("hs.hotkey") returns us
    package.loaded["hs/hotkey"] = M   -- make sure require("hs/hotkey") returns us
end
~~~

See https://github.com/asmagill/hammerspoon-config for an example of this.

It is uncertain, but likely, that confusion and or blindness may occur if you try to use this alongside `hs.hotkey`, which is why the above code tries really hard to prevent this from happening.  If you want to try, it's on your own head!

### License

> Released under MIT license.
>
> Copyright (c) 2015 Aaron Magill
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.
