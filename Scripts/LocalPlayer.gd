#By Jon Chau
extends KinematicBody2D

var counter = -1 #testing value
var rectExtents = null
var collisionMask = null
var label = null

func _ready(): 
	label = get_node("Label")
	rectExtents = get_node("CollisionShape2D").shape.get_extents() #assuming constant rectanglular CollisionShape2D
	collisionMask = Rect2(Vector2(position.x - rectExtents.x, position.y - rectExtents.y), Vector2(rectExtents.x, rectExtents.y) * 2)


#reset object state to that in a given game_state, executed once per rollback 
func reset_state(game_state : Dictionary):
	#check if this object exists within the checked game_state
	if game_state.has(name):
		position.x = game_state[name]['x']
		position.y = game_state[name]['y']
		counter = game_state[name]['counter']
		collisionMask = game_state[name]['collisionMask']
	else:
		free()


func frame_start():
	#code to run at beginning of frame
	collisionMask = Rect2(Vector2(position.x - rectExtents.x, position.y - rectExtents.y), Vector2(rectExtents.x, rectExtents.y) * 2)


func input_update(input, game_state : Dictionary):
	#calculate state of object for the given input
	var vect = Vector2(0, 0)
	
	#Collision detection for InputControl children that can pass through each other
	for object in game_state:
		if object != name:
			if collisionMask.intersects(game_state[object]['collisionMask']):
				counter += 1
	
	if input.local_input[0]: #W
		vect.y -= 7
		
	if input.local_input[1]: #A
		vect.x -= 7
		
	if input.local_input[2]: #S
		vect.y += 7
		
	if input.local_input[3]: #D
		vect.x += 7
		
	if input.local_input[4]: #SPACE
		counter = counter/2

	#move_and_collide for "solid" stationary objects
	var collision = move_and_collide(vect)
	if collision:
		vect = vect.slide(collision.normal)
		move_and_collide(vect)
	
	collisionMask = Rect2(Vector2(position.x - rectExtents.x, position.y - rectExtents.y), Vector2(rectExtents.x, rectExtents.y) * 2)


func frame_end():
	#code to run at end of frame (after all input_update calls)
	label.text = str(counter)


func get_state():
	#return dict of state variables to be stored in Frame_States
	return {'x': position.x, 'y': position.y, 'counter': counter, 'collisionMask': collisionMask}
