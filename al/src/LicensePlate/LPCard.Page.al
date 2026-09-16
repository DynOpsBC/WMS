page 72069 "DOPSWHS LP Card"
{
    Caption = 'License Plate';
    PageType = Card;
    SourceTable = "DOPSWHS LP Header";
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Parent LP No."; Rec."Parent LP No.") { ApplicationArea = All; }
                field("LP Template Code"; Rec."LP Template Code") { ApplicationArea = All; }
                field(SSCC; Rec.SSCC) { ApplicationArea = All; }
            }
            part(Lines; "DOPSWHS LP Line ListPart")
            {
                ApplicationArea = All;
                SubPageLink = "LP No." = field("No.");
            }
            group(Tracking)
            {
                field("Assigned Document Type"; Rec."Assigned Document Type") { ApplicationArea = All; }
                field("Assigned Document No."; Rec."Assigned Document No.") { ApplicationArea = All; }
                field("Built By User"; Rec."Built By User") { ApplicationArea = All; }
                field("Built DateTime"; Rec."Built DateTime") { ApplicationArea = All; }
                field("Last Modified DateTime"; Rec."Last Modified DateTime") { ApplicationArea = All; }
            }
            group(Dimensions)
            {
                field("Weight kg"; Rec."Weight kg") { ApplicationArea = All; }
                field("Length cm"; Rec."Length cm") { ApplicationArea = All; }
                field("Width cm"; Rec."Width cm") { ApplicationArea = All; }
                field("Height cm"; Rec."Height cm") { ApplicationArea = All; }
            }
            group(Notes)
            {
                field(NotesText; Rec.Notes) { ApplicationArea = All; MultiLine = true; Caption = 'Notes'; }
            }
        }
        area(FactBoxes)
        {
            part(NestTree; "DOPSWHS LP Factbox Bin")
            {
                ApplicationArea = All;
                SubPageLink = "Location Code" = field("Location Code"),
                              "Bin Code" = field("Bin Code");
            }
            part(MovementLedger; "DOPSWHS LP Movement Ledger")
            {
                ApplicationArea = All;
                SubPageLink = "LP No." = field("No.");
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(PrintMteTerminalPath)
            {
                // BADE 16 Eyl 2026: the terminal masks BC errors behind a REF
                // code. This runs the very same MTE path the terminal uses
                // (device printer mapping of the current user, built-in or
                // customer report / ZPL) so the admin sees the raw BC error here.
                ApplicationArea = All;
                Caption = 'MTE Yazdır (terminal yolu)';
                ToolTip = 'Terminalin "MTE Yazdır" ile çalıştırdığı baskı yolunu bu kullanıcının yazıcı eşlemesiyle çalıştırır. Terminalde REF kodu görünen hata burada tam metniyle görünür.';
                Image = Print;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    Printer: Record "DOPSWHS Printer";
                    Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
                begin
                    // The BC user usually has no device printer mapping (the
                    // terminal sends its own printer code), so let the admin
                    // pick the printer explicitly; Cancel = mapping of this user.
                    Printer.SetRange(Active, true);
                    if Page.RunModal(Page::"DOPSWHS Printer List", Printer) = Action::LookupOK then
                        Dispatcher.PrintPalletItemLabelsWithOptions(Rec, Printer.Code, 1, '')
                    else
                        Dispatcher.PrintPalletItemLabelsWithOptions(Rec, '', 1, '');
                    Message('MTE baskı isteği gönderildi: %1', Rec."No.");
                end;
            }
        }
    }
}
