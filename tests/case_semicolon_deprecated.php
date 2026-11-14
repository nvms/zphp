<?php
// a case or default label ended by a semicolon is deprecated
function f($x) {
    switch ($x) {
        case 1;
            return "one";
        case 2:
            return "two";
        default;
            return "other";
    }
}
echo f(1), f(2), f(3), "\n";
enum E { case A; case B; }
echo E::B->name, "\n";
eval("switch (1) { case 1; echo \"eval\\n\"; }");
