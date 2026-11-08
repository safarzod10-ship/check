# characters/

| Файл | Назначение |
|---|---|
| `humanoid/humanoid_builder.gd` | `HumanoidBuilder`: скелет (имена костей SkeletonProfileHumanoid, рост ≈1.75 м, лицом к −Z), скиннинговый меш (4 веса/вершину, плавные веса в суставах), `Skin`, параметры внешности (`random_appearance`). Кэш мешей по внешности. |
| `humanoid/humanoid_anims.gd` | `HumanoidAnims.library()`: процедурные анимации — idle, walk, run, sprint, crouch_idle, crouch_walk, jump_up, fall, land, guard, punch_r, punch_l, kick, hit_react, knocked_down, get_up, enter_car, exit_car, sit_drive, interact, pickup, wave, talk. |
| `humanoid/humanoid_animator.gd` | `HumanoidAnimator`: локомоция по скорости с кросс-фейдом и сохранением фазы шага, одноразовые действия, состояния `normal/down/drive`. |
| `player/player.gd` | `Player` (CharacterBody3D): ходьба/бег/спринт, прыжок, присед, подъём на бордюр ≤0.42 м, ближний бой (комбо удар-удар-пинок), здоровье, взаимодействие, посадка/высадка из машины. |
| `player/camera_rig.gd` | `CameraRig`: орбитальная камера от третьего лица (SpringArm, слой 1), следование за машиной, FOV от скорости, 3 дистанции (`camera_mode`). |
| `npc/pedestrian_manager.gd` | Система «Pedestrians»: пул прохожих вокруг игрока (до 25 × `pedestrian_density`). |
| `npc/pedestrian.gd` | `Pedestrian`: ходит по тротуарам/обочинам сельских улиц, стоит, беседует, переходит дорогу на перекрёстках, падает от ударов, встаёт и убегает. |
| `test/character_test.tscn` | Визуальный и функциональный тест (скриншоты → `docs/screenshots/character_*.png`). |

Запуск теста:
```
xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 res://characters/test/character_test.tscn -- --out=res://docs/screenshots
```

## Замена модели на .glb
См. комментарий в начале `humanoid_builder.gd`: импорт с Bone Map = SkeletonProfileHumanoid, узел скелета
`Skeleton3D` под корнем модели, анимации с теми же именами — `HumanoidAnimator` опирается только на имена.

## API для HUD
* `GameState.player.nearby_vehicle` — показать кнопку «Сесть»; кнопка жмёт действие `enter_vehicle`.
* `GameState.player.nearby_interactable` — кнопка «Действие» (`interact`). Узлы в группе `interactable` с методом `interact(player)`.
* `GameState.player.health` + сигнал `health_changed(value)`, сигнал `died`.
* `GameState.player.crouching`, `is_in_vehicle()`.
* Обзор камерой — прибавлять пиксели к `GameState.look_delta`.
