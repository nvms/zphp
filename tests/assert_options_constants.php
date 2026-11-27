<?php
// the ASSERT_* constants take php's values (ASSERT_QUIET_EVAL is gone since
// php 8.0), and assert_options() reads each by its constant
var_dump(ASSERT_ACTIVE, ASSERT_CALLBACK, ASSERT_BAIL, ASSERT_WARNING, ASSERT_EXCEPTION);
var_dump(defined('ASSERT_QUIET_EVAL'));
var_dump(@assert_options(ASSERT_EXCEPTION));
var_dump(@assert_options(ASSERT_EXCEPTION, 0), ini_get('assert.exception'));
try {
    @assert_options(6);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
