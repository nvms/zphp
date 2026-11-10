const std = @import("std");

pub const names = [_][]const u8{
    "stdClass",                            "Closure",                       "Generator",                    "Fiber",                                "WeakMap",                            "WeakReference",
    "Iterator",                            "IteratorAggregate",             "Traversable",                  "Countable",                            "ArrayAccess",                        "Stringable",
    "Serializable",                        "JsonSerializable",              "BackedEnum",                   "UnitEnum",                             "Throwable",                          "Exception",
    "Error",                               "TypeError",                     "ValueError",                   "ArgumentCountError",                   "ArithmeticError",                    "DivisionByZeroError",
    "RuntimeException",                    "LogicException",                "InvalidArgumentException",     "BadMethodCallException",               "BadFunctionCallException",           "OutOfRangeException",
    "OverflowException",                   "UnderflowException",            "LengthException",              "DomainException",                      "RangeException",                     "UnexpectedValueException",
    "JsonException",                       "UnhandledMatchError",           "FiberError",                   "ClosedGeneratorException", "ParseError",                           "CompileError",                       "DateTime",
    "DateTimeImmutable",                   "DateTimeInterface",             "DateTimeZone",                 "DateInterval",                         "DatePeriod",                         "DateException",
    "DateInvalidTimeZoneException",        "DateInvalidOperationException", "DateMalformedStringException", "DateMalformedIntervalStringException", "DateMalformedPeriodStringException", "DateError",
    "DateObjectError",                     "DateRangeError",                "ArrayObject",                  "ArrayIterator",                        "AppendIterator",                     "EmptyIterator",
    "InfiniteIterator",                    "NoRewindIterator",              "FilterIterator",               "CallbackFilterIterator",               "RegexIterator",                      "LimitIterator",
    "IteratorIterator",                    "CachingIterator",               "MultipleIterator",             "RecursiveIteratorIterator",            "RecursiveArrayIterator",             "RecursiveCallbackFilterIterator",
    "RecursiveFilterIterator",             "RecursiveRegexIterator",        "RecursiveTreeIterator",        "RecursiveDirectoryIterator",           "DirectoryIterator",                  "GlobIterator",
    "SplStack",                            "SplQueue",                      "SplDoublyLinkedList",          "SplFixedArray",                        "SplObjectStorage",                   "SplPriorityQueue",
    "SplMinHeap",                          "SplMaxHeap",                    "SplHeap",                      "SplFileObject",                        "SplFileInfo",                        "SplTempFileObject",
    "PDO",                                 "PDOStatement",                  "PDOException",                 "SimpleXMLElement",                     "SimpleXMLIterator",                  "SimpleXMLChildrenIter",
    "XMLReader",                           "XMLWriter",                     "XMLParser",                    "DOMDocument",                          "DOMElement",                         "DOMNode",
    "DOMAttr",                             "DOMText",                       "DOMComment",                   "DOMCdataSection",                      "DOMDocumentType",                    "DOMNodeList",
    "DOMNamedNodeMap",                     "DOMXPath",                      "DOMException",                 "DOMProcessingInstruction",             "DOMEntityReference",                 "Reflection",
    "ReflectionClass",                     "ReflectionMethod",              "ReflectionFunction",           "ReflectionFunctionAbstract",           "ReflectionProperty",                 "ReflectionParameter",
    "ReflectionType",                      "ReflectionNamedType",           "ReflectionUnionType",          "ReflectionIntersectionType",           "ReflectionEnum",                     "ReflectionEnumUnitCase",
    "ReflectionEnumBackedCase",            "ReflectionClassConstant",       "ReflectionAttribute",          "ReflectionObject",                     "ReflectionGenerator",                "ReflectionFiber",
    "ReflectionExtension",                 "ReflectionZendExtension",       "Reflector",                    "ReflectionConstant",                   "RecursiveIterator",                  "OuterIterator",
    "SeekableIterator",                    "HashContext",                   "Random\\Engine",               "Random\\Randomizer",                   "Random\\Engine\\Mt19937",            "Random\\Engine\\Xoshiro256StarStar",
    "Random\\Engine\\PcgOneseq128XslRr64", "Random\\Engine\\Secure",        "IntlChar",                     "Normalizer",                           "Collator",                           "NumberFormatter",
    "IntlDateFormatter",                   "MessageFormatter",              "Locale",                       "Phar",                                 "PharData",                           "SoapClient",
    "SoapServer",                          "SoapFault",                     "GdImage",                      "OpenSSLAsymmetricKey",                 "OpenSSLCertificate",                 "OpenSSLCertificateSigningRequest",
};

pub fn contains(name: []const u8) bool {
    for (names) |builtin| {
        if (std.ascii.eqlIgnoreCase(builtin, name)) return true;
    }
    return false;
}
