<?php
$defined = 1;
var_dump($GLOBALS['defined'], $GLOBALS['missing'], isset($GLOBALS['missing']), $GLOBALS['missing'] ?? 'default');
function readGlobal() {
    return $GLOBALS['nothing_here'];
}
var_dump(readGlobal());
