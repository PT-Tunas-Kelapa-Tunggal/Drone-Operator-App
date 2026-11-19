#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
BRIDGE_PID_FILE="${SCRIPT_DIR}/.bridge.pid"

ensure_venv() {
  if [ ! -d "${VENV_DIR}" ]; then
    echo "Creating Python virtual environment in ${VENV_DIR}..."
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install --upgrade pip
    "${VENV_DIR}/bin/pip" install -r "${SCRIPT_DIR}/requirements.txt"
  elif [ ! -f "${VENV_DIR}/bin/pymavlink" ] && ! "${VENV_DIR}/bin/python3" -c "import pymavlink" 2>/dev/null; then
    echo "Installing requirements into ${VENV_DIR}..."
    "${VENV_DIR}/bin/pip" install -r "${SCRIPT_DIR}/requirements.txt"
  fi
}

start_bridge() {
  stop_bridge
  echo "Starting background MAVLink router (TCP 5760 <-> UDP 14550)..."
  "${VENV_DIR}/bin/python3" "${SCRIPT_DIR}/sim_controller.py" bridge > "${SCRIPT_DIR}/bridge.log" 2>&1 &
  echo $! > "${BRIDGE_PID_FILE}"
}

stop_bridge() {
  if [ -f "${BRIDGE_PID_FILE}" ]; then
    PID=$(cat "${BRIDGE_PID_FILE}" 2>/dev/null || true)
    if [ -n "${PID}" ] && kill -0 "${PID}" 2>/dev/null; then
      echo "Stopping background MAVLink router (PID ${PID})..."
      kill "${PID}" 2>/dev/null || true
    fi
    rm -f "${BRIDGE_PID_FILE}"
  fi
}

run_controller() {
  ensure_venv
  "${VENV_DIR}/bin/python3" "${SCRIPT_DIR}/sim_controller.py" "$@"
}

usage() {
  echo "ArduPilot Quadcopter Drone Simulator (Docker & MAVLink)"
  echo ""
  echo "Usage: $(basename "$0") <command> [options]"
  echo ""
  echo "Commands:"
  echo "  start      Start the ArduCopter SITL Docker container and MAVLink router"
  echo "             Options:"
  echo "               --home LAT,LON,ALT,HDG  (Default: -0.9248,101.4452,35.0,0.0)"
  echo "               --speedup N             (Default: 1)"
  echo "               --wipe                  (Wipe EEPROM/parameters)"
  echo "  stop       Stop the simulator container and router"
  echo "  restart    Restart the simulator container and router"
  echo "  status     Show simulator container status, bridge status, and live drone telemetry"
  echo "  logs       Stream simulator container logs"
  echo "  scenario   Apply a hardware or environmental fault scenario:"
  echo "             healthy, low-battery, critical-battery, motor-fail,"
  echo "             compass-fail, gps-lost, rc-lost, high-wind"
  echo "  param      Get or set an ArduPilot parameter (e.g. param SIM_BATT_VOLTAGE 21.0)"
  echo ""
  exit 1
}

CMD="$1"
shift || true

case "${CMD}" in
  start)
    HOME_COORD="-0.9248,101.4452,35.0,0.0"
    SPEEDUP="1"
    WIPE=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --home)
          HOME_COORD="$2"
          shift 2
          ;;
        --speedup)
          SPEEDUP="$2"
          shift 2
          ;;
        --wipe)
          WIPE="1"
          shift
          ;;
        *)
          echo "Unknown start option: $1"
          usage
          ;;
      esac
    done

    IFS=',' read -r LAT LON ALT YAW <<< "${HOME_COORD}"

    echo "=========================================="
    echo "Starting ArduCopter SITL Simulator..."
    echo "  Location: ${LAT}, ${LON} (Alt: ${ALT}m, Hdg: ${YAW}°)"
    echo "  Speedup : ${SPEEDUP}x"
    echo "  Target  : 127.0.0.1:14550 (QGC auto-connect)"
    echo "  Local   : 127.0.0.1:5760 (MAVLink Controller)"
    echo "=========================================="

    export HOME_LAT="${LAT}"
    export HOME_LON="${LON}"
    export HOME_ALT="${ALT}"
    export HOME_YAW="${YAW}"
    export SPEEDUP="${SPEEDUP}"

    # Stop any conflicting instance first
    docker rm -f arducopter-sitl 2>/dev/null || true

    docker compose -f "${COMPOSE_FILE}" up -d arducopter

    echo "Waiting for ArduCopter SITL to initialize..."
    sleep 3

    ensure_venv
    start_bridge

    sleep 1
    run_controller status || true
    echo ""
    echo "✓ Simulator is running and broadcasting MAVLink on UDP 14550."
    echo "  Open QGroundControl GUI or Drone-Operator-App to view telemetry."
    ;;

  stop)
    echo "Stopping ArduCopter SITL Simulator..."
    stop_bridge
    docker compose -f "${COMPOSE_FILE}" down
    echo "✓ Simulator stopped."
    ;;

  restart)
    "${SCRIPT_DIR}/drone-sim.sh" stop
    "${SCRIPT_DIR}/drone-sim.sh" start "$@"
    ;;

  status)
    echo "--- Docker Container Status ---"
    docker compose -f "${COMPOSE_FILE}" ps
    echo ""
    if [ -f "${BRIDGE_PID_FILE}" ] && kill -0 "$(cat "${BRIDGE_PID_FILE}")" 2>/dev/null; then
      echo "MAVLink Router: Active (PID $(cat "${BRIDGE_PID_FILE}"))"
    else
      echo "MAVLink Router: Stopped"
    fi
    echo ""
    run_controller status
    ;;

  logs)
    docker compose -f "${COMPOSE_FILE}" logs -f arducopter
    ;;

  scenario)
    if [ -z "$1" ]; then
      echo "Error: Scenario name required."
      usage
    fi
    run_controller scenario "$@"
    ;;

  param)
    if [ -z "$1" ]; then
      echo "Error: Parameter name required."
      usage
    fi
    run_controller param "$@"
    ;;

  *)
    usage
    ;;
esac
