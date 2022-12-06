#!/bin/sh

######################################################################
#
# ESCJ.SH
#   A Unicode Escape Sequence Encoder for JSON
#
# === What is This? ===
# * This command converts UTF-8 strings to Unicode escape sequence
#   for some JSON parsers who don't accept raw non-ASCII characters.
# * This program expects one of these formats as input:
#   - "JSONPath-value" format with string values in raw UTF-8
#     (This format is for parsrj.sh/makrj.sh commands.)
#   - Plain UTF-8 strings
#
# === Usage ===
# Usage   : escj.sh [-p|-j|-n|-q] [textfile]
# Options : -p ... Expects the input text data as UTF-8 strings.
#           -j ... Expects the input text data as JSONPath-value.
#                  (default)
#           -n ... Equivalent to -j option.
#           -q ... Expects the input text data as JSONPath-value.
#                  Quotes string value with double-quotation to
#                  clarify its type.
# Environs: LINE_BUFFERED
#             =yes ........ Line-buffered mode if available
#             =forcible ... Force line-buffered mode. Exit if unavailable.
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
	Usage   : ${0##*/} [-p|-j|-n|-q] [textfile]
	Options : -p ... Expects the input text data as UTF-8 strings.
	          -j ... Expects the input text data as JSONPath-value.
	                 (default)
	          -n ... Equivalent to -j option.
	          -q ... Expects the input text data as JSONPath-value.
	                 Quotes string value with double-quotation to
	                 clarify its type.
	Environs: LINE_BUFFERED
	            =yes ........ Line-buffered mode if available
	            =forcible ... Force line-buffered mode. Exit if unavailable.
	Version : 2022-02-04 19:29:07 JST
	          (POSIX Bourne Shell/POSIX commands/UTF-8)
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

# === Get options and filepath =======================================
#
# --- initialize option parameters -----------------------------------
mode=1 # 0:plain_UTF-8, 1:JSONPath-value, 2:quoted-JSONPath-value
file=''
#
# --- get them -------------------------------------------------------
for arg in ${1+"$@"}; do
  case $arg in -) break;; -*) :;; *) break;; esac
  for arg in $(printf '%s\n' "${arg#-}" | sed 's/./& /g'); do
    case $arg in
      p)    mode=0              ;;
      [jn]) mode=1              ;;
      q)    mode=2              ;;
      *)    print_usage_and_exit;;
    esac
  done
  shift
done

# === Validate the argument of the file ==============================
#
# --- check the number of files --------------------------------------
case $# in
  0) set -- -            ;;
  1) :                   ;;
  *) print_usage_and_exit;;
esac
#
# --- Validate the file type -----------------------------------------
[ -f "$1" ] || [ -c "$1" ] || [ -p "$1" ] || [ "_$1" = '_-' ] || {
  error_exit 1 'Invalid file'
}
[ -r "$1" ] || [ "_$1" = '_-' ] || error_exit 1 "Cannot open the file: $1"
case "$1" in -|/*|./*|../*) file=$1;; *) file="./$1";; esac

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
  case "$s $lbm" in
    *s*)   alias cat='stdbuf -o L cat'                       ;;
    *p*)   alias cat='ptw cat'                               ;;
    *' 2') error_exit 1 'Line-buffered mode is not supported';;
  esac
;; esac


######################################################################
# Main Routine (conversion)
######################################################################

# === Open the file and append an LF to plain UTF-8 file ================= #
case $mode in                                                              #
  0) cat "$file"; echo;;                                                   #
  *) cat "$file"      ;;                                                   #
esac                                                                       |
#                                                                          #
# === Escape some characters ============================================= #
awk 'BEGIN {                                                               #
       mode='$mode';                                                       #
       for (i=  1;i<128;i++) {c=sprintf("%c",i);esc[c]=c;         }        #
       esc["\""  ]="\\\""; esc["\\"  ]="\\\\"; esc["/"   ]="\\/" ;         #
       esc["\010"]="\\b" ; esc["\014"]="\\f" ; esc["\012"]="\\n" ;         #
       esc["\014"]="\\r" ; esc["\011"]="\\t" ;                             #
       if (mode!=0) {esc["\\"  ]="\\";}                                    #
       for (i=128;i<192;i++) {u0i[sprintf("%c",i)]= i-128        ;}        #
       for (i=192;i<224;i++) {u2i[sprintf("%c",i)]=(i-192)*    64;}        #
       for (i=224;i<240;i++) {u3i[sprintf("%c",i)]=(i-224)*  4096;}        #
       for (i=240;i<248;i++) {u4i[sprintf("%c",i)]=(i-240)*262144;}        #
       while (getline l) {                                                 #
         dq="";                                                            #
         if        (mode==0) {                          lf="\\n"; dq="";   #
         } else if (mode==1) {                          lf= "\n"; dq="";   #
           if (match(l,/[ \t]/)) {i=RSTART;} else {i=length(l)+1;}         #
           printf("%s ",substr(l,1,i-1)); l=substr(l,i+1);                 #
         } else if (mode==2) {                          lf= "\n";          #
           if (match(l,/[ \t]/)) {i=RSTART;} else {i=length(l)+1;}         #
           printf("%s ",substr(l,1,i-1)); l=substr(l,i+1);                 #
           if (match(l,/^[ \t]*".*"[ \t]*$/)) {                            #
             sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l);                     #
             l=substr(l,2,length(l)-2);                           dq="\""; #
           }                                                               #
         }                                                                 #
         printf("%s",dq);                                                  #
         for (pos=1; c=substr(l,pos,1); pos++) {                           #
           if        (c < "\200") {                    # 1byte             #
             printf("%s",esc[c]);            continue;                     #
           } else if (c < "\300") {          continue; # invalid           #
           } else if (c < "\340") {                    # 2bytes            #
             i = u2i[c]+u0i[substr(l,pos+1,1)];                            #
             pos +=1;                                                      #
           } else if (c < "\360") {                    # 3bytes            #
             i = u3i[c]+u0i[substr(l,pos+1,1)]*64+u0i[substr(l,pos+2,1)];  #
             pos +=2;                                                      #
           } else if (c < "\370") {                    # 4bytes            #
             i = u4i[c]+u0i[substr(l,pos+1,1)]*4096;                       #
             i+= u0i[substr(l,pos+2,1)]*64+u0i[substr(l,pos+3,1)];         #
             pos +=3;                                                      #
           } else if (c < "\374") { pos +=4; continue; # 5bytes            #
           } else if (c < "\376") { pos +=5; continue; # 6bytes            #
           } else                 {          continue; # invalid           #
           }                                                               #
           if (i<65536) {printf("\\u%04X",i                );}             #
           else         {printf("\\u%04X",int(i/1024)+55232);              #
                         printf("\\u%04X",    i%1024 +56320);}             #
         }                                                                 #
         printf("%s%s",dq,lf);'"$awkfl"'                                   #
       }                                                                   #
       if (mode==0) {printf("\n");}                                        #
     }'                                                                    |
#                                                                          #
# === Remove the LF character at the end of output ======================= #
#     if plain text was input                                              #
case $mode in                                                              #
  0) sed '$s/\\n$//';;                                                     #
  *) cat            ;;                                                     #
esac
