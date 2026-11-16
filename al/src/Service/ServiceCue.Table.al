table 72102 "DOPSWHS Service Cue"
{
    DataClassification = CustomerContent;
    fields
    {
        field(1; "Primary Key"; Code[10]) { }
        field(2; "Pending"; Integer)
        {
            FieldClass = FlowField;
            CalcFormula = count("Service Header" where("Document Type" = const(Order), Status = const("Pending")));
        }
        field(3; "In Process"; Integer)
        {
            FieldClass = FlowField;
            CalcFormula = count("Service Header" where("Document Type" = const(Order), Status = const("In Process")));
        }
        field(4; "On Hold"; Integer)
        {
            FieldClass = FlowField;
            CalcFormula = count("Service Header" where("Document Type" = const(Order), Status = const("On Hold")));
        }
        field(5; "Finished"; Integer)
        {
            FieldClass = FlowField;
            CalcFormula = count("Service Header" where("Document Type" = const(Order), Status = const("Finished")));
        }
        field(6; Unassigned; Integer) { }
        field(7; Overdue; Integer)
        {
            FieldClass = FlowField;
            CalcFormula = count("Service Header" where("Document Type" = const(Order), Status = filter(<> Finished), "Response Date" = field("Date Filter")));
        }
        // Caller sets Date Filter to <Today for the overdue count.
        field(8; "Date Filter"; Date) { FieldClass = FlowFilter; }
    }
    keys { key(PK; "Primary Key") { Clustered = true; } }
}
