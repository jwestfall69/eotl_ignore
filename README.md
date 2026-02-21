# eotl_ignore

This is a TF2 sourcemod plugin I wrote for the [EOTL](https://www.endofthelinegaming.com/) community.

This plugin implements server side voice ignores per client.  This was done because sometimes client local voice mutes don't work (bug in 33+ player servers?).

Each client has their own list of ignored players.  Individual client configs are stored in ```sourcemod/configs/eotl_ignore/<user's community id>.cfg```

### Dependencies
<hr>

  * simple-chatprocessor redux plugin (eotl bugfix version located [here](https://github.com/jwestfall69/eotl_simple-chatprocessor))
  * Make sure ```sourcemod/config/eotl_ignore/``` directory exists

### Say Commands
<hr>

**!ignore**

This will bring up a menu to pick which player to ignore or unignore.

**!ignore clear**

This will clear out the callers ignore list.

**!ignore acktest**

This is a debug command that logs some data server side.  Mostly just there to gather info about what the server sees when client local mutes aren't working.

### ConVars
<hr>

**eotl_ignore_debug [0/1]**

Enable additional debug logging.

Default: 0 (disabled)