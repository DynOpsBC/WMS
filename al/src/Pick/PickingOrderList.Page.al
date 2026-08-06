page 72357 "DOPSWHS Picking Order List"
{
    // Depo sorumlusunun "toplanacak siparişler" takip ekranı.
    // Terminalden "Üzerime Al" yapılınca atama buraya da yansır
    // (PickMgmt.SyncPickingOrderAssignment).
    PageType = List;
    Caption = 'Toplanacak Siparişler';
    SourceTable = "DOPSWHS Picking Order Header";
    CardPageId = "DOPSWHS Picking Order Card";
    ApplicationArea = All;
    UsageCategory = Tasks;
    Editable = false;
    SourceTableView = sorting("Entry No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(Headers)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                    Caption = 'Kayıt No.';
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                    Caption = 'Açıklama';
                }
                field(OrderCountText; OrderCountText)
                {
                    ApplicationArea = All;
                    Caption = 'Sipariş';
                    ToolTip = 'Bu gruptaki satış siparişi sayısı ve toplam ürün satırı.';
                }
                field(StatusText; StatusText)
                {
                    ApplicationArea = All;
                    Caption = 'Durum';
                    StyleExpr = StatusStyle;
                    ToolTip = 'Açık: henüz pick oluşturulmadı. Pick Oluşturuldu: terminalde toplayıcıya görünüyor. Tamamlandı: toplama bitti.';
                }
                field("Assigned User ID"; Rec."Assigned User ID")
                {
                    ApplicationArea = All;
                    Caption = 'Toplayıcı';
                    StyleExpr = AssignedStyle;
                    ToolTip = 'Toplamayı üstlenen operatör. Terminalden "Üzerime Al" yapılınca burası otomatik dolar.';
                }
                field(ProgressText; ProgressText)
                {
                    ApplicationArea = All;
                    Caption = 'İlerleme';
                    StyleExpr = ProgressStyle;
                    ToolTip = 'Toplanan / toplam satır (pick oluşturulduysa).';
                }
                field("Location Code"; Rec."Location Code")
                {
                    ApplicationArea = All;
                    Caption = 'Lokasyon';
                }
                field("Warehouse Pick No."; Rec."Warehouse Pick No.")
                {
                    ApplicationArea = All;
                    Caption = 'Toplama Belgesi';
                }
                field("Warehouse Shipment No."; Rec."Warehouse Shipment No.")
                {
                    ApplicationArea = All;
                    Caption = 'Ambar Sevkiyatı';
                    Visible = false;
                }
                field("Created DateTime"; Rec."Created DateTime")
                {
                    ApplicationArea = All;
                    Caption = 'Oluşturulma';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(NewPickingOrder)
            {
                Caption = 'Yeni Toplama Grubu';
                ApplicationArea = All;
                Image = NewDocument;
                Promoted = true;
                PromotedCategory = New;
                RunObject = page "DOPSWHS Picking Order Card";
                RunPageMode = Create;
            }
            group(Filters)
            {
                Caption = 'Görünüm';
                Image = FilterLines;

                action(ShowOpen)
                {
                    ApplicationArea = All;
                    Caption = 'Bekleyenler';
                    Image = List;
                    Promoted = true;
                    PromotedCategory = Process;
                    ToolTip = 'Henüz pick oluşturulmamış grupları gösterir.';

                    trigger OnAction()
                    begin
                        Rec.SetRange(Status, Rec.Status::Open);
                        CurrPage.Update(false);
                    end;
                }
                action(ShowInPicking)
                {
                    ApplicationArea = All;
                    Caption = 'Toplanmakta';
                    Image = PickLines;
                    Promoted = true;
                    PromotedCategory = Process;
                    ToolTip = 'Pick oluşturulmuş, terminalde toplanmayı bekleyen ya da toplanan grupları gösterir.';

                    trigger OnAction()
                    begin
                        Rec.SetRange(Status, Rec.Status::"Pick Created");
                        CurrPage.Update(false);
                    end;
                }
                action(ShowUnassigned)
                {
                    ApplicationArea = All;
                    Caption = 'Atanmamışlar';
                    Image = UserSetup;
                    Promoted = true;
                    PromotedCategory = Process;
                    ToolTip = 'Henüz kimsenin üstlenmediği toplama gruplarını gösterir.';

                    trigger OnAction()
                    begin
                        Rec.SetRange("Assigned User ID", '');
                        Rec.SetFilter(Status, '<>%1', Rec.Status::Completed);
                        CurrPage.Update(false);
                    end;
                }
                action(ShowAll)
                {
                    ApplicationArea = All;
                    Caption = 'Tümü';
                    Image = ShowList;
                    Promoted = true;
                    PromotedCategory = Process;

                    trigger OnAction()
                    begin
                        Rec.SetRange(Status);
                        Rec.SetRange("Assigned User ID");
                        CurrPage.Update(false);
                    end;
                }
            }
            group(Manage)
            {
                Caption = 'Yönet';

                action(AssignPicker)
                {
                    ApplicationArea = All;
                    Caption = 'Toplayıcı Ata';
                    Image = UserSetup;
                    Promoted = true;
                    PromotedCategory = Category4;
                    ToolTip = 'Seçili grubu bir WMS operatörüne atar. Pick oluşturulmuşsa toplama belgesine de yazılır; operatör terminalde görür.';

                    trigger OnAction()
                    var
                        LocalUser: Record "DOPSWHS Local User";
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                    begin
                        if Rec."Entry No." = 0 then
                            exit;
                        if Rec.Status = Rec.Status::Completed then
                            Error(CompletedNotAssignableErr);
                        LocalUser.SetRange(Disabled, false);
                        if Page.RunModal(Page::"DOPSWHS Local User List", LocalUser) <> Action::LookupOK then
                            exit;

                        // Grup başkasındaysa bu bir DEVİR'dir: yanlışlıkla iş elinden
                        // alınmasın diye sorumluya onaylatılır.
                        if (Rec."Assigned User ID" <> '') and (Rec."Assigned User ID" <> LocalUser.Username) then
                            if not Confirm(TakeOverQst, false, PickMgmt.OperatorLabel(Rec."Assigned User ID"), LocalUser."Display Name") then
                                exit;

                        // Kilitli yeniden okuma + pick belgesine yansıtma PickMgmt'te:
                        // eskiden ekrandaki (stale) kayıt doğrudan Modify ediliyordu,
                        // iki sorumlu aynı anda atarsa biri diğerini sessizce eziyordu.
                        PickMgmt.SetPickingOrderPicker(Rec, LocalUser.Username, AssignedFromListLbl);

                        CurrPage.Update(false);
                        Message(AssignedMsg, LocalUser."Display Name");
                    end;
                }
                action(ClearPicker)
                {
                    ApplicationArea = All;
                    Caption = 'Atamayı Kaldır';
                    Image = UnApply;
                    ToolTip = 'Grubu atanmamış duruma döndürür; terminalde başka bir operatör üstlenebilir.';

                    trigger OnAction()
                    var
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                    begin
                        if Rec."Entry No." = 0 then
                            exit;
                        if Rec.Status = Rec.Status::Completed then
                            Error(CompletedNotAssignableErr);
                        if Rec."Assigned User ID" = '' then
                            exit;
                        // Atama kaldırılınca belge terminalde tekrar herkese açılır;
                        // toplamaya başlamış operatörün işi yarıda kalabilir.
                        if not Confirm(ClearPickerQst, false, PickMgmt.OperatorLabel(Rec."Assigned User ID")) then
                            exit;
                        PickMgmt.SetPickingOrderPicker(Rec, '', ClearedFromListLbl);
                        CurrPage.Update(false);
                    end;
                }
            }
            group(Navigate)
            {
                Caption = 'İlgili';

                action(OpenPick)
                {
                    ApplicationArea = All;
                    Caption = 'Toplama Belgesini Aç';
                    Image = Open;
                    Promoted = true;
                    PromotedCategory = Category5;
                    Enabled = Rec."Warehouse Pick No." <> '';

                    trigger OnAction()
                    var
                        PickHeader: Record "Warehouse Activity Header";
                    begin
                        if not PickHeader.Get(PickHeader.Type::Pick, Rec."Warehouse Pick No.") then
                            Error('Toplama %1 artık açık değil (kaydedilmiş olabilir).', Rec."Warehouse Pick No.");
                        Page.Run(Page::"Warehouse Pick", PickHeader);
                    end;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        PickingLine: Record "DOPSWHS Picking Order Line";
        WhseActivityLine: Record "Warehouse Activity Line";
        OrderCount: Integer;
        ItemLines: Integer;
        TotalLines: Integer;
        DoneLines: Integer;
    begin
        case Rec.Status of
            Rec.Status::Open:
                begin
                    StatusText := 'Açık';
                    StatusStyle := 'Attention';
                end;
            Rec.Status::"Pick Created":
                begin
                    StatusText := 'Toplanmakta';
                    StatusStyle := 'Ambiguous';
                end;
            Rec.Status::Completed:
                begin
                    StatusText := 'Tamamlandı';
                    StatusStyle := 'Favorable';
                end;
            else begin
                StatusText := Format(Rec.Status);
                StatusStyle := 'Standard';
            end;
        end;

        // Atanmamış gruplar göze çarpsın.
        if Rec."Assigned User ID" = '' then
            AssignedStyle := 'Unfavorable'
        else
            AssignedStyle := 'Favorable';

        // Gruptaki sipariş / ürün satırı sayısı.
        PickingLine.SetRange("Header Entry No.", Rec."Entry No.");
        if PickingLine.FindSet() then
            repeat
                OrderCount += 1;
                ItemLines += PickingLine."Item Line Count";
            until PickingLine.Next() = 0;
        if OrderCount = 0 then
            OrderCountText := '—'
        else
            OrderCountText := StrSubstNo('%1 sipariş · %2 satır', OrderCount, ItemLines);

        // İlerleme: pick satırlarından toplanan / toplam.
        ProgressText := '';
        ProgressStyle := 'Standard';
        if Rec."Warehouse Pick No." <> '' then begin
            WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
            WhseActivityLine.SetRange("No.", Rec."Warehouse Pick No.");
            WhseActivityLine.SetRange("Action Type", WhseActivityLine."Action Type"::Take);
            if WhseActivityLine.FindSet() then
                repeat
                    TotalLines += 1;
                    if WhseActivityLine."Qty. to Handle" >= WhseActivityLine.Quantity then
                        DoneLines += 1;
                until WhseActivityLine.Next() = 0;
            if TotalLines > 0 then begin
                ProgressText := StrSubstNo('%1 / %2', DoneLines, TotalLines);
                if DoneLines >= TotalLines then
                    ProgressStyle := 'Favorable'
                else if DoneLines > 0 then
                    ProgressStyle := 'Ambiguous'
                else
                    ProgressStyle := 'Attention';
            end else
                // Register edilince açık satırlar silinir toplama bitmiş demektir.
                if Rec.Status = Rec.Status::"Pick Created" then begin
                    ProgressText := 'Toplandı';
                    ProgressStyle := 'Favorable';
                end;
        end;
    end;

    var
        StatusStyle: Text;
        StatusText: Text;
        AssignedStyle: Text;
        OrderCountText: Text;
        ProgressText: Text;
        ProgressStyle: Text;
        CompletedNotAssignableErr: Label 'Tamamlanmış grubun ataması değiştirilemez.';
        TakeOverQst: Label 'Bu grup %1 kullanıcısında. %2 kullanıcısına devredilsin mi?', Comment = '%1 = mevcut operatör, %2 = yeni operatör';
        ClearPickerQst: Label '%1 kullanıcısının ataması kaldırılsın mı? Toplama terminalde yeniden herkese açılır.', Comment = '%1 = mevcut operatör';
        AssignedMsg: Label 'Grup %1 kullanıcısına atandı.', Comment = '%1 = operatör';
        AssignedFromListLbl: Label 'Toplanacak Siparişler ekranından atandı.';
        ClearedFromListLbl: Label 'Toplanacak Siparişler ekranından atama kaldırıldı.';
}
