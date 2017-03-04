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
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2017-03-05
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
export PATH="$(command -p getconf PATH)${PATH:+:}${PATH:-}"

# === Define the functions for printing usage and error message ======
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [XPath-value_textfile]
	Version : 2017-03-05 04:49:02 JST
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

# === Get the options and the filepath ===============================
case "$#" in
  0) file='-'
     ;;
  1) if [ -f "$1" ] || [ -c "$1" ] || [ -p "$1" ] || [ "_$1" = '_-' ]; then
       file=$1
     else
       error_exit 1 'Cannot open the file: '"$file"
     fi
     case "$file" in -|/*|./*|../*) :;; *) file="./$file";; esac
     ;;
  *) print_usage_and_exit
     ;;
esac


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Open the data source ================================================== #
cat "$file"                                                                   |
#                                                                             #
# === Delete XPath lines which have child tags ============================== #
grep -v '/>'                                                                  |
#                                                                             #
# === Delete the top "/" ==================================================== #
sed 's/^\///'                                                                 |
#                                                                             #
# === Reverse line order ==================================================== #
sed -n -e '1!G;h;$p'                                                          |
#                                                                             #
# === Remove every first suffix numbers ([1]) and convert into JSONPath-value #
awk '                                                                         #
BEGIN {                                                                       #
  # --- 0) initialize ------------------------------------------------        #
  OFS=""; ORS="";                                                             #
  odd=0;                                                                      #
  split("", name0, "/");                                                      #
  #                                                                           #
  # --- 1) start of loop ---------------------------------------------        #
  while (getline line) { odd=1-odd;                                           #
  #                                                                           #
  # --- 2) separate XPath-value into XPath and value -----------------        #
  p=index(line," "); path=substr(line,1,p-1); val=substr(line,p+1);           #
  # --- 3) remove every first suffix "[1]" in the path string --------        #
  gsub(/\[1\]/, "", path);                                                    #
  # --- 4) decrement every suffix number -----------------------------        #
  s="";                                                                       #
  while (match(path,/\[[0-9]+\]/)) {                                          #
    s = s substr(path,1,RSTART) substr(path,RSTART+1,RLENGTH-2)-1 "]";        #
    path = substr(path,RSTART+RLENGTH);                                       #
  }                                                                           #
  path = s path;                                                              #
  # --- 5) split up the path into tag/property names -----------------        #
  if (odd==0) {split(path, name0, "/");} else {split(path, name1, "/");}      #
  # --- 6) revive the first suffix "[0]" in the following cases ------        #
  #        a. There is "[0]" or "[1]" at the same name-tag in the same        #
  #           depth of previous line but there is no current one.             #
  #        b. There is the same name-tag in the same depth of previous line   #
  #           but the one is the deepest tag in the line.                     #
  if (odd==0) {                                                               #
    for (i=1; ; i++) {                                                        #
      if (!(i in name0))       {break           ;}                            #
      if (!(i in name1))       {break           ;}                            #
      s=name0[i]; s0=name1[i];                                                #
      if (s==s0              ) {                                              #
        if (index(s,"[")   )     {continue;              }                    #
        if (!(i+1 in name1))     {name0[i]=s "[0]";break;}                    #
        else                     {continue;              }                    #
      }                                                                       #
      p=index(s0,"[");                                                        #
      if (p==0               ) {break           ;}                            #
      if (s==substr(s0,1,p-1)) {name0[i]=s "[0]";}                            #
      break;                                                                  #
    }                                                                         #
  } else {                                                                    #
    for (i=1; ; i++) {                                                        #
      if (!(i in name1))       {break           ;}                            #
      if (!(i in name0))       {break           ;}                            #
      s=name1[i]; s0=name0[i];                                                #
      if (s==s0              ) {                                              #
        if (index(s,"[")   )     {continue;              }                    #
        if (!(i+1 in name0))     {name1[i]=s "[0]";break;}                    #
        else                     {continue;              }                    #
      }                                                                       #
      p=index(s0,"[");                                                        #
      if (p==0               ) {break           ;}                            #
      if (s==substr(s0,1,p-1)) {name1[i]=s "[0]";}                            #
      break;                                                                  #
    }                                                                         #
  }                                                                           #
  # --- 7) print out a line ------------------------------------------        #
  if (odd==0) {                                                               #
    for (i=1; (i in name0); i++) {                                            #
      print "/", name0[i];                                                    #
    }                                                                         #
  } else {                                                                    #
    for (i=1; (i in name1); i++) {                                            #
      print "/", name1[i];                                                    #
    }                                                                         #
  }                                                                           #
  print " ", val, "\n";                                                       #
                                                                              #
  # --- 8) end of loop -----------------------------------------------        #
  }                                                                           #
}'                                                                            |
#                                                                             #
# === Delete the top "/" again ============================================== #
sed 's/^\///'                                                                 |
#                                                                             #
# === Reverse and restore line order again ================================== #
sed -n -e '1!G;h;$p'                                                          |
#                                                                             #
# === Revive the second suffix "[1]" if required ============================ #
awk '                                                                         #
BEGIN {                                                                       #
  # --- 0) initialize ------------------------------------------------        #
  OFS=""; ORS="";                                                             #
  odd=0;                                                                      #
  split("", name0, "/");                                                      #
  #                                                                           #
  # --- 1) start of loop ---------------------------------------------        #
  while (getline line) { odd=1-odd;                                           #
  #                                                                           #
  # --- 2) separate XPath-value into XPath and value -----------------        #
  p=index(line," "); path=substr(line,1,p-1); val=substr(line,p+1);           #
  # --- 3) split up the path into tag/property names -----------------        #
  if (odd==0) {split(path, name0, "/");} else {split(path, name1, "/");}      #
  # --- 4) revive the first suffix "[1]" in the following case -------        #
  #        a. There is "[0]" at the same name-tag in the same                 #
  #           depth of previous line but there is no current one.             #
  if (odd==0) {                                                               #
    for (i=1; ; i++) {                                                        #
      if (i in name0)          {s =name0[i];} else {break;}                   #
      if (i in name1)          {s0=name1[i];} else {s0="";}                   #
      if (s==s0              ) {continue                 ;}                   #
      p=index(s0,"[");                                                        #
      if (p==0               ) {continue                 ;}                   #
      if (s==substr(s0,1,p-1)) {name0[i]=s "[1]"         ;}                   #
      continue;                                                               #
    }                                                                         #
  } else {                                                                    #
    for (i=1; ; i++) {                                                        #
      if (i in name1)          {s =name1[i];} else {break;}                   #
      if (i in name0)          {s0=name0[i];} else {s0="";}                   #
      if (s==s0              ) {continue                 ;}                   #
      p=index(s0,"[");                                                        #
      if (p==0               ) {continue                 ;}                   #
      if (s==substr(s0,1,p-1)) {name1[i]=s "[1]"         ;}                   #
      continue;                                                               #
    }                                                                         #
  }                                                                           #
  # --- 5) print out a line as JSONPath-value ------------------------        #
  print "$";                                                                  #
  if (odd==0) {                                                               #
    for (i=1; (i in name0); i++) {                                            #
      print ".", name0[i];                                                    #
    }                                                                         #
  } else {                                                                    #
    for (i=1; (i in name1); i++) {                                            #
      print ".", name1[i];                                                    #
    }                                                                         #
  }                                                                           #
  print " ", val, "\n";                                                       #
                                                                              #
  # --- 6) end of loop -----------------------------------------------        #
  }                                                                           #
}'