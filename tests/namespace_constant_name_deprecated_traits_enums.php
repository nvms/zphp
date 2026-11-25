<?php
// a trait constant or an enum case named "namespace" is a class constant
// declared with that name, deprecated as the others are
set_error_handler(function ($no, $msg, $file, $line) { echo "$no: $msg (line $line)\n"; return true; });
eval('trait T { const NameSpace = "trait constant"; }
class UsesT { use T; }
enum E: string { case namespace = "case value"; case other = "x"; }
enum U { case NAMESPACE; }
interface I { const namespace = 1; }');
echo UsesT::NameSpace, "\n", E::namespace->value, "\n", U::NAMESPACE->name, "\n";
