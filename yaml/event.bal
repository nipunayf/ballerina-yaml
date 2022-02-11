type Event AliasEvent|StreamStartEvent|DocumentStartEvent|SequenceStartEvent|
    MappingStartEvent|ScalarEvent|EndEvent;

type AliasEvent record {|
    string anchor;
|};

type StreamStartEvent record {|
    string encoding;
|};

type DocumentStartEvent record {|
    boolean explicit = false;
    string docVersion;
    map<string> tags;
|};

type NodeEvent record {|
    string anchor;
    string tag;
    string implicit;
    string style;
|};

type SequenceStartEvent record {|
    *NodeEvent;
|};

type MappingStartEvent record {|
    *NodeEvent;
|};

type ScalarEvent record {|
    *NodeEvent;
    string value;
|};

type EndEvent record {|
    EndEventType endType;
|};

enum EndEventType {
    END_STREAM,
    END_DOCUMENT,
    END_SEQUENCE,
    END_MAPPING
}
