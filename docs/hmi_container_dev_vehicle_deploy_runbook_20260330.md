# hmi_container_dev 车辆部署与开机自启操作手册

Date: 2026-03-30

## 文档目的

这份文档用于记录本次 `hmi_container_dev` 在车辆 `libpet-aps@192.168.0.189` 上从部署、依赖修正、UI/Nest 对齐，到开机自启配置与复验的完整过程。

目标有两个：

1. 后续人工可以按这份文档直接复现。
2. 后续可以把这份文档直接喂给 Codex，让它快速接上当前上下文继续处理。

说明：

- 文档里保留了主机、路径、分支、命令、日志位置、已知问题和修复原因。
- SSH 密码不写入文档，避免把明文凭据留在仓库里。

## 适用范围

- 本地开发机用户：`libpet`
- 远端车辆用户：`libpet-aps`
- 远端车辆 IP：`192.168.0.189`
- 本地时区：`Asia/Shanghai`
- 远端系统：`Ubuntu 22.04.5 LTS`

## 仓库与路径映射

本地：

- `autoware.APS`
  - `/home/libpet/autoware.APS`
- `APS_management_system_ui`
  - `/home/libpet/APS_management_system_ui`
- `nestjs_test`
  - `/home/libpet/nestjs_test`
- `LED_WS2812`
  - `/home/libpet/LED_WS2812`

远端：

- `autoware.APS`
  - `/home/libpet-aps/autoware.APS`
- `APS_management_system_ui`
  - `/home/libpet-aps/APS_management_system_ui`
- `nestjs_test`
  - `/home/libpet-aps/nestjs_test`
- `stm32 runtime script`
  - `/home/libpet-aps/stm32/modbus_read.py`

## 本次部署的最终目标状态

本次处理完成后，远端应该满足以下状态：

1. `autoware.APS` 在 `hmi_container_dev`
2. `APS_management_system_ui` 在 `hmi_container_dev`
3. `nestjs_test` 在 `hmi_container_dev`
4. `aps_hmi_container` 使用 Qt WebEngine，而不是 Qt WebKit
5. `aps_ui.service` 正常运行
6. `modbus_read.service` 正常运行
7. `aps_nestapp.service` 正常运行
8. 图形桌面自动登录后，立即通过 Startup Applications 拉起
   `aps-local-hmi-stack.service`
9. `aps-local-hmi-stack.service` 实际执行：
   - `/home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh`

## 本次已确认的版本信息

当时检查到的分支/提交如下：

- `autoware.APS`
  - branch: `hmi_container_dev`
  - remote commit seen during rebuild: `01ee9c5`
- `APS_management_system_ui`
  - branch: `hmi_container_dev`
  - aligned remote commit: `d7ecd4630ec68ad4d465fcc7daeb09677ea71651`
- `nestjs_test`
  - branch: `hmi_container_dev`
  - remote commit seen during inspection: `821d25b`

后续再次部署时，不要盲信这些提交号，建议重新检查本地与远端是否一致。

## 一、开始前建议先做的检查

### 1. 本地检查

建议先在本地记录三个仓库的分支、提交、工作区状态：

```bash
cd /home/libpet/autoware.APS && git branch --show-current && git rev-parse --short HEAD && git status --short
cd /home/libpet/APS_management_system_ui && git branch --show-current && git rev-parse --short HEAD && git status --short
cd /home/libpet/nestjs_test && git branch --show-current && git rev-parse --short HEAD && git status --short
```

### 2. 远端连通性检查

```bash
ping -c 2 192.168.0.189
ssh libpet-aps@192.168.0.189
```

如果 `ssh` 报 `No route to host`，先不要继续判断 HMI 自启，优先确认：

- 车端是否已经连上网络
- 车端是否还是原来的 `192.168.0.189`
- 车端是否已经进入桌面
- `sshd` 是否已启动

## 二、远端 HMI 基础重编译

### 背景

第一次检查时，远端 `autoware.APS` 已经在同一分支/提交，所以不需要先同步源码，直接在远端重编 HMI 相关产物。

### 命令

```bash
ssh libpet-aps@192.168.0.189
cd ~/autoware.APS

colcon build \
  --packages-select aps_hmi_container autoware_launch \
  --cmake-force-configure \
  --symlink-install \
  --allow-overriding autoware_launch \
  --cmake-args \
    -DBUILD_TESTING=OFF \
    -DCMAKE_BUILD_TYPE=Release
```

### 验证

```bash
source ~/autoware.APS/install/setup.bash
ros2 pkg executables aps_hmi_container
ros2 pkg prefix aps_hmi_container
ros2 pkg prefix autoware_launch
ls -l ~/autoware.APS/scripts/start_local_hmi_stack_fast.sh
ls -l ~/autoware.APS/scripts/start_autoware_hmi.sh
ls -l ~/autoware.APS/scripts/stop_autoware_hmi.sh
ls -l ~/autoware.APS/scripts/start_planning_simulator_hmi.sh
ls -l ~/autoware.APS/scripts/stop_planning_simulator_hmi.sh
```

### 备注

- 当时远端构建日志记录在：
  - `~/build_hmi_remote_20260330_160527.log`
- `install/setup.bash` 里有几条旧的 CUDA 相关 warning，但没有阻塞 HMI 构建。

## 三、远端 UI 对齐到本地 hmi_container_dev

### 背景

远端 `APS_management_system_ui` 当时还在旧分支 `fw/dev`，必须先切到本地正在开发的 `hmi_container_dev`，否则页面样式和功能会偏离本机。

### 命令

```bash
ssh libpet-aps@192.168.0.189
cd ~/APS_management_system_ui

git fetch origin
git checkout -B hmi_container_dev origin/hmi_container_dev
npm run build
sudo systemctl restart aps_ui.service
```

### 验证

```bash
git branch --show-current
git rev-parse HEAD
sudo systemctl status aps_ui.service --no-pager -l
curl -I http://127.0.0.1:3001/aps/welcome
```

### 结论

- 远端 UI 代码必须和本地分支一致，否则页面会看起来像“部署过了但还是旧版”。

## 四、远端 Nest 与 Modbus 修复

### 背景

远端 `aps_nestapp.service` 最初没有起来，不是因为 Nest 代码本身坏了，而是被 `modbus_read.service` 依赖链卡住。

根因是原来脚本里硬编码的串口路径丢失了：

- 旧路径：
  - `/dev/serial/by-path/pci-0000:00:14.0-usb-0:3:1.0-port0`

重新插设备后，当时实际存在的是：

- 新路径：
  - `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`

### 修复思路

把串口选择逻辑改成优先级如下：

1. `MODBUS_PORT`
2. `by-id`
3. `by-path`
4. 当只有一个明确 USB 串口候选时自动选它

### 修改位置

本地源码：

- `/home/libpet/LED_WS2812/tools/modbus_read.py`

远端运行脚本：

- `/home/libpet-aps/stm32/modbus_read.py`

### 服务重启

```bash
ssh libpet-aps@192.168.0.189
sudo systemctl restart modbus_read.service
sudo systemctl restart aps_nestapp.service
```

### 验证

```bash
sudo systemctl status modbus_read.service --no-pager -l
sudo systemctl status aps_nestapp.service --no-pager -l
ls -l /tmp/vttyB
curl http://127.0.0.1:3003/api/battery
```

### 已知现象

- 串口路径问题修好了以后，服务可以起来。
- 但当时仍然存在 `RX (0 bytes)`，表示物理层/协议层是否有回包还要继续看，不再是“找不到串口设备”的问题。

## 五、HMI 依赖修正：强制远端改回 Qt WebEngine

### 背景

虽然远端 Qt 相关开发包都装了，但远端 HMI 实际构建出来用的是 Qt WebKit，而本地用的是 Qt WebEngine。

这是一个非常关键的差异，因为：

- 页面样式可能不同
- JS/runtime 行为可能不同
- HMI 内嵌页面交互可能不同

### 源码依据

本地源码已经明确说明：

- `aps_hmi_container` 优先 `Qt WebEngine`
- 只有回退时才用 `Qt WebKit`

对应源码位置：

- `/home/libpet/autoware.APS/src/launcher/autoware_launch_APS/aps_hmi_container/README.md`
- `/home/libpet/autoware.APS/src/launcher/autoware_launch_APS/aps_hmi_container/CMakeLists.txt`

### 当时发现的问题

远端构建缓存里有：

```text
APS_HMI_PREFER_WEBKIT:BOOL=ON
```

这意味着远端不是“缺少 WebEngine”，而是“构建时主动偏向了 WebKit”。

### 修复命令

```bash
ssh libpet-aps@192.168.0.189
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

### 验证

```bash
grep APS_HMI_PREFER_WEBKIT ~/autoware.APS/build/aps_hmi_container/CMakeCache.txt
ldd ~/autoware.APS/install/aps_hmi_container/lib/aps_hmi_container/aps_hmi_container | rg 'WebEngine|WebKit'
systemctl --user restart aps-local-hmi-stack.service
tail -n 80 ~/hmi_test/.log/hmi_container.log
```

### 正确结果

应该看到：

- `APS_HMI_PREFER_WEBKIT:BOOL=OFF`
- `ldd` 里链接到：
  - `libQt5WebEngineWidgets.so.5`
  - `libQt5WebEngine.so.5`
  - `libQt5WebEngineCore.so.5`

### 当时日志

- `~/build_hmi_webengine_20260330_180025.log`

## 六、本次与开机自启有关的本地源码修复

### 背景

最初“手动运行能起、开机自启起不来”并不是单一原因，而是多个问题叠加。

### 1. UI readiness 判断过严

原脚本要求 UI 必须监听在“精确的 `127.0.0.1:3001` socket”上，才认定页面已经准备好。

但实际 UI 服务可能是监听在：

- `*:3001`

这样虽然浏览器能访问，脚本却误判“UI 没起来”。

### 本地修复文件

- `/home/libpet/autoware.APS/scripts/start_local_hmi_stack.sh`
- `/home/libpet/autoware.APS/scripts/start_planning_simulator_hmi.sh`

### 修复思路

把 readiness check 改成直接探测：

- `http://127.0.0.1:3001/aps/welcome`

而不是依赖精确 socket 绑定形式。

## 七、远端开机自启最终方案

### 最终要求

车辆进入桌面后自动执行：

- `/home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh`

说明：

- `.desktop` 文件名和 wrapper 名仍然沿用旧名字
- 但真正被 `aps-local-hmi-stack.service` 执行的脚本已经切到
  `start_autoware_hmi.sh`
- 这样可以少改 GNOME Startup Applications 现有入口，同时把真实启动
  根切到 `autoware.launch.xml`

### 为什么不能只在 Startup Applications 里直接写脚本

GNOME autostart 在 Ubuntu 22.04 上由 `systemd-xdg-autostart-generator` 参与管理。

如果 `.desktop` 直接跑脚本，脚本退出后，子进程可能还留在同一个 cgroup 里，随后被 systemd 回收。

所以最终采用：

1. Startup Applications 只负责触发 wrapper
2. wrapper 再调用一个独立的 `systemd --user` service
3. 真正执行命令改为 `start_autoware_hmi.sh`

### 本次切换到 `autoware.launch.xml` 的具体做法

为了不直接把原来的仿真脚本改坏，这次没有强行修改
`start_planning_simulator_hmi.sh`，而是新建了专用入口：

- 本地新增：
  - `/home/libpet/autoware.APS/scripts/start_autoware_hmi.sh`
  - `/home/libpet/autoware.APS/scripts/stop_autoware_hmi.sh`
- 远端同步后使用：
  - `/home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh`
  - `/home/libpet-aps/autoware.APS/scripts/stop_autoware_hmi.sh`

新脚本做的事是：

1. 先等待本地 UI `http://127.0.0.1:3001/aps/welcome` 可访问
2. 再起 `ros2 launch autoware_launch autoware.launch.xml`
3. 同时通过 `hmi_single_container:=true` 把 HMI 单窗口模式一起带起来
4. 日志写到：
   - `~/hmi_test/.log/autoware_launch_hmi.log`
5. 停止时用：
   - `stop_autoware_hmi.sh`

这次按“真车用的和仿真用的一样”的要求，沿用了同一套地图/车型/传感器
参数族，当前脚本默认值是：

- `vehicle_model:=aps_vehicle`
- `sensor_model:=aps_sensor_kit`
- `sensor_config_profile:=aps998`
- `lanelet2_map_file:=frontway2.osm`
- `pointcloud_map_file:=front.pcd`
- `hmi_frontend_url:=http://127.0.0.1:3001/aps/welcome`
- `hmi_single_container:=true`
- `hmi_single_fullscreen:=true`
- `hmi_rviz_ratio:=30`

补充说明：

- 我这里把“和仿真一样”落实为“沿用同一套地图/车型/传感器文件”
- `use_sim_time` 仍然保持 `false`，因为当前目标是车端自启而不是 ROS 仿真时钟

### 最终链路

远端最终使用如下链路：

- Startup Applications desktop entry
  - `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop`
- wrapper
  - `~/bin/start_local_hmi_stack_fast_autostart.sh`
- user service
  - `~/.config/systemd/user/aps-local-hmi-stack.service`
- 实际启动脚本
  - `/home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh`

### 最终配置要点

#### 1. desktop entry

核心字段应该是：

```ini
[Desktop Entry]
Type=Application
Version=1.0
Name=APS Local HMI Stack
Comment=Start local HMI stack after graphical login
Exec=/home/libpet-aps/bin/start_local_hmi_stack_fast_autostart.sh
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=0
```

注意：

- `X-GNOME-Autostart-enabled=true` 非常关键
- 之前有一次失败就是因为这个值被写成了 `false`

#### 2. wrapper

关键行为：

- 写入 `startup_application.log`
- 不再固定等待 15 秒
- 直接调用：
  - `systemctl --user start aps-local-hmi-stack.service`

#### 3. user service

核心思路：

- `ExecStart` 现在是：
  - `%h/autoware.APS/scripts/start_autoware_hmi.sh`
- `ExecStop` 现在是：
  - `%h/autoware.APS/scripts/stop_autoware_hmi.sh`
- 日志追加到：
  - `%h/hmi_test/.log/startup_application.log`

当前远端 service 实际内容如下：

```ini
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=%h
Environment=APS_HMI_WAIT_UI_SEC=180
ExecStart=/usr/bin/bash -lc 'exec %h/autoware.APS/scripts/start_autoware_hmi.sh'
ExecStop=/usr/bin/bash -lc 'exec %h/autoware.APS/scripts/stop_autoware_hmi.sh'
StandardOutput=append:%h/hmi_test/.log/startup_application.log
StandardError=append:%h/hmi_test/.log/startup_application.log
TimeoutStartSec=0
```

### 建议检查命令

```bash
ssh libpet-aps@192.168.0.189
sed -n '1,120p' ~/.config/autostart/start_local_hmi_stack_fast.sh.desktop
sed -n '1,120p' ~/bin/start_local_hmi_stack_fast_autostart.sh
systemctl --user cat aps-local-hmi-stack.service
```

## 八、曾经出现过的开机自启失败原因

这部分很重要，后续如果 Codex 再遇到“开机没起来”，优先按这里排查。

### 失败原因 1：UI readiness 误判

现象：

- 脚本日志提示 UI 没起来
- 但实际上浏览器访问 `3001` 正常

原因：

- 旧脚本只认固定 socket 绑定，不认实际 HTTP 可用

解决：

- 改成探测 `http://127.0.0.1:3001/aps/welcome`

### 失败原因 2：GNOME autostart 触发后，子进程被回收

现象：

- 自启动项触发过
- 但 HMI/Autoware 子进程很快消失

原因：

- `.desktop` 直接执行脚本，脚本结束后 cgroup 里的子进程被 systemd 回收

解决：

- 用 Startup Applications 触发 wrapper
- wrapper 再 `start` 独立的 `systemd --user` service

### 失败原因 3：desktop entry 被禁用

现象：

- 真实 reboot 后完全没触发
- `journalctl --user -b` 对应 unit 没记录
- `startup_application.log` 时间戳停留在旧启动

原因：

- `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop` 里写成了：
  - `X-GNOME-Autostart-enabled=false`

解决：

- 改回：
  - `X-GNOME-Autostart-enabled=true`

### 失败原因 4：固定等待 15 秒

现象：

- 自启动不是“立刻跑”，而是桌面起来后还要额外等

原因：

- desktop file 里：
  - `X-GNOME-Autostart-Delay=15`
- wrapper 里：
  - `sleep "${APS_HMI_AUTOSTART_DELAY_SEC:-15}"`

处理：

- 后来都改成了 `0`

## 九、开机自启成功的验证标准

### 历史上第一次成功复验时看到的现象

在一次真实 reboot 后，检查到：

- system boot time:
  - `2026-03-30 18:24:42 +0800`
- 图形桌面会话存在：
  - `libpet-aps :0`
- autostart 日志新记录：
  - `2026-03-30 18:25:07 APS Local HMI Stack autostart`
- `aps-local-hmi-stack.service` 成功：
  - `active (exited)`
- 进程存在：
  - `planning_simulator.launch.xml`
  - `aps_hmi_container`
  - `QtWebEngineProcess`
- HMI 日志存在：
  - `frontend load finished: ok=true`
  - `HMI loading gate satisfied; showing embedded HMI`

### 当前最终方案切到 `autoware.launch.xml` 后的验证

切换到新的 vehicle 自启脚本后，当前远端实际检查到：

- `aps-local-hmi-stack.service` 状态：
  - `active (exited)`
- service 最近一次成功启动时间：
  - `2026-03-30 21:13:06 HKT`
- 进程根已经变成：
  - `ros2 launch autoware_launch autoware.launch.xml`
- HMI 相关子进程存在：
  - `aps_hmi_container`
  - `QtWebEngineProcess`
- 重新启用 `.desktop` 后，手动重放 autostart：
  - `systemctl --user start app-start_local_hmi_stack_fast.sh@autostart.service`
- 新的 autostart 日志时间：
  - `2026-03-30 21:18:54 HKT`

这说明：

- 现在的自启链路已经切到 `autoware.launch.xml`
- 但“切换后的完整整机 reboot 复验”还没有单独再做一次
- 如果下次要做最终验收，建议在真实 reboot 后再跑一遍下面的检查命令

### 标准检查命令

```bash
ssh libpet-aps@192.168.0.189

date '+%F %T %Z'
who -b
who

systemctl --user --no-pager --full status 'app-start_local_hmi_stack_fast.sh@autostart.service' || true
systemctl --user --no-pager --full status aps-local-hmi-stack.service || true

journalctl --user --no-pager -b \
  -u 'app-start_local_hmi_stack_fast.sh@autostart.service' \
  -u aps-local-hmi-stack.service -n 120

tail -n 80 ~/hmi_test/.log/startup_application.log
tail -n 80 ~/hmi_test/.log/hmi_container.log
tail -n 80 ~/hmi_test/.log/autoware_launch_hmi.log

ps -ef | rg 'autoware.launch.xml|planning_simulator.launch.xml|aps_hmi_container --frontend-url|QtWebEngineProcess'
```

## 十、当前仍需注意的非自启问题

### 1. 远端 UI 样式和本机不同，不一定是部署失败

本地 `.env.local` 和远端 `.env.local` 不一样。

本地当时是：

- `NEXT_PUBLIC_MAP_PATH=/map_airport.svg`
- `NEXT_PUBLIC_MAP_REGION=HK`
- `NEXT_PUBLIC_APS_ID=APS555`
- `NEXT_PUBLIC_DEFAULT_WORK_ID=simulation`

远端当时是：

- `NEXT_PUBLIC_MAP_PATH=/map.svg`
- `NEXT_PUBLIC_MAP_REGION=ehub`
- `NEXT_PUBLIC_APS_ID=APS998`
- `NEXT_PUBLIC_DEFAULT_WORK_ID=ehub`

这会导致页面看起来和本机不完全一样。

### 2. 车辆按钮按不了，不一定是前端坏了

当时分析到远端按钮不可用更像是业务状态禁用，而不是页面点不了。

远端状态曾出现：

- `ROUTE_STATE_UNSET`
- localization `ready=false`
- `currentGate=null`

而前端代码会在这些条件下主动 `disabled` 按钮。

### 3. WebEngine/WebKit 差异已经修正

如果后面又出现“页面看着怪、嵌入交互不对”，先重新确认远端有没有又被编回 WebKit。

## 十一、建议保存的关键日志位置

远端：

- HMI 首次重编日志
  - `~/build_hmi_remote_20260330_160527.log`
- HMI WebEngine 重编日志
  - `~/build_hmi_webengine_20260330_180025.log`
- 自启动日志
  - `~/hmi_test/.log/startup_application.log`
- HMI 运行日志
  - `~/hmi_test/.log/hmi_container.log`
- autoware 车端自启日志
  - `~/hmi_test/.log/autoware_launch_hmi.log`
- planning simulator 日志
  - `~/hmi_test/.log/planning_simulator.log`

## 十二、后续再让 Codex 接手时，建议直接给它的上下文

可以把下面这段直接发给 Codex：

```text
我现在在处理车辆 192.168.0.189 上的 hmi_container_dev 部署。请先看文档：
/home/libpet/autoware.APS/docs/hmi_container_dev_vehicle_deploy_runbook_20260330.md

已知信息：
- 远端用户是 libpet-aps
- autoware.APS、APS_management_system_ui、nestjs_test 都应该对齐到 hmi_container_dev
- 远端 HMI 必须用 Qt WebEngine，不要退回 Qt WebKit
- Startup Applications 通过 wrapper + systemd --user service 间接拉起，不是直接跑脚本
- desktop entry 文件名仍然是 start_local_hmi_stack_fast.sh.desktop
- 但 aps-local-hmi-stack.service 的实际 ExecStart 必须是 /home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh
- desktop file 必须是 X-GNOME-Autostart-enabled=true
- 现在固定 15 秒延迟已经取消，Delay 和 wrapper sleep 都应为 0

请先检查：
1. 当前网络和 SSH 是否可达
2. 本次 boot 的 autostart 和 aps-local-hmi-stack.service 状态
3. HMI 是否实际起来，以及当前跑的是 autoware.launch.xml 还是 planning_simulator.launch.xml
4. UI / Nest / Modbus 是否还在正确状态

不要先改代码，先根据这份文档和当前机器状态做核对，再决定下一步。
```

## 十三、如果下次要重新走一遍，最短操作顺序

如果只是重新部署一台相同环境的车，建议按下面顺序执行：

1. 检查本地三个仓库的分支和提交。
2. SSH 上车，确认远端网络和桌面会话正常。
3. 对齐远端 `autoware.APS`、`APS_management_system_ui`、`nestjs_test` 分支。
4. 重编远端 HMI。
5. 确认远端 HMI 是 Qt WebEngine。
6. 重建 UI 并重启 `aps_ui.service`。
7. 检查 `modbus_read.service` 和 `aps_nestapp.service`。
8. 检查 autostart 的 `.desktop`、wrapper、user service 三段链路。
9. 真实 reboot 后，用第九节的命令做复验。

## 关联文档

本次还有一份较短的英文记录，可一起参考：

- `/home/libpet/autoware.APS/docs/hmi_container_dev_setup_20260330.md`
