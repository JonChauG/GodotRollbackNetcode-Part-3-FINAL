#By Jon Chau
extends Node

var inputControl
var statusLabel
enum Game {END, WAITING, PLAYING}

func _ready():
	inputControl = get_node("InputControl")
	statusLabel = get_node("StatusLabel")

func _physics_process(_delta):
	match inputControl.game:
		Game.WAITING:
			statusLabel.text = "WAITING FOR CONNECTION TO PEER"
		Game.PLAYING:
			statusLabel.text = "CONNECTED TO PEER.\n" + str(inputControl.status)
		Game.END:
			statusLabel.text = "THE GAME HAS ENDED. DISCONNECTED FROM PEER"
