#!/usr/bin/env bash
source /home/libpet/autoware.APS/install/setup.bash
cd /home/libpet/autoware.APS
ros2 launch autoware_launch planning_simulator.launch.xml map_path:=/home/libpet/test_map
