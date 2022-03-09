import ballerina/test;

@test:Config {
    dataProvider: documentMarkersDataGen
}

function testDocumentMarkerToken(string lexeme, YAMLToken token) returns error? {
    Lexer lexer = setLexerString(lexeme, LEXER_DOCUMENT_OUT);
    check assertToken(lexer, token);
}

function documentMarkersDataGen() returns map<[string, YAMLToken]> {
    return {
        "directive-marker": ["---", DIRECTIVE_MARKER],
        "document-marker": ["...", DOCUMENT_MARKER]
    };
}

@test:Config {}
function testKeyMapSpanningMultipleValues() returns error? {
    Parser parser = check new Parser(["key : ", " ", "", " value"]);

    Event event = check parser.parse();
    test:assertTrue((<ScalarEvent>event).isKey);
    test:assertEquals((<ScalarEvent>event).value, "key");

    event = check parser.parse();
    test:assertEquals((<ScalarEvent>event).value, "value");
}