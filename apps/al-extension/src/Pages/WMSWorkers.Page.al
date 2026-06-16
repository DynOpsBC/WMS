page 50029000 "WMS Workers"
{
    Caption = 'WMS Workers';
    PageType = List;
    SourceTable = "WMS Worker";
    UsageCategory = Lists;
    ApplicationArea = All;
    CardPageId = "WMS Worker Card";

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("User ID"; Rec."User ID") { ApplicationArea = All; }
                field("User Name"; Rec."User Name") { ApplicationArea = All; }
                field("Default Location Code"; Rec."Default Location Code") { ApplicationArea = All; }
                field("Menu Code"; Rec."Menu Code") { ApplicationArea = All; }
                field(Inactive; Rec.Inactive) { ApplicationArea = All; }
                field("Last Sign-In"; Rec."Last Sign-In") { ApplicationArea = All; }
            }
        }
    }
}
