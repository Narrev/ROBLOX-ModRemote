--[[
	ModRemote v3.18
		ModuleScript for handling networking via client/server
		
	Documentation for this ModuleScript can be found at
		https://github.com/VoidKnight/ROBLOX-RemoteModule/tree/master/Version-3.x
		
	@Author Vorlias
	Edited by Narrev
]]

local server		= game:FindService("NetworkServer")
local ReplicatedStorage	= game:GetService("ReplicatedStorage")
local remote		= {
	Events = {};
	Functions = {};
	FuncCache = {};
	event = {};
	func = {};
}

assert(workspace.FilteringEnabled or not server, "[ModRemote] ModRemote 3.0 does not work with filterless games due to security vulnerabilties. Please consider using Filtering or use ModRemote 2.7x")

local function Make(ClassType, Properties)
	-- @param ClassType The type of class to instantiate
	-- @param Properties The properties to use

	assert(type(Properties) == "table", "Properties is not a table")

	local Object = Instance.new(ClassType)
	
	for Index, Value in next, Properties do
		Object[Index] = Value
	end

	return Object
end

local functionStorage = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Make("Folder" , {
	Parent	= ReplicatedStorage;
	Name	= "RemoteFunctions";
})

local eventStorage = ReplicatedStorage:FindFirstChild("RemoteEvents") or Make("Folder", {
	Parent	= ReplicatedStorage;
	Name	= "RemoteEvents";
})

local function CreateFunctionMetatable(instance)
	return setmetatable({
		Instance = instance
	}, {
		__index = function(self, i)
			if rawget(remote.func,i) then
				return rawget(remote.func,i)
			else
				return rawget(self, i)
			end
		end;

		__newindex = function(self, i, v)
			if (i == 'OnCallback' and type(v) == 'function') then
				self:Callback(v)
			end
		end;
		
		__call = function(self, ...)
			if server then
				return self:CallPlayer(...)
			else
				return self:CallServer(...)
			end
		end;
	})
end

local function CreateEventMetatable(instance)
	return setmetatable({
		Instance = instance;
	}, {
		__index = function(self, i)
			if rawget(remote.event,i) then
				return rawget(remote.event,i)
			else
				return rawget(self, i)
			end
		end;

		__newindex = function(self, i, v)
			if (i == 'OnRecieved' and type(v) == 'function') then
				self:Listen(v)
			end
		end;
	})
end

local function CreateFunction(name, instance)
	local _event = CreateFunctionMetatable(instance or functionStorage:FindFirstChild(name) or Make("RemoteFunction", {
		Parent = functionStorage;
		Name = name;
	}))

	remote.Events[name] = _event
	
	return _event
end

local function CreateEvent(name, instance)
	local _event = CreateEventMetatable(instance or eventStorage:FindFirstChild(name) or Make("RemoteEvent", {
		Parent = eventStorage;
		Name = name;
	}))
	
	remote.Events[name] = _event
	
	return _event
end

local function GetEvent(name)
	return eventStorage:FindFirstChild(name)
end

local function GetFunction(name)
	return functionStorage:FindFirstChild(name)
end

-- Remote functions

function remote:RegisterChildren(instance)
	assert(server, "RegisterChildren can only be called from the server.")
	local parent = instance or getfenv(0).script

	if parent then
		for i, child in pairs(parent:GetChildren()) do
			if child:IsA("RemoteEvent") then
				CreateEvent(child.Name, child)
			elseif child:IsA("RemoteFunction") then
				CreateFunction(child.Name, child)
			end
		end
	end
end

function remote:GetEventFromInstance(instance)
	return CreateEventMetatable(instance)
end

function remote:CreateEvent(name)
	--- Creates an event 
	-- @param string name - the name of the event.

	if not server then warn("[ModRemote] CreateEvent should be used by the server.") end
	return CreateEvent(name)
end

function remote:GetEvent(name)
	--- Gets an event if it exists, otherwise errors
	-- @param string name - the name of the event.

	assert(type(name) == 'string', "[ModRemote] GetEvent - Name must be a string")
	assert(eventStorage:FindFirstChild(name),"[ModRemote] GetEvent - Event " .. name .. " not found, create it using CreateEvent.")
	
	return remote.Events[name] or CreateEvent(name)
end

function remote:GetFunctionFromInstance(instance)
	return CreateFunctionMetatable(instance)
end

function remote:GetFunction(name)
	--- Gets a function if it exists, otherwise errors
	-- @param string name - the name of the function.

	assert(type(name) == 'string', "[ModRemote] GetFunction - Name must be a string")
	assert(functionStorage:FindFirstChild(name),"[ModRemote] GetFunction - Function " .. name .. " not found, create it using CreateFunction.")

	return remote.Functions[name] or CreateFunction(name)
end

function remote:CreateFunction(name)
	--- Creates a function
	-- @param string name - the name of the function.

	if not server then warn("[ModRemote] CreateFunction should be used by the server.") end
	return CreateFunction(name)
end

do	local FuncCache, remoteEvent, remoteFunction = remote.FuncCache, remote.event, remote.func

	-- RemoteEvent Object Methods
	function remoteEvent:SendToPlayers(playerList, ...)
		assert(server, "[ModRemote] SendToPlayers should be called from the Server side.")
		for _, player in pairs(playerList) do
			self.Instance:FireClient(player, ...)
		end
	end
	
	function remoteEvent:SendToPlayer(player, ...)
		assert(server, "[ModRemote] SendToPlayers should be called from the Server side.")
		self.Instance:FireClient(player, ...)
	end
	
	function remoteEvent:SendToServer(...)
		assert(not server, "SendToServer should be called from the Client side.")
		self.Instance:FireServer(...)
	end
	
	function remoteEvent:SendToAllPlayers(...)
		assert(server, "[ModRemote] SendToPlayers should be called from the Server side.")
		self.Instance:FireAllClients(...)
	end
	
	function remoteEvent:Listen(func)
		if server then
			self.Instance.OnServerEvent:connect(func)
		else
			self.Instance.OnClientEvent:connect(func)
		end
	end
	
	function remoteEvent:Wait()
		if server then
			self.Instance.OnServerEvent:wait()
		else
			self.Instance.OnClientEvent:wait()
		end
	end

	function remoteEvent:GetInstance()
		return self.Instance
	end

	function remoteEvent:Destroy()
		self.Instance:Destroy()
	end

	-- RemoteFunction Object Methods
	function remoteFunction:CallPlayer(player, ...)

		assert(server, "[ModRemote] CallPlayer should be called from the server side.")
		
		local args = {...}
		local attempt, err = pcall(function()
			return self.Instance:InvokeClient(player, unpack(args))
		end)
		
		if not attempt then
			warn("[ModRemote] CallPlayer - Failed to recieve response from " .. player.Name)
			return nil
		end	
	end
	
	function remoteFunction:CallServerIntl(...)
		assert(not server, "[ModRemote] CallServer should be called from the client side.")
		return self.Instance:InvokeServer(...)
	end
	
	function remoteFunction:Callback(func)
		if server then
			self.Instance.OnServerInvoke = func
		else
			self.Instance.OnClientInvoke = func
		end
	end
	
	function remoteFunction:GetInstance()
		return self.Instance
	end
	
	function remoteFunction:Destroy()
		self.Instance:Destroy()
	end
	
	function remoteFunction:SetClientCache(seconds, useAction)
		
		local seconds = seconds or 10
		assert(server, "SetClientCache must be called on the server.")
		local instance = self:GetInstance()
		
		if seconds == false or seconds < 1 then
			local cache = instance:FindFirstChild("ClientCache")
			if cache then cache:Destroy() end
		else
			local cache = instance:FindFirstChild("ClientCache") or Make("IntValue", {
				Parent = instance;
				Name = "ClientCache";
				Value = seconds;
			})
		end
		
		if useAction then
			local cache = instance:FindFirstChild("UseActionCaching") or Make("BoolValue", {
				Parent = instance;
				Name = "UseActionCaching";
				Value = true;
			})
		else
			local cache = instance:FindFirstChild("UseActionCaching")
			if cache then cache:Destroy() end			
		end
	end
	
	function remoteFunction:ResetClientCache()

		assert(not server, "ResetClientCache must be used on the client.")

		if self.Instance:FindFirstChild("ClientCache") then
			FuncCache[self.Instance:GetFullName()] = {Expires = 0, Value = nil}
		else
			warn(self.Instance:GetFullName() .. " does not have a cache.")
		end		
	end
	
	function remoteFunction:CallServer(...)
		local args = {...}
		local clientCache = self.Instance:FindFirstChild("ClientCache")

		if clientCache then
			local cacheName = self.Instance:FindFirstChild("UseActionCaching") and self.Instance:GetFullName() .. "-" .. tostring(args[1]) or self.Instance:GetFullName()
			
 			local cached = FuncCache[cacheName]
			if (cached and os.time() < cached.Expires) then
				return unpack(cached.Value)
			else
				
				local newVal = {self:CallServerIntl(unpack(args))}
				FuncCache[cacheName] = {Expires = os.time() + clientCache.Value, Value = newVal}
				return unpack(newVal)
			end
		else
			return self:CallServerIntl(...)
		end
	end
end

local remoteMT = {
	__call = function(self, ...)
		assert(server, "ModRemote can only be called from server.")
		
		local args = {...}
		if #args > 0 then
			for _, dir in pairs(args) do
				remote:RegisterChildren(dir)
			end
		else
			remote:RegisterChildren()
		end
		
		return self
	end;
}

return setmetatable(remote, remoteMT)
