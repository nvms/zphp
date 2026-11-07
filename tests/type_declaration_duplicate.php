<?php
// the same type twice in a union is a compile-time error, whatever its case
echo "not reached\n";
class Item {}
function broken(Item|null|ITEM $value) {}
