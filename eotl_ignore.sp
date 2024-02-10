#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_AUTHOR         "ack"
#define PLUGIN_VERSION        "0.5"

#define CONFIG_PATH           "configs/eotl_ignore/"

#define STEAMID_LENGTH        32

public Plugin myinfo = {
	name = "eotl_ignore",
	author = PLUGIN_AUTHOR,
	description = "server side voice ignore for when local mutes aren't working",
	version = PLUGIN_VERSION,
	url = ""
};

enum struct PlayerState {
    bool isPreAuth;         // when a client is connected, but steam id isn't auth'd yet
    bool hasIgnores;
    StringMap ignores;
    char steamID[STEAMID_LENGTH];
}

PlayerState g_playerStates[MAXPLAYERS + 1];
char g_configPath[PLATFORM_MAX_PATH];
ConVar g_cvDebug;

public void OnPluginStart() {
    LogMessage("version %s starting", PLUGIN_VERSION);
    RegConsoleCmd("sm_ignore", CommandIgnore);

    g_cvDebug = CreateConVar("eotl_ignore_debug", "0", "0/1 enable debug output", FCVAR_NONE, true, 0.0, true, 1.0);

    for(int client = 1;client <= MaxClients; client++) {
        g_playerStates[client].ignores = CreateTrie();
    }

    BuildPath(Path_SM, g_configPath, sizeof(g_configPath), "%s", CONFIG_PATH);
    LogMessage("Client Config Path: %s", g_configPath);

    // todo force a load of all connected clients, in the event the plugin is reloaded
}

public void OnMapStart() {
    for(int client = 1;client <= MaxClients; client++) {
        g_playerStates[client].isPreAuth = true;
        g_playerStates[client].hasIgnores = false;
        g_playerStates[client].steamID[0] = '\0';
        ClearTrie(g_playerStates[client].ignores);
    }
}

// debug if OnClientAuthorized sometimes doesnt fire
public void OnClientConnected(int client) {
    CreateTimer(30.0, PreAuthTimeout, client);
}

public Action PreAuthTimeout(Handle timer, int client) {

    if(!IsClientConnected(client)) {
        return Plugin_Continue;
    }

    if(IsFakeClient(client)) {
        return Plugin_Continue;
    }

    if(!g_playerStates[client].isPreAuth) {
        return Plugin_Continue;
    }

    char steamID[STEAMID_LENGTH];
    if(!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
        LogDebug("PreAuthTimeout: GetClientAuthId failed: %d %N", client, client);
        return Plugin_Continue;
    }

    LogDebug("PreAuthTimeout: GetClientAuthId success: %N %s", client, steamID);
    return Plugin_Continue;
}

public void OnClientAuthorized(int client, const char[] auth) {
    g_playerStates[client].isPreAuth = false;
    strcopy(g_playerStates[client].steamID, STEAMID_LENGTH, auth);

    if(LoadClientIgnores(client)) {
        g_playerStates[client].hasIgnores = true;

        // see if we need to ignore anyone already connected to the server
        for(int target = 1;target <= MaxClients; target++) {

            if(!IsValidTarget(client, target)) {
                continue;
            }

            // pre auth wont have a steamid yet
            if(g_playerStates[target].isPreAuth) {
                continue;
            }

            if(!g_playerStates[client].ignores.ContainsKey(g_playerStates[target].steamID)) {
                continue;
            }

            LogDebug("%N (%s) is on %N's (%s) ignore list, blocking voice", target, g_playerStates[target].steamID, client, g_playerStates[client].steamID);
            SetListenOverride(client, target, Listen_No);
        }
    }

    // see if this newly connected/auth'd client is on anyone elses ignore list
    for(int other = 1;other <= MaxClients; other++) {

        if(!IsValidTarget(other, client)) {
            continue;
        }

        // pre auth wont have a ignores loaded yet
        if(g_playerStates[other].isPreAuth) {
                continue;
        }

        if(!g_playerStates[other].hasIgnores) {
            continue;
        }

        if(!g_playerStates[other].ignores.ContainsKey(g_playerStates[client].steamID)) {
            continue;
        }

        LogDebug("%N (%s) is on %N's (%s) ignore list, blocking voice", client, g_playerStates[client].steamID, other, g_playerStates[other].steamID);
        SetListenOverride(other, client, Listen_No);
    }
}

public void OnClientDisconnect(int client) {
    g_playerStates[client].isPreAuth = true;
    g_playerStates[client].hasIgnores = false;
    g_playerStates[client].steamID[0] = '\0';
    ClearTrie(g_playerStates[client].ignores);
}

public Action CommandIgnore(int client, int args) {

    if(args == 1) {
        char arg1[32];
        GetCmdArg(1, arg1, sizeof(arg1));
        if(StrEqual(arg1, "clear")) {
            ClearClientIgnores(client);
            return Plugin_Continue;
        } else if(StrEqual(arg1, "acktest")) {
            AckTest(client);
            return Plugin_Continue;
        }
    }

    MenuIgnore(client);
    return Plugin_Continue;
}

void AckTest(int client) {

    LogDebug("AckTest for %N (%s)", client, g_playerStates[client].steamID);

    for(int target = 1; target <= MaxClients; target++) {

        if(!IsValidTarget(client, target)) {
            continue;
        }

        if(IsClientMuted(client, target)) {
            LogDebug("  Muted: %N (%s)", target, (g_playerStates[client].isPreAuth ? "PREAUTH" : g_playerStates[client].steamID));
        } else {
            LogDebug("  Not Muted: %N (%s)", target, (g_playerStates[client].isPreAuth ? "PREAUTH" : g_playerStates[client].steamID));
        }
    }
}

void MenuIgnore(int client) {
    Menu menu = CreateMenu(HandleMenuIgnoreInput);

    char targetId[32];
    char targetName[32];
    int targets = 0;
    for(int target = 1; target <= MaxClients; target++) {

        if(!IsValidTarget(client, target)) {
            continue;
        }

        // pre auth wont have a steamid yet
        if(g_playerStates[target].isPreAuth) {
            continue;
        }

        Format(targetId, sizeof(targetId), "%d", GetClientUserId(target));
        GetClientName(target, targetName, sizeof(targetName));

        if(g_playerStates[client].hasIgnores && g_playerStates[client].ignores.ContainsKey(g_playerStates[target].steamID)) {
            StrCat(targetName, sizeof(targetName), " (ignored)");
        }

        AddMenuItem(menu, targetId, targetName);
        targets++;
    }

    if(targets == 0) {
        PrintToChat(client, "No players found");
        CloseHandle(menu);
        return;
    }

    SetMenuTitle(menu, "Toggle Voice Ignore");
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}


int HandleMenuIgnoreInput(Menu menu, MenuAction action, int client, int itemNum) {
    char targetId[32];

    if (action == MenuAction_End) {
        CloseHandle(menu);
        return 0;
    }

    if(action != MenuAction_Select) {
        return 0;
    }

    GetMenuItem(menu, itemNum, targetId, sizeof(targetId));
    int target = GetClientOfUserId(StringToInt(targetId));

    if(target == 0) {
        PrintToChat(client, "Ignore target not on the server anymore!?");
        return 0;
    }

    if(g_playerStates[client].ignores.ContainsKey(g_playerStates[target].steamID)) {
        RemoveClientIgnore(client, target);
    } else {
        AddClientIgnore(client, target);
    }

    return 0;
}

void ClearClientIgnores(int client) {

    if(!g_playerStates[client].hasIgnores) {
        PrintToChat(client, "There are no players on your voice ignore list");
        return;
    }

    Handle snap = CreateTrieSnapshot(g_playerStates[client].ignores);
    int trieSize = TrieSnapshotLength(snap);
    CloseHandle(snap);

    ClearTrie(g_playerStates[client].ignores);

    // now blindly reset every client to default for them
    for(int target = 1; target <= MaxClients; target++) {

        if(!IsValidTarget(client, target)) {
            continue;
        }

        SetListenOverride(client, target, Listen_Default);
    }

    if(!SaveClientIgnores(client)) {
        PrintToChat(client, "There was an error saving your voice ignore list config");
        return;
    }

    LogDebug("%N cleared their voice ignore list of %d players", client, trieSize);
    PrintToChat(client, "Your voice ignore list has been cleared (%d players were ignored)", trieSize);
}

void AddClientIgnore(int client, int target) {

    SetTrieValue(g_playerStates[client].ignores, g_playerStates[target].steamID, 1);
    g_playerStates[client].hasIgnores = true;

    SetListenOverride(client, target, Listen_No);

    if(!SaveClientIgnores(client)) {
        PrintToChat(client, "There was an error saving %N to your voice ignore list config", target);
        return;
    }

    LogDebug("%N added %N to their voice ignore list", client, target);
    PrintToChat(client, "%N has been added to your voice ignore list", target);
}

void RemoveClientIgnore(int client, int target) {

    RemoveFromTrie(g_playerStates[client].ignores, g_playerStates[target].steamID);

    Handle snap = CreateTrieSnapshot(g_playerStates[client].ignores);
    int trieSize = TrieSnapshotLength(snap);
    CloseHandle(snap);

    if(trieSize == 0) {
        g_playerStates[client].hasIgnores = false;
    }

    SetListenOverride(client, target, Listen_Default);

    if(!SaveClientIgnores(client)) {
        PrintToChat(client, "There was an error saving %N to your voice ignore list config", target);
        return;
    }

    LogDebug("%N removed %N to their voice ignore list", client, target);
    PrintToChat(client, "%N has been removed to your voice ignore list", target);
}

bool LoadClientIgnores(int client) {
    char clientConfigFile[PLATFORM_MAX_PATH];
    char steamID64[32];

    // AuthId_SteamID64 is the clients stream community id/number.
    if(!GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64))) {
        LogDebug("GetClientAuthId(): failed for client %d (%N)", client, client);
        return false;
    }

    Format(clientConfigFile, PLATFORM_MAX_PATH, "%s%s.cfg", g_configPath, steamID64);
    LogMessage("Using client config file: %s for %N", clientConfigFile, client);

    File cfgFd = OpenFile(clientConfigFile, "r");
    if(cfgFd == null) {
        LogMessage("%N has 0 voice ignores (no config file)", client);
        return false;
    }

    char line[64];
    int count = 0;
    while(ReadFileLine(cfgFd, line, sizeof(line))) {
        TrimString(line);

        // ignore comments added by SaveClientIgnores
        if(strncmp(line, "//", 2) == 0) {
            continue;
        }

        if(strncmp(line, "STEAM_", 6) != 0) {
            LogMessage("WARN: Invalid steam id: %s, ignoring", line);
            continue;
        }

        LogDebug("  Added %s to voice ignore list", line);
        SetTrieValue(g_playerStates[client].ignores, line, 1);
        count++;
    }
    CloseHandle(cfgFd);

    LogMessage("%N has %d voice ignores", client, count);

    if(count == 0) {
        return false;
    }

    return true;
}

// save out the client's ignore list to a .temp file then rename it to the real one
bool SaveClientIgnores(int client) {
    char clientConfigFileTemp[PLATFORM_MAX_PATH];
    char clientConfigFileReal[PLATFORM_MAX_PATH];
    char steamID64[32];

    if(!GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64))) {
        LogDebug("GetClientAuthId() failed for client %d (%N)", client, client);
        return false;
    }

    Format(clientConfigFileReal, PLATFORM_MAX_PATH, "%s%s.cfg", g_configPath, steamID64);
    Format(clientConfigFileTemp, PLATFORM_MAX_PATH, "%s%s.cfg.temp", g_configPath, steamID64);

    Handle snap = CreateTrieSnapshot(g_playerStates[client].ignores);
    int trieSize = TrieSnapshotLength(snap);

    if(trieSize == 0) {
        LogMessage("SaveClientIgnores: %N no longer has any ignores, removing config file (%s)", client, clientConfigFileReal);
        DeleteFile(clientConfigFileReal);
        CloseHandle(snap);
        return true;
    }

    LogMessage("SaveClientIgnores: Using client config file: %s for %N", clientConfigFileReal, client);

    File cfgFd = OpenFile(clientConfigFileTemp, "w");
    if(cfgFd == null) {
        LogMessage("ERROR: Unable to open %s for writing, is %s directory missing?", clientConfigFileTemp, g_configPath);
        CloseHandle(snap);
        return false;
    }

    WriteFileLine(cfgFd, "// Voice ignores for: %N (%s)", client, g_playerStates[client].steamID);

    char steamID[STEAMID_LENGTH];
    for(int i = 0; i < trieSize; i++) {
        GetTrieSnapshotKey(snap, i, steamID, sizeof(steamID));
        LogDebug("  Adding %s", steamID);
        WriteFileLine(cfgFd, "%s", steamID);
    }
    CloseHandle(cfgFd);
    CloseHandle(snap);

    // The original plan was to write out the config to a temp file then rename it to
    // the correct name, since the rename should be atomic.  This works as expected on
    // linux, however it turns out windows won't allow a rename if the destination file
    // already exists.  There doesn't seem to be any easy way to get the OS of the server
    // so for now we just nuking the original file before the rename to workaround windows
    DeleteFile(clientConfigFileReal);

    if(!RenameFile(clientConfigFileReal, clientConfigFileTemp)) {
        LogMessage("ERROR: Unable to rename %s to %s", clientConfigFileTemp, clientConfigFileReal);
        return false;
    }

    LogMessage("Wrote %d voice ignores", trieSize);
    return true;
}

bool IsValidTarget(int client, int target) {

    if(target == client) {
        return false;
    }

    if(!IsClientConnected(target)) {
        return false;
    }

    if(IsFakeClient(target)) {
        return false;
    }

    return true;
}

void LogDebug(char []fmt, any...) {

    if(!g_cvDebug.BoolValue) {
        return;
    }

    char message[128];
    VFormat(message, sizeof(message), fmt, 2);
    LogMessage(message);
}