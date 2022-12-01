#!/bin/sh

######################################################################
#
# XPATHREAD.SH
#   Create a Subset Table from the XPath-value Formated Data File
#
# === What is This? ===
# * The command "xpathread.sh /foo/bar (A) > (B)" converts the following
#   data file (A) to obtain file (B), who has space separated value data
#   with header.
#   + (A) /foo/bar/name Frog
#         /foo/bar/age 3
#         /foo/bar 
#         /foo/bar/name Chick
#         /foo/bar/age 1
#         /foo/bar 
#         /foo 
#   + (B) name age
#         Frog 3
#         Chick 1
# * This command requires a preprocessor "parsrx.sh" who converts XML
#   data into XPath-value format.
#   + Example to convert the XML file (X) to (B):
#     - cat (X) | parsrx.sh | xpathread.sh /foo/bar
#     - (X) <foo>
#             <bar>
#               <name>Frog</name><age>3</age>
#             </bar>
#             <bar>
#               <name>Chick</name><age>1</age>
#             </bar>
#           </foo>
# * JSON data can also be fed, with preprocessor "parsrj.sh --xpath".
#   + Example to convert the JSON file (J) to (B):
#     - cat (J) | parsrj.sh --xpath | xpathread.sh /foo/bar
#     - (J) {"foo": 
#                   {"bar": [
#                            {"name":"Frog" , "age": 3},
#                            {"name":"Chick", "age": 1}
#                           ]
#                   }
#           }
# * This command ignores index numbers in XPath strings.
#   e.g. "/foo/bar[1]", "/foo[1]/bar[2]"
#   These all are equivalent to "/foo/bar".
#
# Usage   : xpathread.sh [-s<str>] [-n<str>] [-p] <XPath> [XPath_indexed_data]
# Options : -s replaces blank characters in value with <str> (default:"_")
#           -n represents null value with <str> (default:"@")
#           -p permits to add the properties of the tag to the table
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2022-02-07
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
print_usage_and_exit () {
  cat <<-USAGE 1>&2
	Usage   : xpathread.sh [-s<str>] [-n<str>] [-p] <XPath> [XPath_indexed_data]
	Options : -s replaces blank characters in value with <str> (default:"_")
	          -n replaces null value with <str> (default:"@")
	          -p permits to add the properties of the tag to the table
	Version : 2022-02-07 00:30:38 JST
	          (POSIX Bourne Shell/POSIX commands)
	USAGE
  exit 1
}
error_exit() {
  ${2+:} false && echo "${0##*/}: $2" 1>&2
  exit $1
}

# === decide whether to use the alternative length of AWK or not =====
if awk 'BEGIN{a[1]=1;b=length(a)}' 2>/dev/null; then
  arlen='length'
else
  arlen='arlen'
fi


######################################################################
# Prepare for the Main Routine
######################################################################

# === Parse arguments ================================================
opts='_'
optn='@'
optp=''
xpath=''
xpath_file=''
optmode=''
i=0
printhelp=0
case $# in ([!0]*)
  for arg in ${1+"$@"}; do
    i=$((i+1))
    case "${optmode}" in ('')
      case "$arg" in
        (-[sdnip]*)
          ret=$(echo "_${arg#-}" |
                awk '{
                  opts = "_";
                  optn = "_";
                  optp = "_";
                  opt_str = "";
                  for (n=2; n<=length($0); n++) {
                    s = substr($0,n,1);
                    if ((s == "s") || (s == "d")) {
                      opts = "s";
                      opt_str = substr($0, n+1);
                      break;
                    } else if ((s == "n") || (s == "i")) {
                      optn = "n";
                      opt_str = substr($0, n+1);
                      break;
                    } else if (s == "p") {
                      optp = "p";
                    }
                  }
                  printf("%s%s%s %s", opts, optn, optp, opt_str);
                }')
          ret1=${ret%% *}
          ret2=${ret#* }
          case "${ret1}" in (*s*)
            opts=$ret2
          esac
          case "${ret1}" in (*n*)
            case "${#ret2}" in ([!0]*)
              optn=$ret2
            ;;(*)
              optmode='n'
            ;;esac
          esac
          case "${ret1}" in (*p*)
            optp='#'
          esac
          ;;
        (*)
          case "${#xpath},${#xpath_file}" in (0,*)
            if [ $i -lt $(($#-1)) ]; then
              printhelp=1
              break
            fi
            xpath=$arg
          ;;(*,0)
            case $i in ($#)
              :
            ;;(*)
              printhelp=1
              break
            ;;esac
            if [ ! -f "$xpath_file"       ] &&
               [ ! -c "$xpath_file"       ] &&
               [ ! "_$xpath_file" != '_-' ]  ; then
              printhelp=1
              break
            fi
            xpath_file=$arg
          ;;(*)
            printhelp=1
            break
          ;;esac
          ;;
      esac
    ;;(n)
      optn=$arg
      optmode=''
    ;;(*)
      printhelp=1
      break
    ;;esac
  done
  ;;
esac
case "${#xpath}"      in     0) printhelp=1         ;; esac
case $printhelp       in [!0]*) print_usage_and_exit;; esac
case "${#xpath_file}" in     0) xpath_file='-'      ;; esac

# === Prepare a temporary file =======================================
which mktemp >/dev/null 2>&1 || {
  mktemp_fileno=0
  mktemp() {
    local mktemp_filename
    mktemp_filename="/tmp/${0##*/}.$$.$mktemp_fileno"
    mktemp_fileno=$((mktemp_fileno+1))
    touch "$mktemp_filename"
    chmod 600 "$mktemp_filename"
    echo "$mktemp_filename"
  }
}
tempfile=$(mktemp -t "${0##*/}.XXXXXXXX")
case $? in 0) trap "rm -f $tempfile; exit" EXIT HUP INT QUIT ALRM SEGV TERM;;
           *) error_exit 1 "Can't create a temporary file"                 ;;
esac


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === Write the following pre-processed data into a temporary file ===
# * Delete lines that their XPath match none of the following rules
#   + Specified XPath
#   + Chilren of the specified XPath
# * Truncate the XPath string from the top to the specified hierarchy
# * On the first field, cut any strings other than the child name and
#   also cut any index numbers "[n]"
# * On the second field and beyond, replace the blank character with
#   the specified substituted character
awk '
  BEGIN {
    xpath    = "'"$xpath"'";
    xpathlen = length(xpath);
    if (substr(xpath,xpathlen) == "/") {
      sub(/\/$/, "", xpath);
      xpathlen--;
    }
    while (getline line) {
      if (match(line,/^[^[:blank:]]+$/)) {line=line " ";}
      i = index(line, " ");
      f1 = substr(line, 1, i-1);
      if (substr(f1,1,xpathlen) != xpath) {
        continue;
      }
      f1 = substr(f1, xpathlen+1);
      sub(/^\[[0-9]+\]/, "", f1);
      if (length(f1) == 0) {
        print "/";
        continue;
      }
      f1 = substr(f1, 2);
      j = index(f1, "/");
      if (j != 0) {
         '"$optp"'continue;
         if (substr(f1,j+1,1) != "@") {
           continue;
         }
      }
      sub(/\[[0-9]+\]$/, "", f1);
      if ((i==0) || (i==length(line))) {
        f2 = "";
      } else {
        f2 = substr(line, i+1);
        gsub(/[[:blank:]]/, "'"$opts"'", f2);
      }
      print f1, f2;
    }
  }
' "$xpath_file" > "$tempfile"

# === Enumerate the tag names separated by the space character =======
tags=$(awk '                              \
         BEGIN {                          \
           OFS = "";                      \
           ORS = "";                      \
           split("", tagnames);           \
           split("", tags);               \
           numoftags = 0;                 \
           while (getline line) {         \
             if (line == "/") {           \
               continue;                  \
             }                            \
             sub(/ .*$/, "", line);       \
             if (line in tagnames) {      \
               continue;                  \
             }                            \
             numoftags++;                 \
             tagnames[line] = 1;          \
             tags[numoftags] = line;      \
           }                              \
           if (numoftags > 0) {           \
             print tags[1];               \
           }                              \
           for (i=2; i<=numoftags; i++) { \
             print " ", tags[i];          \
           }                              \
         }                                \
       ' "$tempfile"                      )

# === Generate the table =============================================
awk -v tags="$tags" '
  # the alternative length function for array variable
  function arlen(ar,i,l){for(i in ar){l++;}return l;}

  BEGIN {
    # Register the tagnames and the orders
    split(tags, order2tag);
    split(""  , tag2order);
    numoftags = '$arlen'(order2tag);
    for (i=1; i<=numoftags; i++) {
      tag2order[order2tag[i]] = i;
    }
    # Initialize
    OFS = "";
    ORS = "";
    LF = sprintf("\n");
    # Print the tag line
    print tags, LF;
    # Print the body lines
    split("", fields);
    while (getline line) {
      if (line != "/") {
        # a. Memorize the value if the line is regular one
        i = index(line, " ");
        f1 = substr(line, 1  , i-1);
        f2 = substr(line, i+1     );
        if (length(f2)) {
          fields[tag2order[f1]] = f2;
        }
      } else {
        # b. Flush the line if arrived at a record boundary
        if (numoftags >= 1) {
          print      (1 in fields) ? fields[1] : "'"$optn"'";
        }
        for (i=2; i<=numoftags; i++) {
          print " ", (i in fields) ? fields[i] : "'"$optn"'";
        }
        print LF;
        split("", fields);
        continue;
      }
    }
  }
' "$tempfile"
