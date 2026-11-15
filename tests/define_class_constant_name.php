<?php
// define() refuses a class constant name
foreach (["foo::bar", "::", "a::"] as $n) { try { define($n, 1); } catch (ValueError $e) { echo $e->getMessage(), "\n"; } }
try { constant("::"); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(define("ok", 1), ok);
