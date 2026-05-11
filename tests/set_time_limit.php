<?php
// covers: set_time_limit + ini_set('max_execution_time') deadline plumbing.
// the return value of set_time_limit varies between environments (it returns
// false when in disable_functions), so this test exercises the side effects
// rather than the return values

@set_time_limit(0);
$i = 0;
while ($i < 1000) $i++;
echo "loop ran: ", $i, "\n";

@set_time_limit(-5);
@set_time_limit(60);
$j = 0;
for ($k = 0; $k < 100; $k++) $j += $k;
echo "j: ", $j, "\n";

// ini directives. ini_set('max_execution_time', '0') always succeeds and
// returns the previous value (we don't assert on the prev value because it
// depends on whether the environment's set_time_limit propagated to ini)
@ini_set('max_execution_time', '0');
echo "post-ini: ", ini_get('max_execution_time'), "\n";
