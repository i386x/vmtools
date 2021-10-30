#
# File:    ./getimage.sh
# Author:  Jiří Kučera <sanczes AT gmail.com>
# Date:    2021-10-25 20:07:07 +0200
# Project: Virtual Machine Tools (vmtools)
# Brief:   Tools for pulling images
#
# SPDX-License-Identifier: MIT
#

function __bad_image_spec() {
  __p_red "'${1}': Ill-formed image specification." >&2
  return 1
}

function __get_alpha_beta() {
  case "${1:-}" in
    *-a | *-al | *-alp | *-alph | *-alpha )
      echo -n "-Alpha" ;;
    *-b | *-be | *-bet | *-beta )
      echo -n "-Beta" ;;
  esac
}

function __get_version() {
  echo -n "${1%%-*}"
}

function __get_major() {
  echo -n "${1%%.*}"
}

function __verify_version() {
  [[ "${1:-}" =~ ^[[:digit:]]+(\.[[:digit:]]+)?(\.[[:digit:]]+)?$ ]]
}

function __find_qcow2_image() {
  local _result=""

  while read -r _line; do
    if [[ "${_line}" =~ ^.*\<a\ +href=\"(.+)\"\ *\>.*$ ]]; then
      _result="${BASH_REMATCH[1]}"
      if [[ "${_result}" == *.qcow2 ]]; then
        echo -n "${1}/${_result}"
        break
      fi
    fi
  done < <(curl -k -L "${1}" 2>&1)
}

function __create_image_setup_yml() {
  local _url_a=""
  local _url_b=""
  local _basename=""

  __need_arg "${1:-}"
  __need_arg "${2:-}"
  __need_arg "${3:-}"
  __need_arg "${4:-}"

  _url_a="${1}"
  _url_b="${2}"
  _basename="${3}"
  shift 3

  {
    echo '---'
    echo ''
    echo '- name: Setup image'
    echo '  hosts: all'
    echo '  vars:'
    echo "    url_a: \"${_url_a}\""
    echo "    url_b: \"${_url_b}\""
    echo "    march: \"${ARCH:-x86_64}\""
    echo ''
    echo '  tasks:'
    echo '    - name: Add repositories'
    echo '      yum_repository:'
    echo '        name: "{{ item }}"'
    echo '        description: "{{ item }}"'
    echo '        baseurl: "{{ url_a }}/{{ item }}/{{ march }}/os/"'
    echo '        enabled: yes'
    echo '        gpgcheck: no'
    echo '        state: present'
    echo '      loop:'
    for _stream in "$@"; do
      echo "        - ${_stream}"
    done
    echo ''
    echo '    - name: Add source repositories'
    echo '      yum_repository:'
    echo '        name: "{{ item }}-source"'
    echo '        description: "{{ item }} source"'
    echo '        baseurl: "{{ url_a }}/{{ item }}/source/tree/"'
    echo '        enabled: yes'
    echo '        gpgcheck: no'
    echo '        state: present'
    echo '      loop:'
    for _stream in "$@"; do
      echo "        - ${_stream}"
    done
    echo ''
    echo '    - name: Add Buildroot repository'
    echo '      yum_repository:'
    echo '        name: Buildroot'
    echo '        description: Buildroot'
    echo '        baseurl: "{{ url_b }}/{{ march }}/os/"'
    echo '        enabled: yes'
    echo '        gpgcheck: no'
    echo '        state: present'
    echo ''
    echo '    - name: Add Buildroot source repository'
    echo '      yum_repository:'
    echo '        name: Buildroot-source'
    echo '        description: Buildroot source'
    echo '        baseurl: "{{ url_b }}/source/tree/"'
    echo '        enabled: yes'
    echo '        gpgcheck: no'
    echo '        state: present'
  } > "${_basename}.yml"
}

function vmtools_get_fimage_cmd() {
  local _image_file=""
  local _image_spec=""
  local _product=""
  local _version=""
  local _run=""
  local _alpha_beta=""
  local _url_a=""
  local _url_b=""
  declare -a _streams=()
  local _arch="${ARCH:-x86_64}"
  local _image_url=""
  local _temp=""

  __need_arg "${1:-}"

  if [[ "${1:-}" == fhub/* ]]; then
    _image_spec="${1#*/}"
    # fedora-VERSION
    if [[ "${_image_spec}" =~ ^fedora-([[:digit:]]+|n|N)$ ]]; then
      if [[ "${BASH_REMATCH[1]}" == [nN] ]]; then
        _version="rawhide"
      else
        _version="${BASH_REMATCH[1]}"
      fi

      for _x in releases development; do
        _image_url="https://download.fedoraproject.org/pub/fedora/linux"
        _image_url="${_image_url}/${_x}/${_version}/Cloud/${_arch}/images"
        __p_blue_n "Trying ${_image_url}" >&2
        _image_url="$(__find_qcow2_image "${_image_url}")"
        if [[ "${_image_url}" ]]; then
          __p_green " [OK]" >&2
          break
        else
          __p_red " [FAILED]" >&2
        fi
      done
      if [[ -z "${_image_url}" ]]; then
        return 1
      fi

      _image_file="$(__imgname "${_image_url}" "${2:-}")"

      __wget_image "${_image_url}" "${_image_file}"
    else
      __bad_image_spec "${_image_spec}"
    fi
  elif [[ "${1:-}" == rhub/* ]]; then
    _image_spec="${1#*/}"
    # PRODUCT-VERSION[:RUN]
    if [[ "${_image_spec}" =~ ^([^-]+)-([^:]+)(:[^:]+)?$ ]]; then
      _product="${BASH_REMATCH[1]}"
      _version="${BASH_REMATCH[2]}"
      _run="${BASH_REMATCH[3]:-:rel-eng}"
      _run="${_run:1}"
      _alpha_beta="$(__get_alpha_beta "${_version,,}")"
      _version="$(__get_version "${_version}")"
      _major="$(__get_major "${_version}")"

      __verify_version "${_version}" || {
        __p_red "Version '${_version}' is ill-formed." >&2
        return 1
      }

      if [[ -z "${RHUB:-}" ]]; then
        __p_red "RHUB is not set." >&2
        return 1
      fi

      _url_a="${RHUB}/${_product,,}-${_major}/${_run}"
      _url_b="${_url_a}/BUILDROOT-${_major}${_alpha_beta}"
      _url_a="${_url_a}/${_product^^}-${_major}${_alpha_beta}"
      _url_a="${_url_a}/latest-${_product^^}-${_version}/compose"
      _url_b="${_url_b}/latest-BUILDROOT-${_version}-${_product^^}-${_major}"
      _url_b="${_url_b}/compose"

      if [[ ${_major} -lt 8 ]]; then
        _streams=( "Server" )
        _url_b="${_url_b}/Server"
      else
        _streams=( "BaseOS" "AppStream" "CRB" )
        _url_b="${_url_b}/Buildroot"
      fi

      _temp="${_url_a}/${_streams[0]}/${_arch}/images"
      _image_url="$(__find_qcow2_image "${_temp}")"
      if [[ -z "${_image_url}" ]]; then
        __p_red "<${_temp}> has no qcow2 images." >&2
        return 1
      fi

      _image_file="$(__imgname "${_image_url}" "${2:-}")"

      __wget_image "${_image_url}" "${_image_file}"
      __create_image_setup_yml "${_url_a}" "${_url_b}" "${_image_file%.*}" \
        "${_streams[@]}"
    else
      __bad_image_spec "${_image_spec}"
    fi
  else
    vmtools_get_image_cmd "${1}" "${2:-}"
  fi
}
