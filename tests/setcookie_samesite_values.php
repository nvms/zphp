<?php
// php 8.6 accepts only Strict, Lax, None (any case) or "" as samesite
ob_start();
foreach (['Strict', 'lax', 'NONE', '', 'Invalid', "Lax\r\nX-Injected: 1"] as $v) {
    foreach (['setcookie', 'setrawcookie'] as $f) {
        try {
            $r = $f('test', 'value', ['samesite' => $v]);
            echo "$f: ", var_export($r, true), "\n";
        } catch (ValueError $e) {
            echo "$f: ", $e->getMessage(), "\n";
        }
    }
}
ob_end_flush();
