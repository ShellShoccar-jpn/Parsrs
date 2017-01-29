#!/bin/sh

######################################################################
#
# MAKRC.SH
#   A CSV (RFC 4180) Generator Which Makes From "Line#-Field#-value"
#   Formatted Text
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
#    1 1 aaa
#    1 2 b"bb
#    1 3 c\ncc
#    1 4 d d
#    2 1 f,f
# 2. Output Text This Command Generates (CSV : RFC 4180)
#    aaa,"b""bb","c
#    cc",d d
#    "f,f"
#
# === Usage ===
# Usage   : makrc.sh [options] [Line#-Field#-value_textfile]
# Options : -fs<s> Replaces the CSV field separator "," into <s>
#           -lf    Doesn't convert LFs at the end of lines into CR+LFs
#           -t     Doesn't quote with '"' or escape fields
# Caution : Must be done "sort -k 1n,1 -k 2n,2" before using this command
#
# Written by 321516 (@shellshoccarjpn) / 2017-01-30 00:28:18 JST
#
# This is a public-domain software (CC0). It measns that all of the
# people can use this for any purposes with no restrictions at all.
# By the way, I am fed up the side effects which are broght about by
# the major licenses.
#
######################################################################


######################################################################
# Initial configuration
######################################################################

# === Initialize shell environment ===================================
set -eu
export LC_ALL=C
export PATH="$(command -p getconf PATH):${PATH:-}"

# === Usage printing function ========================================
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] [Line#-Field#-value_textfile]
	Options : -fs<s> Replaces the CSV field separator "," into <s>
	          -lf    Doesn't convert LFs at the end of lines into CR+LFs
	          -t     Doesn't quote with '"' or escape fields
	Caution : Must be done "sort -k 1n,1 -k 2n,2" before using this command
	2017-01-30 00:28:18 JST
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
optfs=','
optlf=0
optt=0
file=''
case $# in 0) set -- -;; esac
i=0
for arg in "$@"; do
  i=$((i+1))
  if [ "_${arg#-fs}" != "_$arg" ] && [ -z "$file" ]; then
    optfs=$(printf '%s' "${arg#-fs}_"                |
            tr -d '\n'                               |
            sed 's/\([\&/]\)/\\\1/g' 2>/dev/null || :)
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
[ -z "$file"  ] && file='-'


######################################################################
# Prepare for the Main Routine
######################################################################

# === Define some chrs. to escape some special chrs. temporarily =====
SO=$( printf '\016')               # Escape sign for \
SI=$( printf '\017')               # Escape sign for <0x0A>
LFs=$(printf '\\\n_');LFs=${LFs%_} # <0x0A> for sed substitute chr.


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the "Line#-Field#-value" data source ========== #
cat "$file"                                                |
#                                                          #
# === Transfer line and field numbers separator to "_" === #
sed 's/ \{1,\}/_/' 2>/dev/null                             |
#                                                          #
# === Escape "\n" and "\" as value ======================= #
sed 's/\\\\/'"$SO"'/g'                                     |
sed 's/\\n/'"$SI"'/g'                                      |
#                                                          #
# === Quote strings with '"' as necessary ================ #
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
        print "\n";                                        #
        r++;                                               #
        dlm="";                                            #
        c=1;                                               #
        if (cr>r) {                                        #
          for (; r<cr; r++) {print "\"\"","\n";}           #
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
# === Unescape the escaped <0x0A> and "\" ================ #
sed 's/'"$SO"'/\\/g'                                       |
sed 's/'"$SI"'/'"$LFs"'/g'                                 |
#                                                          #
# === Convert the newline character from LF to CR+LF ===== #
case $optlf in                                             #
  0) sed "s/\$/$(printf '\r')/";;                          #
  *) cat                       ;;                          #
esac
