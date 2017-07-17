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
# Options : -c  Prints the child tags which are had by the parent tag
#         : -n  Prints the array subscript number after the tag name
#         : -lf Replaces the newline sign "\n" with <s>. And in this mode,
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
	Usage   : ${0##*/} [options] [XML_file]
	Options : -c  Prints the child tags which are had by the parent tag
	          -n  Prints the array subscript number after the tag name
	          -lf Replaces the newline sign "\n" with <s>. And in this mode,
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
SCT=$(printf '\016') # タグ開始端(候補)エスケープ用文字
ECT=$(printf '\017') # タグ終端(候補)エスケープ用文字
PRO=$(printf '\020') # 属性行開始識別文字
SCS=$(printf '\021') # 一重引用符開始端(候補)エスケープ用文字
ECS=$(printf '\022') # 一重引用符終端(候補)エスケープ用文字
SCD=$(printf '\023') # 二重引用符開始端(候補)エスケープ用文字
ECD=$(printf '\024') # 二重引用符終端(候補)エスケープ用文字
SPC=$(printf '\025') # 引用符内スペースのエスケープ用文字
TAB=$(printf '\026') # 引用符内タブのエスケープ用文字
GT=$( printf '\027') # 引用符内">"のエスケープ用文字
LT=$( printf '\030') # 引用符内"<"のエスケープ用文字
SLS=$(printf '\031') # 引用符内"/"のエスケープ用文字
LF=$( printf '\177') # 改行(タグ内の引用符外は除く)のエスケープ用文字

T=$( printf '\011')             # タブ(エスケープ用ではない)
N=$( printf '\\\012_');N=${N%_} # sedコマンド用の改行(エスケープ用ではない)

# === Check whether the AWK on this host support length() or not =====
case "$(awk 'BEGIN{a[3]=3;a[4]=4;print length(a)}' 2>/dev/null)" in
  2) arlen='length';;
  *) arlen='arlen' ;; # use an equivalent original function if not supported
esac


######################################################################
# Main Routine (Convert and Generate)
######################################################################

# === データの流し込み ======================================================= #
grep '' ${file:+"$file"}                                                       |
#                                                                              #
# === タグ内の属性値に含まれるスペース,改行,"<",">"を全てエスケープする ====== #
# 1)元あった改行に印をつける                                                   #
sed 's/$/'"$LF"'/'                                                             |
# 2)一般タグ(それ以外も混ざる)の始まる前で改行                                 #
sed 's/\(<[^'" $T"'!-.0-9;-@[-^`{-~][^'" $T"'!-,/;-@[-^`{-~]*\)/'"$N$SCT"'\1/g'|
# 3)属性値開始括弧(それ以外も混ざる)手前で改行                                 #
sed 's/='"'"'/='"$N$SCS""'"'/g'                                                |
sed 's/="/='"$N$SCD"'"/g'                                                      |
# 4)属性値終了括弧(それ以外も混ざる)前で改行                                   #
sed 's/\([^'"$SCS$SCD"']\)'"'"'\(['" $T$LF"'/>]\)/\1'"$N$ECS""'"'\2/g'         |
sed 's/\([^'"$SCS$SCD"']\)"\(['" $T$LF"'/>]\)/\1'"$N$ECD"'"\2/g'               |
sed 's/^'"'"'\(['" $T$LF"'/>]\)/'"$ECS'"'\1/'                                  |
sed 's/^"\(['" $T$LF"'/>]\)/'"$ECD"'"\1/'                                      |
sed "s/^'$/$ECS'/"                                                             |
sed 's/^"$/'"$ECD"'"/'                                                         |
# 5)一般タグ(それ以外も混ざる)の終わる前で改行                                 #
sed 's/>/'"$N$ECT"'>/g'                                                        |
# 6)本処理(混ざりを取り除く)                                                   #
#   ・タグ内の属性値区間のスペース,タブ,"<",">"をエスケープ                    #
#   ・エスケープした改行でもタグ内かつ引用符外のものは半角スペースに変換       #
#   ・一重引用符と二重引用符(値としてのものを除く)はここで除去                 #
awk '                                                                          #
  BEGIN {                                                                      #
    OFS = "";                                                                  #
    ORS = "";                                                                  #
    LF  = sprintf("\n");                                                       #
    Sct = "'"$SCT"'"; # タグ開始端候補識別子として使う文字........残す         #
    Ect = "'"$ECT"'"; # タグ終了端候補識別子として使う文字........残す         #
    Scs = "'"$SCS"'"; # 一重引用符開始端候補識別子として使う文字..消す         #
    Ecs = "'"$ECS"'"; # 一重引用符終了端候補識別子として使う文字..消す         #
    Scd = "'"$SCD"'"; # 二重引用符開始端候補識別子として使う文字..消す         #
    Ecd = "'"$ECD"'"; # 二重引用符終了端候補識別子として使う文字..消す         #
    SPC = "'"$SPC"'"; # スペースをエスケープするための文字........これに置換   #
    TAB = "'"$TAB"'"; # タブをエスケープするための文字............これに置換   #
    SLS = "'"$SLS"'"; # /をエスケープするための文字...............これに置換   #
    GT  = "'"$GT"'";  # >をエスケープするための文字(引用符内用)...これに置換   #
    LT  = "'"$LT"'";  # <をエスケープするための文字(引用符内用)...これに置換   #
    in_tag  =  0; # 今読み進めた最後の文字位置はタグ内か                       #
    in_quot =  0; # 今読み進めた最後の文字位置は括弧内か(SQなら1,DQなら2)      #
    while (getline line) {                                                     #
      headofline = substr(line,1,1);                                           #
      if (in_tag == 0) {                                                       #
        # 1.タグ外だった場合                                                   #
        if (       headofline == Sct) {                                        #
          # 1-1.タグ開始端に来た場合                                           #
          in_tag = 1;                                                          #
          gsub(/'"$LF"'/, " ", line);                                          #
          print LF, line;                                                      #
        } else {                                                               #
          # 1-2.タグに来てない場合                                             #
          print substr(line,2);                                                #
        }                                                                      #
      } else if (in_quot == 0) {                                               #
        # 2.タグ内だけど引用符外だった場合                                     #
        if (       headofline == Ect) {                                        #
          # 2-1.タグ終端に来た場合                                             #
          in_tag = 0;                                                          #
          print line, LF;                                                      #
        } else if (headofline == Scs) {                                        #
          # 2-2.一重引用符開始端に来た場合                                     #
          in_quot = 1;                                                         #
          gsub(/ / ,SPC, line);                                                #
          gsub(/\t/,TAB, line);                                                #
          gsub(/\//,SLS, line);                                                #
          gsub(/>/ , GT, line);                                                #
          gsub(/</ , LT, line);                                                #
          print substr(line,3);                                                #
        } else if (headofline == Scd) {                                        #
          # 2-3.二重引用符開始端に来た場合                                     #
          in_quot = 2;                                                         #
          gsub(/ / ,SPC, line);                                                #
          gsub(/\t/,TAB, line);                                                #
          gsub(/\//,SLS, line);                                                #
          gsub(/>/ , GT, line);                                                #
          gsub(/</ , LT, line);                                                #
          print substr(line,3);                                                #
        } else {                                                               #
          # 2-4.その他(タグ内で属性括弧外のまま)の場合                         #
          gsub(/'"$LF"'/, " ", line);                                          #
          print substr(line,2);                                                #
        }                                                                      #
      } else if (in_quot == 1) {                                               #
        # 3.一重引用符内だった場合                                             #
        if (       headofline == Ecs) {                                        #
          # 3-1.一重引用符終端に来た場合                                       #
          in_quot = 0;                                                         #
          gsub(/'"$LF"'/, " ", line);                                          #
          print substr(line,3);                                                #
        } else {                                                               #
          # 3-2.その他(タグ開始端や上記を除く引用符端....ここでは来ないはず)   #
          gsub(/ / ,SPC, line);                                                #
          gsub(/\t/,TAB, line);                                                #
          gsub(/\//,SLS, line);                                                #
          gsub(/>/ , GT, line);                                                #
          gsub(/</ , LT, line);                                                #
          print line;                                                          #
        }                                                                      #
      } else {                                                                 #
        # 4.二重引用符内だった場合                                             #
        if (       headofline == Ecd) {                                        #
          # 4-1.二重引用符終端に来た場合                                       #
          in_quot = 0;                                                         #
          gsub(/'"$LF"'/, " ", line);                                          #
          print substr(line,3);                                                #
        } else {                                                               #
          # 4-2.その他(タグ開始端や上記を除く引用符端....ここでは来ないはず)   #
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
# === コメント(<!-- -->)を削除する =========================================== #
tr -d '\n'                                                                     |
sed 's/<!--/'"$N"'<!--'"$N"'/g'                                                |
sed 's/-->/-->'"$N"'/g'                                                        |
sed '/^<!--/,/-->$/d'                                                          |
tr -d '\n'                                                                     |
#                                                                              #
# === タグ名行、属性行、タグ内文字列行の3種類に行を分離する ================== #
# 1)タグ文字列部分を単独の行にする(同時に"<",">"はトル)                        #
sed 's/'"$SCT"'<\([^'"$ECT"']*\)'"$ECT"'>/'"$N$SCT"'\1'"$N"'/g'                |
# 2)タグの名称部分と各属性部分を1つ1つ個別の行にする                           #
#   ・先頭にタグ行or属性行識別子をつけて                                       #
#   ・属性行を先にし、タグ行は最後にする                                       #
awk '                                                                          #
  # the alternative length function for array variable                         #
  function arlen(ar,i,l){for(i in ar){l++;}return l;}                          #
                                                                               #
  BEGIN {                                                                      #
    OFS = "";                                                                  #
    Tag = "'"$SCT"'"; # タグ行識別子として使う文字..残す                       #
    Pro = "'"$PRO"'"; # 属性行識別子として使う文字..追加する                   #
    while (getline line) {                                                     #
      headofline = substr(line,1,1);                                           #
      if (headofline == Tag) {                                                 #
        # 1.タグ行である場合....                                               #
        split(line, items);                                                    #
        tagname = substr(items[1],2);                                          #
        sub(/\/$/, "", tagname);                                               #
        # 1-1.単独タグかどうかを検出                                           #
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
        # 1-2.各属性を各々単独の行として出力                                   #
        for (j=2; j<=i; j++) {                                                 #
          item = items[j];                                                     #
          if (match(item, /^[^=]+/)) {                                         #
            proname = substr(item,1,RLENGTH);                                  #
            if (match(item, /^[^=]+["'"'"'].+["'"'"']$/)) {                    #
              k = length(proname);                                             #
              proval = substr(item,k+3,length(item)-k-3);                      #
              print Pro, tagname, Pro, proname, " ", proval;                   #
            } else if (length(proname) == length(item)) {                      #
              print Pro, tagname, Pro, proname, " ";                           #
            } else {                                                           #
              proval = substr(item,length(proname)+2);                         #
              print Pro, tagname, Pro, proname, " ", proval;                   #
            }                                                                  #
          }                                                                    #
        }                                                                      #
        # 1-3.タグ名を単独の行として出力                                       #
        print Tag,      tagname;                                               #
        # 1-4.単独タグだった場合は閉じタグ行を追加                             #
        if (singletag) {                                                       #
          print Tag, "//", tagname;  # (後で区別できるように"//"とする)        #
        }                                                                      #
      } else {                                                                 #
        # 2.タグ行ではない場合....、そのまま出力                               #
        print line;                                                            #
      }                                                                        #
    }                                                                          #
  }                                                                            #
'                                                                              |
# === タグ,属性を絶対パス化し、タグ内文字列をタグの値として同行に記す ======== #
# ・次のような形式になる(第1列はXPath形式)                                     #
#    /PATH/TO/TAG_NAME VALUE                                                   #
#    /PATH/TO/TAG_NNAME/@PROPERTY_NAME VALUE                                   #
# ・VALUEが空の場合でも手前に半角スペースが1個入る                             #
awk '                                                                          #
  BEGIN {                                                                      #
    OFS = "";                                                                  #
    ORS = "";                                                                  #
    LF  = sprintf("\n");                                                       #
    Tag = "'"$SCT"'"; # タグ行識別子として使う文字..消す                       #
    Pro = "'"$PRO"'"; # 属性行識別子として使う文字..消す                       #
    split("", tagpath); # K:階層番号、V:パス名                                 #
    split("", tagvals); # (a)K:階層深度 V:要素数、(b)K:深度,番号 V:文字列      #
    split("", tagbros); # K:階層番号、V:"/所属タグの名前/名前/名前/…"         #
    split("", tagrept); # K:"階層番号/タグ名"、V:出現回数                      #
    currentdepth     =  0; # 現在いる階層の深度                                #
    currentpathitems =  0; # 現在のフルパスが持っている文字列の個数            #
    while (getline line) {                                                     #
      headofline = substr(line,1,1);                                           #
      if (       headofline == Tag) {                                          #
        # 1.タグ行だった場合                                                   #
        if (substr(line,2,1) == "/") {                                         #
          # 1-1.タグ終了行だった場合                                           #
          #     現在の階層の値を付けながら値を表示                             #
          #     一階層出る                                                     #
          for (i=1; i<=currentdepth; i++) {                                    #
            s =  tagpath[i];                                                   #
            print "/", s;                                                      #
            '"$unoptn"'print "[", tagrept[i "/" s], "]";                       #
          }                                                                    #
          if (substr(line,3,1) != "/") {print " ";} #←単独タグだった場合は、  #
          for (i=1; i<=currentpathitems; i++) {     #  タグパスの後ろに        #
            print  tagvals[currentdepth "," i];     #  " "をつけない。         #
            delete tagvals[currentdepth "," i];                                #
          }                                                                    #
          print LF;                                                            #
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
          # 1-2.タグ開始行だった場合                                           #
          #     一階層入る                                                     #
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
        # 2.属性行だった場合                                                   #
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
        print "/@", substr(s,i+1), LF;                                         #
      } else {                                                                 #
        # 3.その他の行だった場合                                               #
        #   現在の階層の値変数にその行を追加                                   #
        currentpathitems++;                                                    #
        tagvals[currentdepth "," currentpathitems] = line;                     #
      }                                                                        #
    }                                                                          #
  }                                                                            #
'                                                                              |
#                                                                              #
# === アンエスケープ ========================================================= #
# 1)スペース,タブ,"<",">","/"を元に戻す                                        #
sed 's/'"$GT"'/>/g'                                                            |
sed 's/'"$LT"'/</g'                                                            |
sed 's/'"$SLS"'/\//g'                                                          |
sed 's/'"$SPC"'/ /g'                                                           |
sed 's/'"$TAB"'/'"$T"'/g'                                                      |
# 2)エスケープ改行を、引数で指定された(あるいはデフォルトの)文字列に変換する   #
if [ "_$bsesc" != '_\\' ]; then                                                #
  sed 's/\\/'"$bsesc"'/g'                                                      #
else                                                                           #
  cat                                                                          #
fi                                                                             |
sed 's/'"$LF"'/'"$optlf"'/g'