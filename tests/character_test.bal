import ballerina/test;

@test:Config {
    dataProvider: indicatorDataGen,
    groups: ["character-productions"]
}
function testIndicatorTokens(string lexeme, YAMLToken expectedToken) returns error? {
    Lexer lexer = setLexerString(lexeme);
    check assertToken(lexer, expectedToken);
}

function indicatorDataGen() returns map<[string, YAMLToken]> {
    return {
        "sequence-entry": ["-", SEQUENCE_ENTRY],
        "mapping-key": ["?", MAPPING_KEY],
        "mapping-value": [":", MAPPING_VALUE],
        "collection-entry": [",", SEPARATOR],
        "sequence-start": ["[", SEQUENCE_START],
        "sequence-end": ["]", SEQUENCE_END],
        "mapping-start": ["{", MAPPING_START],
        "mapping-end": ["}", MAPPING_END]
    };
}

@test:Config {}
function testAnchorToken() returns error? {
    Lexer lexer = setLexerString("&anchor value");
    check assertToken(lexer, ANCHOR, lexeme = "anchor");
}

@test:Config {}
function testAliasToken() returns error? {
    Lexer lexer = setLexerString("*anchor");
    check assertToken(lexer, ALIAS, lexeme = "anchor");
}

@test:Config {}
function testSeparationSpacesToken() returns error? {
    Lexer lexer = setLexerString("  1");
    check assertToken(lexer, SEPARATION_IN_LINE);
    check assertToken(lexer, DECIMAL, lexeme = "1");
}

@test:Config {}
function testEmptyLineToken() returns error? {
    Lexer lexer = setLexerString("");
    check assertToken(lexer, EMPTY_LINE);

    lexer = setLexerString(" ");
    check assertToken(lexer, EMPTY_LINE);
}

@test:Config {
    dataProvider: lineFoldingDataGen
}
function testProcessLineFolding(string[] arr, string value) returns error? {
    check assertParsingEvent(arr, value);
}

function lineFoldingDataGen() returns map<[string[], string]> {
    return {
        "space": [["\"as", "space\""], "as space"],
        "space-empty": [["\"", "space\""], " space"]
    };
}

// @test:Config {
//     dataProvider: separateDataGen
// }
// function testSeparateEvent(string[] arr, string value) returns error? {
//     check assertParsingEvent(arr, value, "!tag", "anchor");
// }

// function separateDataGen() returns map<[string[], string]> {
//     return {
//         "single space": [["!tag &anchor value"], "value"],
//         "new line": [["!tag", "&anchor value"], "value"],
//         "with comment": [["!tag #first-comment", "#second-comment", "&anchor value"]]
//     };
// }

// @test:Config {
//     dataProvider: nodeTagDataGen
// }
// function testNodeTagToken(string line, string value) returns error? {
//     Lexer lexer = setLexerString(line);
//     check assertToken(lexer, TAG, lexeme = value);
// }

// function nodeTagDataGen() returns map<[string, string]> {
//     return {
//         "verbatim global": ["!<tag:yaml.org,2002:str>", "tag:yaml.org,2002:str"],
//         "verbatim local": ["!<!bar>", "!bar"],
//         "tag-shorthand primary": ["!local", "!local"],
//         "tag-shorthand secondary": ["!!str", "!!str"],
//         "tag-shorthand named": ["!e!tag", "!e!tag"],
//         "tag-shorthand escaped": ["!e!tag%21", "!e!tag!"],
//         "non-specific tag": ["!", "!"]
//     };
// }

// @test:Config {
//     dataProvider: invalidNodeTagDataGen
// }
// function testInvalidNodeTagToken(string line) returns error? {
//     assertLexicalError(line);
// }

// function invalidNodeTagDataGen() returns map<[string]> {
//     return {
//         "verbatim primary": ["!<!>"],
//         "verbatim invalid": ["!<$:?>"],
//         "tag-shorthand no-suffix": ["!e!"]

//     };
// }