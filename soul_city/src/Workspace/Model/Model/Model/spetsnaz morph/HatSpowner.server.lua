-- Hat Spowner by TankLeadfoot

while (script:findFirstChild("HatAttachmentForward") == nil) do wait(0.1) end
while (script:findFirstChild("HatAttachmentPos") == nil) do wait(0.1) end
while (script:findFirstChild("HatAttachmentRight") == nil) do wait(0.1) end
while (script:findFirstChild("HatAttachmentUp") == nil) do wait(0.1) end
while (script:findFirstChild("HatMeshId") == nil) do wait(0.1) end
while (script:findFirstChild("HatName") == nil) do wait(0.1) end
while (script:findFirstChild("HatScale") == nil) do wait(0.1) end
while (script:findFirstChild("HatSize") == nil) do wait(0.1) end
while (script:findFirstChild("HatTextureId") == nil) do wait(0.1) end
while (script:findFirstChild("HatVertexColor") == nil) do wait(0.1) end
while (script:findFirstChild("HatformFactor") == nil) do wait(0.1) end

local p = Instance.new("Part")
p.Name = "Handle"
p.BrickColor = BrickColor.new("Medium stone grey")
p.CanCollide = false
p.Locked = true
p.formFactor = 0
p.BackSurface = 0
p.BottomSurface = 0
p.FrontSurface = 0
p.LeftSurface = 0
p.RightSurface = 0
p.TopSurface = 0

local m = Instance.new("SpecialMesh")
m.Name = "Mesh"
m.Parent = p

local h = Instance.new("Hat")
h.Name = script.HatName.Value
h.AttachmentForward = script.HatAttachmentForward.Value
h.AttachmentPos = script.HatAttachmentPos.Value
h.AttachmentRight = script.HatAttachmentRight.Value
h.AttachmentUp = script.HatAttachmentUp.Value
m.MeshId = script.HatMeshId.Value
m.TextureId = script.HatTextureId.Value
m.Scale = script.HatScale.Value
m.VertexColor = script.HatVertexColor.Value
p.formFactor = script.HatformFactor.Value
p.Size = script.HatSize.Value
p:Clone().Parent = h
h.Parent = script.Parent
