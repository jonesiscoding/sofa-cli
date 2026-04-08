#!/bin/bash

## region ###################################### Version Functions

function version::major() {
  local value
  value=$(/usr/bin/awk -F. '{print $1}' <<< "$1")

  echo "${value:-0}"
}

function version::minor() {
  local value
  value=$(/usr/bin/awk -F. '{print $2}' <<< "$1")

  echo "${value:-0}"
}

function version::patch() {
  local value
  value=$(/usr/bin/awk -F. '{print $3}' <<< "$1")

  echo "${value:-0}"
}

function version::is::eq() {
  local verA verB majA majB minA minB revA revB

  verA="$1"
  verB="$2"

  majA=$(version::major "$verA")
  majB=$(version::major "$verB")
  if [ "$majA" -eq "$majB" ]; then
    minA=$(version::minor "$verA")
    minB=$(version::minor "$verB")
    if [ "$minA" -eq "$minB" ]; then
      revA=$(version::patch "$verA")
      revB=$(version::patch "$verB")
      if [ "$revA" -eq "$revB" ]; then
        return 0
      fi
    fi
  fi

  return 1
}

function version::is::gt() {
  local verA verB majA majB minA minB revA revB

  verA="$1"
  verB="$2"

  majA=$(version::major "$verA")
  majB=$(version::major "$verB")
  [ "$majA" -gt "$majB" ] && return 0
  [ "$majA" -lt "$majB" ] && return 1

  # majA = majB
  minA=$(version::minor "$verA")
  minB=$(version::minor "$verB")
  [ -z "$minA" ] && minA=0
  [ -z "$minB" ] && minB=0
  [ "$minA" -gt "$minB" ] && return 0
  [ "$minA" -lt "$minB" ] && return 1

  # minA = minB
  revA=$(version::patch "$verA")
  revB=$(version::patch "$verB")
  [ -z "$revA" ] && revA=0
  [ -z "$revB" ] && revB=0
  [ "$revA" -gt "$revB" ] && return 0
  [ "$revA" -lt "$revB" ] && return 1

  return 1
}

function version::is::ge() {
  if version::is::eq "$1" "$2" || version::is::gt "$1" "$2"; then
    return 0
  fi

  return 1
}

function version::is::le() {
  if version::is::eq "$1" "$2" || version::is::lt "$1" "$2"; then
    return 0
  fi

  return 1
}

function version::is::lt() {
  if version::is::ge "$1" "$2"; then
    return 1
  else
    return 0
  fi
}

# @description Evaluates if the version given is equal to or less than the major, minor, and patch values given.
# @arg $1 string Version
# @arg $2 int    Major Component for Comparison
# @arg $2 int    Optional Minor Component for Comparison
# @arg $3 int    Optional Patch Component for Comparison
# @exitcode 0    Version is less than or equal to the major/minor/patch given
# @exitcode 0    Version is greater than the major/minor/patch given.
function version::is::under() {
  local verA majA majB minA minB revA revB

  verA="$1"
  majB="$2"
  minB="$3"
  revB="$4"
  majA=$(version::major "$verA")
  minA=$(version::minor "$verA")
  revA=$(version::patch "$verA")

  if [ -n "$majB" ]; then
    # Version > Compare Major
    [ "$majA" -gt "$majB" ] && return 1

    # Version == Compare Major, Minor Given
    if [ "$majA" -eq "$majB" ] && [ -n "$minB" ]; then
      # Version == Compare Major, > Compare Minor
      [ "$minA" -gt "$minB" ] && return 1
      # Version == Compare Major.Minor, Patch Given
      if [ "$minA" -eq "$minB" ] && [ -n "$revB" ]; then
        # Version == Compare Major.Minor, > Compare Patch
        [ "$revA" -gt "$revB" ] && return 1
      fi
    fi
  fi

  # No Major Given
  # Version <= Compare Major.Minor.Patch
  # Version <= Compare Major.Minor (no patch given)
  # Version <= Compare Major (no minor given)
  return 0
}

## endregion ################################### Version Functions
