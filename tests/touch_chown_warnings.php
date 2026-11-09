<?php
// touch and the ownership changers warn like php when they fail
$base = sys_get_temp_dir() . "/zphp_touch_" . getmypid();
mkdir($base);

var_dump(touch(""));
var_dump(touch("/zphp_no_such_dir/f"));
try {
    touch("$base/f", null, 100);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(touch("$base/f", 100, 200));
clearstatcache();
var_dump(filemtime("$base/f"), fileatime("$base/f"));
var_dump(touch("$base/f", 300));
clearstatcache();
var_dump(filemtime("$base/f"), fileatime("$base/f"));
// a directory and a file without write permission take the current time
chmod("$base/f", 0444);
var_dump(touch("$base/f"), touch($base));
clearstatcache();
var_dump(filemtime("$base/f") > 300);

var_dump(chown("/zphp_no_such_dir/f", 0), chgrp("/zphp_no_such_dir/f", 0));
var_dump(lchown("/zphp_no_such_dir/f", 0), lchgrp("/zphp_no_such_dir/f", 0));
var_dump(chown("$base/f", "zphp_no_such_user_name"), chgrp("$base/f", "zphp_no_such_group_name"));
var_dump(chown("$base/f", getmyuid()), chgrp("$base/f", getmygid()));
try {
    chown("$base/f", []);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

unlink("$base/f");
rmdir($base);
