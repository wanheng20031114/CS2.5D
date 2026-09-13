# 角色、武器与数值来源

角色和武器为本项目原创的简化低多边形雕塑。建模研究只读取了 `middle-ages-battle/tools/build_units.py`：使用削角轮廓、椭圆截面衣物、平面法线、顶点绘色，以及按刚性关节合并的小零件。CT 有头盔、耳机、护目镜、防弹背心、弹匣袋、无线电、背包、护膝和作战靴；T 使用浅色衬衫、赭红围巾、头套、棕色裤装及手套。模型面朝 -Z，脚底 Y=0；CT 含头盔约 1.90 米，T 约 1.81 米。

模型在离线阶段生成，交付为可编辑的原生 `.tscn` 和压缩 `.res` 网格。CT 4,576 三角面、T 3,892 三角面，每人 11 个材质表面。模型运行时只加载和驱动关节，行走、呼吸、瞄准、后坐、换弹与倒地不在每帧重建网格。枪械有独立模型、枪口标记和不同轮廓；AK 使用木质枪托与弯弹匣，M4 有伸缩枪托，USP-S / M4A1-S 带消音器，AWP / Scout 带长枪管与瞄准镜，SMG、霰弹枪、机枪、手枪和投掷物均有简化模型。它们是俯视玩法使用的卡通近似，不是原版枪械扫描件。

## 当前游戏数据

2026-09-13 核对了 [Valve CS2 weapons.vdata 游戏数据镜像](https://raw.githubusercontent.com/SteamTracking/GameTracking-CS2/master/game/csgo/pak01_dir/scripts/weapons.vdata)，使用其中的 `m_nPrice`、基础伤害、弹匣容量、备用弹药、射速、弹丸数量。保留的原始文件和 SHA-256 位于 `assets/weapons/source`，可复查数值出处。镜像由 SteamTracking 维护；它不是我们自行估算的商店价格。该机器另有 CS2 build 25218825 安装，但本项目没有从本地 VPK 读取武器数值，因此不声称两份数据已逐字比较。

关键价格：AK-47 $2700；M4A4 / M4A1-S $2900；FAMAS $1950；MP7 / MP5-SD $1400；AWP $4750；防弹衣 $650；防弹衣＋头盔 $1000；拆弹器 $400。完整价格由 `assets/weapons/catalog.json` 提供。头盔套装升级折扣和购买条件由商店逻辑处理。

当前源数据对很多武器使用“备用弹匣数”。本项目接口将其换算成备用子弹数，例：AK 3×30=90、M4A4 4×30=120、AWP 2×5=10。此实现不模拟整弹匣丢弃；换弹如何扣除备用弹药由单人战斗系统处理。

## 本项目的手感设计

静止散布、移动散布、每发后坐扩散、换弹时长、物品重量为俯视射击专门设计，不应被解释为 CS2 完整射击算法。AK 初始静止半角 0.0018 弧度（约 0.103°）；移动半角 0.12 弧度，每发增加 0.009 弧度扩散。右键精确瞄准、停步恢复、移动减速、伤害结算和穿墙规则由主战斗脚本组合这些参数。其他武器按射程和定位采用不同基础散布；霰弹枪输出多弹丸。枪口发光持续 45 毫秒，枪身后坐迅速回弹，行走有独立腿部与膝关节摆动。

## API

`AgentVisual.new()` 后调用 `build(team, weapon_id)`，team 为 `CT` 或 `T`。每帧调用 `animate(delta, speed_metres_per_second, aiming, reloading)`；开火调用 `fire()`，倒地调用 `die()`，换枪调用 `set_weapon(id)`。`get_muzzle_position()` 返回全局坐标。

`WeaponCatalog.data(id)` 返回数据副本；`all()` 返回所有条目；`for_team(team, category)` 返回指定阵营与分类。ID 默认遵循 Valve，如 `m4a1` 表示 M4A4，`m4a1_silencer` 表示 M4A1-S。`m4a4`、`m4a1s`、`usp`、`scout`、`he`、`smoke`、`flash` 等别名由 `canonical()` 统一解析。

离线重建：先运行 `python tools/build_actors.py`，再运行 Godot `--headless --path . --script res://tools/build_actors.gd`。渲染检查使用相同命令去掉 `--headless`，末尾加 `-- --preview`，截图输出至 `assets/characters/gallery.png`。颜色以 sRGB 顶点数据保存，材质启用 `vertex_color_is_srgb`，适配 [Godot 不同渲染器的顶点颜色处理](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html#class-basematerial3d-property-vertex-color-is-srgb)。

45 个物品的 512×256 透明 PNG 图标由实际模型离线渲染，位于 `assets/weapons/icons/<id>.png`；用 Godot `--path . --script res://tools/build_actors.gd -- --icons` 可重建。`--headless --path . --script res://tools/build_actors.gd -- --validate` 核验全部模型加载、枪口坐标、AK 四种瞄准/移动组合，以及备用弹药不足与切枪中止换弹。

已在 Godot 4.6.3 / OpenGL Compatibility 下通过：47 个原生场景烘焙、45 个持有物模型切换、3D 渲染与透明图标、换弹结算和中止测试。综合逻辑的 AK 散布半角：静止 0.0018、移动 0.1218、右键移动 0.021077、右键静止 0.000756 弧度。这些是当前实现测试值，手感是否达到玩家满意仍需要实玩反馈。
