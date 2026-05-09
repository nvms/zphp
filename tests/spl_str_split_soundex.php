<?php
// SplStack LIFO
$s = new SplStack();
$s->push('a'); $s->push('b'); $s->push('c');
echo count($s), "\n";
echo $s->pop(), "\n";
echo $s->pop(), "\n";
echo count($s), "\n";

// SplQueue FIFO
$q = new SplQueue();
$q->enqueue(1); $q->enqueue(2); $q->enqueue(3);
echo count($q), "\n";
echo $q->dequeue(), "\n";
echo $q->dequeue(), "\n";

// SplDoublyLinkedList
$dl = new SplDoublyLinkedList();
$dl->push(1); $dl->push(2); $dl->push(3);
echo $dl->top(), "\n";
echo $dl->bottom(), "\n";
echo count($dl), "\n";

// count_chars
$c = count_chars("hello world", 0);
echo $c[ord('l')], "\n";
echo $c[ord(' ')], "\n";
echo $c[ord('z')], "\n";
echo count_chars("hello world", 3), "\n"; // unique chars

// str_split positive
print_r(str_split("abcd", 2));

// negative throws ValueError
try {
    str_split("hello", -1);
} catch (\ValueError $e) {
    echo "neg ok\n";
}

// zero throws
try {
    str_split("hello", 0);
} catch (\ValueError $e) {
    echo "zero ok\n";
}

// soundex
echo soundex("Robert"), "\n";
echo soundex("Rupert"), "\n";
echo soundex(""), "\n"; // "0000"
echo soundex("a"), "\n";
