<?php
// regression: foreach by-ref writeback at end-of-iteration must not
// resurrect a key the body explicitly unset(). PHP's true-ref binding
// drops when the source entry goes away; zphp emulates the binding via
// an array_set at the end of each iteration body. before the
// array_set_if_present guard, an unset($arr[$key]) inside the body was
// re-added by the writeback. surfaces in WordPress's WP_REST_Server::
// get_routes() normalization which unsets non-numeric handler keys.
$h = [0 => 'a', 'x' => 'b', 1 => 'c'];
foreach ($h as $k => &$v) {
    if (!is_numeric($k)) unset($h[$k]);
}
unset($v);
echo implode(',', array_keys($h)), "\n";

// nested foreach with outer by-ref
$endpoints = [
    '/foo' => [0 => ['m' => 'GET'], 'allow_batch' => 'v1', 'schema' => 'x'],
];
$opts = [];
foreach ($endpoints as $route => &$handlers) {
    foreach ($handlers as $key => &$handler) {
        if (!is_numeric($key)) {
            $opts[$route][$key] = $handler;
            unset($handlers[$key]);
        }
    }
    unset($handler);
}
unset($handlers);
foreach ($endpoints as $r => $hs) echo "route $r: keys=", implode(',', array_keys($hs)), "\n";
foreach ($opts as $r => $os) echo "opts $r: keys=", implode(',', array_keys($os)), "\n";
