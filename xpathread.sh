#!/bin/sh

######################################################################
#
# XPATHREAD.SH
#   Create a Subset Table from the XPath-value Formated Data File
#
# === What is This? ===
# * The command "xpathread.sh /foo/bar (A) > (B)" converts the following
#   data file (A) to the following space separated value data with a
#   header (B)
#   + (A) /foo/bar/name Frog
#         /foo/bar/age 3
#         /foo/bar 
#         /foo/bar/name Chick
#         /foo/bar/age 1
#         /foo/bar 
#         /foo 
#   + (B) onamae nenrei
#         Frog 3
#         chick 1
# * You cannot give this command a XML data directly. If you want, change
#   the data format from XML to XPath-value with "parsrx.sh" command behind
#   this command.
#   + So if you want to convert the following XML data (X) to (B),
#     type the following one-liner command
#     - cat (X) | parsrx.sh | xpathread.sh /foo/bar
#     - (X) <foo>
#             <bar>
#               <name>Frog</name><age>3</age>
#             </bar>
#             <bar>
#               <name>Chick</name><age>1</age>
#             </bar>
#           </foo>
# * The JSON parser "parsrj.sh" can also generate XPath-value from JSON
#   data but it requires --xpath option. Therefore, you can use this command
#   not only XML data files but also JSON files with the JSON parser command.
#   + So if you want to convert the following JSON data (J) to (B),
#     type the following one-liner command
#     - cat (J) | parsrj.sh --xpath | xpathread.sh /foo/bar
#     - (J) {"foo": 
#                   {"bar": [
#                            {"name":"Frog" , "age": 3},
#                            {"name":"Chick", "age": 1}
#                           ]
#                   }
#           }
# * This command is tolerant of index numbers in XPath strings.
#   e.g. "/foo/bar[1]", "/foo[1]/bar[2]"
#   These all are regarded as "/foo/bar."
#
# Usage   : xpathread.sh [-s<str>] [-n<str>] [-p] <XPath> [XPath_indexed_data]
# Options : -s is for setting the substitution of blank (default:"_")
#           -n is for setting the substitution of null (default:"@")
#           -p permits to add the properties of the tag to the table
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2022-01-23
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
	Options : -s is for setting the substitution of blank (default:"_")
	          -n is for setting the substitution of null (default:"@")
	          -p permits to add the properties of the tag to the table
	Version : 2022-01-23 02:56:01 JST
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
case $# in [!0]*)
  for arg in ${1+"$@"}; do
    i=$((i+1))
    if [ -z "$optmode" ]; then
      case "$arg" in
        -[sdnip]*)
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
          if [ "${ret1#*s}" != "$ret1" ]; then
            opts=$ret2
          fi
          if [ "${ret1#*n}" != "$ret1" ]; then
            if [ -n "$ret2" ]; then
              optn=$ret2
            else
              optmode='n'
            fi
          fi
          if [ "${ret1#*p}" != "$ret1" ]; then
            optp='#'
          fi
          ;;
        *)
          if [ -z "$xpath" ]; then
            if [ $i -lt $(($#-1)) ]; then
              printhelp=1
              break
            fi
            xpath=$arg
          elif [ -z "$xpath_file" ]; then
            if [ $i -ne $# ]; then
              printhelp=1
              break
            fi
            if [ ! -f "$xpath_file"       ] &&
               [ ! -c "$xpath_file"       ] &&
               [ ! "_$xpath_file" != '_-' ]  ; then
              printhelp=1
              break
            fi
            xpath_file=$arg
          else
            printhelp=1
            break
          fi
          ;;
      esac
    elif [ "$optmode" = 'n' ]; then
      optn=$arg
      optmode=''
    else
      printhelp=1
      break
    fi
  done
  ;;
esac
[ -n "$xpath"  ] || printhelp=1
case $printhelp in [!0]*) print_usage_and_exit;; esac
[ -z "$xpath_file" ] && xpath_file='-'

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
if [ $? -eq 0 ]; then
  trap "rm -f $tempfile; exit" EXIT HUP INT QUIT ALRM SEGV TERM
else
  error_exit 1 "Can't create a temporary file"
fi


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
