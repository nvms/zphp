<?php
// warnings from ArrayObject's own dimension handlers inside an included file
include __DIR__ . "/include/native_method_warnings.php";
function f() { include __DIR__ . "/include/native_method_warnings.php"; }
f();
