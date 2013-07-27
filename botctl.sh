#!/bin/sh
DB=tweets.brn
if [ $# == 0 ]; then
    sqlite3 $DB "SELECT attribute || ' = ' || text FROM info WHERE attribute NOT IN ('markov_order', 'tokenizer_class')"
elif [ $# == 2 ]; then
    [[ "$1" == "markov_order" || "$1" == "tokenizer_class" ]] && exit 1
    sqlite3 $DB "UPDATE info SET text = '$2' WHERE attribute = '$1'"
else
    echo "Usage: $0 [<KEY> <VALUE>]"
    exit 1
fi
