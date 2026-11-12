<?php
echo "never runs\n";
foreach ([1] as $GLOBALS) {
}
