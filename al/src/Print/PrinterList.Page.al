page 72296 "DOPSWHS Printer List"
{
    Caption = 'Printers';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = "DOPSWHS Printer";
    CardPageId = "DOPSWHS Printer Card";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("Code"; Rec."Code") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Format"; Rec."Format") { ApplicationArea = All; }
                field("Printer Handle"; Rec."Printer Handle") { ApplicationArea = All; }
                field(Active; Rec.Active) { ApplicationArea = All; }
                field("Last Seen At"; Rec."Last Seen At") { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(GenerateToken)
            {
                Caption = 'Generate Token';
                ApplicationArea = All;
                Image = EncryptionKeys;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                ToolTip = 'Generates a fresh agent secret. Copy it now — it will not be shown again.';

                trigger OnAction()
                var
                    Client: Codeunit "DOPSWHS Self-Host Print Client";
                    Token: Text;
                begin
                    Token := Client.RotateToken(Rec."Code");
                    Message('Agent token for %1:\n\n%2\n\nCopy now — only the hash is stored.', Rec."Code", Token);
                end;
            }
        }
    }
}
