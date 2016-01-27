#include <sdktools>

/**
 * Callback for RequestNextRespawnTimer.
 * Is a failure state if (client == 0 || flNextRespawnTime < GetGameTime())
 */
typedef RespawnTimerCallback = function void(int client, float flNextRespawnTime, any data);

/**
 * Request the next available respawn timer for the given client, if any.
 */
stock void RequestNextRespawnTimer(int client, RespawnTimerCallback callback, any data = 0) {
	int userid = GetClientUserId(client);
	
	DataPack pack = new DataPack();
	pack.WriteCell(userid);
	pack.WriteFunction(callback);
	pack.WriteCell(data);
	
	RequestFrame(Frame_TryGetRespawnTime, pack);
}

/**
 * Keep checking the resource entity until it's updated with respawn time
 */
public void Frame_TryGetRespawnTime(DataPack pack) {
	pack.Reset();
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	Function callback = pack.ReadFunction();
	any data = pack.ReadCell();
	
	if (client > 0 && IsClientInGame(client) && !IsPlayerAlive(client)
			&& GameRules_GetRoundState() == RoundState_RoundRunning) {
		
		float flNextRespawnTime = GetEntPropFloat(GetPlayerResourceEntity(), Prop_Send, "m_flNextRespawnTime", client);
		
		if (flNextRespawnTime < GetGameTime()) {
			// respawn time invalid, wait for the next one
			// could just check if flNextRespawnTime = 0.0
			DataPack repack = new DataPack();
			repack.WriteCell(userid);
			repack.WriteFunction(callback);
			repack.WriteCell(data);
			
			RequestFrame(Frame_TryGetRespawnTime, repack);
		} else {
			// respawn time available; prepare the rest of the stuff
			Call_StartFunction(INVALID_HANDLE, callback);
			Call_PushCell(client);
			Call_PushFloat(flNextRespawnTime);
			Call_PushCell(data);
			Call_Finish();
		}
	} else {
		Call_StartFunction(INVALID_HANDLE, callback);
		Call_PushCell(client);
		Call_PushFloat(0.0);
		Call_PushCell(data);
		Call_Finish();
	}
	
	delete pack;
}
