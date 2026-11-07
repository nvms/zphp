<?php
// each namespace declaration starts with no imports: a name imported in one
// namespace block resolves plainly in the next, and may be declared there
namespace Shop { use Vendor\Basket as Cart; echo Cart::class, "\n"; }
namespace Store { echo Cart::class, "\n"; class Cart {} echo get_class(new Cart), "\n"; }
namespace { use Vendor\Item; class Entity {} echo Item::class, ' ', Entity::class, "\n"; }
