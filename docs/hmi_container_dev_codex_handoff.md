# hmi_container_dev Codex Handoff Runbook

Date: 2026-03-31
Last updated: 2026-04-02 16:55 HKT

## 1. 文档目的

这份文档不是简单的过程记录，而是一份给 Codex 直接接手用的操作手册。

目标：

1. 让 Codex 在最少追问的前提下，快速理解本地开发机、参考机 `APS998`、`APS002`、目标机 `APS009` 的关系。
2. 让 Codex 以后能把已经在 `APS998` 生效的新版 HMI host 启动链，迁移到 `APS009` 这类机器。
3. 让 Codex 明确区分两条模板路径：
   - `ehub` 路径：以 `APS998` 为模板，代表“新版 host / 新版 HMI 启动链”
   - `HK` 路径：以 `APS002` 为模板，代表“HK 区域设备参数”，但 host 侧仍是旧版
4. 记录当前 `APS998` 的真实生效配置，并标明哪些字段是设备相关、迁移到 `APS009` 时不能照抄。

说明：

- 这份文档尽量写“当前真实状态”，不是旧方案。
- `APS998` 是 `ehub` 路径的新版 host 模板。
- `APS002` 是 `HK` 路径的旧版 host 模板。
- `APS009` 是后续要部署的目标机；它应当采用“host 链路跟 `APS998`，HK 设备参数跟 `APS002`”的组合。
- `APS002` 在 2026-04-02 被当作 `APS009` 的只读对比机使用，因为当时本地到 `APS009:8923` 连接被拒绝。
- 文档不写 SSH 密码和设备 token 明文；只写获取位置和更新方式。
- 如果 Codex 能访问当前工作区和终端，它应该优先以这份文档为准，再对现场做二次确认。

## 2. 机器、角色与仓库关系

### 2.1 本地开发机

- user: `libpet`
- home: `/home/libpet`

本地仓库：

- `autoware.APS`
  - `/home/libpet/autoware.APS`
- `autoware_launch_APS`
  - `/home/libpet/autoware.APS/src/launcher/autoware_launch_APS`
  - 注意：这是嵌在 `autoware.APS` 工作区里的独立 git repo，不跟随顶层 `autoware.APS` 一起提交
- `APS_management_system_ui`
  - `/home/libpet/APS_management_system_ui`
- `nestjs_test`
  - `/home/libpet/nestjs_test`

### 2.2 参考机 `APS998`

- ssh alias: `APS998`
- HostName: `43.154.113.98`
- User: `libpet-aps`
- Port: `8983`
- home: `/home/libpet-aps`
- system: `Ubuntu 22.04`
- 角色：`ehub` 路径的新版 host 模板；当前已完成 HMI container 新链路与 CPU tuning

参考机仓库：

- `autoware.APS`
  - `/home/libpet-aps/autoware.APS`
- `autoware_launch_APS`
  - `/home/libpet-aps/autoware.APS/src/launcher/autoware_launch_APS`
  - 这是车端 HMI container、`autoware.launch.xml`、loading 资源所在的独立 git repo
- `APS_management_system_ui`
  - `/home/libpet-aps/APS_management_system_ui`
- `nestjs_test`
  - `/home/libpet-aps/nestjs_test`
- 运行时 modbus 脚本
  - `/home/libpet-aps/stm32/modbus_read.py`

### 2.3 对比机 `APS002`

- ssh alias: `APS002`
- HostName: `43.154.113.98`
- User: `libpet-aps`
- Port: `8223`
- home: `/home/libpet-aps`
- system: `Ubuntu 22.04`
- 角色：`HK` 路径的旧版 host 模板；与 `APS009` 同类，只做只读对比

说明：

- 2026-04-02 本地开发机到 `APS009:8923` 连接被拒绝，因此本次文档对比以 `APS002` 代替 `APS009`
- 不要在 `APS002` 上落任何迁移改动；它只用来读配置和做差异参考

### 2.4 目标机 `APS009`

- ssh alias: `APS009`
- HostName: `43.154.113.98`
- User: `libpet-aps`
- Port: `8923`
- home: `/home/libpet-aps`
- system: `Ubuntu 22.04`
- 角色：后续要把 `APS998` 的 HMI container 新链路迁移过去的目标机

说明：

- 2026-04-02 16:30 CST 从本地开发机测试，`APS009:8923` 返回 `Connection refused`
- 因此本文件里凡是写“APS009 预期值”的地方，除非另有现场确认，否则都以“基于 APS002 推定”标注

### 2.5 可选的 token 查询服务器

只有在目标机缺 `APS_DEVICE_TOKEN` 时，才需要看这个服务器：

- ssh alias: `server`
- 实际机器：`ubuntu@43.154.113.98`
- 当前有 private key，可直接 `ssh server`
- token 文件：
  - `/home/ubuntu/aps_device_auth.envline`

## 3. 当前目标状态

### 3.1 两条模板路径

后续做 `APS009` 迁移时，不要把“host 启动链模板”和“区域/设备模板”混在一起。当前应分成两条路径理解：

| 路径 | 模板机 | 含义 | 后续给 `APS009` 的使用方式 |
| --- | --- | --- | --- |
| `ehub` 路径 | `APS998` | 新版 host / 新版 HMI 启动链 / CPU tuning / standalone HMI | 复制 host 链路实现 |
| `HK` 路径 | `APS002` | HK 区域地图、设备 ID、work id、sensor profile 等业务参数 | 保留 HK 参数语义，但主机链路不要停留在旧版 |

对 `APS009` 来说，正确目标不是“完全复制 APS998”或“完全复制 APS002”，而是：

1. host 启动链跟 `APS998`
2. HK 区域与设备参数跟 `APS002`

### 3.2 `APS009` 最终应具备的共性

迁移完成后，`APS009` 这类目标机应该具备下面这些“和 APS998 一样”的 host 共性：

1. `autoware.APS` 车端入口改成 `start_autoware_hmi.sh`
2. `aps-local-hmi-stack.service` 由 GNOME Startup Applications 触发
3. 图形桌面自动登录为 `libpet-aps`
4. `aps_ui.service` 提供 `http://127.0.0.1:3001/aps/welcome`
5. `aps_nestapp.service` 提供 `http://127.0.0.1:3003`
6. `modbus_read.service` 提供 `/tmp/vttyB`
7. 登录桌面后先直接拉起 standalone `aps_hmi_container`，随后再启动 `autoware.launch.xml`
8. `ros2 launch autoware_launch autoware.launch.xml` 实际启动参数里带：
   - `launch_hmi_container:=false`
   - `hmi_single_container:=true`
   - `hmi_compose_layout:=false`
   - `hmi_single_fullscreen:=true`
   - `rviz_fullscreen:=false`
9. 当前车端 CPU/调度隔离：
   - standalone HMI / QtWebEngine：`24-31`，`nice=5`
   - `ros2 launch autoware_launch autoware.launch.xml`：`0-23`
   - 当前仍保持 `SCHED_OTHER`，还没有启用 realtime policy

但下面这些字段是区域/设备相关值，迁移到 `APS009` 时不能照抄 `APS998`：

1. `NEXT_PUBLIC_APS_ID`
2. `APS_DEVICE_ID`
3. `APS_DEVICE_TOKEN`
4. `sensor_config_profile`
5. `NEXT_PUBLIC_MAP_REGION`
6. `NEXT_PUBLIC_MAP_PATH`
7. `NEXT_PUBLIC_DEFAULT_WORK_ID`
8. `lanelet2_map_file`
9. `pointcloud_map_file`

## 4. 当前 APS998 真实配置快照

这部分最初是 2026-03-31 现场确认过的车端配置；其中 HMI 启动链已在 2026-04-02 追加过一次车端热修。以下默认都是在说参考机 `APS998`，不是所有机器的通用值。

### 4.1 GDM 自动登录

文件：

- `/etc/gdm3/custom.conf`

关键字段：

```ini
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=libpet-aps
WaylandEnable=false
```

### 4.2 Startup Applications 入口

文件：

- `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop`

当前内容要点：

```ini
Exec=/home/libpet-aps/bin/start_local_hmi_stack_fast_autostart.sh
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=0
```

### 4.3 wrapper

文件：

- `~/bin/start_local_hmi_stack_fast_autostart.sh`

作用：

1. 写日志到 `~/hmi_test/.log/startup_application.log`
2. 不再固定等待 15 秒
3. 直接执行：
   - `systemctl --user start aps-local-hmi-stack.service`

### 4.4 实际自启 user service

文件：

- `~/.config/systemd/user/aps-local-hmi-stack.service`

当前关键字段：

```ini
Environment=APS_HMI_WAIT_UI_SEC=180
ExecStart=/usr/bin/bash -lc 'exec %h/autoware.APS/scripts/start_autoware_hmi.sh'
ExecStop=/usr/bin/bash -lc 'exec %h/autoware.APS/scripts/stop_autoware_hmi.sh'
```

#### 2026-04-02 CPU / 调度 drop-in

文件：

- `~/.config/systemd/user/aps-local-hmi-stack.service.d/cpu-tuning.conf`

当前内容：

```ini
[Service]
Environment="APS_HMI_LAUNCH_PREFIX=taskset -c 24-31 nice -n 5"
Environment="APS_AUTOWARE_LAUNCH_PREFIX=taskset -c 0-23"
```

说明：

- `APS_HMI_LAUNCH_PREFIX` 只作用于 standalone `aps_hmi_container` 进程树
- `APS_AUTOWARE_LAUNCH_PREFIX` 只作用于 `ros2 launch autoware_launch autoware.launch.xml`
- 车端 CPU 是 `Intel i9-13900T`；这次先把 HMI 压到 `24-31` 这段逻辑 CPU，把 Autoware 留在 `0-23`
- 当前没有上 realtime policy，调度策略仍保持 `SCHED_OTHER`

### 4.5 真正启动脚本

文件：

- `~/autoware.APS/scripts/start_autoware_hmi.sh`

当前默认参数：

- `vehicle_model:=aps_vehicle`
- `sensor_model:=aps_sensor_kit`
- `sensor_config_profile:=aps998`
- `lanelet2_map_file:=frontway2.osm`
- `pointcloud_map_file:=front.pcd`
- `hmi_frontend_url:=http://127.0.0.1:3001/aps/welcome`
- `hmi_single_container:=true`
- `hmi_single_fullscreen:=true`
- `hmi_rviz_ratio:=30`
- `hmi_target_monitor:=primary`
- `hmi_layout_direction:=frontend_left`

说明：

- 这里的 `sensor_config_profile:=aps998` 是 `APS998` 专属值
- 迁移到 `APS009` 时，不要保留 `aps998`；应改成目标机对应 profile，当前可先按“基于 APS002 推定为 `aps009`”理解，现场再确认

#### 2026-04-02 HMI 空窗期修正

这次现场加的修正是为了解决：

- 桌面已经自动登录，但 HMI 容器还没弹出来
- 登录后会先看到一段空窗期，过十几秒才进入 loading 页面

现场排查结论：

- GNOME autostart 和 `aps-local-hmi-stack.service` 本身并不慢
- 真正的空窗期主要发生在 `autoware.launch.xml` 还没走到 HMI 节点之前
- 只把 `autoware.launch.xml` 里的 HMI 节点往前挪，仍然会有明显等待

最终保留在车端的生效配置是：

1. `~/autoware.APS/scripts/start_autoware_hmi.sh` 在 `APS_HMI_MODE=single` 时，先直接拉起 standalone `aps_hmi_container`
2. standalone HMI 起来后，再执行 `ros2 launch autoware_launch autoware.launch.xml`
3. 后续传给 `autoware.launch.xml` 的关键参数改成：
   - `launch_hmi_container:=false`
   - `hmi_single_container:=true`
   - `hmi_compose_layout:=false`
   - `hmi_single_fullscreen:=true`
   - `rviz_fullscreen:=false`
4. 这样 `autoware.launch.xml` 不会再重复起第二套 HMI container，而是由前面提前拉起的 standalone `aps_hmi_container` 负责显示 loading 与嵌入前端/RViz

这次实测时间线（2026-04-02 10:30 HKT）：

- `10:30:11` `aps-local-hmi-stack.service` 开始
- `10:30:12` 主 `aps_hmi_container` 已启动
- `10:30:13` `ros2 launch autoware_launch autoware.launch.xml` 才启动
- `10:30:34` 日志出现 `HMI loading gate satisfied; showing embedded HMI`

因此现在的目标效果不是“先空桌面再弹 HMI”，而是：

- 登录桌面后先看到 HMI loading 窗口
- Autoware 在后台继续起
- 等 loading gate 满足后再切到完整嵌入式 HMI

重要说明：

- 这套修正在 2026-04-02 15:55-16:05 HKT 已经同步回本地 repo 并重新部署到参考机
- 当前对应提交为：
  - 顶层 `autoware.APS`：`0f567c8` `Detach vehicle HMI launcher from autoware launch`
  - 内层 `autoware_launch_APS`：`423dd78` `Refine HMI container boot flow and loading UI`
  - 内层 `autoware_launch_APS`：`4ebcf73` `Align vehicle HMI launch defaults`
- 这次车端更新不是直接整仓 `git pull`，而是因为远端 worktree 本来就不干净，所以先备份，再只定向覆盖 HMI 相关文件
- 当前车端保留不动的现场项包括：
  - `autoware_launch/config/serial_ports.param.yaml`
  - `vehicle/aps_vehicle_launch/aps_vehicle_launch`
  - 顶层 repo 里监控脚本相关未提交改动

车端当时留的回滚备份可作为参考：

- `~/hmi_update_backup_20260402_155902/`
- `~/autoware.APS/scripts/start_autoware_hmi.sh.bak_20260402_102956_standalone_hmi_fix`
- `~/autoware.APS/src/launcher/autoware_launch_APS/autoware_launch/launch/autoware.launch.xml.bak_20260402_102159_hmi_earliest`

### 4.6 车端 UI service

文件：

- `/etc/systemd/system/aps_ui.service`

当前关键字段：

```ini
Environment=NODE_ENV=production
Environment=PORT=3001
Environment=ROS_DOMAIN_ID=4
Environment=RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
Environment=CYCLONEDDS_URI=file:///home/libpet-aps/cyclonedds.xml
WorkingDirectory=/home/libpet-aps/APS_management_system_ui
ExecStart=/bin/bash -lc 'source /opt/ros/humble/setup.bash && source /home/libpet-aps/autoware.APS/install/setup.bash && exec /home/libpet-aps/.nvm/versions/node/v20.19.4/bin/node /home/libpet-aps/APS_management_system_ui/node_modules/next/dist/bin/next start -p 3001'
```

### 4.7 车端 UI 环境文件

文件：

- `~/APS_management_system_ui/.env.local`

当前关键字段：

```dotenv
NEXT_PUBLIC_MAP_PATH=/map.svg
NEXT_PUBLIC_MAP_REGION=ehub
NEXT_PUBLIC_AUTOWARE_BACKEND_API=http://localhost:3003
NEXT_PUBLIC_REMOTE_BACKEND_API=https://backend.libpet.vip
NEXT_PUBLIC_APS_ID=APS998
NEXT_PUBLIC_DEFAULT_WORK_ID=ehub
APS_DEVICE_ID=APS998-ehub-ui
APS_DEVICE_TOKEN=<do not commit; fill from server>
```

说明：

- `APS_DEVICE_TOKEN` 现在车端已补上，但不要把明文写进 git。
- 这个区块是 `APS998` 当前实际值，不是目标机通用模板。
- 如果后续迁移到 `APS009`，至少要把：
  - `NEXT_PUBLIC_APS_ID`
  - `APS_DEVICE_ID`
  - `APS_DEVICE_TOKEN`
  - `NEXT_PUBLIC_MAP_REGION`
  - `NEXT_PUBLIC_MAP_PATH`
  - `NEXT_PUBLIC_DEFAULT_WORK_ID`
  改成目标机对应值。

### 4.8 车端 Nest service

文件：

- `~/.config/systemd/user/aps_nestapp.service`

当前关键点：

1. 是 user service，不是 system service
2. 启动前会等待：
   - `modbus_read.service`
   - `/tmp/vttyB`
   - `127.0.0.1:19092`
3. 运行命令：
   - `/home/libpet-aps/.nvm/versions/node/v20.19.4/bin/node /home/libpet-aps/nestjs_test/dist/main.js`

### 4.9 车端 modbus service

文件：

- `/etc/systemd/system/modbus_read.service`
- `/etc/systemd/system/modbus_read.service.d/override.conf`

当前关键点：

```ini
ExecStart=/usr/bin/python3 /home/libpet-aps/stm32/modbus_read.py
```

override 当前为：

```ini
[Service]
Environment=MODBUS_PORT=/dev/serial/by-path/pci-0000:00:14.0-usb-0:7.1.3:1.0-port0
```

说明：

- 超声波：`7.1.1`
- 电机：`7.2.2`
- modbus 当前强制走：`7.1.3`

## 5. ROS 与环境变量说明

### 5.1 `.bashrc`

当前车端 `~/.bashrc` 已确认有：

- `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`
- `CYCLONEDDS_URI=file:///home/libpet-aps/cyclonedds.xml`

### 5.2 `start_autoware_hmi.sh`

脚本支持：

- `APS_ROS_DOMAIN_ID`
- `ROS_DOMAIN_ID`
- `APS_HMI_LAUNCH_PREFIX`
- `APS_AUTOWARE_LAUNCH_PREFIX`

如果没显式传，脚本会让 ROS 落回默认 domain `0`。

补充：

- 车端在 2026-04-02 为了消除桌面空窗期，给 `start_autoware_hmi.sh` 加过一层“先起 standalone `aps_hmi_container`，再起 `autoware.launch.xml`”的热修；当前这层逻辑已同步回 repo
- 当前车端通过 `aps-local-hmi-stack.service.d/cpu-tuning.conf` 把：
  - HMI 前缀设成 `taskset -c 24-31 nice -n 5`
  - Autoware 前缀设成 `taskset -c 0-23`
- 所以后续如果只更新顶层 `autoware.APS` 而忘了同步内层 `autoware_launch_APS`，很容易出现“脚本支持前缀，但 launch / HMI container 版本没对齐”的半更新状态
- 2026-04-02 只读对比 `APS002` 时发现，那台机器还没有这套脚本入口，`~/autoware.APS/scripts/start_autoware_hmi.sh` 直接不存在；这也是后续迁移到 `APS009` 时需要补齐的第一项

### 5.3 `hmi_env.sh`

`hmi_env.sh` 会尝试从登录 shell 导入：

- `APS_ROS_DOMAIN_ID`
- `ROS_DOMAIN_ID`
- `RMW_IMPLEMENTATION`
- `CYCLONEDDS_URI`

因此如果后续现场改了 `.bashrc`，HMI 启动脚本可能会继承到。

## 6. 两条模板路径的关键快照

### 6.1 `ehub` 路径：`APS998` 新版 host 模板

这条路径代表“新版 host + ehub 参数”一起已经跑通的参考实现。

关键 host 特征：

1. `start_autoware_hmi.sh` / `stop_autoware_hmi.sh` 已存在
2. GNOME autostart + wrapper + `aps-local-hmi-stack.service` 已存在
3. `aps-local-hmi-stack.service.d/cpu-tuning.conf` 已存在
4. 实际运行形态是 standalone `aps_hmi_container` 先起，再起 `autoware.launch.xml`
5. `ros2 launch autoware_launch autoware.launch.xml` 运行参数带 `launch_hmi_container:=false`

关键 ehub 参数：

1. `NEXT_PUBLIC_MAP_PATH=/map.svg`
2. `NEXT_PUBLIC_MAP_REGION=ehub`
3. `NEXT_PUBLIC_DEFAULT_WORK_ID=ehub`
4. `NEXT_PUBLIC_APS_ID=APS998`
5. `APS_DEVICE_ID=APS998-ehub-ui`
6. `sensor_config_profile=aps998`
7. `lanelet2_map_file=frontway2.osm`
8. `pointcloud_map_file=front.pcd`

### 6.2 `HK` 路径：`APS002` 旧版 host 模板

这条路径代表“HK 区域参数”当前能看到的旧版 host 机器模板。后续给 `APS009` 用时，只继承 HK 参数语义，不保留旧 host 链路。

当前读到的 HK 参数：

1. `NEXT_PUBLIC_MAP_PATH=/map_airport.svg`
2. `NEXT_PUBLIC_MAP_REGION=HK`
3. `NEXT_PUBLIC_DEFAULT_WORK_ID=hk`
4. `NEXT_PUBLIC_APS_ID=APS002`
5. `APS_DEVICE_ID=APS002-hk-ui`
6. `sensor_config_profile=aps002`
7. `lanelet2_map_file=map_ele.osm`
8. `pointcloud_map_file=hkairport.pcd`

当前读到的旧版 host 特征：

1. `~/autoware.APS/scripts/start_autoware_hmi.sh` 不存在
2. 本次读取路径下没有发现 `aps-local-hmi-stack.service`、autostart desktop、wrapper、CPU drop-in
3. 运行中只看到了 `ros2 launch autoware_launch autoware.launch.xml`

### 6.3 `APS009` 应走的组合路径

`APS009` 目标状态应该是：

1. host 启动链复制 `APS998`
2. HK 区域参数复制 `APS002`
3. 设备身份改成 `APS009`

也就是：

- `APS009` 不应继续停留在 `APS002` 那种旧 host 版本
- `APS009` 也不应把 `APS998` 的 `ehub` 参数直接照抄过去

## 7. `APS998` 与 `APS002` / `APS009` 的关键差异

### 7.1 2026-04-02 实测对比结论

`APS998` 当前已经是新链路；`APS002` 仍是旧链路，因此后续 `APS009` 迁移不能只看某一个文件，要按整条启动链补齐。

| 项目 | `APS998` 参考机 | `APS002` 只读对比机 | `APS009` 迁移目标 |
| --- | --- | --- | --- |
| SSH | `APS998` / port `8983` | `APS002` / port `8223` | `APS009` / port `8923` |
| 2026-04-02 可达性 | 可连接 | 可连接 | `Connection refused` |
| 顶层 repo 观察值 | `hmi_container_dev`，worktree 不干净 | `airy_test`，worktree 不干净 | 现场再确认 |
| 内层 repo 观察值 | `hmi_container_dev`，worktree 不干净 | `speed_test`，worktree 不干净 | 现场再确认 |
| `start_autoware_hmi.sh` | 存在 | 不存在 | 需要补齐 |
| GNOME autostart + wrapper + `aps-local-hmi-stack.service` | 已存在 | 本次读取路径下未发现 | 需要补齐 |
| CPU drop-in | 已存在 | 未发现 | 需要补齐 |
| UI 地图区域 | `ehub` | `HK` | 基于 `APS002` 推定为 `HK` |
| `NEXT_PUBLIC_APS_ID` | `APS998` | `APS002` | 应为 `APS009` |
| `APS_DEVICE_ID` | `APS998-ehub-ui` | `APS002-hk-ui` | 应为 `APS009-hk-ui` |
| `sensor_config_profile` | `aps998` | `aps002` | 基于 `APS002` 推定为 `aps009` |
| 地图默认值 | `frontway2.osm` + `front.pcd` | `map_ele.osm` + `hkairport.pcd` | 基于 `APS002` 推定为 HK 这一组 |
| `launch_hmi_container` 这个 arg | 已存在 | 本次读取结果里未出现 | 需要随内层 repo 同步过去 |
| 实际运行形态 | standalone `aps_hmi_container` + `autoware.launch.xml` | 只看到 `ros2 launch autoware_launch autoware.launch.xml` | 目标应与 `APS998` 一致 |

### 7.2 `APS009` 预期设备相关值

下面这些值不要直接复制 `APS998`，应按目标机改。当前因为 `APS009` 不可达，这里先按“`APS002` 与 `APS009` 同类”做推定：

- `NEXT_PUBLIC_MAP_PATH=/map_airport.svg`
- `NEXT_PUBLIC_MAP_REGION=HK`
- `NEXT_PUBLIC_DEFAULT_WORK_ID=hk`
- `NEXT_PUBLIC_APS_ID=APS009`
- `APS_DEVICE_ID=APS009-hk-ui`
- `APS_DEVICE_TOKEN`
  - 不写入 git
  - 如缺失，到 `server:/home/ubuntu/aps_device_auth.envline` 搜 `APS009-hk-ui`
- `sensor_config_profile=aps009`
- `lanelet2_map_file=map_ele.osm`
- `pointcloud_map_file=hkairport.pcd`

重要说明：

- 上面这组 `APS009` 值里，除了主机别名和端口，其他都是“基于 APS002 推定”的迁移目标
- 真正动 `APS009` 前，Codex 仍然应该先 SSH 上去把 `.env.local`、`autoware.launch.xml`、地图文件和 profile 目录再确认一次

## 8. `APS998 -> APS009` 标准迁移步骤

### 8.1 先确认 `APS009` 已经可连

```bash
ssh APS009
```

如果还是连不上，不要先动本地 repo；继续以 `APS002` 做只读对比即可。

### 8.2 上 `APS009` 后先做只读采样

```bash
cd ~/autoware.APS && git branch --show-current && git rev-parse --short HEAD && git status --short
cd ~/autoware.APS/src/launcher/autoware_launch_APS && git branch --show-current && git rev-parse --short HEAD && git status --short
sed -n '1,120p' ~/.config/autostart/start_local_hmi_stack_fast.sh.desktop 2>/dev/null || true
sed -n '1,120p' ~/bin/start_local_hmi_stack_fast_autostart.sh 2>/dev/null || true
sed -n '1,120p' ~/.config/systemd/user/aps-local-hmi-stack.service 2>/dev/null || true
sed -n '1,80p' ~/.config/systemd/user/aps-local-hmi-stack.service.d/cpu-tuning.conf 2>/dev/null || true
rg -n '^(NEXT_PUBLIC_MAP_PATH|NEXT_PUBLIC_MAP_REGION|NEXT_PUBLIC_APS_ID|NEXT_PUBLIC_DEFAULT_WORK_ID|APS_DEVICE_ID)=' ~/APS_management_system_ui/.env.local || true
rg -n '<arg name="(sensor_config_profile|lanelet2_map_file|pointcloud_map_file|launch_hmi_container)"' ~/autoware.APS/src/launcher/autoware_launch_APS/autoware_launch/launch/autoware.launch.xml || true
```

### 8.3 迁移时只同步 HMI 相关文件

如果目标机 worktree 不干净，不要直接整仓 `git pull`。优先：

1. 先备份目标机当前生效文件
2. `git fetch` 顶层 repo 和内层 `autoware_launch_APS`
3. 只定向覆盖 HMI 相关文件：
   - `scripts/start_autoware_hmi.sh`
   - `scripts/stop_autoware_hmi.sh`
   - `aps_hmi_container/CMakeLists.txt`
   - `aps_hmi_container/src/main.cpp`
   - `aps_hmi_container/assets/`
   - `autoware_launch/launch/autoware.launch.xml`
4. 保留目标机现场配置项不动，例如：
   - `autoware_launch/config/serial_ports.param.yaml`
   - `vehicle/aps_vehicle_launch/aps_vehicle_launch`

### 8.4 再把 `APS009` 的设备相关值改回目标机版本

重点检查：

1. `~/APS_management_system_ui/.env.local`
2. `~/autoware.APS/src/launcher/autoware_launch_APS/autoware_launch/launch/autoware.launch.xml`
3. 如有脚本默认值依赖，也检查：
   - `~/autoware.APS/scripts/start_autoware_hmi.sh`

这一节要按“HK 参数模板来自 `APS002`”来回填，不要按 `APS998` 的 ehub 参数回填。

不要保留这些 `APS998` 值：

- `APS998`
- `APS998-ehub-ui`
- `aps998`
- `frontway2.osm`
- `front.pcd`
- `ehub`
- `/map.svg`

对 `APS009` 来说，优先回填成这组 HK 路径目标值：

- `NEXT_PUBLIC_MAP_PATH=/map_airport.svg`
- `NEXT_PUBLIC_MAP_REGION=HK`
- `NEXT_PUBLIC_DEFAULT_WORK_ID=hk`
- `NEXT_PUBLIC_APS_ID=APS009`
- `APS_DEVICE_ID=APS009-hk-ui`
- `sensor_config_profile=aps009`
- `lanelet2_map_file=map_ele.osm`
- `pointcloud_map_file=hkairport.pcd`

### 8.5 如果目标机还没有新链路，要补齐自启入口

至少应有：

1. `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop`
2. `~/bin/start_local_hmi_stack_fast_autostart.sh`
3. `~/.config/systemd/user/aps-local-hmi-stack.service`
4. `~/.config/systemd/user/aps-local-hmi-stack.service.d/cpu-tuning.conf`
5. `~/autoware.APS/scripts/start_autoware_hmi.sh`
6. `~/autoware.APS/scripts/stop_autoware_hmi.sh`

### 8.6 重编与重启

```bash
cd ~/autoware.APS
colcon build \
  --packages-select aps_hmi_container autoware_launch \
  --cmake-force-configure \
  --symlink-install \
  --allow-overriding autoware_launch \
  --cmake-args \
    -DBUILD_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DAPS_HMI_PREFER_WEBKIT=OFF

cd ~/APS_management_system_ui
npm run build
printf '<sudo-password>\n' | sudo -S systemctl restart aps_ui.service

cd ~/nestjs_test
npm run build
systemctl --user daemon-reload
systemctl --user restart aps_nestapp.service
systemctl --user restart aps-local-hmi-stack.service
```

## 9. 迁移后最小验证清单

```bash
curl -I http://127.0.0.1:3001/aps/welcome
curl http://127.0.0.1:3003/api/vehicle/localization-status
ps -eo pid,ppid,pgid,ni,psr,pcpu,pmem,comm,args --sort=-pcpu | rg 'autoware.launch.xml|aps_hmi_container|QtWebEngineProcess' || true
taskset -pc <hmi-pid>
taskset -pc <autoware-pid>
chrt -p <hmi-pid>
chrt -p <autoware-pid>
```

结果应满足：

1. 页面 `3001` 可访问
2. Nest `3003` 可访问
3. 进程树里同时看到 standalone `aps_hmi_container` 和 `ros2 launch autoware_launch autoware.launch.xml`
4. HMI / QtWebEngine 在 `24-31`
5. Autoware 在 `0-23`
6. 调度策略仍是 `SCHED_OTHER`
7. `ros2 launch autoware_launch autoware.launch.xml` 实际参数里带 `launch_hmi_container:=false`

## 10. 已知坑与固定结论

### 10.1 顶层 repo 和内层 repo 是两套 git

`~/autoware.APS/src/launcher/autoware_launch_APS` 是独立 git repo。

如果只更新顶层 `autoware.APS` 而忘了同步内层 repo，很容易出现：

- 脚本已经支持 standalone HMI
- 但 `autoware.launch.xml` 还没有 `launch_hmi_container`
- 或 `aps_hmi_container` 还是旧版

### 10.2 不要把 `APS998` 的设备值直接抄到 `APS009`

对 `APS009` 来说，下面这些值都应该被视为错的：

- `NEXT_PUBLIC_MAP_REGION=ehub`
- `NEXT_PUBLIC_MAP_PATH=/map.svg`
- `NEXT_PUBLIC_DEFAULT_WORK_ID=ehub`
- `NEXT_PUBLIC_APS_ID=APS998`
- `APS_DEVICE_ID=APS998-ehub-ui`
- `sensor_config_profile=aps998`
- `lanelet2_map_file=frontway2.osm`
- `pointcloud_map_file=front.pcd`

### 10.3 `APS002` / `APS009` 类机器当前更像旧链路

2026-04-02 只读检查 `APS002` 的结论是：

1. `~/autoware.APS/scripts/start_autoware_hmi.sh` 不存在
2. 本次读取路径下没有发现 `aps-local-hmi-stack.service` 和 autostart wrapper
3. 运行中只看到了 `ros2 launch autoware_launch autoware.launch.xml`

所以未来迁移 `APS009` 时，不是改一个参数就够，而是要把整条启动链补齐。

### 10.4 CPU / 调度优化常见坑

如果给 `aps-local-hmi-stack.service` 加 CPU tuning 后重启立即失败，优先检查：

1. `~/.config/systemd/user/aps-local-hmi-stack.service.d/cpu-tuning.conf` 里的 `Environment=` 值如果包含空格，必须整体加双引号
2. 如果没加引号，`journalctl --user -u aps-local-hmi-stack.service` 会出现：
   - `Invalid environment assignment`
3. 同时 `~/hmi_test/.log/startup_application.log` 往往会出现：
   - `HMI launch prefix: taskset`
   - `taskset: failed to parse CPU mask`

当前正确写法是：

```ini
[Service]
Environment="APS_HMI_LAUNCH_PREFIX=taskset -c 24-31 nice -n 5"
Environment="APS_AUTOWARE_LAUNCH_PREFIX=taskset -c 0-23"
```

### 10.5 WebEngine 与 WebKit

这个项目应该优先跑 WebEngine，不要回退 WebKit。

若远端 HMI 表现异常，查：

```bash
grep APS_HMI_PREFER_WEBKIT ~/autoware.APS/build/aps_hmi_container/CMakeCache.txt
ldd ~/autoware.APS/install/aps_hmi_container/lib/aps_hmi_container/aps_hmi_container | rg 'WebEngine|WebKit'
```

## 11. 推荐给 Codex 的直接提示词

下面这段可以直接喂给 Codex：

```text
你现在要把 APS998 上已经生效的 HMI container 新启动链，迁移到 APS009。

请先阅读：
/home/libpet/autoware.APS/docs/hmi_container_dev_codex_handoff_20260331.md

执行原则：
1. APS998 是参考机
2. APS998 代表 ehub 路径，而且是新版 host 模板
3. APS002 代表 HK 路径，但它只是旧版 host 模板，只做只读对比，不要修改 APS002
4. APS009 是目标机，最终要采用“host 链路跟 APS998，HK 参数跟 APS002”的组合
5. 不要把 APS998 的 ehub / APS998 / aps998 / frontway2 / front.pcd 直接复制到 APS009

先做：
1. 检查本地 repo 状态：autoware.APS、autoware_launch_APS、APS_management_system_ui、nestjs_test
2. SSH 到 APS009；如果 APS009 还不可达，就先只读检查 APS002
3. 在目标机上先采样：autostart、wrapper、aps-local-hmi-stack.service、cpu-tuning.conf、.env.local、autoware.launch.xml
4. 确认目标机是否缺 start_autoware_hmi.sh / stop_autoware_hmi.sh / aps-local-hmi-stack.service
5. 只同步 HMI 相关文件，不要盲目整仓 git pull
6. 同步后立刻把目标机的设备相关值改成 APS009 版本
7. 重编 aps_hmi_container 和 autoware_launch，再重启 aps_ui.service、aps_nestapp.service、aps-local-hmi-stack.service

重点注意：
- /home/libpet-aps/autoware.APS/src/launcher/autoware_launch_APS 是独立 git repo
- 目标机 worktree 很可能不干净，先备份再定向覆盖
- launch_hmi_container:=false 是运行时必须带的关键参数
- APS009 的 host 链路以 APS998 为模板；APS009 的地图/设备参数以 APS002 为模板
- CPU tuning drop-in 在 /home/libpet-aps/.config/systemd/user/aps-local-hmi-stack.service.d/cpu-tuning.conf
- 如果 APS_DEVICE_TOKEN 缺失，到 server:/home/ubuntu/aps_device_auth.envline 查 APS009-hk-ui
```

## 12. 这份文档的使用建议

如果后续继续维护：

1. 不要把密码和 token 写进 git 跟踪文件
2. 变更车机自启链路后，至少做一次真实 reboot 复验
3. 如果 APS009 重新上线且可 SSH，把本文件里所有“基于 APS002 推定”的字段逐项改成现场确认值
4. 如果 Codex 要继续写这份文档，优先追加新节，不要把老结论无提示覆盖掉
