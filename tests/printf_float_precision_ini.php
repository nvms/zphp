<?php
// printf's %s converts a float as any string conversion does, with the
// precision ini
foreach ([-1, 0, 5, 14, 17] as $p) {
    ini_set('precision', $p);
    printf("%d: %s %s %s %s\n", $p, M_PI, 0.1 + 0.2, 1e100, -0.0);
    echo sprintf("%s|%5s|%-12s|", 1/3, 2.5, 1e15), "\n";
}
