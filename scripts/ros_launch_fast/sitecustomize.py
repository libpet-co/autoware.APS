"""Optional ROS launch startup patch for APS cold boot.

ROS 2 launch performs a best-effort recursive scan for missing arguments on
every IncludeLaunchDescription. Autoware's nested launch tree contains many
context-dependent includes, so that preflight scan repeatedly tries to load
files without the context they require and can burn tens of seconds before the
first process is spawned.

The patch is enabled only for the parent ros2 launch process when
APS_FAST_ROS_LAUNCH_INCLUDE=1 is present. It preserves the real launch argument
SetLaunchConfiguration actions and only skips the early diagnostics pass.
"""

import os


def _remove_self_from_child_pythonpath() -> None:
    this_dir = os.path.abspath(os.path.dirname(__file__))
    pythonpath = os.environ.get("PYTHONPATH", "")
    if not pythonpath:
        return

    paths = [p for p in pythonpath.split(os.pathsep) if p]
    filtered = [p for p in paths if os.path.abspath(p) != this_dir]
    if filtered:
        os.environ["PYTHONPATH"] = os.pathsep.join(filtered)
    else:
        os.environ.pop("PYTHONPATH", None)


def _install_fast_include_execute() -> None:
    from launch.actions.include_launch_description import IncludeLaunchDescription
    from launch.actions.set_launch_configuration import SetLaunchConfiguration

    def _fast_execute(self, context):
        launch_description = self.launch_description_source.get_launch_description(context)
        context.extend_locals({"current_launch_file_path": self._get_launch_file()})
        context.extend_locals({"current_launch_file_directory": self._get_launch_file_directory()})
        set_launch_configuration_actions = [
            SetLaunchConfiguration(name, value)
            for name, value in self.launch_arguments
        ]
        return [*set_launch_configuration_actions, launch_description]

    IncludeLaunchDescription.execute = _fast_execute


if os.environ.pop("APS_FAST_ROS_LAUNCH_INCLUDE", "") == "1":
    _remove_self_from_child_pythonpath()
    try:
        _install_fast_include_execute()
    except Exception as exc:  # pragma: no cover - diagnostic fallback only
        os.environ["APS_FAST_ROS_LAUNCH_INCLUDE_ERROR"] = str(exc)
