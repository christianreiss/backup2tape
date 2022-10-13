#! /bin/bash

if [ "$2" == "" ] ; then
	echo "Need a module."
	exit 1
fi

if [ "$1" == "" ] ; then
	echo "Need a tape." 
	exit 1
fi

MODULE="$2"
TAPE="$1"
BASE="/home/chris/Documents/LTO"

# Get current tape position.
TAPE_POS=$(mt -f /dev/nst0 status | grep 'File number=' | awk -F'File number=' ' { print $2 } ' | awk -F',' ' { print 1 } ')

# Check if the tape is known to us.
if [ ! -e "${BASE}/${TAPE}.track" ] ; then
	# Fresh tape.
	echo "New tape, starting from BOT."
	TRACK='1'
else
	# Known track.
	CUR_POS=$(cat ${BASE}/${TAPE}.track)
	let CUR_POS=CUR_POS+1
	let fsf_count=CUR_POS-TAPE_POS
	echo "Known tape, continuing at ${CUR_POS}, currently at ${TAPE_POS},need to forward ${fsf_count} marks!"

	# Check if we need to move the tape.
	if [ "${TAPE_POS}" != "${CUR_POS}" ] ;then
		echo "Need to adjust the tape!"
		# mt -f /dev/nst0 rewind
		mt -f /dev/nst0 fsf ${fsf_count}
	else
		echo "Tape at correct position."
	fi
        TRACK="${CUR_POS}"
fi

exit 0

OPTIONS="--listed-incremental=${BASE}/${MODULE}.diff -M --index-file=${BASE}/${MODULE}-${TAPE}-${TRACK}.idx -cvf /dev/nst0"


cd /media
mt -f /dev/nst0 status
tar ${OPTIONS} ${MODULE} || exit 2
# mt -f /dev/nst0 weof
mt -f /dev/nst0 status

CUR_POS=$(mt -f /dev/nst0 status | grep 'File number=' | awk -F'File number=' ' { print $2 } ' | awk -F',' ' { print 1 } ')
echo ${CUR_POS} > ${BASE}/${TAPE}.track

