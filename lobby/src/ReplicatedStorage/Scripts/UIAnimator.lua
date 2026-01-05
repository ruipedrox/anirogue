local TweenService = game:GetService("TweenService")
local UIAnimator = {}

local OPEN_TIME = 0.25
local CLOSE_TIME = 0.20
local EASING = Enum.EasingStyle.Quad

-- Very simple animator: shift Y offset by -30 for entry, tween to original; exit reverses.
function UIAnimator.PlayOpen(frame, onComplete)
    local original = frame.Position
    -- move further offscreen: shift by frame height + margin
    local h = (frame.AbsoluteSize and frame.AbsoluteSize.Y) or 300
    local shift = h + 100
    local shifted = UDim2.new(original.X.Scale, original.X.Offset, original.Y.Scale, original.Y.Offset - shift)
    frame.Position = shifted
    frame.Visible = true
    local tween = TweenService:Create(frame, TweenInfo.new(OPEN_TIME, EASING, Enum.EasingDirection.Out), {Position = original})
    tween:Play()
    tween.Completed:Connect(function()
        if onComplete then onComplete(true) end
    end)
end

function UIAnimator.PlayClose(frame, onComplete)
    local original = frame.Position
    local h = (frame.AbsoluteSize and frame.AbsoluteSize.Y) or 300
    local shift = h + 100
    local shifted = UDim2.new(original.X.Scale, original.X.Offset, original.Y.Scale, original.Y.Offset - shift)
    local tween = TweenService:Create(frame, TweenInfo.new(CLOSE_TIME, EASING, Enum.EasingDirection.In), {Position = shifted})
    tween:Play()
    tween.Completed:Connect(function()
        frame.Visible = false
        frame.Position = original
        if onComplete then onComplete(true) end
    end)
end

return UIAnimator
