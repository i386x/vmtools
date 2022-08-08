#
# File:    ./pkgman.sh
# Author:  Jiří Kučera <sanczes AT gmail.com>
# Date:    2022-08-03 22:42:01 +0200
# Project: Virtual Machine Tools (vmtools)
# Brief:   Package management utilities for VMs
#
# SPDX-License-Identifier: MIT
#

function __add_scratch_repo() {
  local _user="${USER}"
  local _service=""
  local _usr_svc=""
  local _nvr=""
  local _name=""
  local _version=""
  local _release=""
  local _repofile=""
  local _repourl=""

  __need_arg "${1:-}"
  __need_arg "${2:-}"

  if [[ "${2}" =~ ^([^:]+):(.+)$ ]]; then
    _usr_svc="${BASH_REMATCH[1]}"
    _nvr="${BASH_REMATCH[2]}"
  fi

  if [[ "${_usr_svc}" =~ ^([^@]+)@(.+)$ ]]; then
    _user="${BASH_REMATCH[1]}"
    _service="${BASH_REMATCH[2]}"
  else
    _service="${_usr_svc}"
  fi

  if [[ "${_nvr}" =~ ^(.+)-(.+)-(.+)$ ]]; then
    _name="${BASH_REMATCH[1]}"
    _version="${BASH_REMATCH[2]}"
    _release="${BASH_REMATCH[3]}"
  fi

  if [[ -z "${_nvr}" ]]; then
    __error "Name-version-release part is not specified."
  fi

  _repofile="${_nvr}-scratch.repo"

  if [[ "${DELETE_REPO:-}" ]]; then
    vmtools_vmssh "${1}" "rm -f \"/etc/yum.repos.d/${_repofile}\""
    return $?
  fi

  if [[ -z "${_service}" ]]; then
    __error "Brew-like build system service URL is not specified."
  fi

  _service="$(vmtools_get_alias "${_service}")"

  case "${_service}" in
    s+*) _service="https://${_service:2}" ;;
    ???*://*) : ;;
    *) _service="http://${_service}" ;;
  esac

  if [[ -z "${_name}" ]]; then
    __error "Cannot decide name part from ${_nvr}."
  fi
  if [[ -z "${_version}" ]]; then
    __error "Cannot decide version part from ${_nvr}."
  fi
  if [[ -z "${_release}" ]]; then
    __error "Cannot decide release part from ${_nvr}."
  fi

  _repourl="${_service}/repos/scratch/${_user}"
  _repourl="${_repourl}/${_name}/${_version}/${_release}/${_repofile}"

  vmtools_vmssh "${1}" "{
    curl -o \"/etc/yum.repos.d/${_repofile}\" \"${_repourl}\" \
    && test -f \"/etc/yum.repos.d/${_repofile}\" \
    && grep -E '^baseurl=' \"/etc/yum.repos.d/${_repofile}\"
  } >/dev/null"
}

function manage_repo() {
  local _kind=""
  local _repospec="${2:-}"

  __need_arg "${2:-}"

  if [[ "${2}" =~ ^([^/]+)/(.*)$ ]]; then
    _kind="${BASH_REMATCH[1]}"
    _repospec="${BASH_REMATCH[2]}"
  fi

  case "${_kind}" in
    scratch)
      __add_scratch_repo "${1:-}" "${_repospec}"
      ;;
    *)
      __error "Missing or unsupported repository type." \
        "Supported types of repository so far are: scratch."
      ;;
  esac
}
