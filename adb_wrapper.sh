
# DOCUMENTATION
# if you are running this from an Android
# connected to another Android, you must
# set the variable MASTER=1 otherwise,
# leave blank

load_adb() {
  adb() {
  while [ "$1" ]; do
    case $1 in
      shell)
        shift
        if [ "$1" ]; then
          su 2000 -c "$@"
        else
          su 2000
        fi
        break;;
      install)
        shift
        su -c pm install "$@"
        break;;
      uninstall)
        shift
        su -c pm uninstall "$@"
        break;;
      -s)
        shift; shift;;
      *)
        echo "adb: error unknown command: $@";;
    esac
    shift
  done
  }
}

unload_adb() {
  adb_path=$(which adb)
  adb() {
    "$adb_path" "$@"
  }
}

if [ "$TERMUX_VERSION" != "" ] && \
[ "$MASTER" != "1" ] && \
su -c exit; then
  # running on target device
  load_adb
fi
