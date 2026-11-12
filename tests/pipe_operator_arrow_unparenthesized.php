<?php
echo "never runs\n";
$r = 1 |> fn($x) => $x + 1;
