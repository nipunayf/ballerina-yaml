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
        "nested sequence": [["- ", " - value1", " - value2", "- value3"], [{startType: SEQUENCE}, {startType: SEQUENCE}, {value: "value1"}, {value: "value2", entry: true}, {endType: SEQUENCE}, {value: "value3"}]],
        "multiple end sequences": [["- ", " - value1", "   - value2", "- value3"], [{startType: SEQUENCE}, {startType: SEQUENCE}, {value: "value1"}, {startType: SEQUENCE}, {value: "value2"}, {endType: SEQUENCE}, {endType: SEQUENCE}, {value: "value3"}]],
        "differentiate planar value and key": [["first key: first line", " second line", "second key: value"], [{isKey: true, value: "first key"}, {value: "first line second line"}, {isKey: true, value: "second key"}, {value: "value"}]],
        "escaping sequence with mapping" : [["first:", " - ", "   - item", "second: value"], [{isKey: true, value: "first"}, {startType: SEQUENCE}, {startType: SEQUENCE}, {value:"item"}, {endType: SEQUENCE}, {endType: SEQUENCE}, {isKey: true, value: "second"}, {value: "value"}]]
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
function testBlockMapAndSequenceAtSameIndent() returns error? {
    check assertParsingError(["- seq", "map: value"], true, 2);
}

@test:Config {}
function testIndentationOfBlockSequence() returns error? {
    Parser parser = check new Parser(["-", "  -", "     -", "-"]);
    [int, int][] indentMapping = [[0, 1], [2, 2], [5, 3], [0, 1]];

    foreach int i in 0 ... 3 {
        _ = check parser.parse();
        test:assertEquals(parser.lexer.indent, indentMapping[i][0]);
        test:assertEquals(parser.lexer.seqIndents.length(), indentMapping[i][1]);
    }
}

@test:Config {}
function testIndentationOfBlockMapping() returns error? {
    string[] lines = ["first:", "  second:", "     third:", "forth:"];
    [int, int][] indentMapping = [[0, 1], [2, 2], [5, 3], [0, 1]];

    Lexer lexer = new Lexer();
    foreach int i in 0 ... 3 {
        lexer.line = lines[i];
        lexer.index = 0;
        Token token = check lexer.getToken();

        while token.token != PLANAR_CHAR {
            token = check lexer.getToken();
        }

        test:assertEquals(lexer.indent, indentMapping[i][0]);
        test:assertEquals(lexer.mapIndents.length(), indentMapping[i][1]);
    }
}
