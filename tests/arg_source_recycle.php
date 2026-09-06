<?php
class ArgSourceBox { public $x = 1; public $a = ['key' => 2]; }
function argSourceMake() { return new ArgSourceBox; }
function argSourceLater() { return 0; }
function argSourceChange(&$x, $later) { $x = 9; }
for ($i = 0; $i < 1000; $i++) {
    argSourceChange(x: argSourceMake()->x, later: argSourceLater());
    argSourceChange(x: argSourceMake()->a['key'], later: argSourceLater());
    try {
        argSourceChange(x: argSourceMake()->x, later: argSourceThrow());
    } catch (Exception $e) {}
}
function argSourceThrow() { throw new Exception('discard'); }
echo "recycle-ok\n";
