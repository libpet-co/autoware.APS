## HMI Scripts

This directory contains local APS HMI orchestration scripts used for day-to-day
development and validation on top of the main `autoware.APS` workspace.

### Primary entrypoints

- `hmi_env.sh`
  Defines the shared runtime/log/cache directories used by the local HMI
  scripts.
- `start_local_hmi_stack_fast.sh`
  Convenience wrapper for the common local HMI flow with production frontend
  and microservice settings.
- `start_local_hmi_stack.sh`
  Starts the local APS frontend/backend stack together with Autoware
  `planning_simulator` and the HMI container.
- `stop_local_hmi_stack.sh`
  Stops the full local HMI stack started by `start_local_hmi_stack.sh`.
- `start_planning_simulator_hmi.sh`
  Starts `planning_simulator` plus the HMI container only.
- `stop_planning_simulator_hmi.sh`
  Stops the Autoware + HMI processes started by
  `start_planning_simulator_hmi.sh`.
- `start_autoware_hmi.sh`
  Starts standalone `aps_hmi_container` plus `autoware.launch.xml` for
  vehicle-style runtime validation.
- `stop_autoware_hmi.sh`
  Stops the Autoware + HMI processes started by `start_autoware_hmi.sh`.
- `build_hmi_launch_overlay.sh`
  Legacy compatibility wrapper. It now builds the main workspace HMI artifacts
  in `${APS_ROOT_DIR:-$HOME/autoware.APS}`, no longer creates an overlay
  workspace, and forces `aps_hmi_container` to build against Qt WebEngine
  instead of falling back to Qt WebKit from an old CMake cache.
- `install_user_hmi_autostart.sh`
  Installs the GNOME autostart desktop entry, wrapper script, and
  `aps-local-hmi-stack.service` assets for the current user.

### Autostart assets

The repo also carries the reusable user-session assets used on vehicle-style
machines under `./autostart/`:

- `autostart/start_local_hmi_stack_fast.sh.desktop`
- `autostart/start_local_hmi_stack_fast_autostart.sh`
- `autostart/aps-local-hmi-stack.service`
- `autostart/aps-local-hmi-stack.service.d/cpu-tuning.conf`

Install them with:

```bash
bash /root/autoware.APS/scripts/install_user_hmi_autostart.sh
```

If you need to keep the legacy desktop autostart entries in place while
testing, use:

```bash
bash /root/autoware.APS/scripts/install_user_hmi_autostart.sh --keep-legacy-autostart
```

### Optional preview helpers

These scripts are kept for preview-only workflows and are not required for the
current local stack flow driven by `./start_local_hmi_stack_fast.sh`.

- `start_hmi_ui_preview.sh`
- `start_hmi_launch_preview.sh`
- `stop_hmi_preview.sh`

### Assumptions

- The main workspace is available at `${APS_ROOT_DIR:-$HOME/autoware.APS}`.
- The APS frontend/backend repo is available at
  `${APS_FRONTEND_BACKEND_ROOT:-$HOME/APS_Frontend_Backend}`.
- Runtime state, logs, and PID files default to `${APS_HMI_TEST_ROOT:-$HOME/hmi_test}`.
- By default the scripts will try to inherit `APS_ROS_DOMAIN_ID` / `ROS_DOMAIN_ID`
  (and matching ROS middleware vars) from `~/.bashrc` when the current shell
  does not already export them. Disable this with `APS_HMI_IMPORT_SHELL_ROS_ENV=false`.
- ROS domain is optional. If you do not set `APS_ROS_DOMAIN_ID` or `ROS_DOMAIN_ID`,
  the scripts leave it unset and ROS will fall back to its default domain `0`.
- The GUI entrypoints auto-detect an X11 display when `DISPLAY` is unset and
  will try a minimal `gdm` `xhost` grant when started over SSH on machines that
  still expose the desktop on `:0`. Override with `APS_HMI_DISPLAY` and
  `APS_HMI_XAUTHORITY` if needed.

### Common flow

```bash
bash /root/autoware.APS/scripts/start_local_hmi_stack_fast.sh
```

If you want the non-fast entrypoint:

```bash
bash /root/autoware.APS/scripts/start_local_hmi_stack.sh
```

Stop the stack with:

```bash
bash /root/autoware.APS/scripts/stop_local_hmi_stack.sh
```

For the vehicle-style single-window HMI flow backed by
`autoware.launch.xml`, use:

```bash
bash /root/autoware.APS/scripts/start_autoware_hmi.sh
```

Stop that flow with:

```bash
bash /root/autoware.APS/scripts/stop_autoware_hmi.sh
```

To pin or reprioritize the detached HMI process separately from Autoware,
you can prepend launcher commands through environment variables, for example:

```bash
APS_HMI_LAUNCH_PREFIX='taskset -c 2-3 nice -n 5' \
APS_AUTOWARE_LAUNCH_PREFIX='taskset -c 0-1' \
bash /root/autoware.APS/scripts/start_autoware_hmi.sh
```
