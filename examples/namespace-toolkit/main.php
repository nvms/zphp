<?php
// covers: namespaces spanning multiple files, use class aliases, use
//   function, use const, group use, fully-qualified names, the namespace\
//   relative operator, cross-namespace class extension and dispatch

namespace App;

require __DIR__ . '/Geometry.php';
require __DIR__ . '/Shapes.php';

use App\Geometry\Point;
use App\Shapes\{Circle, Rectangle};
use function App\Geometry\distance;

function summarize(Shapes\Shape $s): string
{
    return 'summary: ' . $s->describe();
}

echo "== cross-namespace functions ==\n";
$origin = new Point(0.0, 0.0);
$p = new Point(3.0, 4.0);
echo 'distance: ', distance($origin, $p), "\n";

echo "== group use ==\n";
$c = new Circle($origin, 5.0);
$r = new Rectangle(4.0, 6.0);
echo $c->describe(), "\n";
echo $r->describe(), "\n";

echo "== cross-namespace dispatch ==\n";
echo summarize($c), "\n";
echo summarize($r), "\n";
echo 'center: ', $c->centerString(), "\n";
echo 'covers p: ', $c->covers($p) ? 'yes' : 'no', "\n";
echo 'covers far: ', $c->covers(new Point(10.0, 10.0)) ? 'yes' : 'no', "\n";
echo 'origin x: ', $c->originX(), "\n";

echo "== fully-qualified names ==\n";
$fq = new \App\Geometry\Point(1.5, 2.5);
echo 'fq point: ', $fq, "\n";
echo 'fq distance: ', \App\Geometry\distance($origin, $fq), "\n";

echo "== namespace\\ relative operator ==\n";
echo namespace\summarize($r), "\n";

echo "done\n";
