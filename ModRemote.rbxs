-- @author Vorlias
-- @editor Narrev

--[[
	RemoteManager v4.00
		ModuleScript for handling networking via client/server
		
	Documentation for this ModuleScript can be found at
		https://github.com/VoidKnight/ROBLOX-RemoteModule/tree/master/Version-3.x




Remote Events:
	
functions:

	void FireAllClients ( Variant... arguments )
		Fires the OnClientEvent event for each client.

	void FireClient ( Player player, Variant... arguments )
		Fires OnClientEvent for the specified player. Only connections in LocalScript that are running on the specified player's client will fire. This varies from the RemoteFunction class which will queue requests.

	void FireServer ( Variant... arguments )
		Fires the OnServerEvent event on the server using the arguments specified with an additional player argument at the beginning.

Events:

	OnClientEvent ( Variant... arguments )
		Fires listening functions in LocalScripts when either FireClient or FireAllClients is called from a Script.

	OnServerEvent ( Player player, Variant... arguments )
		Fires listening functions in Scripts when FireServer is called from a LocalScript.

	

]]

-- SOLOTESTMODE -- Use custom signal objects for SoloTestMode
local RunService = game:GetService("RunService")

local SoloTestMode = RunService:IsClient() == RunService:IsServer()
local ServerSide = RunService:IsServer() and not SoloTestMode
local ClientSide = not ServerSide and not SoloTestMode

-- Constants
local client_Max_Wait_For_Remotes = 1
local default_Client_Cache = 10

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = {remoteEvent = {}; remoteFunction = {}}

-- Helper functions
local Load = require(ReplicatedStorage:WaitForChild("NevermoreEngine"))
local Make = Load("Make")
local HireMaid = Load("Maid")
local MakeSignal = Load("Signal")
local WaitForChild = Load("WaitForChild")

local ResourceFolder = ReplicatedStorage:WaitForChild("NevermoreResources")

-- Localize Tables
local remoteEvent = remote.remoteEvent
local remoteFunction = remote.remoteFunction
local FuncCache = {}
local RemoteEvents = {}
local RemoteFunctions = {}

-- Localize Functions
local time = os.time
local newInstance = Instance.new

-- Get storage or create if nonexistent
local functionStorage, eventStorage

if not ClientSide then -- Server, or SoloTestMode
	functionStorage = ResourceFolder:FindFirstChild("RemoteFunctions") or Make("Folder" , {
		Parent	= ResourceFolder;
		Name	= "RemoteFunctions";
	})

	eventStorage = ResourceFolder:FindFirstChild("RemoteEvents") or Make("Folder", {
		Parent	= ResourceFolder;
		Name	= "RemoteEvents";
	})
else
	assert(WaitForChild(ResourceFolder, "RemoteFunctions", client_Max_Wait_For_Remotes), "[RemoteManager] RemoteFunctions folder not found.")
	assert(WaitForChild(ResourceFolder, "RemoteEvents", client_Max_Wait_For_Remotes), "[RemoteManager] RemoteEvents folder not found.")

	functionStorage = ResourceFolder:FindFirstChild("RemoteFunctions")
	eventStorage = ResourceFolder:FindFirstChild("RemoteEvents")
end


-- GiveMetatable function
local GiveMetatable do

	local functionMetatable = {
		__index = function(self, i)
			return rawget(remoteFunction, i) or rawget(self, i)
		end;

		__newindex = function(self, i, v)
			if i == "OnCallback" and type(v) == "function" then
				self:Callback(v)
			elseif i == "OnServerInvoke" then
				return self.Instance.OnServerInvoke
			elseif i == "OnClientInvoke" then
				return self.Instance.OnClientInvoke
			end
		end;
		
		__call = ServerSide and
			function(self, ...) return self:CallPlayer(...) end or
			function(self, ...) return self:CallServer(...) end
	}

	local eventMetatable = {
		__index = function(self, i)
			return rawget(remoteEvent, i) or rawget(self, i)
		end;

		__newindex = function(self, i, v)
			if type(v) == "function" and i == "OnRecieved" then
				return self:Listen(v)
			elseif i == "OnServerEvent" then
				return self.Instance.OnServerEvent
			elseif i == "OnClientEvent" then
				return self.Instance.OnClientEvent
			end
		end;
	}

	function GiveMetatable(instance, bool)
		-- Gives a metatable to instance
		-- @param instance instance the instance to give the metatable to
		-- @param bool true for function, false for Event
		--	@default false
		
		local _remote = setmetatable({Instance = instance; Maid = HireMaid()}, bool and functionMetatable or eventMetatable)
		local tab = bool and RemoteFunctions or RemoteEvents
		tab[instance.Name] = _remote
		return _remote
	end
end

if ServerSide then

	-- Helper functions
	local function CreateRemote(name, bool)
		--- Creates remote with name
		-- @param bool true for function, false for Event
		local parent = bool and functionStorage or eventStorage
		local instance = parent:FindFirstChild(name) or newInstance(bool and "RemoteFunction" or "RemoteEvent")
		instance.Parent = parent
		instance.Name = name
		
		return GiveMetatable(instance, bool)
	end

	
	do -- Remote Object Methods
		local CallOnChildren = Load("CallOnChildren")
			
		local function Register(child)
			local bool = child:IsA("RemoteFunction")
			child.Parent = bool and functionStorage or eventStorage
			GiveMetatable(child, bool)
		end

		function remote:RegisterChildren(instance)
			--- Registers the Children inside of an instance
			-- @param Instance instance the object with Remotes in
			--	@default the script this was imported in to
			local parent = instance or ResourceFolder or getfenv(0).script

			if parent then
				CallOnChildren(parent, Register)
			end
		end
	end
	function remote:CreateFunction(name)
		--- Creates a function
		-- @param string name - the name of the function.

		return CreateRemote(name, true)
	end

	function remote:CreateEvent(name)
		--- Creates an event 
		-- @param string name - the name of the event.

		return CreateRemote(name)
	end

	-- RemoteEvent Object Methods
	do
		local function SendToPlayer(self, player, ...)
			self.Instance:FireClient(player, ...)
		end
		remoteEvent.Fire = SendToPlayer
		remoteEvent.FireClient = SendToPlayer
		remoteEvent.FirePlayer = SendToPlayer
		remoteEvent.SendToPlayer = SendToPlayer

		local function SendToPlayers(self, playerList, ...)
			for a = 1, #playerList do
				self.Instance:FireClient(playerList[a], ...)
			end
		end
		remoteEvent.FireClients = SendToPlayers
		remoteEvent.FirePlayers = SendToPlayers
		remoteEvent.SendToPlayers = SendToPlayers

		function SendToAllPlayers(self, ...)
			self.Instance:FireAllClients(...)
		end	
		remoteEvent.FireAllClients = SendToAllPlayers
		remoteEvent.FireAllPlayers = SendToAllPlayers
		remoteEvent.SendToAllPlayers = SendToAllPlayers
	end

	function remoteEvent:Listen(func)
		local connection = self.Instance.OnServerEvent:connect(func)
		self.Maid:GiveTask(connection)
		return connection
	end

	function remoteEvent:Wait()
		self.Instance.OnServerEvent:wait()
	end

	remoteEvent.wait = remoteEvent.Wait

	-- RemoteFunction Object Methods
	function remoteFunction:CallPlayer(player, ...)
		local tuple = {...}
		local attempt, err = pcall(function()
			return self.Instance:InvokeClient(player, unpack(tuple))
		end)
		
		if not attempt then
			return warn("[RemoteManager] CallPlayer - Failed to recieve response from " .. player.Name)
		end	
	end

	function remoteFunction:Callback(func)
		self.Instance.OnServerInvoke = func
	end

	function remoteFunction:SetClientCache(seconds, useAction)
		local seconds = seconds or default_Client_Cache
		local instance = self.Instance

		if seconds <= 0 then
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
			-- Put a BoolValue object inside of self.Instance to mark that we are UseActionCaching
			-- Possible Future Update: Come up with a better way to mark we are UseActionCaching
			--			We could change the ClientCache string, but that might complicate things
			--			*We could try using the Value of the ClientCache object inside the remoteFunction
			local cache = instance:FindFirstChild("UseActionCaching") or Make("BoolValue", {
				Parent = instance;
				Name = "UseActionCaching";
			})
		else
			local cache = instance:FindFirstChild("UseActionCaching")
			if cache then cache:Destroy() end			
		end
	end

	function remoteEvent:Destroy()
		self.Maid:DoCleaning()
		self.Instance:Destroy()
	end

	remoteFunction.Destroy = remoteEvent.Destroy

elseif ClientSide then
	function remoteEvent:Listen(func)
		local connection = self.Instance.OnClientEvent:connect(func)
		self.Maid:GiveTask(connection)
		return connection
	end

	function remoteEvent:Wait()
		self.Instance.OnClientEvent:wait()
	end

	remoteEvent.wait = remoteEvent.Wait

	do
		local function SendToServer(self, ...)
			self.Instance:FireServer(...)
		end
		remoteEvent.Fire = SendToServer
		remoteEvent.FireServer = SendToServer
		remoteEvent.SendToServer = SendToServer
	end
	
	function remoteFunction:Callback(func)
		self.Instance.OnClientInvoke = func
	end

	function remoteFunction:ResetClientCache()
		local instance = self.Instance
		if instance:FindFirstChild("ClientCache") then
			FuncCache[instance:GetFullName()] = {Expires = 0, Value = nil}
		else
			warn(instance:GetFullName() .. " does not have a cache.")
		end		
	end

	function remoteFunction:CallServer(...)

		local instance = self.Instance
		local clientCache = instance:FindFirstChild("ClientCache")

		if not clientCache then
			return instance:InvokeServer(...)
		else
			local cacheName = instance:GetFullName() .. (instance:FindFirstChild("UseActionCaching") and tostring(({...})[1]) or "")
			local cache = FuncCache[cacheName]

			if cache and time() < cache.Expires then
				-- If the cache exists in FuncCache and the time hasn't expired
				-- Return cached arguments
				return unpack(cache.Value)
			else
				-- The cache isn't in FuncCache or time has expired
				-- Invoke the server with the arguments
				-- Cache Arguments
				
				local cacheValue = {instance:InvokeServer(...)}
				FuncCache[cacheName] = {Expires = time() + clientCache.Value, Value = cacheValue}
				return unpack(cacheValue)
			end
		end
	end
elseif SoloTestMode then

	local ServerDataMetatable = {
		__index = function(ServerData, var)
			assert(var == "ServerSide" or var == "ClientSide", "Inappropriate value of ServerData indexed")
			local b = getfenv(0).script.ClassName
			local c = b == "ModuleScript" and error("Problem with Client/Server Detection") or b == "Script"
			ServerData["ServerSide"] = c
			ServerData["ClientSide"] = not c
			return ServerData[var]
		end
	}

	local ServerData = setmetatable({}, ServerDataMetatable)

	local ServerSide = ServerData.ServerSide
	local ClientSide = ServerData.ClientSide

	local GiveMetatable do
		local functionMetatable = {
			__index = function(self, i)
				return rawget(remoteFunction, i) or rawget(self, i)
			end;

			__newindex = function(self, i, v)
				if i == "OnCallback" and type(v) == "function" then
					self:Callback(v)
				elseif i == "OnServerInvoke" then
					return self.Instance.OnServerInvoke
				elseif i == "OnClientInvoke" then
					return self.Instance.OnClientInvoke
				end
			end;
			
			__call = ServerSide and
				function(self, ...) return self:CallPlayer(...) end or
				function(self, ...) return self:CallServer(...) end
		}

		local eventMetatable = {
			__index = function(self, i)
				return rawget(remoteEvent, i) or rawget(self, i)
			end;

			__newindex = function(self, i, v)
				if type(v) == "function" and i == "OnRecieved" then
					return self:Listen(v)
				elseif i == "OnServerEvent" then
					return self.Instance.OnServerEvent
				elseif i == "OnClientEvent" then
					return self.Instance.OnClientEvent
				end
			end;
		}

		function GiveMetatable(instance, bool)
			-- Gives a metatable to instance
			-- @param instance instance the instance to give the metatable to
			-- @param bool true for function, false for Event
			--	@default false
			
			local _remote = setmetatable({Instance = instance; Maid = HireMaid()}, bool and functionMetatable or eventMetatable)
			local tab = bool and RemoteFunctions or RemoteEvents
			tab[instance.Name] = _remote
			return _remote
		end
	end

	-- Server
	local function CreateRemote(name, bool)
		--- Creates remote with name
		-- @param bool true for function, false for Event
		local parent = bool and functionStorage or eventStorage
		local instance = parent:FindFirstChild(name) or newInstance(bool and "RemoteFunction" or "RemoteEvent")
		instance.Parent = parent
		instance.Name = name
		
		return GiveMetatable(instance, bool)
	end

	
	do -- Remote Object Methods
		local CallOnChildren = Load("CallOnChildren")
			
		local function Register(child)
			local bool = child:IsA("RemoteFunction")
			child.Parent = bool and functionStorage or eventStorage
			GiveMetatable(child, bool)
		end

		function remote:RegisterChildren(instance)
			--- Registers the Children inside of an instance
			-- @param Instance instance the object with Remotes in
			--	@default the script this was imported in to
			local parent = instance or ResourceFolder or getfenv(0).script

			if parent then
				CallOnChildren(parent, Register)
			end
		end
	end
	function remote:CreateFunction(name)
		--- Creates a function
		-- @param string name - the name of the function.

		return CreateRemote(name, true)
	end

	function remote:CreateEvent(name)
		--- Creates an event 
		-- @param string name - the name of the event.

		return CreateRemote(name)
	end

	-- RemoteEvent Object Methods
	do
		local function SendToPlayer(self, player, ...)
			self.Instance:FireClient(player, ...)
		end
		remoteEvent.Fire = SendToPlayer
		remoteEvent.FireClient = SendToPlayer
		remoteEvent.FirePlayer = SendToPlayer
		remoteEvent.SendToPlayer = SendToPlayer

		local function SendToPlayers(self, playerList, ...)
			for a = 1, #playerList do
				self.Instance:FireClient(playerList[a], ...)
			end
		end
		remoteEvent.FireClients = SendToPlayers
		remoteEvent.FirePlayers = SendToPlayers
		remoteEvent.SendToPlayers = SendToPlayers

		function SendToAllPlayers(self, ...)
			self.Instance:FireAllClients(...)
		end	
		remoteEvent.FireAllClients = SendToAllPlayers
		remoteEvent.FireAllPlayers = SendToAllPlayers
		remoteEvent.SendToAllPlayers = SendToAllPlayers
	end

	function remoteEvent:Listen(func)
		local connection = self.Instance.OnServerEvent:connect(func)
		self.Maid:GiveTask(connection)
		return connection
	end

	function remoteEvent:Wait()
		self.Instance.OnServerEvent:wait()
	end

	remoteEvent.wait = remoteEvent.Wait

	-- RemoteFunction Object Methods
	function remoteFunction:CallPlayer(player, ...)
		local tuple = {...}
		local attempt, err = pcall(function()
			return self.Instance:InvokeClient(player, unpack(tuple))
		end)
		
		if not attempt then
			return warn("[RemoteManager] CallPlayer - Failed to recieve response from " .. player.Name)
		end	
	end

	function remoteFunction:Callback(func)
		self.Instance.OnServerInvoke = func
	end

	function remoteFunction:SetClientCache(seconds, useAction)
		local seconds = seconds or default_Client_Cache
		local instance = self.Instance

		if seconds <= 0 then
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
			-- Put a BoolValue object inside of self.Instance to mark that we are UseActionCaching
			-- Possible Future Update: Come up with a better way to mark we are UseActionCaching
			--			We could change the ClientCache string, but that might complicate things
			--			*We could try using the Value of the ClientCache object inside the remoteFunction
			local cache = instance:FindFirstChild("UseActionCaching") or Make("BoolValue", {
				Parent = instance;
				Name = "UseActionCaching";
			})
		else
			local cache = instance:FindFirstChild("UseActionCaching")
			if cache then cache:Destroy() end			
		end
	end

	function remoteEvent:Destroy()
		self.Maid:DoCleaning()
		self.Instance:Destroy()
	end

	remoteFunction.Destroy = remoteEvent.Destroy
	-- End Server

	-- Client
	function remoteEvent:Listen(func)
		local connection = self.Instance.OnClientEvent:connect(func)
		self.Maid:GiveTask(connection)
		return connection
	end

	function remoteEvent:Wait()
		self.Instance.OnClientEvent:wait()
	end

	remoteEvent.wait = remoteEvent.Wait

	do
		local function SendToServer(self, ...)
			self.Instance:FireServer(...)
		end
		remoteEvent.Fire = SendToServer
		remoteEvent.FireServer = SendToServer
		remoteEvent.SendToServer = SendToServer
	end
	
	function remoteFunction:Callback(func)
		self.Instance.OnClientInvoke = func
	end

	function remoteFunction:ResetClientCache()
		local instance = self.Instance
		if instance:FindFirstChild("ClientCache") then
			FuncCache[instance:GetFullName()] = {Expires = 0, Value = nil}
		else
			warn(instance:GetFullName() .. " does not have a cache.")
		end		
	end

	function remoteFunction:CallServer(...)

		local instance = self.Instance
		local clientCache = instance:FindFirstChild("ClientCache")

		if not clientCache then
			return instance:InvokeServer(...)
		else
			local cacheName = instance:GetFullName() .. (instance:FindFirstChild("UseActionCaching") and tostring(({...})[1]) or "")
			local cache = FuncCache[cacheName]

			if cache and time() < cache.Expires then
				-- If the cache exists in FuncCache and the time hasn't expired
				-- Return cached arguments
				return unpack(cache.Value)
			else
				-- The cache isn't in FuncCache or time has expired
				-- Invoke the server with the arguments
				-- Cache Arguments
				
				local cacheValue = {instance:InvokeServer(...)}
				FuncCache[cacheName] = {Expires = time() + clientCache.Value, Value = cacheValue}
				return unpack(cacheValue)
			end
		end
	end
	-- End Client
	
end

function remote:GetFunction(name)
	--- Gets a function if it exists, otherwise errors
	-- @param string name - the name of the function.

	assert(type(name) == "string", "[RemoteManager] GetFunction - Name must be a string")
	assert(WaitForChild(functionStorage, name, client_Max_Wait_For_Remotes), "[RemoteManager] GetFunction - Function " .. name .. " not found, create it using CreateFunction.")

	return RemoteFunctions[name] or GiveMetatable(functionStorage[name], true)
end

function remote:GetEvent(name)
	--- Gets an event if it exists, otherwise errors
	-- @param string name - the name of the event.

	assert(type(name) == "string", "[RemoteManager] GetEvent - Name must be a string")
	assert(WaitForChild(eventStorage, name, client_Max_Wait_For_Remotes), "[RemoteManager] GetEvent - Event " .. name .. " not found, create it using CreateEvent.")
	
	return RemoteEvents[name] or GiveMetatable(eventStorage[name])
end

function remoteEvent:disconnect()
	self.Maid:DoCleaning()
end

remoteFunction.disconnect = remoteEvent.disconnect

if not ClientSide then
	setmetatable(remote, {
		__call = function(self, ...)			
			local args = {...}
			if #args > 0 then
				for a = 1, #args do
					remote:RegisterChildren(args[a])
				end
			else
				remote:RegisterChildren()
			end	
			return self
		end
	})
end

return remote
