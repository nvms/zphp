<?php
echo "never runs\n";
$order = null;
$order?->customer->name = 'x';
