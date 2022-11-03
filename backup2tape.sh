#! /bin/bash

# TODO
# (test) Read Only Tapes system
# (test) Check for started tape id and last tape id
# (test) Test Module exists
# Store last-dump-dates
# Enable Tape Compression by default using mt
# Tape Change Script
# Always-Full Backup modules
# Autochanger support

# Lazy Colors
C_NONE="\033[0m"
C_RED="\033[0;31m"
#C_BLUE="\033[0;34m"
C_GREEN="\033[0;32m"
#C_YELLOW="\033[1;33m"
#C_CYAN="\033[0;36m"
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

function printHeader {
  echo -e "  ┌──══ ${C_GREEN}$*${C_NONE}"
}

function printEnd {
  echo -e "  └──── "
}

# Tell the people who we are :-)
printHeader "backup2tape"

#  Config. Dont touch these, override with config file
MODULE_BASE="/media"
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
BASE="${SCRIPTPATH}/data"
TAPE_DEVICE="/dev/nst0"

# Handle overrides, if present.
if [ -e "config" ] ; then
  printInfo "Local config round, loading."
  . config
fi

##
#
# bash argument pasring START
#
##

die()
{
  local _ret="${2:-1}"
  test "${_PRINT_HELP:-no}" = yes && print_help >&2
  echo "$1" >&2
  exit "${_ret}"
}


begins_with_short_option()
{
  local first_option all_short_options='d'
  first_option="${1:0:1}"
  test "$all_short_options" = "${all_short_options/$first_option/}" && return 1 || return 0
}

# THE DEFAULTS INITIALIZATION - POSITIONALS
_positionals=()

print_help()
{
  printf 'Usage: %s [-d|--device <arg>] <module> \n' "$0"
  printf '\t%s\n' "<module>: what module to back up"
  printf '\t%s\n' "-d, --device: specify a tape device (default: '${TAPE_DEVICE}')"
}


parse_commandline()
{
  _positionals_count=0
  while test $# -gt 0
  do
    _key="$1"
    case "$_key" in
      *)
        _last_positional="$1"
        _positionals+=("$_last_positional")
        _positionals_count=$((_positionals_count + 1))
        ;;
    esac
    shift
  done
}


handle_passed_args_count()
{
  local _required_args_string="'module'"
  test "${_positionals_count}" -ge 1 || _PRINT_HELP=yes die "FATAL ERROR: Not enough positional arguments - we require exactly 1 (namely: $_required_args_string), but got only ${_positionals_count}." 1
  test "${_positionals_count}" -le 1 || _PRINT_HELP=yes die "FATAL ERROR: There were spurious positional arguments --- we expect exactly 1 (namely: $_required_args_string), but got ${_positionals_count} (the last one was: '${_last_positional}')." 1
}


assign_positional_args()
{
  local _positional_name _shift_for=$1
  _positional_names="_arg_module"

  shift "$_shift_for"
  for _positional_name in ${_positional_names}
  do
    test $# -gt 0 || break
    eval "$_positional_name=\${1}" || die "Error during argument parsing, possibly an Argbash bug." 1
    shift
  done
}

parse_commandline "$@"
handle_passed_args_count
assign_positional_args 1 "${_positionals[@]}"

# OTHER STUFF GENERATED BY Argbash

### END OF CODE GENERATED BY Argbash (sortof) ### ])
# [ <-- needed because of Argbash


##
#
# bash argument end
#
##


#
# Pre-Flight Checks
#

# Check for root rights
if [ "$(whoami)" != 'root' ] ; then
  printFail "Need superuser rights."
fi

# Locking
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

#
# End pre-flight checks
#


#
# Set some variables
#
# The module (directory) to back up.
# Load the serial number from the currently loaded tape.
TAPE=$(sg_read_attr -q -f 0x0401 ${TAPE_DEVICE} | awk -F 'Medium serial number: ' ' { print $2 } ' | awk ' { print $1 }')
MODULE=${_arg_module}

# Show a summary of things found.
printInfo "Device : ${TAPE_DEVICE}"
printInfo "Tape   : ${TAPE}"
printInfo "Module : ${MODULE}"

# Check if we have a tape inserted.
if [ -c "${TAPE_DEVICE}" ] ; then
  # Tape device found
  printOK "Tape Device ${TAPE_DEVICE} found."
else
  # No Tape device found
  printFail "Tape Device ${TAPE_DEVICE} not found!"
fi

# Check if there is a tape inserted at all. If not, die.
if [ "$(mt -f ${TAPE_DEVICE} status | grep -c 'DR_OPEN IM_REP_EN')" == '1' ] ; then
  prinfFail "No tape is inserted, aborting."
fi

# Check if the inserted tape is marked as read-only in our DB.
if [ -e "${BASE}/read-only.tapes" ] ; then
  if [ "$(grep -c "${TAPE}" "${BASE}/read-only.tapes")" != '0' ] ; then
    printFail "Tape ${TAPE} is marked as full, can't use!"
  else
    printOK "Tape ${TAPE} is known, but seems to have space left."
  fi
else
  printOK "I have no database of filled tapes."
fi

# Get current tape position.
TAPE_POS=$(mt -f ${TAPE_DEVICE} status | grep 'File number=' | awk -F'File number=' ' { print $2 } ' | awk -F',' ' { print $1 } ')

# Check if the tape is known to us.
if [ ! -e "${BASE}/${TAPE}.track" ] ; then
  # Fresh tape.
  printOK "New tape, starting from BOT."
  TRACK='0'
else
  # Known track.
  CUR_POS=$(cat "${BASE}/${TAPE}.track")
  # let CUR_POS=CUR_POS+1
  #let fsf_count=CUR_POS-TAPE_POS
  (( fsf_count=CUR_POS-TAPE_POS )) || true
  #printLine "Known tape, continuing at ${CUR_POS}, currently at ${TAPE_POS}, need to forward ${fsf_count} marks!"

  # Check if we need to move the tape.
  if [ "${TAPE_POS}" != "${CUR_POS}" ] ;then
    printInfo "Known tape, continuing at ${CUR_POS}, currently at ${TAPE_POS}, need to forward ${fsf_count} marks!"
    mt -f "${TAPE_DEVICE}" fsf "${fsf_count}"

    TAPE_POS=$(mt -f ${TAPE_DEVICE} status | grep 'File number=' | awk -F'File number=' ' { print $2 } ' | awk -F',' ' { print $1 } ')
    printOK "Tape is now at position ${TAPE_POS}."
  else
    printOK "Known tape, continuing at ${CUR_POS}, currently at ${TAPE_POS}, no spooling required."
  fi
  TRACK="${CUR_POS}"
  
  # Free Space
  free_space=$(sg_read_attr ${TAPE_DEVICE} | grep 'Remaining capacity in partition' | awk ' { print $6 } ')
  printLine "Free space remaiming: ${free_space}"
fi

# Accemble the options for tar
OPTIONS="-cvf ${TAPE_DEVICE} --no-check-device --listed-incremental=${BASE}/${MODULE}.diff -M --index-file=${BASE}/${MODULE}-${TAPE}-${TRACK}.idx"

# Check that the module exists in the mount dir.
if [ ! -d "${MODULE_BASE}/${MODULE}" ] ; then
  printFail "module ${MODULE_BASE}/${MODULE} not found."
fi

# Assemble Includes, if any
if [ -e "${SCRIPTPATH}/includes/${MODULE}" ] ; then
  printInfo "Include directive for ${MODULE} found."

  # New per-line handling.
  while IFS= read -r line
  do
    includes="$includes ${MODULE_BASE}/${MODULE}/${line}"
  done < <(grep -v '^ *#' < "${SCRIPTPATH}/includes/${MODULE}")

  # Old but prone to whitespace
  # for i in $(cat "${SCRIPTPATH}/includes/${MODULE}") ; do
  #    includes="$includes ${MODULE_BASE}/${MODULE}/$i"
  # done

else
  printInfo "No Include directive for ${MODULE} found."
  includes="${MODULE}"
fi

# Assemble Excludes, if any
if [ -e "${SCRIPTPATH}/excludes/${MODULE}" ] ; then
  printInfo "Exclude directive for ${MODULE} found."
  #for i in $(cat "${BASE}/excludes/${MODULE}") ; do
  #  excludes=$excludes "--${MODULE_BASE}/${MODULE}/$i"
  #done
  excludes="--exclude-from=${SCRIPTPATH}/excludes/${MODULE}"

fi

# Back up the whole module or the includes ONLY.
if [ "${includes}" != "" ] ; then
  backup_targets=${includes}
else
  backup_targets=${MODULE}
fi

# exit 0

# Encryption

if [ -e "${SCRIPTPATH}/encryption/${MODULE}.key" ] ; then
  stenc -f /dev/nst0 -e on -d on -a 1 -k "/home/chris/backup2tape/encryption/${MODULE}.key" 2>/dev/null || printFail "Unable to set encryption on device."
  printOK "Encryption set successfully."
  ENCRYPT=true
else
  printInfo "No encryption key found."
  ENCRYPT=false
fi

# Do the actual backup.
cd "${MODULE_BASE}" || exit 2
printInfo "Tar options: ${OPTIONS} ${excludes} ${includes}, beginning backup."

#exit 0

tar ${OPTIONS} ${excludes} ${backup_targets} 1>/dev/null >/dev/null
printOK "Backup OK."

if [ "${ENCRYPT}" == "true" ] ; then
  stenc -f /dev/nst0 -e off -d off 2>/dev/null || printFail "Unable to remove encryption on device."
  printOK "Encyption removed from device."
fi

# Free Space
free_space=$(sg_read_attr ${TAPE_DEVICE} | grep 'Remaining capacity in partition' | awk ' { print $6 } ')
printLine "Free space remaiming: ${free_space}"

CUR_POS=$(mt -f ${TAPE_DEVICE} status | grep 'File number=' | awk -F'File number=' ' { print $2 } ' | awk -F',' ' { print $1 } ') || exit 2

# Check if we are on the same tape we started, or not.
CURRENT_TAPE=$(sudo sg_read_attr -q -f 0x0401 ${TAPE_DEVICE} | awk -F 'Medium serial number: ' ' { print $2 } ' | awk ' { print $1 }')

if [ "${CURRENT_TAPE}" == "${TAPE}" ]; then
  # Same Tape.
  echo "${CUR_POS}" > "${BASE}/${TAPE}.track"
else
  # New Tape.
  printLine "Marking Tape ID ${TAPE} as read-only."
  echo "${TAPE}" > "${BASE}/read-only.tapes"
  rm -f "${BASE}/${TAPE}.track"

  printLine "Setting Track ID to ${CUR_POS} for ID ${CURRENT_TAPE}."
  echo "${CUR_POS}" > "${BASE}/${CURRENT_TAPE}.track"
  if [ ! -e "${BASE}/${MODULE}-${CURRENT_TAPE}-${TRACK}.idx" ] ; then
    ln -s "${BASE}/${MODULE}-${TAPE}-${TRACK}.idx" "${BASE}/${MODULE}-${CURRENT_TAPE}-${TRACK}.idx"
  fi
fi

printEnd
