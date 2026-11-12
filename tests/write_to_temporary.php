<?php
echo "never runs\n";
class Config { public $values = []; }
(new Config)->values['debug'] = true;
