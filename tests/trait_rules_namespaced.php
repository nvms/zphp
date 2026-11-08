<?php
// insteadof and as name traits the way any class name is resolved: through
// the namespace and the file's imports
namespace App\Traits { trait Speaks { function say() { return 'speaks'; } } trait Shouts { function say() { return 'SHOUTS'; } } }
namespace App {
    use App\Traits\Shouts;
    class Voice {
        use Traits\Speaks, Shouts { Traits\Speaks::say insteadof Shouts; Shouts::say as shout; }
    }
    echo (new Voice)->say(), ' ', (new Voice)->shout(), "\n";
}
