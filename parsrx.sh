#!/bin/sh

######################################################################
#
# PARSRX.SH
#   A XML Parser Which Convert Into "XPath-value"
#
# === What is "XPath-value" Formatted Text? ===
# 1. Format
#    <XPath_string#1> + <0x20> + <value_at_that_path#1>
#    <XPath_string#2> + <0x20> + <value_at_that_path#2>
#    <XPath_string#3> + <0x20> + <value_at_that_path#3>
#             :              :              :
#
# === This Command will Do Like the Following Conversion ===
# 1. Input Text (XML or HTML which is completely compatible with XML)
#    <foo>
#      Great!
#      <bar foo="FOO" bar="BAR">Wow!<br /><script></script></bar>
#      Awsome!
#    </foo>
# 2. Output Text This Command Converts Into
#    /foo/bar/@foo FOO
#    /foo/bar/@bar BAR
#    /foo/bar/br
#    /foo/bar/script 
#    /foo/bar Wow!
#    /foo \n  Great!\n  \n  Awsome!\n
#
# === Usage ===
# Usage   : parsrx.sh [options] [XML_file]
# Options : -c  Print the child tags in value explicitly
#         : -n  Print the array subscript number after the tag name
#         : -lf Replace the newline sign "\n" with <s>.
#               This mode disables replacing \ with \\.
# Environs: LINE_BUFFERED
#             =yes ........ Line-buffered mode if possible
#             =forcible ... Force line-buffered mode. Exit if unavailable.
#
#
#
# Written by Shell-Shoccar Japan (@shellshoccarjpn) on 2024-01-11
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
print_usage_and_exit() {
  cat <<-USAGE 1>&2
	Usage   : ${0##*/} [options] [XML_file]
	Options : -c  Print the child tags in value explicitly
	          -n  Print the array subscript number after the tag name
	          -lf Replace the newline sign "\n" with <s>. 
	              This option disables replacing \\ with \\\\.
	Environs: LINE_BUFFERED
	            =yes ........ Line-buffered mode if possible
	            =forcible ... Force line-buffered mode. Exit if unavailable.
	Version : 2024-01-11 13:02:00 JST
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
unoptc='#'
unoptn='#'
file=''
#
# --- get them -------------------------------------------------------
for arg in ${1+"$@"}; do
  if   [ "_${arg#-lf}" != "_$arg" ] && [ -z "$file" ]; then
    optlf=$(printf '%s' "${arg#-lf}_" |
            tr -d '\n'                |
            grep ''                   |
            sed 's/\([\&/]\)/\\\1/g'  )
    optlf=${optlf%_}
  elif [ "_${arg#-}" != "_$arg" ] && [ -n "${arg#-}" ] && [ -z "$file" ]; then
    for opt in $(printf '%s\n' "${arg#-}" | sed 's/\(.\)/\1 /g'); do
      case "$opt" in
        c) unoptc=''           ;;
        n) unoptn=''           ;;
        *) print_usage_and_exit;;
      esac
    done
  elif [ "_$arg" = '_-' ] && [ -z "$file" ]; then
    file='-'
  elif ([ -f "$arg" ] || [ -c "$arg" ]) && [ -z "$file" ]; then
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
s=$(printf '\016\017\020\021\022\023\024\025\026\027\030\031\177\t\\\n_')
SCT=${s%????????????????}; s=${s#?} # Escape chr. for "Start Candicate of Tag"
ECT=${s%???????????????} ; s=${s#?} # Escape chr. for "End Candicate of Tag"
PRO=${s%??????????????}  ; s=${s#?} # Identificator for XML property line
SCS=${s%?????????????}   ; s=${s#?} # Escape chr. for "Start Candicate of '"
ECS=${s%????????????}    ; s=${s#?} # Escape chr. for "End Candicate of '"
SCD=${s%???????????}     ; s=${s#?} # Escape chr. for 'Start Candicate of "'
ECD=${s%??????????}      ; s=${s#?} # Escape chr. for 'End Candicate of "'
SPC=${s%?????????}       ; s=${s#?} # Escape chr. for "space chr. in quoted str"
TAB=${s%????????}        ; s=${s#?} # Escape chr. for "tab chr. in quoted str"
GT=${s%???????}          ; s=${s#?} # Escape chr. for '">" chr. in quoted str'
LT=${s%??????}           ; s=${s#?} # Escape chr. for '"<" chr. in quoted str'
SLS=${s%?????}           ; s=${s#?} # Escape chr. for '"/" chr. in quoted str'
LF=${s%????}             ; s=${s#?} # Escape chr. for '"\n" chr. in quoted str'
T=${s%???}               ; s=${s#?} # TAB chr.
N=${s%?}                            # LF chr. for the sed command

# === Check whether the AWK on this host support length() or not =====
case "$(awk 'BEGIN{a[3]=3;a[4]=4;print length(a)}' 2>/dev/null)" in
  2) arlen='length';;
  *) arlen='arlen' ;; # use an equivalent original function if not supported
esac

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

# === Send the datafile into the pipeline ==================================== #
grep '' ${file:+"$file"}                                                       |
#                                                                              #
# === Remove all comment strings (<!-- -->) ================================== #
awk '                                                                          #
  BEGIN {                                                                      #
    OFS=""; ORS=""; f=0;                                                       #
    while (getline line) {                                                     #
      while (line != "") {                                                     #
        if (f==0) { p=index(line,"<!--");                                      #
          if (p==0) {print line; break;}                                       #
          print substr(line,1,p-1); line=substr(line,p+4); f=1;                #
        } else    { p=index(line,"-->" );                                      #
          if (p==0) {break;}                                                   #
                                    line=substr(line,p+3); f=0;                #
        }                                                                      #
      }                                                                        #
      if (f==0) {print "\n";'"$awkfl"'}                                        #
    }                                                                          #
    if (f==1) {print "\n";}                                                    #
  }                                                                            #
'                                                                              |
#                                                                              #
# === Escape all chrs., " ", "\t", "<", and ">" in the tag string ============ #
# 1) Mark behind the end of the line                                           #
sed 's/$/'"$LF"'/'                                                             |
# 2) Insert a LF before the ordinal tags                                       #
sed 's/\(<[^'" $T"'!-.0-9;-@[-^`{-~][^'" $T"'!-,/;-@[-^`{-~]*\)/'"$N$SCT"'\1/g'|
# 3) Also insert a LF before the beginning of the property strings             #
sed 's/='"'"'/='"$N$SCS""'"'/g'                                                |
sed 's/="/='"$N$SCD"'"/g'                                                      |
# 4) Also insert a LF behind the end of the property strings                   #
sed 's/\([^'"$SCS$SCD"']\)'"'"'\(['" $T$LF"'/>]\)/\1'"$N$ECS""'"'\2/g'         |
sed 's/\([^'"$SCS$SCD"']\)"\(['" $T$LF"'/>]\)/\1'"$N$ECD"'"\2/g'               |
sed 's/^'"'"'\(['" $T$LF"'/>]\)/'"$ECS'"'\1/'                                  |
sed 's/^"\(['" $T$LF"'/>]\)/'"$ECD"'"\1/'                                      |
sed "s/^'$/$ECS'/"                                                             |
sed 's/^"$/'"$ECD"'"/'                                                         |
# 5) Also insert a LF behind the end of every ordinal tag                      #
sed 's/>/'"$N$ECT"'>/g'                                                        |
# 6) Main Process                                                              #
#    * Escape all "\t", "<", ">", and " " chrs. in the property value strings  #
#    * Replace all LFs with " " out of quotes and in the tags whenever escaped #
#    * Remove all quotation marks (except as a part of values)                 #
awk '                                                                          #
  BEGIN {                                                                      #
    OFS = "";                                                                  #
    ORS = "";                                                                  #
    LF  = "\n";                                                                #
    Sct = "'"$SCT"'"; # Escape chr. for "Start Candicate of Tag"....keep       #
    Ect = "'"$ECT"'"; # Escape chr. for "End Candicate of Tag"......keep       #
    Scs = "'"$SCS"'"; # Escape chr. for "Start Candicate of 0x27"...delete     #
    Ecs = "'"$ECS"'"; # Escape chr. for "End Candicate of 0x27".....delete     #
    Scd = "'"$SCD"'"; # Escape chr. for "Start Candicate of 0x22"...delete     #
    Ecd = "'"$ECD"'"; # Escape chr. for "End Candicate of 0x22".....delete     #
    SPC = "'"$SPC"'"; # Escape chr. for "space chr. in quoted str"..replace    #
    TAB = "'"$TAB"'"; # Escape chr. for "tab chr. in quoted str"....replace    #
    SLS = "'"$SLS"'"; # Escape chr. for "/" chr. in quoted str......replace    #
    GT  = "'"$GT"'";  # Escape chr. for ">" chr. in quoted str......replace    #
    LT  = "'"$LT"'";  # Escape chr. for "<" chr. in quoted str......replace    #
    in_tag  =  0; # A flag means that the reading pointer is in a tag          #
    in_quot =  0; # A flag means that the reading pointer is in 0x27(1),0x22(2)#
    while (getline line) {                                                     #
      headofline = substr(line,1,1);                                           #
      if (in_tag == 0) {                                                       #
        # 1. when the pointer is out of a tag                                  #
        if (       headofline == Sct) {                                        #
          # 1-1. when the pointer reaches the start of a tab                   #
          in_tag = 1;                                                          #
          gsub(/'"$LF"'/, " ", line);                                          #
          print LF, line;'"$awkfl"'                                            #
        } else {                                                               #
          # 1-2. when the pointer does not reaches a tag yet                   #
          print substr(line,1);                                                #
        }                                                                      #
      } else if (in_quot == 0) {                                               #
        # 2. when the pointer is in a tag, but out of quotations               #
        if (       headofline == Ect) {                                        #
          # 2-1. when the pointer reaches the end of the tag                   #
          in_tag = 0;                                                          #
          print line, LF;'"$awkfl"'                                            #
        } else if (headofline == Scs) {                                        #
          # 2-2. when the pointer reaches a start of a single-quotation        #
          in_quot = 1;                                                         #
          gsub(/ / ,SPC, line);                                                #
          gsub(/\t/,TAB, line);                                                #
          gsub(/\//,SLS, line);                                                #
          gsub(/>/ , GT, line);                                                #
          gsub(/</ , LT, line);                                                #
          print substr(line,3);                                                #
        } else if (headofline == Scd) {                                        #
          # 2-3. when the pointer reaches a start of a double-quotation        #
          in_quot = 2;                                                         #
          gsub(/ / ,SPC, line);                                                #
          gsub(/\t/,TAB, line);                                                #
          gsub(/\//,SLS, line);                                                #
          gsub(/>/ , GT, line);                                                #
          gsub(/</ , LT, line);                                                #
          print substr(line,3);                                                #
        } else {                                                               #
          # 2-4. other case (it is in a tag and also out of quotations         #
          gsub(/'"$LF"'/, " ", line);                                          #
          print substr(line,2);                                                #
        }                                                                      #
      } else if (in_quot == 1) {                                               #
        # 3. when the pointer is in single-quotations                          #
        if (       headofline == Ecs) {                                        #
          # 3-1. when the pointer reaches the end of the single-quotations     #
          in_quot = 0;                                                         #
          gsub(/'"$LF"'/, " ", line);                                          #
          print substr(line,3);                                                #
        } else {                                                               #
          # 3-2. other case (at a start of tag, or other end of quotations)    #
          gsub(/ / ,SPC, line);                                                #
          gsub(/\t/,TAB, line);                                                #
          gsub(/\//,SLS, line);                                                #
          gsub(/>/ , GT, line);                                                #
          gsub(/</ , LT, line);                                                #
          print line;                                                          #
        }                                                                      #
      } else {                                                                 #
        # 4. when the pointer is in double-quotations                          #
        if (       headofline == Ecd) {                                        #
          # 4-1. when the pointer reaches the end of the quotations            #
          in_quot = 0;                                                         #
          gsub(/'"$LF"'/, " ", line);                                          #
          print substr(line,3);                                                #
        } else {                                                               #
          # 4-2. other case (at a start of tag, or other end of quotations)    #
          gsub(/ / ,SPC, line);                                                #
          gsub(/\t/,TAB, line);                                                #
          gsub(/\//,SLS, line);                                                #
          gsub(/>/ , GT, line);                                                #
          gsub(/</ , LT, line);                                                #
          print line;                                                          #
        }                                                                      #
      }                                                                        #
    }                                                                          #
  }                                                                            #
'                                                                              |
#                                                                              #
# === Separate the data into tagnames, properties, and other strings in a tag  #
# 1)Make every tagname independent (and remove "<" and ">" at the same time)   #
sed 's/'"$SCT"'<\([^'"$ECT"']*\)'"$ECT"'>/'"$N$SCT"'\1'"$N"'/g'                |
# 2)Separate the tagname part and each of its properties                       #
#   * Attach an identifier at the beginning to indicate tag or property        #
#   * Property lines are printed first, tagname line is last                   #
awk '                                                                          #
  # the alternative length function for array variable                         #
  function arlen(ar,i,l){for(i in ar){l++;}return l;}                          #
                                                                               #
  BEGIN {                                                                      #
    OFS = "";                                                                  #
    Tag = "'"$SCT"'"; # Escape chr. for "Start Candicate of Tag"....keep       #
    Pro = "'"$PRO"'"; # Escape chr. for "A Property line"...........add        #
    while (getline line) {                                                     #
      headofline = substr(line,1,1);                                           #
      if (headofline == Tag) {                                                 #
        # 1. When the line indicates a tagname                                 #
        split(line, items);                                                    #
        tagname = substr(items[1],2);                                          #
        sub(/\/$/, "", tagname);                                               #
        # 1-1. Is the tag without the closing pair? (as in <br/>)              #
        i = '$arlen'(items);                                                   #
        if (match(items[i],/\/$/)) {                                           #
          singletag = 1;                                                       #
          if (RSTART == 1) {                                                   #
            i--;                                                               #
          } else {                                                             #
            items[i] = substr(items[i], 1, RSTART-1);                          #
          }                                                                    #
        } else {                                                               #
          singletag = 0;                                                       #
        }                                                                      #
        # 1-2. Divide each property into individual lines                      #
        for (j=2; j<=i; j++) {                                                 #
          item = items[j];                                                     #
          if (match(item, /^[^=]+/)) {                                         #
            proname = substr(item,1,RLENGTH);                                  #
            if (match(item, /^[^=]+["'"'"'].+["'"'"']$/)) {                    #
              k = length(proname);                                             #
              proval = substr(item,k+3,length(item)-k-3);                      #
              print Pro, tagname, Pro, proname, " ", proval;'"$awkfl"'         #
            } else if (length(proname) == length(item)) {                      #
              print Pro, tagname, Pro, proname, " ";'"$awkfl"'                 #
            } else {                                                           #
              proval = substr(item,length(proname)+2);                         #
              print Pro, tagname, Pro, proname, " ", proval;'"$awkfl"'         #
            }                                                                  #
          }                                                                    #
        }                                                                      #
        # 1-3. Print a tagname as an individual line                           #
        print Tag,      tagname;'"$awkfl"'                                     #
        # 1-4. Insert the closing tag line if the tag does not have the pair   #
        if (singletag) {                                                       #
          print Tag,"//",tagname;'"$awkfl"' # Mark with "//" for identification#
        }                                                                      #
      } else {                                                                 #
        # 2. Pass through if the line is not a kind of tag                     #
        print line;'"$awkfl"'                                                  #
      }                                                                        #
    }                                                                          #
  }                                                                            #
'                                                                              |
# === Express tags/properties in XPath and print its value after it ========== #
# * XPath will be printed at the 1st field and its value will follow it        #
#    /PATH/TO/TAG_NAME VALUE                                                   #
#    /PATH/TO/TAG_NNAME/@PROPERTY_NAME VALUE                                   #
# * The field separator " " is always put after XPath whenever the value is "" #
awk '                                                                          #
  BEGIN {                                                                      #
    OFS = "";                                                                  #
    ORS = "";                                                                  #
    LF  = "\n";                                                                #
    Tag = "'"$SCT"'"; # Escape chr. for "Start Candicate of Tag"....delete     #
    Pro = "'"$PRO"'"; # Escape chr. for "A Property line"...........delete     #
    split("", tagpath); # K:hierarchy-level, V:pathname                        #
    split("", tagvals); # K:hierarchy-level, V:NumOfProperties/string          #
    split("", tagbros); # K:hierarchy-level, V:XPath                           #
    split("", tagrept); # K:"hierarchy-level/tagname", V:NumOfAppearances      #
    currentdepth     =  0; # My current level                                  #
    currentpathitems =  0; # Number of words that the current XPath has        #
    while (getline line) {                                                     #
      headofline = substr(line,1,1);                                           #
      if (       headofline == Tag) {                                          #
        # 1. When it is a tag                                                  #
        if (substr(line,2,1) == "/") {                                         #
          # 1-1. When it is a closing tag line,                                #
          #      print its value with the XPath and return the parent level    #
          for (i=1; i<=currentdepth; i++) {                                    #
            s =  tagpath[i];                                                   #
            print "/", s;                                                      #
            '"$unoptn"'print "[", tagrept[i "/" s], "]";                       #
          }                                                                    #
          if (substr(line,3,1) != "/") {print " ";} #<-If the tag is a single  #
          for (i=1; i<=currentpathitems; i++) {     #  one, " " will not be    #
            print  tagvals[currentdepth "," i];     #  added after the XPath   #
            delete tagvals[currentdepth "," i];                                #
          }                                                                    #
          print LF;'"$awkfl"'                                                  #
          delete tagpath[currentdepth];                                        #
          '"$unoptn"'i = currentdepth + 1;                                     #
          '"$unoptn"'if (i in tagbros) {                                       #
          '"$unoptn"'  split(substr(tagbros[i],2), array, "/");                #
          '"$unoptn"'  for (j in array) {                                      #
          '"$unoptn"'    delete tagrept[i "/" array[j]];                       #
          '"$unoptn"'  }                                                       #
          '"$unoptn"'  split("", array);                                       #
          '"$unoptn"'}                                                         #
          currentdepth--;                                                      #
          currentpathitems = tagvals[currentdepth];                            #
          delete tagvals[currentdepth];                                        #
        } else {                                                               #
          # 1-2. When it is an opening tag,                                    #
          #      enter the child hierarchy                                     #
          currenttagname = substr(line,2);                                     #
          '"$unoptc"'childtag = "<" currenttagname "/>";                       #
          '"$unoptc"'currentpathitems++;                                       #
          '"$unoptc"'tagvals[currentdepth "," currentpathitems] = childtag;    #
          tagvals[currentdepth] = currentpathitems;                            #
          currentpathitems = 0;                                                #
          currentdepth++;                                                      #
          tagpath[currentdepth] = currenttagname;                              #
          '"$unoptn"'if (currentdepth in tagbros) {                            #
          '"$unoptn"'  if (currentdepth "/" currenttagname in tagrept) {       #
          '"$unoptn"'    tagrept[currentdepth "/" currenttagname]++;           #
          '"$unoptn"'  } else {                                                #
          '"$unoptn"'    s = tagbros[currentdepth] "/" currenttagname;         #
          '"$unoptn"'    tagbros[currentdepth] = s;                            #
          '"$unoptn"'    tagrept[currentdepth "/" currenttagname] = 1;         #
          '"$unoptn"'  }                                                       #
          '"$unoptn"'} else {                                                  #
          '"$unoptn"'  tagbros[currentdepth] = "/" currenttagname;             #
          '"$unoptn"'  tagrept[currentdepth "/" currenttagname] = 1;           #
          '"$unoptn"'}                                                         #
        }                                                                      #
      } else if (headofline == Pro) {                                          #
        # 2. When it is a property line                                        #
        for (i=1; i<=currentdepth; i++) {                                      #
          s =  tagpath[i];                                                     #
          print "/", s;                                                        #
          '"$unoptn"'print "[", tagrept[i "/" s], "]";                         #
        }                                                                      #
        s = substr(line,2);                                                    #
        i = index(s, "'"$PRO"'");                                              #
        currenttagname = substr(s, 1, i-1);                                    #
        print "/", currenttagname;                                             #
        '"$unoptn"'j = currentdepth + 1;                                       #
        '"$unoptn"'if ((j "/" currenttagname) in tagrept) {                    #
        '"$unoptn"'  print "[", (tagrept[j "/" currenttagname]+1), "]";        #
        '"$unoptn"'} else {                                                    #
        '"$unoptn"'  print "[1]";                                              #
        '"$unoptn"'}                                                           #
        print "/@", substr(s,i+1), LF;'"$awkfl"'                               #
      } else {                                                                 #
        # 3. When it is another type, add the string after the current variable#
        currentpathitems++;                                                    #
        tagvals[currentdepth "," currentpathitems] = line;                     #
      }                                                                        #
    }                                                                          #
  }                                                                            #
'                                                                              |
#                                                                              #
# === Un-escape ============================================================== #
# 1) Unescape " ", "\t", "<", ">", and "/"                                     #
sed 's/'"$GT"'/>/g'                                                            |
sed 's/'"$LT"'/</g'                                                            |
sed 's/'"$SLS"'/\//g'                                                          |
sed 's/'"$SPC"'/ /g'                                                           |
sed 's/'"$TAB"'/'"$T"'/g'                                                      |
# 2) Unespace the escaped LF and replace it with "\n" or specified chr.        #
if [ "_$bsesc" != '_\\' ]; then                                                #
  sed 's/\\/'"$bsesc"'/g'                                                      #
else                                                                           #
  cat                                                                          #
fi                                                                             |
sed 's/'"$LF"'/'"$optlf"'/g'
