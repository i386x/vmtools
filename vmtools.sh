#
# File:    ./vmtools.sh
# Author:  Jiří Kučera <sanczes AT gmail.com>
# Date:    2020-03-24 17:36:00 +0100
# Project: Virtual Machine Tools (vmtools)
# Brief:   vmtools shell library
#
# SPDX-License-Identifier: MIT
#

__userhome="${HOME}"
__vmtoolslocaldir="${__userhome}/.vmtools"
__vmtoolsconfig="${__vmtoolslocaldir}/config"
__vmtoolsimagesdir="${__vmtoolslocaldir}/images"
__vmtoolsvmsdir="${__vmtoolslocaldir}/vms"
__artifactsdir="artifacts"
__guest_log="guest.log"
__qemu_log="qemu.log"
__clouddir="cloud"
__cloud_id_rsa="id_rsa"
__cloud_meta_data="meta-data"
__cloud_user_data="user-data"
__cloud_init_iso="cloud-init.iso"
__pidfile="qemu.pid"
__image_list_format='%-30s%-30s%-30s%-30s%s'
__vm_list_format='%-20s%-30s%-25s%s'

if [[ -z "${NOCOLOR:-}" ]]; then
  __creset='\e[0m'
  __cred='\e[31m'
  __cgreen='\e[32m'
  __cblue='\e[34m'
else
  __creset=""
  __cred=""
  __cgreen=""
  __cblue=""
fi

# -----------------------------------------------------------------------------
# -- 1) Helpers
# -----------------------------------------------------------------------------

function __vmpath() {
  echo -n "${__vmtoolsvmsdir}/vm-${1}"
}

function __configpath() {
  echo -n "$(__vmpath "${1}")/config"
}

function __artifactspath() {
  echo -n "$(__vmpath "${1}")/${__artifactsdir}"
}

function __cloudpath() {
  echo -n "$(__vmpath "${1}")/${__clouddir}"
}

function __pidfilepath() {
  echo -n "$(__vmpath "${1}")/${__pidfile}"
}

function __realpath() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "${1}"
  else
    readlink -f "${1}"
  fi
}

function __p_red_n() {
  echo -ne "${__cred}$*${__creset}"
}

function __p_red() {
  __p_red_n "$@"
  echo ""
}

function __p_green_n() {
  echo -ne "${__cgreen}$*${__creset}"
}

function __p_green() {
  __p_green_n "$@"
  echo ""
}

function __p_blue_n() {
  echo -ne "${__cblue}$*${__creset}"
}

function __p_blue() {
  __p_blue_n "$@"
  echo ""
}

function __error() {
  local _exitcode=1

  if [[ "${1:-}" =~ ^[[:digit:]]+$ ]]; then
    _exitcode=${1}
    shift
  fi
  __p_red "$(basename "$0"): $*" >&2
  exit ${_exitcode}
}

function __need_arg() {
  if [[ -z "${1:-}" ]]; then
    __error "${FUNCNAME[1]}: Argument expected."
  fi
}

function __need_var() {
  __need_arg "${1:-}"
  if [[ -z "${!1:-}" ]]; then
    __error "${FUNCNAME[1]}: Variable ${1} is undefined or empty."
  fi
}

function __need_file() {
  __need_arg "${1:-}"
  if [[ ! -s "${1}" ]]; then
    __error "${FUNCNAME[1]}: File ${1} is empty or missing."
  fi
}

function __runcmd() {
  local _error_code=0
  local _stdout=""
  local _cmd=""

  _cmd="$*"
  if [[ "${1}" == --stdout ]]; then
    _stdout="${2}"
    shift 2
    _cmd="$* > ${_stdout}"
  fi
  if [[ -z "${DRY_RUN:-}" ]]; then
    if [[ -z "${_stdout}" ]]; then
      "$@" || _error_code=$?
    else
      "$@" > "${_stdout}" || _error_code=$?
    fi
    if [[ ${_error_code} -ne 0 ]]; then
      __p_red "Command (${_cmd}) ends up with error ${_error_code}." >&2
      return ${_error_code}
    fi
  else
    __p_blue "[dry run] ${_cmd}" >&2
  fi
}

function __cd() {
  __need_arg "${1:-}"
  __runcmd cd "${1}"
}

function __ensure_directory() {
  __need_arg "${1:-}"
  if [[ ! -d "${1}" ]]; then
    __runcmd mkdir -vp "${1}"
  fi
}

function __truncate() {
  __need_arg "${1:-}"
  __runcmd --stdout "${1}" echo -n ""
}

function __source() {
  __need_arg "${1:-}"
  source "${1}" >/dev/null 2>&1 || {
    __error "${FUNCNAME[1]}: Can't source '${1}'."
  }
}

function __softsource() {
  __need_arg "${1:-}"
  if [[ -f "${1}" ]]; then
    __source "${1}"
  fi
}

function __findprog() {
  (
    set +e
    _path=""
    for _prog in "$@"; do
      if [[ "${_prog}" ]]; then
        _path="$(command -v "${_prog}" 2>/dev/null)"
        if [[ "${_path}" ]]; then
          echo -n "${_path}"
          break
        fi
      fi
    done || :
  )
}

function __socketinuse() {
  __need_arg "${1:-}"
  {
    if command -v ss >/dev/null 2>&1; then
      ss -tulwn
    else
      netstat -tulpn
    fi
  } 2>/dev/null | grep "${1}" | grep -q LISTEN
}

function __checkpidfile() {
  local _pidfile=""
  local _pid=0

  __need_arg "${1:-}"
  _pidfile="$(__pidfilepath "${1}")"
  if [[ -f "${_pidfile}" ]]; then
    _pid="$(cat "${_pidfile}")"
    if [[ -f "/proc/${_pid}/status" ]]; then
      __error "VM ${1} is still active. Try \`vmstop ${1}\` to halt it."
    fi
    __runcmd rm -f "${_pidfile}"
  fi
}

# -----------------------------------------------------------------------------
# -- 2) Initialization
# -----------------------------------------------------------------------------

function vmtools_setup() {
  vmtools_init_vmtools_config
  __ensure_directory "${__vmtoolsimagesdir}"
  __ensure_directory "${__vmtoolsvmsdir}"
}

function vmtools_vminit() {
  local _vmdir=""

  __need_arg "${1:-}"
  _vmdir="$(__vmpath "${1}")"

  __checkpidfile "${1}"
  __ensure_directory "${_vmdir}"
  vmtools_init_config "${1}"
  vmtools_vmupdate "${1}"
}

# -----------------------------------------------------------------------------
# -- 3) Update
# -----------------------------------------------------------------------------

function vmtools_vmupdate() {
  __need_arg "${1:-}"
  __checkpidfile "${1}"
  vmtools_genkeys "${1}"
  __create_cloud "${1}"
}

function __create_cloud() {
  local _clouddir=""

  __need_arg "${1:-}"
  _clouddir="$(__cloudpath "${1}")"

  __runcmd rm -vrf "${_clouddir}"
  __runcmd mkdir -vp "${_clouddir}"
  (
    __source "$(__configpath "${1}")"

    __need_var VMCFG_USER
    __need_var VMCFG_PASSWORD
    __need_var VMCFG_ID_RSA
    __need_var VMCFG_ID_RSA_PUB

    __cd "${_clouddir}"

    __need_file "../${VMCFG_ID_RSA_PUB}"

    __runcmd cp -v "../${VMCFG_ID_RSA}" "${__cloud_id_rsa}"
    __runcmd chmod 600 "${__cloud_id_rsa}"
    __runcmd touch "${__cloud_meta_data}"
    __runcmd __create_cloud_user_data "${__cloud_user_data}" \
      "${VMCFG_USER}" "${VMCFG_PASSWORD}" "$(cat "../${VMCFG_ID_RSA_PUB}")"
    __runcmd mkisofs -input-charset utf-8 -volid cidata -joliet -rock \
      -output "${__cloud_init_iso}" \
      "${__cloud_user_data}" "${__cloud_meta_data}"
  )
}

function __create_cloud_user_data() {
  cat > "${1}" <<-__EOF__
	#cloud-config
	users:
	  - default
	  - name: ${2}
	    ssh_authorized_keys:
	      - ${4}
	ssh_pwauth: True
	chpasswd:
	  list: |
	    ${2}:${3}
	  expire: False
	__EOF__
}

# -----------------------------------------------------------------------------
# -- 4) Configuration
# -----------------------------------------------------------------------------

function vmtools_init_vmtools_config() {
  __ensure_directory "${__vmtoolslocaldir}"
  if [[ ! -s "${__vmtoolsconfig}" ]]; then
    __runcmd __create_vmtools_config "${__vmtoolsconfig}"
  fi
}

function __create_vmtools_config() {
  cat > "${1}" <<-_EOF_
	# Virtual Machine Tools configuration.

	# Source your libraries here:

	# Set internal URLs:
	# - composes download hub
	RHUB=""
	# - beaker hub
	BKRHUB=""
	# - brew task repositories hub
	BTRHUB=""

	# A map of aliases used by various commands:
	declare -Ag VMTOOLS_ALIASES=()

	# Editor (if unset, \${EDITOR:-vi} is used):
	VMTOOLS_EDITOR="\${VMTOOLS_EDITOR:-}"

	# Command to get an image. First argument to the command is an image
	# location, second is a name of image file or an image file destination
	# path; the rest of arguments are left to user interpretation. If unset
	# vmtools_get_image_cmd is used:
	VMTOOLS_GET_IMAGE_CMD="\${VMTOOLS_GET_IMAGE_CMD:-}"

	# QEMU command:
	VMTOOLS_QEMU_CMD="\${VMTOOLS_QEMU_CMD:-}"

	# QEMU process name regular expression (if unset, 'qemu' is used):
	VMTOOLS_QEMU_PROC_RE="\${VMTOOLS_QEMU_PROC_RE:-}"

	# CPU limit (determined automatically when unset):
	VMTOOLS_CPU_LIMIT="\${VMTOOLS_CPU_LIMIT:-}"

	# Regular expression for grep that matches VM images (if unset,
	# '\.qcow2$' is used):
	VMTOOLS_IMAGE_RE="\${VMTOOLS_IMAGE_RE:-}"

	# Format of a row printed by vmtools-images (following printf). First
	# column is the image's name, second is the image's type, third is the
	# image's last modification time, fourth is the image's user/group, and
	# the fifth is the image's size. The default format is
	# '${__image_list_format}':
	VMTOOLS_IMAGE_LIST_FORMAT="\${VMTOOLS_IMAGE_LIST_FORMAT:-}"

	# Format of a row printed by vmtools-vms (following printf). First
	# column is the VM's name, second is the VM runner process name and ID,
	# third is the socket, and the fourth is the path to the image. The
	# default format is '${__vm_list_format}':
	VMTOOLS_VM_LIST_FORMAT="\${VMTOOLS_VM_LIST_FORMAT:-}"

	# Path to the Root CA PEM to be installed to the VM. When unset nothing
	# is installed:
	VMTOOLS_ROOT_CA=""
	_EOF_
}

function vmtools_edit_vmtools_config() {
  vmtools_init_vmtools_config
  (
    __softsource "${__vmtoolsconfig}"
    __runcmd "${VMTOOLS_EDITOR:-${EDITOR:-vi}}" "${__vmtoolsconfig}"
  )
}

function vmtools_get_alias() {
  __need_arg "${1:-}"
  (
    __softsource "${__vmtoolsconfig}"

    if [[ "${VMTOOLS_ALIASES[${1}]:-}" ]]; then
      echo -n "${VMTOOLS_ALIASES[${1}]}"
    fi
  )
}

function vmtools_init_config() {
  local _config=""

  __need_arg "${1:-}"
  _config="$(__configpath "${1}")"
  __checkpidfile "${1}"
  if [[ ! -s "${_config}" ]]; then
    __runcmd __create_config_file "${_config}" "${1}"
  fi
}

function __create_config_file() {
  cat > "${1}" <<-_EOF_
	# Configuration for ${2} virtual machine. In case of need, please edit
	# the lines below.

	# Image name:
	VMCFG_IMAGE=""

	# User:
	VMCFG_USER="root"

	# Password:
	VMCFG_PASSWORD="foobar"

	# Host:
	VMCFG_HOST="127.0.0.3"

	# Port:
	VMCFG_PORT="5432"

	# Path to file with private RSA key:
	VMCFG_ID_RSA="id_rsa"

	# Path to file with public RSA key:
	VMCFG_ID_RSA_PUB="id_rsa.pub"

	# RSA key bits:
	VMCFG_RSA_KEY_BITS="4096"

	# RSA key passphrase:
	VMCFG_RSA_KEY_PASSPHRASE=""

	# VM memory size:
	VMCFG_MEMSIZE="4096"

	# VM network NIC model:
	VMCFG_NET_NIC_MODEL="virtio"
	_EOF_
}

function vmtools_edit_config() {
  local _config=""

  __need_arg "${1:-}"
  _config="$(__configpath "${1}")"

  vmtools_init_config "${1}"
  (
    __softsource "${__vmtoolsconfig}"

    __runcmd "${VMTOOLS_EDITOR:-${EDITOR:-vi}}" "${_config}"
  )
}

# -----------------------------------------------------------------------------
# -- 5) SSH & SCP
# -----------------------------------------------------------------------------

function vmtools_genkeys() {
  __need_arg "${1:-}"
  __checkpidfile "${1}"
  (
    __source "$(__configpath "${1}")"

    __need_var VMCFG_ID_RSA
    __need_var VMCFG_ID_RSA_PUB
    __need_var VMCFG_RSA_KEY_BITS

    __cd "$(__vmpath "${1}")"

    __runcmd rm -vf "${VMCFG_ID_RSA}" "${VMCFG_ID_RSA_PUB}"

    __runcmd ssh-keygen \
      -f "${VMCFG_ID_RSA}" -t rsa -b "${VMCFG_RSA_KEY_BITS}" \
      -N "${VMCFG_RSA_KEY_PASSPHRASE:-}" -C "vm-${1}"
    if [[ ! -s "${VMCFG_ID_RSA_PUB}" ]]; then
      __runcmd mv -v "${VMCFG_ID_RSA}.pub" "${VMCFG_ID_RSA_PUB}"
    fi
  )
}

function vmtools_vmsxx() {
  local _sxx=""
  local _vmname=""

  __need_arg "${1:-}"
  __need_arg "${2:-}"
  _sxx="${1}"
  _vmname="${2}"
  shift 2
  (
    __source "$(__configpath "${_vmname}")"

    __need_var VMCFG_USER
    __need_var VMCFG_HOST
    __need_var VMCFG_PORT
    __need_var VMCFG_ID_RSA

    __cd "$(__vmpath "${_vmname}")"

    __need_file "${VMCFG_ID_RSA}"

    declare -a _sxx_params=()
    if [[ "${_sxx}" == scp ]]; then
      _sxx_params+=( -P )
    else
      _sxx_params+=( -p )
    fi
    _sxx_params+=(
      "${VMCFG_PORT}"
      -o "StrictHostKeyChecking=no"
      -o "UserKnownHostsFile=/dev/null"
      -o "LogLevel=ERROR"
      -i "${VMCFG_ID_RSA}"
    )
    if [[ "${_sxx}" == ssh ]]; then
      _sxx_params+=(
        -t
        "${VMUSER:-${VMCFG_USER}}@${VMCFG_HOST}"
        "$@"
      )
    else
      while [[ "${1:-}" ]]; do
        if [[ "${1}" == @* ]]; then
          _sxx_params+=( "${VMUSER:-${VMCFG_USER}}@${VMCFG_HOST}:${1:1}" )
        else
          _sxx_params+=( "${1}" )
        fi
        shift
      done
    fi

    __runcmd "${_sxx}" "${_sxx_params[@]}"
  )
}

function vmtools_vmssh() {
  vmtools_vmsxx ssh "$@"
}

function vmtools_vmscp() {
  vmtools_vmsxx scp "$@"
}

function vmtools_vmping() {
  vmtools_vmssh "${1:-}" /bin/true
}

# -----------------------------------------------------------------------------
# -- 6) Image Management & Cleanup
# -----------------------------------------------------------------------------

function __imgname() {
  local _imgname="${1##*/}"
  local _suffix=""

  if [[ "${2:-}" == *.* ]]; then
    echo -n "${2}"
    return 0
  fi

  if [[ -z "${2:-}" ]]; then
    echo -n "${_imgname}"
    return 0
  fi

  if [[ "${_imgname}" == *.* ]]; then
    _suffix="${_imgname##*.}"
  fi

  echo -n "${2}.${_suffix:-qcow2}"
}

function __copy_image() {
  if [[ -f "${2}" ]]; then
    __error "Image $(__realpath "${2}") already exists."
  fi
  if [[ -d "${2}" ]] && [[ -f "${2}/${1##*/}" ]]; then
    __error "Image $(__realpath "${2}/${1##*/}") already exists."
  fi
  __runcmd cp -v "$@"
}

function __wget_image() {
  local _error_code=0
  local _dest="${2}"
  local _imgfile="${_dest##*/}"

  if [[ -f "${_dest}" ]]; then
    __p_blue "Image $(__realpath "${_dest}") already exists." >&2
    return 0
  fi

  __runcmd wget -O "${_dest}" "${1}" || _error_code=$?
  if [[ ${_error_code} -eq 0 ]]; then
    __p_green "Image ${_imgfile} successfully downloaded." >&2
  else
    __error ${_error_code} \
      "Attempt to get ${_imgfile} from ${1} has failed."
  fi
}

function vmtools_get_image_cmd() {
  if [[ "${1:-}" =~ ^[[:alpha:]]+:.*$ ]]; then
    __wget_image "${1}" "$(__imgname "${1}" "${2:-}")"
  else
    __copy_image "${1}" "$(__imgname "${1}" "${2:-}")"
  fi
}

function vmtools_get_image() {
  __need_arg "${1:-}"
  __ensure_directory "${__vmtoolsimagesdir}"
  (
    __cd "${__vmtoolsimagesdir}"

    __softsource "${__vmtoolsconfig}"

    "${VMTOOLS_GET_IMAGE_CMD:-vmtools_get_image_cmd}" "$@"
  )
}

function vmtools_list_images() {
  (
    __cd "${__vmtoolsimagesdir}"

    __softsource "${__vmtoolsconfig}"

    _format="${VMTOOLS_IMAGE_LIST_FORMAT:-${__image_list_format}}"

    printf "${_format}\n" 'NAME' 'TYPE' 'CHANGED' 'USER/GROUP' 'SIZE' >&2
    while read -r _name; do
      _type="$(file -b "${_name}")"
      _type="${_type%%,*}"
      _changed="$(stat -c '%Y' "${_name}")"
      _changed="$(date --date="@${_changed}" '+%Y-%m-%d %H:%M %z')"
      _user_group="$(stat -c '%U/%G' "${_name}")"
      _size="$(ls -sh "${_name}" | cut -d' ' -f1)"
      printf "${_format}\n" "${_name}" "${_type}" "${_changed}" \
        "${_user_group}" "${_size}"
    done < <(ls -1 | grep -E "${VMTOOLS_IMAGE_RE:-\.qcow2$}")
  )
}

function vmtools_remove_image() {
  __need_arg "${1:-}"
  (
    __cd "${__vmtoolsimagesdir}"

    __softsource "${__vmtoolsconfig}"

    _image="${1}"
    if [[ ! "${_image}" == *.* ]]; then
      _image="${_image}.qcow2"
    fi

    if [[ ! -f "${_image}" ]]; then
      __runcmd rm -vf "${_image%.*}.yml"
      return 0
    fi

    declare -a _in_use=( $(lsof -t "$(__realpath "${_image}")") )
    if [[ ${#_in_use[@]} -gt 0 ]]; then
      __p_red "Image ${_image} is still in use!" \
        " Please, close following processes:" >&2
      __list_vms_by_pids "${_in_use[@]}"
      return 1
    fi

    __runcmd rm -vi "${_image}"
    if [[ ! -f "${_image}" ]]; then
      __runcmd rm -vf "${_image%.*}.yml"
    fi
  )
}

function __wait_ghost() {
  local _i=0

  while [[ ${_i} -lt ${1} ]]; do
    sleep 1
    __p_blue_n "." >&2
    if [[ ! -f "/proc/${2}/status" ]]; then
      return 0
    fi
    _i=$(( _i + 1 ))
  done
  [[ ! -f "/proc/${2}/status" ]]
}

function __kill_ghost() {
  local _vmname="$(__get_vm_name "${1}")"
  local _error_code=0

  if [[ ! "${_vmname}" == \** ]]; then
    return 0
  fi

  __p_blue_n "Killing ghost VM ${_vmname} (PID=${1})..." >&2

  __runcmd kill -SIGTERM "${1}" >/dev/null 2>&1 || _error_code=$?
  if [[ ${_error_code} -eq 0 ]] && __wait_ghost 600 "${1}"; then
    __p_green "[DONE]" >&2
    return 0
  fi

  _error_code=0
  __runcmd kill -9 "${1}" >/dev/null 2>&1 || _error_code=$?
  if [[ ${_error_code} -eq 0 ]] && __wait_ghost 10 "${1}"; then
    __p_green "[DONE]" >&2
    return 0
  fi

  if [[ -f "/proc/${1}/status" ]]; then
    __p_red "[FAIL]" >&2
  else
    _p_green "[DONE]" >&2
  fi
}

function __kill_ghosts() {
  declare -a _pids=( $(__get_qemu_pids) )

  for _pid in "${_pids[@]}"; do
    __kill_ghost "${_pid}"
  done
}

function __remove_artifacts() {
  (
    __cd "${__vmtoolsimagesdir}"

    __runcmd rm -vf ./*.retry

    declare -A _basenames_hist=()
    declare -a _files=( $(ls -1) )
    for _f in "${_files[@]}"; do
      _f="${_f%.*}"
      if [[ -z "${_basenames_hist[${_f}]:-}" ]]; then
        _basenames_hist[${_f}]=0
      fi
      _basenames_hist[${_f}]=$(( ${_basenames_hist[${_f}]} + 1 ))
    done

    for _b in "${!_basenames_hist[@]}"; do
      if [[ ${_basenames_hist[${_b}]} -eq 1 ]]; then
        __runcmd rm -vf "${_b}.yml"
      fi
    done || :
  )
}

function vmtools_cleanup() {
  (
    __softsource "${__vmtoolsconfig}"

    __kill_ghosts
    __remove_artifacts
  )
}

# -----------------------------------------------------------------------------
# -- 7) Launch & Halt
# -----------------------------------------------------------------------------

function vmtools_vmstart() {
  __need_arg "${1:-}"
  __checkpidfile "${1}"
  (
    _pidfile="$(__pidfilepath "${1}")"
    declare -a _qemu_cmds
    declare -a _virtio_rng_devices
    declare -a _qemu_params

    __softsource "${__vmtoolsconfig}"
    __source "$(__configpath "${1}")"

    __need_var VMCFG_IMAGE
    __need_var VMCFG_HOST
    __need_var VMCFG_PORT
    __need_var VMCFG_MEMSIZE
    __need_var VMCFG_NET_NIC_MODEL

    _qemu_cmds=(
      "${VMTOOLS_QEMU_CMD:-}"
      qemu-kvm
      /usr/libexec/qemu-kvm
      /usr/bin/qemu-system-x86_64
    )
    _virtio_rng_devices=(
      virtio-rng
      virtio-rng-pci
      virtio-rng-ccw
    )
    _qemu_params=(
      # Pass through CPU model of host:
      -cpu host
      # Enable KVM full virtualization support:
      -enable-kvm
      # Do not display video output:
      -display none
    )

    _image="${VMCFG_IMAGE}"
    if [[ ! "${_image}" == *.* ]]; then
      _image="${_image}.qcow2"
    fi
    _image="${__vmtoolsimagesdir}/${_image}"
    __need_file "${_image}"
    _image="$(__realpath "${_image}")"

    _cloudinit="$(__cloudpath "${1}")/${__cloud_init_iso}"
    __need_file "${_cloudinit}"
    _cloudinit="$(__realpath "${_cloudinit}")"

    # Check if host and port are free:
    _hostaddr="${VMCFG_HOST}:${VMCFG_PORT}"
    if __socketinuse "${_hostaddr}" || __socketinuse "\*:${VMCFG_PORT}" \
    || __socketinuse ":::${VMCFG_PORT}"; then
      __error "${_hostaddr} is taken."
    fi

    # Artifacts:
    _artifactsdir="$(__artifactspath "${1}")"
    __ensure_directory "${_artifactsdir}"
    _artifactsdir="$(__realpath "${_artifactsdir}")"
    _guest_log="${_artifactsdir}/${__guest_log}"
    _qemu_log="${_artifactsdir}/${__qemu_log}"
    __truncate "${_guest_log}"
    __truncate "${_qemu_log}"

    # Try to find qemu command:
    _qemu_cmd="$(__findprog "${_qemu_cmds[@]}")"
    if [[ -z "${_qemu_cmd}" ]]; then
      __error "Cannot find a command to launch qemu."
    fi

    # Probe virtio-rng device:
    _virtio_rng=""
    for _device in "${_virtio_rng_devices[@]}"; do
      echo "quit" | "${_qemu_cmd}" "${_qemu_params[@]}" -device "${_device}" \
        -S -monitor stdio >/dev/null 2>&1 \
      && {
        _virtio_rng="${_device}"
        break
      }
    done || :

    # Determine the number of CPUs visible to guest:
    _ncpus="${VMTOOLS_CPU_LIMIT:-}"
    if [[ -z "${_ncpus}" ]]; then
      _ncpus="$(lscpu -b -p=Core,Socket | grep -cEe '^[0-9]+,[0-9]+$')"
      if [[ "${_ncpus:-1}" -gt "$(nproc)" ]]; then
        _ncpus="$(nproc)"
      fi
    fi
    if [[ ! "${_ncpus}" =~ ^[1-9][0-9]*$ ]]; then
      __error "${FUNCNAME[0]}: Number of CPUs must be numeric value."
    fi

    _qemu_params+=(
      # Simulate SMP system with obtained number of CPUs:
      -smp "${_ncpus},sockets=${_ncpus},cores=1,threads=1"
      # Set startup RAM size:
      -m "${VMCFG_MEMSIZE}"
      # Add image with OS as a drive:
      -drive "file=${_image},if=virtio"
      # Write to temporary files instead of disk image files:
      -snapshot
      # Use `cloudinit` as CD-ROM image:
      -cdrom "${_cloudinit}"
      # Configure/create an on-board (or machine default) NIC:
      -net "nic,model=${VMCFG_NET_NIC_MODEL}"
      # Configure a host network backend:
      -net "user,hostfwd=tcp:${_hostaddr}-:22"
    )
    # Add a source of randomness:
    if [[ "${_virtio_rng}" ]]; then
      _qemu_params+=( -device "${_virtio_rng}" )
    fi
    _qemu_params+=(
      # Let the RTC start at the current UTC:
      -rtc "base=utc"
      # Connect the virtual serial port with pts2:
      -serial "chardev:pts2"
      # Log all traffic received from the guest to log_quest:
      -chardev "file,id=pts2,path=${_guest_log}"
      # Store the qemu process ID to a file:
      -pidfile "${_pidfile}"
      # Output log to logfile instead of stderr:
      -D "${_qemu_log}"
      # Daemonize:
      -daemonize
    )

    # Launch qemu:
    set +e
    _qemu_ec=0
    __p_blue "Launching VM ${1}..." >&2
    __runcmd "${_qemu_cmd}" "${_qemu_params[@]}" || _qemu_ec=$?
    if [[ "${DRY_RUN:-}" ]]; then
      return 0
    fi

    _failmsg="Launching VM ${1} has failed. See ${_qemu_log} for details."

    if [[ ${_qemu_ec} -ne 0 ]] || [[ ! -s "${_pidfile}" ]]; then
      __error "${_failmsg}"
    fi

    # Wait the launched OS became active:
    _qemu_pid="$(cat "${_pidfile}")"
    _active=""
    sleep 5
    _i=0
    while [[ ${_i} -lt 600 ]]; do
      __p_blue "Waiting to VM ${1} to become ready #$(( _i + 1 ))." >&2
      if [[ ! -f "/proc/${_qemu_pid}/status" ]]; then
        __runcmd rm -f "${_pidfile}"
        __error "${_failmsg}"
      fi
      if vmtools_vmping "${1}"; then
        _active="y"
        break
      fi
      sleep 3
      _i=$(( _i + 1 ))
    done

    if [[ -z "${_active}" ]]; then
      __error "Unable to connect to launched VM ${1}. Killing."
      kill -SIGTERM "${_qemu_pid}"
      __runcmd rm -f "${_pidfile}"
    fi

    __p_green "VM ${1} is ready." >&2
  )
}

function vmtools_vmstop() {
  local _error_code=0

  __need_arg "${1:-}"

  __vmstatusq "${1}" || {
    __p_blue "VM ${1} is already halted." >&2
    return 0
  }

  __vmsshq "${1}" "shutdown -h now" || _error_code=$?
  if [[ ${_error_code} -eq 0 ]] && __vmwait "${1}"; then
    return 0
  fi

  _error_code=0
  __vmkillq "${1}" SIGTERM || _error_code=$?
  if [[ ${_error_code} -eq 0 ]] && __vmwait "${1}"; then
    return 0
  fi

  _error_code=0
  __vmkillq "${1}" 9 || _error_code=$?
  if [[ ${_error_code} -eq 0 ]] && __vmwait "${1}" 10; then
    return 0
  fi

  __error "Unable to halt VM ${1}. Please, check it manually."
}

function __vmsshq() {
  vmtools_vmssh "$@" >/dev/null 2>&1
}

function __vmkillq() {
  vmtools_vmkill "$@" >/dev/null 2>&1
}

function vmtools_vmkill() {
  __need_arg "${1:-}"
  __need_arg "${2:-}"

  __vmstatusq "${1}" || {
    __p_blue "VM ${1} is halted." >&2
    return 0
  }
  __runcmd kill "-${2}" "$(cat "$(__pidfilepath "${1}")")"
}

function __vmwait() {
  local _i=0

  while [[ ${_i} -lt ${2:-600} ]]; do
    __p_blue "Waiting for VM ${1} to become halted #$(( _i + 1 ))." >&2
    sleep 1
    __vmstatusq "${1}" || {
      __p_green "VM ${1} was successfully halted." >&2
      return 0
    }
    _i=$(( _i + 1 ))
  done
  return 1
}

function __vmstatusq() {
  vmtools_vmstatus "$@" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# -- 8) Status
# -----------------------------------------------------------------------------

function __get_vm_name() {
  local _vmname=""
  declare -a _tempa=()

  # Get the virtual machine name in the form of *NAME; star is optional and
  # means that virtual machine has been deleted:
  while read -r _item; do
    if [[ "${_item}" == n*${__pidfile} ]]; then
      _vmname="${_item:1}"
      break
    fi
  done < <(lsof -p "${1}" -P -n -F pn)
  # Get the VM name:
  _vmname="${_vmname%/*}"
  _vmname="${_vmname##*/}"
  # Strip the vm- prefix:
  _vmname="${_vmname#vm-}"
  # Assemble output:
  if [[ -z "${_vmname}" ]]; then
    _vmname='???'
  elif [[ ! -d "$(__vmpath "${_vmname}")" ]]; then
    _vmname="*${_vmname}"
  fi
  # Output:
  echo -n "${_vmname}"
}

function __list_vms_by_pids() {
  local _format="${VMTOOLS_VM_LIST_FORMAT:-${__vm_list_format}}"
  local _pid=""
  local _vmname=""
  local _command=""
  local _process=""
  local _socket=""
  local _image=""
  local _deleted="n"
  local _type=""

  printf "${_format}\n" 'VM NAME' 'PROCESS (ID)' 'SOCKET' 'IMAGE' >&2
  for _pid in "$@"; do
    # Get VM name:
    _vmname="$(__get_vm_name "${_pid}")"
    # Get the socket, process name and ID, and image:
    _command=""
    _process=""
    _socket=""
    _image=""
    _deleted="n"
    _type=""
    while read -r _item; do
      case "${_item}" in
        p*) [[ "${_process}" ]] || _process="${_item:1}" ;;
        c*) [[ "${_command}" ]] || _command="${_item:1}" ;;
        t*) _type="${_item:1}" ;;
        n*)
          _item="${_item:1}"
          _deleted="n"
          if [[ "${_type}" == REG ]]; then
            if [[ "${_item}" == *\ \(deleted\) ]]; then
              _deleted="y"
              _item="${_item::-10}"
            fi
            if [[ "${_item}" =~ ${VMTOOLS_IMAGE_RE:-\.qcow2$} ]]; then
              if [[ -z "${_image}" ]]; then
                _image="${_item}"
                [[ "${_deleted}" == n ]] || _image="(${_image})"
              fi
            fi
          elif [[ "${_type}" == IPv4 ]]; then
            [[ "${_socket}" ]] || _socket="${_item}"
          fi
          ;;
      esac
    done < <(lsof -p "${_pid}" -sTCP:LISTEN -P -n -F cptn)
    _socket="${_socket:-N/A}"
    _process="${_command} (${_process})"
    _image="${_image:-N/A}"
    # Print the row:
    printf "${_format}\n" "${_vmname}" "${_process}" "${_socket}" "${_image}"
  done
}

function __get_qemu_pids() {
  local _qemu_proc_re="${VMTOOLS_QEMU_PROC_RE:-qemu}"

  ps -A | grep -E "${_qemu_proc_re}" | sed -Ee 's/^[ ]+//g' | cut -d' ' -f1
}

function vmtools_vms() {
  (
    __softsource "${__vmtoolsconfig}"

    declare -a _pids=( $(__get_qemu_pids) )
    __list_vms_by_pids "${_pids[@]}"
  )
}

function vmtools_vmstatus() {
  local _pidfile=""
  local _qemu_pid=""

  __need_arg "${1:-}"
  _pidfile="$(__pidfilepath "${1}")"

  if [[ ! -f "${_pidfile}" ]]; then
    __p_red "Halted" >&2
    return 1
  fi

  _qemu_pid="$(cat "${_pidfile}")"

  if [[ ! -f "/proc/${_qemu_pid}/status" ]]; then
    __runcmd rm -f "${_pidfile}"
    __p_red "Halted" >&2
    return 1
  fi

  __p_green "Active" >&2
}

# -----------------------------------------------------------------------------
# -- 9) Ansible
# -----------------------------------------------------------------------------

function vmtools_vmplay() {
  __need_arg "${1:-}"
  (
    declare -a _pythons=(
      /usr/bin/python3
      /usr/bin/python2
      /usr/libexec/platform-python
    )

    __source "$(__configpath "${1}")"

    __need_var VMCFG_USER
    __need_var VMCFG_PASSWORD
    __need_var VMCFG_HOST
    __need_var VMCFG_PORT
    __need_var VMCFG_ID_RSA
    _id_rsa="$(__vmpath "${1}")/${VMCFG_ID_RSA}"
    __need_file "${_id_rsa}"

    _ssh_common_args="-o UserKnownHostsFile=/dev/null"
    _ssh_common_args="${_ssh_common_args} -o StrictHostKeyChecking=no"

    _python=""
    for _i in "${_pythons[@]}"; do
      if __vmsshq "${1}" "test -x ${_i}"; then
        _python="${_i}"
        break
      fi
    done

    shift

    _ansible_vars=""
    while [[ "${1:-}" =~ ^([^=]+)=(.+)$ ]]; do
      _ansible_vars="${_ansible_vars},\"${BASH_REMATCH[1]}\""
      _ansible_vars="${_ansible_vars}:\"${BASH_REMATCH[2]}\""
      shift
    done

    _extra_vars=$(
      echo -n "{\"ansible_host\":\"${VMCFG_HOST}\""
      echo -n ",\"ansible_port\":\"${VMCFG_PORT}\""
      echo -n ",\"ansible_user\":\"${VMCFG_USER}\""
      echo -n ",\"ansible_ssh_pass\":\"${VMCFG_PASSWORD}\""
      echo -n ",\"ansible_ssh_private_key_file\":\"${_id_rsa}\""
      echo -n ",\"ansible_ssh_common_args\":\"${_ssh_common_args}\""
      if [[ "${_python}" ]]; then
        echo -n ",\"ansible_python_interpreter\":\"${_python}\""
      fi
      echo -n "${_ansible_vars}"
      echo -n "}"
    )

    _verbosity_level="${V:-0}"
    _v=""
    while [[ ${_verbosity_level} -gt 0 ]]; do
      _v="${_v}v"
      _verbosity_level=$(( _verbosity_level - 1 ))
    done
    if [[ "${_v}" ]]; then
      _v="-${_v}"
    fi

    __runcmd ansible-playbook \
      ${_v} -i "${VMCFG_HOST}," -e "${_extra_vars}" "$@"
  )
}

# -----------------------------------------------------------------------------
# -- 10) Setup
# -----------------------------------------------------------------------------

function vmtools_vmsetup() {
  __need_arg "${1:-}"
  (
    __source "$(__configpath "${1}")"

    _vmname="${1}"

    shift

    declare -a _posargs=()
    while [[ "${1:-}" == *=* ]]; do
      _posargs+=( "${1}" )
      shift
    done

    if [[ -z "${1:-}" ]]; then
      __need_var VMCFG_IMAGE
      _setup_yml="${__vmtoolsimagesdir}/${VMCFG_IMAGE%.*}.yml"
      if [[ ! -s "${_setup_yml}" ]]; then
        return 0
      fi
      _posargs+=( "${_setup_yml}" )
    else
      _posargs+=( "$@" )
    fi

    vmtools_vmplay "${_vmname}" "${_posargs[@]}"
  )
}
