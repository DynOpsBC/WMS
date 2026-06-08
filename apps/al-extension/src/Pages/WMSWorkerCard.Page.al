page 50101 "WMS Worker Card"
{
    Caption = 'WMS Worker Card';
    PageType = Card;
    SourceTable = "WMS Worker";
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("User ID"; Rec."User ID") { ApplicationArea = All; }
                field("User Name"; Rec."User Name") { ApplicationArea = All; }
                field("Default Location Code"; Rec."Default Location Code") { ApplicationArea = All; }
                field("Menu Code"; Rec."Menu Code") { ApplicationArea = All; }
                field("Entra ID Object ID"; Rec."Entra ID Object ID") { ApplicationArea = All; }
            }
            group(Permissions)
            {
                field(Inactive; Rec.Inactive) { ApplicationArea = All; }
                field("Allow Pick Location Override"; Rec."Allow Pick Location Override") { ApplicationArea = All; }
                field("Cycle Count Supervisor"; Rec."Cycle Count Supervisor") { ApplicationArea = All; }
            }
            group(Activity)
            {
                field("Last Sign-In"; Rec."Last Sign-In") { ApplicationArea = All; }
            }
        }
    }
}
