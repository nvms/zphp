<?php
// a declaration's own name is the namespace plus the name; a `use` import of
// the same short name only matters when it names something else
namespace Tools {
    use Other\Helper;
    function helper() { return __FUNCTION__; }
    echo helper(), "\n";
}
namespace Shop {
    use Shop\Cart;
    class Cart {}
    echo get_class(new Cart), "\n";
    use Vendor\Basket;
    echo "declaring\n";
    if (true) { class Basket {} }
}
