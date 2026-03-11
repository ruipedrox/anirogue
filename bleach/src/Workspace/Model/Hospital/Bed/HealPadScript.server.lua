local onColor = BrickColor.new(37)
local offColor = BrickColor.new(21)

local cooldown = 1
local connection = nil
local isOn = true

function turnOff()
	script.Parent.Pad.BrickColor = offColor
	isOn = false
end

function turnOn()
	script.Parent.Pad.BrickColor = onColor
	isOn = true
end

function onTouch(hit)
	if (isOn == false) then return end
	local human = hit.Parent:findFirstChild("Humanoid")
	if (human ~= nil) then
		human.Health = human.MaxHealth
		turnOff()
	end
end

connection = script.Parent.Pad.Touched:connect(onTouch)


while true do
	wait(cooldown)
	if (isOn == false) then turnOn() end
end