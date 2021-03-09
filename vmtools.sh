# SPDX-License-Identifier: MIT
#
# File:    vmtools.sh
# Author:  Jiří Kučera, <sanczes@gmail.com>
# Date:    2020-03-24 17:36:00 +0100
# Project: Virtual Machine Tools (vmtools)
# Brief:   vmtools shell library.
#

# shellcheck source=/usr/local/share/clishe/clishe.sh
PATH="/usr/local/share/clishe:/usr/share/clishe${PATH:+:}${PATH}" \
. clishe.sh >/dev/null 2>&1 || {
  echo "clishe library is not installed" >&2
  exit 1
}

__wd="${PWD:-$(pwd)}"

__userhome="${HOME}"
__userhome_lit="\${HOME}"
__vmtoolslocaldir="${__userhome}/.vmtools"
__vmtoolslocaldir_lit="${__userhome_lit}/.vmtools"
__vmtoolsconfig="${__vmtoolslocaldir}/config"
__vmtoolsimagesdir="${__vmtoolslocaldir}/images"
__vmtoolsimagesdir_lit="${__vmtoolslocaldir_lit}/images"
__vmcachedir=".vmcache"
__artifactsdir="artifacts"
__guest_log="guest.log"
__qemu_log="qemu.log"
__clouddir="cloud"
__cloud_id_rsa="id_rsa"
__cloud_meta_data="meta-data"
__cloud_user_data="user-data"
__cloud_init_iso="cloud-init.iso"
__pidfile="qemu.pid"

# -----------------------------------------------------------------------------
# -- 1) Helpers
# -----------------------------------------------------------------------------

function __workspacepath() {
  echo -n "${__wd}/${__vmcachedir}/vm-${1}"
}

function __configpath() {
  echo -n "$(__workspacepath "${1}")/config"
}

function __gitignorepath() {
  echo -n "$(__workspacepath "${1}")/.gitignore"
}

function __artifactspath() {
  echo -n "$(__workspacepath "${1}")/${__artifactsdir}"
}

function __cloudpath() {
  echo -n "$(__workspacepath "${1}")/${__clouddir}"
}

function __pidfilepath() {
  echo -n "$(__workspacepath "${1}")/${__pidfile}"
}

function __realpath() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "${1}"
  else
    readlink -f "${1}"
  fi
}

function __need_arg() {
  if [[ -z "${1:-}" ]]; then
    clishe_error "${FUNCNAME[1]}: Argument expected."
  fi
}

function __need_var() {
  __need_arg "${1:-}"
  if [[ -z "${!1:-}" ]]; then
    clishe_error "${FUNCNAME[1]}: Variable ${1} is undefined or empty."
  fi
}

function __need_file() {
  __need_arg "${1:-}"
  if [[ ! -s "${1}" ]]; then
    clishe_error "${FUNCNAME[1]}: File ${1} is empty or missing."
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
      clishe_echo --red "Command (${_cmd}) ends up with error ${_error_code}."
      return ${_error_code}
    fi
  else
    clishe_echo --blue "[dry run] ${_cmd}"
  fi
}

function __cd() {
  __need_arg "${1:-}"
  __runcmd cd "${1}"
}

function __ensure_directory() {
  __need_arg "${1:-}"
  if [[ ! -d "${1}" ]]; then
    __runcmd mkdir -v -p "${1}"
  fi
}

function __truncate() {
  __need_arg "${1:-}"
  __runcmd --stdout "${1}" echo -n ""
}

function __source() {
  __need_arg "${1:-}"
  source "${1}" >/dev/null 2>&1 || {
    clishe_error "${FUNCNAME[1]}: Can't source ${1}"
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
      clishe_error "VM ${1} is still active. Try \`vmstop ${1}\` to halt it."
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
}

function vmtools_vminit() {
  local _workspacedir=""

  __need_arg "${1:-}"
  _workspacedir="$(__workspacepath "${1}")"

  __checkpidfile "${1}"
  __ensure_directory "${_workspacedir}"
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

  __runcmd rm -v -rf "${_clouddir}"
  __runcmd mkdir -v -p "${_clouddir}"
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
    __runcmd genisoimage -input-charset utf-8 -volid cidata -joliet -rock \
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

	# Editor:
	VMTOOLS_EDITOR="\${VMTOOLS_EDITOR:-\${EDITOR:-vi}}"

	# Command to get an image. First argument to the command is an image
	# location, second is a name of image file or an image file destination
	# path; the rest of arguments are left to user interpretation:
	VMTOOLS_GET_IMAGE_CMD="vmtools_get_image_cmd"

	# QEMU command:
	VMTOOLS_QEMU_CMD=""
	_EOF_
}

function vmtools_edit_vmtools_config() {
  vmtools_init_vmtools_config
  (
    __softsource "${__vmtoolsconfig}"
    __runcmd "${VMTOOLS_EDITOR:-${EDITOR:-vi}}" "${__vmtoolsconfig}"
  )
}

function vmtools_init_config() {
  local _config=""

  __need_arg "${1:-}"
  _config="$(__configpath "${1}")"
  _gitignore="$(__gitignorepath "${1}")"
  __checkpidfile "${1}"
  if [[ ! -s "${_config}" ]]; then
    __runcmd __create_config_file "${_config}" "${1}"
  fi
  if [[ ! -s "${_gitignore}" ]]; then
    __runcmd __create_gitignore "${_gitignore}"
  fi
}

function __create_config_file() {
  cat > "${1}" <<-_EOF_
	# Configuration for ${2} virtual machine. In case of need, please edit
	# the lines below.

	# Path to image (absolute or relative to working directory):
	VMCFG_IMAGE="${__vmtoolsimagesdir_lit}"

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

	# Path to the Ansible playbook to setup virtual machine:
	VMCFG_SETUP_YML="\${VMCFG_IMAGE%.*}.yml"
	_EOF_
}

function __create_gitignore() {
  cat > "${1}" <<-_EOF_
	*
	!.gitignore
	!config
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
# -- 5) SSH
# -----------------------------------------------------------------------------

function vmtools_genkeys() {
  __need_arg "${1:-}"
  __checkpidfile "${1}"
  (
    __source "$(__configpath "${1}")"

    __need_var VMCFG_ID_RSA
    __need_var VMCFG_ID_RSA_PUB
    __need_var VMCFG_RSA_KEY_BITS

    __cd "$(__workspacepath "${1}")"

    __runcmd rm -v -f "${VMCFG_ID_RSA}" "${VMCFG_ID_RSA_PUB}"

    __runcmd ssh-keygen \
      -f "${VMCFG_ID_RSA}" -t rsa -b "${VMCFG_RSA_KEY_BITS}" \
      -N "${VMCFG_RSA_KEY_PASSPHRASE:-}" -C "vm-${1}"
    if [[ ! -s "${VMCFG_ID_RSA_PUB}" ]]; then
      __runcmd mv -v "${VMCFG_ID_RSA}.pub" "${VMCFG_ID_RSA_PUB}"
    fi
  )
}

function vmtools_vmssh() {
  local _vmname=""

  __need_arg "${1:-}"
  _vmname="${1}"
  shift
  (
    __source "$(__configpath "${_vmname}")"

    __need_var VMCFG_USER
    __need_var VMCFG_HOST
    __need_var VMCFG_PORT
    __need_var VMCFG_ID_RSA

    __cd "$(__workspacepath "${_vmname}")"

    __need_file "${VMCFG_ID_RSA}"

    declare -a _ssh_params
    _ssh_params=(
      -p "${VMCFG_PORT}"
      -o "StrictHostKeyChecking=no"
      -o "UserKnownHostsFile=/dev/null"
      -o "LogLevel=ERROR"
      -i "${VMCFG_ID_RSA}"
      -t
      "${VMUSER:-${VMCFG_USER}}@${VMCFG_HOST}"
      "$@"
    )

    __runcmd ssh "${_ssh_params[@]}"
  )
}

function vmtools_vmping() {
  vmtools_vmssh "${1:-}" /bin/true
}

# -----------------------------------------------------------------------------
# -- 6) Image Management
# -----------------------------------------------------------------------------

function __copy_image() {
  if [[ -f "${2}" ]]; then
    clishe_error "Image $(__realpath "${2}") already exists."
  fi
  if [[ -d "${2}" ]] && [[ -f "${2}/${1##*/}" ]]; then
    clishe_error "Image $(__realpath "${2}/${1##*/}") already exists."
  fi
  __runcmd cp -v "$@"
}

function __wget_image() {
  local _error_code=0
  local _dest="${2}"
  local _imgfile="${_dest##*/}"

  if [[ -f "${_dest}" ]]; then
    clishe_echo --blue "Image $(__realpath "${_dest}") already exists."
    return
  fi

  __runcmd wget -O "${_dest}" "${1}" || _error_code=$?
  if [[ ${_error_code} -eq 0 ]]; then
    clishe_echo --green "Image ${_imgfile} successfully downloaded."
  else
    clishe_error ${_error_code} \
      "Attempt to get ${_imgfile} from ${1} has failed."
  fi
}

function __cisy_warn() {
  clishe_echo --yellow "${1} Please create your image setup playbook manually."
}

function __create_image_setup_yml() {
  local _url_parts="${1}"
  local _image="${2##*/}"
  local _hub=""
  local _release=""
  local _composever=""
  local _template=""
  local _arch=""

  # Guess the hub
  if [[ "${_url_parts}" =~ ^([[:alpha:]]+://[^/]+)/(.*)$ ]]; then
    _hub="${BASH_REMATCH[1]}"
    _url_parts="${BASH_REMATCH[2]}"
  else
    __cisy_warn "URL <${1}> has invalid format."
    return
  fi

  # Guess the release and compose version
  if [[ "${_url_parts}" =~ ^released/[^/]+/([^/]+)/.*$ ]]; then
    _release="${BASH_REMATCH[1]}"
    _template="rhel-released-setup"
  elif [[ "${_url_parts}" =~ ^[^/]+/composes/[^/]+/([^/]+)/.*$ ]]; then
    _composever="${BASH_REMATCH[1]}"
    _template="rhel-compose-setup"
  else
    __cisy_warn "Release or compose version cannot be guessed from <${1}>."
    return
  fi

  # Guess the release from the compose id
  if [[ -z "${_release}" ]]; then
    if [[ "${_composever}" =~ ^RHEL-([^-]+)-(.+)$ ]]; then
      _release="${BASH_REMATCH[1]}"
      _composever="${BASH_REMATCH[2]}"
    else
      __cisy_warn "Can't guess release from compose id."
    fi
  fi

  # Verify that the release has valid form (hopefully this could catch changes
  # in the hub's layout)
  [[ "${_release}" =~ ^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$ ]] || {
    __cisy_warn "Release string '${_release}' has invalid form."
    return
  }

  # Add -alpha, -beta, etc. to the release
  if [[ "${3:-}" ]]; then
    _release="${_release}-${3}"
  fi

  # Guess architecture from the image name
  _arch="${_image%.*}"
  _arch="${_arch##*.}"

  # Verify the architecture
  [[ "${_arch}" =~ ^(aarch64|ppc64le|s390x|x86_64)$ ]] || {
    __cisy_warn "Unknown architecture '${_arch}'."
    return
  }

  # Prepare parameters
  _extra_vars=$(
    echo -n "{\"pkmaint_task\":\"create_image_setup\""
    echo -n ",\"pkmaint_imagebase\":\"${_image%.*}\""
    echo -n ",\"pkmaint_image_setup_template\":\"${_template}\""
    echo -n ",\"hub\":\"${_hub}\""
    echo -n ",\"release\":\"${_release}\""
    echo -n ",\"composever\":\"${_composever}\""
    echo -n ",\"arch\":\"${_arch}\""
    echo -n "}"
  )

  # Generate the setup playbook
  __runcmd ansible all -c local -i localhost, \
    -m import_role -a 'name=pkmaint' -e "${_extra_vars}" \
  || __cisy_warn "Creating ${_image%.*}.yml has failed."
}

function vmtools_get_image_cmd() {
  local _dest=""
  local _release_phase=""

  __need_arg "${1:-}"

  if [[ "${1}" =~ ^[[:alpha:]]+:.*$ ]]; then
    case $# in
      1)
        _dest="${1##*/}"
        ;;
      2)
        if [[ "${2}" == *.qcow2 ]]; then
          _dest="${2}"
        else
          _dest="${1##*/}"
          _release_phase="${2}"
        fi
        ;;
      *)
        _dest="${2}"
        _release_phase="${3}"
        ;;
    esac
    __wget_image "${1}" "${_dest}"
    __create_image_setup_yml "${1}" "${_dest}" "${_release_phase}"
  else
    __copy_image "${1}" "${2:-.}"
  fi
}

function vmtools_get_image() {
  __ensure_directory "${__vmtoolsimagesdir}"
  (
    __cd "${__vmtoolsimagesdir}"

    __softsource "${__vmtoolsconfig}"

    "${VMTOOLS_GET_IMAGE_CMD:-vmtools_get_image_cmd}" "${1:-}" "${2:-}"
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
    __need_file "${VMCFG_IMAGE}"
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

    _image="$(__realpath "${VMCFG_IMAGE}")"
    _cloudinit="$(__cloudpath "${1}")/${__cloud_init_iso}"
    __need_file "${_cloudinit}"
    _cloudinit="$(__realpath "${_cloudinit}")"

    # Check if host and port are free:
    _hostaddr="${VMCFG_HOST}:${VMCFG_PORT}"
    if __socketinuse "${_hostaddr}"; then
      clishe_error "${_hostaddr} is taken."
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
      clishe_error "Cannot find a command to launch qemu."
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
    _ncpus="${STR_CPU_LIMIT:-}"
    if [[ -z "${_ncpus}" ]]; then
      _ncpus="$(lscpu -b -p=Core,Socket | grep -cEe '^[0-9]+,[0-9]+$')"
      if [[ "${_ncpus:-1}" -gt "$(nproc)" ]]; then
        _ncpus="$(nproc)"
      fi
    fi
    if [[ ! "${_ncpus}" =~ ^[1-9][0-9]*$ ]]; then
      clishe_error "${FUNCNAME[0]}: Number of CPUs must be numeric value."
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
    clishe_echo --blue "Launching VM ${1}..."
    __runcmd "${_qemu_cmd}" "${_qemu_params[@]}" || _qemu_ec=$?
    if [[ "${DRY_RUN:-}" ]]; then
      return 0
    fi

    _failmsg="Launching VM ${1} has failed. See ${_qemu_log} for details."

    if [[ ${_qemu_ec} -ne 0 ]] || [[ ! -s "${_pidfile}" ]]; then
      clishe_error "${_failmsg}"
    fi

    # Wait the launched OS became active:
    _qemu_pid="$(cat "${_pidfile}")"
    _active=""
    sleep 5
    _i=0
    while [[ ${_i} -lt 600 ]]; do
      clishe_echo --blue "Waiting to VM ${1} to become ready #$(( _i + 1 ))."
      if [[ ! -f "/proc/${_qemu_pid}/status" ]]; then
        __runcmd rm -f "${_pidfile}"
        clishe_error "${_failmsg}"
      fi
      if vmtools_vmping "${1}"; then
        _active="y"
        break
      fi
      sleep 3
      _i=$(( _i + 1 ))
    done

    if [[ -z "${_active}" ]]; then
      clishe_error "Unable to connect to launched VM ${1}. Killing."
      kill -SIGTERM "${_qemu_pid}"
      __runcmd rm -f "${_pidfile}"
    fi

    clishe_echo --green "VM ${1} is ready."
  )
}

function vmtools_vmstop() {
  local _error_code

  __need_arg "${1:-}"

  __vmstatusq "${1}" || {
    clishe_echo --blue "VM ${1} is already halted."
    return 0
  }

  _error_code=0
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
  if [[ ${_error_code} -eq 0 ]] && __vmwait "${1}" 5; then
    return 0
  fi

  clishe_error "Unable to halt VM ${1}. Please, check it manually."
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
    clishe_echo --blue "VM ${1} is halted."
    return 0
  }
  __runcmd kill "-${2}" "$(cat "$(__pidfilepath "${1}")")"
}

function __vmwait() {
  local _i=0

  while [[ ${_i} -lt ${2:-600} ]]; do
    clishe_echo --blue "Waiting for VM ${1} to become halted #$(( _i + 1 ))."
    sleep 1
    __vmstatusq "${1}" || {
      clishe_echo --green "VM ${1} was successfully halted."
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

function vmtools_vmstatus() {
  local _pidfile=""
  local _qemu_pid=""

  __need_arg "${1:-}"
  _pidfile="$(__pidfilepath "${1}")"

  if [[ ! -f "${_pidfile}" ]]; then
    clishe_echo --red "Halted"
    return 1
  fi

  _qemu_pid="$(cat "${_pidfile}")"

  if [[ ! -f "/proc/${_qemu_pid}/status" ]]; then
    __runcmd rm -f "${_pidfile}"
    clishe_echo --red "Halted"
    return 1
  fi

  clishe_echo --green "Active"
  return 0
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
    _id_rsa="$(__workspacepath "${1}")/${VMCFG_ID_RSA}"
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
      while [[ "${1:-}" =~ ^([^=]+)=(.+)$ ]]; do
        echo -n ",\"${BASH_REMATCH[1]}\":\"${BASH_REMATCH[2]}\""
        shift
      done
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
      if [[ -z "${VMCFG_SETUP_YML:-}" ]]; then
        clishe_echo --red \
          "Ansible playbook is not provided or VMCFG_SETUP_YML is not set in" \
          "${_vmname}'s config."
        return 1
      fi
      _posargs+=( "${VMCFG_SETUP_YML}" )
    else
      _posargs+=( "$@" )
    fi

    vmtools_vmplay "${_vmname}" "${_posargs[@]}"
  )
}
