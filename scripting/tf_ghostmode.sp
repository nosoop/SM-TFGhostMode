/**
 * Sourcemod Plugin Template
 */

#pragma semicolon 1

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION          "0.2.0"     // Plugin version.

public Plugin:myinfo = {
    name = "[TF2] Ghost Mode",
    author = "nosoop",
    description = "Implementation of Ghost Mode using Valve's ghost TFConds",
    version = PLUGIN_VERSION,
    url = "http://github.com/nosoop"
}

#define A_REALLY_LONG_TIME      9999999999.0

new g_rgRespawnTimes[MAXPLAYERS+1];

public OnPluginStart() {
    // Ghost-on-death condition ("in hell") is applied on spawn.
    HookEvent("player_spawn", EventHook_OnPlayerSpawn);
    
    // Listen for a few commands to properly remove ghost condition on.
    AddCommandListener(CommandListener_CancelGhostMode, "spectate");
    
    // TODO properly handle jointeam argument
    AddCommandListener(CommandListener_CancelGhostMode, "jointeam");
    
    // TODO Check for other cases where we want to cancel ghost mode.
    
    // Late loads.
    for (new i = MaxClients; i > 0; --i) {
        if (IsClientInGame(i)) {
            OnClientPutInServer(i);
            
            if (TF2_IsPlayerInCondition(i, TFCond_HalloweenGhostMode)) {
                PreparePlayerRespawn(i);
            }
        }
    }
}

public OnMapStart() {
    // Precache ghost sounds.
    decl String:halloweenBoo[64];
    for (new i = 0; i < 7; i++) {
        Format(halloweenBoo, sizeof(halloweenBoo), "vo/halloween_boo%d.wav", i+1);
        PrecacheSound(halloweenBoo);
    }
}

public OnClientPutInServer(iClient) {
    SDKHook(iClient, SDKHook_SetTransmit, SDKHook_OnSetTransmit);
}

public Action:EventHook_OnPlayerSpawn(Handle:hEvent, const String:name[], bool:dontBroadcast) {
    new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    
    // TODO make optional, random chance?
    // TODO change condition duration?
    TF2_AddCondition(iClient, TFCond_HalloweenInHell, A_REALLY_LONG_TIME);
}

public TF2_OnConditionAdded(iClient, TFCond:condition) {
    if (condition == TFCond_HalloweenGhostMode) {
        TF2_RemoveAllWeapons(iClient);
        PreparePlayerRespawn(iClient);
    }
}

public Action:CommandListener_CancelGhostMode(iClient, const String:command[], argc) {
    TF2_RemoveCondition(iClient, TFCond_HalloweenInHell);
    TF2_RemoveCondition(iClient, TFCond_HalloweenGhostMode);
    return Plugin_Continue;
}

/**
 * Handles player respawns, attempting to accurately match the normal respawn time.
 */
PreparePlayerRespawn(iClient) {
    new TFTeam:iTeam = TFTeam:GetClientTeam(iClient);
    
    if (iTeam <= TFTeam_Spectator) {
        return;
    }
    
    new Float:fRespawnTime = GetPlayerRespawnTime(iTeam);
    CreateTimer(fRespawnTime, Timer_GhostRespawn, iClient, TIMER_FLAG_NO_MAPCHANGE);
    // TODO kill timer if respawned?
    
    // Creates "respawning in" center chat notification.
    g_rgRespawnTimes[iClient] = RoundFloat(fRespawnTime);
    CreateTimer(FloatFraction(fRespawnTime), Timer_StartRespawnCountdown, iClient, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Starts the timer notification.
 */
public Action:Timer_StartRespawnCountdown(Handle:hTimer, any:iClient) {
    g_rgRespawnTimes[iClient] -= 1;
    CreateTimer(1.0, Timer_RespawnCountdown, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Shows respawn timer notification.  Updates every second while the player it is for is dead.
 */
public Action:Timer_RespawnCountdown(Handle:hTimer, any:iClient) {
    g_rgRespawnTimes[iClient] -= 1;
    if (g_rgRespawnTimes[iClient] > 0) {
        PrintCenterText(iClient, "Respawn in: %d seconds", g_rgRespawnTimes[iClient]);
    } else if (g_rgRespawnTimes[iClient] == 0) {
        PrintCenterText(iClient, "Prepare to respawn");
        Client_ScreenFadeIn(iClient, 512, 512, {255, 255, 255, 255});
    }
    
    if (g_rgRespawnTimes[iClient] < 0
            || !TF2_IsPlayerInCondition(iClient, TFCond_HalloweenGhostMode)
            || GameRules_GetRoundState() == RoundState_TeamWin) {
        OnRespawnCountdownClosed(hTimer, iClient);
    }
}

OnRespawnCountdownClosed(Handle:hTimer, iClient) {
    KillTimer(hTimer);
    PrintCenterText(iClient, "");
}

/**
 * Timer that respawns a player while they are in ghost mode.
 * (Respawn time is set in PreparePlayerRespawn(iClient).)
 */
public Action:Timer_GhostRespawn(Handle:hTimer, any:iClient) {
    if (GameRules_GetRoundState() != RoundState_TeamWin) {
        TF2_RespawnPlayer(iClient);
    }
}

/**
 * Allow ghosts to be seen only by dead players.
 */
public Action:SDKHook_OnSetTransmit(iClient, iObservingClient) {
    new bool:bObserverDeadOrGhost = TF2_IsPlayerInCondition(iObservingClient, TFCond_HalloweenGhostMode)
            || !IsPlayerAlive(iObservingClient);
    
    if (iClient != iObservingClient
            && TF2_IsPlayerInCondition(iClient, TFCond_HalloweenGhostMode)
            && !bObserverDeadOrGhost) {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

/**
 * Amount of time to add to compensate for the freezecam.  Used in GetPlayerRespawnTime(client).
 */
#define FREEZECAM_TIME          5.0

/**
 * Returns the amount of time until respawn, provided a client on the specified team died at the time this method is called.
 */
stock Float:GetPlayerRespawnTime(TFTeam:iTeam) {
    // TODO handle for arena, etc.
    if (iTeam <= TFTeam_Spectator) {
        ThrowError("Team must be a non-spectating team (input %d)", iTeam);
    }

    new Float:fMinRespawnTime = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", _:iTeam);

    new Float:fRespawnTime = GameRules_GetPropFloat("m_flNextRespawnWave", _:iTeam) - GetGameTime();
    fRespawnTime += fMinRespawnTime;
    
    if (fRespawnTime < fMinRespawnTime + FREEZECAM_TIME) {
        fRespawnTime += fMinRespawnTime;
    }

    return fRespawnTime;
}

/**
 * Fades a client's screen to a specified color.
 * Sourced from SMLIB
 */
stock bool:Client_ScreenFadeIn(iClient, nDuration, nHoldtime=-1, rgba[4] = {0, 0, 0, 255}, bool:bReliable=true) {
    new Handle:userMessage = StartMessageOne("Fade", iClient, (bReliable?USERMSG_RELIABLE:0));
    
    if (userMessage == INVALID_HANDLE) {
        return false;
    }
    
    BfWriteShort(userMessage, nDuration);
    BfWriteShort(userMessage, nHoldtime);
    BfWriteShort(userMessage, 0x0002);
    BfWriteByte(userMessage, rgba[0]);
    BfWriteByte(userMessage, rgba[1]);
    BfWriteByte(userMessage, rgba[2]);
    BfWriteByte(userMessage, rgba[3]);
    EndMessage();
    
    return true;
}
