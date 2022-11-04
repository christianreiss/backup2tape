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
printHeader "backup2tape - Tape Changer"

# Handle overrides, if present.
if [ -e "config" ] ; then
  printInfo "Local config round, loading."
  . config
fi

# Wohoo, tar.
printInfo "Using tar ${TAR_VERSION}."

# Check for root rights
check_root

# Check if we have a tape inserted.
checkTapeDevice

# Load the serial number from the currently loaded tape.
getSerialNumber
getTrackNumber
getFreeSpace

# As tar only calls us if the current tape is full, mark it as such.
printLine "Marking Tape ID ${TAPE} as read-only."
echo "${TAPE}" >> "${BASE}/read-only.tapes"
test -e "${BASE}/${TAPE}.track" && rm -f "${BASE}/${TAPE}.track"

# Link current tape to current backup job
# if [ ! -e "${BASE}/${MODULE}-${CURRENT_TAPE}-${TRACK}.idx" ] ; then
#   ln -s "${BASE}/${MODULE}-${TAPE}-${TRACK}.idx" "${BASE}/${MODULE}-${CURRENT_TAPE}-${TRACK}.idx"
# fi

# eject tapes
ejectTape

# insert new tape
requestNewTape

# encryption
encryptionEnable

# Get current tape position.
TAPE_POS=$(returnTrackNumber)

# Check if the tape is known to us.
spoolToLastFile

printOK "New Medium accepted!"

printEnd
