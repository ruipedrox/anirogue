
sphere = script.Parent
a = 0
repeat
	sphere.Rotation = Vector3.new( 0, a, 0) --The second value of vector3 is a,
	wait(.01) 
	a = a+3 
until pigs == 1 
