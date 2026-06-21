{
  "Version": "2019-10-30",
  "StartAction": "set-logging",
  "Actions": [
    {
      "Identifier": "set-logging",
      "Type": "UpdateFlowLoggingBehavior",
      "Parameters": { "FlowLoggingBehavior": "Enabled" },
      "Transitions": { "NextAction": "greet" }
    },
    {
      "Identifier": "greet",
      "Type": "MessageParticipant",
      "Parameters": {
        "Text": "Thanks for calling ${company_name}. Our assistant will be with you shortly."
      },
      "Transitions": {
        "NextAction": "end",
        "Errors": [{ "NextAction": "end", "ErrorType": "NoMatchingError" }]
      }
    },
    {
      "Identifier": "end",
      "Type": "DisconnectParticipant",
      "Parameters": {},
      "Transitions": {}
    }
  ]
}
