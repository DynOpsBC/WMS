table 72018 "DOPSWHS Count Counter"
{
    Caption = 'Count Counter';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Sheet No."; Code[20]) { Caption = 'Sheet No.'; DataClassification = CustomerContent; TableRelation = "DOPSWHS Count Sheet Header"; }
        field(2; "Counter Slot"; Integer) { Caption = 'Counter Slot'; DataClassification = CustomerContent; MinValue = 1; MaxValue = 3; }
        field(10; "User ID"; Code[50]) { Caption = 'User ID'; DataClassification = EndUserIdentifiableInformation; TableRelation = User."User Name"; }
        field(20; "Assigned DateTime"; DateTime) { Caption = 'Assigned DateTime'; DataClassification = CustomerContent; }
    }

    keys
    {
        key(PK; "Sheet No.", "Counter Slot") { Clustered = true; }
        key(User; "User ID") { }
    }
}
