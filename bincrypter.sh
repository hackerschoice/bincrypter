#! /usr/bin/env bash

# set PASSWORD=<password> to use a specific password. This password will be asked
# for at execution unless provided by PASSWORD=<password> environment variable.
#
# https://github.com/hackerschoice/bincrypter

[ -t 2 ] && {
CDR="\033[0;31m" # red
CDG="\033[0;32m" # green
CDY="\033[0;33m" # yellow
CDM="\033[0;35m" # magenta
CM="\033[1;35m" # magenta
CDC="\033[0;36m" # cyan
CN="\033[0m"     # none
CF="\033[2m"     # faint
}

# %%BEGIN_BC_FUNC%%
_bincrypter() {
    local str ifn fn s c DATA P _P S HOOK _PASSWORD
    # local DEBUG=1
    local USE_PERL=1
    local _BC_QUIET="${_OPT_BC_QUIET:-$BC_QUIET}"
    local _BC_LOCK="${_OPT_BC_LOCK:-$BC_LOCK}"

    # vampiredaddy wants this to work if dd + tr are not available:
    if [ -n "$USE_PERL" ]; then
        _bc_xdd() { [ -z "$DEBUG" ] && LANG=C perl -e 'read(STDIN,$_, '"$1"'); print;'; }
        _bc_xtr() { LANG=C perl -pe 's/['"${1}${2}"']//g;'; }
        _bc_xprintf() { LANG=C perl -e "print(\"$1\")"; }
    else
        _bc_xdd() { [ -z "$DEBUG" ] && dd bs="$1" count=1 2>/dev/null;}
        _bc_xtr() { tr -d"${1:+c}" "${2}";}
        _bc_xprintf() { printf "$@"; }
    fi

    _bc_err() { echo -e >&2 "${CDR}ERROR${CN}: $*"; exit 255; }
    # Obfuscate a string with non-printable characters at random intervals.
    # Input must not contain \ (or sh gets confused)
    _bc_ob64() {
        local i
        local h="$1"
        local str
        local x
        local s

        # Always start with non-printable character
        s=0
        while [ ${#h} -gt 0 ]; do
            i=$((1 + RANDOM % 4))
            str+=${h:0:$s}
            [ ${#x} -le $i ] && x=$(_bc_xdd 128 </dev/urandom | _bc_xtr '' '[:print:]\0\n\t')
            str+=${x:0:$i}
            x=${x:$i}
            h=${h:$s}
            s=$((1 + RANDOM % 3))
        done
        echo "$str"
    }

    # Obfuscate a string with `#\b`
    _bc_obbell() {
        local h="$1"
        local str
        local x
        local s

        [ -n "$DEBUG" ] && { echo "$h"; return; }
        while [ ${#h} -gt 0 ]; do
            s=$((1 + RANDOM % 4))
            str+=${h:0:$s}
            if [ $((RANDOM % 2)) -eq 0 ]; then
                str+='`#'$'\b''`' #backspace
            else
                str+='`:||'$'\a''`' #alert/bell
            fi
            h=${h:$s}
        done
        echo "$str"
    }

    # Sets _P
    # Return 0 to continue. Otherwise caller should return.
    # May exit if bin is executed on another host (BC_LOCK).
    _bcl_gen_p() {
        local _k
        # Binary is LOCKED to this host. Check if this is the same host to allow execution.
        _k="$(_bcl_get)" && _P="$(echo "$1" | openssl enc -d -aes-256-cbc -md sha256 -nosalt -k "$_k" -a -A 2>/dev/null)"

        [ -n "$_P" ] && return 0
        [ -n "$fn" ] && {
            # sourced
            unset BCL BCV _P P S fn
            unset -f _bcl_get _bcl_verify _bcl_verify_dec
            return 255
        }
        # base64 to string
        BCL="$(echo "$BCL" | openssl base64 -d -A 2>/dev/null)"
        [ "$BCL" -eq "$BCL" ] 2>/dev/null && exit "$BCL"
        exec /bin/sh -c "$BCL"
        exit 255 # FATAL
    }
    _bcl_gen() {
        local _k
        local p
        # P:=Encrypt(P) using _bcl_get as key
        _k="$(_bcl_get)"
        [ -z "$_k" ] && { echo -e >&2 "${CDR}ERROR${CN}: BC_LOCK not supported on this system"; return 255; }
        p="$(echo "$P" | openssl enc -aes-256-cbc -md sha256 -nosalt -k "${_k}" -a -A 2>/dev/null)"
        [ -z "$p" ] && { echo -e >&2 "${CDR}ERROR${CN}: Failed to generate BC_LOCK password"; return 255; }
        P="$p"
        str+="$(declare -f _bcl_verify_dec)"$'\n'
        str+="_bcl_verify() { _bcl_verify_dec \"\$@\"; }"$'\n'
        str+="$(declare -f _bcl_get)"$'\n'
        str+="$(declare -f _bcl_gen_p)"$'\n'
        str+="BCL='$(openssl base64 -A <<<"${_BC_LOCK}")'"$'\n'
        # Add test value
        str+="BCV='$(echo TEST-VALUE-VERIFY | openssl enc -aes-256-cbc -md sha256 -nosalt -k "${_k}" -a -A 2>/dev/null)'"$'\n'
    }
    # Test a key candidate and on success output the candidate to STDOUT.
    _bcl_verify_dec() {
        [ "TEST-VALUE-VERIFY" != "$(echo "$BCV" | openssl enc -d -aes-256-cbc -md sha256 -nosalt -k "${1}-${UID}" -a -A 2>/dev/null)" ] && return 255
        echo "$1-${UID}"
    }
    # Encrypt & Decrypt BCV for testing.
    _bcl_verify() {
        # [ "TEST-VALUE-VERIFY" != "$(echo "$BCV" | openssl enc -d -aes-256-cbc -md sha256 -nosalt -k "${1}" -a -A 2>/dev/null)" ] && return 255
        echo "$1-${UID}"
    }
    # Generate a LOCK key and output it to STDOUT (if valid).
    # This script uses the above bcl_verify but the decoder uses its own
    # bcl_verify as a trampoline to call bcl_verify_dec.
    # FIXME: Consider cases where machine-id changes. Fallback to dmidecode and others....
    _bcl_get() {
        [ -z "$UID" ] && UID="$(id -u 2>/dev/null)"
        [ -f "/etc/machine-id" ] && _bcl_verify "$(cat "/etc/machine-id")" && return
        command -v dmidecode >/dev/null && _bcl_verify "$(dmidecode -t 1 2>/dev/null | LANG=C perl -ne '/UUID/ && print')" && return
        _bcl_verify "$(fdisk -l 2>/dev/null | grep -i identifier 2>/dev/null | head -n1 2>/dev/null)" && return
    }

    command -v openssl >/dev/null || _bc_err "openssl is required"
    fn="-"
    [ -t 0 ] && [ $# -eq 0 ] && _bc_err "Usage: ${CDC}$0 <file> [<password>]${CN} ${CF}#[use - for stdin]${CN}"
    [ -n "$1" ] && fn="$1"
    [ "$fn" != "-" ] && [ ! -f "$fn" ] && _bc_err "File not found: $fn"

    # Auto-generate password if not provided
    _PASSWORD="${2:-${BC_PASSWORD:-$PASSWORD}}"
    [ -z "$_PASSWORD" ] && P="$(DEBUG='' _bc_xdd 32 </dev/urandom | openssl base64 -A | _bc_xtr '^' '[:alnum:]' | DEBUG='' _bc_xdd 16)"
    _P="${_PASSWORD:-$P}"
    [ -z "$_P" ] && _bc_err "No ${CDC}PASSWORD=<password>${CN} provided and failed to generate one."
    unset _PASSWORD

    # Auto-generate SALT
    S="$(DEBUG='' _bc_xdd 32 </dev/urandom | openssl base64 -A | _bc_xtr '^' '[:alnum:]' | DEBUG='' _bc_xdd 16)"

    # base64 encoded decrypter
    HOOK='Zm9yIHggaW4gb3BlbnNzbCBwZXJsIGd1bnppcDsgZG8KICAgIGNvbW1hbmQgLXYgIiR4IiA+L2Rldi9udWxsIHx8IHsgZWNobyA+JjIgIkVSUk9SOiBDb21tYW5kIG5vdCBmb3VuZDogJHgiOyByZXR1cm4gMjU1OyB9CmRvbmUKaWYgWyAtbiAiJFpTSF9WRVJTSU9OIiBdOyB0aGVuCiAgICBbICIkWlNIX0VWQUxfQ09OVEVYVCIgIT0gIiR7WlNIX0VWQUxfQ09OVEVYVCUiOmZpbGU6Iip9IiBdICYmIGZuPSIkMCIKZWxpZiBbIC1uICIkQkFTSF9WRVJTSU9OIiBdOyB0aGVuCiAgICAocmV0dXJuIDAgMj4vZGV2L251bGwpICYmIGZuPSIke0JBU0hfU09VUkNFWzBdfSIKZWxzZQogICAgWyAhIC1mICIkMCIgXSAmJiB7IGVjaG8gPiYyICdFUlJPUjogU2hlbGwgbm90IHN1cHBvcnRlZC4gVXNlIEJhc2ggb3IgWnNoIGluc3RlYWQuJzsgcmV0dXJuIDI1NTsgfQpmaQpfUD0iJHtCQ19QQVNTV09SRDotJFBBU1NXT1JEfSIKdW5zZXQgXyBQQVNTV09SRCAKaWYgWyAtbiAiJFAiIF07IHRoZW4KICAgIGlmIFsgLW4gIiRCQ1YiIF0gJiYgWyAtbiAiJEJDTCIgXTsgdGhlbgogICAgICAgIF9iY2xfZ2VuX3AgIiRQIiB8fCByZXR1cm4KICAgIGVsc2UKICAgICAgICBfUD0iJChlY2hvICIkUCJ8b3BlbnNzbCBiYXNlNjQgLUEgLWQpIgogICAgZmkKZWxzZQogICAgWyAteiAiJF9QIiBdICYmIHsKICAgICAgICBlY2hvID4mMiAtbiAiRW50ZXIgcGFzc3dvcmQ6ICIKICAgICAgICByZWFkIC10IDYwIC1yIF9QCiAgICB9CmZpClsgLW4gIiRERUJVRyIgXSAmJiBlY2hvID4mMiAiREVCVVg6IF9QPSckX1AnIgpwcmc9InBlcmwgLWUgJzw+Ozw+O3ByaW50KDw+KSc8JyR7Zm46LSQwfSd8b3BlbnNzbCBlbmMgLWQgLWFlcy0yNTYtY2JjIC1tZCBzaGEyNTYgLW5vc2FsdCAtayAnJHtTfS0ke19QfScgMj4vZGV2L251bGx8Z3VuemlwIgpbIC1uICIkZm4iIF0gJiYgewogICAgdW5zZXQgLWYgX2JjbF9nZXQgX2JjbF92ZXJpZnkgX2JjbF92ZXJpZnlfZGVjCiAgICBldmFsICJ1bnNldCBCQ0wgQkNWIF8gX1AgUCBTIHByZyBmbjskKExBTkc9QyBwZXJsIC1lICc8Pjs8PjtwcmludCg8PiknPCIke2ZufSJ8b3BlbnNzbCBlbmMgLWQgLWFlcy0yNTYtY2JjIC1tZCBzaGEyNTYgLW5vc2FsdCAtayAiJHtTfS0ke19QfSIgMj4vZGV2L251bGx8Z3VuemlwKSIKICAgIHJldHVybgp9CkxBTkc9QyBleGVjIHBlcmwgJy1lJF5GPTI1NTtmb3IoMzE5LDI3OSwzODUsNDMxNCw0MzU0KXsoJGY9c3lzY2FsbCRfLCQiLDApPjAmJmxhc3R9O29wZW4oJG8sIj4mPSIuJGYpO29wZW4oJGksIiciJHByZyInfCIpO3ByaW50JG8oPCRpPik7Y2xvc2UoJGkpfHxleGl0KCQ/LzI1Nik7JEVOVnsiTEFORyJ9PSInIiRMQU5HIiciO2V4ZWN7Ii9wcm9jLyQkL2ZkLyRmIn0iJyIkezA6LXB5dGhvbjN9IiciLEBBUkdWJyAtLSAiJEAiCg=='

    # _P - used with openssl below
    #  P - stored in P=$P
    unset str
    [ -n "$_BC_LOCK" ] && _bcl_gen
    # Fallback
    [ -z "$str" ] && {
        str="unset BCV BCL"$'\n'
        P="$(echo "$P"|openssl base64 -A 2>/dev/null)"
    }

    ## Add Password to script ($P might be encrypted if BC_LOCK is set)
    [ -n "$P" ] && {
        str+="P=${P}"$'\n'
        unset P
    }

    ## Add SALT to script
    str+="S='$S'"$'\n'"$(echo "$HOOK"|openssl base64 -A -d)"
    [ -n "$DEBUG" ] && { echo -en >&2 "DEBUG: ===code===\n${CDM}${CF}"; echo >&2 "$str"; echo -en >&2 "${CN}"; }

    ## Encode & obfuscate the HOOK
    HOOK="$(echo "$str" | openssl base64 -A)"
    HOOK="$(_bc_ob64 "$HOOK")"

    [ -z "$_BC_QUIET" ] && [ "$fn" != "-" ] && { 
        s="$(stat -c %s "$fn")"
        [ "$s" -gt 0 ] || _bc_err "Empty file: $fn"
    }
    # Bash strings are not binary safe. Instead, store the binary as base64 in memory:
    ifn="$fn"
    [ "$fn" = "-" ] && ifn="/dev/stdin"
    DATA="$(openssl base64 <"$ifn")" || exit

    [ "$fn" = "-" ] && fn="/dev/stdout"

    # Create the encrypted binary: /bin/sh + Decrypt-Hook + Encrypted binary
    { 
        # printf '#!/bin/sh\0#'
        # Add some binary data after shebang, including \0 (sh reads past \0 but does not process. \0\n count as new line).
        # dd count="${count:-1}" bs=$((1024 + RANDOM % 1024)) if=/dev/urandom 2>/dev/null| tr -d "[:print:]\n'"
        # echo "" # Newline
        # => Unfortunately some systems link /bin/sh -> bash.
        # 1. Bash checks that the first line is binary free.
        # 2. and no \0 in the first 80 bytes (including the #!/bin/sh)
        echo '#!/bin/sh'
        # Add dummy variable containing garbage (for obfuscation) (2nd line)
        echo -n "_='" 
        _bc_xdd 66 </dev/urandom | _bc_xtr '' "[:print:]\0\n'"
        # \0\0 confuses some shells.
        _bc_xdd "$((1024 + RANDOM % 4096))" </dev/urandom| _bc_xtr '' "[:print:]\0{2,}\n'"
        # _bc_xprintf "' \x00" # WORKS ON BASH ONLY
        _bc_xprintf "';" # works on BASH + ZSH
        # far far far after garbage
        ## Add my hook to decrypt/execute binary
        # echo "eval \"\$(echo $HOOK|strings -n1|openssl base64 -d)\""
        echo "$(_bc_obbell 'eval "')\$$(_bc_obbell '(echo ')$HOOK|{ LANG=C $(_bc_obbell "perl -pe \"s/[^[:print:]]//g\"");}$(_bc_obbell "|openssl base64 -A -d)")\""
        # Note: openssl expects \n at the end. Perl filters it. Add it with echo.
        # echo "$(_bc_obbell 'eval "')\$$(_bc_obbell '(echo ')$HOOK|{ LANG=C $(_bc_obbell "perl -pe \"s/[^[:print:]]//g\";echo");}$(_bc_obbell "|openssl base64 -A -d)")\""
        # Add the encrypted binary (from memory)
        openssl base64 -d<<<"$DATA" |gzip|openssl enc -aes-256-cbc -md sha256 -nosalt -k "${S}-${_P}" 2>/dev/null
    } > "$fn"

    [ -n "$s" ] && {
        c="$(stat -c %s "$fn" 2>/dev/null)"
        [ -n "$c" ] && echo -e >&2 "${CDY}Compressed:${CN} ${CDM}$s ${CF}-->${CN}${CDM} $c ${CN}[${CDG}$((c * 100 / s))%${CN}]"
    }
    # [ -z "$_BC_QUIET" ] && [ -n "$_BC_LOCK" ] && echo -e >&2 "${CDY}PASSWORD=${CF}${_P}${CN}"
    unset -f _bcl_get _bcl_verify _bcl_verify_dec _bc_err _bc_ob64 _bc_obbell _bc_xdd _bc_xtr _bc_xprintf
}
# %%END_BC_FUNC%%

# Check if sourced or executed
[ -n "$ZSH_VERSION" ] && [ "$ZSH_EVAL_CONTEXT" != "${ZSH_EVAL_CONTEXT%":file:"*}" ] && _sourced=1
(return 0 2>/dev/null) && _sourced=1
[ -z "$_sourced" ] && {
    # Execute if not sourced:
    _bc_usage() {
        local bc="${0##*/}"
        echo -en >&2 "\
${CM}Encrypt a binary or script.${CDM}
The password is chosen at random unless specified by the user.

${CDG}Usage:${CN}
${CDC}${bc} ${CDY}[-hql] [file] [password]${CN}
   -h   This help
   -q   Quiet mode (no output)
   -l   Lock binary to this system & UID or fail if copied.
        It will exit with BC_LOCK if set to a numerical value.
        Otherwise it will execute BC_LOCK as a command.
        The default is to exit with 0 if copied.

${CDG}Environment variables (optional):${CN}
${CDY}PASSWORD=${CN}     Password to encrypt/decrypt.
${CDY}BC_PASSWORD=${CN}  Password to encrypt/decrypt (exported).
${CDY}BC_QUIET=${CN}     See -q
${CDY}BC_LOCK=${CN}      See -l

${CDG}Examples:${CN}
Encrypt myfile.sh with a random password:
  ${CDC}${bc} ${CDY}myfile.sh${CN}

Encrypt myfile.sh with password 'mysecret':
  ${CDC}${bc} ${CDY}myfile.sh ${CDY}mysecret${CN}

Encrypt by passing the password as environment variable:
  ${CDY}PASSWORD=mysecret ${CDC}${bc} ${CDY}myfile.sh${CN}

Encrypt /usr/bin/id with a random password:
  ${CDC}cat ${CDY}/usr/bin/id${CN} | ${CDC}${bc}${CN} >${CDY}id.enc${CN}

Lock to system. Execute 'id; ls -al' if copied:
  ${CDY}BC_LOCK='id; ls -al' ${CDC}${bc} ${CDY}myfile.sh${CN}

"
        exit 0
    }
    while getopts "hql" opt; do
        case $opt in
            h) _bc_usage ;;
            q) _OPT_BC_QUIET=1 ;;
            l) _OPT_BC_LOCK=0 ;;
            *) ;;
        esac
    done
    shift $((OPTIND - 1))

    _bincrypter "$@"
}

### HERE: sourced
unset _sourced
