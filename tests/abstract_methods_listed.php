<?php
// a class that leaves abstract methods unimplemented names how many and
// the first three, in the order its method table has them
abstract class A { abstract function f(); abstract function g(); abstract function h(); abstract function i(); }
class B extends A {}
