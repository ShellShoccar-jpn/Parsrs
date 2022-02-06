#!/bin/sh

######################################################################
#
# UNESCJ.SH
#   A Unicode Escape Sequence Decoder for JSON
#
# === What is This? ===
# * This command converts Unicode escape sequence strings to UTF-8.
# * But the command is a converter not for original JSONs but for
#   beforehand extracted strings from JSONs.
# * Basically, this command is for the text data (JSONPath-value) after
#   converting by "parsrj.sh" command.
# * When you convert JSONPath-value, you have to use "-n" option to
#   avoid being broken as a JSONPath-value format by being inserted into
#   <0x0A>s which has been converted from "\ux000a"s.
#
# === Usage ===
# Usage   : unescj.sh [-nuU] [JSONPath-value_textfile]
# Options : -n ... Regard the data as JSONPath-value
# Environs: LINE_BUFFERED
#             =yes ........ Line-buffered mode if possible
#             =forcible ... Line-buffered mode or exit if impossible
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2022-02-04
#
# This is a public-domain software (CC0). It means that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, We are fed up with the side effects which are brought
# about by the major licenses.
#
######################################################################


######################################################################
# Initial configuration
######################################################################

# === Initialize shell environment ===================================
set -u
umask 0022
export LC_ALL=C
export PATH="$(command -p getconf PATH 2>/dev/null)${PATH+:}${PATH-}"
case $PATH in :*) PATH=${PATH#?};; esac
export POSIXLY_CORRECT=1 # to make GNU Coreutils conform to POSIX
export UNIX_STD=2003     # to make HP-UX conform to POSIX
IFS=' 	
'

# === Define the functions for printing usage and error message ======
print_usage_and_exit() {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [-nuU] [JSONPath-value_textfile]
	Options : -n ... Regard the data as JSONPath-value
	          -u ... Line-buffered mode if possible
	          -U ... Line-buffered mode or exit if impossible
	Environs: LINE_BUFFERED
	            =yes ........ Line-buffered mode if possible
	            =forcible ... Line-buffered mode or exit if impossible
	Version : 2022-02-04 19:28:27 JST
	          (POSIX Bourne Shell/POSIX commands)
	USAGE
  exit 1
}
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit $1
}


######################################################################
# Prepare for the Main Routine
######################################################################

# === Define some chrs. to escape some special chrs. temporarily =====
s=$(printf '\010\011\\\n\014\015\006')
BS=${s%??????}; s=${s#?}   # Back Space
TAB=${s%?????}; s=${s#?}   # Tab
LFs=${s%???}  ; s=${s#??}  # Line Feed (for sed command)
FF=${s%??}    ; s=${s#?}   # New Pafe (Form Feed)
CR=${s%?}     ;            # Carridge Return
ACK=${s#?}                 # Escape chr. for "\\"

# === Get the options and the filepath ===============================
# --- initialize option parameters -----------------------------------
optn=0 # 0:simple_JSON_encoded_string, 1:JSONPath-value
file=''
#
# --- get them -------------------------------------------------------
for arg in ${1+"$@"}; do
  case $arg in -) break;; -*) :;; *) break;; esac
  for arg in $(printf '%s\n' "${arg#-}" | sed 's/./& /g'); do
    case $arg in
      n)    optn=1              ;;
      *)    print_usage_and_exit;;
    esac
  done
  shift
done
case $# in
  0) :                   ;;
  1) file=$1             ;;
  *) print_usage_and_exit;;
esac

# === Validate the arguments =========================================
if   [ "_$file" = '_'                ] ||
     [ "_$file" = '_-'               ] ||
     [ "_$file" = '_/dev/stdin'      ] ||
     [ "_$file" = '_/dev/fd/0'       ] ||
     [ "_$file" = '_/proc/self/fd/0' ]  ; then
  file=''
elif [ -f "$file"                    ] ||
     [ -c "$file"                    ] ||
     [ -p "$file"                    ]  ; then
  [ -r "$file" ] || error_exit 1 'Cannot open the file: '"$file"
else
  print_usage_and_exit
fi
case "$file" in ''|-|/*|./*|../*) :;; *) file="./$file";; esac

# === Switch to the line-buffered mode if required ===================
awkfl=''
case "${LINE_BUFFERED:-}" in
             [Ff][Oo][Rr][Cc][EeIi]*|2) lbm=2;;
  [Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Yy]|1) lbm=1;;
                                     *) lbm=0;;
esac
case $lbm in [!0]*)
  s=$(awk -W interactive 'BEGIN{}' 2>&1)
  case "$?$s" in
  '0') alias awk='awk -W interactive';;
    *) awkfl='system("");'           ;;
  esac
  s="$(type stdbuf >/dev/null 2>&1 && echo "s")"
  s="$(type ptw    >/dev/null 2>&1 && echo "p")$s"
  if sed -u p </dev/null >/dev/null 2>&1; then
    alias sed='sed -u'
  else
    case "$s $lbm" in
      *s*)   alias sed='stdbuf -o L sed'                       ;;
      *p*)   alias sed='ptw sed'                               ;;
      *' 2') error_exit 1 'Line-buffered mode is not supported';;
    esac
  fi
  if echo 1 | grep -q --line-buffered ^ 2>/dev/null; then
    alias grep='grep --line-buffered'
  else
    case "$s $lbm" in
      *s*)   alias grep='stdbuf -o L grep'                     ;;
      *p*)   alias grep='ptw grep'                             ;;
      *' 2') error_exit 1 'Line-buffered mode is not supported';;
    esac
  fi
;; esac


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the data source =================================================== #
grep '' ${file:+"$file"}                                                       |
#                                                                              #
# === Escape "\\" to ACK temporarily ========================================= #
sed 's/\\\\/'"$ACK"'/g'                                                        |
#                                                                              #
# === Mark the original <0x0A> with <0x0A>+"\N" after it ===================== #
sed 's/$/'"$LFs"'\\N/'                                                         |
#                                                                              #
# === Insert <0x0A> into the behind of "\uXXXX" ============================== #
sed 's/\(\\u[0-9A-Fa-f]\{4\}\)/'"$LFs"'\1/g'                                   |
#                                                                              #
# === Unescape "\uXXXX" into UTF-8 =========================================== #
#     (But the following ones are transfer the following strings               #
#      \u000a -> \n, \u000d -> \r, \u005c -> \\, \u0000 -> \0, \u0006 -> \A)   #
awk '                                                                          #
BEGIN {                                                                        #
  OFS=""; ORS="";                                                              #
  for(i=255;i>0;i--) {                                                         #
    s=sprintf("%c",i);                                                         #
    bhex2chr[sprintf("%02x",i)]=s;                                             #
    bhex2int[sprintf("%02x",i)]=i; # (a)                                       #
  }                                                                            #
  bhex2chr["00"]="\\0" ;                                                       #
  bhex2chr["06"]="\\A" ;                                                       #
  bhex2chr["0a"]="\\n" ;                  # Both (a) and (b) are also the      #
  bhex2chr["0d"]="\\r" ;                  # transferring table from a 2 bytes  #
  bhex2chr["5c"]="\\\\";                  # of hex number to a decimal one.    #
  #for(i=65535;i>=0;i--) {          # (b) # (a) is to use 256 keys twice. (b)  #
  #  whex2int[sprintf("%02x",i)]=i; #  :  # is to use 65536 keys once. And (a) #
  #}                                #  :  # was a litter faster than (b).      #
  j=0;                                                                         #
  while (getline l) {                                                          #
    if (l=="\\N") {print "\n";'"$awkfl"' continue; }                           #
    if (match(l,/^\\u00[0-7][0-9a-fA-F]/)) {                                   #
      print bhex2chr[tolower(substr(l,5,2))], substr(l,7);                     #
      continue;                                                                #
    }                                                                          #
    if (match(l,/^\\u0[0-7][0-9a-fA-F][0-9a-fA-F]/)) {                         #
      #i=whex2int[tolower(substr(l,3,4))]; # <-(a) V(b)                        #
      i=bhex2int[tolower(substr(l,3,2))]*256+bhex2int[tolower(substr(l,5,2))]; #
      printf("%c%c",192+int(i/64),128+i%64);                                   #
      print substr(l,7);                                                       #
      continue;                                                                #
    }                                                                          #
    if (match(l,/^\\u[Dd][89AaBb][0-9a-fA-F][0-9a-fA-F]$/)) {                  #
      # Decode high-surrogate part                                             #
      j = bhex2int["0" tolower(substr(l,4,1))]*262144 +                        \
          bhex2int[    tolower(substr(l,5,2))]*  1024 -                        \
          2031616;                                                             #
      continue;                                                                #
    }                                                                          #
    if (match(l,/^\\u[Dd][C-Fc-f][0-9a-fA-F][0-9a-fA-F]/ )) {                  #
      # Decode low-surrogate part                                              #
      j += bhex2int["0" tolower(substr(l,4,1))]*256 +                          \
           bhex2int[tolower(substr(l,5,2))]         -                          \
           3072;                                                               #
      i1=240+int(j/262144); j%=262144;                                         #
      i2=128+int(j/  4096); j%=  4096;                                         #
      i3=128+int(j/    64); j%=    64;                                         #
      i4=128+    j        ; j =     0;                                         #
      printf("%c%c%c%c",i1,i2,i3,i4);                                          #
      print substr(l,7);                                                       #
      continue;                                                                #
    }                                                                          #
    if (match(l,/^\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/)) {         #
      #i=whex2int[tolower(substr(l,3,4))]; # <-(a) V(b)                        #
      i=bhex2int[tolower(substr(l,3,2))]*256+bhex2int[tolower(substr(l,5,2))]; #
      printf("%c%c%c",224+int(i/4096),128+int((i%4096)/64),128+i%64);          #
      print substr(l,7);                                                       #
      continue;                                                                #
    }                                                                          #
    print l;                                                                   #
  }                                                                            #
}'                                                                             |
# === Unsscape escaped strings except "\n", "\0" and "\\" ==================== #
sed 's/\\"/"/g'                                                                |
sed 's/\\\//\//g'                                                              |
sed 's/\\b/'"$BS"'/g'                                                          |
sed 's/\\f/'"$FF"'/g'                                                          |
sed 's/\\r/'"$CR"'/g'                                                          |
sed 's/\\t/'"$TAB"'/g'                                                         |
#                                                                              #
# === Also unescape "\0", "\r", "\n", "\\" when "-n" option is not given ===== #
case "$optn" in                                                                #
  0) sed 's/\\0//g'                             |  # - "\0" should be deleted  #
     sed 's/\\r/'"$CR"'/g'                      |  #   without conv to <0x00>  #
     sed 's/\\n/'"$LFs"'/g'                     |  #                           #
     sed 's/'"$ACK"'/\\\\/g'                    |  # - Unescaoe escaped "\\"s  #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |  #   and then restore "\A"s  #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |  #   to <ACK>s               #
     sed 's/^\(\(\\\\\)*\)\\A/\1'"$ACK"'/g'     |  #   :                       #
     sed 's/\\\\/\\/g'                          ;; # - Unescape "\\"s into "\"s#
  *) sed 's/'"$ACK"'/\\\\/g'                    |                              #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |                              #
     sed 's/\([^\\]\(\\\\\)*\)\\A/\1'"$ACK"'/g' |                              #
     sed 's/^\(\(\\\\\)*\)\\A/\1'"$ACK"'/g'     ;;                             #
esac
