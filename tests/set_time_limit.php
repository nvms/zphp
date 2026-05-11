<?php
// covers: set_time_limit + ini_set('max_execution_time') deadline enforcement

// 0 = unlimited; calls succeed without throwing
echo "unlimited: ", set_time_limit(0) ? 'ok' : 'fail', "\n";
$i = 0;
while ($i < 1000) $i++;
echo "loop ran: ", $i, "\n";

// negative is treated as 0
echo "neg: ", set_time_limit(-5) ? 'ok' : 'fail', "\n";

// re-arm; the deadline resets to "now + N" on each call
echo "rearm: ", set_time_limit(60) ? 'ok' : 'fail', "\n";
$j = 0;
for ($k = 0; $k < 100; $k++) $j += $k;
echo "j: ", $j, "\n";

// ini_set arms the same deadline
$prev = ini_set('max_execution_time', '0');
echo "ini reset: ", ($prev === '0' || $prev === '' || $prev === false) ? 'ok' : ('was ' . $prev), "\n";
echo "post-ini: ", ini_get('max_execution_time'), "\n";
