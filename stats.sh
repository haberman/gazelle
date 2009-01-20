#!/bin/sh

COMPILER_LINES=`find compiler | grep lua$ | xargs cat | wc -l`
RUNTIME_LINES=`find runtime | grep '\.[hc]$' | xargs cat | wc -l`
CORE_LINES=`perl -e "print $COMPILER_LINES+$RUNTIME_LINES;"`
echo compiler_lines=$COMPILER_LINES
echo runtime_lines=$RUNTIME_LINES
echo core_lines=$CORE_LINES
echo tests_lines=`find tests | grep 'test_.*\.lua$' | xargs cat | wc -l`
echo docs_lines=`cat docs/manual.txt | wc -l`

if [ "$1" = "all" ] ; then

  make clean > /dev/null
  make CFLAGS="-O6 -fomit-frame-pointer -DNDEBUG -std=c99" > /dev/null
  . ./lua_path
  ./compiler/gzlc sketches/json.gzl
  echo json_gzc_size=`cat sketches/json.gzc | wc -c`
  strip runtime/libgazelle.a
  echo runtime_lib_size_stripped=`cat runtime/libgazelle.a | wc -c`

  rm -rf /tmp/gazelle-size-test*
  mkdir -p /tmp/gazelle-size-test
  git checkout-index --prefix=/tmp/gazelle-size-test/ -a
  $(cd /tmp && tar zcf gazelle-size-test.tar.gz gazelle-size-test)
  echo tar_gz_size=`cat /tmp/gazelle-size-test.tar.gz | wc -c`

  LINE='"glossary":{"title":"example glossary","GlossDiv":{"title":"S","GlossList":{"GlossEntry":{"ID":"SGML","SortAs":"SGML","GlossTerm":"Standard Generalized Markup Language","Acronym":"SGML","Abbrev":"ISO 8879:1986","GlossDef":{"para":"A meta-markup language, used to create markup languages such as DocBook.","GlossSeeAlso":["GML","XML"]},"GlossSee":"markup"}}}},'
  echo $LINE > /tmp/jsonfile
  # TODO: let the file keep its newline once the parser can handle whitespace again
  perl -e 'chop($str = <STDIN>); print "{" . $str x 100000 . "\"foo\":1}"' < /tmp/jsonfile > /tmp/jsonfile2
  echo time_35MB_json=`/usr/bin/time -f "%U" ./utilities/gzlparse sketches/json.gzc /tmp/jsonfile2 2>&1`
fi
