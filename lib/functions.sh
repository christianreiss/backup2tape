#! /bin/bash

#
# Fancy Stuff
#

# Lazy Colors
C_NONE="\033[0m"
C_RED="\033[0;31m"
#C_BLUE="\033[0;34m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_CYAN="\033[0;36m"
#C_ORANGE="\033[0;33m"

# Fancy Line printing.
function printLine {
  echo -e "  ├ $*"
}

function printOK {
  echo -e "  ├ [${C_GREEN}OK${C_NONE}] $*"
}

function printInfo {
  echo -e "  ├ [${C_CYAN}INFO${C_NONE}] $*"
}

function printFail {
  echo -e "  ├ [${C_RED}FAIL${C_NONE}] $*"
  printEnd
  exit 2
}

function printWarning {
  echo -e "  ├ [${C_YELLOW}WARN${C_NONE}] $*"
}

function printHeader {
  echo -e "  ┌──══ ${C_GREEN}$*${C_NONE}"
}

function printEnd {
  echo -e "  └──── "
}


# Check root
functon check_root {
  if [ "$(whoami)" != 'root' ] ; then
    printFail "Need superuser rights."
  fi
}



#
# non-git folder init
#
function initFolders {
  for i in encryption excludes includes ; do
    if [ ! -d "${SCRIPTPATH}/${i}" ] ; then
      mkdir "${SCRIPTPATH}/${i}" || printFail "Unable to create directory ${SCRIPTPATH}/${i}. Write permissions?"
      printOK "Initialized directory ${SCRIPTPATH}/${i}."
    fi
  done
}

#
# Tape Fucntions
#

# This checks if the configured tape device is present.
function checkTapeDevice {
  if [ -c "${TAPE_DEVICE}" ] ; then
    # Tape device found
    printOK "Tape Device ${TAPE_DEVICE} found."
  else
    # No Tape device found
    printFail "Tape Device ${TAPE_DEVICE} not found!"
  fi
}

# Eject a present tape
function ejectTape {
  # Check if we have a tape in the drive, eject is present.
  if [ "$(mt -f ${TAPE_DEVICE} status | grep -c 'DR_OPEN IM_REP_EN')" != '1' ] ; then
    # Tape is present, eject it.
    encryptionDisable
    mt -f ${TAPE_DEVICE} eject
    printLine "Tape ejected."
  fi
}

# User action: Wait for a new tape and check.
function waitForNewTape {
  ejectTape
  while true ; do
    echo -n -e "  ├ [${C_CYAN}ACTION REQUIRED${C_NONE}]: Insert new tape, then type 'OK' > "
    read A
    if [ "${A}" == "OK" ] ; then
      if [ "$(mt -f ${TAPE_DEVICE} status | grep -c 'DR_OPEN IM_REP_EN')" == '1' ] ; then
        printWarning "No tape is inserted, retry!"
      else
        getSerialNumber
        if [ "${TAPE}" != "" ] ; then
          break
        else
          printWarning "Invalid or no tape inserted, retry!"
        fi
      fi
    fi
  done
}

# Load Serial Number
function getSerialNumber {
  TAPE=$(sg_read_attr -q -f 0x0401 ${TAPE_DEVICE} | awk -F 'Medium serial number: ' ' { print $2 } ' | awk ' { print $1 }')
  printInfo "Tape Serial Number: ${TAPE}"
}

# Load Serial Number
#function ReturnSerialNumber {
#  CUR_TAPE=$(sg_read_attr -q -f 0x0401 ${TAPE_DEVICE} | awk -F 'Medium serial number: ' ' { print $2 } ' | awk ' { print $1 }')
#  echo ${CUR_TAPE}
#}

# Get the free space of current tape.
function getFreeSpace {
  free_space=$(sg_read_attr ${TAPE_DEVICE} | grep 'Remaining capacity in partition' | awk ' { print $6 } ')
  printInfo "Free space remaiming: ${free_space}"
}

# Get the current tape location (file id)
function getTrackNumber {
  CUR_POS=$(mt -f ${TAPE_DEVICE} status | grep 'File number=' | awk -F'File number=' ' { print $2 } ' | awk -F',' ' { print $1 } ') || exit 2
  printInfo "Current Track Number: ${CUR_POS}"
}

# Same as above, but simply returns the Track Number.
function returnTrackNumber {
  X=$(mt -f ${TAPE_DEVICE} status | grep 'File number=' | awk -F'File number=' ' { print $2 } ' | awk -F',' ' { print $1 } ') || exit 2
  echo -n ${X}
  unset X
}

# Check if the tape is readable.
function checkTapeReadOnly {
  if [ -e "${BASE}/read-only.tapes" ] ; then
    if [ "$(grep -c "${TAPE}" "${BASE}/read-only.tapes")" != '0' ] ; then
      printWarn "Tape ${TAPE} is marked as full, can't use!"
      READONLY=true
    else
      printOK "Tape ${TAPE} is known, but seems to have space left."
      READONLY=false
    fi
  else
    printOK "I have no database of filled tapes."
    READONLY=false
  fi
}

# Pester the user until a new tape is inserted.
function requestNewTape {
  while true ; do
    waitForNewTape
    checkTapeReadOnly
    if [ "${READONLY}" == "false" ] ; then
      printOK "Tape ${TAPE} is writeable, ok."
      break;
    fi
    printWarn "Tape ${TAPE} is write protected!"
    ejectTape
  done
}

# Enable the encryption on a device, stenc is required.
function encryptionEnable {
  encryptionKey="${SCRIPTPATH}/encryption/${TAPE}.key"
  if [ ! -e "${encryptionKey}" ] ; then
    printInfo "No encryption key found for ${TAPE}, generating."
    openssl rand -hex 32 > "${encryptionKey}" || printFail "Unable to generate encryption key ${encryptionKey}"
  fi

  ENCRYPT=true
  stenc -f ${TAPE_DEVICE} -e on -d on -a 1 -k "${encryptionKey}" 2>/dev/null || printFail "Unable to set encryption on device."
  printInfo "Encryption enabled on device ${TAPE_DEVICE} for Volume ${TAPE} using key ${encryptionKey}."
}

# This disabled the encryption on the device.
function encryptionDisable {
  stenc -f ${TAPE_DEVICE} -e off -d off 2>/dev/null || printFail "Unable to remove encryption on device."
  printInfo "Encryption disabled on device ${TAPE_DEVICE}."
}

# Spools the tape to the last used location (free space)
function spoolToLastFile {
  if [ ! -e "${BASE}/${TAPE}.track" ] ; then
    # Fresh tape.
    printOK "New tape, starting from BOT."
    TRACK='0'
  else
    # Known track.
    CUR_POS=$(cat "${BASE}/${TAPE}.track")
    (( fsf_count=CUR_POS-TAPE_POS )) || true

    # Check if we need to move the tape.
    if [ "${TAPE_POS}" != "${CUR_POS}" ] ;then
      printInfo "Known tape, continuing at ${CUR_POS}, currently at ${TAPE_POS}, need to forward ${fsf_count} marks!"
      mt -f "${TAPE_DEVICE}" fsf "${fsf_count}"

      TAPE_POS=$(returnTrackNumber)
      printOK "Tape is now at position ${TAPE_POS}."
    else
      printOK "Known tape, continuing at ${CUR_POS}, currently at ${TAPE_POS}, no spooling required."
    fi
    TRACK="${CUR_POS}"

    # Free Space
    getFreeSpace
    printLine "Free space remaiming: ${free_space}"
  fi
}