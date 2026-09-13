# 整扇面剖切与地图预览验证

2026-09-13，Windows、Godot 4.6.3、Forward+ / Vulkan、NVIDIA GeForce RTX 3080。本次修改游戏显示层和主菜单预览入口；没有重建地图源几何、导航或碰撞。

## 朝向扇面：96 项通过

`tests/fan_view_test.gd` 在真实渲染和 Jolt 物理下检查，结果为 **96 通过、0 失败**，记录在 `tests/fan_view_results.json`。

- A/B 两点分别朝向四个方向，验证 18 米远处及扇面两侧的高处遮挡能够移除。
- 检查扇面外结构保留、转身恢复和低掩体保留。
- 检查世界位置在玩家后方、但从镜头方向覆盖前方扇面的建筑能够剖开。
- 检查 Architecture、Canopy、Foliage 和 Props 的剖切材质，以及观战时观察者位置和朝向同步。
- 使用源墙体确认人物仍不能穿墙、墙后敌人仍隐藏。视觉片元移除不改变这些物理和玩法判定。

实际地图截图位于 `artifacts/fan_view/`。当前剖切直接移除高处片元，部分原空心网格会露出截口，没有额外生成封盖。

## 地图预览：33 项通过

`tests/map_preview_test.gd` 在 1440×810 窗口中实例化真实主场景，通过 `Viewport.push_input()` 分发鼠标和键盘，结果为 **33 通过、0 失败**。记录在 `tests/map_preview_results.json`。

- 点击主菜单“地图预览”进入，完整建筑显示，视野雾与游戏剖切关闭。
- 左键环绕旋转、右键及中键平移、滚轮缩放与缩放上下限。
- 鼠标在工具栏上松开后不会继续拖动镜头。
- A、B、中路、CT 出生点和 T 出生点五个真实按钮均可定位，Home 恢复整图。
- 正交和透视切换，Esc 与返回按钮均能退出；即使在透视下退出，游戏原正交镜头也会恢复。
- 退出后正常开始单人游戏，战斗相机、视野雾和朝向剖切恢复。
- 将闪光透明度设为 0.8 后进入预览，验证其清零；检查整图镜头的太阳阴影距离和退出后原距离恢复。

整图取景使用真实渲染网格的世界包围盒，保留上方工具栏和下方定位按钮空间。点位定位使用 75° 俯角，便于直接查看院落和箱组；仍可手动旋转。预览暂停战斗更新并隐藏角色、投掷物、掉落和临时效果。

实际查看 `artifacts/map_preview_overview.png` 和 `artifacts/map_preview_a_site.png`，确认整图边缘、主要点位及按钮可见。预览模型保持全部建筑高度，不使用游戏中的局部显示剖切。

## 原有流程复核

本次同时通过 `tests/gameplay_test.gd` 的 **55 项玩法检查**和 `tests/input_flow.gd -- --quick` 的 **32 项真实界面输入检查**，后者记录在 `artifacts/runtime_validation_quick.json`。此次未重测全图性能；已有帧率记录的时间与范围见 `runtime-validation.md`。

复现命令：

```powershell
& 'C:/Program Files/Godot/Godot_console.exe' --path . --audio-driver Dummy --script res://tests/fan_view_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --path . --audio-driver Dummy --script res://tests/map_preview_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --audio-driver Dummy --script res://tests/gameplay_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --path . --audio-driver Dummy --script res://tests/input_flow.gd -- --quick
```
