# known bugs

defects noticed during implementation of other features. not blocking current work, but need fixing.

## class constants via :: return null

`Config::VERSION` returns null. class constants defined with `const` inside a class body are stored in `php_constants` with the bare name (e.g. `VERSION`), but accessing them via `ClassName::CONSTANT` goes through `get_static_prop` which looks in `static_props`. the constant is never stored in `static_props`. fix: either store class constants in `static_props` during `class_decl`, or have `get_static_prop` fall back to checking `php_constants` with `ClassName::ConstName` key.

pre-existing bug, noticed during: enum implementation (2026-03-23)
