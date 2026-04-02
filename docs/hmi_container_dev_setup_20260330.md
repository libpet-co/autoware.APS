# hmi_container_dev Setup Notes

Date: 2026-03-30

This note records the local and remote setup work completed for `hmi_container_dev`, including HMI rebuild, UI/Nest alignment, Modbus recovery, and startup-application autostart on the remote vehicle host `libpet-aps@192.168.0.189`.

## Scope

- Local workspace root: `/home/libpet/autoware.APS`
- Remote workspace root: `/home/libpet-aps/autoware.APS`
- Local UI repo: `/home/libpet/APS_management_system_ui`
- Remote UI repo: `/home/libpet-aps/APS_management_system_ui`
- Local Nest repo: `/home/libpet/nestjs_test`
- Remote Nest repo: `/home/libpet-aps/nestjs_test`

## Branches And Revisions

Checked and aligned during this session:

- `autoware.APS`
  - branch: `hmi_container_dev`
  - remote commit seen during rebuild: `01ee9c5`
- `APS_management_system_ui`
  - branch: `hmi_container_dev`
  - aligned remote commit: `d7ecd4630ec68ad4d465fcc7daeb09677ea71651`
- `nestjs_test`
  - branch: `hmi_container_dev`
  - remote commit seen during inspection: `821d25b`

## Remote HMI Rebuild

Remote host already had the same `autoware.APS` branch and commit, so source sync was not required. The HMI-related packages were rebuilt in place:

```bash
cd ~/autoware.APS
colcon build \
  --packages-select aps_hmi_container autoware_launch \
  --cmake-force-configure \
  --symlink-install \
  --allow-overriding autoware_launch \
  --cmake-args -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release
```

Verification completed on the remote host:

- `ros2 pkg executables aps_hmi_container`
- `ros2 pkg prefix aps_hmi_container`
- `ros2 pkg prefix autoware_launch`
- executable bits checked for:
  - `~/autoware.APS/scripts/start_local_hmi_stack_fast.sh`
  - `~/autoware.APS/scripts/start_planning_simulator_hmi.sh`
  - `~/autoware.APS/scripts/stop_planning_simulator_hmi.sh`

Build log captured on the remote host:

- `~/build_hmi_remote_20260330_160527.log`

Note: `~/autoware.APS/install/setup.bash` still prints several non-blocking missing CUDA-related `local_setup.bash` warnings.

## Remote UI Alignment

Remote `APS_management_system_ui` was previously on `fw/dev`. It was aligned to the local `hmi_container_dev` branch:

```bash
cd ~/APS_management_system_ui
git fetch origin
git checkout -B hmi_container_dev origin/hmi_container_dev
npm run build
sudo systemctl restart aps_ui.service
```

Verification completed:

- `aps_ui.service` became `active (running)`
- `curl -I http://127.0.0.1:3001/aps/welcome` returned `200 OK`

## Remote Nest And Modbus Recovery

### Problem

`aps_nestapp.service` was blocked by `modbus_read.service` because the original hard-coded serial path disappeared:

- old path:
  - `/dev/serial/by-path/pci-0000:00:14.0-usb-0:3:1.0-port0`

After the USB device was reinserted, the stable available path was:

- `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`

### Fix

The serial-selection logic was updated to prefer:

1. `MODBUS_PORT`
2. stable `by-id`
3. legacy `by-path`
4. auto-pick a single matching USB serial candidate when unambiguous

Local source updated:

- `/home/libpet/LED_WS2812/tools/modbus_read.py`

The same logic was copied to the remote runtime script:

- `~/stm32/modbus_read.py`

Then the services were restarted:

```bash
sudo systemctl restart modbus_read.service
sudo systemctl restart aps_nestapp.service
```

Verification completed:

- `modbus_read.service` is `active (running)`
- `/tmp/vttyB` exists
- `aps_nestapp.service` is `active (running)`
- `http://127.0.0.1:3003/api/battery` is reachable

Known limitation:

- The serial port now opens correctly, but Modbus reads still show `RX (0 bytes)`, so the physical/protocol side is still not returning frames.

## Startup Application Autostart

### Requirement

Boot into the desktop session and automatically launch the vehicle HMI stack.

Current final target on the remote host:

- `~/autoware.APS/scripts/start_autoware_hmi.sh`

Historical note:

- earlier in the day this path still launched `start_local_hmi_stack_fast.sh`
  and `planning_simulator.launch.xml`

### What happened during debugging

The startup app was firing, but two independent problems prevented a successful result:

1. `start_planning_simulator_hmi.sh` treated the UI as not ready unless it was listening on an exact `127.0.0.1:3001` socket.
   - actual `aps_ui.service` listens on `*:3001`
   - fix: check `http://127.0.0.1:3001/aps/welcome` instead of exact socket binding
2. GNOME autostart is managed by `systemd-xdg-autostart-generator`
   - when the `.desktop` entry directly executed the script, systemd later reaped the child processes in the same cgroup after the wrapper exited
   - fix at that stage: keep Startup Applications as the trigger, but have it start a dedicated user service whose `ExecStart` was `start_local_hmi_stack_fast.sh`

### Local source adjustments recorded

These local source files were updated while fixing the readiness check:

- `/home/libpet/autoware.APS/scripts/start_local_hmi_stack.sh`
- `/home/libpet/autoware.APS/scripts/start_planning_simulator_hmi.sh`

### Remote autostart chain used during the initial planning-simulator phase

- Startup application desktop entry:
  - `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop`
- wrapper:
  - `~/bin/start_local_hmi_stack_fast_autostart.sh`
- user service:
  - `~/.config/systemd/user/aps-local-hmi-stack.service`
- real startup command:
  - `/home/libpet-aps/autoware.APS/scripts/start_local_hmi_stack_fast.sh`

### Verification

The exact startup-app path was manually replayed after the fix:

```bash
systemctl --user start app-start_local_hmi_stack_fast.sh@autostart.service
```

Confirmed afterward:

- `app-start_local_hmi_stack_fast.sh@autostart.service` triggered successfully
- `aps-local-hmi-stack.service` reached `active (exited)`
- child processes stayed alive:
  - `ros2 launch autoware_launch planning_simulator.launch.xml`
  - `aps_hmi_container`
  - frontend child
  - rviz child

### Later root cause found when reboot still did not autostart

After a subsequent real reboot, the reason was not the wrapper or HMI script itself. The autostart desktop entry had been left disabled:

- remote file:
  - `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop`
- problematic key:
  - `X-GNOME-Autostart-enabled=false`

Observed evidence after boot:

- `app-start_local_hmi_stack_fast.sh@autostart.service` existed as a generated unit but stayed `inactive (dead)`
- no entries were written this boot to:
  - `journalctl --user -b -u app-start_local_hmi_stack_fast.sh@autostart.service`
  - `journalctl --user -b -u aps-local-hmi-stack.service`
- `graphical-session.target` did not list:
  - `app-start_local_hmi_stack_fast.sh@autostart.service`
  - `aps-local-hmi-stack.service`
- `~/hmi_test/.log/startup_application.log` was last updated at `2026-03-30 18:01:11 +0800`, which was before the rebooted desktop session that started at `2026-03-30 18:14:34 +0800`

Conclusion:

- the graphical session never launched the autostart entry on that boot because the desktop file itself was disabled
- this is separate from the earlier readiness-check and cgroup-reaping problems, which had already been addressed

### Successful reboot verification afterward

After re-enabling the desktop file, a later real reboot was verified successfully.

Observed on the remote host:

- system boot time:
  - `2026-03-30 18:24:42 +0800`
- graphical desktop session:
  - `libpet-aps :0`
- autostart desktop entry still enabled:
  - `X-GNOME-Autostart-enabled=true`
- autostart wrapper log entry for this boot:
  - `===== 2026-03-30 18:25:07 APS Local HMI Stack autostart =====`
- HMI stack service reached:
  - `aps-local-hmi-stack.service active (exited)` since `2026-03-30 18:25:27 +0800`
- HMI process tree present after boot:
  - `planning_simulator.launch.xml`
  - `aps_hmi_container`
  - `QtWebEngineProcess`
- embedded frontend runtime confirmed:
  - `frontend load finished: ok=true`
  - `HMI loading gate satisfied; showing embedded HMI`

Conclusion:

- the reboot-time autostart path is now working end to end
- the remote machine is able to boot, auto-login, trigger Startup Applications, and bring up `start_local_hmi_stack_fast.sh` without manual intervention

### Later change: removed fixed 15-second autostart delay

The remote autostart path originally waited about 15 seconds after graphical login:

- desktop file:
  - `X-GNOME-Autostart-Delay=15`
- wrapper:
  - `sleep "${APS_HMI_AUTOSTART_DELAY_SEC:-15}"`

This was later changed to no fixed wait:

- desktop file:
  - `X-GNOME-Autostart-Delay=0`
- wrapper:
  - `sleep "${APS_HMI_AUTOSTART_DELAY_SEC:-0}"`

Live verification after the change:

- manual trigger time:
  - `2026-03-30 18:35:32 +0800`
- new autostart log entry time:
  - `2026-03-30 18:35:32 +0800`
- HMI stack service start time:
  - `2026-03-30 18:35:32 +0800`
- HMI stack service finish time:
  - `2026-03-30 18:35:37 +0800`

Conclusion:

- the fixed autostart delay has been removed
- startup now proceeds immediately after the graphical autostart entry is launched

### Later change: switched the remote autostart payload to `autoware.launch.xml`

To avoid patching the old planning-simulator flow in place, dedicated vehicle
entrypoints were added locally:

- `/home/libpet/autoware.APS/scripts/start_autoware_hmi.sh`
- `/home/libpet/autoware.APS/scripts/stop_autoware_hmi.sh`

The remote autostart chain keeps the same desktop-entry filename and wrapper,
but the user service now starts the new vehicle entrypoint instead:

- desktop entry:
  - `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop`
- wrapper:
  - `~/bin/start_local_hmi_stack_fast_autostart.sh`
- user service:
  - `~/.config/systemd/user/aps-local-hmi-stack.service`
- actual command now used by the user service:
  - `/home/libpet-aps/autoware.APS/scripts/start_autoware_hmi.sh`

Remote `aps-local-hmi-stack.service` now contains:

```ini
ExecStart=/usr/bin/bash -lc 'exec %h/autoware.APS/scripts/start_autoware_hmi.sh'
ExecStop=/usr/bin/bash -lc 'exec %h/autoware.APS/scripts/stop_autoware_hmi.sh'
```

The new script keeps the same map/model family as the earlier simulation-style
flow while switching the launch root to `autoware.launch.xml`:

- `use_sim_time:=false`
- `vehicle_model:=aps_vehicle`
- `sensor_model:=aps_sensor_kit`
- `sensor_config_profile:=aps998`
- `lanelet2_map_file:=frontway2.osm`
- `pointcloud_map_file:=front.pcd`
- `hmi_single_container:=true`
- `hmi_frontend_url:=http://127.0.0.1:3001/aps/welcome`

Remote verification after the switch:

- `aps-local-hmi-stack.service` became `active (exited)` at
  `2026-03-30 21:13:06 HKT`
- the running launch root changed to:
  - `ros2 launch autoware_launch autoware.launch.xml ...`
- HMI process tree includes:
  - `aps_hmi_container`
  - `QtWebEngineProcess`

One more regression was caught during this switch:

- `~/.config/autostart/start_local_hmi_stack_fast.sh.desktop` had again become
  `X-GNOME-Autostart-enabled=false`

This was corrected back to `true`, followed by `systemctl --user daemon-reload`
and a manual replay of:

```bash
systemctl --user start app-start_local_hmi_stack_fast.sh@autostart.service
```

Observed after re-enabling:

- generated unit:
  - `app-start_local_hmi_stack_fast.sh@autostart.service`
- start timestamp:
  - `2026-03-30 21:18:54 HKT`
- `~/hmi_test/.log/startup_application.log` gained a fresh autostart entry
  pointing to:
  - `ACTION=systemctl --user start aps-local-hmi-stack.service`

Current conclusion:

- the boot-time autostart chain should now bring up `autoware.launch.xml`,
  not `planning_simulator.launch.xml`
- the desktop entry must remain enabled:
  - `X-GNOME-Autostart-enabled=true`

Remote host also has GDM auto-login enabled:

- `AutomaticLoginEnable=true`
- `AutomaticLogin=libpet-aps`

## Current Remote UI Differences Vs Local

The remote UI build is not using the same `.env.local` values as the local workstation.

Local `/home/libpet/APS_management_system_ui/.env.local` includes:

- `NEXT_PUBLIC_MAP_PATH=/map_airport.svg`
- `NEXT_PUBLIC_MAP_REGION=HK`
- `NEXT_PUBLIC_APS_ID=APS555`
- `NEXT_PUBLIC_DEFAULT_WORK_ID=simulation`

Remote `~/APS_management_system_ui/.env.local` currently includes:

- `NEXT_PUBLIC_MAP_PATH=/map.svg`
- `NEXT_PUBLIC_MAP_REGION=ehub`
- `NEXT_PUBLIC_APS_ID=APS998`
- `NEXT_PUBLIC_DEFAULT_WORK_ID=ehub`

This means the remote UI is not expected to look or behave exactly like the local workstation, even on the same source branch.

## Dependency Findings

### Node dependencies

Local and remote `package.json` / `package-lock.json` hashes match for both UI and Nest:

- `APS_management_system_ui/package.json`
- `APS_management_system_ui/package-lock.json`
- `nestjs_test/package.json`
- `nestjs_test/package-lock.json`

Top-level installed versions also matched at inspection time:

- UI
  - `next@15.4.6`
  - `react@19.1.0`
  - `react-dom@19.1.0`
  - `i18next@25.5.2`
  - `styled-components@6.1.19`
  - `tailwindcss@4.1.13`
- Nest
  - `@nestjs/common@11.1.6`
  - `@nestjs/core@11.1.6`
  - `rxjs@7.8.2`
  - `kafkajs@2.2.4`
  - `serialport@13.0.0`
  - `rclnodejs@1.5.0`

Conclusion:

- No obvious Node dependency drift was found between local and remote.

### HMI Qt backend difference

This is the most important dependency-level difference found.

Local `aps_hmi_container` binary links against Qt WebEngine:

- `libQt5WebEngineWidgets.so.5`
- `libQt5WebEngine.so.5`

Remote `aps_hmi_container` binary links against Qt WebKit instead:

- `libQt5WebKitWidgets.so.5`
- `libQt5WebKit.so.5`

Important detail:

- the remote host does have both dev packages installed:
  - `qtwebengine5-dev`
  - `libqt5webkit5-dev`
- however, the remote CMake cache currently contains:
  - `APS_HMI_PREFER_WEBKIT:BOOL=ON`

That means the remote build is intentionally preferring WebKit even though WebEngine is available.

Why this matters:

- `aps_hmi_container` is designed to prefer WebEngine and only fall back to WebKit
- WebKit and WebEngine differ in rendering, JS/runtime behavior, and input handling
- this is a strong candidate explanation for the remote HMI feeling visually different from local and for embedded page interaction issues

### HMI Qt backend fix applied

The remote HMI was rebuilt again with WebEngine explicitly selected:

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

Verification after rebuild:

- remote `build/aps_hmi_container/CMakeCache.txt` now shows:
  - `APS_HMI_PREFER_WEBKIT:BOOL=OFF`
- remote `ldd` now links against:
  - `libQt5WebEngineWidgets.so.5`
  - `libQt5WebEngine.so.5`
  - `libQt5WebEngineCore.so.5`
- remote HMI stack was restarted and the embedded frontend finished loading successfully
- rebuild log on remote:
  - `~/build_hmi_webengine_20260330_180025.log`

Updated conclusion:

- the main dependency/configuration mismatch between local and remote has now been corrected
- if the remote page still looks different afterward, the next most likely cause is `.env.local` divergence rather than missing npm or Qt packages

### Shared-library/tool availability

No missing shared libraries were found in `ldd` for the built `aps_hmi_container` binary on either side.

Required runtime tools were present on both local and remote at inspection time:

- `xdotool`
- `wmctrl`
- `xinput`
- `curl`
- `node`
- `npm`
- `python3`
- `rg`

## Current Remote Button-State Findings

Remote backend status currently differs sharply from the local workstation:

- local `GET /api/vehicle/car-state`
  - route state: `ARRIVED`
  - current gate available
  - mission data available
- remote `GET /api/vehicle/car-state`
  - route state: `null` / `ROUTE_STATE_UNSET`
  - localization current position not ready
  - current gate unavailable
  - `updatedAt` is stale compared with local

This matters because the dispatch control button is intentionally disabled in the frontend when:

- vehicle UI state is not `DRIVE` or `STOP`
- waiting for initial status
- control is blocked by backend rules

Relevant frontend logic:

- `APS_management_system_ui/src/app/dispatch/page.tsx`
  - `waitingForStatus`
  - `backendToggleBlocked`
  - `btnDisabled`

So there are two separate classes of issue to keep apart:

1. visual/runtime difference from local:
   - caused by remote `.env.local` diverging from local
2. action buttons unavailable:
   - caused by remote vehicle/control/localization state not matching the conditions required to enable those buttons

## Touchscreen Status Snapshot

At inspection time on the remote host:

- the touch devices existed:
  - `ILITEK ILITEK-TP Mouse`
  - `ILITEK ILITEK-TP`
- the target display existed:
  - `DP-3 connected primary 1920x1080`
- the touch devices had a non-identity coordinate transform matrix already applied

This suggests the touchscreen mapping is present, but it does not by itself prove every touch event lands on the expected UI target. If touch still feels wrong, inspect `xinput test-xi2`, calibration, and physical panel mapping next.

## Recommended Next Checks

1. Decide whether remote UI should intentionally keep the `ehub`/`APS998` environment, or be aligned to the local `HK`/`APS555` environment.
2. If the dispatch buttons should be enabled, fix the remote vehicle state inputs first:
   - route state
   - localization readiness
   - current gate / mission freshness
3. If the issue is specifically physical touch and not frontend button state, test the touchscreen input path directly on the remote desktop session.
