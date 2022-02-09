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
        "colleciton-entry": [",", SEPARATOR],
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

// @test:Config {}
// function testSingleQuotedFlowScalar() returns error? {
//     Lexer lexer = setLexerString("'somevalue'");
//     check assertToken(lexer, SCALAR, lexeme = "somevalue");
// }

// @test:Config {}
// function testSingleQuotedScalar() returns error? {
//     Lexer lexer = setLexerString("\"somevalue\"");
//     check assertToken(lexer, SCALAR, lexeme = "somevalue");
    // }
