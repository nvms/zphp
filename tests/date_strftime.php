<?php
// strftime() and gmstrftime() format the time's broken-down fields with the
// C library's strftime, in the C locale

$all = "%a %A %b %B %c %C %d %D %e %F %g %G %h %H %I %j %k %l %m %M %n %p %P %r %R %S %t %T %u %U %V %W %w %x %X %y %Y %Z %z %% %q %E %O %-d %_m %10Y";
foreach (["Asia/Jerusalem", "America/New_York", "Australia/Lord_Howe", "UTC"] as $zone) {
    date_default_timezone_set($zone);
    foreach ([0, 1151366400, 1218182888, 1700000000, -2000000000, 4102444800] as $t) {
        var_dump(@strftime($all, $t), @gmstrftime($all, $t));
    }
}
var_dump(@strftime(""), @gmstrftime(""), @strftime("%%q %%a", 0), @strftime("blah", 0), @strftime("%", 0), @strftime("a\0%Y", 0));
var_dump(strlen(@strftime(str_repeat("%c", 200), 0)));
try {
    @strftime([]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
