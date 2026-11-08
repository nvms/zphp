<?php
echo "not reached\n";
trait Hello { function hello() {} }
trait World { function world() {} }
class C { use Hello, World { hello as world; } }
