import ballerina/test;

@test:Config {
    dataProvider: collectionDataGen
}
function testBlockCollectionEvents(string|string[] line, Event[] eventStream) returns error? {
    Parser parser = check new Parser((line is string) ? [line] : line);

    foreach Event item in eventStream {
        Event event = check parser.parse();
        test:assertEquals(event, item);
    }
}

function collectionDataGen() returns map<[string|string[], Event[]]> {
    return {
        "single element": ["- value", [{startType: SEQUENCE}, {value: "value"}]],
        "compact sequence in-line": ["- - value", [{startType: SEQUENCE}, {startType: SEQUENCE}, {value: "value"}]],
        "empty sequence entry": ["- ", [{startType: SEQUENCE}, {endType: STREAM}]],
        "nested sequence": [["- ", " - value1", " - value2", "- value3"], [{startType: SEQUENCE}, {startType: SEQUENCE}, {value: "value1"}, {value: "value2"}, {endType: SEQUENCE}, {value: "value3"}]],
        "multiple end sequences": [["- ", " - value1", "   - value2", "- value3"], [{startType: SEQUENCE}, {startType: SEQUENCE}, {value: "value1"}, {startType: SEQUENCE}, {value: "value2"}, {endType: SEQUENCE}, {endType: SEQUENCE}, {value: "value3"}]]
    };
}

@test:Config {}
function testInvalidIndentCollection() returns error? {
    Parser parser = check new Parser(["- ", "  - value", " - value"]);

    Event event = check parser.parse();
    test:assertEquals((<StartEvent>event).startType, SEQUENCE);

    event = check parser.parse();
    test:assertEquals((<StartEvent>event).startType, SEQUENCE);

    Event|error err = parser.parse();
    test:assertTrue(err is LexicalError);
}

@test:Config {}
function testIndentationOfBlockToken() returns error? {
    Parser parser = check new Parser(["-", "  -", "     -", "-"]);
    [int, int][] indentMapping = [[0, 1], [2, 2], [5, 3], [0, 1]];

    foreach int i in 0 ... 3 {
        _ = check parser.parse();
        test:assertEquals(parser.lexer.indent, indentMapping[i][0]);
        test:assertEquals(parser.lexer.indents.length(), indentMapping[i][1]);
    }
}
