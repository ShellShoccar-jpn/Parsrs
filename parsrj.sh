#! /bin/sh
#
# parsrj.sh
#    JSONテキストから
#    階層インデックス付き値(tree indexed value)テキスへの正規化
#    (例)
#     {"hoge":111,
#      "foo" :["2\n2",
#              {"bar" :"3 3",
#               "fizz":{"bazz":444}
#              },
#              "\u5555"
#             ]
#     }
#     ↓
#     $.hoge 111
#     $.foo[0] 2\n2
#     $.foo[1].bar 3 3
#     $.foo[1].fizz.bazz 444
#     $.foo[2] \u5555
#     ◇よって grep '^\$foo[1].bar ' | sed 's/^[^ ]* //' などと
#       後ろ grep, sed をパイプで繋げれば目的のキーの値部分が取れる。
#       さらにこれを unescj.sh にパイプすれば、完全な値として取り出せる。
#
# Usage   : parsrj.sh [JSON_file]           ←JSONPath表現
#         : parsrj.sh --xpath [JSON_file]   ←XPath表現     ↓カスタム表現
# Usage   : parsrj.sh [-rt<s>] [-kd<s>] [-lp<s>] [-ls<s>] [-fn<n>] [JSON_file]
# Options : -rt はルート階層シンボル文字列指定(デフォルトは"$")
#         : -kd は各階層のキー名文字列間のデリミター指定(デフォルトは".")
#         : -lp は配列キーのプレフィックス文字列指定(デフォルトは"[")
#         : -ls は配列キーのサフィックス文字列指定(デフォルトは"]")
#         : -fn は配列キー番号の開始番号(デフォルトは0)
#         : --xpathは階層表現をXPath形式にする(-rt -kd/ -lp[ -ls] -fn1と等価)
# Written by Rich Mikan(richmikan[at]richlab.org) / Date : May 11, 2013


DQ=$(printf '\026')              # 値のダブルクォーテーション(DQ)エスケープ用
LF=$(printf '\\\n_');LF=${LF%_}  # sed内で改行を変数として扱うためのもの

file=''
rt='$'
kd='.'
lp='['
ls=']'
fn=0
for arg in "$@"; do
  if [ \( "_${arg#-rt}" != "_$arg" \) -a \( -z "$file" \) ]; then
    rt=${arg#-rt}
  elif [ \( "_${arg#-kd}" != "_$arg" \) -a \( -z "$file" \) ]; then
    kd=${arg#-kd}
  elif [ \( "_${arg#-lp}" != "_$arg" \) -a \( -z "$file" \) ]; then
    lp=${arg#-lp}
  elif [ \( "_${arg#-ls}" != "_$arg" \) -a \( -z "$file" \) ]; then
    ls=${arg#-ls}
  elif [ \( "_${arg#-fn}" != "_$arg" \) -a \( -z "$file" \) -a \
         -n "$(echo -n "_${arg#-fn}" | grep '^_[0-9]\+$')"     ]; then
    fn=${arg#-fn}
    fn=$((fn+0))
  elif [ \( "_$arg" = '_--xpath' \) -a \( -z "$file" \) ]; then
    rt=''
    kd='/'
    lp='['
    ls=']'
    fn=1
  elif [ \( \( -f "$arg" \) -o \( -c "$arg" \) \) -a \( -z "$file" \) ]; then
    file=$arg
  elif [ \( "_$arg" = "_-" \) -a \( -z "$file" \) ]; then
    file='-'
  else
    cat <<____USAGE 1>&2
Usage   : ${0##*/} [JSON_file]           ←JSONPath表現
        : ${0##*/} --xpath [JSON_file]   ←XPath表現     ↓カスタム表現
        : ${0##*/} [-rt<s>] [-kd<s>] [-lp<s>] [-ls<s>] [-fn<n>] [JSON_file]
Options : -rt はルート階層シンボル文字列指定(デフォルトは"$")
        : -kd は各階層のキー名文字列間のデリミター指定(デフォルトは".")
        : -lp は配列キーのプレフィックス文字列指定(デフォルトは"[")
        : -ls は配列キーのサフィックス文字列指定(デフォルトは"]")
        : -fn は配列キー番号の開始番号(デフォルトは0)
        : --xpathは階層表現をXPath形式にする(-rt -kd/ -lp[ -ls] -fn1と等価)
____USAGE
    exit 1
  fi
done
rt=$(echo -n "_$rt"                |
     od -A n -t o1                 |
     tr -d '\n'                    |
     sed 's/^[[:blank:]]*137//'    |
     sed 's/[[:blank:]]*$//'       |
     sed 's/[[:blank:]]\{1,\}/\\/g')
kd=$(echo -n "_$kd"                |
     od -A n -t o1                 |
     tr -d '\n'                    |
     sed 's/^[[:blank:]]*137//'    |
     sed 's/[[:blank:]]*$//'       |
     sed 's/[[:blank:]]\{1,\}/\\/g')
lp=$(echo -n "_$lp"                |
     od -A n -t o1                 |
     tr -d '\n'                    |
     sed 's/^[[:blank:]]*137//'    |
     sed 's/[[:blank:]]*$//'       |
     sed 's/[[:blank:]]\{1,\}/\\/g')
ls=$(echo -n "_$ls"                |
     od -A n -t o1                 |
     tr -d '\n'                    |
     sed 's/^[[:blank:]]*137//'    |
     sed 's/[[:blank:]]*$//'       |
     sed 's/[[:blank:]]\{1,\}/\\/g')
[ -z "$file" ] && file='-'


# === データの流し込み ============================================= #
cat "$file"                                                          |
#                                                                    #
# === 値としてのダブルクォーテーション(DQ)をエスケープ ============= #
sed "s/\\\\\"/$DQ/g"                                                 |
#                                                                    #
# === DQ始まり～DQ終わりの最小マッチングの前後に改行を入れる ======= #
sed "s/\(\"[^\"]*\"\)/$LF\1$LF/g"                                    |
#                                                                    #
# === DQ始まり以外の行の"{","}","[","]",":",","の前後に改行を挿入 == #
sed "/^[^\"]/s/\([][{}:,]\)/$LF\1$LF/g"                              |
#                                                                    #
# === 無駄な空行は予め取り除いておく =============================== #
grep -v '^[[:blank:]]*$'                                             |
#                                                                    #
# === 行頭の記号を見ながら状態遷移させて処理(*1,strict版*2) ======== #
# (*1 エスケープしたDQもここで元に戻す)                              #
# (*2 JSONの厳密なチェックを省略するならもっと簡素で高速にできる)    #
awk '                                                                \
BEGIN {                                                              \
  # 階層表現文字列をシェル変数に基づいて定義する                     \
  root_symbol=sprintf("'"$rt"'");                                    \
  key_delimit=sprintf("'"$kd"'");                                    \
  list_prefix=sprintf("'"$lp"'");                                    \
  list_suffix=sprintf("'"$ls"'");                                    \
  # データ種別スタックの初期化                                       \
  datacat_stack[0]="";                                               \
  delete datacat_stack[0]                                            \
  # キー名スタックの初期化                                           \
  keyname_stack[0]="";                                               \
  delete keyname_stack[0]                                            \
  # スタックの深さを0に設定                                          \
  stack_depth=0;                                                     \
  # エラー終了検出変数を初期化                                       \
  _assert_exit=0;                                                    \
  # 同期信号キャラクタ(事前にエスケープしていたDQを元に戻すため)     \
  DQ=sprintf("\026");                                                \
  # 改行キャラクター                                                 \
  LF =sprintf("\n");                                                 \
  # print文の自動フィールドセパレーター挿入と文末自動改行をなくす    \
  OFS="";                                                            \
  ORS="";                                                            \
}                                                                    \
# "{"行の場合                                                        \
$0~/^{$/{                                                            \
  # データ種別スタックが空、又は最上位が"l0:配列(初期要素値待ち)"、  \
  # "l1:配列(値待ち)"、"h2:ハッシュ(値待ち)"であることを確認したら   \
  # データ種別スタックに"h0:ハッシュ(キー未取得)"をpush              \
  if ((stack_depth==0)                   ||                          \
      (datacat_stack[stack_depth]=="l0") ||                          \
      (datacat_stack[stack_depth]=="l1") ||                          \
      (datacat_stack[stack_depth]=="h2")  ) {                        \
    stack_depth++;                                                   \
    datacat_stack[stack_depth]="h0";                                 \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# "}"行の場合                                                        \
$0~/^}$/{                                                            \
  # データ種別スタックが空でなく最上位が"h0:ハッシュ(キー未取得)"、  \
  # "h3:ハッシュ(値取得済)"であることを確認したら                    \
  # データ種別スタック、キー名スタック双方をpop                      \
  # もしpop直後の最上位が"l0:配列(初期要素値待ち)"または             \
  # "l1:配列(値待ち)"だった場合には"l2:配列(値取得直後)"に変更       \
  # 同様に"h2:ハッシュ(値待ち)"だった時は"h3:ハッシュ(値取得済)"に   \
  if ((stack_depth>0)                       &&                       \
      ((datacat_stack[stack_depth]=="h0") ||                         \
       (datacat_stack[stack_depth]=="h3")  ) ) {                     \
    delete datacat_stack[stack_depth];                               \
    delete keyname_stack[stack_depth];                               \
    stack_depth--;                                                   \
    if (stack_depth>0) {                                             \
      if ((datacat_stack[stack_depth]=="l0") ||                      \
          (datacat_stack[stack_depth]=="l1")  ) {                    \
        datacat_stack[stack_depth]="l2"                              \
      } else if (datacat_stack[stack_depth]=="h2") {                 \
        datacat_stack[stack_depth]="h3"                              \
      }                                                              \
    }                                                                \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# "["行の場合                                                        \
$0~/^\[$/{                                                           \
  # データ種別スタックが空、又は最上位が"l0:配列(初期要素値待ち)"、  \
  # "l1:配列(値待ち)"、"h2:ハッシュ(値待ち)"であることを確認したら   \
  # データ種別スタックに"l0:配列(初期要素値待ち)"をpush、            \
  # およびキー名スタックに配列番号0をpush                            \
  if ((stack_depth==0)                   ||                          \
      (datacat_stack[stack_depth]=="l0") ||                          \
      (datacat_stack[stack_depth]=="l1") ||                          \
      (datacat_stack[stack_depth]=="h2")  ) {                        \
    stack_depth++;                                                   \
    datacat_stack[stack_depth]="l0";                                 \
    keyname_stack[stack_depth]='"$fn"';                              \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# "]"行の場合                                                        \
$0~/^\]$/{                                                           \
  # データ種別スタックが空でなく最上位が"l0:配列(初期要素値待ち)"、  \
  # "l2:配列(値取得直後)"であることを確認したら                      \
  # データ種別スタック、キー名スタック双方をpop                      \
  # もしpop直後の最上位が"l0:配列(初期要素値待ち)"または             \
  # "l1:配列(値待ち)"だった場合には"l2:配列(値取得直後)"に変更       \
  # 同様に"h2:ハッシュ(値待ち)"だった時は"h3:ハッシュ(値取得済)"に   \
  if ((stack_depth>0)                       &&                       \
      ((datacat_stack[stack_depth]=="l0") ||                         \
       (datacat_stack[stack_depth]=="l2")  ) ) {                     \
    delete datacat_stack[stack_depth];                               \
    delete keyname_stack[stack_depth];                               \
    stack_depth--;                                                   \
    if (stack_depth>0) {                                             \
      if ((datacat_stack[stack_depth]=="l0") ||                      \
          (datacat_stack[stack_depth]=="l1")  ) {                    \
        datacat_stack[stack_depth]="l2"                              \
      } else if (datacat_stack[stack_depth]=="h2") {                 \
        datacat_stack[stack_depth]="h3"                              \
      }                                                              \
    }                                                                \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# ":"行の場合                                                        \
$0~/^:$/{                                                            \
  # データ種別スタックが空でなく                                     \
  # 最上位が"h1:ハッシュ(キー取得済)"であることを確認したら          \
  # データ種別スタック最上位を"h2:ハッシュ(値待ち)"に変更            \
  if ((stack_depth>0)                   &&                           \
      (datacat_stack[stack_depth]=="h1") ) {                         \
    datacat_stack[stack_depth]="h2";                                 \
    next;                                                            \
  } else {                                                           \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# ","行の場合                                                        \
$0~/^,$/{                                                            \
  # 1)データ種別スタックが空でないことを確認                         \
  if (stack_depth==0) {                                              \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
  # 2)データ種別スタック最上位値によって分岐                         \
  # 2a)"l2:配列(値取得直後)"の場合                                   \
  if (datacat_stack[stack_depth]=="l2") {                            \
    # 2a-1)データ種別スタック最上位を"l1:配列(値待ち)"に変更         \
    datacat_stack[stack_depth]="l1";                                 \
    # 2a-2)キー名スタックに入っている配列番号を+1                    \
    keyname_stack[stack_depth]++;                                    \
    next;                                                            \
  # 2b)"h3:ハッシュ(値取得済)"の場合                                 \
  } else if (datacat_stack[stack_depth]=="h3") {                     \
    # 2b-1)データ種別スタック最上位を"h0:ハッシュ(キー未取得)"に変更 \
    datacat_stack[stack_depth]="h0";                                 \
    next;                                                            \
  # 2c)その他の場合                                                  \
  } else {                                                           \
    # 2c-1)エラー                                                    \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# それ以外の行(値の入っている行)の場合                               \
{                                                                    \
  # 1)データ種別スタックが空でないことを確認                         \
  if (stack_depth==0) {                                              \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
  # 2)DQ囲みになっている場合は予めそれを除去しておく                 \
  value=(match($0,/^".*"$/))?substr($0,2,RLENGTH-2):$0;              \
  # 3)事前にエスケープしていたDQをここで元に戻す                     \
  gsub(DQ,"\\\"",value);                                             \
  # 4)データ種別スタック最上位値によって分岐                         \
  # 4a)"l0:配列(初期要素値待ち)"又は"l1:配列(値待ち)"の場合          \
  if ((datacat_stack[stack_depth]=="l0") ||                          \
        (datacat_stack[stack_depth]=="l1")  ) {                      \
    # 4a-1)キー名スタックと値を表示                                  \
    print_keys_and_value(value);                                     \
    # 4a-2)データ種別スタック最上位を"l2:配列(値取得直後)"に変更     \
    datacat_stack[stack_depth]="l2";                                 \
  # 4b)"h0:ハッシュ(キー未取得)"の場合                               \
  } else if (datacat_stack[stack_depth]=="h0") {                     \
    # 4b-1)値をキー名としてキー名スタックにpush                      \
    keyname_stack[stack_depth]=value;                                \
    # 4b-2)データ種別スタック最上位を"h1:ハッシュ(キー取得済)"に変更 \
    datacat_stack[stack_depth]="h1";                                 \
  # 4c)"h2:ハッシュ(値待ち)"の場合                                   \
  } else if (datacat_stack[stack_depth]=="h2") {                     \
    # 4c-1)キー名スタックと値を表示                                  \
    print_keys_and_value(value);                                     \
    # 4a-2)データ種別スタック最上位を"h3:ハッシュ(値取得済)"に変更   \
    datacat_stack[stack_depth]="h3";                                 \
  # 4d)その他の場合                                                  \
  } else {                                                           \
    # 4d-1)エラー                                                    \
    _assert_exit=1;                                                  \
    exit _assert_exit;                                               \
  }                                                                  \
}                                                                    \
# 最終処理                                                           \
END {                                                                \
  if (_assert_exit) {                                                \
    print "Invalid JSON format", LF > "/dev/stderr";                 \
    line1="keyname-stack:";                                          \
    line2="datacat-stack:";                                          \
    for (i=1;i<=stack_depth;i++) {                                   \
      line1=line1 sprintf("{%s}",keyname_stack[i]);                  \
      line2=line2 sprintf("{%s}",datacat_stack[i]);                  \
    }                                                                \
    print line1, LF, line2, LF > "/dev/stderr";                      \
  }                                                                  \
  exit _assert_exit;                                                 \
}                                                                    \
# キー名一覧と値を表示する関数                                       \
function print_keys_and_value(str) {                                 \
  print root_symbol;                                                 \
  for (i=1;i<=stack_depth;i++) {                                     \
    if (substr(datacat_stack[i],1,1)=="l") {                         \
      print list_prefix, keyname_stack[i], list_suffix;              \
    } else {                                                         \
      print key_delimit, keyname_stack[i];                           \
    }                                                                \
  }                                                                  \
  print " ", str, LF;                                                \
}                                                                    \
'