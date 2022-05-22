import yaml.common;
import yaml.parser;
import yaml.lexer;
import yaml.schema;

# Compose the sequence collection into Ballerina array.
#
# + state - Current composer state
# + flowStyle - If a collection is flow sequence
# + return - Constructed Ballerina array on success
function composeSequence(ComposerState state, boolean flowStyle) returns json[]|lexer:LexicalError|parser:ParsingError|ComposingError|schema:SchemaError {
    json[] sequence = [];
    common:Event event = check checkEvent(state);

    // Iterate until the end event is detected
    while true {
        if event is common:EndEvent {
            match event.endType {
                common:MAPPING => {
                    return generateExpectedEndEventError(state, event, {endType: common:SEQUENCE});
                }
                common:SEQUENCE => {
                    break;
                }
                common:DOCUMENT|common:STREAM => {
                    state.docTerminated = event.endType == common:DOCUMENT;
                    if !flowStyle {
                        break;
                    }
                    return generateExpectedEndEventError(state, event, {endType: common:SEQUENCE});
                }
            }
        }

        sequence.push(check composeNode(state, event));
        event = check checkEvent(state);
    }

    return sequence;
}

# Compose the mapping collection into Ballerina map.
#
# + state - Current composer state
# + flowStyle - If a collection is flow mapping
# + return - Constructed Ballerina array on success
function composeMapping(ComposerState state, boolean flowStyle) returns map<json>|lexer:LexicalError|parser:ParsingError|ComposingError|schema:SchemaError {
    map<json> structure = {};
    common:Event event = check checkEvent(state, parser:EXPECT_KEY);

    // Iterate until an end event is detected
    while true {
        if event is common:EndEvent {
            match event.endType {
                common:MAPPING => {
                    break;
                }
                common:SEQUENCE => {
                    return generateExpectedEndEventError(state, event, {endType: common:MAPPING});
                }
                common:DOCUMENT|common:STREAM => {
                    state.docTerminated = event.endType == common:DOCUMENT;
                    if !flowStyle {
                        break;
                    }
                    return generateExpectedEndEventError(state, event, {endType: common:MAPPING});
                }
            }
        }

        // Cannot have a nested block mapping if a value is assigned
        if event is common:StartEvent && !event.flowStyle {
            return generateComposeError(state, 
                "Cannot have nested mapping under a key-pair that is already assigned",
                event);
        }

        // Compose the key
        json key = check composeNode(state, event);

        // Compose the value
        event = check checkEvent(state, parser:EXPECT_VALUE);
        json value = check composeNode(state, event);

        // Map the key value pair
        structure[key.toString()] = value;
        event = check checkEvent(state, parser:EXPECT_KEY);
    }

    return structure;
}
