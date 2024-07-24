

## TODO

. adb_wrapper.sh

parse_versions() {
ver_file=".versions.json"
unset -v ver_code
unset -v ver_name
unset -v suggested
curl -s "https://f-droid.org/api/v1/packages/$1" > "$ver_file"
suggested="$(jq 'try .suggestedVersionCode catch fromjson?' "$ver_file")"
if [ "$suggested" == "null" ]; then
  return 1
fi
no=0
until [ "$ver_code" == "$suggested" ]; do
  ver_code="$(jq ".packages[$no].versionCode" "$ver_file")"
  ver_name="$(jq ".packages[$no].versionName" "$ver_file" | sed 's/\"//g')"
  no=$((no+1))
  if [ "$ver_code" == "null" ] || [ "$ver_code" == "" ]; then
    return 1
  fi
done
rm "$ver_file"
}

list_installed() {
  for pkg in $(adb shell pm list packages -f -3 -i | cut -d"/" -f6 | cut -d'=' -f2- | grep -v com.android.vending | cut -d' ' -f1); do
    ver="$(adb shell dumpsys package "$pkg" | grep versionName | cut -d= -f2)"
    echo "$pkg/$ver"
  done > .installed.list
}

install_pkg() {
  if curl -# -o "$apk_file" "$dl_url"; then
    if [ "$TERMUX_VERSION" != "" ]; then
      if adb install -r "$apk_file" >/dev/null; then
        echo "Successfully installed $1"
#        rm "$apk_file"
      else
        echo "Failed to install $1"
      fi
    else
      adb install -r "$apk_file"
    fi
    rm *.apk >/dev/null
  fi
}

download_pkg() {
if ! parse_versions "$1"; then
  echo "We couldnt find $1"
  return 1
fi
url="https://f-droid.org/en/packages/$1/"
dl_url="$(curl -s "$url/" | grep ".apk" | sed '/class/d;/.apk.asc/d;s/<a href=\"//g;s/\">//g' | grep "$1_$ver_code" |xargs)"
apk_file="$(echo "$dl_url" | cut -d"/" -f5)"
echo "APK: $apk_file Version: $ver_name"
if [ ! -f "$apk_file" ]; then
  if [ "$2" == "" ]; then
    echo "$1 uses these permissions."
    echo
    curl -s "$url/" | grep "permission-label" | sed -r '/></d;s/<\/div>//g;s/<div class="permission-label">//g;s/[[:blank:]]+/ /g' | sort -u
    echo
    echo -n "Do you wish to proceed? [y/N]:"
    read -r -n1 confirm
    echo
    if [ "$confirm" != "y" ]; then
      echo "$1 was NOT installed"
      exit
    else
      install_pkg "$1"
      exit 0
    fi
  fi
  if [ "$2" == "-y" ]; then
    install_pkg "$1"
  fi
  if [ "$2" == "-d" ]; then
    curl -# -o "$apk_file" "$dl_url"
  fi
fi
}

pkg_search() {
  app_count=0
  n=0
  new_ver=""
  pkg_name=()
  pkg_ver=()
  app_name=()
  app_desc=()
  app_url=()
  curl -s "https://search.f-droid.org/api/search_apps?q=$1" | jq '.apps[] | "\(.name)", "\(.summary)", "\(.url)"' > .fdroid_search_results
  while IFS="" read -r line; do
    line="${line//\"/}"
    if [ "$n" == "0" ]; then
      app_name+=("$line")
      app_count=$((app_count+1))
    elif [ "$n" == "1" ]; then
      app_desc+=("$line")
    else
      app_url+=("$line")
      tmp_pkg_name="$(echo "$line" | cut -d"/" -f6)"
      pkg_name+=("$tmp_pkg_name")
      parse_versions "$tmp_pkg_name"
      pkg_ver+=("$ver_name")
    fi
    if [ "$n" == "2" ]; then
      n=0
    else
      n=$((n+1))
    fi
  done < .fdroid_search_results
}

display_search() {
  echo
  list_installed
  pkg_search "$1"
  for ((i=0;i<=((app_count-1));i++)); do
    if grep -q "${pkg_name[$i]}/" .installed.list ; then
      installed_ver="$(grep "${pkg_name[$i]}/" .installed.list | cut -d"/" -f2-)"
      if [ "$installed_ver" == "${pkg_ver[$i]}" ]; then
        echo "${pkg_name[$i]}/${pkg_ver[$i]} [installed]"
      else
        echo "${pkg_name[$i]}/${pkg_ver[$i]} [upgradable from $installed_ver]"
      fi
    else
      echo "${pkg_name[$i]}/${pkg_ver[$i]}"
    fi
    echo "${app_name[$i]}: ${app_desc[$i]}"
    echo
  done
}

mass_install() {
  file="$1"
  if [ ! -f "$file" ]; then
    echo "mass takes a file argument"
    exit 1
  fi
  if [ "$TERMUX_VERSION" != "" ]; then
    sed -i '/com.termux /d' "$file"
  fi
  while read -r pkg ver; do
    download_pkg "$pkg" "-y"
  done < "$file"
}

check_update() {
  list_installed
  sed -i 's/\// /g' .installed.list
  while read -r pkg ver; do
    if ! parse_versions "$pkg"; then
      continue
    fi
    if [[ "$ver_name" != "$ver" ]] && [ "$ver_name" != "" ] && [ "$ver_name" != "null" ]; then
      echo "$pkg \"$ver\" -> \"$ver_name\""
      download_pkg "$pkg" "-y"
    fi
  done < .installed.list
}

MY_VERSION="1.0"

show_usage() {
echo
echo "$0: $MY_VERSION"
echo
echo "    list		lists installed packages"
echo "			and versions"
echo "    install		installs a package"
echo "    search		searches for an app"
echo "    mass		installs mutiple apps"
echo "			listed in a file"
echo "    update		updates all apps"
echo
echo
}

case $1 in
  search)
    shift
    display_search "$1";;
  install)
    shift
    download_pkg "$1" "$2";;
  list)
    list_installed
    sed 's/\// /g' .installed.list;;
  mass)
    shift
    mass_install "$1";;
  update)
    check_update;;
  *)
    show_usage;;
esac

# cleanup
if [ -f .installed.list ]; then
  rm .installed.list
fi
if [ -f .fdroid_search_results ]; then
  rm .fdroid_search_results
fi

