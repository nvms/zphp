<?php
// global accepts variable variables, naming the global at run time
$alpha = 'A'; $beta = 'B';
function f() { $n = 'alpha'; global $$n, ${'be' . 'ta'}; echo $alpha, $beta, "\n"; $alpha = 'changed'; }
f(); echo $alpha, "\n";
function g() { global ${'fresh'}; $fresh = 'made'; }
g(); echo $fresh, "\n";
function h() { $k = 5; global $$k; var_dump(${'5'}); }
$GLOBALS['5'] = 'five'; h();
function i() { $names = ['alpha']; global ${$names[0]}, $beta; echo $alpha, $beta, "\n"; }
i();
try { (function () { global ${new stdClass}; })(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
