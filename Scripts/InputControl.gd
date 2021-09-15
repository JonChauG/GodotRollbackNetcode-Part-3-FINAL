#By Jon Chau
extends Node

#amount of input delay in frames
var input_delay = 5 
#number of frame states to save in order to implement rollback (max amount of frames able to rollback)
var rollback = 7 

var frame_num = 0 #ranges between 0-255 per circular input array cycle (cycle is every 256 frames)

var input_array = [] #array to hold 256 Inputs
var state_queue = [] #queue for Frame_States of past frames (for rollback)

#tracks current game status
enum Game {END, WAITING, PLAYING}
var game = Game.WAITING
var status = "" #for giving additional StatusLabel info

var network_thread = null #thread to receive inputs from over the network
var UDPPeer = PacketPeerUDP.new()

var input_arrival_array = [] #256 boolean array, tracks if inputs for a given frame have arrived from the network
var input_viable_request_array = [] #256 boolean array, tracks if local inputs for a given frame are viable to be sent by request
var input_array_mutex = Mutex.new() #encloses input_array and input_arrival_array
var input_viable_request_array_mutex = Mutex.new()

var input_received = false #boolean to communicate between threads if new inputs have been received
var input_received_mutex = Mutex.new() #encloses input_received and also the game variable that tracks current game status

#frame range of past inputs to send every frame
var dup_send_range = 5
#amount of input packets to send per frame
var packet_amount = 3

# --- new global script variables ---

var prev_frame_arrival_array = [] #boolean array to compare input arrivals between current frame and previous frame

#---classes---
class Inputs:
	#Indexing [0]: W, [1]: A, [2]: S, [3]: D, [4]: SPACE
	#inputs by local player for a single frame
	var local_input = [false, false, false, false, false] 
	#inputs by a player over network for a single frame
	var net_input = [false, false, false, false, false]
	var encoded_local_input = 0
	
	func duplicate():
		var duplicate = Inputs.new()
		duplicate.local_input = local_input.duplicate()
		duplicate.net_input = net_input.duplicate()
		duplicate.encoded_local_input = encoded_local_input
		return duplicate


class Frame_State:
	var inputs #the Inputs of this state's frame
	var frame #frame number according to 256 frame cycle number
	var game_state #dictionary holds the values need for tracking a game's state at a given frame. Keys are child names.
	var actual_input #boolean, whether the state contains guessed input (false) or actual input (true) from networked player

	func _init(_inputs : Inputs, _frame : int, _game_state : Dictionary, _actual_input : bool):
		inputs = _inputs
		frame = _frame
		game_state = _game_state #Dictionary of dictionaries
		#game_state keys are child names, values are their individual state dictionaries
		#state dicts: Keys are state var names (e.g. x, y), values are the var values 
		actual_input = _actual_input


#---functions---
func thr_network_inputs(_userdata): #thread function to process data from network
	var result = null
	var packet_idx = 1
	var new_input = false
	
	while(true):
		input_received_mutex.lock()
		if (game == Game.END): #stop thread function if game has ended
			input_received_mutex.unlock()
			return
		input_received_mutex.unlock()
		
		result = UDPPeer.get_packet() #receive a single packet
		if result:
			match result[0]: #switch statement for first byte
				0: #input received
					packet_idx = 1
					input_array_mutex.lock()
					while (packet_idx < result.size()):
						if input_arrival_array[result[packet_idx]] == false: #if a non-duplicate input arrives for a frame
							input_array[result[packet_idx]].net_input = [
									bool(result[packet_idx + 1] & 1),
									bool(result[packet_idx + 1] & 2),
									bool(result[packet_idx + 1] & 4),
									bool(result[packet_idx + 1] & 8),
									bool(result[packet_idx + 1] & 16)]
							input_arrival_array[result[packet_idx]] = true
							new_input = true
						packet_idx += 2
					input_array_mutex.unlock()
					
					if new_input:
						input_received_mutex.lock()
						input_received = true
						if game == Game.WAITING:
							game = Game.PLAYING
						input_received_mutex.unlock()
					new_input = false
				
				1: #request for input received
					var frame = result[1]
					var packet_arr = [0]
					input_array_mutex.lock()
					input_viable_request_array_mutex.lock()
					while (frame != result[2]): #send inputs for requested frame and newer past frames
						if input_viable_request_array[frame] == false: 
							break #do not send invalid inputs from future frames
						packet_arr.append(frame)
						packet_arr.append(input_array[frame].encoded_local_input)
						frame = (frame + 1)%256
					input_viable_request_array_mutex.unlock()
					input_array_mutex.unlock()
					for _x in range(packet_amount):
						UDPPeer.put_packet(PoolByteArray(packet_arr))
				
				2: #game start (handshake)
					input_received_mutex.lock()
					if game == Game.WAITING:
						game = Game.PLAYING
						input_received = true
						input_received_mutex.unlock()
					else:
						input_received_mutex.unlock()
						if (result[1] == 0):
							for _x in range(packet_amount):
								UDPPeer.put_packet(PoolByteArray([2, 1])) #send reply handshake to networked game	
				
				3: #game end
					input_received_mutex.lock()
					game = Game.END
					input_received_mutex.unlock()
					return


func _ready():
	#initialize arrays
	for _x in range (0, 256):
		input_array.append(Inputs.new())
		input_arrival_array.append(false)
		input_viable_request_array.append(false)
	
	#initialize state queue, prev_frame_arrival_array
	for i in range (0, rollback):
		#empty inputs, frame 0, inital game state, treat initial empty inputs as true, actual inputs
		state_queue.append(Frame_State.new(Inputs.new(), 0, get_game_state(), true))
		prev_frame_arrival_array.append(true)
		input_arrival_array[-(i + 1)] = true #assume empty inputs at game start during rollback window
	
	for i in range (0, input_delay):
		input_arrival_array[i] = true #assume empty inputs at game start during input_delay window
		input_viable_request_array[i] = true
	
	#set up networking thread
	UDPPeer.listen(7700, "*")
	UDPPeer.set_dest_address("::1", 7700)
	network_thread = Thread.new()
	network_thread.start(self, "thr_network_inputs", null, 2)


func _physics_process(_delta):
	input_received_mutex.lock()
	
	if Input.is_key_pressed(KEY_ESCAPE):
		game = Game.END
		for _x in range(packet_amount):
			UDPPeer.put_packet(PoolByteArray([3])) #send game end signal to networked game
	
	if (game == Game.END): #if game has ended, stop networking thread (cleanup)
		input_received_mutex.unlock()
		if (network_thread):
			network_thread = network_thread.wait_to_finish() #join networking thread
			UDPPeer.close()
		return
	
	if (input_received):
		#if the oldest Frame_State in the queue uses a guess input, and the actual input for the oldest Frame_State has not arrived,
		#then DELAY the game
		if state_queue[0].actual_input == false:
			input_array_mutex.lock()
			if input_arrival_array[state_queue[0].frame] == false:
				input_array_mutex.unlock()
				input_received = false #wait until needed net input arrives
				input_received_mutex.unlock()
				for _x in range(packet_amount):
					UDPPeer.put_packet(PoolByteArray([1, state_queue[0].frame, (frame_num + input_delay)%256])) #send request for needed input
				status = "DELAY: Waiting for net input. Current frame_num: " + str(frame_num)
			else:
				input_array_mutex.unlock()
				input_received_mutex.unlock()
				status = "" 
				handle_input()
		else:
			input_received_mutex.unlock()
			status = "" 
			handle_input()
	elif (game == Game.PLAYING):#send request for needed inputs for past frames
		input_received_mutex.unlock()
		for _x in range(packet_amount):
			UDPPeer.put_packet(PoolByteArray([1, state_queue[0].frame, (frame_num + input_delay)%256])) #send request for needed input
	elif (game == Game.WAITING): #search for networked game instance
		input_received_mutex.unlock()
		UDPPeer.put_packet(PoolByteArray([2, 0])) #send ready handshake to networked player
	else:
		input_received_mutex.unlock()


func handle_input(): #get input, call child functions and run rollback if necessary
	var pre_game_state = null
	frame_start_all()
	
	var local_input = [false, false, false, false, false]
	var encoded_local_input = 0
	#record local inputs
	if Input.is_key_pressed(KEY_W):
		local_input[0] = true
		encoded_local_input += 1
	if Input.is_key_pressed(KEY_A):
		local_input[1] = true
		encoded_local_input += 2
	if Input.is_key_pressed(KEY_S):
		local_input[2] = true
		encoded_local_input +=4
	if Input.is_key_pressed(KEY_D):
		local_input[3] = true
		encoded_local_input += 8
	if Input.is_key_pressed(KEY_SPACE):
		local_input[4] = true
		encoded_local_input += 16

	input_array_mutex.lock()
	input_array[(frame_num + input_delay) % 256].local_input = local_input
	input_array[(frame_num + input_delay) % 256].encoded_local_input = encoded_local_input
	
	#send inputs over network for current and past frames
	var packet_arr = [0]
	for i in dup_send_range + 1:
		packet_arr.append((frame_num + input_delay - i) % 256)
		packet_arr.append(input_array[(frame_num + input_delay - i) % 256].encoded_local_input)
	for _x in packet_amount:
		UDPPeer.put_packet(PoolByteArray(packet_arr))
	
	var current_input = input_array[frame_num].duplicate() #use duplicate so that networking thread safely can work on input_array
	
	#if the net input for the current frame has not arrived, use a guess instead
	var actual_input = true
	if input_arrival_array[frame_num] == false:
		current_input.net_input = input_array[frame_num - 1].net_input.duplicate() #use previous frame's net input as guess
		input_array[frame_num].net_input = input_array[frame_num - 1].net_input.duplicate()
		actual_input = false
	
	input_arrival_array[(frame_num + input_delay*2 + rollback + 1) % 256] = false #reset input arrival boolean for old frame
	
	#get input arrival checks for current frame and for old frames eligible for rollback, compare them to checks of previous frame
	var current_frame_arrival_array = []
	var current_frame_arrival = input_arrival_array[frame_num]
	var past_actual_inputs_array = []
	for i in range(1, rollback + 1): #oldest frame in first index
		current_frame_arrival_array.push_front(input_arrival_array[frame_num - i]) 
		if input_arrival_array[frame_num - i] != prev_frame_arrival_array[rollback - i]:
			past_actual_inputs_array.push_front(input_array[frame_num - i].net_input.duplicate())
	input_array_mutex.unlock()
	
	#the input made on the current frame can now be sent by request
	input_viable_request_array_mutex.lock()
	input_viable_request_array[(frame_num + input_delay) % 256] = true
	input_viable_request_array[frame_num - input_delay - rollback*2] = false #old input is not viable for requests
	input_viable_request_array_mutex.unlock()

	#Resimulate the game state whenever an actual input arrives to replace a guess (unless the actual input matches the guess),
	#even if there are still other unfulfilled guess input "holes" from second-oldest saved game state to current frame's game state
	
	var start_rollback = false
	#if an actual input for a past frame has arrived to fulfill a guess,
	if !past_actual_inputs_array.empty():
		#iterate through all saved states until the state with the guessed input to be replaced by the arrived actual input is found (rollback will begin with that state)
		#then, continue iterating and operating on remaining saved states to continue the resimulation process
		var state_index = 0 #for tracking iterated Frame_State's index in state_queue
		var new_past_actual_input = null #for operating on individual actual net_inputs in the past_actual_inputs_array
		for frame_state in state_queue: #index 0 is oldest state
			#if an arrived actual input is for a frame with a guessed input,
			if (prev_frame_arrival_array[state_index] == false && current_frame_arrival_array[state_index] == true):
				#set net input in the Frame_State from guess to actual input
				new_past_actual_input = past_actual_inputs_array.pop_front()
				if frame_state.inputs.net_input.hash() != new_past_actual_input.hash():
					frame_state.inputs.net_input = new_past_actual_input
					#if first rollback iteration, set update variables for all children to match start state required for rollback
					if start_rollback == false: 
						reset_state_all(frame_state.game_state) 
						start_rollback = true
				frame_state.actual_input = true
			
			if start_rollback == true:
				pre_game_state = get_game_state() #store pre-update game_state value for Frame_State
				input_update_all(frame_state.inputs, pre_game_state) #resimulate game state using new actual input, old guessed input, or old actual input
				frame_state.game_state = pre_game_state #update Frame_States with updated pre_game_state value
				
			state_index += 1
	
	pre_game_state = get_game_state() #get pre_game_state for current frame
	input_update_all(current_input, pre_game_state) #update with current input
	frame_end_all() 
	
	#store current frame state into queue
	state_queue.append(Frame_State.new(current_input, frame_num, pre_game_state, actual_input))
	#remove oldest state from queue
	state_queue.pop_front()
	
	#reinsert current frame's arrival boolean (for next frame's prev_frame_arrival_array)
	current_frame_arrival_array.push_back(current_frame_arrival)
	#remove oldest frame's arrival boolean (unwanted for next frame's prev_frame_arrival_array)
	current_frame_arrival_array.pop_front() 
	#save current input arrival array for comaparisons in next frame
	prev_frame_arrival_array = current_frame_arrival_array 
	
	frame_num = (frame_num + 1)%256 #increment frame_num


func frame_start_all():
	for child in get_children():
		child.frame_start()


func reset_state_all(game_state : Dictionary):
	for child in get_children():
		child.reset_state(game_state)


func input_update_all(input : Inputs, game_state : Dictionary):
	for child in get_children():
		child.input_update(input, game_state)


func frame_end_all():
	for child in get_children():
		child.frame_end()


func get_game_state():
	var state = {}
	for child in get_children():
		state[child.name] = child.get_state()
	return state.duplicate(true) #deep duplicate to copy all nested dictionaries by value instead of by reference
