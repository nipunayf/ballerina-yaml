type Token record {|
    YAMLToken token;
    string value = "";
|};

enum YAMLToken {
    DOCUMENT_START,
    DOCUMENT_END,
    STREAM_START,
    STREAM_END,
    BLOCK_START,
    BLOCK_END,
    BOM,
    SEQUENCE_ENTRY,
    MAPPING_KEY,
    MAPPING_VALUE,
    SEPARATOR,
    SEQUENCE_START,
    SEQUENCE_END,
    MAPPING_START,
    MAPPING_END,
    KEY_TOKEN,
    VALUE_TOKEN,
    BLOCK_ENTRY,
    FLOW_ENTRY,
    DIRECTIVE = "%",
    ALIAS = "*",
    ANCHOR = "&",
    TAG_HANDLE = "!",
    TAG_PREFIX = "<tag-prefix>",
    DOT = ".",
    SCALAR = "<scalar>",
    LITERAL,
    FOLDED,
    DECIMAL = "<decimal-integer>",
    SEPARATION_IN_LINE = "<separation-in-line>",
    LINE_BREAK = "<break>",
    DIRECTIVE_MARKER = "---",
    DOCUMENT_MARKER = "...",
    EOL,
    DUMMY
}
