<?php
error_reporting(0);
echo "before\n";
ob_start('strtoupper');
echo 'discarded';
ob_end_clean();
echo "unreachable\n";
