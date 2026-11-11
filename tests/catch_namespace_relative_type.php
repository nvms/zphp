<?php
namespace N2;
class Foo extends \Exception {}
try { throw new Foo("x"); } catch (namespace\Foo $e) { echo get_class($e), "\n"; }
try { throw new \RuntimeException("y"); } catch (namespace\Foo | \RuntimeException $e) { echo get_class($e), "\n"; }
