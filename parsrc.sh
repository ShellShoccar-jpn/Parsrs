#! /bin/sh
#
# parsrc.sh
#    CSV(Excel形式(RFC 4180):ダブルクォーテーションのエスケープは"")から
#    行番号列番号インデックス付き値(line field indexed value)テキストへの正規化
#    (例)
#     aaa,"b""bb","c
#     cc",d d
#     "f,f"
#     ↓
#     1 1 aaa
#     1 2 b"bb
#     1 3 c\ncc
#     1 4 d d
#     2 1 f,f
#     ◇よって grep '^1 3 ' | sed 's/^[^ ]* [^ ]* //' などと
#       後ろに grep&sed をパイプで繋げれば目的の行・列の値が得られる。
#       さらにこれを
#         sed 's/\\n/\<LF>/g' (←"<LF>"は実際には改行を表す)
#       にパイプすれば、元データに改行を含む場合でも完全な値として取り出せる。
#
# Usage: parsrc.sh [-lf<str>] [CSV_file]
# Options : -lf は値として含まれている改行を表現する文字列指定(デフォルトは
#               "\n"であり、この場合は元々の \ が \\ にエスケープされる)
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

SO=$(printf '\016')              # ダブルクォーテーション*2のエスケープ印
SI=$(printf '\017')              # 値としての改行文字列エスケープ印
RS=$(printf '\036')              # 1列1行化後に元々の改行を示すための印
US=$(printf '\037')              # 1列1行化後に元々の列区切りを示すための印
LF=$(printf '\\\n_');LF=${LF%_}  # SED内で改行を変数として扱うためのもの
HT=$(printf '\011')              # タブ

optlf=''
bsesc='\\'
file=''
printhelp=0
i=0
for arg in "$@"; do
  i=$((i+1))
  if [ \( "_${arg#-lf}" != "_$arg" \) -a \( -z "$file" \) ]; then
    optlf=$(printf '%s' "${arg#-lf}_" |
            tr -d '\n'                |
            sed 's/\([\&/]\)/\\\1/g'  )
    optlf=${optlf%_}
  elif [ \( $i -eq $# \) -a \( "_$arg" = '_-' \) -a \( -z "$file" \) ]; then
    file='-'
  elif [ \( $i -eq $# \) -a \( \( -f "$arg" \) -o \( -c "$arg" \) \) \
         -a \( -z "$file" \) ]
  then
    file=$arg
  else
    printhelp=1;
  fi
done
if [ $printhelp -ne 0 ]; then
  cat <<-__USAGE
	Usage : ${0##*/} [-lf<str>] [CSV_file] 1>&2
	Options : -lf は値として含まれている改行を表現する文字列指定(デフォルトは
	              "\n"であり、この場合は元々の \ が \\ にエスケープされる)
__USAGE
  exit 1
fi
[ -z "$optlf" ] && { optlf='\\n'; bsesc='\\\\'; }
[ -z "$file"  ] && file='-'

# === データの流し込み ============================================= #
cat "$file"                                                          |
#                                                                    #
# === 行末のCRを取り除く =========================================== #
sed "s/$(printf '\r')\$//"                                           |
#                                                                    #
# === 値としてのダブルクォーテーションをエスケープ ================= #
#     (但しnull囲みの""も区別が付かず、エスケープされる)             #
sed 's/""/'$SO'/g'                                                   |
#                                                                    #
# === 値としての改行を\nに変換 ===================================== #
#     (ダブルクォーテーションが奇数個ならSI付けて次の行と結合する)   #
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
# === 各列を1行化するにあたり、元々の改行には予め印をつけておく ==== #
#     (元々の改行の後にRS行を挿入する)                               #
sed "s/\$/$LF$RS/"                                                   |
#                                                                    #
# === ダブルクォーテーション囲み列の1列1行化 ======================= #
#     (その前後にスペースもあれば余計なのでここで取り除いておく)     #
# (1/3)先頭からNF-1までのダブルクォーテーション囲み列の1列1行化      #
sed 's/['"$HT"' ]*\("[^"]*"\)['"$HT"' ]*,/\1'"$LF$US$LF"'/g'         |
# (2/3)最後列(NF)のダブルクォーテーション囲み列の1列1行化            #
sed 's/,['"$HT"' ]*\("[^"]*"\)['"$HT"' ]*$/'"$LF$US$LF"'\1/g'        |
# (3/3)ダブルクォーテーション囲み列が単独行だったらスペース除去だけ  #
sed 's/^['"$HT"' ]*\("[^"]*"\)['"$HT"' ]*$/\1/g'                     |
#                                                                    #
# === ダブルクォーテーション囲みでない列の1列1行化 ================= #
#     (単純にカンマを改行にすればよい)                               #
#     (ただしダブルクォーテーション囲みの行は反応しないようにする)   #
sed '/['$RS'"]/!s/,/'"$LF$US$LF"'/g'                                 |
#                                                                    #
# === ダブルクォーテーション囲みを外す ============================= #
#     (単純にダブルクォーテーションを除去すればよい)                 #
#     (値としてのダブルクォーテーションはエスケープ中なので問題無し) #
tr -d '"'                                                            |
#                                                                    #
# === エスケープしてた値としてのダブルクォーテーションを戻す ======= #
#     (ただし、区別できなかったnull囲みの""も戻ってくるので適宜処理) #
# (1/3)まずは""に戻す                                                #
sed 's/'$SO'/""/g'                                                   |
# (2/3)null囲みの""だった場合はそれを空行に変換する                  #
sed 's/^['"$HT"' ]*""['"$HT"' ]*$//'                                 |
# (3/3)""(二重)を一重に戻す                                          #
sed 's/""/"/g'                                                       |
#                                                                    #
# === 先頭に行番号と列番号をつける ================================= #
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
# === 値としての改行のエスケープ(SI)を代替文字列に変換 ============= #
if [ "_$bsesc" != '_\\' ]; then                                      #
  sed 's/\\/'"$bsesc"'/g'                                            #
else                                                                 #
  cat                                                                #
fi                                                                   |
sed 's/'"$SI"'/'"$optlf"'/g'