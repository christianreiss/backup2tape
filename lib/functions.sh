#! /bin/bash

VERSION="20221104"

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
function check_root {
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
    printOK "Tape ejected."
  fi
}

# Check if there is a tape in the drive.
function testIfTapeInDrive {
  if [ "$(mt -f ${TAPE_DEVICE} status | grep -c 'DR_OPEN IM_REP_EN')" == '1' ] ; then
    echo -n "false"
  else
    echo -n "true"
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
  TAPE=$(sg_read_attr -q -f 0x0401 ${TAPE_DEVICE} 2>/dev/null | awk -F 'Medium serial number: ' ' { print $2 } ' | awk ' { print $1 }')
  printInfo "Tape Serial Number: ${TAPE}"
}

function ReturnSerialNumber {
  X=$(sg_read_attr -q -f 0x0401 ${TAPE_DEVICE} 2>/dev/null | awk -F 'Medium serial number: ' ' { print $2 } ' | awk ' { print $1 }')
  echo -n ${X}
  unset X
}

# Get the free space of current tape.
function getFreeSpace {
  free_space=$(sg_read_attr ${TAPE_DEVICE} 2>/dev/null | grep 'Remaining capacity in partition' | awk ' { print $6 } ')
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
  # Our own Database.
  if [ -e "${BASE}/read-only.tapes" ] ; then
    if [ "$(grep -c "${TAPE}" "${BASE}/read-only.tapes")" != '0' ] ; then
      printWarning "Tape ${TAPE} is marked as full, can't use!"
      READONLY=true
    else
      # printOK "Tape ${TAPE} is known, but seems to have space left."
      READONLY=false
    fi
  else
    printOK "I have no database of filled tapes."
    READONLY=false
  fi

  # Physical Switch
  if [ "${READONLY}" == 'false' ] ; then
    if [ "$(mt -f ${TAPE_DEVICE} status | grep -c 'WR_PROT')" -gt 0 ] ; then
      printWarning "Tape ${TAPE} is phsically write protected, can't use!"
      READONLY=true
    fi
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
    printWarning "Tape ${TAPE} is write protected!"
    ejectTape
  done
}

# Enable the encryption on a device, stenc is required.
function encryptionEnable {

  # Skip encryption for some modules.
  if [ -e "${SCRIPTPATH}/encryption/skip_modules" ] ; then
    if [ "$(grep -c ${MODULE} ${SCRIPTPATH}/encryption/skip_modules)" -gt 0 ] ; then
      printInfo "As per override encryption will not be enabled for module ${MODULE}."
      ENCRYPT=false
    else
      ENCRYPT=true
    fi
  else
    ENCRYPT=true
  fi

  # Encryption Disabled: Make sure its off.
  if [ "${ENCRYPT}" == 'true' ] ; then
    stenc -f ${TAPE_DEVICE} -e off -d off 2>/dev/null || printFail "Unable to remove encryption on device."
  fi

  # Encryption Enabled: Load the ley.
  if [ "${ENCRYPT}" == 'true' ] ; then
    # Enable encryption with random keys per tape.
    encryptionKey="${SCRIPTPATH}/encryption/${TAPE}.key"
    if [ ! -e "${encryptionKey}" ] ; then
      # Create a new random key for this one tape (not module)
      openssl rand -hex 32 > "${encryptionKey}" || printFail "Unable to generate encryption key ${encryptionKey}"
      printOK "Encryption key for ${TAPE} generated."
    fi
    ENCRYPT=true
    stenc -f ${TAPE_DEVICE} -e on -d on -a 1 -k "${encryptionKey}" 2>/dev/null || printFail "Unable to set encryption on device."
    printOK "Encryption enabled on device ${TAPE_DEVICE} for Volume ${TAPE} using key ${encryptionKey}."
  fi
}

# This disabled the encryption on the device.
function encryptionDisable {
  if [ "$(stenc -f /dev/nst0 | grep -c Encrypting)" -gt 0 ] ; then
    stenc -f ${TAPE_DEVICE} -e off -d off 2>/dev/null || printFail "Unable to remove encryption on device."
    printInfo "Encryption disabled on device ${TAPE_DEVICE}."
  fi
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

    if [ "${fsf_count}" -lt 0 ] ; then
      printFail "Safety alert: Current Tape is as position ${TAPE_POS}, last known is ${CUR_POS}.. Was there some manual write on it?"
    fi

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
