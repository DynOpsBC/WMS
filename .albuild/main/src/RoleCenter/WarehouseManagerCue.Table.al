table 72026 "DOPSWHS Warehouse Mgr Cue"
{
    Caption = 'Warehouse Manager Cues';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10]) { Caption = 'Primary Key'; DataClassification = SystemMetadata; }
        // TODO Sprint H+ post-deploy: restore status filter if the target BC app exposes receipt/activity status fields.
        field(10; "Open Receipts"; Integer) { Caption = 'Open Receipts'; FieldClass = FlowField; CalcFormula = count("Warehouse Receipt Header"); }
        field(20; "Open Picks"; Integer) { Caption = 'Open Picks'; FieldClass = FlowField; CalcFormula = count("Warehouse Activity Header" where(Type = const(Pick))); }
        field(30; "Open Shipments"; Integer) { Caption = 'Open Shipments'; FieldClass = FlowField; CalcFormula = count("Warehouse Shipment Header" where(Status = const(Released))); }
        // TODO Sprint H+ post-deploy: restore late-pick date filter if the target BC app exposes due date on activity headers.
        field(40; "Late Picks"; Integer) { Caption = 'Late Picks'; FieldClass = FlowField; CalcFormula = count("Warehouse Activity Header" where(Type = const(Pick))); }
        field(50; "Unbuilt LPs"; Integer) { Caption = 'Unbuilt LPs'; FieldClass = FlowField; CalcFormula = count("DOPSWHS LP Header" where(Status = const(Open))); }
        field(60; "Count Discrepancies"; Integer) { Caption = 'Count Discrepancies'; FieldClass = FlowField; CalcFormula = count("DOPSWHS Count Sheet Header" where(Status = const(InProgress))); }
        field(70; "Devices Online"; Integer) { Caption = 'Devices Online'; FieldClass = FlowField; CalcFormula = count("DOPSWHS Device Registration" where("Last Seen DateTime" = field("Online Since DateTime Filter"))); }
        field(100; "Late Pick Date Filter"; Date) { Caption = 'Late Pick Date Filter'; FieldClass = FlowFilter; }
        field(110; "Online Since DateTime Filter"; DateTime) { Caption = 'Online Since DateTime Filter'; FieldClass = FlowFilter; }
    }

    keys { key(PK; "Primary Key") { Clustered = true; } }

    trigger OnInsert()
    begin
        "Primary Key" := '';
    end;
}
