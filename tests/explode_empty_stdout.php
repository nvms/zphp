<?php
try { explode("", "abc"); echo "no err\n"; } catch (\ValueError $e) { echo "ve\n"; }
fprintf(STDOUT, "x=%d\n", 5);
fwrite(STDOUT, "via-fwrite\n");
