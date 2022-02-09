import ballerina/regex;

# Represenst an error caused by the lexical analyzer
type LexicalError distinct error;

enum RegexPattern {
    PRINTABLE_PATTERN = "\\x09\\x0a\\x0d\\x20-\\x7e\\x85\\xa0-\\xd7ff\\xe000-\\xfffd",
    JSON_PATTERN = "\\x09\\x20-\\xffff",
    BOM_PATTERN = "\\xfeff",
    DECIMAL_DIGIT_PATTERN = "0-9",
    HEXADECIMAL_DIGIT_PATTERN = "0-9a-fA-F",
    OCTAL_DIGIT_PATTERN = "0-7",
    BINARY_DIGIT_PATTERN = "0-1",
    LINE_BREAK_PATTERN = "\\x0a\\x0d",
    WORD_PATTERN = "a-zA-Z0-9\\-"
}

# Represents the state of the Lexer.
enum State {
    START,
    KEY
}

# Generates tokens based on the YAML lexemes  
class Lexer {
    # Properties to represent current position 
    int index = 0;
    int lineNumber = 0;

    # Line to be lexically analyzed
    string line = "";

    # Value of the generateed token
    string lexeme = "";

    # Current state of the Lexer
    State state = KEY;

    # Generates a Token for the next immediate lexeme.
    #
    # + return - If success, returns a token, else returns a Lexical Error 
    function getToken() returns Token|error {

        // Ignore comments from processing
        if (self.line[self.index] == "#") {
            return self.generateToken(EOL);
        }

        match self.state {
            START => {
                return check self.stateStart();
            }
            _ => {
                return self.generateError("Invalid state", self.index);
            }
        }

    }

    private function stateStart() returns Token|error {
        if (self.matchRegexPattern(BOM_PATTERN)) {
            return self.generateToken(BOM);
        }

        match self.line[self.index] {
            "&" => {
                return self.generateToken(ANCHOR);
            }
            "*" => {
                return self.generateToken(ALIAS);
            }
            "-" => {
                return self.generateToken(SEQUENCE_ENTRY);
            }
            "!" => {
                return self.generateToken(TAG);
            }
            "'" => { //TODO: Single-quoted flow scalar

            }
            "\"" => { //TODO: Double-quoted flow scalar

            }
            "%" => { // Directive line

            }
            "|" => { // Literal block scalar
                return self.generateToken(LITERAL);
            }
            ">" => { // Folded block scalar
                return self.generateToken(FOLDED);
            }
            "?" => {
                return self.generateToken(MAPPING_KEY);
            }
            ":" => {
                return self.generateToken(MAPPING_VALUE);
            }
            "," => {
                return self.generateToken(SEPARATOR);
            }
            "[" => {
                return self.generateToken(SEQUENCE_START);
            }
            "]" => {
                return self.generateToken(SEQUENCE_END);
            }
            "{" => {
                return self.generateToken(MAPPING_START);
            }
            "}" => {
                return self.generateToken(MAPPING_END);
            }
            "'" => {

            }

        }

        return self.generateError("Invalid character", self.index);
    }

    # Encapsulate a function to run isolatedly on the remaining characters.
    # Function lookaheads to capture the lexems for a targetted token.
    #
    # + process - Function to be executed on each iteration  
    # + successToken - Token to be returned on successful traverse of the characters
    # + message - Message to display if the end delimeter is not shown
    # + return - Lexical Error if available
    private function iterate(function (int) returns boolean|LexicalError process,
                            YAMLToken successToken,
                            string message = "") returns Token|LexicalError {

        // Iterate the given line to check the DFA
        foreach int i in self.index ... self.line.length() - 1 {
            if (check process(i)) {
                return self.generateToken(successToken);
            }
        }
        self.index = self.line.length() - 1;

        // If the lexer does not expect an end delimiter at EOL, returns the token. Else it an error.
        return message.length() == 0 ? self.generateToken(successToken) : self.generateError(message, self.index);
    }

    # Peeks the character succeeding after k indexes. 
    # Returns the character after k spots.
    #
    # + k - Number of characters to peek
    # + return - Character at the peek if not null  
    private function peek(int k) returns string? {
        return self.index + k < self.line.length() ? self.line[self.index + k] : ();
    }

    # Check if the given character matches the regex pattern.
    #
    # + inclusionPatterns - Included the regex patterns
    # + index - Index of the character. Default = self.index  
    # + exclusionPatterns - Exclude the regex pattenrs
    # + return - True if the pattern mathces
    private function matchRegexPattern(string|string[] inclusionPatterns, int? index = (), string|string[]? exclusionPatterns = ()) returns boolean {
        string inclusionPattern = "[" + self.concatenateStringArray(inclusionPatterns) + "]";
        string exclusionPattern = "";

        if (exclusionPatterns != ()) {
            exclusionPattern = "(?![" + self.concatenateStringArray(exclusionPatterns) + "])";
        }
        return regex:matches(self.line[index == () ? self.index : index], exclusionPattern + inclusionPattern + "{1}");
    }

    # Concatenate one or more strings.
    #
    # + strings - Strings to be concatenated
    # + return - Concatenated string
    function concatenateStringArray(string[]|string strings) returns string {
        if (strings is string) {
            return strings;
        }
        string output = "";
        strings.forEach(function(string line) {
            output += line;
        });
        return output;
    }

    # Check if the tokens adhere to the given string.
    #
    # + chars - Expected string  
    # + successToken - Output token if succeed
    # + return - If success, returns the token. Else, returns the parsing error.  
    private function tokensInSequence(string chars, YAMLToken successToken) returns Token|LexicalError {
        foreach string char in chars {
            if (!self.checkCharacter(char)) {
                return self.generateError(self.formatErrorMessage(self.index, successToken), self.index);
            }
            self.index += 1;
        }
        self.lexeme += chars;
        self.index -= 1;
        return self.generateToken(successToken);
    }

    # Assert the character of the current index
    #
    # + expectedCharacters - Expected characters at the current index  
    # + index - Index of the character. If null, takes the lexer's 
    # + return - True if the assertion is true. Else, an lexical error
    private function checkCharacter(string|string[] expectedCharacters, int? index = ()) returns boolean {
        if (expectedCharacters is string) {
            return expectedCharacters == self.line[index == () ? self.index : index];
        } else if (expectedCharacters.indexOf(self.line[index == () ? self.index : index]) == ()) {
            return false;
        }
        return true;
    }

    # Generate a lexical token.
    #
    # + token - TOML token
    # + return - Generated lexical token  
    private function generateToken(YAMLToken token) returns Token {
        self.index += 1;
        string lexemeBuffer = self.lexeme;
        self.lexeme = "";
        return {
            token: token,
            value: lexemeBuffer
        };
    }

    # Generates a Lexical Error.
    #
    # + message - Error message  
    # + index - Index where the Lexical error occurred
    # + return - Constructed Lexcial Error message
    private function generateError(string message, int index) returns LexicalError {
        string text = "Lexical Error at line "
                        + (self.lineNumber + 1).toString()
                        + " index "
                        + index.toString()
                        + ": "
                        + message
                        + ".";
        return error LexicalError(text);
    }

    # Generate the template error message "Invalid character '${char}' for a '${token}'"
    #
    # + index - Index of the character
    # + tokenName - Expected token name
    # + return - Generated error message
    private function formatErrorMessage(int index, YAMLToken tokenName) returns string {
        return "Invalid character '" + self.line[index] + "' for a '" + tokenName + "'";
    }
}
