#! /bin/bash

function locking {
  LOCKFILE="/tmp/$0.lock"
  # Check if the lockfile exists.
  if [ -e "${LOCKFILE}" ] ; then
    # it does exist. Check if the process is still running.
    PID="$(cat "${LOCKFILE}")"
    if [ "$(ps --no-heading -q "${PID}" | wc -l)" != "0" ] ; then
      # it is. Don't touch anything, walk away slowly.
      printFail "Script is still running."
      exit 1
    else
      # it is not. Stale lockfile. Keep calm and remove the lockfile.
      rm "${LOCKFILE}"
    fi
  fi
  # No lockfile present (anymore, stale would have been deleted)
  echo "$BASHPID" > "${LOCKFILE}" || error "unable to create lockfile."
  # Remove lockfile on script exit.
  trap 'rm -f ${LOCKFILE}; exit' INT TERM EXIT
}

# Check if drive is busy.
if ! mt -f ${TAPE_DEVICE} status >/dev/null 2>/dev/null ; then
  printFail "Tape drive ${TAPE_DEVICE} is busy."
else
  printOK "Tape drive ${TAPE_DEVICE} is idle."
fi
