page 72203 "DOPSWHS Field WO Line List"
{
    // Kitoko/Element4 #3338: seçilen saha iş emrinin satırları (ekip ve malzemeler),
    // terminalin gördüğü biçimde (madde satırı mı, planlanan / gerçekleşen).
    Caption = 'Saha İş Emri Satırları (WMS)';
    PageType = List;
    SourceTable = "DOPSWHS Field WO Line Buffer";
    SourceTableTemporary = true;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Work Order No."; Rec."Work Order No.") { ApplicationArea = All; }
                field("Line No."; Rec."Line No.") { ApplicationArea = All; }
                field(Type; Rec.Type) { ApplicationArea = All; }
                field("Is Item"; Rec."Is Item") { ApplicationArea = All; }
                field("No."; Rec."No.") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Actual Quantity"; Rec."Actual Quantity") { ApplicationArea = All; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; }
            }
        }
    }

    trigger OnOpenPage()
    var
        ProjectIssueMgmt: Codeunit "DOPSWHS Project Issue Mgmt";
    begin
        ProjectIssueMgmt.FillOpenWorkOrderLines(Rec);
    end;
}
