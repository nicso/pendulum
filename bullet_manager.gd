extends Node


const MAX_BULLETS = 200
const BULLET_SCENE = preload("res://Bullet.tscn")

var bullet_pool = []
var active_bullets = []

func _ready():
	# Pré-charge le pool de projectiles
	for i in range(MAX_BULLETS):
		var bullet = BULLET_SCENE.instantiate()
		bullet.visible = false
		bullet.set_process(false)
		bullet_pool.append(bullet)
		add_child(bullet)

func spawn_bullet(pos: Vector2, direction: Vector2, speed: float = 800, damage: int = 10):
	var bullet = get_bullet_from_pool()
	if bullet:
		bullet.initialize(pos, direction, speed, damage)
		active_bullets.append(bullet)

func get_bullet_from_pool():
	if bullet_pool.size() > 0:
		return bullet_pool.pop_back()
	elif active_bullets.size() > 0:
		# Si plus de bullets dans le pool, recycle la plus ancienne
		var oldest_bullet = active_bullets[0]
		return_bullet(oldest_bullet)
		return oldest_bullet
	return null

func return_bullet(bullet):
	if bullet in active_bullets:
		active_bullets.erase(bullet)
	if not bullet in bullet_pool:
		bullet.deactivate()
		bullet_pool.append(bullet)
