#!/bin/sh

######################################################################
#
# PARSRC.SH
#   A CSV (RFC 4180) Parser Which Convert Into "Line#-Field#-value"
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
# 1. Input Text (CSV : RFC 4180)
#    aaa,"b""bb","c
#    cc",d d
#    "f,f"
# 2. Output Text This Command Converts Into
#    1 1 aaa
#    1 2 b"bb
#    1 3 c\ncc
#    1 4 d d
#    2 1 f,f
#
# === Usage ===
# Usage   : parsrc.sh [-lf<s>] [CSV_file]
# Options : -lf Replaces the newline sign "\n" with <s>. And in this mode,
#               also replaces \ with \\
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-07-18
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
set -eu
export LC_ALL=C
type command >/dev/null 2>&1 && type getconf >/dev/null 2>&1 &&
export PATH="$(command -p getconf PATH)${PATH+:}${PATH-}"
export UNIX_STD=2003  # to make HP-UX conform to POSIX

# === Usage printing function ========================================
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [-lf<s>] [CSV_file]
	Options : -lf Replaces the newline sign "\n" with <s>. And in this mode,
	            also replaces \ with \\
	Version : 2017-07-18 02:39:39 JST
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
optlf=''
bsesc='\\'
file=''
#
# --- get them -------------------------------------------------------
i=0
for arg in ${1+"$@"}; do
  i=$((i+1))
  if [ "_${arg#-lf}" != "_$arg" ] && [ -z "$file" ]; then
    optlf=$(printf '%s' "${arg#-lf}_" |
            tr -d '\n'                |
            grep ''                   |
            sed 's/\([\&/]\)/\\\1/g'  )
    optlf=${optlf%_}
  elif [ $i -eq $# ] && [ "_$arg" = '_-' ] && [ -z "$file" ]; then
    file='-'
  elif [ $i -eq $# ] && ([ -f "$arg" ] || [ -c "$arg" ]) && [ -z "$file" ]; then
    file=$arg
  else
    print_usage_and_exit
  fi
done
[ -z "$optlf" ] && { optlf='\\n'; bsesc='\\\\'; }

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
SO=$( printf '\016')               # Escape sign for '""'
SI=$( printf '\017')               # Escape sign for <0x0A> as a value
RS=$( printf '\036')               # Sign for record separator of CSV
US=$( printf '\037')               # Sign for field separator of CSV
LFs=$(printf '\\\n_');LFs=${LFs%_} # <0x0A> for sed substitute chr.
HT=$( printf '\011')               # TAB
CR=$( printf '\015')               # Carridge Return


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the CSV data source ===================================== #
grep '' ${file:+"$file"}                                             |
#                                                                    #
# === Remove <CR> at the end of every line ========================= #
sed "s/$CR\$//"                                                      |
#                                                                    #
# === Escape DQs as value ========================================== #
#     (However '""'s meaning null are also escape for the moment)    #
sed 's/""/'$SO'/g'                                                   |
#                                                                    #
# === Convert <0x0A>s as value into "\n" =========================== #
#     (It's possible to distinguish it from the ones as CSV record   #
#      separator if the number of DQs in a line is an odd number.    #
#      And mark the point with <SI> and join with it the next line.) #
awk '                                                                #
  BEGIN {                                                            #
    while (getline line) {                                           #
      s = line;                                                      #
      gsub(/[^"]/, "", s);                                           #
      if (((length(s)+cy) % 2) == 0) {                               #
        cy = 0;                                                      #
        printf("%s\n", line);                                        #
      } else {                                                       #
        cy = 1;                                                      #
        printf("%s'$SI'", line);                                     #
      }                                                              #
    }                                                                #
  }                                                                  #
'                                                                    |
#                                                                    #
# === Mark record separators of CSV with RS after it in advance ==== #
sed "s/\$/$LFs$RS/"                                                  |
#                                                                    #
# === Split fields which is quoted with DQ into individual lines === #
#     (Also remove spaces behind and after the DQ field)             #
# (1/3)Split the DQ fields from the top to NF-1                      #
sed 's/['"$HT"' ]*\("[^"]*"\)['"$HT"' ]*,/\1'"$LFs$US$LFs"'/g'       |
# (2/3)Split the DQ fields at the end (NF)                           #
sed 's/,['"$HT"' ]*\("[^"]*"\)['"$HT"' ]*$/'"$LFs$US$LFs"'\1/g'      |
# (3/3)Remove spaces behind and after the single DQ field in line    #
sed 's/^['"$HT"' ]*\("[^"]*"\)['"$HT"' ]*$/\1/g'                     |
#                                                                    #
# === Split non-quoted fields into individual lines ================ #
#     (It is simple, only convert "," to <0x0A> on non-quoted lines) #
sed '/['$RS'"]/!s/,/'"$LFs$US$LFs"'/g'                               |
#                                                                    #
# === Unquote DQ-quoted field ====================================== #
#     (It is also simple, only remove DQs. Because the DQs as value  #
#      are all escaped now.)                                         #
tr -d '"'                                                            |
#                                                                    #
# === Unescape the DQs as value ==================================== #
#     (However '""'s meaning null are also unescaped)                #
# (1/3)Unescape all '""'s                                            #
sed 's/'$SO'/""/g'                                                   |
# (2/3)Convert only '""'s mean null into empty lines                 #
sed 's/^['"$HT"' ]*""['"$HT"' ]*$//'                                 |
# (3/3)Convert the left '""'s, which are as value, into '"'s         #
sed 's/""/"/g'                                                       |
#                                                                    #
# === Assign the pair number of line and field on the head of line = #
awk '                                                                #
  BEGIN{                                                             #
    l=1;                                                             #
    f=1;                                                             #
    while (getline line) {                                           #
      if (line == "'$RS'") {                                         #
        l++;                                                         #
        f=1;                                                         #
      } else if (line == "'$US'") {                                  #
        f++;                                                         #
      } else {                                                       #
        printf("%d %d %s\n", l, f, line);                            #
      }                                                              #
    }                                                                #
  }                                                                  #
'                                                                    |
#                                                                    #
# === Convert escaped <CR>s as value (SI) into the substitute str. = #
if [ "_$bsesc" != '_\\' ]; then                                      #
  sed 's/\\/'"$bsesc"'/g'                                            #
else                                                                 #
  cat                                                                #
fi                                                                   |
sed 's/'"$SI"'/'"$optlf"'/g'
