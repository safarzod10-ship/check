# DUSHANBE-X — архитектура проекта

Godot 4.4.1, рендер **Mobile** (Vulkan) с автоматическим откатом на OpenGL ES 3 (`rendering_device/fallback_to_opengl3`), физика **Jolt**.

## Поток данных

```
tools/worldgen/layout.py   — авторская раскладка (дороги, реки, районы, достопримечательности, деревни)
tools/worldgen/worldgen.py — генератор: рельеф, вырезка рек/дорог, мосты/тоннели, здания, поля → data/
tools/worldgen/texgen.py   — процедурные бесшовные текстуры → textures/
data/heightmap.f32  float32 2001×2001 (шаг 5 м, 10×10 км)
data/holes.bin      маска дыр в рельефе (порталы тоннеля)
data/splat.pngdat   R грунт, G пашня, B городская плитка, A гравий/песок (2048²)
data/fields.pngdat  код культуры ×30 (1 пшеница, 2 хлопок, 3 пашня, 4 люцерна, 5 залежь, 6 сад, 7 виноградник)
data/veg.pngdat     R лес, G сады, B виноградники, A луговая трава (1024²)
data/world.json     дороги (точки каждые 4 м с высотой), мосты/тоннели/разрывы, перекрёстки, реки, озёра,
                    водопады, достопримечательности, деревни, POI, здания, участки садов/виноградников
```

Godot ничего не импортирует из `data/` (расширения `.f32/.bin/.pngdat/.json`) — файлы читаются через
`FileAccess` и включаются в APK фильтром экспорта `data/*`.

## Координаты

* X — восток, Z — юг, Y — вверх. Север = −Z. Мир: X,Z ∈ [−5000, 5000].
* Сектор стриминга 500×500 м (20×20). `WorldData.sector_of()`, `sector_origin()`, `sector_data()`.
* Поверхность проезжей части = `pts[i].y + WorldData.ROAD_LIFT`. Движение правостороннее, полоса 3.5 м.

## Автозагрузки (autoload/)

| Синглтон | Назначение |
|---|---|
| `WorldData` | загрузка мира, `height_at`, `normal_at`, `nearest_road`, `place_name`, индексы по секторам |
| `GameSettings` | пресеты графики low/medium/high/ultra, сохранение, `changed`, `get_v(key)`; создаёт InputMap |
| `TimeWeather` | часы, погода, `wetness`, `night_factor` → глобальные uniform шейдеров |
| `GameState` | `player`, `camera`, `current_vehicle`, деньги, розыск, `look_delta`, `message()` |

## Контракты между модулями

* **Ввод.** Игровой код читает только `Input` (действия: `move_forward/back/left/right`, `jump`, `sprint`,
  `crouch`, `attack`, `interact`, `enter_vehicle`, `handbrake`, `horn`, `pause`, `map`, `camera_mode`).
  Сенсорный HUD нажимает те же действия (`Input.action_press(a, strength)`), стик задаёт силу осей.
  Обзор камерой: HUD/мышь прибавляют пиксели к `GameState.look_delta`, риг камеры забирает и обнуляет.
* **Автомобиль** (`vehicles/vehicle.gd`, `class_name Vehicle extends VehicleBody3D`, группа `vehicles`):
  `get_speed_kmh()`, `get_seat_transform()`, `get_door_position()`, `set_driver(node_or_null)`,
  `is_player_controlled()`. Вождение игроком: газ `move_forward`, тормоз/задний `move_back`,
  руль `move_left/right`, `handbrake`, `horn`.
* **Игрок** (`characters/player/player.gd`, `class_name Player extends CharacterBody3D`):
  `enter_vehicle(v)`, `exit_vehicle()`, `is_in_vehicle()`, свойство `nearby_vehicle` (для кнопки «Сесть»),
  `health`. Риг камеры следует за `GameState.current_vehicle`, иначе за игроком.
* **NPC** (группа `pedestrians`): `take_hit(from: Vector3, force: float)`. Машины при наезде вызывают его.
  Трафик — группа `traffic`, полиция — `police`.
* **Слои коллизий:** 1 мир, 2 игрок, 3 транспорт, 4 NPC, 5 мелкие пропсы.
* **Стримеры** — узлы, добавляемые `scenes/main.gd` по списку `SYSTEMS` (если файл существует).
  Каждый имеет свойство `is_idle` (для режима скриншотов), строит геометрию в `WorkerThreadPool`,
  узлы создаёт в главном потоке, учитывает `GameSettings` (дальности) и `GameState.view_position()`.
* **Геометрия:** `MeshKit` (util/mesh_kit.gd) + материалы `Mats.get_mat(name)` (util/mats.gd):
  `plain, plain2, glossy, metal, gold, glass, chrome, rubber, lamp, lamp_always, facade, stone, marble,
  concrete, paving, dirt, gravel, rock, tin, bark, wood, foliage, flag, water, waterfall, road...`.
  Цвет — через вершинный цвет. Лицевые грани — по часовой стрелке (контракт Godot); `quad(a,b,c,d)`
  принимает вершины против часовой стрелки, если смотреть спереди.

## Тестирование

Скриншоты без игрока: `xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 -- --shots=res://tools/shots/<file>.json`
(формат: `[{"out": path, "cam": "x,y|gY,z,yaw,pitch", "hour": 10, "weather": 0}]`, yaw 0 = взгляд на север).
