<?php
// regression: bare fatal errors (uncatchable, not from exceptions) emit
// PHP's 'PHP Fatal error:' prefix and a clean 'in {file} on line N' suffix
// instead of zphp's debug-style source-snippet format. previously a fatal
// from the compile-time check (e.g. 'Cannot override final method',
// 'Cannot redeclare ...') printed without the prefix and with a source
// preview that doesn't match PHP

// trigger an inheritance-time fatal: 'Cannot override final method'
class FF { final public function x() {} }
class FX extends FF { public function x() {} }
