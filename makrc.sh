#!/bin/sh

######################################################################
#
# MAKRC.SH
#   A CSV (RFC 4180) Generator From "Line#-Field#-value" Formatted Text
#
# === What is "Line#-Field#-value" Formatted Text? ===
# 1. Format
#    1 1 <cell_value_which_was_in_(1,1)>
#    1 2 <cell_value_which_was_in_(1,2)>
#                :
#    1 m <cell_value_which_was_in_(1,m)>
#    2 1 <cell_value_which_was_in_(2,1)>
#                :
#                :
#    m n <cell_value_which_was_in_(m,n)>
#
# === This Command will Do Like the Following Conversion ===
# 1. Input Text (Line#-Field#-value Formatted Text)
#      1 1 aaa
#      1 2 b"bb
#      1 3 c\ncc
#      1 4 d d
#      2 1 f,f
#    (" is the double quotation character.)
# 2. Output Text This Command Generates (CSV : RFC 4180)
#      aaa,"b""bb","c
#      cc",d d
#      "f,f"
#
# === Usage ===
# Usage   : makrc.sh [options] [Line#-Field#-value_textfile]
# Options : -fs<s> Specify the CSV field separator (default: ",")
#           -lf    Represent end of line with LFs rather than CR+LFs
#           -t     Don't quote values with '"' nor escape fields
# Environs: LINE_BUFFERED
#             =yes ........ Line-buffered mode if possible
#             =forcible ... Force line-buffered mode. Exit if unavailable.
# Caution : Requires line# and field# to be sorted, i.e.
#           use preprocessor "sort -k 1n,1 -k 2n,2"
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

# === Usage printing function ========================================
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] [Line#-Field#-value_textfile]
	Options : -fs<s> Specify the CSV field separator (default: ",")
	          -lf    Represent end of line with LFs rather than CR+LFs
	          -t     Don't quote values with '"' nor escape fields
	Environs: LINE_BUFFERED
	            =yes ........ Line-buffered mode if possible
	            =forcible ... Force line-buffered mode. Exit if unavailable.
	Caution : Requires line# and field# to be sorted, i.e.
	          use preprocessor "sort -k 1n,1 -k 2n,2"
	Version : 2022-02-04 18:23:47 JST
	          (POSIX Bourne Shell/POSIX commands)
	USAGE
  exit 1
}


######################################################################
# Parse Arguments
######################################################################

# === Print the usage when "--help" is put ===========================
case "$# ${1:-}" in
  '1 -h'|'1 --help'|'1 --version') print_usage_and_exit;;
esac

# === Get the options and the filepath ===============================
# --- initialize option parameters -----------------------------------
optfs=','
optlf=0
optt=0
file=''
#
# --- get them -------------------------------------------------------
i=0
for arg in ${1+"$@"}; do
  i=$((i+1))
  if [ "_${arg#-fs}" != "_$arg" ] && [ -z "$file" ]; then
    optfs=$(printf '%s' "${arg#-fs}_" |
            tr -d '\n'                |
            grep ''                   |
            sed 's/\([\&/]\)/\\\1/g'  )
    optfs=${optfs%_}
  elif [ "_${arg}" = '_-lf' ] && [ -z "$file" ]; then
    optlf=1
  elif [ "_${arg}" = '_-t'  ] && [ -z "$file" ]; then
    optt=1
  elif [ $i -eq $# ] && [ "_$arg" = '_-' ] && [ -z "$file" ]; then
    file='-'
  elif [ $i -eq $# ] && ([ -f "$arg" ] || [ -c "$arg" ]) && [ -z "$file" ]; then
    file=$arg
  else
    print_usage_and_exit
  fi
done

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


######################################################################
# Prepare for the Main Routine
######################################################################

# === Define some chrs. to escape some special chrs. temporarily =====
s=$(printf '\016\017\\\n_')
SO=${s%????}; s=${s#?} # Escape sign for \
SI=${s%???} ; s=${s#?} # Escape sign for <0x0A>
LFs=${s%?}             # <0x0A> for sed substitute chr.

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
  case "$s $lbm" in
    *s*)   alias cat='stdbuf -o L cat'                       ;;
    *p*)   alias cat='ptw cat'                               ;;
    *' 2') error_exit 1 'Line-buffered mode is not supported';;
  esac
;; esac


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the "Line#-Field#-value" data source ========== #
grep '' ${file:+"$file"}                                   |
#                                                          #
# === Transfer line and field numbers separator to "_" === #
sed 's/ \{1,\}/_/'                                         |
#                                                          #
# === Escape "\n" and the backslash as value ============= #
sed 's/\\\\/'"$SO"'/g'                                     |
sed 's/\\n/'"$SI"'/g'                                      |
#                                                          #
# === Quote strings with '"' as necessity ================ #
case $optt in                                              #
  0) sed '/['"$SO$SI"',"]/{s/"/""/g;s/ \(.*\)$/ "\1"/;}';; #
  1) cat                                                ;; #
esac                                                       |
#                                                          #
# === Generate CSV with the line# and field# infomations = #
FLDSP="$optfs" awk '                                       #
  BEGIN{                                                   #
    # --- Initialization ---                               #
    fldsp=ENVIRON["FLDSP"];                                #
    OFS=""; ORS="";                                        #
    r=1; c=1; dlm="";                                      #
                                                           #
    # --- Main Loop ---                                    #
    while (getline line) {                                 #
      match(line, /_[0-9]+/);                              #
      cr =substr(line,       1,RSTART -1)*1;               #
      cc =substr(line,RSTART+1,RLENGTH-1)*1;               #
      val=substr(line,RSTART+RLENGTH+1  );                 #
      if (cr==r) {                                         #
        print_col();                                       #
      } else {                                             #
        print "\n";'"$awkfl"'                              #
        r++;                                               #
        dlm="";                                            #
        c=1;                                               #
        if (cr>r) {                                        #
          for(; r<cr; r++){print "\"\"","\n";'"$awkfl"'}   #
        }                                                  #
        print_col();                                       #
      }                                                    #
    }                                                      #
                                                           #
    # --- Post Loop ---                                    #
    print "\n";                                            #
  }                                                        #
  function print_col() {                                   #
    if (cc==c) {                                           #
      print dlm,val;                                       #
      c++;                                                 #
      dlm=fldsp;                                           #
    } else if (cc>c) {                                     #
      for (; c<cc; c++) {print dlm,"\"\"";dlm=fldsp;}      #
      print dlm,val;                                       #
      c++;                                                 #
    } else {                                               #
      print val;                                           #
    }                                                      #
  }'                                                       |
#                                                          #
# === Unescape the escaped <0x0A> and the backslash ====== #
sed 's/'"$SO"'/\\/g'                                       |
sed 's/'"$SI"'/'"$LFs"'/g'                                 |
#                                                          #
# === Convert the newline character from LF to CR+LF ===== #
case $optlf in                                             #
  0) sed "s/\$/$(printf '\r')/";;                          #
  *) cat                       ;;                          #
esac
