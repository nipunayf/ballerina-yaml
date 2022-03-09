type Token record {|
    YAMLToken token;
    string value = "";
|};

enum YAMLToken {
    BOM,
    SEQUENCE_ENTRY,
    MAPPING_KEY = "?",
    MAPPING_VALUE = ":",
    SEPARATOR = ",",
    SEQUENCE_START = "[",
    SEQUENCE_END = "]",
    MAPPING_START = "{",
    MAPPING_END = "}",
    KEY_TOKEN,
    VALUE_TOKEN,
    BLOCK_ENTRY,
    FLOW_ENTRY,
    DIRECTIVE = "%",
    ALIAS = "*",
    ANCHOR = "&",
    TAG_HANDLE = "<tag-handle>",
    TAG_PREFIX = "<tag-prefix>",
    TAG = "<tag>",
    DOT = ".",
    SCALAR = "<scalar>",
    LITERAL,
    FOLDED,
    DECIMAL = "<decimal-integer>",
    SEPARATION_IN_LINE = "<separation-in-line>",
    LINE_BREAK = "<break>",
    DIRECTIVE_MARKER = "---",
    DOCUMENT_MARKER = "...",
    DOUBLE_QUOTE_DELIMITER = "\"",
    DOUBLE_QUOTE_CHAR,
    SINGLE_QUOTE_DELIMITER = "'",
    SINGLE_QUOTE_CHAR,
    PLANAR_CHAR,
    EMPTY_LINE,
    EOL,
    DUMMY
}
