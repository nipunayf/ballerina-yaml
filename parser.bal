# Parses the TOML document using the lexer
class Parser {
    # Properties for the TOML lines
    private string[] lines;
    private int numLines;
    private int lineIndex = -1;

    # Current token
    private Token currentToken = {token: DUMMY};

    # Previous YAML token
    private YAMLToken prevToken = DUMMY;

    # Used to store the token after peeked.
    # Used later when the checkToken method is invoked.
    private Token tokenBuffer = {token: DUMMY};

    # Hold the lexemes until the final value is generated
    private string lexemeBuffer = "";

    # Lexical analyzer tool for getting the tokens
    Lexer lexer = new Lexer();

    # Flag is set if an empty node is possible to expect
    private boolean expectEmptyNode = false;
    private boolean sequenceEntry = false;

    map<string> tagHandles = {};

    # YAML version of the document.
    string? yamlVersion = ();

    private Event[] eventBuffer = [];

    function init(string[] lines) returns ParsingError? {
        self.lines = lines;
        self.numLines = lines.length();
        check self.initLexer();
    }

    # Parse the initialized array of strings
    #
    # + return - Lexical or parsing error on failure
    public function parse() returns Event|LexicalError|ParsingError {
        // Empty the event buffer before getting new tokens
        if self.eventBuffer.length() > 0 {
            Event event = self.eventBuffer.remove(0);
            return event;
        }

        self.lexer.state = LEXER_START;
        check self.checkToken();

        // Ignore the whitespace at the head
        if self.currentToken.token == SEPARATION_IN_LINE {
            check self.checkToken();
        }

        match self.currentToken.token {
            EOL|EMPTY_LINE => {
                // if self.expectEmptyNode {
                //     self.expectEmptyNode = false;
                //     return {
                //         value: ()
                //     }
                // }

                if self.lineIndex >= self.numLines - 1 {
                    return {
                        endType: STREAM
                    };
                }
                check self.initLexer();
                return self.parse();
            }
            DIRECTIVE => {
                if (self.currentToken.value == "YAML") { // YAML directive
                    check self.yamlDirective();
                    check self.checkToken([SEPARATION_IN_LINE, EOL]);
                } else { // TAG directive
                    check self.tagDirective();
                    check self.checkToken([SEPARATION_IN_LINE, EOL]);
                }
                check self.initLexer();
                return check self.parse();
            }
            DIRECTIVE_MARKER => {
                return {
                    docVersion: self.yamlVersion == () ? "1.2.2" : <string>self.yamlVersion,
                    tags: self.tagHandles
                };
            }
            DOUBLE_QUOTE_DELIMITER|SINGLE_QUOTE_DELIMITER|PLANAR_CHAR => {
                return self.appendData(peeked = true);
            }
            ALIAS => {
                string alias = self.currentToken.value;
                return {
                    alias
                };
            }
            TAG_HANDLE => {
                string tagHandle = self.currentToken.value;

                // Obtain the tag associated with the tag handle
                self.lexer.state = LEXER_TAG_NODE;
                check self.checkToken(TAG);
                string tag = self.currentToken.value;

                // Check if there is a separate 
                check self.separate();

                // Obtain the anchor value if there exists
                string? anchor = ();
                if self.tokenBuffer.token == ANCHOR {
                    check self.checkToken();
                    anchor = self.currentToken.value;
                    check self.separate();
                }

                return self.appendData({tag, tagHandle, anchor});
            }
            TAG => {
                // Obtain the tag name
                string tag = self.currentToken.value;

                // Check fi there is a separate
                check self.separate();

                // Obtain the anchor if there exists
                string? anchor = ();
                if self.tokenBuffer.token == ANCHOR {
                    check self.checkToken();
                    anchor = self.currentToken.value;
                    check self.separate();
                }

                return self.appendData({tag, anchor});
            }
            ANCHOR => {
                // Obtain the anchor name
                string anchor = self.currentToken.value;

                // Check if there is a separate
                check self.separate();

                // Obtain the tag if there exists
                string? tag = ();
                string? tagHandle = ();
                match self.tokenBuffer.token {
                    TAG => {
                        check self.checkToken();
                        tag = self.currentToken.value;
                        check self.separate();
                    }
                    TAG_HANDLE => {
                        check self.checkToken();
                        tagHandle = self.currentToken.value;

                        self.lexer.state = LEXER_TAG_NODE;
                        check self.checkToken(TAG);
                        tag = self.currentToken.value;
                        check self.separate();
                    }
                }

                return self.appendData({tagHandle, tag, anchor});
            }
            MAPPING_VALUE => { // Empty node as the key
                check self.separate();
                return {
                    value: (),
                    isKey: true
                };
            }
            MAPPING_KEY => { // Explicit key
                check self.separate();
                return self.appendData();
            }
            SEQUENCE_ENTRY => {
                match self.currentToken.value {
                    "+" => {
                        return {startType: SEQUENCE};
                    }
                    "" => {
                        self.sequenceEntry = true;
                        return self.parse();
                    }
                    _ => {
                        if self.currentToken.value[0] != "-" {
                            return self.generateError("Invalid <sequence-entry> token");
                        }
                        int decrease = <int>(check self.processTypeCastingError('int:fromString(self.currentToken.value.substring(1))));
                        if decrease < 1 {
                            return self.generateError("Invalid <sequence-entry> token");
                        }
                        if decrease > 1 {
                            foreach int i in 2 ... decrease {
                                self.eventBuffer.push({endType: SEQUENCE});
                            }
                        }
                        return {endType: SEQUENCE};
                    }
                }
            }
            MAPPING_START => {
                return {startType: MAPPING};
            }
            SEQUENCE_START => {
                return {startType: SEQUENCE, flowStyle: true};
            }
            DOCUMENT_MARKER => {
                return {endType: DOCUMENT};
            }
            SEQUENCE_END => {
                return {endType: SEQUENCE};
            }
            MAPPING_END => {
                return {endType: MAPPING};
            }
            LITERAL|FOLDED => {
                self.lexer.state = LEXER_LITERAL;
                string value = check self.blockScalar(self.currentToken.token == FOLDED);
                return {value};
            }
        }
        return self.generateError(string `Invalid token '${self.currentToken.token}' as the first for generating an event`);
    }

    # Check the grammar productions for TAG directives.
    # Update the tag handles map.
    #
    # + return - An error on mismatch.
    private function tagDirective() returns (LexicalError|ParsingError)? {
        // Expect a separate in line
        check self.checkToken(SEPARATION_IN_LINE);

        // Expect a tag handle
        self.lexer.state = LEXER_TAG_HANDLE;
        check self.checkToken(TAG_HANDLE);
        string tagHandle = self.currentToken.value;
        check self.checkToken(SEPARATION_IN_LINE);

        // Expect a tag prefix
        self.lexer.state = LEXER_TAG_PREFIX;
        check self.checkToken(TAG_PREFIX);
        string tagPrefix = self.currentToken.value;

        if (self.tagHandles.hasKey(tagHandle)) {
            return self.generateError(check self.formatErrorMessage(2, value = tagHandle));
        }
        self.tagHandles[tagHandle] = tagPrefix;
    }

    # Check the grammar productions for YAML directives.
    # Update the yamlVersion of the document.
    #
    # + return - An error on mismatch.
    private function yamlDirective() returns LexicalError|ParsingError|() {
        // Expect a separate in line.
        check self.checkToken(SEPARATION_IN_LINE);

        self.lexer.state = LEXER_DIRECTIVE;

        // Expect yaml version
        check self.checkToken(DECIMAL, true);
        check self.checkToken(DOT);
        self.lexemeBuffer += ".";
        check self.checkToken(DECIMAL, true);

        // Update the version
        if (self.yamlVersion is null) {
            self.yamlVersion = self.lexemeBuffer;
            self.lexemeBuffer = "";
            return;
        }

        return self.generateError(check self.formatErrorMessage(2, value = "%YAML"));
    }

    private function doubleQuoteScalar() returns LexicalError|ParsingError|string {
        self.lexer.state = LEXER_DOUBLE_QUOTE;
        string lexemeBuffer = "";
        boolean isFirstLine = true;
        boolean emptyLine = false;
        boolean escaped = false;

        check self.checkToken();

        // Iterate the content until the delimiter is found
        while (self.currentToken.token != DOUBLE_QUOTE_DELIMITER) {
            match self.currentToken.token {
                DOUBLE_QUOTE_CHAR => { // Regular double quoted string char
                    string lexeme = self.currentToken.value;

                    // Check for double escaped character
                    if lexeme.length() > 0 && lexeme[lexeme.length() - 1] == "\\" {
                        lexeme = lexeme.substring(0, lexeme.length() - 2);
                        escaped = true;
                    }

                    else if !isFirstLine {
                        if escaped {
                            escaped = false;
                        } else { // Trim the white space if not escaped
                            lexemeBuffer = self.trimTailWhitespace(lexemeBuffer);
                        }

                        if emptyLine {
                            emptyLine = false;
                        } else { // Add a white space if there are not preceding empty lines
                            lexemeBuffer += " ";
                        }
                    }

                    lexemeBuffer += lexeme;
                }
                EOL => { // Processing new lines
                    if !escaped { // If not escaped, trim the trailing white spaces
                        lexemeBuffer = self.trimTailWhitespace(lexemeBuffer);
                    }
                    isFirstLine = false;
                    check self.initLexer("Expected to end the multi-line double string");
                }
                EMPTY_LINE => {
                    if isFirstLine { // Whitespace is preserved on the first line
                        lexemeBuffer += self.currentToken.value;
                        isFirstLine = false;
                    } else if escaped { // Whitespace is preserved when escaped
                        lexemeBuffer += self.currentToken.value + "\n";
                    } else { // Whitespace is ignored when line folding
                        lexemeBuffer = self.trimTailWhitespace(lexemeBuffer);
                        lexemeBuffer += "\n";
                    }
                    emptyLine = true;
                    check self.initLexer("Expected to end the multi-line double quoted scalar");
                }
                _ => {
                    return self.generateError(string `Invalid character '${self.currentToken.token}' inside the double quote`);
                }
            }
            check self.checkToken();
        }

        return lexemeBuffer;
    }

    private function singleQuoteScalar() returns ParsingError|LexicalError|string {
        self.lexer.state = LEXER_SINGLE_QUOTE;
        string lexemeBuffer = "";
        boolean isFirstLine = true;
        boolean emptyLine = false;

        check self.checkToken();

        // Iterate the content until the delimiter is found
        while self.currentToken.token != SINGLE_QUOTE_DELIMITER {
            match self.currentToken.token {
                SINGLE_QUOTE_CHAR => {
                    string lexeme = self.currentToken.value;

                    if isFirstLine {
                        lexemeBuffer += lexeme;
                    } else {
                        if emptyLine {
                            emptyLine = false;
                        } else { // Add a white space if there are not preceding empty lines
                            lexemeBuffer += " ";
                        }
                        lexemeBuffer += self.trimHeadWhitespace(lexeme);
                    }
                }
                EOL => {
                    // Trim trailing white spaces
                    lexemeBuffer = self.trimTailWhitespace(lexemeBuffer);
                    isFirstLine = false;
                    check self.initLexer("Expected to end the multi-line double string");
                }
                EMPTY_LINE => {
                    if isFirstLine { // Whitespace is preserved on the first line
                        lexemeBuffer += self.currentToken.value;
                        isFirstLine = false;
                    } else { // Whitespace is ignored when line folding
                        lexemeBuffer = self.trimTailWhitespace(lexemeBuffer);
                        lexemeBuffer += "\n";
                    }
                    emptyLine = true;
                    check self.initLexer("Expected to end the multi-line double quoted scalar");
                }
                _ => {
                    return self.generateError("Expected to end the multi-line single quoted scalar");
                }
            }
            check self.checkToken();
        }

        return lexemeBuffer;
    }

    private function planarScalar() returns ParsingError|LexicalError|string {
        // Process the first planar char
        string lexemeBuffer = self.currentToken.value;
        boolean emptyLine = false;

        check self.checkToken(peek = true);

        // Iterate the content until an invalid token is found
        while true {
            match self.tokenBuffer.token {
                PLANAR_CHAR => {
                    if self.tokenBuffer.indentation {
                        break;
                    }
                    check self.checkToken();
                    if emptyLine {
                        emptyLine = false;
                    } else { // Add a whitespace if there are no preceding empty lines
                        lexemeBuffer += " ";
                    }
                    lexemeBuffer += self.currentToken.value;
                }
                EOL => {
                    check self.checkToken();
                    // Terminate at the end of the line
                    if self.lineIndex == self.numLines - 1 {
                        break;
                    }
                    check self.initLexer("");
                }
                EMPTY_LINE => {
                    lexemeBuffer += "\n";
                    emptyLine = true;
                    check self.checkToken();
                    // Terminate at the end of the line
                    if self.lineIndex == self.numLines - 1 {
                        break;
                    }
                    check self.initLexer("");
                }
                SEPARATION_IN_LINE => {
                    check self.checkToken();
                    // Continue to scan planar char if the white space at the EOL
                    check self.checkToken(peek = true);
                    if self.tokenBuffer.token == MAPPING_VALUE {
                        break;
                    }
                }
                _ => { // Break the character when the token does not belong to planar scalar
                    break;
                }
            }
            check self.checkToken(peek = true);
        }
        return self.trimTailWhitespace(lexemeBuffer);
    }

    private function blockScalar(boolean isFolded) returns ParsingError|LexicalError|string {
        string chompingIndicator = check self.chompingIndicator();

        self.lexer.state = LEXER_LITERAL;
        string lexemeBuffer = "";
        string newLineBuffer = "";
        boolean isFirstLine = true;
        boolean prevTokenIndented = false;

        check self.checkToken();

        while true {
            match self.currentToken.token {
                PRINTABLE_CHAR => {
                    if !isFirstLine {
                        string suffixChar = "\n";
                        if isFolded && prevTokenIndented && self.currentToken.value[0] != " " {
                            suffixChar = newLineBuffer.length() == 0 ? " " : "";
                        }
                        lexemeBuffer += newLineBuffer + suffixChar;
                        newLineBuffer = "";
                    }

                    lexemeBuffer += self.currentToken.value;
                    prevTokenIndented = self.currentToken.value[0] != " ";
                    isFirstLine = false;
                }
                EOL => {
                    // Terminate at the end of the line
                    if self.lineIndex == self.numLines - 1 {
                        break;
                    }
                    check self.initLexer();
                }
                EMPTY_LINE => {
                    if !isFirstLine {
                        newLineBuffer += "\n";
                    }
                    if self.lineIndex == self.numLines - 1 {
                        break;
                    }
                    check self.initLexer();
                    isFirstLine = false;
                }
                TRAILING_COMMENT => {
                    self.lexer.trailingComment = true;
                    // Terminate at the end of the line
                    if self.lineIndex == self.numLines - 1 {
                        break;
                    }
                    check self.initLexer();
                    check self.checkToken();

                    // Ignore the tokens inside trailing comments
                    while self.currentToken.token == EOL || self.currentToken.token == EMPTY_LINE {
                        // Terminate at the end of the line
                        if self.lineIndex == self.numLines - 1 {
                            break;
                        }
                        check self.initLexer();
                        check self.checkToken();
                    }

                    self.lexer.trailingComment = false;
                    break;
                }
                _ => { // Break the character when the token does not belong to planar scalar
                    break;
                }
            }
            check self.checkToken();
        }

        // Adjust the tail based on the chomping values
        match chompingIndicator {
            "-" => {
                //TODO: trim trailing newlines
            }
            "+" => {
                lexemeBuffer += "\n";
                lexemeBuffer += newLineBuffer;
            }
            "=" => {
                //TODO: trim trailing newlines
                lexemeBuffer += "\n";
            }
        }

        return lexemeBuffer;
    }

    private function chompingIndicator() returns string|LexicalError|ParsingError {
        self.lexer.state = LEXER_BLOCK_HEADER;
        check self.checkToken();

        // Scan for block-header
        match self.currentToken.token {
            CHOMPING_INDICATOR => { // Strip and keep chomping indicators
                string chompingIndicator = self.currentToken.value;
                check self.checkToken(EOL);
                check self.initLexer();
                return chompingIndicator;
            }
            EOL => { // Clip chomping indicator
                check self.initLexer();
                return "=";
            }
            _ => { // Any other characters are not allowed
                return self.generateError(check self.formatErrorMessage(1, CHOMPING_INDICATOR, self.currentToken.token));
            }
        }
    }

    private function appendData(map<anydata> tagStructure = {}, boolean peeked = false) returns Event|LexicalError|ParsingError {
        // Obtain the flow node value
        string|EventType value = check self.content(peeked);
        Event? buffer = ();

        if self.currentToken.indentation {
            int decrease = self.lexer.getSequenceIndentChange();
            if decrease > 1 {
                foreach int i in 2 ... decrease {
                    self.eventBuffer.push({endType: SEQUENCE});
                }
                buffer = {endType: SEQUENCE};
            }
            if decrease == 1 {
                buffer = {endType: SEQUENCE};
            }
        }

        // Check if the current node is a key
        boolean isKey = check self.isNodeKey();

        boolean entry = false;
        if self.sequenceEntry {
            entry = true;
            self.sequenceEntry = false;
        }

        Event event = check self.constructEvent(tagStructure, value is EventType ? {startType: value, isKey, entry} : {value: value, isKey, entry});

        if buffer == () {
            return event;
        }
        self.eventBuffer.push(event);
        return buffer;
    }

    private function content(boolean peeked) returns string|EventType|LexicalError|ParsingError {
        self.lexer.state = LEXER_START;

        if !peeked {
            check self.checkToken();
        }

        // Check for flow scalars
        match self.currentToken.token {
            SINGLE_QUOTE_DELIMITER => {
                self.lexer.isJsonKey = true;
                return self.singleQuoteScalar();
            }
            DOUBLE_QUOTE_DELIMITER => {
                self.lexer.isJsonKey = true;
                return self.doubleQuoteScalar();
            }
            PLANAR_CHAR => {
                return self.planarScalar();
            }
            SEQUENCE_START => {
                return SEQUENCE;
            }
            MAPPING_START => {
                return MAPPING;
            }
            LITERAL|FOLDED => {
                if self.lexer.context == FLOW_ENTRY || self.lexer.context == FLOW_IN || self.lexer.context == FLOW_OUT {
                    return self.generateError("Cannot have a block node inside a flow node");
                }

                return self.blockScalar(self.currentToken.token == FOLDED);
            }
            // TODO: Consider block nodes
        }
        return self.generateError(check self.formatErrorMessage(1, "<data-node>", self.prevToken));
    }

    private function separate(boolean optional = false, boolean allowEmptyNode = false) returns ()|LexicalError|ParsingError {
        self.lexer.state = LEXER_START;
        check self.checkToken(peek = true);

        // Only separation-in-line is considered for keys
        if self.lexer.context == BLOCK_KEY || self.lexer.context == FLOW_KEY {
            // If separate is optional, skip the check when no separate-in-line is detected
            if optional && self.tokenBuffer.token != SEPARATION_IN_LINE {
                return;
            }

            check self.checkToken();
            return self.currentToken.token == SEPARATION_IN_LINE ? ()
                : self.generateError(check self.formatErrorMessage(1, SEPARATION_IN_LINE, self.prevToken));
        }

        // If separate is optional, skip the check when either EOL or separate-in-line is not detected.
        if optional && !(self.tokenBuffer.token == EOL || self.tokenBuffer.token == SEPARATION_IN_LINE) {
            return;
        }

        // Consider the separate for the latter contexts
        check self.checkToken();

        if self.currentToken.token == SEPARATION_IN_LINE {
            // Check for s-b comment
            check self.checkToken(peek = true);
            if self.tokenBuffer.token != EOL {
                return;
            }
            check self.checkToken();
        }

        // For the rest of the contexts, check either separation in line or comment lines
        while self.currentToken.token == EOL || self.currentToken.token == EMPTY_LINE {
            ParsingError? err = self.initLexer();
            if err is ParsingError {
                return optional || allowEmptyNode ? () : err;
            }
            check self.checkToken(peek = true);

            //TODO: account flow-line prefix
            match self.tokenBuffer.token {
                EOL|EMPTY_LINE => { // Check for multi-lines
                    check self.checkToken();
                }
                SEPARATION_IN_LINE => { // Check for l-comment
                    check self.checkToken();
                    check self.checkToken(peek = true);
                    if self.tokenBuffer.token != EOL {
                        return;
                    }
                }
                _ => {
                    return;
                }
            }
        }

        return self.generateError(check self.formatErrorMessage(1, [EOL, SEPARATION_IN_LINE], self.currentToken.token));
    }

    private function isNodeKey() returns boolean|LexicalError|ParsingError {
        boolean isJsonKey = self.lexer.isJsonKey;

        // If there are no whitespace, and the current token is ':'
        if self.currentToken.token == MAPPING_VALUE {
            self.lexer.isJsonKey = false;
            self.lexer.context = FLOW_IN;
            check self.separate(isJsonKey, true);
            self.expectEmptyNode = true;
            return true;
        }

        // If there ano no whitespace, and the current token is ","
        if self.currentToken.token == SEPARATOR {
            check self.separate(true);
            self.lexer.context = FLOW_KEY;
            return true;
        }

        // There are whitespace, and consider next tokens for either ":" or ","
        check self.separate(true);
        check self.checkToken(peek = true);

        if self.tokenBuffer.token == MAPPING_VALUE {
            check self.checkToken();
            self.lexer.isJsonKey = false;
            self.lexer.context = FLOW_IN;
            check self.separate(isJsonKey, true);
            self.expectEmptyNode = true;
            return true;
        }

        if self.tokenBuffer.token == SEPARATOR {
            check self.checkToken();
            check self.separate(true);
            self.lexer.context = FLOW_KEY;
            return true;
        }

        return false;
    }

    private function constructEvent(map<anydata> m1, map<anydata>? m2 = ()) returns Event|ParsingError {
        map<anydata> returnMap = m1.clone();

        if m2 != () {
            m2.keys().forEach(function(string key) {
                returnMap[key] = m2[key];
            });
        }

        error|Event processedMap = returnMap.cloneWithType(Event);

        return processedMap is Event ? processedMap : self.generateError('error:message(processedMap));
    }

    # Find the first non-space character from tail.
    #
    # + value - String to be trimmed
    # + return - Trimmed string
    private function trimTailWhitespace(string value) returns string {
        int i = value.length() - 1;

        if i < 1 {
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

    private function trimHeadWhitespace(string value) returns string {
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
    # + expectedTokens - Predicted token or tokens  
    # + addToLexeme - If set, add the value of the token to lexemeBuffer.  
    # + customMessage - Error message to be displayed if the expected token not found  
    # + peek - Stores the token in the buffer
    # + return - Parsing error if not found
    private function checkToken(YAMLToken|YAMLToken[] expectedTokens = DUMMY, boolean addToLexeme = false, string customMessage = "", boolean peek = false) returns (LexicalError|ParsingError)? {
        Token token;

        // Obtain a token form the lexer if there is none in the buffer.
        if self.tokenBuffer.token == DUMMY {
            self.prevToken = self.currentToken.token;
            token = check self.lexer.getToken();
        } else {
            token = self.tokenBuffer;
            self.tokenBuffer = {token: DUMMY};
        }

        // Add the token to the tokenBuffer if the peek flag is set.
        if peek {
            self.tokenBuffer = token;
        } else {
            self.currentToken = token;
        }

        // Bypass error handling.
        if (expectedTokens == DUMMY) {
            return;
        }

        // Automatically generates a template error message if there is no custom message.
        string errorMessage = customMessage.length() == 0
                                ? check self.formatErrorMessage(1, expectedTokens, self.prevToken)
                                : customMessage;

        // Generate an error if the expected token differ from the actual token.
        if (expectedTokens is YAMLToken) {
            if (token.token != expectedTokens) {
                return self.generateError(errorMessage);
            }
        } else {
            if (expectedTokens.indexOf(token.token) == ()) {
                return self.generateError(errorMessage);
            }
        }

        if (addToLexeme) {
            self.lexemeBuffer += self.currentToken.value;
        }
    }

    # Initialize the lexer with the attributes of a new line.
    #
    # + message - Error message to display when if the initialization fails 
    # + return - An error if it fails to initialize  
    private function initLexer(string message = "Unexpected end of stream") returns ParsingError? {
        self.lineIndex += 1;
        if (self.lineIndex >= self.numLines) {
            return self.generateError(message);
        }
        self.lexer.line = self.lines[self.lineIndex];
        self.lexer.index = 0;
        self.lexer.lineNumber = self.lineIndex;
    }

    # Check errors during type casting to Ballerina types.
    #
    # + value - Value to be type casted.
    # + return - Value as a Ballerina data type  
    private function processTypeCastingError(anydata|error value) returns anydata|ParsingError {
        // Check if the type casting has any errors
        if value is error {
            return self.generateError("Invalid value for assignment");
        }

        // Returns the value on success
        return value;
    }

    # Generates a Parsing Error Error.
    #
    # + message - Error message
    # + return - Constructed Parsing Error message  
    private function generateError(string message) returns ParsingError {
        string text = "Parsing Error at line "
                        + self.lexer.lineNumber.toString()
                        + " index "
                        + self.lexer.index.toString()
                        + ": "
                        + message
                        + ".";
        return error ParsingError(text);
    }

    # Generate a standard error message based on the type.
    #
    # 1 - Expected ${expectedTokens} after ${beforeToken}, but found ${actualToken}
    #
    # 2 - Duplicate key exists for ${value}
    #
    # + messageType - Number of the template message
    # + expectedTokens - Predicted tokens  
    # + beforeToken - Token before the predicted token  
    # + value - Any value name. Commonly used to indicate keys.
    # + return - If success, the generated error message. Else, an error message.
    private function formatErrorMessage(
            int messageType,
            YAMLToken|YAMLToken[]|string expectedTokens = DUMMY,
            YAMLToken|string beforeToken = DUMMY,
            string value = "") returns string|ParsingError {

        match messageType {
            1 => { // Expected ${expectedTokens} after ${beforeToken}, but found ${actualToken}
                if (expectedTokens == DUMMY || beforeToken == DUMMY) {
                    return error("Token parameters cannot be null for this template error message.");
                }
                string expectedTokensMessage;
                if (expectedTokens is YAMLToken[]) { // If multiple tokens
                    string tempMessage = expectedTokens.reduce(function(string message, YAMLToken token) returns string {
                        return message + " '" + token + "' or";
                    }, "");
                    expectedTokensMessage = tempMessage.substring(0, tempMessage.length() - 3);
                } else { // If a single token
                    expectedTokensMessage = " '" + <string>expectedTokens + "'";
                }
                return "Expected" + expectedTokensMessage + " after '" + <string>beforeToken + "', but found '" + self.currentToken.token + "'";
            }

            2 => { // Duplicate key exists for ${value}
                if (value.length() == 0) {
                    return error("Value cannot be empty for this template message");
                }
                return "Duplicate key exists for '" + value + "'";
            }

            _ => {
                return error("Invalid message type number. Enter a value between 1-2");
            }
        }
    }
}
