set -eu
# A small Godot 3 project, written as the Godot 3.x editor writes one: the project file
# (config_version=4), two scenes in format=2 with 3.x node types, and scripts in 3.x GDScript
# (onready, export, yield, KinematicBody's move_and_slide with arguments).
p=/s/godot
rm -rf $p && mkdir -p $p/scenes $p/scripts
cat > $p/project.godot <<'P'
; Engine configuration file.
config_version=4

[application]

config/name="Courier"
run/main_scene="res://scenes/Main.tscn"
config/icon="res://icon.png"

[input]

jump={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":32,"physical_scancode":0,"unicode":0,"echo":false,"script":null)
 ]
}

[rendering]

environment/default_environment="res://default_env.tres"
P
cat > $p/default_env.tres <<'P'
[gd_resource type="Environment" load_steps=2 format=2]

[sub_resource type="ProceduralSky" id=1]

[resource]
background_mode = 2
background_sky = SubResource( 1 )
P
cat > $p/scenes/Main.tscn <<'P'
[gd_scene load_steps=3 format=2]

[ext_resource path="res://scripts/Player.gd" type="Script" id=1]
[ext_resource path="res://scenes/Crate.tscn" type="PackedScene" id=2]

[node name="Main" type="Spatial"]

[node name="Player" type="KinematicBody" parent="."]
script = ExtResource( 1 )
speed = 7.0

[node name="Camera" type="Camera" parent="Player"]
transform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 5 )

[node name="Crate" parent="." instance=ExtResource( 2 )]
transform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, 3, 0, 0 )
P
cat > $p/scenes/Crate.tscn <<'P'
[gd_scene load_steps=3 format=2]

[ext_resource path="res://scripts/Crate.gd" type="Script" id=1]

[sub_resource type="BoxShape" id=1]

[node name="Crate" type="RigidBody"]
script = ExtResource( 1 )

[node name="CollisionShape" type="CollisionShape" parent="."]
shape = SubResource( 1 )
P
cat > $p/scripts/Player.gd <<'P'
extends KinematicBody

export var speed := 5.0
onready var camera = $Camera
var velocity = Vector3.ZERO

func _physics_process(delta):
	var dir = Vector3.ZERO
	if Input.is_action_pressed("ui_right"):
		dir.x += 1
	velocity = move_and_slide(dir * speed, Vector3.UP)
	if Input.is_action_just_pressed("jump"):
		yield(get_tree().create_timer(0.2), "timeout")
		emit_signal("jumped")

signal jumped
P
cat > $p/scripts/Crate.gd <<'P'
extends RigidBody

export(int) var weight = 3

func _ready():
	connect("body_entered", self, "_on_hit")

func _on_hit(body):
	print(str(body.name) + " hit " + str(weight))
P
python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000') + b'\x1f\x15\xc4\x89' + bytes.fromhex('0000000d49444154789c63000100000500010d0a2db40000000049454e44ae426082'))" > $p/icon.png
install -m 755 /ap/defines/godot/check.sh /s/godot-check.sh
install -m 755 /ap/defines/godot/check-recovered.sh /s/godot-check-recovered.sh
# The two references the checkers compare against, made once per box from the same seed: the
# project as written (old) and as one uninterrupted conversion leaves it (new).
if [ ! -f /s/aux/godot-ref/new.sha ]; then
    mkdir -p /s/aux/godot-ref && cd /s/godot
    find . -path ./.godot -prune -o -type f -print | sort | xargs sha256sum > /s/aux/godot-ref/old.sha
    rm -rf /s/aux/godot-ref/p && cp -a /s/godot /s/aux/godot-ref/p
    /opt/bin/godot --headless --path /s/aux/godot-ref/p --convert-3to4 > /s/aux/godot-ref/convert.log 2>&1
    cd /s/aux/godot-ref/p && find . -path ./.godot -prune -o -type f -print | sort | xargs sha256sum > /s/aux/godot-ref/new.sha
fi
