import ballerina/test;

@test:Config {
    dataProvider: simpleEventDataGen
}
function testWritingSimpleEvent(Event[] events, string[] expectedOutput) returns error? {
    string[] output = check emit(events);
    test:assertEquals(output, expectedOutput);
}

function simpleEventDataGen() returns map<[Event[], string[]]> {
    return {
        // "empty block sequence": [[{startType: SEQUENCE}], ["-"]],
        // "block sequence": [[{startType: SEQUENCE}, {value: "value1"}, {value: "value2"}, {endType: SEQUENCE}], ["- value1", "- value2"]],
        // "indented block sequence": [[{startType: SEQUENCE}, {startType: SEQUENCE}, {value: "value"}, {endType: SEQUENCE}, {endType: SEQUENCE}], ["-", "  - value"]],
        // "single block value": [[{startType: MAPPING}, {value: "key", isKey: true}, {value: "value"}], ["key: value"]],
        // "multiple block mappings": [[{startType: MAPPING}, {value: "key1", isKey: true}, {value: "value1"}, {value: "key2", isKey: true}, {value: "value2"}], ["key1: value1", "key2: value2"]],
        "indented block mapping": [[{startType: MAPPING}, {value: "parentKey", isKey: true}, {startType: MAPPING}, {value: "childKey", isKey: true}, {value: "value"}], ["parentKey: ", "  childKey: value"]],
        "single value": [[{value: "value"}], ["value"]]
    };
}
