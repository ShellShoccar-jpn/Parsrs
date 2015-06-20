#! /bin/sh
#
# makrc.sh
#   parsrc.shの逆変換
#   ・行番号列番号インデックス付き値(line field indexed value)テキストから
#     CSV(Excel形式(RFC 4180):ダブルクォーテーションのエスケープは"")を生成する
#    (例)
#     1 1 aaa
#     1 2 b"bb
#     1 3 c\ncc
#     1 4 d d
#     2 1 f,f
#     ↓
#     aaa,"b""bb","c
#     cc",d d
#     "f,f"
#
# 書式: makrc.sh [-fs<str>] [-t] [file]
#       -fs は列区切り文字列でありデフォルトは","（CSV）
#       -lf は、行末をCR+LFにせずLFのままにする
#       -t  は、列をダブルクォーテーションで囲まず、エスケープもしない
# 注意: 行番号昇順→列番号昇順でのソート(sort -k1n,1 -k2n,2)を済ませておくこと
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

SO=$(printf '\016')              # バックスラッシュ表現のエスケープ用
SI=$(printf '\017')              # 改行コード表現のエスケープ用
LF=$(printf '\\\n_');LF=${LF%_}  # SED内で改行を変数として扱うためのもの

optfs=','
optlf=0
optt=0
file=''
printhelp=0
i=0
for arg in "$@"; do
  i=$((i+1))
  if [ \( "_${arg#-fs}" != "_$arg" \) -a \( -z "$file" \) ]; then
    optfs=$(printf '%s' "${arg#-fs}_" |
            tr -d '\n'                )
    optfs=${optfs%_}
  elif [ \( "_${arg}" = '_-lf' \) -a \( -z "$file" \) ]; then
    optlf=1
  elif [ \( "_${arg}" = '_-t' \) -a \( -z "$file" \) ]; then
    optt=1
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
	書式: ${0##*/} [-fs<str>] [-t] [file]
	      -fs は列区切り文字列でありデフォルトは","（CSV）
	      -lf は、行末をCR+LFにせずLFのままにする
	      -t  は、列をダブルクォーテーションで囲まず、エスケープもしない
	注意: 行番号昇順→列番号昇順でのソート(sort -k1n,1 -k2n,2)を済ませておくこと
__USAGE
  exit 1
fi
[ -z "$file"  ] && file='-'


# === データの流し込み =================================== #
cat "$file"                                                |
#                                                          #
# === 行番号列番号をアンダースコア"_"区切りにする ======== #
sed 's/ \{1,\}/_/'                                         |
#                                                          #
# === 値としてのバックスラッシュと改行表現をエスケープ === #
sed 's/\\\\/'"$SO"'/g'                                     |
sed 's/\\n/'"$SI"'/g'                                      |
#                                                          #
# === 必要なら値文字列をDQで囲む(同時に中のDQをエスケープ) #
case $optt in                                              #
  0) sed '/['"$SO$SI"',"]/{s/"/""/g;s/ \(.*\)$/ "\1"/;}';; #
  1) cat                                                ;; #
esac                                                       |
#                                                          #
# === 行番号列番号に応じてカンマ区切り表にする =========== #
FLDSP="$optfs" awk '                                       #
  BEGIN{                                                   #
    # --- 初期設定 ---                                     #
    fldsp=ENVIRON["FLDSP"];                                #
    OFS=""; ORS="";                                        #
    LF=sprintf("\n");                                      #
    r=1; c=1; dlm="";                                      #
                                                           #
    # --- メインループ ---                                 #
    while (getline line) {                                 #
      match(line, /_[0-9]+/);                              #
      cr =substr(line,       1,RSTART -1)*1;               #
      cc =substr(line,RSTART+1,RLENGTH-1)*1;               #
      val=substr(line,RSTART+RLENGTH+1  );                 #
      if (cr==r) {                                         #
        print_col();                                       #
      } else {                                             #
        print LF;                                          #
        r++;                                               #
        dlm="";                                            #
        c=1;                                               #
        if (cr>r) {                                        #
          for (; r<cr; r++) {print "\"\"",LF;}             #
        }                                                  #
        print_col();                                       #
      }                                                    #
    }                                                      #
                                                           #
    # --- 終端 ---                                         #
    print LF;                                              #
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
# === エスケープされていた改行と"\"を復元する ============ #
sed 's/'"$SO"'/\\/g'                                       |
sed 's/'"$SI"'/'"$LF"'/g'                                  |
#                                                          #
# === 改行コードをCR+LFにする ============================ #
case $optlf in                                             #
  0) sed "s/\$/$(printf '\r')/";;                          #
  *) cat                       ;;                          #
esac
