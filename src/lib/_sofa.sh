#!/bin/bash

[ -z "$SOFA_FEED_URL" ] && SOFA_FEED_URL="https://sofafeed.macadmins.io/v2/macos_data_feed.json"
[ -z "$SOFA_USER_AGENT" ] && SOFA_USER_AGENT="SOFA-Jamf/1.0"

## region ###################################### JSON Retrieval Functions

# @description Retrieves the SOFA JSON feed, allowing for caching via etag
# @noargs
# @stdout string JSON Data
# @exitcode 0 Retrieval Successful
# @exitcode 1 Error Retrieving
function sofa::json() {
  local online_json_url user_agent json_cache json_cache_dir etag_cache etag_cache_temp etag_old etag_temp sofa_ver
  # URL to the online JSON data
  online_json_url="${SOFA_FEED_URL}"
  user_agent="${SOFA_USER_AGENT}"

  # Local store
  sofa_ver=$(echo "$online_json_url" | awk -F'/' '{ print $4 }')
  json_cache_dir="/private/var/tmp/sofa/$sofa_ver"
  json_cache="$json_cache_dir/macos_data_feed.json"
  etag_cache="$json_cache_dir/macos_data_feed_etag.txt"
  etag_cache_temp="$json_cache_dir/macos_data_feed_etag_temp.txt"

  # Ensure local cache folder exists
  /bin/mkdir -p "$json_cache_dir"

  # Check local vs online using etag (only available on macOS 12+)
  if [[ -f "$etag_cache" && -f "$json_cache" ]]; then
    etag_old=$(/bin/cat "$etag_cache")
    /usr/bin/curl --compressed --silent --etag-compare "$etag_cache" --etag-save "$etag_cache_temp" --header "User-Agent: $user_agent" "$online_json_url" --output "$json_cache"
    etag_temp=$(/bin/cat "$etag_cache_temp")
    if [[ "$etag_old" == "$etag_temp" || $etag_temp == "" ]]; then
        # Cached ETag matched online ETag - cached json file is up to date
        /bin/rm "$etag_cache_temp"
    else
        # Cached ETag did not match online ETag, so downloaded new SOFA json file
        /bin/mv "$etag_cache_temp" "$etag_cache"
    fi
  elif [[ "$myMajor" -lt "12" ]]; then
    # OS not compatible with e-tags, proceeding to download SOFA json file
    /usr/bin/curl --compressed --location --max-time 3 --silent --header "User-Agent: $user_agent" "$online_json_url" --output "$json_cache"
  else
    # No e-tag or SOFA json file cached, proceeding to download SOFA json file
    /usr/bin/curl --compressed --location --max-time 3 --silent --header "User-Agent: $user_agent" "$online_json_url" --etag-save "$etag_cache" --output "$json_cache"
  fi

  if [ -f "$json_cache" ]; then
    echo "$json_cache"
    return 0
  else
    return 1
  fi
}

## endregion ################################### JSON Retrieval Functions

## region ###################################### Index Functions

function sofa::outer::count() {
  local outer json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  outer="$1"

  jq --arg outer "$outer" '.OSVersions[$outer | tonumber ].SecurityReleases | length' <<< "$sofa"
}

function sofa::outer() {
  local json version major

  json=$(/bin/cat "$(sofa::json)")
  version="$1"
  major=$(version::major "$version")

  jq --arg major " $major" '.OSVersions | [range(0; length) as $i | select(.[$i].OSVersion | endswith($major)) | $i] | first' <<< "$json"
}

function sofa::inner() {
  local json version outer

  json=$(/bin/cat "$(sofa::json)")
  version="$1"
  outer="$2"
  [ -z "$outer" ] && outer=$(sofa::outer "$version")

  jq --arg v "$version" --arg outer "$outer" '.OSVersions[$outer | tonumber ].SecurityReleases | range(0; length) as $i | select(.[$i].ProductVersion == $v) | $i' <<< "$json"
}

function sofa::indices::object() {
  local outer inner json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  outer="$1"
  inner="$2"

  jq --arg outer "$outer" --arg inner "$inner" '.OSVersions[$outer | tonumber ].SecurityReleases[$inner | tonumber]' <<< "$json"
}

function sofa::indices::next() {
  local json outer count ver max lVer inner obj objVer objMaj i maxVer maxMaj nOuter nInner cur maxMin maxRev

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  outer="$1"
  inner="$2"
  maxVer="$3"
  count=$(sofa::outer::count "$outer" <<< "$json")
  max=$((count-1))
  [ "$inner" -gt "$max" ] && inner="$max"
  cur=$(sofa::indices::object "$outer" "$inner" <<< "$json")
  ver=$(sofa::obj::version <<< "$cur")
  for ((i = $max; i >= 0 ; i-- ));
  do
    obj=$(sofa::indices::object "$outer" "$i" <<< "$json")
    lVer=$(sofa::obj::version <<< "$obj")
    if version::is::gt "$lVer" "$ver"; then
      echo "$outer.$i" && return 0
    fi
  done

  if [ "$outer" -gt "0" ]; then
    nOuter=$((outer-1))
    count=$(sofa::outer::count "$nOuter" <<< "$json")
    nInner=0
    if [ -n "$maxVer" ]; then
      maxMaj=$(version::major "$maxVer")
      obj=$(sofa::indices::object "$nOuter" "$nInner" <<< "$json")
      objVer=$(sofa::obj::version <<< "$obj")
      objMaj=$(version::major "$objVer")
      if ! version::is::under "$objVer" "$maxMaj"; then
        echo "$outer.$inner" && return 0
      else
        while [ "$nInner" -lt "$count" ]; do
          obj=$(sofa::indices::object "$nOuter" "$nInner" <<< "$json")
          objVer=$(sofa::obj::version <<< "$obj")
          maxMin=$(echo "$maxVer" | awk -F"." '{ print $2 }')
          maxRev=$(echo "$maxVer" | awk -F"." '{ print $3 }')
          if version::is::under "$objVer" "$maxMaj" "$maxMin" "$maxRev"; then
            echo "$nOuter.$nInner" && return 0
          fi
          nInner=$((nInner+1))
        done

        echo "$outer.$inner" && return 0
      fi
    fi

    echo "$nOuter.0" && return 0
  else
    echo "$outer.$inner" && return 0
  fi
}

## endregion ################################### Index Functions

## region ###################################### Getter Functions

# @description Attempts to retrieve the device string of this Mac
# @noargs
# @internal
# @stdout string Device String
function _deviceString() {
  local j

  j=$(ioreg -arc IOPlatformExpertDevice -d 1 | plutil -extract 0.IORegistryEntryName raw -o - -)

  # Fallback: if it's just 'Root', pull the Board ID (common on older Intel)
  if [[ "$j" == "Root" ]]; then
    j=$(ioreg -p IODeviceTree -n / -ar | grep -A 1 "board-id" | grep "string" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
  fi

  echo "$j" && return 0
}

function sofa::ver::latest() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  jq '.OSVersions | first | .SecurityReleases | first' <<< "$json"
}

function sofa::ver::next::major() {
  local json ver outer

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  ver="$1"
  outer=$(sofa::outer "$ver" <<< "$json")
  if [ "$outer" -gt "0" ]; then
    outer=$((outer-1))
  fi

  jq --arg index "$outer" '.OSVersions[$index | tonumber].SecurityReleases[0]' <<< "$json"
}

function sofa::ver::next::minor() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::ver::next "$1" 1 <<< "$json"
}

function sofa::ver::next() {
  local json major minor version outer inner indices nOuter nInner maxVer

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  version="$1"
  maxVer="$2"
  major=$(version::major "$version")
  minor=$(version::minor "$version")
  outer=$(sofa::outer "$version")
  inner=$(sofa::inner "$version" "$outer")

  indices=$(sofa::indices::next "$outer" "$inner" "$maxVer" <<< "$json")
  nOuter=$(echo "$indices" | awk -F"." '{ print $1 }')
  nInner=$(echo "$indices" | awk -F"." '{ print $2 }')

  sofa::indices::object "$nOuter" "$nInner" <<< "$json"
}

sofa::device::latest() {
  local json device

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  device="$1"
  [ -z "$device" ] && device=$(_deviceString)

  sofa::ver::latest <<< "$(sofa::filter::device "$device" <<< "$json")"
}

sofa::device::next() {
  local json device

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  device="$1"
  [ -z "$device" ] && device=$(_deviceString)

  sofa::ver::next <<< "$(sofa::filter::device "$device" <<< "$json")"
}

sofa::model::latest() {
  local json device model

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  model="$1"
  device="$2"
  [ -z "$model" ] && model=$(/usr/sbin/sysctl -n hw.model)

  json=$(sofa::filter::model "$model" <<< "$json")
  if [ -n "$device" ]; then
    json=$(sofa::filter::device "$device" <<< "$json")
  fi

  sofa::ver::latest <<< "$json"
}

sofa::model::next() {
  local json device model

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  model="$1"
  device="$2"
  [ -z "$model" ] && model=$(/usr/sbin/sysctl -n hw.model)

  json=$(sofa::filter::model "$model" <<< "$json")
  if [ -n "$device" ]; then
    json=$(sofa::filter::device "$device" <<< "$json")
  fi

  sofa::ver::next <<< "$json"
}

## endregion ################################### Object Functions

## region ###################################### Version Filters

# @arg $1 int Position of Version Part
# @arg $2 int Comparison String (eq, gte, lte, ne)
function _queryVersion() {
  local pos comp

  pos="$1"
  case $2 in
    eq)   comp="==" ;;
    ne)   comp="!=" ;;
    gte)  comp=">=" ;;
    lte)  comp="<=" ;;
    lt)   comp="<"  ;;
    gt)   comp=">"  ;;
    *)    comp=">=" ;;
  esac

  echo ".OSVersions |= map(.SecurityReleases |= map(select(.ProductVersion | tostring | split(\".\")[$pos] | tonumber? | . as \$n | \$v | any(\$n $comp .))) | select(.SecurityReleases | length > 0))"
}

function sofa::filter::ver() {
  local json comp ver major minor patch

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  comp="$1"
  ver="$2"
  major=$(echo "$ver" | awk -F"." '{ print $1 }')
  minor=$(echo "$ver" | awk -F"." '{ print $2 }')
  patch=$(echo "$ver" | awk -F"." '{ print $3 }')

  if [ -n "$patch" ]; then
    sofa::filter::patch "$comp" "$major" "$minor" "$patch" <<< "$json"
  elif [ -n "$minor" ]; then
    sofa::filter::minor "$comp" "$major" "$minor" <<< "$json"
  else
    sofa::filter::major "$comp" "$major" <<< "$json"
  fi
}

function sofa::filter::ver::gte() {
  sofa::filter::ver "gte" "$1"
}

function sofa::filter::ver::lte() {
  sofa::filter::ver "lte" "$1"
}

function sofa::filter::ver::eq() {
  sofa::filter::ver "eq" "$1"
}

function sofa::filter::ver::ne() {
  sofa::filter::ver "ne" "$1"
}

# @arg $1 string Comparison String
# @arg $2 string|array|int Full Version, Major Version or an array of Major versions
# @stdin  string JSON
# @stdout string JSON
function sofa::filter::major() {
  local json major comp query

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  comp="$1"
  major="$2"

  if ! jq -e 'type == "array"' <<< "$major" > /dev/null; then
    # Make sure we parse versions to just have the major part
    echo "$major" | grep -q "\." && major=$(version::major "$major")
    # Make sure we wrap the major in an array
    major="[$major]"
  fi
  query=$(_queryVersion "0" "$comp")

  jq --argjson v "$major" "$query" <<< "$json"
}

# @arg $1 string Comparison String
# @arg $2 string|array|int Full Version, Major Version or an array of Major versions
# @arg $3 string|array|int Minor Version or an array of Minor versions
# @stdin  string JSON
# @stdout string JSON
function sofa::filter::minor() {
  local json major minor comp query

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  comp="$1"
  major="$2"
  minor="$3"
  if echo "$major" | grep -q "\."; then
    minor=$(version::minor "$major")
    major=$(version::major "$major")
  fi

  if ! jq -e 'type == "array"' <<< "$minor" > /dev/null; then
    minor="[$minor]"
  fi

  json=$(sofa::filter::major "$comp" "$major" <<< "$json")
  query=$(_queryVersion "1" "$comp")

  jq --argjson v "$minor" "$query" <<< "$json"
}

# @description Filters feed by major, minor, and patch version
# @arg $1 string Comparison String
# @arg $2 string|array|int Full Version, Major Version or an array of Major versions
# @arg $3 string|array|int Minor Version or an array of Minor versions
# @arg $4 string|array|int Patch Version or an array of Patch versions
# @stdin  string JSON
# @stdout string JSON
function sofa::filter::patch() {
  local json major minor patch comp query

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  comp="$1"
  major="$2"
  minor="$3"
  patch="$4"
  if echo "$major" | grep -q "\."; then
    patch=$(version::patch "$major")
    minor=$(version::minor "$major")
    major=$(version::major "$major")
  fi

  if ! jq -e 'type == "array"' <<< "$minor" > /dev/null; then
    patch="[$patch]"
  fi

  json=$(sofa::filter::minor "$comp" "$major" "$minor" <<< "$json")
  query=$(_queryVersion "2" "$comp")

  jq --argjson v "$patch" "$query" <<< "$json"
}

function sofa::filter::eq::major() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::major "eq" "$1" <<< "$json"
}

function sofa::filter::eq::minor() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::minor "eq" "$1" "$2" <<< "$json"
}


function sofa::filter::eq::patch() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::patch "eq" "$1" "$2" "$3" <<< "$json"
}

function sofa::filter::gte::major() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::major "gte" "$1" <<< "$json"
}

function sofa::filter::gte::minor() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::minor "gte" "$1" "$2" <<< "$json"
}

function sofa::filter::gte::patch() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::patch "gte" "$1" "$2" "$3" <<< "$json"
}

function sofa::filter::lte::major() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::major "lte" "$1" <<< "$json"
}

function sofa::filter::lte::minor() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::minor "lte" "$1" "$2" <<< "$json"
}

function sofa::filter::lte::patch() {
  local json

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  sofa::filter::patch "lte" "$1" "$2" "$3" <<< "$json"
}

## endregion ################################### Version Filters

## region ###################################### Other Filters

function sofa::filter::delay() {
  local json delay major today cutoff

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  delay="$1"
  major="$2"
  if [ -n "$major" ]; then
    json=$(sofa::filter::major "$major" <<< "$json")
  fi

  today=$(date "+%Y-%m-%d %H:%M:%S %z")
  cutoff=$(date -j -u -f "%Y-%m-%d %H:%M:%S %z" -v "-${delay}d" "${today}" +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg date "$cutoff" '.OSVersions |= map(.SecurityReleases |= map(select(.ReleaseDate <= $date)))' <<< "$json"
}

function sofa::filter::device() {
  local device json

  [ ! -t 0 ] && json=$(cat)
  device="$1"
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  [ -z "$device" ] && device=$(ioreg -arc IOPlatformExpertDevice -d 1 | plutil -extract 0.IORegistryEntryName raw -o - -)
  jq --arg device "$device" '.OSVersions[].SecurityReleases |= map(select(.SupportedDevices | index($device)))' <<< "$json"
}

function sofa::filter::max() {
  local json ver major minor patch

  [ ! -t 0 ] && json=$(cat)
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")

  ver="$1"
  major=$(echo "$ver" | awk -F"." '{ print $1 }')
  minor=$(echo "$ver" | awk -F"." '{ print $2 }')
  patch=$(echo "$ver" | awk -F"." '{ print $3 }')

  if [ -n "$patch" ]; then
    sofa::filter::lte::patch "$major" "$minor" "$patch" <<< "$json"
  elif [ -n "$minor" ]; then
    sofa::filter::lte::minor "$major" "$minor" <<< "$json"
  else
    sofa::filter::lte::major "$major" <<< "$json"
  fi
}

function sofa::filter::model() {
  local modelMajor model json

  [ ! -t 0 ] && json=$(cat)
  model="$1"
  [ -z "$json" ] && json=$(/bin/cat "$(sofa::json)")
  [ -z "$model" ] && model=$(/usr/sbin/sysctl -n hw.model)

  if [[ $model == "VirtualMac"* ]]; then
    # if virtual, we need to arbitrarily choose a model that supports all current OSes. Plucked for an M1 Mac mini
    model="Macmini9,1"
  fi

  modelMajor=$(jq --arg model "$model" '.Models[$model].OSVersions' <<< "$json")

  sofa::filter::major "$modelMajor" <<< "$json"
}

## region ###################################### Other Filter Functions

## region ###################################### Object Functions

function sofa::obj::build() {
  if [ ! -t 0 ]; then
    jq -r ".Build//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::cve() {
  if [ ! -t 0 ]; then
    jq ".CVEs//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::cve::unique() {
  if [ ! -t 0 ]; then
    jq -r ".UniqueCVEsCount//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::cve::active() {
  if [ ! -t 0 ]; then
    jq ".ActivelyExploitedCVEs//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::date() {
  local format localDate tempFormat feedDate

  format="$1"
  [ -z "$format" ] && format="%Y-%m-%d %H:%M:%S"
  if echo "$format" | grep -E "(%Z|%z)"; then
    tempFormat="$format"
  else
    tempFormat="$format %z"
  fi
  if [ ! -t 0 ]; then
    feedDate=$(jq -r ".ReleaseDate//empty" <<< "$(cat)")
    if [ -n "$feedDate" ]; then
      localDate=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$feedDate" +"$tempFormat")
      if [ "$tempFormat" != "$format" ]; then
        localDate=$(date -j -u -f "$tempFormat" "$localDate" +"$format")
      fi
      echo "$localDate" && return 0
    fi
  fi

  return 1
}

function sofa::obj::daysSincePrevious() {
  if [ ! -t 0 ]; then
    jq -r ".DaysSincePreviousRelease//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::devices() {
  if [ ! -t 0 ]; then
    jq ".SupportedDevices//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::name() {
  if [ ! -t 0 ]; then
    jq -r ".UpdateName//empty" <<< "$(cat)"
  else
    return 1
  fi
}


function sofa::obj::product() {
  if [ ! -t 0 ]; then
    jq -r ".ProductName//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::securityDesc() {
  if [ ! -t 0 ]; then
    jq -r ".SecurityInfoContext//empty" <<< "$(cat)"
  else
    return 1
  fi
}

function sofa::obj::securityUrl() {
  if [ ! -t 0 ]; then
    jq -r ".SecurityInfo//empty" <<< "$(cat)"
  else
    return 1
  fi
}


function sofa::obj::version() {
  if [ ! -t 0 ]; then
    jq -r ".ProductVersion//empty" <<< "$(cat)"
  else
    return 1
  fi
}

## endregion ################################### Object Functions
