public enum FailSafeSchema {
    MAPPING,
    SEQUENCE,
    STRING
}

public type YAMLTypeConstructor record {|
    FailSafeSchema kind;
    function (json data) returns json|TypeError construct;
|};
