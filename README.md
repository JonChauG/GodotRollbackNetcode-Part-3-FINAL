# GodotRollbackNetcode-Part-3

Repositories:

https://github.com/JonChauG/GodotRollbackNetcode-Part-1

https://github.com/JonChauG/GodotRollbackNetcode-Part-2

https://github.com/JonChauG/GodotRollbackNetcode-Part-3-FINAL

---

Tutorial Videos:

Part 1: Base Game and Saving Game States - https://www.youtube.com/watch?v=AOct7C422z8

Part 2: Delay-Based Netcode - https://www.youtube.com/watch?v=X55-gfqhQ_E

Part 3 (Final): Rollback Netcode - https://www.youtube.com/watch?v=sg1Q_71cjd8

---

Part 3 Video Transcript:

### DEMO

  In this third, final video, we will be forming rollback netcode by combining the saving of game states we made in the first video with the delay-based netcode we made in the second video. Here is the final product of this video: a player controls the bottom green square in one game that corresponds to the top yellow square in the other game.

  In a good connection, both games are synchronized and gameplay is smooth.
 
  In an ok connection when some necessary communication is not immediately fulfilled, the games will temporarily continue without delaying in a desynchronized state, but will later readjust themselves to a correctly synchronized state when the necessary communication occurs.

  During a very bad connection, the games will delay when the necessary communication between them is not fulfilled after a period of time so that they can wait for the communication to occur.

### PRESENTATION: ROLLBACK NETCODE OVERVIEW

  With our delay-based netcode that we made previously, if the input from the networked game that is intended for the current frame does not arrive on time before our game tries to proceed on the current frame, our game will delay until that needed input for the current frame arrives.

  Assuming that two network-connected game instances are on the same frame number (as shown here), the time window for inputs to be sent from one game and arrive on time for the other game so that the receiving game will not delay- is determined by the input delay that we set.
  
  So if both games were on frame 100 and the input delay was 5 frames, the inputs recorded and sent on frame 100 by both games would be intended for frame 105. These inputs would have 5 frames’ worth of time to be delivered before the games reach frame 105 and need the inputs to proceed. If the inputs are not delivered on time for either game, that game will delay to wait for the inputs to arrive.
  
  If one game ends up ahead of another in terms of frame number, the time window is smaller for inputs sent by the game that is behind. So here, Game B is two frames ahead of Game A in frame number. As a result, Game B will need inputs from Game A for any given frame two frames sooner, so the time window for inputs that Game A sends will be two frames shorter than the input delay. If Game A were on frame 100 and Game B were on frame 102, Game A will send an input intended for frame 105, but Game B will need that input in 3 frames’ worth of time before it will delay to wait.

  So now, I’ll go over rollback netcode. Unlike delay-based netcode, when the input for the current frame has not arrived yet, we still allow the game to proceed on the current frame by using a temporary guess input instead. In this example, the game has not received any inputs when the current frame number was 101, 102, 103, 104, and 105, so the game has moved the yellow net player object, here, to the right as a guess on each frame.
  
  When the actual input for a past frame arrives later, we use it to replace the temporary guess input of that past frame, and we resimulate the game state using the actual input to obtain a corrected game state. This corrected game state is as if the actual input arrived on time. In our example, all of the missing actual inputs have now arrived before frame 106. Using a base game state from before temporary guess inputs were used, we apply the newly arrived actual net inputs on the net player object and reapply the local inputs to the local player object for the past frames. Then, we process the inputs for the current frame, frame 106, as normal. Because the actual net inputs in this example moved the net player diagonally down and right for each frame, the end result on frame 106 has the net player moved diagonally down and right compared to its position in the base game state.

  For our game, the baseline game states we use for starting resimulation comes from the saving of game states that we implemented in the first video.
  
  Because resimulation of past frames and the processing of the current frame takes place in a single frame, there will be an immediate visual adjustment. Here, because all of the actual inputs moved the net player object down and right, compared to the guess inputs which moved the net player only to the right, the net player seemingly moves an impossible distance in a single frame during the adjustment to a corrected game state.

  Overall, the benefit of rollback netcode is not having to delay the game when inputs do not arrive on time as long as we can correct the game state when the inputs arrive later.

  If we allow the game to use temporary guess inputs for and resimulate for an unlimited number of frames when inputs do not arrive on time, we would never have to delay our game when waiting for late inputs. However, when resimulating a large number of frames, we could have giant visual adjustment that could result in an unwanted game experience. Of course, there would also be memory and processing limitations when trying to save an absurd amount of states and resimulating a very large number of frames respectively.

  As a result, we should decide on a limit for the amount of frames we are able to use temporary guess inputs for and later resimulate. If inputs still have not arrived on time when we have reached our set limit of the amount of frames we can resimulate, we can delay the game as we would with regular delay-based netcode to wait for the late inputs. When the late inputs finally arrive while we are delaying, we resimulate the game state with the late inputs and continue the game normally.

  To summarize the benefit of rollback netcode, here with delay-based netcode, the time window for inputs to be sent for our game is ideally five frames as given by our five-frame input delay.

  But with rollback netcode, we can have a larger time window before we delay the game given by the maximum number of frames that we can use temporary guessed inputs for and later resimulate for a corrected game state. For our game, we save game states up to seven frames in the past, giving us an extra seven frames for our time window, so our final time window is 12 frames in total.
  
### INPUTCONTROL.GD

  To add rollback netcode, we are only changing our InputControl script. 

  The new prev_frame_arrival_array stores the input arrival checks of the past frames represented in the current state_queue and that were made on the frame previous to the current frame. So if the current frame is frame 100, the prev_frame_arrival_array only stores the input arrival checks for frames 99 to 93 that were made on frame 99. Later, we compare these input arrival checks to the checks for the same past frames- that are made on the current frame- to determine if an actual input has arrived to replace a guess input. So if the current frame is frame 100, we redo the input arrival checks for frames 99 to 93 and compare them to the checks made on frame 99 for the same frames. If there is a difference in the checks as a result of a newly arrived actual input, we resimulate the game state with the new actual input. I’ll go over this more later when we look at the input check comparison and resimulation in our code.

  In our classes, we only build upon our Frame_State class, adding the actual_input boolean to track if the net input used to move the NetPlayer object on a Frame_State instance’s frame is either an actual input from the networked player (true) or if it is a temporary guess input (false).
  
  In our ready() function, we initialize our prev_frame_arrival_array.

  Previously in our physics_process() function, the game would choose to delay when the input for the current frame had not arrived yet. Now, it instead checks if the net input used on the frame given by the oldest Frame_State instance in the state_queue is either still an unfulfilled guess or an actual input. If the net input is still an unfulfilled guess and the actual input has not arrived yet, the game will delay to wait until the actual input arrives. Otherwise, the game will call handle_input.

  In addition, when we send requests for missing needed inputs, we now start the request frame range at the frame given by the oldest Frame_State instance in our state_queue.

  Now, we move to our handle_input() function.
  
  Here, if the net_input for the current frame has not arrived yet, we proceed forward with a temporary guess net_input. For our game, I have chosen to guess using the net_input that was used on the previous frame, but you can choose something else like an empty input, in which no button presses have been registered.

  And, we have an actual_input boolean here to note that the net input used on the current frame is a guess so that when we later create a Frame_State instance for the current frame to put into the state_queue, we will set the instance’s actual_input boolean to false.

  With both the input_arrival_array and the input_viable_request_array, we also change for which old frames we reset booleans to false.

  ### PRESENTATION: RESET BOOLEANS FOR OLD FRAMES
  
  In the previous video detailing delay-based netcode, I gave a scenario in which a Game A and Game B are far apart in terms of frame number, and Game A has not received any inputs from Game B, so Game A cannot proceed on its current frame number. The game that is ahead, Game B, should fulfill requests for inputs from at least up to (input_delay)-many frames in the past, so that the game that is behind, Game A, can proceed forward. So we had the input_viable_request_array reset booleans for old frame numbers at that index.

  Here, we have the same scenario but with our rollback netcode. The games are far apart in terms of frame number, and Game A has not received any inputs from Game B

  However, when Game A does not receive any inputs, it continues forward on temporary guessed inputs for as many frames as it can resimulate later, sending inputs to Game B during this time. When Game A reaches the maximum amount of frames it can resimulate for, it chooses to delay to wait for needed inputs to continue.
When Game B stops receiving inputs from the delaying Game A, Game B continues forward on temporary guessed inputs until it reaches the maximum amount of frames it can resimulate for and delays.

  Note that the games are waiting for inputs not intended for their current frame numbers, but for the frame numbers represented by each of their oldest saved states, or the frame number given by their current frame number minus the maximum amount of frames they can resimulate later. 

  So Game B should still fulfill requests for inputs from at least up to (maxrollback + input_delay + maxrollback)-many frames* in the past so that Game A can proceed. We have the input_viable_request_array now reset booleans for old frame numbers at that index. The value described by maxrollback in this video script is defined by the rollback variable in the code (InputControl.gd script).

  In this scenario from the previous video for delay-based netcode, Game A and Game B are both proceeding on each of their current frames, and Game B gives valid new inputs to Game A, so to accept all inputs that Game B sends, Game A should reset the boolean in its input_arrival_array for old frame numbers at (input_delay + input_delay + 1)-many frames away in the future, with the “+ 1” given by the input_arrival_array possibly not resetting the boolean in time for valid inputs intended for and arriving on the game’s current frame.

  In the same scenario with rollback netcode, Game B can be much further ahead if it had proceeded forward on temporary guess inputs. To receive all valid inputs that Game B sends, Game A should accept inputs intended for at least up to (input_delay + maxrollback + input_delay + 1)-many frames away in the future. We have the input_arrival_array now reset booleans for old frame numbers at that index.
  
 ### INPUTCONTROL.GD
 
  Here, we obtain input arrival checks for past frames, build a current_frame_arrival_array with these checks, and compare it with our prev_frame_arrival_array. Remember that our prev_frame_arrival_array holds the input arrival checks made on the previous frame and only for the past frames represented in our current state_queue. When we build our current_frame_arrival_array, we put in the input arrival checks made on the current frame only for the past frames represented in our current state_queue.

  If we find any differences when comparing the input arrival checks of the previous frame and those of the current frame, we determine that one or more actual net inputs have arrived to replace guess inputs that one or more past frames have used. We store the newly arrived actual net inputs into the past_actual_inputs_array to be used in the game state resimulation process.

  If actual net inputs have arrived to replace temporary guess inputs used in past frames, we start the resimulation process:

- We iterate through all Frame_State class instances in our state queue, starting with the oldest instance first,
to check if an instance contains a temporary guess input that can now be replaced with an actual input- by comparing the arrival checks for the frame that the instance represents- in the prev_frame_arrival_array and the current_frame_arrival_array

- If there is a temporary guess to be replaced in an individual Frame_State instance, we check if the guess is the same as the actual input. If they are the same, we keep the guess, now considering it an actual input. 

- Otherwise, we replace the guess input in the instance with the actual input.

- If we have not begun the resimulation of the game state with the new actual input, we now begin by resetting or rolling back the state of all children of InputControl to the game state given by the Frame_State instance we are currently iterating on using the reset_state_all() function. We also set the start_rollback boolean to true to indicate that we have begun resimulation of the game state.


- If we have begun resimulation of the game state, we use the inputs stored in the Frame State instance we are currently iterating on to resimulate one frame with the input_update_all() function.

 As we continue iterating through the remaining instances in the state_queue from oldest to newest, if more actual inputs have come to replace temporary guess inputs in our Frame_State instances, we replace the guess inputs and continue resimulation using those new actual inputs. If the net input in a Frame_State is still an unfulfilled guess, we still use the guess in resimulation. And of course, if the net input in the Frame_State is already an actual input, we use it in resimulation as well.

  With our new code, when we update the children of InputControl for the current frame using the current_input variable, it can now contain either a temporary guess net_input or an actual net_input.

  When we add a new Frame_State instance to the state queue for the current frame, we include the new actual_input boolean to track the type of net_input used on the current frame.

  And, we set up the prev_frame_arrival_array for the next frame by storing our current_frame_arrival_array.

### DEMO

  So now, let’s run and observe two separate game instances with pre-programmed moves.

  In this good connection, inputs arrive within the input-delay window and the games are smoothly synchronized.
  
  In this ok connection, some inputs arrive late but within the extended time window allowed by rollback netcode, so some resimulation occurs.

  Here, we can see resimulation more clearly when both games only receive packets by request.

  Here in this very bad connection, inputs arrive after the extended window allowed by rollback netcode, so the games delay to wait for the late inputs to arrive.

### WHAT'S NEXT?

  So, what can we add from here? One thing is a connection timeout system. If we don’t receive packets from the networked game for a given period of time, we can assume that the networked game has stopped communication and end our game. Also, when we want to end our game by pressing Escape, we only send a handful of game-end signals to the networked game by UDP. We could improve this by sending a game-end signal by TCP instead.

  We could also have a dynamic input delay determined by the network latency instead of a constant one as we have used so far. We could do something like testing the network latency once connected to another game instance and setting the input delay accordingly.

  The way I’ve implemented the handshake and the game start synchronization between game instances could be done a lot better so that two network-connected games start closer to at the same time. Right now, a game instance only starts the game when receiving a UDP handshake signal, so in the worst case, a Game A only starts when receiving a reply handshake signal from another Game B that has already started from the initial handshake signal that Game A sent. 

  As I have mentioned in the second video, another thing is resolving a possible problem resulting from game instances growing far apart in terms of frame number. Looking at this diagram again, the game that is ahead may always be delaying in a stop-and-go manner because it constantly does not receive the needed net inputs to proceed forward. A solution is to have a one-time, long delay so that the game that is far behind can “catch up” and the frame numbers of both games can become  closer to each other. With the game we’ve made, we could probably have a game purposefully delay for a bit when a request for inputs is received. You could also do something like this for a better synchronized game start between games. 

  When we save game states in our game, we save states every frame, but this is not necessary for rollback netcode. You only really need to save a game state whenever a frame proceeds on a temporary guess input so that you have a base game state for that frame to begin resimulation with later. You may need to keep track of inputs used on every frame though.

  And you could probably optimize a lot of the code I’ve written. Thanks for watching.
