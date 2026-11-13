<?php
// statics declared in top-level code, an eval among them (a debug build
// once reported their compile-time list as leaked)

static $top = ['a' => 1];
var_dump($top);
eval('static $n = 5; $n++; var_dump($n);');
try {
    eval('static $e = [1, 2]; throw new Exception("thrown after a static");');
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
