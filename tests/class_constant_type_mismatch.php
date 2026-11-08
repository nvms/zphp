<?php
// a typed constant's override must have a compatible type
echo "not reached\n";
class Base { const int ID = 1; }
class Child extends Base { const string ID = 'x'; }
