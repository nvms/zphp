<?php
class SpliceParent { private string $value = 'parent'; }
class SpliceReplacement extends SpliceParent {
    private string $value = 'child';
    protected string $hidden = 'protected';
    public string $visible = 'public';
    public int $unset;
    public function __destruct() { echo "replacement released\n"; }
}
$a = ['before', 'remove', 'after'];
$r = array_splice($a, 1, 1, new SpliceReplacement());
var_dump($a, $r);
foreach ([new stdClass(), (object) ['a' => 3, 'b' => 4], null, false, 7, 'text'] as $replacement) {
    $a = [1, 2];
    array_splice($a, 1, 0, $replacement);
    var_dump($a);
}
