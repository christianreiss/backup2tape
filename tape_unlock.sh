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
printHeader "backup2tape - Tape Unlocker, Version ${VERSION}"

# Check for root rights
check_root

# Check if we have a tape inserted.
checkTapeDevice

# Check if there is a tape in the drive
if [ "$(testIfTapeInDrive)" == 'false' ] ; then
  printFail "There is no tape in the drive."
fi

# Load the serial number from the currently loaded tape.
getSerialNumber
getTrackNumber
getFreeSpace

# encryption
# We set the module to a random string, else the grep will wait forever.
MODULE="A69KhcOzegGI6ntmXBPTV15il7iMw61GWvDjVctauoWsjWbuIWaAhEquKYL8f"
encryptionEnable

# Done
printEnd
