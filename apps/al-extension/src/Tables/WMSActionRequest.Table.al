table 50118 "WMS Action Request"
{
    Caption = 'WMS Action Request';
    DataClassification = CustomerContent;
    Description = 'Inbound transactional submissions from the mobile app. OnInsert dispatches to the matching service codeunit and writes the result back inline.';

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }
        field(2; "Request Id"; Guid)
        {
            Caption = 'Request Id';
            ToolTip = 'Idempotency key supplied by the device. Re-posting the same id replays the prior result.';
        }
        field(3; "Flow Id"; Code[50]) { Caption = 'Flow Id'; }
        field(4; Payload; Text[2048]) { Caption = 'Payload'; ToolTip = 'JSON payload of the captured flow fields.'; }
        field(5; "Worker Id"; Code[50]) { Caption = 'Worker Id'; }
        field(6; Status; Enum "WMS Action Status") { Caption = 'Status'; }
        field(7; "Result Message"; Text[250]) { Caption = 'Result Message'; }
        field(8; "Result Document No."; Code[20]) { Caption = 'Result Document No.'; }
        field(9; "Received At"; DateTime) { Caption = 'Received At'; Editable = false; }
        field(10; "Processed At"; DateTime) { Caption = 'Processed At'; Editable = false; }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Request; "Request Id") { }
    }

    trigger OnInsert()
    var
        Existing: Record "WMS Action Request";
        Dispatcher: Codeunit "WMS Action Dispatcher";
    begin
        "Received At" := CurrentDateTime();

        // Idempotent replay: a prior submission with the same Request Id wins.
        if not IsNullGuid("Request Id") then begin
            Existing.SetRange("Request Id", "Request Id");
            if Existing.FindFirst() then begin
                Status := Existing.Status;
                "Result Message" := Existing."Result Message";
                "Result Document No." := Existing."Result Document No.";
                "Processed At" := CurrentDateTime();
                exit;
            end;
        end;

        Dispatcher.Dispatch(Rec);
    end;
}
