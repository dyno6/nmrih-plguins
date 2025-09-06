// Simple Report Menu for SourceMod
// Author: CULINFECTÉAVECCHEVEUXDEZOMBIE
// Version: 1.1

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

#define REPORT_PREFIX "[Report]"
#define REMIND_INTERVAL 420.0   // 7 minutes in seconds

Handle g_hRemindTimer = null;
char g_sLogPath[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
    name        = "Simple Report Menu",
    author      = "CULINFECTÉAVECCHEVEUXDEZOMBIE",
    description = "Players can report others via !report or /report, logs to addons/sourcemod/data/reports.txt, reminder every 7 minutes.",
    version     = "1.1",
    url         = ""
};

public void OnPluginStart()
{
    // Commands: works with !report and /report in chat
    RegConsoleCmd("sm_report", Command_Report);
    RegAdminCmd("sm_report_remind_now", Command_RemindNow, ADMFLAG_GENERIC, "Send the report reminder now.");

    // Build path: addons/sourcemod/data/reports.txt
    BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "data/reports.txt");

    // Start repeating reminder
    if (g_hRemindTimer != null) {
        CloseHandle(g_hRemindTimer);
    }
    g_hRemindTimer = CreateTimer(REMIND_INTERVAL, Timer_Reminder, _, TIMER_REPEAT);
}

public Action Command_Report(int client, int args)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    Handle menu = CreateMenu(MenuHandler_Report);
    SetMenuTitle(menu, "Report a player");
    SetMenuExitButton(menu, true);

    // Add all connected human players except the reporter
    bool added = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == client) continue;
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;

        char name[64];
        GetClientName(i, name, sizeof(name));

        char uidstr[16];
        IntToString(GetClientUserId(i), uidstr, sizeof(uidstr));

        AddMenuItem(menu, uidstr, name);
        added = true;
    }

    if (!added)
    {
        PrintToChat(client, "%s No other players to report right now.", REPORT_PREFIX);
        CloseHandle(menu);
        return Plugin_Handled;
    }

    DisplayMenu(menu, client, 15);
    return Plugin_Handled;
}

public int MenuHandler_Report(Handle menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Select)
    {
        char uidstr[16], name[64];
        GetMenuItem(menu, item, uidstr, sizeof(uidstr), _, name, sizeof(name));
        int userid = StringToInt(uidstr);
        int target = GetClientOfUserId(userid);

        if (target <= 0 || !IsClientInGame(target))
        {
            PrintToChat(client, "%s Target left the server.", REPORT_PREFIX);
            return 0;
        }

        LogReport(client, target);
        PrintToChat(client, "%s You reported: %s", REPORT_PREFIX, name);
        PrintToChatAll("%s %N submitted a report on %N.", REPORT_PREFIX, client, target);
    }
    return 0;
}

void LogReport(int client, int target)
{
    // Collect info
    char timeStr[64];
    FormatTime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", GetTime());

    char map[64];
    GetCurrentMap(map, sizeof(map));

    char repName[64], repAuth[64], tgtName[64], tgtAuth[64];
    GetClientName(client, repName, sizeof(repName));
    GetClientAuthId(client, AuthId_Steam2, repAuth, sizeof(repAuth), true);
    GetClientName(target, tgtName, sizeof(tgtName));
    GetClientAuthId(target, AuthId_Steam2, tgtAuth, sizeof(tgtAuth), true);

    Handle file = OpenFile(g_sLogPath, "a");
    if (file != null)
    {
        WriteFileLine(file, "=== REPORT ===");
        WriteFileLine(file, "Time: %s | Map: %s", timeStr, map);
        WriteFileLine(file, "Reporter: %s (%s)", repName, repAuth);
        WriteFileLine(file, "Target  : %s (%s)", tgtName, tgtAuth);
        WriteFileLine(file, "");
        CloseHandle(file);
    }
    else
    {
        LogError("[SimpleReport] Could not open log file: %s", g_sLogPath);
    }
}

public Action Timer_Reminder(Handle timer, any data)
{
    PrintToChatAll("\x04%s \x03If you have an issue with a player, type \x04!report \x03(or /report).", REPORT_PREFIX);
    return Plugin_Continue;
}

public Action Command_RemindNow(int client, int args)
{
    PrintToChatAll("\x04%s \x03If you have an issue with a player, type \x04!report \x03(or /report).", REPORT_PREFIX);
    return Plugin_Handled;
}
