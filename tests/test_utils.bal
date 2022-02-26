import ballerina/test;

const ORIGIN_FILE_PATH = "tests/resources/";

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
# + index - Index of the targeted token (default = 0) 
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
# + yamlString - String to generate a Lexer token  
# + index - Index of the targeted token (default = 0)  
# + state - State of the lexer
function assertLexicalError(string yamlString, int index = 0, State state = LEXER_START) {
    Lexer lexer = setLexerString(yamlString, state);
    Token|error token = getToken(lexer, index);
    test:assertTrue(token is LexicalError);
}

# Obtain the token at the given index
#
# + lexer - Testing lexer
# + index - Index of the targeted token
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

function assertParsingEvent(string|string[] lines, string value) returns error?{
    Parser parser = new Parser((lines is string) ? [lines] : lines);
    Event event = check parser.parse();
    test:assertEquals((<ScalarEvent>event).value, value);
}

# Assert if an parsing error is generated during the parsing
#
# + lines - Lines to be parsed.
# + isLexical - If set, checks for Lexical errors. Else, checks for Parsing errors.
function assertParsingError(string|string[] lines, boolean isLexical = false) {
    Parser parser = new Parser((lines is string) ? [lines] : lines);
    Event|error err = parser.parse();

    if (isLexical) {
        test:assertTrue(err is LexicalError);
    } else {
        test:assertTrue(err is ParsingError);
    }

}