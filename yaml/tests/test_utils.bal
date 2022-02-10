import ballerina/test;

const ORIGIN_FILE_PATH = "yaml/tests/resources/";

# Returns a new lexer with the configured line for testing
#
# + line - Testing TOML string  
# + lexerState - The state for the lexer to be initialized with
# + return - Configured lexer
function setLexerString(string line, State lexerState = LEXER_START) returns Lexer {
    Lexer lexer = new Lexer();
    lexer.line = line;
    lexer.state = lexerState;
    return lexer;
}

# Assert the token at the given index
#
# + lexer - Testing lexer  
# + assertingToken - Expected TOML token  
# + index - Index of the targetted token (default = 0) 
# + lexeme - Expected lexeme of the token (optional)
# + return - Returns an lexical error if unsuccessful
function assertToken(Lexer lexer, YAMLToken assertingToken, int index = 0, string lexeme = "") returns error? {
    Token token = check getToken(lexer, index);

    test:assertEquals(token.token, assertingToken);

    if (lexeme != "") {
        test:assertEquals(token.value, lexeme);
    }
}

# Assert if a lexical error is generated during the tokenization
#
# + tomlString - String to generate a Lexer token  
# + index - Index of the targetted token (defualt = 0)  
# + state - State of the lexer
function assertLexicalError(string tomlString, int index = 0, State state = LEXER_START) {
    Lexer lexer = setLexerString(tomlString, state);
    Token|error token = getToken(lexer, index);
    test:assertTrue(token is LexicalError);
}

# Obtian the token at the given index
#
# + lexer - Testing lexer
# + index - Index of the targetted token
# + return - If success, returns the token. Else a Lexical Error.  
function getToken(Lexer lexer, int index) returns Token|error {
    Token token;

    if (index == 0) {
        token = check lexer.getToken();
    } else {
        foreach int i in 0 ... index - 1 {
            token = check lexer.getToken();
        }
    }

    return token;
}
