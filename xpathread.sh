#! /bin/sh
#
# xpathread.sh
#    XPath形式インデックス付きデータをタグ形式に変換する
#    (例)
#    /foo/bar/onamae かえる
#    /foo/bar/nenrei 3
#    /foo/bar 
#    /foo/bar/onamae ひよこ
#    /foo/bar/nenrei 1
#    /foo/bar 
#    /foo 
#    ↓
#    ★ xpath2tag.sh /foo/bar <上記データファイル> として実行すると...
#    ↓
#    onamae nenrei
#    かえる 3
#    ひよこ 1
#    (備考)
#    ・XMLデータは一旦parsrx.shに掛けることでXPath形式インデックス付きデータに
#      になる
#    ・JSONデータは一旦parsrj.shに--xpathオプション付きで掛けることでXPath形式
#      インデックス付きデータになる
#    ・処理対象データにおいて、対象となる階層名に、添字[n]が付いていてもよい。
#      (上記の例では、最初の3行が /foo/bar[1]...、後の3行が/foo/bar[2]...、と
#      なっていてもよい。)
#
# Usage   : xpathread.sh [-s<str>] [-n<str>] [-p] <XPath> [XPath_indexed_data]
# Options : -s is for setting the substitution of blank (default:"_")
#         : -n is for setting the substitution of null (default:"@")
#         : -p permits to add the properties of the tag to the table
#
# Written by Rich Mikan(richmikan[at]richlab.org) / Date : Jun 21, 2015
#
# This is a public-domain software. It measns that all of the people
# can use this with no restrictions at all. By the way, I am fed up
# the side effects which are broght about by the major licenses.


set -u
PATH='/usr/bin:/bin'
IFS=$(printf ' \t\n_'); IFS=${IFS%_}
export IFS LANG=C LC_ALL=C PATH

# ===== 配列にlength()が使えない旧来のAWKであれば独自の関数を用いる ==
if awk 'BEGIN{a[1]=1;b=length(a)}' 2>/dev/null; then
  arlen='length'
else
  arlen='arlen'
fi

# ===== 引数を解析する ===============================================
opts='_'
optn='@'
optp=''
xpath=''
xpath_file=''
optmode=''
i=0
printhelp=0
for arg in "$@"; do
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
          if [ \( ! -f "$xpath_file"       \) -a \
               \( ! -c "$xpath_file"       \) -a \
               \( ! "_$xpath_file" != '_-' \)    ]
          then
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
[ -n "$xpath"  ] || printhelp=1
if [ $printhelp -ne 0 ]; then
  cat <<-__USAGE 1>&2
	Usage   : ${0##*/} [-s<str>] [-n<str>] [-p] <XPath> [XPath_indexed_data]
	Options : -s is for setting the substitution of blank (default:"_")
	        : -n is for setting the substitution of null (default:"@")
	        : -p permits to add the properties of the tag to the table
__USAGE
  exit 1
fi
[ -z "$xpath_file" ] && xpath_file='-'

# ===== テンポラリーファイルを確保する ===============================
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
  echo "${0##*/}: Can't create a temporary file" 1>&2
  exit 1
fi

# ===== 下記の前処理を施したテキストをテンポラリーファイルに書き出す =
# ・指定されたパス自身とその子でない(=孫以降)の行は削除
# ・指定されたパス自身の行は"/"として出力
# ・第1列は子の名前のみとし、更に添字[n]があれば取り除く
# ・第2列の空白を全て所定の文字に置き換える
awk '
  BEGIN {
    xpath    = "'"$xpath"'";
    xpathlen = length(xpath);
    if (substr(xpath,xpathlen) == "/") {
      sub(/\/$/, "", xpath);
      xpathlen--;
    }
    while (getline line) {
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

# ===== 対象タグ名の一覧をスペース区切りで列挙する ===================
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

# ===== タグ表を生成する =============================================
awk -v tags="$tags" '
  # the alternative length function for array variable
  function arlen(ar,i,l){for(i in ar){l++;}return l;}

  BEGIN {
    # タグ名と出現順序を登録
    split(tags, order2tag);
    split(""  , tag2order);
    numoftags = '$arlen'(order2tag);
    for (i=1; i<=numoftags; i++) {
      tag2order[order2tag[i]] = i;
    }
    # その他初期設定
    OFS = "";
    ORS = "";
    LF = sprintf("\n");
    # 最初の行(タグ行)を出力
    print tags, LF;
    # データ行を出力
    split("", fields);
    while (getline line) {
      if (line != "/") {
        # a.通常の行(タグ名+値)なら値を保持
        i = index(line, " ");
        f1 = substr(line, 1  , i-1);
        f2 = substr(line, i+1     );
        if (length(f2)) {
          fields[tag2order[f1]] = f2;
        }
      } else {
        # b."/"行(一周した印)なら一行出力し、その行の保持データをクリア
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