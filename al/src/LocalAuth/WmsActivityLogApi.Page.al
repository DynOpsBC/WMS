page 72363 "DOPSWHS WMS Activity Log API"
{
    PageType = API;
    SourceTable = "DOPSWHS WMS Activity Log";
    Caption = 'Activity Log';
    ApplicationArea = All;
    ODataKeyFields = "Entry No.";
    APIVersion = '2.0';
    APIPublisher = 'dynops';
    APIGroup = 'wms';

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("entryNo"; Rec."Entry No.") { Caption = 'entryNo'; }
                field(timestamp; Rec.Timestamp) { Caption = 'timestamp'; }
                field(localUser; Rec."Local User") { Caption = 'localUser'; }
                field(userDisplayName; Rec."User Display Name") { Caption = 'userDisplayName'; }
                field(action; Rec.Action) { Caption = 'action'; }
                field(actionStatus; Rec."Action Status") { Caption = 'actionStatus'; }
                field(documentType; Rec."Document Type") { Caption = 'documentType'; }
                field(documentNo; Rec."Document No.") { Caption = 'documentNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(details; Rec.Details) { Caption = 'details'; }
            }
        }
    }

    // Android app POST /wmsActivityLog with activity JSON:
    // {
    //   "timestamp": "2026-07-27T14:30:45.123Z",
    //   "localUser": "wms-op-01",
    //   "userDisplayName": "Operator 01",
    //   "action": "ScanItem",
    //   "actionStatus": 0,  // 0=Success, 1=Fail, 2=Timeout
    //   "documentType": "Pick",
    //   "documentNo": "WHSEPICK-0001",
    //   "lineNo": 1,
    //   "itemNo": "1000",
    //   "quantity": 5,
    //   "unitOfMeasureCode": "PCS",
    //   "details": "{\"binCode\": \"A-01-01\", \"lotNo\": \"LOT-2026-001\"}"
    // }
}
