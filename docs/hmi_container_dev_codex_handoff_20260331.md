# hmi_container_dev Codex Handoff Runbook

Date: 2026-03-31

## 1. 文档目的

这份文档不是简单的过程记录，而是一份给 Codex 直接接手用的操作手册。

目标：

1. 让 Codex 在最少追问的前提下，快速理解本地开发机、车辆、远端服务器三边的关系。
2. 让 Codex 可以按固定步骤完成 HMI 相关部署、自启修复、UI/Nest 对齐、远端 order 联调。
3. 记录当前车辆 `libpet-aps@<vehicle-ip>` 上真实生效的最终配置。

说明：

- 这份文档尽量写“当前真实状态”，不是旧方案。
- 文档不写 SSH 密码和设备 token 明文；只写获取位置和更新方式。
- 如果 Codex 能访问当前工作区和终端，它应该优先以这份文档为准，再对现场做二次确认。

## 2. 机器与仓库关系

### 2.1 本地开发机

- user: `libpet`
- home: `/home/libpet`

本地仓库：

- `autoware.APS`
  - `/home/libpet/autoware.APS`
- `APS_management_system_ui`
  - `/home/libpet/APS_management_system_ui`
- `nestjs_test`
  - `/home/libpet/nestjs_test`
- `LED_WS2812`
  - `/home/libpet/LED_WS2812`

### 2.2 车辆

- ssh user: `libpet-aps`
- ip: 现场确认，不要写死
- home: `/home/libpet-aps`
- system: `Ubuntu 22.04`

说明：

- 车机 IP 不是稳定配置项，后续让 Codex 接手时，不要默认使用某个旧 IP。
- 应先通过现场网络、ARP、路由器、车机屏幕，或已知 SSH 配置确认“当前车机 IP”。

车辆仓库：

- `autoware.APS`
  - `/home/libpet-aps/autoware.APS`
- `APS_management_system_ui`
  - `/home/libpet-aps/APS_management_system_ui`
- `nestjs_test`
  - `/home/libpet-aps/nestjs_test`
- 运行时 modbus 脚本
  - `/home/libpet-aps/stm32/modbus_read.py`

### 2.3 远端服务器

- ssh alias: `server`
- 实际机器：`ubuntu@43.154.113.98`
- 当前有 private key，可直接 `ssh server`

远端后台关键服务：

- `aps_remote_backend.service`
- 服务工作目录实际被 runtime override 切到：
  - `/home/ubuntu/.deploy/aps_remote_backend_production`

## 3. 当前目标状态

车辆当前 HMI 相关正确状态应该是：

1. `autoware.APS` 车端执行 `start_autoware_hmi.sh`
2. `aps-local-hmi-stack.service` 由 GNOME Startup Applications 触发
3. 图形桌面自动登录为 `libpet-aps`
4. `aps_ui.service` 提供 `http://127.0.0.1:3001/aps/welcome`
5. `aps_nestapp.service` 提供 `http://127.0.0.1:3003`
6. `modbus_read.service` 提供 `/tmp/vttyB`
7. 登录桌面后先直接拉起 standalone `aps_hmi_container`，随后再启动 `autoware.launch.xml`
8. 当前车端地图默认：
   - `frontway2.osm`
   - `front.pcd`
9. 当前远端 order 设备标识：
   - `APS998`
   - `APS_DEVICE_ID=APS998-ehub-ui`

## 4. 当前车辆真实配置快照

这部分最初是 2026-03-31 现场确认过的车端配置；其中 HMI 启动链已在 2026-04-02 追加过一次车端热修。

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
   - `rviz:=false`
   - `hmi_single_container:=false`
   - `hmi_compose_layout:=false`
4. 这样 Autoware 不会再重复起第二套单窗 HMI，而是由前面提前拉起的 standalone `aps_hmi_container` 负责显示 loading 与嵌入前端/RViz

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

- 这套修正目前是直接改在车端 `libpet-aps@192.168.0.189` 上的热修状态
- 本机 repo 里的 `start_autoware_hmi.sh` / `autoware.launch.xml` 不一定已经同步包含这次变更
- 如果后续重新部署车端，必须先确认不要把这次“先起 standalone HMI”的配置覆盖掉

车端当时留的回滚备份可作为参考：

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
- 缺 token 时，UI 仍可能通过 `x-user-id` 旧逻辑建单，但远端 stop/complete/resume 的稳定性会差。

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

如果没显式传，脚本会让 ROS 落回默认 domain `0`。

补充：

- 车端在 2026-04-02 为了消除桌面空窗期，给 `start_autoware_hmi.sh` 加过一层“先起 standalone `aps_hmi_container`，再起 `autoware.launch.xml`”的热修
- 所以后续如果只看 repo 源码，不一定等于车上当前真实生效脚本

### 5.3 `hmi_env.sh`

`hmi_env.sh` 会尝试从登录 shell 导入：

- `APS_ROS_DOMAIN_ID`
- `ROS_DOMAIN_ID`
- `RMW_IMPLEMENTATION`
- `CYCLONEDDS_URI`

因此如果后续现场改了 `.bashrc`，HMI 启动脚本可能会继承到。

## 6. 远端 order / token 相关事实

### 6.1 服务器设备 token 的获取位置

服务器当前可以通过下面这个文件拿到 UI 设备鉴权列表：

- `/home/ubuntu/aps_device_auth.envline`

查 `APS998-ehub-ui` 的方法：

```bash
ssh server
rg 'APS998-ehub-ui' /home/ubuntu/aps_device_auth.envline
```

### 6.2 车端 order 创建时机

这点很容易误判。

当前 UI 不是在 `dispatch/plan` 页“选完终点就立刻创建 order”。

真实时序是：

1. `dispatch/plan` 只负责选起点/终点，然后跳到 `/aps/depart-instruct`
2. 真正的 `createNavigation()` 在 `DepartInstructClient.tsx` 里触发
3. 如果远端建单失败，前端会记录日志并继续本地 route 流程

所以会出现这种现象：

- 车端本地路线继续跑
- 但服务器没看到 order

### 6.3 车端 order 联调结论

2026-03-31 已实测：

- 车机本地访问
  - `http://127.0.0.1:3001/api/remote-navigations`
- 成功创建：
  - `ORD-EHUB-260331-000010`

说明：

- 车机到 `backend.libpet.vip` 的建单链路本身是通的
- 重点应查“前端何时调用 createNavigation”和“失败是否被前端吞掉”

## 7. 给 Codex 的标准排查顺序

后续让 Codex 接手时，建议按这个顺序做，不要一上来乱改。

### 7.1 先查本地三个仓库状态

```bash
cd /home/libpet/autoware.APS && git branch --show-current && git rev-parse --short HEAD && git status --short
cd /home/libpet/APS_management_system_ui && git branch --show-current && git rev-parse --short HEAD && git status --short
cd /home/libpet/nestjs_test && git branch --show-current && git rev-parse --short HEAD && git status --short
```

### 7.2 再查车机连通性

```bash
ping -c 2 <vehicle-ip>
ssh libpet-aps@<vehicle-ip>
```

如果车机不通，先不要判断 HMI 脚本对不对。

### 7.3 上车先查核心服务

```bash
systemctl --user status aps-local-hmi-stack.service --no-pager -l
systemctl --user status aps_nestapp.service --no-pager -l
printf '<sudo-password>\n' | sudo -S systemctl status aps_ui.service --no-pager -l
printf '<sudo-password>\n' | sudo -S systemctl status modbus_read.service --no-pager -l
ss -ltnp | rg ':3001|:3003' || true
```

### 7.4 查 HMI 自启链路

```bash
sed -n '1,120p' ~/.config/autostart/start_local_hmi_stack_fast.sh.desktop
sed -n '1,120p' ~/bin/start_local_hmi_stack_fast_autostart.sh
systemctl --user cat aps-local-hmi-stack.service
tail -n 120 ~/hmi_test/.log/startup_application.log
```

### 7.5 查 HMI 运行日志

```bash
tail -n 120 ~/hmi_test/.log/autoware_launch_hmi.log
tail -n 120 ~/hmi_test/.log/hmi_container.log
ps -ef | rg 'autoware.launch.xml|aps_hmi_container|QtWebEngineProcess' || true
```

### 7.6 查 UI 与 Nest 是否正常

```bash
curl -I http://127.0.0.1:3001/aps/welcome
curl http://127.0.0.1:3003/api/vehicle/localization-status
curl http://127.0.0.1:3001/api/gates
```

### 7.7 查 order 创建链路

车机本地直接打代理接口：

```bash
ts=$(date +%s%3N)
cat > /tmp/remote_nav_req.json <<EOF
{"deviceIds":["APS998"],"deviceStatuses":["PROGRESS_RESUME"],"status":"PROGRESS_RESUME","fromTerminalGateId":"Gate0","toTerminalGateId":"Gate1","createdBy":"ehub","events":{"type":"local_navigation_session","session_id":"debug-session","sessionId":"debug-session","triggerSource":"LOCAL_UI","ts":$ts}}
EOF

curl -sS -D - -o /tmp/remote_nav_resp.txt \
  -X POST http://127.0.0.1:3001/api/remote-navigations \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H 'x-user-id: ehub' \
  -H 'x-app-id: APS_Management_system_ui' \
  --data @/tmp/remote_nav_req.json

cat /tmp/remote_nav_resp.txt
```

服务器端同时看：

```bash
ssh server
journalctl -u aps_remote_backend.service -n 80 --no-pager | rg 'APS998|LOCAL_UI|/api/navigations|Invalid APS device credentials|not configured|expired'
```

## 8. 标准部署步骤

下面这组步骤是“从本地开发机把 HMI 相关部署到车端”的标准流程。

### 8.1 对齐 `autoware.APS`

如果本地脚本有更新：

1. 确认本地改动正确
2. 同步到车端
3. 如涉及 `aps_hmi_container` 或 launch 逻辑，必要时重编

车端重编命令：

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
```

### 8.2 对齐 `APS_management_system_ui`

```bash
cd ~/APS_management_system_ui
git fetch origin
git checkout -B hmi_container_dev origin/hmi_container_dev
npm run build
printf '<sudo-password>\n' | sudo -S systemctl restart aps_ui.service
```

验证：

```bash
curl -I http://127.0.0.1:3001/aps/welcome
```

### 8.3 对齐 `nestjs_test`

```bash
cd ~/nestjs_test
git fetch origin
git checkout -B hmi_container_dev origin/hmi_container_dev
npm run build
systemctl --user daemon-reload
systemctl --user restart aps_nestapp.service
```

验证：

```bash
curl http://127.0.0.1:3003/api/vehicle/localization-status
```

### 8.4 确认 modbus 串口

车端当前期望：

- 超声波：`7.1.1`
- modbus：`7.1.3`
- 电机：`7.2.2`

验证：

```bash
ls -l /dev/serial/by-path
printf '<sudo-password>\n' | sudo -S systemctl status modbus_read.service --no-pager -l
tail -n 80 /var/log/syslog | rg 'modbus|ttyUSB|RX'
```

### 8.5 重启整条 HMI 栈

```bash
systemctl --user restart aps-local-hmi-stack.service
```

验证：

```bash
ps -ef | rg 'autoware.launch.xml|aps_hmi_container|QtWebEngineProcess' || true
tail -n 120 ~/hmi_test/.log/autoware_launch_hmi.log
tail -n 120 ~/hmi_test/.log/hmi_container.log
```

## 9. 已知坑与固定结论

### 9.1 HMI 一直 loading

优先查：

1. `aps_ui.service` 是否起来
2. `aps_nestapp.service` 是否起来
3. `3003` 是否监听
4. `/api/gates` 是否返回 200
5. 是否有重复 `/nestjs_vehicle_backend`

重复 node 的典型症状：

- `AUTONOMOUS_MODE_UNAVAILABLE`
- `duplicated_node_checker`
- route 已经 `SET` 但 resume 不可用

### 9.2 order 没有出现在服务器

优先区分：

1. 你是不是还只停在 `dispatch/plan` 页
2. 有没有真正进入 `/aps/depart-instruct`
3. `createNavigation()` 是否失败但被前端吞掉
4. 车机 `APS_DEVICE_TOKEN` 是否为空

### 9.3 WebEngine 与 WebKit

这个项目应该优先跑 WebEngine，不要回退 WebKit。

若远端 HMI 表现异常，查：

```bash
grep APS_HMI_PREFER_WEBKIT ~/autoware.APS/build/aps_hmi_container/CMakeCache.txt
ldd ~/autoware.APS/install/aps_hmi_container/lib/aps_hmi_container/aps_hmi_container | rg 'WebEngine|WebKit'
```

### 9.4 LiDAR 融合空点云

之前修过一次 `rslidar_sdk` 扩展字段：

- `channel` 用 `ring`
- `azimuth/elevation/distance` 由几何值重算

如果再遇到 `concatenated/pointcloud` 空或闪烁，先确认车端是否已经拉齐到对应提交。

### 9.5 登录桌面后 HMI 空窗期

如果车端再次出现“桌面出来了，但 HMI 还要等十几秒才弹”的现象，优先检查：

1. `~/autoware.APS/scripts/start_autoware_hmi.sh` 是否还保留 `starting standalone aps_hmi_container...` 这条逻辑
2. 当前实际 `ros2 launch autoware_launch autoware.launch.xml` 参数里是否仍然带有：
   - `rviz:=false`
   - `hmi_single_container:=false`
   - `hmi_compose_layout:=false`
3. `aps-local-hmi-stack.service` 是否仍然指向：
   - `/home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh`
4. 如果你把车端脚本重新从本机 repo 覆盖了一遍，要高度怀疑是不是把这次 2026-04-02 的热修冲掉了

## 10. 推荐给 Codex 的直接提示词

下面这段可以直接喂给 Codex：

```text
你现在要接手 hmi_container_dev 在车辆上的部署与排障。

请先阅读：
/home/libpet/autoware.APS/docs/hmi_container_dev_codex_handoff_20260331.md

然后按这个顺序执行：
1. 检查本地三个仓库状态：autoware.APS、APS_management_system_ui、nestjs_test
2. 先确认当前车机 IP，再 SSH 到 libpet-aps@<vehicle-ip>
3. 检查 aps-local-hmi-stack.service、aps_ui.service、aps_nestapp.service、modbus_read.service
4. 检查 3001、3003、/api/gates、/api/vehicle/localization-status
5. 如果是 order 问题，再检查 /api/remote-navigations 和服务器 aps_remote_backend.service 日志

注意：
- 不要假定旧的车机 IP 仍然有效，先确认现场当前 IP
- 车机真正的自启脚本是 /home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh
- GNOME autostart desktop 文件名虽然还是 start_local_hmi_stack_fast.sh.desktop，但实际已通过 wrapper 转到 aps-local-hmi-stack.service
- 2026-04-02 车端为了消除桌面空窗期，已把 HMI 改成“先 standalone aps_hmi_container，再起 autoware.launch.xml”；在覆盖车端脚本前先确认这层热修是否要保留
- 车机 UI 当前使用 APS998 / ehub
- APS_DEVICE_TOKEN 不要写入 git，如缺失请到 server 上的 /home/ubuntu/aps_device_auth.envline 里查 APS998-ehub-ui
- 选终点后不一定立刻建 order；真实 createNavigation 时机在 /aps/depart-instruct 阶段
```

## 11. 这份文档的使用建议

如果后续继续维护：

1. 不要把密码和 token 写进 git 跟踪文件
2. 变更车机自启链路后，至少做一次真实 reboot 复验
3. 变更远端 order 逻辑后，必须同时做：
   - 车机本地代理接口验证
   - 服务器 `journalctl -u aps_remote_backend.service` 验证
4. 如果 Codex 要继续写这份文档，优先追加新节，不要把老结论无提示覆盖掉
