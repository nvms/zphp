<?php
// an uncaught exception whose file is empty is reported as thrown in Unknown
class A extends Exception { public function __construct() { $this->file = ""; } }
throw new A;
