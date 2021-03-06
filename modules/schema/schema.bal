public function getJsonSchemaTags() returns map<YAMLTypeConstructor> {
    return {
        "tag:yaml.org,2002:null": {
            kind: STRING,
            construct: constructSimpleNull,
            identity: function (json j) returns boolean => j is (),
            represent: representAsString
        },
        "tag:yaml.org,2002:bool": {
            kind: STRING,
            construct: constructSimpleBool,
            identity: generateIdentityFunction(boolean),
            represent: representAsString
        },
        "tag:yaml.org,2002:int": {
            kind: STRING,
            construct: constructSimpleInteger,
            identity: generateIdentityFunction(int),
            represent: representAsString
        },
        "tag:yaml.org,2002:float": {
            kind: STRING,
            construct: constructSimpleFloat,
            identity: generateIdentityFunction(float),
            represent: representAsString
        }
    };
}

public function getCoreSchemaTags() returns map<YAMLTypeConstructor> {
    return {
        "tag:yaml.org,2002:null": {
            kind: STRING,
            construct: constructNull,
            identity: function (json j) returns boolean => j is (),
            represent: representAsString
        },
        "tag:yaml.org,2002:bool": {
            kind: STRING,
            construct: constructBool,
            identity: generateIdentityFunction(boolean),
            represent: representAsString
        },
        "tag:yaml.org,2002:int": {
            kind: STRING,
            construct: constructInteger,
            identity: generateIdentityFunction(int),
            represent: representAsString
        },
        "tag:yaml.org,2002:float": {
            kind: STRING,
            construct: constructFloat,
            identity: generateIdentityFunction(float),
            represent: representFloat
        }
    };
}
