page 72292 "DOPSWHS Purch Source API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'purchaseSource';
    EntitySetName = 'purchaseSources';
    SourceTable = "Purchase Header";
    SourceTableView = where("Document Type" = const(Order));
    DelayedInsert = true;
    Editable = false;
    ODataKeyFields = "No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(vendorNo; Rec."Buy-from Vendor No.") { Caption = 'vendorNo'; }
                field(vendorName; Rec."Buy-from Vendor Name") { Caption = 'vendorName'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(orderDate; Rec."Order Date") { Caption = 'orderDate'; }
                field(expectedReceiptDate; Rec."Expected Receipt Date") { Caption = 'expectedReceiptDate'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(vendorInvoiceNo; Rec."Vendor Invoice No."){ Caption = 'vendorInvoiceNo'; }
                field(lineCount; LineCount) { Caption = 'lineCount'; }
                field(outstandingQty; OutstandingQty) { Caption = 'outstandingQty'; }
                field(percentComplete; PercentComplete) { Caption = 'percentComplete'; }
                field(requiresWhseReceipt; RequiresWhseReceipt) { Caption = 'requiresWhseReceipt'; }
                field(directReceiveAllowed; DirectReceiveAllowed) { Caption = 'directReceiveAllowed'; }
                part(lines; "DOPSWHS Purch Source Line API")
                {
                    Caption = 'lines';
                    EntityName = 'purchaseSourceLine';
                    EntitySetName = 'purchaseSourceLines';
                    SubPageLink = "Document Type" = const(Order), "Document No." = field("No.");
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        FillCalculatedFields();
    end;

    /// <summary>PO'dan ambar mal kabul belgesi üretir; varsa mevcut belge numarasını döner.</summary>
    [ServiceEnabled]
    procedure createWhseReceipt(): Code[20]
    var
        Mgmt: Codeunit "DOPSWHS Purch Source Mgmt";
    begin
        exit(Mgmt.CreateWhseReceipt(Rec."No."));
    end;

    [ServiceEnabled]
    procedure receive(invoice: Boolean): Text
    var
        Mgmt: Codeunit "DOPSWHS Purch Source Mgmt";
    begin
        exit(Mgmt.ReceiveOrder(Rec."No.", invoice));
    end;

    var
        LineCount: Integer;
        OutstandingQty: Decimal;
        PercentComplete: Decimal;
        RequiresWhseReceipt: Boolean;
        DirectReceiveAllowed: Boolean;

    local procedure FillCalculatedFields()
    var
        PL: Record "Purchase Line";
        Loc: Record Location;
        TotalQty: Decimal;
        ReceivedQty: Decimal;
    begin
        Clear(LineCount); Clear(OutstandingQty); Clear(PercentComplete);
        Clear(RequiresWhseReceipt); Clear(DirectReceiveAllowed);
        PL.SetRange("Document Type", PL."Document Type"::Order);
        PL.SetRange("Document No.", Rec."No.");
        PL.SetFilter(Type, '<>%1', PL.Type::" ");
        if PL.FindSet() then
            repeat
                LineCount += 1;
                OutstandingQty += PL."Outstanding Quantity";
                TotalQty += PL.Quantity;
                ReceivedQty += PL."Quantity Received";
            until PL.Next() = 0;
        if TotalQty <> 0 then
            PercentComplete := Round(ReceivedQty / TotalQty * 100, 1);

        if Rec."Location Code" = '' then begin
            // Başlıksız (karışık) sipariş: kapıyı satır lokasyonlarına göre kur.
            RequiresWhseReceipt := false;
            DirectReceiveAllowed := true;
            PL.Reset();
            PL.SetRange("Document Type", PL."Document Type"::Order);
            PL.SetRange("Document No.", Rec."No.");
            PL.SetRange(Type, PL.Type::Item);
            PL.SetFilter("Outstanding Quantity", '>0');
            if PL.FindSet() then
                repeat
                    if PL."Location Code" = '' then
                        DirectReceiveAllowed := false
                    else
                        if Loc.Get(PL."Location Code") and Loc."Require Receive" then begin
                            RequiresWhseReceipt := true;
                            DirectReceiveAllowed := false;
                        end else
                            DirectReceiveAllowed := false; // satır lokasyonu başlıktan farklı → BC reddeder
                until PL.Next() = 0;
        end else if Loc.Get(Rec."Location Code") then begin
            RequiresWhseReceipt := Loc."Require Receive";
            DirectReceiveAllowed := not Loc."Require Receive";
        end else begin
            RequiresWhseReceipt := false;
            DirectReceiveAllowed := true;
        end;
    end;
}
