page 72202 "DOPSWHS Field WO List"
{
    // Kitoko/Element4 #3338: açık saha iş emirleri seçim listesi (BC Projeye Çıkış sayfası).
    Caption = 'Açık Saha İş Emirleri';
    PageType = List;
    SourceTable = "DOPSWHS Field WO Buffer";
    SourceTableTemporary = true;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Orders)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Project No."; Rec."Project No.") { ApplicationArea = All; }
                field("Project Task No."; Rec."Project Task No.") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Project Description"; Rec."Project Description") { ApplicationArea = All; }
                field(Team; Rec.Team) { ApplicationArea = All; }
                field("Planned Start"; Rec."Planned Start") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Item Line Count"; Rec."Item Line Count") { ApplicationArea = All; }
            }
        }
    }

    trigger OnOpenPage()
    var
        ProjectIssueMgmt: Codeunit "DOPSWHS Project Issue Mgmt";
    begin
        ProjectIssueMgmt.FillOpenWorkOrders(Rec);
    end;
}
