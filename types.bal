import yaml.schema;

# Configurations for writing a YAML document.
#
# + indentationPolicy - Number of whitespace for an indentation  
# + blockLevel - The maximum depth level for a block collection.  
# + canonical - If set, the tags are written along with the nodes.
# + useSingleQuotes - If set, single quotes are used to surround scalars.
# + forceQuotes - If set, all the scalars are surrounded by quotes.  
# + schema - YAML schema used for writing  
# + yamlTypes - Custom YAML types for the schema
public type WriteConfig record {|
    int indentationPolicy = 2;
    int blockLevel = 1;
    boolean canonical = false;
    boolean useSingleQuotes = false;
    boolean forceQuotes = false;
    YAMLSchema schema = CORE_SCHEMA;
    YAMLType[] yamlTypes = [];
|};

# Configurations for reading a YAML document.
#
# + schema - YAML schema used for writing
# + yamlTypes - Custom YAML types for the schema
public type ReadConfig record {|
    YAMLSchema schema = CORE_SCHEMA;
    YAMLType[] yamlTypes = [];
|};

# Represents the attributes of the custom YAML type.
#
# + tag - YAML tag for the custom type  
# + ballerinaType - The equivalent Ballerina type for the YAML tag
public type YAMLType record {|
    string tag;
    typedesc<json> ballerinaType;
    *schema:YAMLTypeConstructor;
|};

# Represents the basic YAML types available in the Fail safe schema.
# 
# + MAPPING - YAML mapping collection
# + SEQUENCE - YAML sequence collection
# + STRING - YAML scalar string
public enum FailSafeSchema {
    MAPPING,
    SEQUENCE,
    STRING
}

# Represents the YAML schema available for the parser.
# 
# + FAILSAFE_SCHEMA - Generic schema that works for any YAML document
# + JSON_SCHEMA - Schema supports all the basic JSON types
# + CORE_SCHEMA - An extension of JSON schema that allows more human-readable presentation
public enum YAMLSchema {
    FAILSAFE_SCHEMA,
    JSON_SCHEMA,
    CORE_SCHEMA
}
