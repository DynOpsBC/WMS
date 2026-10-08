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
            action(RepairHistoricalProductionPick)
            {
                ApplicationArea = All;
                AccessByPermission = codeunit "DOPSWHS LP Management" = X;
                Caption = 'Eski Üretim Çekmesini Onar';
                ToolTip = 'Kayıtlı çekmeyi bu LP ile eşleştirir. Kaynak ve hedef göz miktarları kesin eşleşirse eksik LP düşümünü ve gerekliyse geri taşınmış stoku düzeltir.';
                Image = Entries;

                trigger OnAction()
                var
                    RegisteredTake: Record "Registered Whse. Activity Line";
                    TakeLookup: Page "DOPSWHS Prod Pick Repair Lines";
                    LPMgt: Codeunit "DOPSWHS LP Management";
                    Preview: Text;
                    Result: Text;
                begin
                    Rec.TestField("Location Code");
                    Rec.TestField("Bin Code");
                    RegisteredTake.SetRange("Activity Type", RegisteredTake."Activity Type"::Pick);
                    RegisteredTake.SetRange("Action Type", RegisteredTake."Action Type"::Take);
                    RegisteredTake.SetRange("Source Type", Database::"Prod. Order Component");
                    RegisteredTake.SetRange("Location Code", Rec."Location Code");
                    RegisteredTake.SetRange("Bin Code", Rec."Bin Code");
                    TakeLookup.SetTableView(RegisteredTake);
                    TakeLookup.LookupMode(true);
                    if TakeLookup.RunModal() <> Action::LookupOK then
                        exit;
                    TakeLookup.GetRecord(RegisteredTake);
                    Preview := LPMgt.RepairHistoricalProductionPickLp(
                        Rec."No.", RegisteredTake."No.", RegisteredTake."Line No.", false);
                    if not Confirm('%1. Bu kayıtlı çekme için onarım uygulansın mı?', false, Preview) then
                        exit;
                    Result := LPMgt.RepairHistoricalProductionPickLp(
                        Rec."No.", RegisteredTake."No.", RegisteredTake."Line No.", true);
                    Message('%1', Result);
                    CurrPage.Update(false);
                end;
            }
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
