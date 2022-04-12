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
        "empty sequence": ["[]", []],
        "mapping": ["{key: value}", {"key": "value"}],
        "multiple flow-mapping": ["{key1: value1, key2: value2}", {"key1": "value1", "key2": "value2"}],
        "multiple flow-sequence": ["[first, second]", ["first", "second"]],
        "block style nested mapping": [["key1: ", " key2: value"], {"key1": {"key2": "value"}}],
        "block style nested sequence": [["- ", " - first", " - second"], [["first", "second"]]],
        "mapping nested under sequence": [["- first: item1", "  second: item2", "- third: item3"], [{"first": "item1", "second": "item2"}, {"third": "item3"}]],
        "multiple mapping nested under sequence": [["- first:", "    second: item2", "- third: item3"], [{"first": {"second": "item2"}}, {"third": "item3"}]],
        "aliasing a string": [["- &anchor value", "- *anchor"], ["value", "value"]],
        "aliasing a sequence": [["- &anchor", " - first", " - second", "- *anchor"], [["first", "second"], ["first", "second"]]],
        "only explicit key in block mapping": [["?"], {"": ()}],
        "explicit key and mapping value in block mapping": [["?", ":"], {"": ()}],
        "explicit key in block mapping": [["? key"], {"key": ()}],
        "explicit key with mapping value in block mapping": [["? key", ":"], {"key": ()}],
        "explicit key empty key": [["? ", ": value"], {"": "value"}]
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
        // "multiple root data values": [["|-", " 123", "", ">-", " 123"]],
        "flow style sequence without end": [["[", " first, ", "second "]],
        "aliasing anchor does note exist": [["*alias"]],
        "cyclic reference": [["- &anchor [*anchor]"]]
    };
}
