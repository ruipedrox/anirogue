local animation = script.Parent:WaitForChild('Animation'):WaitForChild('run')
local humanoid = script.Parent:WaitForChild('Humanoid')
local idle = humanoid:LoadAnimation(animation)
idle:play()
idle.Looped = true