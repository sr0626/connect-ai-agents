{
  "Version": "2019-10-30",
  "StartAction": "set-logging",
  "Metadata": {
    "entryPointPosition": { "x": 20, "y": 20 },
    "ActionMetadata": {
      "set-logging": { "position": { "x": 180, "y": 20 } },
      "set-voice": { "position": { "x": 380, "y": 20 } },
      "ai-agent": { "position": { "x": 600, "y": 20 } },
      "set-queue": { "position": { "x": 820, "y": 120 } },
      "transfer-to-queue": { "position": { "x": 1040, "y": 120 } },
      "disconnect": { "position": { "x": 1040, "y": 20 } }
    }
  },
  "Actions": [
    {
      "Identifier": "set-logging",
      "Type": "UpdateFlowLoggingBehavior",
      "Parameters": { "FlowLoggingBehavior": "Enabled" },
      "Transitions": { "NextAction": "set-voice" }
    },
    {
      "Identifier": "set-voice",
      "Type": "UpdateContactTextToSpeechVoice",
      "Parameters": {
        "TextToSpeechVoice": "Matthew",
        "TextToSpeechEngine": "generative",
        "LanguageCode": "en-US"
      },
      "Transitions": { "NextAction": "ai-agent" }
    },
    {
      "Identifier": "ai-agent",
      "Type": "ConnectParticipantWithLexBot",
      "Parameters": {
        "LexV2Bot": { "AliasArn": "${bot_alias_arn}" }
      },
      "Transitions": {
        "NextAction": "disconnect",
        "Conditions": [
          {
            "NextAction": "set-queue",
            "Condition": {
              "Operator": "Equals",
              "Operands": ["escalate"]
            }
          }
        ],
        "Errors": [
          { "NextAction": "set-queue", "ErrorType": "NoMatchingError" }
        ]
      }
    },
    {
      "Identifier": "set-queue",
      "Type": "UpdateContactTargetQueue",
      "Parameters": { "QueueId": "${escalation_queue_arn}" },
      "Transitions": {
        "NextAction": "transfer-to-queue",
        "Errors": [
          { "NextAction": "disconnect", "ErrorType": "NoMatchingError" }
        ]
      }
    },
    {
      "Identifier": "transfer-to-queue",
      "Type": "TransferContactToQueue",
      "Parameters": {},
      "Transitions": {
        "NextAction": "disconnect",
        "Errors": [
          { "NextAction": "disconnect", "ErrorType": "QueueAtCapacity" },
          { "NextAction": "disconnect", "ErrorType": "NoMatchingError" }
        ]
      }
    },
    {
      "Identifier": "disconnect",
      "Type": "DisconnectParticipant",
      "Parameters": {},
      "Transitions": {}
    }
  ]
}
