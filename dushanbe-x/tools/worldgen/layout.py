"""
DUSHANBE-X — authored world layout.

World coordinates (metres):  X = east (+), Z = south (+), Y = up.
The playable square is X in [-5000, 5000], Z in [-5000, 5000]  (100 km^2).
North (the Varzob gorge and the Hissar range) is towards -Z.

Relative positions follow real Dushanbe (Rudaki Avenue runs N-S through the
centre, the Dushanbinka/Varzob river runs N-S west of the centre, Hisor lies to
the west, the Varzob gorge opens to the north), compressed to fit the game map.
This is an original game map inspired by the city, not a 1:1 copy.
"""

# ----------------------------------------------------------------------------
# Regions (for HUD location names, ground types and generation rules)
# ----------------------------------------------------------------------------
CITY_POLY = [(-1450, -150), (2650, -150), (2700, 4150), (-1450, 4150)]

DISTRICTS = [
    # name, polygon
    ("Исмоили Сомони", [(-200, -150), (2650, -150), (2650, 1400), (-200, 1400)]),
    ("Фирдавси", [(-1450, -150), (-200, -150), (-200, 1800), (-1450, 1800)]),
    ("Сино", [(-1450, 1800), (-200, 1800), (-200, 4150), (-1450, 4150)]),
    ("Шохмансур", [(1000, 1400), (2700, 1400), (2700, 4150), (1000, 4150)]),
    ("Центр (Исмоили Сомони)", [(-200, 1400), (1000, 1400), (1000, 4150), (-200, 4150)]),
]

REGIONS = [
    ("Варзоб", [(-1300, -5000), (2300, -5000), (2300, -150), (-1300, -150)]),
    ("Горы Гиссарского хребта", [(-5000, -5000), (-1300, -5000), (-1300, 300), (-5000, 300)]),
    ("Горы Рамит", [(2300, -5000), (5000, -5000), (5000, 1200), (2300, 1200)]),
    ("Гиссар", [(-5000, 300), (-1450, 300), (-1450, 5000), (-5000, 5000)]),
    ("Сельская местность", [(2700, 1200), (5000, 1200), (5000, 5000), (-1450, 5000), (-1450, 4150), (2700, 4150)]),
]

# ----------------------------------------------------------------------------
# Valley corridors: (polyline [(x,z,floor_height)], half_width)
# Mountains are suppressed inside corridors and the floor follows the profile.
# ----------------------------------------------------------------------------
RIVER_MAIN = [  # Dushanbinka / Varzob river, north -> south
    (330, -5000), (210, -4550), (380, -4050), (300, -3650), (700, -3250),
    (640, -2900), (360, -2600), (250, -2100), (420, -1600), (300, -1100),
    (150, -600), (-60, -100), (-260, 500), (-300, 1200), (-280, 2000),
    (-350, 2800), (-300, 3500), (-240, 4200), (-150, 5000),
]

CORRIDORS = [
    # Varzob gorge floor
    dict(name="varzob", pts=[(330, -5000, 330), (210, -4550, 295), (380, -4050, 255), (300, -3650, 225),
                             (700, -3250, 195), (640, -2900, 170), (360, -2600, 150), (250, -2100, 120),
                             (420, -1600, 95), (300, -1100, 70), (150, -600, 45), (-60, -100, 25)],
         half=230, edge=170),
    # West side valley to Kuli Sabz lake and the waterfall
    dict(name="sabz", pts=[(260, -1950, 125), (-500, -2150, 210), (-1200, -2350, 300),
                           (-1850, -2550, 400), (-2450, -2750, 470)], half=170, edge=200),
    # Gusgarf side creek (east of gorge) – short hanging valley
    dict(name="gusgarf", pts=[(380, -2350, 140), (700, -2400, 230), (1000, -2450, 330)], half=70, edge=120),
    # Hisor north valley to the mountain village of Sangtuda
    dict(name="sangtuda", pts=[(-3700, 500, 6), (-3650, -300, 120), (-3550, -1000, 260), (-3450, -1500, 340)],
         half=200, edge=220),
]

# Flat-ish basins: (x, z, radius, floor height)
BASINS = [
    (-2600, -2820, 330, 465),     # Kuli Sabz lake basin
    (1900, -3050, 300, 520),      # Safedi Varzob plateau (viewpoint / ski base)
    (-3450, -1550, 260, 335),     # Sangtuda village plateau
]

# Extra hills: (x, z, radius, height)
HILLS = [
    (1500, 650, 260, 55),         # Victory Park hill
    (-4100, 1400, 140, 26),       # Hisor fortress hill
    (430, -3250, 190, 150),       # rocky spur in the gorge (road tunnels through it)
    (3400, 3500, 600, 40), (4300, 4400, 700, 70), (-4500, 4500, 600, 60), (1200, 4800, 500, 35),
]

# ----------------------------------------------------------------------------
# Rivers, creeks, canals: dict(name, pts[(x,z)], width, depth, kind)
# ----------------------------------------------------------------------------
RIVERS = [
    dict(name="Душанбинка (Варзоб)", pts=RIVER_MAIN, width=24, depth=4.5, kind="river"),
    dict(name="Ручей Кули Сабз", pts=[(-2450, -2750), (-1850, -2550), (-1200, -2350), (-500, -2150), (230, -1980)],
         width=8, depth=2.0, kind="creek"),
    dict(name="Водопад Кули Сабз", pts=[(-2980, -3300), (-2850, -3120), (-2760, -3010), (-2700, -2940)],
         width=6, depth=1.5, kind="creek"),
    dict(name="Гусгарф", pts=[(1150, -2470), (1000, -2450), (760, -2410), (560, -2380), (340, -2350)],
         width=6, depth=1.5, kind="creek"),
    dict(name="Ручей Сангтуда", pts=[(-3450, -1650), (-3550, -1000), (-3650, -300), (-3700, 500), (-3800, 1300),
                                       (-3900, 2600), (-3950, 5000)], width=7, depth=1.8, kind="creek"),
    # Irrigation canals (aryks / kanal)
    dict(name="Гиссарский канал", pts=[(-340, 2550), (-1450, 2500), (-2200, 2550), (-3000, 2450), (-3900, 2500), (-5000, 2450)],
         width=5, depth=1.2, kind="canal"),
    dict(name="Канал Чорбог", pts=[(2700, 3600), (3300, 3550), (3900, 3700), (4700, 3650)],
         width=4, depth=1.0, kind="canal"),
]

# Lakes: (name, x, z, radius, depth)
LAKES = [
    ("Кули Сабз", -2600, -2820, 230, 7.0),
    ("Комсомольское озеро", -700, 3050, 150, 3.5),
    ("Пруд Кохи Навруз", 1300, 1060, 40, 1.2),
    ("Пруд Сангтуда", -3400, -1520, 60, 2.5),
]

# ----------------------------------------------------------------------------
# Roads. type -> (half width of carriageway, lanes, sidewalk, lights, guardrail, surface)
# ----------------------------------------------------------------------------
ROAD_TYPES = {
    "avenue":   dict(half=12.0, lanes=6, sidewalk=5.0, lights=True, guard=False, surface="asphalt", tier=0, grade=0.07, smooth=40),
    "boulevard": dict(half=8.0, lanes=4, sidewalk=4.0, lights=True, guard=False, surface="asphalt", tier=0, grade=0.07, smooth=40),
    "highway":  dict(half=7.0, lanes=2, sidewalk=0.0, lights=False, guard=True, surface="asphalt", tier=0, grade=0.08, smooth=60),
    "street":   dict(half=4.5, lanes=2, sidewalk=2.5, lights=True, guard=False, surface="asphalt", tier=1, grade=0.10, smooth=25),
    "mountain": dict(half=4.0, lanes=2, sidewalk=0.0, lights=False, guard=True, surface="asphalt", tier=1, grade=0.13, smooth=40),
    "rural":    dict(half=3.2, lanes=2, sidewalk=0.0, lights=False, guard=False, surface="asphalt_old", tier=2, grade=0.12, smooth=30),
    "dirt":     dict(half=2.6, lanes=1, sidewalk=0.0, lights=False, guard=False, surface="dirt", tier=2, grade=0.18, smooth=25),
}

ROADS = [
    # ---- City avenues (main) ----
    dict(name="проспект Рудаки", type="avenue",
         pts=[(560, -120), (530, 400), (510, 1000), (500, 1500), (500, 2000), (500, 2600), (505, 3200), (500, 3900)]),
    dict(name="проспект Исмоили Сомони", type="avenue",
         pts=[(500, 1700), (200, 1690), (-100, 1685), (-450, 1670), (-800, 1660), (-1450, 1650)]),
    dict(name="проспект Хафиза Шерози", type="boulevard",
         pts=[(500, 3300), (200, 3420), (-150, 3560), (-500, 3700), (-900, 3850), (-1450, 4000)]),
    dict(name="улица Мирзо Турсунзаде", type="boulevard",
         pts=[(-180, 2420), (300, 2420), (900, 2440), (1500, 2450), (2650, 2470)]),
    dict(name="улица Айни", type="boulevard",
         pts=[(505, 2850), (1000, 2840), (1700, 2820), (2400, 2810), (2700, 2830)]),
    dict(name="улица Фирдавси", type="boulevard",
         pts=[(-900, -120), (-880, 500), (-880, 1100), (-880, 1650)]),
    dict(name="проспект Абу Али ибн Сино", type="boulevard",
         pts=[(-880, 1650), (-900, 2300), (-920, 3000), (-930, 3700), (-950, 4130)]),
    dict(name="улица Алишера Навои", type="boulevard",
         pts=[(-1450, 1100), (-880, 1100), (-500, 1080), (-150, 1060), (500, 1050)]),
    dict(name="проспект Исмоили Сомони (север)", type="boulevard",
         pts=[(510, 1000), (1000, 980), (1600, 960), (2650, 950)]),
    dict(name="улица Н. Карабоева", type="boulevard",
         pts=[(1700, -120), (1720, 600), (1700, 1400), (1700, 2200), (1720, 3200), (1700, 4130)]),
    dict(name="Южная кольцевая", type="boulevard",
         pts=[(-1450, 4120), (-500, 4110), (500, 3950), (1200, 4100), (2700, 4120)]),
    dict(name="улица Бохтар", type="boulevard",
         pts=[(500, 400), (-200, 380), (-700, 300), (-1450, 260)]),

    # ---- Intercity highways ----
    dict(name="Трасса Душанбе — Гиссар", type="highway",
         pts=[(-1450, 1650), (-2000, 1680), (-2600, 1720), (-3200, 1690), (-3700, 1640), (-4300, 1700), (-5000, 1760)]),
    dict(name="Трасса Душанбе — Варзоб", type="highway", tunnel=True, tunnel_zones=[(425, -3245, 260)],
         pts=[(560, -120), (480, -300), (310, -620), (440, -1050), (560, -1500), (420, -1950), (480, -2300),
              (520, -2600), (520, -2850), (430, -3100), (390, -3420), (440, -3700), (500, -4050),
              (390, -4500), (420, -5000)]),
    dict(name="Трасса на Курган-Тюбе", type="highway",
         pts=[(1200, 4100), (1150, 4500), (1050, 5000)]),
    dict(name="Восточная трасса", type="highway",
         pts=[(2700, 2830), (3200, 2900), (3800, 3050), (4400, 3150), (5000, 3200)]),

    # ---- Mountain roads ----
    # Serpentine up to the Safedi Varzob plateau (switchbacks on the east slope)
    dict(name="Серпантин Сафеди Варзоб", type="mountain", serpentine=True,
         pts=[(520, -2600), (720, -2700), (900, -2620), (980, -2760), (800, -2860), (760, -2990),
              (1000, -2950), (1180, -2870), (1260, -3010), (1080, -3120), (1060, -3240), (1300, -3200),
              (1500, -3130), (1600, -3050), (1800, -3040), (1900, -3050)]),
    dict(name="Дорога на Кули Сабз", type="mountain",
         pts=[(420, -1950), (100, -2075), (-450, -2200), (-1150, -2400), (-1800, -2600), (-2150, -2780),
              (-2330, -2930)]),
    dict(name="Дорога на Сангтуду", type="rural",
         pts=[(-3700, 1640), (-3720, 1000), (-3700, 500), (-3600, -300), (-3500, -1000), (-3420, -1450)]),

    # ---- Hisor rural roads ----
    dict(name="улица Гиссар-Шахринав", type="rural",
         pts=[(-4300, 1700), (-4350, 2300), (-4300, 3000), (-4250, 3800), (-4300, 5000)]),
    dict(name="Сельская дорога Гиссар", type="rural",
         pts=[(-2600, 1720), (-2700, 2400), (-2650, 3200), (-2700, 4000), (-2600, 4800)]),
    dict(name="Полевая дорога", type="dirt",
         pts=[(-4300, 3000), (-3600, 3050), (-2650, 3200), (-1900, 3150), (-1450, 3300)]),
    dict(name="Полевая дорога 2", type="dirt",
         pts=[(-4250, 3800), (-3500, 3900), (-2700, 4000)]),
    dict(name="Дорога к крепости", type="rural",
         pts=[(-4300, 1700), (-4200, 1520), (-4100, 1450)]),

    # ---- Rural east ----
    dict(name="Дорога Чорбог", type="rural",
         pts=[(3800, 3050), (3850, 3500), (3800, 4000), (3900, 4600), (3950, 5000)]),
    dict(name="Дорога Сурх", type="rural",
         pts=[(3200, 2900), (3150, 2300), (3300, 1700), (3500, 1350)]),
    dict(name="Садовая дорога", type="dirt",
         pts=[(3850, 3500), (4300, 3550), (4700, 3700)]),
    dict(name="Садовая дорога 2", type="dirt",
         pts=[(2700, 4120), (3200, 4150), (3800, 4000)]),
    # Varzob village lanes
    dict(name="Варзоб, улица Чинор", type="rural",
         pts=[(560, -1500), (720, -1480), (850, -1550)]),
    dict(name="Хушёри, дорога", type="dirt",
         pts=[(440, -3700), (180, -3720), (90, -3800)]),
    dict(name="Турбаза, дорога", type="dirt",
         pts=[(500, -4050), (600, -4130), (650, -4200)]),
]

# ----------------------------------------------------------------------------
# Landmarks (built in Godot by world/landmarks/*.gd). pad = flatten half-size
# ----------------------------------------------------------------------------
LANDMARKS = [
    dict(id="somoni_monument", name="Памятник Исмоили Сомони", x=380, z=1800, yaw=90, pad=(85, 95)),
    dict(id="dusti_square", name="Площадь Дусти", x=380, z=1800, yaw=90, pad=(85, 95)),
    dict(id="rudaki_park", name="Парк Рудаки", x=320, z=2120, yaw=90, pad=(145, 170)),
    dict(id="palace_of_nations", name="Дворец Наций", x=30, z=2120, yaw=90, pad=(110, 120)),
    dict(id="flag_park", name="Парк Национального флага", x=30, z=1850, yaw=90, pad=(110, 110)),
    dict(id="national_museum", name="Национальный музей Таджикистана", x=80, z=1520, yaw=0, pad=(130, 70)),
    dict(id="national_library", name="Национальная библиотека", x=260, z=2330, yaw=180, pad=(110, 50)),
    dict(id="opera_ayni", name="Театр оперы и балета им. Айни", x=640, z=2620, yaw=-90, pad=(70, 90)),
    dict(id="kohi_navruz", name="Кохи Навруз", x=1300, z=1220, yaw=180, pad=(150, 120)),
    dict(id="mehrgon", name="Рынок Мехргон", x=1400, z=3050, yaw=0, pad=(120, 90)),
    dict(id="ismaili_centre", name="Исмаилитский центр", x=-620, z=1530, yaw=0, pad=(90, 80)),
    dict(id="vahdat_palace", name="Дворец Вахдат", x=680, z=820, yaw=-90, pad=(90, 110)),
    dict(id="tnu", name="Таджикский национальный университет", x=680, z=3050, yaw=-90, pad=(80, 120)),
    dict(id="medical_university", name="Медицинский университет им. Абуали ибн Сино", x=-1120, z=2600, yaw=90, pad=(70, 100)),
    dict(id="victory_park", name="Парк Победы", x=1500, z=650, yaw=180, pad=(110, 110)),
    dict(id="railway_station", name="Железнодорожный вокзал", x=500, z=4020, yaw=180, pad=(120, 50)),
    dict(id="hisor_fortress", name="Гиссарская крепость", x=-4100, z=1400, yaw=180, pad=(110, 90)),
    dict(id="hisor_madrasa", name="Медресе Кухна", x=-4120, z=1580, yaw=180, pad=(45, 40)),
    dict(id="safedi_viewpoint", name="Смотровая Сафеди Варзоб", x=1950, z=-3080, yaw=0, pad=(70, 70)),
]

# ----------------------------------------------------------------------------
# Villages: (name, x, z, radius, style, houses)
# ----------------------------------------------------------------------------
VILLAGES = [
    ("Варзоб", 640, -1500, 200, "mountain", 45),
    ("Зидды", 520, -4300, 170, "mountain", 22),
    ("Хушёри", 160, -3780, 140, "mountain", 18),
    ("Сангтуда", -3450, -1550, 210, "mountain", 26),
    ("Гиссар", -4050, 2100, 520, "valley", 110),
    ("Шахринав", -4300, 3700, 380, "valley", 70),
    ("Кишлак Навобод", -2700, 3300, 300, "valley", 45),
    ("Кишлак Сурх", 3300, 1750, 300, "valley", 50),
    ("Чорбог", 3850, 3600, 380, "valley", 70),
    ("Кишлак Офтобруй", 4000, 4700, 260, "valley", 35),
]

# Points of interest along roads: type, x, z, yaw (deg)
POIS = [
    ("gas_station", -2300, 1760, 0), ("gas_station", 3500, 2900, 0), ("gas_station", 470, -900, 90),
    ("gas_station", 1900, 2480, 0), ("gas_station", -1200, 4060, 0), ("gas_station", 1150, 4450, 90),
    ("cafe", 600, -2250, 90), ("cafe", 300, -4450, 90), ("cafe", -2330, -2950, 0), ("cafe", 1850, -2970, 0),
    ("chaikhana", 480, -1750, 90), ("chaikhana", -4150, 1900, 0), ("chaikhana", 3750, 3200, 0),
    ("chaikhana", 250, -3600, 90),
    ("viewpoint", 1980, -3150, 0), ("viewpoint", 1150, -3070, 0), ("viewpoint", -2200, -2950, 0),
    ("tourist_base", 620, -4150, 0), ("tourist_base", -2450, -3050, 0),
    ("restaurant", 200, -1300, 90), ("restaurant", 600, -3450, 90),
    ("market", -4000, 2350, 0), ("market", 3350, 1950, 0),
    ("parking", 820, 1700, 0), ("parking", 1500, 3200, 0), ("parking", -400, 1900, 0),
    ("shop", 760, -1450, 0), ("shop", -3480, -1400, 0), ("shop", 3900, 3450, 0), ("shop", -4280, 3550, 0),
]

PLAYER_SPAWN = (470, 1760, 90)   # Dusti square, facing east (towards Rudaki)
