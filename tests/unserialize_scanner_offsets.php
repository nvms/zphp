<?php
// unserialize() reads as php's re2c scanner does: a malformed string fails
// at the offset php reports, with php's warnings along the way
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "  [$no] $msg\n";
    return true;
});

$inputs = [
    'i:5', 'i:5;x', 'i:+5;', 'i:-0;', 'i:99999999999999999999;', 'i:-9223372036854775808;', 'i:;',
    'b:2;', 'b:1', 'N', 'N;N;',
    'd:1.5;', 'd:.5;', 'd:5.;', 'd:1e5;', 'd:-1.5E-3;', 'd:NAN;', 'd:-INF;', 'd:INF;', 'd:-NAN;', 'd:1e;', 'd:.;',
    's:3:"abc";', 's:3:"abc"', 's:3:"ab";', 's:5:"abc";', 's:-1:"";', 's:1:"a"x', 'S:3:"a\62c";', 'S:3:"a\6zc";',
    'a:1:{i:0;i:1;}', 'a:1:{i:0;i:1;', 'a:2:{i:0;i:1;}', 'a:1:{i:0;i:1;}}', 'a:-1:{}', 'a:0:{}', 'a:0:{', 'a:1:{s:1:"x";}',
    'a:1:{a:0:{}i:1;}', 'a:1:{d:1.5;i:1;}', 'a:1:{i:0;R:1;}', 'a:1:{i:0;r:1;}', 'a:1:{i:0;R:5;}', 'a:2:{i:0;i:1;i:1;R:2;}',
    'a:9999999999:{}', 'a:99999999999999999999:{}', 'a:1:{i:0;i:1;i:1;i:2;}',
    'O:8:"stdClass":0:{}', 'O:8:"stdClass":1:{s:1:"a";i:1;}', 'O:8:"stdClass":1:{s:1:"a";i:1;', 'O:9:"stdClass":0:{}',
    'O:0:"":0:{}', 'O:3:"a b":0:{}', 'O:1:"\\":0:{}', 'O:8:"stdClass":-1:{}', 'O:8:"stdClass"', 'O:8:"stdClass":0:[}',
    'O:7:"Unknown":1:{s:1:"x";i:1;}', 'O:8:"stdClass":1:{i:0;i:1;}',
    'C:8:"stdClass":0:{}', 'C:3:"Foo":5:{abc}', 'C:3:"Foo":-1:{}', 'C:3:"Foo":2:{a}',
    'E:7:"Foo:Bar";', 'E:3:"Foo";', 'E:11:"Suit:Hearts";', 'E:10:"Suit:Clubs";', 'E:9:"Suit:BASE";', 'E:15:"stdClass:Hearts";',
    'R:1;', 'r:1;', 'x', '}', 'a:1:{}',
];
enum Suit { case Hearts; const BASE = 1; }
foreach ($inputs as $s) {
    echo var_export($s, true), "\n";
    try {
        $r = unserialize($s);
        echo "  => ", str_replace("\n", "", var_export($r, true)), "\n";
    } catch (Throwable $e) {
        echo "  ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
