import ballerina/test;

@test:Config {
    dataProvider: nativeDataStructureDataGen
}
function testGenerateNativeDataStructure(string|string[] line, anydata structure) returns error? {
    Parser parser = check new Parser((line is string) ? [line] : line);
    Composer composer = new Composer(parser);
    anydata[] output = check composer.compose();

    test:assertEquals(output[0], structure);
}

function nativeDataStructureDataGen() returns map<[string|string[], anydata]> {
    return {
        // "empty sequence": ["[]", []],
        // "mapping": ["{key: value}", {"key": "value"}]
        "block style nested mapping": [["key1: ", " key2: value"], {"key1": {"key2": "value"}}]
        // "block style nested sequence": [["- ", " - first", " - second"], [["first", "second"]]]
    };
}

@test:Config {
    dataProvider: invalidEventStreamDataGen
}
function testComposeInvalidEventStream(string[] lines) returns error? {
    Parser parser = check new Parser(lines);
    Composer composer = new Composer(parser);

    anydata[]|error output = composer.compose();
    test:assertTrue(output is ComposingError);
}

function invalidEventStreamDataGen() returns map<[string[]]> {
    return {
        // "multiple root data values": [["|-", " 123", "", ">-", " 123"]]
        "flow style sequence without end": [["[", " first, ", "second "]]
    };
}
