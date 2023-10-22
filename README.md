# Welcome to Backup2Tape!

Hi!

I am Chris and I always had the issue of my digital data pile to grow and grow. Of course I had a NAS, this is where the problems intensified. I even had *more* files and replacing the disks in the drive went from funny to amazing to expensive. And keeping all the data always online was not something I felt was neccessary.
LTO was always a nice option and nowadays (2022) LTO 5 and LTO 6 are affordable for the home user with devices in the 200 bucks range, with an additional SCSI controller worth 40 bucks. And if you are lucky you can get a 20-tape box on eBay for less than 200. In my case of LTO 5 that 30TB of storage for under 200 bucks.
Gimme.

Now there was the issue of actually managing to get stuff on the tapes. Sure there is LTFS, but what about tape spanning? Modification watching? I wanted a solution for cold storage that knows what files are new and only appends. I do not want redudnant data, like a full backup every month. I want my data to *move* to cold storage and keep one copy of that file there.
New files should be appended, deleted files from NAS remain on the tapes. Also, if a tape fails it should not affect the backup chain at all.

And I want encryption. Fully automatic. So I can discard defunct tapes without a worry.
Also extracting tapes should only require three things:

 1. The Tape(s)
 2. The encryption keys
 3. Standard Linux utilities

So I can extract all the files if I had access to any Linux machine in the future, holding only the tapes and a git repo/ usb stick/ printout of my encryption keys.

I looked around but there is no such solution.

So I made one, consisting only of bash, stupid flat files and tar.


# Usage
You should clone the repository on your local PC/ Server where the LTO drive is in. I am assuming your drive is already recognized as a Linux device. If it is not, come back later when it does.

## Requirements
 - A working tape drive
 - Linux
 - root access on that Linux
 - these scripts
 - stenc installed (https://github.com/scsitape/stenc)

## Workflow
backup2file assumes a directory to back up (the "module") and a target tape drive. You run the script as root with only one parameter: the module to back up. By default the modules are expected to reside in /media, so a module movies must exist as /media/movies.


## Configuration overrides

By default backup2drive has the following directives:

 - MODULE_BASE: The directory where you modules reside, by default /media.
 - TAPE_DEVICE: The /dev device of your tape device, /dev/nst0 is assumed.

If you require a change of these files, create a .config file and set the variables accordingly, like

TAPE_DEVICE=/dev/st0

## Excludes and includes

Uppon first launch of backup2drive, the includes and exludes directories are created. You can place a file that is named like your module in each directory if you want. If no files are present, then all files under the modules are backed up. If you place a includes/movies file with

horror
comedy

 in it, only /media/movies/horror and /media/movies/comedy will be backed up.
 This is analogue for excludes.

## Data files

backup2drive has a "data" folder where is stores

 - module-tape-track.idx files that contain a list of backed up files. So you can grep them later and know which tape and what track its on.
 - module.diff: This is a tar incremental status file, so tar knows what files are new and changed, and only back up the changed and new files in subsequent runs.

## Filling tapes and Read Only

backup2drive records on what track is stopped. So if you fill a tape partially with a backup job, the next run backup2tape will seek to that marker and continue there.
If a tape gets filled complety it marks it internally as read-only and refuse to do any write  operations on that device. In *addition* to the phyiscal write protect switch.

## Encryption
backup2drive creates a unique and random 256bit key for each tape. So even a spanning backup job across 4 tapes has 4 unique keys. Don't worry, backup2drive manages them all. If you continue to write on an not-yet-full tape, backup2drive load the existing key and unlocks the drive for you.

Protip: Create a git repository of encryption/ and store it in a safe place. This is the only stuff you need to restore files.

# Backup
If your backup drive is working in Linux, you have tar installed and, if necessary, configuration overrides done, you can start a backup by

./backup2drive {module}

If you have a tape in your drive it is

 - Checked that is is writeable (physical and local database)
 - Encryption key loaded or generated
 - Encryption set up
 - All checks done for your (source dir present, sufficient rights, drive okay)
 - Tape spooled to correct position

Up to this point there are no writes done to your tape. There is a request to type "OK" to proceed. Once you type and hit enter, the backup will commence. If the backup job requires more tapes, you will  be prompted to exchange them. Just follow the on-screen prompts.

## Restoring

Restoring is done with "no tools needed" approach. You only need tape, tar and the encryption keys. If you have backup2drive you can run tape_unlock.sh with an inserted tape. backup2drive will read the tape information and unlock it for you. You can then do normal tar operations.

In a later stage I might even write a restore script. But restoring is soo easy I might not even bother.
