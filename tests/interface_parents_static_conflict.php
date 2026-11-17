<?php
// a static method one parent interface declares and an instance method
// another declares under the same name

interface StaticOne { static function f(); }
interface PlainOne { function F(); }
interface Broken extends StaticOne, PlainOne {}
echo "not reached\n";
