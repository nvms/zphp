<?php
// regression: uncaught-exception header uses "in <path>:<line>" (not "on
// line N") and does not include a source snippet between the header and
// the stack trace. matches PHP's format with log_errors=0
function inner() {
    throw new RuntimeException("boom");
}
function outer() {
    inner();
}
outer();
