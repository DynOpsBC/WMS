page 72297 "DOPSWHS Printer Card"
{
    Caption = 'Printer Card';
    PageType = Card;
    ApplicationArea = All;
    SourceTable = "DOPSWHS Printer";

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("Code"; Rec."Code") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Format"; Rec."Format") { ApplicationArea = All; }
                field(Active; Rec.Active) { ApplicationArea = All; }
                field(Comment; Rec.Comment) { ApplicationArea = All; }
            }
            group(Connection)
            {
                Caption = 'Local Agent Binding';
                field("Printer Handle"; Rec."Printer Handle") { ApplicationArea = All; }
                field(Hostname; Rec.Hostname) { ApplicationArea = All; }
                field(Port; Rec.Port) { ApplicationArea = All; }
                field("Default Copies"; Rec."Default Copies") { ApplicationArea = All; }
            }
            group(Security)
            {
                Caption = 'Security';
                field("Token Hash"; Rec."Token Hash") { ApplicationArea = All; Editable = false; }
                field("Token Issued At"; Rec."Token Issued At") { ApplicationArea = All; Editable = false; }
                field("Last Seen At"; Rec."Last Seen At") { ApplicationArea = All; Editable = false; }
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
                ToolTip = 'Generates a fresh agent secret. The plain value is shown only once.';

                trigger OnAction()
                var
                    Client: Codeunit "DOPSWHS Self-Host Print Client";
                    Token: Text;
                begin
                    Token := Client.RotateToken(Rec."Code");
                    Message('Agent token for %1:\n\n%2\n\nCopy it now — only the hash is stored.', Rec."Code", Token);
                end;
            }
            action(TestPrint)
            {
                Caption = 'Test Print';
                ApplicationArea = All;
                Image = Print;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Queues a small ZPL self-test label for the agent to pull.';

                trigger OnAction()
                var
                    Client: Codeunit "DOPSWHS Self-Host Print Client";
                begin
                    Client.EnqueueSelfTest(Rec."Code");
                    Message('Self-test job queued for %1.', Rec."Code");
                end;
            }
        }
    }
}
