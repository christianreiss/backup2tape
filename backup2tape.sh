#! /bin/bash

#  Config. Dont touch these, override with config file
MODULE_BASE="/media"
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
BASE="${SCRIPTPATH}/data"
TAPE_DEVICE="/dev/nst0"

# Load some required functions
. ${SCRIPTPATH}/lib/functions.sh

# Tell the people who we are :-)
printHeader "backup2tape, Version ${VERSION}"

# Handle overrides, if present.
if [ -e "${SCRIPTPATH}/.config" ] ; then
  printInfo "Local config round, loading."
  . "${SCRIPTPATH}/.config"
fi

# Parse command line arguments
. ${SCRIPTPATH}/lib/arguments.sh

# Check for root rights
check_root

# Sert up directories.
initFolders

# Locking
. ${SCRIPTPATH}/lib/locking.sh

# Set some variables
# Load the serial number from the currently loaded tape.
getSerialNumber
MODULE=${_arg_module}

# Show a summary of things found.
printInfo "Device : ${TAPE_DEVICE}"
printInfo "Tape   : ${TAPE}"
printInfo "Module : ${MODULE}"

# Check if we have a tape device.
checkTapeDevice

# Check if there is a tape inserted at all. If not, ask for one.
if [ "$(mt -f ${TAPE_DEVICE} status | grep -c 'DR_OPEN IM_REP_EN')" == '1' ] ; then
  requestNewTape
fi

# Check if the inserted tape is marked as read-only in our DB.
checkTapeReadOnly

# If read-only, spit it out.
if [ "${READONLY}" == 'true' ] ; then
  while true ; do
    ejectTape
    requestNewTape
    checkTapeReadOnly
    if [ "${READONLY}" == 'false' ] ; then
      break;
    fi
  done
fi

# Enable encryption
encryptionEnable

# Get current tape position.
TAPE_POS=$(returnTrackNumber)

# Check if the tape is known to us.
spoolToLastFile

# Accemble the options for tar
OPTIONS="-cvf ${TAPE_DEVICE} --hard-dereference --no-xattrs --no-selinux --no-acls --no-check-device --listed-incremental=${BASE}/${MODULE}.diff -M --index-file=${BASE}/${MODULE}-${TAPE}-${TRACK}.idx"

# Check that the module exists in the mount dir.
if [ ! -d "${MODULE_BASE}/${MODULE}" ] ; then
  printFail "module ${MODULE_BASE}/${MODULE} not found."
fi

# Assemble Includes, if any
if [ -e "${SCRIPTPATH}/includes/${MODULE}" ] ; then
  # With includes (only backup those)
  printInfo "Include directive for ${MODULE} found."

  # New per-line handling.
  while IFS= read -r line
  do
    includes="$includes ${MODULE_BASE}/${MODULE}/${line}"
  done < <(grep -v '^ *#' < "${SCRIPTPATH}/includes/${MODULE}")
else
  # Without includes (backup all)
  printInfo "No Include directive for ${MODULE} found."
  includes="${MODULE}"
fi

# Assemble Excludes, if any
if [ -e "${SCRIPTPATH}/excludes/${MODULE}" ] ; then
  printInfo "Exclude directive for ${MODULE} found."
  excludes="--exclude-from=${SCRIPTPATH}/excludes/${MODULE}"
fi

# Back up the whole module or the includes ONLY.
if [ "${includes}" != "" ] ; then
  backup_targets=${includes}
else
  backup_targets=${MODULE}
fi

# Do the actual backup.
cd "${MODULE_BASE}" || exit 2
printInfo "Tar options: ${OPTIONS} ${excludes} ${includes}"
printInfo "Tar Changer Command: --new-volume-script=${SCRIPTPATH}/tape_change.sh ${MODULE}"

# This exit is a SAFE stop before things go awry.
while true ; do
  echo -n -e "  ├ [${C_CYAN}ACTION REQUIRED${C_NONE}]: We're all set, please type 'OK' to start! > "
  read A
  if [ "${A}" == "OK" ] ; then
    break
  fi
done
printEnd

export TAPE
export TAPE_POS
tar ${OPTIONS} ${excludes} ${backup_targets} --new-volume-script="${SCRIPTPATH}/tape_change.sh ${MODULE}"
printHeader "Backup completed."

# Disable encryption
encryptionDisable

# Free Space
getFreeSpace

# Get current Track number
getTrackNumber

# Check if we are on the same tape we started, or not.
CURRENT_TAPE=$(ReturnSerialNumber)

if [ "${CURRENT_TAPE}" == "${TAPE}" ]; then
  # Same Tape.
  echo "${CUR_POS}" > "${BASE}/${TAPE}.track"
else
  # New Tape.
  printLine "Marking Tape ID ${TAPE} as read-only."
  echo "${TAPE}" >> "${BASE}/read-only.tapes"
  rm -f "${BASE}/${TAPE}.track"

  printLine "Setting Track ID to ${CUR_POS} for ID ${CURRENT_TAPE}."
  echo "${CUR_POS}" > "${BASE}/${CURRENT_TAPE}.track"
  if [ ! -e "${BASE}/${MODULE}-${CURRENT_TAPE}-${TRACK}.idx" ] ; then
    ln -s "${BASE}/${MODULE}-${TAPE}-${TRACK}.idx" "${BASE}/${MODULE}-${CURRENT_TAPE}-${TRACK}.idx"
  fi
fi

printEnd
