#! /bin/bash

function locking {
  LOCKFILE="/tmp/$(basename "$0").lock"

  # Check if the lockfile exists.
  if [ -e "${LOCKFILE}" ]; then
    # It exists. Check if the process is still running.
    PID=$(cat "${LOCKFILE}")
    if ps -p "${PID}" >/dev/null 2>&1; then
      # It is. Don't touch anything, exit gracefully.
      echo "Script is already running with PID ${PID}. Exiting."
      exit 1
    else
      # It is not. Stale lockfile. Remove the lockfile.
      rm "${LOCKFILE}"
    fi
  fi

  # Create a new lockfile and store the current process ID.
  echo "$$" > "${LOCKFILE}" || { echo "Unable to create lockfile."; exit 1; }

  # Remove lockfile on script exit.
  trap 'rm -f "${LOCKFILE}"' INT TERM EXIT
}

# Check if drive is busy.
if ! mt -f ${TAPE_DEVICE} status >/dev/null 2>/dev/null ; then
  printFail "Tape drive ${TAPE_DEVICE} is busy."
else
  printOK "Tape drive ${TAPE_DEVICE} is idle."
fi

