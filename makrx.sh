#!/bin/sh

######################################################################
#
# MAKRX.SH (only for WebAPI)
#  A XML Generator From "XPath-value" Formatted Text
#
# === What is "XPath-value" Formatted Text? ===
# 1. Format
#    <XPath_string#1> + <0x20> + <value_at_that_path#1>
#    <XPath_string#2> + <0x20> + <value_at_that_path#2>
#    <XPath_string#3> + <0x20> + <value_at_that_path#3>
#             :              :              :
# 2. How do I get that formatted text?
#   The easiest way is to convert from XML data with "parsrx.sh".
#   (Try to convert some XML data with parsrx.sh, and learn its format)
#
# === This Command will Do Like the Following Conversion ===
# 1. Input Text 
#    /foo/bar/@foo FOO
#    /foo/bar/@bar BAR
#    /foo/bar/br
#    /foo/bar/script 
#    /foo/bar Wow!
#    /foo Great!Awsome!
# 2. Output Text This Command Generates
#    <?xml version="1.0" encoding="UTF-8"?>
#    <foo>
#      Great!Awsome!
#      <bar bar="BAR" foo="FOO">Wow!<br /><script /></bar>
#    </foo>
#
# === Usage ===
# Usage : makrx.sh [XPath-value_textfile]
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2020-05-06
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
export UNIX_STD=2003  # to make HP-UX conform to POSIX

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [XPath-value_textfile]
	Version : 2020-05-06 22:42:19 JST
	          (POSIX Bourne Shell/POSIX commands)
	USAGE
  exit 1
}
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit $1
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
file=''
#
# --- get them -------------------------------------------------------
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


######################################################################
# Prepare for the Main Routine
######################################################################

# === LF chr. for sed replacement string =============================
LF=$(printf '\\\n_')
LF=${LF%_}


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the "XPath-value" data source =============================
cat ${file:+"$file"}                                                 |
#                                                                    #
# === Replace "/" in value for attribute with "^" ====================
sed '/@/ s:@:'"$LF"'@:'                                              |
sed '/@/ s:/:^:g'                                                    |
sed '/@/ s:@\(.*\) \(.*\):@\1="\2":'                                 |
#                                                                    #
# === Revert the LF in previous step =================================
awk '/^\/.*\/$/{printf("%s",$1)}/.*[^\/]$/{print $0}'                |
#                                                                    #
# === Enumerate path to each elements. Append "\" for sort ===========
awk -F '/' '{                                                        #
  i=1;                                                               #
  while (i <= NF-1 ) {                                               #
    for(j=1;j<i;j++) {                                               #
      printf("%s/",$j);                                              #
    }                                                                #
    printf("%s\\\n",$i);                                             #
    i++;                                                             #
  }                                                                  #
  print $0}'                                                         |
awk 'NF==2 && $0 !~ /@/{printf("%s\n%s\\\n",$0,$1)}                  #
     NF<2{print $0}NF>2{print $0}'                                   |
sed 's/ $//'                                                         |
awk 'NF<2 && ($0 !~ /\\$/ && $0 !~ /@/){printf("%s\n%s\\\n",$0,$0)}  #
     NF<2 && (/\\$/ || /@/){print $0}                                #
     NF>=2{print $0}'                                                |
#                                                                    #
# === Uniquify common lines. Sort to close tags ======================
sort -u                                                              |
#                                                                    #
# === XPath-value to key-value =======================================
awk -F '/' '{print $NF}'                                             |
#                                                                    #
# === Uniquify blanks ================================================
sed 's/  */ /g'                                                      |
#                                                                    #
# === Generate xml ===================================================
awk 'NF==2{printf("\n%s %s",$1, $2)}                                 #
     /^@/{printf(" %s",$0)}                                          #
     /\\$/{printf("\n%s",$0)}                                        #
     /^[^@]/ && /[^\\]$/ && NF<2{printf("\n%s",$0)}'                 |
sed 's/\(.*\) \([^@]*\) \(@.*\)$/<\1 \3>\2/'                         |
awk 'NF==2 && $0 !~ /@/{printf("<%s>%s\n",$1,$2)}                    #
     NF!=2 || /@/{print $0}'                                         |
sed 's/ $//'                                                         |
sed '/^[^<].*[^\//]$/ s/.*/<&>/'                                     |
grep -v '^\\$'                                                       |
grep -v '^$'                                                         |
sed '/.*\\$/ s:\(.*\)\\:</\1>:'                                      |
#                                                                    #
# === Revert unnecesary caret "^" to "/" =============================
sed 's:\^:/:g'                                                       |
#                                                                    #
# === Remove attribute marker ========================================
sed 's/@//g'                                                         |
#                                                                    #
# === Remove LFs =====================================================
tr -d '\n'                                                           |
grep ^                                                               |
#                                                                    #
# === Insert XML declaration =========================================
sed 's/^/<?xml version="1.0" encoding="UTF-8"?>/'                    |
#                                                                    #
# === Empty tags =====================================================
sed 's:<\(.*\)></\1>:<\1 />:g'                                       # 
#                                                                    #
# === Final LF =======================================================
echo                                                                 #
