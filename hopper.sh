
#vars
backup_dir="/sdcard/Termux/Backups" #no trailing "/"
nc_dir="Backup/Pixel-5" #no trailing "/"
# dont edit these
date="$(date "+%Y-%m-%d")"
pkgs_file="termux_pkgs_$date.list"
home_file="termux_home_$date.tar.gz"
storage_file="storage_$date.tar.gz"
apps_file="apps_$date.list"
storage="/storage/emulated/0/"
apt_hist="$PREFIX/var/log/apt/history.log"
t='       '    # tab
R='\e[1;31m' # red
G='\e[1;32m' # green
W='\e[1;37m' # white bold
off='\e[0m'  # turn off color
OK=" $W[$G + $W]$off"
INFO=" $W[$G i $W]$off"
ERR=" $W[$R - $W]$off"
#MASTER=0 # client=0 master=1

if [ "$TERMUX_VERSION" = "" ] && ! command -v getprop; then
  # Running on PC
  MASTER=1
else
  export PREFIX='/data/data/com.termux/files/usr'
  export HOME='/data/data/com.termux/files/home'
  export LD_LIBRARY_PATH='/data/data/com.termux/files/usr/lib'
  export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH"
  export LANG='en_US.UTF-8'
  export SHELL='/data/data/com.termux/files/usr/bin/bash'
  export MASTER=0
fi

error() {
  echo -e "$ERR $1"
  exit $2
}

progress() {
  pid="$1"
  spin[0]="\\"
  spin[1]="|"
  spin[2]="/"
  spin[3]="-"

  #echo -n " $2 ${spin[0]}"
  while kill -0 $pid 2>/dev/null; do
    for i in "${spin[@]}"; do
      if [ $3 ]; then
        touch $3
        size="$(ls -sh "$3" | cut -d' ' -f1)"
      fi
      echo -ne "\r\e[K"
      echo -ne " $2 $i $size"
      sleep 0.25
    done
  done
  echo " [done]"
  wait $pid
  return "$?"
}

check_deps() {
  echo -e "$INFO Installing dependencies..."
  pkg_list=""
  for pkg in git tar curl pigz; do
    if ! command -v "$pkg" ; then
      pkg_list+="$pkg "
    fi
  done
  if [ "$pkg_list" != "" ]; then
    if [ "$MASTER" = "1" ] && [ "$EUID" != "0" ]; then
      sudo apt update -y && apt install "$pkg_list" -y
    else
      if [ "$MASTER" + "!" ]; then
        apt update -y && apt install "$pkg_list" -y
      else
        pkg update -y && pkg upgrade -y && pkg install "$pkg_list" -y
      fi
    fi
  fi
  #nccli
  if ! command -v nccli ; then
    git clone https://github.com/DethByte64/nccli
    if [ "$MASTER" != "1" ]; then
      termux-fix-shebang nccli/nccli
      chmod 755 nccli/nccli
      cp nccli/nccli $PREFIX/bin/
      nccli setup
    else
      chmod 755 nccli/nccli
      cp nccli/nccli /usr/local/bin/
      nccli setup
    fi
  fi
  echo -e " $OK Installed dependencies."
}

check_net() {
  if ping -q -w 1 -c 1 1.1.1.1 &> /dev/null; then
    return 0
  fi
  return 1
}

backup_home() {
  cd "$HOME"
  echo -e "$INFO Backing up home..."
  tar -cf - "./" 2>/dev/null | pigz > "$backup_dir/$home_file" 2>/dev/null &
  progress $! "[ copying ]" "$backup_dir/$home_file"
  if [ $? != 0 ]; then
    error "Failed to backup home directory." "$home_ret"
  else
  sleep 5
  touch "$backup_dir"/"$home_file"
  home_size="$(ls -sh "$backup_dir"/"$home_file" | cut -d' ' -f1)"
  echo -e "$OK Successfully backed up home. size=$home_size"
  fi
}

backup_storage() {
  cd $storage
  echo -e "$INFO Backing up storage..."
  tar --exclude="$backup_dir" --exclude="Android" --exclude="DCIM" --exclude="Pictures" --exclude="Movies" -cf - "./" 2>/dev/null | pigz > "$backup_dir/$storage_file" 2>/dev/null &
  progress $! "[ copying ]" "$backup_dir/$storage_file"
  if [ $? != 0 ]; then
    error "Failed to backup storage." "$storage_ret"
  fi
  sleep 5
  touch $backup_dir/$storage_file
  size="$(ls -sh $backup_dir/$storage_file | cut -d' ' -f1)"
  echo -e "$OK Successfully backed up storage. size=$size"
}

backup_pkgs() {
  while IFS= read -r line; do
    line=${line/-y/}
    if [[ "$line" =~ ' install ' ]]; then
      installed+=(${line##* install })
    else
      removed+=(${line##* remove })
      removed+=(${line##* purge })
    fi
  done < <(grep -E ' install | remove | purge ' ${apt_hist})
  for pkg in "${removed[@]}";do
    for i in "${!installed[@]}";do
      if [[ "${installed[$i]}" == "$pkg" ]]; then
        unset installed[$i]
        break
      fi
    done
  done
  declare -A tmp_array
  for i in "${installed[@]}"; do
    [[ $i ]] && IFS=" " tmp_array["${i:- }"]=1
  done
  printf "${t}%s\n" "${!tmp_array[@]}" | tee "$backup_dir/$pkgs_file"
  echo -e "$OK Successfully backed up packages."
}

backup_apps() {
  ./fdroidcli.sh list > "$backup_dir/$apps_file" &
  progress $! "[ listing ]" "$backup_dir/$apps_file"
}

backup() {
  if [ ! -d "$backup_dir" ]; then
    mkdir -p "$backup_dir"
  fi
  check_deps
  case "$1" in
    home )
      backup_home;;
    pkgs )
      backup_pkgs;;
    storage )
      backup_storage;;
    apps )
      backup_apps;;
    '' )
      backup_home
      backup_storage
      backup_pkgs
      backup_apps ;;
    * )
      error "invalid argument" "1";;
  esac
}

up_real() {
  nccli up "$backup_dir/$file" "$nc_dir/$1"
  if [ $? != 0 ]; then
    error "Failed to upload $file" 1
  fi
}

upload() {
  if ! (check_net); then
    error "No network" 1
  fi
  check_deps
  case "$1" in
    home )
      file="$home_file"; up_real;;
    pkgs )
      file="$pkgs_file"; up_real;;
    storage )
      file="$storage_file"; up_real;;
    apps )
      file="$apps_file"; up_real;;
    '' )
      file="$home_file"; up_real
      file="$pkgs_file"; up_real
      file="$storage_file"; up_real
      file="$apps_file"; up_real;;
    * )
      error "invalid argument" "1";;
  esac
}

restore_pkgs() {
  if ! check_net; then
    error "No network." "1"
  fi
    echo -e "$INFO Updating repo"
    pkg update -y
    echo -e "$INFO Restoring packages"
    if pkg install -y $(awk '{print $1}' "$HOME/../termux_pkgs_*.list" ); then
      echo -e "${OK} packages restored\n"
      echo "Start a new session."
      exit
    fi
}

restore_home() {
  echo -e "$INFO restoring home."
  tar -xzf "$HOME/../termux_home_*.tar.gz" "$HOME" &
  progress $! " [ restoring ]"
  if [ $? != 0 ]; then
    error "Failed to restore Home" 3
  else
    echo -e " ${OK} Successfully restored home."
    rm "$HOME/../termux_home_*.tar.gz"
  fi
}

restore_storage() {
  echo -e "$INFO restoring storage."
  tar -xzf "$storage/storage_*.tar.gz" "$storage" &
  progress $! " [ restoring ]"
  if [ $? != 0 ]; then
    error "Failed to restore storage" 3
  else
   echo -e " ${OK} Successfully restored storage"
   rm "$storage/storage_*.tar.gz"
  fi
}

restore_apps() {
  echo -e "$INFO restoring apps."
  ./fdroidcli.sh mass install apps.list
}

setup() {
  if ! (check_net); then
    error "No network" 1
  fi
  check_deps
  echo -e "$INFO Downloading Termux backups. This might take some time."
  nccli dl "$(nccli ls "$nc_dir" | grep home | tail -n 1)"
  nccli dl "$(nccli ls "$nc_dir" | grep pkgs | tail -n 1)"
  mv termux_home_*.tar.gz "$HOME/../"
  mv termux_pkgs_*.list "$HOME/../"
  restore_home
  restore_pkgs
  echo -e "$INFO Downloading internal storage backups. This may take some time."
  nccli dl "$(nccli ls "$nc_dir" | grep storage | tail -n 1)"
  restore_storage
  echo -e "$INFO Fetching app list."
  nccli dl "$(nccli ls "$nc_dir" | grep apps | tail -n 1)"
  restore_apps
}

if [ "$MASTER" = "1" ]; then
  # run hopper setup to install nccli and
  # fdroidcli
  # nccli pull termux_home and termux_pkgs
  # hopper restore home
  # hopper restore pkgs
  # nccli pull storage
  # hopper restore storage
  # fdroidcli mass apps.list
  # exit

  # install termux
  echo -e "$INFO Waiting for device..."
  adb wait-for-device
  echo -e "$INFO Installing Termux to device."
  ./fdroidcli.sh install com.termux -y
  # launch termux
  adb shell su -c am start --user 0 -n com.termux/.HomeActivity
  echo -e "$INFO Waiting 1 minute...\nGrant Termux Internet permissions"
  sleep 60
  # push root-termux, hopper, fdroidcli, and adb_wrapper
  # then launch hopper.sh setup in termux context
  echo -e "$INFO Pushing hopper to device..."
#  adb push root-termux.sh /data/local/tmp/
#  adb shell su -c cp /data/local/tmp/root-termux.sh /data/data/com.termux/files/home/
#  adb shell su -c chmod +x /data/data/com.termux/files/home/root-termux.sh
  adb push hopper.sh /data/local/tmp/
  adb shell su -c cp /data/local/tmp/hopper.sh /data/data/com.termux/files/home/
  adb shell su -c chmod +x /data/data/com.termux/files/home/hopper.sh
  adb push adb_wrapper.sh /data/local/tmp/
  adb shell su -c cp /data/local/tmp/adb_wrapper.sh /data/data/com.termux/files/home/
  adb shell su -c chmod +x /data/data/com.termux/files/home/adb_wrapper.sh
  adb push fdroidcli.sh /data/local/tmp/
  adb shell su -c cp /data/local/tmp/fdroidcli.sh /data/data/com.termux/files/home/
  adb shell su -c chmod +x /data/data/com.termux/files/home/fdroidcli.sh
  echo -e "$INFO Launching Hopper."
  echo "allow-external-apps=true" >> /data/data/com.termux/files/home/.termux/termux.properties
  adb shell su -c am startservice --user 0 -n com.termux/com.termux.app.RunCommandService -a com.termux.RUN_COMMAND --es com.termux.RUN_COMMAND_PATH '/data/data/com.termux/files/home/hopper.sh' --esa com.termux.RUN_COMMAND_ARGUMENTS 'setup' --es com.termux.RUN_COMMAND_WORKDIR '/data/data/com.termux/files/home' --ez com.termux.RUN_COMMAND_BACKGROUND 'false' --es com.termux.RUN_COMMAND_SESSION_ACTION '0'
#  adb shell su -c /data/data/com.termux/files/home/adb-termux.sh "/data/data/com.termux/files/home/hopper.sh setup"
else
  $@
fi
