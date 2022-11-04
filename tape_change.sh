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

# Assign module vars
MODULE="$1"

# Check for root rights
check_root

# Check if we have a tape inserted.
checkTapeDevice

# Load the serial number from the currently loaded tape.
getSerialNumber
getTrackNumber
getFreeSpace

# Set old vars
OLD_POS=${TAPE_POS}
OLD_TAPE=${TAPE}

# As tar only calls us if the current tape is full, mark it as such.
echo "${TAPE}" >> "${BASE}/read-only.tapes"
test -e "${BASE}/${TAPE}.track" && rm -f "${BASE}/${TAPE}.track"
printOK "Marking tape ${TAPE} as read-only."

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

# Set the link for the new medium.
if [ ! -e "${BASE}/${MODULE}-${TAPE}-${TAPE_POS}.idx" ] ; then
  ln -s "${BASE}/${MODULE}-${OLD_TAPE}-${OLD_POS}.idx" "${BASE}/${MODULE}-${TAPE}-${TAPE_POS}.idx"
fi

printOK "New Medium accepted!"

printEnd
