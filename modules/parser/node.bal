import yaml.lexer;
import yaml.common;

function nodeTag(ParserState state) returns [string?, string?]|ParsingError|lexer:LexicalError {
    string? tagPrefix = ();
    string? tagHandle = ();
    match state.tokenBuffer.token {
        lexer:TAG => {
            check checkToken(state);
            tagPrefix = state.currentToken.value;
            check separate(state);
        }
        lexer:TAG_HANDLE => {
            check checkToken(state);
            tagHandle = state.currentToken.value;

            state.updateLexerContext(lexer:LEXER_TAG_NODE);
            check checkToken(state, lexer:TAG);
            tagPrefix = state.currentToken.value;
            check separate(state);
        }
    }
    return [tagHandle, tagPrefix];
}

function nodeAnchor(ParserState state) returns string?|ParsingError {
    string? anchor = ();
    if state.tokenBuffer.token == lexer:ANCHOR {
        check checkToken(state);
        anchor = state.currentToken.value;
        check separate(state);
    }
    return anchor;
}

# Description
#
# + state - Current parser state
# + option - Expected values inside a mapping collection  
# + definedProperties - Tag properties defined by the previous node
# + return - Constructed node with the properties and the value.
function nodeComplete(ParserState state, ParserOption option, TagStructure? definedProperties = ()) returns common:Event|ParsingError {
    TagStructure tagStructure = {};
    state.tagPropertiesInLine = true;

    match state.currentToken.token {
        lexer:TAG_HANDLE => {
            string tagHandle = state.currentToken.value;

            // Obtain the tagPrefix associated with the tag handle
            state.updateLexerContext(lexer:LEXER_TAG_NODE);
            check checkToken(state, lexer:TAG);
            string tagPrefix = state.currentToken.value;
            tagStructure.tag = check generateCompleteTagName(state, tagHandle, tagPrefix);

            // Check if there is a separate 
            check separate(state, true);

            // Obtain the anchor if there exists
            tagStructure.anchor = check nodeAnchor(state);
        }
        lexer:TAG => {
            // Obtain the tagPrefix name
            tagStructure.tag = state.currentToken.value;

            // There must be a separate after the tagPrefix
            check separate(state);

            // Obtain the anchor if there exists
            tagStructure.anchor = check nodeAnchor(state);
        }
        lexer:ANCHOR => {
            // Obtain the anchor name
            tagStructure.anchor = state.currentToken.value;

            // Check if there is a separate
            check separate(state);

            // Obtain the tag if there exists
            string? tagHandle;
            string? tagPrefix;
            [tagHandle, tagPrefix] = check nodeTag(state);

            // Construct the complete tag
            if tagPrefix != () {
                tagStructure.tag = tagHandle == () ? tagPrefix : check generateCompleteTagName(state, tagHandle, tagPrefix);
            }
        }
    }
    return appendData(state, option, tagStructure, false, definedProperties);
}

