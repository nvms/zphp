<?php
echo "never runs\n";
function &total($cart) {
    return $cart?->total;
}
