import ballerina/regex;

enum RegexPattern {
    PRINTABLE_PATTERN = "\\x09\\x0a\\x0d\\x20-\\x7e\\x85\\xa0-\\ud7ff\\ue000-\\ufffd",
    JSON_PATTERN = "\\x09\\x20-\\uffff",
    BOM_PATTERN = "\\ufeff",
    DECIMAL_DIGIT_PATTERN = "0-9",
    HEXADECIMAL_DIGIT_PATTERN = "0-9a-fA-F",
    OCTAL_DIGIT_PATTERN = "0-7",
    BINARY_DIGIT_PATTERN = "0-1",
    LINE_BREAK_PATTERN = "\\x0a\\x0d",
    WORD_PATTERN = "a-zA-Z0-9\\-",
    FLOW_INDICATOR_PATTERN = "\\,\\[\\]\\{\\}",
    WHITESPACE_PATTERN = "\\s\\t",
    URI_CHAR_PATTERN = "#;/\\?:@&=\\+\\$,_\\.!~\\*'\\(\\)\\[\\]",
    INDICATOR_PATTERN = "\\-\\?:\\,\\[\\]\\{\\}#&\\*!\\|\\>\\'\\\"%@\\`"
}

# Represents the state of the Lexer.
enum State {
    LEXER_START,
    LEXER_TAG_HANDLE,
    LEXER_TAG_PREFIX,
    LEXER_TAG_NODE,
    LEXER_DIRECTIVE,
    LEXER_DOUBLE_QUOTE,
    LEXER_SINGLE_QUOTE,
    LEXER_BLOCK_HEADER,
    LEXER_LITERAL
}

# Represents the different contexts of the Lexer introduced in the YAML specification.
enum Context {
    BLOCK_IN,
    BLOCK_OUT,
    BLOCK_KEY,
    FLOW_IN,
    FLOW_OUT,
    FLOW_KEY
}

# Generates tokens based on the YAML lexemes  
class Lexer {
    # Properties to represent current position 
    int index = 0;
    int lineNumber = 0;

    # Line to be lexically analyzed
    string line = "";

    # Value of the generated token
    string lexeme = "";

    # Current state of the Lexer
    State state = LEXER_START;

    # Minimum indentation imposed by the parent nodes
    int[] seqIndents = [];
    int[] mapIndents = [];

    # Minimum indentation required to the current line
    int indent = -1;
    int keyIndent = 0;

    # Store the lexeme if it will be scanned again by the next token
    string lexemeBuffer = "";

    # Represents the current context of the parser
    Context context = BLOCK_OUT;

    # Flag is enabled after a JSON key is detected.
    # Used to generate mapping value even when it is possible to generate a planar scalar.
    boolean isJsonKey = false;

    # The lexer is currently processing trailing comments when the flag is set.
    boolean trailingComment = false;

    # When flag is set, updates the current indent to the indent of the first line
    boolean captureIndent = false;

    private map<string> escapedCharMap = {
        "0": "\u{00}",
        "a": "\u{07}",
        "b": "\u{08}",
        "t": "\t",
        "n": "\n",
        "v": "\u{0b}",
        "f": "\u{0c}",
        "r": "\r",
        "e": "\u{1b}",
        "\"": "\"",
        "/": "/",
        "\\": "\\",
        "N": "\u{85}",
        "_": "\u{a0}",
        "L": "\u{2028}",
        "P": "\u{2029}",
        " ": "\u{20}"
    };

    # Generates a Token for the next immediate lexeme.
    #
    # + return - If success, returns a token, else returns a Lexical Error 
    function getToken() returns Token|LexicalError {

        // Generate EOL token at the last index
        if (self.index >= self.line.length()) {
            return self.index == 0 ? self.generateToken(EMPTY_LINE) : {token: EOL};
        }

        if (self.matchRegexPattern(LINE_BREAK_PATTERN)) {
            return self.generateToken(LINE_BREAK);
        }

        match self.state {
            LEXER_START => {
                return self.stateStart();
            }
            LEXER_TAG_HANDLE => {
                return self.stateTagHandle();
            }
            LEXER_TAG_PREFIX => {
                return self.stateTagPrefix();
            }
            LEXER_TAG_NODE => {
                return self.stateTagNode();
            }
            LEXER_DIRECTIVE => {
                return self.stateYamlDirective();
            }
            LEXER_DOUBLE_QUOTE => {
                return self.stateDoubleQuote();
            }
            LEXER_SINGLE_QUOTE => {
                return self.stateSingleQuote();
            }
            LEXER_BLOCK_HEADER => {
                return self.stateBlockHeader();
            }
            LEXER_LITERAL => {
                return self.stateLiteral();
            }
            _ => {
                return self.generateError("Invalid state");
            }
        }

    }

    private function stateDoubleQuote() returns Token|LexicalError {
        // Check for empty lines
        if self.peek() == " " {
            Token token = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
            if self.peek() == () {
                return self.generateToken(EMPTY_LINE);
            }
            self.lexeme += token.value;
        }

        // Terminating delimiter
        if self.peek() == "\"" {
            return self.generateToken(DOUBLE_QUOTE_DELIMITER);
        }
        // Regular double quoted characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["\""]) {
            return self.iterate(self.scanDoubleQuoteChar, DOUBLE_QUOTE_CHAR);
        }

        return self.generateError(self.formatErrorMessage("double-quoted flow style"));
    }

    private function stateSingleQuote() returns Token|LexicalError {
        // Check for empty lines
        if self.peek() == " " {
            Token token = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
            if self.peek() == () {
                return self.generateToken(EMPTY_LINE);
            }
            self.lexeme += token.value;
        }

        // Escaped single quote
        if self.peek() == "'" && self.peek(1) == "'" {
            self.lexeme += "'";
            self.forward(2);
        }

        // Terminating delimiter
        if self.peek() == "'" {
            if self.lexeme.length() > 0 {
                self.index -= 1;
                return self.generateToken(SINGLE_QUOTE_CHAR);
            }
            return self.generateToken(SINGLE_QUOTE_DELIMITER);
        }

        // Regular single quoted characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["'"]) {
            return self.iterate(self.scanSingleQuotedChar, SINGLE_QUOTE_CHAR);
        }

        return self.generateError(self.formatErrorMessage("single-quoted flow style"));
    }

    private function stateYamlDirective() returns Token|LexicalError {
        // Ignore any comments
        if self.peek() == "#" {
            return self.generateToken(EOL);
        }

        // Check for decimal digits
        if (self.matchRegexPattern(DECIMAL_DIGIT_PATTERN)) {
            return self.iterate(self.scanDigit(DECIMAL_DIGIT_PATTERN), DECIMAL);
        }

        // Check for decimal point
        if self.peek() == "." {
            return self.generateToken(DOT);
        }

        return self.generateError(self.formatErrorMessage("version number"));
    }

    private function stateStart() returns Token|LexicalError {
        match self.peek() {
            " " => {
                // Return empty line if there is only whitespace
                // Else, return separation in line
                boolean isFirstChar = self.index == 0;
                Token token = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
                return (self.peek() == () && isFirstChar) ? self.generateToken(EMPTY_LINE) : token;
            }
            "#" => { // Ignore comments
                return self.generateToken(EOL);
            }
        }

        if (self.matchRegexPattern(BOM_PATTERN)) {
            return self.generateToken(BOM);
        }

        match self.peek() {
            "-" => {
                // Scan for directive marker
                if self.peek(1) == "-" && self.peek(2) == "-" {
                    self.forward(2);
                    return self.generateToken(DIRECTIVE_MARKER);
                }

                // Scan for planar characters
                if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN], 1) {
                    self.forward();
                    self.keyIndent = self.index;
                    self.lexeme += "-";
                    return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
                }

                // Return block sequence entry
                check self.checkIndent();
                return self.generateToken(SEQUENCE_ENTRY);
            }
            "." => {
                // Scan for directive marker
                if self.peek(1) == "." && self.peek(2) == "." {
                    self.forward(2);
                    return self.generateToken(DOCUMENT_MARKER);
                }

                // Scan for planar characters
                self.forward();
                self.keyIndent = self.index;
                self.lexeme += ".";
                return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
            }
            "*" => {
                LexicalError? err = check self.assertIndent(1);
                int startIndent = self.index;
                self.forward();
                Token token = check self.iterate(self.scanAnchorName, ALIAS);

                if err is LexicalError { // Not sufficient indent to process as a value token
                    if self.peek(1) == ":" { // The token is a mapping key
                        check self.checkIndent(startIndent);
                    }
                    return self.generateError("Invalid indentation");
                }
                return token;
            }
            "%" => { // Directive line
                self.forward();
                match self.peek() {
                    "T" => {
                        return check self.tokensInSequence("TAG", DIRECTIVE);
                    }
                    "Y" => {
                        return check self.tokensInSequence("YAML", DIRECTIVE);
                    }
                    _ => {
                        return self.generateError(self.formatErrorMessage(DIRECTIVE));
                    }
                }
            }
            "!" => { // Node tags
                check self.assertIndent(1);
                match self.peek(1) {
                    "<" => { // Verbatim tag
                        self.forward(2);

                        if self.peek() == "!" && self.peek(1) == ">" {
                            return self.generateError("'verbatim tag' are not resolved. Hence, '!' is invalid");
                        }

                        return self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN]) ?
                            self.iterate(self.scanURICharacter(true), TAG, true)
                            : self.generateError("Expected a 'uri-char' after '<' in a 'verbatim tag'");
                    }
                    " "|"\t"|() => { // Non-specific tag
                        self.lexeme = "!";
                        self.forward();
                        return self.generateToken(TAG);
                    }
                    "!" => { // Secondary tag handle 
                        self.lexeme = "!!";
                        self.forward();
                        return self.generateToken(TAG_HANDLE);
                    }
                    _ => { // Check for primary and name tag handles
                        self.lexeme = "!";
                        self.forward();

                        // Differentiate between primary and named tag
                        return self.iterate(self.scanTagHandle(true), TAG_HANDLE, true);
                    }
                }
            }
            "&" => {
                check self.assertIndent(1);
                self.forward();
                return self.iterate(self.scanAnchorName, ANCHOR);
            }
            ":" => {
                self.lexeme += ":";
                if !self.isJsonKey && self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN], 1) {
                    self.forward();
                    return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
                }
                return self.generateToken(MAPPING_VALUE);
            }
            "?" => {
                self.lexeme += "?";
                if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN], 1) {
                    self.forward();
                    return self.iterate(self.scanPlanarChar, PLANAR_CHAR);
                }
                return self.generateToken(MAPPING_KEY);
            }
            "\"" => { // Process double quote flow style value
                check self.assertIndent(1);
                self.keyIndent = self.index;
                return self.generateToken(DOUBLE_QUOTE_DELIMITER);
            }
            "'" => {
                check self.assertIndent(1);
                self.keyIndent = self.index;
                return self.generateToken(SINGLE_QUOTE_DELIMITER);
            }
            "," => {
                //TODO: only valid in flow sequence
                return self.generateToken(SEPARATOR);
            }
            "[" => {
                check self.assertIndent(1);
                return self.generateToken(SEQUENCE_START);
            }
            "]" => {
                return self.generateToken(SEQUENCE_END);
            }
            "{" => {
                check self.assertIndent(1);
                return self.generateToken(MAPPING_START);
            }
            "}" => {
                return self.generateToken(MAPPING_END);
            }
            "|"|">" => { // Block scalars
                self.indent += 1;
                self.captureIndent = true;
                return self.generateToken(self.peek() == "|" ? LITERAL : FOLDED);
            }
        }

        // Check for first character of planar scalar
        if self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN, INDICATOR_PATTERN]) {
            // TODO: repeat this strategy for double and single quoted strings
            LexicalError? err = self.assertIndent(1);
            int startIndent = self.index;
            Token token = check self.iterate(self.scanPlanarChar, PLANAR_CHAR);

            if err is LexicalError { // Not sufficient indent to process as a value token
                if self.peek() == ":" { // The token is a mapping key
                    check self.checkIndent(startIndent);
                    token.indentation = true;
                    return token;
                }
                return self.generateError("Invalid indentation");
            }
            if self.peek() == ":" {
                check self.checkIndent(startIndent);
            }
            return token;
        }

        return self.generateError(self.formatErrorMessage("document prefix"));
    }

    private function stateTagHandle() returns Token|LexicalError {
        // Ignore any comments
        if self.peek() == "#" {
            return self.generateToken(EOL);
        }

        // Check fo primary, secondary, and named tag handles
        if self.peek() == "!" {
            match self.peek(1) {
                " "|"\t" => { // Primary tag handle
                    self.lexeme = "!";
                    return self.generateToken(TAG_HANDLE);
                }
                "!" => { // Secondary tag handle
                    self.lexeme = "!!";
                    self.forward();
                    return self.generateToken(TAG_HANDLE);
                }
                () => {
                    return self.generateError(string `Expected a ${SEPARATION_IN_LINE} after primary tag handle`);
                }
                _ => { // Check for named tag handles
                    self.lexeme = "!";
                    self.forward();
                    return self.iterate(self.scanTagHandle(), TAG_HANDLE, true);
                }
            }
        }

        // Check for separation-in-space before the tag prefix
        if self.peek() == " " {
            return check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
        }

        return self.generateError("Expected '!' to start the tag handle");
    }

    # Perform scanning for tag prefixes.
    #
    # + return - The respective token on success. Else, an error.
    private function stateTagPrefix() returns Token|LexicalError {
        // Ignore any comments
        if self.peek() == "#" {
            return self.generateToken(EOL);
        }

        // Match the global tag prefix or local tag prefix
        if self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], exclusionPatterns = ["!", FLOW_INDICATOR_PATTERN])
        || self.peek() == "!" {
            return self.iterate(self.scanURICharacter(), TAG_PREFIX);
        }

        // Match the global prefix with hexadecimal value
        if self.peek() == "%" {
            check self.scanUnicodeEscapedCharacters("%", 2);
            self.forward();
            return self.iterate(self.scanURICharacter(), TAG_PREFIX);
        }

        // Check for tail separation-in-line
        if self.peek() == " " {
            return check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
        }

        return self.generateError(self.formatErrorMessage(TAG_PREFIX));
    }

    private function stateTagNode() returns Token|LexicalError {
        // Check the lexeme buffer for the lexeme stored by the primary tag
        if self.lexemeBuffer.length() > 0 {
            self.lexeme = self.lexemeBuffer;
            self.lexemeBuffer = "";

            // The complete primary tag is stored in the buffer
            if self.matchRegexPattern(WHITESPACE_PATTERN) {
                self.forward(-1);
                return self.generateToken(TAG);
            }

            // A first portion of the primary tag is stored in the buffer
            if self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], ["!", FLOW_INDICATOR_PATTERN]) {
                return self.iterate(self.scanTagCharacter, TAG);
            }

            return self.generateError(self.formatErrorMessage("primary tag"));
        }

        // Scan the anchor node
        if self.peek() == "&" {
            self.forward();
            return self.iterate(self.scanAnchorName, ANCHOR);
        }

        // Match the tag with the t ag character pattern
        if self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], exclusionPatterns = ["!", FLOW_INDICATOR_PATTERN]) {
            return self.iterate(self.scanTagCharacter, TAG);
        }

        // Match the global prefix with hexadecimal value
        if self.peek() == "%" {
            check self.scanUnicodeEscapedCharacters("%", 2);
            self.forward();
            return self.iterate(self.scanURICharacter(), TAG_PREFIX);
        }

        // Check for tail separation-in-line
        if self.peek() == " " {
            return check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
        }

        return self.generateError(self.formatErrorMessage(TAG));
    }

    private function stateBlockHeader() returns Token|LexicalError {
        // Check for indentation indicators and adjust the current indent
        if self.matchRegexPattern("1-9") {
            int indentationIndicator = <int>(check self.processTypeCastingError('int:fromString(<string>self.peek()))) - 1;
            self.indent += indentationIndicator;
            self.forward();
        }

        // If the indentation indicator is at the tail
        if (self.index >= self.line.length()) {
            return self.generateToken(EOL);
        }

        // Check for chomping indicators
        if self.checkCharacter(["+", "-"]) {
            self.lexeme = <string>self.peek();
            return self.generateToken(CHOMPING_INDICATOR);
        }

        return self.generateError(self.formatErrorMessage("<block-header>"));
    }

    private function stateLiteral() returns Token|LexicalError {
        // Check for comments in trailing comments
        if self.trailingComment {
            match self.peek() {
                " " => {
                    _ = check self.iterate(self.scanWhitespace, SEPARATION_IN_LINE);
                    match self.peek() {
                        "#" => { // New line comments are allowed in trailing comments
                            return self.generateToken(EOL);
                        }
                        () => { // Empty lines are allowed in trailing comments
                            return self.generateToken(EMPTY_LINE);
                        }
                        _ => { // Any other characters are not allowed
                            return self.generateError(self.formatErrorMessage(TRAILING_COMMENT));
                        }
                    }
                }
                "#" => { // New line comments are allowed in trailing comments
                    return self.generateToken(EOL);
                }
                _ => { // Any other characters are not allowed
                    return self.generateError(self.formatErrorMessage(TRAILING_COMMENT));
                }
            }
        }

        // There is no sufficient indent to consider printable characters
        if !self.scanIndent() {
            // Generate beginning of the trailing comment
            return self.peek() == "#" ? self.generateToken(TRAILING_COMMENT)
                //Other characters are not allowed when the indentation is less
                : self.generateError("Insufficient indent to process literal characters");
        }

        // Generate an empty lines that have less index.
        if (self.index >= self.line.length()) {
            return self.generateToken(EMPTY_LINE);
        }

        // Update the indent to the first line
        if self.captureIndent {
            int additionalIndent = 0;

            while self.peek() == " " {
                additionalIndent += 1;
                self.forward();
            }

            self.indent += additionalIndent;
            self.captureIndent = false;
        }

        // Scan printable character
        if self.matchRegexPattern(PRINTABLE_PATTERN, [BOM_PATTERN, LINE_BREAK_PATTERN]) {
            return self.iterate(self.scanPrintableChar, PRINTABLE_CHAR);
        }

        return self.generateError(self.formatErrorMessage(LITERAL));
    }

    # Scan lexemes for the escaped characters.
    # Adds the processed escaped character to the lexeme.
    #
    # + return - An error on failure
    private function scanEscapedCharacter() returns LexicalError? {
        string currentChar;

        // Process double escape character
        if (self.peek() == ()) {
            self.lexeme += "\\";
            return;
        } else {
            currentChar = <string>self.peek();
        }

        // Check for predefined escape characters
        if (self.escapedCharMap.hasKey(currentChar)) {
            self.lexeme += <string>self.escapedCharMap[currentChar];
            return;
        }

        // Check for unicode characters
        match currentChar {
            "x" => {
                check self.scanUnicodeEscapedCharacters("x", 2);
                return;
            }
            "u" => {
                check self.scanUnicodeEscapedCharacters("u", 4);
                return;
            }
            "U" => {
                check self.scanUnicodeEscapedCharacters("U", 8);
                return;
            }
        }
        return self.generateError(self.formatErrorMessage("escaped character"));
    }

    # Process the hex codes under the unicode escaped character.
    #
    # + escapedChar - Escaped character before the digits. Only used to present in the error message.
    # + length - Number of digits
    # + return - An error on failure
    private function scanUnicodeEscapedCharacters(string escapedChar, int length) returns LexicalError? {

        // Check if the required digits do not overflow the current line.
        if self.line.length() <= length + self.index {
            return self.generateError("Expected " + length.toString() + " characters for the '\\" + escapedChar + "' unicode escape");
        }

        string unicodeDigits = "";

        // Check if the digits adhere to the hexadecimal code pattern.
        foreach int i in 0 ... length - 1 {
            self.forward();
            if self.matchRegexPattern(HEXADECIMAL_DIGIT_PATTERN) {
                unicodeDigits += <string>self.peek();
                continue;
            }
            return self.generateError(self.formatErrorMessage("unicode hex escape"));
        }

        // Check if the lexeme can be converted to hexadecimal
        int|error hexResult = 'int:fromHexString(unicodeDigits);
        if hexResult is error {
            return self.generateError('error:message(hexResult));
        }

        // Check if there exists a unicode string for the hexadecimal value
        string|error unicodeResult = 'string:fromCodePointInt(hexResult);
        if unicodeResult is error {
            return self.generateError('error:message(unicodeResult));
        }

        self.lexeme += unicodeResult;
    }

    # Process double quoted scalar values.
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanDoubleQuoteChar() returns boolean|LexicalError {
        // Process nb-json characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["\\\\", "\""]) {
            self.lexeme += <string>self.peek();
            return false;
        }

        // Process escaped characters
        if (self.peek() == "\\") {
            self.forward();
            check self.scanEscapedCharacter();
            return false;
        }

        // Terminate when delimiter is found
        if self.peek() == "\"" {
            return true;
        }

        return self.generateError(self.formatErrorMessage(DOUBLE_QUOTE_CHAR));
    }

    # Process double quoted scalar values.
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanSingleQuotedChar() returns boolean|LexicalError {
        // Process nb-json characters
        if self.matchRegexPattern(JSON_PATTERN, exclusionPatterns = ["'"]) {
            self.lexeme += <string>self.peek();
            return false;
        }

        // Terminate when the delimiter is found
        if self.peek() == "'" {
            if self.peek(1) == "'" {
                self.lexeme += "'";
                self.forward();
                return false;
            }
            return true;
        }

        return self.generateError(self.formatErrorMessage(SINGLE_QUOTE_CHAR));
    }

    private function scanPlanarChar() returns boolean|LexicalError {
        // Store the whitespace before a ns-planar char
        string whitespace = "";
        int numWhitespace = 0;
        while self.peek() == "\t" || self.peek() == " " {
            whitespace += <string>self.peek();
            numWhitespace += 1;
            self.forward();
        }

        // Step back from the white spaces if EOL or ':' is reached 
        if self.peek() == () {
            self.forward(-numWhitespace);
            return true;
        }

        // Process ns-plain-safe character
        if self.matchRegexPattern([PRINTABLE_PATTERN], self.context == FLOW_KEY || self.context == FLOW_IN ?
        [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN, FLOW_INDICATOR_PATTERN, "#", ":"]
        : [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN, "#", ":"]) {
            self.lexeme += whitespace + <string>self.peek();
            return false;
        }

        // Check for comments with a space before it
        if self.peek() == "#" {
            if self.peek(-1) == " " {
                self.forward(-numWhitespace);
                return true;
            }
            self.lexeme += whitespace + "#";
            return false;
        }

        // Check for mapping value with a space after it 
        if self.peek() == ":" {
            if !self.matchRegexPattern([PRINTABLE_PATTERN], self.context == FLOW_KEY || self.context == FLOW_IN ?
                [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN, FLOW_INDICATOR_PATTERN]
                : [LINE_BREAK_PATTERN, BOM_PATTERN, WHITESPACE_PATTERN], 1) {
                self.forward(-numWhitespace);
                return true;
            }
            self.lexeme += whitespace + ":";
            return false;
        }

        // If the whitespace is at the trail, discard it from the planar chars
        if numWhitespace > 0 {
            self.forward(-numWhitespace);
            return true;
        }

        if self.checkCharacter(["}", "]"]) {
            return true;
        }

        //TODO: consider the actions for incorrect planar char
        return self.generateError(self.formatErrorMessage(PLANAR_CHAR));
    }

    private function scanPrintableChar() returns boolean|LexicalError {
        if self.matchRegexPattern(PRINTABLE_PATTERN, [BOM_PATTERN, LINE_BREAK_PATTERN]) {
            self.lexeme += <string>self.peek();
            return false;
        }

        return true;
    }

    # Scan the lexeme for tag characters.
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanTagCharacter() returns boolean|LexicalError {
        // Check for URI character
        if self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], ["!", FLOW_INDICATOR_PATTERN]) {
            self.lexeme += <string>self.peek();
            return false;
        }

        if self.matchRegexPattern(WHITESPACE_PATTERN) {
            return true;
        }

        // Process the hexadecimal values after '%'
        if self.peek() == "%" {
            check self.scanUnicodeEscapedCharacters("%", 2);
            return false;
        }

        return self.generateError(self.formatErrorMessage(TAG));
    }

    # Scan the lexeme for URI characters
    #
    # + isVerbatim - If set, terminates when ">" is detected.
    # + return - Generates a function to scan the URI characters.
    private function scanURICharacter(boolean isVerbatim = false) returns function () returns boolean|LexicalError {
        return function() returns boolean|LexicalError {
            // Check for URI characters
            if (self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN])) {
                self.lexeme += <string>self.peek();
                return false;
            }

            // Process the hexadecimal values after '%'
            if self.peek() == "%" {
                check self.scanUnicodeEscapedCharacters("%", 2);
                return false;
            }

            // Ignore the comments
            if self.matchRegexPattern([LINE_BREAK_PATTERN, WHITESPACE_PATTERN]) {
                return true;
            }

            // Terminate when '>' is detected for a verbatim tag
            if isVerbatim && self.peek() == ">" {
                return true;
            }

            return self.generateError(self.formatErrorMessage("URI character"));
        };
    }

    # Scan the lexeme for named tag handle.
    #
    # + differentiate - If set, the function handles to differentiate between named and primary tags.
    # + return - Generates a function to scan the lexeme of a named or primary tag handle.
    private function scanTagHandle(boolean differentiate = false) returns function () returns boolean|LexicalError {
        return function() returns boolean|LexicalError {
            // Scan the word of the name tag.
            if (self.matchRegexPattern(WORD_PATTERN)) {
                self.lexeme += <string>self.peek();
                return false;
            }

            // Scan the end delimiter of the tag.
            if self.peek() == "!" {
                self.lexeme += "!";
                return true;
            }

            // If the tag handle contains non-word character before '!', 
            // Then the tag is primary
            if differentiate && self.matchRegexPattern([URI_CHAR_PATTERN, WORD_PATTERN], FLOW_INDICATOR_PATTERN) {
                self.lexemeBuffer = self.lexeme.substring(1) + <string>self.peek();
                self.lexeme = "!";
                return true;
            }

            // If the tag handle contains a hexadecimal escape,
            // Then the tag is primary
            if differentiate && self.peek() == "%" {
                check self.scanUnicodeEscapedCharacters("%", 2);
                self.lexemeBuffer = self.lexeme.substring(1);
                self.lexeme = "!";
                return true;
            }

            // Store the complete primary tag if a white space is detected
            if differentiate && self.matchRegexPattern(WHITESPACE_PATTERN) {
                self.forward(-1);
                self.lexemeBuffer = self.lexeme.substring(1);
                self.lexeme = "!";
                return true;
            }

            return self.generateError(self.formatErrorMessage(TAG_HANDLE));
        };
    }

    # Scan the lexeme for the anchor name.
    #
    # + return - False to continue. True to terminate the token. An error on failure.
    private function scanAnchorName() returns boolean|LexicalError {
        if (self.matchRegexPattern([PRINTABLE_PATTERN], [LINE_BREAK_PATTERN, BOM_PATTERN, FLOW_INDICATOR_PATTERN, WHITESPACE_PATTERN])) {
            self.lexeme += <string>self.peek();
            return false;
        }
        return true;
    }

    # Scan the white spaces for a line-in-separation.
    #
    # + return - False to continue. True to terminate the token.
    private function scanWhitespace() returns boolean {
        if self.peek() == " " {
            self.lexeme += " ";
            return false;
        }
        return true;
    }

    # Scan the whitespace to build an indent.
    #
    # + return - Returns true if there are sufficient whitespace to build the indent.
    private function scanIndent() returns boolean {
        foreach int i in 0 ... self.indent {
            if !(self.peek() == " ") {
                return false;
            }
            self.forward();
        }
        return true;
    }

    # Validates the indentation of block collections.
    # Increments and decrement the indentation safely.
    # If the indent is explicitly given, then the function continues for mappings.
    #
    # + mapIndex - If the current token is a mapping key, then the starting index of it.
    # + return - An indentation error on failure
    public function checkIndent(int? mapIndex = ()) returns LexicalError? {
        int startIndex = mapIndex == () ? self.index : mapIndex;
        int[] indents = mapIndex == () ? self.seqIndents : self.mapIndents;

        if self.indent == startIndex {
            return;
        }

        if self.indent < startIndex {
            indents.push(startIndex);
            if mapIndex == () {
                self.lexeme = "+";
            }
            self.indent = startIndex;
            return;
        }

        int decrease = 0;
        while self.indent > startIndex {
            self.indent = indents.pop();
            decrease += 1;
        }

        if self.indent == startIndex {
            indents.push(self.indent);
            if mapIndex == () {
                self.lexeme = "-" + (decrease - 1).toString();
            }
            return;
        }

        return self.generateError("Invalid indentation");
    }

    private function assertIndent(int offset = 0) returns LexicalError? {
        if self.index < self.indent + offset {
            return self.generateError("Invalid indentation");
        }
    }

    # Check for the lexemes to crete an DECIMAL token.
    #
    # + digitPattern - Regex pattern of the number system
    # + return - Generates a function which checks the lexemes for the given number system.  
    private function scanDigit(string digitPattern) returns function () returns boolean|LexicalError {
        return function() returns boolean|LexicalError {
            if (self.matchRegexPattern(digitPattern)) {
                self.lexeme += <string>self.peek();
                return false;
            }
            return true;
        };
    }

    # Encapsulate a function to run isolated on the remaining characters.
    # Function lookahead to capture the lexemes for a targeted token.
    #
    # + process - Function to be executed on each iteration  
    # + successToken - Token to be returned on successful traverse of the characters  
    # + message - Message to display if the end delimiter is not shown  
    # + include - True when the last char belongs to the token
    # + return - Lexical Error if available
    private function iterate(function () returns boolean|LexicalError process,
                            YAMLToken successToken,
                            boolean include = false,
                            string message = "") returns Token|LexicalError {

        // Iterate the given line to check the DFA
        while self.index < self.line.length() {
            if (check process()) {
                self.index = include ? self.index : self.index - 1;
                return self.generateToken(successToken);
            }
            self.forward();
        }
        self.index = self.line.length() - 1;

        // If the lexer does not expect an end delimiter at EOL, returns the token. Else it an error.
        return message.length() == 0 ? self.generateToken(successToken) : self.generateError(message);
    }

    # Peeks the character succeeding after k indexes. 
    # Returns the character after k spots.
    #
    # + k - Number of characters to peek. Default = 0
    # + return - Character at the peek if not null  
    private function peek(int k = 0) returns string? {
        return self.index + k < self.line.length() ? self.line[self.index + k] : ();
    }

    # Increment the index of the column by k indexes
    #
    # + k - Number of indexes to forward. Default = 1
    private function forward(int k = 1) {
        if (self.index + k <= self.line.length()) {
            self.index += k;
        }
    }

    # Check if the given character matches the regex pattern.
    #
    # + inclusionPatterns - Included the regex patterns
    # + offset - Offset of the character from the current index. Default = 0  
    # + exclusionPatterns - Exclude the regex patterns
    # + return - True if the pattern matches
    private function matchRegexPattern(string|string[] inclusionPatterns, string|string[]? exclusionPatterns = (), int offset = 0) returns boolean {
        // If there is no character to check the pattern, then return false.
        if self.peek(offset) == () {
            return false;
        }

        string inclusionPattern = "[" + self.concatenateStringArray(inclusionPatterns) + "]";
        string exclusionPattern = "";

        if (exclusionPatterns != ()) {
            exclusionPattern = "(?![" + self.concatenateStringArray(exclusionPatterns) + "])";
        }
        return regex:matches(self.line[self.index + offset], exclusionPattern + inclusionPattern + "{1}");
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
            // The expected character is not found
            if (self.peek() == () || !self.checkCharacter(char)) {
                return self.generateError(string `Expected '${char}' for ${successToken}`);
            }
            self.forward();
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
        self.forward();
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
    # + return - Constructed Lexical Error message
    private function generateError(string message) returns LexicalError {
        string text = "Lexical Error at line "
                        + (self.lineNumber + 1).toString()
                        + " index "
                        + self.index.toString()
                        + ": "
                        + message
                        + ".";
        return error LexicalError(text);
    }

    # Check errors during type casting to Ballerina types.
    #
    # + value - Value to be type casted.
    # + return - Value as a Ballerina data type  
    private function processTypeCastingError(anydata|error value) returns anydata|LexicalError {
        // Check if the type casting has any errors
        if value is error {
            return self.generateError("Invalid value for assignment");
        }

        // Returns the value on success
        return value;
    }

    # Generate the template error message "Invalid character '${char}' for a '${token}'"
    #
    # + value - Expected token name or the value
    # + return - Generated error message
    private function formatErrorMessage(YAMLToken|string value) returns string {
        return "Invalid character '" + <string>self.peek() + "' for a '" + <string>value + "'";
    }
}
