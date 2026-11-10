<?php
$e = new ReflectionExtension('date'); ob_start(); $e->info(); $e->info(); ob_end_clean();
$s = new ReflectionExtension('standard'); ob_start(); $s->info(); ob_end_clean();
$c = (new ReflectionExtension('pcre'))->getConstants(); echo count($c) > 0 ? "ok\n" : "none\n";
