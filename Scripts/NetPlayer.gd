#By Jon Chau
extends "res://Scripts/LocalPlayer.gd"

func _ready():
	._ready()
	var polygon = get_node("Polygon2D")
	polygon.color = Color(1, 1, 0, 1) #make NetPlayer yellow

func input_update(input, game_state : Dictionary):
	#calculate state of object for the given input
	var vect = Vector2(0, 0)

	#Collision detection for moving objects that can pass through each other
	for object in game_state:
		if object != name:
			if collisionMask.intersects(game_state[object]['collisionMask']):
				counter += 1

	if input.net_input[0]: #W
		vect.y += 7

	if input.net_input[1]: #A
		vect.x += 7

	if input.net_input[2]: #S
		vect.y -= 7

	if input.net_input[3]: #D
		vect.x -= 7

	if input.net_input[4]: #SPACE
		counter = counter/2

	#move_and_collide for "solid" stationary objects
	var collision = move_and_collide(vect)
	if collision:
		vect = vect.slide(collision.normal)
		move_and_collide(vect)

	collisionMask = Rect2(Vector2(position.x - rectExtents.x, position.y - rectExtents.y), Vector2(rectExtents.x, rectExtents.y) * 2)
