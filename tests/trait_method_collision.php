<?php
echo "not reached\n";
trait A { function talk() {} function shout() {} }
trait B { function talk() {} function shout() {} }
class Talker { use A, B; }
