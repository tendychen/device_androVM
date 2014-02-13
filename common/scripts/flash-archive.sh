#!/system/bin/sh

#############
# CONSTANTS #
#############

TMP_DIR="/data/local/tmp/flash-tmp-dir/"
INSTALL_DIR="/"
ARM_SO_SUB_DIR="/arm/"

# Value for e_machine field in elf header for ARM
# http://en.wikipedia.org/wiki/Executable_and_Linkable_Format#File_header
ARM_E_MACHINE="28"

#############
# FUNCTIONS #
#############

_log_message() {
    echo "$1"
    log -t "$PROGNAME" "$1"
}

_exit_success() {
    echo "{Result:OK};"
    exit 0
}

_exit_failure() {
    echo "{Result:KO};"
    exit 1
}

# mkdir_and_copy_file <file> <copy.path>
# Copy file into dir (keeping file specified path)
mkdir_and_copy_file() {
    FILE="$1"
    DIR="$2"
    NEW_FILE=${DIR}/${FILE}
    # Construct and build dir
    DIR_TO_MKDIR=$(dirname "$NEW_FILE")
    mkdir -p $DIR_TO_MKDIR

    if [ ! -d "$FILE" ] # is NOT a directory
    then
        # Remove previous file if exists
        [ -e "$NEW_FILE" ] && rm $NEW_FILE
        # Copy file
        if ! cp "$FILE" "$NEW_FILE"; then
            _log_message "[ERROR][mkdir_and_copy_file] cp failed : $FILE $NEW_FILE"
        fi
    fi
}

check_and_install_lib() {
    FILE="$1"
    # Retrieve the e_machine value from the elf header
    E_MACHINE=`hexdump -e '"%02x"' -s 18 -n 1 $FILE`
    _log_message "[check_and_install_lib] $FILE e_machine flag is $E_MACHINE"
    if [ "$E_MACHINE" = $ARM_E_MACHINE ]
    then
        _log_message "[check_and_install_lib] $FILE is an ARM library and needs a special treatment."
        install_arm_lib "$FILE"
    else
        _log_message "[check_and_install_lib] $FILE is not an ARM lib, standard install process"
        install_file "$FILE"
    fi
}

install_file() {
    mkdir_and_copy_file "$1" "$INSTALL_DIR"
}

install_arm_lib() {
    FILE=$1
    # Build the library install path
    SO_DEST_DIR=${INSTALL_DIR}/$(dirname "$FILE")/${ARM_SO_SUB_DIR}
    # Create the library install directory
    if ! mkdir -p "$SO_DEST_DIR"; then
        exit_on_error "[ERROR][install_arm_lib] mkdir failed : $SO_DEST_DIR"
    fi
    # Copy the library in the newly created dir
    if ! cp "$FILE" "$SO_DEST_DIR"; then
        exit_on_error "[ERROR][install_arm_lib] cp failed : $FILE $SO_DEST_DIR"
    fi

    # Create a link if the x86 lib does not exist
    if [ ! -f "${INSTALL_DIR}/${FILE}" ]
    then
        _log_message "[install_arm_lib] No x86 version of $FILE making link.";
        NEW_FILE=${SO_DEST_DIR}/$(basename "$FILE")
        LINK=${INSTALL_DIR}/${FILE}
        # Create a link in standard dir to /arm/ lib
        if ! ln -s "$NEW_FILE" "$LINK"; then
            _log_message "[ERROR][install_arm_lib] ln failed : $NEW_FILE $LINK"
        fi
    fi
}

check_and_install_file() {
    FILE=$1
    case "$FILE" in
        *.so)
            _log_message "[check_and_install_file] $FILE is a library"
            check_and_install_lib "$FILE"
            ;;
        *)
            _log_message "[check_and_install_file] $FILE is not a library"
            install_file "$FILE"
    esac
}

delete_tmp_dir() {
    rm -r "$TMP_DIR"
}

create_tmp_dir() {
    # Remove previous version if exist
    delete_tmp_dir
    if ! mkdir -p "$TMP_DIR"; then
        exit_on_error "[ERROR][create_tmp_dir] mkdir failed : $TMP_DIR"
    fi
}

unzip_archive_in_tmp_dir() {
    if ! unzip "$1" -d "$TMP_DIR"; then
        exit_on_error "[ERROR][unzip_archive_in_tmp_dir] unzip failed : $1"
    fi
}

remount_system_rw() {
    if ! mount -o rw,remount /system; then
        _log_message "[ERROR][remount_system_rw] cannot remount system in rw"
    fi
}

remount_system_ro() {
    if ! mount -o ro,remount /system; then
        _log_message "[ERROR][remount_system_ro] cannot remount system in ro"
    fi
}

install_all_files() {
    for i in $(find system/) ;
    do
        check_and_install_file "$i"
    done
}

exit_on_error() {
    echo "$1" >&2
    log -p e -t "flash_archive" "$1"
    _exit_failure 1
}

##########
# SCRIPT #
##########
flash_archive() {
  # Retrieve params
    ARCHIVE=$1


    _log_message "[flash_archive] Creating tmp dir"
    create_tmp_dir

    _log_message "[flash_archive] Unzip archive"
    unzip_archive_in_tmp_dir "$ARCHIVE"

    if ! cd "$TMP_DIR"; then
        _log_message "[ERROR][flash_archive] cd failed : $TMP_DIR"
    fi

    _log_message "[flash_archive] Remount /system/ in rw"
    remount_system_rw

    _log_message "[flash_archive] Start file install"
    install_all_files

    _log_message "[flash_archive] Remount /system/ in ro"
    remount_system_ro

    _log_message "[flash_archive] Delete tmp directory"
    delete_tmp_dir

    _log_message "[flash_archive] Done successfully !"
}

# check root access
id | grep root
if [ $? -ne 0 ]
then
    exit_on_error "`basename $0` must be run as root"
fi

########
# main #
########
{
    # Check if args are ok
    if [ $# -ne 1 ]
    then
        exit_on_error "Usage: `basename $0` <archive-to-flash.zip>"
    fi

    ZIPFILE=$1

    # Check if argument is an .zip archive
    case "$ZIPFILE" in
        *.zip)
            _log_message "$ZIPFILE seems to be a zip archive";
            ;;
        *)
            exit_on_error "Sorry $ZIPFILE doesn't seem to be a zip archive"
    esac

    # Change umask for the whole process
    UMASK=`umask`
    if ! umask 022; then
        _log_message "[ERROR][main] umask failed !"
        _exit_failure 1664
    fi

    # launching flash mechanics
    flash_archive "$ZIPFILE"

    # Restore umask
    if ! umask $UMASK; then
        _log_message "[ERROR][flash_archive] unable to revert to umask $UMASK."
    fi

    _exit_success
}

