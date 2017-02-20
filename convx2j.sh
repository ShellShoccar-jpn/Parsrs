#!/bin/sh

######################################################################
#
# CONVX2J.SH
#   Converting From XPath-value To JSONPath-value
#
# === What is This? ===
# * This command will probably be very useful to convert from XML to JSON!
#   You can convert a lot of XML data into JSON data by passing it through
#   the following one-liner.
#     > cat hoge.xml | parsrx.sh -c -n | convx2j.sh | makrj.sh
# * But by the difference between XML and JSON, the lines of XPath-value
#   which have child tags in its value will be ignored.
#
#
# === Usage ===
# Usage: convx2j.sh [XPath-value_textfile]
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-02-20
#
# This is a public-domain software (CC0). It means that all of the
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
export PATH="$(command -p getconf PATH)${PATH:+:}${PATH:-}"

# === Usage printing function ========================================
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [-n] [XPath-value_textfile]
	Version : 2017-02-20 22:36:45 JST
	          (POSIX Bourne Shell/POSIX commands)
	USAGE
  exit 1
}


######################################################################
# Prepare for the Main Routine
######################################################################

# === Get the options and the filepath ===============================
nopt=0
case "$#" in [!0]*) case "$1" in '-n') nopt=1;shift;; esac;; esac
case "$#" in
  0) file='-'
     ;;
  1) if [ -f "$1" ] || [ -c "$1" ] || [ -p "$1" ] || [ "_$1" = '_-' ]; then
       file=$1
     fi
     ;;
  *) print_usage_and_exit
     ;;
esac


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the data source =================================================== #
cat "$file"                                                                    |
#                                                                              #
# === Delete XPath lines which have child tags =============================== #
grep -v '/>'                                                                   |
#                                                                              #
# === Delete the top "/" ===================================================== #
sed 's/^\///'                                                                  |
#                                                                              #
# === Reverse line order ===================================================== #
sed -n -e '1!G;h;$p'                                                           |
#                                                                              #
# === Remove every first suffix numbers ([1]) ================================ #
awk '                                                                          #
BEGIN {                                                                        #
  # --- 0) initialize ------------------------------------------------         #
  OFS=""; ORS="";                                                              #
  odd=0;                                                                       #
  split("", name0, "/");                                                       #
  #                                                                            #
  # --- 1) start of loop ---------------------------------------------         #
  while (getline line) { odd=1-odd;                                            #
  #                                                                            #
  # --- 2) separate XPath-value into XPath and value -----------------         #
  p=index(line," "); path=substr(line,1,p-1); val=substr(line,p+1);            #
  # --- 3) remove every first suffix "[1]" in the path string --------         #
  gsub(/\[1\]/, "", path);                                                     #
  # --- 4) decrement every suffix number -----------------------------         #
  s="";                                                                        #
  while (match(path,/\[[0-9]+\]/)) {                                           #
    s = s substr(path,1,RSTART) substr(path,RSTART+1,RLENGTH-2)-1 "]";         #
    path = substr(path,RSTART+RLENGTH);                                        #
  }                                                                            #
  path = s path;                                                               #
  # --- 5) split up the path into tag/property names -----------------         #
  if (odd==0) {split(path, name0, "/");} else {split(path, name1, "/");}       #
  # --- 6) revive the first suffix "[0]" if there is "[1]" in the previous one #
  if (odd==0) {                                                                #
    for (i=1; ; i++) {                                                         #
      if (!(i in name0))       {break           ;}                             #
      if (!(i in name1))       {break           ;}                             #
      s=name0[i]; s0=name1[i];                                                 #
      if (s==s0              ) {continue        ;}                             #
      p=index(s0,"[");                                                         #
      if (p==0               ) {break           ;}                             #
      if (s==substr(s0,1,p-1)) {name0[i]=s "[0]";}                             #
      break;                                                                   #
    }                                                                          #
  } else {                                                                     #
    for (i=1; ; i++) {                                                         #
      if (!(i in name1))       {break           ;}                             #
      if (!(i in name0))       {break           ;}                             #
      s=name1[i]; s0=name0[i];                                                 #
      if (s==s0              ) {continue        ;}                             #
      p=index(s0,"[");                                                         #
      if (p==0               ) {break           ;}                             #
      if (s==substr(s0,1,p-1)) {name1[i]=s "[0]";}                             #
      break;                                                                   #
    }                                                                          #
  }                                                                            #
  # --- 7) print out a line as JSONPath-value ------------------------         #
  print "$";                                                                   #
  if (odd==0) {                                                                #
    for (i=1; (i in name0); i++) {                                             #
      print ".", name0[i];                                                     #
    }                                                                          #
  } else {                                                                     #
    for (i=1; (i in name1); i++) {                                             #
      print ".", name1[i];                                                     #
    }                                                                          #
  }                                                                            #
  print " ", val, "\n";                                                        #
                                                                               #
  # --- 8) end of loop -----------------------------------------------         #
  }                                                                            #
}'                                                                             |
#                                                                              #
# === Reverse and restore line order again =================================== #
sed -n -e '1!G;h;$p'
