<?php
// A nonexistent Unix socket needs neither a listener nor a database fixture.
$socket = __DIR__ . '/mysqli-report-missing/socket';
$a = new mysqli_driver();
$b = new mysqli_driver();
var_dump($a->report_mode);
foreach ([MYSQLI_REPORT_OFF, MYSQLI_REPORT_ERROR, MYSQLI_REPORT_STRICT,
          MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT, MYSQLI_REPORT_ALL,
          MYSQLI_REPORT_INDEX] as $mode) {
    var_dump(mysqli_report($mode));
    var_dump($a->report_mode, $b->report_mode);
    try {
        $result = @mysqli_connect('localhost', 'nobody', '', '', 3306, $socket);
        var_dump($result);
    } catch (mysqli_sql_exception $e) {
        echo get_class($e), ':', $e->getCode() > 0 ? 'code' : 'no-code', ':', strlen($e->getSqlState()), "\n";
    }
}
$a->report_mode = MYSQLI_REPORT_STRICT;
var_dump($b->report_mode);
$link = mysqli_init();
try {
    @$link->real_connect('localhost', 'nobody', '', '', 3306, $socket);
    echo "missing exception\n";
} catch (mysqli_sql_exception $e) {
    echo "method caught\n";
}
mysqli_close($link);
try {
    $link = @new mysqli('localhost', 'nobody', '', '', 3306, $socket);
    echo "missing constructor exception\n";
} catch (mysqli_sql_exception $e) {
    echo "constructor caught\n";
}
$b->report_mode = MYSQLI_REPORT_OFF;
var_dump($a->report_mode);
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
