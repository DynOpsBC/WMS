page 72478 "DOPSWHS Project Issue"
{
    // Kitoko/Element4 #3338: terminaldeki "Projeye Çıkış" işleminin BC karşılığı. Terminal
    // olmadan (ör. ofisten) aynı kurallarla saha iş emrine malzeme çıkışı yapar; terminal
    // akışının BC'de doğrulanması için de kullanılır.
    Caption = 'WMS Projeye Çıkış (Saha İş Emri)';
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Tasks;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(WorkOrder)
            {
                Caption = 'Saha İş Emri';
                field(WorkOrderNoField; WorkOrderNo)
                {
                    ApplicationArea = All;
                    Caption = 'Saha İş Emri No.';
                    ToolTip = 'Açık saha iş emrini seçin.';
                    trigger OnLookup(var Text: Text): Boolean
                    var
                        Orders: Page "DOPSWHS Field WO List";
                        Selected: Record "DOPSWHS Field WO Buffer" temporary;
                    begin
                        Orders.LookupMode(true);
                        if Orders.RunModal() <> Action::LookupOK then
                            exit(false);
                        Orders.GetRecord(Selected);
                        Text := Selected."No.";
                        exit(true);
                    end;

                    trigger OnValidate()
                    begin
                        RefreshWorkOrder();
                    end;
                }
                field(ProjectNoField; ProjectNo) { ApplicationArea = All; Caption = 'Proje No.'; Editable = false; }
                field(ProjectTaskNoField; ProjectTaskNo) { ApplicationArea = All; Caption = 'Proje Görevi No.'; Editable = false; }
                field(WorkOrderDescField; WorkOrderDesc) { ApplicationArea = All; Caption = 'Açıklama'; Editable = false; }
            }
            group(Issue)
            {
                Caption = 'Çıkış';
                field(LocationCodeField; LocationCode) { ApplicationArea = All; Caption = 'Lokasyon'; TableRelation = Location.Code; }
                field(BinCodeField; BinCode)
                {
                    ApplicationArea = All;
                    Caption = 'Raf';
                    trigger OnLookup(var Text: Text): Boolean
                    var
                        Bin: Record Bin;
                    begin
                        Bin.SetRange("Location Code", LocationCode);
                        if Page.RunModal(0, Bin) <> Action::LookupOK then
                            exit(false);
                        Text := Bin.Code;
                        exit(true);
                    end;
                }
                field(LpNoField; LpNo) { ApplicationArea = All; Caption = 'LP No. (isteğe bağlı)'; TableRelation = "DOPSWHS LP Header"."No."; }
                field(ItemNoField; ItemNo) { ApplicationArea = All; Caption = 'Madde No.'; TableRelation = Item."No."; }
                field(QuantityField; Qty) { ApplicationArea = All; Caption = 'Miktar'; DecimalPlaces = 0 : 5; }
                field(UomField; UomCode) { ApplicationArea = All; Caption = 'Ölçü Birimi (boş = temel)'; }
                field(LotNoField; LotNo) { ApplicationArea = All; Caption = 'Lot No.'; }
                field(SerialNoField; SerialNo) { ApplicationArea = All; Caption = 'Seri No.'; }
            }
            group(Result)
            {
                Caption = 'Son İşlem';
                field(LastResultField; LastResult) { ApplicationArea = All; Caption = 'Sonuç'; Editable = false; MultiLine = true; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(IssueAction)
            {
                ApplicationArea = All;
                Caption = 'Çıkış Yap';
                Image = Post;
                ToolTip = 'Malzemeyi seçilen saha iş emrinin projesine kullanım olarak kaydeder.';
                trigger OnAction()
                var
                    ProjectIssueMgmt: Codeunit "DOPSWHS Project Issue Mgmt";
                begin
                    LastResult := ProjectIssueMgmt.IssueItem(WorkOrderNo, ItemNo, '', Qty, UomCode, LocationCode, BinCode, LpNo, LotNo, SerialNo,
                        CopyStr(UserId(), 1, 50));
                    Clear(Qty);
                    Clear(LotNo);
                    Clear(SerialNo);
                    CurrPage.Update(false);
                end;
            }
            action(EntriesAction)
            {
                ApplicationArea = All;
                Caption = 'Proje Malzeme Çıkışları';
                Image = JobLedger;
                RunObject = page "DOPSWHS Project Issue Entries";
                ToolTip = 'Projelere yapılan madde kullanımlarını listeler.';
            }
        }
        area(Promoted)
        {
            actionref(IssuePromoted; IssueAction) { }
            actionref(EntriesPromoted; EntriesAction) { }
        }
    }

    var
        WorkOrderNo: Code[20];
        ProjectNo: Code[20];
        ProjectTaskNo: Code[20];
        WorkOrderDesc: Text[100];
        LocationCode: Code[10];
        BinCode: Code[20];
        LpNo: Code[20];
        ItemNo: Code[20];
        Qty: Decimal;
        UomCode: Code[10];
        LotNo: Code[50];
        SerialNo: Code[50];
        LastResult: Text;

    local procedure RefreshWorkOrder()
    var
        Buffer: Record "DOPSWHS Field WO Buffer" temporary;
        ProjectIssueMgmt: Codeunit "DOPSWHS Project Issue Mgmt";
    begin
        Clear(ProjectNo);
        Clear(ProjectTaskNo);
        Clear(WorkOrderDesc);
        if WorkOrderNo = '' then
            exit;
        ProjectIssueMgmt.GetWorkOrder(WorkOrderNo, Buffer);
        ProjectNo := Buffer."Project No.";
        ProjectTaskNo := Buffer."Project Task No.";
        WorkOrderDesc := Buffer.Description;
    end;
}
