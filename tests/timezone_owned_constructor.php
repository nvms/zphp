<?php
function timezoneFromReplacement() {
    return new DateTimeZone(str_replace('zone', 'UTC', 'zone'));
}
$zone = timezoneFromReplacement();
for ($i = 0; $i < 100; ++$i) {
    $temporary = str_replace('old', 'new', 'old');
}
gc_collect_cycles();
var_dump($zone->getName());
$date = new DateTimeImmutable('2026-01-01 12:00:00', $zone);
var_dump($date->format('Y-m-d H:i:s T'));
