-- PlayX
-- Copyright (c) 2009 sk89q <http://www.sk89q.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 2 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
-- $Id$

require("datastream")

PlayX = {}

include("playx/providers.lua")

--- Casts a console command arg to a string.
-- @param v
-- @param default
local function ConCmdToString(v, default)
    if v == nil then return default end
    return tostring(v)
end

--- Casts a console command arg to a number.
-- @param v
-- @param default
local function ConCmdToNumber(v, default)
    v = tonumber(v)
    if v == nil then return default end
    return v
end

--- Casts a console command arg to a bool.
-- @param v
-- @param default
local function ConCmdToBool(v, default)
    if v == nil then return default end
    if v == "false" then return false end
    v = tonumber(v)
    if v == nil then return true end
    return v ~= 0
end

--- Parses a human-readable time string. Returns the number in seconds, or
-- nil if it cannot detect a format. Blank strings will return 0.
-- @Param str
function ParseTimeString(str)
    if str == "" or str == nil then return 0 end
    
    str = str:Trim()
    
    if tonumber(str) then
        return tonumber(str)
    end
    
    str = str:gsub("t=", "")
    str = str:gsub("#", "")
    
    local m, s = str:match("^([0-9]+):([0-9]+)$")
    if m then
        return tonumber(m) * 60 + tonumber(s)
    end
    
    local m, s, ms = str:match("^([0-9]+):([0-9]+)(%.[0-9]+)$")
    if m then
        return tonumber(m) * 60 + tonumber(s) + tonumber(ms)
    end
    
    local h, m, s = str:match("^([0-9]+):([0-9]+):([0-9]+)$")
    if h then
        return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    end
    
    local h, m, s, ms = str:match("^([0-9]+):([0-9]+):([0-9]+)(%.[0-9]+)$")
    if h then
        return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms)
    end
    
    local s = str:match("^([0-9]+)s$")
    if s then
        return tonumber(s)
    end
    
    local m, s = str:match("^([0-9]+)m *([0-9]+)s$")
    if m then
        return tonumber(m) * 60 + tonumber(s)
    end
    
    local m, s = str:match("^([0-9]+)m$")
    if m then
        return tonumber(m) * 60
    end
    
    local h, m, s = str:match("^([0-9]+)h *([0-9]+)m *([0-9]+)s$")
    if h then
        return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    end
    
    local h, m = str:match("^([0-9]+)h *([0-9]+)m$")
    if h then
        return tonumber(h) * 3600 + tonumber(m) * 60
    end
    
    return nil
end

CreateConVar("playx_jw_url", "http://playx.googlecode.com/svn/jwplayer/player.swf", {FCVAR_ARCHIVE})
CreateConVar("playx_jw_youtube", "1", {FCVAR_ARCHIVE})
CreateConVar("playx_admin_timeout", "120", {FCVAR_ARCHIVE})
CreateConVar("playx_expire", "-1", {FCVAR_ARCHIVE})

PlayX.CurrentMedia = nil
PlayX.AdminTimeoutTimerRunning = false

--- Checks if a player instance exists in the game.
-- @return Whether a player exists
function PlayX.PlayerExists()
    return table.Count(ents.FindByClass("gmod_playx")) > 0
end

--- Gets the player instance entity
-- @return Entity or nil
function PlayX.GetInstance()
    local props = ents.FindByClass("gmod_playx")
    return props[1]
end

--- Checks whether the JW player is enabled.
-- @return Whether the JW player is enabled
function PlayX.IsUsingJW()
    return GetConVar("playx_jw_url"):GetString():Trim() ~= ""
end

--- Gets the URL of the JW player.
-- @return
function PlayX.GetJWURL()
    return GetConVar("playx_jw_url"):GetString():Trim()
end

--- Returns whether the JW player supports YouTube.
-- @return
function PlayX.JWPlayerSupportsYouTube()
    return GetConVar("playx_jw_youtube"):GetBool()
end

--- Returns whether a player is permitted to use the player.
-- @param ply Player
-- @return
function PlayX.IsPermitted(ply)
    if PlayXIsPermittedHandler then
        return PlayXIsPermittedHook(ply)
    else
        return ply:IsAdmin()
    end
end

--- Spawns the player at the location that a player is looking at. This
-- function will check whether there is already a player or not.
-- @param ply Player
-- @param model Model path
-- @return Success, and error message
function PlayX.SpawnForPlayer(ply, model)
    if PlayX.PlayerExists() then
        return false, "There is already a PlayX player somewhere on the map"
    end
    
    if not util.IsValidModel(model) then
        return false, "The server doesn't have the selected model"
    end
    
    local tr = ply:GetEyeTrace()

	local ent = ents.Create("gmod_playx")
    ent:SetModel(model)
	ent:SetPos(tr.HitPos + tr.HitNormal * 100)
    ent:DropToFloor()
    ent:PhysWake()
    ent:Spawn()
    ent:Activate()
    
    ply:AddCleanup("gmod_playx", ent)
    
    undo.Create("gmod_playx")
    undo.AddEntity(ent)
    undo.SetPlayer(ply)
    undo.Finish()
    
    return true
end

--- Opens a media file to be played. Clients will be informed of the new
-- media. This is the typical function that you would call to play a
-- certain video.
-- @param provider Name of provider, leave blank to auto-detect
-- @param uri URI to play
-- @param start Time to start the video at, in seconds
-- @param forceLowFramerate Force the client side players to play at 1 FPS
-- @param useJW True to allow the use of the JW player, false for otherwise, nil to default true
-- @param ignoreLength True to not check the length of the video (for auto-close)
-- @return The result generated by a provider, or nil and the error message
function PlayX.OpenMedia(provider, uri, start, forceLowFramerate, useJW, ignoreLength)
    if not PlayX.PlayerExists() then
        return false, "There is no player spawned to play the media"
    end
    
    if start == nil then
        start = 0
    end
    
    if useJW == nil then
        useJW = true
    end
    local useJW = useJW and PlayX.IsUsingJW()
    
    if uri == "" then
        return false, "No URI provided"
    end
    
    local result = nil
    
    if provider ~= "" then -- Provider detected
        if not PlayX.Providers[provider] then
            return false, "Unknown provider specified"
        end
        
        local newURI = PlayX.Providers[provider].Detect(uri)
        result = PlayX.Providers[provider].GetPlayer(newURI and newURI or uri, useJW)
        
        if not result then
            return false, "The provider did not recognize the media URI"
        end
    else -- Time to detect the provider
        for id, p in pairs(PlayX.Providers) do
            local newURI = p.Detect(uri)
            
            if newURI then
                provider = id
                result = p.GetPlayer(newURI, useJW)
                break
            end
        end
        
        if not result then
            return false, "No provider was auto-detected"
        end
    end
    
    local useLowFramerate = result.LowFramerate
    if forceLowFramerate then
        useLowFramerate = true
    end
    
    PlayX.BeginMedia(result.Handler, result.URI, start,
                     result.ResumeSupported, useLowFramerate, nil,
                     result.HandlerArgs, provider)
    
    if not ignoreLength and result.LengthFunc then
        result.LengthFunc(function(length)
            if length then
                PlayX.SetCurrentMediaLength(length)
            end
        end)
    end
    
    return result
end

--- Stops playing.
function PlayX.CloseMedia()
    if PlayX.CurrentMedia then
        PlayX.EndMedia()
    end
end

--- Sets the current media length. This can be called even after the media
-- has begun playing. Calling this when there is no player spawned has
-- no effect or there is no media playing has no effect.
-- @param length Time in seconds
function PlayX.SetCurrentMediaLength(length)
    if not PlayX.PlayerExists() or not PlayX.CurrentMedia then
        return
    end
    
    PlayX.CurrentMedia.Length = length
    PlayX:GetInstance():UpdateWireLength(length)
    
    if GetConVar("playx_expire"):GetFloat() <= -1 then
        timer.Stop("PlayXMediaExpire")
        return
    end
    
    length = length + GetConVar("playx_expire"):GetFloat() -- Pad length
     
    PlayX.CurrentMedia.StopTime = PlayX.CurrentMedia.StartTime + length
    
    local timeLeft = PlayX.CurrentMedia.StopTime - PlayX.CurrentMedia.StartTime
    
    print("PlayX: Length of current media set to " .. tostring(length) ..
          " (grace 10 seconds), time left: " .. tostring(timeLeft) .. " seconds")
    
    if timeLeft > 0 then
        timer.Adjust("PlayXMediaExpire", timeLeft, 1)
        timer.Start("PlayXMediaExpire")
    else -- Looks like it ended already!
        print("PlayX: Media has already expired")
        PlayX.EndMedia()
    end
end

--- Begins a piece of media and informs clients about it. This allows you
-- to skip the provider detection code and force a handler and URI.
-- @param handler
-- @param uri
-- @param start
-- @param resumeSupported
-- @param lowFramerate
-- @param length Length of the media in seconds, can be nil
-- @param handlerArgs Arguments for the handler, can be nil
-- @Param provider Used for wire outputs & metadata, optional
-- @Param identifier Identifies video URL/etc, used for wire outputs & metadata, optional
-- @Param title Used for wire outputs & metadata, optional
function PlayX.BeginMedia(handler, uri, start, resumeSupported, lowFramerate,
                          length, handlerArgs, provider, identifier, title)
    timer.Stop("PlayXMediaExpire")
    timer.Stop("PlayXAdminTimeout")
    
    print(string.format("PlayX: Beginning media %s with handler %s, start at %ss",
                        uri, handler, start))
    
    if not handlerArgs then
        handlerArgs = {}
    end
    
    PlayX.GetInstance():UpdateWireOutputs(handler, uri, start, length and length or 0,
                                          provider and provider or "",
                                          identifier and identifier or "",
                                          title and title or "")
    
    PlayX.CurrentMedia = {
        ["Handler"] = handler,
        ["URI"] = uri,
        ["StartTime"] = CurTime() - start,
        ["ResumeSupported"] = resumeSupported,
        ["LowFramerate"] = lowFramerate,
        ["StopTime"] = nil,
        ["HandlerArgs"] = handlerArgs,
        ["Length"] = length,
        ["Provider"] = provider,
        ["Identifier"] = identifier,
        ["Title"] = title,
    }
    
    if length then
        PlayX.SetCurrentMediaLength(length)
    end
    
    PlayX.SendBeginDStream()
end

--- Clears the current media information and inform clients of the change.
-- Unlike PlayX.CloseMedia(), this does not check if something is already
-- playing to begin with.
function PlayX.EndMedia()
    timer.Stop("PlayXMediaExpire")
    timer.Stop("PlayXAdminTimeout")
    
    PlayX.GetInstance():ClearWireOutputs()
    
    PlayX.CurrentMedia = nil
    PlayX.AdminTimeoutTimerRunning = false
    
    PlayX.SendEndUMsg()
end

--- Send the PlayXBegin datastream to clients. You should not have much of
-- a reason to call this method. We're using datastreams here because
-- some providers (cough. Livestream cough.) send a little too much data.
-- @param ply Pass a player to filter the message to just that player
function PlayX.SendBeginDStream(ply)
    local filter = nil
    
    if ply then
        filter = ply
    else
        filter = RecipientFilter()
        filter:AddAllPlayers()
    end
    
    datastream.StreamToClients(filter, "PlayXBegin", {
        ["Handler"] = PlayX.CurrentMedia.Handler,
        ["URI"] = PlayX.CurrentMedia.URI,
        ["PlayAge"] = CurTime() - PlayX.CurrentMedia.StartTime,
        ["ResumeSupported"] = PlayX.CurrentMedia.ResumeSupported,
        ["LowFramerate"] = PlayX.CurrentMedia.LowFramerate,
        ["HandlerArgs"] = PlayX.CurrentMedia.HandlerArgs,
    })
end

--- Send the PlayXEnd umsg to clients. You should not have much of a
-- a reason to call this method.
function PlayX.SendEndUMsg()
    local filter = RecipientFilter()
    filter:AddAllPlayers()
    
    umsg.Start("PlayXEnd", filter)
    umsg.End()
end

--- Send the PlayXEnd umsg to clients. You should not have much of a
-- a reason to call this method.
function PlayX.SendError(ply, err)
    umsg.Start("PlayXError", ply)
	umsg.String(err)
    umsg.End()
end

--- Send the PlayXSpawnDialog umsg to a client, telling the client to
-- open the spawn dialog.
-- @param ply Player to send to
function PlayX.SendSpawnDialogUMsg(ply)
	if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        ply:ChatPrint("PlayX: You do not have permission to use the player")
    else
        umsg.Start("PlayXSpawnDialog", ply)
        umsg.End()
    end
end

local function JWURLCallback(cvar, old, new)
    print("PlayX: Manually replicating value of playx_jw_url")
    
    SendUserMessage("PlayXJWURL", nil, GetConVar("playx_jw_url"):GetString())
end

-- TODO: This does not work
cvars.AddChangeCallback("playx_jw_url", JWURLCallback)

--- Called for concmd playx_open.
local function ConCmdOpen(ply, cmd, args)
	if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        PlayX.SendError(ply, "You do not have permission to use the player")
    elseif not PlayX.PlayerExists() then
        PlayX.SendError(ply, "There is no player spawned! Go to the spawn menu > Entities")
    elseif not args[1] then
        ply:PrintMessage(HUD_PRINTCONSOLE, "playx_open requires a URI")
    else
        local uri = args[1]:Trim()
        local provider = ConCmdToString(args[2], ""):Trim()
        local start = ParseTimeString(args[3])
        local forceLowFramerate = ConCmdToBool(args[4], false)
        local useJW = ConCmdToBool(args[5], true)
        local ignoreLength = ConCmdToBool(args[6], false)
        
        if start == nil then
            PlayX.SendError(ply, "The time format you entered for \"Start At\" isn't understood")
        elseif start < 0 then
            PlayX.SendError(ply, "A non-negative start time is required")
        else
            local result, err = PlayX.OpenMedia(provider, uri, start,
                                                forceLowFramerate, useJW,
                                                ignoreLength)
            
            if not result then
                PlayX.SendError(ply, err)
            end
        end
    end
end

--- Called for concmd playx_close.
function ConCmdClose(ply, cmd, args)
	if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        PlayX.SendError(ply, "You do not have permission to use the player")
    else
        PlayX.EndMedia()
    end
end

--- Called for concmd playx_spawn.
function ConCmdSpawn(ply, cmd, args)
	if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        PlayX.SendError(ply, "You do not have permission to use the player")
    else
        if not args[1] or args[1]:Trim() == "" then
            PlayX.SendError(ply, "No model specified")
        else
            local model = args[1]:Trim()
            local result, err = PlayX.SpawnForPlayer(ply, model)
        
            if not result then
                PlayX.SendError(ply, err)
            end
        end
    end
end
 
concommand.Add("playx_open", ConCmdOpen)
concommand.Add("playx_close", ConCmdClose)
concommand.Add("playx_spawn", ConCmdSpawn)

--- Called on game mode hook PlayerInitialSpawn.
function PlayerInitialSpawn(ply)
    SendUserMessage("PlayXJWURL", ply, GetConVar("playx_jw_url"):GetString())
    
    timer.Simple(3, function()
        if PlayX.CurrentMedia and PlayX.CurrentMedia.ResumeSupported then
            if PlayX.CurrentMedia.StopTime and PlayX.CurrentMedia.StopTime < CurTime() then
                print("PlayX: Media expired, not sending begin UMSG")
                
                PlayX.EndMedia()
            else
                print("PlayX: Sending begin UMSG " .. ply:GetName())
                
                PlayX.SendBeginDStream(ply)
            end
        end
    end)
end

--- Called on game mode hook PlayerAuthed.
function PlayerAuthed(ply, steamID, uniqueID)
    if PlayX.CurrentMedia and PlayX.AdminTimeoutTimerRunning then
        if PlayX.IsPermitted(ply) then
            print("PlayX: Administrator authed (connecting); killing timeout")
            
            timer.Stop("PlayXAdminTimeout")
            PlayX.AdminTimeoutTimerRunning = false
        end
    end
end

--- Called on game mode hook PlayerDisconnected.
function PlayerDisconnected(ply)
    if not PlayX.CurrentMedia then return end
    if PlayX.AdminTimeoutTimerRunning then return end
    
    for _, v in pairs(player.GetAll()) do
        if v ~= ply and PlayX.IsPermitted(v) then return end
    end
    
    -- No timer, no admin, no soup for you
    local timeout = GetConVar("playx_admin_timeout"):GetFloat()
    
    if timeout > 0 then
        print(string.format("PlayX: No admin on server; setting timeout for %fs", timeout))
        
        timer.Adjust("PlayXAdminTimeout", timeout, 1)
        timer.Start("PlayXAdminTimeout")
        
        PlayX.AdminTimeoutTimerRunning = true
    end
end

hook.Add("PlayerInitialSpawn", "PlayXPlayerInitialSpawn", PlayerInitialSpawn)
hook.Add("PlayerAuthed", "PlayXPlayerPlayerAuthed", PlayerAuthed)
hook.Add("PlayerDisconnected", "PlayXPlayerDisconnected", PlayerDisconnected)

timer.Adjust("PlayXMediaExpire", 1, 1, function()
    print("PlayX: Media has expired")
    PlayX.EndMedia()
end)

timer.Adjust("PlayXAdminTimeout", 1, 1, function()
    print("PlayX: No administrators have been present for an extended period of time; timing out media")
    PlayX.EndMedia()
end) 