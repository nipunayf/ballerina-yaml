import yaml.lexer;
import yaml.event;

# Generates an event my combining to map<json> objects.
#
# + state - Current parser state
# + m1 - The first map structure
# + m2 - The second map structure
# + return - The constructed event after combined.
function constructEvent(ParserState state, map<json> m1, map<json>? m2 = ()) returns event:Event|ParsingError {
    map<json> returnMap = m1.clone();

    if m2 != () {
        m2.keys().forEach(function(string key) {
            returnMap[key] = m2[key];
        });
    }

    error|event:Event processedMap = returnMap.cloneWithType(event:Event);

    return processedMap is event:Event ? processedMap : generateError(state, 'error:message(processedMap));
}

# Trims the trailing whitespace of a string.
#
# + value - String to be trimmed
# + return - Trimmed string
function trimTailWhitespace(string value) returns string {
    int i = value.length() - 1;

    if i < 0 {
        return "";
    }

    while value[i] == " " || value[i] == "\t" {
        if i < 1 {
            break;
        }
        i -= 1;
    }

    return value.substring(0, i + 1);
}

# Trims the leading whitespace of a string.
#
# + value - String to be trimmed
# + return - Trimmed string
function trimHeadWhitespace(string value) returns string {
    int len = value.length();

    if len < 1 {
        return "";
    }

    int i = 0;
    while value[i] == " " || value == "\t" {
        if i == len - 1 {
            break;
        }
        i += 1;
    }

    return value.substring(i);
}

# Assert the next lexer token with the predicted token.
# If no token is provided, then the next token is retrieved without an error checking.
# Hence, the error checking must be done explicitly.
#
# + state - Current parser state
# + expectedTokens - Predicted token or tokens  
# + customMessage - Error message to be displayed if the expected token not found  
# + peek - Stores the token in the buffer
# + return - Parsing error if not found
function checkToken(ParserState state, lexer:YAMLToken|lexer:YAMLToken[] expectedTokens = lexer:DUMMY, string customMessage = "", boolean peek = false) returns (lexer:LexicalError|ParsingError)? {
    lexer:Token token;

    // Obtain a token form the lexer if there is none in the buffer.
    if state.tokenBuffer.token == lexer:DUMMY {
        state.prevToken = state.currentToken.token;
        state.lexerState = check lexer:scan(state.lexerState);
        token = state.lexerState.getToken();
    } else {
        token = state.tokenBuffer;
        state.tokenBuffer = {token: lexer:DUMMY};
    }

    // Add the token to the tokenBuffer if the peek flag is set.
    if peek {
        state.tokenBuffer = token;
    } else {
        state.currentToken = token;
    }

    // Bypass error handling.
    if (expectedTokens == lexer:DUMMY) {
        return;
    }

    // Automatically generates a template error message if there is no custom message.
    string errorMessage = customMessage.length() == 0
                                ? formatExpectErrorMessage(state.currentToken.token, expectedTokens, state.prevToken)
                                : customMessage;

    // Generate an error if the expected token differ from the actual token.
    if (expectedTokens is lexer:YAMLToken) {
        if (token.token != expectedTokens) {
            return generateError(state, errorMessage);
        }
    } else {
        if (expectedTokens.indexOf(token.token) == ()) {
            return generateError(state, errorMessage);
        }
    }
}

# Check errors during type casting to Ballerina types.
#
# + state - Current parser state
# + value - Value to be type casted.
# + return - Value as a Ballerina data type  
function processTypeCastingError(ParserState state, json|error value) returns json|ParsingError {
    // Check if the type casting has any errors
    if value is error {
        return generateError(state, "Invalid value for assignment");
    }

    // Returns the value on success
    return value;
}

# Check if the given key adheres to either a explicit or a implicit key.
#
# + state - Current parser state  
# + isSingleLine - If the scalar only spanned for one line.
# + return - An error on invalid key.
function verifyKey(ParserState state, boolean isSingleLine) returns lexer:LexicalError|ParsingError|() {
    // Explicit keys can span multiple lines. 
    if state.explicitKey {
        return;
    }

    // Regular keys can only exist within one line
    state.updateLexerContext(lexer:LEXER_START);
    check checkToken(state, peek = true);
    if state.tokenBuffer.token == lexer:MAPPING_VALUE && !isSingleLine {
        return generateError(state, "Single-quoted keys cannot span multiple lines");
    }
}

function generateCompleteTagName(ParserState state, string tagHandle, string tagPrefix) returns string|ParsingError {
    string tagHandleName;

    // Check if the tag handle is defined in the map
    if state.customTagHandles.hasKey(tagHandle) {
        tagHandleName = state.customTagHandles.get(tagHandle);
    } else {
        if state.defaultTagHandles.hasKey(tagHandle) {
            tagHandleName = state.defaultTagHandles.get(tagHandle);
        }
        else {
            return generateError(state, string `'${tagHandle}' tag handle is not defined`);
        }
    }

    return tagHandleName + tagPrefix;
}
