page 72469 "DOPSWHS Label Layout List"
{
    Caption = 'Etiket Tasarımları';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Administration;
    AdditionalSearchTerms = 'Etiket Tasarımları,etiket tasarımı,label layout,ZPL';
    SourceTable = "DOPSWHS Label Layout";
    CardPageId = "DOPSWHS Label Layout Card";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("Code"; Rec."Code") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Label Kind"; Rec."Label Kind") { ApplicationArea = All; }
                field("Width (mm)"; Rec."Width (mm)") { ApplicationArea = All; }
                field("Height (mm)"; Rec."Height (mm)") { ApplicationArea = All; }
                field(Active; Rec.Active) { ApplicationArea = All; }
            }
        }
    }

    trigger OnOpenPage()
    var
        Engine: Codeunit "DOPSWHS Label Layout Engine";
    begin
        // Kitoko (20 Eki 2026): ilk açılışta varsayılan tasarımlar (pasif) yüklenir.
        if Rec.IsEmpty() then
            if Rec.WritePermission() then
                Engine.SeedDefaults();
    end;
}
