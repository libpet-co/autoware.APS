#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def run_command(command_args: list[str]) -> None:
    result = subprocess.run(command_args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        print(f"Command failed: {' '.join(command_args)}\n{result.stdout}", file=sys.stderr)
        sys.exit(result.returncode)
    if result.stdout:
        print(result.stdout.strip())


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def copy_service_file(source: Path, destination_dir: Path) -> Path:
    destination = destination_dir / source.name
    shutil.copy2(source, destination)
    return destination


def enable_user_service(service_name: str) -> None:
    run_command(["systemctl", "--user", "daemon-reload"]) 
    run_command(["systemctl", "--user", "enable", "--now", service_name])


def enable_linger(username: str) -> None:
    # Use non-interactive sudo; if it fails, instruct the user.
    try:
        result = subprocess.run(
            ["sudo", "-n", "loginctl", "enable-linger", username],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if result.returncode != 0:
            print(
                "Warning: Could not enable linger non-interactively.\n"
                "If you want this user service to run at boot without login, run:\n"
                f"  sudo loginctl enable-linger {username}\n"
                f"Details:\n{result.stdout}",
                file=sys.stderr,
            )
        elif result.stdout:
            print(result.stdout.strip())
    except FileNotFoundError:
        print(
            "Warning: 'sudo' not found. Skipping linger. To enable later, run:\n"
            f"  loginctl enable-linger {username}",
            file=sys.stderr,
        )


def parse_args() -> argparse.Namespace:
    default_service_path = "/home/libpet/autoware.APS/script/autoware-simulation/autoware-simulation.service"
    parser = argparse.ArgumentParser(description="Install and enable Autoware user systemd service")
    parser.add_argument(
        "--service",
        default=default_service_path,
        help=f"Path to .service file (default: {default_service_path})",
    )
    parser.add_argument(
        "--username",
        default="libpet",
        help="Username to enable linger for (default: libpet)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    service_src = Path(args.service).expanduser().resolve()
    if not service_src.exists():
        print(f"Service file not found: {service_src}", file=sys.stderr)
        sys.exit(1)

    user_systemd_dir = Path.home() / ".config" / "systemd" / "user"
    ensure_directory(user_systemd_dir)

    copied_path = copy_service_file(service_src, user_systemd_dir)
    print(f"Installed service to: {copied_path}")

    service_name = copied_path.name
    enable_user_service(service_name)
    print(f"Enabled and started user service: {service_name}")

    enable_linger(args.username)

    print("Done. You can check status with:\n  systemctl --user status autoware-simulation.service")


if __name__ == "__main__":
    main()


