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
- `build_hmi_launch_overlay.sh`
  Builds the overlay workspace at
  `${APS_HMI_OVERLAY_WS:-$HOME/autoware.APS_hmi_overlay_ws}`.

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
- The HMI overlay workspace is available at
  `${APS_HMI_OVERLAY_WS:-$HOME/autoware.APS_hmi_overlay_ws}`.
- Runtime state, logs, and PID files default to `${APS_HMI_TEST_ROOT:-$HOME/hmi_test}`.
- By default the scripts will try to inherit `APS_ROS_DOMAIN_ID` / `ROS_DOMAIN_ID`
  (and matching ROS middleware vars) from `~/.bashrc` when the current shell
  does not already export them. Disable this with `APS_HMI_IMPORT_SHELL_ROS_ENV=false`.
- ROS domain is optional. If you do not set `APS_ROS_DOMAIN_ID` or `ROS_DOMAIN_ID`,
  the scripts leave it unset and ROS will fall back to its default domain `0`.

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
