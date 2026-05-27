page 72482 "DOPSWHS Count Counter Part"
{
    Caption = 'Count Counters';
    PageType = ListPart;
    SourceTable = "DOPSWHS Count Counter";
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(Counters)
            {
                field("Counter Slot"; Rec."Counter Slot") { ApplicationArea = All; }
                field("User ID"; Rec."User ID") { ApplicationArea = All; }
                field("Assigned DateTime"; Rec."Assigned DateTime") { ApplicationArea = All; }
            }
        }
    }
}
