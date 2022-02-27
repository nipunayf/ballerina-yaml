import ballerina/test;

@test:Config {
    dataProvider: singleQuoteDataGen
}
function testSingleQuoteEvent(string[] arr, string value) returns error? {
    check assertParsingEvent(arr, value);
}

function singleQuoteDataGen() returns map<[string[], string]> {
    return {
        "empty": [["''"], ""],
        "single-quote": [["''''"], "'"],
        "multi-line": [["' 1st non-empty",""," 2nd non-empty ","3rd non-empty '"], " 1st non-empty\n2nd non-empty 3rd non-empty "]
    };
}

@test:Config {
    dataProvider: invalidSingleQuoteDataGen
}
function testInvalidSingleQuoteEvent(string value) returns error? {
    assertParsingError(value);
}

function invalidSingleQuoteDataGen() returns map<[string]> {
    return {
        "not-escaped": ["'''"]
    };
}

