<?php
// an abstract property hook counts as an abstract method of the class
abstract class P { abstract public $prop { get; set; } }
interface I { public $other { get; } }
class C extends P implements I {}
