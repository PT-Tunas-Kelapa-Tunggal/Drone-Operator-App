#!/usr/bin/env python3
"""
ArduPilot SITL Fault & Scenario Controller
Connects to ArduCopter SITL via MAVLink and provides:
1. Live telemetry & status reporting
2. Parameter inspection and live modification
3. Pre-configured hardware & environmental fault injection
4. Transparent bidirectional MAVLink router (SITL TCP 5760 <-> QGC UDP 14550 + CLI UDP 14551)
"""

import argparse
import select
import socket
import sys
import time

try:
    from pymavlink import mavutil
except ImportError:
    print("Error: pymavlink not found. Please run within the simulator venv or install pymavlink.")
    sys.exit(1)


SCENARIOS = {
    "healthy": {
        "description": "Restore full health (6S 25.2V battery, healthy motors, compass, GPS, RC, no wind)",
        "params": {
            "SIM_BATT_VOLTAGE": 25.2,
            "SIM_ENGINE_FAIL": 0.0,
            "SIM_ENGINE_MUL": 1.0,
            "SIM_MAG_ERROR": 0.0,
            "SIM_GPS_DISABLE": 0.0,
            "SIM_RC_FAIL": 0.0,
            "SIM_WIND_SPD": 0.0,
            "SIM_WIND_TURB": 0.0,
        },
    },
    "low-battery": {
        "description": "Simulate low battery (~3.53V/cell, 21.2V total on 6S)",
        "params": {
            "SIM_BATT_VOLTAGE": 21.2,
        },
    },
    "critical-battery": {
        "description": "Simulate critical battery (<3.3V/cell, 9.8V total on 6S, triggers failsafe RTL/Land)",
        "params": {
            "SIM_BATT_VOLTAGE": 9.8,
        },
    },
    "motor-fail": {
        "description": "Simulate motor / propulsion failure (cuts thrust to motor 1)",
        "params": {
            "SIM_ENGINE_FAIL": 1.0,
            "SIM_ENGINE_MUL": 0.0,
        },
    },
    "compass-fail": {
        "description": "Simulate compass / magnetometer inconsistency or failure",
        "params": {
            "SIM_MAG_ERROR": 1.0,
        },
    },
    "gps-lost": {
        "description": "Simulate total GPS signal loss (satellites drop, HDOP fails)",
        "params": {
            "SIM_GPS_DISABLE": 1.0,
        },
    },
    "rc-lost": {
        "description": "Simulate RC receiver loss (triggers RC failsafe)",
        "params": {
            "SIM_RC_FAIL": 1.0,
        },
    },
    "high-wind": {
        "description": "Simulate strong plantation wind (12 m/s wind with 2.5 m/s turbulence)",
        "params": {
            "SIM_WIND_SPD": 12.0,
            "SIM_WIND_TURB": 2.5,
        },
    },
}


def connect_mavlink(target=None, timeout=4.0):
    candidates = []
    if target:
        candidates.append(target)
    else:
        # Prefer the UDP bridge listener if running; fall back to direct TCP 5760
        candidates = ["udpin:127.0.0.1:14551", "tcp:127.0.0.1:5760"]

    for cand in candidates:
        try:
            print(f"Connecting to SITL at {cand}...")
            master = mavutil.mavlink_connection(cand)
            start = time.time()
            while time.time() - start < timeout:
                msg = master.recv_match(type="HEARTBEAT", blocking=True, timeout=1.0)
                if msg:
                    mode = mavutil.mode_string_v10(msg)
                    print(f"Connected to System {master.target_system}, Component {master.target_component} (Mode: {mode})")
                    return master
        except Exception:
            pass

    print("Error: Could not connect to ArduCopter SITL. Is the simulator running?")
    sys.exit(1)


def get_param(master, param_name, timeout=3.0):
    name_bytes = param_name.encode("utf-8")
    master.mav.param_request_read_send(
        master.target_system, master.target_component, name_bytes, -1
    )
    start = time.time()
    while time.time() - start < timeout:
        msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if msg and msg.param_id.rstrip("\x00") == param_name:
            return msg.param_value
    return None


def set_param(master, param_name, value, timeout=3.0):
    name_bytes = param_name.encode("utf-8")
    master.mav.param_set_send(
        master.target_system,
        master.target_component,
        name_bytes,
        float(value),
        mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
    )
    start = time.time()
    while time.time() - start < timeout:
        msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if msg and msg.param_id.rstrip("\x00") == param_name:
            return msg.param_value
    return None


def cmd_status(master):
    print("\n--- Live Drone Simulator Status ---")
    hb = master.recv_match(type="HEARTBEAT", blocking=True, timeout=2.0)
    armed = bool(hb.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED) if hb else False
    mode = mavutil.mode_string_v10(hb) if hb else "Unknown"

    sys_status = master.recv_match(type="SYS_STATUS", blocking=True, timeout=2.0)
    voltage = (sys_status.voltage_battery / 1000.0) if sys_status and sys_status.voltage_battery != 65535 else None
    remaining = sys_status.battery_remaining if sys_status and sys_status.battery_remaining != -1 else None

    gps = master.recv_match(type="GPS_RAW_INT", blocking=True, timeout=2.0)
    sats = gps.satellites_visible if gps else "N/A"
    fix_type = gps.fix_type if gps else 0

    hud = master.recv_match(type="VFR_HUD", blocking=True, timeout=2.0)
    alt = hud.alt if hud else 0.0
    spd = hud.groundspeed if hud else 0.0
    heading = hud.heading if hud else 0

    print(f"  Mode           : {mode} ({'ARMED' if armed else 'DISARMED'})")
    if voltage is not None:
        rem_str = f" ({remaining}%)" if remaining is not None else ""
        print(f"  Battery        : {voltage:.2f}V{rem_str}")
    print(f"  GPS Fix        : Type {fix_type} ({sats} satellites)")
    print(f"  Altitude       : {alt:.1f} m")
    print(f"  Ground Speed   : {spd:.1f} m/s")
    print(f"  Heading        : {heading}°")

    # Fault parameters
    print("\n--- Simulation Parameters ---")
    sim_batt = get_param(master, "SIM_BATT_VOLTAGE")
    sim_eng = get_param(master, "SIM_ENGINE_FAIL")
    sim_mag = get_param(master, "SIM_MAG_ERROR")
    sim_gps = get_param(master, "SIM_GPS_DISABLE")
    sim_rc = get_param(master, "SIM_RC_FAIL")
    sim_wind = get_param(master, "SIM_WIND_SPD")

    print(f"  SIM_BATT_VOLTAGE : {sim_batt:.2f}V" if sim_batt is not None else "  SIM_BATT_VOLTAGE : (default)")
    print(f"  SIM_ENGINE_FAIL  : {int(sim_eng)}" if sim_eng is not None else "  SIM_ENGINE_FAIL  : 0")
    print(f"  SIM_MAG_ERROR    : {int(sim_mag)}" if sim_mag is not None else "  SIM_MAG_ERROR    : 0")
    print(f"  SIM_GPS_DISABLE  : {int(sim_gps)}" if sim_gps is not None else "  SIM_GPS_DISABLE  : 0")
    print(f"  SIM_RC_FAIL      : {int(sim_rc)}" if sim_rc is not None else "  SIM_RC_FAIL      : 0")
    print(f"  SIM_WIND_SPD     : {sim_wind:.1f} m/s" if sim_wind is not None else "  SIM_WIND_SPD     : 0 m/s")
    print("-----------------------------------\n")


def cmd_param(master, name, value=None):
    if value is None:
        val = get_param(master, name)
        if val is not None:
            print(f"{name} = {val}")
        else:
            print(f"Failed to read parameter: {name}")
    else:
        new_val = set_param(master, name, float(value))
        if new_val is not None:
            print(f"Success: {name} set to {new_val}")
        else:
            print(f"Failed to set parameter: {name} to {value}")


def cmd_scenario(master, scenario_name):
    if scenario_name not in SCENARIOS:
        print(f"Unknown scenario: '{scenario_name}'. Available scenarios:")
        for k, v in SCENARIOS.items():
            print(f"  - {k:<18}: {v['description']}")
        sys.exit(1)

    sc = SCENARIOS[scenario_name]
    print(f"\nApplying Scenario: [{scenario_name}] - {sc['description']}")
    for param, val in sc["params"].items():
        res = set_param(master, param, val)
        if res is not None:
            print(f"  ✓ {param} = {res}")
        else:
            print(f"  ✗ Failed to set {param}")
    print(f"Scenario [{scenario_name}] applied successfully.\n")


def cmd_bridge(tcp_host="127.0.0.1", tcp_port=5760, qgc_port=14550, ctrl_port=14551):
    """
    Transparent bidirectional MAVLink router:
    SITL TCP 5760 <---> QGC UDP 14550 & CLI UDP 14551
    """
    print(f"Starting MAVLink Bridge: SITL TCP {tcp_host}:{tcp_port} <--> UDP {qgc_port} & UDP {ctrl_port}")

    qgc_addr = ("127.0.0.1", qgc_port)
    ctrl_addr = ("127.0.0.1", ctrl_port)

    while True:
        try:
            tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            tcp_sock.connect((tcp_host, tcp_port))
            tcp_sock.setblocking(False)

            udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            udp_sock.bind(("127.0.0.1", 0))
            udp_sock.setblocking(False)

            print(f"Bridge connected to SITL. Forwarding MAVLink bidirectionally.")

            while True:
                r, _, _ = select.select([tcp_sock, udp_sock], [], [], 1.0)
                for s in r:
                    if s is tcp_sock:
                        data = tcp_sock.recv(4096)
                        if not data:
                            raise ConnectionResetError("SITL TCP connection closed")
                        udp_sock.sendto(data, qgc_addr)
                        try:
                            udp_sock.sendto(data, ctrl_addr)
                        except Exception:
                            pass
                    elif s is udp_sock:
                        data, addr = udp_sock.recvfrom(4096)
                        if data:
                            tcp_sock.sendall(data)
        except Exception as e:
            print(f"Bridge connection error: {e}. Retrying in 2 seconds...")
            time.sleep(2.0)


def main():
    parser = argparse.ArgumentParser(description="ArduPilot SITL Scenario & Fault Controller")
    parser.add_argument("--target", default=None, help="MAVLink target (e.g. udpin:127.0.0.1:14551 or tcp:127.0.0.1:5760)")

    subparsers = parser.add_subparsers(dest="command")

    # bridge
    subparsers.add_parser("bridge", help="Run the background MAVLink router (SITL TCP <-> QGC UDP)")

    # status
    subparsers.add_parser("status", help="Show live drone simulator telemetry and fault parameters")

    # scenario
    sc_parser = subparsers.add_parser("scenario", help="Apply a hardware or environmental scenario")
    sc_parser.add_argument("name", choices=list(SCENARIOS.keys()), help="Scenario name")

    # param
    p_parser = subparsers.add_parser("param", help="Get or set an ArduPilot parameter")
    p_parser.add_argument("name", help="Parameter name (e.g. SIM_BATT_VOLTAGE)")
    p_parser.add_argument("value", nargs="?", help="Optional new value to set")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(0)

    if args.command == "bridge":
        cmd_bridge()
        return

    master = connect_mavlink(args.target)

    if args.command == "status":
        cmd_status(master)
    elif args.command == "scenario":
        cmd_scenario(master, args.name)
    elif args.command == "param":
        cmd_param(master, args.name, args.value)


if __name__ == "__main__":
    main()
