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
                field("User ID"; Rec."User ID")
                {
                    ApplicationArea = All;
                    Caption = 'User ID';
                    Lookup = true;
                    ToolTip = 'Bu sayıcı slotuna atanacak etkin terminal operatörünü Local WMS Users listesinden seçin.';

                    // BADE (1 Eki 2026): OnLookup true döndüğünde platform alanı
                    // Text ile doğrular. Önceden Text boş kaldığı için seçilen
                    // kullanıcı alana hiç yazılmıyordu.
                    trigger OnLookup(var Text: Text): Boolean
                    var
                        LocalUser: Record "DOPSWHS Local User";
                    begin
                        LocalUser.SetRange(Disabled, false);
                        if Page.RunModal(Page::"DOPSWHS Terminal Users", LocalUser) <> Action::LookupOK then
                            exit(false);

                        Text := LocalUser.Username;
                        exit(true);
                    end;
                }
                field("Assigned DateTime"; Rec."Assigned DateTime")
                {
                    ApplicationArea = All;
                    Editable = false;
                }
                field(Completed; Rec.Completed) { ApplicationArea = All; Editable = false; }
                field("Completed DateTime"; Rec."Completed DateTime") { ApplicationArea = All; Editable = false; }
            }
        }
    }

    // Yeni satır 0 slotla açılıyordu (geçerli değerler 1-3); ilk boş slot verilir.
    trigger OnNewRecord(BelowxRec: Boolean)
    var
        Counter: Record "DOPSWHS Count Counter";
        Slot: Integer;
    begin
        if Rec.GetFilter("Sheet No.") = '' then
            exit;
        for Slot := 1 to 3 do begin
            Counter.SetFilter("Sheet No.", Rec.GetFilter("Sheet No."));
            Counter.SetRange("Counter Slot", Slot);
            if Counter.IsEmpty() then begin
                Rec."Counter Slot" := Slot;
                exit;
            end;
        end;
    end;
}
